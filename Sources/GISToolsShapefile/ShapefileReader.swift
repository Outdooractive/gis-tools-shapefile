import Foundation
import GISTools

// MARK: - .shp reading

extension ShapefileCoder {

    /// The layout shared by PolyLine, Polygon and MultiPatch records.
    private struct PartLayout {

        let numParts: Int
        let numPoints: Int
        let partStarts: [Int]
        let pointsOffset: Int
        let arrayBase: Int

    }

    /// Offsets for optional Z and M blocks.
    private struct ZMOffsets {

        let zOffset: Int?
        let mOffset: Int?

    }

    /// Reads all geometry records from a `.shp` file.
    ///
    /// - Parameters:
    ///   - data: The contents of the `.shp` file.
    ///   - projection: The CRS declared by the `.prj` file.
    /// - Returns: One entry per record; `nil` represents a null shape.
    static func readShp(
        _ data: Data,
        projection: Projection
    ) throws -> [GeoJsonGeometry?] {
        guard data.count >= 100 else { throw ShapefileError.invalidFileLength(data.count) }
        guard data.readBigEndianInt32(at: 0) == 9994 else {
            throw ShapefileError.invalidFileCode
        }

        // The header is mixed endian: file code and file length are big-endian,
        // the version, shape type and all doubles are little-endian.
        guard let version = data.readLittleEndianInt32(at: 28) else {
            throw ShapefileError.invalidFileLength(data.count)
        }
        guard version == 1000 else {
            throw ShapefileError.unsupportedVersion(Int(version))
        }
        guard let lengthWords = data.readBigEndianInt32(at: 24), lengthWords >= 50 else {
            throw ShapefileError.invalidFileLength(Int(data.readBigEndianInt32(at: 24) ?? 0))
        }

        let (fileLength, lengthOverflow) = Int(lengthWords).multipliedReportingOverflow(by: 2)
        guard !lengthOverflow, fileLength <= data.count else {
            throw ShapefileError.invalidFileLength(lengthOverflow ? Int.max : fileLength)
        }
        guard let rawShapeType = data.readLittleEndianInt32(at: 32),
              let shapeType = ShapeType(rawValue: Int(rawShapeType))
        else {
            throw ShapefileError.unsupportedShapeType(Int(data.readLittleEndianInt32(at: 32) ?? -1))
        }

        var geometries: [GeoJsonGeometry?] = []
        var offset = 100

        while offset < fileLength {
            guard offset + 8 <= fileLength,
                  let contentWords = data.readBigEndianInt32(at: offset + 4),
                  contentWords >= 0
            else {
                throw ShapefileError.corruptedRecord
            }

            let (contentLength, contentOverflow) = Int(contentWords).multipliedReportingOverflow(by: 2)
            guard !contentOverflow, contentLength >= 4 else {
                throw ShapefileError.corruptedRecord
            }

            let contentStart = offset + 8
            let (contentEnd, endOverflow) = contentStart.addingReportingOverflow(contentLength)
            guard !endOverflow, contentEnd <= fileLength else {
                throw ShapefileError.corruptedRecord
            }
            guard let rawRecordType = data.readLittleEndianInt32(at: contentStart) else {
                throw ShapefileError.corruptedRecord
            }

            let recordType = Int(rawRecordType)

            if recordType == 0 {
                // Null shape: keep the record so .dbf rows stay aligned.
                geometries.append(nil)
            }
            else if recordType != shapeType.rawValue {
                // A record whose type differs from the file header is invalid.
                // Treat it as a null shape instead of silently dropping it and
                // shifting every following .dbf row.
                geometries.append(nil)
            }
            else {
                try geometries.append(
                    readShape(
                        data: data,
                        start: contentStart,
                        end: contentEnd,
                        type: shapeType,
                        projection: projection))
            }

            offset = contentEnd
        }

        return geometries
    }

    // MARK: - Shape dispatch

