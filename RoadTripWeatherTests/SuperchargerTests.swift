import Foundation
import RoadTripCore
import SwiftData
import Testing
@testable import RoadTripWeather

/// Phase-2 task P2-5: Superchargers from Open Charge Map for EV trips.
@Suite("Superchargers (P2-5)", .serialized)
@MainActor
struct SuperchargerTests {
    let net = FakeNetwork()

    private func makeCoordinator(chargers: FakeChargers, ev: Bool, container: ModelContainer? = nil, defaults: UserDefaults? = nil) throws -> BriefingCoordinator {
        let env = AppEnvironment(
            container: try container ?? AppSchema.makeContainer(inMemory: true),
            settings: AppSettings(defaults: defaults ?? UserDefaults(suiteName: "SuperchargerTests-\(UUID().uuidString)") ?? .standard),
            geocoding: FakeGeocoding(net: net),
            routing: FakeRouting(net: net, through: nil),
            timeZones: MockTimeZoneService(),
            weather: FakeWeather(net: net),
            alerts: FakeAlerts(net: net),
            chargers: chargers,
            refresher: nil,
            isPreview: true
        )
        env.trips.seedVehiclesIfNeeded()
        let c = BriefingCoordinator(env: env)
        c.plan.originText = "Denver"
        c.plan.destinationText = "Dallas"
        let vehicle = try #require(env.trips.vehicles().first { $0.isEV == ev })
        c.plan.vehicleID = vehicle.id.uuidString
        c.plan.rangeMi = 180
        return c
    }

    private func brief(_ c: BriefingCoordinator) async throws -> Briefing {
        await c.findRoutes()
        await c.generateBriefing()
        return try #require(c.briefing)
    }

    @Test func evTripGetsChargersAtEveryStopButTheOrigin() async throws {
        let chargers = FakeChargers(configured: true)
        let c = try makeCoordinator(chargers: chargers, ev: true)
        let b = try await brief(c)
        #expect(b.stops[0].chargers.isEmpty, "origin needs no charging stop")
        #expect(b.stops.dropFirst().allSatisfy { $0.chargers.count == 2 })
        #expect(chargers.calls == b.stops.count - 1)
        let ocm = try #require(c.env.status.status(.openChargeMap))
        #expect(ocm.recordCount == 2 * (b.stops.count - 1))
        #expect(c.env.status.sessionCalls[.openChargeMap] == b.stops.count - 1)
        #expect(b.stops[1].chargers.first?.summary == "Fake Supercharger · 1.5 mi off route · 8 stalls · 250 kW")
    }

    @Test func noLookupsWithoutAnEVOrAKey() async throws {
        let notEV = FakeChargers(configured: true)
        _ = try await brief(try makeCoordinator(chargers: notEV, ev: false))
        #expect(notEV.calls == 0)

        let noKey = FakeChargers(configured: false)
        let c = try makeCoordinator(chargers: noKey, ev: true)
        let b = try await brief(c)
        #expect(noKey.calls == 0)
        #expect(b.stops.allSatisfy { $0.chargers.isEmpty })
        #expect(c.env.status.status(.openChargeMap) == nil)
    }

    @Test func lookupFailureNeverFailsTheBriefing() async throws {
        let chargers = FakeChargers(configured: true, failing: true)
        let c = try makeCoordinator(chargers: chargers, ev: true)
        let b = try await brief(c)
        #expect(b.stops.allSatisfy { $0.chargers.isEmpty })
        #expect(b.stops.allSatisfy { $0.weather != nil })
        let n = b.stops.count - 1
        #expect(c.env.status.status(.openChargeMap)?.lastError == "\(n) of \(n) lookups failed (Request failed (HTTP 401).)")
    }

    @Test func chargersArePersistedAndAddedStopsGetThem() async throws {
        let container = try AppSchema.makeContainer(inMemory: true)
        let defaults = try #require(UserDefaults(suiteName: "SuperchargerTests-\(UUID().uuidString)"))
        let chargers = FakeChargers(configured: true)
        let c = try makeCoordinator(chargers: chargers, ev: true, container: container, defaults: defaults)
        _ = try await brief(c)
        #expect(await c.addStop(named: "Amarillo"))
        let added = try #require(c.briefing?.stops.first { $0.kind == .manual })
        #expect(added.chargers.count == 2)

        net.online = false
        let relaunched = try makeCoordinator(chargers: FakeChargers(configured: true), ev: true, container: container, defaults: defaults)
        let restored = try #require(relaunched.briefing)
        #expect(restored.stops.dropFirst().allSatisfy { $0.chargers.count == 2 }, "shown offline from the cache")
        #expect(restored.stops.first { $0.kind == .manual }?.chargers == added.chargers)
    }

