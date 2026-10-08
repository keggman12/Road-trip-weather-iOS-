import CoreLocation
import Foundation
import MapKit
import RoadTripCore

extension Coordinate {
    var clLocationCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    init(_ c: CLLocationCoordinate2D) {
        self.init(latitude: c.latitude, longitude: c.longitude)
    }
}

/// Geocoding through `MKLocalSearch`. The first result wins, like the web's
/// `size=1` Pelias query. The map item's time zone is kept for ETA display.
struct MapKitGeocodingService: GeocodingService {
    func geocode(_ query: String) async throws -> PlacePoint {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = [.address, .pointOfInterest]
        let response = try await MKLocalSearch(request: request).start()
        guard let item = response.mapItems.first else { throw ServiceError.notFound(query) }
        let placemark = item.placemark
        let coordinate = Coordinate(placemark.coordinate)
        let parts = [item.name, placemark.locality, placemark.administrativeArea]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        var label = parts.isEmpty ? query : parts.joined(separator: ", ")
        if let name = item.name, let locality = placemark.locality, name == locality {
            // "Amarillo, Amarillo, TX" → "Amarillo, TX"
            label = [locality, placemark.administrativeArea].compactMap { $0 }.joined(separator: ", ")
        }
        return PlacePoint(query: query, label: label, coordinate: coordinate, timeZoneID: item.timeZone?.identifier)
    }
}

/// Routing through `MKDirections`.
///
/// - Two points: `requestsAlternateRoutes` on, MapKit returns up to ~3.
/// - Via-points: `MKDirections.Request` has no intermediate stops, so one
///   request per leg is chained into a single `RouteGeometry`, labelled
///   "via X · Y"; the direct route is fetched too for comparison (web
///   `findRoutes` does the same).
struct MapKitRoutingService: RoutingService {
    func routes(through points: [PlacePoint], departure: Date) async throws -> RoutingResult {
        guard points.count >= 2, let first = points.first, let last = points.last else { throw ServiceError.noRoute }
        if points.count == 2 {
            let routes = RouteComparison.dedupe(try await directions(from: first, to: last, departure: departure, alternates: true))
            guard !routes.isEmpty else { throw ServiceError.noRoute }
            let note = routes.count == 1 ? "MapKit returned a single route for this trip. Add a via-point to shape it." : nil
            return RoutingResult(routes: routes, note: note)
        }

        let viaLabel = "via " + points.dropFirst().dropLast().map(\.shortLabel).joined(separator: " · ")
        var routes = [try await chained(points, departure: departure, label: viaLabel)]
        // Direct routes with alternates for comparison (best-effort). The
        // best direct route often follows the via route anyway; dedupe drops
        // it so a genuinely different road (e.g. east through Kansas) shows.
        let direct = (try? await directions(from: first, to: last, departure: departure, alternates: true)) ?? []
        for (i, var d) in direct.enumerated() {
            d.label = i == 0 ? "Direct" : nil
            routes.append(d)
        }
        return RoutingResult(routes: RouteComparison.dedupe(routes), note: nil)
    }

    func chainedRoute(through points: [PlacePoint], departure: Date) async throws -> RouteGeometry {
        try await chained(points, departure: departure, label: nil)
    }

    private func chained(_ points: [PlacePoint], departure: Date, label: String?) async throws -> RouteGeometry {
        var legs: [RouteGeometry] = []
        var legStart = departure
        for (a, b) in zip(points, points.dropFirst()) {
            let leg = try await directions(from: a, to: b, departure: legStart, alternates: false)
            guard let best = leg.first else { throw ServiceError.noRoute }
            legs.append(best)
            legStart = legStart.addingTimeInterval(best.durationSec)
        }
        return RouteGeometry.chained(legs, label: label)
    }

    private func directions(from a: PlacePoint, to b: PlacePoint, departure: Date, alternates: Bool) async throws -> [RouteGeometry] {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: a.coordinate.clLocationCoordinate))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: b.coordinate.clLocationCoordinate))
        request.transportType = .automobile
        request.requestsAlternateRoutes = alternates
        request.departureDate = departure
        let response = try await MKDirections(request: request).calculate()
        return response.routes.map { route in
            RouteGeometry(
                coordinates: route.polyline.coordinates.map(Coordinate.init),
                distanceMi: route.distance / Geo.metersPerMile,
                durationSec: route.expectedTravelTime,
                label: nil
            )
        }
    }
}

extension MKMultiPoint {
    var coordinates: [CLLocationCoordinate2D] {
        var coords = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: pointCount)
        getCoordinates(&coords, range: NSRange(location: 0, length: pointCount))
        return coords
    }
}

/// Reverse geocodes a coordinate to its time zone. Apple throttles
/// `CLGeocoder`, so lookups are serialized through this actor and cached by
/// a ~1 km grid cell; a briefing never needs more than 25.
actor CLTimeZoneService: TimeZoneService {
    private var cache: [String: PlaceInfo] = [:]
    private let geocoder = CLGeocoder()

    func timeZone(at coordinate: Coordinate) async -> TimeZone? {
        await place(at: coordinate)?.timeZone
    }

    /// One reverse geocode gives both the zone and a stop name.
    func place(at coordinate: Coordinate) async -> PlaceInfo? {
        let key = POINormalizer.dedupeKey(coordinate, decimals: 2)
        if let cached = cache[key] { return cached }
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard let p = (try? await geocoder.reverseGeocodeLocation(location))?.first else { return nil }
        let info = PlaceInfo(timeZone: p.timeZone, road: p.thoroughfare, town: p.locality, county: p.subAdministrativeArea, state: p.administrativeArea)
        cache[key] = info
        return info
    }
}
