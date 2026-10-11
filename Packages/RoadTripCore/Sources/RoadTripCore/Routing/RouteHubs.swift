import Foundation

/// Suggests extra via cities for "More routes": routing services return only
/// a few alternatives, so the app asks for routes through hubs off to either
/// side of the trip. Coordinates here only choose candidates; the city is
/// geocoded by name before routing, so small errors don't matter.
public enum RouteHubs {
    public struct Hub: Hashable, Sendable {
        public var name: String
        public var state: String
        public var coordinate: Coordinate
        public var query: String { "\(name), \(state)" }
    }

    /// Longest acceptable trip through a hub, relative to the straight line.
    public static let maxDetour = 1.35
    /// A hub this close to an existing route would just repeat it.
    public static let minDistanceFromRoutesMi = 25.0
    /// Hubs this close to the origin or destination add nothing.
    public static let minDistanceFromEndsMi = 50.0
    /// Chosen hubs must be at least this far apart.
    public static let minSpacingMi = 75.0

    /// Up to `count` hubs off the existing routes, alternating sides of the
    /// origin→destination line, lowest detour first.
    public static func candidates(origin: Coordinate, destination: Coordinate, existingRoutes: [[Coordinate]], count: Int = 4, hubs: [Hub] = all) -> [Hub] {
        let direct = Geo.haversineMiles(origin, destination)
        guard direct > 2 * minDistanceFromEndsMi else { return [] }
        let refs = existingRoutes.map { Geo.thinPolyline($0, maxPoints: 300) }
        struct Scored { var hub: Hub; var detour: Double; var left: Bool }
        let scored: [Scored] = hubs.compactMap { h in
            let a = Geo.haversineMiles(origin, h.coordinate), b = Geo.haversineMiles(h.coordinate, destination)
            guard a >= minDistanceFromEndsMi, b >= minDistanceFromEndsMi else { return nil }
            let detour = (a + b) / direct
            guard detour <= maxDetour else { return nil }
            guard refs.allSatisfy({ Geo.minDistanceMiles(from: h.coordinate, to: $0) >= minDistanceFromRoutesMi }) else { return nil }
            // Side of the origin→destination line (planar cross product is fine at this scale).
            let cross = (destination.lon - origin.lon) * (h.coordinate.lat - origin.lat) - (destination.lat - origin.lat) * (h.coordinate.lon - origin.lon)
            return Scored(hub: h, detour: detour, left: cross > 0)
        }
        var left = scored.filter(\.left).sorted { $0.detour < $1.detour }
        var right = scored.filter { !$0.left }.sorted { $0.detour < $1.detour }
        var picked: [Hub] = []
        var takeLeft = (left.first?.detour ?? .infinity) <= (right.first?.detour ?? .infinity)
        while picked.count < count, !(left.isEmpty && right.isEmpty) {
            var side = takeLeft ? left : right
            if side.isEmpty { takeLeft.toggle(); continue }
            let next = side.removeFirst()
            if takeLeft { left = side } else { right = side }
            if picked.allSatisfy({ Geo.haversineMiles($0.coordinate, next.hub.coordinate) >= minSpacingMi }) {
                picked.append(next.hub)
                takeLeft.toggle()
            }
        }
        return picked
    }

    /// "Suggested · via Lubbock, TX".
    public static func label(for hub: Hub) -> String { "Suggested · via \(hub.query)" }

    static func h(_ n: String, _ s: String, _ lat: Double, _ lon: Double) -> Hub {
        Hub(name: n, state: s, coordinate: Coordinate(lat: lat, lon: lon))
    }

