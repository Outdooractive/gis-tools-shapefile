import Foundation
import GISTools

// MARK: - FeatureCollection convenience extensions

extension FeatureCollection {

    /// Initialize a `FeatureCollection` by reading a Shapefile from the given base URL.
    ///
    /// Loads `<url>.shp` (required), `<url>.dbf` (required), and optionally
    /// `<url>.prj` for the projection and `<url>.cpg` for the `.dbf` encoding.
    ///
    /// The URL may point to the base path (`/data/cities`), any of the
    /// shapefile components (`/data/cities.shp`).
    ///
    /// - Parameters:
    ///   - url: The base URL or the URL of one of the shapefile components.
    ///   - calculateBoundingBox: Whether to calculate a bounding box (default `false`).
    ///   - idColumn: The `.dbf` column promoted to `Feature.id`, or `nil`
    ///     to keep it as a regular property (default `"id"`).
    ///   - dbfEncoding: The `.dbf` encoding. When `nil`, the `.cpg` file is
    ///     consulted and UTF-8 is used as the fallback.
    public init?(
        shapefile url: URL,
        calculateBoundingBox: Bool = false,
        idColumn: String? = "id",
        dbfEncoding: String.Encoding? = nil
    ) {
        guard let collection = try? ShapefileCoder.read(
            from: url,
            calculateBoundingBox: calculateBoundingBox,
            idColumn: idColumn,
            dbfEncoding: dbfEncoding)
        else {
            return nil
        }

        self = collection
    }

    /// Write the receiver as a Shapefile to the given base URL.
    ///
    /// Writes `<url>.shp`, `<url>.dbf`, `<url>.shx`, `<url>.cpg` and, when
    /// the projection has a WKT representation, `<url>.prj`.
    ///
    /// - Parameters:
    ///   - url: The base output URL (without extension), or a URL using one of
    ///     the shapefile extensions.
    ///   - encoding: The `.dbf` string encoding (default UTF-8).
    ///   - idColumn: The `.dbf` column receiving `Feature.id` values. Pass
    ///     `nil` to omit feature identifiers (default `"id"`).
    public func writeShapefile(
        to url: URL,
        encoding: String.Encoding = .utf8,
        idColumn: String? = "id"
    ) throws {
        try ShapefileCoder.write(
            self,
            to: url,
            encoding: encoding,
            idColumn: idColumn)
    }

}

// MARK: - ShapefileCoder

/// Reads and writes ESRI Shapefiles (`.shp`, `.dbf`, `.shx`, `.prj`).
///
/// A shapefile is a set of files sharing one base path:
///
/// | Extension | Contents |
/// |-----------|----------|
/// | `.shp`    | Geometry records (big-endian header, little-endian records) |
/// | `.dbf`    | dBase attribute table |
/// | `.shx`    | Fixed-size spatial index written by this library |
/// | `.prj`    | WKT coordinate reference system (optional) |
/// | `.cpg`    | `.dbf` code page (optional) |
///
/// Geometry types map between shapefile and GeoJSON as follows:
///
/// | Shape type                 | GeoJSON type |
/// |----------------------------|--------------|
/// | Point, PointZ, PointM      | `Point` |
/// | PolyLine, Z, M             | `LineString` or `MultiLineString` |
/// | Polygon, Z, M              | `Polygon` or `MultiPolygon` |
/// | MultiPoint, Z, M           | `MultiPoint` |
/// | MultiPatch                 | `GeometryCollection` of `Polygon` values |
///
/// Null shapes become features without a geometry (RFC 7946 §3.2).
public enum ShapefileCoder {

    /// The error type thrown by the coder.
    ///
    /// Kept as a nested type for compatibility; new code can use
    /// ``ShapefileError`` directly.
    public typealias ShapefileCoderError = ShapefileError

    /// The maximum number of fields in a `.dbf` table (`1024`).
    public static let maximumFieldCount = 1024

