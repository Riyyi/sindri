package file

import "base:runtime"
import "core:fmt"
import "core:mem"
import "core:os"

// -----------------------------------------

write_metadata :: proc(
	output: ^os.File,
	entries: []FileEntry,
	size_per_chunk: u64 = SIZE_PER_CHUNK,
	compression: u16 = COMPRESSION,
	allocator := context.allocator,
) {
	output_path := os.name(output)
	number_of_assets := cast(u32)len(entries)

	// ----------------------------------------

	chunk_path := compute_chunk_path(output_path, 0, allocator)
	defer delete(chunk_path)
	chunk_file, err := os.open(chunk_path, {.Read, .Write})
	if err != nil {
		fmt.eprintln("error: open chunk failed: ", err)
		os.exit(1)
	}
	defer os.close(chunk_file)

	write_header(chunk_file, number_of_assets, size_per_chunk, compression)

	write_asset_index(chunk_file, entries, number_of_assets, allocator)
}

@(private)
write_header :: proc(
	chunk_file: ^os.File,
	number_of_assets: u32,
	size_per_chunk: u64 = SIZE_PER_CHUNK,
	compression: u16 = COMPRESSION,
) {
	last_offset := offsets.asset_offsets[len(offsets.asset_offsets) - 1]
	last_size := offsets.asset_sizes[len(offsets.asset_sizes) - 1]
	total_size := last_offset + last_size

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
	n, err := os.write_at(chunk_file, header_bytes, 0)
	if err != nil {
		fmt.eprintln("error: chunk write error:", err)
		os.exit(1)
	}
}

@(private)
write_asset_index :: proc(
	chunk_file: ^os.File,
	entries: []FileEntry,
	number_of_assets: u32,
	allocator: runtime.Allocator,
) {
	index_size: u64 = size_of(AssetIndex) * cast(u64)number_of_assets

	// ----------------------------------------

	index_bytes := make([]u8, index_size, allocator)
	defer delete(index_bytes)

	for f, i in entries {

		// TODO: Move to cli validation so it happens sooner
		path_length := len(f.relpath)
		if path_length > 512 {
			fmt.eprintln("error: path exeeds maximum of 512:", f.relpath)
			os.exit(1)
		}

		offset_in_bytes := size_of(AssetIndex) * cast(u64)i
		offset_pointer := mem.ptr_offset(&index_bytes[0], offset_in_bytes)

		ai := cast(^AssetIndex)offset_pointer
		copy(ai.relpath[:PATH_SIZE], f.relpath)
		ai.size = offsets.asset_sizes[i]
		ai.offset = offsets.asset_offsets[i]
	}

	assert(len(index_bytes) % size_of(AssetIndex) == 0) // clean multiple

	// Write asset index
	n, err := os.write_at(
		chunk_file,
		index_bytes,
		cast(i64)offsets.asset_index_offset,
	)
	if err != nil {
		fmt.eprintln("error: chunk write error:", err)
		os.exit(1)
	}
}
