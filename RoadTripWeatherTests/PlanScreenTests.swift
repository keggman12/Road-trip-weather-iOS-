import Foundation
import RoadTripCore
import SwiftData
import Testing
@testable import RoadTripWeather

/// Phase-1 task 7: Find Routes gating, recents only after successful
/// geocoding, no WeatherKit call during Find Routes, departure defaults.
@Suite("Plan screen (task 7)", .serialized)
@MainActor
struct PlanScreenTests {
    let net = FakeNetwork()

    private func makeCoordinator() throws -> BriefingCoordinator {
        let env = AppEnvironment(
            container: try AppSchema.makeContainer(inMemory: true),
            settings: AppSettings(defaults: UserDefaults(suiteName: "PlanScreenTests-\(UUID().uuidString)") ?? .standard),
            geocoding: FakeGeocoding(net: net),
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

    @Test func pastDepartureDoesNotClearCachedRoutes() async throws {
        let c = try makeCoordinator()
        c.plan.originText = "Denver"
        c.plan.destinationText = "Dallas"
        await c.findRoutes()
        let routes = c.routes
        let past = Date().addingTimeInterval(-86400)
        c.plan.departure = past
        await c.findRoutes()
        #expect(!c.canFindRoutes)
        #expect(c.plan.departure == past)
        #expect(c.routes == routes)
        #expect(c.errorMessage?.contains("departure has passed") == true)
        c.departToday()
        #expect(c.plan.departure > Date())
        #expect(c.routes == routes)
    }

    @Test func findRoutesNeedsOriginAndDestination() throws {
        let c = try makeCoordinator()
        #expect(!c.canFindRoutes)
        c.plan.originText = "Denver"
        #expect(!c.canFindRoutes)
        c.plan.destinationText = "   "
        #expect(!c.canFindRoutes, "whitespace is not a destination")
        c.plan.destinationText = "Dallas"
        #expect(c.canFindRoutes)
        c.plan.viaTexts = [""]
        #expect(c.canFindRoutes, "an empty via-point row is ignored")
        c.phase = .routing
        #expect(!c.canFindRoutes, "disabled while busy")
    }

    @Test func recentsUpdateOnlyAfterEveryPointGeocodes() async throws {
        let c = try makeCoordinator()
        c.plan.originText = "Denver"
        c.plan.viaTexts = ["Atlantis"]          // the fake geocoder can't find it
        c.plan.destinationText = "Dallas"
        await c.findRoutes()
        #expect(c.errorMessage?.contains("Atlantis") == true)
        #expect(c.env.settings.recentLocations.isEmpty, "a failed lookup remembers nothing")
        #expect(c.routes.isEmpty)

        c.plan.viaTexts = ["Amarillo", " "]
        await c.findRoutes()
        #expect(c.errorMessage == nil)
        #expect(c.env.settings.recentLocations == ["Dallas", "Amarillo", "Denver"], "most recent first, blanks skipped")
        #expect(c.routes.map(\.label) == ["via Amarillo", "Direct"])

        net.online = false
        c.plan.originText = "Oklahoma City"
        await c.findRoutes()
        #expect(c.env.settings.recentLocations.first == "Dallas", "offline lookups don't touch recents")
    }

    @Test func pickedPlaceIsUsedWithoutGeocodingOrMismatchNotice() async throws {
        let c = try makeCoordinator()
        let picked = PlacePoint(query: "Atlantis Casino, Reno, NV", label: "Reno, NV", coordinate: Coordinate(lat: 39.4868, lon: -119.7942), timeZoneID: "America/Los_Angeles")
        c.pick(picked)
        c.plan.originText = "Atlantis Casino, Reno, NV"   // the fake geocoder can't find it
        c.plan.destinationText = "Dallas"
        await c.findRoutes()
        #expect(c.errorMessage == nil)
        #expect(c.plan.origin == picked, "the picked place is used as is")
        #expect(c.placeNotices.isEmpty, "a picked place never gets a 'check the spelling' notice")
        #expect(c.plan.departureTimeZoneID == "America/Los_Angeles")
    }

    @Test func viaRowsKeepTheirIdentityWhenOneIsRemoved() throws {
        var plan = TripPlan()
        plan.viaTexts = ["Amarillo", "Wichita Falls", "Raton"]
        let ids = plan.viaEntries.map(\.id)
        plan.viaEntries.removeAll { $0.id == ids[1] }
        #expect(plan.viaTexts == ["Amarillo", "Raton"])
        #expect(plan.viaEntries.map(\.id) == [ids[0], ids[2]], "rows are not renumbered")
    }

    @Test func viaPointsKeepTheSavedSessionFormat() throws {
        var plan = TripPlan()
        plan.viaTexts = ["Amarillo", "Raton"]
        let data = try JSONEncoder().encode(plan)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["viaTexts"] as? [String] == ["Amarillo", "Raton"], "same key and shape as before")
        let decoded = try JSONDecoder().decode(TripPlan.self, from: data)
        #expect(decoded.viaTexts == ["Amarillo", "Raton"])
    }

    @Test func findRoutesMakesNoWeatherCallsAndAdoptsOriginZone() async throws {
        let c = try makeCoordinator()
        c.plan.originText = "Denver"
        c.plan.destinationText = "Dallas"
        await c.findRoutes()
        #expect(!c.routes.isEmpty)
        #expect(c.env.status.sessionCalls[.weatherkit, default: 0] == 0)
        #expect(await net.snapshot().weather == 0)
        #expect(c.plan.departureTimeZoneID == "America/Denver", "departure is edited in the origin's zone")
    }

    @Test func defaultDepartureIsTheNextFullHour() throws {
        var cal = Calendar.current
        cal.timeZone = .current
        let now = try #require(cal.date(from: DateComponents(year: 2026, month: 10, day: 8, hour: 8, minute: 24, second: 13)))
        let d = TripPlan.defaultDeparture(now: now)
        #expect(cal.dateComponents([.hour, .minute, .second], from: d) == DateComponents(hour: 9, minute: 0, second: 0))
        let onTheHour = try #require(cal.date(from: DateComponents(year: 2026, month: 10, day: 8, hour: 23, minute: 0)))
        #expect(TripPlan.defaultDeparture(now: onTheHour) == onTheHour.addingTimeInterval(3600), "rolls over midnight")
    }
}
