import Testing
@testable import RoadTripCore

@Suite("Place match and trip naming")
struct PlaceMatchTests {
    @Test(arguments: [
        ("Rotan, New Mexico", "Raton, NM", true),
        ("Thornton, Colorado", "Thornton, CO", false),
        ("Dallas, Texas", "Dallas, TX", false),
        ("Denver", "Denver, CO", false),
        ("Buc-ee's Amarillo", "Buc-ee's, Amarillo, TX", false),
        ("San Jose", "San José, CA", false),
        ("St. Louis", "St Louis, MO", false),
        ("Springfeild", "Springfield, IL", true),
    ])
    func mismatch(_ query: String, _ label: String, _ expected: Bool) {
        #expect(PlaceMatch.isLikelyMismatch(query: query, label: label) == expected)
    }

    @Test func names() {
        #expect(TripNaming.defaultName(origin: "Thornton", vias: [], destination: "Dallas") == "Thornton → Dallas")
        #expect(TripNaming.defaultName(origin: "Thornton", vias: ["Rotan"], destination: "Dallas") == "Thornton → Dallas via Rotan")
        #expect(TripNaming.defaultName(origin: "A", vias: ["B", "C"], destination: "D") == "A → D via B · C")
    }
}

@Suite("Stop naming")
struct StopNamingTests {
    @Test func labels() {
        #expect(StopNaming.label(road: "I-25", town: "Pueblo", county: "Pueblo County", state: "CO") == "I-25 near Pueblo, CO")
        #expect(StopNaming.label(road: "Main St", town: "Pueblo", county: nil, state: "CO") == "near Pueblo, CO")
        #expect(StopNaming.label(road: nil, town: nil, county: "Fisher County", state: "TX") == "near Fisher County, TX")
        #expect(StopNaming.label(road: "US-287", town: nil, county: nil, state: nil) == "US-287")
        #expect(StopNaming.label(road: nil, town: nil, county: nil, state: nil) == nil)
    }

    @Test func genericRestAreaNames() {
        #expect(StopNaming.isGeneric("Rest Area", kind: .rest))
        #expect(!StopNaming.isGeneric("Raton Pass Welcome Center", kind: .rest))
        #expect(!StopNaming.isGeneric("Rest Area", kind: .loves))
    }
}
