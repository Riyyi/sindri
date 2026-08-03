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
		offset_pointer := mem.ptr_offset(&bytes[0], offset_in_bytes)

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

write_header :: proc(
	output: ^os.File,
	header: Header,
	asset_index: []AssetIndex,
	allocator := context.allocator,
) {
	// remove :: proc(name: string) -> Error {…}
	// create :: proc(name: string) -> (^File, Error) {…}
	// write_at :: proc(f: ^File, p: []u8, offset: i64) -> (n: int, err: Error) {…}

	output_path := os.name(output)

	chunk_1, c1_err := os.join_path({output_path, "CHUNK1"}, allocator)
	if c1_err != nil {
		fmt.eprintln("error: failed to allocate path join:", c1_err)
		os.exit(1)
	}

	// Remove old chunk 1
	if os.exists(chunk_1) {
		rm_err := os.remove(chunk_1)
		if rm_err != nil {
			fmt.eprintln("error: failed to remove old chunk:", rm_err)
			os.exit(1)
		}
	}

	// Create chunk 1
	chunk_file_1, cf1_err := os.create(chunk_1)
	if cf1_err != nil {
		fmt.eprintln("error: failed to create chunk:", cf1_err)
		os.exit(1)
	}

	// Write header
	header := header // shadow parameter
	header_bytes := mem.ptr_to_bytes(&header)
	os.write_at(chunk_file_1, header_bytes, 0)

	// Write asset index
	asset_index := asset_index // shadow parameter
	index_bytes := mem.slice_data_cast([]u8, asset_index) // transmute slice with proper size
	os.write_at(chunk_file_1, index_bytes, size_of(Header))
}
