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
