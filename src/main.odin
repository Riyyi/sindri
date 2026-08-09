package main

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

	err := chunks.write_assets(
		&w,
		opts.output,
		entries[:],
		opts.size,
		opts.compression,
	)
	if err != nil do os.exit(1)

	chunks.write_metadata(
		&w,
		opts.output,
		entries[:],
		opts.size,
		opts.compression,
	)
	if err != nil do os.exit(2)
}

// TODO: .chunkignore
