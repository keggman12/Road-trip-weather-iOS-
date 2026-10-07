import Foundation
import RoadTripCore
import SwiftUI

/// Device-local settings (web `localStorage`): temperature bands, recents,
/// NWS contact. The Open Charge Map key lives in the Keychain.
@MainActor
@Observable
final class AppSettings {
    private let defaults: UserDefaults
    private let keychain: KeychainStore

    static let scaleKey = "rtwx-scale-v1"
    static let recentsKey = "rtwx-recent-locations-v1"
    static let nwsContactKey = "rtwx-nws-contact"
    static let cloudSyncKey = "rtwx-icloud-sync"
    static let autoRefreshKey = "rtwx-poi-auto-refresh"

    var temperatureScale: TemperatureScale {
        didSet { defaults.set(JSONCoding.encode(temperatureScale), forKey: AppSettings.scaleKey) }
    }

    var recentLocations: [String] {
        didSet { defaults.set(recentLocations, forKey: AppSettings.recentsKey) }
    }

    var nwsContact: String {
        didSet { defaults.set(nwsContact, forKey: AppSettings.nwsContactKey) }
    }

    var cloudSyncEnabled: Bool {
        didSet { defaults.set(cloudSyncEnabled, forKey: AppSettings.cloudSyncKey) }
    }

    /// Weekly automatic Buc-ee's / Love's refresh (manual button always works).
    var poiAutoRefreshEnabled: Bool {
        didSet { defaults.set(poiAutoRefreshEnabled, forKey: AppSettings.autoRefreshKey) }
    }

    var openChargeMapKey: String {
        didSet {
            if openChargeMapKey.isEmpty {
                keychain.delete(KeychainStore.openChargeMapAccount)
            } else {
                keychain.write(openChargeMapKey, account: KeychainStore.openChargeMapAccount)
            }
        }
    }

    init(defaults: UserDefaults = .standard, keychain: KeychainStore = KeychainStore()) {
        self.defaults = defaults
        self.keychain = keychain
        self.temperatureScale = JSONCoding.decode(TemperatureScale.self, from: defaults.data(forKey: AppSettings.scaleKey))?.normalized() ?? .default
        self.recentLocations = defaults.stringArray(forKey: AppSettings.recentsKey) ?? []
        self.nwsContact = defaults.string(forKey: AppSettings.nwsContactKey) ?? ""
        self.cloudSyncEnabled = defaults.bool(forKey: AppSettings.cloudSyncKey)
        self.poiAutoRefreshEnabled = defaults.object(forKey: AppSettings.autoRefreshKey) as? Bool ?? true
        self.openChargeMapKey = keychain.read(KeychainStore.openChargeMapAccount) ?? ""
    }

    func remember(_ texts: String...) {
        recentLocations = RecentLocations.remember(texts, into: recentLocations)
    }

    static var appVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.1"
    }
}
