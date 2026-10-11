import RoadTripCore
import SwiftUI

/// One stop card (web `renderStops`): tag, place, temp, ETA in the stop's
/// zone, condition badge, wind with head/tail/cross chip, leg chip, dwell
/// and overnight controls.
struct StopCardView: View {
    let stop: Stop
    let index: Int
    let total: Int
    let rangeMi: Double
    let scale: TemperatureScale
    let fallbackTZ: TimeZone
    let onDwell: (Int) -> Void
    let onOvernight: (Bool) -> Void
    let onRemove: () -> Void

    private var isInterior: Bool { index > 0 && index < total - 1 }
    /// " · 0.4 mi off route" (or " · on route").
    private var offRouteText: String {
        guard let off = stop.offRouteMi else { return "" }
        return off < 0.1 ? " · on route" : " · \(String(format: "%.1f", off)) mi off route"
    }
    private var tempColor: Color { Color(hex: scale.colorHex(forTemperatureF: stop.weather.map { Double($0.temperatureF) })) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Tag(text: stop.tag(index: index, total: total), color: Theme.muted)
                if let w = stop.weather {
                    Image(systemName: w.category.symbolName).foregroundStyle(w.category.badgeColor)
                }
                Text(stop.label).fontWeight(.semibold).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                Spacer()
                if let w = stop.weather {
                    Text("\(w.temperatureF)°").font(.title3.monospacedDigit().weight(.bold)).foregroundStyle(tempColor)
                } else {
                    Text(stop.horizon == .beyondHorizon ? "—" : "ERR").font(.caption.weight(.bold)).foregroundStyle(Theme.danger)
                }
                if NavigationLinks.isNavigable(stopIndex: index) { NavigateMenu(stop: stop) }
            }

            HStack(spacing: 6) {
                Text("↳ ETA \(stop.etaText(fallback: fallbackTZ))").foregroundStyle(Theme.accent)
                Text(stop.zoneText(fallback: fallbackTZ)).foregroundStyle(Theme.muted)
                if let w = stop.weather { Tag(text: w.kind.rawValue, color: Theme.muted) }
                if stop.isForecastStale { Tag(text: "stale", color: Theme.warn) }
                if stop.isOvernight { Tag(text: "☾ overnight", color: Theme.warn) }
            }
            .font(.caption.monospacedDigit())

            if stop.isOvernight, let resume = stop.resume {
                Text("↦ Resume \(Fmt.clock(resume, timeZone: stop.timeZone(fallback: fallbackTZ)))")
                    .font(.caption.monospacedDigit()).foregroundStyle(Theme.warn)
            }

            if !stop.alerts.isEmpty {
                FlowRow(items: stop.alerts.map { "⚠ \($0.event)" }, color: Theme.danger)
            }

