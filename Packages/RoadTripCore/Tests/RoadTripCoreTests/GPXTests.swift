import Foundation
import Testing
@testable import RoadTripCore

/// Expected documents come from the web's own `buildGPX`
/// (`tools/web-reference/gen-gpx.mjs` → Fixtures/web-gpx.json).
@Suite("GPX export (web gpx.buildGPX)")
struct GPXTests {
    struct Case: Decodable {
        struct C: Decodable { var lat: Double; var lon: Double }
        struct W: Decodable { var temp: Int; var category: String; var windSpeed: Int; var pop: Double? }
        struct S: Decodable { var lat: Double; var lon: Double; var etaEpoch: Double; var label: String; var weather: W?; var overnight: Bool }
        var name: String
        var coords: [C]
        var stops: [S]
        var gpx: String
    }

    static let cases: [Case] = (try? JSONDecoder().decode([Case].self, from: Fixtures.data("web-gpx.json"))) ?? []

    @Test func casesLoaded() { #expect(Self.cases.count == 2) }

    @Test(arguments: cases.indices)
    func matchesWebOutput(_ index: Int) throws {
        let c = Self.cases[index]
        let stops = try c.stops.map { s -> Stop in
            var stop = Stop(kind: .sampled, label: s.label, coordinate: Coordinate(lat: s.lat, lon: s.lon), routeIndex: 0, distanceMi: 0)
            stop.eta = date(s.etaEpoch)
            stop.manualOvernight = s.overnight
            if let w = s.weather {
                let category = try #require(ConditionCategory(rawValue: w.category))
                stop.weather = WeatherSnapshot(temperatureF: w.temp, feelsLikeF: w.temp, humidityPercent: nil, windMph: w.windSpeed, windFromDegrees: nil, cloudPercent: nil, conditionRaw: w.category, conditionText: w.category, category: category, recordDate: stop.eta, precipitationChance: w.pop, kind: .hourly)
            }
            return stop
        }
        let now = date(1_781_000_000)
        let gpx = GPXBuilder.build(name: c.name, coordinates: c.coords.map { Coordinate(lat: $0.lat, lon: $0.lon) }, stops: stops, now: now)
            .replacingOccurrences(of: "<time>\(GPXBuilder.isoTime(now))</time></metadata>", with: "<time>NOW</time></metadata>")
        #expect(gpx == c.gpx)
    }

    @Test func isoTimeMatchesJavaScript() {
        #expect(GPXBuilder.isoTime(date(1_781_096_400)) == "2026-06-10T13:00:00.000Z")
        #expect(GPXBuilder.isoTime(date(1_781_096_400.1239)) == "2026-06-10T13:00:00.123Z", "milliseconds truncate like JS")
        #expect(GPXBuilder.isoTime(date(0)) == "1970-01-01T00:00:00.000Z")
    }

    @Test func fileNames() {
        #expect(GPXBuilder.fileName(for: "Denver → Dallas") == "Denver → Dallas.gpx")
        #expect(GPXBuilder.fileName(for: "a/b:c?") == "a-b-c-.gpx")
        #expect(GPXBuilder.fileName(for: "  ") == "Road trip.gpx")
    }
}

@Suite("Navigation links (web itinerary.js)")
struct NavigationLinkTests {
    @Test func wazeLinks() {
        let c = Coordinate(lat: 35.2219971, lon: -101.8312969)
        #expect(NavigationLinks.wazeApp(c)?.absoluteString == "waze://?ll=35.221997,-101.831297&navigate=yes")
        #expect(NavigationLinks.wazeWeb(c)?.absoluteString == "https://waze.com/ul?ll=35.22200%2C-101.83130&navigate=yes&zoom=17")
    }

    @Test func originIsNotNavigable() {
        #expect(!NavigationLinks.isNavigable(stopIndex: 0))
        #expect(NavigationLinks.isNavigable(stopIndex: 1))
    }
}
