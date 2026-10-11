import Foundation

/// Samples fuel waypoints along a route at the vehicle's range
/// (web `util.sampleWaypoints`).
public enum WaypointSampler {
    /// Web `MAX_WAYPOINTS`.
    public static let maxWaypoints = 25
    /// Web: `interval = Math.max(5, rangeMi)`.
    public static let minIntervalMi: Double = 5
    /// Web: the last interior target must be `< total − 0.35·interval`.
    public static let tailFraction = 0.35

    public struct Sample: Hashable, Sendable {
        public var coordinate: Coordinate
        public var routeIndex: Int
        public var distanceMi: Double
    }

    public struct Result: Hashable, Sendable {
        public var waypoints: [Sample]
        public var totalMi: Double
    }

    /// Returns start, interior points every `rangeMi` (collapsed to fit 25
    /// points), and the end.
    public static func sample(_ coords: [Coordinate], rangeMi: Double) -> Result {
        guard !coords.isEmpty else { return Result(waypoints: [], totalMi: 0) }
        let cum = Geo.cumulativeMiles(coords)
        let total = cum[cum.count - 1]
        var interval = max(minIntervalMi, rangeMi)
        if Int(floor(total / interval)) + 2 > maxWaypoints {
            interval = total / Double(maxWaypoints - 1)
        }

        var targets: [Double] = [0]
        var d = interval
        while d < total - interval * tailFraction {
            targets.append(d)
            d += interval
        }
        targets.append(total)

        var out: [Sample] = []
        out.reserveCapacity(targets.count)
        var j = 0
        for target in targets {
            while j < cum.count - 1, cum[j + 1] < target { j += 1 }
            if j >= coords.count - 1 {
                out.append(Sample(coordinate: coords[coords.count - 1], routeIndex: coords.count - 1, distanceMi: target))
            } else {
                let seg = cum[j + 1] - cum[j]
                let frac = seg > 0 ? (target - cum[j]) / seg : 0
                let a = coords[j], b = coords[j + 1]
                let pt = Coordinate(
                    lat: a.lat + (b.lat - a.lat) * frac,
                    lon: a.lon + (b.lon - a.lon) * frac
                )
                out.append(Sample(coordinate: pt, routeIndex: j, distanceMi: target))
            }
        }
        return Result(waypoints: out, totalMi: total)
    }
}

/// Builds the initial stop list for a route (web `buildWaypoints`).
public enum StopListBuilder {
    public static func initialStops(
        route: RouteGeometry,
        rangeMi: Double,
        originLabel: String,
        destinationLabel: String
    ) -> (stops: [Stop], totalMi: Double) {
        let range = Vehicle.clampRange(rangeMi)
        let sampled = WaypointSampler.sample(route.coordinates, rangeMi: range)
        let n = sampled.waypoints.count
        var stops: [Stop] = []
        stops.reserveCapacity(n)
        for (i, wp) in sampled.waypoints.enumerated() {
            let kind: StopKind = i == 0 ? .origin : (i == n - 1 ? .destination : .sampled)
            let label: String
            switch kind {
            case .origin: label = originLabel
            case .destination: label = destinationLabel
            default: label = "Waypoint \(i)"
            }
            stops.append(Stop(kind: kind, label: label, coordinate: wp.coordinate, routeIndex: wp.routeIndex, distanceMi: wp.distanceMi))
        }
        return (stops, sampled.totalMi)
    }
}
