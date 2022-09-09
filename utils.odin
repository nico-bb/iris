package iris

import "core:math/linalg"
import gl "vendor:OpenGL"

@(private)
draw_triangles :: proc(count: int) {
	gl.DrawElements(gl.TRIANGLES, i32(count), gl.UNSIGNED_INT, nil)
}

set_backface_culling :: proc(on: bool) {
	if on {
		gl.Enable(gl.CULL_FACE)
		gl.CullFace(gl.BACK)
	} else {
		gl.Disable(gl.CULL_FACE)
	}
}

set_frontface_culling :: proc(on: bool) {
	if on {
		gl.Enable(gl.CULL_FACE)
		gl.CullFace(gl.FRONT)
	} else {
		gl.Disable(gl.CULL_FACE)
	}
}

blend :: proc(on: bool) {
	if on {
		gl.Enable(gl.BLEND)
	} else {
		gl.Disable(gl.BLEND)
	}
}

depth :: proc(on: bool) {
	if on {
		gl.Enable(gl.DEPTH_TEST)
	} else {
		gl.Disable(gl.DEPTH_TEST)
	}
}

Vector2 :: linalg.Vector2f32
Vector3 :: linalg.Vector3f32
VECTOR_ZERO :: Vector3{0, 0, 0}
VECTOR_UP :: Vector3{0, 1, 0}
VECTOR_ONE :: Vector3{1, 1, 1}

Vector4 :: linalg.Vector4f32

Quaternion :: linalg.Quaternionf32
Matrix4 :: linalg.Matrix4f32

Transform :: struct {
	translation: Vector3,
	rotation:    Quaternion,
	scale:       Vector3,
}

transform :: proc(t := VECTOR_ZERO, r := Quaternion(1), s := VECTOR_ONE) -> Transform {
	return {translation = t, rotation = r, scale = s}
}

transform_from_matrix :: proc(m: Matrix4) -> (result: Transform) {
	sx := linalg.vector_length(Vector3{m[0][0], m[0][1], m[0][2]})
	sy := linalg.vector_length(Vector3{m[1][0], m[1][1], m[1][2]})
	sz := linalg.vector_length(Vector3{m[2][0], m[2][1], m[2][2]})
	if determinant(m) < 0 {
		result.scale.x = -result.scale.x
	}

	result.translation = Vector3{m[3][0], m[3][1], m[3][2]}

	isx := 1 / sx
	isy := 1 / sy
	isz := 1 / sz

	_m := m
	_m[0][0] *= isx
	_m[0][1] *= isx
	_m[0][2] *= isx

	_m[1][0] *= isy
	_m[1][1] *= isy
	_m[1][2] *= isy

	_m[2][0] *= isz
	_m[2][1] *= isz
	_m[2][2] *= isz
	result.rotation = linalg.quaternion_from_matrix4_f32(_m)

	result.scale = {sx, sy, sz}
	return
}


set_viewport :: proc(width, height: int) {
	gl.Viewport(0, 0, i32(width), i32(height))
}

// clear_viewport :: proc(clr: Color) {

// }

Color :: distinct [4]f32


Rectangle :: struct {
	x, y:          f32,
	width, height: f32,
}

in_rect_bounds :: proc(rect: Rectangle, p: Vector2) -> bool {
	ok :=
		(p.x >= rect.x && p.x <= rect.x + rect.width) &&
		(p.y >= rect.y && p.y <= rect.y + rect.height)
	return ok
}

Direction :: enum {
	Up,
	Right,
	Down,
	Left,
}
