import Foundation
import Testing
@testable import RoadTripCore

@Suite("Stop edits, replay, recents, misc model rules")
struct StopEditTests {
    let ref = WebReference.shared

    func briefing() -> Briefing {
        let geometry = RouteGeometry(coordinates: ref.routeCoordinates, distanceMi: 663, durationSec: 41_400)
        let (stops, total) = StopListBuilder.initialStops(route: geometry, rangeMi: 180, originLabel: "Denver", destinationLabel: "Dallas")
        var b = Briefing(routeIndex: 0, geometry: geometry, totalMi: total, departure: Date(timeIntervalSince1970: 1_781_096_400), rangeMi: 180, stops: stops)
        ETACalculator.recompute(&b, fallbackTimeZone: utc)
        return b
    }

    @Test func removalMatchesWithin12Miles() {
        let b = briefing()
        let interior = Array(b.stops.dropFirst().dropLast())
        // Saved markers: one exact, one 11 mi off, one 13 mi off (no match), one duplicate of the first.
        let saved = [Int(interior[0].distanceMi.rounded()), Int(interior[1].distanceMi.rounded()) + 11, Int(interior[2].distanceMi.rounded()) + 13, Int(interior[0].distanceMi.rounded())]
        let ids = StopEditReplayer.stopsToRemove(in: b.stops, removedMi: saved)
        #expect(ids == [interior[0].id, interior[1].id])
    }

    @Test func removalNeverTouchesEndpointsOrUserStops() {
        var b = briefing()
        let manual = StopEditReplayer.insert(ManualStopEdit(coordinate: Coordinate(lat: 36.0, lon: -100.5), label: "Lunch"), into: &b)
        #expect(manual != nil)
        ETACalculator.recompute(&b, fallbackTimeZone: utc)
        let ids = StopEditReplayer.stopsToRemove(in: b.stops, removedMi: [0, Int((manual?.distanceMi ?? 0).rounded()), Int(b.totalMi.rounded())])
        #expect(!ids.contains(b.stops.first?.id ?? UUID()))
        #expect(!ids.contains(b.stops.last?.id ?? UUID()))
        #expect(!ids.contains(manual?.id ?? UUID()))
    }

    @Test func removeRemembersSampledMileOnly() {
        var b = briefing()
        let sampled = b.stops[1]
        #expect(StopEditReplayer.remove(stopID: sampled.id, from: &b))
        #expect(b.removedMi == [Int(sampled.distanceMi.rounded())])
        let manual = StopEditReplayer.insert(ManualStopEdit(coordinate: Coordinate(lat: 36.0, lon: -100.5), label: "Lunch"), into: &b)
        #expect(StopEditReplayer.remove(stopID: manual?.id ?? UUID(), from: &b))
        #expect(b.removedMi.count == 1)
        #expect(!StopEditReplayer.remove(stopID: UUID(), from: &b))
    }

    @Test func insertSnapsToRouteAndKeepsPOIIdentity() throws {
        var b = briefing()
        let edit = ManualStopEdit(coordinate: Coordinate(lat: 36.0, lon: -100.5), label: "Love's #312", dwellMinutes: 20, manualOvernight: true, poiKind: .loves, poiSourceID: "loves/312")
        let s = try #require(StopEditReplayer.insert(edit, into: &b))
        #expect(s.kind == .poi && s.poiKind == .loves && s.poiSourceID == "loves/312")
        #expect(s.dwellMinutes == 20 && s.manualOvernight)
        #expect(approx(s.coordinate.lat, ref.project.lat, tolerance: 1e-9))
        #expect(approx(s.distanceMi, ref.project.distanceMi, tolerance: 1e-6))
        #expect(approx(s.offRouteMi ?? -1, ref.project.distOff, tolerance: 1e-9))
        ETACalculator.recompute(&b, fallbackTimeZone: utc)
        // Sorted into place by distance.
        #expect(b.stops.map(\.distanceMi) == b.stops.map(\.distanceMi).sorted())
        #expect(s.tag(index: 2, total: 6) == "LOVE'S")
    }

    @Test func stopEditsCaptureAndEmpty() {
        var b = briefing()
        #expect(StopEdits(from: b).isEmpty)
        _ = StopEditReplayer.insert(ManualStopEdit(coordinate: Coordinate(lat: 36.0, lon: -100.5), label: "Lunch"), into: &b)
        StopEditReplayer.remove(stopID: b.stops[1].id, from: &b)
        let e = StopEdits(from: b)
        #expect(e.manualStops.count == 1 && e.manualStops[0].label == "Lunch" && e.manualStops[0].dwellMinutes == 15)
        #expect(e.removedMi.count == 1)
    }