    private static func readShape(
        data: Data,
        start: Int,
        end: Int,
        type: ShapeType,
        projection: Projection
    ) throws -> GeoJsonGeometry {
        switch type {
        case .nullShape:
            throw ShapefileError.corruptedRecord
        case .point, .pointM, .pointZ:
            return try readPoint(data: data, start: start, end: end, type: type, projection: projection)
        case .polyLine, .polyLineM, .polyLineZ:
            return try readPolyLine(data: data, start: start, end: end, type: type, projection: projection)
        case .polygon, .polygonM, .polygonZ:
            return try readPolygon(data: data, start: start, end: end, type: type, projection: projection)
        case .multiPoint, .multiPointM, .multiPointZ:
            return try readMultiPoint(data: data, start: start, end: end, type: type, projection: projection)
        case .multiPatch:
            return try readMultiPatch(data: data, start: start, end: end, projection: projection)
        }
    }

    // MARK: - Points

    private static func readPoint(
        data: Data,
        start: Int,
        end: Int,
        type: ShapeType,
        projection: Projection
    ) throws -> Point {
        try requireBytes(start: start, length: 20, within: end)
        let contentLength = end - start

        let x = try readDouble(data, at: start + 4, end: end)
        let y = try readDouble(data, at: start + 12, end: end)

        var altitude: Double?
        var m: Double?

        if type.hasZ {
            try requireBytes(start: start, length: 28, within: end)
            let z = try readDouble(data, at: start + 20, end: end)
            altitude = ShapefileCoder.isValidZ(z) ? z : nil

            // Some writers omit the optional M value for PointZ records.
            if contentLength >= 36 {
                let rawM = try readDouble(data, at: start + 28, end: end)
                m = ShapefileCoder.isNoData(rawM) ? nil : rawM
            }
        }
        else if type.hasM {
            try requireBytes(start: start, length: 28, within: end)
            let rawM = try readDouble(data, at: start + 20, end: end)
            m = ShapefileCoder.isNoData(rawM) ? nil : rawM
        }

        return Point(Coordinate3D(
            x: x,
            y: y,
            z: altitude,
            m: m,
            projection: projection))
    }

    // MARK: - MultiPoint

    private static func readMultiPoint(
        data: Data,
        start: Int,
        end: Int,
        type: ShapeType,
        projection: Projection
    ) throws -> MultiPoint {
        try requireBytes(start: start, length: 40, within: end)

        let numPoints = try Int(readInt32(data, at: start + 36, end: end))
        guard numPoints >= 0 else { throw ShapefileError.corruptedRecord }
        guard numPoints <= (end - start - 40) / 16 else {
            throw ShapefileError.corruptedRecord
        }

        let pointsOffset = start + 40
        let arrayBase = pointsOffset + numPoints * 16
        let offsets = try readZMOffsets(
            data: data,
            type: type,
            arrayBase: arrayBase,
            numPoints: numPoints,
            end: end)

        let coordinates = try readCoordinates(
            data: data,
            numPoints: numPoints,
            pointsOffset: pointsOffset,
            zOffset: offsets.zOffset,
            mOffset: offsets.mOffset,
            end: end,
            projection: projection)

        return MultiPoint(unchecked: coordinates)
    }

    // MARK: - PolyLine

    private static func readPolyLine(
        data: Data,
        start: Int,
        end: Int,
        type: ShapeType,
        projection: Projection
    ) throws -> GeoJsonGeometry {
        let layout = try readPartLayout(data: data, start: start, end: end)
        let offsets = try readZMOffsets(
            data: data,
            type: type,
            arrayBase: layout.arrayBase,
            numPoints: layout.numPoints,
            end: end)

        let coordinates = try readCoordinates(
            data: data,
            numPoints: layout.numPoints,
            pointsOffset: layout.pointsOffset,
            zOffset: offsets.zOffset,
            mOffset: offsets.mOffset,
            end: end,
            projection: projection)

        var lineStrings: [LineString] = []
        lineStrings.reserveCapacity(layout.numParts)

        for index in 0 ..< layout.numParts {
            let partStart = layout.partStarts[index]
            let partEnd = index + 1 < layout.numParts
                ? layout.partStarts[index + 1]
                : layout.numPoints

            guard partEnd >= partStart else { throw ShapefileError.corruptedRecord }

            if let lineString = LineString(Array(coordinates[partStart ..< partEnd])) {
                lineStrings.append(lineString)
            }
        }

        if lineStrings.count == 1, let lineString = lineStrings.first {
            return lineString
        }
        else {
            return MultiLineString(unchecked: lineStrings)
        }
    }

