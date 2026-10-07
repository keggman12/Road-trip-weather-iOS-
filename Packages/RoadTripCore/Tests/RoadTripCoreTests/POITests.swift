import Foundation
import Testing
@testable import RoadTripCore

@Suite("POI normalisation and parsers (web seed-pois.js / api.js)")
struct POITests {
    typealias El = OverpassResponse.Element

    @Test func dedupeKeyUsesToFixed() {
        #expect(POINormalizer.dedupeKey(Coordinate(lat: 30.123456, lon: -97.987654), decimals: 2) == "30.12,-97.99")
        #expect(POINormalizer.dedupeKey(Coordinate(lat: 30.123456, lon: -97.987654), decimals: 3) == "30.123,-97.988")
    }

    @Test func brandSitesCollapseWithinCell() {
        let els = [
            El(type: "node", id: 1, lat: 30.1234, lon: -97.5678, tags: ["amenity": "fuel", "name": "Buc-ee's"]),
            El(type: "way", id: 2, center: .init(lat: 30.1249, lon: -97.5651), tags: ["building": "yes", "brand": "Buc-ee's"]),
            El(type: "node", id: 3, lat: 30.1201, lon: -97.5699, tags: ["shop": "convenience"]),   // same 2-dp cell: 30.12,-97.57
            El(type: "node", id: 4, lat: 30.2000, lon: -97.5678, tags: [:]),                       // different cell
            El(type: "node", id: 5, tags: ["name": "no coords"]),                                  // skipped
        ]
        let out = POINormalizer.normalize(els, kind: .bucees)
        #expect(out.map(\.sourceID) == ["node/1", "node/4"])
        #expect(out[0].name == "Buc-ee's")
        #expect(out[1].name == "Buc-ee's")          // fallback name
        #expect(out[0].detail == nil)
    }

    @Test func restAreasDedupeTighterAndExcludeBrands() {
        let els = [
            El(type: "node", id: 10, lat: 35.1001, lon: -101.0001, tags: ["highway": "rest_area", "name": "Rest Area NB"]),
            El(type: "node", id: 11, lat: 35.1012, lon: -101.0003, tags: ["highway": "rest_area", "name": "Rest Area SB"]), // 3-dp cell differs → survives
            El(type: "node", id: 12, lat: 35.1001, lon: -101.0001, tags: ["highway": "rest_area"]),                        // same 3-dp cell → dropped
            El(type: "way", id: 13, center: .init(lat: 36.0, lon: -100.0), tags: ["highway": "services", "brand": "Love's"]), // branded → excluded
            El(type: "way", id: 14, center: .init(lat: 36.5, lon: -100.5), tags: ["highway": "services"]),
        ]
        let out = POINormalizer.normalize(els, kind: .rest)
        #expect(out.map(\.sourceID) == ["node/10", "node/11", "way/14"])
        #expect(out[0].detail == "Rest area")
        #expect(out[2].detail == "Service plaza")
        #expect(out[2].name == "Service plaza")     // detail is the fallback name for rest
    }

