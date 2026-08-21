package chunks

import "base:runtime"
import "core:fmt"
import "core:mem"
import "core:os"

import "src:file"

// -----------------------------------------

write_metadata :: proc(
	w: ^Writer,
	output: ^os.File,
	entries: []file.File_Entry,
	size_per_chunk: u64 = SIZE_PER_CHUNK,
	compression: u16 = COMPRESSION,
	allocator := context.allocator,
) -> Error {
	output_path := os.name(output)
	number_of_assets := cast(u32)len(entries)

	// ----------------------------------------

	chunk_path := compute_chunk_path(output_path, 0, allocator) or_return
	defer delete(chunk_path, allocator)
	chunk_file := os.open(chunk_path, {.Read, .Write}) or_return
	defer os.close(chunk_file)

	write_header(w, chunk_file, number_of_assets, size_per_chunk, compression)

	write_asset_index(w, chunk_file, entries, number_of_assets, allocator)

	return nil
}

@(private)
write_header :: proc(
	w: ^Writer,
	chunk_file: ^os.File,
	number_of_assets: u32,
	size_per_chunk: u64 = SIZE_PER_CHUNK,
	compression: u16 = COMPRESSION,
) -> Error {

	// Get total_size
	total_size: u64 = 0
	offset_len := len(w.asset_table.asset_offsets)
	size_len := len(w.asset_table.asset_sizes)
	if offset_len > 0 && size_len > 0 {
		last_offset := w.asset_table.asset_offsets[offset_len - 1]
		last_size := w.asset_table.asset_sizes[size_len - 1]
		total_size = last_offset + last_size
	}

	header := Header {
		magic_string     = MAGIC_STRING,
		version          = VERSION,
		compression      = compression,
		size_per_chunk   = size_per_chunk,
		total_size       = total_size,
		number_of_assets = number_of_assets,
	}

	// Write header
	header_bytes := mem.ptr_to_bytes(&header)
	n := os.write_at(chunk_file, header_bytes, 0) or_return

	return nil
}

@(private)
write_asset_index :: proc(
	w: ^Writer,
	chunk_file: ^os.File,
	entries: []file.File_Entry,
	number_of_assets: u32,
	allocator: runtime.Allocator,
) -> Error {
	index_size: u64 = size_of(Asset_Index) * cast(u64)number_of_assets

	// ----------------------------------------

	index_bytes := make([]u8, index_size, allocator)
	defer delete(index_bytes)

	for f, i in entries {

		// TODO: Move to cli validation so it happens sooner
		path_length := len(f.relpath)
		if path_length > 512 {
			fmt.eprintf("path: {} ({})\n", f.relpath, path_length)
			return .Path_Too_Large
		}

		offset_in_bytes := size_of(Asset_Index) * cast(u64)i
		offset_pointer := mem.ptr_offset(&index_bytes[0], offset_in_bytes)

		ai := cast(^Asset_Index)offset_pointer
		copy(ai.relpath[:PATH_SIZE], f.relpath)
		ai.size = w.asset_table.asset_sizes[i]
		ai.offset = w.asset_table.asset_offsets[i]
	}

	assert(len(index_bytes) % size_of(Asset_Index) == 0) // clean multiple

	// Write asset index
	n := os.write_at(
		chunk_file,
		index_bytes,
		cast(i64)w.asset_table.asset_index_offset,
	) or_return

	return nil
}
