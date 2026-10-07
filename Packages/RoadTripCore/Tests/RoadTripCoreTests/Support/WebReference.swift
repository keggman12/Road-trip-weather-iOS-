import Foundation
import Testing
@testable import RoadTripCore

/// Expected values produced by running the web app's own JavaScript
/// (`public/js/util.js`, `icons.js`, and functions extracted from `app.js`)
/// against fixed inputs. Regenerate with `tools/web-reference/gen.mjs`.
struct WebReference: Decodable {
    struct Haversine: Decodable { var denverDallas: Double; var zero: Double }
    struct Bearing: Decodable { var denverToDallas: Double; var dallasToDenver: Double; var north: Double; var east: Double }
    struct Waypoint: Decodable { var lat: Double; var lon: Double; var routeIndex: Int; var distanceMi: Double }
    struct Sample: Decodable { var totalMi: Double; var waypoints: [Waypoint] }
    struct Eta: Decodable {
        var etaEpoch: Double
        var legMi: Double?
        var overnight: Bool
        var autoOvernight: Bool?
        var resumeEpoch: Double?
        var travelBearing: Double?
    }
    struct Wind: Decodable { var w: Double; var t: Double; var rel: String?; var compass: String; var rot: Int }
    struct Categorize: Decodable {
        var id: IDValue
        var cl: Double?
        var cat: String
        enum IDValue: Decodable {
            case number(Int), none
            init(from decoder: Decoder) throws {
                let c = try decoder.singleValueContainer()
                if let i = try? c.decode(Int.self) { self = .number(i) } else { self = .none }
            }
            var value: Int? { if case let .number(i) = self { return i }; return nil }
        }
    }
    struct Score: Decodable { var score: Int; var worstIdx: Int; var worstP: Double }
    struct ScoreEmpty: Decodable { var score: Int }
    struct Project: Decodable { var lat: Double; var lon: Double; var routeIndex: Int; var distanceMi: Double; var distOff: Double }
    struct Thin: Decodable {
        struct Pt: Decodable { var lat: Double; var lon: Double }
        var len: Int; var first: Pt; var last: Pt; var idx7: Pt
    }
    struct Candidate: Decodable { var spanH: Double; var r: Int; var n: Int }

    var route: [[Double]]
    var haversine: Haversine
    var bearing: Bearing
    var sample300: Sample
    var sample180: Sample
    var sample5: Sample
    var sample2: Sample
    var sampleHuge: Sample
    var eta300: [Eta]
    var eta180multiday: [Eta]
    var eta300manual: [Eta]
    var wind: [Wind]
    var compassAll: [[CompassEntry]]
    var compassEdge: [[CompassEntry]]
    var categorize: [Categorize]
    var score: Score
    var scoreEmpty: ScoreEmpty
    var scoreAllUnknown: Int
    var scoreRounding: Int
    var project: Project
    var minDist: Double
    var thin: Thin
    var candidates: [Candidate]

    enum CompassEntry: Decodable {
        case degrees(Double), label(String)
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let d = try? c.decode(Double.self) { self = .degrees(d) } else { self = .label(try c.decode(String.self)) }
        }
    }

    var routeCoordinates: [Coordinate] { route.map { Coordinate(lat: $0[0], lon: $0[1]) } }

    static let shared: WebReference = {
        do {
            return try JSONDecoder().decode(WebReference.self, from: Fixtures.data("web-reference.json"))
        } catch {
            fatalError("web-reference.json fixture unreadable: \(error)")
        }
    }()
}

enum Fixtures {
    static func url(_ name: String) -> URL {
        let parts = name.split(separator: ".", maxSplits: 1).map(String.init)
        let base = parts.first ?? name
        let ext = parts.count > 1 ? parts[1] : nil
        if let u = Bundle.module.url(forResource: base, withExtension: ext, subdirectory: "Fixtures") { return u }
        // Fallback for toolchains that flatten resource directories.
        if let u = Bundle.module.url(forResource: base, withExtension: ext) { return u }
        fatalError("fixture \(name) not found in test bundle")
    }

    static func data(_ name: String) -> Data {
        do { return try Data(contentsOf: url(name)) } catch { fatalError("fixture \(name) unreadable: \(error)") }
    }

    static func string(_ name: String) -> String {
        String(decoding: data(name), as: UTF8.self)
    }
}

/// Approximate equality for doubles coming through JSON.
func approx(_ a: Double, _ b: Double, tolerance: Double = 1e-6) -> Bool {
    abs(a - b) <= tolerance
}

let utc = TimeZone(identifier: "UTC") ?? .current
func date(_ epoch: Double) -> Date { Date(timeIntervalSince1970: epoch) }
