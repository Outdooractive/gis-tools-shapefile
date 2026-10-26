import Foundation

/// Errors thrown while reading or writing ESRI Shapefiles.
///
/// The error type is also available as ``ShapefileCoder/ShapefileCoderError``
/// for source compatibility with earlier releases.
public enum ShapefileError: Error, LocalizedError, Equatable, Sendable {

    /// The `.shp` file does not start with the ESRI file code `9994`.
    case invalidFileCode

    /// The shape type stored in the file header or a record is not supported.
    case unsupportedShapeType(Int)

    /// A record is truncated, has inconsistent lengths, or contains invalid indices.
    case corruptedRecord

    /// The `.dbf` header or a field descriptor is invalid.
    case invalidDbfHeader(String)

    /// A `.dbf` field uses a type that this implementation cannot read.
    case unsupportedDbfFieldType(Character)

    /// A file could not be read from or written to disk.
    case ioError(String)

    /// The `.shp` file length field is invalid or exceeds the available data.
    case invalidFileLength(Int)

    /// The `.shp` version field is not `1000`.
    case unsupportedVersion(Int)

    /// A collection contains more than one shape family (for example points and polygons).
    case mixedGeometryTypes

    /// Features use different coordinate reference systems.
    case mixedProjections

    /// A geometry cannot be represented by the shape type being written.
    case invalidGeometry(String)

    /// The configured id column is also used as a regular property.
    case idColumnConflict(String)

    /// A `.dbf` table exceeds the supported field count.
    case tooManyFields(Int)

    /// A `.dbf` record exceeds the supported byte size.
    case recordTooLarge(Int)

    /// A `.dbf` field name is not a valid dBase identifier.
    case invalidFieldName(String)

    /// The `.shp` and `.dbf` files contain a different number of records.
    case recordCountMismatch(shp: Int, dbf: Int)

    /// A shapefile would exceed the 32-bit file size limit.
    case fileTooLarge

    /// The projection has no WKT representation in this library, or a `.prj`
    /// string could not be recognised.
    case unsupportedProjection(String)

    /// A string could not be encoded with the requested `.dbf` encoding.
    case unsupportedEncoding(String)

    /// A human-readable description of the error.
    public var errorDescription: String? {
        switch self {
        case .invalidFileCode:
            "Not an ESRI Shapefile: the .shp file code is not 9994"
        case let .unsupportedShapeType(type):
            "Unsupported shapefile shape type \(type)"
        case .corruptedRecord:
            "The shapefile contains a corrupted record"
        case let .invalidDbfHeader(detail):
            "Invalid .dbf header: \(detail)"
        case let .unsupportedDbfFieldType(type):
            "Unsupported .dbf field type '\(type)'"
        case let .ioError(detail):
            "Shapefile I/O error: \(detail)"
        case let .invalidFileLength(length):
            "Invalid .shp file length \(length)"
        case let .unsupportedVersion(version):
            "Unsupported shapefile version \(version), expected 1000"
        case .mixedGeometryTypes:
            "A shapefile can only contain one geometry family"
        case .mixedProjections:
            "All features must use the same projection"
        case let .invalidGeometry(detail):
            "Geometry cannot be written to a shapefile: \(detail)"
        case let .idColumnConflict(column):
            "The id column '\(column)' is also used as a property"
        case let .tooManyFields(count):
            "Too many .dbf fields (\(count)); the maximum is 1024"
        case let .recordTooLarge(length):
            "The .dbf record length \(length) exceeds the maximum of 65531 bytes"
        case let .invalidFieldName(name):
            "Invalid .dbf field name '\(name)'"
        case let .recordCountMismatch(shp, dbf):
            "The .shp file has \(shp) records but the .dbf file has \(dbf)"
        case .fileTooLarge:
            "The shapefile exceeds the 32-bit file size limit"
        case let .unsupportedProjection(detail):
            "Unsupported projection: \(detail)"
        case let .unsupportedEncoding(detail):
            "Unsupported .dbf encoding: \(detail)"
        }
    }

}
