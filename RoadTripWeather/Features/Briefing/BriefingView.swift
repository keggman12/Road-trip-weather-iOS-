import Charts
import MapKit
import RoadTripCore
import SwiftUI

/// Map + summary + alerts + precip timeline + stop cards for the selected route.
struct BriefingView: View {
    @Bindable var coordinator: BriefingCoordinator
    @Environment(AppEnvironment.self) private var env
    @State private var showSave = false
    @State private var tripName = ""
    @State private var selectedPOI: POI?

    var body: some View {
        Group {
            if let briefing = coordinator.briefing {
                content(briefing)
            } else {
                ContentUnavailableView("No briefing", systemImage: "cloud.sun", description: Text("Generate a weather briefing from the Routes screen."))
            }
        }
        .background(Theme.background)
        .navigationTitle(coordinator.briefing?.routeLabel ?? "Briefing")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { tripName = coordinator.plan.defaultName; showSave = true } label: { Label("Save trip", systemImage: "bookmark") }
                    Button { Task { await coordinator.refreshForecasts() } } label: { Label("Refresh forecasts", systemImage: "arrow.clockwise") }
                    Section("POI layers") {
                        ForEach(POIKind.allCases) { kind in
                            Toggle(kind.displayName.capitalized, isOn: Binding(
                                get: { coordinator.poiLayersEnabled.contains(kind) },
                                set: { coordinator.setPOILayer(kind, enabled: $0) }
                            ))
                        }
                    }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .alert("Trip name", isPresented: $showSave) {
            TextField("Name", text: $tripName)
            Button("Save") { try? coordinator.save(name: tripName) }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(item: $selectedPOI) { poi in
            POICalloutView(poi: poi, briefing: coordinator.briefing) {
                selectedPOI = nil
                Task { await coordinator.addStop(from: poi) }
            }
            .presentationDetents([.height(220)])
        }
    }

    @ViewBuilder
    private func content(_ briefing: Briefing) -> some View {
        let fallbackTZ = coordinator.plan.departureTimeZone
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                BriefingMapView(
                    briefing: briefing,
                    dimmed: coordinator.briefings.values.filter { $0.routeIndex != briefing.routeIndex },
                    scale: env.settings.temperatureScale,
                    pois: coordinator.corridorPOIs,
                    onPOITap: { selectedPOI = $0 }
                )
                .frame(height: 320)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                if case let .refreshing(done, total) = coordinator.phase {
                    ProgressView(value: Double(done), total: Double(max(1, total))) { Text("Refreshing \(done) / \(total)") }
                }

                DataAgeBanner(briefing: briefing)
                if briefing.isStale {
                    StaleBanner(count: briefing.staleStops.count) { Task { await coordinator.refreshForecasts() } }
                }
                if let msg = coordinator.statusMessage { Text(msg).font(.footnote).foregroundStyle(Theme.muted) }
                if let e = coordinator.errorMessage { Text(e).font(.footnote).foregroundStyle(Theme.danger) }

                SummaryView(briefing: briefing, fallbackTZ: fallbackTZ)
                AlertsBanner(alerts: briefing.alerts)
                PrecipTimelineView(stops: briefing.stops)

                Text("Stops").font(.headline).padding(.top, 4)
                ForEach(Array(briefing.stops.enumerated()), id: \.element.id) { i, stop in
                    StopCardView(
                        stop: stop,
                        index: i,
                        total: briefing.stops.count,
                        rangeMi: briefing.rangeMi,
                        scale: env.settings.temperatureScale,
                        fallbackTZ: fallbackTZ,
                        onDwell: { coordinator.updateDwell(stopID: stop.id, minutes: $0) },
                        onOvernight: { coordinator.toggleManualOvernight(stopID: stop.id, on: $0) },
                        onRemove: { coordinator.removeStop(stopID: stop.id) }
                    )
                }

                if let url = coordinator.weatherAttributionURL ?? briefing.weatherAttributionURL.flatMap(URL.init(string:)) {
                    Link(destination: url) {
                        Text("Weather data by \u{F8FF} Weather · Legal").font(.caption).foregroundStyle(Theme.muted)
                    }
                    .padding(.top, 8)
                }
            }
            .padding()
        }
    }
}

struct DataAgeBanner: View {
    let briefing: Briefing

    var body: some View {
        // Re-render each minute so "generated 3 hours ago" stays true while
        // a cached briefing sits on screen.
        TimelineView(.periodic(from: .now, by: 60)) { context in
            HStack {
                Image(systemName: "clock")
                Text("Briefing generated \(Fmt.age(briefing.generatedAt, now: context.date))")
                Spacer()
                if briefing.dataAge(at: context.date) > 6 * 3600 {
                    Tag(text: "aging", color: Theme.warn)
                }
            }
            .font(.caption)
            .foregroundStyle(Theme.muted)
        }
    }
}

