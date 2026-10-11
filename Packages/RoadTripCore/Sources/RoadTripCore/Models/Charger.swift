import Foundation

/// A Tesla Supercharger near a stop (web `getSuperchargersNear` item).
public struct Charger: Hashable, Codable, Sendable {
    public var name: String
    public var coordinate: Coordinate
    /// Distance from the stop, rounded to 0.1 mi by OCM's `Distance`.
    public var distanceMi: Double?
    public var town: String
    public var stalls: Int?
    public var powerKW: Double?

    public init(name: String, coordinate: Coordinate, distanceMi: Double?, town: String, stalls: Int?, powerKW: Double?) {
        self.name = name
        self.coordinate = coordinate
        self.distanceMi = distanceMi
        self.town = town
        self.stalls = stalls
        self.powerKW = powerKW
    }

    /// Web stop-card line: "Name · 3.3 mi off route · 12 stalls · 250 kW".
    public var summary: String {
        var parts = [name]
        if let d = distanceMi { parts.append("\(Self.trim(d)) mi off route") }
        if let s = stalls { parts.append("\(s) stalls") }
        if let kw = powerKW { parts.append("\(Int(kw.rounded())) kW") }
        return parts.joined(separator: " · ")
    }

    /// JS number formatting for 0.1-mi values: 18 → "18", 3.3 → "3.3".
    static func trim(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
    }
}

/// Open Charge Map query + parsing (web `getSuperchargersNear`).
public enum OpenChargeMap {
    public static let base = "https://api.openchargemap.io/v3/poi/"
    /// Tesla (Tesla-only + NACS sites).
    public static let teslaOperatorID = 23
    public static let maxResults = 2
    public static let radiusMi = 30

    /// The web's request URL without `&key=` — the app sends the key in the
    /// `X-API-Key` header so it never lands in URL logs.
    public static func url(near c: Coordinate) -> URL? {
        URL(string: base + "?output=json&latitude=\(String(format: "%.4f", c.latitude))&longitude=\(String(format: "%.4f", c.longitude))"
            + "&distance=\(radiusMi)&distanceunit=Miles&maxresults=\(maxResults)"
            + "&operatorid=\(teslaOperatorID)&compact=true&verbose=false")
    }

    public static let apiKeyHeader = "X-API-Key"

    struct POI: Decodable {
        struct Address: Decodable {
            var Title: String?
            var Latitude: Double?
            var Longitude: Double?
            var Distance: Double?
            var Town: String?
            var StateOrProvince: String?
        }
        struct Connection: Decodable { var PowerKW: Double? }
        var AddressInfo: Address?
        var NumberOfPoints: Int?
        var Connections: [Connection]?
    }

    /// Parses a compact OCM response. Anything that isn't an array → [].
    public static func parse(_ data: Data) -> [Charger] {
        guard let pois = try? JSONDecoder().decode([POI].self, from: data) else { return [] }
        return pois.compactMap { p in
            let a = p.AddressInfo
            guard let lat = a?.Latitude, let lon = a?.Longitude else { return nil }
            let kw = (p.Connections ?? []).map { $0.PowerKW ?? 0 }.reduce(0, max)
            let title = a?.Title ?? ""
            return Charger(
                name: title.isEmpty ? "Supercharger" : title,
                coordinate: Coordinate(lat: lat, lon: lon),
                distanceMi: a?.Distance.map { ($0 * 10).rounded() / 10 },
                town: [a?.Town, a?.StateOrProvince].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", "),
                stalls: p.NumberOfPoints.flatMap { $0 == 0 ? nil : $0 },
                powerKW: kw > 0 ? kw : nil
            )
        }
    }
}
