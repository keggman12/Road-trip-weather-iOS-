import Foundation
import RoadTripCore
import SwiftData
import Testing
@testable import RoadTripWeather

/// Phase-2 task P2-3: type a place, it becomes a manual stop on the route.
@Suite("Manual stop entry (P2-3)", .serialized)
@MainActor
struct ManualStopTests {
    let net = FakeNetwork()
    static let amarillo = Coordinate(lat: 35.222, lon: -101.8313)

    private func briefed(routeThrough: Coordinate? = nil, container: ModelContainer? = nil, defaults: UserDefaults? = nil) async throws -> BriefingCoordinator {
        let env = AppEnvironment(
            container: try container ?? AppSchema.makeContainer(inMemory: true),
            settings: AppSettings(defaults: defaults ?? UserDefaults(suiteName: "ManualStopTests-\(UUID().uuidString)") ?? .standard),
            geocoding: FakeGeocoding(net: net),
            routing: FakeRouting(net: net, through: routeThrough),
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

    @Test func placeOnTheRouteIsSnappedForecastAndShiftsLaterStops() async throws {
        let c = try await briefed(routeThrough: Self.amarillo)
        let before = try #require(c.briefing)
        let recentsBefore = c.env.settings.recentLocations

        #expect(await c.addStop(named: "  Amarillo "))
        let after = try #require(c.briefing)
        #expect(after.stops.count == before.stops.count + 1)
        let added = try #require(after.stops.first { $0.kind == .manual })
        #expect(added.label == "Amarillo, TX, USA")
        #expect(added.dwellMinutes == 15)
        #expect((added.offRouteMi ?? .infinity) < 1)
        #expect(c.statusMessage == "Added “Amarillo, TX, USA” (snapped to route).")
        #expect(added.weather != nil && added.forecastFor == added.eta)
        #expect(added.alerts.count == 1, "alerts fetched too")
        #expect(c.env.settings.recentLocations.first == "Amarillo")
        #expect(c.env.settings.recentLocations.count == recentsBefore.count + 1)

        // Every stop past the new one leaves 15 min later; earlier ones don't move.
        for old in before.stops {
            let now = try #require(after.stops.first { $0.id == old.id })
            let shift = now.eta.timeIntervalSince(old.eta)
            #expect(abs(shift - (old.distanceMi > added.distanceMi ? 15 * 60 : 0)) < 0.01, "\(old.label)")
        }
        #expect(c.env.trips.draftBriefings().first?.stops.contains { $0.id == added.id } == true, "persisted")
    }

    @Test func placeOffTheRouteReportsTheDistance() async throws {
        let c = try await briefed()          // fake road runs well north of Amarillo
        #expect(await c.addStop(named: "Amarillo"))
        let added = try #require(c.briefing?.stops.first { $0.kind == .manual })
        let off = try #require(added.offRouteMi)
        #expect(off > 1)
        #expect(c.statusMessage == "Added “Amarillo, TX, USA” (~\(Int(off.rounded())) mi off route).")
    }

    @Test func unknownPlaceChangesNothing() async throws {
        let c = try await briefed()
        let before = try #require(c.briefing)
        let recents = c.env.settings.recentLocations
        #expect(await c.addStop(named: "Atlantis") == false)
        #expect(c.errorMessage?.contains("Atlantis") == true)
        #expect(c.briefing == before)
        #expect(c.env.settings.recentLocations == recents)
        #expect(await c.addStop(named: "   ") == false)
        #expect(!c.isBusy)
    }

    @Test func manualStopSurvivesSaveReloadAndRegenerate() async throws {
        let container = try AppSchema.makeContainer(inMemory: true)
        let defaults = try #require(UserDefaults(suiteName: "ManualStopTests-\(UUID().uuidString)"))
        let c = try await briefed(routeThrough: Self.amarillo, container: container, defaults: defaults)
        #expect(await c.addStop(named: "Amarillo"))
        try c.save(name: "With Amarillo")

        // Relaunch: the draft carries the stop.
        let relaunched = try await briefedRelaunch(container: container, defaults: defaults)
        #expect(relaunched.briefing?.stops.contains { $0.kind == .manual && $0.label == "Amarillo, TX, USA" } == true)

        // Reload the saved trip, re-find routes and regenerate: the edit replays.
        let trip = try #require(relaunched.env.trips.allTrips().first)
        relaunched.load(trip)
        #expect(relaunched.plan.stopEdits.manualStops.map(\.label) == ["Amarillo, TX, USA"])
        await relaunched.findRoutes()
        await relaunched.generateBriefing()
        let replayed = try #require(relaunched.briefing?.stops.first { $0.kind == .manual })
        #expect(replayed.label == "Amarillo, TX, USA")
        #expect(replayed.weather != nil)
    }

    private func briefedRelaunch(container: ModelContainer, defaults: UserDefaults) async throws -> BriefingCoordinator {
        let env = AppEnvironment(
            container: container,
            settings: AppSettings(defaults: defaults),
            geocoding: FakeGeocoding(net: net),
            routing: FakeRouting(net: net, through: Self.amarillo),
            timeZones: MockTimeZoneService(),
            weather: FakeWeather(net: net),
            alerts: FakeAlerts(net: net),
            chargers: MockChargerService(),
            refresher: nil,
            isPreview: true
        )
        return BriefingCoordinator(env: env)
    }
}
