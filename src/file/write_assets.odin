package file

import "base:runtime"
import "core:fmt"
import "core:io"
import "core:os"

// -----------------------------------------

@(private = "file")
chunk_file: ^os.File

@(private = "file")
asset_file: ^os.File

// -----------------------------------------

write_assets :: proc(
	output: ^os.File,
	entries: []FileEntry,
	size_per_chunk: u64 = SIZE_PER_CHUNK,
	compression: u16 = COMPRESSION,
	allocator := context.allocator,
) {
	output_path := os.name(output)
	chunk_index := 0
	asset_index := 0
	chunk_offset: u64 = 0
	asset_offset: u64 = 0
	total_offset: u64 = offsets.data_offset
	number_of_assets := len(entries)
	resize(&offsets.asset_offsets, number_of_assets)
	resize(&offsets.asset_sizes, number_of_assets)

	if size_per_chunk < offsets.data_offset {
		fmt.eprintln(
			"error: chunk size too small to hold asset index:",
			offsets.data_offset,
		)
		os.exit(1)
	}

	// ----------------------------------------

	// Create new chunk
	chunk_stream := create_new_chunk(output_path, chunk_index, allocator)

	// Edge case of the chunk size being exactly the size of the data offset
	if size_per_chunk == offsets.data_offset {
		chunk_index += 1
		chunk_stream = create_new_chunk(output_path, chunk_index, allocator)
	}

	// Chunk 0 starts after metadata
	if (chunk_index == 0) {
		chunk_offset = offsets.data_offset
	}

	// ----------------------------------------

	// Open asset
	asset_stream, asset_size := open_asset(entries[asset_index].relpath)
	offsets.asset_offsets[asset_index] = total_offset
	offsets.asset_sizes[asset_index] = asset_size

	// ----------------------------------------

	for {
		chunk_remaining := size_per_chunk - chunk_offset
		asset_remaining := asset_size - asset_offset

		io.seek(chunk_stream, cast(i64)chunk_offset, .Start)
		io.seek(asset_stream, cast(i64)asset_offset, .Start)

		if asset_remaining < chunk_remaining {

			// Write asset to chunk
			write_chunk(chunk_stream, asset_stream, asset_remaining)
			chunk_offset += asset_remaining
			total_offset += asset_remaining

			// Open next asset
			asset_index += 1
			asset_offset = 0
			if asset_index == number_of_assets do break
			asset_stream, asset_size = open_asset(entries[asset_index].relpath)
			offsets.asset_offsets[asset_index] = total_offset
			offsets.asset_sizes[asset_index] = asset_size

		} else if asset_remaining == chunk_remaining {

			// Write asset to chunk
			write_chunk(chunk_stream, asset_stream, asset_remaining)
			total_offset += asset_remaining

			// Open next asset
			asset_index += 1
			asset_offset = 0
			if asset_index == number_of_assets do break
			asset_stream, asset_size = open_asset(entries[asset_index].relpath)
			offsets.asset_offsets[asset_index] = total_offset
			offsets.asset_sizes[asset_index] = asset_size

			// Create new chunk
			chunk_index += 1
			chunk_offset = 0
			chunk_stream = create_new_chunk(
				output_path,
				chunk_index,
				allocator,
			)
		} else { 	// spillover to next chunk
			write_chunk(chunk_stream, asset_stream, chunk_remaining)
			asset_offset += chunk_remaining
			total_offset += chunk_remaining

			// Create new chunk
			chunk_index += 1
			chunk_offset = 0
			chunk_stream = create_new_chunk(
				output_path,
				chunk_index,
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
	allocator: runtime.Allocator,
) -> io.Stream {
	// Remove old chunk
	chunk_path := compute_chunk_path(output_path, chunk_index, allocator)
	defer delete(chunk_path)
	if os.exists(chunk_path) {
		rm_err := os.remove(chunk_path)
		if rm_err != nil {
			fmt.eprintln("error: remove old chunk failed:", rm_err)
			os.exit(1)
		}
	}

	if chunk_file != nil do os.close(chunk_file) // close previous

	// Create new chunk
	cf_err: os.Error
	chunk_file, cf_err = os.create(chunk_path)
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

@(private)
write_chunk :: proc(dst: io.Stream, src: io.Stream, n: u64) {
	w, err := io.copy_n(dst, src, cast(i64)n)
	if err != nil {
		fmt.eprintln("error: chunk write error:", err)
		os.exit(1)
	}
}
