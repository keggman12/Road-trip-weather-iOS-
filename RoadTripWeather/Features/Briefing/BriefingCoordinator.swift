import Foundation
import RoadTripCore
import SwiftUI

/// The two-phase flow (web `findRoutes` → `generateBriefing`) plus every stop
/// mutation that follows. Owns the in-memory routes and briefings; the views
/// render what's here and `TripStore` persists it.
@MainActor
@Observable
final class BriefingCoordinator {
    enum Phase: Equatable {
        case idle
        case geocoding(String)
        case routing
        case briefing(done: Int, total: Int, routeLabel: String)
        case refreshing(done: Int, total: Int)
    }

    let env: AppEnvironment

    var plan = TripPlan()
    var routes: [RouteGeometry] = []
    var routeNote: String?
    var selectedRouteIndex: Int = -1
    /// Briefings by route index. Only the selected route is briefed unless
    /// the user asks for all routes.
    var briefings: [Int: Briefing] = [:]
    var phase: Phase = .idle
    var statusMessage: String?
    var errorMessage: String?
    var poiLayersEnabled: Set<POIKind> = []
    /// POIs per kind within the selected route's corridor.
    var corridorPOIs: [POIKind: [POI]] = [:]
    var weatherAttributionURL: URL?
    /// The saved trip the current plan came from, if any.
    var loadedTrip: TripRecord?

    init(env: AppEnvironment) {
        self.env = env
    }

    var isBusy: Bool { phase != .idle }
    var selectedRoute: RouteGeometry? { routes.indices.contains(selectedRouteIndex) ? routes[selectedRouteIndex] : nil }
    var briefing: Briefing? { briefings[selectedRouteIndex] }

    // MARK: Phase 1 — find routes (no weather calls)

