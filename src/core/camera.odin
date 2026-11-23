/*
 * Copyright (C) 2026 Riyyi
 *
 * SPDX-License-Identifier: MIT
 */

package core

import "core:math"
import "core:math/linalg"

import "sindri:base"
import "sindri:platform"

CAMERA_SPEED :: 5

// -----------------------------------------
// Public functions

camera_update :: proc(
	dt: f32,
	camera: ^Thing,
	mouse_delta: base.Vec2,
	sensitivity: f32 = 0.005,
) {
	// Look
	camera.rot.y -= mouse_delta.x * sensitivity
	camera.rot.x -= mouse_delta.y * sensitivity
	camera.rot.x = clamp(camera.rot.x, -math.PI / 2 + 0.01, math.PI / 2 - 0.01)

	// Move (yaw-relative, world-Y up)
	yaw := linalg.matrix4_rotate(camera.rot.y, {0, 1, 0})
	forward := (yaw * base.Vec4{0, 0, -1, 0}).xyz
	right := (yaw * base.Vec4{1, 0, 0, 0}).xyz

	move := base.Vec3{0, 0, 0}
	if platform.os_key_state(.Key_W) == .Press do move += forward
	if platform.os_key_state(.Key_S) == .Press do move -= forward
	if platform.os_key_state(.Key_A) == .Press do move -= right
	if platform.os_key_state(.Key_D) == .Press do move += right
	if platform.os_key_state(.Key_Space) == .Press do move += base.Vec3{0, 1, 0}
	if platform.os_key_state(.Key_Left_Shift) == .Press do move -= base.Vec3{0, 1, 0}

	if move != {0, 0, 0} {
		move = linalg.normalize(move) * CAMERA_SPEED
		camera.pos += move * dt
	}
}
