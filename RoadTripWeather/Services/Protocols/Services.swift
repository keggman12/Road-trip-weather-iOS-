import Foundation
import RoadTripCore

// Service boundaries. Every provider (MapKit, WeatherKit, NWS, Overpass,
// Open Charge Map) sits behind one of these so it can be swapped or mocked.
// Implementations must be `Sendable` (structs or actors).

/// Turns typed text into a place (web `api.geocode`).
protocol GeocodingService: Sendable {
    func geocode(_ query: String) async throws -> PlacePoint
}

struct RoutingResult: Sendable {
    var routes: [RouteGeometry]
    /// Shown under the route list when alternatives were not available.
    var note: String?
}

/// Driving routes through ordered points (web `api.getRoutes` + the
/// via/direct logic in `findRoutes`).
protocol RoutingService: Sendable {
    /// `points` is origin, vias…, destination (at least two).
    func routes(through points: [PlacePoint], departure: Date) async throws -> RoutingResult
}

/// Time zone for an arbitrary coordinate (sampled waypoints have none).
protocol TimeZoneService: Sendable {
    func timeZone(at coordinate: Coordinate) async -> TimeZone?
}

struct ForecastResult: Sendable {
    var snapshot: WeatherSnapshot?
    var horizon: ForecastHorizon
}

/// Forecast at an ETA (web `api.getWeatherAt`).
protocol WeatherService: Sendable {
    func forecast(at coordinate: Coordinate, for eta: Date) async throws -> ForecastResult
    /// Legal attribution page (WeatherKit requires showing it); nil for mocks.
    func attributionURL() async -> URL?
}

/// Alerts in effect around an ETA (web `api.getAlertsAt`). Best-effort:
/// never throws, returns [] on failure.
protocol AlertService: Sendable {
    func alerts(at coordinate: Coordinate, eta: Date) async -> [WeatherAlert]
}

struct POIRefreshOutcome: Sendable {
    var kind: POIKind
    var count: Int
    var source: POISource
}

/// POI storage + refresh (web `/api/pois` + `seed-pois.js`).
protocol POIService: Sendable {
    func pois(kind: POIKind) async throws -> [POI]
    /// Refreshes a brand kind from its official site, falling back to
    /// Overpass. Throws without touching stored data when every source fails.
    func refresh(kind: POIKind) async throws -> POIRefreshOutcome
}

/// Optional Tesla Supercharger lookup (Phase 2).
protocol ChargerService: Sendable {
    var isConfigured: Bool { get async }
}

enum ServiceError: LocalizedError {
    case notFound(String)
    case noRoute
    case http(Int)
    case badPayload(String)
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case let .notFound(q): "Couldn’t find a location for “\(q)”."
        case .noRoute: "No route found through those points."
        case let .http(code): "Request failed (HTTP \(code))."
        case let .badPayload(what): "Unexpected response from \(what)."
        case let .unavailable(what): "\(what) is unavailable."
        }
    }
}
