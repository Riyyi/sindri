package platform

import "core:fmt"
import "core:reflect"
import "core:strings"

import "wgpu:wgpu"

// -----------------------------------------
// Types

// -----------------------------------------
// Public functions

// Generate a WGSL struct declaration from an Odin struct type.
// The caller owns the returned string (allocated on context.allocator).
//
// If locations is true, each member is prefixed with @location(n). This is
// required for vertex input structs; uniform structs should use false.
to_wgsl_struct :: proc(
	$T: typeid,
	name: string,
	locations := false,
) -> string {
	ti := base_type_info(type_info_of(T))
	s, ok := ti.variant.(reflect.Type_Info_Struct)
	if !ok do fmt.panicf("[wgpu_reflect] %s is not a struct", typeid_of(T))

	b: strings.Builder
	strings.write_string(&b, "struct ")
	strings.write_string(&b, name)
	strings.write_string(&b, " {\n")

	names := s.names[:s.field_count]
	types := s.types[:s.field_count]
	for i in 0 ..< s.field_count {
		wgsl_type, type_ok := to_wgsl_type(types[i])
		if !type_ok {
			fmt.panicf("[wgpu_reflect] cannot map field %s to WGSL", names[i])
		}
		if locations {
			fmt.sbprintf(
				&b,
				"\t@location(%d) %s: %s,\n",
				i,
				names[i],
				wgsl_type,
			)
		} else {
			fmt.sbprintf(&b, "\t%s: %s,\n", names[i], wgsl_type)
		}
	}

	strings.write_string(&b, "};")
	return strings.to_string(b)
}

// Generate a []wgpu.VertexAttribute array that matches the fields of struct T.
// The caller owns the returned slice (allocated on context.allocator)
to_vertex_attributes :: proc($T: typeid) -> []wgpu.VertexAttribute {
	ti := base_type_info(type_info_of(T))
	s, ok := ti.variant.(reflect.Type_Info_Struct)
	if !ok do fmt.panicf("[wgpu_reflect] %s is not a struct", typeid_of(T))

	attrs := make([]wgpu.VertexAttribute, s.field_count)
	names := s.names[:s.field_count]
	types := s.types[:s.field_count]
	offsets := s.offsets[:s.field_count]

	for i in 0 ..< s.field_count {
		format, format_ok := to_vertex_format(types[i])
		if !format_ok {
			fmt.panicf(
				"[wgpu_reflect] cannot map field %s to a vertex format",
				names[i],
			)
		}

		attrs[i] = wgpu.VertexAttribute {
			format         = format,
			offset         = cast(u64)offsets[i],
			shaderLocation = u32(i),
		}
	}

	return attrs
}

// -----------------------------------------
// Private functions

// Strips named-type wrappers so we can inspect the underlying type
@(private = "file")
base_type_info :: proc(type_info: ^reflect.Type_Info) -> ^reflect.Type_Info {
	#partial switch v in type_info.variant {
		case reflect.Type_Info_Named:
			return base_type_info(v.base)
	}
	return type_info
}

// Map an Odin type to a WGSL scalar/vector/matrix type name
@(private = "file")
to_wgsl_type :: proc(type_info: ^reflect.Type_Info) -> (string, bool) {
	ti := base_type_info(type_info)

	#partial switch v in ti.variant {
		case reflect.Type_Info_Float:
			switch ti.size {
				case 4:
					return "f32", true
				case 8:
					return "f64", true
			}

		case reflect.Type_Info_Integer:
			prefix := v.signed ? "i" : "u"
			switch ti.size {
				case 1:
					return fmt.tprintf("%s8", prefix), true
				case 2:
					return fmt.tprintf("%s16", prefix), true
				case 4:
					return fmt.tprintf("%s32", prefix), true
				case 8:
					return fmt.tprintf("%s64", prefix), true
			}

		case reflect.Type_Info_Array:
			elem_type, elem_ok := to_wgsl_type(v.elem)
			if !elem_ok do return "", false
			switch v.count {
				case 2:
					return fmt.tprintf("vec2<%s>", elem_type), true
				case 3:
					return fmt.tprintf("vec3<%s>", elem_type), true
				case 4:
					return fmt.tprintf("vec4<%s>", elem_type), true
			}

		case reflect.Type_Info_Matrix:
			elem_type, elem_ok := to_wgsl_type(v.elem)
			if !elem_ok do return "", false
			return fmt.tprintf(
					"mat%dx%d<%s>",
					v.column_count,
					v.row_count,
					elem_type,
				),
				true

		case:
			fmt.panicf("[wgpu_reflect] unimplemented type translation: %v", ti)
	}

	return "", false
}

// Map an Odin type to a wgpu.VertexFormat.
// Only handles the scalar/vector numeric formats commonly used as vertex attributes
@(private = "file")
to_vertex_format :: proc(
	type_info: ^reflect.Type_Info,
) -> (
	wgpu.VertexFormat,
	bool,
) {
	ti := base_type_info(type_info)

	#partial switch v in ti.variant {
		case reflect.Type_Info_Float:
			if ti.size == 2 do return .Float16, true
			else if ti.size == 4 do return .Float32, true

		case reflect.Type_Info_Integer:
			if v.signed {
				switch ti.size {
					case 1:
						return .Sint8, true
					case 2:
						return .Sint16, true
					case 4:
						return .Sint32, true
				}
			} else {
				switch ti.size {
					case 1:
						return .Uint8, true
					case 2:
						return .Uint16, true
					case 4:
						return .Uint32, true
				}
			}

		case reflect.Type_Info_Array:
			elem := base_type_info(v.elem)
			#partial switch ev in elem.variant {
				case reflect.Type_Info_Float:
					if elem.size == 2 {
						switch v.count {
							case 2:
								return .Float16x2, true
							case 4:
								return .Float16x4, true
						}
					} else if elem.size == 4 {
						switch v.count {
							case 2:
								return .Float32x2, true
							case 3:
								return .Float32x3, true
							case 4:
								return .Float32x4, true
						}
					}

				case reflect.Type_Info_Integer:
					if ev.signed {
						switch elem.size {
							case 1:
								switch v.count {
									case 2:
										return .Sint8x2, true
									case 4:
										return .Sint8x4, true
								}
							case 2:
								switch v.count {
									case 2:
										return .Sint16x2, true
									case 4:
										return .Sint16x4, true
								}
							case 4:
								switch v.count {
									case 2:
										return .Sint32x2, true
									case 3:
										return .Sint32x3, true
									case 4:
										return .Sint32x4, true
								}
						}
					} else {
						switch elem.size {
							case 1:
								switch v.count {
									case 2:
										return .Uint8x2, true
									case 4:
										return .Uint8x4, true
								}
							case 2:
								switch (v.count) {
									case 2:
										return .Uint16x2, true
									case 4:
										return .Uint16x4, true
								}
							case 4:
								switch (v.count) {
									case 2:
										return .Uint32x2, true
									case 3:
										return .Uint32x3, true
									case 4:
										return .Uint32x4, true
								}
						}
					}
			}
	}

	return .Float32, false
}
