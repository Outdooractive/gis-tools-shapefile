import Foundation
@testable import GISTools
@testable import GISToolsShapefile
import Testing

struct ShapefileAPITests {

    private func point() -> Point {
        Point(Coordinate3D(latitude: 48.1, longitude: 16.3))
    }

    @Test
    func featureCollectionConvenienceAPI() throws {
        let url = ShapefileTestSupport.temporaryBaseURL()
        defer { ShapefileTestSupport.cleanup(url) }

        var feature = ShapefileTestSupport.feature(point())
        feature.properties = ["name": "Vienna"]
        feature.id = .int(1)

        try FeatureCollection([feature]).writeShapefile(to: url)

        let loaded = try #require(FeatureCollection(shapefile: url))
        #expect(loaded.features.count == 1)
        #expect(loaded.features[0].id == .int(1))
        #expect(loaded.features[0].properties["name"] as? String == "Vienna")
    }

    @Test
    func calculateBoundingBox() throws {
        let features = [
            ShapefileTestSupport.feature(Point(Coordinate3D(latitude: -10.0, longitude: -20.0))),
            ShapefileTestSupport.feature(Point(Coordinate3D(latitude: 30.0, longitude: 40.0))),
        ]

        let loaded = try ShapefileTestSupport.writeAndRead(
            features,
            calculateBoundingBox: true)

        let boundingBox = try #require(loaded.boundingBox)
        #expect(boundingBox.southWest.latitude == -10.0)
        #expect(boundingBox.southWest.longitude == -20.0)
        #expect(boundingBox.northEast.latitude == 30.0)
        #expect(boundingBox.northEast.longitude == 40.0)
    }

    @Test
    func inMemoryReadAndWrite() throws {
        let feature = ShapefileTestSupport.feature(point(), properties: ["name": "Vienna"])
        let data = try ShapefileCoder.encode(FeatureCollection([feature]))

        #expect(!data.shp.isEmpty)
        #expect(!data.dbf.isEmpty)
        #expect(!data.shx.isEmpty)
        #expect(data.prj != nil)

        let loaded = try ShapefileCoder.read(
            shp: data.shp,
            dbf: data.dbf,
            prj: data.prj)
        #expect(loaded.features.count == 1)
    }

    @Test
    func errorDescriptionsAreLocalized() {
        #expect(ShapefileError.invalidFileCode.errorDescription != nil)
        #expect(ShapefileError.unsupportedShapeType(99).errorDescription != nil)
        #expect(ShapefileError.corruptedRecord.errorDescription != nil)
        #expect(ShapefileError.invalidDbfHeader("x").errorDescription != nil)
        #expect(ShapefileError.unsupportedDbfFieldType("X").errorDescription != nil)
        #expect(ShapefileError.ioError("x").errorDescription != nil)
        #expect(ShapefileError.invalidFileLength(1).errorDescription != nil)
        #expect(ShapefileError.unsupportedVersion(1).errorDescription != nil)
        #expect(ShapefileError.mixedGeometryTypes.errorDescription != nil)
        #expect(ShapefileError.mixedProjections.errorDescription != nil)
        #expect(ShapefileError.invalidGeometry("x").errorDescription != nil)
        #expect(ShapefileError.idColumnConflict("id").errorDescription != nil)
        #expect(ShapefileError.tooManyFields(1).errorDescription != nil)
        #expect(ShapefileError.recordTooLarge(1).errorDescription != nil)
        #expect(ShapefileError.invalidFieldName("x").errorDescription != nil)
        #expect(ShapefileError.recordCountMismatch(shp: 1, dbf: 2).errorDescription != nil)
        #expect(ShapefileError.fileTooLarge.errorDescription != nil)
        #expect(ShapefileError.unsupportedProjection("x").errorDescription != nil)
        #expect(ShapefileError.unsupportedEncoding("x").errorDescription != nil)
    }

    @Test
    func legacyErrorTypealias() {
        let error: ShapefileCoder.ShapefileCoderError = .corruptedRecord
        #expect(error == ShapefileError.corruptedRecord)
    }

    @Test
    func shapefileDataIsSendable() {
        let data = ShapefileData(
            shp: Data(),
            dbf: Data(),
            shx: Data(),
            prj: nil)
        let _: any Sendable = data
        #expect(data.prj == nil)
    }

    @Test
    func dataSlicesWithNonZeroStartIndexAreSupported() throws {
        let feature = ShapefileTestSupport.feature(point(), properties: ["name": "Vienna"])
        let data = try ShapefileCoder.encode(FeatureCollection([feature]))

        var paddedShp = Data([0xAA])
        paddedShp.append(data.shp)
        var paddedDbf = Data([0xBB])
        paddedDbf.append(data.dbf)

        let shpSlice = paddedShp[1...]
        let dbfSlice = paddedDbf[1...]
        #expect(shpSlice.startIndex == 1)
        #expect(dbfSlice.startIndex == 1)

        let loaded = try ShapefileCoder.read(
            shp: shpSlice,
            dbf: dbfSlice,
            prj: data.prj)
        #expect(loaded.features.count == 1)
        #expect(loaded.features[0].properties["name"] as? String == "Vienna")
    }

}
