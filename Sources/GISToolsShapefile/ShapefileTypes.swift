import Foundation
import GISTools

extension ShapefileCoder {

    /// The canonical "no data" value for measure (M) coordinates in
    /// Shapefiles (`-1e38`).
    ///
    /// Values less than or equal to this sentinel are treated as missing.
    static let noData: Double = -100_000_000_000_000_000_000_000_000_000_000_000_000.0

    /// Returns `true` when a measure value represents the shapefile no-data
    /// sentinel.
    static func isNoData(_ value: Double) -> Bool {
        !value.isFinite || value <= noData
    }

    /// Returns `true` when a Z value can be represented as a real altitude.
    static func isValidZ(_ value: Double) -> Bool {
        value.isFinite && value > noData
    }

    /// ESRI Shapefile shape types.
    enum ShapeType: Int {

        case nullShape = 0
        case point = 1
        case polyLine = 3
        case polygon = 5
        case multiPoint = 8
        case pointZ = 11
        case polyLineZ = 13
        case polygonZ = 15
        case multiPointZ = 18
        case pointM = 21
        case polyLineM = 23
        case polygonM = 25
        case multiPointM = 28
        case multiPatch = 31

        /// `true` when records of this type carry a Z range and Z array.
        var hasZ: Bool {
            switch self {
            case .multiPatch, .multiPointZ, .pointZ, .polygonZ, .polyLineZ: true
            default: false
            }
        }

        /// `true` when records of this type carry an M range and M array.
        ///
        /// Z shape types also carry an optional M block.
        var hasM: Bool {
            switch self {
            case .multiPointM, .pointM, .polygonM, .polyLineM: true
            case .multiPatch, .multiPointZ, .pointZ, .polygonZ, .polyLineZ: true
            default: false
            }
        }

        /// The shape family without Z or M suffixes.
        var baseType: ShapeType {
            switch self {
            case .pointM, .pointZ: .point
            case .polyLineM, .polyLineZ: .polyLine
            case .polygonM, .polygonZ: .polygon
            case .multiPointM, .multiPointZ: .multiPoint
            default: self
            }
        }

    }

    /// MultiPatch part types.
    enum MultiPatchPartType: Int {

        case triangleStrip = 0
        case triangleFan = 1
        case outerRing = 2
        case innerRing = 3
        case firstRing = 4
        case ring = 5

    }

    /// dBase field types that this implementation reads or writes.
    enum DbfFieldType: Character {

        case character = "C"
        case numeric = "N"
        case logical = "L"
        case date = "D"
        case float = "F"
        case memo = "M"

    }

    /// A `.dbf` field descriptor.
    struct DbfFieldDescriptor {

        /// The name stored in the `.dbf` file (at most 10 ASCII characters).
        let name: String

        /// The feature property backing this field, or `nil` for the id column.
        let propertyKey: String?

        /// The dBase data type.
        let type: DbfFieldType

        /// The field width in bytes (`1 ... 254`).
        let length: Int

        /// The number of decimal places for numeric fields.
        let decimalCount: Int

    }

    /// A row read from a `.dbf` file.
    struct DbfRecord {

        let id: Feature.Identifier?
        let properties: [String: Sendable]

    }

}

/// Minimum and maximum values for a single axis.
struct ValueRange {

    private(set) var minimum: Double?
    private(set) var maximum: Double?

    mutating func add(_ value: Double?) {
        guard let value, value.isFinite else { return }

        minimum = min(minimum ?? value, value)
        maximum = max(maximum ?? value, value)
    }

    var minOrZero: Double {
        minimum ?? 0.0
    }

    var maxOrZero: Double {
        maximum ?? 0.0
    }

}

/// Minimum and maximum X/Y values.
struct BoundingBoxValues {

    private(set) var minX: Double?
    private(set) var minY: Double?
    private(set) var maxX: Double?
    private(set) var maxY: Double?

    mutating func add(_ coordinate: Coordinate3D) {
        guard coordinate.longitude.isFinite, coordinate.latitude.isFinite else { return }

        minX = Swift.min(minX ?? coordinate.longitude, coordinate.longitude)
        maxX = Swift.max(maxX ?? coordinate.longitude, coordinate.longitude)
        minY = Swift.min(minY ?? coordinate.latitude, coordinate.latitude)
        maxY = Swift.max(maxY ?? coordinate.latitude, coordinate.latitude)
    }

    mutating func add(_ coordinates: [Coordinate3D]) {
        for coordinate in coordinates {
            add(coordinate)
        }
    }

    var minXOrZero: Double {
        minX ?? 0.0
    }

    var minYOrZero: Double {
        minY ?? 0.0
    }

    var maxXOrZero: Double {
        maxX ?? 0.0
    }

    var maxYOrZero: Double {
        maxY ?? 0.0
    }

}
