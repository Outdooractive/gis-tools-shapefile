# Changelog

## Unreleased

### Fixed

- **Projections are preserved.** Reading now tags coordinates with the CRS
  from `.prj` instead of treating them as EPSG:4326 and reprojecting them.
  Writing uses the collection's projection verbatim and writes a matching
  `.prj`; EPSG:3857 round-trips correctly.
- **Z and M arrays.** PolyLine, Polygon, MultiPoint and MultiPatch readers now
  skip both `Zmin`/`Zmax` (and `Mmin`/`Mmax`) before the value array. The old
  reader was shifted by one value.
- **Bounding boxes and ranges.** The `.shp`/`.shx` header bounding box is
  computed from the coordinates instead of relying on a precomputed
  `BoundingBox`, and the header Z/M ranges are populated.
- **dBase 16-bit lengths.** Header and record lengths are written and read as
  unsigned 16-bit values, so 1024-field tables (`32801`-byte header) no longer
  overflow.
- **Deleted `.dbf` records.** Deleted rows no longer shift the attributes of
  all following features out of alignment.
- **Malformed `.shp` records.** Negative or zero content lengths no longer
  loop forever, and every record read is bounds-checked against the record's
  declared content. Truncated files throw `ShapefileError`.
- **Polygon rings.** Outer rings are written clockwise and holes
  counter-clockwise. Reads group holes correctly and tolerate reversed
  third-party files.
- **Ids.** `Feature.id` is written to and read from the `id` column. A
  configurable `idColumn` is available.
- **Field names.** Names longer than 10 characters are truncated and made
  unique; non-ASCII names are sanitised; empty names become `field`.
- **Field values.** Non-ASCII text no longer collapses to blanks. Character
  and numeric fields are truncated/padded in bytes, and overlong numerics use
  the dBase asterisk overflow marker.
- **Empty output.** An empty collection now produces a valid empty `.dbf`
  table instead of a zero-byte file.
- **Mixed input.** Mixed geometry families and projections throw instead of
  producing an invalid shapefile.
- **Null geometries.** Features without a geometry are written as null shapes
  and read back as unlocated features with their attributes.
- **Stale files.** Writing a collection without a `.prj` removes an old
  `.prj`, and `.cpg` files are kept in sync with the selected encoding.
- **`.shx` offsets** are covered by tests that verify every index entry points
  at the corresponding `.shp` record header.
- **Case-insensitive components.** Upper-case component extensions (`.SHP`,
  `.DBF`, `.PRJ`, `.CPG`, …) are readable on case-sensitive file systems.
- **`Data` slices.** In-memory reads now work when the supplied `Data` values
  have a non-zero `startIndex`.

### Added

- `ShapefileError` with `LocalizedError` descriptions. The old nested name
  `ShapefileCoder.ShapefileCoderError` remains available as a type alias.
- `ShapefileData` and `ShapefileCoder.encode(_:encoding:idColumn:)` for
  in-memory workflows.
- `ShapefileCoder.read(shp:dbf:prj:...)` for in-memory reading.
- `idColumn` and `dbfEncoding` options on reading and writing.
- `.cpg` code-page support for UTF-8, ASCII, ISO-8859-1 and Windows-1252.
- Public constants `maximumFieldCount`, `maximumRecordLength`,
  `maximumFieldNameLength` and `maximumCharacterFieldLength`.
- A DocC catalog with getting-started, reading, writing and limits articles.
- 107 tests (up from 9 active tests) covering headers, records, DBF
  descriptors, encodings, ids, malformed files and all four projections.
- CI coverage reporting and a DocC build with diagnostics treated as errors.

### Changed

- Reading a shapefile now returns coordinates in the `.prj` projection, not in
  EPSG:4326. Callers that relied on the previous (incorrect) behavior should
  call `.projected(to:)` explicitly.
- A present but invalid `.prj` throws `unsupportedProjection` instead of
  silently assuming EPSG:4326.
- Writing a projection without a WKT template throws `unsupportedProjection`.
- Reading an empty `.dbf` file throws `invalidDbfHeader`; the writer no longer
  produces one.
- Date properties are written as dBase `D` fields (`yyyyMMdd`, UTC) and read
  back as strings.
- The `encoding` parameter documents `.dbf` text encoding; `.prj` files are
  always written as UTF-8.