    /// The maximum `.dbf` record length in bytes (`65_531`).
    public static let maximumRecordLength = 65531

    /// The maximum `.dbf` field-name length in bytes (`10`).
    public static let maximumFieldNameLength = 10

    /// The maximum length of a `.dbf` character field in bytes (`254`).
    public static let maximumCharacterFieldLength = 254

}

// MARK: - In-memory representation

/// The individual files that make up a shapefile.
///
/// This is returned by ``ShapefileCoder/encode(_:encoding:idColumn:)`` and is
/// useful for tests, in-memory pipelines, or writing the components yourself.
public struct ShapefileData: Sendable {

    /// The contents of the `.shp` file.
    public let shp: Data

    /// The contents of the `.dbf` file.
    public let dbf: Data

    /// The contents of the `.shx` file.
    public let shx: Data

    /// The `.prj` WKT string, or `nil` for coordinates without an SRID.
    public let prj: String?

    /// Creates a shapefile data bundle.
    public init(shp: Data, dbf: Data, shx: Data, prj: String?) {
        self.shp = shp
        self.dbf = dbf
        self.shx = shx
        self.prj = prj
    }

}

// MARK: - Reading

extension ShapefileCoder {

    /// Reads a Shapefile from a base URL.
    ///
    /// - Parameters:
    ///   - url: The base URL or the URL of one of the shapefile components.
    ///   - calculateBoundingBox: Whether to calculate a bounding box (default `false`).
    ///   - idColumn: The `.dbf` column promoted to `Feature.id`, or `nil`
    ///     to keep it as a property (default `"id"`).
    ///   - dbfEncoding: The `.dbf` encoding. When `nil`, `<url>.cpg` is
    ///     consulted and UTF-8 is used as the fallback.
    /// - Returns: A `FeatureCollection` with one feature per active
    ///   `.dbf` record.
    /// - Throws: ``ShapefileError`` when a file is missing, malformed or uses
    ///   an unsupported feature.
    public static func read(
        from url: URL,
        calculateBoundingBox: Bool = false,
        idColumn: String? = "id",
        dbfEncoding: String.Encoding? = nil
    ) throws -> FeatureCollection {
        let baseURL = componentBaseURL(for: url)
        let shpURL = componentURL(baseURL, extension: "shp")
        let dbfURL = componentURL(baseURL, extension: "dbf")
        let prjURL = componentURL(baseURL, extension: "prj")

        let shpData = try readFile(shpURL)
        let dbfData = try readFile(dbfURL)
        let prjString = try readOptionalText(prjURL)
        let encoding = dbfEncoding ?? cpgEncoding(for: baseURL) ?? .utf8

        return try read(
            shp: shpData,
            dbf: dbfData,
            prj: prjString,
            calculateBoundingBox: calculateBoundingBox,
            idColumn: idColumn,
            dbfEncoding: encoding)
    }

