import Foundation
import GISTools

// MARK: - .shp writing

extension ShapefileCoder {

    /// Writes `.shp` and `.shx` data for the given features.
    ///
    /// Coordinates are written verbatim in `FeatureCollection.projection`.
    /// The caller is responsible for writing a matching `.prj` file.
    static func writeShp(
        _ features: [Feature],
        projection: Projection
    ) throws -> (shp: Data, shx: Data) {
        let shapeType = try determineShapeType(features, projection: projection)

        var bounds = BoundingBoxValues()
        var zRange = ValueRange()
        var mRange = ValueRange()

        for feature in features {
            guard let geometry = feature.geometry else { continue }

            let coordinates = geometry.allCoordinates
            bounds.add(coordinates)

            if shapeType.hasZ {
                for coordinate in coordinates {
                    zRange.add(coordinate.altitude.flatMap { ShapefileCoder.isValidZ($0) ? $0 : nil })
                }
            }
            if shapeType.hasM {
                for coordinate in coordinates {
                    mRange.add(coordinate.m.flatMap { ShapefileCoder.isNoData($0) ? nil : $0 })
                }
            }
        }

        var records = Data()
        var shxRecords = Data()

        var recordNumber: Int32 = 1
        var recordOffsetInWords = 50

        for feature in features {
            var content = try shapeContent(for: feature.geometry, shapeType: shapeType)

            // Record content lengths are measured in 16-bit words. All shape
            // payloads are naturally even-sized, but pad defensively so the
            // declared length always matches the bytes that follow.
            if content.count % 2 != 0 {
                content.append(0)
            }

            let contentLengthInWords = content.count / 2
            guard contentLengthInWords <= Int(Int32.max),
                  recordOffsetInWords <= Int(Int32.max)
            else {
                throw ShapefileError.fileTooLarge
            }

            records.appendBigEndian(recordNumber)
            records.appendBigEndian(Int32(contentLengthInWords))
            records.append(content)

            shxRecords.appendBigEndian(Int32(recordOffsetInWords))
            shxRecords.appendBigEndian(Int32(contentLengthInWords))

            let (nextOffset, offsetOverflow) = recordOffsetInWords.addingReportingOverflow(4 + contentLengthInWords)
            guard !offsetOverflow else {
                throw ShapefileError.fileTooLarge
            }

            recordOffsetInWords = nextOffset

            guard recordNumber < Int32.max else {
                throw ShapefileError.fileTooLarge
            }

            recordNumber += 1
        }

        let shp = try makeHeader(
            shapeType: shapeType,
            totalByteLength: 100 + records.count,
            bounds: bounds,
            zRange: zRange,
            mRange: mRange) + records

        let shx = try makeHeader(
            shapeType: shapeType,
            totalByteLength: 100 + shxRecords.count,
            bounds: bounds,
            zRange: zRange,
            mRange: mRange) + shxRecords

        return (shp: shp, shx: shx)
    }

    /// Writes a 100-byte `.shp` or `.shx` header.
    private static func makeHeader(
        shapeType: ShapeType,
        totalByteLength: Int,
        bounds: BoundingBoxValues,
        zRange: ValueRange,
        mRange: ValueRange
    ) throws -> Data {
        guard totalByteLength % 2 == 0 else {
            throw ShapefileError.fileTooLarge
        }

        let lengthInWords = totalByteLength / 2
        guard lengthInWords <= Int(Int32.max) else {
            throw ShapefileError.fileTooLarge
        }

        var header = Data()
        header.appendBigEndian(Int32(9994)) // file code (big-endian)
        header.append(Data(count: 20)) // unused
        header.appendBigEndian(Int32(lengthInWords)) // file length in 16-bit words (big-endian)
        header.appendLittleEndian(Int32(1000)) // version (little-endian)
        header.appendLittleEndian(Int32(shapeType.rawValue)) // shape type (little-endian)

        header.appendLittleEndian(bounds.minXOrZero)
        header.appendLittleEndian(bounds.minYOrZero)
        header.appendLittleEndian(bounds.maxXOrZero)
        header.appendLittleEndian(bounds.maxYOrZero)
        header.appendLittleEndian(shapeType.hasZ ? zRange.minOrZero : 0.0)
        header.appendLittleEndian(shapeType.hasZ ? zRange.maxOrZero : 0.0)
        header.appendLittleEndian(shapeType.hasM ? mRange.minOrZero : 0.0)
        header.appendLittleEndian(shapeType.hasM ? mRange.maxOrZero : 0.0)

        return header
    }

