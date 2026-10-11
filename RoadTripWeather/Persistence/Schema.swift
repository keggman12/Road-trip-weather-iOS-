import Foundation
import SwiftData

// SwiftData schema — see docs/data-model.md. CloudKit rules: no unique
// attributes, every property defaulted, every relationship optional with an
// explicit inverse, no `.deny` delete rules.

@Model
final class VehicleRecord {
    var id: UUID = UUID()
    var name: String = ""
    var rangeMi: Double = 300
    var isEV: Bool = false
    var sortOrder: Int = 0
    var isBuiltIn: Bool = false
    var createdAt: Date = Date()
    @Relationship(deleteRule: .nullify, inverse: \TripRecord.vehicle) var trips: [TripRecord]?

    init(id: UUID = UUID(), name: String, rangeMi: Double, isEV: Bool, sortOrder: Int, isBuiltIn: Bool = false) {
        self.id = id
        self.name = name
        self.rangeMi = rangeMi
        self.isEV = isEV
        self.sortOrder = sortOrder
        self.isBuiltIn = isBuiltIn
    }
}

@Model
final class TripRecord {
    var id: UUID = UUID()
    var name: String = ""
    var originQuery: String = ""
    var originLabel: String = ""
    var originLat: Double = 0
    var originLon: Double = 0
    var originTimeZoneID: String?
    var destQuery: String = ""
    var destLabel: String = ""
    var destLat: Double = 0
    var destLon: Double = 0
    var destTimeZoneID: String?
    /// JSON `[PlacePoint]`.
    var viasData: Data = Data()
    var departureDate: Date = Date()
    var departureTimeZoneID: String?
    var vehicle: VehicleRecord?
    var rangeMiSnapshot: Double = 300
    var multiDayEnabled: Bool = false
    var maxDriveHours: Double = 10
    var resumeTime: String = "08:00"
    var selectedRouteIndex: Int = 0
    /// JSON `StopEdits`.
    var stopEditsData: Data?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    @Relationship(deleteRule: .cascade, inverse: \CachedBriefingRecord.trip) var briefings: [CachedBriefingRecord]?

    init(name: String) {
        self.name = name
    }
}

@Model
final class CachedBriefingRecord {
    var id: UUID = UUID()
    var trip: TripRecord?
    var routeIndex: Int = 0
    var routeLabel: String = ""
    var generatedAt: Date = Date()
    var departureDate: Date = Date()
    var departureTimeZoneID: String?
    var distanceMi: Double = 0
    var durationSec: Double = 0
    var totalMi: Double = 0
    var rangeMi: Double = 300
    var multiDayEnabled: Bool = false
    var maxDriveHours: Double = 10
    var resumeTime: String = "08:00"
    /// Packed Float64 lat,lon pairs.
    var polylineData: Data = Data()
    var legBoundaryIndices: [Int] = []
    var removedMi: [Int] = []
    var weatherAttributionURL: String?
    var briefedAllRoutes: Bool = false
    var schemaVersion: Int = 1
    /// JSON `[String: [String]]` — POI ids shown per kind, for offline pins.
    var shownPOIData: Data?
    @Relationship(deleteRule: .cascade, inverse: \StopRecord.briefing) var stops: [StopRecord]?
    @Relationship(deleteRule: .cascade, inverse: \RouteSegmentRecord.briefing) var segments: [RouteSegmentRecord]?

    init() {}
}

@Model
final class StopRecord {
    var id: UUID = UUID()
    var briefing: CachedBriefingRecord?
    var index: Int = 0
    var kindRaw: String = "sampled"
    var label: String = ""
    var lat: Double = 0
    var lon: Double = 0
    var routeIndex: Int = 0
    var distanceMi: Double = 0
    var legMi: Double = 0
    var etaDate: Date = Date()
    var dwellMin: Int = 15
    var manualOvernight: Bool = false
    var autoOvernight: Bool = false
    var resumeDate: Date?
    var travelBearing: Double?
    var timeZoneID: String?
    var poiKindRaw: String?
    var poiSourceID: String?
    var offRouteMi: Double?
    var forecastForDate: Date?
    var horizonRaw: String = "failed"
    /// JSON `[Charger]`, nil when there are none.
    var chargersData: Data?
    var planNote: String?
    @Relationship(deleteRule: .cascade, inverse: \WeatherSnapshotRecord.stop) var weather: WeatherSnapshotRecord?
    @Relationship(deleteRule: .nullify, inverse: \AlertRecord.stops) var alerts: [AlertRecord]?

