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
        #expect(c.routes.first?.label == "via Amarillo")
        #expect(c.routes.count >= 1 && c.routes.count <= RouteComparison.maxRoutes)
        assertNoDuplicates(c.routes)
        let via = try #require(c.routes.first)
        // The via route must actually pass through Amarillo.
        let amarillo = Coordinate(lat: 35.222, lon: -101.8313)
        let closest = via.coordinates.map { Geo.haversineMiles($0, amarillo) }.min() ?? .infinity
        #expect(closest < 5, "via route passes \(closest) mi from Amarillo")
        #expect(await weather.calls == 0)
    }

    /// Owner report: via Raton showed two copies of the same road and never
    /// the eastern route through Kansas / the Oklahoma panhandle.
    @Test func viaRatonAlsoOffersTheEasternRoute() async throws {
        let c = try makeCoordinator()
        c.plan.originText = "Thornton, CO"
        c.plan.viaTexts = ["Raton, NM"]
        c.plan.destinationText = "Dallas, TX"
        await c.findRoutes()
        #expect(c.errorMessage == nil)
        #expect(c.routes.first?.label == "via Raton")
        #expect(c.routes.count >= 2, "\(c.routes.map { "\($0.label ?? "-") \(Int($0.distanceMi)) mi" })")
        assertNoDuplicates(c.routes)
        // Something east of the I-25 / US-87 corridor (west edge of Kansas is −102.05°).
        let eastern = c.routes.dropFirst().contains { r in r.coordinates.contains { $0.lat > 36.5 && $0.lat < 38.5 && $0.lon > -102.6 } }
        #expect(eastern, "\(c.routes.map { $0.label ?? "-" })")
        for r in c.routes.dropFirst() { #expect(r.label?.contains("via ") == true, "alternatives are named: \(r.label ?? "nil")") }
        print("ROUTES", c.routes.map { "\($0.label ?? "-") \(Int($0.distanceMi)) mi \(Int($0.durationSec / 60)) min" })
    }

    private func assertNoDuplicates(_ routes: [RouteGeometry]) {
        for i in routes.indices {
            for j in routes.indices where j > i {
                let same = RouteComparison.overlap(routes[i].coordinates, with: routes[j].coordinates) >= RouteComparison.duplicateOverlap
                    && RouteComparison.overlap(routes[j].coordinates, with: routes[i].coordinates) >= RouteComparison.duplicateOverlap
                #expect(!same, "routes \(i) and \(j) are the same road")
            }
        }
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
