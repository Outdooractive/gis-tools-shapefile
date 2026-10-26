# Reading Shapefiles

Understand the file components, projection detection, attribute decoding, and
the handling of malformed input.

## File components

`ShapefileCoder.read(from:)` derives every component from one base URL. A
`.shp` and a `.dbf` file are required; `.prj` and `.cpg` are optional. The
`.shx` index is not needed for sequential reading and is ignored by the reader.

```swift
let collection = try ShapefileCoder.read(
    from: URL(fileURLWithPath: "/data/cities.dbf"))
```

The base URL can use `.shp`, `.shx`, `.dbf`, `.prj`, `.cpg` or no extension.
The extension is matched case-insensitively.

## Projection detection

The `.prj` WKT is resolved through `GISTools`. If no `.prj` file exists,
EPSG:4326 is assumed. If a `.prj` file exists but cannot be recognised, reading
throws ``ShapefileError/unsupportedProjection(_:)`` instead of silently
mislabeling the coordinates.

The returned collection and its coordinates use the projection from the
`.prj` file. Coordinates without an SRID are copied verbatim.

## Attributes

`.dbf` records become `Feature.properties`. The default id column is `id`:
when a field with that name exists, its value is promoted to `Feature.id` and
removed from the properties. Pass `idColumn: nil` to keep it as a property, or
use another column name.

```swift
let collection = try ShapefileCoder.read(
    from: url,
    idColumn: "fid",
    dbfEncoding: .windowsCP1252)
```

When `dbfEncoding` is `nil`, the `.cpg` file is consulted and UTF-8 is used as
the fallback. Deleted `.dbf` records are skipped together with their geometry.
Null shapes become features without a geometry and keep their attributes.

## In-memory data

Use ``ShapefileCoder/read(shp:dbf:prj:calculateBoundingBox:idColumn:dbfEncoding:)``
when the components come from a network response or an archive:

```swift
let collection = try ShapefileCoder.read(
    shp: shpData,
    dbf: dbfData,
    prj: prjString,
    dbfEncoding: .utf8)
```

## Malformed input

Truncated headers, impossible record lengths, out-of-range part indexes and
inconsistent `.shp`/`.dbf` record counts throw ``ShapefileError``. The reader
never reads beyond a record's declared content, so a damaged file cannot cause
an out-of-bounds memory access.
