import Foundation

/// The seven condition buckets the web app renders (icons.js). Raw values
/// are the web's strings so saved data and tests line up.
public enum ConditionCategory: String, Codable, Sendable, CaseIterable {
    case clear
    case partlyCloudy = "partly-cloudy"
    case mostlyCloudy = "mostly-cloudy"
    case rain
    case thunderstorm
    case severe
    case snow

    /// Web `CONDITION_LABEL`.
    public var label: String {
        switch self {
        case .clear: "Clear"
        case .partlyCloudy: "Partly cloudy"
        case .mostlyCloudy: "Mostly cloudy"
        case .rain: "Rain"
        case .thunderstorm: "Thunderstorm"
        case .severe: "Severe"
        case .snow: "Snow"
        }
    }

    /// Web `CONDITION_BADGE.fg`.
    public var badgeColorHex: String {
        switch self {
        case .clear: "#fbbf24"
        case .partlyCloudy: "#7dd3fc"
        case .mostlyCloudy: "#94a3b8"
        case .rain: "#38bdf8"
        case .thunderstorm: "#a78bfa"
        case .severe: "#f87171"
        case .snow: "#e0f2fe"
        }
    }

    /// Categories the precipitation chart paints red regardless of chance.
    public var isHazardousPrecipitation: Bool {
        self == .thunderstorm || self == .severe || self == .snow
    }

    /// Web fallback when no condition id is known: `<15 clear, <50 partly,
    /// else mostly`. Used by the WeatherKit adapter for conditions that only
    /// describe sky cover indirectly (clear/mostlyClear/hot/windy…).
    public static func fromCloudCover(percent: Double?) -> ConditionCategory {
        guard let percent else { return .clear }
        if percent < 15 { return .clear }
        if percent < 50 { return .partlyCloudy }
        return .mostlyCloudy
    }

    /// Reference port of `icons.categorize(owmId, cloudsPct)`. Not used by
    /// the iOS data path (WeatherKit has no OWM ids) but kept so tests can pin
    /// the bucket semantics the WeatherKit mapping must reproduce.
    public static func fromOpenWeatherMap(id: Int?, cloudPercent: Double?) -> ConditionCategory {
        if let id {
            if (200..<300).contains(id) { return .thunderstorm }
            if id == 771 || id == 781 { return .severe }
            if (300..<600).contains(id) { return .rain }
            if (600..<700).contains(id) { return .snow }
            if (700..<800).contains(id) { return .mostlyCloudy }
            if id == 800 { return .clear }
            if id == 801 || id == 802 { return .partlyCloudy }
            if id == 803 || id == 804 { return .mostlyCloudy }
        }
        if cloudPercent != nil { return fromCloudCover(percent: cloudPercent) }
        return .clear
    }
}

/// Which timeline the record came from — shown as a precision chip.
public enum ForecastKind: String, Codable, Sendable {
    case hourly
    case daily
}

/// Why a stop may have no usable forecast.
public enum ForecastHorizon: String, Codable, Sendable {
    /// A record was found for the ETA.
    case ok
    /// The ETA is past the provider's forecast window (WeatherKit: 10 days).
    case beyondHorizon
    /// The request failed; the card shows "Weather unavailable".
    case failed
}

/// Normalised forecast record for one stop at (about) its ETA — the Swift
/// shape of the web's `normalizeWx` output, in °F / mph / %.
public struct WeatherSnapshot: Hashable, Codable, Sendable {
    public var temperatureF: Int
    public var feelsLikeF: Int
    public var humidityPercent: Int?
    public var windMph: Int
    /// Direction the wind blows FROM, degrees clockwise from north.
    public var windFromDegrees: Double?
    public var cloudPercent: Int?
    /// Provider's own condition identifier (e.g. WeatherKit `WeatherCondition`
    /// raw value) for debugging and re-mapping.
    public var conditionRaw: String
    /// Human description, e.g. "light rain".
    public var conditionText: String
    public var category: ConditionCategory
    /// Timestamp of the record chosen (nearest to the ETA).
    public var recordDate: Date
    /// Probability of precipitation 0…1.
    public var precipitationChance: Double?
    public var kind: ForecastKind
    public var fetchedAt: Date

    public init(
        temperatureF: Int,
        feelsLikeF: Int,
        humidityPercent: Int? = nil,
        windMph: Int,
        windFromDegrees: Double? = nil,
        cloudPercent: Int? = nil,
        conditionRaw: String = "",
        conditionText: String = "",
        category: ConditionCategory,
        recordDate: Date,
        precipitationChance: Double? = nil,
        kind: ForecastKind,
        fetchedAt: Date = Date()
    ) {
        self.temperatureF = temperatureF
        self.feelsLikeF = feelsLikeF
        self.humidityPercent = humidityPercent
        self.windMph = windMph
        self.windFromDegrees = windFromDegrees
        self.cloudPercent = cloudPercent
        self.conditionRaw = conditionRaw
        self.conditionText = conditionText
        self.category = category
        self.recordDate = recordDate
        self.precipitationChance = precipitationChance
        self.kind = kind
        self.fetchedAt = fetchedAt
    }

    /// Web: `Math.round(pop * 100)`.
    public var precipitationPercent: Int? {
        precipitationChance.map { Int(($0 * 100).rounded()) }
    }
}

/// Picks the record nearest a target time — the web's `timelineNearest`
/// selection rule, generic over any timestamped record.
public enum NearestRecord {
    public static func pick<T>(from records: [T], date: (T) -> Date, nearestTo target: Date) -> T? {
        var best: T?
        var bestDelta = Double.infinity
        for r in records {
            let delta = abs(date(r).timeIntervalSince(target))
            if delta < bestDelta {
                bestDelta = delta
                best = r
            }
        }
        return best
    }
}
