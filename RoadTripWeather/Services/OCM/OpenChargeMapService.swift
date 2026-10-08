import Foundation
import RoadTripCore

/// Tesla Superchargers from Open Charge Map. The key is read from the
/// Keychain on every call, so entering it in Settings takes effect at once;
/// it travels in the `X-API-Key` header, never in the URL.
struct OpenChargeMapService: ChargerService {
    let apiKey: @Sendable () -> String?
    let session: URLSession

    init(keychain: KeychainStore, session: URLSession = .shared) {
        self.init(session: session) { keychain.read(KeychainStore.openChargeMapAccount) }
    }

    init(session: URLSession = .shared, apiKey: @escaping @Sendable () -> String?) {
        self.apiKey = apiKey
        self.session = session
    }

    var isConfigured: Bool {
        !(apiKey() ?? "").trimmingCharacters(in: .whitespaces).isEmpty
    }

    func superchargers(near coordinate: Coordinate) async throws -> [Charger] {
        let key = (apiKey() ?? "").trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return [] }
        guard let url = OpenChargeMap.url(near: coordinate) else { throw ServiceError.badPayload("Open Charge Map URL") }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue(key, forHTTPHeaderField: OpenChargeMap.apiKeyHeader)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(ClientIdentity.nwsUserAgent(version: AppVersion.current, contact: nil), forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw ServiceError.http(code) }
        return OpenChargeMap.parse(data)
    }
}

/// Bundle version without touching the main-actor settings object.
enum AppVersion {
    static var current: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.1"
    }
}