    /// Determines the single shape type used by all records in the file.
    private static func determineShapeType(
        _ features: [Feature],
        projection: Projection
    ) throws -> ShapeType {
        var family: ShapeType?
        var hasZ = projection.isGeocentric
        var hasM = false

        for feature in features {
            guard let geometry = feature.geometry else { continue }
            guard geometry.projection == projection else {
                throw ShapefileError.mixedProjections
            }

            let baseType = try baseShapeType(for: geometry)
            if let family, family != baseType {
                throw ShapefileError.mixedGeometryTypes
            }
            family = baseType

            let coordinates = geometry.allCoordinates

            if coordinates.contains(where: { $0.projection != projection }) {
                throw ShapefileError.mixedProjections
            }
            if projection.isGeocentric,
               coordinates.contains(where: { $0.altitude == nil })
            {
                throw ShapefileError.invalidGeometry(
                    "EPSG:4978 coordinates require an altitude")
            }

            if coordinates.contains(where: { $0.altitude != nil }) {
                hasZ = true
            }
            if coordinates.contains(where: { $0.m != nil }) {
                hasM = true
            }
        }

        guard let family else {
            return .nullShape
        }

        if family == .multiPatch {
            return .multiPatch
        }
        if hasZ {
            return withZ(family)
        }
        if hasM {
            return withM(family)
        }
        return family
    }

    private static func baseShapeType(for geometry: GeoJsonGeometry) throws -> ShapeType {
        switch geometry {
        case is Point: return .point
        case is MultiPoint: return .multiPoint
        case is LineString, is MultiLineString: return .polyLine
        case is MultiPolygon, is Polygon: return .polygon
        case is GeometryCollection: return .multiPatch
        default: throw ShapefileError.unsupportedShapeType(0)
        }
    }

    private static func withZ(_ type: ShapeType) -> ShapeType {
        switch type {
        case .point: return .pointZ
        case .polyLine: return .polyLineZ
        case .polygon: return .polygonZ
        case .multiPoint: return .multiPointZ
        default: return type
        }
    }

    private static func withM(_ type: ShapeType) -> ShapeType {
        switch type {
        case .point: return .pointM
        case .polyLine: return .polyLineM
        case .polygon: return .polygonM
        case .multiPoint: return .multiPointM
        default: return type
        }
    }

    // MARK: - Shape content

    private static func shapeContent(
        for geometry: GeoJsonGeometry?,
        shapeType: ShapeType
    ) throws -> Data {
        guard let geometry else {
            return nullShapeContent()
        }

        switch geometry {
        case let point as Point:
            guard shapeType.baseType == .point else {
                throw ShapefileError.mixedGeometryTypes
            }

            return writePoint(point, shapeType: shapeType)

        case let multiPoint as MultiPoint:
            guard shapeType.baseType == .multiPoint else {
                throw ShapefileError.mixedGeometryTypes
            }

            return try writeMultiPoint(multiPoint, shapeType: shapeType)

        case let lineString as LineString:
            guard shapeType.baseType == .polyLine else {
                throw ShapefileError.mixedGeometryTypes
            }

            return try writePolyLine([lineString.coordinates], shapeType: shapeType)

        case let multiLineString as MultiLineString:
            guard shapeType.baseType == .polyLine else {
                throw ShapefileError.mixedGeometryTypes
            }

            return try writePolyLine(
                multiLineString.lineStrings.map { $0.coordinates },
                shapeType: shapeType)

        case let polygon as Polygon:
            guard shapeType.baseType == .polygon else {
                throw ShapefileError.mixedGeometryTypes
            }

            return try writePolygon([polygon], shapeType: shapeType)

        case let multiPolygon as MultiPolygon:
            guard shapeType.baseType == .polygon else {
                throw ShapefileError.mixedGeometryTypes
            }

            return try writePolygon(multiPolygon.polygons, shapeType: shapeType)

        case let geometryCollection as GeometryCollection:
            guard shapeType == .multiPatch else {
                throw ShapefileError.mixedGeometryTypes
            }

            return try writeMultiPatch(geometryCollection)

        default:
            throw ShapefileError.unsupportedShapeType(0)
        }
    }

