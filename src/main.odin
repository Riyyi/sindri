package main

import "core:os"

import "src:chunks"
import "src:cli"
import "src:file"

VERSION :: #config(VERSION, "dev")

CLI_ERR :: 1
WORKING_DIR_ERR :: 2
LIST_DIR_ERR :: 3
WRITE_ASSETS_ERR :: 4
WRITE_METADATA_ERR :: 5

// -----------------------------------------

main :: proc() {
	working_dir, wd_err := file.get_working_dir()
	if wd_err != nil do os.exit(WORKING_DIR_ERR)
	defer delete(working_dir)

	opts, c_err := cli.parse(working_dir)
	if c_err != nil do os.exit(CLI_ERR)

	// fmt.println("verbose:", opts.verbose)
	// fmt.println("compression:", opts.compression)
	// fmt.println("size:", opts.size)

	entries, e_err := file.list_dir_recursive(opts.input, working_dir)
	if e_err != nil do os.exit(LIST_DIR_ERR)
	defer file.delete_entries(&entries)

	w := chunks.writer_init(cast(u64)len(entries))
	defer chunks.writer_destroy(&w)

	wa_err := chunks.write_assets(
		&w,
		opts.output,
		entries[:],
		opts.size,
		opts.compression,
	)
	if wa_err != nil do os.exit(WRITE_ASSETS_ERR)

	wm_err := chunks.write_metadata(
		&w,
		opts.output,
		entries[:],
		opts.size,
		opts.compression,
	)
	if wm_err != nil do os.exit(WRITE_METADATA_ERR)
}

// TODO: .chunkignore
