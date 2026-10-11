import Foundation
import Testing
@testable import RoadTripCore

@Suite("TripScorer / DepartureCandidates (web scoreStops / runOptimizer)")
struct ScoringTests {
    let ref = WebReference.shared
    let origin = Coordinate(lat: 0, lon: 0)

    func stop(_ temp: Int, _ pop: Double?, _ cat: ConditionCategory, _ wind: Int, alerts: Int = 0) -> Stop {
        let w = WeatherSnapshot(temperatureF: temp, feelsLikeF: temp, windMph: wind, category: cat, recordDate: Date(), precipitationChance: pop, kind: .hourly)
        let a = (0..<alerts).map { WeatherAlert(id: "a\($0)", event: "x") }
        return Stop(kind: .sampled, label: "s", coordinate: origin, routeIndex: 0, distanceMi: 0, weather: w, alerts: a)
    }

    var webInput: [Stop] {
        [
            stop(65, 0, .clear, 5),
            stop(72, 0.3, .rain, 18),
            Stop(kind: .sampled, label: "no weather", coordinate: origin, routeIndex: 0, distanceMi: 0),
            stop(40, 0.9, .thunderstorm, 25, alerts: 1),
            stop(95, nil, .mostlyCloudy, 10),
            stop(55, 0.5, .snow, 0),
        ]
    }

    @Test func scoreMatchesWeb() {
        let r = TripScorer.score(webInput)
        #expect(r.score == ref.score.score)
        #expect(r.worstStopIndex == ref.score.worstIdx)
        #expect(approx(r.worstPenalty ?? -1, ref.score.worstP, tolerance: 1e-9))
    }

    @Test func perStopPenaltyComponents() {
        // 72°F, pop .3, rain, 18 mph: 12 + 12 + 2.1 + 6.4 = 32.5
        #expect(approx(TripScorer.penalty(for: stop(72, 0.3, .rain, 18)) ?? -1, 32.5, tolerance: 1e-9))
        // Alerts add 40.
        #expect(approx(TripScorer.penalty(for: stop(65, 0, .clear, 0, alerts: 2)) ?? -1, 40, tolerance: 1e-9))
        // Missing weather → nil.
        #expect(TripScorer.penalty(for: webInput[2]) == nil)
    }

    @Test func emptyAndUnknown() {
        let e = TripScorer.score([])
        #expect(e.score == ref.scoreEmpty.score && e.worstStopIndex == nil)
        let u = TripScorer.score([webInput[2], webInput[2], webInput[2]])
        #expect(u.score == ref.scoreAllUnknown)
        #expect(u.worstStopIndex == nil)
    }

    @Test func roundingMatchesJavaScript() {
        #expect(TripScorer.score([stop(66, 0.0125, .clear, 10)]).score == ref.scoreRounding)
    }

    @Test func nearLabelRule() {
        var s = stop(60, 0, .clear, 0)
        s.label = "Waypoint 3"; s.distanceMi = 212.6
        #expect(TripScorer.nearLabel(for: s) == "mi 213")
        s.label = "Amarillo, TX, USA"
        #expect(TripScorer.nearLabel(for: s) == "Amarillo")
    }

    @Test func candidateCountMatchesWeb() {
        let start = Date(timeIntervalSince1970: 1_781_096_400)
        for c in ref.candidates {
            let end = start.addingTimeInterval(c.spanH * 3600)
            #expect(DepartureCandidates.count(windowStart: start, windowEnd: end, routeCount: c.r) == c.n, "span \(c.spanH) routes \(c.r)")
        }
    }

    @Test func candidatesAreEvenlySpacedInclusive() {
        let start = Date(timeIntervalSince1970: 1_781_096_400)
        let end = start.addingTimeInterval(10 * 3600)
        let c = DepartureCandidates.candidates(windowStart: start, windowEnd: end, routeCount: 1)
        #expect(c.count == 5)
        #expect(c.first == start && c.last == end)
        #expect(c[1].timeIntervalSince(c[0]) == 2.5 * 3600)
        #expect(DepartureCandidates.candidates(windowStart: end, windowEnd: start, routeCount: 1).isEmpty)
    }
}