    private static func nullShapeContent() -> Data {
        var data = Data()
        data.appendLittleEndian(Int32(0))
        return data
    }

    // MARK: - Point

    private static func writePoint(_ point: Point, shapeType: ShapeType) -> Data {
        let coordinate = point.coordinate

        var data = Data()
        data.appendLittleEndian(Int32(shapeType.rawValue))
        data.appendLittleEndian(coordinate.longitude)
        data.appendLittleEndian(coordinate.latitude)

        if shapeType.hasZ {
            data.appendLittleEndian(validAltitude(coordinate.altitude))
        }
        if shapeType.hasM {
            data.appendLittleEndian(validMeasure(coordinate.m))
        }

        return data
    }

    // MARK: - MultiPoint

    private static func writeMultiPoint(
        _ multiPoint: MultiPoint,
        shapeType: ShapeType
    ) throws -> Data {
        let coordinates = multiPoint.coordinates

        var data = Data()
        data.appendLittleEndian(Int32(shapeType.rawValue))

        var bounds = BoundingBoxValues()
        bounds.add(coordinates)
        append(bounds: bounds, to: &data)

        guard let numPoints = Int32(exactly: coordinates.count) else {
            throw ShapefileError.fileTooLarge
        }

        data.appendLittleEndian(numPoints)

        for coordinate in coordinates {
            data.appendLittleEndian(coordinate.longitude)
            data.appendLittleEndian(coordinate.latitude)
        }

        appendZBlock(coordinates, to: &data, include: shapeType.hasZ)
        appendMBlock(coordinates, to: &data, include: shapeType.hasM)

        return data
    }

    // MARK: - PolyLine

    private static func writePolyLine(
        _ rawParts: [[Coordinate3D]],
        shapeType: ShapeType
    ) throws -> Data {
        let parts = rawParts.filter { $0.isNotEmpty }

        guard parts.isNotEmpty else {
            return nullShapeContent()
        }

        for part in parts {
            guard part.count >= 2 else {
                throw ShapefileError.invalidGeometry(
                    "A PolyLine part must contain at least two coordinates")
            }
        }

        return try writePartShape(type: shapeType, parts: parts, partTypes: nil)
    }

    // MARK: - Polygon

    private static func writePolygon(
        _ polygons: [Polygon],
        shapeType: ShapeType
    ) throws -> Data {
        var parts: [[Coordinate3D]] = []

        for polygon in polygons {
            for (index, ringCoordinates) in polygon.coordinates.enumerated() {
                guard var coordinates = closedRing(ringCoordinates) else {
                    continue
                }

                let isOuter = index == 0
                let clockwise = isClockwise(
                    coordinates,
                    wrapLongitude: coordinates.first?.projection.isGeographic ?? false)

                // Shapefile convention: outer rings are clockwise and holes
                // are counter-clockwise. GeoJSON often uses the opposite
                // convention, so normalise every ring.
                if clockwise != isOuter {
                    coordinates.reverse()
                }

                parts.append(coordinates)
            }
        }

        guard parts.isNotEmpty else {
            return nullShapeContent()
        }

        return try writePartShape(type: shapeType, parts: parts, partTypes: nil)
    }

    // MARK: - MultiPatch

    private static func writeMultiPatch(
        _ geometryCollection: GeometryCollection
    ) throws -> Data {
        var parts: [[Coordinate3D]] = []
        var partTypes: [MultiPatchPartType] = []

        for geometry in geometryCollection.geometries {
            switch geometry {
            case let polygon as Polygon:
                try appendMultiPatchRings(
                    from: polygon,
                    parts: &parts,
                    partTypes: &partTypes)

            case let multiPolygon as MultiPolygon:
                for polygon in multiPolygon.polygons {
                    try appendMultiPatchRings(
                        from: polygon,
                        parts: &parts,
                        partTypes: &partTypes)
                }

            case let lineString as LineString:
                try appendMultiPatchLine(
                    lineString.coordinates,
                    parts: &parts,
                    partTypes: &partTypes)

            case let multiLineString as MultiLineString:
                for lineString in multiLineString.lineStrings {
                    try appendMultiPatchLine(
                        lineString.coordinates,
                        parts: &parts,
                        partTypes: &partTypes)
                }

            default:
                throw ShapefileError.invalidGeometry(
                    "A MultiPatch can only contain Polygons, MultiPolygons and LineStrings")
            }
        }

        guard parts.isNotEmpty else {
            return nullShapeContent()
        }

        return try writePartShape(type: .multiPatch, parts: parts, partTypes: partTypes)
    }

