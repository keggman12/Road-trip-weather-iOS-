import CoreTransferable
import Foundation
import RoadTripCore
import UniformTypeIdentifiers

extension UTType {
    /// GPX has no system type; declare it by extension, conforming to XML.
    static let gpx = UTType(filenameExtension: "gpx", conformingTo: .xml) ?? .xml
}

/// A briefing as a shareable `.gpx` file. The document is only built when
/// the share sheet asks for it, not every time the menu renders.
struct GPXExport: Transferable, Sendable {
    let tripName: String
    let briefing: Briefing

    var fileName: String { GPXBuilder.fileName(for: tripName) }

    func gpx(now: Date = Date()) -> String {
        GPXBuilder.build(name: tripName, coordinates: briefing.geometry.coordinates, stops: briefing.stops, now: now)
    }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .gpx) { export in
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent(export.fileName)
            try Data(export.gpx().utf8).write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }
}
