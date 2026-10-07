import Foundation

/// A vehicle in the garage. `rangeMi` sets the waypoint spacing.
public struct Vehicle: Hashable, Codable, Sendable, Identifiable {
    public static let minRangeMi: Double = 20
    public static let maxRangeMi: Double = 800

    public var id: String
    public var name: String
    public var rangeMi: Double
    public var isEV: Bool

    public init(id: String, name: String, rangeMi: Double, isEV: Bool = false) {
        self.id = id
        self.name = name
        self.rangeMi = Vehicle.clampRange(rangeMi)
        self.isEV = isEV
    }

    /// Web: `Math.max(20, Math.min(800, range))`.
    public static func clampRange(_ miles: Double) -> Double {
        guard miles.isFinite else { return minRangeMi }
        return min(maxRangeMi, max(minRangeMi, miles))
    }

    /// Web `DEFAULT_VEHICLES` (motorcycle is 180 since web 0.4.0).
    public static let defaults: [Vehicle] = [
        Vehicle(id: "auto", name: "Automobile", rangeMi: 300),
        Vehicle(id: "moto", name: "Motorcycle", rangeMi: 180),
        Vehicle(id: "tesla", name: "Tesla", rangeMi: 250, isEV: true),
    ]

    /// Web: `"veh-" + name.toLowerCase().replace(/[^a-z0-9]+/g, "-")`.
    public static func slugID(for name: String) -> String {
        var out = ""
        var pendingDash = false
        for ch in name.lowercased() {
            if ch.isASCII, ch.isLetter || ch.isNumber {
                if pendingDash { out.append("-"); pendingDash = false }
                out.append(ch)
            } else {
                pendingDash = true
            }
        }
        if pendingDash { out.append("-") }
        return "veh-" + out
    }
}
