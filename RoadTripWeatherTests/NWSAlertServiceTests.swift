import Foundation
import RoadTripCore
import Testing
@testable import RoadTripWeather

/// Phase-1 task 6 acceptance: User-Agent on every request, ±2 h ETA buffer,
/// 429 retried, network failure yields []. Serialized because the stub's
/// responder is shared state.
@Suite("NWS alert service", .serialized)
struct NWSAlertServiceTests {
    private let point = Coordinate(lat: 35.222, lon: -101.8313)
    private let eta = Date(timeIntervalSince1970: 1_781_118_000) // 2026-06-10 19:00Z

    private func makeService(sink: (@Sendable (Result<Int, Error>) -> Void)? = nil) -> NWSAlertService {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return NWSAlertService(contactEmail: "me@example.com", appVersion: "0.1.0", session: URLSession(configuration: config), retryDelay: .zero, statusSink: sink)
    }

    @Test func everyRequestCarriesUserAgentAndPoint() async throws {
        StubURLProtocol.respond([.status(429), .json(Self.body([]))])
        _ = await makeService().alerts(at: point, eta: eta)

        let requests = StubURLProtocol.requests
        #expect(requests.count == 2)
        for r in requests {
            let ua = try #require(r.value(forHTTPHeaderField: "User-Agent"))
            #expect(ua == ClientIdentity.nwsUserAgent(version: "0.1.0", contact: "me@example.com"))
            #expect(ua.contains("me@example.com"))
            #expect(r.value(forHTTPHeaderField: "Accept") == "application/geo+json")
            #expect(r.url?.absoluteString == "https://api.weather.gov/alerts/active?point=35.2220,-101.8313")
        }
    }

    @Test func endsBufferKeepsOneHourBeforeAndDropsThreeHoursBefore() async {
        StubURLProtocol.respond([.json(Self.body([
            ("urn:ended-3h", eta.addingTimeInterval(-6 * 3600), eta.addingTimeInterval(-3 * 3600)),
            ("urn:ended-1h", eta.addingTimeInterval(-6 * 3600), eta.addingTimeInterval(-1 * 3600)),
        ]))])
        let alerts = await makeService().alerts(at: point, eta: eta)
        #expect(alerts.map(\.id) == ["urn:ended-1h"])
    }

    @Test func rateLimitIsRetried() async {
        StubURLProtocol.respond([.status(429), .status(503), .json(Self.body([("urn:a", nil, nil)]))])
        let alerts = await makeService().alerts(at: point, eta: eta)
        #expect(alerts.map(\.id) == ["urn:a"])
        #expect(StubURLProtocol.requests.count == 3)
    }

    @Test func persistentServerErrorGivesUpAfterThreeAttempts() async {
        StubURLProtocol.respond([.status(503), .status(503), .status(503), .status(503)])
        let sink = ResultRecorder()
        let alerts = await makeService(sink: sink.record).alerts(at: point, eta: eta)
        #expect(alerts.isEmpty)
        #expect(StubURLProtocol.requests.count == 3)
        #expect(sink.failures == 1)
    }

    @Test func clientErrorIsNotRetried() async {
        StubURLProtocol.respond([.status(404), .json(Self.body([("urn:a", nil, nil)]))])
        let alerts = await makeService().alerts(at: point, eta: eta)
        #expect(alerts.isEmpty)
        #expect(StubURLProtocol.requests.count == 1)
    }

    @Test func offlineYieldsEmptyWithoutRetry() async {
        StubURLProtocol.respond([.error(URLError(.notConnectedToInternet)), .json(Self.body([("urn:a", nil, nil)]))])
        let sink = ResultRecorder()
        let alerts = await makeService(sink: sink.record).alerts(at: point, eta: eta)
        #expect(alerts.isEmpty)
        #expect(StubURLProtocol.requests.count == 1)
        #expect(sink.failures == 1)
    }

    @Test func timeoutIsRetried() async {
        StubURLProtocol.respond([.error(URLError(.timedOut)), .json(Self.body([("urn:a", nil, nil)]))])
        let sink = ResultRecorder()
        let alerts = await makeService(sink: sink.record).alerts(at: point, eta: eta)
        #expect(alerts.map(\.id) == ["urn:a"])
        #expect(sink.successes == [1])
    }

    // MARK: - Fixtures

    private static func body(_ alerts: [(id: String, onset: Date?, ends: Date?)]) -> Data {
        let iso = ISO8601DateFormatter()
        let features: [[String: Any]] = alerts.map { a in
            var props: [String: Any] = ["id": a.id, "event": "Heat Advisory", "severity": "Moderate", "headline": "h", "areaDesc": "Potter, TX"]
            if let onset = a.onset { props["onset"] = iso.string(from: onset) }
            if let ends = a.ends { props["ends"] = iso.string(from: ends) }
            return ["id": "https://api.weather.gov/alerts/\(a.id)", "type": "Feature", "properties": props]
        }
        let json: [String: Any] = ["type": "FeatureCollection", "features": features]
        return (try? JSONSerialization.data(withJSONObject: json)) ?? Data()
    }
}

/// Captures the service's status callbacks.
private final class ResultRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var results: [Result<Int, Error>] = []

    var record: @Sendable (Result<Int, Error>) -> Void {
        { [self] r in lock.withLock { results.append(r) } }
    }

    var failures: Int {
        lock.withLock { results.filter { if case .failure = $0 { true } else { false } }.count }
    }

    var successes: [Int] {
        lock.withLock { results.compactMap { try? $0.get() } }
    }
}

/// Serves queued canned responses in order and records every request.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    enum Reply {
        case status(Int)
        case json(Data)
        case error(URLError)
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var queue: [Reply] = []
    nonisolated(unsafe) private static var seen: [URLRequest] = []

    static func respond(_ replies: [Reply]) {
        lock.withLock {
            queue = replies
            seen = []
        }
    }

    static var requests: [URLRequest] { lock.withLock { seen } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let reply: Reply? = Self.lock.withLock {
            Self.seen.append(request)
            return Self.queue.isEmpty ? nil : Self.queue.removeFirst()
        }
        guard let url = request.url, let reply else {
            client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable))
            return
        }
        switch reply {
        case let .error(error):
            client?.urlProtocol(self, didFailWithError: error)
            return
        case let .status(code):
            send(url: url, code: code, body: Data())
        case let .json(body):
            send(url: url, code: 200, body: body)
        }
    }

    override func stopLoading() {}

    private func send(url: URL, code: Int, body: Data) {
        if let response = HTTPURLResponse(url: url, statusCode: code, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/geo+json"]) {
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        }
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
}
