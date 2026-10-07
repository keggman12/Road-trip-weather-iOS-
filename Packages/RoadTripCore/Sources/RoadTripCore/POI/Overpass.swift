import Foundation

/// Minimal Codable view of an Overpass `[out:json]` response.
public struct OverpassResponse: Decodable, Sendable {
    public struct Center: Decodable, Sendable {
        public var lat: Double
        public var lon: Double
    }

    public struct Element: Decodable, Sendable {
        public var type: String
        public var id: Int64
        public var lat: Double?
        public var lon: Double?
        public var center: Center?
        public var tags: [String: String]?

        public init(type: String, id: Int64, lat: Double? = nil, lon: Double? = nil, center: Center? = nil, tags: [String: String]? = nil) {
            self.type = type
            self.id = id
            self.lat = lat
            self.lon = lon
            self.center = center
            self.tags = tags
        }

        /// Node position or way/relation centre.
        public var coordinate: Coordinate? {
            if let lat, let lon { return Coordinate(lat: lat, lon: lon) }
            if let c = center { return Coordinate(lat: c.lat, lon: c.lon) }
            return nil
        }

        /// `node/123`, `way/456` — the web's POI id for OSM-sourced rows.
        public var osmID: String { "\(type)/\(id)" }
    }

    public var elements: [Element]
    public var remark: String?

    private enum CodingKeys: String, CodingKey { case elements, remark }

    public init(elements: [Element], remark: String? = nil) {
        self.elements = elements
        self.remark = remark
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        elements = try c.decodeIfPresent([Element].self, forKey: .elements) ?? []
        remark = try c.decodeIfPresent(String.self, forKey: .remark)
    }

    /// Overpass reports its own timeouts as HTTP 200 + a `remark` containing
    /// "error" and no elements. That is a failure, not an empty corridor
    /// (both web paths check this).
    public var isServerSideFailure: Bool {
        guard let remark, elements.isEmpty else { return false }
        return remark.range(of: "error", options: .caseInsensitive) != nil
    }

    public static func decode(_ data: Data) throws -> OverpassResponse {
        try JSONDecoder().decode(OverpassResponse.self, from: data)
    }
}

/// Overpass QL builders. Brand queries use exact tag matches (`brand:wikidata`,
/// `brand`, `name`) as in `seed-pois.js` — never regexes — so they hit
/// Overpass indexes on both nationwide and corridor scopes.
public enum OverpassQueries {
    /// Default mirrors (web `OVERPASS_URLS` / `MIRRORS`).
    public static let mirrors: [URL] = [
        "https://overpass-api.de/api/interpreter",
        "https://overpass.kumi.systems/api/interpreter",
        "https://overpass.private.coffee/api/interpreter",
    ].compactMap(URL.init(string:))

    static let usArea = #"area["ISO3166-1"="US"][admin_level=2]->.us;"#

    /// Exact-tag brand clauses for a scope such as `(area.us)` or
    /// `(around:8000,lat,lon,…)`.
    static func brandClauses(_ kind: POIKind, scope: String) -> String? {
        switch kind {
        case .bucees:
            return """
            (
              nwr["brand:wikidata"="Q4982335"]\(scope);
              nwr["brand"="Buc-ee's"]\(scope);
              nwr["name"="Buc-ee's"]\(scope);
            );
            """
        case .loves:
            return """
            (
              nwr["brand:wikidata"="Q1872496"]\(scope);
              nwr["brand"="Love's"]\(scope);
              nwr["name"="Love's Travel Stop"]\(scope);
            );
            """
        case .rest:
            return nil
        }
    }

    /// Nationwide harvest queries (web `seed-pois.js` `QUERIES`). Rest areas
    /// are deliberately heavy (300 s, 1 GB, 50 000 results) and must only run
    /// from `tools/poi-snapshot` on a Mac — never on the phone.
    public static func nationwide(_ kind: POIKind) -> String {
        switch kind {
        case .bucees:
            return "[out:json][timeout:120];\n\(usArea)\n\(brandClauses(.bucees, scope: "(area.us)") ?? "")out center 2000;"
        case .loves:
            return "[out:json][timeout:120];\n\(usArea)\n\(brandClauses(.loves, scope: "(area.us)") ?? "")out center 5000;"
        case .rest:
            return """
            [out:json][timeout:300][maxsize:1073741824];
            \(usArea)
            (
              nwr["highway"="rest_area"](area.us);
              nwr["highway"="services"](area.us);
            );
            out center 50000;
            """
        }
    }

    /// Route-corridor query (web `getPoisAlong`): `around:<radius>,<lat,lon,…>`
    /// over a thinned polyline, 30 s server timeout, 120 results. Coordinates
    /// are written with 4 decimals like the web.
    public static func corridor(_ kind: POIKind, along thinned: [Coordinate], radiusMeters: Double? = nil) -> String {
        let radius = Int((radiusMeters ?? kind.corridorRadiusMeters).rounded())
        let line = thinned.map { String(format: "%.4f,%.4f", $0.lat, $0.lon) }.joined(separator: ",")
        let scope = "(around:\(radius),\(line))"
        let body: String
        switch kind {
        case .bucees, .loves:
            body = brandClauses(kind, scope: scope) ?? ""
        case .rest:
            body = """
            nwr["highway"="rest_area"]\(scope)->.ra;
            nwr["highway"="services"]\(scope)->.sv;
            (
              nwr.ra;
              nwr.sv[!"brand"];
            );
            """
        }
        return "[out:json][timeout:30];\n\(body)\nout center 120;"
    }
}
