// poi-snapshot — harvest Buc-ee's, Love's Travel Stops and US rest areas into
// the app's bundled snapshot. Port of server/seed-pois.js.
//
//   swift run poi-snapshot --out ../../RoadTripWeather/Resources/pois-snapshot.json
//   swift run poi-snapshot --out … --kinds bucees,loves      # subset
//
// Sources (authoritative first):
//   bucees → buc-ees.com/locations (schema.org JSON-LD; store #, address)
//   loves  → loves.com/api/fetch_stores (Travel Stops only)
//   rest   → OpenStreetMap via Overpass (300 s, 1 GB, 50 000 results — Mac only)
// Brands fall back to exact-tag Overpass queries when the official site fails.
// A kind that fails every source keeps its rows from the existing snapshot;
// if nothing could be harvested the file is left untouched.

import Foundation
import RoadTripCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

let version = "0.1"
let triesPerMirror = 2
let overpassTimeout: TimeInterval = 330   // > the largest [timeout:] in the queries
let officialTimeout: TimeInterval = 60

struct Options {
    var out: String = "RoadTripWeather/Resources/pois-snapshot.json"
    var kinds: [POIKind] = POIKind.allCases
}

func parseOptions() -> Options {
    var o = Options()
    var args = Array(CommandLine.arguments.dropFirst())
    while !args.isEmpty {
        let a = args.removeFirst()
        switch a {
        case "--out":
            guard !args.isEmpty else { usage("--out needs a path") }
            o.out = args.removeFirst()
        case "--kinds":
            guard !args.isEmpty else { usage("--kinds needs a comma-separated list") }
            let names = args.removeFirst().split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            o.kinds = names.map { n in
                guard let k = POIKind(rawValue: n) else { usage("unknown kind \"\(n)\" — expected \(POIKind.allCases.map(\.rawValue).joined(separator: ", "))") }
                return k
            }
        case "-h", "--help":
            usage(nil)
        default:
            usage("unknown argument \(a)")
        }
    }
    return o
}

func usage(_ error: String?) -> Never {
    if let error { FileHandle.standardError.write(Data("error: \(error)\n".utf8)) }
    print("usage: poi-snapshot --out <path> [--kinds bucees,loves,rest]")
    exit(error == nil ? 0 : 64)
}

func log(_ s: String) { FileHandle.standardOutput.write(Data((s + "\n").utf8)) }
func logInline(_ s: String) { FileHandle.standardOutput.write(Data(s.utf8)) }

let session: URLSession = {
    let c = URLSessionConfiguration.ephemeral
    c.timeoutIntervalForRequest = overpassTimeout
    c.timeoutIntervalForResource = overpassTimeout
    return URLSession(configuration: c)
}()

func get(_ url: URL, accept: String, userAgent: String, timeout: TimeInterval) async throws -> Data {
    var req = URLRequest(url: url)
    req.timeoutInterval = timeout
    req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
    req.setValue(accept, forHTTPHeaderField: "Accept")
    let (data, resp) = try await session.data(for: req)
    let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
    guard (200..<300).contains(code) else { throw NSError(domain: "http", code: code, userInfo: [NSLocalizedDescriptionKey: "HTTP \(code)"]) }
    return data
}

// MARK: Official sites

func officialBucees() async throws -> [POI] {
    guard let url = URL(string: "https://buc-ees.com/locations/") else { throw URLError(.badURL) }
    let data = try await get(url, accept: "text/html", userAgent: ClientIdentity.browserStyleUserAgent(version: version), timeout: officialTimeout)
    return try BuceesLocationsParser.parse(html: String(decoding: data, as: UTF8.self))
}

func officialLoves() async throws -> [POI] {
    guard let url = URL(string: "https://www.loves.com/api/fetch_stores") else { throw URLError(.badURL) }
    let data = try await get(url, accept: "application/json", userAgent: ClientIdentity.browserStyleUserAgent(version: version), timeout: officialTimeout)
    return try LovesStoresParser.parse(data: data)
}