    // MARK: - Polygon

    private static func readPolygon(
        data: Data,
        start: Int,
        end: Int,
        type: ShapeType,
        projection: Projection
    ) throws -> GeoJsonGeometry {
        let layout = try readPartLayout(data: data, start: start, end: end)
        let offsets = try readZMOffsets(
            data: data,
            type: type,
            arrayBase: layout.arrayBase,
            numPoints: layout.numPoints,
            end: end)

        let coordinates = try readCoordinates(
            data: data,
            numPoints: layout.numPoints,
            pointsOffset: layout.pointsOffset,
            zOffset: offsets.zOffset,
            mOffset: offsets.mOffset,
            end: end,
            projection: projection)

        var rings: [(ring: Ring, clockwise: Bool)] = []
        rings.reserveCapacity(layout.numParts)

        for index in 0 ..< layout.numParts {
            let partStart = layout.partStarts[index]
            let partEnd = index + 1 < layout.numParts
                ? layout.partStarts[index + 1]
                : layout.numPoints

            guard partEnd >= partStart else { throw ShapefileError.corruptedRecord }

            if let ring = Ring(Array(coordinates[partStart ..< partEnd])) {
                rings.append((
                    ring: ring,
                    clockwise: isClockwise(
                        ring.coordinates,
                        wrapLongitude: projection.isGeographic)
                ))
            }
        }

        guard rings.isNotEmpty else {
            return MultiPolygon()
        }

        // Shapefile convention: outer rings are clockwise and holes are
        // counter-clockwise. Some third-party files use the opposite order, so
        // fall back to treating the first ring as the outer ring when no
        // clockwise ring exists.
        guard rings.contains(where: { $0.clockwise }) else {
            let outer = rings[0].ring
            let holes = rings.dropFirst().map { $0.ring }
            return Polygon(unchecked: [outer] + holes)
        }

        var polygons: [Polygon] = []
        var currentOuter: Ring?
        var currentHoles: [Ring] = []

        for item in rings {
            if item.clockwise {
                if let outer = currentOuter {
                    polygons.append(Polygon(unchecked: [outer] + currentHoles))
                }
                currentOuter = item.ring
                currentHoles = []
            }
            else if currentOuter != nil {
                currentHoles.append(item.ring)
            }
        }

        if let outer = currentOuter {
            polygons.append(Polygon(unchecked: [outer] + currentHoles))
        }

        if polygons.count == 1, let polygon = polygons.first {
            return polygon
        }
        else {
            return MultiPolygon(unchecked: polygons)
        }
    }

    // MARK: - MultiPatch

