import MapKit
import RoadTripCore
import SwiftUI

/// Route alternatives with a map preview; "Generate Weather Briefing" is the
/// only place weather calls start.
struct RoutesView: View {
    @Bindable var coordinator: BriefingCoordinator
    @State private var showBriefing = false
    /// Where the user long-pressed, awaiting "Add via-point".
    @State private var pendingPin: Coordinate?
    @State private var viaToRemove: PlacePoint?

    var body: some View {
        VStack(spacing: 0) {
            MapReader { proxy in
                Map {
                    ForEach(Array(coordinator.routes.enumerated()), id: \.offset) { i, route in
                        MapPolyline(coordinates: route.coordinates.map(\.clLocationCoordinate))
                            .stroke(
                                Theme.routeColor(i).opacity(i == coordinator.selectedRouteIndex ? 1 : 0.5),
                                style: StrokeStyle(lineWidth: i == coordinator.selectedRouteIndex ? 6 : 3.5, dash: i == coordinator.selectedRouteIndex ? [] : [3, 7])
                            )
                    }
                    ForEach(coordinator.plan.vias, id: \.query) { via in
                        Annotation(via.label, coordinate: via.coordinate.clLocationCoordinate, anchor: .bottom) {
                            Button { viaToRemove = via } label: {
                                Image(systemName: "mappin.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(.white, Theme.accent)
                            }
                            .accessibilityLabel("Via-point \(via.label)")
                        }
                        .annotationTitles(.hidden)
                    }
                    if let pendingPin {
                        Marker("New via-point", systemImage: "mappin", coordinate: pendingPin.clLocationCoordinate)
                    }
                }
                .mapStyle(.standard(elevation: .flat, emphasis: .muted))
                // Hold, then lift: drops a pin where the finger was. Simultaneous
                // so panning and zooming the map still work.
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.5)
                        .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .local))
                        .onEnded { value in
                            guard canDropPin, case let .second(true, drag?) = value,
                                  let c = proxy.convert(drag.location, from: .local)
                            else { return }
                            pendingPin = Coordinate(c)
                        }
                )
            }
            .frame(height: 260)
            .confirmationDialog("Add a via-point here?", isPresented: Binding(get: { pendingPin != nil }, set: { if !$0 { pendingPin = nil } }), titleVisibility: .visible, presenting: pendingPin) { pin in
                Button("Add via-point and find routes") {
                    pendingPin = nil
                    Task { await coordinator.addViaPin(at: pin) }
                }
                Button("Cancel", role: .cancel) { pendingPin = nil }
            } message: { _ in
                Text(coordinator.briefings.isEmpty
                     ? "Routes are found again through this spot."
                     : "Routes are found again through this spot; this search’s briefings are cleared (saved trips keep theirs).")
            }
            .confirmationDialog(viaToRemove.map { "Remove \($0.label)?" } ?? "", isPresented: Binding(get: { viaToRemove != nil }, set: { if !$0 { viaToRemove = nil } }), titleVisibility: .visible, presenting: viaToRemove) { via in
                Button("Remove via-point and find routes", role: .destructive) {
                    viaToRemove = nil
                    Task { await coordinator.removeVia(query: via.query) }
                }
                Button("Cancel", role: .cancel) { viaToRemove = nil }
            }

            List {
                if let note = coordinator.routeNote {
                    Text("ℹ \(note)").font(.footnote).foregroundStyle(Theme.muted)
                }
                if canDropPin {
                    Text("Long-press the map to add a via-point and reshape the route. Tap a pin to remove it.")
                        .font(.footnote).foregroundStyle(Theme.muted)
                }
                if realRoutes.count < coordinator.routes.count {
                    Text("ℹ Showing cached routes only. Find Routes again for every alternative.").font(.footnote).foregroundStyle(Theme.muted)
                }
                // Cached briefings pad un-briefed indices with empty
                // placeholders; those aren't routes the user can pick.
                ForEach(realRoutes, id: \.offset) { i, route in
                    RouteRow(index: i, route: route, fastest: fastestDuration, selected: i == coordinator.selectedRouteIndex, score: coordinator.briefings[i].flatMap { b in b.stops.isEmpty || b.stops.contains(where: { $0.weather == nil || $0.isForecastStale }) ? nil : TripScorer.score(b.stops).score })
                        .contentShape(Rectangle())
                        .onTapGesture { coordinator.selectRoute(i) }
                }
                Section {
                    Button {
                        Task {
                            await coordinator.generateBriefing()
                            if coordinator.briefing != nil { showBriefing = true }
                        }
                    } label: {
                        HStack {
                            if coordinator.isBusy { ProgressView().controlSize(.small) }
                            Text(buttonTitle).fontWeight(.semibold)
                        }.frame(maxWidth: .infinity)
                    }
                    .disabled(coordinator.isBusy || coordinator.selectedRouteIndex < 0)
                    if coordinator.canFindMoreRoutes || coordinator.routes.count >= BriefingCoordinator.maxRoutesWithSuggestions {
                        Button {
                            Task { await coordinator.findMoreRoutes() }
                        } label: {
                            Label("More routes (suggest roads Apple Maps didn't offer)", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                        }
                        .disabled(!coordinator.canFindMoreRoutes)
                    }
                    if let msg = coordinator.statusMessage, msg.contains("suggested route") || msg.contains("distinct routes") {
                        Text(msg).font(.footnote).foregroundStyle(Theme.muted)
                    }
                    if realRoutes.count > 1 {
                        Button("Brief all routes (compare weather)") {
                            Task {
                                await coordinator.generateBriefing(allRoutes: true)
                                if coordinator.briefing != nil { showBriefing = true }
                            }
                        }
                        .disabled(coordinator.isBusy)
                    }
                    if coordinator.briefing != nil {
                        Button("Show briefing") { showBriefing = true }
                    }
                    if let e = coordinator.errorMessage { Text(e).foregroundStyle(Theme.danger).font(.footnote) }
                }
            }
            .scrollContentBackground(.hidden)
        }
        .background(Theme.background)
        .navigationTitle("Routes")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showBriefing) {
            BriefingView(coordinator: coordinator)
        }
    }

    /// Pins need the trip's geocoded ends and a free coordinator.
    private var canDropPin: Bool {
        !coordinator.isBusy && coordinator.plan.origin != nil && coordinator.plan.destination != nil
    }

    private var realRoutes: [(offset: Int, element: RouteGeometry)] {
        coordinator.routes.enumerated().filter { $0.element.coordinates.count >= 2 }
    }

    private var fastestDuration: Double {
        realRoutes.map(\.element.durationSec).min() ?? 0
    }

    private var buttonTitle: String {
        if case let .briefing(done, total, label) = coordinator.phase {
            return "Briefing \(label) — \(done) / \(total)"
        }
        return "Generate Weather Briefing"
    }
}

