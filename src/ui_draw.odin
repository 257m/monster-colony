package main

import rl "vendor:raylib"
import "core:fmt"

// ============================================================================
// SHARED UI DRAWING
//
// Small reusable pieces used by every screen and panel, so the shapes and
// palettes live in one place instead of being copy-pasted around.
// ============================================================================

// A rounded panel: dark fill + coloured border (dialogs, lists, HUD boxes).
draw_panel :: proc(
	p: rl.Rectangle,
	bg, border: rl.Color,
	radius := f32(0.04),
	segments := i32(8),
	thickness := f32(2),
) {
	rl.DrawRectangleRounded(p, radius, segments, bg)
	rl.DrawRectangleRoundedLinesEx(p, radius, segments, thickness, border)
}

// A button palette. Copy one and tweak a field for a one-off.
Button_Style :: struct {
	bg, bg_hover, bg_off:             rl.Color,
	border, border_hover, border_off: rl.Color,
	text, text_hover, text_off:       rl.Color,
	radius:                           f32,
}

BUTTON_PANEL :: Button_Style{
	bg = {44, 48, 60, 255}, bg_hover = {70, 80, 100, 255}, bg_off = {30, 30, 38, 255},
	border = {150, 170, 210, 255}, border_hover = {150, 170, 210, 255}, border_off = {80, 80, 92, 255},
	text = {225, 230, 245, 255}, text_hover = {240, 244, 255, 255}, text_off = {130, 130, 142, 255},
	radius = 0.2,
}
BUTTON_TITLE :: Button_Style{
	bg = {26, 30, 42, 255}, bg_hover = {44, 52, 72, 255}, bg_off = {26, 30, 42, 255},
	border = {80, 90, 115, 255}, border_hover = {150, 180, 235, 255}, border_off = {80, 90, 115, 255},
	text = {205, 212, 230, 255}, text_hover = {240, 244, 255, 255}, text_off = {140, 145, 165, 255},
	radius = 0.22,
}
BUTTON_SHOP :: Button_Style{
	bg = {30, 30, 42, 255}, bg_hover = {44, 44, 58, 255}, bg_off = {26, 24, 26, 255},
	border = {180, 160, 90, 255}, border_hover = {180, 160, 90, 255}, border_off = {90, 80, 80, 255},
	text = {235, 235, 245, 255}, text_hover = {235, 235, 245, 255}, text_off = {140, 140, 150, 255},
	radius = 0.16,
}
BUTTON_GO :: Button_Style{
	bg = {70, 130, 100, 255}, bg_hover = {95, 175, 130, 255}, bg_off = {40, 40, 46, 255},
	border = {210, 230, 220, 255}, border_hover = {210, 230, 220, 255}, border_off = {80, 80, 92, 255},
	text = {240, 255, 245, 255}, text_hover = {240, 255, 245, 255}, text_off = {140, 140, 150, 255},
	radius = 0.25,
}

// A centred button. `enabled` dims it and suppresses the hover state.
draw_button :: proc(
	rec: rl.Rectangle,
	label: cstring,
	enabled: bool,
	style := BUTTON_PANEL,
	font := i32(16),
	segments := i32(6),
) {
	hover := enabled && rl.CheckCollisionPointRec(mouse_pos(), rec)
	if hover {
		ui_want_hand()
	}
	bg := style.bg_off
	border := style.border_off
	col := style.text_off
	if enabled {
		bg = hover ? style.bg_hover : style.bg
		border = hover ? style.border_hover : style.border
		col = hover ? style.text_hover : style.text
	}
	rl.DrawRectangleRounded(rec, style.radius, segments, bg)
	rl.DrawRectangleRoundedLinesEx(rec, style.radius, segments, 2, border)
	w := rl.MeasureText(label, font)
	rl.DrawText(label, i32(rec.x + rec.width / 2) - w / 2, i32(rec.y + rec.height / 2) - font / 2, font, col)
}

// A selectable list row: fill + border tinted by state.
draw_row :: proc(rec: rl.Rectangle, selected, hover: bool, accent: rl.Color) {
	if hover {
		ui_want_hand()
	}
	bg := rl.Color{26, 28, 36, 255}
	if selected {
		bg = rl.Color{52, 78, 56, 255}
	} else if hover {
		bg = rl.Color{38, 42, 54, 255}
	}
	border := selected ? accent : rl.Color{90, 100, 120, 255}
	rl.DrawRectangleRounded(rec, 0.18, 4, bg)
	rl.DrawRectangleRoundedLinesEx(rec, 0.18, 4, 2, border)
}

// A scrollable, clickable list — shared by the encyclopedia, the dexes and the
// bag. `index` is the selected row; `first` is the top visible row. Geometry
// (x/y/w/row_h/rows) can live in a package-level constant; the caller copies it
// and fills in index/first from the game state.
List_View :: struct {
	index, first, rows: int,
	row_h, x, y, w:     f32,
}

