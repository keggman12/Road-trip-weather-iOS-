import Foundation
import RoadTripCore
import Testing
@testable import RoadTripWeather

/// Coordinator behaviour with the deterministic mocks (no network).
@Suite("Briefing coordinator")
@MainActor
struct BriefingCoordinatorTests {
    nonisolated static let legalURL = URL(string: "https://weatherkit.apple.com/legal-attribution.html")

    private func makeCoordinator() throws -> BriefingCoordinator {
        let container = try AppSchema.makeContainer(inMemory: true)
        let defaults = UserDefaults(suiteName: "BriefingCoordinatorTests-\(UUID().uuidString)") ?? .standard
        let env = AppEnvironment(
            container: container,
            settings: AppSettings(defaults: defaults),
            geocoding: MockGeocodingService(),
            routing: MockRoutingService(),
            timeZones: MockTimeZoneService(),
            weather: AttributedMockWeather(),
            alerts: MockAlertService(),
            chargers: MockChargerService(),
            refresher: nil,
            isPreview: true
        )
        let c = BriefingCoordinator(env: env)
        c.plan.originText = "Denver"
        c.plan.destinationText = "Dallas"
        c.plan.rangeMi = 180
        return c
    }

    @Test func briefingCarriesAttributionURLForOfflineDisplay() async throws {
        let c = try makeCoordinator()
        await c.findRoutes()
        await c.generateBriefing()
        let b = try #require(c.briefing)
        #expect(b.weatherAttributionURL == Self.legalURL?.absoluteString)
    }

    @Test func briefAllRoutesStampsEveryBriefing() async throws {
        let c = try makeCoordinator()
        await c.findRoutes()
        await c.generateBriefing(allRoutes: true)
        #expect(c.briefings.count == c.routes.count)
        #expect(c.briefings.values.allSatisfy { $0.weatherAttributionURL == Self.legalURL?.absoluteString })
    }
}

private struct AttributedMockWeather: WeatherService {
    func forecast(at coordinate: Coordinate, for eta: Date) async throws -> ForecastResult {
        try await MockWeatherService().forecast(at: coordinate, for: eta)
    }

    func attributionURL() async -> URL? { BriefingCoordinatorTests.legalURL }
}
