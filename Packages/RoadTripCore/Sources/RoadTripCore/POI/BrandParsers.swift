import Foundation

/// Errors shared by the official-site parsers.
public enum POIParseError: Error, Equatable, Sendable, CustomStringConvertible {
    case missingJSONLD
    case unexpectedPayload
    case tooFewResults(kind: POIKind, parsed: Int, minimum: Int)

    public var description: String {
        switch self {
        case .missingJSONLD:
            "no JSON-LD block on the locations page"
        case .unexpectedPayload:
            "unexpected fetch_stores payload"
        case let .tooFewResults(kind, parsed, minimum):
            "only \(parsed) \(kind.displayName) parsed (minimum \(minimum)) — site layout changed?"
        }
    }
}

/// Small helpers shared by both parsers.
enum ParserSupport {
    /// Web `decodeEntities`: numeric (`&#8211;`, `&#x2013;`) plus `&amp;`,
    /// `&quot;`, `&apos;`.
    static func decodeEntities(_ s: String) -> String {
        var out = s
        if let re = try? Regex(#"&#(\d+);"#) {
            out = out.replacing(re) { m in
                guard let numStr = m.output[1].substring, let n = UInt32(numStr), let sc = Unicode.Scalar(n) else { return "" }
                return String(Character(sc))
            }
        }
        if let re = try? Regex(#"&#[xX]([0-9a-fA-F]+);"#) {
            out = out.replacing(re) { m in
                guard let hex = m.output[1].substring, let n = UInt32(hex, radix: 16), let sc = Unicode.Scalar(n) else { return "" }
                return String(Character(sc))
            }
        }
        return out
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
    }

    /// Web `grab(chunk, key)`: first `"key": "value"` in the chunk.
    static func grab(_ chunk: Substring, key: String) -> String? {
        guard let re = try? Regex("\"\(key)\":\\s*\"([^\"]*)\"") else { return nil }
        guard let m = chunk.firstMatch(of: re) else { return nil }
        return m.output[1].substring.map(String.init)
    }

    static func fixed4(_ v: Double) -> String { String(format: "%.4f", v) }
}

/// buc-ees.com/locations embeds one schema.org JSON-LD block with a
/// `GasStation` entry per store. The blob is not always valid JSON (template
/// artifacts), so each store chunk is field-scraped, as the web script does.
public enum BuceesLocationsParser {
    public static let minimumCount = POIKind.bucees.sanityMinimumCount