    /// Highway hub cities across the lower 48 (approximate centres).
    public static let all: [Hub] = [
        h("Albuquerque", "NM", 35.08, -106.65), h("Santa Fe", "NM", 35.69, -105.94), h("Las Cruces", "NM", 32.31, -106.78),
        h("Tucumcari", "NM", 35.17, -103.72), h("Clovis", "NM", 34.40, -103.21), h("Roswell", "NM", 33.39, -104.52),
        h("Gallup", "NM", 35.53, -108.74), h("Raton", "NM", 36.90, -104.44), h("Clayton", "NM", 36.45, -103.18),
        h("Amarillo", "TX", 35.22, -101.83), h("Lubbock", "TX", 33.58, -101.86), h("Wichita Falls", "TX", 33.91, -98.49),
        h("Abilene", "TX", 32.45, -99.73), h("San Angelo", "TX", 31.46, -100.44), h("Midland", "TX", 32.00, -102.08),
        h("El Paso", "TX", 31.76, -106.49), h("Fort Stockton", "TX", 30.89, -102.88), h("San Antonio", "TX", 29.42, -98.49),
        h("Austin", "TX", 30.27, -97.74), h("Waco", "TX", 31.55, -97.15), h("Houston", "TX", 29.76, -95.37),
        h("Dallas", "TX", 32.78, -96.80), h("Tyler", "TX", 32.35, -95.30), h("Texarkana", "TX", 33.43, -94.05),
        h("Childress", "TX", 34.43, -100.20), h("Dalhart", "TX", 36.06, -102.52), h("Laredo", "TX", 27.51, -99.51),
        h("Corpus Christi", "TX", 27.80, -97.40), h("Beaumont", "TX", 30.08, -94.13),
        h("Oklahoma City", "OK", 35.47, -97.52), h("Tulsa", "OK", 36.15, -95.99), h("Lawton", "OK", 34.61, -98.39),
        h("Woodward", "OK", 36.43, -99.39), h("Guymon", "OK", 36.68, -101.48), h("Enid", "OK", 36.40, -97.88), h("McAlester", "OK", 34.93, -95.77),
        h("Wichita", "KS", 37.69, -97.34), h("Dodge City", "KS", 37.75, -100.02), h("Garden City", "KS", 37.97, -100.87),
        h("Liberal", "KS", 37.04, -100.92), h("Salina", "KS", 38.84, -97.61), h("Hays", "KS", 38.88, -99.33),
        h("Goodland", "KS", 39.35, -101.71), h("Topeka", "KS", 39.05, -95.68), h("Pratt", "KS", 37.64, -98.74),
        h("Kansas City", "MO", 39.10, -94.58), h("Springfield", "MO", 37.21, -93.29), h("St. Louis", "MO", 38.63, -90.20), h("Joplin", "MO", 37.08, -94.51),
        h("Denver", "CO", 39.74, -104.99), h("Colorado Springs", "CO", 38.83, -104.82), h("Pueblo", "CO", 38.25, -104.61),
        h("Trinidad", "CO", 37.17, -104.50), h("Lamar", "CO", 38.09, -102.62), h("Limon", "CO", 39.26, -103.69),
        h("Grand Junction", "CO", 39.06, -108.55), h("Alamosa", "CO", 37.47, -105.87), h("Durango", "CO", 37.28, -107.88),
        h("Fort Collins", "CO", 40.59, -105.08), h("Sterling", "CO", 40.63, -103.21), h("Glenwood Springs", "CO", 39.55, -107.32),
        h("Cheyenne", "WY", 41.14, -104.82), h("Laramie", "WY", 41.31, -105.59), h("Rawlins", "WY", 41.79, -107.24),
        h("Rock Springs", "WY", 41.59, -109.20), h("Casper", "WY", 42.87, -106.31), h("Sheridan", "WY", 44.80, -106.96),
        h("North Platte", "NE", 41.12, -100.77), h("Kearney", "NE", 40.70, -99.08), h("Lincoln", "NE", 40.81, -96.70),
        h("Omaha", "NE", 41.26, -95.93), h("Scottsbluff", "NE", 41.87, -103.66), h("Ogallala", "NE", 41.13, -101.72),
        h("Rapid City", "SD", 44.08, -103.23), h("Sioux Falls", "SD", 43.55, -96.73), h("Pierre", "SD", 44.37, -100.35),
        h("Billings", "MT", 45.78, -108.50), h("Bozeman", "MT", 45.68, -111.04), h("Missoula", "MT", 46.87, -113.99), h("Great Falls", "MT", 47.50, -111.30),
        h("Bismarck", "ND", 46.81, -100.78), h("Fargo", "ND", 46.88, -96.79),
        h("Salt Lake City", "UT", 40.76, -111.89), h("Green River", "UT", 38.99, -110.16), h("Cedar City", "UT", 37.68, -113.06), h("Moab", "UT", 38.57, -109.55),
        h("Flagstaff", "AZ", 35.20, -111.65), h("Phoenix", "AZ", 33.45, -112.07), h("Tucson", "AZ", 32.22, -110.97), h("Kingman", "AZ", 35.19, -114.05),
        h("Las Vegas", "NV", 36.17, -115.14), h("Reno", "NV", 39.53, -119.81), h("Elko", "NV", 40.83, -115.76), h("Ely", "NV", 39.25, -114.89),
        h("Boise", "ID", 43.62, -116.20), h("Idaho Falls", "ID", 43.49, -112.03), h("Twin Falls", "ID", 42.56, -114.46),
        h("Los Angeles", "CA", 34.05, -118.24), h("Barstow", "CA", 34.90, -117.02), h("Bakersfield", "CA", 35.37, -119.02),
        h("Sacramento", "CA", 38.58, -121.49), h("Fresno", "CA", 36.74, -119.79), h("Redding", "CA", 40.59, -122.39), h("San Diego", "CA", 32.72, -117.16),
        h("Portland", "OR", 45.52, -122.68), h("Medford", "OR", 42.33, -122.87), h("Bend", "OR", 44.06, -121.32), h("Pendleton", "OR", 45.67, -118.79),
        h("Seattle", "WA", 47.61, -122.33), h("Spokane", "WA", 47.66, -117.43), h("Yakima", "WA", 46.60, -120.51),
        h("Little Rock", "AR", 34.75, -92.29), h("Fort Smith", "AR", 35.39, -94.40), h("Shreveport", "LA", 32.53, -93.75),
        h("Baton Rouge", "LA", 30.45, -91.19), h("New Orleans", "LA", 29.95, -90.07), h("Jackson", "MS", 32.30, -90.18),
        h("Memphis", "TN", 35.15, -90.05), h("Nashville", "TN", 36.16, -86.78), h("Knoxville", "TN", 35.96, -83.92),
        h("Birmingham", "AL", 33.52, -86.80), h("Mobile", "AL", 30.69, -88.04), h("Atlanta", "GA", 33.75, -84.39), h("Macon", "GA", 32.84, -83.63),
        h("Jacksonville", "FL", 30.33, -81.66), h("Tallahassee", "FL", 30.44, -84.28), h("Orlando", "FL", 28.54, -81.38),
        h("Charlotte", "NC", 35.23, -80.84), h("Raleigh", "NC", 35.78, -78.64), h("Columbia", "SC", 34.00, -81.03),
        h("Richmond", "VA", 37.54, -77.44), h("Roanoke", "VA", 37.27, -79.94), h("Charleston", "WV", 38.35, -81.63),
        h("Louisville", "KY", 38.25, -85.76), h("Lexington", "KY", 38.04, -84.50), h("Indianapolis", "IN", 39.77, -86.16),
        h("Chicago", "IL", 41.88, -87.63), h("Springfield", "IL", 39.80, -89.64), h("Des Moines", "IA", 41.59, -93.62),
        h("Minneapolis", "MN", 44.98, -93.27), h("Madison", "WI", 43.07, -89.40), h("Detroit", "MI", 42.33, -83.05),
        h("Columbus", "OH", 39.96, -83.00), h("Cleveland", "OH", 41.50, -81.69), h("Pittsburgh", "PA", 40.44, -80.00),
        h("Harrisburg", "PA", 40.27, -76.88), h("Albany", "NY", 42.65, -73.76), h("Buffalo", "NY", 42.89, -78.88),
    ]
}
