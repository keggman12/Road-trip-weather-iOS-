import Foundation
import RoadTripCore

// Deterministic fakes for previews and tests. No network.

struct MockGeocodingService: GeocodingService {
    static let places: [String: PlacePoint] = [
        "denver": PlacePoint(query: "Denver", label: "Denver, CO, USA", coordinate: Coordinate(lat: 39.7392, lon: -104.9903), timeZoneID: "America/Denver"),
        "dallas": PlacePoint(query: "Dallas", label: "Dallas, TX, USA", coordinate: Coordinate(lat: 32.7767, lon: -96.797), timeZoneID: "America/Chicago"),
        "amarillo": PlacePoint(query: "Amarillo", label: "Amarillo, TX, USA", coordinate: Coordinate(lat: 35.222, lon: -101.8313), timeZoneID: "America/Chicago"),
        "oklahoma city": PlacePoint(query: "Oklahoma City", label: "Oklahoma City, OK, USA", coordinate: Coordinate(lat: 35.4676, lon: -97.5164), timeZoneID: "America/Chicago"),
    ]

    func geocode(_ query: String) async throws -> PlacePoint {
        let key = query.lowercased().split(separator: ",").first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
        if var p = MockGeocodingService.places[key] {
            p.query = query
            return p
        }
        throw ServiceError.notFound(query)
    }
}

struct MockRoutingService: RoutingService {
    /// Straight-ish line with a gentle curve, like the test fixture route.
    static func line(from a: Coordinate, to b: Coordinate, points: Int = 200, bulge: Double = 0.4) -> [Coordinate] {
        (0..<points).map { i in
            let f = Double(i) / Double(points - 1)
            return Coordinate(lat: a.lat + (b.lat - a.lat) * f + bulge * sin(f * .pi), lon: a.lon + (b.lon - a.lon) * f)
        }
    }

    func routes(through points: [PlacePoint], departure: Date) async throws -> RoutingResult {
        guard points.count >= 2, let first = points.first, let last = points.last else { throw ServiceError.noRoute }
        func geometry(_ coords: [Coordinate], label: String?) -> RouteGeometry {
            let miles = Geo.cumulativeMiles(coords).last ?? 0
            return RouteGeometry(coordinates: coords, distanceMi: miles, durationSec: miles / 62 * 3600, label: label)
        }
        if points.count == 2 {
            return RoutingResult(routes: [
                geometry(MockRoutingService.line(from: first.coordinate, to: last.coordinate), label: nil),
                geometry(MockRoutingService.line(from: first.coordinate, to: last.coordinate, bulge: -0.6), label: nil),
            ], note: nil)
        }
        var legs: [RouteGeometry] = []
        for (a, b) in zip(points, points.dropFirst()) {
            legs.append(geometry(MockRoutingService.line(from: a.coordinate, to: b.coordinate, points: 80, bulge: 0.1), label: nil))
        }
        let viaLabel = "via " + points.dropFirst().dropLast().map(\.shortLabel).joined(separator: " · ")
        let direct = geometry(MockRoutingService.line(from: first.coordinate, to: last.coordinate), label: "Direct")
        return RoutingResult(routes: [RouteGeometry.chained(legs, label: viaLabel), direct], note: nil)
    }
}

struct MockTimeZoneService: TimeZoneService {
    func timeZone(at coordinate: Coordinate) async -> TimeZone? {
        // Rough US zones by longitude; good enough for previews.
        if coordinate.lon < -114 { return TimeZone(identifier: "America/Los_Angeles") }
        if coordinate.lon < -102 { return TimeZone(identifier: "America/Denver") }
        if coordinate.lon < -87 { return TimeZone(identifier: "America/Chicago") }
        return TimeZone(identifier: "America/New_York")
    }
}

struct MockWeatherService: WeatherService {
    func forecast(at coordinate: Coordinate, for eta: Date) async throws -> ForecastResult {
        let hoursAhead = eta.timeIntervalSinceNow / 3600
        if hoursAhead > 240 { return ForecastResult(snapshot: nil, horizon: .beyondHorizon) }
        // Deterministic pseudo-weather from the coordinate.
        let seed = abs(sin(coordinate.lat * 3.1) * cos(coordinate.lon * 1.7))
        let temp = Int((45 + seed * 50).rounded())
        let pop = (seed * 1.3).truncatingRemainder(dividingBy: 1)
        let category: ConditionCategory = pop > 0.75 ? .thunderstorm : pop > 0.5 ? .rain : seed > 0.6 ? .partlyCloudy : .clear
        let snapshot = WeatherSnapshot(
            temperatureF: temp,
            feelsLikeF: temp - 2,
            humidityPercent: Int((30 + seed * 60).rounded()),
            windMph: Int((seed * 25).rounded()),
            windFromDegrees: (seed * 360).rounded(),
            cloudPercent: Int((seed * 100).rounded()),
            conditionRaw: category.rawValue,
            conditionText: category.label.lowercased(),
            category: category,
            recordDate: eta,
            precipitationChance: pop,
            kind: hoursAhead <= 47 ? .hourly : .daily
        )
        return ForecastResult(snapshot: snapshot, horizon: .ok)
    }

    func attributionURL() async -> URL? { nil }
}

struct MockAlertService: AlertService {
    func alerts(at coordinate: Coordinate, eta: Date) async -> [WeatherAlert] {
        // One alert band across the Texas panhandle.
        guard (34.5...36.5).contains(coordinate.lat), (-103.0 ... -100.0).contains(coordinate.lon) else { return [] }
        return [WeatherAlert(
            id: "mock-tornado-watch",
            event: "Tornado Watch",
            severity: .severe,
            headline: "Tornado Watch in effect this evening",
            areaDescription: "Potter, TX; Randall, TX",
            onset: eta.addingTimeInterval(-3600),
            ends: eta.addingTimeInterval(4 * 3600)
        )]
    }
}

struct MockPOIService: POIService {
    func pois(kind: POIKind) async throws -> [POI] {
        switch kind {
        case .bucees:
            [POI(kind: .bucees, sourceID: "bucees/mock-1", name: "Buc-ee's #00 – Amarillo, TX", detail: "I-40", coordinate: Coordinate(lat: 35.19, lon: -101.75))]
        case .loves:
            [POI(kind: .loves, sourceID: "loves/312", name: "Love's #312 — Amarillo, TX", detail: "I-40 · Exit 76", coordinate: Coordinate(lat: 35.2141, lon: -101.7023))]
        case .rest:
            [POI(kind: .rest, sourceID: "node/1", name: "Rest Area", detail: "Rest area", coordinate: Coordinate(lat: 36.9, lon: -102.9))]
        }
    }

    func refresh(kind: POIKind) async throws -> POIRefreshOutcome {
        POIRefreshOutcome(kind: kind, count: 1, source: .official)
    }
}

struct MockChargerService: ChargerService {
    var isConfigured: Bool { false }
}
