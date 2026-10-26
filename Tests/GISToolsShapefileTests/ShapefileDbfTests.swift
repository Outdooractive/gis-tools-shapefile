import Foundation
@testable import GISTools
@testable import GISToolsShapefile
import Testing

struct ShapefileDbfTests {

    private func fieldNames(inDbf data: Data) throws -> [String] {
        let header = try ShapefileTestSupport.dbfHeader(data)
        let fieldCount = (header.headerLength - 33) / 32

        return (0 ..< fieldCount).map { index in
            let offset = 32 + index * 32
            let bytes = data[offset ..< (offset + 11)].prefix(while: { $0 != 0 })
            return String(decoding: bytes, as: UTF8.self)
        }
    }

    @Test
    func propertyTypesRoundTrip() throws {
        var feature = ShapefileTestSupport.feature(Point(Coordinate3D(latitude: 0.0, longitude: 0.0)))
        feature.properties = [
            "name": "Vienna",
            "count": 42,
            "value": 3.14159,
            "flag": true,
            "date": Date(timeIntervalSince1970: 86400.0),
            "leading": "  padded",
        ]

        let loaded = try ShapefileTestSupport.writeAndRead([feature])
        let properties = loaded.features[0].properties

        #expect(properties["name"] as? String == "Vienna")
        #expect(properties["count"] as? Int == 42)
        #expect((properties["value"] as? Double).map { abs($0 - 3.14159) < 0.00000001 } == true)
        #expect(properties["flag"] as? Bool == true)
        #expect(properties["date"] as? String == "19700102")
        #expect(properties["leading"] as? String == "  padded")
    }

    @Test
    func doubleTypeFidelity() throws {
        var feature = ShapefileTestSupport.feature(Point(Coordinate3D(latitude: 0.0, longitude: 0.0)))
        feature.properties = ["integral": 1.0, "fractional": 2.5]

        let loaded = try ShapefileTestSupport.writeAndRead([feature])
        let properties = loaded.features[0].properties

        #expect(properties["integral"] as? Double == 1.0)
        #expect(properties["fractional"] as? Double == 2.5)
        #expect((properties["integral"] as? Int) == nil)
    }

    @Test
    func fieldNamesAreTruncatedAndUnique() throws {
        var feature = ShapefileTestSupport.feature(Point(Coordinate3D(latitude: 0.0, longitude: 0.0)))
        feature.properties = [
            "abcdefghij": "ten",
            "abcdefghijkl": "eleven",
            "abcdefghijklm": "twelve",
            "café": "coffee",
            "123": "digits",
        ]

        let encoded = try ShapefileCoder.encode(FeatureCollection([feature]))
        let names = try fieldNames(inDbf: encoded.dbf)

        #expect(names.count == 5)
        #expect(names.allSatisfy { $0.count <= ShapefileCoder.maximumFieldNameLength })
        #expect(Set(names).count == names.count)
        #expect(names.contains("abcdefghij"))
        #expect(names.contains("caf_"))
        #expect(names.contains("f123"))

        let loaded = try ShapefileCoder.read(shp: encoded.shp, dbf: encoded.dbf)
        let values = Set(loaded.features[0].properties.values.compactMap { $0 as? String })
        #expect(values == ["ten", "eleven", "twelve", "coffee", "digits"])
    }

    @Test
    func maximumFieldCountRoundTrip() throws {
        var feature = ShapefileTestSupport.feature(Point(Coordinate3D(latitude: 0.0, longitude: 0.0)))
        var properties: [String: Sendable] = [:]
        for index in 0 ..< ShapefileCoder.maximumFieldCount {
            properties["f\(String(format: "%04d", index))"] = "v\(index)"
        }
        feature.properties = properties

        let encoded = try ShapefileCoder.encode(FeatureCollection([feature]))
        let header = try ShapefileTestSupport.dbfHeader(encoded.dbf)

        #expect(header.headerLength == 32 + 1024 * 32 + 1)
        #expect(encoded.dbf.readLittleEndianUInt16(at: 8) == 32801)

        let loaded = try ShapefileCoder.read(shp: encoded.shp, dbf: encoded.dbf)
        #expect(loaded.features[0].properties.count == 1024)
        #expect(loaded.features[0].properties["f0000"] as? String == "v0")
        #expect(loaded.features[0].properties["f1023"] as? String == "v1023")
    }

