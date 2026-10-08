import RoadTripCore
import SwiftUI

/// "Data sources and freshness": per source, last success, record count,
/// last error, this session's call count; manual POI refresh buttons.
struct DataSourcesView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var refreshing: POIKind?
    @State private var message: String?

    var body: some View {
        List {
            ForEach(DataSource.allCases) { source in
                let s = env.status.status(source)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(source.title).fontWeight(.semibold)
                        Spacer()
                        if let calls = env.status.sessionCalls[source], calls > 0 {
                            Text("\(calls) calls").font(.caption.monospacedDigit()).foregroundStyle(Theme.muted)
                        }
                    }
                    if let ok = s.lastSuccessAt {
                        Text("Last success \(Fmt.age(ok)) · \(s.recordCount) record\(s.recordCount == 1 ? "" : "s")")
                            .font(.caption).foregroundStyle(Theme.ok)
                    } else {
                        Text(source == .openChargeMap && env.settings.openChargeMapKey.isEmpty ? "disabled — add a key in Settings" : "no successful call yet")
                            .font(.caption).foregroundStyle(Theme.muted)
                    }
                    if let err = s.lastError {
                        Text("Error\(s.lastErrorAt.map { " \(Fmt.age($0))" } ?? ""): \(err)").font(.caption2).foregroundStyle(Theme.danger).lineLimit(3)
                    }
                    if let kind = poiKind(source), kind != .rest {
                        HStack {
                            if let meta = env.pois.meta(for: kind) {
                                Text("Source: \(meta.sourceRaw)\(meta.snapshotVersion.isEmpty ? "" : " · snapshot \(meta.snapshotVersion.prefix(10))")")
                                    .font(.caption2).foregroundStyle(Theme.muted)
                            } else {
                                Text("Loading bundled snapshot…")
                                    .font(.caption2).foregroundStyle(Theme.muted)
                            }
                            Spacer()
                            Button(refreshing == kind ? "Refreshing…" : "Refresh now") {
                                Task { await refresh(kind) }
                            }
                            .controlSize(.small)
                            .disabled(refreshing != nil)
                        }
                    }
                }
                .padding(.vertical, 4)
                .listRowBackground(Theme.surface)
            }
            if let message { Text(message).font(.footnote).foregroundStyle(Theme.muted) }
            Section {
                Text("Refreshes replace a kind wholesale only after the official site (or OpenStreetMap fallback) returns at least 30 Buc-ee's / 300 Love's. Failures never overwrite existing data. Rest areas come from the bundled snapshot; regenerate it with tools/poi-snapshot.")
                    .font(.caption2).foregroundStyle(Theme.muted)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Data sources")
        .id(env.status.revision)
    }

    private func poiKind(_ source: DataSource) -> POIKind? {
        switch source {
        case .bucees: .bucees
        case .loves: .loves
        case .rest: .rest
        default: nil
        }
    }

    private func refresh(_ kind: POIKind) async {
        refreshing = kind
        defer { refreshing = nil }
        do {
            let outcome = try await env.pois.refresh(kind: kind)
            message = "\(kind.displayName): \(outcome.count) locations from \(outcome.source.rawValue)."
        } catch {
            message = "\(kind.displayName) refresh failed — existing data kept. \(error.localizedDescription)"
        }
    }
}
