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

	file.compute_metadata_offsets(cast(u64)len(entries))
	file.write_assets(opts.output, entries[:], opts.size, opts.compression)
	file.write_metadata(opts.output, entries[:], opts.size, opts.compression)
	file.delete_offsets()
}