    private static func appendMultiPatchRings(
        from polygon: Polygon,
        parts: inout [[Coordinate3D]],
        partTypes: inout [MultiPatchPartType]
    ) throws {
        for (index, ringCoordinates) in polygon.coordinates.enumerated() {
            guard var coordinates = closedRing(ringCoordinates) else { continue }

            let isOuter = index == 0
            let clockwise = isClockwise(
                coordinates,
                wrapLongitude: coordinates.first?.projection.isGeographic ?? false)

            if clockwise != isOuter {
                coordinates.reverse()
            }

            parts.append(coordinates)
            partTypes.append(isOuter ? .outerRing : .innerRing)
        }
    }

    private static func appendMultiPatchLine(
        _ rawCoordinates: [Coordinate3D],
        parts: inout [[Coordinate3D]],
        partTypes: inout [MultiPatchPartType]
    ) throws {
        guard let coordinates = closedRing(rawCoordinates) else {
            throw ShapefileError.invalidGeometry(
                "A MultiPatch ring must contain at least three coordinates")
        }

        parts.append(coordinates)
        partTypes.append(.ring)
    }

    // MARK: - Shared part layout

    private static func writePartShape(
        type: ShapeType,
        parts: [[Coordinate3D]],
        partTypes: [MultiPatchPartType]?
    ) throws -> Data {
        if let partTypes, partTypes.count != parts.count {
            throw ShapefileError.invalidGeometry("MultiPatch part types do not match the part count")
        }

        let allCoordinates = parts.flatMap { $0 }

        guard let numParts = Int32(exactly: parts.count),
              let numPoints = Int32(exactly: allCoordinates.count)
        else {
            throw ShapefileError.fileTooLarge
        }

        var data = Data()
        data.appendLittleEndian(Int32(type.rawValue))

        var bounds = BoundingBoxValues()
        bounds.add(allCoordinates)
        append(bounds: bounds, to: &data)

        data.appendLittleEndian(numParts)
        data.appendLittleEndian(numPoints)

        var pointOffset = 0
        for part in parts {
            guard let start = Int32(exactly: pointOffset) else {
                throw ShapefileError.fileTooLarge
            }

            data.appendLittleEndian(start)
            pointOffset += part.count
        }

        if let partTypes {
            for partType in partTypes {
                data.appendLittleEndian(Int32(partType.rawValue))
            }
        }

        for coordinate in allCoordinates {
            data.appendLittleEndian(coordinate.longitude)
            data.appendLittleEndian(coordinate.latitude)
        }

        appendZBlock(allCoordinates, to: &data, include: type.hasZ)
        appendMBlock(allCoordinates, to: &data, include: type.hasM)

        return data
    }

    private static func append(
        bounds: BoundingBoxValues,
        to data: inout Data
    ) {
        data.appendLittleEndian(bounds.minXOrZero)
        data.appendLittleEndian(bounds.minYOrZero)
        data.appendLittleEndian(bounds.maxXOrZero)
        data.appendLittleEndian(bounds.maxYOrZero)
    }

    private static func appendZBlock(
        _ coordinates: [Coordinate3D],
        to data: inout Data,
        include: Bool
    ) {
        guard include else { return }

        let values = coordinates.map { validAltitude($0.altitude) }

        var range = ValueRange()
        for value in values where !ShapefileCoder.isNoData(value) {
            range.add(value)
        }

        data.appendLittleEndian(range.minOrZero)
        data.appendLittleEndian(range.maxOrZero)
        for value in values {
            data.appendLittleEndian(value)
        }
    }

    private static func appendMBlock(
        _ coordinates: [Coordinate3D],
        to data: inout Data,
        include: Bool
    ) {
        guard include else { return }

        let values = coordinates.map { validMeasure($0.m) }

        var range = ValueRange()
        for value in values where !ShapefileCoder.isNoData(value) {
            range.add(value)
        }

        data.appendLittleEndian(range.minOrZero)
        data.appendLittleEndian(range.maxOrZero)
        for value in values {
            data.appendLittleEndian(value)
        }
    }

