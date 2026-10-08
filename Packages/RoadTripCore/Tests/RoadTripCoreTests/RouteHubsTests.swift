import Foundation
import Testing
@testable import RoadTripCore

@Suite("Route hubs (More routes)")
struct RouteHubsTests {
    static let thornton = Coordinate(lat: 39.87, lon: -104.99)
    static let dallas = Coordinate(lat: 32.78, lon: -96.80)

    @Test func thorntonToDallasSuggestsBothSidesOffTheExistingRoutes() {
        // Existing: I-25/US-87 via Amarillo (west) — approximate with its towns.
        let existing = [[Self.thornton, Coordinate(lat: 38.25, lon: -104.61), Coordinate(lat: 36.90, lon: -104.44), Coordinate(lat: 35.22, lon: -101.83), Self.dallas]]
        let hubs = RouteHubs.candidates(origin: Self.thornton, destination: Self.dallas, existingRoutes: existing)
        #expect(!hubs.isEmpty && hubs.count <= 4, "\(hubs.map(\.query))")
        let direct = Geo.haversineMiles(Self.thornton, Self.dallas)
        for h in hubs {
            #expect((Geo.haversineMiles(Self.thornton, h.coordinate) + Geo.haversineMiles(h.coordinate, Self.dallas)) / direct <= RouteHubs.maxDetour)
            #expect(Geo.minDistanceMiles(from: h.coordinate, to: existing[0]) >= RouteHubs.minDistanceFromRoutesMi)
        }
        for (i, a) in hubs.enumerated() {
            for b in hubs.dropFirst(i + 1) { #expect(Geo.haversineMiles(a.coordinate, b.coordinate) >= RouteHubs.minSpacingMi) }
        }
        #expect(!hubs.contains { $0.name == "Amarillo" || $0.name == "Pueblo" }, "on the existing route")
        #expect(!hubs.contains { $0.name == "Denver" || $0.name == "Dallas" }, "too close to the ends")
    }

    @Test func alternatesSides() {
        let o = Coordinate(lat: 35, lon: -105), d = Coordinate(lat: 35, lon: -95)
        let hubs = [
            RouteHubs.Hub(name: "N1", state: "X", coordinate: Coordinate(lat: 36, lon: -100)),
            RouteHubs.Hub(name: "N2", state: "X", coordinate: Coordinate(lat: 36.5, lon: -98)),
            RouteHubs.Hub(name: "S1", state: "X", coordinate: Coordinate(lat: 33.5, lon: -100)),
        ]
        let picked = RouteHubs.candidates(origin: o, destination: d, existingRoutes: [[o, d]], count: 2, hubs: hubs)
        #expect(Set(picked.map(\.name)) == ["N1", "S1"])
    }

    @Test func shortTripsGetNone() {
        #expect(RouteHubs.candidates(origin: Coordinate(lat: 35, lon: -100), destination: Coordinate(lat: 35, lon: -99), existingRoutes: []).isEmpty)
    }
}
