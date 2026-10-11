import Foundation
import Testing
@testable import RoadTripCore

@Suite("Stop planner (real places within range)")
struct StopPlannerTests {
    /// Straight east-west road along the equator: 1° ≈ 69.1 mi.
    static let route: RouteGeometry = {
        let coords = (0...600).map { Coordinate(lat: 0, lon: Double($0) * 0.01) }   // ≈ 414 mi
        return RouteGeometry(coordinates: coords, distanceMi: Geo.cumulativeMiles(coords).last ?? 0, durationSec: 6 * 3600)
    }()
    static let mi = 1 / 69.093   // degrees of longitude per mile at the equator

    static func poi(_ kind: POIKind, atMile m: Double, offMi: Double = 0, id: String) -> POI {
        POI(kind: kind, sourceID: id, name: "\(kind.fallbackName) \(id)", detail: nil, coordinate: Coordinate(lat: offMi * mi, lon: m * mi))
    }

    func plan(_ pois: [POI], range: Double = 180) -> [Stop] {
        let c = StopPlanner.candidates(route: Self.route.coordinates, pois: pois)
        return StopPlanner.plan(route: Self.route, rangeMi: range, candidates: c, originLabel: "A", destinationLabel: "B").stops
    }

    @Test func picksTheFarthestFuelStopWithinNinetyPercent() {
        // 180 mi bike → 162 mi legs. Fuel at 130 and 170 (out of reach), rest at 150.
        let stops = plan([Self.poi(.bucees, atMile: 130, id: "b"), Self.poi(.loves, atMile: 170, id: "l"), Self.poi(.rest, atMile: 150, id: "r")])
        let first = stops[1]
        #expect(first.kind == .planned && first.poiKind == .bucees)
        #expect(abs(first.distanceMi - 130) < 0.5)
        #expect(first.tag(index: 1, total: stops.count) == "BUC-EE'S")
        #expect(first.planNote == nil)
        let legs = zip(stops, stops.dropFirst()).map { $1.distanceMi - $0.distanceMi }
        #expect(legs.allSatisfy { $0 <= 162 + 1e-6 }, "\(legs)")
    }

    @Test func restAreaOnlyWhenNoFuelInReach() {
        let stops = plan([Self.poi(.rest, atMile: 120, id: "r"), Self.poi(.loves, atMile: 200, id: "l")])
        #expect(stops[1].poiKind == .rest)
        #expect(stops[1].planNote == "Rest area — no fuel")
        #expect(stops[2].poiKind == .loves, "200 − 120 = 80 mi, reachable")
    }

    @Test func plainWaypointWithWarningWhenNothingInReach() {
        let stops = plan([])
        #expect(stops.map(\.kind) == [.origin, .sampled, .sampled, .destination])
        #expect(abs(stops[1].distanceMi - 162) < 1e-6)
        #expect(abs(stops[2].distanceMi - 324) < 1e-6)
        #expect(stops[1].planNote?.hasPrefix("No fuel stop or rest area within 162 mi") == true)
    }

    @Test func detourCountsAgainstTheLeg() {
        // At mile 158 but 5 mi off the road: 163 > 162, so the closer one wins.
        let stops = plan([Self.poi(.loves, atMile: 158, offMi: 5, id: "far"), Self.poi(.loves, atMile: 140, offMi: 1, id: "near")])
        #expect(stops[1].poiSourceID == "near")
    }

    @Test func noStopsWhenTheTripFitsInOneLeg() {
        let stops = plan([Self.poi(.bucees, atMile: 100, id: "b")], range: 800)
        #expect(stops.map(\.kind) == [.origin, .destination])
    }

    @Test func plannedStopsAreNotUserEditsButCanBeRemoved() {
        var b = Briefing(routeIndex: 0, routeLabel: nil, geometry: Self.route, totalMi: 414, departure: Date(timeIntervalSince1970: 0), departureTimeZoneID: "UTC", rangeMi: 180, stops: plan([Self.poi(.bucees, atMile: 130, id: "b")]))
        #expect(StopEdits(from: b).manualStops.isEmpty, "planned stops are not replayed as manual stops")
        let id = b.stops[1].id
        StopEditReplayer.remove(stopID: id, from: &b)
        #expect(b.removedMi == [130])
        let replan = plan([Self.poi(.bucees, atMile: 130, id: "b")])
        #expect(StopEditReplayer.stopsToRemove(in: replan, removedMi: [130]).count == 1)
    }
}

@Suite("Stop planner summary")
struct StopPlannerSummaryTests {
    @Test func summary() {
        let pois = [
            StopPlannerTests.poi(.loves, atMile: 150, id: "l"),
            StopPlannerTests.poi(.rest, atMile: 260, id: "r"),
        ]
        let c = StopPlanner.candidates(route: StopPlannerTests.route.coordinates, pois: pois)
        let stops = StopPlanner.plan(route: StopPlannerTests.route, rangeMi: 180, candidates: c, originLabel: "A", destinationLabel: "B").stops
        #expect(StopPlanner.summary(for: stops, rangeMi: 180) == "Stops at the farthest fuel within 162 mi (90% of 180 mi range): 1 Love's · 1 rest area (no fuel)")
        #expect(StopPlanner.summary(for: [stops[0], stops[stops.count - 1]], rangeMi: 180) == nil)
    }
}
