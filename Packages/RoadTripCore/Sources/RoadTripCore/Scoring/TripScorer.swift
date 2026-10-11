import Foundation

/// Weather score for a set of stops — lower is better (web `scoreStops`).
public enum TripScorer {
    /// Web `condPenalty`.
    public static func conditionPenalty(_ c: ConditionCategory) -> Double {
        switch c {
        case .severe: 50
        case .thunderstorm: 30
        case .snow: 35
        case .rain: 12
        case .mostlyCloudy: 2
        case .partlyCloudy: 1
        case .clear: 0
        }
    }

    /// Web: a stop with no weather adds a flat 10.
    public static let unknownWeatherPenalty: Double = 10
    public static let alertPenalty: Double = 40
    public static let comfortTemperatureF: Double = 65

    public struct Result: Hashable, Sendable {
        /// Rounded total (web `Math.round(score)`).
        public var score: Int
        /// Index into the scored stops of the highest per-stop penalty, if any
        /// stop had weather.
        public var worstStopIndex: Int?
        public var worstPenalty: Double?
    }

    /// Per-stop penalty: `pop×40 + condition + |t−65|×0.3 + max(0, wind−10)×0.8
    /// + 40 if alerts`. Returns nil when the stop has no weather.
    public static func penalty(for stop: Stop) -> Double? {
        guard let w = stop.weather else { return nil }
        var p = 0.0
        p += (w.precipitationChance ?? 0) * 40
        p += conditionPenalty(w.category)
        p += abs(Double(w.temperatureF) - comfortTemperatureF) * 0.3
        p += max(0, Double(w.windMph) - 10) * 0.8
        if !stop.alerts.isEmpty { p += alertPenalty }
        return p
    }

    public static func score(_ stops: [Stop]) -> Result {
        var total = 0.0
        var worstIdx: Int?
        var worstP: Double?
        for (i, s) in stops.enumerated() {
            guard let p = penalty(for: s) else {
                total += unknownWeatherPenalty
                continue
            }
            total += p
            if worstP == nil || p > (worstP ?? -1) {
                worstP = p
                worstIdx = i
            }
        }
        // JS Math.round rounds .5 toward +∞; Swift's .toNearestOrAwayFromZero
        // agrees for positive values, which penalties always are.
        return Result(score: Int(total.rounded(.toNearestOrAwayFromZero)), worstStopIndex: worstIdx, worstPenalty: worstP)
    }

    /// Web "worst … near X" label: sampled waypoints are named by mile
    /// marker, everything else by the part of the label before the comma.
    public static func nearLabel(for stop: Stop) -> String {
        if stop.label.hasPrefix("Waypoint") || stop.label.isEmpty {
            return "mi \(Int(stop.distanceMi.rounded()))"
        }
        return stop.label.split(separator: ",", maxSplits: 1).first.map(String.init) ?? stop.label
    }
}

/// Candidate departure times for the best-time-to-leave optimizer
/// (web `runOptimizer`).
public enum DepartureCandidates {
    /// Web `OPT_MAX_CANDIDATES`.
    public static let maxCandidates = 6
    public static let minCandidates = 2
    /// Web: one candidate every ~2.5 h.
    public static let spacingHours = 2.5
    /// Web: with several routes cap the matrix at ~12 forecast sets.
    public static let maxMatrixCells = 12

    /// Number of candidates for a window and route count.
    public static func count(windowStart: Date, windowEnd: Date, routeCount: Int) -> Int {
        let spanH = windowEnd.timeIntervalSince(windowStart) / 3600
        var n = max(minCandidates, min(maxCandidates, Int((spanH / spacingHours).rounded()) + 1))
        if routeCount > 1 {
            n = max(minCandidates, min(n, maxMatrixCells / max(1, routeCount)))
        }
        return n
    }

    /// Evenly spaced departures from start to end inclusive, rounded to whole
    /// seconds like the web's epoch math. Empty when the window is invalid.
    public static func candidates(windowStart: Date, windowEnd: Date, routeCount: Int) -> [Date] {
        guard windowEnd > windowStart else { return [] }
        let n = count(windowStart: windowStart, windowEnd: windowEnd, routeCount: routeCount)
        let step = windowEnd.timeIntervalSince(windowStart) / Double(n - 1)
        let start = windowStart.timeIntervalSince1970
        return (0..<n).map { i in
            Date(timeIntervalSince1970: (start + Double(i) * step).rounded())
        }
    }
}
