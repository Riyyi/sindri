package chunks

import "base:runtime"
import "core:fmt"
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

// -----------------------------------------

@(require_results)
format_error :: proc(ferr: Error) -> string {
	if ferr == nil do return ""

	switch e in ferr {
		case nil:
			return ""
		case runtime.Allocator_Error:
			return fmt.tprintf("allocator: {}", e)
		case io.Error:
			return fmt.tprintf("io: {}", e)
		case os.Error:
			return fmt.tprintf("os: {}", e)
		case Read_Error:
			return fmt.tprintf("chunks: {}", read_error_strings[e])
		case Write_Error:
			return fmt.tprintf("chunks: {}", write_error_strings[e])
	}

	return "unknown error"
}
