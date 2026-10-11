import RoadTripCore
import SwiftData
import SwiftUI

/// Saved trips (web trips list). Loading restores the plan and the cached
/// briefing so it is viewable with no signal.
struct TripsView: View {
    @Bindable var coordinator: BriefingCoordinator
    @Environment(AppEnvironment.self) private var env
    @Query(sort: \TripRecord.updatedAt, order: .reverse) private var trips: [TripRecord]
    @State private var showBriefing = false

    var body: some View {
        NavigationStack {
            List {
                if trips.isEmpty {
                    ContentUnavailableView("No saved trips yet", systemImage: "bookmark", description: Text("Generate a briefing, then choose Save trip."))
                }
                ForEach(trips) { trip in
                    Button {
                        coordinator.load(trip)
                        showBriefing = coordinator.briefing != nil
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(trip.name).fontWeight(.semibold)
                            Text(([trip.originLabel] + (JSONCoding.decode([PlacePoint].self, from: trip.viasData) ?? []).map(\.label) + [trip.destLabel]).joined(separator: " → "))
                                .font(.caption).foregroundStyle(Theme.muted).lineLimit(2)
                            if let b = trip.briefings?.max(by: { $0.generatedAt < $1.generatedAt }) {
                                Text("Briefing cached \(Fmt.age(b.generatedAt))").font(.caption2).foregroundStyle(Theme.muted)
                            }
                        }
                    }
                    .listRowBackground(Theme.surface)
                }
                .onDelete { offsets in
                    for i in offsets { try? env.trips.delete(trips[i]) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Saved trips")
            .navigationDestination(isPresented: $showBriefing) {
                BriefingView(coordinator: coordinator)
            }
        }
    }
}
