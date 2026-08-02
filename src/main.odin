package main

import "core:fmt"

import "src:cli"
import "src:file"

VERSION :: #config(VERSION, "dev")

main :: proc() {
	file.store_working_dir()
	defer file.remove_working_dir()

	opts := cli.parse(file.working_dir)

	fmt.println("verbose:", opts.verbose)
	fmt.println("compression:", opts.compression)
	fmt.println("size:", opts.size)

	asset := file.get_asset_by_path("./odinfmt.json")
	fmt.println("path:", asset.relpath)
	fmt.println("size:", asset.size)
	fmt.println("data:", asset.data)

	entries := file.list_dir_recursive_by_path("./src")
	fmt.println("entries:", entries)

	header, asset_index_array := file.compute_header(entries)
	fmt.println("header:", header)
	fmt.println("aia:", asset_index_array)
}