    private static func readMultiPatch(
        data: Data,
        start: Int,
        end: Int,
        projection: Projection
    ) throws -> GeometryCollection {
        try requireBytes(start: start, length: 44, within: end)

        let numParts = try Int(readInt32(data, at: start + 36, end: end))
        let numPoints = try Int(readInt32(data, at: start + 40, end: end))
        guard numParts >= 0, numPoints >= 0 else { throw ShapefileError.corruptedRecord }

        let partsOffset = start + 44
        guard numParts <= (end - partsOffset) / 4 else { throw ShapefileError.corruptedRecord }

        let partTypesOffset = partsOffset + numParts * 4
        guard partTypesOffset <= end, numParts <= (end - partTypesOffset) / 4 else {
            throw ShapefileError.corruptedRecord
        }

        let pointsOffset = partTypesOffset + numParts * 4
        guard pointsOffset <= end, numPoints <= (end - pointsOffset) / 16 else {
            throw ShapefileError.corruptedRecord
        }

        var partStarts: [Int] = []
        partStarts.reserveCapacity(numParts)
        for index in 0 ..< numParts {
            let value = try Int(readInt32(data, at: partsOffset + index * 4, end: end))
            guard value >= 0, value <= numPoints else { throw ShapefileError.corruptedRecord }

            if let previous = partStarts.last, value < previous {
                throw ShapefileError.corruptedRecord
            }
            partStarts.append(value)
        }
        if numParts > 0, partStarts.first != 0 {
            throw ShapefileError.corruptedRecord
        }

        var partTypes: [MultiPatchPartType] = []
        partTypes.reserveCapacity(numParts)
        for index in 0 ..< numParts {
            let rawValue = try Int(readInt32(data, at: partTypesOffset + index * 4, end: end))
            guard let partType = MultiPatchPartType(rawValue: rawValue) else {
                throw ShapefileError.corruptedRecord
            }

            partTypes.append(partType)
        }

        let arrayBase = pointsOffset + numPoints * 16
        let offsets = try readZMOffsets(
            data: data,
            type: .multiPatch,
            arrayBase: arrayBase,
            numPoints: numPoints,
            end: end)

        let coordinates = try readCoordinates(
            data: data,
            numPoints: numPoints,
            pointsOffset: pointsOffset,
            zOffset: offsets.zOffset,
            mOffset: offsets.mOffset,
            end: end,
            projection: projection)

        var geometries: [GeoJsonGeometry] = []
        var currentRing: [Coordinate3D]?
        var currentHoles: [[Coordinate3D]] = []

        func appendCurrentPolygon() {
            defer {
                currentRing = nil
                currentHoles = []
            }

            guard let ringCoordinates = currentRing, let ring = Ring(ringCoordinates) else {
                return
            }

            let holes = currentHoles.compactMap { Ring($0) }
            geometries.append(Polygon(unchecked: [ring] + holes))
        }

        for index in 0 ..< numParts {
            let partStart = partStarts[index]
            let partEnd = index + 1 < numParts ? partStarts[index + 1] : numPoints
            guard partEnd >= partStart else { throw ShapefileError.corruptedRecord }

            let partCoordinates = Array(coordinates[partStart ..< partEnd])

            switch partTypes[index] {
            case .firstRing, .outerRing, .ring:
                appendCurrentPolygon()
                currentRing = partCoordinates

            case .innerRing:
                currentHoles.append(partCoordinates)

            case .triangleFan, .triangleStrip:
                appendCurrentPolygon()
                geometries.append(contentsOf: decomposeTriangleMesh(partCoordinates, type: partTypes[index]))
            }
        }

        appendCurrentPolygon()
        return GeometryCollection(geometries)
    }

    private static func decomposeTriangleMesh(
        _ coordinates: [Coordinate3D],
        type: MultiPatchPartType
    ) -> [Polygon] {
        guard coordinates.count >= 3 else { return [] }

        var polygons: [Polygon] = []

        switch type {
        case .triangleStrip:
            // (0,1,2), (2,1,3), (2,3,4), ... with alternating winding.
            for index in 0 ..< (coordinates.count - 2) {
                let triangle: [Coordinate3D]
                if index % 2 == 0 {
                    triangle = [
                        coordinates[index],
                        coordinates[index + 1],
                        coordinates[index + 2],
                        coordinates[index],
                    ]
                }
                else {
                    triangle = [
                        coordinates[index + 1],
                        coordinates[index],
                        coordinates[index + 2],
                        coordinates[index + 1],
                    ]
                }

                if let polygon = Polygon([triangle]) {
                    polygons.append(polygon)
                }
            }

        case .triangleFan:
            // (0,1,2), (0,2,3), (0,3,4), ...
            for index in 1 ..< (coordinates.count - 1) {
                let triangle = [
                    coordinates[0],
                    coordinates[index],
                    coordinates[index + 1],
                    coordinates[0],
                ]

                if let polygon = Polygon([triangle]) {
                    polygons.append(polygon)
                }
            }

        default:
            break
        }

        return polygons
    }

    // MARK: - Shared record layout

