import Foundation

/// How a stop came to exist.
public enum StopKind: String, Codable, Sendable {
    case origin
    case destination
    /// Auto-sampled fuel waypoint.
    case sampled
    /// Typed by the user and snapped to the route.
    case manual
    /// Added from a POI pin (keeps its `poiKind`).
    case poi

    public var isEndpoint: Bool { self == .origin || self == .destination }
    /// Web `isManual`: manual and POI stops.
    public var isUserAdded: Bool { self == .manual || self == .poi }
}

/// Default dwell at every intermediate waypoint (assumed fuel stop).
public let defaultDwellMinutes = 15

/// One stop in a briefing: position, timing, and what the weather and alert
/// services found for its ETA.
public struct Stop: Hashable, Codable, Sendable, Identifiable {
    public var id: UUID
    public var kind: StopKind
    public var label: String
    public var coordinate: Coordinate
    /// Index of the route polyline segment the stop lies on.
    public var routeIndex: Int
    /// Distance from the origin along the route, miles.
    public var distanceMi: Double
    /// Distance since the previous stop, miles (0 at origin).
    public var legMi: Double
    public var eta: Date
    public var dwellMinutes: Int
    public var manualOvernight: Bool
    public var autoOvernight: Bool
    /// When driving resumes after an overnight (nil otherwise).
    public var resume: Date?
    /// Direction of travel at this stop, degrees, toward the next stop.
    public var travelBearing: Double?
    public var timeZoneID: String?
    public var poiKind: POIKind?
    public var poiSourceID: String?
    /// For manual stops: how far off the route the typed place was.
    public var offRouteMi: Double?
    public var weather: WeatherSnapshot?
    /// The ETA the forecast was fetched for (web `weatherForEpoch`).
    public var forecastFor: Date?
    public var horizon: ForecastHorizon
    public var alerts: [WeatherAlert]

    public init(
        id: UUID = UUID(),
        kind: StopKind,
        label: String,
        coordinate: Coordinate,
        routeIndex: Int,
        distanceMi: Double,
        legMi: Double = 0,
        eta: Date = .distantPast,
        dwellMinutes: Int? = nil,
        manualOvernight: Bool = false,
        autoOvernight: Bool = false,
        resume: Date? = nil,
        travelBearing: Double? = nil,
        timeZoneID: String? = nil,
        poiKind: POIKind? = nil,
        poiSourceID: String? = nil,
        offRouteMi: Double? = nil,
        weather: WeatherSnapshot? = nil,
        forecastFor: Date? = nil,
        horizon: ForecastHorizon = .failed,
        alerts: [WeatherAlert] = []
    ) {
        self.id = id
        self.kind = kind
        self.label = label
        self.coordinate = coordinate
        self.routeIndex = routeIndex
        self.distanceMi = distanceMi
        self.legMi = legMi
        self.eta = eta
        self.dwellMinutes = dwellMinutes ?? (kind.isEndpoint ? 0 : defaultDwellMinutes)
        self.manualOvernight = manualOvernight
        self.autoOvernight = autoOvernight
        self.resume = resume
        self.travelBearing = travelBearing
        self.timeZoneID = timeZoneID
        self.poiKind = poiKind
        self.poiSourceID = poiSourceID
        self.offRouteMi = offRouteMi
        self.weather = weather
        self.forecastFor = forecastFor
        self.horizon = horizon
        self.alerts = alerts
    }

    public var isOvernight: Bool { manualOvernight || autoOvernight }

    /// Web `STALE_THRESHOLD_SEC`: ETA drift before a forecast is flagged.
    public static let staleThreshold: TimeInterval = 30 * 60

    /// Web: weather present and `|eta − weatherForEpoch| > 30 min`.
    public var isForecastStale: Bool {
        guard weather != nil, let forecastFor else { return false }
        return abs(eta.timeIntervalSince(forecastFor)) > Stop.staleThreshold
    }

    /// Stop's time zone, falling back to the given zone, then UTC.
    public func timeZone(fallback: TimeZone? = nil) -> TimeZone {
        if let timeZoneID, let tz = TimeZone(identifier: timeZoneID) { return tz }
        return fallback ?? TimeZone(identifier: "UTC") ?? .current
    }
}

extension Stop {
    /// Web `stopTag(stop, i, total)`.
    public func tag(index: Int, total: Int) -> String {
        if index == 0 { return "ORIGIN" }
        if index == total - 1 { return "DEST" }
        if kind.isUserAdded { return poiKind?.stopTag ?? "MANUAL" }
        return "STOP \(index)"
    }

    /// Web `legHTML` rule: an intermediate/destination leg longer than the
    /// vehicle range gets a ⚠.
    public func legExceedsRange(_ rangeMi: Double) -> Bool {
        rangeMi > 0 && legMi > rangeMi
    }
}
