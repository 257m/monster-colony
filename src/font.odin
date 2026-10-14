package main

import rl "vendor:raylib"
import "core:c"

// ============================================================================
// UI FONT
//
// raylib's built-in font is a 10px bitmap that looks rough once this UI scales it
// up to the sizes it uses. We load a real TTF (a subset of Noto Sans, SIL OFL)
// and route every string through `draw_text` / `measure_text`, which fall back
// to the default font if the file is missing.
// ============================================================================

FONT_PATH       :: "assets/font.ttf"
FONT_ATLAS_SIZE :: 48 // rendered size of the atlas; text is scaled from this

UI_FONT:    rl.Font
UI_FONT_OK: bool

font_init :: proc() {
	// ASCII + Latin-1 + the em dash we use in prose.
	cps := make([dynamic]rune, 0, 300)
	defer delete(cps)
	for ch in 32..=126 {
		append(&cps, rune(ch))
	}
	for ch in 160..=255 {
		append(&cps, rune(ch))
	}
	append(&cps, rune(0x2014))
	f := rl.LoadFontEx(FONT_PATH, FONT_ATLAS_SIZE, raw_data(cps), c.int(len(cps)))
	if f.texture.id == 0 {
		return
	}
	rl.SetTextureFilter(f.texture, .BILINEAR)
	UI_FONT = f
	UI_FONT_OK = true
}

font_shutdown :: proc() {
	if UI_FONT_OK {
		rl.UnloadFont(UI_FONT)
	}
}

font_spacing :: proc(size: i32) -> f32 {
	return f32(size) * 0.02
}

// Draw text with the UI font (or raylib's default as a fallback).
draw_text :: proc(txt: cstring, x, y: i32, size: i32, col: rl.Color) {
	if !UI_FONT_OK {
		draw_text(txt, x, y, size, col)
		return
	}
	rl.DrawTextEx(UI_FONT, txt, rl.Vector2{f32(x), f32(y)}, f32(size), font_spacing(size), col)
}

// Width of `txt` at `size`, matching `draw_text`.
measure_text :: proc(txt: cstring, size: i32) -> i32 {
	if !UI_FONT_OK {
		return measure_text(txt, size)
	}
	return i32(rl.MeasureTextEx(UI_FONT, txt, f32(size), font_spacing(size)).x)
}
