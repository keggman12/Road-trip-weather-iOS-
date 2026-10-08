import Foundation
import RoadTripCore
import SwiftData
import Testing
@testable import RoadTripWeather

/// Phase-1 task 14: Settings (bands, garage) and the Data Sources screen —
/// every row updates after its call; OCM reads "disabled — add a key".
@Suite("Settings and data sources (task 14)", .serialized)
@MainActor
struct SettingsDataSourcesTests {
    let net = FakeNetwork()

    private func makeEnv(refresher: POIRefreshService? = nil, defaults: UserDefaults? = nil) throws -> AppEnvironment {
        AppEnvironment(
            container: try AppSchema.makeContainer(inMemory: true),
            settings: AppSettings(defaults: defaults ?? UserDefaults(suiteName: "SettingsDataSourcesTests-\(UUID().uuidString)") ?? .standard),
            geocoding: FakeGeocoding(net: net),
            routing: FakeRouting(net: net, through: nil),
            timeZones: MockTimeZoneService(),
            weather: FakeWeather(net: net),
            alerts: FakeAlerts(net: net),
            chargers: MockChargerService(),
            refresher: refresher,
            isPreview: true
        )
    }

    // MARK: Data sources rows

    @Test func mapKitAndWeatherKitRowsUpdateAfterTheirCalls() async throws {
        let env = try makeEnv()
        #expect(env.status.status(.mapkit) == nil, "reading a row never inserts one")

        let c = BriefingCoordinator(env: env)
        c.plan.originText = "Denver"
        c.plan.destinationText = "Dallas"
        c.plan.rangeMi = 180
        await c.findRoutes()
        let mapkit = try #require(env.status.status(.mapkit))
        #expect(mapkit.lastSuccessAt != nil)
        #expect(mapkit.recordCount == c.routes.count)
        #expect(env.status.sessionCalls[.mapkit] == 3, "two geocodes + one route request")
        #expect(env.status.status(.weatherkit) == nil, "Find Routes makes no weather call")

        await c.generateBriefing()
        let stops = try #require(c.briefing?.stops.count)
        let wk = try #require(env.status.status(.weatherkit))
        #expect(wk.recordCount == stops, "one success covering every forecast, not 1")
        #expect(wk.lastError == nil)
        #expect(env.status.sessionCalls[.weatherkit] == stops)

        net.online = false
        await c.refreshForecasts()
        let failed = try #require(env.status.status(.weatherkit))
        #expect(failed.lastError == "\(stops) of \(stops) forecasts failed (\(c.briefing?.stops.prefix(3).map(\.label).joined(separator: ", ") ?? ""))")
        #expect(env.status.sessionCalls[.weatherkit] == stops * 2)

        let geocodeFail = BriefingCoordinator(env: env)
        geocodeFail.plan.originText = "Denver"
        geocodeFail.plan.destinationText = "Dallas"
        await geocodeFail.findRoutes()
        #expect(env.status.status(.mapkit)?.lastError != nil)
    }

    @Test func nwsRowRecordsEachCallsOutcome() throws {
        let env = try makeEnv()
        env.status.record(.nws, result: .success(2))
        #expect(env.status.status(.nws)?.recordCount == 2)
        env.status.record(.nws, result: .failure(ServiceError.http(503)))
        #expect(env.status.status(.nws)?.lastError == "Request failed (HTTP 503).")
        #expect(env.status.sessionCalls[.nws] == 2)
    }

    @Test func bundledImportFillsPOIAndSnapshotRows() async throws {
        let env = try makeEnv()
        await env.pois.importBundledSnapshotIfNeeded()
        let counts = try [POIKind.bucees, .loves, .rest].map { kind in
            try #require(env.status.status(DataSource(kind))?.recordCount)
        }
        // Snapshot payload counts are 57 / 619 / 3,622; rows within the
        // kind's dedupe cell collapse on import, and the rows report what's stored.
        var stored: [Int] = []
        for kind in [POIKind.bucees, .loves, .rest] { stored.append(try await env.pois.pois(kind: kind).count) }
        #expect(counts == stored)
        #expect(stored[0] >= 30 && stored[1] >= 300 && stored[2] > 0)
        #expect(env.status.status(.bundledSnapshot)?.recordCount == counts.reduce(0, +))
        #expect(env.pois.meta(for: .bucees)?.sourceRaw == POISource.bundled.rawValue)
    }

    @Test func overpassRowUpdatesOnFallbackSuccessAndFailure() async throws {
        let session = RefreshStub.session()
        let refresher = POIRefreshService(appVersion: "0.1.0", session: session, overpass: OverpassClient(appVersion: "0.1.0", session: session, timeout: 5))
        let env = try makeEnv(refresher: refresher)
        await env.pois.importBundledSnapshotIfNeeded()
        let lovesBefore = try await env.pois.pois(kind: .loves).count

        // Buc-ee's site down, first Overpass mirror answers with 40 locations.
        RefreshStub.handler = { url in
            if url.host == "buc-ees.com" { return (500, Data()) }
            if url.host == "overpass-api.de" { return (200, RefreshStub.overpassBody(count: 40)) }
            return (503, Data())
        }
        let outcome = try await env.pois.refresh(kind: .bucees)
        #expect(outcome.source == .osm && outcome.count == 40)
        #expect(env.status.status(.overpass)?.recordCount == 40)
        #expect(env.status.status(.bucees)?.recordCount == 40)
        #expect(env.status.sessionCalls[.overpass] == 1)

        // Love's site and every mirror down: both rows show errors, data kept.
        RefreshStub.handler = { _ in (503, Data()) }
        await #expect(throws: POIRefreshService.BothSourcesFailed.self) { try await env.pois.refresh(kind: .loves) }
        #expect(env.status.status(.overpass)?.lastError == "every mirror was unavailable")
        #expect(env.status.status(.loves)?.lastError?.contains("OpenStreetMap fallback failed") == true)
        do {
            let loves = try await env.pois.pois(kind: .loves)
            #expect(loves.count == lovesBefore, "failures never touch stored rows")
        } catch {
            Issue.record("pois(kind: .loves) threw \(error)")
        }
        #expect(env.status.sessionCalls[.overpass] == 2)
    }

