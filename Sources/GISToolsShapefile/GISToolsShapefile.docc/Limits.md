# Limits and Limitations

The ESRI Shapefile and dBase formats impose hard limits. Plan exports around
them, or use GeoPackage when attributes need more room.

## Format limits

| Limit | Value |
|-------|-------|
| Field-name length | 10 ASCII characters |
| Fields per table | 1,024 |
| Record size | 65,531 bytes |
| Character field size | 254 bytes |
| Numeric precision | up to 15 decimal places |
| `.shp` file size | ~2 GB practical (32-bit word offsets; tool-dependent) |

``ShapefileCoder/maximumFieldNameLength``,
``ShapefileCoder/maximumFieldCount``,
``ShapefileCoder/maximumRecordLength`` and
``ShapefileCoder/maximumCharacterFieldLength`` expose the values used by the
writer.

Field names longer than 10 characters are truncated. Collisions receive a
numeric suffix. Non-ASCII characters in property names become underscores.
Character values that exceed 254 bytes are truncated at a character boundary.

## Projection limits

Only EPSG:4326, EPSG:3857 and EPSG:4978 have built-in WKT templates. Writing
another projection throws ``ShapefileError/unsupportedProjection(_:)``. A
missing `.prj` is read as EPSG:4326; an invalid `.prj` throws rather than being
ignored.

EPSG:4978 (geocentric) coordinates require an altitude. Writing a geocentric
coordinate without one throws ``ShapefileError/invalidGeometry(_:)``.

## Geometry limits

- A shapefile contains one shape family. Points cannot be mixed with polygons,
  for example.
- MultiPatch is read as a `GeometryCollection` of `Polygon` values. Triangle
  strips and fans are decomposed into individual triangles.
- MultiPatch writing accepts `Polygon`, `MultiPolygon`, `LineString` and
  `MultiLineString` members of a `GeometryCollection`. Other members throw.
- Null shapes become features without a geometry.
- Deleted `.dbf` records are skipped.
- Blank `.dbf` fields and empty strings read back as `nil`; dBase cannot
  distinguish them from a missing value.
- Numeric values that do not fit their field are written as asterisks and read
  back as `nil`.

## Not implemented

- Memo (`.dbt`/`.fpt`) field contents: memo fields are returned as the raw
  block number string.
- AutoCAD Civil 3D and ArcGIS-specific shape types outside the ESRI
  specification.
- `.shx` validation on read: records are read sequentially from `.shp`.
- Automatic code-page detection beyond common `.cpg` labels. Pass
  `dbfEncoding` for other encodings.

## Empty and malformed files

An empty collection produces a valid empty `.shp` header, `.shx` header and
`.dbf` header. Truncated files, invalid file codes, negative or oversized
record lengths, and mismatched `.shp`/`.dbf` record counts throw
``ShapefileError`` instead of being silently truncated.