struct StaleBanner: View {
    let count: Int
    let refresh: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.arrow.circlepath").foregroundStyle(Theme.warn)
            Text("\(count) stop\(count == 1 ? "" : "s") drifted > 30 min from their forecast.")
            Spacer()
            Button("Refresh", action: refresh).buttonStyle(.borderedProminent).controlSize(.small)
        }
        .font(.footnote)
        .padding(10)
        .background(Theme.warn.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct SummaryView: View {
    let briefing: Briefing
    let fallbackTZ: TimeZone

    var body: some View {
        if let s = briefing.summary, let first = briefing.stops.first, let last = briefing.stops.last {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 18) {
                    Stat(value: "\(Int(s.distanceMi.rounded()))", unit: "mi")
                    Stat(value: Fmt.duration(s.driveSeconds), unit: s.pausedSeconds > 0 ? "+ \(Fmt.duration(s.pausedSeconds)) stopped" : "drive")
                    Stat(value: "\(s.stopCount)", unit: s.overnightCount > 0 ? "stops (+\(s.overnightCount)☾)" : "stops")
                }
                Text("Depart \(Fmt.clock(s.departure, timeZone: first.timeZone(fallback: fallbackTZ))) · Arrive \(Fmt.clock(s.arrival, timeZone: last.timeZone(fallback: fallbackTZ))) \(last.zoneText(fallback: fallbackTZ))")
                    .font(.footnote).foregroundStyle(Theme.muted)
            }
            .padding(12)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
        }
    }
}

struct Stat: View {
    let value: String
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(.title3.monospacedDigit().weight(.semibold))
            Text(unit).font(.caption2).foregroundStyle(Theme.muted)
        }
    }
}

struct AlertsBanner: View {
    let alerts: [WeatherAlert]

    var body: some View {
        if !alerts.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("⚠ \(alerts.count) weather alert\(alerts.count == 1 ? "" : "s") in effect during your transit (NWS)")
                    .font(.footnote.weight(.bold))
                ForEach(alerts) { a in
                    HStack(alignment: .top, spacing: 4) {
                        Text(a.event).fontWeight(.semibold)
                        if a.severity != .unknown { Text("(\(a.severity.rawValue))") }
                        if let ends = a.ends { Text("· until \(Fmt.clock(ends, timeZone: .current))") }
                    }
                    .font(.caption)
                    Text(a.areaDescription).font(.caption2).foregroundStyle(Theme.muted)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.danger.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
            .foregroundStyle(Theme.danger)
        }
    }
}

/// Web `renderPrecipChart`: hidden unless ≥ 2 stops have precip; red for
/// thunderstorm/severe/snow, amber ≥ 50 %, label from 15 %.
struct PrecipTimelineView: View {
    let stops: [Stop]

    struct Point: Identifiable {
        var id: UUID
        var label: String
        var percent: Int
        var hazardous: Bool
    }

    var points: [Point] {
        let n = stops.count
        return stops.enumerated().compactMap { i, s in
            guard let w = s.weather, let p = w.precipitationPercent else { return nil }
            let label = i == 0 ? "DEP" : i == n - 1 ? "ARR" : "\(Int(s.distanceMi.rounded()))"
            return Point(id: s.id, label: label, percent: p, hazardous: w.category.isHazardousPrecipitation)
        }
    }

    enum BarTone: Equatable { case severe, high, normal }

    /// Web: red for thunderstorm/severe/snow, amber from 50 %, else accent.
    static func tone(_ p: Point) -> BarTone {
        p.hazardous ? .severe : p.percent >= 50 ? .high : .normal
    }

    static func barColor(_ p: Point) -> Color {
        switch tone(p) {
        case .severe: Theme.danger
        case .high: Theme.warn
        case .normal: Theme.accent.opacity(0.7)
        }
    }

    /// Web shows the value from 15 %.
    static func showsValue(_ p: Point) -> Bool { p.percent >= 15 }

    var body: some View {
        let pts = points
        if pts.count >= 2 {
            VStack(alignment: .leading, spacing: 6) {
                Text("Precip probability by stop").font(.caption).foregroundStyle(Theme.muted)
                Chart(pts) { p in
                    // Web draws at least a 1.5 px sliver so 0 % stops still show.
                    BarMark(x: .value("Stop", p.label), y: .value("Precip %", max(Double(p.percent), 1.5)))
                        .foregroundStyle(Self.barColor(p))
                        .annotation(position: .top) {
                            if Self.showsValue(p) { Text("\(p.percent)").font(.caption2.monospacedDigit()).foregroundStyle(Theme.muted) }
                        }
                }
                .chartYScale(domain: 0...100)
                .chartYAxis { AxisMarks(values: [0, 50, 100]) }
                .frame(height: 110)
            }
            .padding(12)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
        }
    }
}

struct POICalloutView: View {
    let poi: POI
    let briefing: Briefing?
    let add: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(poi.name).font(.headline)
            Text(poi.detail ?? poi.kind.displayName).font(.subheadline).foregroundStyle(Theme.muted)
            if let near = briefing?.nearestForecastStop(to: poi.coordinate), let w = near.weather {
                HStack(spacing: 6) {
                    Image(systemName: w.category.symbolName).foregroundStyle(w.category.badgeColor)
                    Text("\(w.temperatureF)°F \(w.category.label)").monospacedDigit()
                    Text("(nearest stop fcst)").foregroundStyle(Theme.muted)
                }.font(.subheadline)
            } else {
                Text("no forecast nearby").font(.subheadline).foregroundStyle(Theme.muted)
            }
            Button(action: add) {
                Text(poi.kind.isFuel ? "+ Add as fuel stop" : "+ Add as stop").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .presentationBackground(Theme.surface)
    }
}
