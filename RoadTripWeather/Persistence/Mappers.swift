import Foundation
import RoadTripCore
import SwiftData

// Core value types ⇄ SwiftData records. Pure functions; the UI and the logic
// layer never touch records directly.

enum BriefingMapper {
    /// Writes a Core briefing into a (new or existing) record inside `context`.
    @MainActor
    static func store(_ briefing: Briefing, into record: CachedBriefingRecord, context: ModelContext) {
        record.id = briefing.id
        record.routeIndex = briefing.routeIndex
        record.routeLabel = briefing.routeLabel ?? ""
        record.generatedAt = briefing.generatedAt
        record.departureDate = briefing.departure
        record.departureTimeZoneID = briefing.departureTimeZoneID
        record.distanceMi = briefing.geometry.distanceMi
        record.durationSec = briefing.geometry.durationSec
        record.totalMi = briefing.totalMi
        record.rangeMi = briefing.rangeMi
        record.multiDayEnabled = briefing.multiDay.enabled
        record.maxDriveHours = briefing.multiDay.maxDriveHours
        record.resumeTime = briefing.multiDay.resumeTime.hhmm
        record.polylineData = CoordinatePacking.pack(briefing.geometry.coordinates)
        record.legBoundaryIndices = briefing.geometry.legBoundaryIndices
        record.removedMi = briefing.removedMi
        record.weatherAttributionURL = briefing.weatherAttributionURL

        for old in record.stops ?? [] { context.delete(old) }
        for old in record.segments ?? [] { context.delete(old) }

        var alertRecords: [String: AlertRecord] = [:]
        var stopRecords: [StopRecord] = []
        for (i, stop) in briefing.stops.enumerated() {
            let s = StopRecord()
            s.id = stop.id
            s.index = i
            s.kindRaw = stop.kind.rawValue
            s.label = stop.label
            s.lat = stop.coordinate.latitude
            s.lon = stop.coordinate.longitude
            s.routeIndex = stop.routeIndex
            s.distanceMi = stop.distanceMi
            s.legMi = stop.legMi
            s.etaDate = stop.eta
            s.dwellMin = stop.dwellMinutes
            s.manualOvernight = stop.manualOvernight
            s.autoOvernight = stop.autoOvernight
            s.resumeDate = stop.resume
            s.travelBearing = stop.travelBearing
            s.timeZoneID = stop.timeZoneID
            s.poiKindRaw = stop.poiKind?.rawValue
            s.poiSourceID = stop.poiSourceID
            s.offRouteMi = stop.offRouteMi
            s.forecastForDate = stop.forecastFor
            s.horizonRaw = stop.horizon.rawValue
            if let w = stop.weather {
                let wr = WeatherSnapshotRecord()
                wr.recordDate = w.recordDate
                wr.fetchedAt = w.fetchedAt
                wr.tempF = w.temperatureF
                wr.feelsLikeF = w.feelsLikeF
                wr.humidityPct = w.humidityPercent
                wr.windMph = w.windMph
                wr.windDeg = w.windFromDegrees
                wr.cloudPct = w.cloudPercent
                wr.conditionRaw = w.conditionRaw
                wr.conditionText = w.conditionText
                wr.categoryRaw = w.category.rawValue
                wr.precipChance = w.precipitationChance
                wr.kindRaw = w.kind.rawValue
                context.insert(wr)
                s.weather = wr
            }
            var alerts: [AlertRecord] = []
            for a in stop.alerts {
                let ar: AlertRecord
                if let existing = alertRecords[a.id] {
                    ar = existing
                } else {
                    ar = AlertRecord()
                    ar.nwsID = a.id
                    ar.event = a.event
                    ar.severityRaw = a.severity.rawValue
                    ar.headline = a.headline
                    ar.areaDesc = a.areaDescription
                    ar.onset = a.onset
                    ar.ends = a.ends
                    context.insert(ar)
                    alertRecords[a.id] = ar
                }
                alerts.append(ar)
            }
            s.alerts = alerts
            context.insert(s)
            s.briefing = record
            stopRecords.append(s)
        }
        record.stops = stopRecords

        var segments: [RouteSegmentRecord] = []
        for (i, (a, b)) in zip(briefing.stops, briefing.stops.dropFirst()).enumerated() {
            let seg = RouteSegmentRecord()
            seg.index = i
            seg.fromStopIndex = i
            seg.toStopIndex = i + 1
            seg.coordsData = CoordinatePacking.pack(segmentCoordinates(briefing.geometry.coordinates, from: a, to: b))
            seg.avgTempF = TemperatureScale.segmentTemperature(a.weather.map { Double($0.temperatureF) }, b.weather.map { Double($0.temperatureF) })
            context.insert(seg)
            seg.briefing = record
            segments.append(seg)
        }
        record.segments = segments
    }

