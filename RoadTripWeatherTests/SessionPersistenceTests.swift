import Foundation
import Observation
import RoadTripCore
import SwiftData
import Testing
@testable import RoadTripWeather

/// Phase-1 task 8: a generated briefing is persisted as a CachedBriefing with
/// all stops before the UI sees it, and the session survives a relaunch.
@Suite("Session persistence (task 8)", .serialized)
@MainActor
struct SessionPersistenceTests {
    let net = FakeNetwork()

    /// A "launch": a fresh environment + coordinator over the given store.
    private func launch(container: ModelContainer, defaults: UserDefaults) -> BriefingCoordinator {
        let env = AppEnvironment(
            container: container,
            settings: AppSettings(defaults: defaults),
            geocoding: FakeGeocoding(net: net),
            routing: FakeRouting(net: net, through: nil),
            timeZones: MockTimeZoneService(),
            weather: FakeWeather(net: net),
            alerts: FakeAlerts(net: net),
            chargers: MockChargerService(),
            refresher: nil,
            isPreview: true
        )
        return BriefingCoordinator(env: env)
    }

    private func freshStore() throws -> (ModelContainer, UserDefaults) {
        let defaults = try #require(UserDefaults(suiteName: "SessionPersistenceTests-\(UUID().uuidString)"))
        return (try AppSchema.makeContainer(inMemory: true), defaults)
    }

    private func plan(_ c: BriefingCoordinator, to destination: String = "Dallas") {
        c.plan.originText = "Denver"
        c.plan.destinationText = destination
        c.plan.rangeMi = 180
    }

    @Test func briefingIsPersistedBeforeItIsPublished() async throws {
        let (container, defaults) = try freshStore()
        let c = launch(container: container, defaults: defaults)
        plan(c)
        await c.findRoutes()

        nonisolated(unsafe) var draftsAtPublish: [Briefing]?
        withObservationTracking { _ = c.briefings } onChange: {
            MainActor.assumeIsolated { draftsAtPublish = c.env.trips.draftBriefings() }
        }
        await c.generateBriefing()

        let shown = try #require(c.briefing)
        let persisted = try #require(draftsAtPublish?.first, "a draft existed when briefings changed")
        #expect(persisted.id == shown.id)
        #expect(persisted.stops.map(\.id) == shown.stops.map(\.id), "all stops")
        #expect(persisted.stops.allSatisfy { $0.weather != nil })
        #expect(persisted.weatherAttributionURL != nil)
    }

    @Test func sessionSurvivesRelaunchIncludingEdits() async throws {
        let (container, defaults) = try freshStore()
        let first = launch(container: container, defaults: defaults)
        plan(first)
        await first.findRoutes()
        await first.generateBriefing()
        let stop = try #require(first.briefing?.stops[2])
        first.updateDwell(stopID: stop.id, minutes: 40)
        let before = try #require(first.briefing)

        net.online = false
        let callsBefore = await net.totalCalls
        let second = launch(container: container, defaults: defaults)
        let restored = try #require(second.briefing)
        #expect(restored.stops.map(\.id) == before.stops.map(\.id))
        #expect(restored.stops.map(\.eta) == before.stops.map(\.eta))
        #expect(restored.stops[2].dwellMinutes == 40)
        #expect(second.plan.originText == "Denver" && second.plan.destinationText == "Dallas")
        #expect(second.selectedRouteIndex == first.selectedRouteIndex)
        #expect(second.selectedRoute?.coordinates.count == before.geometry.coordinates.count)
        #expect(second.statusMessage?.hasPrefix("Restored your last briefing") == true)
        #expect(await net.totalCalls == callsBefore, "restoring made no network calls")
    }

    @Test func newBriefingReplacesTheOldDrafts() async throws {
        let (container, defaults) = try freshStore()
        let c = launch(container: container, defaults: defaults)
        plan(c)
        await c.findRoutes()
        await c.generateBriefing(allRoutes: true)
        #expect(c.env.trips.draftBriefings().count == c.routes.count)

        plan(c, to: "Amarillo")
        await c.findRoutes()
        await c.generateBriefing()
        let drafts = c.env.trips.draftBriefings()
        #expect(drafts.count == 1)
        #expect(drafts.first?.stops.last?.label.contains("Amarillo") == true)
    }

    @Test func savedTripSessionRestoresTheTripLink() async throws {
        let (container, defaults) = try freshStore()
        let first = launch(container: container, defaults: defaults)
        plan(first)
        await first.findRoutes()
        await first.generateBriefing()
        try first.save(name: "Work trip")

        let second = launch(container: container, defaults: defaults)
        #expect(second.loadedTrip?.name == "Work trip")
        #expect(second.env.trips.allTrips().count == 1, "drafts don't show up as trips")
    }

    @Test func noSessionMeansAnEmptyStart() throws {
        let (container, defaults) = try freshStore()
        let c = launch(container: container, defaults: defaults)
        #expect(c.briefings.isEmpty)
        #expect(c.routes.isEmpty)
        #expect(c.statusMessage == nil)
    }
}
