import Foundation

/// A via-point dropped on the map instead of typed. Its query is the
/// coordinate itself ("38.05412, -104.98761"), so it routes through exactly
/// that spot and survives saved trips and relaunches without geocoding by
/// name (a pin in open country has no name to geocode).
public enum DroppedPin {
    /// "38.05412, -104.98761" — five decimals is about a metre.
    public static func query(for c: Coordinate) -> String {
        String(format: "%.5f, %.5f", c.latitude, c.longitude)
    }

    /// The coordinate typed or stored as "lat, lon", or nil for any other text.
    public static func coordinate(fromQuery text: String) -> Coordinate? {
        let parts = text.split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2, let lat = Double(parts[0]), let lon = Double(parts[1]) else { return nil }
        let c = Coordinate(latitude: lat, longitude: lon)
        return c.isValid ? c : nil
    }

    /// "Pin near Rye, CO"; "Pin near Rye" without a state; the coordinate
    /// when reverse geocoding found nothing. `shortLabel` (route labels,
    /// trip names) is the part before the comma: "Pin near Rye".
    public static func label(near town: String?, state: String?, coordinate: Coordinate) -> String {
        guard let town = town?.trimmingCharacters(in: .whitespaces), !town.isEmpty else {
            return String(format: "Pin %.3f° %.3f°", coordinate.latitude, coordinate.longitude)
        }
        let place = [town, state].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
        return "Pin near " + place
    }

    /// Where a new pin goes among the vias: the gap between consecutive
    /// points (origin, vias…, destination) it lengthens least, measured
    /// as the crow flies. Returns an index into the vias (0…vias.count).
    public static func insertionIndex(of pin: Coordinate, origin: Coordinate, vias: [Coordinate], destination: Coordinate) -> Int {
        let points = [origin] + vias + [destination]
        var best = 0
        var bestDetour = Double.infinity
        for i in 0..<(points.count - 1) {
            let a = points[i], b = points[i + 1]
            let detour = Geo.haversineMiles(a, pin) + Geo.haversineMiles(pin, b) - Geo.haversineMiles(a, b)
            if detour < bestDetour {
                bestDetour = detour
                best = i
            }
        }
        return best
    }
}