    private static func readPartLayout(
        data: Data,
        start: Int,
        end: Int
    ) throws -> PartLayout {
        try requireBytes(start: start, length: 44, within: end)

        let numParts = try Int(readInt32(data, at: start + 36, end: end))
        let numPoints = try Int(readInt32(data, at: start + 40, end: end))
        guard numParts >= 0, numPoints >= 0 else { throw ShapefileError.corruptedRecord }

        let partsOffset = start + 44
        guard numParts <= (end - partsOffset) / 4 else { throw ShapefileError.corruptedRecord }

        let pointsOffset = partsOffset + numParts * 4
        guard pointsOffset <= end, numPoints <= (end - pointsOffset) / 16 else {
            throw ShapefileError.corruptedRecord
        }

        var partStarts: [Int] = []
        partStarts.reserveCapacity(numParts)
        for index in 0 ..< numParts {
            let value = try Int(readInt32(data, at: partsOffset + index * 4, end: end))
            guard value >= 0, value <= numPoints else { throw ShapefileError.corruptedRecord }

            if let previous = partStarts.last, value < previous {
                throw ShapefileError.corruptedRecord
            }
            partStarts.append(value)
        }

        if numParts > 0, partStarts.first != 0 {
            throw ShapefileError.corruptedRecord
        }

        return PartLayout(
            numParts: numParts,
            numPoints: numPoints,
            partStarts: partStarts,
            pointsOffset: pointsOffset,
            arrayBase: pointsOffset + numPoints * 16)
    }

    /// Validates and returns the offsets of optional Z and M blocks.
    private static func readZMOffsets(
        data: Data,
        type: ShapeType,
        arrayBase: Int,
        numPoints: Int,
        end: Int
    ) throws -> ZMOffsets {
        var zOffset: Int?
        var mOffset: Int?

        if type.hasZ {
            guard arrayBase + 16 <= end,
                  numPoints <= (end - arrayBase - 16) / 8
            else {
                throw ShapefileError.corruptedRecord
            }

            zOffset = arrayBase
            let mBase = arrayBase + 16 + numPoints * 8

            // The M block is optional for Z shape types.
            if mBase + 16 <= end, numPoints <= (end - mBase - 16) / 8 {
                mOffset = mBase
            }
        }
        else if type.hasM {
            guard arrayBase + 16 <= end,
                  numPoints <= (end - arrayBase - 16) / 8
            else {
                throw ShapefileError.corruptedRecord
            }

            mOffset = arrayBase
        }

        return ZMOffsets(zOffset: zOffset, mOffset: mOffset)
    }

    // MARK: - Coordinates

    private static func readCoordinates(
        data: Data,
        numPoints: Int,
        pointsOffset: Int,
        zOffset: Int?,
        mOffset: Int?,
        end: Int,
        projection: Projection
    ) throws -> [Coordinate3D] {
        var coordinates: [Coordinate3D] = []
        coordinates.reserveCapacity(numPoints)

        for index in 0 ..< numPoints {
            let x = try readDouble(data, at: pointsOffset + index * 16, end: end)
            let y = try readDouble(data, at: pointsOffset + index * 16 + 8, end: end)

            var altitude: Double?
            if let zOffset {
                let rawZ = try readDouble(data, at: zOffset + 16 + index * 8, end: end)
                altitude = ShapefileCoder.isValidZ(rawZ) ? rawZ : nil
            }

            var m: Double?
            if let mOffset {
                let rawM = try readDouble(data, at: mOffset + 16 + index * 8, end: end)
                m = ShapefileCoder.isNoData(rawM) ? nil : rawM
            }

            coordinates.append(Coordinate3D(
                x: x,
                y: y,
                z: altitude,
                m: m,
                projection: projection))
        }

        return coordinates
    }

    // MARK: - Ring orientation

    /// Returns `true` when the ring is clockwise in the X/Y plane.
    ///
    /// Geographic longitudes are unwrapped first so that rings crossing the
    /// antimeridian are not classified incorrectly.
    static func isClockwise(
        _ coordinates: [Coordinate3D],
        wrapLongitude: Bool
    ) -> Bool {
        guard coordinates.count >= 3 else { return false }

        var longitudes: [Double] = []
        longitudes.reserveCapacity(coordinates.count)

        var previousLongitude = coordinates[0].longitude
        longitudes.append(previousLongitude)

        for coordinate in coordinates.dropFirst() {
            var longitude = coordinate.longitude

            if wrapLongitude {
                while longitude - previousLongitude > 180.0 {
                    longitude -= 360.0
                }
                while previousLongitude - longitude > 180.0 {
                    longitude += 360.0
                }
            }

            longitudes.append(longitude)
            previousLongitude = longitude
        }

        var area = 0.0
        for index in 0 ..< coordinates.count {
            let next = (index + 1) % coordinates.count
            area += longitudes[index] * coordinates[next].latitude
            area -= longitudes[next] * coordinates[index].latitude
        }

        return area < 0.0
    }

