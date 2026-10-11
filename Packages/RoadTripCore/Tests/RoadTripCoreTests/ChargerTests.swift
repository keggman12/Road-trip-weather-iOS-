import Foundation
import Testing
@testable import RoadTripCore

/// Expected values from the web's own `getSuperchargersNear` with fetch
/// stubbed (`tools/web-reference/gen-ocm.mjs` → Fixtures/web-ocm.json).
@Suite("Superchargers (web getSuperchargersNear)")
struct ChargerTests {
    struct Reference: Decodable {
        struct Expected: Decodable {
            var name: String; var lat: Double; var lon: Double
            var distanceMi: Double?; var town: String; var stalls: Int?; var powerKW: Double?
        }
        struct Case: Decodable {
            var name: String
            var httpOK: Bool?
            var chargers: [Expected]
        }
        var url: String
        var cases: [Case]
    }

    static let ref: Reference? = try? JSONDecoder().decode(Reference.self, from: Fixtures.data("web-ocm.json"))

    /// Raw payload bytes per case, re-read so they reach the parser untouched.
    static func payload(_ name: String) throws -> Data {
        let root = try #require(try JSONSerialization.jsonObject(with: Fixtures.data("web-ocm.json")) as? [String: Any])
        let cases = try #require(root["cases"] as? [[String: Any]])
        let c = try #require(cases.first { $0["name"] as? String == name })
        return try JSONSerialization.data(withJSONObject: try #require(c["payload"]), options: [.fragmentsAllowed])
    }

    @Test(arguments: ["typical", "sparse", "notArray"])
    func parsesLikeTheWeb(_ name: String) throws {
        let ref = try #require(Self.ref)
        let expected = try #require(ref.cases.first { $0.name == name }).chargers
        let got = OpenChargeMap.parse(try Self.payload(name))
        #expect(got.count == expected.count)
        for (g, e) in zip(got, expected) {
            #expect(g.name == e.name)
            #expect(g.coordinate == Coordinate(lat: e.lat, lon: e.lon))
            #expect(g.distanceMi == e.distanceMi)
            #expect(g.town == e.town)
            #expect(g.stalls == e.stalls)
            #expect(g.powerKW == e.powerKW)
        }
    }

    @Test func urlMatchesTheWebWithoutTheKey() throws {
        let ref = try #require(Self.ref)
        let webWithoutKey = try #require(ref.url.components(separatedBy: "&key=").first)
        #expect(OpenChargeMap.url(near: Coordinate(lat: 35.22198765, lon: -101.83129876))?.absoluteString == webWithoutKey)
    }

    @Test func summaryMatchesTheWebCardLine() {
        let c = Charger(name: "Amarillo, TX Supercharger", coordinate: Coordinate(lat: 0, lon: 0), distanceMi: 3.3, town: "Amarillo, TX", stalls: 12, powerKW: 249.6)
        #expect(c.summary == "Amarillo, TX Supercharger · 3.3 mi off route · 12 stalls · 250 kW")
        let bare = Charger(name: "Canyon Supercharger", coordinate: Coordinate(lat: 0, lon: 0), distanceMi: 18, town: "", stalls: nil, powerKW: nil)
        #expect(bare.summary == "Canyon Supercharger · 18 mi off route")
    }
}
