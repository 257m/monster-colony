package main

import rl "vendor:raylib"

// ============================================================================
// UI SCALING
//
// The whole UI is laid out in a fixed 1280x720 "design space". Instead of
// touching every coordinate, the frame is drawn through a 2D camera whose zoom
// scales that design space to fill the window (letterboxed, aspect preserved).
// Because raylib draws shapes as geometry and the default font is a
// point-filtered bitmap, this keeps panels and text crisp rather than
// resampling a low-res buffer.
//
// `screen_w`/`screen_h` report the design size and the `mouse_*` helpers map
// the real cursor back into it, so callers keep using design coordinates.
// ============================================================================

DESIGN_W :: 1280
DESIGN_H :: 720

screen_w :: proc() -> i32 { return DESIGN_W }
screen_h :: proc() -> i32 { return DESIGN_H }

// Scale + letterbox offset from design space to the window.
screen_transform :: proc() -> (scale, ox, oy: f32) {
	ww := f32(rl.GetScreenWidth())
	wh := f32(rl.GetScreenHeight())
	scale = min(ww / f32(DESIGN_W), wh / f32(DESIGN_H))
	ox = (ww - f32(DESIGN_W) * scale) / 2
	oy = (wh - f32(DESIGN_H) * scale) / 2
	return
}

// The camera used for a frame (optionally shifted by a screen shake, in design
// units). Callers that need to re-enter 2D mode (e.g. the battle shake) must
// use this so they don't drop the UI scale.
ui_camera :: proc(shake_x := f32(0), shake_y := f32(0)) -> rl.Camera2D {
	scale, ox, oy := screen_transform()
	return rl.Camera2D {
		offset = rl.Vector2{ox + shake_x * scale, oy + shake_y * scale},
		target = rl.Vector2{0, 0},
		rotation = 0,
		zoom = scale,
	}
}

// Start a frame: clear, then enter the scaled design space.
screen_begin :: proc() {
	rl.BeginDrawing()
	rl.ClearBackground(rl.BLACK)
	rl.BeginMode2D(ui_camera())
}

// Finish a frame.
screen_end :: proc() {
	rl.EndMode2D()
	rl.EndDrawing()
}

// Scissor rectangles are in framebuffer pixels, not design space, so they need
// mapping through the same transform.
scissor_begin :: proc(rec: rl.Rectangle) {
	scale, ox, oy := screen_transform()
	rl.BeginScissorMode(
		i32(rec.x * scale + ox),
		i32(rec.y * scale + oy),
		i32(rec.width * scale),
		i32(rec.height * scale),
	)
}

scissor_end :: proc() {
	rl.EndScissorMode()
}

// The cursor in design space.
mouse_pos :: proc() -> rl.Vector2 {
	mp := rl.GetMousePosition()
	scale, ox, oy := screen_transform()
	return rl.Vector2{(mp.x - ox) / scale, (mp.y - oy) / scale}
}

mouse_x :: proc() -> i32 { return i32(mouse_pos().x) }
mouse_y :: proc() -> i32 { return i32(mouse_pos().y) }

mouse_delta :: proc() -> rl.Vector2 {
	d := rl.GetMouseDelta()
	scale, _, _ := screen_transform()
	return rl.Vector2{d.x / scale, d.y / scale}
}
