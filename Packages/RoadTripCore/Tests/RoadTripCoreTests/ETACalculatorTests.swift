import Foundation
import Testing
@testable import RoadTripCore

@Suite("ETACalculator (web computeEtas / nextResumeEpoch)")
struct ETACalculatorTests {
    let ref = WebReference.shared
    /// The reference run used TZ=UTC for the browser, departure 2026-06-10 13:00Z.
    let departure = Date(timeIntervalSince1970: 1_781_096_400)
    let durationSec = 11.5 * 3600

    func stops(from sample: WebReference.Sample) -> [Stop] {
        let n = sample.waypoints.count
        return sample.waypoints.enumerated().map { i, w in
            let kind: StopKind = i == 0 ? .origin : (i == n - 1 ? .destination : .sampled)
            return Stop(kind: kind, label: "W\(i)", coordinate: Coordinate(lat: w.lat, lon: w.lon), routeIndex: w.routeIndex, distanceMi: w.distanceMi)
        }
    }

    @Test func singleDayETAsAndBearingsMatchWeb() {
        var s = stops(from: ref.sample300)
        let arrival = ETACalculator.computeETAs(stops: &s, totalMi: ref.sample300.totalMi, durationSec: durationSec, departure: departure, multiDay: .off, fallbackTimeZone: utc)
        ETACalculator.assignTravelBearings(stops: &s)
        #expect(s.count == ref.eta300.count)
        for (got, want) in zip(s, ref.eta300) {
            #expect(approx(got.eta.timeIntervalSince1970, want.etaEpoch, tolerance: 1e-3))
            #expect(approx(got.legMi, want.legMi ?? -1, tolerance: 1e-9))
            #expect(got.isOvernight == want.overnight)
            #expect(got.resume == nil)
            if let tb = want.travelBearing { #expect(approx(got.travelBearing ?? -1, tb, tolerance: 1e-9)) }
        }
        // Final arrival = departure + drive + dwell at the one interior stop.
        #expect(approx(arrival.timeIntervalSince1970, ref.eta300[2].etaEpoch, tolerance: 1e-3))
        #expect(approx(arrival.timeIntervalSince(departure), durationSec + 15 * 60, tolerance: 1e-3))
    }

    @Test func multiDayAutoOvernightMatchesWeb() {
        var s = stops(from: ref.sample180)
        s[2].dwellMinutes = 45
        let md = MultiDayOptions(enabled: true, maxDriveHours: 6, resumeTime: TimeOfDay(hhmm: "08:30"))
        ETACalculator.computeETAs(stops: &s, totalMi: ref.sample180.totalMi, durationSec: durationSec, departure: departure, multiDay: md, fallbackTimeZone: utc)
        for (got, want) in zip(s, ref.eta180multiday) {
            #expect(approx(got.eta.timeIntervalSince1970, want.etaEpoch, tolerance: 1e-3))
            #expect(got.isOvernight == want.overnight)
            #expect(got.autoOvernight == (want.autoOvernight ?? false))
            if let r = want.resumeEpoch {
                #expect(approx(got.resume?.timeIntervalSince1970 ?? -1, r, tolerance: 1e-3))
            } else {
                #expect(got.resume == nil)
            }
        }
    }

    @Test func manualOvernightMatchesWeb() {
        var s = stops(from: ref.sample300)
        s[1].manualOvernight = true
        let md = MultiDayOptions(enabled: false, resumeTime: TimeOfDay(hhmm: "07:15"))
        ETACalculator.computeETAs(stops: &s, totalMi: ref.sample300.totalMi, durationSec: durationSec, departure: departure, multiDay: md, fallbackTimeZone: utc)
        for (got, want) in zip(s, ref.eta300manual) {
            #expect(approx(got.eta.timeIntervalSince1970, want.etaEpoch, tolerance: 1e-3))
            #expect(got.isOvernight == want.overnight)
            if let r = want.resumeEpoch { #expect(approx(got.resume?.timeIntervalSince1970 ?? -1, r, tolerance: 1e-3)) }
        }
    }

    @Test func resumeUsesStopTimeZone() {
        // Arrive 22:00 Mountain (04:00Z next day). Resume "08:00" must be 08:00 Mountain, not UTC.
        let denverTZ = TimeZone(identifier: "America/Denver") ?? utc
        let arrive = Date(timeIntervalSince1970: 1_781_150_400) // 2026-06-11 04:00:00Z = 22:00 MDT Jun 10
        let resume = ETACalculator.nextResume(after: arrive, at: TimeOfDay(hour: 8, minute: 0), in: denverTZ)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = denverTZ
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute], from: resume)
        #expect(c.month == 6 && c.day == 11 && c.hour == 8 && c.minute == 0)
        // And strictly after the arrival.
        #expect(resume > arrive)
    }