    @Test func rowWording() {
        let none = DataSourcesView.summary(for: .openChargeMap, status: nil, calls: 0, ocmKeyStored: false)
        #expect(none.state == "disabled — add a key in Settings")
        #expect(!none.isSuccess && none.error == nil && none.calls == nil)
        #expect(DataSourcesView.summary(for: .openChargeMap, status: nil, calls: 0, ocmKeyStored: true).state.hasPrefix("key stored"))
        #expect(DataSourcesView.summary(for: .nws, status: nil, calls: 0, ocmKeyStored: false).state == "no successful call yet")

        let now = Date()
        let r = DataSourceStatusRecord(sourceRaw: DataSource.weatherkit.rawValue)
        r.lastSuccessAt = now.addingTimeInterval(-2 * 3600)
        r.recordCount = 6
        r.lastError = "1 of 6 forecasts failed (Waypoint 3)"
        r.lastErrorAt = now
        let row = DataSourcesView.summary(for: .weatherkit, status: r, calls: 1, ocmKeyStored: false, now: now)
        #expect(row.state == "Last success 2 hours ago · 6 records")
        #expect(row.isSuccess)
        #expect(row.error == "Error just now: 1 of 6 forecasts failed (Waypoint 3)")
        #expect(row.calls == "1 call this session")
    }

    // MARK: Temperature bands

    @Test func bandsApplyFixesBoundsPersistsAndResets() throws {
        let defaults = try #require(UserDefaults(suiteName: "bands-\(UUID().uuidString)"))
        let settings = AppSettings(defaults: defaults)
        var draft = TemperatureScale.default
        draft.bands[1].upperBound = 40          // below Cold's 48
        draft.bands[2].upperBound = 40          // not above the fixed Cool
        draft.bands[4].upperBound = 100         // last band must stay open
        draft.bands[0].colorHex = "#000000"
        settings.applyScale(draft)
        #expect(settings.temperatureScale.bands.map(\.upperBound) == [48, 49, 50, 83, nil])
        #expect(settings.temperatureScale.bands[0].colorHex == "#000000")

        let relaunched = AppSettings(defaults: defaults)
        #expect(relaunched.temperatureScale == settings.temperatureScale, "persisted")

        relaunched.resetScale()
        #expect(relaunched.temperatureScale == .default)
        #expect(AppSettings(defaults: defaults).temperatureScale == .default)
    }

    // MARK: Garage

    @Test func garageKeepsOneVehicleClampsRangeAndResets() throws {
        let env = try makeEnv()
        let trips = env.trips
        trips.seedVehiclesIfNeeded()
        let seeded = trips.vehicles()
        #expect(seeded.map(\.name) == Vehicle.defaults.map(\.name))

        let added = trips.addVehicle()
        #expect(trips.vehicles().last?.id == added.id)
        trips.setRange(5000, for: added)
        #expect(added.rangeMi == 800)
        trips.setRange(5, for: added)
        #expect(added.rangeMi == 20)

        #expect(trips.deleteVehicles(trips.vehicles()) == false, "can't empty the garage")
        #expect(trips.vehicles().count == seeded.count + 1)
        #expect(trips.deleteVehicles(Array(trips.vehicles().dropFirst())))
        #expect(trips.vehicles().count == 1)

        trips.resetVehicles()
        #expect(trips.vehicles().map(\.name) == Vehicle.defaults.map(\.name))
        #expect(trips.vehicles().map(\.rangeMi) == Vehicle.defaults.map(\.rangeMi))
    }
}

/// URL-keyed stub for the POI refresh path; separate from `StubURLProtocol`
/// so suites running in parallel don't share responders.
final class RefreshStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: @Sendable (URL) -> (Int, Data) = { _ in (503, Data()) }

    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RefreshStub.self]
        return URLSession(configuration: config)
    }

    static func overpassBody(count: Int) -> Data {
        let elements: [[String: Any]] = (0..<count).map { i in
            ["type": "node", "id": 9000 + i, "lat": 30 + Double(i) * 0.1, "lon": -97.0, "tags": ["brand": "Buc-ee's", "name": "Buc-ee's #\(i)"]]
        }
        return (try? JSONSerialization.data(withJSONObject: ["version": 0.6, "elements": elements])) ?? Data()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        let (code, body) = Self.handler(url)
        if let response = HTTPURLResponse(url: url, statusCode: code, httpVersion: "HTTP/1.1", headerFields: nil) {
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        }
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
