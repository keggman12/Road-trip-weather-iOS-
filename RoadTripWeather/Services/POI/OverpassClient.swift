import Foundation
import RoadTripCore

/// Overpass POST client (web `overpassQuery` / `seed-pois.js overpass`).
/// Queries are serialized (public instances allow only a couple of slots per
/// IP), fall back across mirrors, pause 30 s after a 429/406, and treat an
/// HTTP 200 with a "remark" and no elements as a failure.
actor OverpassClient {
    let mirrors: [URL]
    let userAgent: String
    let session: URLSession
    let timeout: TimeInterval
    private var cooldownUntil: Date = .distantPast

    init(mirrors: [URL] = OverpassQueries.mirrors, appVersion: String, session: URLSession = .shared, timeout: TimeInterval = 25) {
        self.mirrors = mirrors
        self.userAgent = ClientIdentity.overpassUserAgent(version: appVersion)
        self.session = session
        self.timeout = timeout
    }

    /// Returns nil when every mirror failed (callers must not cache that).
    func query(_ ql: String) async -> OverpassResponse? {
        let wait = cooldownUntil.timeIntervalSinceNow
        if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }

        for url in mirrors {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = timeout
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            request.httpBody = Data(("data=" + (ql.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ql)).utf8)
            do {
                let (data, response) = try await session.data(for: request)
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                if code == 429 || code == 406 {
                    cooldownUntil = Date().addingTimeInterval(30)
                    continue
                }
                guard (200..<300).contains(code) else { continue }
                let parsed = try OverpassResponse.decode(data)
                if parsed.isServerSideFailure { continue }
                return parsed
            } catch {
                continue   // busy or timed out — next mirror
            }
        }
        return nil
    }
}