    @Test func staleRule() {
        var s = Stop(kind: .sampled, label: "x", coordinate: Coordinate(lat: 0, lon: 0), routeIndex: 0, distanceMi: 0)
        let t = Date(timeIntervalSince1970: 1_781_096_400)
        s.eta = t
        #expect(!s.isForecastStale)   // no weather
        s.weather = WeatherSnapshot(temperatureF: 70, feelsLikeF: 70, windMph: 5, category: .clear, recordDate: t, kind: .hourly)
        s.forecastFor = t.addingTimeInterval(-1800)
        #expect(!s.isForecastStale)   // exactly 30 min is not > 30 min
        s.forecastFor = t.addingTimeInterval(-1801)
        #expect(s.isForecastStale)
    }

    @Test func tagsAndLegWarning() {
        let s = Stop(kind: .sampled, label: "x", coordinate: Coordinate(lat: 0, lon: 0), routeIndex: 0, distanceMi: 100, legMi: 301)
        #expect(s.tag(index: 0, total: 5) == "ORIGIN")
        #expect(s.tag(index: 4, total: 5) == "DEST")
        #expect(s.tag(index: 2, total: 5) == "STOP 2")
        let m = Stop(kind: .manual, label: "x", coordinate: Coordinate(lat: 0, lon: 0), routeIndex: 0, distanceMi: 100)
        #expect(m.tag(index: 2, total: 5) == "MANUAL")
        #expect(s.legExceedsRange(300))
        #expect(!s.legExceedsRange(301))
        #expect(!s.legExceedsRange(0))
    }

    @Test func nearestForecastStop() {
        var b = briefing()
        b.stops[1].weather = WeatherSnapshot(temperatureF: 70, feelsLikeF: 70, windMph: 5, category: .clear, recordDate: Date(), kind: .hourly)
        b.stops[3].weather = WeatherSnapshot(temperatureF: 80, feelsLikeF: 80, windMph: 5, category: .clear, recordDate: Date(), kind: .hourly)
        let near3 = Coordinate(lat: b.stops[3].coordinate.lat + 0.01, lon: b.stops[3].coordinate.lon)
        #expect(b.nearestForecastStop(to: near3)?.id == b.stops[3].id)
        // Stop 2 has no weather, so a point next to it resolves to whichever forecast stop is nearest.
        let near2 = b.stops[2].coordinate
        #expect([b.stops[1].id, b.stops[3].id].contains(b.nearestForecastStop(to: near2)?.id ?? UUID()))
        var none = b
        for i in none.stops.indices { none.stops[i].weather = nil }
        #expect(none.nearestForecastStop(to: near2) == nil)
    }

    @Test func recentLocationsMRU() {
        var r = RecentLocations.remember(["Denver, CO", "Dallas, TX"], into: [])
        #expect(r == ["Dallas, TX", "Denver, CO"])
        r = RecentLocations.remember(["denver, co", "  "], into: r)
        #expect(r == ["denver, co", "Dallas, TX"])
        let many = (0..<20).map { "Place \($0)" }
        r = RecentLocations.remember(many, into: r)
        #expect(r.count == 12 && r.first == "Place 19")
    }

    @Test func vehicleRules() {
        #expect(Vehicle.defaults.map(\.rangeMi) == [300, 180, 250])
        #expect(Vehicle.defaults.map(\.isEV) == [false, false, true])
        #expect(Vehicle.clampRange(5) == 20 && Vehicle.clampRange(900) == 800 && Vehicle.clampRange(.nan) == 20)
        #expect(Vehicle.slugID(for: "Tesla Model Y!") == "veh-tesla-model-y-")
        #expect(Vehicle.slugID(for: "F-150") == "veh-f-150")
    }

    @Test func placeShortLabel() {
        #expect(PlacePoint(query: "q", label: "Amarillo, TX, USA", coordinate: Coordinate(lat: 0, lon: 0)).shortLabel == "Amarillo")
        #expect(PlacePoint(query: "q", label: "Nowhere", coordinate: Coordinate(lat: 0, lon: 0)).shortLabel == "Nowhere")
    }

    @Test func briefingCodableRoundTrip() throws {
        var b = briefing()
        b.stops[1].weather = WeatherSnapshot(temperatureF: 70, feelsLikeF: 68, humidityPercent: 40, windMph: 12, windFromDegrees: 200, cloudPercent: 30, conditionRaw: "partlyCloudy", conditionText: "Partly cloudy", category: .partlyCloudy, recordDate: Date(timeIntervalSince1970: 1_781_100_000), precipitationChance: 0.2, kind: .hourly, fetchedAt: Date(timeIntervalSince1970: 1_781_096_400))
        b.stops[1].alerts = [WeatherAlert(id: "a", event: "Heat Advisory", severity: .moderate)]
        let data = try JSONEncoder().encode(b)
        let back = try JSONDecoder().decode(Briefing.self, from: data)
        #expect(back == b)
    }
}
