import Foundation
import RoadTripCore
import SwiftData
import Testing
@testable import RoadTripWeather

/// Phase-1 tasks 9–13 acceptance criteria, driven through the coordinator
/// with fakes whose network can be switched off (airplane mode).
@Suite("Briefing acceptance (tasks 9–13)", .serialized)
@MainActor
struct BriefingAcceptanceTests {
    let net = FakeNetwork()

    private func makeEnv(container: ModelContainerBox? = nil, routeThrough: Coordinate? = nil) throws -> AppEnvironment {
        let container = try container?.container ?? AppSchema.makeContainer(inMemory: true)
        let defaults = UserDefaults(suiteName: "BriefingAcceptanceTests-\(UUID().uuidString)") ?? .standard
        return AppEnvironment(
            container: container,
            settings: AppSettings(defaults: defaults),
            geocoding: FakeGeocoding(net: net),
            routing: FakeRouting(net: net, through: routeThrough),
            timeZones: MockTimeZoneService(),
            weather: FakeWeather(net: net),
            alerts: FakeAlerts(net: net),
            chargers: MockChargerService(),
            refresher: nil,
            isPreview: true
        )
    }

    private func briefed(_ env: AppEnvironment, range: Double = 180) async throws -> BriefingCoordinator {
        let c = BriefingCoordinator(env: env)
        c.plan.originText = "Denver"
        c.plan.destinationText = "Dallas"
        c.plan.rangeMi = range
        await c.findRoutes()
        try #require(!c.routes.isEmpty)
        await c.generateBriefing()
        try #require(c.briefing != nil)
        return c
    }

    // MARK: Task 9 — map colours

    @Test func segmentColoursFollowTheScaleAndRecolourWithoutNetwork() async throws {
        let c = try await briefed(makeEnv())
        let b = try #require(c.briefing)
        let map = BriefingMapView(briefing: b, dimmed: [], scale: .default, pois: [:], onPOITap: { _ in })
        let segs = map.segments(of: b)
        #expect(segs.count == b.stops.count - 1)
        for (seg, pair) in zip(segs, zip(b.stops, b.stops.dropFirst())) {
            let avg = TemperatureScale.segmentTemperature(pair.0.weather.map { Double($0.temperatureF) }, pair.1.weather.map { Double($0.temperatureF) })
            #expect(seg.colorHex == TemperatureScale.default.colorHex(forTemperatureF: avg))
        }

        // A single-band scale paints everything one colour; no service is touched.
        let callsBefore = await net.totalCalls
        net.online = false
        let flat = TemperatureScale(bands: [.init(label: "all", upperBound: nil, colorHex: "#123456")])
        let recoloured = BriefingMapView(briefing: b, dimmed: [], scale: flat, pois: [:], onPOITap: { _ in }).segments(of: b)
        #expect(recoloured.allSatisfy { $0.colorHex == "#123456" })
        #expect(await net.totalCalls == callsBefore)
    }

    // MARK: Task 10 — dwell → ETA shift → stale → refresh

