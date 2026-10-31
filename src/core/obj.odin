package core

import "core:fmt"
import "core:math/linalg"
import "core:os"
import "core:strconv"
import "core:strings"

import "sindri:base"

// Minimal OBJ loader: reads v, vt, vn and triangulates convex polygon faces.
// Produces one GPU vertex per face corner, then centers and normalizes the
// model so it fits roughly inside a [-1, 1] cube at the origin
load_obj_model :: proc(
	path: string,
	allocator := context.allocator,
) -> (
	vertices: []base.Vertex,
	indices: []u16,
	ok: bool,
) {
	data, err := os.read_entire_file_from_path(path, allocator)
	if err != os.ERROR_NONE {
		fmt.eprintfln("[obj] failed to read model: %s", path)
		return nil, nil, false
	}
	defer delete(data)

	positions: [dynamic]base.Vec3
	uvs: [dynamic]base.Vec2
	normals: [dynamic]base.Vec3
	temp_vertices: [dynamic]base.Vertex
	temp_indices: [dynamic]u16
	defer {
		delete(positions)
		delete(uvs)
		delete(normals)
		delete(temp_vertices)
		delete(temp_indices)
	}

	text := string(data)
	for line in strings.split_lines_iterator(&text) {
		trimmed := strings.trim_space(line)
		if len(trimmed) == 0 || trimmed[0] == '#' do continue

		fields := strings.fields(trimmed)
		defer delete(fields)
		if len(fields) == 0 do continue

		switch fields[0] {
			case "v":
				if len(fields) < 4 do continue
				x, _ := strconv.parse_f32(fields[1])
				y, _ := strconv.parse_f32(fields[2])
				z, _ := strconv.parse_f32(fields[3])
				append(&positions, base.Vec3{x, y, z})
			case "vt":
				if len(fields) < 3 do continue
				u, _ := strconv.parse_f32(fields[1])
				v, _ := strconv.parse_f32(fields[2])
				append(&uvs, base.Vec2{u, v})
			case "vn":
				if len(fields) < 4 do continue
				x, _ := strconv.parse_f32(fields[1])
				y, _ := strconv.parse_f32(fields[2])
				z, _ := strconv.parse_f32(fields[3])
				append(&normals, base.Vec3{x, y, z})
			case "f":
				face_indices: [dynamic]u16
				defer delete(face_indices)

				for i := 1; i < len(fields); i += 1 {
					token := fields[i]
					slash := strings.index_byte(token, '/')

					vi_str := token
					vti_str := ""
					if slash != -1 {
						vi_str = token[:slash]
						slash2 := strings.index_byte(token[slash + 1:], '/')
						if slash2 != -1 {
							vti_str = token[slash + 1:slash + 1 + slash2]
						} else {
							vti_str = token[slash + 1:]
						}
					}

					vi, _ := strconv.parse_int(vi_str)
					vi -= 1 // OBJ indices are 1-based
					if vi < 0 || vi >= len(positions) do continue

					uv := base.Vec2{0, 0}
					if len(vti_str) > 0 {
						vti, _ := strconv.parse_int(vti_str)
						vti -= 1
						if vti >= 0 && vti < len(uvs) {
							uv = uvs[vti]
						}
					} else if vi < len(uvs) {
						uv = uvs[vi]
					}

					append(
						&temp_vertices,
						base.Vertex {
							pos = positions[vi],
							col = {1, 1, 1},
							uv = uv,
						},
					)
					append(&face_indices, cast(u16)(len(temp_vertices) - 1))
				}

				// Triangulate convex polygon by fanning from the first vertex
				for i := 2; i < len(face_indices); i += 1 {
					append(&temp_indices, face_indices[0])
					append(&temp_indices, face_indices[i - 1])
					append(&temp_indices, face_indices[i])
				}
		}
	}

	if len(temp_vertices) == 0 {
		return nil, nil, false
	}

	// Center and normalize: fit the model inside a roughly [-1, 1] cube
	min_p := temp_vertices[0].pos
	max_p := temp_vertices[0].pos
	for v in temp_vertices {
		min_p = linalg.min(min_p, v.pos)
		max_p = linalg.max(max_p, v.pos)
	}
	center := (min_p + max_p) * 0.5
	size := max_p - min_p
	max_size := max(size.x, size.y, size.z)
	scale := 1.8 / max_size

	for &v in temp_vertices {
		v.pos = (v.pos - center) * scale
	}

	vertices = make([]base.Vertex, len(temp_vertices), allocator)
	indices = make([]u16, len(temp_indices), allocator)
	copy(vertices, temp_vertices[:])
	copy(indices, temp_indices[:])
	return vertices, indices, true
}
