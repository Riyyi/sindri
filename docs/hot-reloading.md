# Hot Reloading

Instead of having the engine as an exe and game as a dll, and having to jump
through hoops to share libraries internal state between them we do it
differently. The engine and game live in the same binary, compiled fully each
time. We rely mostly on static memory, and register these memory regions. Then
when we want to hot reload: we send a close signal to the running instance, it
writes a snapshot of the active memory to disk, instance closes, recompile,
restart the application, it restores the memory from the snapshot.

## Byte Layout On Disk

```odin
Snapshot_Header :: struct #packed #all_or_none {
	magic_string:     u32,
	version:          u16, // spec of the snapshot
    app_version:      [4 + time.MIN_YYYY_DATE_LEN + 8]u8, // example: `dev-2026-09-23-a4084b3`
    region_count:     u32,
}

Region_Header :: struct #packed #all_or_none {
	name_size: u32,
	data_size: u32,
}
```

[ Snapshot_Header  ]
[ Region_Header    ]
[   name bytes     ]
[   data bytes     ]
[ Region_Header    ]
[   name bytes     ]
[   data bytes     ]
[ etc..            ]

## Diff Checking

Use hashing per memory segment to do a sanity diff-check.

```odin
import "core:crypto/hash"

data: []byte = ...

digest := hash.hash_bytes(hash.Algorithm.SHA256, data)
defer delete(digest)
```
