import Foundation
@testable import GISTools
@testable import GISToolsShapefile
import Testing

enum ShapefileTestSupport {

    static func temporaryBaseURL() -> URL {
        let directory = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("shp_test_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("test")
    }

    static func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    static func feature(
        _ geometry: GeoJsonGeometry,
        properties: [String: Sendable] = [:],
        id: Feature.Identifier? = nil
    ) -> Feature {
        Feature(geometry, id: id, properties: properties)
    }

    static func writeAndRead(
        _ features: [Feature],
        idColumn: String? = "id",
        dbfEncoding: String.Encoding = .utf8,
        calculateBoundingBox: Bool = false
    ) throws -> FeatureCollection {
        let url = temporaryBaseURL()
        defer { cleanup(url) }

        try ShapefileCoder.write(
            FeatureCollection(features),
            to: url,
            encoding: dbfEncoding,
            idColumn: idColumn)

        return try ShapefileCoder.read(
            from: url,
            calculateBoundingBox: calculateBoundingBox,
            idColumn: idColumn,
            dbfEncoding: dbfEncoding)
    }

    static func records(inShp data: Data) throws -> [(number: Int32, offset: Int, contentLength: Int)] {
        guard let words = data.readBigEndianInt32(at: 24) else {
            throw ShapefileError.corruptedRecord
        }

        let fileLength = Int(words) * 2
        var records: [(number: Int32, offset: Int, contentLength: Int)] = []
        var offset = 100

        while offset < fileLength {
            guard let number = data.readBigEndianInt32(at: offset),
                  let contentWords = data.readBigEndianInt32(at: offset + 4),
                  contentWords >= 0
            else {
                throw ShapefileError.corruptedRecord
            }

            let contentLength = Int(contentWords) * 2
            records.append((number: number, offset: offset, contentLength: contentLength))
            offset += 8 + contentLength
        }

        return records
    }

    static func setByte(_ value: UInt8, at offset: Int, in data: inout Data) {
        guard offset >= 0, offset < data.count else { return }

        data.replaceSubrange(offset ..< (offset + 1), with: [value])
    }

    static func setBigEndianInt32(_ value: Int32, at offset: Int, in data: inout Data) {
        guard offset >= 0, offset + 4 <= data.count else { return }

        var value = value.bigEndian
        withUnsafeBytes(of: &value) { data.replaceSubrange(offset ..< (offset + 4), with: $0) }
    }

    static func setLittleEndianInt32(_ value: Int32, at offset: Int, in data: inout Data) {
        guard offset >= 0, offset + 4 <= data.count else { return }

        var value = value.littleEndian
        withUnsafeBytes(of: &value) { data.replaceSubrange(offset ..< (offset + 4), with: $0) }
    }

    static func setLittleEndianUInt16(_ value: UInt16, at offset: Int, in data: inout Data) {
        guard offset >= 0, offset + 2 <= data.count else { return }

        var value = value.littleEndian
        withUnsafeBytes(of: &value) { data.replaceSubrange(offset ..< (offset + 2), with: $0) }
    }

    static func dbfHeader(_ data: Data) throws -> (recordCount: Int, headerLength: Int, recordLength: Int) {
        guard let recordCount = data.readLittleEndianInt32(at: 4),
              let headerLength = data.readLittleEndianUInt16(at: 8),
              let recordLength = data.readLittleEndianUInt16(at: 10)
        else {
            throw ShapefileError.invalidDbfHeader("missing header")
        }

        return (Int(recordCount), Int(headerLength), Int(recordLength))
    }

    static func coordinate(
        x: Double,
        y: Double,
        projection: Projection,
        z: Double? = nil,
        m: Double? = nil
    ) -> Coordinate3D {
        Coordinate3D(x: x, y: y, z: z, m: m, projection: projection)
    }

}
