import Foundation
import RoadTripCore
import Testing
@testable import RoadTripWeather

@Suite("More routes", .serialized)
@MainActor
struct MoreRoutesTests {
    let net = FakeNetwork()

    @Test func addsDistinctSuggestionsKeepsExistingRoutesAndBriefings() async throws {
        let env = AppEnvironment(
            container: try AppSchema.makeContainer(inMemory: true),
            settings: AppSettings(defaults: UserDefaults(suiteName: "MoreRoutes-\(UUID().uuidString)") ?? .standard),
            geocoding: HubGeocoder(net: net), routing: FakeRouting(net: net, through: nil), timeZones: MockTimeZoneService(),
            weather: FakeWeather(net: net), alerts: FakeAlerts(net: net), chargers: MockChargerService(), refresher: nil, isPreview: true
        )
        let c = BriefingCoordinator(env: env)
        c.plan.originText = "Denver"
        c.plan.destinationText = "Dallas"
        await c.findRoutes()
        await c.generateBriefing()
        let before = c.routes
        let briefing = try #require(c.briefing)
        let weatherCalls = await net.snapshot().weather
        #expect(c.canFindMoreRoutes)

        await c.findMoreRoutes()
        #expect(Array(c.routes.prefix(before.count)) == before, "existing routes keep their place")
        #expect(c.routes.count > before.count, "\(c.routes.map { $0.label ?? "-" })")
        #expect(c.routes.count <= BriefingCoordinator.maxRoutesWithSuggestions)
        #expect(c.routes.dropFirst(before.count).allSatisfy { $0.label?.hasPrefix("Suggested · via ") == true })
        #expect(c.briefing == briefing, "selected briefing untouched")
        #expect(await net.snapshot().weather == weatherCalls, "no weather calls")
        #expect(c.statusMessage?.hasPrefix("Added ") == true)
        #expect(c.phase == .idle)
    }
}

/// Mock places plus every RouteHubs city at its listed coordinate.
struct HubGeocoder: GeocodingService {
    let net: FakeNetwork
    func geocode(_ query: String) async throws -> PlacePoint {
        if let h = RouteHubs.all.first(where: { $0.query == query }) {
            return PlacePoint(query: query, label: "\(h.query), USA", coordinate: h.coordinate, timeZoneID: "America/Chicago")
        }
        return try await FakeGeocoding(net: net).geocode(query)
    }
}
