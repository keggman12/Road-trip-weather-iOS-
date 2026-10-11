import Foundation

/// A user-added stop as saved with a trip (web `currentTripData.manualStops`).
public struct ManualStopEdit: Hashable, Codable, Sendable {
    public var coordinate: Coordinate
    public var label: String
    public var dwellMinutes: Int
    public var manualOvernight: Bool
    public var poiKind: POIKind?
    public var poiSourceID: String?

    public init(coordinate: Coordinate, label: String, dwellMinutes: Int = defaultDwellMinutes, manualOvernight: Bool = false, poiKind: POIKind? = nil, poiSourceID: String? = nil) {
        self.coordinate = coordinate
        self.label = label
        self.dwellMinutes = dwellMinutes
        self.manualOvernight = manualOvernight
        self.poiKind = poiKind
        self.poiSourceID = poiSourceID
    }
}

/// Stop edits persisted with a saved trip and replayed after re-briefing
/// (web `stopEdits { manualStops, removedMi }`).
public struct StopEdits: Hashable, Codable, Sendable {
    public var manualStops: [ManualStopEdit]
    /// Rounded mile markers of removed sampled waypoints.
    public var removedMi: [Int]

    public init(manualStops: [ManualStopEdit] = [], removedMi: [Int] = []) {
        self.manualStops = manualStops
        self.removedMi = removedMi
    }

    public var isEmpty: Bool { manualStops.isEmpty && removedMi.isEmpty }

    /// Web `currentTripData`: capture edits from a briefing.
    public init(from briefing: Briefing) {
        manualStops = briefing.stops.filter { $0.kind.isUserAdded }.map {
            ManualStopEdit(
                coordinate: $0.coordinate,
                label: $0.label,
                dwellMinutes: $0.dwellMinutes,
                manualOvernight: $0.manualOvernight,
                poiKind: $0.poiKind,
                poiSourceID: $0.poiSourceID
            )
        }
        removedMi = briefing.removedMi
    }
}

/// Matches saved removals to freshly sampled waypoints (web `applyStopEdits`).
public enum StopEditReplayer {
    /// Web `REMOVED_WP_TOLERANCE_MI`: the same route + range resamples to
    /// nearly the same mile markers, so a saved removal finds its waypoint
    /// even if routing shifted slightly.
    public static let toleranceMi: Double = 12

    /// Returns the ids of intermediate sampled stops to remove, one per saved
    /// mile marker (first match wins, never the same stop twice). Markers that
    /// match nothing are skipped silently, like the web.
    public static func stopsToRemove(in stops: [Stop], removedMi: [Int], toleranceMi: Double = toleranceMi) -> [Stop.ID] {
        guard stops.count > 2 else { return [] }
        var taken = Set<Stop.ID>()
        var out: [Stop.ID] = []
        let interior = stops.dropFirst().dropLast()
        for mi in removedMi {
            if let s = interior.first(where: { !$0.kind.isUserAdded && !taken.contains($0.id) && abs($0.distanceMi - Double(mi)) <= toleranceMi }) {
                taken.insert(s.id)
                out.append(s.id)
            }
        }
        return out
    }

    /// Removes a stop from a briefing, remembering sampled removals by
    /// rounded mile (web `removeStop`). Returns false when not found.
    @discardableResult
    public static func remove(stopID: Stop.ID, from briefing: inout Briefing) -> Bool {
        guard let idx = briefing.stops.firstIndex(where: { $0.id == stopID }) else { return false }
        let stop = briefing.stops.remove(at: idx)
        if !stop.kind.isUserAdded {
            briefing.removedMi.append(Int(stop.distanceMi.rounded()))
        }
        return true
    }

    /// Projects a place onto the route and appends it as a user-added stop
    /// (web `insertManualStop`, without the network part). ETAs must be
    /// recomputed by the caller.
    public static func insert(_ edit: ManualStopEdit, into briefing: inout Briefing) -> Stop? {
        guard let proj = Geo.projectOntoRoute(briefing.geometry.coordinates, target: edit.coordinate) else { return nil }
        let stop = Stop(
            kind: edit.poiKind == nil ? .manual : .poi,
            label: edit.label,
            coordinate: proj.coordinate,
            routeIndex: proj.routeIndex,
            distanceMi: proj.distanceMi,
            dwellMinutes: edit.dwellMinutes,
            manualOvernight: edit.manualOvernight,
            poiKind: edit.poiKind,
            poiSourceID: edit.poiSourceID,
            offRouteMi: proj.offRouteMi
        )
        briefing.stops.append(stop)
        return stop
    }
}

/// Most-recently-used location strings (web `rememberLocations`).
public enum RecentLocations {
    public static let maxCount = 12

    /// Inserts `texts` at the front (last given ends up first), case-insensitive
    /// dedupe, blank entries ignored, capped at 12.
    public static func remember(_ texts: [String], into recents: [String], maxCount: Int = maxCount) -> [String] {
        var out = recents
        for raw in texts {
            let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { continue }
            out.removeAll { $0.lowercased() == t.lowercased() }
            out.insert(t, at: 0)
        }
        return Array(out.prefix(maxCount))
    }
}
