import Foundation
import RoadTripCore
import SwiftData

/// SwiftData-backed `POIService`. Imports the bundled snapshot on first
/// launch, serves kinds to the corridor filter, and replaces a kind
/// wholesale in one transaction on refresh (web `seed-pois.js` semantics:
/// failures never touch existing rows).
@MainActor
final class POIStore: POIService {
    private let container: ModelContainer
    private let refresher: POIRefreshService?
    private let statusStore: DataSourceStatusStore

    /// Automatic refresh is allowed at most this often (be polite to the chains).
    static let autoRefreshInterval: TimeInterval = 7 * 24 * 3600

    init(container: ModelContainer, refresher: POIRefreshService?, statusStore: DataSourceStatusStore) {
        self.container = container
        self.refresher = refresher
        self.statusStore = statusStore
    }

    private var context: ModelContext { container.mainContext }

    // MARK: Bundled snapshot

    private var importTask: Task<Void, Never>?

    /// Starts importing the bundled snapshot on a background context and
    /// returns at once, so launch never waits on ~4,000 inserts. Reads and
    /// refreshes wait for it to finish.
    func startBundledSnapshotImport(bundle: Bundle = .main) {
        guard importTask == nil else { return }
        let url = bundle.url(forResource: "pois-snapshot", withExtension: "json")
        let importer = POISnapshotImporter(modelContainer: container)
        importTask = Task {
            let outcome = await importer.importIfNeeded(snapshotURL: url)
            if let error = outcome.loadError { statusStore.recordError(.bundledSnapshot, error) }
            for (kind, count) in outcome.imported { statusStore.recordSuccess(DataSource(kind), count: count) }
            for (kind, error) in outcome.failed { statusStore.recordError(DataSource(kind), error) }
        }
    }

    /// Imports kinds that have never been loaded, or whose bundled snapshot
    /// is newer than what a bundled import previously wrote. Kinds refreshed
    /// from a live source are left alone.
    func importBundledSnapshotIfNeeded(bundle: Bundle = .main) async {
        startBundledSnapshotImport(bundle: bundle)
        await importTask?.value
    }

    // MARK: POIService

