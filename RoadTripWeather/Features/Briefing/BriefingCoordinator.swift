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
        case optimizing(done: Int, total: Int)
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
    /// Places that resolved to a different name than was typed.
    var placeNotices: [String] = []
    /// StopPlanner candidates per route index (cleared with the routes).
    var candidateCache: [Int: [StopPlanner.Candidate]] = [:]
    /// The saved trip the current plan came from, if any.
    var loadedTrip: TripRecord?
    /// Best-time-to-leave results (P2-4); never touches `briefings`.
    var optimizer: OptimizerResult?
    var optimizerTask: Task<Void, Never>?

    init(env: AppEnvironment) {
        self.env = env
        restoreSession()
    }

    var isBusy: Bool { phase != .idle }

    /// The on-screen briefing as a GPX file, named after the saved trip or
    /// "Origin → Destination". Works offline from a cached briefing.
    var gpxExport: GPXExport? {
        briefing.map { GPXExport(tripName: loadedTrip?.name ?? plan.defaultName, briefing: $0) }
    }
    var selectedRoute: RouteGeometry? { routes.indices.contains(selectedRouteIndex) ? routes[selectedRouteIndex] : nil }
    var briefing: Briefing? { briefings[selectedRouteIndex] }

    // MARK: Phase 1 — find routes (no weather calls)

    /// Find Routes is enabled once origin and destination have text (blank
    /// or whitespace doesn't count) and nothing else is running.
    var canFindRoutes: Bool {
        !isBusy
            && !plan.originText.trimmingCharacters(in: .whitespaces).isEmpty
            && !plan.destinationText.trimmingCharacters(in: .whitespaces).isEmpty
    }

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
            // A new search detaches from the saved trip it came from, so Save
            // creates a new trip instead of overwriting the old one.
            if let trip = loadedTrip, !Self.matches(trip, texts: texts) { loadedTrip = nil }
            placeNotices = zip(texts, points).compactMap { query, place in
                PlaceMatch.isLikelyMismatch(query: query, label: place.label) ? PlaceMatch.notice(query: query, label: place.label) : nil
            }
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
            routeNote = ([result.note].compactMap { $0 } + placeNotices.map { "⚠ " + $0 }).joined(separator: "\n").nilIfEmpty
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
        if !briefings.isEmpty { persistSession() }
        Task { await refreshPOILayers() }
    }

    /// True when `texts` (origin, vias…, destination) are the saved trip's queries.
    static func matches(_ trip: TripRecord, texts: [String]) -> Bool {
        let saved = [trip.originQuery] + (JSONCoding.decode([PlacePoint].self, from: trip.viasData) ?? []).map(\.query) + [trip.destQuery]
        let norm = { (s: [String]) in s.map { $0.trimmingCharacters(in: .whitespaces).lowercased() } }
        return norm(saved) == norm(texts)
    }

    private func resetRoutes() {
        routes = []
        routeNote = nil
        placeNotices = []
        candidateCache = [:]
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
        // Built off-screen: nothing reaches `briefings` (and the UI) until
        // it is complete and persisted.
        var fresh: [Int: Briefing] = [:]
        let wantChargers = await chargersWanted()
        for j in indices {
            if let b = await brief(routeIndex: j, label: routes[j].label ?? "Route \(j + 1)", withChargers: wantChargers) { fresh[j] = b }
        }
        if let edits = plan.stopEdits.isEmpty ? nil : plan.stopEdits, var b = fresh[selectedRouteIndex] {
            await replayEdits(edits, into: &b, withChargers: wantChargers)
            fresh[selectedRouteIndex] = b
            plan.stopEdits = StopEdits()
        }
        if weatherAttributionURL == nil { weatherAttributionURL = await env.weather.attributionURL() }
        // Persisted with the briefing so a cached trip can show it offline.
        if let url = weatherAttributionURL?.absoluteString {
            for j in fresh.keys { fresh[j]?.weatherAttributionURL = url }
        }
        persistSession(briefings.merging(fresh) { $1 })
        briefings.merge(fresh) { $1 }
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

    /// Builds one route's briefing off-screen. `departure` overrides the plan's
    /// (optimizer candidates); `progress` replaces the briefing phase updates.
    func brief(routeIndex j: Int, label: String, departure: Date? = nil, withChargers: Bool = false, progress: ((Int, Int) -> Void)? = nil) async -> Briefing? {
        let route = routes[j]
        let (stops0, totalMi) = StopPlanner.plan(
            route: route,
            rangeMi: plan.rangeMi,
            candidates: await stopCandidates(routeIndex: j),
            originLabel: plan.origin?.label ?? plan.originText,
            destinationLabel: plan.destination?.label ?? plan.destinationText
        )
        var b = Briefing(
            routeIndex: j,
            routeLabel: route.label,
            geometry: route,
            totalMi: totalMi,
            departure: departure ?? plan.departure,
            departureTimeZoneID: plan.departureTimeZoneID,
            rangeMi: Vehicle.clampRange(plan.rangeMi),
            multiDay: plan.multiDay,
            stops: stops0,
            generatedAt: Date()
        )
        guard !b.stops.isEmpty else { return nil }
        b.stops[0].timeZoneID = plan.origin?.timeZoneID
        if b.stops.count > 1 { b.stops[b.stops.count - 1].timeZoneID = plan.destination?.timeZoneID }
        ETACalculator.recompute(&b, fallbackTimeZone: plan.departureTimeZone)

        if progress == nil { phase = .briefing(done: 0, total: b.stops.count, routeLabel: label) }
        await resolveTimeZones(&b)
        // Time zones can change overnight resume times, so recompute.
        ETACalculator.recompute(&b, fallbackTimeZone: plan.departureTimeZone)
        await fetchWeather(for: &b, indices: Array(b.stops.indices), routeLabel: label, withChargers: withChargers, progress: progress)
        b.generatedAt = Date()
        return b
    }

    /// Fuel stops and rest areas in the route's corridor, projected onto it.
    /// Cached per route: the optimizer re-plans the same route many times.
    func stopCandidates(routeIndex j: Int) async -> [StopPlanner.Candidate] {
        if let cached = candidateCache[j] { return cached }
        let route = routes[j].coordinates
        var pois: [POI] = []
        for kind in POIKind.allCases {
            if let all = try? await env.pois.pois(kind: kind) {
                pois += CorridorFilter.filter(all, kind: kind, alongRoute: route)
            }
        }
        let candidates = StopPlanner.candidates(route: route, pois: pois)
        candidateCache[j] = candidates
        return candidates
    }

    /// Time zone for every stop that lacks one, and a real name ("I-25 near
    /// Pueblo, CO") for plain waypoints and generically named rest areas.
    private func resolveTimeZones(_ b: inout Briefing) async {
        for i in b.stops.indices {
            let s = b.stops[i]
            let needsName = s.kind == .sampled || (s.poiKind.map { StopNaming.isGeneric(s.label, kind: $0) } ?? false)
            guard s.timeZoneID == nil || needsName else { continue }
            guard let info = await env.timeZones.place(at: s.coordinate) else { continue }
            if s.timeZoneID == nil, let tz = info.timeZone { b.stops[i].timeZoneID = tz.identifier }
            if needsName, let name = info.stopLabel {
                b.stops[i].label = s.kind == .sampled ? name : "Rest area · \(name)"
            }
        }
    }

    /// Fetches weather + alerts for the given stops concurrently (web
    /// `fetchStopWeather`). Failures leave `weather == nil`, `horizon == .failed`.
    /// Web `wantChargers`: an EV vehicle and an Open Charge Map key.
    func chargersWanted() async -> Bool {
        guard let id = plan.vehicleID.flatMap(UUID.init(uuidString:)),
              env.trips.vehicles().first(where: { $0.id == id })?.isEV == true
        else { return false }
        return await env.chargers.isConfigured
    }

    private struct StopFetch: Sendable {
        var index: Int
        var forecast: ForecastResult?
        var alerts: [WeatherAlert]
        /// nil when chargers weren't requested for this stop.
        var chargers: Result<[Charger], ChargerLookupError>?
    }

    struct ChargerLookupError: Error { var message: String }

    /// Web `fetchStopWeather`: forecast + alerts (+ Superchargers when
    /// `withChargers`, never for the origin) for each stop, concurrently.
    /// `progress(done, total)` defaults to the briefing phase for `routeLabel`.
    func fetchWeather(for b: inout Briefing, indices: [Int], routeLabel: String, withChargers: Bool = false, progress: ((Int, Int) -> Void)? = nil) async {
        let total = indices.count
        var done = 0
        let snapshot = b
        let results = await withTaskGroup(of: StopFetch.self, returning: [StopFetch].self) { group in
            for i in indices {
                let stop = snapshot.stops[i]
                let weather = env.weather
                let alerts = env.alerts
                let chargers = env.chargers
                let wantChargers = withChargers && stop.kind != .origin
                group.addTask {
                    async let f: ForecastResult? = try? await weather.forecast(at: stop.coordinate, for: stop.eta)
                    async let a = alerts.alerts(at: stop.coordinate, eta: stop.eta)
                    async let c: Result<[Charger], ChargerLookupError>? = wantChargers ? Self.lookUpChargers(chargers, near: stop.coordinate) : nil
                    return StopFetch(index: i, forecast: await f, alerts: await a, chargers: await c)
                }
            }
            var out: [StopFetch] = []
            for await r in group {
                out.append(r)
                done += 1
                if let progress { progress(done, total) } else { phase = .briefing(done: done, total: total, routeLabel: routeLabel) }
            }
            return out
        }
        var failed: [String] = []
        var chargerCount = 0
        var chargerErrors: [String] = []
        for r in results.sorted(by: { $0.index < $1.index }) {
            let i = r.index
            env.status.countCall(.weatherkit)
            if let forecast = r.forecast {
                b.stops[i].weather = forecast.snapshot
                b.stops[i].horizon = forecast.horizon
            } else {
                b.stops[i].weather = nil
                b.stops[i].horizon = .failed
                failed.append(b.stops[i].label)
            }
            b.stops[i].forecastFor = b.stops[i].eta
            b.stops[i].alerts = r.alerts
            switch r.chargers {
            case nil:
                break
            case let .success(found)?:
                env.status.countCall(.openChargeMap)
                b.stops[i].chargers = found
                chargerCount += found.count
            case let .failure(e)?:
                env.status.countCall(.openChargeMap)
                b.stops[i].chargers = []
                chargerErrors.append(e.message)
            }
        }
        if failed.count < results.count {
            env.status.recordSuccess(.weatherkit, count: results.count - failed.count)
        }
        if !failed.isEmpty {
            env.status.recordError(.weatherkit, "\(failed.count) of \(results.count) forecasts failed (\(failed.prefix(3).joined(separator: ", ")))")
        }
        let lookups = results.filter { $0.chargers != nil }.count
        if lookups > chargerErrors.count { env.status.recordSuccess(.openChargeMap, count: chargerCount) }
        if let first = chargerErrors.first {
            env.status.recordError(.openChargeMap, "\(chargerErrors.count) of \(lookups) lookups failed (\(first))")
        }
    }

    private nonisolated static func lookUpChargers(_ service: any ChargerService, near c: Coordinate) async -> Result<[Charger], ChargerLookupError> {
        do { return .success(try await service.superchargers(near: c)) }
        catch { return .failure(ChargerLookupError(message: error.localizedDescription)) }
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
        persistSession()
    }

    /// Web `refreshForecasts`: refetch weather + alerts at the current ETAs.
    func refreshForecasts() async {
        guard var b = briefing else { return }
        phase = .refreshing(done: 0, total: b.stops.count)
        await fetchWeather(for: &b, indices: Array(b.stops.indices), routeLabel: b.routeLabel ?? "") { [weak self] done, total in
            self?.phase = .refreshing(done: done, total: total)
        }
        b.generatedAt = Date()
        briefings[selectedRouteIndex] = b
        persistSession()
        phase = .idle
        statusMessage = "Forecasts refreshed for current ETAs."
    }

    /// Web `insertManualStop` from a POI pin ("Add as fuel stop").
    func addStop(from poi: POI) async {
        await addStop(ManualStopEdit(coordinate: poi.coordinate, label: poi.name, poiKind: poi.kind, poiSourceID: poi.sourceID))
    }

    /// Web `addManualStop`: geocode typed text, insert it as a manual stop
    /// snapped to the route, fetch its forecast. Returns false (and changes
    /// nothing) when the place can't be found.
    @discardableResult
    func addStop(named text: String) async -> Bool {
        let query = text.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return false }
        guard briefing != nil else { errorMessage = "Generate a briefing first."; return false }
        errorMessage = nil
        phase = .geocoding(query)
        env.status.countCall(.mapkit)
        let place: PlacePoint
        do {
            place = try await env.geocoding.geocode(query)
            env.status.recordSuccess(.mapkit, count: 1)
        } catch {
            env.status.recordError(.mapkit, error.localizedDescription)
            errorMessage = error.localizedDescription
            phase = .idle
            return false
        }
        phase = .idle
        guard await addStop(ManualStopEdit(coordinate: place.coordinate, label: place.label)) else { return false }
        env.settings.remember(query)
        return true
    }

    @discardableResult
    func addStop(_ edit: ManualStopEdit) async -> Bool {
        guard var b = briefing else { errorMessage = "Generate a briefing first."; return false }
        guard let stop = StopEditReplayer.insert(edit, into: &b) else { errorMessage = "Couldn't project onto the route."; return false }
        ETACalculator.recompute(&b, fallbackTimeZone: plan.departureTimeZone)
        guard let i = b.stops.firstIndex(where: { $0.id == stop.id }) else { return false }
        if b.stops[i].timeZoneID == nil, let tz = await env.timeZones.timeZone(at: b.stops[i].coordinate) {
            b.stops[i].timeZoneID = tz.identifier
            ETACalculator.recompute(&b, fallbackTimeZone: plan.departureTimeZone)
        }
        phase = .refreshing(done: 0, total: 1)
        await fetchWeather(for: &b, indices: [i], routeLabel: b.routeLabel ?? "", withChargers: await chargersWanted()) { [weak self] done, total in
            self?.phase = .refreshing(done: done, total: total)
        }
        briefings[selectedRouteIndex] = b
        persistSession()
        phase = .idle
        let off = stop.offRouteMi ?? 0
        statusMessage = "Added “\(edit.label)” (\(off < 1 ? "snapped to route" : "~\(Int(off.rounded())) mi off route"))."
        return true
    }

    private func replayEdits(_ edits: StopEdits, into b: inout Briefing, withChargers: Bool) async {
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
            await fetchWeather(for: &b, indices: indices, routeLabel: b.routeLabel ?? "", withChargers: withChargers)
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

    /// Name the Save dialog suggests: the linked trip's, else the plan's.
    var suggestedTripName: String { loadedTrip?.name ?? plan.defaultName }

    /// Saves into the linked trip, or a new one when `asNew` or not linked.
    func save(name: String, asNew: Bool = false) throws {
        loadedTrip = try env.trips.save(plan: plan, name: name, selectedRouteIndex: max(0, selectedRouteIndex), briefing: briefing, existing: asNew ? nil : loadedTrip)
        persistSession()
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
        show(cached, selecting: trip.selectedRouteIndex)
        statusMessage = cached.isEmpty ? "Trip loaded — find routes to continue." : "Showing cached briefing from \(Fmt.age(cached[0].generatedAt))."
        if !cached.isEmpty { persistSession() }
        Task { await refreshPOILayers() }
    }

    /// Puts cached briefings on screen; their geometry stands in for routes
    /// until the user re-finds them.
    private func show(_ cached: [Briefing], selecting index: Int) {
        for b in cached {
            briefings[b.routeIndex] = b
            while routes.count <= b.routeIndex {
                routes.append(RouteGeometry(coordinates: [], distanceMi: 0, durationSec: 0))
            }
            routes[b.routeIndex] = b.geometry
        }
        selectedRouteIndex = routes.isEmpty ? -1 : max(0, min(index, routes.count - 1))
    }

    // MARK: Session persistence (task 8)

    /// Writes the session's briefings as drafts plus the plan behind them,
    /// so the latest briefing survives a relaunch without an explicit Save.
    private func persistSession(_ all: [Int: Briefing]? = nil) {
        do {
            try env.trips.replaceDrafts(with: Array((all ?? briefings).values))
            env.settings.session = AppSettings.Session(plan: plan, selectedRouteIndex: selectedRouteIndex, tripID: loadedTrip?.id)
        } catch {
            errorMessage = "Couldn't cache the briefing on this device: \(error.localizedDescription)"
        }
    }

    private func restoreSession() {
        guard let session = env.settings.session else { return }
        let drafts = env.trips.draftBriefings()
        guard !drafts.isEmpty else { return }
        plan = session.plan
        if let id = session.tripID { loadedTrip = env.trips.allTrips().first { $0.id == id } }
        show(drafts, selecting: session.selectedRouteIndex)
        statusMessage = "Restored your last briefing (generated \(Fmt.age(drafts[0].generatedAt)))."
    }
}
