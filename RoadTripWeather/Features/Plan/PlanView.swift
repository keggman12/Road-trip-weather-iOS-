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
                LocationField(title: "Origin", placeholder: "Origin address or city", text: $coordinator.plan.originText, recents: env.settings.recentLocations, onPick: coordinator.pick)
                // Rows are found by ID, never by position: a binding to a row
                // that was just removed crashed the form (issue #2).
                ForEach(coordinator.plan.viaEntries) { via in
                    HStack {
                        LocationField(title: "Via", placeholder: "Via-point address or city", text: viaText(via.id), recents: env.settings.recentLocations, onPick: coordinator.pick)
                        // A minus, not an ✕: the ✕ inside the field clears it (#9).
                        Button(role: .destructive) {
                            coordinator.plan.viaEntries.removeAll { $0.id == via.id }
                        } label: { Image(systemName: "minus.circle.fill") }
                        .buttonStyle(.borderless)
                        .foregroundStyle(Theme.danger)
                        .accessibilityLabel("Remove via-point")
                    }
                }
                Button { coordinator.plan.viaEntries.append(ViaEntry(text: "")) } label: {
                    Label("Add via-point", systemImage: "plus")
                }
                LocationField(title: "Destination", placeholder: "Destination address or city", text: $coordinator.plan.destinationText, recents: env.settings.recentLocations, onPick: coordinator.pick)
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

            if coordinator.errorMessage != nil || !coordinator.routes.isEmpty || !coordinator.placeNotices.isEmpty {
                Section {
                    if let e = coordinator.errorMessage {
                        Text(e).foregroundStyle(Theme.danger).font(.footnote)
                    }
                    ForEach(coordinator.placeNotices, id: \.self) { n in
                        Label(n, systemImage: "exclamationmark.triangle").foregroundStyle(Theme.warn).font(.footnote)
                    }
                    if !coordinator.routes.isEmpty {
                        Button("Show routes") { showRoutes = true }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        // Pinned above the tab bar: as the form's last row it sat behind the
        // floating tab bar until you scrolled.
        .safeAreaInset(edge: .bottom) {
            Button {
                Task {
                    await coordinator.findRoutes()
                    if !coordinator.routes.isEmpty { showRoutes = true }
                }
            } label: {
                HStack {
                    if coordinator.isBusy { ProgressView().controlSize(.small).tint(Theme.background) }
                    Text(buttonTitle).fontWeight(.semibold)
                }
                .foregroundStyle(Theme.background)   // dark on the light accent
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!coordinator.canFindRoutes)
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
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

    private func viaText(_ id: UUID) -> Binding<String> {
        Binding(
            get: { coordinator.plan.viaEntries.first { $0.id == id }?.text ?? "" },
            set: { new in
                if let i = coordinator.plan.viaEntries.firstIndex(where: { $0.id == id }) {
                    coordinator.plan.viaEntries[i].text = new
                }
            }
        )
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

/// A place field: free text, address suggestions while typing (issue #4),
/// "use current location" (issue #3), recent places and a clear button (#9).
/// The placeholder says what to type; once filled, a small caption keeps the
/// field's name (#5). Used on the Plan screen and for adding a stop (#8).
struct LocationField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    let recents: [String]
    /// Called with the exact place when the user picks a suggestion or their
    /// current location; its `query` is the text put in the field.
    var onPick: (PlacePoint) -> Void = { _ in }
    /// Return key action; when set, the key reads "Done".
    var onSubmit: (() -> Void)?

    @State private var completer = AddressCompleter()
    @State private var locating = false
    @State private var problem: String?
    /// Text this field just filled in itself, so it doesn't suggest it back.
    @State private var filled: String?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !text.isEmpty {
                Text(title).font(.caption).foregroundStyle(Theme.muted)
            }
            HStack {
                TextField(placeholder, text: $text)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .focused($focused)
                    .submitLabel(onSubmit == nil ? .return : .done)
                    .onSubmit { onSubmit?() }
                if !text.isEmpty {
                    Button {
                        filled = nil
                        text = ""
                        focused = true
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.muted)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Clear \(title)")
                }
                if locating {
                    ProgressView().controlSize(.small)
                } else {
                    Button { Task { await useCurrentLocation() } } label: {
                        Image(systemName: "scope").foregroundStyle(Theme.muted)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Use current location")
                }
                if !recents.isEmpty {
                    Menu {
                        ForEach(recents, id: \.self) { r in
                            Button(r) { fill(r) }
                        }
                    } label: {
                        Image(systemName: "clock.arrow.circlepath").foregroundStyle(Theme.muted)
                    }
                }
            }
            if focused {
                ForEach(completer.suggestions) { suggestion in
                    Button { Task { await pick(suggestion) } } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(suggestion.title).foregroundStyle(.primary)
                            if !suggestion.subtitle.isEmpty {
                                Text(suggestion.subtitle).font(.caption).foregroundStyle(Theme.muted)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                }
            }
            if let problem {
                Text(problem).font(.caption).foregroundStyle(Theme.danger)
            }
        }
        .onChange(of: text) { _, new in
            problem = nil
            if focused, new != filled { completer.update(new) } else { completer.clear() }
        }
        .onChange(of: focused) { _, isFocused in
            if !isFocused { completer.clear() }
        }
    }

    private func fill(_ value: String) {
        filled = value
        focused = false
        completer.clear()
        text = value
    }

    private func pick(_ suggestion: AddressCompleter.Suggestion) async {
        fill(suggestion.text)
        // If the lookup fails, Find Routes geocodes the text as usual.
        if let place = try? await completer.resolve(suggestion) { onPick(place) }
    }

    private func useCurrentLocation() async {
        problem = nil
        locating = true
        defer { locating = false }
        do {
            let place = try await CurrentLocation.place()
            fill(place.query)
            onPick(place)
        } catch {
            problem = error.localizedDescription
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