    // MARK: - Primitive reads

    @discardableResult
    private static func requireBytes(
        start: Int,
        length: Int,
        within end: Int
    ) throws -> Int {
        guard start >= 0, length >= 0, start <= end, length <= end - start else {
            throw ShapefileError.corruptedRecord
        }

        return length
    }

    private static func readInt32(
        _ data: Data,
        at offset: Int,
        end: Int
    ) throws -> Int32 {
        guard offset >= 0, offset + 4 <= end, let value = data.readLittleEndianInt32(at: offset) else {
            throw ShapefileError.corruptedRecord
        }

        return value
    }

    private static func readDouble(
        _ data: Data,
        at offset: Int,
        end: Int
    ) throws -> Double {
        guard offset >= 0, offset + 8 <= end, let value = data.readLittleEndianDouble(at: offset) else {
            throw ShapefileError.corruptedRecord
        }

        return value
    }

}

// MARK: - .dbf reading

extension ShapefileCoder {

    /// Reads the attribute table from a `.dbf` file.
    ///
    /// - Parameters:
    ///   - data: The contents of the `.dbf` file.
    ///   - encoding: The encoding used for character fields and field names.
    ///   - idColumn: The column promoted to `Feature.Identifier`, or `nil`.
    /// - Returns: One entry per `.dbf` record. Deleted records are `nil`.
    static func readDbf(
        _ data: Data,
        encoding: String.Encoding,
        idColumn: String?
    ) throws -> [DbfRecord?] {
        guard data.count >= 32 else {
            throw ShapefileError.invalidDbfHeader("File too small")
        }
        guard let rawRecordCount = data.readLittleEndianInt32(at: 4),
              rawRecordCount >= 0
        else {
            throw ShapefileError.invalidDbfHeader("Invalid record count")
        }
        guard let headerLength = data.readLittleEndianUInt16(at: 8).map(Int.init),
              let recordLength = data.readLittleEndianUInt16(at: 10).map(Int.init)
        else {
            throw ShapefileError.invalidDbfHeader("Missing header lengths")
        }

        let recordCount = Int(rawRecordCount)

        guard headerLength >= 33 else {
            throw ShapefileError.invalidDbfHeader("Header too small")
        }
        guard recordLength >= 1 else {
            throw ShapefileError.invalidDbfHeader("Record length too small")
        }
        guard recordLength <= ShapefileCoder.maximumRecordLength else {
            throw ShapefileError.recordTooLarge(recordLength)
        }
        guard headerLength <= data.count else {
            throw ShapefileError.invalidDbfHeader("Truncated header")
        }
        guard data.readByte(at: headerLength - 1) == 0x0D else {
            throw ShapefileError.invalidDbfHeader("Missing field descriptor terminator")
        }

        let descriptorBytes = headerLength - 33
        guard descriptorBytes % 32 == 0 else {
            throw ShapefileError.invalidDbfHeader("Misaligned field descriptors")
        }

        let fieldCount = descriptorBytes / 32
        guard fieldCount <= ShapefileCoder.maximumFieldCount else {
            throw ShapefileError.tooManyFields(fieldCount)
        }

        var fields: [DbfFieldDescriptor] = []
        fields.reserveCapacity(fieldCount)

        for index in 0 ..< fieldCount {
            let fieldOffset = 32 + index * 32

            let nameStart = data.startIndex + fieldOffset
            let nameBytes = data[nameStart ..< (nameStart + 11)].prefix(while: { $0 != 0 })
            let name = String(bytes: nameBytes, encoding: .ascii)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                ?? String(decoding: nameBytes, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard let typeByte = data.readByte(at: fieldOffset + 11),
                  let scalar = UnicodeScalar(Int(typeByte)),
                  let fieldType = DbfFieldType(rawValue: Character(scalar))
            else {
                let rawType = data.readByte(at: fieldOffset + 11) ?? 0
                throw ShapefileError.unsupportedDbfFieldType(
                    Character(UnicodeScalar(rawType)))
            }
            guard let length = data.readByte(at: fieldOffset + 16).map(Int.init),
                  let decimalCount = data.readByte(at: fieldOffset + 17).map(Int.init)
            else {
                throw ShapefileError.invalidDbfHeader("Truncated field descriptor")
            }
            guard length > 0 else {
                throw ShapefileError.invalidDbfHeader("Field '\(name)' has zero length")
            }

            fields.append(DbfFieldDescriptor(
                name: name,
                propertyKey: nil,
                type: fieldType,
                length: length,
                decimalCount: decimalCount))
        }

        var fieldOffset = 1
        for field in fields {
            guard fieldOffset + field.length <= recordLength else {
                throw ShapefileError.invalidDbfHeader("Field '\(field.name)' exceeds the record length")
            }

            fieldOffset += field.length
        }

        guard recordCount == 0 || recordCount <= (data.count - headerLength) / recordLength else {
            throw ShapefileError.invalidDbfHeader("Truncated data")
        }

        var records: [DbfRecord?] = []
        records.reserveCapacity(recordCount)

        for recordIndex in 0 ..< recordCount {
            let recordStart = headerLength + recordIndex * recordLength

            guard let deleteFlag = data.readByte(at: recordStart) else {
                throw ShapefileError.invalidDbfHeader("Truncated record")
            }
            guard deleteFlag != 0x2A else {
                records.append(nil)
                continue
            }

            var properties: [String: Sendable] = [:]
            var recordFieldOffset = 1
            var id: Feature.Identifier?

            for field in fields {
                let fieldStart = recordStart + recordFieldOffset
                let fieldEnd = fieldStart + field.length
                recordFieldOffset += field.length

                let raw = data[(data.startIndex + fieldStart) ..< (data.startIndex + fieldEnd)]
                let value = parseDbfValue(raw, field: field, encoding: encoding)

                if field.name == idColumn {
                    id = Feature.Identifier(value: value)
                }
                else if let value {
                    properties[field.name] = value
                }
            }

            records.append(DbfRecord(id: id, properties: properties))
        }

        return records
    }

    private static func parseDbfValue(
        _ raw: Data.SubSequence,
        field: DbfFieldDescriptor,
        encoding: String.Encoding
    ) -> Sendable? {
        var bytes = Array(raw)
        while let last = bytes.last, last == 0 {
            bytes.removeLast()
        }

        switch field.type {
        case .character:
            // Character fields are right-padded with spaces. Leading spaces
            // are significant and must be preserved.
            while let last = bytes.last, last == 0x20 {
                bytes.removeLast()
            }

            let text = decodeDbfText(bytes, encoding: encoding)
            return text.isEmpty ? nil : text

        case .float, .numeric:
            let text = decodeDbfText(bytes, encoding: encoding)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !text.isEmpty, !text.allSatisfy({ $0 == "*" }) else { return nil }

            if field.decimalCount > 0 {
                return Double(text)
            }

            if let integer = Int(text) {
                return integer
            }
            if let integer = Int64(text) {
                return integer
            }
            if let integer = UInt64(text) {
                return integer
            }

            return Double(text)

        case .logical:
            let text = decodeDbfText(bytes, encoding: encoding)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased()

            switch text {
            case "T", "Y": return true
            case "F", "N": return false
            default: return nil
            }

        case .date, .memo:
            let text = decodeDbfText(bytes, encoding: encoding)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        }
    }

    private static func decodeDbfText(
        _ bytes: [UInt8],
        encoding: String.Encoding
    ) -> String {
        let data = Data(bytes)

        if let text = String(data: data, encoding: encoding) {
            return text
        }

        return String(decoding: bytes, as: UTF8.self)
    }

}
