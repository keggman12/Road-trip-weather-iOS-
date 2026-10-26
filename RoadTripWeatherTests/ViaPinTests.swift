import Foundation
import RoadTripCore
import Testing
@testable import RoadTripWeather

@Suite("Dropped-pin via-points", .serialized)
@MainActor
struct ViaPinTests {
    let net = FakeNetwork()

    private func coordinator(defaults: UserDefaults? = nil) throws -> BriefingCoordinator {
        let env = AppEnvironment(
            container: try AppSchema.makeContainer(inMemory: true),
            settings: AppSettings(defaults: defaults ?? UserDefaults(suiteName: "ViaPin-\(UUID().uuidString)") ?? .standard),
            geocoding: FakeGeocoding(net: net), routing: FakeRouting(net: net, through: nil), timeZones: PinTownNamer(),
            weather: FakeWeather(net: net), alerts: FakeAlerts(net: net), chargers: MockChargerService(), refresher: nil, isPreview: true
        )
        let c = BriefingCoordinator(env: env)
        c.plan.originText = "Denver"
        c.plan.destinationText = "Dallas"
        return c
    }

    @Test func droppedPinRoutesThroughThatSpotWithoutGeocodingIt() async throws {
        let c = try coordinator()
        await c.findRoutes()
        let before = await net.snapshot()

        await c.addViaPin(at: PinSpots.nearPueblo)
        let query = DroppedPin.query(for: PinSpots.nearPueblo)
        #expect(c.plan.viaTexts == [query])
        let via = try #require(c.plan.vias.first)
        let expected = try #require(DroppedPin.coordinate(fromQuery: query))
        #expect(via.coordinate == expected)
        #expect(via.label == "Pin near Pueblo, CO")
        #expect(c.routes.first?.label == "via Pin near Pueblo")
        let calls = await net.snapshot() - before
        #expect(calls.geocode == 2, "origin and destination only")
        #expect(calls.route == 1)
        #expect(c.placeNotices.isEmpty, "a coordinate query is never a name mismatch")
        #expect(!c.env.settings.recentLocations.contains(query), "pins stay out of recents")
        #expect(c.errorMessage == nil && c.phase == .idle)
    }

    @Test func pinsSlotInBetweenThePointsTheyDetourLeast() async throws {
        let c = try coordinator()
        c.plan.viaTexts = ["Amarillo"]
        await c.findRoutes()

        await c.addViaPin(at: PinSpots.nearWichitaFalls)
        await c.addViaPin(at: PinSpots.nearPueblo)
        #expect(c.plan.viaTexts == [DroppedPin.query(for: PinSpots.nearPueblo), "Amarillo", DroppedPin.query(for: PinSpots.nearWichitaFalls)])
        #expect(c.plan.vias.map(\.shortLabel) == ["Pin near Pueblo", "Amarillo", "Pin near Wichita Falls"])
    }

    @Test func aRestoredPlanReroutesThroughThePinWithoutPickedPlaces() async throws {
        let c = try coordinator()
        await c.findRoutes()
        await c.addViaPin(at: PinSpots.nearPueblo)

        // A relaunch or saved trip: same plan, nothing picked this session.
        let restored = try coordinator()
        restored.plan = c.plan
        let before = await net.snapshot()
        await restored.findRoutes()
        #expect((await net.snapshot() - before).geocode == 2)
        #expect(restored.plan.vias.first?.label == "Pin near Pueblo, CO", "label kept from the plan")

        // Only the text survived (an old saved trip's plan): reverse geocoded again.
        let textOnly = try coordinator()
        textOnly.plan.viaTexts = c.plan.viaTexts
        await textOnly.findRoutes()
        #expect(textOnly.plan.vias.first?.label == "Pin near Pueblo, CO")
        #expect(textOnly.errorMessage == nil)
    }

    @Test func removingAPinReroutesWithoutIt() async throws {
        let c = try coordinator()
        await c.findRoutes()
        await c.addViaPin(at: PinSpots.nearPueblo)
        let query = DroppedPin.query(for: PinSpots.nearPueblo)

        await c.removeVia(query: query)
        #expect(c.plan.viaTexts.isEmpty)
        #expect(c.plan.vias.isEmpty)
        #expect(!c.routes.contains { $0.label?.hasPrefix("via ") == true })
    }

    @Test func aPinIsBriefedAsAStopWithItsOwnForecast() async throws {
        let c = try coordinator()
        await c.findRoutes()
        await c.addViaPin(at: PinSpots.nearPueblo)
        try #require(c.routes.first?.label == "via Pin near Pueblo")
        c.selectRoute(0)
        await c.generateBriefing(allRoutes: true)
        let via = try #require(c.briefings[0]?.stops.first { $0.kind == .via })
        #expect(via.label == "Pin near Pueblo, CO")
        #expect(via.coordinate == DroppedPin.coordinate(fromQuery: DroppedPin.query(for: PinSpots.nearPueblo)))
        #expect(via.weather != nil && via.forecastFor == via.eta)
        #expect(via.dwellMinutes == 0, "passing through adds no time")
        let stops = try #require(c.briefings[0]?.stops)
        #expect(stops.first?.kind == .origin && stops.last?.kind == .destination)
        #expect(zip(stops, stops.dropFirst()).allSatisfy { $0.eta <= $1.eta })
        // The direct route doesn't go through the pin.
        let direct = try #require(c.routes.firstIndex { $0.label == "Direct" })
        #expect(c.briefings[direct]?.stops.contains { $0.kind == .via } == false)
        // Removing it on the card is not offered; removing the pin drops it.
        c.removeStop(stopID: via.id)
        #expect(c.briefings[0]?.stops.contains { $0.id == via.id } == true)
    }

    @Test func droppingTheSameSpotTwiceAddsOnePin() async throws {
        let c = try coordinator()
        await c.findRoutes()
        await c.addViaPin(at: PinSpots.nearPueblo)
        await c.addViaPin(at: PinSpots.nearPueblo)
        #expect(c.plan.viaTexts.count == 1)
    }
}

/// Names a coordinate after the nearest of a few towns, like CLGeocoder.
struct PinTownNamer: TimeZoneService {
    static let towns: [(String, String, Coordinate)] = [
        ("Pueblo", "CO", PinSpots.nearPueblo),
        ("Wichita Falls", "TX", PinSpots.nearWichitaFalls),
    ]

    func timeZone(at coordinate: Coordinate) async -> TimeZone? {
        await MockTimeZoneService().timeZone(at: coordinate)
    }

    func place(at coordinate: Coordinate) async -> PlaceInfo? {
        let tz = await timeZone(at: coordinate)
        guard let town = Self.towns.first(where: { Geo.haversineMiles($0.2, coordinate) < 5 }) else { return PlaceInfo(timeZone: tz) }
        return PlaceInfo(timeZone: tz, town: town.0, state: town.1)
    }
}

enum PinSpots {
    static let nearPueblo = Coordinate(lat: 38.25, lon: -104.61)
    static let nearWichitaFalls = Coordinate(lat: 33.91, lon: -98.49)
}
