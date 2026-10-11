import RoadTripCore
import SwiftUI

/// Best-time-to-leave (web optimizer panel): pick a window, score evenly
/// spaced departures, tap a result to adopt it and regenerate the briefing.
struct OptimizerView: View {
    @Bindable var coordinator: BriefingCoordinator
    @Environment(\.dismiss) private var dismiss
    @State private var start = Date()
    @State private var end = Date()

    private var tz: TimeZone { coordinator.plan.departureTimeZone }
    private var running: Bool { if case .optimizing = coordinator.phase { true } else { false } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("From", selection: $start, displayedComponents: [.date, .hourAndMinute])
                    DatePicker("To", selection: $end, in: start..., displayedComponents: [.date, .hourAndMinute])
                    Text(windowSummary).font(.caption).foregroundStyle(Theme.muted)
                } header: {
                    Text("Departure window")
                } footer: {
                    Text("Times in \(tz.identifier). Each candidate is a full forecast run (~1 WeatherKit call per stop).")
                }
                .environment(\.timeZone, tz)

                Section {
                    if case let .optimizing(done, total) = coordinator.phase {
                        ProgressView(value: Double(done), total: Double(max(1, total))) {
                            Text("Optimizing — \(done) / \(total)").monospacedDigit()
                        }
                        Button("Cancel", role: .cancel) { coordinator.cancelOptimizer() }
                    } else {
                        Button("Find the best time to leave") { coordinator.startOptimizer(windowStart: start, windowEnd: end) }
                            .disabled(end <= start || coordinator.isBusy)
                    }
                    if let e = coordinator.errorMessage { Text(e).font(.footnote).foregroundStyle(Theme.danger) }
                }

                if let result = coordinator.optimizer, !running {
                    if result.cancelled { Text("Cancelled — partial results.").font(.footnote).foregroundStyle(Theme.warn) }
                    if result.isMatrix {
                        OptimizerMatrix(result: result, coordinator: coordinator, timeZone: tz) { adopt($0) }
                    } else {
                        Section("Ranked departures") {
                            ForEach(Array(result.ranked.enumerated()), id: \.element.id) { i, cell in
                                Button { adopt(cell) } label: { OptimizerRow(cell: cell, isBest: i == 0, timeZone: tz) }
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Best time to leave")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { coordinator.cancelOptimizer(); dismiss() }
                }
            }
            .onAppear {
                let w = coordinator.optimizer.map { ($0.windowStart, $0.windowEnd) } ?? coordinator.defaultOptimizerWindow
                start = w.0
                end = w.1
            }
        }
    }

    private var windowSummary: String {
        let n = DepartureCandidates.count(windowStart: start, windowEnd: end, routeCount: coordinator.optimizableRouteIndices.count)
        let routes = coordinator.optimizableRouteIndices.count
        return end > start ? "\(n) departures\(routes > 1 ? " × \(routes) routes" : "")" : "End must be after start"
    }

    private func adopt(_ cell: OptimizerCell) {
        dismiss()
        Task { await coordinator.adopt(cell) }
    }
}

struct OptimizerRow: View {
    let cell: OptimizerCell
    let isBest: Bool
    let timeZone: TimeZone

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(Fmt.clock(cell.departure, timeZone: timeZone)).fontWeight(.semibold)
                if isBest { Tag(text: "Best", color: Theme.ok) }
                Spacer()
                Text("wx score \(cell.score)").monospacedDigit().foregroundStyle(Theme.accent)
            }
            Text(detail(cell, fallback: timeZone)).font(.caption).foregroundStyle(Theme.muted)
        }
        .contentShape(Rectangle())
    }
}

/// Departure × route grid with ★ on the best cell (web `renderOptimizerMatrix`).
struct OptimizerMatrix: View {
    let result: OptimizerResult
    let coordinator: BriefingCoordinator
    let timeZone: TimeZone
    let adopt: (OptimizerCell) -> Void

    var body: some View {
        let best = result.best
        Section("Score by departure and route — lower is better") {
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 8) {
                GridRow {
                    Text("Depart").font(.caption).foregroundStyle(Theme.muted)
                    ForEach(result.routeIndices, id: \.self) { j in
                        Text(shortLabel(j)).font(.caption).foregroundStyle(Theme.routeColor(j)).lineLimit(1)
                    }
                }
                ForEach(result.rows.indices, id: \.self) { r in
                    GridRow {
                        Text(Fmt.time(result.rows[r][0].departure, timeZone: timeZone)).font(.caption.monospacedDigit())
                        ForEach(result.rows[r]) { cell in
                            Button { adopt(cell) } label: {
                                VStack(spacing: 0) {
                                    Text("\(cell.score)\(cell.id == best?.id ? " ★" : "")").font(.callout.monospacedDigit().weight(.semibold))
                                    Text("arr \(Fmt.time(cell.arrival, timeZone: cell.arrivalTimeZoneID.flatMap(TimeZone.init(identifier:)) ?? timeZone))")
                                        .font(.caption2.monospacedDigit()).foregroundStyle(Theme.muted)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(6)
                                .background(cell.id == best?.id ? Theme.ok.opacity(0.18) : Theme.surface, in: RoundedRectangle(cornerRadius: 6))
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Depart \(Fmt.clock(cell.departure, timeZone: timeZone)) on \(cell.routeLabel), score \(cell.score). \(detail(cell, fallback: timeZone))")
                        }
                    }
                }
            }
        }
    }

    private func shortLabel(_ j: Int) -> String {
        let l = coordinator.routes.indices.contains(j) ? (coordinator.routes[j].label ?? "Route \(j + 1)") : "Route \(j + 1)"
        return l.count > 16 ? String(l.prefix(15)) + "…" : l
    }
}

/// "arrive 6:55 PM CDT · worst Thunderstorm near Amarillo".
private func detail(_ cell: OptimizerCell, fallback: TimeZone) -> String {
    let arriveTZ = cell.arrivalTimeZoneID.flatMap(TimeZone.init(identifier:)) ?? fallback
    var parts = ["arrive \(Fmt.clock(cell.arrival, timeZone: arriveTZ)) \(Fmt.zoneAbbreviation(cell.arrival, timeZone: arriveTZ))"]
    if let c = cell.worstCondition, let near = cell.worstNear { parts.append("worst: \(c.label) near \(near)") }
    if cell.failedForecasts > 0 { parts.append("\(cell.failedForecasts) forecast\(cell.failedForecasts == 1 ? "" : "s") unavailable") }
    return parts.joined(separator: " · ")
}
