import Foundation
@testable import GISTools
@testable import GISToolsShapefile
import Testing

struct ShapefileGeometryTests {

    private func coordinate(
        _ x: Double,
        _ y: Double,
        projection: Projection,
        z: Double? = nil,
        m: Double? = nil
    ) -> Coordinate3D {
        Coordinate3D(x: x, y: y, z: z, m: m, projection: projection)
    }

    private func expectedReadProjection(_ projection: Projection) -> Projection {
        projection == .noSRID ? .epsg4326 : projection
    }

    @Test(arguments: [Projection.epsg4326, .epsg3857, .epsg4978, .noSRID])
    func pointRoundTrip(projection: Projection) throws {
        let source = coordinate(16.3, 48.1, projection: projection, z: projection == .epsg4978 ? 4_500_000.0 : nil)
        let loaded = try ShapefileTestSupport.writeAndRead([
            ShapefileTestSupport.feature(Point(source)),
        ])

        #expect(loaded.projection == expectedReadProjection(projection))
        let point = try #require(loaded.features.first?.geometry as? Point)
        #expect(point.coordinate.longitude == source.longitude)
        #expect(point.coordinate.latitude == source.latitude)
        #expect(point.coordinate.projection == expectedReadProjection(projection))

        if projection == .epsg4978 {
            #expect(point.coordinate.altitude == 4_500_000.0)
        }
    }

    @Test(arguments: [Projection.epsg4326, .epsg3857, .epsg4978, .noSRID])
    func pointZAndMRoundTrip(projection: Projection) throws {
        let source = coordinate(1.0, 2.0, projection: projection, z: 123.5, m: 77.25)
        let loaded = try ShapefileTestSupport.writeAndRead([
            ShapefileTestSupport.feature(Point(source)),
        ])

        let point = try #require(loaded.features.first?.geometry as? Point)
        #expect(point.coordinate.altitude == 123.5)
        #expect(point.coordinate.m == 77.25)
    }

    @Test(arguments: [Projection.epsg4326, .epsg3857, .epsg4978, .noSRID])
    func lineStringZMArraysRoundTrip(projection: Projection) throws {
        // Regression test for the Z/M array offsets: the Z array starts after
        // Zmin/Zmax (16 bytes), not after Zmin (8 bytes). The old reader was
        // shifted by one value.
        let coordinates = [
            coordinate(1.0, 2.0, projection: projection, z: 10.0, m: 1.0),
            coordinate(3.0, 4.0, projection: projection, z: 20.0, m: 2.0),
            coordinate(5.0, 6.0, projection: projection, z: 30.0, m: 3.0),
        ]

        let loaded = try ShapefileTestSupport.writeAndRead([
            ShapefileTestSupport.feature(#require(LineString(coordinates))),
        ])

        let line = try #require(loaded.features.first?.geometry as? LineString)
        #expect(line.coordinates.count == 3)
        #expect(line.coordinates.map(\.altitude) == [10.0, 20.0, 30.0])
        #expect(line.coordinates.map(\.m) == [1.0, 2.0, 3.0])
    }

    @Test(arguments: [Projection.epsg4326, .epsg3857, .epsg4978, .noSRID])
    func lineStringMOnlyRoundTrip(projection: Projection) throws {
        // EPSG:4978 is geocentric and therefore requires a Z value.
        let z = projection == .epsg4978 ? 0.0 : nil
        let coordinates = [
            coordinate(1.0, 2.0, projection: projection, z: z, m: 5.0),
            coordinate(3.0, 4.0, projection: projection, z: z, m: 6.0),
        ]

        let loaded = try ShapefileTestSupport.writeAndRead([
            ShapefileTestSupport.feature(#require(LineString(coordinates))),
        ])

        let line = try #require(loaded.features.first?.geometry as? LineString)
        #expect(line.coordinates.map(\.altitude) == (projection == .epsg4978 ? [0.0, 0.0] : [nil, nil]))
        #expect(line.coordinates.map(\.m) == [5.0, 6.0])
    }

    @Test
    func multiPointRoundTrip() throws {
        let coordinates = [
            Coordinate3D(latitude: 1.0, longitude: 2.0),
            Coordinate3D(latitude: 3.0, longitude: 4.0),
        ]

        let loaded = try ShapefileTestSupport.writeAndRead([
            ShapefileTestSupport.feature(#require(MultiPoint(coordinates))),
        ])

        let multiPoint = try #require(loaded.features.first?.geometry as? MultiPoint)
        #expect(multiPoint.coordinates.count == 2)
        #expect(multiPoint.coordinates.map(\.latitude) == [1.0, 3.0])
    }

    @Test
    func multiLineStringRoundTrip() throws {
        let multiLine = try #require(MultiLineString([
            [
                Coordinate3D(latitude: 0.0, longitude: 0.0),
                Coordinate3D(latitude: 1.0, longitude: 1.0),
            ],
            [
                Coordinate3D(latitude: 2.0, longitude: 2.0),
                Coordinate3D(latitude: 3.0, longitude: 3.0),
                Coordinate3D(latitude: 4.0, longitude: 4.0),
            ],
        ]))

        let loaded = try ShapefileTestSupport.writeAndRead([
            ShapefileTestSupport.feature(multiLine),
        ])

        let result = try #require(loaded.features.first?.geometry as? MultiLineString)
        #expect(result.lineStrings.count == 2)
        #expect(result.lineStrings[0].coordinates.count == 2)
        #expect(result.lineStrings[1].coordinates.count == 3)
    }