    @Test
    func tooManyFieldsThrows() throws {
        var feature = ShapefileTestSupport.feature(Point(Coordinate3D(latitude: 0.0, longitude: 0.0)))
        var properties: [String: Sendable] = [:]
        for index in 0 ... ShapefileCoder.maximumFieldCount {
            properties["f\(String(format: "%04d", index))"] = "v"
        }
        feature.properties = properties

        #expect(throws: ShapefileError.tooManyFields(1025)) {
            _ = try ShapefileCoder.encode(FeatureCollection([feature]))
        }
    }

    @Test
    func recordTooLargeThrows() throws {
        var feature = ShapefileTestSupport.feature(Point(Coordinate3D(latitude: 0.0, longitude: 0.0)))
        var properties: [String: Sendable] = [:]
        let value = String(repeating: "x", count: 64)
        for index in 0 ..< ShapefileCoder.maximumFieldCount {
            properties["f\(String(format: "%04d", index))"] = value
        }
        feature.properties = properties

        #expect(throws: ShapefileError.recordTooLarge(65537)) {
            _ = try ShapefileCoder.encode(FeatureCollection([feature]))
        }
    }

    @Test
    func longCharacterFieldsAreTruncatedTo254Bytes() throws {
        var feature = ShapefileTestSupport.feature(Point(Coordinate3D(latitude: 0.0, longitude: 0.0)))
        feature.properties = ["long": String(repeating: "a", count: 300)]

        let loaded = try ShapefileTestSupport.writeAndRead([feature])
        let value = try #require(loaded.features[0].properties["long"] as? String)
        #expect(value.count == 254)
        #expect(value.allSatisfy { $0 == "a" })
    }

    @Test
    func numericOverflowBecomesNoData() throws {
        var feature = ShapefileTestSupport.feature(Point(Coordinate3D(latitude: 0.0, longitude: 0.0)))
        feature.properties = ["huge": 1.0e300]

        let loaded = try ShapefileTestSupport.writeAndRead([feature])
        #expect(loaded.features[0].properties["huge"] == nil)
    }

    @Test
    func deletedRecordKeepsGeometryAlignment() throws {
        let features = [
            ShapefileTestSupport.feature(
                Point(Coordinate3D(latitude: 0.0, longitude: 0.0)),
                properties: ["index": 0]),
            ShapefileTestSupport.feature(
                Point(Coordinate3D(latitude: 1.0, longitude: 1.0)),
                properties: ["index": 1]),
        ]

        let encoded = try ShapefileCoder.encode(FeatureCollection(features))
        var dbf = encoded.dbf
        let header = try ShapefileTestSupport.dbfHeader(dbf)
        ShapefileTestSupport.setByte(0x2A, at: header.headerLength, in: &dbf)

        let loaded = try ShapefileCoder.read(shp: encoded.shp, dbf: dbf)

        #expect(loaded.features.count == 1)
        #expect(loaded.features[0].properties["index"] as? Int == 1)

        let point = try #require(loaded.features[0].geometry as? Point)
        #expect(point.coordinate.latitude == 1.0)
        #expect(point.coordinate.longitude == 1.0)
    }

    @Test
    func integerAndStringIdColumnsRoundTrip() throws {
        let integerFeatures = [
            ShapefileTestSupport.feature(
                Point(Coordinate3D(latitude: 0.0, longitude: 0.0)),
                properties: ["name": "one"],
                id: .int(1)),
            ShapefileTestSupport.feature(
                Point(Coordinate3D(latitude: 1.0, longitude: 1.0)),
                properties: ["name": "two"],
                id: .int(2)),
        ]

        let integerResult = try ShapefileTestSupport.writeAndRead(integerFeatures)
        #expect(integerResult.features.map(\.id) == [.int(1), .int(2)])
        #expect(integerResult.features[0].properties["id"] == nil)

        let stringFeatures = [
            ShapefileTestSupport.feature(
                Point(Coordinate3D(latitude: 0.0, longitude: 0.0)),
                id: .string("alpha")),
        ]

        let stringResult = try ShapefileTestSupport.writeAndRead(stringFeatures)
        #expect(stringResult.features[0].id == .string("alpha"))
    }

    @Test
    func doubleIdColumnRoundTrip() throws {
        let feature = ShapefileTestSupport.feature(
            Point(Coordinate3D(latitude: 0.0, longitude: 0.0)),
            id: .double(1.5))

        let loaded = try ShapefileTestSupport.writeAndRead([feature])
        #expect(loaded.features[0].id == .double(1.5))
    }

    @Test
    func customIdColumnRoundTrip() throws {
        let feature = ShapefileTestSupport.feature(
            Point(Coordinate3D(latitude: 0.0, longitude: 0.0)),
            properties: ["name": "x"],
            id: .int(9))

        let loaded = try ShapefileTestSupport.writeAndRead([feature], idColumn: "fid")
        #expect(loaded.features[0].id == .int(9))
        #expect(loaded.features[0].properties["fid"] == nil)
        #expect(loaded.features[0].properties["name"] as? String == "x")
    }

    @Test
    func idColumnConflictThrows() throws {
        let feature = ShapefileTestSupport.feature(
            Point(Coordinate3D(latitude: 0.0, longitude: 0.0)),
            properties: ["id": "property"],
            id: .int(1))

        #expect(throws: ShapefileError.idColumnConflict("id")) {
            _ = try ShapefileCoder.encode(FeatureCollection([feature]))
        }
    }

    @Test
    func idColumnCanBeDisabled() throws {
        let feature = ShapefileTestSupport.feature(
            Point(Coordinate3D(latitude: 0.0, longitude: 0.0)),
            properties: ["id": "property"],
            id: .int(1))

        let encoded = try ShapefileCoder.encode(
            FeatureCollection([feature]),
            idColumn: nil)

        let loaded = try ShapefileCoder.read(
            shp: encoded.shp,
            dbf: encoded.dbf,
            idColumn: nil)

        #expect(loaded.features[0].id == nil)
        #expect(loaded.features[0].properties["id"] as? String == "property")
    }

    @Test
    func regularIdPropertyIsPromotedOnRead() throws {
        var feature = ShapefileTestSupport.feature(
            Point(Coordinate3D(latitude: 0.0, longitude: 0.0)))
        feature.properties = ["id": 42, "name": "x"]

        let encoded = try ShapefileCoder.encode(
            FeatureCollection([feature]),
            idColumn: nil)

        let loaded = try ShapefileCoder.read(shp: encoded.shp, dbf: encoded.dbf)
        #expect(loaded.features[0].id == .int(42))
        #expect(loaded.features[0].properties["id"] == nil)
        #expect(loaded.features[0].properties["name"] as? String == "x")
    }

    @Test
    func latin1EncodingAndCpgRoundTrip() throws {
        let feature = ShapefileTestSupport.feature(
            Point(Coordinate3D(latitude: 0.0, longitude: 0.0)),
            properties: ["name": "Kärnten"])
        let url = ShapefileTestSupport.temporaryBaseURL()
        defer { ShapefileTestSupport.cleanup(url) }

        try ShapefileCoder.write(
            FeatureCollection([feature]),
            to: url,
            encoding: .isoLatin1)

        let cpgURL = url.appendingPathExtension("cpg")
        let cpg = try String(contentsOf: cpgURL, encoding: .utf8)
        #expect(cpg.trimmingCharacters(in: .whitespacesAndNewlines) == "ISO-8859-1")

        // The .cpg file is used when no explicit encoding is requested.
        let automatic = try ShapefileCoder.read(from: url)
        #expect(automatic.features[0].properties["name"] as? String == "Kärnten")

        let explicit = try ShapefileCoder.read(from: url, dbfEncoding: .isoLatin1)
        #expect(explicit.features[0].properties["name"] as? String == "Kärnten")
    }

    @Test
    func invalidDbfHeadersThrow() throws {
        let encoded = try ShapefileCoder.encode(FeatureCollection([
            ShapefileTestSupport.feature(
                Point(Coordinate3D(latitude: 0.0, longitude: 0.0)),
                properties: ["name": "x"]),
        ]))

        #expect(throws: ShapefileError.invalidDbfHeader("File too small")) {
            _ = try ShapefileCoder.read(shp: encoded.shp, dbf: Data("short".utf8))
        }

        var missingTerminator = encoded.dbf
        let header = try ShapefileTestSupport.dbfHeader(missingTerminator)
        ShapefileTestSupport.setByte(0x00, at: header.headerLength - 1, in: &missingTerminator)
        #expect(throws: ShapefileError.invalidDbfHeader("Missing field descriptor terminator")) {
            _ = try ShapefileCoder.read(shp: encoded.shp, dbf: missingTerminator)
        }

        let truncatedHeader = try ShapefileTestSupport.dbfHeader(encoded.dbf)
        let truncated = Data(encoded.dbf.prefix(truncatedHeader.headerLength))
        #expect(throws: ShapefileError.invalidDbfHeader("Truncated data")) {
            _ = try ShapefileCoder.read(shp: encoded.shp, dbf: truncated)
        }

        var unsupportedType = encoded.dbf
        ShapefileTestSupport.setByte(0x5A, at: 43, in: &unsupportedType)
        #expect(throws: ShapefileError.unsupportedDbfFieldType("Z")) {
            _ = try ShapefileCoder.read(shp: encoded.shp, dbf: unsupportedType)
        }

        var hugeRecord = encoded.dbf
        ShapefileTestSupport.setLittleEndianUInt16(65535, at: 10, in: &hugeRecord)
        #expect(throws: ShapefileError.recordTooLarge(65535)) {
            _ = try ShapefileCoder.read(shp: encoded.shp, dbf: hugeRecord)
        }
    }

    @Test
    func emptyStringDoesNotRoundTripAsEmptyString() throws {
        var feature = ShapefileTestSupport.feature(Point(Coordinate3D(latitude: 0.0, longitude: 0.0)))
        feature.properties = ["empty": ""]

        let loaded = try ShapefileTestSupport.writeAndRead([feature])
        #expect(loaded.features[0].properties["empty"] == nil)
    }

    @Test
    func missingFieldValuesBecomeNil() throws {
        let date = Date(timeIntervalSince1970: 86400.0)
        let first = ShapefileTestSupport.feature(
            Point(Coordinate3D(latitude: 0.0, longitude: 0.0)),
            properties: ["name": "x", "count": 1, "when": date])
        let second = ShapefileTestSupport.feature(
            Point(Coordinate3D(latitude: 1.0, longitude: 1.0)))

        let loaded = try ShapefileTestSupport.writeAndRead([first, second])
        let properties = loaded.features[1].properties

        #expect(properties["name"] == nil)
        #expect(properties["count"] == nil)
        #expect(properties["when"] == nil)
    }

    @Test
    func mixedNumericAndStringFieldUsesCharacter() throws {
        let first = ShapefileTestSupport.feature(
            Point(Coordinate3D(latitude: 0.0, longitude: 0.0)),
            properties: ["mixed": 42])
        let second = ShapefileTestSupport.feature(
            Point(Coordinate3D(latitude: 1.0, longitude: 1.0)),
            properties: ["mixed": "forty-two"])

        let loaded = try ShapefileTestSupport.writeAndRead([first, second])
        #expect(loaded.features[0].properties["mixed"] as? String == "42")
        #expect(loaded.features[1].properties["mixed"] as? String == "forty-two")
    }

    @Test
    func arrayAndBoolPropertiesUseCharacterWhenMixed() throws {
        let first = ShapefileTestSupport.feature(
            Point(Coordinate3D(latitude: 0.0, longitude: 0.0)),
            properties: ["value": [1, 2, 3] as [Int]])
        let second = ShapefileTestSupport.feature(
            Point(Coordinate3D(latitude: 1.0, longitude: 1.0)),
            properties: ["value": true])

        let loaded = try ShapefileTestSupport.writeAndRead([first, second])
        #expect(loaded.features[0].properties["value"] as? String == "[1, 2, 3]")
        #expect(loaded.features[1].properties["value"] as? String == "true")
    }

    @Test
    func floatPropertyRoundTrip() throws {
        let feature = ShapefileTestSupport.feature(
            Point(Coordinate3D(latitude: 0.0, longitude: 0.0)),
            properties: ["float": Float(1.5)])

        let loaded = try ShapefileTestSupport.writeAndRead([feature])
        #expect(loaded.features[0].properties["float"] as? Double == 1.5)
    }

    @Test
    func maximumWidthInteger() throws {
        let feature = ShapefileTestSupport.feature(
            Point(Coordinate3D(latitude: 0.0, longitude: 0.0)),
            properties: [
                "minimum": Int64.min,
                "maximum": UInt64.max,
            ])

        let loaded = try ShapefileTestSupport.writeAndRead([feature])
        #expect(loaded.features[0].properties["minimum"] as? Int == Int(Int64.min))
        #expect(loaded.features[0].properties["maximum"] as? UInt64 == UInt64.max)
    }

    @Test
    func emptyPropertyNameBecomesField() throws {
        var feature = ShapefileTestSupport.feature(Point(Coordinate3D(latitude: 0.0, longitude: 0.0)))
        feature.properties = ["": "value"]

        let encoded = try ShapefileCoder.encode(FeatureCollection([feature]))
        let names = try fieldNames(inDbf: encoded.dbf)
        #expect(names == ["field"])

        let loaded = try ShapefileCoder.read(shp: encoded.shp, dbf: encoded.dbf)
        #expect(loaded.features[0].properties["field"] as? String == "value")
    }

    @Test
    func invalidIdColumnsThrow() throws {
        let feature = ShapefileTestSupport.feature(
            Point(Coordinate3D(latitude: 0.0, longitude: 0.0)),
            id: .int(1))

        for invalid in ["1id", "id!", "id with space", "this_is_too_long"] {
            #expect(throws: ShapefileError.invalidFieldName(invalid)) {
                _ = try ShapefileCoder.encode(
                    FeatureCollection([feature]),
                    idColumn: invalid)
            }
        }
    }

    @Test
    func nonAsciiTextWithAsciiEncodingThrows() throws {
        let feature = ShapefileTestSupport.feature(
            Point(Coordinate3D(latitude: 0.0, longitude: 0.0)),
            properties: ["name": "Kärnten"])

        #expect(throws: ShapefileError.self) {
            _ = try ShapefileCoder.encode(
                FeatureCollection([feature]),
                encoding: .ascii)
        }
    }

    @Test
    func multibyteTruncationKeepsValidUTF8() throws {
        // 253 ASCII bytes + a two-byte UTF-8 character. The 254-byte field
        // boundary falls inside the character, so the writer must back off.
        let value = String(repeating: "a", count: 253) + "é"
        let feature = ShapefileTestSupport.feature(
            Point(Coordinate3D(latitude: 0.0, longitude: 0.0)),
            properties: ["text": value])

        let loaded = try ShapefileTestSupport.writeAndRead([feature])
        let result = try #require(loaded.features[0].properties["text"] as? String)
        #expect(result.count == 253)
        #expect(result.allSatisfy { $0 == "a" })
    }

    @Test
    func mixedDateAndStringUsesCharacter() throws {
        let date = Date(timeIntervalSince1970: 86400.0)
        let first = ShapefileTestSupport.feature(
            Point(Coordinate3D(latitude: 0.0, longitude: 0.0)),
            properties: ["value": date])
        let second = ShapefileTestSupport.feature(
            Point(Coordinate3D(latitude: 1.0, longitude: 1.0)),
            properties: ["value": "not a date"])

        let loaded = try ShapefileTestSupport.writeAndRead([first, second])
        #expect(loaded.features[0].properties["value"] as? String == "19700102")
        #expect(loaded.features[1].properties["value"] as? String == "not a date")
    }

    @Test
    func mixedDoubleAndStringUsesCharacter() throws {
        let first = ShapefileTestSupport.feature(
            Point(Coordinate3D(latitude: 0.0, longitude: 0.0)),
            properties: ["value": 1.5])
        let second = ShapefileTestSupport.feature(
            Point(Coordinate3D(latitude: 1.0, longitude: 1.0)),
            properties: ["value": "one and a half"])

        let loaded = try ShapefileTestSupport.writeAndRead([first, second])
        #expect(loaded.features[0].properties["value"] as? String == "1.5")
        #expect(loaded.features[1].properties["value"] as? String == "one and a half")
    }

    @Test
    func malformedDbfHeaderFieldsThrow() throws {
        let encoded = try ShapefileCoder.encode(FeatureCollection([
            ShapefileTestSupport.feature(
                Point(Coordinate3D(latitude: 0.0, longitude: 0.0)),
                properties: ["name": "x"]),
        ]))

        var negativeCount = encoded.dbf
        ShapefileTestSupport.setLittleEndianInt32(-1, at: 4, in: &negativeCount)
        #expect(throws: ShapefileError.invalidDbfHeader("Invalid record count")) {
            _ = try ShapefileCoder.read(shp: encoded.shp, dbf: negativeCount)
        }

        var smallHeader = encoded.dbf
        ShapefileTestSupport.setLittleEndianUInt16(10, at: 8, in: &smallHeader)
        #expect(throws: ShapefileError.invalidDbfHeader("Header too small")) {
            _ = try ShapefileCoder.read(shp: encoded.shp, dbf: smallHeader)
        }

        var zeroRecordLength = encoded.dbf
        ShapefileTestSupport.setLittleEndianUInt16(0, at: 10, in: &zeroRecordLength)
        #expect(throws: ShapefileError.invalidDbfHeader("Record length too small")) {
            _ = try ShapefileCoder.read(shp: encoded.shp, dbf: zeroRecordLength)
        }

        var truncatedHeader = encoded.dbf
        ShapefileTestSupport.setLittleEndianUInt16(1000, at: 8, in: &truncatedHeader)
        #expect(throws: ShapefileError.invalidDbfHeader("Truncated header")) {
            _ = try ShapefileCoder.read(shp: encoded.shp, dbf: truncatedHeader)
        }

        var misaligned = encoded.dbf
        ShapefileTestSupport.setLittleEndianUInt16(34, at: 8, in: &misaligned)
        ShapefileTestSupport.setByte(0x0D, at: 33, in: &misaligned)
        #expect(throws: ShapefileError.invalidDbfHeader("Misaligned field descriptors")) {
            _ = try ShapefileCoder.read(shp: encoded.shp, dbf: misaligned)
        }

        var zeroLengthField = encoded.dbf
        ShapefileTestSupport.setByte(0, at: 48, in: &zeroLengthField)
        #expect(throws: ShapefileError.invalidDbfHeader("Field 'name' has zero length")) {
            _ = try ShapefileCoder.read(shp: encoded.shp, dbf: zeroLengthField)
        }

        var oversizedField = encoded.dbf
        ShapefileTestSupport.setByte(200, at: 48, in: &oversizedField)
        #expect(throws: ShapefileError.invalidDbfHeader("Field 'name' exceeds the record length")) {
            _ = try ShapefileCoder.read(shp: encoded.shp, dbf: oversizedField)
        }
    }

    @Test
    func tooManyFieldsOnReadThrows() throws {
        let fieldCount = ShapefileCoder.maximumFieldCount + 1
        let headerLength = 32 + fieldCount * 32 + 1
        var dbf = Data(count: headerLength)
        ShapefileTestSupport.setByte(0x03, at: 0, in: &dbf)
        ShapefileTestSupport.setLittleEndianInt32(0, at: 4, in: &dbf)
        ShapefileTestSupport.setLittleEndianUInt16(UInt16(headerLength), at: 8, in: &dbf)
        ShapefileTestSupport.setLittleEndianUInt16(1, at: 10, in: &dbf)
        ShapefileTestSupport.setByte(0x0D, at: headerLength - 1, in: &dbf)

        let encoded = try ShapefileCoder.encode(FeatureCollection())
        #expect(throws: ShapefileError.tooManyFields(fieldCount)) {
            _ = try ShapefileCoder.read(shp: encoded.shp, dbf: dbf)
        }
    }

    @Test
    func encodingWithoutCpgLabelRemovesStaleCpg() throws {
        let url = ShapefileTestSupport.temporaryBaseURL()
        defer { ShapefileTestSupport.cleanup(url) }

        let feature = ShapefileTestSupport.feature(
            Point(Coordinate3D(latitude: 0.0, longitude: 0.0)),
            properties: ["name": "x"])

        try ShapefileCoder.write(FeatureCollection([feature]), to: url)
        #expect(FileManager.default.fileExists(atPath: url.appendingPathExtension("cpg").path))

        try ShapefileCoder.write(
            FeatureCollection([feature]),
            to: url,
            encoding: .utf16)
        #expect(!FileManager.default.fileExists(atPath: url.appendingPathExtension("cpg").path))
    }

    @Test
    func tinyDoublePrecisionIsPreserved() throws {
        let feature = ShapefileTestSupport.feature(
            Point(Coordinate3D(latitude: 0.0, longitude: 0.0)),
            properties: ["tiny": 1.0e-9])

        let loaded = try ShapefileTestSupport.writeAndRead([feature])
        let value = try #require(loaded.features[0].properties["tiny"] as? Double)
        #expect(abs(value - 1.0e-9) < 1.0e-15)
    }

    @Test
    func maximumRecordLengthIsAccepted() throws {
        var feature = ShapefileTestSupport.feature(Point(Coordinate3D(latitude: 0.0, longitude: 0.0)))
        var properties: [String: Sendable] = [:]
        for index in 0 ..< 1023 {
            properties["f\(String(format: "%04d", index))"] = String(repeating: "x", count: 64)
        }
        properties["f1023"] = String(repeating: "y", count: 58)
        feature.properties = properties

        let encoded = try ShapefileCoder.encode(FeatureCollection([feature]))
        let header = try ShapefileTestSupport.dbfHeader(encoded.dbf)
        #expect(header.recordLength == 65531)

        let loaded = try ShapefileCoder.read(shp: encoded.shp, dbf: encoded.dbf)
        #expect(loaded.features[0].properties.count == 1024)
        #expect((loaded.features[0].properties["f1022"] as? String)?.count == 64)
        #expect((loaded.features[0].properties["f1023"] as? String)?.count == 58)
    }

    @Test
    func unsignedIdRoundTrip() throws {
        let feature = ShapefileTestSupport.feature(
            Point(Coordinate3D(latitude: 0.0, longitude: 0.0)),
            id: .uint(UInt.max))

        let loaded = try ShapefileTestSupport.writeAndRead([feature])
        #expect(loaded.features[0].id == Feature.Identifier.uint(UInt.max))
    }

}
