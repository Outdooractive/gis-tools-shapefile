# Writing Shapefiles

Map feature collections to `.shp`, `.dbf`, `.shx`, `.prj` and `.cpg` files.

## Basic writing

```swift
try collection.writeShapefile(to: URL(fileURLWithPath: "/data/output"))
```

or use the coder directly:

```swift
try ShapefileCoder.write(collection, to: outputURL)
```

The writer creates a valid `.dbf` even for an empty collection and removes a
stale `.prj` or `.cpg` file that the new output does not need.

## Projections

Coordinates are written verbatim in `FeatureCollection.projection`; they are
not reprojected implicitly. Project the collection first when a specific output
CRS is required:

```swift
let webMercator = collection.projected(to: .epsg3857)
try webMercator.writeShapefile(to: outputURL)
```

The `.prj` file is written for EPSG:4326, EPSG:3857 and EPSG:4978. A collection
without an SRID is written without a `.prj`. Any other SRID throws
``ShapefileError/unsupportedProjection(_:)`` because the library has no WKT
template for it.

All non-null geometries in a file must use the same shape family and the same
projection. Mixed collections throw ``ShapefileError/mixedGeometryTypes`` or
``ShapefileError/mixedProjections``. Null geometries are allowed and are
written as null shapes.

## Attributes and ids

Feature properties become `.dbf` fields:

| Swift value | dBase type |
|-------------|------------|
| `String` | `C` (character) |
| `Bool` | `L` (logical) |
| Integer types | `N` with zero decimals |
| `Double`, `Float` | `N` with up to 15 decimals |
| `Date` | `D` (`yyyyMMdd`, UTC) |
| other values | `C` using the value's description |

`Feature.id` is written to the `id` column by default. Pass
`idColumn: nil` to omit ids, or another valid dBase name to choose a different
column. A property that uses the same name as the id column throws
``ShapefileError/idColumnConflict(_:)``.

Field names longer than 10 characters are truncated and made unique. Character
values longer than 254 bytes are truncated. Missing values are written as
blank fields and read back as `nil`.

## Round-trip guarantees

- Point, MultiPoint, PolyLine, Polygon and MultiPatch geometry survives a
  round trip, including Z and M values.
- Polygon rings are normalised to the shapefile convention (outer rings
  clockwise, holes counter-clockwise).
- Null Z and M values use the shapefile no-data sentinel and read back as
  `nil`.
- Empty lines and polygons are written as null shapes.
- Empty `MultiPoint` values are written as a MultiPoint record with zero
  points.

## In-memory data

Use ``ShapefileCoder/encode(_:encoding:idColumn:)`` to obtain the individual
file contents as ``ShapefileData``:

```swift
let data = try ShapefileCoder.encode(collection)
try data.shp.write(to: shpURL)
try data.dbf.write(to: dbfURL)
try data.shx.write(to: shxURL)
```
