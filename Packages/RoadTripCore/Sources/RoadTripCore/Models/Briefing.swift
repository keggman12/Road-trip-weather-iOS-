import Foundation

/// Multi-day driving options (web `multiDayOpts`).
public struct MultiDayOptions: Hashable, Codable, Sendable {
    public static let minDriveHours: Double = 2
    public static let maxDriveHours: Double = 20
    public static let defaultDriveHours: Double = 10

    public var enabled: Bool
    /// Clamped to 2…20 like the web (`Math.max(2, Math.min(20, h || 10))`).
    public var maxDriveHours: Double
    public var resumeTime: TimeOfDay

    public init(enabled: Bool = false, maxDriveHours: Double = MultiDayOptions.defaultDriveHours, resumeTime: TimeOfDay = TimeOfDay(hour: 8, minute: 0)) {
        self.enabled = enabled
        self.maxDriveHours = MultiDayOptions.clampDriveHours(maxDriveHours)
        self.resumeTime = resumeTime
    }

    public static func clampDriveHours(_ h: Double) -> Double {
        guard h.isFinite, h > 0 else { return defaultDriveHours }
        return min(maxDriveHours, max(minDriveHours, h))
    }

    public var maxDriveSeconds: TimeInterval { maxDriveHours * 3600 }

    public static let off = MultiDayOptions()
}

/// A wall-clock time such as "08:00".
public struct TimeOfDay: Hashable, Codable, Sendable {
    public var hour: Int
    public var minute: Int

    public init(hour: Int, minute: Int) {
        self.hour = min(23, max(0, hour))
        self.minute = min(59, max(0, minute))
    }

    /// Parses "HH:mm"; non-numeric parts become 0 like the web's `parseInt || 0`.
    public init(hhmm: String) {
        let parts = hhmm.split(separator: ":", omittingEmptySubsequences: false)
        let h = parts.indices.contains(0) ? Int(parts[0]) ?? 0 : 0
        let m = parts.indices.contains(1) ? Int(parts[1]) ?? 0 : 0
        self.init(hour: h, minute: m)
    }

    public var hhmm: String {
        String(format: "%02d:%02d", hour, minute)
    }
}

/// Summary numbers for the briefing header (web `renderSummary`).
public struct BriefingSummary: Hashable, Sendable {
    public var distanceMi: Double
    public var driveSeconds: TimeInterval
    /// Dwell plus overnight gaps at intermediate stops (web `totalPauseSec`).
    public var pausedSeconds: TimeInterval
    public var stopCount: Int
    public var overnightCount: Int
    public var departure: Date
    public var arrival: Date
}

/// A generated weather briefing for one route.
public struct Briefing: Hashable, Codable, Sendable, Identifiable {
    public var id: UUID
    public var routeIndex: Int
    public var routeLabel: String?
    public var geometry: RouteGeometry
    /// Length of the sampled polyline, miles (what ETA math uses).
    public var totalMi: Double
    public var departure: Date
    public var departureTimeZoneID: String?
    public var rangeMi: Double
    public var multiDay: MultiDayOptions
    public var stops: [Stop]
    /// Rounded mile markers of removed sampled waypoints (for saved-trip replay).
    public var removedMi: [Int]
    public var generatedAt: Date
    public var weatherAttributionURL: String?

    public init(
        id: UUID = UUID(),
        routeIndex: Int,
        routeLabel: String? = nil,
        geometry: RouteGeometry,
        totalMi: Double,
        departure: Date,
        departureTimeZoneID: String? = nil,
        rangeMi: Double,
        multiDay: MultiDayOptions = .off,
        stops: [Stop],
        removedMi: [Int] = [],
        generatedAt: Date = Date(),
        weatherAttributionURL: String? = nil
    ) {
        self.id = id
        self.routeIndex = routeIndex
        self.routeLabel = routeLabel
        self.geometry = geometry
        self.totalMi = totalMi
        self.departure = departure
        self.departureTimeZoneID = departureTimeZoneID
        self.rangeMi = rangeMi
        self.multiDay = multiDay
        self.stops = stops
        self.removedMi = removedMi
        self.generatedAt = generatedAt
        self.weatherAttributionURL = weatherAttributionURL
    }

    /// Deduped alerts across all stops, most severe first.
    public var alerts: [WeatherAlert] { AlertDeduper.dedupe(stops: stops) }

    /// Stops whose ETA drifted more than 30 minutes from their forecast.
    public var staleStops: [Stop] { stops.filter(\.isForecastStale) }
    public var isStale: Bool { !staleStops.isEmpty }

    /// Web `totalPauseSec`: dwell + overnight gaps at intermediate stops.
    public var pausedSeconds: TimeInterval {
        guard stops.count > 2 else { return 0 }
        var sum: TimeInterval = 0
        for s in stops.dropFirst().dropLast() {
            let dwell = TimeInterval(s.dwellMinutes * 60)
            let overnight: TimeInterval
            if s.isOvernight, let resume = s.resume {
                overnight = resume.timeIntervalSince(s.eta.addingTimeInterval(dwell))
            } else {
                overnight = 0
            }
            sum += dwell + overnight
        }
        return sum
    }

    public var summary: BriefingSummary? {
        guard let first = stops.first, let last = stops.last else { return nil }
        return BriefingSummary(
            distanceMi: geometry.distanceMi,
            driveSeconds: geometry.durationSec,
            pausedSeconds: pausedSeconds,
            stopCount: stops.count,
            overnightCount: stops.filter(\.isOvernight).count,
            departure: first.eta,
            arrival: last.eta
        )
    }

    /// Web `nearestStopWeather`: the closest stop that has a forecast.
    public func nearestForecastStop(to point: Coordinate) -> Stop? {
        var best: Stop?
        var bestD = Double.infinity
        for s in stops where s.weather != nil {
            let d = Geo.haversineMiles(point, s.coordinate)
            if d < bestD {
                bestD = d
                best = s
            }
        }
        return best
    }

    /// Age of the briefing data at `now`.
    public func dataAge(at now: Date = Date()) -> TimeInterval {
        max(0, now.timeIntervalSince(generatedAt))
    }
}
