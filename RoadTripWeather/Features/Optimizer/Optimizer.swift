import Foundation
import RoadTripCore

/// One scored departure on one route (web optimizer cell).
struct OptimizerCell: Identifiable, Hashable, Sendable {
    var id: String { "\(routeIndex)@\(Int(departure.timeIntervalSince1970))" }
    var departure: Date
    var routeIndex: Int
    var routeLabel: String
    var score: Int
    var arrival: Date
    var arrivalTimeZoneID: String?
    /// "Thunderstorm near Amarillo" (web `worst: … near …`).
    var worstCondition: ConditionCategory?
    var worstNear: String?
    /// Stops whose forecast failed and were scored as unknown weather.
    var failedForecasts: Int
}

/// Web `runOptimizer` output: a ranked list for one route, or a
/// departure × route matrix when several routes were found.
struct OptimizerResult: Sendable {
    var windowStart: Date
    var windowEnd: Date
    var routeIndices: [Int]
    /// Rows by departure; each row has one cell per route in `routeIndices`.
    var rows: [[OptimizerCell]]
    var isMatrix: Bool { routeIndices.count > 1 }
    /// True when Cancel stopped the run early.
    var cancelled = false

    var cells: [OptimizerCell] { rows.flatMap { $0 } }

    /// Lowest score; ties go to the earlier candidate (web `reduce(<=)`).
    var best: OptimizerCell? {
        cells.reduce(nil) { best, c in
            guard let b = best else { return c }
            return c.score < b.score ? c : b
        }
    }

    /// Single-route list, best first; ties keep departure order (JS sort is stable).
    var ranked: [OptimizerCell] {
        cells.enumerated().sorted { l, r in
            l.element.score != r.element.score ? l.element.score < r.element.score : l.offset < r.offset
        }.map(\.element)
    }
}

extension BriefingCoordinator {
    /// Web default window: the planned departure to 12 h later.
    var defaultOptimizerWindow: (start: Date, end: Date) {
        (plan.departure, plan.departure.addingTimeInterval(12 * 3600))
    }

    /// Routes the optimizer can brief (cached-only placeholders are skipped).
    var optimizableRouteIndices: [Int] {
        routes.indices.filter { routes[$0].coordinates.count >= 2 }
    }

    func startOptimizer(windowStart: Date, windowEnd: Date) {
        optimizerTask?.cancel()
        optimizerTask = Task { await runOptimizer(windowStart: windowStart, windowEnd: windowEnd) }
    }

    func cancelOptimizer() {
        optimizerTask?.cancel()
    }

    /// Briefs every candidate departure (× every route) off-screen and
    /// scores it. Never changes `briefings`, the drafts or the plan.
    func runOptimizer(windowStart: Date, windowEnd: Date) async {
        errorMessage = nil
        let routeIndices = optimizableRouteIndices
        guard !routeIndices.isEmpty else { errorMessage = "Find routes first."; return }
        let departures = DepartureCandidates.candidates(windowStart: windowStart, windowEnd: windowEnd, routeCount: routeIndices.count)
        guard !departures.isEmpty else { errorMessage = "Set a valid optimizer window (end after start)."; return }

        let total = departures.count * routeIndices.count
        var step = 0
        var result = OptimizerResult(windowStart: windowStart, windowEnd: windowEnd, routeIndices: routeIndices, rows: [])
        phase = .optimizing(done: 0, total: total)
        defer { phase = .idle }

        for departure in departures {
            var row: [OptimizerCell] = []
            for j in routeIndices {
                if Task.isCancelled { result.cancelled = true; break }
                let label = routes[j].label ?? "Route \(j + 1)"
                guard let b = await brief(routeIndex: j, label: label, departure: departure, progress: { _, _ in }) else { continue }
                row.append(Self.cell(for: b, departure: departure, label: label))
                step += 1
                phase = .optimizing(done: step, total: total)
            }
            if !row.isEmpty { result.rows.append(row) }
            if result.cancelled { break }
        }
        optimizer = result
        if let best = result.best {
            let route = result.isMatrix ? " on \(best.routeLabel)" : ""
            statusMessage = "\(result.cancelled ? "Optimizer cancelled" : "Optimizer done") — best: depart \(Fmt.clock(best.departure, timeZone: plan.departureTimeZone))\(route) (score \(best.score))."
        } else if result.cancelled {
            statusMessage = "Optimizer cancelled."
        }
    }

    /// Adopts a result: its departure (and route) become the plan, then the
    /// briefing is regenerated (web: click a result → regenerate).
    func adopt(_ cell: OptimizerCell) async {
        plan.departure = cell.departure
        if routes.indices.contains(cell.routeIndex) { selectedRouteIndex = cell.routeIndex }
        await generateBriefing()
    }

    static func cell(for b: Briefing, departure: Date, label: String) -> OptimizerCell {
        let scored = TripScorer.score(b.stops)
        let worst = scored.worstStopIndex.flatMap { b.stops.indices.contains($0) ? b.stops[$0] : nil }
        let last = b.stops.last
        return OptimizerCell(
            departure: departure,
            routeIndex: b.routeIndex,
            routeLabel: label,
            score: scored.score,
            arrival: last?.eta ?? departure,
            arrivalTimeZoneID: last?.timeZoneID,
            worstCondition: worst?.weather?.category,
            worstNear: worst.map(TripScorer.nearLabel(for:)),
            failedForecasts: b.stops.filter { $0.weather == nil }.count
        )
    }
}
