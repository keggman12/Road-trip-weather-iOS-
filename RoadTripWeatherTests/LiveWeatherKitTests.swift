import Foundation
import RoadTripCore
import Testing
@testable import RoadTripWeather

/// Phase-1 task 5 acceptance against live WeatherKit (needs network and the
/// WeatherKit capability + App Service on the App ID).
@Suite("Live WeatherKit", .serialized, .tags(.live))
struct LiveWeatherKitTests {
    private let amarillo = Coordinate(lat: 35.222, lon: -101.8313)
    private let service = WeatherKitService()

    @Test func thirtyHoursOutIsHourlyWithinHalfAnHour() async throws {
        let eta = Date().addingTimeInterval(30 * 3600)
        let result = try await service.forecast(at: amarillo, for: eta)
        #expect(result.horizon == .ok)
        let s = try #require(result.snapshot)
        #expect(s.kind == .hourly)
        #expect(abs(s.recordDate.timeIntervalSince(eta)) <= 30 * 60)
        #expect((-40...130).contains(s.temperatureF))
        #expect(s.humidityPercent != nil)
    }

    @Test func nineDaysOutStillHasAForecast() async throws {
        let eta = Date().addingTimeInterval(9 * 86_400)
        let result = try await service.forecast(at: amarillo, for: eta)
        #expect(result.horizon == .ok)
        let s = try #require(result.snapshot)
        #expect(abs(s.recordDate.timeIntervalSince(eta)) <= 24 * 3600)
    }

    @Test func twelveDaysOutIsBeyondHorizon() async throws {
        let result = try await service.forecast(at: amarillo, for: Date().addingTimeInterval(12 * 86_400))
        #expect(result.horizon == .beyondHorizon)
        #expect(result.snapshot == nil)
    }

    @Test func attributionURLIsAvailable() async {
        #expect(await service.attributionURL() != nil)
    }
}
