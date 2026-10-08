import Foundation
import RoadTripCore

/// Limits concurrent requests to a public API (the web fired 25 at once).
actor AsyncLimiter {
    private let limit: Int
    private var running = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) { self.limit = max(1, limit) }

    func acquire() async {
        if running < limit {
            running += 1
            return
        }
        await withCheckedContinuation { waiters.append($0) }
        running += 1
    }

    func release() {
        running -= 1
        if !waiters.isEmpty {
            waiters.removeFirst().resume()
        }
    }

    func withPermit<T: Sendable>(_ body: @Sendable () async throws -> T) async rethrows -> T {
        await acquire()
        defer { release() }
        return try await body()
    }
}

/// `GET api.weather.gov/alerts/active?point=lat,lon` with the mandatory
/// User-Agent, 4 concurrent requests, retry on 429/5xx. Best-effort like the
/// web: any failure yields [] so the briefing never fails over alerts.
struct NWSAlertService: AlertService {
    static let base = URL(string: "https://api.weather.gov/alerts/active")

    let userAgent: String
    let session: URLSession
    let limiter = AsyncLimiter(limit: 4)
    let statusSink: (@Sendable (Result<Int, Error>) -> Void)?

    init(contactEmail: String?, appVersion: String, session: URLSession = .shared, statusSink: (@Sendable (Result<Int, Error>) -> Void)? = nil) {
        self.userAgent = ClientIdentity.nwsUserAgent(version: appVersion, contact: contactEmail)
        self.session = session
        self.statusSink = statusSink
    }

    func alerts(at coordinate: Coordinate, eta: Date) async -> [WeatherAlert] {
        guard let base = NWSAlertService.base,
              var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
        else { return [] }
        components.queryItems = [URLQueryItem(name: "point", value: String(format: "%.4f,%.4f", coordinate.latitude, coordinate.longitude))]
        guard let url = components.url else { return [] }
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/geo+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20
        let finalRequest = request

        do {
            let data = try await limiter.withPermit { try await fetchWithRetry(finalRequest) }
            let all = try NWSAlertsResponse.decode(data).alerts()
            let matched = AlertMatcher.inEffect(all, at: eta)
            statusSink?(.success(matched.count))
            return matched
        } catch {
            statusSink?(.failure(error))
            return []
        }
    }

    private func fetchWithRetry(_ request: URLRequest, attempts: Int = 3) async throws -> Data {
        var lastError: Error = ServiceError.unavailable("NWS")
        for attempt in 0..<attempts {
            do {
                let (data, response) = try await session.data(for: request)
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                if (200..<300).contains(code) { return data }
                lastError = ServiceError.http(code)
                guard code == 429 || code >= 500 else { throw lastError }
            } catch {
                lastError = error
            }
            if attempt < attempts - 1 {
                try await Task.sleep(for: .seconds(Double(1 << attempt) * 1.5))
            }
        }
        throw lastError
    }
}
