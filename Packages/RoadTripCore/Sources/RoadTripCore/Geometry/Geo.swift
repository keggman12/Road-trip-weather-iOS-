import Foundation

/// Geometry helpers ported from the web app's `util.js` and `app.js`.
/// All distances are statute miles unless a name says otherwise.
public enum Geo {
    /// Earth radius used by the web app (`3958.7613` mi).
    public static let earthRadiusMiles = 3958.7613
    public static let metersPerMile = 1609.344

    @inline(__always) static func rad(_ d: Double) -> Double { d * .pi / 180 }
    @inline(__always) static func deg(_ r: Double) -> Double { r * 180 / .pi }

    /// Great-circle distance (web `haversineMi`).
    public static func haversineMiles(_ a: Coordinate, _ b: Coordinate) -> Double {
        let dLat = rad(b.lat - a.lat)
        let dLon = rad(b.lon - a.lon)
        let la1 = rad(a.lat), la2 = rad(b.lat)
        let h = pow(sin(dLat / 2), 2) + cos(la1) * cos(la2) * pow(sin(dLon / 2), 2)
        return 2 * earthRadiusMiles * asin(min(1, sqrt(h)))
    }

    /// Initial bearing from `a` to `b`, degrees in [0, 360) (web `bearingDeg`).
    public static func bearingDegrees(from a: Coordinate, to b: Coordinate) -> Double {
        let la1 = rad(a.lat), la2 = rad(b.lat), dLon = rad(b.lon - a.lon)
        let y = sin(dLon) * cos(la2)
        let x = cos(la1) * sin(la2) - sin(la1) * cos(la2) * cos(dLon)
        let brg = (deg(atan2(y, x)) + 360).truncatingRemainder(dividingBy: 360)
        return brg < 0 ? brg + 360 : brg
    }

    /// Cumulative distance along a polyline; `result[i]` is miles from the
    /// first point to point `i`.
    public static func cumulativeMiles(_ coords: [Coordinate]) -> [Double] {
        guard !coords.isEmpty else { return [] }
        var cum = [0.0]
        cum.reserveCapacity(coords.count)
        for i in 1..<coords.count {
            cum.append(cum[i - 1] + haversineMiles(coords[i - 1], coords[i]))
        }
        return cum
    }

    /// Thin a polyline to at most `maxPoints` evenly spaced points, keeping
    /// both endpoints (web `thinPolyline`).
    public static func thinPolyline(_ coords: [Coordinate], maxPoints: Int) -> [Coordinate] {
        guard maxPoints >= 2, coords.count > maxPoints else { return coords }
        let step = Double(coords.count - 1) / Double(maxPoints - 1)
        var out: [Coordinate] = []
        out.reserveCapacity(maxPoints)
        for i in 0..<maxPoints {
            let idx = Int((Double(i) * step).rounded())
            out.append(coords[min(idx, coords.count - 1)])
        }
        return out
    }

    /// Result of projecting a point onto a polyline.
    public struct Projection: Hashable, Sendable {
        /// Snapped point on the polyline.
        public var coordinate: Coordinate
        /// Index of the segment (between `coords[i]` and `coords[i+1]`).
        public var routeIndex: Int
        /// Distance along the polyline from its start, miles.
        public var distanceMi: Double
        /// Distance from the original point to the snapped point, miles.
        public var offRouteMi: Double
    }

    /// Equirectangular projection of one segment, shared by `projectOntoRoute`
    /// and `minDistanceMiles`. Returns the snapped point and `t` in [0, 1].
    @inline(__always)
    static func snap(_ p: Coordinate, onto a: Coordinate, _ b: Coordinate) -> (Coordinate, Double) {
        let cosLat = cos(rad((a.lat + b.lat) * 0.5))
        let ax = a.lon * cosLat, ay = a.lat
        let bx = b.lon * cosLat, by = b.lat
        let px = p.lon * cosLat, py = p.lat
        let dx = bx - ax, dy = by - ay
        let len2 = dx * dx + dy * dy
        var t = len2 > 0 ? ((px - ax) * dx + (py - ay) * dy) / len2 : 0
        t = max(0, min(1, t))
        let snapped = Coordinate(lat: ay + t * dy, lon: cosLat != 0 ? (ax + t * dx) / cosLat : a.lon)
        return (snapped, t)
    }

    /// Minimum distance from a point to a polyline (web `minDistToPolylineMi`).
    public static func minDistanceMiles(from point: Coordinate, to coords: [Coordinate]) -> Double {
        guard let first = coords.first else { return .infinity }
        if coords.count == 1 { return haversineMiles(point, first) }
        var best = Double.infinity
        for i in 0..<(coords.count - 1) {
            let (snapped, _) = snap(point, onto: coords[i], coords[i + 1])
            let d = haversineMiles(snapped, point)
            if d < best { best = d }
        }
        return best
    }

    /// Project a point onto the route (web `projectOntoRoute`). Returns nil
    /// for a polyline with fewer than two points.
    public static func projectOntoRoute(_ coords: [Coordinate], target: Coordinate) -> Projection? {
        guard coords.count >= 2 else { return nil }
        var best: Projection?
        var cum = 0.0
        for i in 0..<(coords.count - 1) {
            let a = coords[i], b = coords[i + 1]
            let segLen = haversineMiles(a, b)
            let (snapped, t) = snap(target, onto: a, b)
            let off = haversineMiles(snapped, target)
            if best == nil || off < (best?.offRouteMi ?? .infinity) {
                best = Projection(coordinate: snapped, routeIndex: i, distanceMi: cum + segLen * t, offRouteMi: off)
            }
            cum += segLen
        }
        return best
    }

    /// Axis-aligned bounding box.
    public struct BoundingBox: Hashable, Sendable {
        public var minLat: Double, maxLat: Double, minLon: Double, maxLon: Double

        public init(minLat: Double, maxLat: Double, minLon: Double, maxLon: Double) {
            self.minLat = minLat; self.maxLat = maxLat; self.minLon = minLon; self.maxLon = maxLon
        }

        public func contains(_ c: Coordinate) -> Bool {
            c.lat >= minLat && c.lat <= maxLat && c.lon >= minLon && c.lon <= maxLon
        }
    }

    /// Bounding box of a polyline padded by `radiusMeters` (web `getPoisFromDb`:
    /// `latPad = r/111320`, `lonPad = r/(111320·cos(midLat))`).
    public static func boundingBox(of coords: [Coordinate], paddedByMeters radiusMeters: Double) -> BoundingBox? {
        guard !coords.isEmpty else { return nil }
        var minLat = 90.0, maxLat = -90.0, minLon = 180.0, maxLon = -180.0
        for c in coords {
            minLat = min(minLat, c.lat); maxLat = max(maxLat, c.lat)
            minLon = min(minLon, c.lon); maxLon = max(maxLon, c.lon)
        }
        let latPad = radiusMeters / 111_320
        let cosMid = cos(rad((minLat + maxLat) / 2))
        let lonPad = cosMid != 0 ? radiusMeters / (111_320 * cosMid) : 180
        return BoundingBox(minLat: minLat - latPad, maxLat: maxLat + latPad, minLon: minLon - lonPad, maxLon: maxLon + lonPad)
    }
}
