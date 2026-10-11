import Foundation
import Testing
@testable import RoadTripCore

@Suite("TemperatureScale (web DEFAULT_SCALE / colorForTemp)")
struct TemperatureScaleTests {
    let scale = TemperatureScale.default

    @Test func defaultBands() {
        #expect(scale.bands.map(\.label) == ["Cold", "Cool", "Mild", "Warm", "Hot"])
        #expect(scale.bands.map(\.upperBound) == [48, 58, 68, 83, nil])
        #expect(scale.bands.map(\.colorHex) == ["#3b82f6", "#22c55e", "#eab308", "#f97316", "#ef4444"])
    }

    @Test func colorUsesStrictLessThan() {
        #expect(scale.colorHex(forTemperatureF: -20) == "#3b82f6")
        #expect(scale.colorHex(forTemperatureF: 47.9) == "#3b82f6")
        #expect(scale.colorHex(forTemperatureF: 48) == "#22c55e")
        #expect(scale.colorHex(forTemperatureF: 57.99) == "#22c55e")
        #expect(scale.colorHex(forTemperatureF: 58) == "#eab308")
        #expect(scale.colorHex(forTemperatureF: 68) == "#f97316")
        #expect(scale.colorHex(forTemperatureF: 82) == "#f97316")
        #expect(scale.colorHex(forTemperatureF: 83) == "#ef4444")
        #expect(scale.colorHex(forTemperatureF: 120) == "#ef4444")
    }

    @Test func unknownTemperature() {
        #expect(scale.colorHex(forTemperatureF: nil) == TemperatureScale.unknownColorHex)
        #expect(scale.colorHex(forTemperatureF: .nan) == TemperatureScale.unknownColorHex)
        #expect(scale.band(forTemperatureF: nil) == nil)
        #expect(scale.band(forTemperatureF: 90)?.label == "Hot")
    }

    @Test func segmentTemperatureRule() {
        #expect(TemperatureScale.segmentTemperature(60, 70) == 65)
        #expect(TemperatureScale.segmentTemperature(60, nil) == 60)
        #expect(TemperatureScale.segmentTemperature(nil, 70) == 70)
        #expect(TemperatureScale.segmentTemperature(nil, nil) == nil)
    }

    @Test func normalizedFixesNonMonotonicBounds() {
        var s = scale
        s.bands[1].upperBound = 40   // ≤ previous 48 → becomes 49
        s.bands[2].upperBound = 49   // ≤ 49 → becomes 50
        s.bands[4].upperBound = 500  // last is always open
        let n = s.normalized()
        #expect(n.bands.map(\.upperBound) == [48, 49, 50, 83, nil])
    }

    @Test func normalizedKeepsValidScale() {
        #expect(scale.normalized() == scale)
    }

    @Test func legendLabels() {
        #expect(scale.legendLabels() == ["< 48°", "48–58°", "58–68°", "68–83°", "83°+"])
    }

    @Test func codableRoundTripKeepsOpenEnd() throws {
        let data = try JSONEncoder().encode(scale)
        let back = try JSONDecoder().decode(TemperatureScale.self, from: data)
        #expect(back == scale)
        #expect(back.bands.last?.upperBound == nil)
    }
}
