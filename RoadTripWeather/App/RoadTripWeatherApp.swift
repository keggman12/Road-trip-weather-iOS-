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
    @Environment(\.scenePhase) private var scenePhase
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
        .task(id: "\(scenePhase)-\(env.settings.poiAutoRefreshEnabled)") {
            guard scenePhase == .active, !env.isPreview else { return }
            await env.pois.refreshAutomaticallyIfDue(enabled: { env.settings.poiAutoRefreshEnabled })
        }
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
