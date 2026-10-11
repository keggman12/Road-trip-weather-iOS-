import SwiftData
import SwiftUI

@main
struct RoadTripWeatherApp: App {
    @State private var env = AppEnvironment.live()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(env)
                .modelContainer(env.container)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
    }
}

struct RootView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var coordinator: BriefingCoordinator?

    var body: some View {
        Group {
            if let coordinator {
                TabView {
                    Tab("Plan", systemImage: "map") {
                        PlanFlowView(coordinator: coordinator)
                    }
                    Tab("Trips", systemImage: "bookmark") {
                        TripsView(coordinator: coordinator)
                    }
                    Tab("Settings", systemImage: "gearshape") {
                        SettingsView()
                    }
                }
            } else {
                ProgressView().task { coordinator = BriefingCoordinator(env: env) }
            }
        }
        .background(Theme.background)
    }
}

/// Plan → Routes → Briefing as a navigation stack.
struct PlanFlowView: View {
    @Bindable var coordinator: BriefingCoordinator

    var body: some View {
        NavigationStack {
            PlanView(coordinator: coordinator)
        }
    }
}

#Preview {
    let env = AppEnvironment.preview()
    return RootView()
        .environment(env)
        .modelContainer(env.container)
        .preferredColorScheme(.dark)
}
