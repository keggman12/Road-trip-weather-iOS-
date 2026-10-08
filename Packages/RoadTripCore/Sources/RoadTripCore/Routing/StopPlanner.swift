import Foundation

/// Places stops at real Buc-ee's / Love's / rest areas instead of at exact
/// range intervals (owner request; the web sampled every `range` miles).
///
/// Each leg ends at the farthest fuel stop reachable within `reserve` × range,
/// counting the drive off the route and back. With no fuel stop in reach the
/// farthest rest area is used (flagged "no fuel"); with nothing in reach a
/// plain waypoint goes at the reachable limit, with a warning.
public enum StopPlanner {
    /// Legs use at most 90 % of the vehicle range (owner decision).
    public static let reserve = 0.9
    /// Web `MAX_WAYPOINTS`: forecasts per briefing stay bounded.
    public static let maxStops = WaypointSampler.maxWaypoints

    /// A place projected onto the route.
    public struct Candidate: Hashable, Sendable {
        public var poi: POI
        public var distanceMi: Double
        public var offRouteMi: Double
        public var routeIndex: Int
    }

    /// Projects corridor POIs onto the route, nearest first along it.
    public static func candidates(route: [Coordinate], pois: [POI]) -> [Candidate] {
        pois.compactMap { p -> Candidate? in
            guard let proj = Geo.projectOntoRoute(route, target: p.coordinate) else { return nil }
            return Candidate(poi: p, distanceMi: proj.distanceMi, offRouteMi: proj.offRouteMi, routeIndex: proj.routeIndex)
        }
        .sorted { $0.distanceMi < $1.distanceMi }
    }

    public static func maxLegMi(rangeMi: Double) -> Double {
        Vehicle.clampRange(rangeMi) * reserve
    }

    public static func plan(
        route: RouteGeometry,
        rangeMi: Double,
        candidates: [Candidate],
        originLabel: String,
        destinationLabel: String
    ) -> (stops: [Stop], totalMi: Double) {
        let coords = route.coordinates
        guard let first = coords.first, let last = coords.last else { return ([], 0) }
        let cum = Geo.cumulativeMiles(coords)
        let total = cum.last ?? 0
        let maxLeg = maxLegMi(rangeMi: rangeMi)

        var stops = [Stop(kind: .origin, label: originLabel, coordinate: first, routeIndex: 0, distanceMi: 0)]
        var pos = 0.0          // along-route mile of the last stop
        var carryOff = 0.0     // miles to get back onto the route from it

        while total - pos + carryOff > maxLeg, stops.count < maxStops - 1 {
            let budget = maxLeg - carryOff
            let reachable = candidates.filter {
                $0.distanceMi > pos + 0.5 && ($0.distanceMi - pos) + $0.offRouteMi <= budget
            }
            let fuel = reachable.filter { $0.poi.kind.isFuel }
            if let pick = farthest(fuel) ?? farthest(reachable) {
                stops.append(Stop(
                    kind: .planned,
                    label: pick.poi.name,
                    coordinate: pick.poi.coordinate,
                    routeIndex: pick.routeIndex,
                    distanceMi: pick.distanceMi,
                    poiKind: pick.poi.kind,
                    poiSourceID: pick.poi.sourceID,
                    offRouteMi: pick.offRouteMi,
                    planNote: pick.poi.kind.isFuel ? nil : "Rest area — no fuel"
                ))
                pos = pick.distanceMi
                carryOff = pick.offRouteMi
            } else {
                let target = pos + budget
                let (pt, idx) = point(at: target, coords: coords, cum: cum)
                stops.append(Stop(
                    kind: .sampled,
                    label: "Waypoint \(stops.count)",
                    coordinate: pt,
                    routeIndex: idx,
                    distanceMi: target,
                    planNote: "No fuel stop or rest area within \(Int(maxLeg.rounded())) mi — plan fuel ahead"
                ))
                pos = target
                carryOff = 0
            }
        }
        stops.append(Stop(kind: .destination, label: destinationLabel, coordinate: last, routeIndex: coords.count - 1, distanceMi: total))
        return (stops, total)
    }

    /// Farthest along the route; ties go to the one closer to the road.
    static func farthest(_ c: [Candidate]) -> Candidate? {
        c.max { l, r in
            l.distanceMi != r.distanceMi ? l.distanceMi < r.distanceMi : l.offRouteMi > r.offRouteMi
        }
    }

    static func point(at mile: Double, coords: [Coordinate], cum: [Double]) -> (Coordinate, Int) {
        var j = 0
        while j < cum.count - 1, cum[j + 1] < mile { j += 1 }
        guard j < coords.count - 1 else { return (coords[coords.count - 1], coords.count - 1) }
        let seg = cum[j + 1] - cum[j]
        let f = seg > 0 ? (mile - cum[j]) / seg : 0
        let a = coords[j], b = coords[j + 1]
        return (Coordinate(lat: a.lat + (b.lat - a.lat) * f, lon: a.lon + (b.lon - a.lon) * f), j)
    }
}

extension StopPlanner {
    /// One line explaining how the stops were chosen, e.g. "Stops at the
    /// farthest fuel within 162 mi (90% of 180 mi range): 2 Love's · 1 Buc-ee's
    /// · 1 rest area (no fuel)". Nil when the trip needs no stops.
    public static func summary(for stops: [Stop], rangeMi: Double) -> String? {
        let interior = stops.filter { $0.kind == .planned || $0.kind == .sampled }
        guard !interior.isEmpty else { return nil }
        let count = { (k: POIKind) in interior.filter { $0.kind == .planned && $0.poiKind == k }.count }
        var parts: [String] = []
        if count(.loves) > 0 { parts.append("\(count(.loves)) Love's") }
        if count(.bucees) > 0 { parts.append("\(count(.bucees)) Buc-ee's") }
        if count(.rest) > 0 { parts.append("\(count(.rest)) rest area\(count(.rest) == 1 ? "" : "s") (no fuel)") }
        let plain = interior.filter { $0.kind == .sampled }.count
        if plain > 0 { parts.append("\(plain) with nothing in reach") }
        let range = Vehicle.clampRange(rangeMi)
        return "Stops at the farthest fuel within \(Int(maxLegMi(rangeMi: range).rounded())) mi (90% of \(Int(range.rounded())) mi range): " + parts.joined(separator: " · ")
    }
}