    @Test
    func polygonWithHoleRoundTrip() throws {
        let outer = [
            Coordinate3D(latitude: 0.0, longitude: 0.0),
            Coordinate3D(latitude: 0.0, longitude: 10.0),
            Coordinate3D(latitude: 10.0, longitude: 10.0),
            Coordinate3D(latitude: 10.0, longitude: 0.0),
            Coordinate3D(latitude: 0.0, longitude: 0.0),
        ]
        let hole = [
            Coordinate3D(latitude: 2.0, longitude: 2.0),
            Coordinate3D(latitude: 8.0, longitude: 2.0),
            Coordinate3D(latitude: 8.0, longitude: 8.0),
            Coordinate3D(latitude: 2.0, longitude: 8.0),
            Coordinate3D(latitude: 2.0, longitude: 2.0),
        ]

        let polygon = try #require(Polygon([outer, hole]))
        #expect(!ShapefileCoder.isClockwise(outer, wrapLongitude: true))
        #expect(ShapefileCoder.isClockwise(hole, wrapLongitude: true))

        let loaded = try ShapefileTestSupport.writeAndRead([
            ShapefileTestSupport.feature(polygon),
        ])

        let result = try #require(loaded.features.first?.geometry as? Polygon)
        #expect(result.rings.count == 2)
        #expect(ShapefileCoder.isClockwise(result.rings[0].coordinates, wrapLongitude: true))
        #expect(!ShapefileCoder.isClockwise(result.rings[1].coordinates, wrapLongitude: true))
    }

