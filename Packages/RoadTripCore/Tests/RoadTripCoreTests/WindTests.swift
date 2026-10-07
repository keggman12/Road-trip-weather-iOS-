import Foundation
import Testing
@testable import RoadTripCore

@Suite("Wind (web util.js wind section)")
struct WindTests {
    let ref = WebReference.shared

    @Test func relativeCompassAndRotationMatchWeb() {
        for w in ref.wind {
            let rel = Wind.relative(windFrom: w.w, travelBearing: w.t)
            #expect(rel?.rawValue == w.rel, "wind \(w.w) travel \(w.t)")
            #expect(Wind.compass(degrees: w.w) == w.compass, "compass \(w.w)")
            #expect(Wind.arrowRotation(windFrom: w.w) == w.rot, "rotation \(w.w)")
        }
    }

    @Test func compassEveryTenDegrees() {
        for entry in ref.compassAll {
            guard entry.count == 2, case let .degrees(d) = entry[0], case let .label(l) = entry[1] else { continue }
            #expect(Wind.compass(degrees: d) == l, "compass \(d)")
        }
        for entry in ref.compassEdge {
            guard entry.count == 2, case let .degrees(d) = entry[0], case let .label(l) = entry[1] else { continue }
            #expect(Wind.compass(degrees: d) == l, "compass edge \(d)")
        }
    }

    @Test func nilInputs() {
        #expect(Wind.relative(windFrom: nil, travelBearing: 90) == nil)
        #expect(Wind.relative(windFrom: 90, travelBearing: nil) == nil)
        #expect(Wind.compass(degrees: nil) == "")
        #expect(Wind.arrowRotation(windFrom: nil) == 0)
    }

    @Test func boundaries() {
        // Travel north (0). Wind from 180 blows toward 0 → diff 0 → tail.
        #expect(Wind.relative(windFrom: 180, travelBearing: 0) == .tail)
        // Wind from 135 blows toward 315: diff 45 → tail (inclusive).
        #expect(Wind.relative(windFrom: 135, travelBearing: 0) == .tail)
        // Wind from 45 blows toward 225: diff 135 → head (inclusive).
        #expect(Wind.relative(windFrom: 45, travelBearing: 0) == .head)
        // Wind from 90 blows toward 270: diff 90 → cross.
        #expect(Wind.relative(windFrom: 90, travelBearing: 0) == .cross)
    }

    @Test func rotationWrapsNegativeAndLarge() {
        #expect(Wind.arrowRotation(windFrom: 370) == 10)
        #expect(Wind.arrowRotation(windFrom: -10) == 350)
        #expect(Wind.arrowRotation(windFrom: 359.6) == 360)
    }

    @Test func chipLabels() {
        #expect(RelativeWind.head.chipLabel == "headwind")
        #expect(RelativeWind.tail.chipLabel == "tailwind")
        #expect(RelativeWind.cross.chipLabel == "x-wind")
    }
}
