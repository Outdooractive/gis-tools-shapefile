[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2FOutdooractive%2Fgis-tools-shapefile%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/Outdooractive/gis-tools-shapefile)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2FOutdooractive%2Fgis-tools-shapefile%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/Outdooractive/gis-tools-shapefile)
[![](https://img.shields.io/github/license/Outdooractive/gis-tools-shapefile)](https://github.com/Outdooractive/gis-tools-shapefile/blob/main/LICENSE)  
[![](https://img.shields.io/github/v/release/Outdooractive/gis-tools-shapefile?sort=semver&display_name=tag)](https://github.com/Outdooractive/gis-tools-shapefile/releases) [![](https://img.shields.io/github/release-date/Outdooractive/gis-tools-shapefile?display_date=published_at)](https://github.com/Outdooractive/gis-tools-shapefile/releases)  
[![](https://img.shields.io/github/issues/Outdooractive/gis-tools-shapefile)](https://github.com/Outdooractive/gis-tools-shapefile/issues) [![](https://img.shields.io/github/issues-pr/Outdooractive/gis-tools-shapefile)](https://github.com/Outdooractive/gis-tools-shapefile/pulls)

# GISToolsShapefile

ESRI Shapefile (`.shp`/`.dbf`/`.shx`/`.prj`) read and write support for Swift, built on top of [**gis-tools**](https://github.com/Outdooractive/gis-tools).

## Features

- Reads and writes Point, PolyLine, Polygon, MultiPoint, and MultiPatch geometry, including Z and M variants
- Reads `.prj` files to determine the source projection (EPSG:4326 assumed if absent)
- Writes `.prj` files for EPSG:4326, EPSG:3857 and EPSG:4978
- Attributes are mapped to and from `Feature.properties` via the companion `.dbf` file
- Feature ids are mapped to and from a dedicated `id` column (configurable)
- Writes `.shx` index files and `.cpg` code-page files
- Multipatch geometries are decomposed into `GeometryCollection` values with `Polygon` parts
- Null shapes become features without a geometry and keep their attributes
- Deleted `.dbf` records are skipped together with their geometry

## Requirements

Swift 6.1 or higher. Compiles on iOS (≥ iOS 15), macOS (≥ macOS 15), tvOS (≥ tvOS 15), watchOS (≥ watchOS 7), Linux, Android and Wasm.

## Installation with Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/Outdooractive/gis-tools", from: "3.0.0"),
    .package(url: "https://github.com/Outdooractive/gis-tools-shapefile", from: "3.0.0"),
],
targets: [
    .target(name: "MyTarget", dependencies: [
        .product(name: "GISTools", package: "gis-tools"),
        .product(name: "GISToolsShapefile", package: "gis-tools-shapefile"),
    ]),
]
```

## Usage

### Reading

```swift
import GISTools
import GISToolsShapefile

let url = URL(fileURLWithPath: "/path/to/file") // or ".../file.shp"

// Failable convenience initializer:
if let fc = FeatureCollection(shapefile: url) {
    print(fc.features.count)
}

// Or via ShapefileCoder directly, which reports errors:
let fc = try ShapefileCoder.read(from: url)
```

The failable `FeatureCollection(shapefile:)` initializer returns `nil` on any
error. Use `ShapefileCoder.read` when you need the underlying error.

`read` accepts optional `idColumn` and `dbfEncoding` parameters. When
`dbfEncoding` is `nil`, a `.cpg` file is consulted and UTF-8 is used as the
fallback. A column named `id` is promoted to `Feature.id` by default; pass
`idColumn: nil` to keep it as a property.

### Writing

```swift
import GISTools
import GISToolsShapefile

let url = URL(fileURLWithPath: "/path/to/new_file")
try fc.writeShapefile(to: url)

// Or via ShapefileCoder directly:
try ShapefileCoder.write(fc, to: url)
```

The shapefile path is constructed from the base URL by replacing the extension:

| Extension | Contents |
|-----------|----------|
| `.shp` | Geometry data |
| `.dbf` | Attribute data |
| `.shx` | Spatial index |
| `.prj` | Projection string |
| `.cpg` | `.dbf` code page |

Coordinates are written verbatim in the collection's projection. Project the
collection first when a specific output CRS is required:

```swift
try fc.projected(to: .epsg3857).writeShapefile(to: url)
```

### In-memory data

```swift
let data = try ShapefileCoder.encode(fc)
let fc = try ShapefileCoder.read(
    shp: data.shp,
    dbf: data.dbf,
    prj: data.prj)
```

### Errors

All failures throw `ShapefileError` (also available under the compatibility
name `ShapefileCoder.ShapefileCoderError`). Truncated files, invalid headers,
unsupported shape types and mismatched `.shp`/`.dbf` record counts are reported
instead of being silently truncated.

## Limitations

- Maximum field count: 1024 (library limit)
- Maximum record size: 65531 bytes (library limit)
- Field name length: maximum 10 ASCII characters; longer names are truncated, non-ASCII characters become underscores, and collisions receive a numeric suffix
- Character field values longer than 254 bytes are truncated
- Numeric values support up to 15 decimal places
- A shapefile contains one shape family; mixed geometry types throw
- All features in a file must use the same projection
- GeoJSON `Feature.id` values are mapped to an `id` column by default
- MultiPatch is read as a `GeometryCollection`; triangle strips and fans are decomposed into triangles
- Writing a projection without a built-in WKT template (anything other than EPSG:4326, 3857 and 4978) throws
- An invalid `.prj` file throws instead of being ignored
- Blank `.dbf` fields and empty strings read back as `nil`
- Numeric values that do not fit their field are written as asterisks and read back as `nil`
- Memo (`.dbt`/`.fpt`) field contents are not resolved
- AutoCAD Civil 3D and ArcGIS-specific variants are not supported

See the DocC documentation in `Sources/GISToolsShapefile/GISToolsShapefile.docc` for detailed articles.

## Development

```bash
swift test
swift test --enable-code-coverage
python3 scripts/coverage_report.py --minimum 90
python3 scripts/check_documentation.py
```

The CI workflow runs the tests on macOS and Linux, enforces 90% line coverage on
Linux, and builds the DocC catalog with warnings treated as errors.

## Contributing

Please [create an issue](https://github.com/Outdooractive/gis-tools-shapefile/issues) or [open a pull request](https://github.com/Outdooractive/gis-tools-shapefile/pulls) with a fix or enhancement.

## License

MIT

## Authors

Thomas Rasch, Outdooractive

Built on top of [**gis-tools**](https://github.com/Outdooractive/gis-tools).
