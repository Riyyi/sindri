package chunks

import "base:runtime"
import "core:fmt"
import "core:io"
import "core:os"

import "src:file"

// -----------------------------------------

write_assets :: proc(
	w: ^Writer,
	output: ^os.File,
	entries: []file.File_Entry,
	size_per_chunk: u64 = SIZE_PER_CHUNK,
	compression: u16 = COMPRESSION,
	allocator := context.allocator,
) -> Error {
	output_path := os.name(output)
	chunk_index := 0
	asset_index := 0
	chunk_offset: u64 = 0
	asset_offset: u64 = 0
	total_offset: u64 = w.asset_table.data_offset
	number_of_assets := len(entries)

	if size_per_chunk < w.asset_table.data_offset {
		fmt.eprintf(
			"chunk size: {}\nasset index size: {}\n",
			size_per_chunk,
			w.asset_table.data_offset,
		)
		return .Chunk_Size_Too_Small
	}

	// ----------------------------------------

	// Create new chunk
	chunk_stream := create_new_chunk(
		w,
		output_path,
		chunk_index,
		allocator,
	) or_return

	// Edge case of the chunk size being exactly the size of the data offset
	if size_per_chunk == w.asset_table.data_offset {
		chunk_index += 1
		chunk_stream = create_new_chunk(
			w,
			output_path,
			chunk_index,
			allocator,
		) or_return
	}

	// Chunk 0 starts after metadata
	if (chunk_index == 0) {
		chunk_offset = w.asset_table.data_offset
	}

	// ----------------------------------------

	// Open asset
	asset_stream, asset_size := open_asset(
		w,
		entries[asset_index].relpath,
	) or_return
	w.asset_table.asset_offsets[asset_index] = total_offset
	w.asset_table.asset_sizes[asset_index] = asset_size

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
			asset_stream, asset_size = open_asset(
				w,
				entries[asset_index].relpath,
			) or_return
			w.asset_table.asset_offsets[asset_index] = total_offset
			w.asset_table.asset_sizes[asset_index] = asset_size

		} else if asset_remaining == chunk_remaining {

			// Write asset to chunk
			write_chunk(chunk_stream, asset_stream, asset_remaining)
			total_offset += asset_remaining

			// Open next asset
			asset_index += 1
			asset_offset = 0
			if asset_index == number_of_assets do break
			asset_stream, asset_size = open_asset(
				w,
				entries[asset_index].relpath,
			) or_return
			w.asset_table.asset_offsets[asset_index] = total_offset
			w.asset_table.asset_sizes[asset_index] = asset_size

			// Create new chunk
			chunk_index += 1
			chunk_offset = 0
			chunk_stream = create_new_chunk(
				w,
				output_path,
				chunk_index,
				allocator,
			) or_return
		} else { 	// spillover to next chunk
			write_chunk(chunk_stream, asset_stream, chunk_remaining)
			asset_offset += chunk_remaining
			total_offset += chunk_remaining

			// Create new chunk
			chunk_index += 1
			chunk_offset = 0
			chunk_stream = create_new_chunk(
				w,
				output_path,
				chunk_index,
				allocator,
			) or_return
		}
	}

	return nil
}

@(private)
create_new_chunk :: proc(
	w: ^Writer,
	output_path: string,
	chunk_index: int,
	allocator: runtime.Allocator,
) -> (
	chunk_stream: io.Stream,
	err: Error,
) {
	// Remove old chunk
	chunk_path := compute_chunk_path(
		output_path,
		chunk_index,
		allocator,
	) or_return
	defer delete(chunk_path, allocator)
	if os.exists(chunk_path) {
		os.remove(chunk_path) or_return
	}

	if w.chunk_file != nil do os.close(w.chunk_file) // close previous

	// Create new chunk
	w.chunk_file = os.create(chunk_path) or_return

	chunk_stream = os.to_stream(w.chunk_file)

	return chunk_stream, nil
}

@(private)
open_asset :: proc(
	w: ^Writer,
	path: string,
) -> (
	asset_stream: io.Stream,
	asset_size: u64,
	err: Error,
) {
	if w.asset_file != nil do os.close(w.asset_file) // close previous

	// Open asset
	asset := os.open(path, {.Read}) or_return

	// Asset size
	asset_stream = os.to_stream(asset)
	asset_size = cast(u64)io.size(asset_stream) or_return

	return asset_stream, cast(u64)asset_size, nil
}

@(private)
write_chunk :: proc(dst: io.Stream, src: io.Stream, n: u64) -> Error {
	w := io.copy_n(dst, src, cast(i64)n) or_return

	return nil
}