    func pois(kind: POIKind) async throws -> [POI] {
        await importTask?.value
        let raw = kind.rawValue
        let descriptor = FetchDescriptor<POIRecord>(predicate: #Predicate { $0.kindRaw == raw })
        return try context.fetch(descriptor).compactMap(POIMapper.poi(from:))
    }

    func refresh(kind: POIKind) async throws -> POIRefreshOutcome {
        guard let refresher else { throw ServiceError.unavailable("POI refresh") }
        await importTask?.value
        let meta = metaRecord(for: kind)
        meta.lastAttemptAt = Date()
        do {
            let fetched = try await refresher.fetch(kind: kind)
            replace(kind: kind, with: fetched.pois, source: fetched.source, snapshotVersion: meta.snapshotVersion, fetchedAt: Date())
            meta.lastError = fetched.officialError.map { "Official site failed (\($0)); used OpenStreetMap." }
            try? context.save()
            statusStore.recordSuccess(DataSource(kind), count: fetched.pois.count)
            return POIRefreshOutcome(kind: kind, count: fetched.pois.count, source: fetched.source)
        } catch {
            meta.lastError = String(describing: error)
            try? context.save()
            statusStore.recordError(DataSource(kind), String(describing: error))
            throw error
        }
    }

    /// True when the kind has not been refreshed within the weekly window.
    func isDueForAutoRefresh(kind: POIKind, now: Date = Date()) -> Bool {
        guard kind != .rest else { return false }
        let meta = metaRecord(for: kind)
        if let last = meta.lastAttemptAt, now.timeIntervalSince(last) < POIStore.autoRefreshInterval { return false }
        if let last = meta.lastUpdated, meta.sourceRaw != POISource.bundled.rawValue, now.timeIntervalSince(last) < POIStore.autoRefreshInterval { return false }
        return true
    }

    /// Read-only: never inserts, so it can't race the background import
    /// into a duplicate meta row.
    func meta(for kind: POIKind) -> POIMetaRecord? { POIWriter.existingMeta(for: kind, in: context) }

    /// Manual import (Files app / share sheet). Deduped with the kind's
    /// precision, replaces the kind wholesale.
    func importManually(_ pois: [POI], kind: POIKind) throws {
        let filtered = POINormalizer.dedupe(pois.filter { $0.kind == kind })
        guard !filtered.isEmpty else { throw ServiceError.badPayload("import file (no \(kind.displayName) rows)") }
        replace(kind: kind, with: filtered, source: .imported, snapshotVersion: metaRecord(for: kind).snapshotVersion, fetchedAt: Date())
        statusStore.recordSuccess(DataSource(kind), count: filtered.count)
    }

    // MARK: Internals

    private func metaRecord(for kind: POIKind) -> POIMetaRecord {
        POIWriter.metaRecord(for: kind, in: context)
    }

    private func replace(kind: POIKind, with pois: [POI], source: POISource, snapshotVersion: String, fetchedAt: Date) {
        do {
            try POIWriter.replace(kind: kind, with: pois, source: source, snapshotVersion: snapshotVersion, fetchedAt: fetchedAt, in: context)
            statusStore.recordSuccess(DataSource(kind), count: pois.count)
        } catch {
            statusStore.recordError(DataSource(kind), String(describing: error))
        }
    }
}

/// POI row writes shared by the main-actor store and the background importer.
enum POIWriter {
    static func existingMeta(for kind: POIKind, in context: ModelContext) -> POIMetaRecord? {
        let raw = kind.rawValue
        let descriptor = FetchDescriptor<POIMetaRecord>(predicate: #Predicate { $0.kindRaw == raw })
        return (try? context.fetch(descriptor))?.first
    }

    static func metaRecord(for kind: POIKind, in context: ModelContext) -> POIMetaRecord {
        if let existing = existingMeta(for: kind, in: context) { return existing }
        let created = POIMetaRecord(kindRaw: kind.rawValue)
        context.insert(created)
        return created
    }

    /// Single transaction: delete the kind's rows, insert the new ones,
    /// update meta. SwiftData's `transaction` rolls back on throw.
    static func replace(kind: POIKind, with pois: [POI], source: POISource, snapshotVersion: String, fetchedAt: Date, in context: ModelContext) throws {
        let raw = kind.rawValue
        try context.transaction {
            try context.delete(model: POIRecord.self, where: #Predicate { $0.kindRaw == raw })
            let now = Date()
            for p in POINormalizer.dedupe(pois) {
                context.insert(POIMapper.record(from: p, source: source, updatedAt: now))
            }
            let meta = metaRecord(for: kind, in: context)
            meta.lastUpdated = fetchedAt
            meta.count = pois.count
            meta.sourceRaw = source.rawValue
            meta.snapshotVersion = snapshotVersion
            meta.lastError = nil
        }
    }
}

/// Imports the bundled snapshot off the main actor.
@ModelActor
actor POISnapshotImporter {
    struct Outcome: Sendable {
        var imported: [(POIKind, Int)] = []
        var failed: [(POIKind, String)] = []
        var loadError: String?
    }

    func importIfNeeded(snapshotURL: URL?) -> Outcome {
        var outcome = Outcome()
        let snapshot: POISnapshot
        do {
            guard let snapshotURL else { throw ServiceError.unavailable("bundled POI snapshot") }
            snapshot = try POISnapshot.decoder().decode(POISnapshot.self, from: Data(contentsOf: snapshotURL))
        } catch {
            outcome.loadError = error.localizedDescription
            return outcome
        }
        let version = ISO8601DateFormatter().string(from: snapshot.generatedAt)
        for kind in POIKind.allCases {
            guard let payload = snapshot.payload(for: kind), !payload.pois.isEmpty else { continue }
            let meta = POIWriter.existingMeta(for: kind, in: modelContext)
            let neverLoaded = meta?.lastUpdated == nil
            let bundledAndOlder = meta?.sourceRaw == POISource.bundled.rawValue && meta?.snapshotVersion != version
            guard neverLoaded || bundledAndOlder else { continue }
            do {
                try POIWriter.replace(kind: kind, with: payload.pois, source: .bundled, snapshotVersion: version, fetchedAt: payload.fetchedAt, in: modelContext)
                outcome.imported.append((kind, payload.pois.count))
            } catch {
                outcome.failed.append((kind, String(describing: error)))
            }
        }
        return outcome
    }
}
