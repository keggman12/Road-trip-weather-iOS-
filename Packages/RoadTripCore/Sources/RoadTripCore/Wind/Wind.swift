import Foundation

/// Wind relative to the direction of travel (web `util.js` wind section).
public enum RelativeWind: String, Codable, Sendable {
    case head
    case tail
    case cross

    /// Web chip text: "headwind", "tailwind", "x-wind".
    public var chipLabel: String {
        switch self {
        case .head: "headwind"
        case .tail: "tailwind"
        case .cross: "x-wind"
        }
    }
}

public enum Wind {
    static let compassPoints = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
                                "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]

    /// 16-point compass label for a direction in degrees (web `windCompass`).
    public static func compass(degrees: Double?) -> String {
        guard let degrees, degrees.isFinite else { return "" }
        let idx = Int((degrees / 22.5).rounded()) % 16
        return compassPoints[idx < 0 ? idx + 16 : idx]
    }

    /// `windFrom` is where the wind comes from; `travelBearing` is the way we
    /// drive. Diff between travel and the direction the wind blows TOWARD:
    /// ≤ 45° tail, ≥ 135° head, else cross (web `relativeWind`).
    public static func relative(windFrom: Double?, travelBearing: Double?) -> RelativeWind? {
        guard let windFrom, let travelBearing, windFrom.isFinite, travelBearing.isFinite else { return nil }
        let toward = (windFrom + 180).truncatingRemainder(dividingBy: 360)
        var diff = abs(toward - travelBearing).truncatingRemainder(dividingBy: 360)
        if diff > 180 { diff = 360 - diff }
        if diff <= 45 { return .tail }
        if diff >= 135 { return .head }
        return .cross
    }

    /// Rotation for a "↓" glyph so it points the way the wind blows
    /// (web `windArrowRotation`: `Math.round(windDeg % 360)`).
    public static func arrowRotation(windFrom: Double?) -> Int {
        guard let windFrom, windFrom.isFinite else { return 0 }
        var r = windFrom.truncatingRemainder(dividingBy: 360)
        if r < 0 { r += 360 }
        return Int(r.rounded())
    }
}
