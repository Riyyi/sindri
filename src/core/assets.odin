/*
 * Copyright (C) 2026 Riyyi
 *
 * SPDX-License-Identifier: MIT
 */

package core

import "base:runtime"
import "core:fmt"
import "core:hash/xxhash"
import "core:os"

import "sindri:base"

ASSET_NIL :: 0
ASSETS_MAX :: 512

DIGEST :: xxhash.XXH64_hash

// -----------------------------------------
// Types

Model :: struct {
	vertices: []base.Vertex,
	indices:  []u16,
	// Some file formats embed their texture
	// texture: ^Texture2D,
}

Texture :: struct {
	width:           u32,
	height:          u32,
	id:              u32,
	internal_format: u32,
	data_format:     u32,
	data_type:       u32,
}

Asset_Idx :: u16

Asset_Ref :: struct {
	// TODO: 22 bits index, 10 bits generation, so we can store it in one 32bit number
	idx: Asset_Idx,
	gen: u16,
}

Asset_Kind :: enum {
	Model,
	Texture,
}

Asset :: struct {
	kind: Asset_Kind,

	digest: DIGEST,

	data: union #no_nil {
		Model,
		Texture,
	},
}

Assets :: struct {
	allocator:   runtime.Allocator,
	assets:      [ASSETS_MAX]Asset,
	// TODO: Collapse used and gen into 1 array
	used:        [ASSETS_MAX]bool,
	gen:         [ASSETS_MAX]u16,
	free_list:   [ASSETS_MAX]Asset_Idx,
	next_free:   Asset_Idx, // first free'd slot
	next_unused: Asset_Idx, // never previously used slot
}

// -----------------------------------------
// Constructor/destructor

assets_init :: proc(allocator := context.allocator) -> Assets {
	return {allocator = allocator}
}

assets_destroy :: proc(a: ^Assets) {
	for &asset, i in a.assets {
		if !a.used[i] do continue
		m, ok := asset.data.(Model)
		if !ok do continue
		delete(m.vertices, a.allocator)
		delete(m.indices, a.allocator)
	}
}

// -----------------------------------------
// Public functions

asset_add :: proc(a: ^Assets) -> Asset_Ref {
	slot: Asset_Idx
	gen: u16

	// Two-tiered searching of slots:
	// - first search the free-list, that contains freed up slots
	// - fallback to the index that has never been allocated before
	if a.next_free != ASSET_NIL {
		slot = a.next_free
		a.next_free = a.free_list[a.next_free]
		a.free_list[slot] = ASSET_NIL // clean up the pop'ed free-slot
	}
	else if (a.next_unused < ASSETS_MAX) {
		if a.next_unused == ASSET_NIL do a.next_unused = 1 // first ever add()
		slot = a.next_unused
		a.next_unused += 1
	}

	if slot != ASSET_NIL {
		a.assets[slot] = {} // reset data
		a.used[slot] = true
		a.gen[slot] += 1
		gen = a.gen[slot]
	}

	return {idx = slot, gen = gen}
}

asset_rem :: proc(a: ^Assets, ref: Asset_Ref) {
	idx := asset_deref(a, ref)
	if idx == ASSET_NIL do return

	a.used[idx] = false
	a.free_list[idx] = a.next_free
	a.next_free = idx
}

asset_get :: proc(a: ^Assets, ref: Asset_Ref) -> ^Asset {
	return &a.assets[asset_deref(a, ref)]
}

asset_deref :: proc(a: ^Assets, ref: Asset_Ref) -> Asset_Idx {
	if ref.idx > ASSET_NIL &&
	   ref.idx < ASSETS_MAX &&
	   a.used[ref.idx] &&
	   ref.gen == a.gen[ref.idx] {
		return ref.idx
	}

	return ASSET_NIL
}

asset_find :: proc(a: ^Assets, path: string) -> (Asset_Idx, DIGEST) {
	digest := xxhash.XXH64(transmute([]u8)path)

	found: u16
	for i: u16 = 1; i < min(a.next_unused, ASSETS_MAX); i += 1 {
		if a.used[i] && a.assets[i].digest == digest {
			return i, digest
		}
	}

	return ASSET_NIL, digest
}

asset_load_model :: proc(a: ^Assets, path: string) -> Asset_Ref {
	asset, digest := asset_find(a, path)
	if asset != ASSET_NIL {
		fmt.println("[assets] loading cached model", path)
		return {idx = asset, gen = a.gen[asset]}
	}

	fmt.println("[assets] loading model", path)
	vertices, indices, ok := load_obj_model(path, a.allocator)
	fmt.assertf(ok, "[assets] failed to read model: %s", path)

	ref := asset_add(a)
	a.assets[ref.idx] = {
		kind = .Model,
		digest = digest,
		data = Model{vertices = vertices, indices = indices},
	}

	return ref
}

asset_reload_after_hot_reload :: proc(a: ^Assets, path: string) {
	pwd, pwd_err := os.get_working_directory(context.temp_allocator)
	if pwd_err != nil {
		fmt.eprintfln("[assets] failed to get working directory: %s", pwd_err)
		return
	}

	w := os.walker_create(path)
	defer os.walker_destroy(&w)

	for info in os.walker_walk(&w) {
		if path, err := os.walker_error(&w); err != nil {
			fmt.eprintfln("[assets] failed walking %s: %s", path, err)
			continue
		}

		a_path := info.fullpath[len(pwd) + 1:]
		digest := xxhash.XXH64(transmute([]u8)a_path)

		for i: u16 = 1; i < min(a.next_unused, ASSETS_MAX); i += 1 {
			if !a.used[i] || a.assets[i].kind != .Model do continue
			if a.assets[i].digest == digest {
				fmt.println("[assets] loading model", a_path)
				vertices, indices, ok := load_obj_model(a_path, a.allocator)
				fmt.assertf(ok, "[assets] failed to read model: %s", a_path)

				a.assets[i].data = Model {
					vertices = vertices,
					indices  = indices,
				}
			}
		}
	}
}

// Batching:
// max_vertices 60k
// max_elements 60k
// max_texture_slots 32, query gpu or can wgpu do a larger buffer?

// Scene load: loop through all models, add all model sizes together,
// then create a vertex_buffer using the max size, storing the index somewhere.