// MARK: Overpass

func overpass(_ query: String, label: String) async -> OverpassResponse? {
    for attempt in 0..<triesPerMirror {
        for url in OverpassQueries.mirrors {
            logInline("  \(label): \(url.host ?? url.absoluteString) (try \(attempt + 1))… ")
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.timeoutInterval = overpassTimeout
            req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            req.setValue(ClientIdentity.overpassUserAgent(version: version), forHTTPHeaderField: "User-Agent")
            req.httpBody = Data(("data=" + (query.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? query)).utf8)
            do {
                let (data, resp) = try await session.data(for: req)
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                guard (200..<300).contains(code) else { log("HTTP \(code)"); continue }
                let parsed = try OverpassResponse.decode(data)
                if parsed.isServerSideFailure {
                    log("remark: \(String(parsed.remark?.prefix(80) ?? ""))")
                    continue
                }
                log("\(parsed.elements.count) elements")
                return parsed
            } catch {
                log(error.localizedDescription)
            }
        }
    }
    return nil
}

// MARK: Main

func readExisting(_ path: String) -> POISnapshot? {
    guard let data = FileManager.default.contents(atPath: path) else { return nil }
    return try? POISnapshot.decoder().decode(POISnapshot.self, from: data)
}

func harvest(_ kind: POIKind) async -> POISnapshot.KindPayload? {
    log("\n\(kind.rawValue):")
    if kind != .rest {
        do {
            let pois = try kind == .bucees ? await officialBucees() : await officialLoves()
            log("  official site: \(pois.count) locations")
            return POISnapshot.KindPayload(source: .official, fetchedAt: Date(), pois: pois)
        } catch {
            log("  official site failed (\(error.localizedDescription)) — falling back to OpenStreetMap…")
        }
    }
    guard let response = await overpass(OverpassQueries.nationwide(kind), label: kind.rawValue) else {
        log("  FAILED — every source was unavailable.")
        return nil
    }
    let pois = POINormalizer.normalize(response.elements, kind: kind)
    guard pois.count >= kind.sanityMinimumCount else {
        log("  FAILED — only \(pois.count) \(kind.displayName) after normalisation (minimum \(kind.sanityMinimumCount)).")
        return nil
    }
    log("  OpenStreetMap: \(pois.count) locations")
    return POISnapshot.KindPayload(source: .osm, fetchedAt: Date(), pois: pois)
}

let options = parseOptions()
let existing = readExisting(options.out)
var kinds: [POIKind: POISnapshot.KindPayload] = [:]
for k in POIKind.allCases {
    if let p = existing?.payload(for: k) { kinds[k] = p }
}
var failed = 0
var changed = 0
for kind in options.kinds {
    if let payload = await harvest(kind) {
        kinds[kind] = payload
        changed += 1
    } else {
        failed += 1
        if let kept = existing?.payload(for: kind) {
            log("  keeping \(kept.count) \(kind.rawValue) rows from the existing snapshot (\(kept.fetchedAt)).")
        }
    }
}

guard changed > 0 else {
    log("\nNothing harvested; \(options.out) left untouched.")
    exit(2)
}

let snapshot = POISnapshot(generatedAt: Date(), kinds: kinds)
do {
    let data = try POISnapshot.encoder().encode(snapshot)
    let url = URL(fileURLWithPath: options.out)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    // Write atomically so a crash mid-write cannot leave a truncated snapshot.
    try data.write(to: url, options: .atomic)
    let summary = POIKind.allCases.compactMap { k in kinds[k].map { "\(k.rawValue)=\($0.count) (\($0.source.rawValue))" } }.joined(separator: ", ")
    log("\nWrote \(options.out): \(summary)")
} catch {
    log("\nFailed to write \(options.out): \(error.localizedDescription)")
    exit(1)
}
if failed > 0 { exit(2) }
