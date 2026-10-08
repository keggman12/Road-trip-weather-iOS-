import Foundation
import Testing
@testable import RoadTripCore

@Suite("Route comparison (distinct alternatives)")
struct RouteComparisonTests {
    /// A→B along y = bulge·sin(πx); degrees, ~4° long.
    static func line(bulge: Double, n: Int = 300) -> [Coordinate] {
        (0..<n).map { i in
            let f = Double(i) / Double(n - 1)
            return Coordinate(lat: 35 + bulge * sin(f * .pi), lon: -104 + 4 * f)
        }
    }
    static func route(_ bulge: Double, _ label: String? = nil, minutes: Double = 600) -> RouteGeometry {
        let c = line(bulge: bulge)
        return RouteGeometry(coordinates: c, distanceMi: Geo.cumulativeMiles(c).last ?? 0, durationSec: minutes * 60, label: label)
    }

    @Test func overlapOfSameAndDifferentRoads() {
        #expect(RouteComparison.overlap(Self.line(bulge: 0), with: Self.line(bulge: 0.01)) == 1)
        #expect(RouteComparison.overlap(Self.line(bulge: 0), with: Self.line(bulge: 1.5)) < 0.3)
    }

    @Test func dedupeDropsTheSameRoadKeepsTheOtherOne() {
        // Like the owner's trip: "via Raton" and "Direct" share the road; an
        // eastern alternative doesn't.
        let routes = [Self.route(0, "via Raton", minutes: 718), Self.route(0.01, "Direct", minutes: 716), Self.route(-1.5, nil, minutes: 720)]
        let kept = RouteComparison.dedupe(routes)
        #expect(kept.map(\.label) == ["via Raton", nil])
    }

    @Test func capsAtFourAndKeepsTheFirst() {
        let routes = (0..<6).map { Self.route(Double($0) * 0.8 - 2, $0 == 0 ? "via X" : nil) }
        let kept = RouteComparison.dedupe(routes)
        #expect(kept.count == 4)
        #expect(kept.first?.label == "via X")
    }

    @Test func distinctivePointIsWhereTheRoutesDiverge() throws {
        let p = try #require(RouteComparison.distinctivePoint(of: Self.line(bulge: 1.5), others: [Self.line(bulge: 0)]))
        #expect(abs(p.lat - 36.5) < 0.1 && abs(p.lon - -102) < 0.1, "middle of the bulge")
        #expect(RouteComparison.distinctivePoint(of: Self.line(bulge: 0.01), others: [Self.line(bulge: 0)]) == nil)
    }

    @Test func labels() {
        #expect(RouteComparison.label(existing: "via Raton", distinctivePlace: "Clayton, NM") == "via Raton")
        #expect(RouteComparison.label(existing: "Direct", distinctivePlace: "Lamar, CO") == "Direct · via Lamar, CO")
        #expect(RouteComparison.label(existing: nil, distinctivePlace: "Lamar, CO") == "via Lamar, CO")
        #expect(RouteComparison.label(existing: nil, distinctivePlace: nil) == nil)
    }
}