list_row_rect :: proc(v: List_View, row: int) -> rl.Rectangle {
	return rl.Rectangle{v.x, v.y + f32(row) * v.row_h, v.w, v.row_h - 2}
}

// Keyboard (Up/Down/W/S), wheel and click navigation; keeps the selection in
// view and clamps the scroll. Call after handling the panel's close key.
list_navigate :: proc(v: ^List_View, n: int) {
	changed := false
	if rl.IsKeyPressed(.DOWN) || rl.IsKeyPressed(.S) {
		v.index = min(v.index + 1, max(n - 1, 0))
		changed = true
	}
	if rl.IsKeyPressed(.UP) || rl.IsKeyPressed(.W) {
		v.index = max(v.index - 1, 0)
		changed = true
	}
	if rl.IsMouseButtonPressed(.LEFT) {
		mp := mouse_pos()
		for row in 0 ..< v.rows {
			i := v.first + row
			if i >= n {
				break
			}
			if rl.CheckCollisionPointRec(mp, list_row_rect(v^, row)) {
				v.index = i
				changed = true
			}
		}
	}
	if changed {
		if v.index < v.first {
			v.first = v.index
		}
		if v.index >= v.first + v.rows {
			v.first = v.index - v.rows + 1
		}
	}
	if wheel := rl.GetMouseWheelMove(); wheel != 0 {
		v.first -= int(wheel)
	}
	v.first = clamp(v.first, 0, max(0, n - v.rows))
}

// The full-screen backdrop + title + subtitle used by the list screens.
draw_list_screen_header :: proc(title, subtitle: cstring) {
	sw := f32(screen_w())
	sh := f32(screen_h())
	rl.DrawRectangle(0, 0, i32(sw), i32(sh), rl.Color{8, 10, 16, 245})
	rl.DrawText(title, 40, 38, 32, rl.Color{225, 225, 240, 255})
	rl.DrawText(subtitle, 40, 80, 16, rl.Color{140, 140, 160, 255})
}

// A vertical scrollbar for anything that scrolls. The track is always drawn —
// a short list should look like a long one, just with a full-height thumb — so
// every screen that scrolls reads the same.
draw_scrollbar :: proc(track: rl.Rectangle, first, rows, n: int) {
	if rows <= 0 || track.height <= 8 {
		return
	}
	rl.DrawRectangleRounded(track, 0.5, 4, rl.Color{40, 42, 54, 255})
	frac := f32(0)
	thumb_h := track.height
	if n > rows {
		frac = f32(clamp(first, 0, n - rows)) / f32(n - rows)
		thumb_h = max(track.height * f32(rows) / f32(n), 18)
	}
	thumb := rl.Rectangle{track.x, track.y + (track.height - thumb_h) * frac, track.width, thumb_h}
	rl.DrawRectangleRounded(thumb, 0.5, 4, rl.Color{130, 140, 170, 255})
}

// The left list panel's chrome: the box, the scrollbar and the "N / total"
// pager. The caller draws the rows themselves. The list has to be narrower than
// the panel so its rows never paint over the bar.
draw_list_chrome :: proc(v: List_View, n: int, panel: rl.Rectangle) {
	draw_panel(panel, rl.Color{18, 20, 28, 255}, rl.Color{60, 62, 80, 255}, 0.03, 6, 2)
	// The bar is placed off the *list*, not the panel, so its rows can never
	// paint over it however the caller sizes the two.
	draw_scrollbar(rl.Rectangle{v.x + v.w + 6, v.y + 4, 5, f32(v.rows) * v.row_h - 8}, v.first, v.rows, n)
	if n > 0 {
		rl.DrawText(fmt.ctprintf("%d / %d", v.index + 1, n), i32(panel.x) + 10, i32(panel.y + panel.height) + 6, 15, rl.Color{150, 150, 170, 255})
	}
}

// The borderless row highlight the list screens use (selected / hover).
draw_list_row_bg :: proc(rec: rl.Rectangle, selected, hover: bool) {
	if selected {
		rl.DrawRectangleRounded(rec, 0.3, 6, rl.Color{40, 50, 44, 255})
	} else if hover {
		rl.DrawRectangleRounded(rec, 0.3, 6, rl.Color{28, 30, 40, 255})
	}
}

// ----------------------------------------------------------------------------
// Hover tooltips
//
// Immediate-mode UI can't pop a tooltip at the moment of hover (later draws
// would cover it), so a hovered widget queues a line here and the frame draws
// it last. The string is owned and freed at the start of the next frame. This
// lives at package scope so battle drawing (which has no ^Game) can use it too.
// ----------------------------------------------------------------------------

@(private)
g_tooltip: string

@(private)
g_tooltips_on := true

ui_set_tooltips :: proc(on: bool) {
	g_tooltips_on = on
}

tooltip_clear :: proc() {
	if g_tooltip != "" {
		delete(g_tooltip)
		g_tooltip = ""
	}
}