    public static func parse(html: String, minimumCount: Int = minimumCount) throws -> [POI] {
        guard let block = try? Regex(#"<script type="application/ld\+json">([\s\S]*?)</script>"#),
              let m = html.firstMatch(of: block),
              let jsonld = m.output[1].substring
        else { throw POIParseError.missingJSONLD }

        guard let splitter = try? Regex(#""@type":\s*"GasStation""#) else { throw POIParseError.missingJSONLD }
        let chunks = jsonld.split(separator: splitter, omittingEmptySubsequences: false).dropFirst()

        var out: [POI] = []
        for chunk in chunks {
            guard let latS = ParserSupport.grab(chunk, key: "latitude"),
                  let lonS = ParserSupport.grab(chunk, key: "longitude"),
                  let lat = Double(latS), let lon = Double(lonS),
                  lat.isFinite, lon.isFinite
            else { continue }
            let rawName = ParserSupport.decodeEntities(ParserSupport.grab(chunk, key: "name") ?? "")
            let street = ParserSupport.decodeEntities(ParserSupport.grab(chunk, key: "streetAddress") ?? "")
            let number = storeNumber(in: rawName)
            let coordinate = Coordinate(lat: lat, lon: lon)
            out.append(POI(
                kind: .bucees,
                sourceID: "bucees/" + (number ?? "\(ParserSupport.fixed4(lat)),\(ParserSupport.fixed4(lon))"),
                name: rawName.isEmpty ? "Buc-ee's" : "Buc-ee's \(rawName)",
                detail: street.isEmpty ? nil : street,
                coordinate: coordinate
            ))
        }
        if out.count < minimumCount {
            throw POIParseError.tooFewResults(kind: .bucees, parsed: out.count, minimum: minimumCount)
        }
        return out
    }

    /// `#57 – Athens, AL` → "57".
    public static func storeNumber(in name: String) -> String? {
        guard let re = try? Regex(#"#(\d+)"#), let m = name.firstMatch(of: re) else { return nil }
        return m.output[1].substring.map(String.init)
    }
}

/// loves.com/api/fetch_stores returns every Love's facility. Keep Travel
/// Stops (`mapPinUrl` contains "travelstop"); skip Country Stores and Speedco.
public enum LovesStoresParser {
    public static let minimumCount = POIKind.loves.sanityMinimumCount

    /// A number that the API may serve as a JSON number or a string.
    struct LooseNumber: Decodable {
        var value: Double?
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let d = try? c.decode(Double.self) { value = d; return }
            if let s = try? c.decode(String.self) { value = Double(s.trimmingCharacters(in: .whitespaces)); return }
            value = nil
        }
    }

    struct LooseString: Decodable {
        var value: String?
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let s = try? c.decode(String.self) { value = s; return }
            if let i = try? c.decode(Int.self) { value = String(i); return }
            if let d = try? c.decode(Double.self) { value = d == d.rounded() ? String(Int(d)) : String(d); return }
            value = nil
        }
    }

    struct Store: Decodable {
        var number: LooseString?
        var mapPinUrl: String?
        var latitude: LooseNumber?
        var longitude: LooseNumber?
        var city: String?
        var state: String?
        var highway: LooseString?
        var exitNumber: LooseString?
    }

    struct Payload: Decodable {
        var stores: [Store]?
    }

    public static func parse(data: Data, minimumCount: Int = minimumCount) throws -> [POI] {
        let payload: Payload
        do { payload = try JSONDecoder().decode(Payload.self, from: data) }
        catch { throw POIParseError.unexpectedPayload }
        guard let stores = payload.stores else { throw POIParseError.unexpectedPayload }

        var out: [POI] = []
        for s in stores {
            guard let pin = s.mapPinUrl, pin.range(of: "travelstop", options: .caseInsensitive) != nil else { continue }
            guard let lat = s.latitude?.value, let lon = s.longitude?.value, lat.isFinite, lon.isFinite else { continue }
            let number = s.number?.value.flatMap { $0.isEmpty ? nil : $0 }
            let place = [s.city, s.state].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
            let detail = [s.highway?.value, s.exitNumber?.value].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
            out.append(POI(
                kind: .loves,
                sourceID: "loves/" + (number ?? "\(ParserSupport.fixed4(lat)),\(ParserSupport.fixed4(lon))"),
                name: "Love's #\(number ?? "?")" + (place.isEmpty ? "" : " — \(place)"),
                detail: detail.isEmpty ? nil : detail,
                coordinate: Coordinate(lat: lat, lon: lon)
            ))
        }
        if out.count < minimumCount {
            throw POIParseError.tooFewResults(kind: .loves, parsed: out.count, minimum: minimumCount)
        }
        return out
    }
}

/// Browser-style identification used for the chains' sites (web `BROWSER_UA`)
/// and the identifying UA Overpass asks for.
public enum ClientIdentity {
    public static let repoURL = "https://github.com/keggman12/Road-trip-weather-iOS-"

    public static func browserStyleUserAgent(version: String) -> String {
        "Mozilla/5.0 (compatible; RoadTripWeather-iOS/\(version); +\(repoURL))"
    }

    /// NWS wants an app name and a way to reach you.
    public static func nwsUserAgent(version: String, contact: String?) -> String {
        let trimmed = contact?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let who = trimmed.isEmpty ? repoURL : "\(repoURL); \(trimmed)"
        return "RoadTripWeather-iOS/\(version) (\(who))"
    }

    public static func overpassUserAgent(version: String) -> String {
        "RoadTripWeather-iOS/\(version) (\(repoURL))"
    }
}
