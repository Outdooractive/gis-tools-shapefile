# ``GISToolsShapefile``

Read and write ESRI Shapefiles from Swift.

## Overview

`GISToolsShapefile` maps the ESRI Shapefile file set to and from
`GISTools` feature collections:

| File | Contents |
|------|----------|
| `.shp` | Geometry records |
| `.dbf` | dBase attribute table |
| `.shx` | Fixed-size spatial index (written by this library) |
| `.prj` | Coordinate reference system as WKT (optional) |
| `.cpg` | `.dbf` code page (optional) |

```swift
import GISTools
import GISToolsShapefile

let collection = try ShapefileCoder.read(from: shapefileURL)
try collection.writeShapefile(to: outputURL)
```

The coder supports Point, MultiPoint, PolyLine, Polygon and MultiPatch
geometry, including Z and M variants. MultiPatch records are exposed as a
`GeometryCollection` of `Polygon` values.

## Topics

### Essentials

- ``ShapefileCoder``
- ``ShapefileData``
- ``ShapefileError``

### Guides

- <doc:GettingStarted>
- <doc:ReadingShapefiles>
- <doc:WritingShapefiles>
- <doc:Limits>