    @Test func dwellShiftsLaterETAsMarksStaleAndRefreshClearsIt() async throws {
        let env = try makeEnv()
        let c = try await briefed(env)
        let before = try #require(c.briefing)
        try #require(before.stops.count >= 5)
        #expect(!before.isStale)

        // "Stop 3" counting the origin as stop 1 → index 2.
        let target = before.stops[2]
        c.updateDwell(stopID: target.id, minutes: target.dwellMinutes + 45)
        let after = try #require(c.briefing)

        for i in 0...2 { #expect(after.stops[i].eta == before.stops[i].eta, "stop \(i) must not move") }
        for i in 3..<after.stops.count {
            #expect(after.stops[i].eta.timeIntervalSince(before.stops[i].eta) == 45 * 60, "stop \(i) shifts by the dwell delta")
            #expect(after.stops[i].isForecastStale)
        }
        #expect(after.staleStops.count == after.stops.count - 3)

        // A 20-min change is under the 30-min drift threshold.
        c.updateDwell(stopID: target.id, minutes: target.dwellMinutes + 20)
        #expect(c.briefing?.isStale == false)
        c.updateDwell(stopID: target.id, minutes: target.dwellMinutes + 45)

        let calls = await net.snapshot()
        await c.refreshForecasts()
        let delta = await net.snapshot() - calls
        let refreshed = try #require(c.briefing)
        #expect(!refreshed.isStale)
        #expect(delta.geocode == 0 && delta.route == 0, "refresh must not re-route")
        #expect(delta.weather == refreshed.stops.count)
        #expect(delta.alerts == refreshed.stops.count)
        for s in refreshed.stops { #expect(s.forecastFor == s.eta) }
    }

    // MARK: Task 11 — precipitation timeline

    @Test func precipTimelineRules() {
        func stop(_ pop: Double?, _ cat: ConditionCategory = .clear) -> Stop {
            var s = Stop(kind: .sampled, label: "s", coordinate: Coordinate(lat: 0, lon: 0), routeIndex: 0, distanceMi: 0)
            s.weather = WeatherSnapshot(temperatureF: 60, feelsLikeF: 60, humidityPercent: nil, windMph: 0, windFromDegrees: nil, cloudPercent: nil, conditionRaw: "", conditionText: "", category: cat, recordDate: Date(), precipitationChance: pop, kind: .hourly)
            return s
        }
        #expect(PrecipTimelineView(stops: [stop(0.2), stop(nil), stop(nil)]).points.count < 2, "hidden with fewer than two stops with data")
        let pts = PrecipTimelineView(stops: [stop(0.1), stop(0.14), stop(0.15), stop(0.49), stop(0.5), stop(0.2, .thunderstorm), stop(0.05, .snow), stop(0.3, .severe)]).points
        #expect(pts.count == 8)
        #expect(pts.map(PrecipTimelineView.tone) == [.normal, .normal, .normal, .normal, .high, .severe, .severe, .severe])
        #expect(pts.map(PrecipTimelineView.showsValue) == [false, false, true, true, true, true, false, true])
        #expect(pts.first?.label == "DEP" && pts.last?.label == "ARR")
    }

    // MARK: Task 12 — POI layers offline

    @Test func poiLayerWorksOfflineAndAddedStopIsSnappedWithDefaultDwell() async throws {
        // Route the fake road through a real Buc-ee's from the bundled snapshot.
        let probe = try makeEnv()
        probe.pois.importBundledSnapshotIfNeeded()
        let store = try await probe.pois.pois(kind: .bucees)
        try #require(store.count >= 30, "bundled snapshot has \(store.count) Buc-ee's")
        let bucees = try #require(store.first { $0.name.contains("TX") } ?? store.first)

        let env = try makeEnv(container: ModelContainerBox(probe.container), routeThrough: bucees.coordinate)
        let c = try await briefed(env)
        net.online = false

        c.setPOILayer(.bucees, enabled: true)
        await c.refreshPOILayers()
        let pins = try #require(c.corridorPOIs[.bucees])
        #expect(pins.contains { $0.sourceID == bucees.sourceID })
        let route = try #require(c.selectedRoute)
        for p in pins { #expect(Geo.minDistanceMiles(from: p.coordinate, to: route.coordinates) * Geo.metersPerMile <= 8000 + 1) }

        let countBefore = c.briefing?.stops.count ?? 0
        await c.addStop(from: bucees)
        let b = try #require(c.briefing)
        #expect(b.stops.count == countBefore + 1)
        let added = try #require(b.stops.first { $0.poiSourceID == bucees.sourceID })
        #expect(added.poiKind == .bucees)
        #expect(added.kind == .poi)
        #expect(added.dwellMinutes == 15)
        #expect((added.offRouteMi ?? .infinity) < 1, "snapped to the route")
        #expect(added.weather == nil, "offline: no forecast yet")
        let i = try #require(b.stops.firstIndex { $0.id == added.id })
        #expect(b.stops[i - 1].distanceMi <= added.distanceMi && added.distanceMi <= b.stops[i + 1].distanceMi, "inserted in route order")

        net.online = true
        await c.refreshForecasts()
        #expect(c.briefing?.stops.first { $0.id == added.id }?.weather != nil, "forecast fetched once online")
    }

    // MARK: Task 13 — saved trip offline

    @Test func savedTripOpensOfflineWithEverything() async throws {
        let env = try makeEnv()
        env.pois.importBundledSnapshotIfNeeded()
        let c = try await briefed(env)
        let generated = Date().addingTimeInterval(-3 * 3600)
        c.briefings[c.selectedRouteIndex]?.generatedAt = generated
        let original = try #require(c.briefing)
        #expect(original.alerts.count > 0)
        try c.save(name: c.plan.defaultName)
        #expect(c.loadedTrip?.name == "Denver → Dallas")

        // Fresh coordinator on the same store, network off.
        net.online = false
        let offline = BriefingCoordinator(env: try makeEnv(container: ModelContainerBox(env.container)))
        let trip = try #require(env.trips.allTrips().first)
        offline.load(trip)

        let b = try #require(offline.briefing)
        #expect(b.stops.map(\.id) == original.stops.map(\.id))
        #expect(b.stops.map(\.eta) == original.stops.map(\.eta))
        #expect(b.stops.map { $0.weather?.temperatureF } == original.stops.map { $0.weather?.temperatureF })
        #expect(b.alerts.map(\.id) == original.alerts.map(\.id))
        #expect(b.geometry.coordinates.count == original.geometry.coordinates.count)
        #expect(offline.selectedRoute?.coordinates.count == original.geometry.coordinates.count, "route overlay available offline")
        #expect(b.weatherAttributionURL != nil)
        #expect(abs(b.generatedAt.timeIntervalSince(generated)) < 1)
        #expect(Fmt.age(b.generatedAt) == "3 hours ago")
        #expect(offline.statusMessage?.contains("3 hours ago") == true)

        offline.poiLayersEnabled = [.loves]
        await offline.refreshPOILayers()
        #expect(offline.corridorPOIs[.loves]?.isEmpty == false, "POIs from the local store")
    }

    @Test func ageWording() {
        let now = Date()
        #expect(Fmt.age(now.addingTimeInterval(0.2), now: now) == "just now")
        #expect(Fmt.age(now.addingTimeInterval(-30), now: now) == "just now")
        #expect(Fmt.age(now.addingTimeInterval(-3 * 3600), now: now) == "3 hours ago")
    }
}

// MARK: - Fakes with an airplane-mode switch

struct ModelContainerBox {
    let container: ModelContainer
    init(_ c: ModelContainer) { container = c }
}

final class FakeNetwork: @unchecked Sendable {
    struct Calls: Sendable {
        var geocode = 0, route = 0, weather = 0, alerts = 0
        static func - (a: Calls, b: Calls) -> Calls {
            Calls(geocode: a.geocode - b.geocode, route: a.route - b.route, weather: a.weather - b.weather, alerts: a.alerts - b.alerts)
        }
    }

    private let lock = NSLock()
    private var _online = true
    private var calls = Calls()

    var online: Bool {
        get { lock.withLock { _online } }
        set { lock.withLock { _online = newValue } }
    }

    func snapshot() async -> Calls { lock.withLock { calls } }
    var totalCalls: Int { get async { lock.withLock { calls.geocode + calls.route + calls.weather + calls.alerts } } }

    func hit(_ kp: WritableKeyPath<Calls, Int>) -> Bool {
        lock.withLock {
            calls[keyPath: kp] += 1
            return _online
        }
    }
}

struct FakeGeocoding: GeocodingService {
    let net: FakeNetwork
    func geocode(_ query: String) async throws -> PlacePoint {
        guard net.hit(\.geocode) else { throw URLError(.notConnectedToInternet) }
        return try await MockGeocodingService().geocode(query)
    }
}

/// Mock routes, or a straight east-west road through `through` when given.
struct FakeRouting: RoutingService {
    let net: FakeNetwork
    let through: Coordinate?

    func routes(through points: [PlacePoint], departure: Date) async throws -> RoutingResult {
        guard net.hit(\.route) else { throw URLError(.notConnectedToInternet) }
        guard let p = through else { return try await MockRoutingService().routes(through: points, departure: departure) }
        let coords = MockRoutingService.line(from: Coordinate(lat: p.lat, lon: p.lon - 4), to: Coordinate(lat: p.lat, lon: p.lon + 4), points: 400, bulge: 0)
        let miles = Geo.cumulativeMiles(coords).last ?? 0
        return RoutingResult(routes: [RouteGeometry(coordinates: coords, distanceMi: miles, durationSec: miles / 62 * 3600)], note: nil)
    }
}

struct FakeWeather: WeatherService {
    let net: FakeNetwork
    func forecast(at coordinate: Coordinate, for eta: Date) async throws -> ForecastResult {
        guard net.hit(\.weather) else { throw URLError(.notConnectedToInternet) }
        return try await MockWeatherService().forecast(at: coordinate, for: eta)
    }

    func attributionURL() async -> URL? { URL(string: "https://weatherkit.apple.com/legal-attribution.html") }
}

/// One alert at every stop while online.
struct FakeAlerts: AlertService {
    let net: FakeNetwork
    func alerts(at coordinate: Coordinate, eta: Date) async -> [WeatherAlert] {
        guard net.hit(\.alerts) else { return [] }
        return [WeatherAlert(id: "urn:wind", event: "Wind Advisory", severity: .moderate, headline: "h", areaDescription: "Somewhere", onset: eta.addingTimeInterval(-3600), ends: eta.addingTimeInterval(3600))]
    }
}
