package file

import "base:runtime"
import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"

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

Offsets :: struct {
	asset_index_offset: u64,
	data_offset:        u64,
	asset_offsets:      [dynamic]u64,
	asset_sizes:        [dynamic]u64,
}

// -----------------------------------------

@(private)
offsets: Offsets

// -----------------------------------------

compute_metadata_offsets :: proc(number_of_assets: u64) {
	// [ Header ][ []Asset Index ][ Data ]
	offsets.asset_index_offset = size_of(Header)
	offsets.data_offset =
		size_of(Header) + (size_of(AssetIndex) * number_of_assets)
}

@(private)
compute_chunk_path :: proc(
	output_path: string,
	chunk_index: int,
	allocator: runtime.Allocator,
) -> string {

	@(static) buf: [20]u8

	chunk_index_str := strconv.write_int(buf[:], cast(i64)chunk_index, 10)
	chunk_name := strings.concatenate({"CHUNK", chunk_index_str}, allocator)
	defer delete(chunk_name, allocator)

	chunk_path, c_err := os.join_path({output_path, chunk_name}, allocator)
	if c_err != nil {
		fmt.eprintln("error: chunk join path failed:", c_err)
		os.exit(1)
	}

	return chunk_path // owning string
}

delete_offsets :: proc() {
	delete(offsets.asset_offsets)
	delete(offsets.asset_sizes)
}
