# Getting Started

Add the package, read a shapefile, and write it back.

## Installation

Add both the core library and the shapefile companion to your package
dependencies:

```swift
dependencies: [
    .package(
        url: "https://github.com/Outdooractive/gis-tools",
        from: "3.0.0-beta.5"),
    .package(
        url: "https://github.com/Outdooractive/gis-tools-shapefile",
        from: "3.0.0-beta.1"),
],
targets: [
    .target(
        name: "MyTarget",
        dependencies: [
            .product(name: "GISTools", package: "gis-tools"),
            .product(name: "GISToolsShapefile", package: "gis-tools-shapefile"),
        ]),
]
```

The package requires Swift 6.1 or newer.

## Reading

Pass the base path, a `.shp` URL, or any other component URL:

```swift
import GISTools
import GISToolsShapefile

if let collection = FeatureCollection(shapefile: URL(fileURLWithPath: "/data/cities")) {
    print(collection.features.count)
}
```

The failable initializer returns `nil` on any error. To see the error, use the
coder directly:

```swift
do {
    let collection = try ShapefileCoder.read(
        from: URL(fileURLWithPath: "/data/cities"))
    print(collection.features.count)
}
catch {
    print(error)
}
```

## Writing

```swift
let output = URL(fileURLWithPath: "/data/cities_copy")
try collection.writeShapefile(to: output)
```

This writes `cities_copy.shp`, `cities_copy.dbf`, `cities_copy.shx`, a `.cpg`
file, and a `.prj` file when the collection's projection has a WKT
representation.

## Next Steps

- <doc:ReadingShapefiles>
- <doc:WritingShapefiles>
- <doc:Limits>