    private static func validAltitude(_ altitude: Double?) -> Double {
        guard let altitude, ShapefileCoder.isValidZ(altitude) else {
            return ShapefileCoder.noData
        }

        return altitude
    }

    private static func validMeasure(_ measure: Double?) -> Double {
        guard let measure, !ShapefileCoder.isNoData(measure) else {
            return ShapefileCoder.noData
        }

        return measure
    }

    private static func closedRing(_ coordinates: [Coordinate3D]) -> [Coordinate3D]? {
        var coordinates = coordinates

        if coordinates.count >= 3, coordinates.first != coordinates.last {
            coordinates.append(coordinates[0])
        }

        return coordinates.count >= 4 ? coordinates : nil
    }

}

// MARK: - .dbf writing

extension ShapefileCoder {

    /// Writes a `.dbf` attribute table for the given features.
    static func writeDbf(
        _ features: [Feature],
        encoding: String.Encoding,
        idColumn: String?
    ) throws -> Data {
        let fields = try buildFieldDescriptors(
            features: features,
            encoding: encoding,
            idColumn: idColumn)

        guard let recordCount = Int32(exactly: features.count) else {
            throw ShapefileError.fileTooLarge
        }

        let recordLength = 1 + fields.reduce(0) { $0 + $1.length }
        guard recordLength <= maximumRecordLength else {
            throw ShapefileError.recordTooLarge(recordLength)
        }

        let headerLength = 32 + fields.count * 32 + 1
        guard headerLength <= Int(UInt16.max), let headerLength16 = UInt16(exactly: headerLength),
              let recordLength16 = UInt16(exactly: recordLength)
        else {
            throw ShapefileError.recordTooLarge(recordLength)
        }

        var header = Data()
        header.append(0x03) // dBase III without memo file

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let today = calendar.dateComponents([.year, .month, .day], from: Date())
        header.append(UInt8(truncatingIfNeeded: (today.year ?? 1970) % 100))
        header.append(UInt8(truncatingIfNeeded: today.month ?? 1))
        header.append(UInt8(truncatingIfNeeded: today.day ?? 1))

        header.appendLittleEndian(recordCount)
        header.appendLittleEndian(headerLength16)
        header.appendLittleEndian(recordLength16)
        header.append(Data(count: 20)) // reserved

        for field in fields {
            var nameBytes = field.name.data(using: .ascii) ?? Data()
            if nameBytes.count > maximumFieldNameLength {
                nameBytes = nameBytes.prefix(maximumFieldNameLength)
            }
            nameBytes.append(contentsOf: repeatElement(0, count: 11 - nameBytes.count))
            header.append(nameBytes)

            let typeValue = field.type.rawValue.unicodeScalars.first?.value ?? 0x20
            header.append(UInt8(truncatingIfNeeded: typeValue))
            header.appendLittleEndian(Int32(0)) // field address, unused
            header.append(UInt8(truncatingIfNeeded: field.length))
            header.append(UInt8(truncatingIfNeeded: field.decimalCount))
            header.append(Data(count: 14)) // reserved
        }

        header.append(0x0D) // field descriptor terminator

        var records = Data()
        for feature in features {
            records.append(0x20) // active record

            for field in fields {
                let value: Sendable?
                if let propertyKey = field.propertyKey {
                    value = feature.properties[propertyKey]
                }
                else {
                    value = feature.id?.asJson
                }

                try records.append(formatDbfValue(value, field: field, encoding: encoding))
            }
        }

        records.append(0x1A) // end-of-file marker
        return header + records
    }

    // MARK: - Field descriptors

