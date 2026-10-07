import Foundation
import RoadTripCore

/// Packs coordinates as little-endian Float64 lat,lon pairs for compact
/// SwiftData blobs.
enum CoordinatePacking {
    static func pack(_ coords: [Coordinate]) -> Data {
        var data = Data(capacity: coords.count * 16)
        for c in coords {
            withUnsafeBytes(of: c.latitude.bitPattern.littleEndian) { data.append(contentsOf: $0) }
            withUnsafeBytes(of: c.longitude.bitPattern.littleEndian) { data.append(contentsOf: $0) }
        }
        return data
    }

    static func unpack(_ data: Data) -> [Coordinate] {
        let count = data.count / 16
        var out: [Coordinate] = []
        out.reserveCapacity(count)
        data.withUnsafeBytes { raw in
            for i in 0..<count {
                let latBits = raw.loadUnaligned(fromByteOffset: i * 16, as: UInt64.self)
                let lonBits = raw.loadUnaligned(fromByteOffset: i * 16 + 8, as: UInt64.self)
                out.append(Coordinate(
                    latitude: Double(bitPattern: UInt64(littleEndian: latBits)),
                    longitude: Double(bitPattern: UInt64(littleEndian: lonBits))
                ))
            }
        }
        return out
    }
}

enum JSONCoding {
    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    static func encode<T: Encodable>(_ value: T) -> Data {
        (try? encoder.encode(value)) ?? Data()
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data?) -> T? {
        guard let data, !data.isEmpty else { return nil }
        return try? decoder.decode(type, from: data)
    }
}
