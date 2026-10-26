import Foundation
import RoadTripCore

/// Everything the Plan screen collects (web form state + `currentTripData`).
struct TripPlan: Hashable, Codable, Sendable {
    var originText: String = ""
    var destinationText: String = ""
    /// Via-point rows. Each has a stable ID so the Plan form never binds a
    /// row by position (a removed row once crashed the form, issue #2).
    var viaEntries: [ViaEntry] = []
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

    // `viaEntries` keeps the old "viaTexts" key (a plain string array) so
    // saved sessions still decode.
    enum CodingKeys: String, CodingKey {
        case originText, destinationText, origin, destination, vias
        case viaEntries = "viaTexts"
        case departure, departureTimeZoneID, vehicleID, rangeMi, multiDay, stopEdits
    }

    /// The via-point texts in order.
    var viaTexts: [String] {
        get { viaEntries.map(\.text) }
        set { viaEntries = newValue.map { ViaEntry(text: $0) } }
    }

    /// Web `defaultDeparture`: next full hour.
    static func defaultDeparture(now: Date = Date(), timeZone: TimeZone = .current) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let plusHour = now.addingTimeInterval(3600)
        return cal.dateInterval(of: .hour, for: plusHour)?.start ?? plusHour
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

/// One via-point row on the Plan screen. Encodes as its text alone; the ID
/// only lives for the session.
struct ViaEntry: Identifiable, Hashable, Codable, Sendable {
    var id = UUID()
    var text: String

    init(text: String) { self.text = text }

    init(from decoder: Decoder) throws {
        text = try decoder.singleValueContainer().decode(String.self)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(text)
    }
}
