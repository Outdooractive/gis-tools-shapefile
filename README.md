[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2FOutdooractive%2Fgis-tools-shapefile%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/Outdooractive/gis-tools-shapefile)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2FOutdooractive%2Fgis-tools-shapefile%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/Outdooractive/gis-tools-shapefile)
[![](https://img.shields.io/github/license/Outdooractive/gis-tools-shapefile)](https://github.com/Outdooractive/gis-tools-shapefile/blob/main/LICENSE)  
[![](https://img.shields.io/github/v/release/Outdooractive/gis-tools-shapefile?sort=semver&display_name=tag)](https://github.com/Outdooractive/gis-tools-shapefile/releases) [![](https://img.shields.io/github/release-date/Outdooractive/gis-tools-shapefile?display_date=published_at)](https://github.com/Outdooractive/gis-tools-shapefile/releases)  
[![](https://img.shields.io/github/issues/Outdooractive/gis-tools-shapefile)](https://github.com/Outdooractive/gis-tools-shapefile/issues) [![](https://img.shields.io/github/issues-pr/Outdooractive/gis-tools-shapefile)](https://github.com/Outdooractive/gis-tools-shapefile/pulls)

# GISToolsShapefile

ESRI Shapefile (.shp/.dbf/.shx/.prj) read and write support for Swift, built on top of [**gis-tools**](https://github.com/Outdooractive/gis-tools).

## Features

- Reads and writes Point, PolyLine, Polygon, MultiPoint, and MultiPatch geometry types, including Z and M variants
- Reads `.prj` files to determine the source projection (EPSG:4326 assumed if absent)
- Writes `.prj` files matching the output projection
- Attributes are mapped to and from `Feature.properties` via the companion `.dbf` file
- Writes `.shx` index files for compatibility with tools that require them
- Multipatch geometries are decomposed into `GeometryCollection` with `Polygon` parts

## Requirements

Swift 6.1 or higher. Compiles on iOS (≥ iOS 15), macOS (≥ macOS 15), tvOS (≥ tvOS 15), watchOS (≥ watchOS 7), Linux, Android and Wasm.

## Installation with Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/Outdooractive/gis-tools-shapefile", from: "1.0.1"),
    .package(url: "https://github.com/Outdooractive/gis-tools", from: "2.0.0"),
],
targets: [
    .target(name: "MyTarget", dependencies: [
        .product(name: "GISToolsShapefile", package: "gis-tools-shapefile"),
        .product(name: "GISTools", package: "gis-tools"),
    ]),
]
```

## Usage

### Reading

```swift
import GISTools
import GISToolsShapefile

let url = URL(fileURLWithPath: "/path/to/file.shp")
let fc = try FeatureCollection(shapefile: url)

// Or via ShapefileCoder directly:
let fc = try ShapefileCoder.read(from: url)
```

### Writing

```swift
import GISTools
import GISToolsShapefile

let url = URL(fileURLWithPath: "/path/to/new_file.shp")
try fc.writeShapefile(to: url)

// Or via ShapefileCoder directly:
try ShapefileCoder.write(fc, to: url)
```

The shapefile path is constructed from the base URL by replacing the extension:
- `.shp` — geometry data
- `.dbf` — attribute data
- `.shx` — spatial index
- `.prj` — projection string

### Limitations

- GeoJSON `id` values are mapped to an `id` column in the `.dbf` file
- Maximum field count: 1024 per dBase specification
- Maximum record size: 65531 bytes per dBase specification
- Field name length: maximum 10 characters per dBase specification
- Multipatch geometry is read-only (converted to `GeometryCollection`)
- AutoCAD Civil 3D and ArcGIS variants are not supported

## Contributing

Please [create an issue](https://github.com/Outdooractive/gis-tools-shapefile/issues) or [open a pull request](https://github.com/Outdooractive/gis-tools-shapefile/pulls) with a fix or enhancement.

## License

MIT

## Authors

Thomas Rasch, Outdooractive

Built on top of [**gis-tools**](https://github.com/Outdooractive/gis-tools).