    /// Reads an in-memory Shapefile.
    ///
    /// This is useful when the individual components come from a database, an
    /// archive, or a network response instead of the file system.
    ///
    /// - Parameters:
    ///   - shp: The contents of the `.shp` file.
    ///   - dbf: The contents of the `.dbf` file.
    ///   - prj: The `.prj` WKT string, or `nil` to assume EPSG:4326.
    ///   - calculateBoundingBox: Whether to calculate a bounding box (default `false`).
    ///   - idColumn: The `.dbf` column promoted to `Feature.id`, or `nil`
    ///     to keep it as a property (default `"id"`).
    ///   - dbfEncoding: The `.dbf` string encoding (default UTF-8).
    /// - Returns: A `FeatureCollection` with one feature per active
    ///   `.dbf` record.
    /// - Throws: ``ShapefileError`` when the data is malformed or uses an
    ///   unsupported feature.
    public static func read(
        shp: Data,
        dbf: Data,
        prj: String? = nil,
        calculateBoundingBox: Bool = false,
        idColumn: String? = "id",
        dbfEncoding: String.Encoding = .utf8
    ) throws -> FeatureCollection {
        let projection = try resolveProjection(prj)

        let geometries = try readShp(shp, projection: projection)
        let rows = try readDbf(dbf, encoding: dbfEncoding, idColumn: idColumn)

        guard geometries.count == rows.count else {
            throw ShapefileError.recordCountMismatch(
                shp: geometries.count,
                dbf: rows.count)
        }

        var features: [Feature] = []
        features.reserveCapacity(rows.count)

        for index in 0 ..< rows.count {
            // Deleted .dbf records are skipped together with their geometry.
            guard let row = rows[index] else { continue }

            if let geometry = geometries[index] {
                features.append(Feature(
                    geometry,
                    id: row.id,
                    properties: row.properties,
                    calculateBoundingBox: calculateBoundingBox))
            }
            else {
                // Null shape: keep the attributes on an unlocated feature.
                features.append(Feature(
                    id: row.id,
                    properties: row.properties))
            }
        }

        return FeatureCollection(
            features,
            calculateBoundingBox: calculateBoundingBox)
    }

}

// MARK: - Writing

extension ShapefileCoder {

    /// Encodes a `FeatureCollection` as a set of in-memory shapefile files.
    ///
    /// Coordinates are written verbatim in the collection's projection. Only
    /// EPSG:4326, EPSG:3857 and EPSG:4978 have a WKT representation and can be
    /// written with a `.prj` file; other projections throw
    /// ``ShapefileError/unsupportedProjection(_:)``. Coordinates without an
    /// SRID are written without a `.prj` file.
    ///
    /// - Parameters:
    ///   - featureCollection: The collection to encode.
    ///   - encoding: The `.dbf` string encoding (default UTF-8).
    ///   - idColumn: The `.dbf` column receiving `Feature.id` values. Pass
    ///     `nil` to omit identifiers (default `"id"`).
    /// - Returns: The `.shp`, `.dbf`, `.shx` and optional `.prj` contents.
    /// - Throws: ``ShapefileError`` when the features cannot be represented by
    ///   one shapefile.
    public static func encode(
        _ featureCollection: FeatureCollection,
        encoding: String.Encoding = .utf8,
        idColumn: String? = "id"
    ) throws -> ShapefileData {
        let projection = featureCollection.projection

        let (shp, shx) = try writeShp(featureCollection.features, projection: projection)
        let dbf = try writeDbf(
            featureCollection.features,
            encoding: encoding,
            idColumn: idColumn)
        let prj = try projectionWKT(projection)

        return ShapefileData(shp: shp, dbf: dbf, shx: shx, prj: prj)
    }

    /// Writes a `FeatureCollection` to the given base URL.
    ///
    /// Writes `<url>.shp`, `<url>.dbf`, `<url>.shx`, `<url>.cpg` and, when
    /// available, `<url>.prj`. A stale `.prj` or `.cpg` file is removed when
    /// the new output does not need one.
    ///
    /// - Parameters:
    ///   - featureCollection: The collection to write.
    ///   - url: The base output URL, or a URL using one of the shapefile
    ///     extensions.
    ///   - encoding: The `.dbf` string encoding (default UTF-8).
    ///   - idColumn: The `.dbf` column receiving `Feature.id` values. Pass
    ///     `nil` to omit identifiers (default `"id"`).
    /// - Throws: ``ShapefileError`` when the collection cannot be represented
    ///   or a file cannot be written.
    public static func write(
        _ featureCollection: FeatureCollection,
        to url: URL,
        encoding: String.Encoding = .utf8,
        idColumn: String? = "id"
    ) throws {
        let data = try encode(
            featureCollection,
            encoding: encoding,
            idColumn: idColumn)

        let baseURL = componentBaseURL(for: url)
        let shpURL = baseURL.appendingPathExtension("shp")
        let dbfURL = baseURL.appendingPathExtension("dbf")
        let shxURL = baseURL.appendingPathExtension("shx")
        let prjURL = baseURL.appendingPathExtension("prj")
        let cpgURL = baseURL.appendingPathExtension("cpg")

        do {
            try data.shp.write(to: shpURL, options: .atomic)
            try data.dbf.write(to: dbfURL, options: .atomic)
            try data.shx.write(to: shxURL, options: .atomic)

            if let prj = data.prj {
                try prj.write(to: prjURL, atomically: true, encoding: .utf8)
            }
            else {
                removeFileIfExists(prjURL)
            }

            if let label = cpgLabel(for: encoding) {
                try label.write(to: cpgURL, atomically: true, encoding: .utf8)
            }
            else {
                removeFileIfExists(cpgURL)
            }
        }
        catch let error as ShapefileError {
            throw error
        }
        catch {
            throw ShapefileError.ioError(error.localizedDescription)
        }
    }

}

