import CoreLocation
import Foundation
import RoadTripCore
import WeatherKit

/// WeatherKit adapter. One `weather(for:including:)` call per stop asks for
/// the hourly window around the ETA (WeatherKit serves hourly data up to
/// 240 h ahead, far past the web's 47 h) and the daily forecast as a
/// fallback near the 10-day edge. Beyond 10 days there is no forecast.
struct WeatherKitService: RoadTripWeather.WeatherService {   // our protocol, not WeatherKit.WeatherService
    /// WeatherKit's forecast horizon.
    static let horizon: TimeInterval = 240 * 3600
    /// Half-width of the hourly window requested around the ETA.
    static let hourlyWindow: TimeInterval = 3 * 3600

    func forecast(at coordinate: Coordinate, for eta: Date) async throws -> ForecastResult {
        let now = Date()
        if eta.timeIntervalSince(now) > WeatherKitService.horizon {
            return ForecastResult(snapshot: nil, horizon: .beyondHorizon)
        }
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let start = max(now, eta.addingTimeInterval(-WeatherKitService.hourlyWindow))
        let end = eta.addingTimeInterval(WeatherKitService.hourlyWindow)
        let (hourly, daily) = try await WeatherKit.WeatherService.shared.weather(
            for: location,
            including: .hourly(startDate: start, endDate: end), .daily
        )
        let fetchedAt = Date()

        if let hour = NearestRecord.pick(from: hourly.forecast, date: \.date, nearestTo: eta) {
            return ForecastResult(snapshot: snapshot(from: hour, fetchedAt: fetchedAt), horizon: .ok)
        }
        if let day = NearestRecord.pick(from: daily.forecast, date: \.date, nearestTo: eta) {
            return ForecastResult(snapshot: snapshot(from: day, fetchedAt: fetchedAt), horizon: .ok)
        }
        return ForecastResult(snapshot: nil, horizon: .beyondHorizon)
    }

    func attributionURL() async -> URL? {
        try? await WeatherKit.WeatherService.shared.attribution.legalPageURL
    }

    // MARK: Normalisation (web `normalizeWx`)

    private func snapshot(from h: HourWeather, fetchedAt: Date) -> WeatherSnapshot {
        let temp = h.temperature.converted(to: .fahrenheit).value
        let feels = h.apparentTemperature.converted(to: .fahrenheit).value
        let cloud = h.cloudCover * 100
        return WeatherSnapshot(
            temperatureF: Int(temp.rounded()),
            feelsLikeF: Int(feels.rounded()),
            humidityPercent: Int((h.humidity * 100).rounded()),
            windMph: Int(h.wind.speed.converted(to: .milesPerHour).value.rounded()),
            windFromDegrees: h.wind.direction.converted(to: .degrees).value,
            cloudPercent: Int(cloud.rounded()),
            conditionRaw: h.condition.rawValue,
            conditionText: h.condition.description,
            category: WeatherKitService.category(for: h.condition, cloudPercent: cloud),
            recordDate: h.date,
            precipitationChance: h.precipitationChance,
            kind: .hourly,
            fetchedAt: fetchedAt
        )
    }

    private func snapshot(from d: DayWeather, fetchedAt: Date) -> WeatherSnapshot {
        // DayWeather has no single "day" temperature (the web used OWM's
        // temp.day); use the mean of high and low.
        let hi = d.highTemperature.converted(to: .fahrenheit).value
        let lo = d.lowTemperature.converted(to: .fahrenheit).value
        let mean = (hi + lo) / 2
        return WeatherSnapshot(
            temperatureF: Int(mean.rounded()),
            feelsLikeF: Int(mean.rounded()),
            humidityPercent: nil,
            windMph: Int(d.wind.speed.converted(to: .milesPerHour).value.rounded()),
            windFromDegrees: d.wind.direction.converted(to: .degrees).value,
            cloudPercent: nil,
            conditionRaw: d.condition.rawValue,
            conditionText: d.condition.description,
            category: WeatherKitService.category(for: d.condition, cloudPercent: nil),
            recordDate: d.date,
            precipitationChance: d.precipitationChance,
            kind: .daily,
            fetchedAt: fetchedAt
        )
    }

    /// `WeatherCondition` → the web's seven buckets (see docs/gaps.md).
    static func category(for condition: WeatherCondition, cloudPercent: Double?) -> ConditionCategory {
        switch condition {
        case .thunderstorms, .isolatedThunderstorms, .scatteredThunderstorms, .strongStorms:
            return .thunderstorm
        case .hurricane, .tropicalStorm:
            return .severe
        case .rain, .drizzle, .heavyRain, .freezingRain, .freezingDrizzle, .sunShowers, .hail:
            return .rain
        case .snow, .flurries, .heavySnow, .sleet, .wintryMix, .blowingSnow, .blizzard, .sunFlurries:
            return .snow
        case .cloudy, .foggy, .haze, .smoky, .blowingDust:
            return .mostlyCloudy
        case .mostlyCloudy:
            return .mostlyCloudy
        case .partlyCloudy:
            return .partlyCloudy
        case .clear, .mostlyClear:
            return cloudPercent == nil ? .clear : ConditionCategory.fromCloudCover(percent: cloudPercent)
        case .hot, .frigid, .breezy, .windy:
            return ConditionCategory.fromCloudCover(percent: cloudPercent)
        @unknown default:
            return ConditionCategory.fromCloudCover(percent: cloudPercent)
        }
    }
}
