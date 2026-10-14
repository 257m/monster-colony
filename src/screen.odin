package main

import rl "vendor:raylib"

// ============================================================================
// VIRTUAL RESOLUTION
//
// The whole UI is laid out for a fixed 1280x720 space. Rather than scale every
// coordinate, the game renders into a 1280x720 render texture and blits that to
// the window (letterboxed), so text and panels keep their proportions at any
// window size. `screen_w`/`screen_h` report the virtual size and `mouse_pos`
// maps the real cursor into that space — callers use these instead of raylib's
// window-space functions.
// ============================================================================

VIRTUAL_W :: 1280
VIRTUAL_H :: 720

SCREEN_RT:    rl.RenderTexture2D
SCREEN_RT_OK: bool

screen_init :: proc() {
	SCREEN_RT = rl.LoadRenderTexture(VIRTUAL_W, VIRTUAL_H)
	SCREEN_RT_OK = SCREEN_RT.id != 0
	if SCREEN_RT_OK {
		rl.SetTextureFilter(SCREEN_RT.texture, .BILINEAR)
	}
}

screen_shutdown :: proc() {
	if SCREEN_RT_OK {
		rl.UnloadRenderTexture(SCREEN_RT)
	}
}

screen_transform :: proc() -> (scale, ox, oy: f32) {
	ww := f32(rl.GetScreenWidth())
	wh := f32(rl.GetScreenHeight())
	scale = min(ww / f32(VIRTUAL_W), wh / f32(VIRTUAL_H))
	ox = (ww - f32(VIRTUAL_W) * scale) / 2
	oy = (wh - f32(VIRTUAL_H) * scale) / 2
	return
}

// Start a frame: draw the game into the virtual buffer (or the window directly
// if the buffer couldn't be created).
screen_begin :: proc() {
	if SCREEN_RT_OK {
		rl.BeginTextureMode(SCREEN_RT)
	} else {
		rl.BeginDrawing()
	}
	rl.ClearBackground(rl.Color{8, 9, 12, 255})
}

// Finish the frame: blit the virtual buffer to the window, letterboxed.
screen_end :: proc() {
	if SCREEN_RT_OK {
		rl.EndTextureMode()
		rl.BeginDrawing()
		rl.ClearBackground(rl.BLACK)
		scale, ox, oy := screen_transform()
		src := rl.Rectangle{0, 0, f32(VIRTUAL_W), -f32(VIRTUAL_H)} // render textures are flipped
		dst := rl.Rectangle{ox, oy, f32(VIRTUAL_W) * scale, f32(VIRTUAL_H) * scale}
		rl.DrawTexturePro(SCREEN_RT.texture, src, dst, rl.Vector2{0, 0}, 0, rl.WHITE)
		rl.EndDrawing()
	} else {
		rl.EndDrawing()
	}
}

screen_w :: proc() -> i32 { return VIRTUAL_W }
screen_h :: proc() -> i32 { return VIRTUAL_H }

// The cursor in virtual space.
mouse_pos :: proc() -> rl.Vector2 {
	mp := rl.GetMousePosition()
	if !SCREEN_RT_OK {
		return mp
	}
	scale, ox, oy := screen_transform()
	return rl.Vector2{(mp.x - ox) / scale, (mp.y - oy) / scale}
}

mouse_x :: proc() -> i32 { return i32(mouse_pos().x) }
mouse_y :: proc() -> i32 { return i32(mouse_pos().y) }

// The cursor delta in virtual space (window deltas are scaled by the transform).
mouse_delta :: proc() -> rl.Vector2 {
	d := rl.GetMouseDelta()
	if !SCREEN_RT_OK {
		return d
	}
	scale, _, _ := screen_transform()
	return rl.Vector2{d.x / scale, d.y / scale}
}
