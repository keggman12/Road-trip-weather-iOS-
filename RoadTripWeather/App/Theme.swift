import RoadTripCore
import SwiftUI

/// Aviation-briefing look: dark surfaces, monospaced digits, high-contrast
/// condition badges. Colours mirror the web CSS variables.
enum Theme {
    static let background = Color(red: 0x0b / 255, green: 0x0f / 255, blue: 0x14 / 255)
    static let surface = Color(red: 0x11 / 255, green: 0x17 / 255, blue: 0x22 / 255)
    static let border = Color(red: 0x1e / 255, green: 0x29 / 255, blue: 0x3b / 255)
    static let text = Color(red: 0xe2 / 255, green: 0xe8 / 255, blue: 0xf0 / 255)
    static let muted = Color(red: 0x94 / 255, green: 0xa3 / 255, blue: 0xb8 / 255)
    static let accent = Color(red: 0x7d / 255, green: 0xd3 / 255, blue: 0xfc / 255)
    static let warn = Color(red: 0xfb / 255, green: 0xbf / 255, blue: 0x24 / 255)
    static let danger = Color(red: 0xf8 / 255, green: 0x71 / 255, blue: 0x71 / 255)
    static let ok = Color(red: 0x34 / 255, green: 0xd3 / 255, blue: 0x99 / 255)

    /// Web `ROUTE_PALETTE`.
    static let routePalette: [Color] = [
        Color(hex: "#38bdf8"), Color(hex: "#c084fc"), Color(hex: "#34d399"), Color(hex: "#fbbf24"),
    ]

    static func routeColor(_ index: Int) -> Color {
        routePalette[((index % routePalette.count) + routePalette.count) % routePalette.count]
    }

    static func poiColor(_ kind: POIKind) -> Color {
        switch kind {
        case .bucees: Color(hex: "#fbbf24")
        case .loves: Color(hex: "#f87171")
        case .rest: Color(hex: "#38bdf8")
        }
    }
}

extension Color {
    /// `#rrggbb` → Color. Falls back to grey for malformed input.
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else {
            // Malformed input → the web's "no data" grey.
            self.init(red: 0x6b / 255, green: 0x72 / 255, blue: 0x80 / 255)
            return
        }
        self.init(
            red: Double((v >> 16) & 0xff) / 255,
            green: Double((v >> 8) & 0xff) / 255,
            blue: Double(v & 0xff) / 255
        )
    }
}

enum Fmt {
    /// Web `fmtDurTxt`: "11h 30m" / "45m".
    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let h = total / 3600
        let m = Int((Double(total % 3600) / 60).rounded())
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    /// Web `fmtClockTZ`: "Wed, Jun 10, 3:05 PM" in the given zone.
    static func clock(_ date: Date, timeZone: TimeZone) -> String {
        let f = DateFormatter()
        f.timeZone = timeZone
        f.setLocalizedDateFormatFromTemplate("EEE MMM d h:mm a")
        return f.string(from: date)
    }

    /// Web `fmtTimeTZ`: "3:05 PM".
    static func time(_ date: Date, timeZone: TimeZone) -> String {
        let f = DateFormatter()
        f.timeZone = timeZone
        f.timeStyle = .short
        f.dateStyle = .none
        return f.string(from: date)
    }

    /// Web `tzAbbr`: "MDT".
    static func zoneAbbreviation(_ date: Date, timeZone: TimeZone) -> String {
        timeZone.abbreviation(for: date) ?? ""
    }

    static func miles(_ mi: Double) -> String { "\(Int(mi.rounded())) mi" }

    /// "just now" under a minute, else "3 hours ago". Never in the future:
    /// a timestamp a few ms ahead of `now` used to read "in 0 seconds".
    static func age(_ date: Date, now: Date = Date()) -> String {
        guard now.timeIntervalSince(date) >= 60 else { return "just now" }
        return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: now)
    }
}

extension Stop {
    func etaText(fallback: TimeZone) -> String {
        Fmt.clock(eta, timeZone: timeZone(fallback: fallback))
    }

    func zoneText(fallback: TimeZone) -> String {
        Fmt.zoneAbbreviation(eta, timeZone: timeZone(fallback: fallback))
    }
}

/// Condition glyphs (web `conditionSVG` → SF Symbols).
extension ConditionCategory {
    var symbolName: String {
        switch self {
        case .clear: "sun.max"
        case .partlyCloudy: "cloud.sun"
        case .mostlyCloudy: "cloud"
        case .rain: "cloud.rain"
        case .thunderstorm: "cloud.bolt.rain"
        case .severe: "exclamationmark.triangle"
        case .snow: "cloud.snow"
        }
    }

    var badgeColor: Color { Color(hex: badgeColorHex) }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
