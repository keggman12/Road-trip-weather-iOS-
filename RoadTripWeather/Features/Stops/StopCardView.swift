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
    private var tempColor: Color { Color(hex: scale.colorHex(forTemperatureF: stop.weather.map { Double($0.temperatureF) })) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Tag(text: stop.tag(index: index, total: total), color: Theme.muted)
                if let w = stop.weather {
                    Image(systemName: w.category.symbolName).foregroundStyle(w.category.badgeColor)
                }
                Text(stop.label).fontWeight(.semibold).lineLimit(1)
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

            if let w = stop.weather {
                FlowRow(items: metaChips(w), color: Theme.muted)
            } else {
                Text(stop.horizon == .beyondHorizon ? "Beyond the 10-day forecast horizon" : "Weather fetch failed")
                    .font(.caption).foregroundStyle(Theme.danger)
            }

            if isInterior {
                HStack(spacing: 14) {
                    Stepper(value: Binding(get: { stop.dwellMinutes }, set: { onDwell($0) }), in: 0...600, step: 5) {
                        Text("Dwell \(stop.dwellMinutes) min").font(.caption.monospacedDigit())
                    }
                    Toggle(isOn: Binding(get: { stop.manualOvernight }, set: { onOvernight($0) })) {
                        Text(stop.autoOvernight ? "Overnight (auto)" : "Overnight").font(.caption)
                    }
                    .disabled(stop.autoOvernight)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    Button(role: .destructive, action: onRemove) { Image(systemName: "xmark") }.buttonStyle(.plain).foregroundStyle(Theme.muted)
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
        if !w.conditionText.isEmpty { chips.append(w.conditionText) }
        if index > 0 {
            let over = stop.legExceedsRange(rangeMi)
            chips.append("\(over ? "⚠ " : "")+\(Int(stop.legMi.rounded())) mi leg")
        }
        chips.append("mile \(Int(stop.distanceMi.rounded()))")
        return chips
    }
}

/// Simple wrapping row of caption chips.
struct FlowRow: View {
    let items: [String]
    let color: Color

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), alignment: .leading)], alignment: .leading, spacing: 4) {
            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(item.hasPrefix("⚠") ? Theme.danger : color)
                    .lineLimit(1)
            }
        }
    }
}