            if let kind = stop.poiKind, kind.isFuel, stop.kind == .planned || stop.kind == .poi {
                Label("Fuel stop\(offRouteText)", systemImage: "fuelpump.fill")
                    .font(.caption).foregroundStyle(Theme.ok)
            } else if stop.poiKind == .rest, stop.planNote == nil {
                Label("Rest area\(offRouteText)", systemImage: "bed.double").font(.caption).foregroundStyle(Theme.muted)
            }
            if let note = stop.planNote {
                Label(note, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(Theme.warn)
            }

            if let charger = stop.chargers.first {
                (Text("⚡ Supercharger: ").foregroundStyle(Theme.warn) + Text(charger.summary))
                    .font(.caption)
                    .accessibilityLabel("Nearest Supercharger: \(charger.summary)")
            }

            if let w = stop.weather {
                FlowRow(items: metaChips(w), color: Theme.muted)
            } else {
                Text(stop.horizon == .beyondHorizon ? "Beyond the 10-day forecast horizon" : "Weather fetch failed")
                    .font(.caption).foregroundStyle(Theme.danger)
            }

            if isInterior {
                Divider().overlay(Theme.muted.opacity(0.3))
                Stepper(value: Binding(get: { stop.dwellMinutes }, set: { onDwell($0) }), in: 0...600, step: 5) {
                    Text("Dwell \(stop.dwellMinutes) min").font(.caption.monospacedDigit())
                }
                HStack(spacing: 12) {
                    Toggle(isOn: Binding(get: { stop.isOvernight }, set: { onOvernight($0) })) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Stay overnight here").font(.caption)
                            if stop.autoOvernight {
                                Text("Set automatically — daily drive limit reached").font(.caption2).foregroundStyle(Theme.muted)
                            }
                        }
                    }
                    .toggleStyle(.switch)
                    .disabled(stop.autoOvernight)
                    Button(role: .destructive, action: onRemove) {
                        Label("Remove", systemImage: "xmark.circle").font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityLabel("Remove \(stop.label)")
                }
            }
        }
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 10).fill(stop.isOvernight ? Theme.warn : tempColor).frame(width: 3).padding(.vertical, 6)
        }
    }

    private func metaChips(_ w: WeatherSnapshot) -> [String] {
        var chips: [String] = [w.category.label]
        var wind = "Wind \(w.windMph) mph"
        if let deg = w.windFromDegrees {
            wind += " \(Wind.compass(degrees: deg))"
            if let rel = Wind.relative(windFrom: deg, travelBearing: stop.travelBearing) { wind += " · \(rel.chipLabel)" }
        }
        chips.append(wind)
        chips.append("Feels \(w.feelsLikeF)°")
        if let h = w.humidityPercent { chips.append("Humidity \(h)%") }
        if let p = w.precipitationPercent { chips.append("Precip \(p)%") }
        // WeatherKit's description often repeats the category ("Clear").
        if !w.conditionText.isEmpty, w.conditionText.caseInsensitiveCompare(w.category.label) != .orderedSame {
            chips.append(w.conditionText)
        }
        if index > 0 {
            let over = stop.legExceedsRange(rangeMi)
            chips.append("\(over ? "⚠ " : "")+\(Int(stop.legMi.rounded())) mi leg")
        }
        chips.append("mile \(Int(stop.distanceMi.rounded()))")
        return chips
    }
}

/// Simple wrapping row of caption chips.
/// Chips that wrap to the next line at their natural width (the old
/// fixed-column grid truncated "Wind 11 mph S · headwind").
struct FlowRow: View {
    let items: [String]
    let color: Color

    var body: some View {
        FlowLayout(horizontalSpacing: 14, verticalSpacing: 4) {
            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(item.hasPrefix("⚠") ? Theme.danger : color)
            }
        }
    }
}

/// Left-aligned wrapping layout: each subview gets its ideal width (capped
/// at the row width, where it may wrap its own text) and moves to a new line
/// when it doesn't fit.
struct FlowLayout: Layout {
    var horizontalSpacing: CGFloat = 8
    var verticalSpacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, maxWidth: proposal.width ?? .infinity)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + verticalSpacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, maxWidth: bounds.width) {
            var x = bounds.minX
            for item in row.items {
                subviews[item.index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(item.size))
                x += item.size.width + horizontalSpacing
            }
            y += row.height + verticalSpacing
        }
    }

    private struct Row {
        var items: [(index: Int, size: CGSize)] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for i in subviews.indices {
            var size = subviews[i].sizeThatFits(.unspecified)
            if size.width > maxWidth {
                size = subviews[i].sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
            }
            let needed = row.items.isEmpty ? size.width : row.width + horizontalSpacing + size.width
            if !row.items.isEmpty && needed > maxWidth {
                rows.append(row)
                row = Row()
            }
            row.width = row.items.isEmpty ? size.width : row.width + horizontalSpacing + size.width
            row.height = max(row.height, size.height)
            row.items.append((i, size))
        }
        if !row.items.isEmpty { rows.append(row) }
        return rows
    }
}