// MARK: - File helpers

extension ShapefileCoder {

    private static func componentBaseURL(for url: URL) -> URL {
        switch url.pathExtension.lowercased() {
        case "cpg", "dbf", "prj", "shp", "shx":
            return url.deletingPathExtension()
        default:
            return url
        }
    }

    /// Resolves a shapefile component, accepting both lower- and upper-case
    /// extensions on case-sensitive file systems.
    private static func componentURL(_ baseURL: URL, extension pathExtension: String) -> URL {
        let candidates = [
            pathExtension,
            pathExtension.uppercased(),
            pathExtension.capitalized,
        ]

        for candidate in candidates {
            let url = baseURL.appendingPathExtension(candidate)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }

        return baseURL.appendingPathExtension(pathExtension)
    }

    private static func readFile(_ url: URL) throws -> Data {
        do {
            return try Data(contentsOf: url)
        }
        catch {
            throw ShapefileError.ioError(
                "\(url.lastPathComponent): \(error.localizedDescription)")
        }
    }

    private static func readOptionalText(_ url: URL) throws -> String? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }

        let data = try readFile(url)

        if let text = String(data: data, encoding: .utf8) {
            return text
        }
        if let text = String(data: data, encoding: .isoLatin1) {
            return text
        }

        throw ShapefileError.unsupportedProjection("The .prj file is not readable text")
    }

    private static func resolveProjection(_ wkt: String?) throws -> Projection {
        guard let wkt else {
            // Absent .prj: the shapefile specification does not mandate a CRS,
            // and EPSG:4326 is the conventional assumption.
            return .epsg4326
        }

        let cleaned = wkt
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .replacingOccurrences(of: "\0", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard cleaned.isNotEmpty else {
            throw ShapefileError.unsupportedProjection("The .prj file is empty")
        }
        guard let projection = Projection(wkt: cleaned) else {
            throw ShapefileError.unsupportedProjection(
                String(cleaned.prefix(120)))
        }

        return projection
    }

    private static func removeFileIfExists(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        try? FileManager.default.removeItem(at: url)
    }

    private static func cpgLabel(for encoding: String.Encoding) -> String? {
        switch encoding {
        case .utf8: return "UTF-8"
        case .ascii: return "ASCII"
        case .isoLatin1: return "ISO-8859-1"
        case .windowsCP1252: return "1252"
        default: return nil
        }
    }

    private static func cpgEncoding(for baseURL: URL) -> String.Encoding? {
        let url = componentURL(baseURL, extension: "cpg")
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8)
        else {
            return nil
        }

        let normalized = text
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .replacingOccurrences(of: "_", with: "-")

        switch normalized {
        case "65001", "UTF-8", "UTF8": return .utf8
        case "20127", "ASCII", "US-ASCII": return .ascii
        case "28591", "ISO-8859-1", "ISO8859-1", "LATIN-1", "LATIN1": return .isoLatin1
        case "1252", "ANSI 1252", "CP1252", "WINDOWS-1252": return .windowsCP1252
        default: return nil
        }
    }

}
