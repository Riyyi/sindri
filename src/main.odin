package main

import "core:fmt"
import "core:os"

import "src:chunks"
import "src:cli"
import "src:file"

VERSION :: #config(VERSION, "dev")

main :: proc() {
	working_dir := file.get_working_dir()
	defer delete(working_dir)

	opts := cli.parse(working_dir)

	// fmt.println("verbose:", opts.verbose)
	// fmt.println("compression:", opts.compression)
	// fmt.println("size:", opts.size)

	entries := file.list_dir_recursive(opts.input, working_dir)
	defer file.delete_entries(&entries)

	w := chunks.writer_init(cast(u64)len(entries))
	defer chunks.writer_destroy(&w)

	// chunks.write_assets(
	// 	&w,
	// 	opts.output,
	// 	entries[:],
	// 	opts.size,
	// 	opts.compression,
	// )
	//
	// chunks.write_metadata(
	// 	&w,
	// 	opts.output,
	// 	entries[:],
	// 	opts.size,
	// 	opts.compression,
	// )

	header, err := chunks.read_header_by_path("./build/CHUNK0")
	chunk0, o_err := os.open("./build/CHUNK0")
	asset_index, a_err := chunks.read_asset_index(chunk0, header)
	fmt.println(
		"found: ",
		chunks.file_exists(header, asset_index, "not_exists"),
	)
	fmt.println(
		"found: ",
		chunks.file_exists(header, asset_index, "./toby/engage"),
	)

	fmt.printf(
		"file: %c\n",
		chunks.read_file(header, asset_index, opts.output, "./toby/engage"),
	)
}

// TODO: .chunkignore
