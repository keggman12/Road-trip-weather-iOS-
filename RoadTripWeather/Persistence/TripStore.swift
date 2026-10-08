import Foundation
import RoadTripCore
import SwiftData

/// Saved trips and their cached briefings (web `/api/trips` + `currentTripData`).
@MainActor
final class TripStore {
    private let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
    }

    private var context: ModelContext { container.mainContext }

    func allTrips() -> [TripRecord] {
        let d = FetchDescriptor<TripRecord>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        return (try? context.fetch(d)) ?? []
    }

    func save(plan: TripPlan, name: String, selectedRouteIndex: Int, briefing: Briefing?, existing: TripRecord? = nil) throws -> TripRecord {
        let trip = existing ?? TripRecord(name: name)
        trip.name = String(name.trimmingCharacters(in: .whitespaces).prefix(120))
        if let o = plan.origin {
            trip.originQuery = o.query; trip.originLabel = o.label
            trip.originLat = o.coordinate.latitude; trip.originLon = o.coordinate.longitude
            trip.originTimeZoneID = o.timeZoneID
        }
        if let d = plan.destination {
            trip.destQuery = d.query; trip.destLabel = d.label
            trip.destLat = d.coordinate.latitude; trip.destLon = d.coordinate.longitude
            trip.destTimeZoneID = d.timeZoneID
        }
        trip.viasData = JSONCoding.encode(plan.vias)
        trip.departureDate = plan.departure
        trip.departureTimeZoneID = plan.departureTimeZoneID
        trip.rangeMiSnapshot = plan.rangeMi
        trip.multiDayEnabled = plan.multiDay.enabled
        trip.maxDriveHours = plan.multiDay.maxDriveHours
        trip.resumeTime = plan.multiDay.resumeTime.hhmm
        trip.selectedRouteIndex = selectedRouteIndex
        if let vid = plan.vehicleID, let uuid = UUID(uuidString: vid) {
            let d = FetchDescriptor<VehicleRecord>(predicate: #Predicate { $0.id == uuid })
            trip.vehicle = (try? context.fetch(d))?.first
        }
        if let briefing {
            let edits = StopEdits(from: briefing)
            trip.stopEditsData = edits.isEmpty ? nil : JSONCoding.encode(edits)
            // Keep one cached briefing per route index.
            let record = (trip.briefings ?? []).first { $0.routeIndex == briefing.routeIndex } ?? {
                let r = CachedBriefingRecord()
                context.insert(r)
                r.trip = trip
                return r
            }()
            BriefingMapper.store(briefing, into: record, context: context)
        }
        trip.updatedAt = Date()
        if existing == nil { context.insert(trip) }
        try context.save()
        return trip
    }

    func delete(_ trip: TripRecord) throws {
        context.delete(trip)
        try context.save()
    }

    func plan(from trip: TripRecord) -> TripPlan {
        var plan = TripPlan()
        plan.origin = PlacePoint(query: trip.originQuery, label: trip.originLabel, coordinate: Coordinate(latitude: trip.originLat, longitude: trip.originLon), timeZoneID: trip.originTimeZoneID)
        plan.destination = PlacePoint(query: trip.destQuery, label: trip.destLabel, coordinate: Coordinate(latitude: trip.destLat, longitude: trip.destLon), timeZoneID: trip.destTimeZoneID)
        plan.vias = JSONCoding.decode([PlacePoint].self, from: trip.viasData) ?? []
        plan.departure = trip.departureDate
        plan.departureTimeZoneID = trip.departureTimeZoneID
        plan.rangeMi = trip.rangeMiSnapshot
        plan.vehicleID = trip.vehicle?.id.uuidString
        plan.multiDay = MultiDayOptions(enabled: trip.multiDayEnabled, maxDriveHours: trip.maxDriveHours, resumeTime: TimeOfDay(hhmm: trip.resumeTime))
        plan.stopEdits = JSONCoding.decode(StopEdits.self, from: trip.stopEditsData) ?? StopEdits()
        return plan
    }

    func cachedBriefings(for trip: TripRecord) -> [Briefing] {
        (trip.briefings ?? []).sorted { $0.routeIndex < $1.routeIndex }.map(BriefingMapper.briefing(from:))
    }

    // MARK: Current session (unsaved briefings)

    /// Cached briefings with no trip: the current session's briefings,
    /// written as soon as they are generated so they survive a relaunch
    /// even if the user never taps Save.
    func draftBriefings() -> [Briefing] {
        draftRecords().sorted { $0.routeIndex < $1.routeIndex }.map(BriefingMapper.briefing(from:))
    }

    /// Makes the drafts exactly `briefings` (one record per route index).
    func replaceDrafts(with briefings: [Briefing]) throws {
        let existing = draftRecords()
        let keep = Set(briefings.map(\.routeIndex))
        for r in existing where !keep.contains(r.routeIndex) { context.delete(r) }
        for b in briefings {
            let record = existing.first { $0.routeIndex == b.routeIndex } ?? {
                let r = CachedBriefingRecord()
                context.insert(r)
                return r
            }()
            BriefingMapper.store(b, into: record, context: context)
        }
        try context.save()
    }

    private func draftRecords() -> [CachedBriefingRecord] {
        ((try? context.fetch(FetchDescriptor<CachedBriefingRecord>())) ?? []).filter { $0.trip == nil }
    }

    // MARK: Vehicles

    func vehicles() -> [VehicleRecord] {
        let d = FetchDescriptor<VehicleRecord>(sortBy: [SortDescriptor(\.sortOrder)])
        return (try? context.fetch(d)) ?? []
    }

    /// Seeds the web defaults once.
    func seedVehiclesIfNeeded() {
        guard vehicles().isEmpty else { return }
        for (i, v) in Vehicle.defaults.enumerated() {
            context.insert(VehicleRecord(name: v.name, rangeMi: v.rangeMi, isEV: v.isEV, sortOrder: i, isBuiltIn: true))
        }
        try? context.save()
    }
}
