import Foundation
import RoadTripCore
import Testing
@testable import RoadTripWeather

/// Phase-1 task 4 acceptance against live MapKit (needs network). Geocoding,
/// routing and time zones are real; weather and alerts are counting fakes so
/// the "no weather call during Find Routes" rule can be asserted.
@Suite("Live MapKit routing", .serialized, .tags(.live))
@MainActor
struct LiveRoutingTests {
    private let weather = CountingWeatherService()

    private func makeCoordinator() throws -> BriefingCoordinator {
        let container = try AppSchema.makeContainer(inMemory: true)
        let defaults = UserDefaults(suiteName: "LiveRoutingTests-\(UUID().uuidString)") ?? .standard
        let env = AppEnvironment(
            container: container,
            settings: AppSettings(defaults: defaults),
            geocoding: MapKitGeocodingService(),
            routing: MapKitRoutingService(),
            timeZones: CLTimeZoneService(),
            weather: weather,
            alerts: MockAlertService(),
            chargers: MockChargerService(),
            refresher: nil,
            isPreview: false
        )
        return BriefingCoordinator(env: env)
    }

    @Test func denverToDallasFindsRoutesWithoutWeatherCalls() async throws {
        let c = try makeCoordinator()
        c.plan.originText = "Denver, CO"
        c.plan.destinationText = "Dallas, TX"
        await c.findRoutes()

        #expect(c.errorMessage == nil)
        #expect(!c.routes.isEmpty)
        #expect(c.selectedRouteIndex == 0)
        for r in c.routes {
            #expect((700...900).contains(r.distanceMi), "Denver→Dallas is ~790 mi by road, got \(r.distanceMi)")
            #expect(r.coordinates.count > 100)
        }
        if c.routes.count == 1 { #expect(c.routeNote != nil) }
        #expect(await weather.calls == 0)
        #expect(c.env.status.sessionCalls[.weatherkit, default: 0] == 0)
        #expect(c.plan.origin?.label.contains("Denver") == true)
    }

    @Test func viaAmarilloGivesViaAndDirectRoutes() async throws {
        let c = try makeCoordinator()
        c.plan.originText = "Denver, CO"
        c.plan.viaTexts = ["Amarillo, TX"]
        c.plan.destinationText = "Dallas, TX"
        await c.findRoutes()

        #expect(c.errorMessage == nil)
        #expect(c.routes.map(\.label) == ["via Amarillo", "Direct"])
        let via = try #require(c.routes.first)
        // The via route must actually pass through Amarillo.
        let amarillo = Coordinate(lat: 35.222, lon: -101.8313)
        let closest = via.coordinates.map { Geo.haversineMiles($0, amarillo) }.min() ?? .infinity
        #expect(closest < 5, "via route passes \(closest) mi from Amarillo")
        #expect(await weather.calls == 0)
    }

    @Test func everyBriefedStopHasATimeZone() async throws {
        let c = try makeCoordinator()
        c.plan.originText = "Denver, CO"
        c.plan.destinationText = "Dallas, TX"
        c.plan.rangeMi = 180
        await c.findRoutes()
        try #require(!c.routes.isEmpty)
        await c.generateBriefing()

        let b = try #require(c.briefing)
        #expect(b.stops.count >= 5)
        #expect(await weather.calls == b.stops.count)
        let missing = b.stops.filter { $0.timeZoneID == nil }.map(\.label)
        #expect(missing.isEmpty, "stops without timeZoneID: \(missing)")
        #expect(b.stops.first?.timeZoneID == "America/Denver")
        #expect(b.stops.last?.timeZoneID == "America/Chicago")
    }
}

extension Testing.Tag {
    @Tag static var live: Self
}

/// Forecast fake that counts calls.
actor CountingWeatherService: WeatherService {
    private(set) var calls = 0
    private let inner = MockWeatherService()

    func forecast(at coordinate: Coordinate, for eta: Date) async throws -> ForecastResult {
        calls += 1
        return try await inner.forecast(at: coordinate, for: eta)
    }

    func attributionURL() async -> URL? { nil }
}
