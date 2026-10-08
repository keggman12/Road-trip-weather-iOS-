import RoadTripCore
import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        NavigationStack {
            Form {
                Section("Temperature bands (°F)") {
                    TemperatureScaleEditor()
                }
                Section("Vehicle garage") {
                    VehicleGarageEditor()
                }
                Section("Alerts (NWS)") {
                    TextField("Contact email for NWS User-Agent (optional)", text: Bindable(env.settings).nwsContact)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                    Text("NWS asks API clients to identify themselves. The app always sends its name and repository URL; an email is optional. Takes effect on next launch.")
                        .font(.caption).foregroundStyle(Theme.muted)
                }
                Section("Superchargers (Open Charge Map)") {
                    SecureField("Open Charge Map API key", text: Bindable(env.settings).openChargeMapKey)
                    Text(env.settings.openChargeMapKey.isEmpty ? "Disabled until a key is entered. Stored in the Keychain." : "EV vehicles get up to 2 Superchargers within 30 mi of each stop.")
                        .font(.caption).foregroundStyle(Theme.muted)
                }
                Section("Data") {
                    Toggle("Weekly automatic Buc-ee's / Love's refresh", isOn: Bindable(env.settings).poiAutoRefreshEnabled)
                    Toggle("iCloud sync (restart required)", isOn: Bindable(env.settings).cloudSyncEnabled)
                    NavigationLink("Data sources and freshness") { DataSourcesView() }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Settings")
        }
    }
}

/// Web scale editor: colour + upper bound per band, last band open-ended,
/// bounds forced monotonic on apply.
struct TemperatureScaleEditor: View {
    @Environment(AppEnvironment.self) private var env
    @State private var draft: TemperatureScale = .default

    var body: some View {
        ForEach(draft.bands.indices, id: \.self) { i in
            HStack {
                ColorPicker("", selection: Binding(
                    get: { Color(hex: draft.bands[i].colorHex) },
                    set: { draft.bands[i].colorHex = $0.hexString }
                ), supportsOpacity: false)
                .labelsHidden()
                Text(draft.bands[i].label).frame(width: 60, alignment: .leading)
                Spacer()
                if i == draft.bands.count - 1 {
                    Text("and up").foregroundStyle(Theme.muted)
                } else {
                    TextField("max", value: Binding(
                        get: { draft.bands[i].upperBound ?? 0 },
                        set: { draft.bands[i].upperBound = $0 }
                    ), format: .number)
                    .keyboardType(.numbersAndPunctuation)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .frame(width: 70)
                }
            }
        }
        HStack {
            Button("Apply") { env.settings.applyScale(draft); draft = env.settings.temperatureScale }
                .buttonStyle(.borderless)
            Spacer()
            Button("Reset") { env.settings.resetScale(); draft = env.settings.temperatureScale }
                .buttonStyle(.borderless)
        }
        .onAppear { draft = env.settings.temperatureScale }
    }
}

struct VehicleGarageEditor: View {
    @Environment(AppEnvironment.self) private var env
    @Query(sort: \VehicleRecord.sortOrder) private var vehicles: [VehicleRecord]

    var body: some View {
        ForEach(vehicles) { v in
            HStack {
                TextField("Name", text: Bindable(v).name)
                TextField("mi", value: Binding(
                    get: { v.rangeMi },
                    set: { env.trips.setRange($0, for: v) }
                ), format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(width: 64)
                Toggle("EV", isOn: Bindable(v).isEV).labelsHidden()
            }
        }
        .onDelete { offsets in
            env.trips.deleteVehicles(offsets.map { vehicles[$0] })
        }
        Button { env.trips.addVehicle() } label: { Label("Add vehicle", systemImage: "plus") }
        Button("Reset to defaults") { env.trips.resetVehicles() }
    }
}

extension Color {
    /// Best-effort `#rrggbb` for persisting a picked colour.
    var hexString: String {
        #if canImport(UIKit)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a) else { return TemperatureScale.unknownColorHex }
        return String(format: "#%02x%02x%02x", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
        #else
        return TemperatureScale.unknownColorHex
        #endif
    }
}
