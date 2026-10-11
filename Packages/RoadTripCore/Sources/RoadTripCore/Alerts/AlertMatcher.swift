import Foundation

/// Filters alerts to those in effect around a stop's ETA (web `getAlertsAt`).
public enum AlertMatcher {
    /// Web `ALERT_ETA_BUFFER_SEC`: ±2 h of slack around the ETA.
    public static let etaBuffer: TimeInterval = 2 * 3600

    /// Keep alerts with `onset ≤ eta + buffer` and `ends ≥ eta − buffer`
    /// (missing bounds count as open). A nil ETA keeps everything.
    public static func inEffect(_ alerts: [WeatherAlert], at eta: Date?, buffer: TimeInterval = etaBuffer) -> [WeatherAlert] {
        guard let eta else { return alerts }
        return alerts.filter { a in
            let startsBy = a.onset.map { $0 <= eta.addingTimeInterval(buffer) } ?? true
            let stillOn = a.ends.map { $0 >= eta.addingTimeInterval(-buffer) } ?? true
            return startsBy && stillOn
        }
    }
}

/// Collapses alerts across stops (web `dedupeAlerts`).
public enum AlertDeduper {
    /// First occurrence per id, ordered most severe first (stable within a rank).
    public static func dedupe(stops: [Stop]) -> [WeatherAlert] {
        dedupe(stops.flatMap(\.alerts))
    }

    public static func dedupe(_ alerts: [WeatherAlert]) -> [WeatherAlert] {
        var seen = Set<String>()
        var out: [WeatherAlert] = []
        for a in alerts where !seen.contains(a.id) {
            seen.insert(a.id)
            out.append(a)
        }
        // Stable sort by severity rank.
        return out.enumerated().sorted { l, r in
            if l.element.severity.rank != r.element.severity.rank {
                return l.element.severity.rank < r.element.severity.rank
            }
            return l.offset < r.offset
        }.map(\.element)
    }
}

// MARK: - NWS response decoding

/// Minimal Codable view of `GET api.weather.gov/alerts/active?point=…`
/// (GeoJSON `FeatureCollection`). Lives in Core so parsing is unit-tested
/// without a network stack.
public struct NWSAlertsResponse: Decodable, Sendable {
    public struct Feature: Decodable, Sendable {
        public var id: String?
        public var properties: Properties
    }

    public struct Properties: Decodable, Sendable {
        public var id: String?
        public var event: String?
        public var severity: String?
        public var headline: String?
        public var areaDesc: String?
        public var onset: String?
        public var effective: String?
        public var ends: String?
        public var expires: String?
    }

    public var features: [Feature]

    private enum CodingKeys: String, CodingKey { case features }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        features = try c.decodeIfPresent([Feature].self, forKey: .features) ?? []
    }

    /// Web mapping: `id = p.id || f.id`, `event || "Alert"`, `onset || effective`,
    /// `ends || expires`.
    public func alerts() -> [WeatherAlert] {
        features.compactMap { f in
            let p = f.properties
            guard let id = p.id ?? f.id else { return nil }
            return WeatherAlert(
                id: id,
                event: p.event ?? "Alert",
                severity: AlertSeverity(nwsString: p.severity),
                headline: p.headline ?? "",
                areaDescription: p.areaDesc ?? "",
                onset: NWSAlertsResponse.parseDate(p.onset ?? p.effective),
                ends: NWSAlertsResponse.parseDate(p.ends ?? p.expires)
            )
        }
    }

    /// NWS timestamps look like `2026-06-10T15:00:00-05:00`.
    public static func parseDate(_ s: String?) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        let f1 = ISO8601DateFormatter()
        f1.formatOptions = [.withInternetDateTime]
        if let d = f1.date(from: s) { return d }
        let f2 = ISO8601DateFormatter()
        f2.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f2.date(from: s)
    }

    public static func decode(_ data: Data) throws -> NWSAlertsResponse {
        try JSONDecoder().decode(NWSAlertsResponse.self, from: data)
    }
}