    func findRoutes() async {
        errorMessage = nil
        let originText = plan.originText.trimmingCharacters(in: .whitespaces)
        let destText = plan.destinationText.trimmingCharacters(in: .whitespaces)
        guard !originText.isEmpty, !destText.isEmpty else {
            errorMessage = "Enter both an origin and a destination."
            return
        }
        resetRoutes()
        do {
            phase = .geocoding(([originText] + plan.viaTexts + [destText]).joined(separator: " → "))
            let texts = [originText] + plan.viaTexts.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } + [destText]
            var points: [PlacePoint] = []
            for t in texts {
                env.status.countCall(.mapkit)
                points.append(try await env.geocoding.geocode(t))
            }
            guard let first = points.first, let last = points.last else { throw ServiceError.noRoute }
            plan.origin = first
            plan.destination = last
            plan.vias = Array(points.dropFirst().dropLast())
            if let tz = first.timeZoneID { plan.departureTimeZoneID = tz }
            // Geocoding succeeded — worth remembering (web `rememberLocations`).
            for t in texts { env.settings.remember(t) }

            phase = .routing
            env.status.countCall(.mapkit)
            let result = try await env.routing.routes(through: points, departure: plan.departure)
            routes = result.routes
            routeNote = result.note
            env.status.recordSuccess(.mapkit, count: routes.count)
            selectedRouteIndex = routes.isEmpty ? -1 : 0
            statusMessage = "\(routes.count) route\(routes.count == 1 ? "" : "s") found — choose one, set range, then generate the briefing."
        } catch {
            env.status.recordError(.mapkit, error.localizedDescription)
            errorMessage = error.localizedDescription
        }
        phase = .idle
    }

    func selectRoute(_ index: Int) {
        guard routes.indices.contains(index) else { return }
        selectedRouteIndex = index
        Task { await refreshPOILayers() }
    }

    private func resetRoutes() {
        routes = []
        routeNote = nil
        selectedRouteIndex = -1
        briefings = [:]
        corridorPOIs = [:]
        statusMessage = nil
    }

    // MARK: Phase 2 — generate briefing

    /// Briefs the selected route (default) or every route.
    func generateBriefing(allRoutes: Bool = false) async {
        guard selectedRouteIndex >= 0 else { errorMessage = "Pick a route first."; return }
        guard let selected = selectedRoute, selected.coordinates.count >= 2 else {
            errorMessage = "Find routes first — this saved trip only has a cached briefing."
            return
        }
        errorMessage = nil
        let indices = (allRoutes ? Array(routes.indices) : [selectedRouteIndex]).filter { routes[$0].coordinates.count >= 2 }
        for j in indices {
            await brief(routeIndex: j, label: routes[j].label ?? "Route \(j + 1)")
        }
        if let edits = plan.stopEdits.isEmpty ? nil : plan.stopEdits, var b = briefings[selectedRouteIndex] {
            await replayEdits(edits, into: &b)
            briefings[selectedRouteIndex] = b
            plan.stopEdits = StopEdits()
        }
        if weatherAttributionURL == nil { weatherAttributionURL = await env.weather.attributionURL() }
        // Persisted with the briefing so a cached trip can show it offline.
        if let url = weatherAttributionURL?.absoluteString {
            for j in indices { briefings[j]?.weatherAttributionURL = url }
        }
        await refreshPOILayers()
        phase = .idle
        if let b = briefing {
            let failed = b.stops.filter { $0.weather == nil && $0.horizon == .failed }.count
            let alerts = b.alerts.count
            if failed > 0 { statusMessage = "Briefing ready — \(failed) of \(b.stops.count) forecasts failed." }
            else if alerts > 0 { statusMessage = "Briefing ready — ⚠ \(alerts) weather alert\(alerts == 1 ? "" : "s") during transit." }
            else { statusMessage = "Briefing ready — \(b.stops.count) waypoints." }
        }
    }

    private func brief(routeIndex j: Int, label: String) async {
        let route = routes[j]
        let (stops0, totalMi) = StopListBuilder.initialStops(
            route: route,
            rangeMi: plan.rangeMi,
            originLabel: plan.origin?.label ?? plan.originText,
            destinationLabel: plan.destination?.label ?? plan.destinationText
        )
        var b = Briefing(
            routeIndex: j,
            routeLabel: route.label,
            geometry: route,
            totalMi: totalMi,
            departure: plan.departure,
            departureTimeZoneID: plan.departureTimeZoneID,
            rangeMi: Vehicle.clampRange(plan.rangeMi),
            multiDay: plan.multiDay,
            stops: stops0,
            generatedAt: Date()
        )
        guard !b.stops.isEmpty else { return }
        b.stops[0].timeZoneID = plan.origin?.timeZoneID
        if b.stops.count > 1 { b.stops[b.stops.count - 1].timeZoneID = plan.destination?.timeZoneID }
        ETACalculator.recompute(&b, fallbackTimeZone: plan.departureTimeZone)

        phase = .briefing(done: 0, total: b.stops.count, routeLabel: label)
        await resolveTimeZones(&b)
        // Time zones can change overnight resume times, so recompute.
        ETACalculator.recompute(&b, fallbackTimeZone: plan.departureTimeZone)
        await fetchWeather(for: &b, indices: Array(b.stops.indices), routeLabel: label)
        b.generatedAt = Date()
        briefings[j] = b
    }

    private func resolveTimeZones(_ b: inout Briefing) async {
        for i in b.stops.indices where b.stops[i].timeZoneID == nil {
            if let tz = await env.timeZones.timeZone(at: b.stops[i].coordinate) {
                b.stops[i].timeZoneID = tz.identifier
            }
        }
    }

    /// Fetches weather + alerts for the given stops concurrently (web
    /// `fetchStopWeather`). Failures leave `weather == nil`, `horizon == .failed`.
    private func fetchWeather(for b: inout Briefing, indices: [Int], routeLabel: String) async {
        let total = indices.count
        var done = 0
        let snapshot = b
        let results = await withTaskGroup(of: (Int, ForecastResult?, [WeatherAlert]).self, returning: [(Int, ForecastResult?, [WeatherAlert])].self) { group in
            for i in indices {
                let stop = snapshot.stops[i]
                let weather = env.weather
                let alerts = env.alerts
                group.addTask {
                    async let f: ForecastResult? = try? await weather.forecast(at: stop.coordinate, for: stop.eta)
                    async let a = alerts.alerts(at: stop.coordinate, eta: stop.eta)
                    return (i, await f, await a)
                }
            }
            var out: [(Int, ForecastResult?, [WeatherAlert])] = []
            for await r in group {
                out.append(r)
                done += 1
                phase = .briefing(done: done, total: total, routeLabel: routeLabel)
            }
            return out
        }
        for (i, forecast, alerts) in results {
            env.status.countCall(.weatherkit)
            if let forecast {
                b.stops[i].weather = forecast.snapshot
                b.stops[i].horizon = forecast.horizon
                env.status.recordSuccess(.weatherkit, count: 1)
            } else {
                b.stops[i].weather = nil
                b.stops[i].horizon = .failed
                env.status.recordError(.weatherkit, "Forecast failed for \(b.stops[i].label)")
            }
            b.stops[i].forecastFor = b.stops[i].eta
            b.stops[i].alerts = alerts
        }
    }

    // MARK: Stop mutations (web onStopsMutated / refreshForecasts / insert / remove)

    func updateDwell(stopID: Stop.ID, minutes: Int) {
        mutateBriefing { b in
            guard let i = b.stops.firstIndex(where: { $0.id == stopID }) else { return }
            b.stops[i].dwellMinutes = max(0, minutes)
        }
    }

    func toggleManualOvernight(stopID: Stop.ID, on: Bool) {
        mutateBriefing { b in
            guard let i = b.stops.firstIndex(where: { $0.id == stopID }) else { return }
            b.stops[i].manualOvernight = on
        }
    }

    func removeStop(stopID: Stop.ID) {
        mutateBriefing { b in StopEditReplayer.remove(stopID: stopID, from: &b) }
    }

    private func mutateBriefing(_ change: (inout Briefing) -> Void) {
        guard var b = briefing else { return }
        change(&b)
        ETACalculator.recompute(&b, fallbackTimeZone: plan.departureTimeZone)
        briefings[selectedRouteIndex] = b
    }

    /// Web `refreshForecasts`: refetch weather + alerts at the current ETAs.
    func refreshForecasts() async {
        guard var b = briefing else { return }
        phase = .refreshing(done: 0, total: b.stops.count)
        await fetchWeather(for: &b, indices: Array(b.stops.indices), routeLabel: b.routeLabel ?? "")
        b.generatedAt = Date()
        briefings[selectedRouteIndex] = b
        phase = .idle
        statusMessage = "Forecasts refreshed for current ETAs."
    }

    /// Web `insertManualStop` from a POI pin ("Add as fuel stop").
    func addStop(from poi: POI) async {
        await addStop(ManualStopEdit(coordinate: poi.coordinate, label: poi.name, poiKind: poi.kind, poiSourceID: poi.sourceID))
    }

    func addStop(_ edit: ManualStopEdit) async {
        guard var b = briefing else { errorMessage = "Generate a briefing first."; return }
        guard let stop = StopEditReplayer.insert(edit, into: &b) else { errorMessage = "Couldn't project onto the route."; return }
        ETACalculator.recompute(&b, fallbackTimeZone: plan.departureTimeZone)
        guard let i = b.stops.firstIndex(where: { $0.id == stop.id }) else { return }
        if b.stops[i].timeZoneID == nil, let tz = await env.timeZones.timeZone(at: b.stops[i].coordinate) {
            b.stops[i].timeZoneID = tz.identifier
            ETACalculator.recompute(&b, fallbackTimeZone: plan.departureTimeZone)
        }
        phase = .refreshing(done: 0, total: 1)
        await fetchWeather(for: &b, indices: [i], routeLabel: b.routeLabel ?? "")
        briefings[selectedRouteIndex] = b
        phase = .idle
        let off = stop.offRouteMi ?? 0
        statusMessage = "Added “\(edit.label)” (\(off < 1 ? "snapped to route" : "~\(Int(off.rounded())) mi off route"))."
    }

    private func replayEdits(_ edits: StopEdits, into b: inout Briefing) async {
        for id in StopEditReplayer.stopsToRemove(in: b.stops, removedMi: edits.removedMi) {
            StopEditReplayer.remove(stopID: id, from: &b)
        }
        ETACalculator.recompute(&b, fallbackTimeZone: plan.departureTimeZone)
        var added: [Int] = []
        for m in edits.manualStops {
            if let s = StopEditReplayer.insert(m, into: &b) {
                ETACalculator.recompute(&b, fallbackTimeZone: plan.departureTimeZone)
                if let i = b.stops.firstIndex(where: { $0.id == s.id }) { added.append(i) }
            }
        }
        if !added.isEmpty {
            await resolveTimeZones(&b)
            ETACalculator.recompute(&b, fallbackTimeZone: plan.departureTimeZone)
            // Indices may have shifted after recompute's sort; refetch by id.
            let ids = Set(added.compactMap { b.stops.indices.contains($0) ? b.stops[$0].id : nil })
            let indices = b.stops.indices.filter { ids.contains(b.stops[$0].id) }
            await fetchWeather(for: &b, indices: indices, routeLabel: b.routeLabel ?? "")
        }
    }

    // MARK: POI layers (web loadPoiLayer / refreshPoiLayers)

    func setPOILayer(_ kind: POIKind, enabled: Bool) {
        if enabled { poiLayersEnabled.insert(kind) } else { poiLayersEnabled.remove(kind) }
        Task { await refreshPOILayers() }
    }

    func refreshPOILayers() async {
        guard let route = selectedRoute else { corridorPOIs = [:]; return }
        var next: [POIKind: [POI]] = [:]
        for kind in poiLayersEnabled {
            do {
                let all = try await env.pois.pois(kind: kind)
                next[kind] = CorridorFilter.filter(all, kind: kind, alongRoute: route.coordinates)
            } catch {
                env.status.recordError(DataSource(kind), error.localizedDescription)
            }
        }
        corridorPOIs = next
    }

    // MARK: Saved trips

    func save(name: String) throws {
        loadedTrip = try env.trips.save(plan: plan, name: name, selectedRouteIndex: max(0, selectedRouteIndex), briefing: briefing, existing: loadedTrip)
        statusMessage = "Trip “\(name)” saved."
    }

    /// Loads a saved trip: restores the plan and any cached briefing so it is
    /// viewable offline; routes are re-found only when the user asks.
    func load(_ trip: TripRecord) {
        resetRoutes()
        loadedTrip = trip
        plan = env.trips.plan(from: trip)
        plan.originText = plan.origin?.query ?? ""
        plan.destinationText = plan.destination?.query ?? ""
        plan.viaTexts = plan.vias.map(\.query)
        let cached = env.trips.cachedBriefings(for: trip)
        for b in cached {
            briefings[b.routeIndex] = b
            while routes.count <= b.routeIndex {
                routes.append(RouteGeometry(coordinates: [], distanceMi: 0, durationSec: 0))
            }
            routes[b.routeIndex] = b.geometry
        }
        selectedRouteIndex = routes.isEmpty ? -1 : min(trip.selectedRouteIndex, routes.count - 1)
        statusMessage = cached.isEmpty ? "Trip loaded — find routes to continue." : "Showing cached briefing from \(RelativeDateTimeFormatter().localizedString(for: cached[0].generatedAt, relativeTo: Date()))."
        Task { await refreshPOILayers() }
    }
}
