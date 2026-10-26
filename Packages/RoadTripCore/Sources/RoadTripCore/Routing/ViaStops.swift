import Foundation

/// The user's via-points as briefing stops: every route chained through
/// them gets one stop per via, at the via's own coordinate (weather where
/// the user put the pin), placed along the route where its leg joins.
public enum ViaStops {
    /// How far a leg junction may be from its via. MapKit snaps a via to the
    /// nearest road, which can be miles away for a pin in open country;
    /// "More routes" hubs are geocoded cities, never this close to a user via
    /// they didn't route through by chance.
    public static let maxSnapMi: Double = 25

    /// One `.via` stop per via, or [] when `route` wasn't chained through
    /// `vias` in order (the direct route, plain alternates, suggestions).
    public static func stops(for vias: [PlacePoint], on route: RouteGeometry) -> [Stop] {
        let coords = route.coordinates
        guard !vias.isEmpty, route.legBoundaryIndices.count == vias.count,
              route.legBoundaryIndices.allSatisfy({ coords.indices.contains($0) })
        else { return [] }
        let junctions = route.legBoundaryIndices.map { coords[$0] }
        guard zip(vias, junctions).allSatisfy({ Geo.haversineMiles($0.coordinate, $1) <= maxSnapMi }) else { return [] }
        let cum = Geo.cumulativeMiles(coords)
        return zip(vias, route.legBoundaryIndices).map { via, i in
            Stop(
                kind: .via,
                label: via.label,
                coordinate: via.coordinate,
                routeIndex: min(i, max(0, coords.count - 2)),
                distanceMi: cum[i],
                dwellMinutes: 0,
                timeZoneID: via.timeZoneID,
                offRouteMi: Geo.haversineMiles(via.coordinate, coords[i])
            )
        }
    }

    /// `stops` with the via stops added between origin and destination;
    /// ETA recomputation sorts them into place by `distanceMi`.
    public static func inserting(_ vias: [Stop], into stops: [Stop]) -> [Stop] {
        guard !vias.isEmpty, stops.count >= 2 else { return stops }
        var out = stops
        out.insert(contentsOf: vias, at: out.count - 1)
        let interior = out[1..<(out.count - 1)].sorted { $0.distanceMi < $1.distanceMi }
        return [out[0]] + interior + [out[out.count - 1]]
    }
}
