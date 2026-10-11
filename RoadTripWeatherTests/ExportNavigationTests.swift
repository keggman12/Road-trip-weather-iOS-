import Foundation
import MapKit
import RoadTripCore
import Testing
@testable import RoadTripWeather

/// Phase-2 tasks P2-1 (GPX export) and P2-2 (navigate to a stop), app side.
@Suite("GPX export and navigation (P2-1, P2-2)", .serialized)
@MainActor
struct ExportNavigationTests {
    let net = FakeNetwork()

    private func briefed() async throws -> BriefingCoordinator {
        let env = AppEnvironment(
            container: try AppSchema.makeContainer(inMemory: true),
            settings: AppSettings(defaults: UserDefaults(suiteName: "ExportNavigationTests-\(UUID().uuidString)") ?? .standard),
            geocoding: FakeGeocoding(net: net),
            routing: FakeRouting(net: net, through: nil),
            timeZones: MockTimeZoneService(),
            weather: FakeWeather(net: net),
            alerts: FakeAlerts(net: net),
            chargers: MockChargerService(),
            refresher: nil,
            isPreview: true
        )
        let c = BriefingCoordinator(env: env)
        c.plan.originText = "Denver"
        c.plan.destinationText = "Dallas"
        c.plan.rangeMi = 180
        await c.findRoutes()
        await c.generateBriefing()
        try #require(c.briefing != nil)
        return c
    }

    @Test func exportIsNamedAfterTheTripAndCoversTheBriefing() async throws {
        let c = try await briefed()
        let export = try #require(c.gpxExport)
        #expect(export.fileName == "Denver → Dallas.gpx")
        let b = try #require(c.briefing)
        let gpx = export.gpx()
        #expect(gpx.components(separatedBy: "<wpt ").count - 1 == b.stops.count)
        #expect(gpx.components(separatedBy: "<trkpt ").count - 1 == b.geometry.coordinates.count)
        #expect(gpx.contains("<name>Origin — \(b.stops[0].label)</name>"))

        try c.save(name: "Spring break")
        #expect(c.gpxExport?.fileName == "Spring break.gpx")
    }

    @Test func exportWorksOfflineFromACachedTrip() async throws {
        let c = try await briefed()
        try c.save(name: "Cached")
        net.online = false
        let offline = BriefingCoordinator(env: c.env)
        let trip = try #require(c.env.trips.allTrips().first)
        offline.load(trip)
        let gpx = try #require(offline.gpxExport).gpx()
        #expect(gpx.contains("<desc>"), "forecasts come from the cache")
        #expect(await net.snapshot().weather == c.briefing?.stops.count, "no new forecast calls")
    }

    @Test func navigationTargets() async throws {
        let c = try await briefed()
        let b = try #require(c.briefing)
        let dest = try #require(b.stops.last)
        let item = StopNavigator.mapItem(for: dest)
        #expect(item.name == dest.label)
        #expect(abs(item.placemark.coordinate.latitude - dest.coordinate.latitude) < 1e-9)
        #expect(abs(item.placemark.coordinate.longitude - dest.coordinate.longitude) < 1e-9)
        #expect(StopNavigator.wazeURL(for: dest, wazeInstalled: true)?.scheme == "waze")
        #expect(StopNavigator.wazeURL(for: dest, wazeInstalled: false)?.host == "waze.com")
        #expect(!NavigationLinks.isNavigable(stopIndex: 0), "no Navigate on the origin card")
    }
}
