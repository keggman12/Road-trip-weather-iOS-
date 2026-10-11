import Foundation
import RoadTripCore
import SwiftData
import Testing
@testable import RoadTripWeather

@Suite("Persistence mappers")
@MainActor
struct MapperTests {
    @Test func coordinatePackingRoundTrip() {
        let coords = [Coordinate(lat: 39.7392, lon: -104.9903), Coordinate(lat: -33.9, lon: 151.2), Coordinate(lat: 0, lon: 0)]
        #expect(CoordinatePacking.unpack(CoordinatePacking.pack(coords)) == coords)
        #expect(CoordinatePacking.unpack(Data()).isEmpty)
    }

    @Test func briefingRoundTripThroughSwiftData() throws {
        let container = try AppSchema.makeContainer(inMemory: true)
        let context = container.mainContext
        let route = RouteGeometry(coordinates: MockRoutingService.line(from: Coordinate(lat: 39.7392, lon: -104.9903), to: Coordinate(lat: 32.7767, lon: -96.797)), distanceMi: 663, durationSec: 41_400, label: "Direct")
        let (stops, total) = StopListBuilder.initialStops(route: route, rangeMi: 180, originLabel: "Denver", destinationLabel: "Dallas")
        var b = Briefing(routeIndex: 1, routeLabel: "Direct", geometry: route, totalMi: total, departure: Date(timeIntervalSince1970: 1_781_096_400), departureTimeZoneID: "America/Denver", rangeMi: 180, stops: stops, removedMi: [180])
        ETACalculator.recompute(&b, fallbackTimeZone: TimeZone(identifier: "America/Denver") ?? .current)
        b.stops[1].weather = WeatherSnapshot(temperatureF: 71, feelsLikeF: 69, humidityPercent: 40, windMph: 12, windFromDegrees: 200, cloudPercent: 30, conditionRaw: "partlyCloudy", conditionText: "Partly cloudy", category: .partlyCloudy, recordDate: b.stops[1].eta, precipitationChance: 0.2, kind: .hourly, fetchedAt: Date(timeIntervalSince1970: 1_781_096_400))
        b.stops[1].forecastFor = b.stops[1].eta
        b.stops[1].horizon = .ok
        let alert = WeatherAlert(id: "urn:x", event: "Heat Advisory", severity: .moderate, headline: "h", areaDescription: "Dallas", onset: Date(timeIntervalSince1970: 1_781_000_000), ends: Date(timeIntervalSince1970: 1_781_200_000))
        b.stops[1].alerts = [alert]
        b.stops[2].alerts = [alert]

        let record = CachedBriefingRecord()
        context.insert(record)
        BriefingMapper.store(b, into: record, context: context)
        try context.save()

        let back = BriefingMapper.briefing(from: record)
        #expect(back.id == b.id)
        #expect(back.stops.count == b.stops.count)
        #expect(back.stops.map(\.id) == b.stops.map(\.id))
        #expect(back.stops[1].weather == b.stops[1].weather)
        #expect(back.stops[1].alerts == [alert] && back.stops[2].alerts == [alert])
        #expect(back.geometry.coordinates == route.coordinates)
        #expect(back.removedMi == [180])
        #expect(back.routeLabel == "Direct" && back.routeIndex == 1)
        #expect(back.alerts.count == 1)   // deduped across stops
        #expect(record.segments?.count == b.stops.count - 1)
        // One AlertRecord shared by two stops.
        #expect(try context.fetchCount(FetchDescriptor<AlertRecord>()) == 1)
    }

    @Test func segmentCoordinatesIncludeBothStops() {
        let coords = (0..<10).map { Coordinate(lat: Double($0), lon: 0) }
        let a = Stop(kind: .origin, label: "a", coordinate: Coordinate(lat: 0.5, lon: 0), routeIndex: 0, distanceMi: 0)
        let b = Stop(kind: .sampled, label: "b", coordinate: Coordinate(lat: 3.5, lon: 0), routeIndex: 3, distanceMi: 3)
        let seg = BriefingMapper.segmentCoordinates(coords, from: a, to: b)
        #expect(seg.first == a.coordinate && seg.last == b.coordinate)
        #expect(seg.count == 2 + 4)   // coords[0...3]
    }
}

@Suite("WeatherKit condition mapping")
struct ConditionMappingTests {
    @Test func bucketsMatchWebSemantics() {
        #expect(WeatherKitService.category(for: .thunderstorms, cloudPercent: nil) == .thunderstorm)
        #expect(WeatherKitService.category(for: .hurricane, cloudPercent: nil) == .severe)
        #expect(WeatherKitService.category(for: .drizzle, cloudPercent: 90) == .rain)
        #expect(WeatherKitService.category(for: .blizzard, cloudPercent: nil) == .snow)
        #expect(WeatherKitService.category(for: .foggy, cloudPercent: 10) == .mostlyCloudy)
        #expect(WeatherKitService.category(for: .partlyCloudy, cloudPercent: 90) == .partlyCloudy)
        #expect(WeatherKitService.category(for: .clear, cloudPercent: nil) == .clear)
        #expect(WeatherKitService.category(for: .mostlyClear, cloudPercent: 40) == .partlyCloudy)
        #expect(WeatherKitService.category(for: .windy, cloudPercent: 70) == .mostlyCloudy)
    }
}