    @Test func refreshAndOptimizerDontLookUpChargers() async throws {
        let chargers = FakeChargers(configured: true)
        let c = try makeCoordinator(chargers: chargers, ev: true)
        let b = try await brief(c)
        let calls = chargers.calls
        await c.refreshForecasts()
        #expect(chargers.calls == calls, "chargers don't depend on time; refresh keeps them")
        #expect(c.briefing?.stops.map(\.chargers) == b.stops.map(\.chargers))
        await c.runOptimizer(windowStart: c.plan.departure, windowEnd: c.plan.departure.addingTimeInterval(3 * 3600))
        #expect(chargers.calls == calls, "web optimizer skips chargers")
    }

    // MARK: Open Charge Map client

    @Test func clientSendsKeyInHeaderAndParses() async throws {
        OCMStub.reply = (200, Data(#"[{"AddressInfo":{"Title":"Amarillo Supercharger","Latitude":35.18,"Longitude":-101.87,"Distance":3.26,"Town":"Amarillo","StateOrProvince":"TX"},"NumberOfPoints":12,"Connections":[{"PowerKW":250}]}]"#.utf8))
        let service = OpenChargeMapService(session: OCMStub.session()) { " secret-key " }
        #expect(service.isConfigured)
        let found = try await service.superchargers(near: Coordinate(lat: 35.22198765, lon: -101.83129876))
        #expect(found.map(\.summary) == ["Amarillo Supercharger · 3.3 mi off route · 12 stalls · 250 kW"])
        let request = try #require(OCMStub.lastRequest)
        #expect(request.value(forHTTPHeaderField: "X-API-Key") == "secret-key")
        #expect(request.url?.absoluteString == "https://api.openchargemap.io/v3/poi/?output=json&latitude=35.2220&longitude=-101.8313&distance=30&distanceunit=Miles&maxresults=2&operatorid=23&compact=true&verbose=false")
        #expect(request.url?.query?.contains("secret") == false, "key never in the URL")
    }

    @Test func clientErrorsAndMissingKey() async throws {
        OCMStub.reply = (403, Data())
        let service = OpenChargeMapService(session: OCMStub.session()) { "k" }
        await #expect(throws: ServiceError.self) { try await service.superchargers(near: Coordinate(lat: 35, lon: -101)) }

        OCMStub.lastRequest = nil
        let noKey = OpenChargeMapService(session: OCMStub.session()) { "  " }
        #expect(!noKey.isConfigured)
        #expect(try await noKey.superchargers(near: Coordinate(lat: 35, lon: -101)).isEmpty)
        #expect(OCMStub.lastRequest == nil, "no request without a key")
    }
}

/// Canned Supercharger lookups with a call counter.
final class FakeChargers: ChargerService, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls = 0
    let configured: Bool
    let failing: Bool

    init(configured: Bool, failing: Bool = false) {
        self.configured = configured
        self.failing = failing
    }

    var calls: Int { lock.withLock { _calls } }
    var isConfigured: Bool { configured }

    func superchargers(near coordinate: Coordinate) async throws -> [Charger] {
        lock.withLock { _calls += 1 }
        if failing { throw ServiceError.http(401) }
        return (0..<2).map { i in
            Charger(name: i == 0 ? "Fake Supercharger" : "Backup Supercharger", coordinate: Coordinate(lat: coordinate.lat + 0.01, lon: coordinate.lon), distanceMi: 1.5 + Double(i), town: "Somewhere, TX", stalls: 8, powerKW: 250)
        }
    }
}

/// Single-reply stub for the OCM client; records the last request.
final class OCMStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var reply: (Int, Data) = (200, Data("[]".utf8))
    nonisolated(unsafe) static var lastRequest: URLRequest?

    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [OCMStub.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastRequest = request
        guard let url = request.url else { return }
        if let response = HTTPURLResponse(url: url, statusCode: Self.reply.0, httpVersion: "HTTP/1.1", headerFields: nil) {
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        }
        client?.urlProtocol(self, didLoad: Self.reply.1)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
