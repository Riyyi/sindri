# Design

The data layout design is very simple. It consists of data split into chunks
with the first chunk holding the metadata for the structure and assets.

## Spec

```
                                         METADATA                                           DATA
|----------------------------------------------------------------------------------------||------|

[ MAGIC ][ VERSION ][ COMPRESSION ][ SIZE_PER_CHUNK ][ TOTAL_SIZE ][ #ASSETS ][ []ASSETS ][ DATA ] # chunk 1
[                                              DATA                                              ] # chunk 2
[                                              DATA                                              ] # etc..
[       DATA       ]                                                                               # last chunk
```

### Magic string

Magic string to detect if the read file is what we expect it is.
Represented in 4 bytes.

Value is `0x514D21`, the closest approximation of "Sindri".

### Version

Version of the specification.
Represented in `2 bytes`.

Value is `1` currently.

### Compression

Wether LZ4 compression is enabled/disabled.
Represented in `2 byte`.

Value is configurable, defaulting to `0`.

`0` = off<br>
`1` = default LZ4 algorithm<br>
`2` = lowest LZ4-HC algorithm, faster and larger<br>
..<br>
`12` = highest LZ4-HC algorithm, slower and smaller

### Size per chunks

The size in bytes of each chunk.
Represented in `8 bytes`.

Value is configurable, defaulting to `2GiB`.

### Total size

The total size in bytes of all chunks combined.
Represented in `8 bytes`.

### Number of assets

The total number of assets in the pack.
Represented in `4 bytes`.

### []Asset

Index to piece of stored data, consisting of 3 parts:

- Path
- Size
- Offset

#### Path

Path of the asset as if it were on the filesystem.
Represented in `512 bytes`.

#### Size

Size of the asset.
Represented in `8 bytes`.

#### Offset

The offset to the asset, starting from the true 0th byte of the first chunk.
Represented in `8 bytes`.
