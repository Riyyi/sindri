package chunks

import "base:runtime"
import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"

// -----------------------------------------

Writer :: struct {
	chunk_file:  ^os.File,
	asset_file:  ^os.File,
	asset_table: Asset_Table,
}

Write_Error :: enum u8 {
	None                 = 0,
	Chunk_Size_Too_Small = 1,
	Path_Too_Large       = 2,
	Unimplemented        = 127,
	Okay                 = None,
}

// -----------------------------------------

write_error_strings := #sparse[Write_Error]string { 	// enumerated array
	.None                 = "",
	.Chunk_Size_Too_Small = "chunk size too small to hold asset index",
	.Path_Too_Large       = "path exeeds maximum of 512",
	.Unimplemented        = "feature is unimplemented",
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
		size_of(Header) + (size_of(Asset_Index) * number_of_assets)
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
) -> (
	chunk_path: string,
	err: Error,
) {

	@(static) buf: [20]u8

	chunk_index_str := strconv.write_int(buf[:], cast(i64)chunk_index, 10)
	chunk_name := strings.concatenate({CHUNK, chunk_index_str}, allocator)
	defer delete(chunk_name, allocator)

	chunk_path = os.join_path({output_path, chunk_name}, allocator) or_return

	return chunk_path, nil // owning string
}