struct RouteRow: View {
    let index: Int
    let route: RouteGeometry
    let fastest: Double
    let selected: Bool
    let score: Int?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle().fill(Theme.routeColor(index)).frame(width: 10, height: 10).padding(.top, 6)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(route.label.map { "Route \(index + 1) · \($0)" } ?? "Route \(index + 1)").fontWeight(.semibold)
                    Spacer()
                    if route.durationSec == fastest {
                        Tag(text: "Fastest", color: Theme.ok)
                    } else {
                        Tag(text: "+\(Fmt.duration(route.durationSec - fastest))", color: Theme.muted, uppercase: false)
                    }
                }
                HStack(spacing: 8) {
                    Text("\(Int(route.distanceMi.rounded())) mi").monospacedDigit()
                    Text("·").foregroundStyle(Theme.muted)
                    Text(Fmt.duration(route.durationSec)).monospacedDigit()
                    if let score {
                        Text("·").foregroundStyle(Theme.muted)
                        Text("wx \(score)").monospacedDigit().foregroundStyle(Theme.accent)
                    }
                }
                .font(.subheadline)
                .foregroundStyle(Theme.text)
            }
        }
        .padding(.vertical, 4)
        .listRowBackground(selected ? Theme.routeColor(index).opacity(0.12) : Theme.surface)
    }
}

struct Tag: View {
    let text: String
    let color: Color
    var uppercase = true

    var body: some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .textCase(uppercase ? .uppercase : nil)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(color))
            .foregroundStyle(color)
    }
}
