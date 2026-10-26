import Foundation
import RoadTripCore
import Testing
@testable import RoadTripWeather

/// Coordinator behaviour with the deterministic mocks (no network).
@Suite("Briefing coordinator")
@MainActor
struct BriefingCoordinatorTests {
    nonisolated static let legalURL = URL(string: "https://weatherkit.apple.com/legal-attribution.html")

    private func makeCoordinator(weather: any WeatherService = AttributedMockWeather()) throws -> BriefingCoordinator {
        let container = try AppSchema.makeContainer(inMemory: true)
        let defaults = UserDefaults(suiteName: "BriefingCoordinatorTests-\(UUID().uuidString)") ?? .standard
        let env = AppEnvironment(
            container: container,
            settings: AppSettings(defaults: defaults),
            geocoding: MockGeocodingService(),
            routing: MockRoutingService(),
            timeZones: MockTimeZoneService(),
            weather: weather,
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

    @Test func explicitDepartureEditRejectsPastAndPreservesItinerary() async throws {
        let c = try makeCoordinator()
        await c.findRoutes()
        await c.generateBriefing()
        let original = try #require(c.briefing)
        c.updateDwell(stopID: original.stops[1].id, minutes: 75)
        let edited = try #require(c.briefing)
        let now = Date()
        c.setDeparture(now.addingTimeInterval(-60), now: now)
        #expect(c.plan.departure == original.departure)
        #expect(c.errorMessage != nil)
        c.departToday(now: original.departure.addingTimeInterval(60))
        #expect(c.plan.departure > original.departure)
        #expect(c.briefing?.stops.map(\.id) == edited.stops.map(\.id))
        #expect(c.briefing?.stops[1].dwellMinutes == 75)
        #expect(c.briefing?.stops.map(\.weather) == edited.stops.map(\.weather))
        #expect(c.briefing?.departure == c.plan.departure)
    }

    @Test func refreshSkipsElapsedStopsAndEndedTripsKeepCache() async throws {
        let weather = SwitchableWeather()
        let c = try makeCoordinator(weather: weather)
        await c.findRoutes()
        await c.generateBriefing()
        let cached = try #require(c.briefing)
        let cutoff = cached.stops[1].eta
        await weather.resetRequests()
        await c.refreshForecasts(now: cutoff)
        #expect(await weather.requests.sorted() == cached.stops.filter { $0.eta >= cutoff }.map(\.eta).sorted())
        #expect(c.briefing?.stops.first == cached.stops.first)
        #expect(c.briefing?.generatedAt == cached.generatedAt)
        #expect(c.statusMessage?.contains("upcoming stops") == true)
        let refreshed = try #require(c.briefing)
        await weather.resetRequests()
        let last = try #require(cached.stops.last)
        await c.refreshForecasts(now: last.eta.addingTimeInterval(1))
        #expect(await weather.requests.isEmpty)
        #expect(c.briefing?.stops == refreshed.stops)
        #expect(c.statusMessage?.contains("trip has ended") == true)
    }

    @Test func failedRefreshPreservesCacheAndReportsFailure() async throws {
        let weather = SwitchableWeather()
        let c = try makeCoordinator(weather: weather)
        await c.findRoutes()
        await c.generateBriefing()
        let cached = try #require(c.briefing)
        await weather.fail()
        await c.refreshForecasts()
        let refreshed = try #require(c.briefing)
        #expect(refreshed.stops.map(\.weather) == cached.stops.map(\.weather))
        #expect(refreshed.stops.map(\.forecastFor) == cached.stops.map(\.forecastFor))
        #expect(refreshed.generatedAt == cached.generatedAt)
        #expect(c.statusMessage?.contains("Refresh failed") == true)
    }

    @Test func partialRefreshUpdatesSuccessesAndKeepsFailedCache() async throws {
        let weather = SwitchableWeather()
        let c = try makeCoordinator(weather: weather)
        await c.findRoutes()
        await c.generateBriefing()
        let cached = try #require(c.briefing)
        let first = try #require(cached.stops.first)
        await weather.fail(at: first.coordinate)
        await c.refreshForecasts()
        let result = try #require(c.briefing)
        #expect(result.stops.first?.weather == first.weather)
        #expect(result.stops.first?.forecastFor == first.forecastFor)
        #expect(result.generatedAt == cached.generatedAt)
        #expect(c.statusMessage?.contains("Refresh failed for 1 of") == true)
        #expect(result.stops.dropFirst().allSatisfy { $0.forecastFor == $0.eta })
    }

    @Test func regenerationAndAdoptionKeepEditedItinerary() async throws {
        let c = try makeCoordinator()
        await c.findRoutes()
        await c.generateBriefing()
        let initial = try #require(c.briefing)
        let id = initial.stops[1].id
        c.updateDwell(stopID: id, minutes: 75)
        c.toggleManualOvernight(stopID: id, on: true)
        c.removeStop(stopID: initial.stops[2].id)
        await c.addStop(ManualStopEdit(coordinate: initial.stops[1].coordinate, label: "Lunch"))
        let edited = try #require(c.briefing)
        await c.generateBriefing()
        #expect(c.briefing?.stops.map(\.id) == edited.stops.map(\.id))
        // The optimizer scores planned stops only (HANDOFF §4).
        let candidate = try #require(await c.brief(routeIndex: c.selectedRouteIndex, label: "Candidate", departure: c.plan.departure.addingTimeInterval(3600), progress: { _, _ in }))
        #expect(candidate.stops.count == initial.stops.count)
        #expect(!candidate.stops.contains { $0.kind.isUserAdded || $0.dwellMinutes == 75 })
        #expect(c.briefing?.stops.map(\.id) == edited.stops.map(\.id), "scoring a candidate leaves the briefing alone")
        let cell = BriefingCoordinator.cell(for: candidate, departure: candidate.departure, label: "Candidate")
        await c.adopt(cell)
        #expect(c.briefing?.stops.map(\.id) == edited.stops.map(\.id))
        #expect(c.briefing?.stops.first(where: { $0.id == id })?.dwellMinutes == 75)
        #expect(c.briefing?.stops.first(where: { $0.id == id })?.manualOvernight == true)
        #expect(c.briefing?.removedMi == edited.removedMi)
    }

    @Test func rangeChangeReplansAndKeepsUserStops() async throws {
        let c = try makeCoordinator()
        await c.findRoutes()
        await c.generateBriefing()
        let initial = try #require(c.briefing)
        await c.addStop(ManualStopEdit(coordinate: initial.stops[1].coordinate, label: "Lunch"))
        c.plan.rangeMi = 400
        await c.generateBriefing()
        let replanned = try #require(c.briefing)
        #expect(replanned.rangeMi == 400)
        #expect(replanned.stops.filter { !$0.kind.isUserAdded }.count < initial.stops.count, "fewer stops at a longer range")
        #expect(replanned.stops.contains { $0.kind.isUserAdded && $0.label == "Lunch" })
    }

    @Test func newBriefingForPassedDepartureIsRefused() async throws {
        let c = try makeCoordinator()
        await c.findRoutes()
        await c.generateBriefing(now: c.plan.departure.addingTimeInterval(60))
        #expect(c.briefing == nil)
        #expect(c.errorMessage?.contains("Depart today") == true)
    }

    @Test func adoptingAPassedDepartureIsRefused() async throws {
        let c = try makeCoordinator()
        await c.findRoutes()
        await c.generateBriefing()
        let b = try #require(c.briefing)
        let cell = BriefingCoordinator.cell(for: b, departure: b.departure.addingTimeInterval(-3600), label: "Past")
        await c.adopt(cell)
        #expect(c.plan.departure == b.departure)
        #expect(c.errorMessage != nil)
    }

    @Test func incompleteCandidatesCannotBeRecommended() async throws {
        let c = try makeCoordinator()
        await c.findRoutes()
        await c.generateBriefing()
        let b = try #require(c.briefing)
        var complete = BriefingCoordinator.cell(for: b, departure: b.departure, label: "Complete")
        complete.failedForecasts = 0
        complete.score = 500
        var missing = complete
        missing.departure = b.departure.addingTimeInterval(3600)
        missing.failedForecasts = 1
        missing.score = 0
        var result = OptimizerResult(windowStart: b.departure, windowEnd: missing.departure, routeIndices: [0], rows: [[missing], [complete]])
        #expect(result.best == complete)
        #expect(result.ranked.first == complete)
        result.rows = [[missing]]
        #expect(result.best == nil)
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

private actor SwitchableWeather: WeatherService {
    var requests: [Date] = []
    func resetRequests() { requests = [] }
    var failing = false
    var failedCoordinate: Coordinate?
    func fail(at coordinate: Coordinate) { failedCoordinate = coordinate }
    func fail() { failing = true }
    func forecast(at coordinate: Coordinate, for eta: Date) async throws -> ForecastResult {
        requests.append(eta)
        if failing || coordinate == failedCoordinate { throw URLError(.notConnectedToInternet) }
        return try await MockWeatherService().forecast(at: coordinate, for: eta)
    }
    func attributionURL() async -> URL? { nil }
}
