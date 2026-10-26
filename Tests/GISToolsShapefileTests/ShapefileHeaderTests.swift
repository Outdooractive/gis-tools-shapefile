import Foundation
@testable import GISTools
@testable import GISToolsShapefile
import Testing

struct ShapefileHeaderTests {

    @Test
    func headerBoundingBoxAndLength() throws {
        let features = [
            ShapefileTestSupport.feature(Point(Coordinate3D(latitude: 20.0, longitude: 10.0))),
            ShapefileTestSupport.feature(Point(Coordinate3D(latitude: -3.0, longitude: -5.0))),
        ]

        let data = try ShapefileCoder.encode(FeatureCollection(features))

        #expect(data.shp.readBigEndianInt32(at: 0) == 9994)
        #expect(data.shp.readLittleEndianInt32(at: 28) == 1000)
        #expect(data.shp.readLittleEndianInt32(at: 32) == 1)

        let fileLength = try #require(data.shp.readBigEndianInt32(at: 24))
        #expect(Int(fileLength) * 2 == data.shp.count)

        #expect(data.shp.readLittleEndianDouble(at: 36) == -5.0)
        #expect(data.shp.readLittleEndianDouble(at: 44) == -3.0)
        #expect(data.shp.readLittleEndianDouble(at: 52) == 10.0)
        #expect(data.shp.readLittleEndianDouble(at: 60) == 20.0)

        // Unused Z and M ranges.
        #expect(data.shp.readLittleEndianDouble(at: 68) == 0.0)
        #expect(data.shp.readLittleEndianDouble(at: 76) == 0.0)
        #expect(data.shp.readLittleEndianDouble(at: 84) == 0.0)
        #expect(data.shp.readLittleEndianDouble(at: 92) == 0.0)
    }

    @Test
    func shxOffsetsPointAtRecords() throws {
        let features = (0 ..< 5).map { index in
            ShapefileTestSupport.feature(Point(Coordinate3D(
                latitude: Double(index),
                longitude: Double(index * 2))))
        }

        let data = try ShapefileCoder.encode(FeatureCollection(features))
        let shpRecords = try ShapefileTestSupport.records(inShp: data.shp)

        #expect(shpRecords.count == 5)
        #expect(shpRecords.map(\.number) == [1, 2, 3, 4, 5])

        let shxLength = try #require(data.shx.readBigEndianInt32(at: 24))
        #expect(Int(shxLength) * 2 == data.shx.count)
        #expect(data.shx.count == 100 + features.count * 8)

        for index in 0 ..< features.count {
            let entryOffset = 100 + index * 8
            let recordOffsetWords = try #require(data.shx.readBigEndianInt32(at: entryOffset))
            let contentLengthWords = try #require(data.shx.readBigEndianInt32(at: entryOffset + 4))

            let recordOffset = Int(recordOffsetWords) * 2
            #expect(recordOffset == shpRecords[index].offset)
            #expect(Int(contentLengthWords) * 2 == shpRecords[index].contentLength)
        }
    }