    private static func buildFieldDescriptors(
        features: [Feature],
        encoding: String.Encoding,
        idColumn: String?
    ) throws -> [DbfFieldDescriptor] {
        var fields: [DbfFieldDescriptor] = []
        var usedNames = Set<String>()

        let hasIdentifiers = features.contains { $0.id != nil }

        if let idColumn, hasIdentifiers {
            guard isValidFieldName(idColumn) else {
                throw ShapefileError.invalidFieldName(idColumn)
            }

            for feature in features where feature.properties[idColumn] != nil {
                throw ShapefileError.idColumnConflict(idColumn)
            }

            usedNames.insert(idColumn)
            try fields.append(identifierFieldDescriptor(
                name: idColumn,
                features: features,
                encoding: encoding))
        }

        var keys: [String] = []
        var seenKeys = Set<String>()
        for feature in features {
            for key in feature.properties.keys where seenKeys.insert(key).inserted {
                keys.append(key)
            }
        }

        for key in keys {
            let name = try uniqueFieldName(key, usedNames: &usedNames)
            try fields.append(propertyFieldDescriptor(
                name: name,
                propertyKey: key,
                features: features,
                encoding: encoding))
        }

        guard fields.count <= maximumFieldCount else {
            throw ShapefileError.tooManyFields(fields.count)
        }

        return fields
    }

    private static func identifierFieldDescriptor(
        name: String,
        features: [Feature],
        encoding: String.Encoding
    ) throws -> DbfFieldDescriptor {
        let identifiers = features.compactMap { $0.id }

        let hasDouble = identifiers.contains { identifier in
            if case .double = identifier {
                return true
            }
            return false
        }

        let allNumeric = identifiers.allSatisfy { identifier in
            switch identifier {
            case .double, .int, .uint: return true
            case .string: return false
            }
        }

        if allNumeric {
            let decimalCount = hasDouble
                ? max(1, min(
                    15,
                    identifiers.compactMap { identifier -> Int? in
                        guard case let .double(value) = identifier else { return nil }

                        return requiredDecimalDigits(for: value)
                    }
                    .max() ?? 0))
                : 0

            return DbfFieldDescriptor(
                name: name,
                propertyKey: nil,
                type: .numeric,
                length: 20,
                decimalCount: decimalCount)
        }

        let length = identifiers
            .map { encodedLength($0.description, encoding: encoding) }
            .max() ?? 1

        return DbfFieldDescriptor(
            name: name,
            propertyKey: nil,
            type: .character,
            length: min(max(length, 1), maximumCharacterFieldLength),
            decimalCount: 0)
    }

    private static func propertyFieldDescriptor(
        name: String,
        propertyKey: String,
        features: [Feature],
        encoding: String.Encoding
    ) throws -> DbfFieldDescriptor {
        let values = features.compactMap { $0.properties[propertyKey] }
        guard values.isNotEmpty else {
            return DbfFieldDescriptor(
                name: name,
                propertyKey: propertyKey,
                type: .character,
                length: 1,
                decimalCount: 0)
        }

        var kinds = Set<DbfValueKind>()
        for value in values {
            kinds.insert(DbfValueKind(value))
        }

        if kinds == [.bool] {
            return DbfFieldDescriptor(
                name: name,
                propertyKey: propertyKey,
                type: .logical,
                length: 1,
                decimalCount: 0)
        }

        if kinds == [.integer] {
            return DbfFieldDescriptor(
                name: name,
                propertyKey: propertyKey,
                type: .numeric,
                length: 20,
                decimalCount: 0)
        }

        if kinds.isSubset(of: [.integer, .double]), kinds.contains(.double) {
            let decimalCount = max(1, min(
                15,
                values.compactMap { value -> Int? in
                    guard let double = value as? Double else { return nil }

                    return requiredDecimalDigits(for: double)
                }
                .max() ?? 0))

            return DbfFieldDescriptor(
                name: name,
                propertyKey: propertyKey,
                type: .numeric,
                length: 20,
                decimalCount: decimalCount)
        }

        if kinds == [.date] {
            return DbfFieldDescriptor(
                name: name,
                propertyKey: propertyKey,
                type: .date,
                length: 8,
                decimalCount: 0)
        }

        let length = values
            .map { encodedLength(dbfString($0), encoding: encoding) }
            .max() ?? 1

        return DbfFieldDescriptor(
            name: name,
            propertyKey: propertyKey,
            type: .character,
            length: min(max(length, 1), maximumCharacterFieldLength),
            decimalCount: 0)
    }

    private enum DbfValueKind: Hashable {

        case bool
        case integer
        case double
        case string
        case date
        case other

