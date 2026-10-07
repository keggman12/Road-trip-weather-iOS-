import Foundation
import Testing
@testable import RoadTripCore

@Suite("ConditionCategory (web icons.categorize)")
struct ConditionCategoryTests {
    let ref = WebReference.shared

    @Test func openWeatherMapMappingMatchesWeb() {
        for c in ref.categorize {
            let got = ConditionCategory.fromOpenWeatherMap(id: c.id.value, cloudPercent: c.cl)
            #expect(got.rawValue == c.cat, "id \(String(describing: c.id.value)) clouds \(String(describing: c.cl))")
        }
    }

    @Test func cloudCoverFallback() {
        #expect(ConditionCategory.fromCloudCover(percent: nil) == .clear)
        #expect(ConditionCategory.fromCloudCover(percent: 0) == .clear)
        #expect(ConditionCategory.fromCloudCover(percent: 14.9) == .clear)
        #expect(ConditionCategory.fromCloudCover(percent: 15) == .partlyCloudy)
        #expect(ConditionCategory.fromCloudCover(percent: 49.9) == .partlyCloudy)
        #expect(ConditionCategory.fromCloudCover(percent: 50) == .mostlyCloudy)
        #expect(ConditionCategory.fromCloudCover(percent: 100) == .mostlyCloudy)
    }

    @Test func labelsAndBadges() {
        #expect(ConditionCategory.partlyCloudy.label == "Partly cloudy")
        #expect(ConditionCategory.severe.badgeColorHex == "#f87171")
        #expect(ConditionCategory.allCases.filter(\.isHazardousPrecipitation) == [.thunderstorm, .severe, .snow])
    }

    @Test func rawValuesAreWebStrings() {
        #expect(ConditionCategory(rawValue: "partly-cloudy") == .partlyCloudy)
        #expect(ConditionCategory(rawValue: "mostly-cloudy") == .mostlyCloudy)
    }

    @Test func nearestRecordPicksSmallestDelta() {
        let target = Date(timeIntervalSince1970: 10_000)
        let recs: [Date] = [0, 7_000, 9_000, 12_000, 20_000].map(Date.init(timeIntervalSince1970:))
        #expect(NearestRecord.pick(from: recs, date: { $0 }, nearestTo: target)?.timeIntervalSince1970 == 9_000)
        #expect(NearestRecord.pick(from: [Date](), date: { $0 }, nearestTo: target) == nil)
        // Ties keep the first (strict <).
        let tie: [Date] = [Date(timeIntervalSince1970: 9_000), Date(timeIntervalSince1970: 11_000)]
        #expect(NearestRecord.pick(from: tie, date: { $0 }, nearestTo: target)?.timeIntervalSince1970 == 9_000)
    }

    @Test func precipitationPercentRounds() {
        let w = WeatherSnapshot(temperatureF: 70, feelsLikeF: 70, windMph: 5, category: .clear, recordDate: Date(), precipitationChance: 0.345, kind: .hourly)
        #expect(w.precipitationPercent == 35)
        let none = WeatherSnapshot(temperatureF: 70, feelsLikeF: 70, windMph: 5, category: .clear, recordDate: Date(), kind: .hourly)
        #expect(none.precipitationPercent == nil)
    }
}
