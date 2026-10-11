import Foundation
import RoadTripCore
import SwiftData

/// Every external source the app talks to — one row each on the
/// "Data sources and freshness" screen.
enum DataSource: String, CaseIterable, Identifiable {
    case mapkit, weatherkit, nws, overpass, openChargeMap, bucees, loves, rest, bundledSnapshot

    var id: String { rawValue }

    init(_ kind: POIKind) {
        switch kind {
        case .bucees: self = .bucees
        case .loves: self = .loves
        case .rest: self = .rest
        }
    }

    var title: String {
        switch self {
        case .mapkit: "MapKit routing & geocoding"
        case .weatherkit: "WeatherKit forecasts"
        case .nws: "NWS alerts (api.weather.gov)"
        case .overpass: "OpenStreetMap Overpass (corridor)"
        case .openChargeMap: "Open Charge Map (Superchargers)"
        case .bucees: "Buc-ee's locations"
        case .loves: "Love's Travel Stops"
        case .rest: "Rest areas (OpenStreetMap)"
        case .bundledSnapshot: "Bundled POI snapshot"
        }
    }
}

/// Persists last-success / last-error per source and counts this session's
/// calls in memory (web's API-call counter).
@MainActor
@Observable
final class DataSourceStatusStore {
    private let container: ModelContainer
    private(set) var sessionCalls: [DataSource: Int] = [:]
    /// Bumped on every write so views refresh.
    private(set) var revision = 0

    init(container: ModelContainer) {
        self.container = container
    }

    func countCall(_ source: DataSource) {
        sessionCalls[source, default: 0] += 1
    }

    func recordSuccess(_ source: DataSource, count: Int) {
        let r = record(source)
        r.lastSuccessAt = Date()
        r.recordCount = count
        r.lastError = nil
        try? container.mainContext.save()
        revision += 1
    }

    func recordError(_ source: DataSource, _ message: String) {
        let r = record(source)
        r.lastErrorAt = Date()
        r.lastError = message
        try? container.mainContext.save()
        revision += 1
    }

    /// Counts one call and records its outcome (`count` = records returned).
    func record(_ source: DataSource, result: Result<Int, Error>) {
        countCall(source)
        switch result {
        case let .success(n): recordSuccess(source, count: n)
        case let .failure(e): recordError(source, e.localizedDescription)
        }
    }

    /// Read-only: views call this while rendering, so it must not insert.
    func status(_ source: DataSource) -> DataSourceStatusRecord? {
        let raw = source.rawValue
        let descriptor = FetchDescriptor<DataSourceStatusRecord>(predicate: #Predicate { $0.sourceRaw == raw })
        return (try? container.mainContext.fetch(descriptor))?.first
    }

    private func record(_ source: DataSource) -> DataSourceStatusRecord {
        let raw = source.rawValue
        let descriptor = FetchDescriptor<DataSourceStatusRecord>(predicate: #Predicate { $0.sourceRaw == raw })
        if let existing = (try? container.mainContext.fetch(descriptor))?.first { return existing }
        let created = DataSourceStatusRecord(sourceRaw: raw)
        container.mainContext.insert(created)
        return created
    }
}
