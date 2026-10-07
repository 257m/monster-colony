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
	corners := hex_corners(r, cx, cy)
	rl.DrawTriangleFan(&corners[0], 6, color)
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

draw_hex_connection :: proc(r: ^Hex_Renderer, a, b: Hex, color: rl.Color, thickness: f32) {
	ax, ay := hex_to_screen(r, a)
	bx, by := hex_to_screen(r, b)
	rl.DrawLineEx(rl.Vector2{ax, ay}, rl.Vector2{bx, by}, thickness, color)
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

// ============================================================================
// NODE PRESENTATION
// ============================================================================

node_type_color :: proc(t: Node_Type) -> rl.Color {
	switch t {
	case .START:  return rl.Color{90, 200, 120, 255}
	case .COMBAT: return rl.Color{200, 80, 80, 255}
	case .ELITE:  return rl.Color{230, 140, 50, 255}
	case .REST:   return rl.Color{80, 160, 230, 255}
	case .SHOP:   return rl.Color{225, 200, 70, 255}
	case .EVENT:  return rl.Color{170, 90, 220, 255}
	case .BOSS:   return rl.Color{235, 40, 60, 255}
	}
	return rl.Color{120, 120, 130, 255}
}

node_type_label :: proc(t: Node_Type) -> cstring {
	switch t {
	case .START:  return "S"
	case .COMBAT: return "M"
	case .ELITE:  return "E"
	case .REST:   return "R"
	case .SHOP:   return "$"
	case .EVENT:  return "?"
	case .BOSS:   return "B"
	}
	return "?"
}

node_type_name :: proc(t: Node_Type) -> cstring {
	switch t {
	case .START:  return "Entrance"
	case .COMBAT: return "Combat"
	case .ELITE:  return "Elite"
	case .REST:   return "Campfire"
	case .SHOP:   return "Merchant"
	case .EVENT:  return "Event"
	case .BOSS:   return "Boss"
	}
	return "Unknown"
}

// One border colour for every hex so that shared edges (drawn by both
// neighbours) always match and never show a mix of colours.
HEX_BORDER :: rl.Color{45, 45, 58, 255}

draw_hex_inset :: proc(r: ^Hex_Renderer, hex: Hex, color: rl.Color, thickness, scale: f32) {
	cx, cy := hex_to_screen(r, hex)
	size := r.hex_size * r.zoom * scale
	corners: [6]rl.Vector2
	for i in 0..<6 {
		angle := f32(i) * math.PI / 3.0
		corners[i] = rl.Vector2{cx + size * math.cos(angle), cy + size * math.sin(angle)}
	}
	for i in 0..<6 {
		j := (i + 1) % 6
		rl.DrawLineEx(corners[i], corners[j], thickness, color)
	}
}

draw_map_node :: proc(r: ^Hex_Renderer, hex: Hex, kind: Node_Type, revealed, visited, current, reachable: bool) {
	cx, cy := hex_to_screen(r, hex)
	size := r.hex_size * r.zoom

	fill := node_type_color(kind)
	if !revealed {
		fill = rl.Color{28, 28, 38, 255}
	} else if visited && !current {
		fill = rl.Color{u8(fill[0] / 3), u8(fill[1] / 3), u8(fill[2] / 3), 255}
	}

	draw_hex(r, hex, fill, HEX_BORDER, 2.0 * r.zoom)

	// Emphasis is drawn inside the hexagon so it never affects the shared
	// borders. (Hover/reachable is highlighted by the separate hover marker.)
	if current {
		draw_hex_inset(r, hex, rl.Color{120, 255, 220, 255}, 3.0 * r.zoom, 0.78)
	}

	if !revealed {
		return
	}

	label := node_type_label(kind)
	font_size := i32(size * 0.9)
	text_w := rl.MeasureText(label, font_size)
	text_color := rl.WHITE
	if visited && !current {
		text_color = rl.Color{150, 150, 160, 255}
	}
	rl.DrawText(label, i32(cx) - text_w / 2, i32(cy) - font_size / 2, font_size, text_color)
}

// ============================================================================
// MINIMAP
// ============================================================================

draw_minimap :: proc(r: ^Hex_Renderer, hexes: []Hex, current: Hex, rect: rl.Rectangle) {
	rl.DrawRectangleRec(rect, rl.Color{16, 16, 24, 220})
	rl.DrawRectangleLinesEx(rect, 2, rl.Color{70, 70, 100, 255})

	if len(hexes) == 0 {
		return
	}

	min_q, max_q, min_r, max_r := hex_bounds(hexes)
	w := f32(max_q - min_q + 1)
	h := f32(max_r - min_r + 1)

	world_w := r.horiz_spacing * (w + 1)
	world_h := r.vert_spacing * (h + 1)
	scale := min(rect.width / world_w, rect.height / world_h) * 0.8

	cq := f32(min_q + max_q) / 2
	cr := f32(min_r + max_r) / 2
	center_wx := r.horiz_spacing * cq
	center_wy := r.vert_spacing * (cr + 0.5 * cq)

	dot := max(f32(2.0), r.hex_size * scale * 0.45)

	for hex in hexes {
		wx, wy := hex_world(r, hex)
		sx := rect.x + rect.width / 2 + (wx - center_wx) * scale
		sy := rect.y + rect.height / 2 + (wy - center_wy) * scale

		color := rl.Color{90, 90, 110, 255}
		radius := dot
		if hex_equal(hex, current) {
			color = rl.Color{120, 255, 220, 255}
			radius = max(dot, 4)
		}
		rl.DrawCircleV(rl.Vector2{sx, sy}, radius, color)
	}
}