    @Test func resumeIsStrictlyAfterWhenTomorrowAtTimeIsNotLater() {
        // Arrive 2026-06-10 23:30Z; "tomorrow 08:00" is after, so a single step.
        let late = Date(timeIntervalSince1970: 1_781_134_200)
        let r1 = ETACalculator.nextResume(after: late, at: TimeOfDay(hour: 8, minute: 0), in: utc)
        #expect(r1.timeIntervalSince1970 == 1_781_164_800) // 2026-06-11 08:00Z
        // Arrive 2026-06-10 03:00Z: tomorrow 08:00 is still the next day (web always moves to tomorrow first).
        let early = Date(timeIntervalSince1970: 1_781_060_400)
        let r2 = ETACalculator.nextResume(after: early, at: TimeOfDay(hour: 8, minute: 0), in: utc)
        #expect(r2.timeIntervalSince1970 == 1_781_164_800)
    }

    @Test func sortsByDistanceBeforeComputing() {
        var s = stops(from: ref.sample180)
        s.reverse()
        ETACalculator.computeETAs(stops: &s, totalMi: ref.sample180.totalMi, durationSec: durationSec, departure: departure, multiDay: .off, fallbackTimeZone: utc)
        #expect(s.map(\.distanceMi) == s.map(\.distanceMi).sorted())
        #expect(s.first?.eta == departure)
    }

    @Test func dwellChangeShiftsLaterStopsOnly() {
        var a = stops(from: ref.sample180)
        ETACalculator.computeETAs(stops: &a, totalMi: ref.sample180.totalMi, durationSec: durationSec, departure: departure, multiDay: .off, fallbackTimeZone: utc)
        var b = a
        b[2].dwellMinutes += 30
        ETACalculator.computeETAs(stops: &b, totalMi: ref.sample180.totalMi, durationSec: durationSec, departure: departure, multiDay: .off, fallbackTimeZone: utc)
        #expect(b[1].eta == a[1].eta && b[2].eta == a[2].eta)
        #expect(approx(b[3].eta.timeIntervalSince(a[3].eta), 1800, tolerance: 1e-6))
        #expect(approx(b[4].eta.timeIntervalSince(a[4].eta), 1800, tolerance: 1e-6))
    }

    @Test func multiDayClampsAndParses() {
        #expect(MultiDayOptions(maxDriveHours: 1).maxDriveHours == 2)
        #expect(MultiDayOptions(maxDriveHours: 99).maxDriveHours == 20)
        #expect(MultiDayOptions(maxDriveHours: .nan).maxDriveHours == 10)
        #expect(TimeOfDay(hhmm: "08:30") == TimeOfDay(hour: 8, minute: 30))
        #expect(TimeOfDay(hhmm: "x:y") == TimeOfDay(hour: 0, minute: 0))
        #expect(TimeOfDay(hhmm: "7").hhmm == "07:00")
    }

    @Test func pausedSecondsCountsDwellAndOvernightGaps() {
        var s = stops(from: ref.sample180)
        s[2].dwellMinutes = 45
        let md = MultiDayOptions(enabled: true, maxDriveHours: 6, resumeTime: TimeOfDay(hhmm: "08:30"))
        ETACalculator.computeETAs(stops: &s, totalMi: ref.sample180.totalMi, durationSec: durationSec, departure: departure, multiDay: md, fallbackTimeZone: utc)
        let geometry = RouteGeometry(coordinates: ref.routeCoordinates, distanceMi: 663, durationSec: durationSec)
        let b = Briefing(routeIndex: 0, geometry: geometry, totalMi: ref.sample180.totalMi, departure: departure, rangeMi: 180, multiDay: md, stops: s)
        // dwell: 15 + 45 + 15 = 75 min; overnight gap at stop 2: resume − (eta + 45 min)
        let gap = (s[2].resume ?? departure).timeIntervalSince(s[2].eta.addingTimeInterval(45 * 60))
        #expect(approx(b.pausedSeconds, 75 * 60 + gap, tolerance: 1e-6))
        #expect(b.summary?.overnightCount == 1)
        #expect(b.summary?.arrival == s.last?.eta)
    }
}
