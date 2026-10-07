import Foundation

/// ETA, dwell and overnight arithmetic (web `computeEtas`, `nextResumeEpoch`,
/// `assignTravelBearings`).
///
/// Deviation from the web, on purpose: the web evaluated the resume time
/// ("08:00") in the browser's time zone. Here it is evaluated in the stop's
/// own zone (`Stop.timeZoneID`, falling back to `fallbackTimeZone`), which is
/// what "resume at 8 in the morning" means to someone who slept there.
public enum ETACalculator {
    /// Recomputes `eta`, `legMi`, `autoOvernight`/`resume` for every stop in
    /// place. Stops are sorted by `distanceMi` first. Returns the final arrival.
    @discardableResult
    public static func computeETAs(
        stops: inout [Stop],
        totalMi: Double,
        durationSec: Double,
        departure: Date,
        multiDay: MultiDayOptions,
        fallbackTimeZone: TimeZone,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> Date {
        stops.sort { $0.distanceMi < $1.distanceMi }
        var t = departure
        var driveToday: TimeInterval = 0
        let n = stops.count
        for i in 0..<n {
            let isLast = i == n - 1
            if i == 0 {
                stops[i].eta = departure
                stops[i].legMi = 0
                stops[i].autoOvernight = false
                stops[i].resume = nil
                continue
            }
            let legMi = stops[i].distanceMi - stops[i - 1].distanceMi
            stops[i].legMi = legMi
            let segFrac = totalMi > 0 ? legMi / totalMi : 0
            let segSec = durationSec * segFrac
            t = t.addingTimeInterval(segSec)
            driveToday += segSec
            stops[i].eta = t
            stops[i].autoOvernight = false
            stops[i].resume = nil
            if isLast { continue }
            t = t.addingTimeInterval(TimeInterval(stops[i].dwellMinutes * 60))
            if multiDay.enabled, driveToday >= multiDay.maxDriveSeconds {
                stops[i].autoOvernight = true
            }
            if stops[i].manualOvernight || stops[i].autoOvernight {
                let tz = stops[i].timeZone(fallback: fallbackTimeZone)
                let resume = nextResume(after: t, at: multiDay.resumeTime, in: tz, calendar: calendar)
                stops[i].resume = resume
                t = resume
                driveToday = 0
            }
        }
        return t
    }

    /// The next calendar day's `time`, strictly after `date`, in `timeZone`
    /// (web `nextResumeEpoch`: tomorrow at HH:mm, then step forward by a day
    /// while not after `t`).
    public static func nextResume(after date: Date, at time: TimeOfDay, in timeZone: TimeZone, calendar base: Calendar = Calendar(identifier: .gregorian)) -> Date {
        var cal = base
        cal.timeZone = timeZone
        guard let tomorrow = cal.date(byAdding: .day, value: 1, to: date) else {
            return date.addingTimeInterval(86_400)
        }
        var comps = cal.dateComponents([.year, .month, .day], from: tomorrow)
        comps.hour = time.hour
        comps.minute = time.minute
        comps.second = 0
        guard var resume = cal.date(from: comps) else {
            return date.addingTimeInterval(86_400)
        }
        var guardCount = 0
        while resume <= date, guardCount < 3 {
            resume = cal.date(byAdding: .day, value: 1, to: resume) ?? resume.addingTimeInterval(86_400)
            guardCount += 1
        }
        return resume
    }

    /// Bearing of travel at each stop: toward the next stop, or for the last
    /// stop the bearing from the previous one (web `assignTravelBearings`).
    public static func assignTravelBearings(stops: inout [Stop]) {
        let n = stops.count
        for i in 0..<n {
            if i + 1 < n {
                stops[i].travelBearing = Geo.bearingDegrees(from: stops[i].coordinate, to: stops[i + 1].coordinate)
            } else if i - 1 >= 0 {
                stops[i].travelBearing = Geo.bearingDegrees(from: stops[i - 1].coordinate, to: stops[i].coordinate)
            } else {
                stops[i].travelBearing = nil
            }
        }
    }

    /// Convenience: recompute ETAs and bearings on a briefing after any stop
    /// mutation (web `onStopsMutated`).
    public static func recompute(_ briefing: inout Briefing, fallbackTimeZone: TimeZone) {
        computeETAs(
            stops: &briefing.stops,
            totalMi: briefing.totalMi,
            durationSec: briefing.geometry.durationSec,
            departure: briefing.departure,
            multiDay: briefing.multiDay,
            fallbackTimeZone: fallbackTimeZone
        )
        assignTravelBearings(stops: &briefing.stops)
    }
}
