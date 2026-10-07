import Foundation
import RoadTripCore
import SwiftData
import SwiftUI

/// Dependency container handed to the view tree. `live()` wires MapKit,
/// WeatherKit, NWS and the SwiftData stores; `preview()` wires the mocks.
@MainActor
@Observable
final class AppEnvironment {
    let container: ModelContainer
    let settings: AppSettings
    let status: DataSourceStatusStore
    let trips: TripStore
    let pois: POIStore
    let geocoding: any GeocodingService
    let routing: any RoutingService
    let timeZones: any TimeZoneService
    let weather: any WeatherService
    let alerts: any AlertService
    let chargers: any ChargerService
    let isPreview: Bool

    init(
        container: ModelContainer,
        settings: AppSettings,
        geocoding: any GeocodingService,
        routing: any RoutingService,
        timeZones: any TimeZoneService,
        weather: any WeatherService,
        alerts: any AlertService,
        chargers: any ChargerService,
        refresher: POIRefreshService?,
        isPreview: Bool
    ) {
        self.container = container
        self.settings = settings
        self.status = DataSourceStatusStore(container: container)
        self.trips = TripStore(container: container)
        self.pois = POIStore(container: container, refresher: refresher, statusStore: status)
        self.geocoding = geocoding
        self.routing = routing
        self.timeZones = timeZones
        self.weather = weather
        self.alerts = alerts
        self.chargers = chargers
        self.isPreview = isPreview
    }

    static func live() -> AppEnvironment {
        let settings = AppSettings()
        let container: ModelContainer
        do {
            container = try AppSchema.makeContainer(cloud: settings.cloudSyncEnabled)
        } catch {
            // A corrupt or incompatible store must not take the app down; fall
            // back to memory so the user can still plan a trip.
            container = (try? AppSchema.makeContainer(inMemory: true)) ?? fatalContainer()
        }
        let version = AppSettings.appVersion
        let status = Box<DataSourceStatusStore?>(nil)
        let nws = NWSAlertService(contactEmail: settings.nwsContact, appVersion: version) { result in
            Task { @MainActor in
                switch result {
                case let .success(n): status.value?.recordSuccess(.nws, count: n)
                case let .failure(e): status.value?.recordError(.nws, e.localizedDescription)
                }
                status.value?.countCall(.nws)
            }
        }
        let overpass = OverpassClient(appVersion: version)
        let env = AppEnvironment(
            container: container,
            settings: settings,
            geocoding: MapKitGeocodingService(),
            routing: MapKitRoutingService(),
            timeZones: CLTimeZoneService(),
            weather: WeatherKitService(),
            alerts: nws,
            chargers: OpenChargeMapService(keychain: KeychainStore()),
            refresher: POIRefreshService(appVersion: version, overpass: overpass),
            isPreview: false
        )
        status.value = env.status
        env.trips.seedVehiclesIfNeeded()
        env.pois.importBundledSnapshotIfNeeded()
        return env
    }

    static func preview() -> AppEnvironment {
        let container = (try? AppSchema.makeContainer(inMemory: true)) ?? fatalContainer()
        let env = AppEnvironment(
            container: container,
            settings: AppSettings(defaults: UserDefaults(suiteName: "preview") ?? .standard),
            geocoding: MockGeocodingService(),
            routing: MockRoutingService(),
            timeZones: MockTimeZoneService(),
            weather: MockWeatherService(),
            alerts: MockAlertService(),
            chargers: MockChargerService(),
            refresher: nil,
            isPreview: true
        )
        env.trips.seedVehiclesIfNeeded()
        return env
    }

    private static func fatalContainer() -> ModelContainer {
        // Only reached if even an in-memory store cannot be created, which
        // means the schema itself is broken — a programmer error.
        do { return try ModelContainer(for: Schema(AppSchema.models), configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]) }
        catch { preconditionFailure("SwiftData schema failed to load: \(error)") }
    }
}

/// Tiny reference box for wiring a callback before its target exists.
final class Box<T>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
}
