package main

import rl "vendor:raylib"
import "core:math"

// ============================================================================
// HEX RENDERER - flat-top hexes with a simple pannable / zoomable camera.
// ============================================================================

Hex_Renderer :: struct {
	hex_size:      f32, // center -> corner
	origin_x:      f32,
	origin_y:      f32,

	// Derived flat-top metrics.
	horiz_spacing: f32, // 1.5 * hex_size
	vert_spacing:  f32, // sqrt(3) * hex_size

	camera_x: f32,
	camera_y: f32,
	zoom:     f32,
}

hex_renderer_init :: proc(r: ^Hex_Renderer, hex_size: f32, screen_w, screen_h: int) {
	r.hex_size = hex_size
	r.origin_x = f32(screen_w) / 2
	r.origin_y = f32(screen_h) / 2
	r.horiz_spacing = 1.5 * hex_size
	r.vert_spacing = math.sqrt(f32(3.0)) * hex_size
	r.camera_x = 0
	r.camera_y = 0
	r.zoom = 1.0
}

// World-space (unzoomed, uncameraed) centre of a hex.
hex_world :: proc(r: ^Hex_Renderer, hex: Hex) -> (f32, f32) {
	x := r.horiz_spacing * f32(hex.q)
	y := r.vert_spacing * (f32(hex.r) + 0.5 * f32(hex.q))
	return x, y
}

hex_to_screen :: proc(r: ^Hex_Renderer, hex: Hex) -> (f32, f32) {
	wx, wy := hex_world(r, hex)
	x := (wx - r.camera_x) * r.zoom + r.origin_x
	y := (wy - r.camera_y) * r.zoom + r.origin_y
	return x, y
}

screen_to_hex :: proc(r: ^Hex_Renderer, sx, sy: f32) -> Hex {
	x := (sx - r.origin_x) / r.zoom + r.camera_x
	y := (sy - r.origin_y) / r.zoom + r.camera_y

	q_f := (2.0 / 3.0 * x) / r.hex_size
	r_f := (-1.0 / 3.0 * x + math.sqrt(f32(3.0)) / 3.0 * y) / r.hex_size
	return hex_round_axial(q_f, r_f)
}

center_camera_on :: proc(r: ^Hex_Renderer, hex: Hex) {
	r.camera_x, r.camera_y = hex_world(r, hex)
}

hex_corners :: proc(r: ^Hex_Renderer, cx, cy: f32) -> [6]rl.Vector2 {
	size := r.hex_size * r.zoom
	corners: [6]rl.Vector2
	for i in 0..<6 {
		angle := f32(i) * math.PI / 3.0
		corners[i] = rl.Vector2{cx + size * math.cos(angle), cy + size * math.sin(angle)}
	}
	return corners
}

draw_hex_filled :: proc(r: ^Hex_Renderer, hex: Hex, color: rl.Color) {
	cx, cy := hex_to_screen(r, hex)
	// DrawPoly draws a regular polygon from angle 0, matching our flat-top
	// corner angles (0, 60, 120, ...). DrawTriangleFan is unreliable here.
	rl.DrawPoly(rl.Vector2{cx, cy}, 6, r.hex_size * r.zoom, 0, color)
}

draw_hex_outline :: proc(r: ^Hex_Renderer, hex: Hex, color: rl.Color, thickness: f32) {
	cx, cy := hex_to_screen(r, hex)
	corners := hex_corners(r, cx, cy)
	for i in 0..<6 {
		j := (i + 1) % 6
		rl.DrawLineEx(corners[i], corners[j], thickness, color)
	}
}

draw_hex :: proc(r: ^Hex_Renderer, hex: Hex, fill: rl.Color, outline: rl.Color, thickness: f32) {
	draw_hex_filled(r, hex, fill)
	draw_hex_outline(r, hex, outline, thickness)
}

// ============================================================================
// CAMERA INPUT
// ============================================================================

hex_renderer_update_camera :: proc(r: ^Hex_Renderer, dt: f32) {
	speed := 600.0 / r.zoom

	if rl.IsKeyDown(.RIGHT) || rl.IsKeyDown(.D) { r.camera_x += speed * dt }
	if rl.IsKeyDown(.LEFT)  || rl.IsKeyDown(.A) { r.camera_x -= speed * dt }
	if rl.IsKeyDown(.DOWN)  || rl.IsKeyDown(.S) { r.camera_y += speed * dt }
	if rl.IsKeyDown(.UP)    || rl.IsKeyDown(.W) { r.camera_y -= speed * dt }

	wheel := rl.GetMouseWheelMove()
	if wheel != 0 {
		mx := f32(rl.GetMouseX())
		my := f32(rl.GetMouseY())

		world_x := (mx - r.origin_x) / r.zoom + r.camera_x
		world_y := (my - r.origin_y) / r.zoom + r.camera_y

		r.zoom = clamp(r.zoom * (1.0 + wheel * 0.12), 0.3, 3.0)

		r.camera_x = world_x - (mx - r.origin_x) / r.zoom
		r.camera_y = world_y - (my - r.origin_y) / r.zoom
	}
}

hex_renderer_hovered :: proc(r: ^Hex_Renderer) -> Hex {
	return screen_to_hex(r, f32(rl.GetMouseX()), f32(rl.GetMouseY()))
}

// One border colour for every hex so that shared edges (drawn by both
// neighbours) always match and never show a mix of colours.
HEX_BORDER :: rl.Color{45, 45, 58, 255}