    /// Web `drawColoredRoute`: stop A, the polyline slice between the stops'
    /// route indices, stop B.
    static func segmentCoordinates(_ coords: [Coordinate], from a: Stop, to b: Stop) -> [Coordinate] {
        guard !coords.isEmpty else { return [a.coordinate, b.coordinate] }
        let lo = max(0, min(a.routeIndex, coords.count - 1))
        let hi = max(lo, min(b.routeIndex + 1, coords.count))
        return [a.coordinate] + Array(coords[lo..<hi]) + [b.coordinate]
    }

    static func briefing(from r: CachedBriefingRecord) -> Briefing {
        let stops = (r.stops ?? []).sorted { $0.index < $1.index }.map(stop(from:))
        let geometry = RouteGeometry(
            coordinates: CoordinatePacking.unpack(r.polylineData),
            distanceMi: r.distanceMi,
            durationSec: r.durationSec,
            label: r.routeLabel.isEmpty ? nil : r.routeLabel,
            legBoundaryIndices: r.legBoundaryIndices
        )
        return Briefing(
            id: r.id,
            routeIndex: r.routeIndex,
            routeLabel: r.routeLabel.isEmpty ? nil : r.routeLabel,
            geometry: geometry,
            totalMi: r.totalMi,
            departure: r.departureDate,
            departureTimeZoneID: r.departureTimeZoneID,
            rangeMi: r.rangeMi,
            multiDay: MultiDayOptions(enabled: r.multiDayEnabled, maxDriveHours: r.maxDriveHours, resumeTime: TimeOfDay(hhmm: r.resumeTime)),
            stops: stops,
            removedMi: r.removedMi,
            generatedAt: r.generatedAt,
            weatherAttributionURL: r.weatherAttributionURL
        )
    }

    static func stop(from s: StopRecord) -> Stop {
        let weather: WeatherSnapshot? = s.weather.map { w in
            WeatherSnapshot(
                temperatureF: w.tempF,
                feelsLikeF: w.feelsLikeF,
                humidityPercent: w.humidityPct,
                windMph: w.windMph,
                windFromDegrees: w.windDeg,
                cloudPercent: w.cloudPct,
                conditionRaw: w.conditionRaw,
                conditionText: w.conditionText,
                category: ConditionCategory(rawValue: w.categoryRaw) ?? .clear,
                recordDate: w.recordDate,
                precipitationChance: w.precipChance,
                kind: ForecastKind(rawValue: w.kindRaw) ?? .hourly,
                fetchedAt: w.fetchedAt
            )
        }
        let alerts = (s.alerts ?? []).map { a in
            WeatherAlert(id: a.nwsID, event: a.event, severity: AlertSeverity(nwsString: a.severityRaw), headline: a.headline, areaDescription: a.areaDesc, onset: a.onset, ends: a.ends)
        }
        return Stop(
            id: s.id,
            kind: StopKind(rawValue: s.kindRaw) ?? .sampled,
            label: s.label,
            coordinate: Coordinate(latitude: s.lat, longitude: s.lon),
            routeIndex: s.routeIndex,
            distanceMi: s.distanceMi,
            legMi: s.legMi,
            eta: s.etaDate,
            dwellMinutes: s.dwellMin,
            manualOvernight: s.manualOvernight,
            autoOvernight: s.autoOvernight,
            resume: s.resumeDate,
            travelBearing: s.travelBearing,
            timeZoneID: s.timeZoneID,
            poiKind: s.poiKindRaw.flatMap(POIKind.init(rawValue:)),
            poiSourceID: s.poiSourceID,
            offRouteMi: s.offRouteMi,
            weather: weather,
            forecastFor: s.forecastForDate,
            horizon: ForecastHorizon(rawValue: s.horizonRaw) ?? (weather == nil ? .failed : .ok),
            alerts: alerts
        )
    }
}

enum POIMapper {
    static func poi(from r: POIRecord) -> POI? {
        guard let kind = POIKind(rawValue: r.kindRaw) else { return nil }
        return POI(kind: kind, sourceID: r.sourceID, name: r.name, detail: r.detail, coordinate: Coordinate(latitude: r.lat, longitude: r.lon))
    }

    static func record(from p: POI, source: POISource, updatedAt: Date) -> POIRecord {
        POIRecord(kindRaw: p.kind.rawValue, sourceID: p.sourceID, name: p.name, detail: p.detail, lat: p.coordinate.latitude, lon: p.coordinate.longitude, sourceRaw: source.rawValue, updatedAt: updatedAt)
    }
}

enum VehicleMapper {
    static func vehicle(from r: VehicleRecord) -> Vehicle {
        Vehicle(id: r.id.uuidString, name: r.name, rangeMi: r.rangeMi, isEV: r.isEV)
    }
}
