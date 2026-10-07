import Foundation
import Testing
@testable import RoadTripCore

@Suite("WaypointSampler (web util.sampleWaypoints)")
struct WaypointSamplerTests {
    let ref = WebReference.shared

    func check(_ expected: WebReference.Sample, rangeMi: Double, sourceLocation: SourceLocation = #_sourceLocation) {
        let r = WaypointSampler.sample(ref.routeCoordinates, rangeMi: rangeMi)
        #expect(approx(r.totalMi, expected.totalMi, tolerance: 1e-9), sourceLocation: sourceLocation)
        #expect(r.waypoints.count == expected.waypoints.count, "count for range \(rangeMi)", sourceLocation: sourceLocation)
        for (got, want) in zip(r.waypoints, expected.waypoints) {
            #expect(approx(got.coordinate.lat, want.lat, tolerance: 1e-9), sourceLocation: sourceLocation)
            #expect(approx(got.coordinate.lon, want.lon, tolerance: 1e-9), sourceLocation: sourceLocation)
            #expect(got.routeIndex == want.routeIndex, sourceLocation: sourceLocation)
            #expect(approx(got.distanceMi, want.distanceMi, tolerance: 1e-9), sourceLocation: sourceLocation)
        }
    }

    @Test func range300() { check(ref.sample300, rangeMi: 300) }
    @Test func range180() { check(ref.sample180, rangeMi: 180) }
    /// 663 mi / 5 mi would need 134 points: interval collapses to total/24 → 25 points.
    @Test func overflowCollapsesTo25() { check(ref.sample5, rangeMi: 5) }
    /// Below the 5 mi floor the interval is clamped first, then overflows.
    @Test func intervalFloorThenOverflow() { check(ref.sample2, rangeMi: 2) }
    /// Range longer than the trip: start and end only.
    @Test func hugeRangeGivesEndpoints() { check(ref.sampleHuge, rangeMi: 5000) }

    @Test func emptyRoute() {
        let r = WaypointSampler.sample([], rangeMi: 300)
        #expect(r.waypoints.isEmpty && r.totalMi == 0)
    }

    @Test func tailRuleDropsTargetCloseToEnd() {
        // 100 mi straight line (approx), range 45: targets 0, 45, (90 is within 0.35·45=15.75 of 100 → dropped), 100
        let a = Coordinate(lat: 35, lon: -100)
        let b = Coordinate(lat: 35, lon: -100 + 100 / (Geo.haversineMiles(a, Coordinate(lat: 35, lon: -99))))
        let r = WaypointSampler.sample([a, b], rangeMi: 45)
        #expect(r.waypoints.map { Int($0.distanceMi.rounded()) } == [0, 45, 100])
    }

    @Test func initialStopsCarryLabelsDwellAndKinds() {
        let route = RouteGeometry(coordinates: ref.routeCoordinates, distanceMi: 663, durationSec: 41_400)
        let (stops, total) = StopListBuilder.initialStops(route: route, rangeMi: 180, originLabel: "Denver, CO", destinationLabel: "Dallas, TX")
        #expect(approx(total, ref.sample180.totalMi, tolerance: 1e-9))
        #expect(stops.count == ref.sample180.waypoints.count)
        #expect(stops.first?.kind == .origin && stops.first?.label == "Denver, CO" && stops.first?.dwellMinutes == 0)
        #expect(stops.last?.kind == .destination && stops.last?.label == "Dallas, TX" && stops.last?.dwellMinutes == 0)
        for (i, s) in stops.dropFirst().dropLast().enumerated() {
            #expect(s.kind == .sampled)
            #expect(s.label == "Waypoint \(i + 1)")
            #expect(s.dwellMinutes == defaultDwellMinutes)
        }
    }

    @Test func initialStopsClampRange() {
        let route = RouteGeometry(coordinates: ref.routeCoordinates, distanceMi: 663, durationSec: 41_400)
        let tiny = StopListBuilder.initialStops(route: route, rangeMi: 1, originLabel: "a", destinationLabel: "b").stops
        let twenty = StopListBuilder.initialStops(route: route, rangeMi: 20, originLabel: "a", destinationLabel: "b").stops
        #expect(tiny.count == twenty.count)
    }
}
