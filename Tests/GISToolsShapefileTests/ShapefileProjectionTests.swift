import Foundation
@testable import GISTools
@testable import GISToolsShapefile
import Testing

struct ShapefileProjectionTests {

    private func point(_ projection: Projection) -> Point {
        switch projection {
        case .epsg3857:
            Point(Coordinate3D.epsg3857(x: 1_000_000.0, y: 2_000_000.0))
        case .epsg4978:
            Point(Coordinate3D.epsg4978(x: 4_000_000.0, y: 1_000_000.0, z: 4_500_000.0))
        case .noSRID:
            Point(Coordinate3D(x: 10.0, y: 20.0, projection: .noSRID))
        default:
            Point(Coordinate3D(latitude: 48.1, longitude: 16.3))
        }
    }

    @Test
    func webMercatorRoundTrip() throws {
        let loaded = try ShapefileTestSupport.writeAndRead([
            ShapefileTestSupport.feature(point(.epsg3857)),
        ])

        #expect(loaded.projection == .epsg3857)
        let coordinate = try #require((loaded.features.first?.geometry as? Point)?.coordinate)
        #expect(coordinate.longitude == 1_000_000.0)
        #expect(coordinate.latitude == 2_000_000.0)
        #expect(coordinate.projection == .epsg3857)
    }

    @Test
    func geocentricRoundTrip() throws {
        let loaded = try ShapefileTestSupport.writeAndRead([
            ShapefileTestSupport.feature(point(.epsg4978)),
        ])

        #expect(loaded.projection == .epsg4978)
        let coordinate = try #require((loaded.features.first?.geometry as? Point)?.coordinate)
        #expect(coordinate.longitude == 4_000_000.0)
        #expect(coordinate.latitude == 1_000_000.0)
        #expect(coordinate.altitude == 4_500_000.0)
        #expect(coordinate.projection == .epsg4978)
    }

    @Test
    func noSRIDWritesNoPrjFile() throws {
        let url = ShapefileTestSupport.temporaryBaseURL()
        defer { ShapefileTestSupport.cleanup(url) }

        try ShapefileCoder.write(
            FeatureCollection([ShapefileTestSupport.feature(point(.noSRID))]),
            to: url)

        let prjURL = url.appendingPathExtension("prj")
        #expect(!FileManager.default.fileExists(atPath: prjURL.path))

        let loaded = try ShapefileCoder.read(from: url)
        // Without a .prj file, EPSG:4326 is assumed. The numeric values are
        // preserved because noSRID coordinates are copied verbatim.
        #expect(loaded.projection == .epsg4326)
        let coordinate = try #require((loaded.features.first?.geometry as? Point)?.coordinate)
        #expect(coordinate.longitude == 10.0)
        #expect(coordinate.latitude == 20.0)
    }

    @Test
    func stalePrjFileIsRemoved() throws {
        let url = ShapefileTestSupport.temporaryBaseURL()
        defer { ShapefileTestSupport.cleanup(url) }

        try ShapefileCoder.write(
            FeatureCollection([ShapefileTestSupport.feature(point(.epsg3857))]),
            to: url)
        #expect(FileManager.default.fileExists(atPath: url.appendingPathExtension("prj").path))

        try ShapefileCoder.write(
            FeatureCollection([ShapefileTestSupport.feature(point(.noSRID))]),
            to: url)
        #expect(!FileManager.default.fileExists(atPath: url.appendingPathExtension("prj").path))
    }

    @Test
    func invalidPrjThrows() throws {
        let encoded = try ShapefileCoder.encode(FeatureCollection([
            ShapefileTestSupport.feature(point(.epsg4326)),
        ]))

        #expect(throws: ShapefileError.unsupportedProjection("not a projection")) {
            _ = try ShapefileCoder.read(shp: encoded.shp, dbf: encoded.dbf, prj: "not a projection")
        }

