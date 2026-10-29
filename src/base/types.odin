package base

// -----------------------------------------
// Types

Vec2 :: [2]f32
Vec3 :: [3]f32
Vec4 :: [4]f32

Mat3 :: matrix[3, 3]f32
Mat4 :: matrix[4, 4]f32

Vertex :: struct #align (4) {
	pos: Vec3,
	col: Vec3,
	uv:  Vec2, // texture coordinate
}