        init(_ value: Sendable) {
            if value is Bool {
                self = .bool
            }
            else if value is String {
                self = .string
            }
            else if value is Date {
                self = .date
            }
            else if value is any BinaryInteger {
                self = .integer
            }
            else if value is Double || value is Float {
                self = .double
            }
            else {
                self = .other
            }
        }

    }

    // MARK: - Field names

    private static func uniqueFieldName(
        _ key: String,
        usedNames: inout Set<String>
    ) throws -> String {
        var name = ""
        for scalar in key.unicodeScalars {
            let value = scalar.value
            let isLetter = (65 ... 90).contains(value) || (97 ... 122).contains(value)
            let isDigit = (48 ... 57).contains(value)
            let isUnderscore = value == 95

            if isLetter || isDigit || isUnderscore {
                name.unicodeScalars.append(scalar)
            }
            else {
                name.append("_")
            }

            if name.count == maximumFieldNameLength {
                break
            }
        }

        if name.isEmpty {
            name = "field"
        }

        if let first = name.first, first.isNumber {
            name = "f" + name.prefix(maximumFieldNameLength - 1)
        }

        if usedNames.insert(name).inserted {
            return name
        }

        for index in 1 ..< 1_000_000 {
            let suffix = String(index)
            let stemLength = max(0, maximumFieldNameLength - suffix.count)
            let candidate = String(name.prefix(stemLength)) + suffix

            if usedNames.insert(candidate).inserted {
                return candidate
            }
        }

        throw ShapefileError.invalidFieldName(key)
    }

    private static func isValidFieldName(_ name: String) -> Bool {
        guard name.isNotEmpty, name.count <= maximumFieldNameLength else { return false }

        for (index, scalar) in name.unicodeScalars.enumerated() {
            let value = scalar.value
            let isLetter = (65 ... 90).contains(value) || (97 ... 122).contains(value)
            let isDigit = (48 ... 57).contains(value)
            let isUnderscore = value == 95

            if index == 0, !isLetter, !isUnderscore {
                return false
            }
            if !isLetter, !isDigit, !isUnderscore {
                return false
            }
        }

        return true
    }

    // MARK: - Value formatting

    private static func formatDbfValue(
        _ value: Sendable?,
        field: DbfFieldDescriptor,
        encoding: String.Encoding
    ) throws -> Data {
        switch field.type {
        case .character:
            return try formatCharacter(value, length: field.length, encoding: encoding)
        case .float, .numeric:
            return formatNumeric(value, length: field.length, decimalCount: field.decimalCount)
        case .logical:
            return formatLogical(value, length: field.length)
        case .date:
            return formatDate(value, length: field.length)
        case .memo:
            return spaces(field.length)
        }
    }

    private static func formatCharacter(
        _ value: Sendable?,
        length: Int,
        encoding: String.Encoding
    ) throws -> Data {
        guard let value else { return spaces(length) }

        let text = dbfString(value).replacingOccurrences(of: "\0", with: " ")

        guard var data = text.data(using: encoding) else {
            throw ShapefileError.unsupportedEncoding(
                "String.Encoding(rawValue: \(encoding.rawValue))")
        }

        if data.count > length {
            var prefix = data.prefix(length)
            while prefix.isNotEmpty, String(data: prefix, encoding: encoding) == nil {
                prefix = prefix.dropLast()
            }
            data = Data(prefix)
        }

        if data.count < length {
            data.append(Data(repeating: 0x20, count: length - data.count))
        }

        return data
    }

    private static func formatNumeric(
        _ value: Sendable?,
        length: Int,
        decimalCount: Int
    ) -> Data {
        guard let value else { return spaces(length) }

        if let integer = value as? any BinaryInteger {
            return leftPadded("\(integer)", length: length)
        }

        let double: Double?
        if let value = value as? Double {
            double = value
        }
        else if let value = value as? Float {
            double = Double(value)
        }
        else {
            double = nil
        }

        guard let double else { return spaces(length) }
        guard double.isFinite else { return asterisks(length) }

        let locale = Locale(identifier: "en_US_POSIX")
        var decimals = min(max(decimalCount, 0), 15)

        while decimals >= 0 {
            let text = String(format: "%.\(decimals)f", locale: locale, double)
            if text.count <= length {
                return leftPadded(text, length: length)
            }
            decimals -= 1
        }

        return asterisks(length)
    }

