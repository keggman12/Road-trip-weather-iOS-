import Foundation
import RoadTripCore
import SwiftData
import Testing
@testable import RoadTripWeather

/// Owner-reported issues: a new search saved under (and over) the previous
/// trip; a misspelled via-point silently resolved elsewhere.
@Suite("Save naming and place checks", .serialized)
@MainActor
struct SaveNamingTests {
    let net = FakeNetwork()

    private func makeCoordinator(geocoder: any GeocodingService) throws -> BriefingCoordinator {
        let env = AppEnvironment(
            container: try AppSchema.makeContainer(inMemory: true),
            settings: AppSettings(defaults: UserDefaults(suiteName: "SaveNamingTests-\(UUID().uuidString)") ?? .standard),
            geocoding: geocoder,
            routing: FakeRouting(net: net, through: nil),
            timeZones: MockTimeZoneService(),
            weather: FakeWeather(net: net),
            alerts: FakeAlerts(net: net),
            chargers: MockChargerService(),
            refresher: nil,
            isPreview: true
        )
        return BriefingCoordinator(env: env)
    }

    private func search(_ c: BriefingCoordinator, _ origin: String, _ vias: [String], _ dest: String) async {
        c.plan.originText = origin
        c.plan.viaTexts = vias
        c.plan.destinationText = dest
        await c.findRoutes()
        await c.generateBriefing()
    }

    @Test func secondSearchSavesAsANewTripWithItsOwnName() async throws {
        let c = try makeCoordinator(geocoder: FakeGeocoding(net: net))
        await search(c, "Denver", [], "Dallas")
        #expect(c.suggestedTripName == "Denver → Dallas")
        try c.save(name: c.suggestedTripName)

        await search(c, "Denver", ["Amarillo"], "Dallas")
        #expect(c.loadedTrip == nil, "new search detaches from the saved trip")
        #expect(c.suggestedTripName == "Denver → Dallas via Amarillo")
        try c.save(name: c.suggestedTripName)

        let names = c.env.trips.allTrips().map(\.name).sorted()
        #expect(names == ["Denver → Dallas", "Denver → Dallas via Amarillo"], "first trip not overwritten")
    }

    @Test func reFindingALoadedTripKeepsItLinked() async throws {
        let c = try makeCoordinator(geocoder: FakeGeocoding(net: net))
        await search(c, "Denver", ["Amarillo"], "Dallas")
        try c.save(name: "Spring break")
        let trip = try #require(c.env.trips.allTrips().first)
        c.load(trip)
        await c.findRoutes()
        await c.generateBriefing()
        #expect(c.loadedTrip?.name == "Spring break")
        #expect(c.suggestedTripName == "Spring break")
        try c.save(name: "Spring break")
        #expect(c.env.trips.allTrips().count == 1, "updates in place")
        try c.save(name: "Spring break 2", asNew: true)
        #expect(c.env.trips.allTrips().count == 2)
    }

    @Test func misspelledViaIsFlagged() async throws {
        let c = try makeCoordinator(geocoder: RatonGeocoder())
        c.plan.originText = "Thornton, Colorado"
        c.plan.viaTexts = ["Rotan, New Mexico"]
        c.plan.destinationText = "Dallas, Texas"
        await c.findRoutes()
        #expect(c.placeNotices == ["“Rotan, New Mexico” matched Raton, NM, USA — check the spelling or add the state."])
        #expect(c.routeNote?.contains("Raton") == true, "also shown on the Routes screen")
        #expect(c.routes.first?.label == "via Raton", "via route still listed and selected first")
        #expect(c.selectedRouteIndex == 0)

        c.plan.viaTexts = ["Rotan, TX"]
        await c.findRoutes()
        #expect(c.placeNotices.isEmpty)
    }
}

/// Resolves like Apple's geocoder did for the owner's trip.
struct RatonGeocoder: GeocodingService {
    func geocode(_ query: String) async throws -> PlacePoint {
        let q = query.lowercased()
        func p(_ label: String, _ lat: Double, _ lon: Double) -> PlacePoint {
            PlacePoint(query: query, label: label, coordinate: Coordinate(lat: lat, lon: lon), timeZoneID: lon < -102 ? "America/Denver" : "America/Chicago")
        }
        if q.hasPrefix("thornton") { return p("Thornton, CO, USA", 39.869, -104.985) }
        if q.hasPrefix("dallas") { return p("Dallas, TX, USA", 32.776, -96.796) }
        if q.contains("new mexico") { return p("Raton, NM, USA", 36.905, -104.440) }
        if q.hasPrefix("rotan") { return p("Rotan, TX, USA", 32.851, -100.469) }
        throw ServiceError.notFound(query)
    }
}
