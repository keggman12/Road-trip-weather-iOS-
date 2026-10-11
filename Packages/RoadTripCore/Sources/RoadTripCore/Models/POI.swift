import Foundation

/// The three POI overlays. Raw values match the web's kind strings.
public enum POIKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case bucees
    case loves
    case rest

    public var id: String { rawValue }

    /// Web `POI_TYPES.name`.
    public var displayName: String {
        switch self {
        case .bucees: "Buc-ee's"
        case .loves: "Love's Travel Stops"
        case .rest: "rest areas"
        }
    }

    /// Web `POI_TYPES.tag` — the stop-card tag when a POI becomes a stop.
    public var stopTag: String {
        switch self {
        case .bucees: "BUC-EE'S"
        case .loves: "LOVE'S"
        case .rest: "REST AREA"
        }
    }

    /// Web `POI_TYPES.short` — the letter on the map pin.
    public var pinLetter: String {
        switch self {
        case .bucees: "B"
        case .loves: "L"
        case .rest: "P"
        }
    }

    /// Web `POI_TYPES.fuel` — whether "Add as fuel stop" vs "Add as stop".
    public var isFuel: Bool { self != .rest }

    /// Web `POI_TYPES.radiusM`: brands get a wider corridor than rest areas.
    public var corridorRadiusMeters: Double {
        switch self {
        case .bucees, .loves: 8000
        case .rest: 4000
        }
    }

    /// Web dedupe precision: `toFixed(2)` for brands (~1.1 km cells),
    /// `toFixed(3)` for rest areas so paired NB/SB facilities survive.
    public var dedupeDecimals: Int {
        self == .rest ? 3 : 2
    }

    /// Fallback name when OSM has neither `name` nor `brand`.
    public var fallbackName: String {
        switch self {
        case .bucees: "Buc-ee's"
        case .loves: "Love's Travel Stop"
        case .rest: "Rest area"
        }
    }

    /// Minimum parsed count below which a refresh is rejected as a layout
    /// change (web `seed-pois.js`: 30 Buc-ee's, 300 Love's). Rest areas are
    /// never refreshed in-app.
    public var sanityMinimumCount: Int {
        switch self {
        case .bucees: 30
        case .loves: 300
        case .rest: 1
        }
    }
}

/// Where a POI record came from.
public enum POISource: String, Codable, Sendable {
    case bundled
    case official
    case osm
    case imported
}

/// A fuel stop / rest area candidate.
public struct POI: Hashable, Codable, Sendable, Identifiable {
    public var kind: POIKind
    /// Stable id within the kind: `bucees/57`, `loves/312`, `node/123456`.
    public var sourceID: String
    public var name: String
    /// Street address, "I-35 · Exit 212", or "Rest area" / "Service plaza".
    public var detail: String?
    public var coordinate: Coordinate

    public var id: String { "\(kind.rawValue):\(sourceID)" }

    public init(kind: POIKind, sourceID: String, name: String, detail: String? = nil, coordinate: Coordinate) {
        self.kind = kind
        self.sourceID = sourceID
        self.name = name
        self.detail = detail
        self.coordinate = coordinate
    }
}

/// The bundled snapshot file (`pois-snapshot.json`) written by
/// `tools/poi-snapshot` and read by the app on first launch.
public struct POISnapshot: Codable, Sendable {
    public struct KindPayload: Codable, Sendable {
        public var source: POISource
        public var fetchedAt: Date
        public var count: Int
        public var pois: [POI]

        public init(source: POISource, fetchedAt: Date, pois: [POI]) {
            self.source = source
            self.fetchedAt = fetchedAt
            self.count = pois.count
            self.pois = pois
        }
    }

    public static let currentFormatVersion = 1

    public var formatVersion: Int
    public var generatedAt: Date
    public var kinds: [String: KindPayload]

    public init(generatedAt: Date, kinds: [POIKind: KindPayload]) {
        self.formatVersion = POISnapshot.currentFormatVersion
        self.generatedAt = generatedAt
        self.kinds = Dictionary(uniqueKeysWithValues: kinds.map { ($0.key.rawValue, $0.value) })
    }

    public func payload(for kind: POIKind) -> KindPayload? {
        kinds[kind.rawValue]
    }

    public static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    public static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return e
    }
}
