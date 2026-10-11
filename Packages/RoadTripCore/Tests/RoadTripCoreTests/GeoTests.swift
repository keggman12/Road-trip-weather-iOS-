import Foundation
import Testing
@testable import RoadTripCore

@Suite("Geo (web util.js / app.js)")
struct GeoTests {
    let ref = WebReference.shared
    let denver = Coordinate(lat: 39.7392, lon: -104.9903)
    let dallas = Coordinate(lat: 32.7767, lon: -96.797)

    @Test func haversineMatchesWeb() {
        #expect(approx(Geo.haversineMiles(denver, dallas), ref.haversine.denverDallas, tolerance: 1e-9))
        #expect(Geo.haversineMiles(denver, denver) == 0)
        #expect(approx(Geo.haversineMiles(denver, dallas), Geo.haversineMiles(dallas, denver), tolerance: 1e-9))
    }

    @Test func bearingMatchesWeb() {
        #expect(approx(Geo.bearingDegrees(from: denver, to: dallas), ref.bearing.denverToDallas, tolerance: 1e-9))
        #expect(approx(Geo.bearingDegrees(from: dallas, to: denver), ref.bearing.dallasToDenver, tolerance: 1e-9))
        #expect(approx(Geo.bearingDegrees(from: Coordinate(lat: 0, lon: 0), to: Coordinate(lat: 1, lon: 0)), 0))
        #expect(approx(Geo.bearingDegrees(from: Coordinate(lat: 0, lon: 0), to: Coordinate(lat: 0, lon: 1)), 90))
        // Always in [0, 360).
        let west = Geo.bearingDegrees(from: Coordinate(lat: 0, lon: 0), to: Coordinate(lat: 0, lon: -1))
        #expect(approx(west, 270))
    }

    @Test func cumulativeDistanceEndsAtTotal() {
        let cum = Geo.cumulativeMiles(ref.routeCoordinates)
        #expect(cum.count == ref.route.count)
        #expect(cum[0] == 0)
        #expect(approx(cum[cum.count - 1], ref.sample300.totalMi, tolerance: 1e-9))
        #expect(Geo.cumulativeMiles([]).isEmpty)
    }

    @Test func thinPolylineMatchesWeb() {
        let thinned = Geo.thinPolyline(ref.routeCoordinates, maxPoints: 120)
        #expect(thinned.count == ref.thin.len)
        #expect(approx(thinned[0].lat, ref.thin.first.lat) && approx(thinned[0].lon, ref.thin.first.lon))
        #expect(approx(thinned[119].lat, ref.thin.last.lat) && approx(thinned[119].lon, ref.thin.last.lon))
        #expect(approx(thinned[7].lat, ref.thin.idx7.lat) && approx(thinned[7].lon, ref.thin.idx7.lon))
        // Short input is returned unchanged.
        let short = Array(ref.routeCoordinates.prefix(10))
        #expect(Geo.thinPolyline(short, maxPoints: 120) == short)
    }

    @Test func projectOntoRouteMatchesWeb() throws {
        let p = Coordinate(lat: 36.0, lon: -100.5)
        let proj = try #require(Geo.projectOntoRoute(ref.routeCoordinates, target: p))
        #expect(approx(proj.coordinate.lat, ref.project.lat, tolerance: 1e-9))
        #expect(approx(proj.coordinate.lon, ref.project.lon, tolerance: 1e-9))
        #expect(proj.routeIndex == ref.project.routeIndex)
        #expect(approx(proj.distanceMi, ref.project.distanceMi, tolerance: 1e-6))
        #expect(approx(proj.offRouteMi, ref.project.distOff, tolerance: 1e-9))
        #expect(Geo.projectOntoRoute([denver], target: p) == nil)
    }

    @Test func minDistanceMatchesWeb() {
        let p = Coordinate(lat: 36.0, lon: -100.5)
        #expect(approx(Geo.minDistanceMiles(from: p, to: ref.routeCoordinates), ref.minDist, tolerance: 1e-9))
        #expect(approx(Geo.minDistanceMiles(from: dallas, to: [denver]), ref.haversine.denverDallas, tolerance: 1e-9))
        #expect(Geo.minDistanceMiles(from: p, to: []) == .infinity)
    }

    @Test func boundingBoxPaddingFollowsWebFormula() throws {
        let bbox = try #require(Geo.boundingBox(of: [denver, dallas], paddedByMeters: 8000))
        let latPad = 8000.0 / 111_320
        #expect(approx(bbox.minLat, dallas.lat - latPad))
        #expect(approx(bbox.maxLat, denver.lat + latPad))
        let cosMid = cos(((denver.lat + dallas.lat) / 2) * .pi / 180)
        let lonPad = 8000.0 / (111_320 * cosMid)
        #expect(approx(bbox.minLon, denver.lon - lonPad))
        #expect(approx(bbox.maxLon, dallas.lon + lonPad))
        #expect(bbox.contains(Coordinate(lat: 36, lon: -100)))
        #expect(!bbox.contains(Coordinate(lat: 45, lon: -100)))
        #expect(Geo.boundingBox(of: [], paddedByMeters: 1) == nil)
    }

    @Test func chainedRoutesDropDuplicateJunction() {
        let leg1 = RouteGeometry(coordinates: [denver, Coordinate(lat: 36, lon: -100)], distanceMi: 100, durationSec: 3600)
        let leg2 = RouteGeometry(coordinates: [Coordinate(lat: 36, lon: -100), dallas], distanceMi: 200, durationSec: 7200)
        let r = RouteGeometry.chained([leg1, leg2], label: "via Somewhere")
        #expect(r.coordinates.count == 3)
        #expect(r.distanceMi == 300)
        #expect(r.durationSec == 10_800)
        #expect(r.legBoundaryIndices == [1])
        #expect(r.legDurationsSec == [3600, 7200])
        #expect(r.label == "via Somewhere")
    }
}
