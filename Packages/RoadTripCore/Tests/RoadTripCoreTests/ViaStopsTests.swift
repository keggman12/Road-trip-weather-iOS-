import Foundation
import Testing
@testable import RoadTripCore

@Suite("Via stops (via-points briefed as stops)")
struct ViaStopsTests {
    static let a = Coordinate(lat: 39.0, lon: -105.0)
    static let b = Coordinate(lat: 38.0, lon: -104.0)
    static let c = Coordinate(lat: 36.0, lon: -102.0)
    static let d = Coordinate(lat: 33.0, lon: -97.0)

    static func leg(_ from: Coordinate, _ to: Coordinate) -> RouteGeometry {
        let coords = (0...20).map { i in
            let f = Double(i) / 20
            return Coordinate(lat: from.lat + (to.lat - from.lat) * f, lon: from.lon + (to.lon - from.lon) * f)
        }
        return RouteGeometry(coordinates: coords, distanceMi: Geo.cumulativeMiles(coords).last ?? 0, durationSec: 3600)
    }

    static func place(_ label: String, _ c: Coordinate) -> PlacePoint {
        PlacePoint(query: DroppedPin.query(for: c), label: label, coordinate: c, timeZoneID: "America/Denver")
    }

    @Test func oneStopPerViaAtItsJunction() throws {
        // The pin sits 3 mi off the road; the leg joins at the nearest road point.
        let pin = Coordinate(lat: Self.b.lat + 0.04, lon: Self.b.lon)
        let route = RouteGeometry.chained([Self.leg(Self.a, Self.b), Self.leg(Self.b, Self.c), Self.leg(Self.c, Self.d)], label: "via …")
        let vias = [Self.place("Pin near Rye, CO", pin), Self.place("Amarillo, TX", Self.c)]
        let stops = ViaStops.stops(for: vias, on: route)
        try #require(stops.count == 2)
        #expect(stops.map(\.kind) == [.via, .via])
        #expect(stops.map(\.label) == ["Pin near Rye, CO", "Amarillo, TX"])
        #expect(stops[0].coordinate == pin, "weather where the pin is, not where the road passes")
        #expect(stops.allSatisfy { $0.dwellMinutes == 0 && $0.timeZoneID == "America/Denver" })
        let cum = Geo.cumulativeMiles(route.coordinates)
        #expect(stops[0].distanceMi == cum[route.legBoundaryIndices[0]])
        #expect(stops[0].distanceMi < stops[1].distanceMi)
        #expect(abs((stops[0].offRouteMi ?? 0) - Geo.haversineMiles(pin, Self.b)) < 1e-9)
        #expect(stops[0].tag(index: 1, total: 4) == "VIA")
    }

    @Test func routesNotChainedThroughTheViasGetNone() {
        let vias = [Self.place("Pin near Rye, CO", Self.b)]
        // Direct route: no junctions.
        #expect(ViaStops.stops(for: vias, on: Self.leg(Self.a, Self.d)).isEmpty)
        // A "More routes" hub route: one junction, but at the hub, far from the via.
        let hub = RouteGeometry.chained([Self.leg(Self.a, Self.c), Self.leg(Self.c, Self.d)], label: "Suggested · via Amarillo")
        #expect(ViaStops.stops(for: vias, on: hub).isEmpty)
        // No vias at all.
        #expect(ViaStops.stops(for: [], on: hub).isEmpty)
    }

    @Test func insertingKeepsEndpointsAndOrdersByMile() {
        let origin = Stop(kind: .origin, label: "O", coordinate: Self.a, routeIndex: 0, distanceMi: 0)
        let fuel = Stop(kind: .planned, label: "Fuel", coordinate: Self.c, routeIndex: 5, distanceMi: 300)
        let dest = Stop(kind: .destination, label: "D", coordinate: Self.d, routeIndex: 9, distanceMi: 700)
        let via = Stop(kind: .via, label: "Pin", coordinate: Self.b, routeIndex: 2, distanceMi: 100, dwellMinutes: 0)
        #expect(ViaStops.inserting([via], into: [origin, fuel, dest]).map(\.label) == ["O", "Pin", "Fuel", "D"])
    }

    @Test func viaStopsAreNotUserEditsAndCantBeRemovedOnTheirOwn() {
        let route = Self.leg(Self.a, Self.d)
        var b = Briefing(
            routeIndex: 0, routeLabel: nil, geometry: route, totalMi: route.distanceMi,
            departure: Date(timeIntervalSince1970: 0), departureTimeZoneID: nil, rangeMi: 300, multiDay: .off,
            stops: [
                Stop(kind: .origin, label: "O", coordinate: Self.a, routeIndex: 0, distanceMi: 0),
                Stop(kind: .via, label: "Pin", coordinate: Self.b, routeIndex: 2, distanceMi: 100, dwellMinutes: 0),
                Stop(kind: .destination, label: "D", coordinate: Self.d, routeIndex: 19, distanceMi: route.distanceMi),
            ],
            generatedAt: Date(timeIntervalSince1970: 0)
        )
        let viaID = b.stops[1].id
        #expect(StopEdits(from: b).isEmpty, "rebuilt from the plan, never replayed as an edit")
        #expect(StopEditReplayer.stopsToRemove(in: b.stops, removedMi: [100]).isEmpty)
        #expect(!StopEditReplayer.remove(stopID: viaID, from: &b))
        #expect(b.stops.count == 3 && b.removedMi.isEmpty)
    }
}
