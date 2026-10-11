import Foundation

/// NWS alert severity. Rank order is the web's `dedupeAlerts` sort order.
public enum AlertSeverity: String, Codable, Sendable, CaseIterable, Comparable {
    case extreme = "Extreme"
    case severe = "Severe"
    case moderate = "Moderate"
    case minor = "Minor"
    case unknown = "Unknown"

    public var rank: Int {
        switch self {
        case .extreme: 0
        case .severe: 1
        case .moderate: 2
        case .minor: 3
        case .unknown: 4
        }
    }

    public static func < (lhs: AlertSeverity, rhs: AlertSeverity) -> Bool {
        lhs.rank < rhs.rank
    }

    /// Lenient parse: anything unrecognised is `.unknown`, like the web.
    public init(nwsString: String?) {
        self = AlertSeverity(rawValue: nwsString ?? "") ?? .unknown
    }
}

/// One active NWS alert, normalised like the web's `getAlertsAt` mapping.
public struct WeatherAlert: Hashable, Codable, Sendable, Identifiable {
    public var id: String
    public var event: String
    public var severity: AlertSeverity
    public var headline: String
    public var areaDescription: String
    /// `onset`, falling back to `effective`.
    public var onset: Date?
    /// `ends`, falling back to `expires`.
    public var ends: Date?

    public init(
        id: String,
        event: String,
        severity: AlertSeverity = .unknown,
        headline: String = "",
        areaDescription: String = "",
        onset: Date? = nil,
        ends: Date? = nil
    ) {
        self.id = id
        self.event = event
        self.severity = severity
        self.headline = headline
        self.areaDescription = areaDescription
        self.onset = onset
        self.ends = ends
    }
}
