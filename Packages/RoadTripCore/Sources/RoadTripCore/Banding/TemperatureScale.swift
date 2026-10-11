import Foundation

/// Temperature colour bands (web `DEFAULT_SCALE`, `colorForTemp`,
/// `applyScaleFromEditor`). Each band covers temperatures strictly below
/// `upperBound`; the last band is open-ended (`upperBound == nil`).
public struct TemperatureScale: Hashable, Codable, Sendable {
    public struct Band: Hashable, Codable, Sendable {
        public var label: String
        /// Exclusive upper bound in °F; nil = "and up".
        public var upperBound: Double?
        public var colorHex: String

        public init(label: String, upperBound: Double?, colorHex: String) {
            self.label = label
            self.upperBound = upperBound
            self.colorHex = colorHex
        }
    }

    /// Web `UNKNOWN_COLOR`.
    public static let unknownColorHex = "#6b7280"

    public var bands: [Band]

    public init(bands: [Band]) {
        self.bands = bands
    }

    /// Web defaults: Cold <48 blue, Cool <58 green, Mild <68 yellow,
    /// Warm <83 orange, Hot ≥83 red.
    public static let `default` = TemperatureScale(bands: [
        Band(label: "Cold", upperBound: 48, colorHex: "#3b82f6"),
        Band(label: "Cool", upperBound: 58, colorHex: "#22c55e"),
        Band(label: "Mild", upperBound: 68, colorHex: "#eab308"),
        Band(label: "Warm", upperBound: 83, colorHex: "#f97316"),
        Band(label: "Hot", upperBound: nil, colorHex: "#ef4444"),
    ])

    /// Colour for a temperature (web `colorForTemp`: first band with
    /// `t < max`, else the last band; nil/NaN → unknown colour).
    public func colorHex(forTemperatureF t: Double?) -> String {
        guard let t, t.isFinite, let last = bands.last else { return TemperatureScale.unknownColorHex }
        for b in bands {
            if let max = b.upperBound, t < max { return b.colorHex }
            if b.upperBound == nil { return b.colorHex }
        }
        return last.colorHex
    }

    public func band(forTemperatureF t: Double?) -> Band? {
        guard let t, t.isFinite else { return nil }
        for b in bands {
            if let max = b.upperBound, t < max { return b }
            if b.upperBound == nil { return b }
        }
        return bands.last
    }

    /// Segment colour between two stops (web `drawColoredRoute`): the mean
    /// of both temperatures, or whichever one exists.
    public static func segmentTemperature(_ a: Double?, _ b: Double?) -> Double? {
        switch (a, b) {
        case let (ta?, tb?): (ta + tb) / 2
        case let (ta?, nil): ta
        case let (nil, tb?): tb
        default: nil
        }
    }

    /// Web `applyScaleFromEditor` fix-up: every bounded `max` must exceed the
    /// previous one, else it becomes previous + 1. The last band is forced
    /// open-ended like the web's `Infinity`.
    public func normalized() -> TemperatureScale {
        guard !bands.isEmpty else { return .default }
        var out = bands
        let lastIndex = out.count - 1
        out[lastIndex].upperBound = nil
        for i in 1..<max(1, lastIndex) {
            guard let prev = out[i - 1].upperBound else { continue }
            if let cur = out[i].upperBound, cur > prev { continue }
            out[i].upperBound = prev + 1
        }
        return TemperatureScale(bands: out)
    }

    /// Web legend text per band: "< 48°", "48–58°", "83°+".
    public func legendLabels() -> [String] {
        var labels: [String] = []
        for (i, b) in bands.enumerated() {
            let lower = i == 0 ? nil : bands[i - 1].upperBound
            switch (lower, b.upperBound) {
            case (nil, let up?): labels.append("< \(Self.fmt(up))°")
            case (let lo?, nil): labels.append("\(Self.fmt(lo))°+")
            case (let lo?, let up?): labels.append("\(Self.fmt(lo))–\(Self.fmt(up))°")
            case (nil, nil): labels.append("all")
            }
        }
        return labels
    }

    static func fmt(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(v)
    }
}
