import RoadTripCore
import SwiftData
import SwiftUI

/// Origin / destination / via-points / departure / vehicle / range — then
/// "Find Routes" (no weather calls).
struct PlanView: View {
    @Bindable var coordinator: BriefingCoordinator
    @Environment(AppEnvironment.self) private var env
    @Query(sort: \VehicleRecord.sortOrder) private var vehicles: [VehicleRecord]
    @State private var showRoutes = false
    @FocusState private var rangeFocused: Bool

    var body: some View {
        Form {
            Section("Route") {
                LocationField(title: "Origin", text: $coordinator.plan.originText, recents: env.settings.recentLocations)
                ForEach(coordinator.plan.viaTexts.indices, id: \.self) { i in
                    HStack {
                        LocationField(title: "Via", text: $coordinator.plan.viaTexts[i], recents: env.settings.recentLocations)
                        Button(role: .destructive) {
                            coordinator.plan.viaTexts.remove(at: i)
                        } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.muted)
                    }
                }
                Button { coordinator.plan.viaTexts.append("") } label: {
                    Label("Add via-point", systemImage: "plus")
                }
                LocationField(title: "Destination", text: $coordinator.plan.destinationText, recents: env.settings.recentLocations)
            }

            Section("Departure") {
                DatePicker("Depart", selection: $coordinator.plan.departure, displayedComponents: [.date, .hourAndMinute])
                    .environment(\.timeZone, coordinator.plan.departureTimeZone)
                if let id = coordinator.plan.departureTimeZoneID {
                    Text("Times in \(id) (origin)").font(.caption).foregroundStyle(Theme.muted)
                }
            }

            Section("Vehicle") {
                Picker("Vehicle", selection: vehicleSelection) {
                    ForEach(vehicles) { v in
                        Text("\(v.isEV ? "⚡ " : "")\(v.name)").tag(v.id.uuidString as String?)
                    }
                    Text("Custom range").tag(nil as String?)
                }
                HStack {
                    Text("Range between stops")
                    Spacer()
                    TextField("mi", value: $coordinator.plan.rangeMi, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                        .frame(width: 80)
                        .focused($rangeFocused)
                        .onChange(of: coordinator.plan.rangeMi) { _, new in
                            if let vid = coordinator.plan.vehicleID, let v = vehicles.first(where: { $0.id.uuidString == vid }), v.rangeMi != new {
                                coordinator.plan.vehicleID = nil
                            }
                        }
                    Text("mi").foregroundStyle(Theme.muted)
                }
            }

            Section("Multi-day") {
                Toggle("Overnight stops", isOn: $coordinator.plan.multiDay.enabled)
                if coordinator.plan.multiDay.enabled {
                    Stepper(value: $coordinator.plan.multiDay.maxDriveHours, in: MultiDayOptions.minDriveHours...MultiDayOptions.maxDriveHours, step: 0.5) {
                        Text("Max \(coordinator.plan.multiDay.maxDriveHours, format: .number) h driving / day").monospacedDigit()
                    }
                    ResumeTimePicker(time: $coordinator.plan.multiDay.resumeTime)
                }
            }

            Section {
                Button {
                    Task {
                        await coordinator.findRoutes()
                        if !coordinator.routes.isEmpty { showRoutes = true }
                    }
                } label: {
                    HStack {
                        if coordinator.isBusy { ProgressView().controlSize(.small) }
                        Text(buttonTitle).fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                }
                .disabled(!coordinator.canFindRoutes)
                if let e = coordinator.errorMessage {
                    Text(e).foregroundStyle(Theme.danger).font(.footnote)
                }
                if !coordinator.routes.isEmpty {
                    Button("Show routes") { showRoutes = true }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.background)
        .navigationTitle("Road Trip Weather")
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { rangeFocused = false }
            }
        }
        .onChange(of: rangeFocused) { _, focused in
            if !focused { coordinator.plan.rangeMi = Vehicle.clampRange(coordinator.plan.rangeMi) }
        }
        .navigationDestination(isPresented: $showRoutes) {
            RoutesView(coordinator: coordinator)
        }
        .onAppear {
            if coordinator.plan.vehicleID == nil, coordinator.plan.rangeMi == 300, let first = vehicles.first {
                coordinator.plan.vehicleID = first.id.uuidString
                coordinator.plan.rangeMi = first.rangeMi
            }
        }
    }

    private var buttonTitle: String {
        switch coordinator.phase {
        case let .geocoding(what): "Geocoding \(what)…"
        case .routing: "Finding driving routes…"
        default: "Find Routes"
        }
    }

    private var vehicleSelection: Binding<String?> {
        Binding(
            get: { coordinator.plan.vehicleID },
            set: { id in
                coordinator.plan.vehicleID = id
                if let id, let v = vehicles.first(where: { $0.id.uuidString == id }) {
                    coordinator.plan.rangeMi = v.rangeMi
                }
            }
        )
    }
}

struct LocationField: View {
    let title: String
    @Binding var text: String
    let recents: [String]

    var body: some View {
        HStack {
            TextField(title, text: $text)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
            if !recents.isEmpty {
                Menu {
                    ForEach(recents, id: \.self) { r in
                        Button(r) { text = r }
                    }
                } label: {
                    Image(systemName: "clock.arrow.circlepath").foregroundStyle(Theme.muted)
                }
            }
        }
    }
}

struct ResumeTimePicker: View {
    @Binding var time: TimeOfDay

    var body: some View {
        DatePicker("Resume next morning", selection: dateBinding, displayedComponents: .hourAndMinute)
            .environment(\.timeZone, TimeZone(identifier: "UTC") ?? .current)
    }

    private var dateBinding: Binding<Date> {
        Binding(
            get: {
                var cal = Calendar(identifier: .gregorian)
                cal.timeZone = TimeZone(identifier: "UTC") ?? .current
                return cal.date(from: DateComponents(year: 2000, month: 1, day: 1, hour: time.hour, minute: time.minute)) ?? Date()
            },
            set: { d in
                var cal = Calendar(identifier: .gregorian)
                cal.timeZone = TimeZone(identifier: "UTC") ?? .current
                let c = cal.dateComponents([.hour, .minute], from: d)
                time = TimeOfDay(hour: c.hour ?? 8, minute: c.minute ?? 0)
            }
        )
    }
}

#Preview {
    let env = AppEnvironment.preview()
    return NavigationStack {
        PlanView(coordinator: BriefingCoordinator(env: env))
    }
    .environment(env)
    .modelContainer(env.container)
    .preferredColorScheme(.dark)
}
