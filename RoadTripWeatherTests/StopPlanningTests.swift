import Foundation
import RoadTripCore
import SwiftData
import Testing
@testable import RoadTripWeather

/// Owner requests 3 and 4: briefings put stops at real Buc-ee's / Love's /
/// rest areas from the bundled data, and name plain waypoints by place.
@Suite("Stop planning in briefings", .serialized)
@MainActor
struct StopPlanningTests {
    let net = FakeNetwork()

    @Test func briefingUsesRealStopsWithinNinetyPercentOfRange() async throws {
        let container = try AppSchema.makeContainer(inMemory: true)
        let probe = AppEnvironment(container: container, settings: AppSettings(defaults: UserDefaults(suiteName: "plan-\(UUID().uuidString)") ?? .standard), geocoding: FakeGeocoding(net: net), routing: FakeRouting(net: net, through: nil), timeZones: NamingTimeZones(), weather: FakeWeather(net: net), alerts: FakeAlerts(net: net), chargers: MockChargerService(), refresher: nil, isPreview: true)
        await probe.pois.importBundledSnapshotIfNeeded()
        // Run the fake road east-west through Amarillo, where the snapshot
        // has Love's and Buc-ee's on I-40.
        let env = AppEnvironment(container: container, settings: probe.settings, geocoding: FakeGeocoding(net: net), routing: FakeRouting(net: net, through: Coordinate(lat: 35.19, lon: -101.75)), timeZones: NamingTimeZones(), weather: FakeWeather(net: net), alerts: FakeAlerts(net: net), chargers: MockChargerService(), refresher: nil, isPreview: true)
        let c = BriefingCoordinator(env: env)
        c.plan.originText = "Denver"
        c.plan.destinationText = "Dallas"
        c.plan.rangeMi = 180
        await c.findRoutes()
        await c.generateBriefing()
        let b = try #require(c.briefing)

        let interior = b.stops.dropFirst().dropLast()
        #expect(!interior.isEmpty)
        let legs = zip(b.stops, b.stops.dropFirst()).map { $1.distanceMi - $0.distanceMi }
        #expect(legs.allSatisfy { $0 <= 162 + 1e-6 }, "\(legs)")
        let planned = interior.filter { $0.kind == .planned }
        #expect(!planned.isEmpty, "uses real places from the bundled snapshot")
        #expect(planned.contains { $0.poiKind?.isFuel == true })
        for s in planned { #expect(s.tag(index: 1, total: 3) == s.poiKind?.stopTag) }
        for s in interior where s.kind == .sampled { #expect(s.label.hasPrefix("near "), "plain waypoints are named: \(s.label)") }
        #expect(StopPlanner.summary(for: b.stops, rangeMi: 180)?.hasPrefix("Stops at the farthest fuel within 162 mi") == true)

        // Saved and reloaded, planned stops keep their kind and note.
        try c.save(name: "planned")
        let trip = try #require(env.trips.allTrips().first)
        let reloaded = try #require(env.trips.cachedBriefings(for: trip).first)
        #expect(reloaded.stops.map(\.kind) == b.stops.map(\.kind))
        #expect(reloaded.stops.map(\.planNote) == b.stops.map(\.planNote))
    }
}

/// Mock zones plus a town name, like CLGeocoder gives.
struct NamingTimeZones: TimeZoneService {
    func timeZone(at coordinate: Coordinate) async -> TimeZone? { await MockTimeZoneService().timeZone(at: coordinate) }
    func place(at coordinate: Coordinate) async -> PlaceInfo? {
        PlaceInfo(timeZone: await timeZone(at: coordinate), road: "Main St", town: "Town\(Int(coordinate.lon.rounded()))", county: nil, state: "TX")
    }
}
