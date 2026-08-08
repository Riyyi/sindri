package chunks

import "base:runtime"
import "core:fmt"
import "core:io"
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

AssetTable :: struct {
	asset_index_offset: u64,
	data_offset:        u64,
	asset_offsets:      [dynamic]u64,
	asset_sizes:        [dynamic]u64,
}

Writer :: struct {
	chunk_file:  ^os.File,
	asset_file:  ^os.File,
	asset_table: AssetTable,
}

Error :: union #shared_nil {
	io.Error,
	os.Error,
	Read_Error,
}

// -----------------------------------------

writer_init :: proc(
	number_of_assets: u64,
	allocator := context.allocator,
) -> (
	w: Writer,
	err: runtime.Allocator_Error,
) #optional_allocator_error {
	// [ Header ][ []Asset Index ][ Data ]
	w.asset_table.asset_index_offset = size_of(Header)
	w.asset_table.data_offset =
		size_of(Header) + (size_of(AssetIndex) * number_of_assets)
	w.asset_table.asset_offsets = make([dynamic]u64, allocator) or_return
	w.asset_table.asset_sizes = make([dynamic]u64, allocator) or_return
	resize(&w.asset_table.asset_offsets, number_of_assets)
	resize(&w.asset_table.asset_sizes, number_of_assets)
	return w, nil
}

writer_destroy :: proc(w: ^Writer) {
	if w.chunk_file != nil do os.close(w.chunk_file)
	if w.asset_file != nil do os.close(w.asset_file)
	delete(w.asset_table.asset_offsets)
	delete(w.asset_table.asset_sizes)
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
