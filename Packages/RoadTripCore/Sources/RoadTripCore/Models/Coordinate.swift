import Foundation

/// A WGS-84 position. RoadTripCore has no CoreLocation dependency, so this is
/// the only coordinate type the logic layer knows about; the app converts to
/// and from `CLLocationCoordinate2D` at the edges.
public struct Coordinate: Hashable, Codable, Sendable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    /// Convenience with the web app's short field names.
    public init(lat: Double, lon: Double) {
        self.init(latitude: lat, longitude: lon)
    }

    public var lat: Double { latitude }
    public var lon: Double { longitude }

    /// True when both components are finite and within range.
    public var isValid: Bool {
        latitude.isFinite && longitude.isFinite
            && abs(latitude) <= 90 && abs(longitude) <= 180
    }
}

/// A geocoded place: what the user typed, how it resolved, and where.
public struct PlacePoint: Hashable, Codable, Sendable {
    public var query: String
    public var label: String
    public var coordinate: Coordinate
    /// IANA identifier (e.g. "America/Denver") when the geocoder knows it.
    public var timeZoneID: String?

    public init(query: String, label: String, coordinate: Coordinate, timeZoneID: String? = nil) {
        self.query = query
        self.label = label
        self.coordinate = coordinate
        self.timeZoneID = timeZoneID
    }

    /// The part before the first comma — the web app uses this for short
    /// labels like "via Amarillo" and "Denver → Dallas".
    public var shortLabel: String {
        let s = label.split(separator: ",", maxSplits: 1).first.map(String.init) ?? label
        return s.trimmingCharacters(in: .whitespaces)
    }
}
