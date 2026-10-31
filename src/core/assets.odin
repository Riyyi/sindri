package core

import "base:runtime"
import "core:fmt"

import "sindri:base"

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

Assets :: struct {
	allocator:    runtime.Allocator,
	model_list:   map[string]Model,
	texture_list: map[string]Texture,
}

// -----------------------------------------
// Constructor/destructor

assets_init :: proc(allocator := context.allocator) -> Assets {
	return {
		allocator = allocator,
		model_list = make(map[string]Model, allocator),
		texture_list = make(map[string]Texture, allocator),
	}
}

assets_destroy :: proc(a: ^Assets) {
	for _, &model in a.model_list {
		delete(model.vertices, a.allocator)
		delete(model.indices, a.allocator)
	}

	for _, &texture in a.texture_list {
	}

	delete(a.model_list)
	delete(a.texture_list)
}

// -----------------------------------------
// Public functions

load_model :: proc(a: ^Assets, path: string) -> ^Model {
	if path in a.model_list do return &a.model_list[path]

	vertices, indices, ok := load_obj_model(path, a.allocator)
	fmt.assertf(ok, "[assets] failed to read model: %s", path)

	a.model_list[path] = {
		vertices = vertices,
		indices  = indices,
	}

	return &a.model_list[path]
}

// Batching:
// max_vertices 60k
// max_elements 60k
// max_texture_slots 32, query gpu or can wgpu do a larger buffer?

// Scene load: loop through all models, add all model sizes together,
// then create a vertex_buffer using the max size, storing the index somewhere.
