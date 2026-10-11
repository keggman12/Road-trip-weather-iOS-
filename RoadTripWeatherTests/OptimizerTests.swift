import Foundation
import RoadTripCore
import SwiftData
import Testing
@testable import RoadTripWeather

/// Phase-2 task P2-4: best-time-to-leave optimizer.
@Suite("Optimizer (P2-4)", .serialized)
@MainActor
struct OptimizerTests {
    let net = FakeNetwork()

    private func briefed(routeThrough: Coordinate? = nil, weather: (any WeatherService)? = nil) async throws -> BriefingCoordinator {
        let env = AppEnvironment(
            container: try AppSchema.makeContainer(inMemory: true),
            settings: AppSettings(defaults: UserDefaults(suiteName: "OptimizerTests-\(UUID().uuidString)") ?? .standard),
            geocoding: FakeGeocoding(net: net),
            routing: FakeRouting(net: net, through: routeThrough),
            timeZones: MockTimeZoneService(),
            weather: weather ?? FakeWeather(net: net),
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

    @Test func singleRouteIsRankedBestFirstAndLeavesTheBriefingAlone() async throws {
        let start = TripPlan.defaultDeparture()
        let warming = WarmingWeather(reference: start, net: net)
        let c = try await briefed(routeThrough: Coordinate(lat: 35.2, lon: -101.8), weather: warming)
        try #require(c.optimizableRouteIndices.count == 1)
        let briefingBefore = c.briefings
        let draftsBefore = c.env.trips.draftBriefings()
        let planBefore = c.plan
        let callsBefore = await net.snapshot().weather
        let stops = try #require(c.briefing?.stops.count)

        let end = start.addingTimeInterval(6 * 3600)
        await c.runOptimizer(windowStart: start, windowEnd: end)
        let result = try #require(c.optimizer)

        let expected = DepartureCandidates.candidates(windowStart: start, windowEnd: end, routeCount: 1)
        #expect(expected.count == 3, "round(6 / 2.5) + 1")
        #expect(!result.isMatrix)
        #expect(result.cells.map(\.departure) == expected)
        #expect(await net.snapshot().weather - callsBefore == expected.count * stops, "one forecast per stop per candidate")

        // Later departures drive through hotter hours, so the earliest wins.
        #expect(result.ranked.map(\.departure) == expected)
        #expect(result.ranked.map(\.score) == result.ranked.map(\.score).sorted())
        #expect(result.best?.departure == start)
        let best = try #require(result.best)
        #expect(best.worstNear != nil && best.worstCondition != nil)
        #expect(best.arrivalTimeZoneID == "America/Chicago")
        #expect(c.statusMessage?.hasPrefix("Optimizer done — best: depart") == true)

        #expect(c.briefings == briefingBefore, "on-screen briefing untouched")
        #expect(c.env.trips.draftBriefings() == draftsBefore, "drafts untouched")
        #expect(c.plan == planBefore)
        #expect(c.phase == .idle)
    }

    @Test func severalRoutesMakeAMatrixWithOneBest() async throws {
        let c = try await briefed()
        let routes = c.optimizableRouteIndices
        try #require(routes.count == 2)
        let start = c.plan.departure
        await c.runOptimizer(windowStart: start, windowEnd: start.addingTimeInterval(12 * 3600))
        let result = try #require(c.optimizer)
        #expect(result.isMatrix)
        #expect(result.rows.count == 6, "min(round(12/2.5)+1, 12/2 routes)")
        #expect(result.rows.allSatisfy { $0.map(\.routeIndex) == routes })
        let best = try #require(result.best)
        #expect(best.score == result.cells.map(\.score).min())
        #expect(best.id == result.cells.first { $0.score == best.score }?.id, "ties go to the earliest cell")
    }

    @Test func failedForecastsScoreAsUnknownInsteadOfAborting() async throws {
        let c = try await briefed(routeThrough: Coordinate(lat: 35.2, lon: -101.8))
        net.online = false
        let start = c.plan.departure
        await c.runOptimizer(windowStart: start, windowEnd: start.addingTimeInterval(3 * 3600))
        let result = try #require(c.optimizer)
        let stops = try #require(c.briefing?.stops.count)
        #expect(result.cells.count == 2)
        for cell in result.cells {
            #expect(cell.failedForecasts == stops)
            #expect(cell.score == Int(TripScorer.unknownWeatherPenalty) * stops)
        }
    }

    @Test func cancelStopsBeforeAnyCall() async throws {
        let c = try await briefed()
        let calls = await net.snapshot().weather
        let start = c.plan.departure
        c.startOptimizer(windowStart: start, windowEnd: start.addingTimeInterval(12 * 3600))
        c.cancelOptimizer()
        await c.optimizerTask?.value
        #expect(c.optimizer?.cancelled == true)
        #expect(c.optimizer?.cells.isEmpty == true)
        #expect(await net.snapshot().weather == calls)
        #expect(c.phase == .idle)
    }

    @Test func adoptingAResultRebriefsWithItsDepartureAndRoute() async throws {
        let c = try await briefed()
        let start = c.plan.departure
        await c.runOptimizer(windowStart: start, windowEnd: start.addingTimeInterval(12 * 3600))
        let pick = try #require(c.optimizer?.cells.last)       // latest departure, last route
        await c.adopt(pick)
        #expect(c.plan.departure == pick.departure)
        #expect(c.selectedRouteIndex == pick.routeIndex)
        let b = try #require(c.briefing)
        #expect(b.departure == pick.departure && b.routeIndex == pick.routeIndex)
        #expect(c.env.trips.draftBriefings().contains { $0.departure == pick.departure }, "adopted briefing is persisted")
    }

    @Test func invalidWindowIsRejected() async throws {
        let c = try await briefed()
        await c.runOptimizer(windowStart: c.plan.departure, windowEnd: c.plan.departure)
        #expect(c.errorMessage == "Set a valid optimizer window (end after start).")
        #expect(c.optimizer == nil)
    }
}

/// Clear skies everywhere, 65 °F at `reference` and 3 °F warmer every hour
/// after — so a later departure always scores worse.
struct WarmingWeather: WeatherService {
    let reference: Date
    let net: FakeNetwork

    func forecast(at coordinate: Coordinate, for eta: Date) async throws -> ForecastResult {
        guard net.hit(\.weather) else { throw URLError(.notConnectedToInternet) }
        let hours = max(0, eta.timeIntervalSince(reference) / 3600)
        let t = 65 + Int((hours * 3).rounded())
        return ForecastResult(snapshot: WeatherSnapshot(temperatureF: t, feelsLikeF: t, humidityPercent: 30, windMph: 5, windFromDegrees: 180, cloudPercent: 0, conditionRaw: "clear", conditionText: "Clear", category: .clear, recordDate: eta, precipitationChance: 0, kind: .hourly), horizon: .ok)
    }

    func attributionURL() async -> URL? { nil }
}
