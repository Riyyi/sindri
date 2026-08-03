package file

import "base:runtime"
import "core:fmt"
import "core:io"
import "core:mem"
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
}

// -----------------------------------------

@(private)
offsets: Offsets

@(private = "file")
chunk_file: ^os.File

@(private = "file")
asset_file: ^os.File

// -----------------------------------------

compute_metadata_offsets :: proc(number_of_assets: u64) {
	// [ Header ][ []Asset Index ][ Data ]
	offsets.asset_index_offset = size_of(Header)
	offsets.data_offset =
		size_of(Header) + (size_of(AssetIndex) * number_of_assets)
}

// Returning `[]u8` is owned by the caller.
compute_header :: proc(
	entries: []FileEntry,
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

	if data_offset > size_per_chunk {
		fmt.eprintln(
			"error: chunk size too small to hold metadata:",
			data_offset,
		)
		os.exit(1)
	}

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

write_chunks :: proc(
	output: ^os.File,
	size_per_chunk: u64 = SIZE_PER_CHUNK,
	entries: []FileEntry,
	allocator := context.allocator,
) {
	output_path := os.name(output)
	chunk_index := 0
	asset_index := 0
	chunk_offset: u64 = 0
	asset_offset: u64 = 0
	total_offset: u64 = 0
	number_of_assets := len(entries)
	reserve(&offsets.asset_offsets, number_of_assets)

	buf: [20]u8

	// ----------------------------------------

	chunk_stream := create_new_chunk(
		output_path,
		chunk_index,
		buf[:],
		allocator,
	)

	if (chunk_index == 0) {
		// Chunk 0 starts after metadata
		chunk_offset = offsets.data_offset
		total_offset = offsets.data_offset
	}

	// ----------------------------------------

	asset_stream, asset_size := open_asset(entries[asset_index].relpath)
	offsets.asset_offsets[asset_index] = total_offset

	// ----------------------------------------

	for {
		chunk_remaining := size_per_chunk - chunk_offset
		asset_remaining := asset_size - asset_offset

		io.seek(chunk_stream, cast(i64)chunk_offset, .Start)
		io.seek(asset_stream, cast(i64)asset_offset, .Start)

		if asset_remaining < chunk_remaining {

			// Write asset to chunk
			io.copy_n(chunk_stream, asset_stream, cast(i64)asset_remaining)
			chunk_offset += asset_remaining
			total_offset += asset_remaining

			// Open new asset
			asset_index += 1
			asset_offset = 0
			if asset_index == number_of_assets do break
			asset_stream, asset_size = open_asset(entries[asset_index].relpath)
			offsets.asset_offsets[asset_index] = total_offset

		} else if asset_remaining == chunk_remaining {

			// Write asset to chunk
			io.copy_n(chunk_stream, asset_stream, cast(i64)asset_remaining)
			total_offset += asset_remaining

			// Open new asset
			asset_index += 1
			asset_offset = 0
			if asset_index == number_of_assets do break
			asset_stream, asset_size = open_asset(entries[asset_index].relpath)
			offsets.asset_offsets[asset_index] = total_offset

			// Create new chunk
			chunk_index += 1
			chunk_offset = 0
			chunk_stream = create_new_chunk(
				output_path,
				chunk_index,
				buf[:],
				allocator,
			)
		} else {
			io.copy_n(chunk_stream, asset_stream, cast(i64)chunk_remaining)
			asset_offset += chunk_remaining
			total_offset += chunk_remaining

			// Create new chunk
			chunk_index += 1
			chunk_offset = 0
			chunk_stream = create_new_chunk(
				output_path,
				chunk_index,
				buf[:],
				allocator,
			)
		}
	}

	// ----------------------------------------

	// Cleaup leftover
	os.close(chunk_file)
	os.close(asset_file)
}

@(private)
create_new_chunk :: proc(
	output_path: string,
	chunk_index: int,
	buf: []u8,
	allocator: runtime.Allocator,
) -> io.Stream {
	// Get chunk path
	chunk_index_str := strconv.write_int(buf[:], cast(i64)chunk_index, 10)
	chunk_name := strings.concatenate({"CHUNK", chunk_index_str}, allocator)
	defer delete(chunk_name, allocator)
	chunk, c_err := os.join_path({output_path, chunk_name}, allocator)
	if c_err != nil {
		fmt.eprintln("error: chunk join path failed:", c_err)
		os.exit(1)
	}
	defer delete(chunk, allocator)

	// Remove old chunk
	if os.exists(chunk) {
		rm_err := os.remove(chunk)
		if rm_err != nil {
			fmt.eprintln("error: remove old chunk failed:", rm_err)
			os.exit(1)
		}
	}

	if chunk_file != nil do os.close(chunk_file) // close previous

	// Create new chunk
	cf_err: os.Error
	chunk_file, cf_err = os.create(chunk)
	if cf_err != nil {
		fmt.eprintln("error: create new chunk failed:", cf_err)
		os.exit(1)
	}

	chunk_stream := os.to_stream(chunk_file)

	return chunk_stream
}

@(private)
open_asset :: proc(path: string) -> (io.Stream, u64) {
	if asset_file != nil do os.close(asset_file) // close previous

	// Open asset
	asset, open_err := os.open(path, {.Read})
	if open_err != nil {
		fmt.eprintln("error: asset open failed:", open_err)
		os.exit(1)
	}

	// Asset size
	asset_stream := os.to_stream(asset)
	asset_size, size_err := io.size(asset_stream)
	if size_err != nil {
		fmt.eprintln("error: asset size failed:", size_err)
		os.exit(1)
	}

	return asset_stream, cast(u64)asset_size
}
