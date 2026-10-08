import MapKit
import RoadTripCore
import SwiftUI

/// Route alternatives with a map preview; "Generate Weather Briefing" is the
/// only place weather calls start.
struct RoutesView: View {
    @Bindable var coordinator: BriefingCoordinator
    @State private var showBriefing = false

    var body: some View {
        VStack(spacing: 0) {
            Map {
                ForEach(Array(coordinator.routes.enumerated()), id: \.offset) { i, route in
                    MapPolyline(coordinates: route.coordinates.map(\.clLocationCoordinate))
                        .stroke(
                            Theme.routeColor(i).opacity(i == coordinator.selectedRouteIndex ? 1 : 0.5),
                            style: StrokeStyle(lineWidth: i == coordinator.selectedRouteIndex ? 6 : 3.5, dash: i == coordinator.selectedRouteIndex ? [] : [3, 7])
                        )
                }
            }
            .mapStyle(.standard(elevation: .flat, emphasis: .muted))
            .frame(height: 260)

            List {
                if let note = coordinator.routeNote {
                    Text("ℹ \(note)").font(.footnote).foregroundStyle(Theme.muted)
                }
                if realRoutes.count < coordinator.routes.count {
                    Text("ℹ Showing cached routes only. Find Routes again for every alternative.").font(.footnote).foregroundStyle(Theme.muted)
                }
                // Cached briefings pad un-briefed indices with empty
                // placeholders; those aren't routes the user can pick.
                ForEach(realRoutes, id: \.offset) { i, route in
                    RouteRow(index: i, route: route, fastest: fastestDuration, selected: i == coordinator.selectedRouteIndex, score: coordinator.briefings[i].map { TripScorer.score($0.stops).score })
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
