import Foundation

/// GPX 1.1 export of a briefing (web `gpx.buildGPX`): one waypoint per stop
/// with its ETA and a weather summary, plus the route as a single track.
public enum GPXBuilder {
    public static func build(name: String, coordinates: [Coordinate], stops: [Stop], now: Date = Date()) -> String {
        var lines: [String] = []
        lines.append(#"<?xml version="1.0" encoding="UTF-8"?>"#)
        lines.append(#"<gpx version="1.1" creator="Road Trip Weather Map" xmlns="http://www.topografix.com/GPX/1/1">"#)
        lines.append("  <metadata><name>\(escape(name))</name><time>\(isoTime(now))</time></metadata>")

        for (i, s) in stops.enumerated() {
            let tag = i == 0 ? "Origin" : i == stops.count - 1 ? "Destination" : "Stop \(i)"
            var desc: [String] = []
            if let w = s.weather {
                desc.append("\(w.temperatureF)°F \(w.category.label)")
                desc.append("wind \(w.windMph) mph")
                if let p = w.precipitationPercent { desc.append("precip \(p)%") }
            }
            if s.isOvernight { desc.append("OVERNIGHT STOP") }
            lines.append("  <wpt lat=\"\(fixed6(s.coordinate.latitude))\" lon=\"\(fixed6(s.coordinate.longitude))\">")
            lines.append("    <time>\(isoTime(s.eta))</time>")
            lines.append("    <name>\(escape("\(tag) — \(s.label)"))</name>")
            if !desc.isEmpty { lines.append("    <desc>\(escape(desc.joined(separator: " · ")))</desc>") }
            lines.append("  </wpt>")
        }

        lines.append("  <trk><name>\(escape(name))</name><trkseg>")
        for c in coordinates {
            lines.append("    <trkpt lat=\"\(fixed6(c.latitude))\" lon=\"\(fixed6(c.longitude))\"/>")
        }
        lines.append("  </trkseg></trk>")
        lines.append("</gpx>")
        return lines.joined(separator: "\n")
    }

    /// A file name for the export: the trip name with path-hostile
    /// characters replaced (web `downloadGPX` appends ".gpx").
    public static func fileName(for tripName: String) -> String {
        let bad = CharacterSet(charactersIn: "/\\:?%*|\"<>").union(.controlCharacters).union(.newlines)
        let cleaned = String(tripName.unicodeScalars.map { bad.contains($0) ? "-" : Character($0) })
            .trimmingCharacters(in: .whitespaces)
        return (cleaned.isEmpty ? "Road trip" : cleaned) + ".gpx"
    }

    /// Web `escapeHTML`.
    static func escape(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for ch in s {
            switch ch {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "'": out += "&#39;"
            default: out.append(ch)
            }
        }
        return out
    }

    /// JS `toFixed(6)`.
    static func fixed6(_ v: Double) -> String { String(format: "%.6f", v) }

    /// JS `Date.toISOString()`: UTC with milliseconds, e.g. 2026-06-10T13:00:00.000Z.
    static func isoTime(_ date: Date) -> String {
        let ms = Int64((date.timeIntervalSince1970 * 1000).rounded(.down))
        let seconds = Double(ms / 1000)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC") ?? cal.timeZone
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: Date(timeIntervalSince1970: seconds))
        return String(format: "%04d-%02d-%02dT%02d:%02d:%02d.%03dZ", c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0, c.second ?? 0, Int(ms % 1000))
    }
}
