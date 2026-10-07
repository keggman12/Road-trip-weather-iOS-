import Foundation
import RoadTripCore

/// Fetches a brand kind from its official locator, falling back to exact-tag
/// Overpass (web `seed-pois.js`). Pure fetch + parse: storage happens in
/// `POIStore` so a failure here never touches saved data.
struct POIRefreshService: Sendable {
    let session: URLSession
    let overpass: OverpassClient
    let browserUserAgent: String

    static let buceesURL = URL(string: "https://buc-ees.com/locations/")
    static let lovesURL = URL(string: "https://www.loves.com/api/fetch_stores")

    init(appVersion: String, session: URLSession = .shared, overpass: OverpassClient) {
        self.session = session
        self.overpass = overpass
        self.browserUserAgent = ClientIdentity.browserStyleUserAgent(version: appVersion)
    }

    struct Fetched: Sendable {
        var pois: [POI]
        var source: POISource
        /// Why the official site was skipped, if it was.
        var officialError: String?
    }

    func fetch(kind: POIKind) async throws -> Fetched {
        guard kind != .rest else { throw ServiceError.unavailable("Rest areas are only refreshed via the bundled snapshot") }
        var officialError: String?
        do {
            let pois = try await official(kind: kind)
            return Fetched(pois: pois, source: .official, officialError: nil)
        } catch {
            officialError = String(describing: error)
        }
        guard let response = await overpass.query(OverpassQueries.nationwide(kind)) else {
            throw ServiceError.unavailable("\(kind.displayName): official site failed (\(officialError ?? "unknown")) and every Overpass mirror was unavailable")
        }
        let pois = POINormalizer.normalize(response.elements, kind: kind)
        guard pois.count >= kind.sanityMinimumCount else {
            throw POIParseError.tooFewResults(kind: kind, parsed: pois.count, minimum: kind.sanityMinimumCount)
        }
        return Fetched(pois: pois, source: .osm, officialError: officialError)
    }

    private func official(kind: POIKind) async throws -> [POI] {
        switch kind {
        case .bucees:
            guard let url = POIRefreshService.buceesURL else { throw ServiceError.unavailable("Buc-ee's URL") }
            let data = try await get(url, accept: "text/html")
            return try BuceesLocationsParser.parse(html: String(decoding: data, as: UTF8.self))
        case .loves:
            guard let url = POIRefreshService.lovesURL else { throw ServiceError.unavailable("Love's URL") }
            let data = try await get(url, accept: "application/json")
            return try LovesStoresParser.parse(data: data)
        case .rest:
            throw ServiceError.unavailable("rest areas")
        }
    }

    private func get(_ url: URL, accept: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        request.setValue(browserUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(accept, forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw ServiceError.http(code) }
        return data
    }
}

/// Reads `pois-snapshot.json` from the app bundle.
enum BundledPOISnapshot {
    static func load(bundle: Bundle = .main) throws -> POISnapshot {
        guard let url = bundle.url(forResource: "pois-snapshot", withExtension: "json") else {
            throw ServiceError.unavailable("bundled POI snapshot")
        }
        return try POISnapshot.decoder().decode(POISnapshot.self, from: Data(contentsOf: url))
    }
}