    private static func formatLogical(_ value: Sendable?, length: Int) -> Data {
        guard let value = value as? Bool else { return spaces(length) }

        let text = value ? "T" : "F"
        if text.count >= length {
            return Data(text.prefix(length).utf8)
        }

        return Data(text.utf8) + Data(repeating: 0x20, count: length - text.count)
    }

    private static func formatDate(_ value: Sendable?, length: Int) -> Data {
        guard let value else { return spaces(length) }

        let text: String
        if let date = value as? Date {
            text = dateText(date)
        }
        else if let string = value as? String {
            text = String(string.filter { $0.isNumber }.prefix(8))
        }
        else {
            return spaces(length)
        }

        if text.count >= length {
            return Data(text.prefix(length).utf8)
        }

        return Data(text.utf8) + Data(repeating: 0x20, count: length - text.count)
    }

    private static func dbfString(_ value: Sendable) -> String {
        if let string = value as? String {
            return string
        }
        if let bool = value as? Bool {
            return bool ? "true" : "false"
        }
        if let date = value as? Date {
            return dateText(date)
        }
        if let integer = value as? any BinaryInteger {
            return "\(integer)"
        }
        if let double = value as? Double {
            return "\(double)"
        }
        if let float = value as? Float {
            return "\(float)"
        }

        return String(describing: value)
    }

    private static func dateText(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let components = calendar.dateComponents([.year, .month, .day], from: date)

        guard let year = components.year,
              let month = components.month,
              let day = components.day
        else {
            return ""
        }

        return String(format: "%04d%02d%02d", year, month, day)
    }

    private static func leftPadded(_ text: String, length: Int) -> Data {
        if text.count >= length {
            return text.count == length
                ? Data(text.utf8)
                : asterisks(length)
        }

        return Data(repeating: 0x20, count: length - text.count) + Data(text.utf8)
    }

    private static func spaces(_ length: Int) -> Data {
        Data(repeating: 0x20, count: length)
    }

    private static func asterisks(_ length: Int) -> Data {
        Data(repeating: 0x2A, count: length)
    }

    private static func requiredDecimalDigits(for value: Double) -> Int {
        guard value.isFinite else { return 0 }

        let locale = Locale(identifier: "en_US_POSIX")
        let tolerance = max(abs(value) * 0.000000000001, 0.000000000000001)

        for decimals in 0 ... 15 {
            let text = String(format: "%.\(decimals)f", locale: locale, value)
            if let parsed = Double(text), abs(parsed - value) <= tolerance {
                return decimals
            }
        }

        return 15
    }

    private static func encodedLength(_ text: String, encoding: String.Encoding) -> Int {
        (text.data(using: encoding) ?? text.data(using: .utf8) ?? Data()).count
    }

}

// MARK: - .prj writing

extension ShapefileCoder {

    /// The WKT representation of a projection, or `nil` for `noSRID`.
    ///
    /// - Throws: ``ShapefileError/unsupportedProjection(_:)`` when the
    ///   projection has no WKT template in this library.
    static func projectionWKT(_ projection: Projection) throws -> String? {
        guard projection.hasSRID else { return nil }

        switch projection.srid {
        case 4326:
            return #"GEOGCS["WGS 84",DATUM["WGS_1984",SPHEROID["WGS 84",6378137,298.257223563]],PRIMEM["Greenwich",0],UNIT["degree",0.0174532925199433]]"#

        case 3857:
            return #"PROJCS["WGS 84 / Pseudo-Mercator",GEOGCS["WGS 84",DATUM["WGS_1984",SPHEROID["WGS 84",6378137,298.257223563]],PRIMEM["Greenwich",0],UNIT["degree",0.0174532925199433]],PROJECTION["Mercator_1SP"],PARAMETER["central_meridian",0],PARAMETER["scale_factor",1],PARAMETER["false_easting",0],PARAMETER["false_northing",0],UNIT["metre",1]]"#

        case 4978:
            return #"GEOCCS["WGS 84 (geocentric)",DATUM["WGS_1984",SPHEROID["WGS 84",6378137,298.257223563]],PRIMEM["Greenwich",0],UNIT["metre",1]]"#

        default:
            throw ShapefileError.unsupportedProjection(projection.description)
        }
    }

}