        #expect(throws: ShapefileError.unsupportedProjection("The .prj file is empty")) {
            _ = try ShapefileCoder.read(shp: encoded.shp, dbf: encoded.dbf, prj: "   ")
        }
    }

    @Test
    func prjWithByteOrderMarkIsAccepted() throws {
        let encoded = try ShapefileCoder.encode(FeatureCollection([
            ShapefileTestSupport.feature(point(.epsg4326)),
        ]))
        let prj = "\u{FEFF}" + (encoded.prj ?? "")

        let loaded = try ShapefileCoder.read(shp: encoded.shp, dbf: encoded.dbf, prj: prj)
        #expect(loaded.projection == .epsg4326)
    }

    @Test
    func unsupportedOutputProjectionThrows() throws {
        let feature = ShapefileTestSupport.feature(Point(Coordinate3D.epsg3857(
            x: 500_000.0,
            y: 5_000_000.0)))
        let projected = FeatureCollection([feature]).projected(to: .epsg32633)

        #expect(throws: ShapefileError.unsupportedProjection("EPSG:32633")) {
            _ = try ShapefileCoder.encode(projected)
        }
    }

    @Test
    func componentURLsAreAccepted() throws {
        let url = ShapefileTestSupport.temporaryBaseURL()
        defer { ShapefileTestSupport.cleanup(url) }

        try ShapefileCoder.write(
            FeatureCollection([ShapefileTestSupport.feature(point(.epsg4326))]),
            to: url.appendingPathExtension("dbf"))

        #expect(FileManager.default.fileExists(atPath: url.appendingPathExtension("shp").path))
        #expect(FileManager.default.fileExists(atPath: url.appendingPathExtension("dbf").path))
        #expect(!FileManager.default.fileExists(atPath: url.appendingPathExtension("dbf").appendingPathExtension("shp").path))

        let loaded = try ShapefileCoder.read(from: url.appendingPathExtension("SHP"))
        #expect(loaded.features.count == 1)
    }

    @Test
    func missingDbfThrows() throws {
        let url = ShapefileTestSupport.temporaryBaseURL()
        defer { ShapefileTestSupport.cleanup(url) }

        try ShapefileCoder.write(
            FeatureCollection([ShapefileTestSupport.feature(point(.epsg4326))]),
            to: url)

        try FileManager.default.removeItem(at: url.appendingPathExtension("dbf"))

        #expect(throws: ShapefileError.self) {
            _ = try ShapefileCoder.read(from: url)
        }
    }

    @Test
    func latin1PrjIsDecodedBeforeProjectionResolution() throws {
        let encoded = try ShapefileCoder.encode(FeatureCollection([
            ShapefileTestSupport.feature(point(.epsg4326)),
        ]))
        let url = ShapefileTestSupport.temporaryBaseURL()
        defer { ShapefileTestSupport.cleanup(url) }

        try encoded.shp.write(to: url.appendingPathExtension("shp"))
        try encoded.dbf.write(to: url.appendingPathExtension("dbf"))
        try Data([0xFF]).write(to: url.appendingPathExtension("prj"))

        #expect(throws: ShapefileError.self) {
            _ = try ShapefileCoder.read(from: url)
        }
    }

    @Test
    func writeFailureIsWrapped() throws {
        let feature = ShapefileTestSupport.feature(point(.epsg4326))
        let url = URL(fileURLWithPath: "/nonexistent-shapefile-directory-\(UUID().uuidString)/test")

        #expect(throws: ShapefileError.self) {
            try ShapefileCoder.write(FeatureCollection([feature]), to: url)
        }
    }

    @Test
    func uppercaseComponentExtensionsAreReadable() throws {
        let url = ShapefileTestSupport.temporaryBaseURL()
        defer { ShapefileTestSupport.cleanup(url) }

        try ShapefileCoder.write(
            FeatureCollection([ShapefileTestSupport.feature(point(.epsg3857))]),
            to: url)

        for pathExtension in ["shp", "dbf", "shx", "prj", "cpg"] {
            let lower = url.appendingPathExtension(pathExtension)
            guard FileManager.default.fileExists(atPath: lower.path) else { continue }

            let upper = url.appendingPathExtension(pathExtension.uppercased())
            try FileManager.default.moveItem(at: lower, to: upper)
        }

        let fromBase = try ShapefileCoder.read(from: url)
        #expect(fromBase.projection == .epsg3857)
        #expect(fromBase.features.count == 1)

        let fromUppercaseShp = try ShapefileCoder.read(
            from: url.appendingPathExtension("SHP"))
        #expect(fromUppercaseShp.projection == .epsg3857)
        #expect(fromUppercaseShp.features.count == 1)
    }

}
