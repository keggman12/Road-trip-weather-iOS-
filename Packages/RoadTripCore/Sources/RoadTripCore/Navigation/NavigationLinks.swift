import Foundation

/// Turn-by-turn hand-off for a stop (replaces the web's phone itinerary
/// links, `itinerary.js`).
public enum NavigationLinks {
    /// Opens the Waze app straight into navigation.
    public static func wazeApp(_ c: Coordinate) -> URL? {
        URL(string: "waze://?ll=\(GPXBuilder.fixed6(c.latitude)),\(GPXBuilder.fixed6(c.longitude))&navigate=yes")
    }

    /// Universal link used when Waze isn't installed — exactly the web
    /// itinerary's `wazeURL` (5 decimals, encoded comma, zoom 17).
    public static func wazeWeb(_ c: Coordinate) -> URL? {
        URL(string: "https://waze.com/ul?ll=\(String(format: "%.5f", c.latitude))%2C\(String(format: "%.5f", c.longitude))&navigate=yes&zoom=17")
    }

    /// Stops worth navigating to: everything after the origin.
    public static func isNavigable(stopIndex: Int) -> Bool { stopIndex > 0 }
}