// Queue a tooltip for the hovered widget. Last call in a frame wins.
tooltip_set :: proc(format: string, args: ..any) {
	if !g_tooltips_on {
		return
	}
	if g_tooltip != "" {
		delete(g_tooltip)
	}
	g_tooltip = fmt.aprintf(format, ..args)
}

// Queue a tooltip from an already-built (heap) string, taking ownership.
tooltip_set_owned :: proc(s: string) {
	if !g_tooltips_on {
		delete(s)
		return
	}
	if g_tooltip != "" {
		delete(g_tooltip)
	}
	g_tooltip = s
}

// Draw the queued tooltip near the cursor, wrapped and kept on screen.
// Call last, after every other draw, so it sits on top.
tooltip_draw :: proc() {
	if !g_tooltips_on || g_tooltip == "" {
		return
	}
	font := i32(15)
	pad := f32(9)
	line_h := f32(font) + 3
	max_w := i32(460)

	// Greedy word-wrap into byte ranges of g_tooltip (no allocation).
	starts: [10]int
	lens: [10]int
	nl := 0
	{
		i := 0
		for i < len(g_tooltip) && nl < len(starts) {
			line_start := i
			last_space := -1
			width := i32(0)
			j := i
			for j < len(g_tooltip) && g_tooltip[j] != '\n' {
				ch := g_tooltip[j]
				chw := rl.MeasureText(fmt.ctprintf("%c", ch), font)
				if width + chw > max_w && j > line_start {
					break
				}
				if ch == ' ' {
					last_space = j
				}
				width += chw
				j += 1
			}
			brk := j
			if j < len(g_tooltip) && g_tooltip[j] != '\n' && last_space > line_start {
				brk = last_space
			}
			if brk <= line_start {
				brk = line_start + 1
			}
			starts[nl] = line_start
			lens[nl] = brk - line_start
			nl += 1
			i = brk
			if i < len(g_tooltip) && (g_tooltip[i] == ' ' || g_tooltip[i] == '\n') {
				i += 1
			}
		}
	}
	if nl == 0 {
		return
	}

	// Measure the wrapped box.
	max_line_w := i32(0)
	buf: [512]u8
	for k in 0..<nl {
		cnt := min(lens[k], len(buf) - 1)
		copy(buf[:cnt], g_tooltip[starts[k]:starts[k] + cnt])
		buf[cnt] = 0
		w := rl.MeasureText(cstring(raw_data(buf[:])), font)
		if w > max_line_w {
			max_line_w = w
		}
	}
	box_w := f32(max_line_w) + pad * 2
	box_h := f32(nl) * line_h + pad * 2 - 3

	mp := mouse_pos()
	x := mp.x + 16
	y := mp.y + 18
	sw := f32(screen_w())
	sh := f32(screen_h())
	if x + box_w > sw - 8 {
		x = mp.x - box_w - 12
	}
	if y + box_h > sh - 8 {
		y = mp.y - box_h - 12
	}
	x = clamp(x, 6, max(sw - box_w - 6, 6))
	y = clamp(y, 6, max(sh - box_h - 6, 6))

	rec := rl.Rectangle{x, y, box_w, box_h}
	rl.DrawRectangleRounded(rec, 0.18, 6, rl.Color{12, 12, 18, 246})
	rl.DrawRectangleRoundedLinesEx(rec, 0.18, 6, 1, rl.Color{130, 130, 150, 255})
	for k in 0..<nl {
		cnt := min(lens[k], len(buf) - 1)
		copy(buf[:cnt], g_tooltip[starts[k]:starts[k] + cnt])
		buf[cnt] = 0
		rl.DrawText(cstring(raw_data(buf[:])), i32(x) + i32(pad), i32(y + pad + f32(k) * line_h), font,
			rl.Color{235, 235, 245, 255})
	}
}

// Format an integer with thousands separators into `buf`, returning a string.
// Callers pass a scratch buffer so several can be used in one format string.
fmt_thousands :: proc(buf: []u8, v: int) -> string {
	n := v
	neg := n < 0
	if neg {
		n = -n
	}
	i := len(buf)
	if n == 0 {
		i -= 1
		buf[i] = '0'
	} else {
		digits := 0
		for n > 0 {
			if digits > 0 && digits % 3 == 0 {
				i -= 1
				buf[i] = ','
			}
			i -= 1
			buf[i] = u8('0' + u8(n % 10))
			n /= 10
			digits += 1
		}
	}
	if neg {
		i -= 1
		buf[i] = '-'
	}
	return string(buf[i:])
}

// ----------------------------------------------------------------------------
// Cursor feedback: hovered widgets mark the frame as "wants a hand cursor".
// ----------------------------------------------------------------------------

@(private)
g_hand: bool

ui_cursor_reset :: proc() {
	g_hand = false
}

ui_want_hand :: proc() {
	g_hand = true
}

ui_cursor_apply :: proc() {
	rl.SetMouseCursor(g_hand ? .POINTING_HAND : .DEFAULT)
}
