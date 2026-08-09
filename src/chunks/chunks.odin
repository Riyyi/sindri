package chunks

import "base:runtime"
import "core:io"
import "core:os"

MAGIC_STRING :: 0x514D21 // SINDRI
VERSION :: 1
COMPRESSION :: 0
SIZE_PER_CHUNK :: 2 * (1 << 30) // 2GiB
PATH_SIZE :: 512
CHUNK :: "CHUNK"

// -----------------------------------------

Header :: struct #packed #all_or_none {
	magic_string:     u32,
	version:          u16,
	compression:      u16,
	size_per_chunk:   u64,
	total_size:       u64,
	number_of_assets: u32,
}

Asset_Index :: struct #packed #all_or_none {
	relpath: [PATH_SIZE]u8,
	size:    u64,
	offset:  u64,
}

Asset_Table :: struct {
	asset_index_offset: u64,
	data_offset:        u64,
	asset_offsets:      [dynamic]u64,
	asset_sizes:        [dynamic]u64,
}

Error :: union #shared_nil {
	runtime.Allocator_Error,
	io.Error,
	os.Error,
	Read_Error,
	Write_Error,
}
