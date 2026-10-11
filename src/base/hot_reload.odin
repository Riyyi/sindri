package base

import "base:runtime"
import "core:crypto/hash"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:strings"
import "core:time"

SNAPSHOT_NAME :: "snapshot"
SNAPSHOT_EXTENSION :: "sndr"

MAGIC_STRING :: 0x72646E73 // "rdns" -> "sndr" in little endian
HOT_RELOAD_VERSION :: 1
APP_VERSION_SIZE :: 4 + time.MIN_YYYY_DATE_LEN + 8 + 6 // example: `dev-2026-09-23-a4084b3-debug`

// -----------------------------------------
// Types

@(private)
Snapshot_Header :: struct #packed #all_or_none {
	magic_string: u32,
	version:      u16, // spec of the snapshot
	app_version:  [APP_VERSION_SIZE]u8,
	region_count: u32,
}

@(private)
Region_Header :: struct #packed #all_or_none {
	name_size: u32,
	data_size: u32,
}

@(private)
Memory_Region :: struct {
	ptr_location: rawptr,
	// TODO: How do we do hash compare without having to hash current memory every frame?
	digest:       []u8, // hash of this region in last snapshot
}

@(private)
Hot_Reload :: struct {
	allocator:           runtime.Allocator,
	snapshot_path:       string,
	snapshot_header:     Snapshot_Header,
	region_headers:      map[string]Region_Header, // hash of name:size
	regions:             map[string]Memory_Region, // hash of name:size
	write_full_snapshot: bool,
}

// -----------------------------------------
// Variables

@(private)
hr: Hot_Reload

// -----------------------------------------
// Constructor & destructor

hot_reload_init :: proc(
	app_version: string,
	allocator := context.allocator,
) -> os.Error {
	// Get snapshot path
	out := os.get_executable_directory(allocator) or_return
	defer delete(out, allocator)
	snapshot_path := fmt.tprintf(
		"%v/%v.%v",
		out,
		SNAPSHOT_NAME,
		SNAPSHOT_EXTENSION,
	)
	snapshot_path_cpy := strings.clone(snapshot_path, allocator)

	// Copy version string
	version: [APP_VERSION_SIZE]u8
	n := min(len(app_version), APP_VERSION_SIZE)
	copy(version[:n], app_version[:n])

	hr = {
		allocator = allocator,
		snapshot_path = snapshot_path_cpy,
		snapshot_header = {
			magic_string = MAGIC_STRING,
			version = HOT_RELOAD_VERSION,
			app_version = version,
			region_count = 0,
		},
		region_headers = make(map[string]Region_Header, 1, allocator), // initial capacity for nil checks
		regions = make(map[string]Memory_Region, 1, allocator), // initial capacity for nil checks
		write_full_snapshot = true,
	}

	return nil
}

hot_reload_destroy :: proc() {
	assert(
		hr.region_headers != nil,
		"[hot-reload] destroying uninitialized data",
	)

	assert(hr.regions != nil, "[hot-reload] destroying uninitialized data")

	delete(hr.snapshot_path, hr.allocator)

	for key, region in hr.region_headers do delete(key, hr.allocator)
	for key, region in hr.regions {
		if region.digest != nil do delete(region.digest, hr.allocator)
	}

	delete(hr.region_headers)
	delete(hr.regions)
}

// -----------------------------------------
// Public functions

register_region :: proc(
	name: string,
	ptr_location: rawptr,
	data_size: u32,
) -> os.Error {
	assert(hr.region_headers != nil, "[hot-reload] uninitialized")
	assert(hr.regions != nil, "[hot-reload] uninitialized")
	assert(ptr_location != nil, "[hot_reload] invalid location")
	assert(data_size > 0, "[hot_reload] invalid type size")

	hash := fmt.tprintf("%v:%d", name, data_size)
	assert(!(hash in hr.regions), "[hot_reload] double registration")
	hash_cpy := strings.clone(hash, hr.allocator)
	hr.region_headers[hash_cpy] = Region_Header {
		name_size = cast(u32)len(name),
		data_size = data_size,
	}
	hr.regions[hash_cpy] = Memory_Region {
		ptr_location = ptr_location,
	}

	hr.snapshot_header.region_count += 1

	hr.write_full_snapshot = true

	return nil
}