    init() {}
}

@Model
final class WeatherSnapshotRecord {
    var id: UUID = UUID()
    var stop: StopRecord?
    var recordDate: Date = Date()
    var fetchedAt: Date = Date()
    var tempF: Int = 0
    var feelsLikeF: Int = 0
    var humidityPct: Int?
    var windMph: Int = 0
    var windDeg: Double?
    var cloudPct: Int?
    var conditionRaw: String = ""
    var conditionText: String = ""
    var categoryRaw: String = "clear"
    var precipChance: Double?
    var kindRaw: String = "hourly"
    var source: String = "weatherkit"

    init() {}
}

@Model
final class AlertRecord {
    var id: UUID = UUID()
    var nwsID: String = ""
    var event: String = ""
    var severityRaw: String = "Unknown"
    var headline: String = ""
    var areaDesc: String = ""
    var onset: Date?
    var ends: Date?
    var fetchedAt: Date = Date()
    var stops: [StopRecord]?

    init() {}
}

@Model
final class RouteSegmentRecord {
    var id: UUID = UUID()
    var briefing: CachedBriefingRecord?
    var index: Int = 0
    var fromStopIndex: Int = 0
    var toStopIndex: Int = 0
    /// Packed Float64 lat,lon pairs including both stop positions.
    var coordsData: Data = Data()
    var avgTempF: Double?

    init() {}
}

@Model
final class POIRecord {
    var kindRaw: String = "bucees"
    var sourceID: String = ""
    var name: String = ""
    var detail: String?
    var lat: Double = 0
    var lon: Double = 0
    var sourceRaw: String = "bundled"
    var updatedAt: Date = Date()

    init(kindRaw: String, sourceID: String, name: String, detail: String?, lat: Double, lon: Double, sourceRaw: String, updatedAt: Date) {
        self.kindRaw = kindRaw
        self.sourceID = sourceID
        self.name = name
        self.detail = detail
        self.lat = lat
        self.lon = lon
        self.sourceRaw = sourceRaw
        self.updatedAt = updatedAt
    }
}

@Model
final class POIMetaRecord {
    var kindRaw: String = "bucees"
    var lastUpdated: Date?
    var count: Int = 0
    var sourceRaw: String = "bundled"
    var lastAttemptAt: Date?
    var lastError: String?
    var snapshotVersion: String = ""

    init(kindRaw: String) {
        self.kindRaw = kindRaw
    }
}

@Model
final class DataSourceStatusRecord {
    var sourceRaw: String = ""
    var lastSuccessAt: Date?
    var recordCount: Int = 0
    var lastErrorAt: Date?
    var lastError: String?

    init(sourceRaw: String) {
        self.sourceRaw = sourceRaw
    }
}

enum AppSchema {
    static let models: [any PersistentModel.Type] = [
        VehicleRecord.self, TripRecord.self, CachedBriefingRecord.self, StopRecord.self,
        WeatherSnapshotRecord.self, AlertRecord.self, RouteSegmentRecord.self,
        POIRecord.self, POIMetaRecord.self, DataSourceStatusRecord.self,
    ]

    /// Local store by default; pass `cloud: true` to sync through the
    /// container named in the entitlements.
    static func makeContainer(cloud: Bool = false, inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(models)
        let config = ModelConfiguration(
            "RoadTripWeather",
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: cloud ? .automatic : .none
        )
        return try ModelContainer(for: schema, configurations: [config])
    }
}
