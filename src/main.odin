package main

import "core:os"

import "src:cli"
import "src:file"

VERSION :: #config(VERSION, "dev")

main :: proc() {
	file.store_working_dir()
	defer file.remove_working_dir()

	opts := cli.parse(file.working_dir)

	// fmt.println("verbose:", opts.verbose)
	// fmt.println("compression:", opts.compression)
	// fmt.println("size:", opts.size)

	entries := file.list_dir_recursive(opts.input)
	defer file.delete_entries(&entries)

	w := file.writer_init(cast(u64)len(entries))
	defer file.writer_destroy(&w)

	file.write_assets(&w, opts.output, entries[:], opts.size, opts.compression)

	file.write_metadata(
		&w,
		opts.output,
		entries[:],
		opts.size,
		opts.compression,
	)
}