read_snapshot :: proc() -> os.Error {
	assert(hr.region_headers != nil, "[hot-reload] uninitialized")
	assert(hr.regions != nil, "[hot-reload] uninitialized")

	if !os.exists(hr.snapshot_path) {
		hr.write_full_snapshot = true
		return nil
	}

	snapshot := os.open(hr.snapshot_path, {.Read}) or_return
	defer os.close(snapshot)

	offset: i64

	// Read snapshot header
	snapshot_header: Snapshot_Header
	header_bytes := mem.ptr_to_bytes(&snapshot_header)
	os.read_at(snapshot, header_bytes, offset) or_return
	offset += size_of(Snapshot_Header)
	assert(
		snapshot_header.magic_string == MAGIC_STRING,
		"[hot-reload] unknown filetype",
	)
	assert(
		snapshot_header.version == HOT_RELOAD_VERSION,
		"[hot-reload] incompatible snapshot version",
	)

	region_header: Region_Header
	for i in 0 ..< snapshot_header.region_count {

		// Read region header
		header_bytes := mem.ptr_to_bytes(&region_header)
		os.read_at(snapshot, header_bytes, offset) or_return
		offset += size_of(Region_Header)

		// Read region name
		name_bytes := make([]byte, region_header.name_size, hr.allocator)
		defer delete(name_bytes, hr.allocator)
		os.read_at(snapshot, name_bytes, offset) or_return
		offset += cast(i64)region_header.name_size
		name := transmute(string)name_bytes[:]

		// Read region data
		data_bytes := make([]byte, region_header.data_size, hr.allocator)
		defer delete(data_bytes, hr.allocator)
		os.read_at(snapshot, data_bytes, offset) or_return
		offset += cast(i64)region_header.data_size

		// Compare currently registered region with the loaded region
		key := fmt.tprintf("%v:%d", name, region_header.data_size)
		new_region_header, ok := hr.region_headers[key]
		if !ok || region_header.data_size != new_region_header.data_size {
			hr.write_full_snapshot = true
			fmt.println("[hot-reload] bail loading region:", name)
			continue
		}

		// Create digest and store in registered regions
		digest := hash.hash_bytes(
			hash.Algorithm.SHA256,
			data_bytes,
			hr.allocator,
		)
		region := &hr.regions[key]
		region.digest = digest

		// Write snapshot memory to the memory region
		dest := mem.byte_slice(
			region.ptr_location,
			cast(int)region_header.data_size,
		)
		copy(dest, data_bytes)
	}

	return nil
}

// Next write will be a full memory snapshot
set_write_full_snapshot :: proc() {
	hr.write_full_snapshot = true
}

// Write memory snapshot, save on writes by diff-ing
write_snapshot :: proc() -> os.Error {
	assert(hr.region_headers != nil, "[hot-reload] uninitialized")
	assert(hr.regions != nil, "[hot-reload] uninitialized")

	snapshot: ^os.File
	if hr.write_full_snapshot || !os.exists(hr.snapshot_path) {
		snapshot = os.create(hr.snapshot_path) or_return
	} else {
		snapshot = os.open(hr.snapshot_path, {.Read, .Write}) or_return
	}
	defer os.close(snapshot)

	offset: i64

	// Write header
	if hr.write_full_snapshot {
		header_bytes := mem.ptr_to_bytes(&hr.snapshot_header)
		n := os.write_at(snapshot, header_bytes, offset) or_return
	}
	offset += size_of(Snapshot_Header)

	for key, &region in hr.regions {
		header := hr.region_headers[key]

		// Write region header
		if hr.write_full_snapshot {
			header_bytes := mem.ptr_to_bytes(&header)
			os.write_at(snapshot, header_bytes, offset) or_return
		}
		offset += size_of(Region_Header)

		// Write region name
		if hr.write_full_snapshot {
			name := key[:header.name_size] // get name from first part of the hash
			name_bytes := transmute([]byte)name
			os.write_at(snapshot, name_bytes, offset) or_return
		}
		offset += cast(i64)header.name_size

		// Write region data (if bytes differ)
		data_bytes := mem.byte_slice(region.ptr_location, header.data_size)
		digest := hash.hash_bytes(
			hash.Algorithm.SHA256,
			data_bytes,
			hr.allocator,
		)
		if hr.write_full_snapshot || mem.compare(digest, region.digest) != 0 {
			delete(region.digest, hr.allocator)
			region.digest = digest
			os.write_at(snapshot, data_bytes, offset) or_return
		} else {
			delete(digest, hr.allocator)
		}
		offset += cast(i64)header.data_size
	}

	hr.write_full_snapshot = false

	return nil
}

force_reload :: proc() {
	should_close = true
}

force_restart :: proc() -> os.Error {
	should_close = true
	os.remove(hr.snapshot_path) or_return

	return nil
}
