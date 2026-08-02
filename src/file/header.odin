package file

import "core:fmt"
import "core:mem"
import "core:os"

MAGIC_STRING :: 0x514D21 // SINDRI
VERSION :: 1
COMPRESSION :: 0
SIZE_PER_CHUNK :: 2 * (1 << 30) // 2GiB
PATH_SIZE :: 512

// -----------------------------------------

Header :: struct #packed #all_or_none {
	magic_string:     u32,
	version:          u16,
	compression:      u16,
	size_per_chunk:   u64,
	total_size:       u64,
	number_of_assets: u32,
	// asset_index:      []AssetIndex,
}

AssetIndex :: struct #packed #all_or_none {
	relpath: [PATH_SIZE]u8,
	size:    u64,
	offset:  u64,
}

// -----------------------------------------

// remove :: proc(name: string) -> Error {…}
// create :: proc(name: string) -> (^File, Error) {…}
// write_at :: proc(f: ^File, p: []u8, offset: i64) -> (n: int, err: Error) {…}

// Returning `[]u8` is owned by the caller.
compute_header :: proc(
	entries: [dynamic]FileEntry,
	compression: u16 = COMPRESSION,
	size_per_chunk: u64 = SIZE_PER_CHUNK,
	allocator := context.allocator,
) -> (
	header: Header,
	asset_index: []AssetIndex,
) {
	number_of_assets := cast(u32)len(entries)

	index_size: u64 = size_of(AssetIndex) * cast(u64)number_of_assets
	data_offset: u64 = size_of(Header) + index_size
	total_size: u64 = data_offset

	bytes := make([]u8, index_size, allocator)

	for f, i in entries {

		path_length := len(f.relpath)
		if path_length > 512 {
			fmt.eprintln("error: path exeeds maximum of 512:", f.relpath)
			os.exit(1)
		}

		offset_in_bytes := size_of(AssetIndex) * cast(u64)i
		offset_pointer := mem.ptr_offset(
			&bytes[0],
			offset_in_bytes,
		)

		ai := cast(^AssetIndex)offset_pointer
		copy(ai.relpath[:PATH_SIZE], f.relpath)
		ai.size = cast(u64)f.size
		ai.offset = data_offset
		data_offset += ai.size

		total_size += ai.size
	}

	header = Header {
		magic_string     = MAGIC_STRING,
		version          = VERSION,
		compression      = compression,
		size_per_chunk   = size_per_chunk,
		total_size       = total_size,
		number_of_assets = number_of_assets,
	}

	assert(len(bytes) % size_of(AssetIndex) == 0) // clean multiple
	return header, mem.slice_data_cast([]AssetIndex, bytes) // transmute slice with proper size
}
