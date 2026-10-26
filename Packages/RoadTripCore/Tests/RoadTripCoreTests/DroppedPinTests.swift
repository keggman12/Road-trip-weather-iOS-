import Foundation
import Testing
@testable import RoadTripCore

@Suite("Dropped pins (map via-points)")
struct DroppedPinTests {
    static let thornton = Coordinate(lat: 39.87, lon: -104.99)
    static let amarillo = Coordinate(lat: 35.22, lon: -101.83)
    static let dallas = Coordinate(lat: 32.78, lon: -96.80)

    @Test func queryRoundTripsThroughTheParser() throws {
        let c = Coordinate(lat: 38.054123, lon: -104.987614)
        let q = DroppedPin.query(for: c)
        #expect(q == "38.05412, -104.98761")
        let back = try #require(DroppedPin.coordinate(fromQuery: q))
        #expect(abs(back.lat - c.lat) < 1e-5 && abs(back.lon - c.lon) < 1e-5)
    }

    @Test func parsesTypedCoordinatesAndRejectsPlaceNames() {
        #expect(DroppedPin.coordinate(fromQuery: " 35.2 ,-101.83 ") == Coordinate(lat: 35.2, lon: -101.83))
        #expect(DroppedPin.coordinate(fromQuery: "Amarillo, TX") == nil)
        #expect(DroppedPin.coordinate(fromQuery: "Amarillo") == nil)
        #expect(DroppedPin.coordinate(fromQuery: "35.2, -101.83, 4") == nil)
        #expect(DroppedPin.coordinate(fromQuery: "95, 10") == nil, "latitude out of range")
        #expect(DroppedPin.coordinate(fromQuery: "35, 181") == nil, "longitude out of range")
        #expect(DroppedPin.coordinate(fromQuery: "nan, 10") == nil)
    }

    @Test func labelsByNearestTownElseCoordinate() {
        let c = Coordinate(lat: 38.05412, lon: -104.98761)
        #expect(DroppedPin.label(near: "Rye", state: "CO", coordinate: c) == "Pin near Rye, CO")
        #expect(DroppedPin.label(near: "Rye", state: nil, coordinate: c) == "Pin near Rye")
        #expect(DroppedPin.label(near: " ", state: "CO", coordinate: c) == "Pin 38.054° -104.988°")
        #expect(PlacePoint(query: "", label: "Pin near Rye, CO", coordinate: c).shortLabel == "Pin near Rye")
    }

    @Test func insertsBetweenThePointsItDetoursLeast() {
        // No vias: the only gap.
        #expect(DroppedPin.insertionIndex(of: Coordinate(lat: 38, lon: -104), origin: Self.thornton, vias: [], destination: Self.dallas) == 0)
        // Pueblo-ish lies between Thornton and Amarillo; Wichita Falls-ish after Amarillo.
        let vias = [Self.amarillo]
        #expect(DroppedPin.insertionIndex(of: Coordinate(lat: 38.25, lon: -104.61), origin: Self.thornton, vias: vias, destination: Self.dallas) == 0)
        #expect(DroppedPin.insertionIndex(of: Coordinate(lat: 33.91, lon: -98.49), origin: Self.thornton, vias: vias, destination: Self.dallas) == 1)
    }
}
