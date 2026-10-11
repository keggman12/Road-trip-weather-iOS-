import Foundation
import RoadTripCore

/// Everything the Plan screen collects (web form state + `currentTripData`).
struct TripPlan: Hashable, Codable, Sendable {
    var originText: String = ""
    var destinationText: String = ""
    var viaTexts: [String] = []
    var origin: PlacePoint?
    var destination: PlacePoint?
    var vias: [PlacePoint] = []
    /// Interpreted in `departureTimeZoneID` (the origin's zone once geocoded).
    var departure: Date = TripPlan.defaultDeparture()
    var departureTimeZoneID: String?
    var vehicleID: String?
    var rangeMi: Double = 300
    var multiDay: MultiDayOptions = .off
    var stopEdits: StopEdits = StopEdits()

    /// Web `defaultDeparture`: next full hour.
    static func defaultDeparture(now: Date = Date()) -> Date {
        let cal = Calendar.current
        let plusHour = now.addingTimeInterval(3600)
        var comps = cal.dateComponents([.year, .month, .day, .hour], from: plusHour)
        comps.minute = 0
        comps.second = 0
        return cal.date(from: comps) ?? plusHour
    }

    var departureTimeZone: TimeZone {
        departureTimeZoneID.flatMap(TimeZone.init(identifier:)) ?? .current
    }

    /// Ordered points for routing: origin, vias…, destination.
    var routingPoints: [PlacePoint]? {
        guard let origin, let destination else { return nil }
        return [origin] + vias + [destination]
    }

    /// Web default trip name "Origin → Dest".
    var defaultName: String {
        let o = origin?.shortLabel ?? originText.split(separator: ",").first.map(String.init) ?? "Origin"
        let d = destination?.shortLabel ?? destinationText.split(separator: ",").first.map(String.init) ?? "Destination"
        return TripNaming.defaultName(origin: o, vias: vias.map(\.shortLabel), destination: d)
    }
}