    @Test func overpassFailureRemark() throws {
        let fail = try OverpassResponse.decode(Data(#"{"elements":[],"remark":"runtime error: Query timed out in \"query\" at line 3"}"#.utf8))
        #expect(fail.isServerSideFailure)
        let okEmpty = try OverpassResponse.decode(Data(#"{"elements":[]}"#.utf8))
        #expect(!okEmpty.isServerSideFailure)
        let warnWithData = try OverpassResponse.decode(Data(#"{"elements":[{"type":"node","id":1,"lat":1,"lon":2}],"remark":"runtime error: something"}"#.utf8))
        #expect(!warnWithData.isServerSideFailure)
        let fixture = try OverpassResponse.decode(Fixtures.data("overpass-sample.json"))
        #expect(fixture.elements.count == 4)
        #expect(POINormalizer.normalize(fixture.elements, kind: .loves).count == 2)
    }

    @Test func overpassQueriesUseExactTags() {
        let q = OverpassQueries.nationwide(.bucees)
        #expect(q.contains(#"["brand:wikidata"="Q4982335"]"#))
        #expect(q.contains(#"["name"="Buc-ee's"]"#))
        #expect(!q.contains("~"))
        #expect(q.contains("out center 2000;"))
        let rest = OverpassQueries.nationwide(.rest)
        #expect(rest.contains("[timeout:300][maxsize:1073741824]"))
        #expect(rest.contains("out center 50000;"))

        // 35.12345 is stored just below the half, so both JS toFixed(4) and %.4f print 35.1234.
        let corridor = OverpassQueries.corridor(.loves, along: [Coordinate(lat: 35.12345, lon: -101.98765), Coordinate(lat: 35.2, lon: -102)])
        #expect(corridor.contains("(around:8000,35.1234,-101.9877,35.2000,-102.0000)"))
        #expect(corridor.contains("[timeout:30]"))
        #expect(corridor.contains("out center 120;"))
        #expect(!corridor.contains("~"))
        let restCorridor = OverpassQueries.corridor(.rest, along: [Coordinate(lat: 35, lon: -101)])
        #expect(restCorridor.contains("around:4000,"))
        #expect(restCorridor.contains(#"nwr.sv[!"brand"];"#))
    }

    @Test func corridorFilterKeepsPOIsNearRoute() {
        let route = WebReference.shared.routeCoordinates
        let thinned = CorridorFilter.thin(route)
        #expect(thinned.count == 120)
        let onRoute = route[100]
        let near = POI(kind: .loves, sourceID: "loves/1", name: "near", coordinate: Coordinate(lat: onRoute.lat + 0.03, lon: onRoute.lon)) // ~2 mi
        let far = POI(kind: .loves, sourceID: "loves/2", name: "far", coordinate: Coordinate(lat: onRoute.lat + 0.2, lon: onRoute.lon))   // ~14 mi
        let wrongKind = POI(kind: .bucees, sourceID: "bucees/9", name: "b", coordinate: near.coordinate)
        let kept = CorridorFilter.filter([near, far, wrongKind], kind: .loves, alongRoute: route)
        #expect(kept.map(\.sourceID) == ["loves/1"])
        // Rest radius (4000 m ≈ 2.49 mi) excludes a point whose perpendicular
        // distance to the (diagonal) route is ≈ 3.2 mi, while the brand radius
        // (8000 m ≈ 4.97 mi) keeps it.
        let three = POI(kind: .rest, sourceID: "node/3", name: "r", coordinate: Coordinate(lat: onRoute.lat + 0.065, lon: onRoute.lon))
        let perpendicular = Geo.minDistanceMiles(from: three.coordinate, to: thinned)
        #expect(perpendicular > 2.49 && perpendicular < 4.97)
        #expect(CorridorFilter.filter([three], kind: .rest, alongRoute: route).isEmpty)
        #expect(CorridorFilter.filter([three], alongThinned: thinned, radiusMeters: 8000).count == 1)
    }

    @Test func buceesParserFieldScrapesChunks() throws {
        let html = Fixtures.string("bucees-sample.html")
        let pois = try BuceesLocationsParser.parse(html: html, minimumCount: 1)
        #expect(pois.count == 3)   // 4 chunks, one has no coordinates
        let athens = try #require(pois.first { $0.sourceID == "bucees/57" })
        #expect(athens.name == "Buc-ee's #57 – Athens, AL")        // &#8211; decoded
        #expect(athens.detail == "2328 Lindsay Lane S & Hwy 72")   // &amp; decoded
        #expect(approx(athens.coordinate.lat, 34.7986) && approx(athens.coordinate.lon, -86.9544))
        let noNumber = try #require(pois.first { $0.sourceID.hasPrefix("bucees/3") && !$0.sourceID.contains("/35") })
        _ = noNumber
        let fallbackID = try #require(pois.first { $0.sourceID.contains(",") })
        #expect(fallbackID.sourceID == "bucees/30.0427,-97.8390")   // no "#NN" in name → 4-dp lat,lon
        #expect(fallbackID.detail == nil)                            // empty street → nil
        let quoted = try #require(pois.first { $0.sourceID == "bucees/35" })
        #expect(quoted.name == "Buc-ee's #35 – New Braunfels \"North\", TX")
    }

    @Test func buceesParserErrors() {
        #expect(throws: POIParseError.missingJSONLD) {
            try BuceesLocationsParser.parse(html: "<html><body>nothing</body></html>")
        }
        let html = Fixtures.string("bucees-sample.html")
        #expect(throws: POIParseError.tooFewResults(kind: .bucees, parsed: 3, minimum: 30)) {
            try BuceesLocationsParser.parse(html: html)
        }
        #expect(BuceesLocationsParser.storeNumber(in: "#57 – Athens, AL") == "57")
        #expect(BuceesLocationsParser.storeNumber(in: "Athens") == nil)
    }

    @Test func lovesParserKeepsTravelStopsOnly() throws {
        let pois = try LovesStoresParser.parse(data: Fixtures.data("loves-sample.json"), minimumCount: 1)
        #expect(pois.map(\.sourceID) == ["loves/312", "loves/845", "loves/35.1000,-101.9000"])
        #expect(pois[0].name == "Love's #312 — Amarillo, TX")
        #expect(pois[0].detail == "I-40 · Exit 76")
        #expect(pois[1].name == "Love's #845 — Ardmore, OK")   // number served as a string
        #expect(pois[1].detail == "I-35")                        // no exit number
        #expect(pois[2].name == "Love's #?")                     // no number, no city/state
        #expect(pois[2].detail == nil)
    }

    @Test func lovesParserErrors() {
        #expect(throws: POIParseError.unexpectedPayload) {
            try LovesStoresParser.parse(data: Data("not json".utf8))
        }
        #expect(throws: POIParseError.unexpectedPayload) {
            try LovesStoresParser.parse(data: Data(#"{"nope":[]}"#.utf8))
        }
        #expect(throws: POIParseError.tooFewResults(kind: .loves, parsed: 3, minimum: 300)) {
            try LovesStoresParser.parse(data: Fixtures.data("loves-sample.json"))
        }
    }

    @Test func snapshotRoundTrip() throws {
        let pois = [POI(kind: .bucees, sourceID: "bucees/1", name: "Buc-ee's #1", detail: "x", coordinate: Coordinate(lat: 1, lon: 2))]
        let snap = POISnapshot(generatedAt: Date(timeIntervalSince1970: 1_781_096_400), kinds: [.bucees: .init(source: .official, fetchedAt: Date(timeIntervalSince1970: 1_781_096_400), pois: pois)])
        let data = try POISnapshot.encoder().encode(snap)
        let back = try POISnapshot.decoder().decode(POISnapshot.self, from: data)
        #expect(back.formatVersion == POISnapshot.currentFormatVersion)
        #expect(back.payload(for: .bucees)?.count == 1)
        #expect(back.payload(for: .bucees)?.pois == pois)
        #expect(back.payload(for: .loves) == nil)
    }

    @Test func kindMetadata() {
        #expect(POIKind.bucees.corridorRadiusMeters == 8000 && POIKind.rest.corridorRadiusMeters == 4000)
        #expect(POIKind.rest.dedupeDecimals == 3 && POIKind.loves.dedupeDecimals == 2)
        #expect(POIKind.bucees.sanityMinimumCount == 30 && POIKind.loves.sanityMinimumCount == 300)
        #expect(POIKind.rest.isFuel == false && POIKind.loves.isFuel)
        #expect(POIKind.loves.stopTag == "LOVE'S")
    }

    @Test func userAgents() {
        #expect(ClientIdentity.nwsUserAgent(version: "0.1", contact: nil) == "RoadTripWeather-iOS/0.1 (https://github.com/keggman12/Road-trip-weather-iOS-)")
        #expect(ClientIdentity.nwsUserAgent(version: "0.1", contact: " me@example.com ") == "RoadTripWeather-iOS/0.1 (https://github.com/keggman12/Road-trip-weather-iOS-; me@example.com)")
        #expect(ClientIdentity.browserStyleUserAgent(version: "0.1").hasPrefix("Mozilla/5.0 (compatible;"))
    }
}