    @Test
    func zAndMRanges() throws {
        let coordinates = [
            Coordinate3D(latitude: 1.0, longitude: 2.0, altitude: 100.0, m: 10.0),
            Coordinate3D(latitude: 3.0, longitude: 4.0, altitude: 300.0, m: 30.0),
        ]
        let data = try ShapefileCoder.encode(
            FeatureCollection([ShapefileTestSupport.feature(#require(LineString(coordinates)))]))
        let records = try ShapefileTestSupport.records(inShp: data.shp)
        let contentStart = records[0].offset + 8

        // PolyLineZ layout: type (4) + bbox (32) + numParts (4) +
        // numPoints (4) + parts (4) + points (32) = 80 bytes before Zmin.
        let zOffset = contentStart + 80
        #expect(data.shp.readLittleEndianDouble(at: zOffset) == 100.0)
        #expect(data.shp.readLittleEndianDouble(at: zOffset + 8) == 300.0)
        #expect(data.shp.readLittleEndianDouble(at: zOffset + 16) == 100.0)
        #expect(data.shp.readLittleEndianDouble(at: zOffset + 24) == 300.0)

        // Header Z range.
        #expect(data.shp.readLittleEndianDouble(at: 68) == 100.0)
        #expect(data.shp.readLittleEndianDouble(at: 76) == 300.0)
        #expect(data.shp.readLittleEndianDouble(at: 84) == 10.0)
        #expect(data.shp.readLittleEndianDouble(at: 92) == 30.0)
    }

    @Test
    func emptyCollectionWritesValidEmptyFiles() throws {
        let data = try ShapefileCoder.encode(FeatureCollection())

        #expect(data.shp.count == 100)
        #expect(data.shx.count == 100)
        #expect(data.prj == nil)

        #expect(data.shp.readLittleEndianInt32(at: 32) == 0)
        #expect(data.shx.readLittleEndianInt32(at: 32) == 0)

        let header = try ShapefileTestSupport.dbfHeader(data.dbf)
        #expect(header.recordCount == 0)
        #expect(header.headerLength == 33)
        #expect(header.recordLength == 1)
        #expect(data.dbf.readByte(at: 32) == 0x0D)
        #expect(data.dbf.readByte(at: 33) == 0x1A)

        let collection = try ShapefileCoder.read(
            shp: data.shp,
            dbf: data.dbf,
            prj: data.prj)
        #expect(collection.features.isEmpty)
    }

    @Test
    func nullShapeFeatureKeepsProperties() throws {
        var feature = Feature(id: .int(7), properties: ["name": "unlocated"])
        feature.properties["name"] = "unlocated"

        let data = try ShapefileCoder.encode(FeatureCollection([feature]))
        #expect(data.shp.readLittleEndianInt32(at: 32) == 0)

        let records = try ShapefileTestSupport.records(inShp: data.shp)
        #expect(records.count == 1)
        #expect(records[0].contentLength == 4)

        let collection = try ShapefileCoder.read(
            shp: data.shp,
            dbf: data.dbf,
            prj: data.prj)
        #expect(collection.features.count == 1)
        #expect(collection.features[0].geometry == nil)
        #expect(collection.features[0].id == .int(7))
        #expect(collection.features[0].properties["name"] as? String == "unlocated")
    }

    @Test
    func mixedGeometryTypesThrow() throws {
        let features = try [
            ShapefileTestSupport.feature(Point(Coordinate3D(latitude: 0.0, longitude: 0.0))),
            ShapefileTestSupport.feature(#require(LineString([
                Coordinate3D(latitude: 0.0, longitude: 0.0),
                Coordinate3D(latitude: 1.0, longitude: 1.0),
            ]))),
        ]

        #expect(throws: ShapefileError.mixedGeometryTypes) {
            _ = try ShapefileCoder.encode(FeatureCollection(features))
        }
    }

