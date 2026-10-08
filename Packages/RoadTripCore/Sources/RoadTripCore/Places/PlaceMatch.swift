import Foundation

/// Flags geocoder results whose name doesn't match what was typed — e.g.
/// "Rotan, New Mexico" resolving to "Raton, NM". Geocoders return their best
/// guess silently; a via-point that resolves somewhere else changes the route.
public enum PlaceMatch {
    /// True when neither the typed place name (text before the first comma)
    /// nor the resolved name (label before its first comma) contains the
    /// other, ignoring case, accents and punctuation.
    public static func isLikelyMismatch(query: String, label: String) -> Bool {
        let q = normalized(firstPart(query))
        let l = normalized(firstPart(label))
        guard !q.isEmpty, !l.isEmpty else { return false }
        return !(l.contains(q) || q.contains(l))
    }

    /// "“Rotan, New Mexico” matched Raton, NM — check the spelling or add the state."
    public static func notice(query: String, label: String) -> String {
        "“\(query)” matched \(label) — check the spelling or add the state."
    }

    static func firstPart(_ s: String) -> String {
        s.split(separator: ",", maxSplits: 1).first.map(String.init) ?? s
    }

    static func normalized(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init).joined()
    }
}

/// Default trip name: "Thornton → Dallas", or "Thornton → Dallas via Rotan".
public enum TripNaming {
    public static func defaultName(origin: String, vias: [String], destination: String) -> String {
        let base = "\(origin) → \(destination)"
        return vias.isEmpty ? base : base + " via " + vias.joined(separator: " · ")
    }
}

/// Names a stop from a reverse-geocoded place: "I-25 near Pueblo, CO".
public enum StopNaming {
    /// `road` is kept only when it looks like a numbered highway (has a digit).
    public static func label(road: String?, town: String?, county: String?, state: String?) -> String? {
        let place = [town ?? county, state].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
        let highway = road.flatMap { r in r.rangeOfCharacter(from: .decimalDigits) != nil ? r : nil }
        switch (highway, place.isEmpty) {
        case let (h?, false): return "\(h) near \(place)"
        case (nil, false): return "near \(place)"
        case let (h?, true): return h
        case (nil, true): return nil
        }
    }

    /// Rest-area names from OpenStreetMap are often just "Rest Area".
    public static func isGeneric(_ name: String, kind: POIKind) -> Bool {
        kind == .rest && ["rest area", "rest stop", "rest area/welcome center", ""].contains(name.lowercased().trimmingCharacters(in: .whitespaces))
    }
}
