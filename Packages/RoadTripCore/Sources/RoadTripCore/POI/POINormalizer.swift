import Foundation

/// Normalises OSM elements into POIs with the web app's dedupe rules
/// (`seed-pois.js normalize`, `api.js getPoisAlong`).
public enum POINormalizer {
    /// Dedupe key: coordinates rounded to `decimals` places, joined with a
    /// comma — exactly `lat.toFixed(p) + "," + lon.toFixed(p)`.
    public static func dedupeKey(_ c: Coordinate, decimals: Int) -> String {
        let f = "%.\(decimals)f"
        return String(format: f, c.lat) + "," + String(format: f, c.lon)
    }

    /// - Brand kinds collapse within ~1 km cells (2 decimals): a fuel node, a
    ///   building way and a shop are one site.
    /// - Rest areas dedupe at 3 decimals so paired NB/SB facilities survive.
    /// - Any element carrying a `brand` tag is excluded from `rest`; branded
    ///   service plazas belong to the brand layers.
    public static func normalize(_ elements: [OverpassResponse.Element], kind: POIKind) -> [POI] {
        var seen = Set<String>()
        var out: [POI] = []
        for el in elements {
            guard let coordinate = el.coordinate else { continue }
            let tags = el.tags ?? [:]
            if kind == .rest, let brand = tags["brand"], !brand.isEmpty { continue }
            let detail: String? = kind == .rest
                ? (tags["highway"] == "services" ? "Service plaza" : "Rest area")
                : nil
            let key = dedupeKey(coordinate, decimals: kind.dedupeDecimals)
            if seen.contains(key) { continue }
            seen.insert(key)
            let name = tags["name"] ?? tags["brand"] ?? (detail ?? kind.fallbackName)
            out.append(POI(kind: kind, sourceID: el.osmID, name: name, detail: detail, coordinate: coordinate))
        }
        return out
    }

    /// Dedupe an arbitrary POI list with the kind's precision (used after a
    /// manual import). Keeps the first occurrence.
    public static func dedupe(_ pois: [POI]) -> [POI] {
        var seen = Set<String>()
        var out: [POI] = []
        for p in pois {
            let key = "\(p.kind.rawValue)|" + dedupeKey(p.coordinate, decimals: p.kind.dedupeDecimals)
            if seen.contains(key) { continue }
            seen.insert(key)
            out.append(p)
        }
        return out
    }
}

/// Keeps the POIs that lie within a corridor around the route
/// (web `getPoisFromDb` bbox + `minDistToPolylineMi` filter).
public enum CorridorFilter {
    /// Web thins the route to 120 points before any corridor work.
    public static let thinnedPointCount = 120

    public static func thin(_ route: [Coordinate]) -> [Coordinate] {
        Geo.thinPolyline(route, maxPoints: thinnedPointCount)
    }

    /// POIs within `radiusMeters` of the thinned polyline. A bounding-box
    /// prefilter keeps the per-POI polyline distance cheap on a nationwide set.
    public static func filter(_ pois: [POI], alongThinned thinned: [Coordinate], radiusMeters: Double) -> [POI] {
        guard let bbox = Geo.boundingBox(of: thinned, paddedByMeters: radiusMeters) else { return [] }
        let radiusMi = radiusMeters / Geo.metersPerMile
        return pois.filter { p in
            bbox.contains(p.coordinate) && Geo.minDistanceMiles(from: p.coordinate, to: thinned) <= radiusMi
        }
    }

    /// Convenience using the kind's default radius.
    public static func filter(_ pois: [POI], kind: POIKind, alongRoute route: [Coordinate]) -> [POI] {
        filter(pois.filter { $0.kind == kind }, alongThinned: thin(route), radiusMeters: kind.corridorRadiusMeters)
    }
}