    @Test
    func mixedProjectionsThrow() throws {
        let features = [
            ShapefileTestSupport.feature(Point(Coordinate3D(latitude: 0.0, longitude: 0.0))),
            ShapefileTestSupport.feature(Point(Coordinate3D.epsg3857(x: 1.0, y: 2.0))),
        ]

        #expect(throws: ShapefileError.mixedProjections) {
            _ = try ShapefileCoder.encode(FeatureCollection(features))
        }
    }

    @Test
    func invalidFileCodeThrows() throws {
        let encoded = try ShapefileCoder.encode(FeatureCollection(
            [ShapefileTestSupport.feature(Point(Coordinate3D(latitude: 0.0, longitude: 0.0)))]))
        var shp = encoded.shp
        ShapefileTestSupport.setBigEndianInt32(1, at: 0, in: &shp)

        #expect(throws: ShapefileError.invalidFileCode) {
            _ = try ShapefileCoder.read(shp: shp, dbf: encoded.dbf)
        }
    }

    @Test
    func unsupportedVersionThrows() throws {
        let encoded = try ShapefileCoder.encode(FeatureCollection(
            [ShapefileTestSupport.feature(Point(Coordinate3D(latitude: 0.0, longitude: 0.0)))]))
        var shp = encoded.shp
        ShapefileTestSupport.setLittleEndianInt32(999, at: 28, in: &shp)

        #expect(throws: ShapefileError.unsupportedVersion(999)) {
            _ = try ShapefileCoder.read(shp: shp, dbf: encoded.dbf)
        }
    }

    @Test
    func unsupportedHeaderShapeTypeThrows() throws {
        let encoded = try ShapefileCoder.encode(FeatureCollection(
            [ShapefileTestSupport.feature(Point(Coordinate3D(latitude: 0.0, longitude: 0.0)))]))
        var shp = encoded.shp
        ShapefileTestSupport.setLittleEndianInt32(2, at: 32, in: &shp)

        #expect(throws: ShapefileError.unsupportedShapeType(2)) {
            _ = try ShapefileCoder.read(shp: shp, dbf: encoded.dbf)
        }
    }

    @Test
    func truncatedShpThrows() throws {
        let encoded = try ShapefileCoder.encode(FeatureCollection(
            [ShapefileTestSupport.feature(Point(Coordinate3D(latitude: 0.0, longitude: 0.0)))]))
        var shp = encoded.shp
        let originalLength = shp.count
        shp.removeLast(10)

        #expect(throws: ShapefileError.invalidFileLength(originalLength)) {
            _ = try ShapefileCoder.read(shp: shp, dbf: encoded.dbf)
        }
    }

    @Test
    func negativeContentLengthThrowsInsteadOfLooping() throws {
        let encoded = try ShapefileCoder.encode(FeatureCollection(
            [ShapefileTestSupport.feature(Point(Coordinate3D(latitude: 0.0, longitude: 0.0)))]))
        var shp = encoded.shp
        ShapefileTestSupport.setBigEndianInt32(-1, at: 104, in: &shp)

        #expect(throws: ShapefileError.corruptedRecord) {
            _ = try ShapefileCoder.read(shp: shp, dbf: encoded.dbf)
        }
    }

    @Test
    func oversizedRecordLengthThrows() throws {
        let encoded = try ShapefileCoder.encode(FeatureCollection(
            [ShapefileTestSupport.feature(Point(Coordinate3D(latitude: 0.0, longitude: 0.0)))]))
        var shp = encoded.shp
        ShapefileTestSupport.setBigEndianInt32(1000, at: 104, in: &shp)

        #expect(throws: ShapefileError.corruptedRecord) {
            _ = try ShapefileCoder.read(shp: shp, dbf: encoded.dbf)
        }
    }

    @Test
    func hugePointCountThrows() throws {
        let line = try #require(LineString([
            Coordinate3D(latitude: 0.0, longitude: 0.0),
            Coordinate3D(latitude: 1.0, longitude: 1.0),
        ]))
        let encoded = try ShapefileCoder.encode(FeatureCollection(
            [ShapefileTestSupport.feature(line)]))

        var shp = encoded.shp
        let records = try ShapefileTestSupport.records(inShp: shp)
        let contentStart = records[0].offset + 8
        ShapefileTestSupport.setLittleEndianInt32(1_000_000, at: contentStart + 40, in: &shp)

        #expect(throws: ShapefileError.corruptedRecord) {
            _ = try ShapefileCoder.read(shp: shp, dbf: encoded.dbf)
        }
    }

    @Test
    func recordCountMismatchThrows() throws {
        let encoded = try ShapefileCoder.encode(FeatureCollection([
            ShapefileTestSupport.feature(Point(Coordinate3D(latitude: 0.0, longitude: 0.0))),
            ShapefileTestSupport.feature(Point(Coordinate3D(latitude: 1.0, longitude: 1.0))),
        ]))
        var dbf = encoded.dbf
        ShapefileTestSupport.setLittleEndianInt32(1, at: 4, in: &dbf)

        #expect(throws: ShapefileError.recordCountMismatch(shp: 2, dbf: 1)) {
            _ = try ShapefileCoder.read(shp: encoded.shp, dbf: dbf)
        }
    }

}
