import Foundation

/// Compares route alternatives so the list shows genuinely different roads
/// (owner request: "via Raton" and "Direct" were the same road, while the
/// eastern route through Kansas was never offered).
public enum RouteComparison {
    /// Routes shown at most.
    public static let maxRoutes = 4
    /// Two routes whose points are this close count as the same road.
    public static let sameRoadToleranceMi = 3.0
    /// Mutual overlap at or above this makes a route a near-duplicate.
    public static let duplicateOverlap = 0.9
    /// A distinctive point must be at least this far from every other route.
    public static let distinctiveMinMi = 15.0

    static let samplePoints = 120
    static let referencePoints = 400

    /// Fraction of `a`'s length (sampled) that lies within `toleranceMi` of `b`.
    public static func overlap(_ a: [Coordinate], with b: [Coordinate], toleranceMi: Double = sameRoadToleranceMi) -> Double {
        let pts = Geo.thinPolyline(a, maxPoints: samplePoints)
        let ref = Geo.thinPolyline(b, maxPoints: referencePoints)
        guard !pts.isEmpty, ref.count >= 2 else { return 0 }
        let near = pts.filter { Geo.minDistanceMiles(from: $0, to: ref) <= toleranceMi }.count
        return Double(near) / Double(pts.count)
    }

    /// Keeps routes in order, dropping any that mutually overlap a kept one,
    /// then caps the list. The first route (the user's via route, or the
    /// fastest) always survives.
    public static func dedupe(_ routes: [RouteGeometry], maxRoutes: Int = maxRoutes) -> [RouteGeometry] {
        var kept: [RouteGeometry] = []
        for r in routes where kept.count < maxRoutes {
            let duplicate = kept.contains { k in
                overlap(r.coordinates, with: k.coordinates) >= duplicateOverlap
                    && overlap(k.coordinates, with: r.coordinates) >= duplicateOverlap
            }
            if !duplicate { kept.append(r) }
        }
        return kept
    }

    /// The point of `route` farthest from all `others` — where it differs
    /// most — or nil when it never strays `distinctiveMinMi` from them.
    public static func distinctivePoint(of route: [Coordinate], others: [[Coordinate]]) -> Coordinate? {
        guard !others.isEmpty else { return nil }
        let refs = others.map { Geo.thinPolyline($0, maxPoints: referencePoints) }
        var best: (Coordinate, Double)?
        for p in Geo.thinPolyline(route, maxPoints: samplePoints) {
            let d = refs.map { Geo.minDistanceMiles(from: p, to: $0) }.min() ?? 0
            if d > (best?.1 ?? -1) { best = (p, d) }
        }
        guard let (p, d) = best, d >= distinctiveMinMi else { return nil }
        return p
    }

    /// "via Raton" stays; "Direct" → "Direct · via Lamar, CO"; nil → "via Lamar, CO".
    public static func label(existing: String?, distinctivePlace: String?) -> String? {
        guard let place = distinctivePlace, !place.isEmpty else { return existing }
        guard let existing else { return "via \(place)" }
        if existing.hasPrefix("via ") { return existing }
        return "\(existing) · via \(place)"
    }
}
