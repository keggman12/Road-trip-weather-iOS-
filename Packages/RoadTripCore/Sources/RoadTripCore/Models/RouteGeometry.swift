import Foundation

/// A driving route as the routing service returned it.
public struct RouteGeometry: Hashable, Codable, Sendable {
    /// Dense polyline from origin to destination.
    public var coordinates: [Coordinate]
    /// Total distance in statute miles.
    public var distanceMi: Double
    /// Expected drive time in seconds (no stops).
    public var durationSec: Double
    /// "via Amarillo · Lubbock", "Direct", or nil for a plain alternative.
    public var label: String?
    /// Indices into `coordinates` where via-point legs join (empty for a
    /// single-leg route). Lets the UI mark via-points and lets a leg-aware ETA
    /// use per-leg durations later.
    public var legBoundaryIndices: [Int]
    /// Per-leg drive times when the route was chained from several requests.
    public var legDurationsSec: [Double]

    public init(
        coordinates: [Coordinate],
        distanceMi: Double,
        durationSec: Double,
        label: String? = nil,
        legBoundaryIndices: [Int] = [],
        legDurationsSec: [Double] = []
    ) {
        self.coordinates = coordinates
        self.distanceMi = distanceMi
        self.durationSec = durationSec
        self.label = label
        self.legBoundaryIndices = legBoundaryIndices
        self.legDurationsSec = legDurationsSec
    }

    /// Concatenate consecutive legs into one route (via-point routing).
    /// The shared junction point is kept once.
    public static func chained(_ legs: [RouteGeometry], label: String?) -> RouteGeometry {
        var coords: [Coordinate] = []
        var boundaries: [Int] = []
        var distance = 0.0
        var duration = 0.0
        var legDurations: [Double] = []
        for (i, leg) in legs.enumerated() {
            var legCoords = leg.coordinates
            if i > 0, let last = coords.last, let first = legCoords.first, last == first {
                legCoords.removeFirst()
            }
            if i > 0 { boundaries.append(max(0, coords.count - 1)) }
            coords.append(contentsOf: legCoords)
            distance += leg.distanceMi
            duration += leg.durationSec
            legDurations.append(leg.durationSec)
        }
        return RouteGeometry(
            coordinates: coords,
            distanceMi: distance,
            durationSec: duration,
            label: label,
            legBoundaryIndices: boundaries,
            legDurationsSec: legDurations
        )
    }
}