    @Test
    func multiPolygonRoundTrip() throws {
        let first = try #require(Polygon([[
            Coordinate3D(latitude: 0.0, longitude: 0.0),
            Coordinate3D(latitude: 0.0, longitude: 5.0),
            Coordinate3D(latitude: 5.0, longitude: 5.0),
            Coordinate3D(latitude: 5.0, longitude: 0.0),
            Coordinate3D(latitude: 0.0, longitude: 0.0),
        ]]))
        let second = try #require(Polygon([[
            Coordinate3D(latitude: 10.0, longitude: 10.0),
            Coordinate3D(latitude: 10.0, longitude: 15.0),
            Coordinate3D(latitude: 15.0, longitude: 15.0),
            Coordinate3D(latitude: 15.0, longitude: 10.0),
            Coordinate3D(latitude: 10.0, longitude: 10.0),
        ]]))

        let loaded = try ShapefileTestSupport.writeAndRead([
            ShapefileTestSupport.feature(#require(MultiPolygon([first, second]))),
        ])

        let result = try #require(loaded.features.first?.geometry as? MultiPolygon)
        #expect(result.polygons.count == 2)
        #expect(result.polygons.allSatisfy { $0.rings.count == 1 })
    }

    @Test
    func polygonCrossingAntimeridianRoundTrip() throws {
        let polygon = try #require(Polygon([[
            Coordinate3D(latitude: -5.0, longitude: 179.0),
            Coordinate3D(latitude: -5.0, longitude: -179.0),
            Coordinate3D(latitude: 5.0, longitude: -179.0),
            Coordinate3D(latitude: 5.0, longitude: 179.0),
            Coordinate3D(latitude: -5.0, longitude: 179.0),
        ]]))

        let loaded = try ShapefileTestSupport.writeAndRead([
            ShapefileTestSupport.feature(polygon),
        ])

        let result = try #require(loaded.features.first?.geometry as? Polygon)
        #expect(result.rings.count == 1)
        #expect(ShapefileCoder.isClockwise(result.rings[0].coordinates, wrapLongitude: true))
    }

    @Test
    func multiPatchRoundTrip() throws {
        let polygon = try #require(Polygon([[
            Coordinate3D(latitude: 0.0, longitude: 0.0, altitude: 10.0),
            Coordinate3D(latitude: 0.0, longitude: 10.0, altitude: 10.0),
            Coordinate3D(latitude: 10.0, longitude: 10.0, altitude: 20.0),
            Coordinate3D(latitude: 0.0, longitude: 0.0, altitude: 10.0),
        ]]))

        let collection = GeometryCollection([polygon])
        let loaded = try ShapefileTestSupport.writeAndRead([
            ShapefileTestSupport.feature(collection),
        ])

        let result = try #require(loaded.features.first?.geometry as? GeometryCollection)
        #expect(result.geometries.count == 1)
        let resultPolygon = try #require(result.geometries.first as? Polygon)
        #expect(resultPolygon.rings.count == 1)
        // Ring orientation normalisation can rotate/reverse the vertex order,
        // so compare the altitude multiset.
        #expect(resultPolygon.allCoordinates.compactMap(\.altitude).sorted() == [10.0, 10.0, 10.0, 20.0])
    }

    @Test
    func multiPatchTriangleStripAndFanDecomposition() throws {
        let polygon = try #require(Polygon([[
            Coordinate3D(latitude: 0.0, longitude: 0.0, altitude: 0.0),
            Coordinate3D(latitude: 0.0, longitude: 1.0, altitude: 0.0),
            Coordinate3D(latitude: 1.0, longitude: 1.0, altitude: 0.0),
            Coordinate3D(latitude: 1.0, longitude: 0.0, altitude: 0.0),
            Coordinate3D(latitude: 0.0, longitude: 0.0, altitude: 0.0),
        ]]))

        let encoded = try ShapefileCoder.encode(FeatureCollection([
            ShapefileTestSupport.feature(GeometryCollection([polygon])),
        ]))

        let records = try ShapefileTestSupport.records(inShp: encoded.shp)
        let contentStart = records[0].offset + 8
        let numParts = try #require(encoded.shp.readLittleEndianInt32(at: contentStart + 36))
        #expect(numParts == 1)

        // Outer ring -> triangle strip (0): 5 points produce 3 triangles.
        var strip = encoded.shp
        ShapefileTestSupport.setLittleEndianInt32(0, at: contentStart + 48, in: &strip)

        let stripCollection = try ShapefileCoder.read(shp: strip, dbf: encoded.dbf)
        let stripGeometry = try #require(stripCollection.features.first?.geometry as? GeometryCollection)
        #expect(stripGeometry.geometries.count == 3)
        #expect(stripGeometry.geometries.allSatisfy { $0 is Polygon })

        // Outer ring -> triangle fan (1): 5 points produce 3 triangles.
        var fan = encoded.shp
        ShapefileTestSupport.setLittleEndianInt32(1, at: contentStart + 48, in: &fan)

        let fanCollection = try ShapefileCoder.read(shp: fan, dbf: encoded.dbf)
        let fanGeometry = try #require(fanCollection.features.first?.geometry as? GeometryCollection)
        #expect(fanGeometry.geometries.count == 3)
    }

    @Test
    func mixedZAndMRoundTripPreservesNil() throws {
        let features = [
            ShapefileTestSupport.feature(Point(Coordinate3D(
                latitude: 1.0,
                longitude: 2.0,
                altitude: 100.0,
                m: 7.0))),
            ShapefileTestSupport.feature(Point(Coordinate3D(
                latitude: 3.0,
                longitude: 4.0))),
        ]

        let loaded = try ShapefileTestSupport.writeAndRead(features)
        #expect(loaded.features.count == 2)

        let first = try #require(loaded.features[0].geometry as? Point)
        let second = try #require(loaded.features[1].geometry as? Point)

        #expect(first.coordinate.altitude == 100.0)
        #expect(first.coordinate.m == 7.0)
        #expect(second.coordinate.altitude == nil)
        #expect(second.coordinate.m == nil)
    }

    @Test
    func emptyGeometriesRoundTripAsNullShapes() throws {
        let loaded = try ShapefileTestSupport.writeAndRead([
            ShapefileTestSupport.feature(LineString()),
        ])

        #expect(loaded.features.count == 1)
        #expect(loaded.features[0].geometry == nil)
    }

    @Test
    func emptyMultiPointRoundTrip() throws {
        let loaded = try ShapefileTestSupport.writeAndRead([
            ShapefileTestSupport.feature(MultiPoint()),
        ])

        let multiPoint = try #require(loaded.features.first?.geometry as? MultiPoint)
        #expect(multiPoint.coordinates.isEmpty)
    }

    @Test
    func multiPatchWithMultiPolygonAndLineString() throws {
        let polygon = try #require(Polygon([[
            Coordinate3D(latitude: 0.0, longitude: 0.0, altitude: 1.0),
            Coordinate3D(latitude: 0.0, longitude: 5.0, altitude: 1.0),
            Coordinate3D(latitude: 5.0, longitude: 5.0, altitude: 1.0),
            Coordinate3D(latitude: 0.0, longitude: 0.0, altitude: 1.0),
        ]]))
        let line = try #require(LineString([
            Coordinate3D(latitude: 10.0, longitude: 10.0, altitude: 2.0),
            Coordinate3D(latitude: 11.0, longitude: 11.0, altitude: 2.0),
            Coordinate3D(latitude: 12.0, longitude: 10.0, altitude: 2.0),
        ]))

        let collection = try GeometryCollection([
            #require(MultiPolygon([polygon])),
            line,
            #require(MultiLineString([line])),
        ])

        let loaded = try ShapefileTestSupport.writeAndRead([
            ShapefileTestSupport.feature(collection),
        ])

        let result = try #require(loaded.features.first?.geometry as? GeometryCollection)
        // One polygon from the MultiPolygon plus one closed ring per line.
        #expect(result.geometries.count == 3)
        #expect(result.geometries.allSatisfy { $0 is Polygon })
    }

    @Test
    func multiPatchRejectsUnsupportedGeometry() throws {
        let collection = GeometryCollection([
            Point(Coordinate3D(latitude: 0.0, longitude: 0.0)),
        ])

        #expect(throws: ShapefileError.invalidGeometry(
            "A MultiPatch can only contain Polygons, MultiPolygons and LineStrings"))
        {
            _ = try ShapefileCoder.encode(FeatureCollection([
                ShapefileTestSupport.feature(collection),
            ]))
        }
    }

    @Test
    func polyLineWithSingleCoordinateThrows() throws {
        let line = LineString(unchecked: [Coordinate3D(latitude: 0.0, longitude: 0.0)])

        #expect(throws: ShapefileError.invalidGeometry(
            "A PolyLine part must contain at least two coordinates"))
        {
            _ = try ShapefileCoder.encode(FeatureCollection([
                ShapefileTestSupport.feature(line),
            ]))
        }
    }

    @Test
    func emptyMultiPatchBecomesNullShape() throws {
        let loaded = try ShapefileTestSupport.writeAndRead([
            ShapefileTestSupport.feature(GeometryCollection([] as [GeoJsonGeometry])),
        ])

        #expect(loaded.features.count == 1)
        #expect(loaded.features[0].geometry == nil)
    }

    @Test
    func pointMOnlyRoundTrip() throws {
        let source = Coordinate3D(latitude: 1.0, longitude: 2.0, m: 42.0)
        let loaded = try ShapefileTestSupport.writeAndRead([
            ShapefileTestSupport.feature(Point(source)),
        ])

        let point = try #require(loaded.features.first?.geometry as? Point)
        #expect(point.coordinate.altitude == nil)
        #expect(point.coordinate.m == 42.0)
    }

    @Test
    func multiPatchWithHole() throws {
        let outer = [
            Coordinate3D(latitude: 0.0, longitude: 0.0, altitude: 1.0),
            Coordinate3D(latitude: 0.0, longitude: 10.0, altitude: 1.0),
            Coordinate3D(latitude: 10.0, longitude: 10.0, altitude: 1.0),
            Coordinate3D(latitude: 0.0, longitude: 0.0, altitude: 1.0),
        ]
        let hole = [
            Coordinate3D(latitude: 2.0, longitude: 2.0, altitude: 1.0),
            Coordinate3D(latitude: 8.0, longitude: 2.0, altitude: 1.0),
            Coordinate3D(latitude: 8.0, longitude: 8.0, altitude: 1.0),
            Coordinate3D(latitude: 2.0, longitude: 2.0, altitude: 1.0),
        ]
        let polygon = try #require(Polygon([outer, hole]))

        let loaded = try ShapefileTestSupport.writeAndRead([
            ShapefileTestSupport.feature(GeometryCollection([polygon])),
        ])

        let result = try #require(loaded.features.first?.geometry as? GeometryCollection)
        let resultPolygon = try #require(result.geometries.first as? Polygon)
        #expect(resultPolygon.rings.count == 2)
    }

    @Test
    func reversedPolygonOrientationIsAccepted() throws {
        let polygon = try #require(Polygon([[
            Coordinate3D(latitude: 0.0, longitude: 0.0),
            Coordinate3D(latitude: 0.0, longitude: 10.0),
            Coordinate3D(latitude: 10.0, longitude: 10.0),
            Coordinate3D(latitude: 10.0, longitude: 0.0),
            Coordinate3D(latitude: 0.0, longitude: 0.0),
        ]]))

        let encoded = try ShapefileCoder.encode(FeatureCollection([
            ShapefileTestSupport.feature(polygon),
        ]))

        var shp = encoded.shp
        let records = try ShapefileTestSupport.records(inShp: shp)
        let contentStart = records[0].offset + 8
        let numParts = try Int(#require(shp.readLittleEndianInt32(at: contentStart + 36)))
        let numPoints = try Int(#require(shp.readLittleEndianInt32(at: contentStart + 40)))
        let pointsOffset = contentStart + 44 + numParts * 4

        var points: [Data] = []
        for index in 0 ..< numPoints {
            let start = pointsOffset + index * 16
            points.append(shp.subdata(in: start ..< (start + 16)))
        }
        for (index, point) in points.reversed().enumerated() {
            let start = pointsOffset + index * 16
            shp.replaceSubrange(start ..< (start + 16), with: point)
        }

        let loaded = try ShapefileCoder.read(shp: shp, dbf: encoded.dbf)
        let result = try #require(loaded.features.first?.geometry as? Polygon)
        #expect(result.rings.count == 1)
    }

    @Test
    func geocentricCoordinatesRequireAltitude() throws {
        let point = Point(Coordinate3D.epsg4978(x: 1.0, y: 2.0))

        #expect(throws: ShapefileError.invalidGeometry(
            "EPSG:4978 coordinates require an altitude"))
        {
            _ = try ShapefileCoder.encode(FeatureCollection([
                ShapefileTestSupport.feature(point),
            ]))
        }
    }

    @Test
    func pointZWithOptionalMOmitted() throws {
        let feature = ShapefileTestSupport.feature(Point(Coordinate3D(
            latitude: 1.0,
            longitude: 2.0,
            altitude: 100.0,
            m: 5.0)))
        let encoded = try ShapefileCoder.encode(FeatureCollection([feature]))

        var shp = encoded.shp
        let records = try ShapefileTestSupport.records(inShp: shp)
        #expect(records.count == 1)

        // Remove the trailing M double from the PointZ record and fix up the
        // record and file lengths.
        let recordOffset = records[0].offset
        shp.removeSubrange((recordOffset + 8 + 28) ..< shp.count)
        ShapefileTestSupport.setBigEndianInt32(14, at: recordOffset + 4, in: &shp)
        ShapefileTestSupport.setBigEndianInt32(Int32(shp.count / 2), at: 24, in: &shp)

        let loaded = try ShapefileCoder.read(shp: shp, dbf: encoded.dbf)
        let point = try #require(loaded.features.first?.geometry as? Point)
        #expect(point.coordinate.altitude == 100.0)
        #expect(point.coordinate.m == nil)
    }

    @Test
    func recordTypeMismatchBecomesNullShape() throws {
        let feature = ShapefileTestSupport.feature(
            Point(Coordinate3D(latitude: 1.0, longitude: 2.0)),
            properties: ["name": "x"])
        let encoded = try ShapefileCoder.encode(FeatureCollection([feature]))

        var shp = encoded.shp
        let records = try ShapefileTestSupport.records(inShp: shp)
        ShapefileTestSupport.setLittleEndianInt32(0, at: records[0].offset + 8, in: &shp)

        let loaded = try ShapefileCoder.read(shp: shp, dbf: encoded.dbf)
        #expect(loaded.features.count == 1)
        #expect(loaded.features[0].geometry == nil)
        #expect(loaded.features[0].properties["name"] as? String == "x")
    }

    @Test(arguments: [Projection.epsg4326, .epsg3857, .epsg4978, .noSRID])
    func multiPointZMArraysRoundTrip(projection: Projection) throws {
        let coordinates = [
            coordinate(1.0, 2.0, projection: projection, z: 10.0, m: 1.0),
            coordinate(3.0, 4.0, projection: projection, z: 20.0, m: 2.0),
            coordinate(5.0, 6.0, projection: projection, z: 30.0, m: 3.0),
        ]

        let loaded = try ShapefileTestSupport.writeAndRead([
            ShapefileTestSupport.feature(#require(MultiPoint(coordinates))),
        ])

        let multiPoint = try #require(loaded.features.first?.geometry as? MultiPoint)
        #expect(multiPoint.coordinates.map(\.altitude) == [10.0, 20.0, 30.0])
        #expect(multiPoint.coordinates.map(\.m) == [1.0, 2.0, 3.0])
    }

    @Test(arguments: [Projection.epsg4326, .epsg3857, .epsg4978, .noSRID])
    func polygonZMArraysRoundTrip(projection: Projection) throws {
        let coordinates = [
            coordinate(0.0, 0.0, projection: projection, z: 10.0, m: 1.0),
            coordinate(10.0, 0.0, projection: projection, z: 20.0, m: 2.0),
            coordinate(10.0, 10.0, projection: projection, z: 30.0, m: 3.0),
            coordinate(0.0, 10.0, projection: projection, z: 40.0, m: 4.0),
            coordinate(0.0, 0.0, projection: projection, z: 10.0, m: 1.0),
        ]

        let polygon = try #require(Polygon([coordinates]))
        let loaded = try ShapefileTestSupport.writeAndRead([
            ShapefileTestSupport.feature(polygon),
        ])

        let result = try #require(loaded.features.first?.geometry as? Polygon)
        #expect(result.rings.count == 1)

        let ring = result.rings[0].coordinates
        #expect(Set(ring.compactMap(\.altitude)) == [10.0, 20.0, 30.0, 40.0])
        #expect(Set(ring.compactMap(\.m)) == [1.0, 2.0, 3.0, 4.0])
    }

    @Test
    func nullShapeBetweenFeaturesKeepsAlignment() throws {
        let features = [
            ShapefileTestSupport.feature(
                Point(Coordinate3D(latitude: 0.0, longitude: 0.0)),
                properties: ["index": 0]),
            Feature(properties: ["index": 1]),
            ShapefileTestSupport.feature(
                Point(Coordinate3D(latitude: 2.0, longitude: 2.0)),
                properties: ["index": 2]),
        ]

        let loaded = try ShapefileTestSupport.writeAndRead(features)
        #expect(loaded.features.count == 3)
        #expect(loaded.features[0].geometry is Point)
        #expect(loaded.features[1].geometry == nil)
        #expect(loaded.features[2].geometry is Point)
        #expect(loaded.features.map { $0.properties["index"] as? Int } == [0, 1, 2])

        let lastPoint = try #require(loaded.features[2].geometry as? Point)
        #expect(lastPoint.coordinate.latitude == 2.0)
    }

}
