package main

import rl "vendor:raylib"
import "core:fmt"
import "core:math"
running_on_web :: proc() -> bool {
	when ODIN_ARCH == .wasm32 || ODIN_ARCH == .wasm64p32 {
		return true
	}
	return false
}

TITLE_BUTTON_W :: f32(320)
TITLE_BUTTON_H :: f32(58)
TITLE_BUTTON_GAP :: f32(16)

title_button_rect :: proc(i: int) -> rl.Rectangle {
	sw := f32(rl.GetScreenWidth())
	sh := f32(rl.GetScreenHeight())
	y := sh * 0.54 + f32(i) * (TITLE_BUTTON_H + TITLE_BUTTON_GAP)
	return rl.Rectangle{sw / 2 - TITLE_BUTTON_W / 2, y, TITLE_BUTTON_W, TITLE_BUTTON_H}
}

update_title :: proc(g: ^Game) {
	if rl.IsKeyPressed(.ENTER) || rl.IsKeyPressed(.SPACE) {
		reset_to_starter(g)
		return
	}
	if rl.IsKeyPressed(.L) {
		g.show_save = true
		return
	}
	if !rl.IsMouseButtonPressed(.LEFT) {
		return
	}
	mp := rl.GetMousePosition()
	if rl.CheckCollisionPointRec(mp, title_button_rect(0)) {
		reset_to_starter(g)
		return
	}
	if rl.CheckCollisionPointRec(mp, title_button_rect(1)) {
		g.show_save = true
		return
	}
	if !running_on_web() && rl.CheckCollisionPointRec(mp, title_button_rect(2)) {
		g.quit = true
		return
	}
}

draw_title :: proc(g: ^Game) {
	sw := f32(rl.GetScreenWidth())
	sh := f32(rl.GetScreenHeight())
	rl.ClearBackground(rl.Color{9, 10, 16, 255})

	cx := sw / 2
	cy := sh * 0.30
	t := f32(rl.GetTime())

	// Soft breathing glow behind the title.
	for i := 9; i >= 1; i -= 1 {
		r := f32(i) * 44 + math.sin(t * 1.4) * 6
		a := u8(8 + (9 - i) * 2)
		rl.DrawCircleV(rl.Vector2{cx, cy}, r, rl.Color{58, 78, 140, a})
	}

	title := cstring("MONSTER COLONY")
	tw := rl.MeasureText(title, 76)
	rl.DrawText(title, i32(cx) - tw / 2 + 3, i32(cy) - 52 + 3, 76, rl.Color{0, 0, 0, 150})
	rl.DrawText(title, i32(cx) - tw / 2, i32(cy) - 52, 76, rl.Color{236, 232, 250, 255})

	tag := cstring("Build a colony in the deep. Raise monsters. Delve.")
	tgw := rl.MeasureText(tag, 20)
	rl.DrawText(tag, i32(cx) - tgw / 2, i32(cy) + 42, 20, rl.Color{150, 160, 185, 255})

	draw_button(title_button_rect(0), cstring("New Game"), true, BUTTON_TITLE, 26)
	draw_button(title_button_rect(1), cstring("Load Game"), true, BUTTON_TITLE, 26)
	if !running_on_web() {
		draw_button(title_button_rect(2), cstring("Quit"), true, BUTTON_TITLE, 26)
	}

	hint := cstring("Enter: new game   |   L: load game")
	hw := rl.MeasureText(hint, 15)
	rl.DrawText(hint, i32(cx) - hw / 2, i32(sh) - 40, 15, rl.Color{110, 115, 135, 255})
}

// ----------------------------------------------------------------------------
// Starter screen
// ----------------------------------------------------------------------------

starter_rect :: proc(i: int) -> rl.Rectangle {
	sw := f32(rl.GetScreenWidth())
	sh := f32(rl.GetScreenHeight())
	w := f32(280)
	h := f32(470)
	gap := f32(34)
	total := 3 * w + 2 * gap
	start := sw / 2 - total / 2
	return rl.Rectangle{start + f32(i) * (w + gap), sh / 2 - h / 2 - 10, w, h}
}

draw_starter :: proc() {
	sw := f32(rl.GetScreenWidth())
	sh := f32(rl.GetScreenHeight())
	rl.ClearBackground(rl.Color{12, 12, 20, 255})

	title := cstring("CHOOSE YOUR STARTER")
	tw := rl.MeasureText(title, 38)
	rl.DrawText(title, i32(sw) / 2 - tw / 2, 34, 38, rl.Color{225, 225, 240, 255})
	sub := cstring("Build a colony, raise your monsters, and delve to floor 10")
	sw2 := rl.MeasureText(sub, 16)
	rl.DrawText(sub, i32(sw) / 2 - sw2 / 2, 82, 16, rl.Color{140, 140, 160, 255})

	mp := rl.GetMousePosition()
	for idx in 0..<len(STARTER_SPECIES) {
		sp := SPECIES[STARTER_SPECIES[idx]]
		rec := starter_rect(idx)
		hover := rl.CheckCollisionPointRec(mp, rec)

		bg := rl.Color{24, 24, 34, 255}
		if hover {
			bg = rl.Color{34, 36, 48, 255}
		}
		rl.DrawRectangleRounded(rec, 0.05, 8, bg)
		rl.DrawRectangleRoundedLinesEx(rec, 0.05, 8, 3, sp.color)

		// Number-key badge (press 1/2/3 to pick this starter).
		badge := rl.Rectangle{rec.x + 12, rec.y + 12, 30, 30}
		rl.DrawRectangleRounded(badge, 0.3, 6, rl.Color{0, 0, 0, 120})
		rl.DrawRectangleRoundedLinesEx(badge, 0.3, 6, 2, sp.color)
		kn := fmt.ctprintf("%d", idx + 1)
		kw := rl.MeasureText(kn, 20)
		rl.DrawText(kn, i32(badge.x + badge.width / 2) - kw / 2, i32(badge.y + badge.height / 2) - 10, 20, rl.Color{235, 240, 250, 255})

		circle := rl.Vector2{rec.x + rec.width / 2, rec.y + 74}
		rl.DrawCircleV(circle, 46, sp.color)
		rl.DrawCircleLinesV(circle, 46, rl.Color{235, 235, 245, 255})
		initial := fmt.ctprintf("%c", sp.name[0])
		iw := rl.MeasureText(initial, 44)
		rl.DrawText(initial, i32(circle.x) - iw / 2, i32(circle.y) - 22, 44, rl.Color{255, 255, 255, 255})

		name := fmt.ctprintf("%s", sp.name)
		nw := rl.MeasureText(name, 26)
		rl.DrawText(name, i32(rec.x + rec.width / 2) - nw / 2, i32(rec.y) + 126, 26, rl.Color{235, 235, 245, 255})

		elem := element_name(sp.elements[0])
		ew := rl.MeasureText(elem, 17)
		rl.DrawText(elem, i32(rec.x + rec.width / 2) - ew / 2, i32(rec.y) + 158, 17, sp.color)

		line1 := fmt.ctprintf("HP %d   PWR x%s   DEF %s", sp.base_hp, fmt_num(sp.base_power), fmt_num(sp.base_defense))
		l1w := rl.MeasureText(line1, 15)
		rl.DrawText(line1, i32(rec.x + rec.width / 2) - l1w / 2, i32(rec.y) + 184, 15, rl.Color{192, 192, 212, 255})

		line2 := fmt.ctprintf("SPD %s   Learnset %d moves", fmt_num(sp.base_speed), len(sp.learnset))
		l2w := rl.MeasureText(line2, 15)
		rl.DrawText(line2, i32(rec.x + rec.width / 2) - l2w / 2, i32(rec.y) + 204, 15, rl.Color{192, 192, 212, 255})

		line3 := fmt.ctprintf("Energy %d regen / %d max", sp.base_energy, sp.base_energy_max)
		l3w := rl.MeasureText(line3, 15)
		rl.DrawText(line3, i32(rec.x + rec.width / 2) - l3w / 2, i32(rec.y) + 224, 15, rl.Color{192, 192, 212, 255})

		abs := species_abilities(STARTER_SPECIES[idx])
		ab_line := fmt.ctprintf("%s / %s / %s", ability_name(abs[0]), ability_name(abs[1]), ability_name(abs[2]))
		abw := rl.MeasureText(ab_line, 13)
		rl.DrawText(ab_line, i32(rec.x + rec.width / 2) - abw / 2, i32(rec.y) + 244, 13, rl.Color{200, 180, 240, 255})

		rl.DrawText("STARTS WITH", i32(rec.x) + 20, i32(rec.y) + 268, 14, rl.Color{150, 150, 170, 255})

		counts: [Move_Id]int
		shown: [Move_Id]bool
		for m in sp.starter {
			counts[m] += 1
		}
		ly := i32(rec.y) + 290
		for m in sp.starter {
			if shown[m] {
				continue
			}
			shown[m] = true
			label := fmt.ctprintf("%s", MOVE_DATA[m].name)
			rl.DrawText(label, i32(rec.x) + 20, ly, 14, element_color(MOVE_DATA[m].element))
			if counts[m] > 1 {
				cnt_s := fmt.ctprintf("x%d", counts[m])
				cw := rl.MeasureText(cnt_s, 14)
				rl.DrawText(cnt_s, i32(rec.x + rec.width) - 20 - cw, ly, 14, rl.Color{150, 150, 170, 255})
			}
			ly += 20
		}

		pick := fmt.ctprintf("Click or press %d", idx + 1)
		pkw := rl.MeasureText(pick, 16)
		rl.DrawText(pick, i32(rec.x + rec.width / 2) - pkw / 2, i32(rec.y + rec.height) - 34, 16, rl.Color{200, 210, 180, 255})
	}
}

// ----------------------------------------------------------------------------
// Game over
// ----------------------------------------------------------------------------

draw_colony_game_over :: proc(turns: int) {
	sw := f32(rl.GetScreenWidth())
	sh := f32(rl.GetScreenHeight())

	rl.ClearBackground(rl.Color{28, 8, 12, 255})

	title := cstring("YOUR COLONY HAS FALLEN")
	tw := rl.MeasureText(title, 56)
	rl.DrawText(title, i32(sw) / 2 - tw / 2, i32(sh) / 2 - 100, 56, rl.Color{220, 60, 60, 255})

	sub := fmt.ctprintf("Your last monster fell on turn %d.", turns)
	sw2 := rl.MeasureText(sub, 22)
	rl.DrawText(sub, i32(sw) / 2 - sw2 / 2, i32(sh) / 2 - 10, 22, rl.Color{228, 228, 238, 255})

	hint := cstring("N: begin again   |   Esc: main menu")
	hw := rl.MeasureText(hint, 26)
	rl.DrawText(hint, i32(sw) / 2 - hw / 2, i32(sh) / 2 + 56, 26, rl.Color{220, 180, 120, 255})
}

// ----------------------------------------------------------------------------
// Deck viewer (shows a roster monster's deck)
// ----------------------------------------------------------------------------

DV_COLS   :: 7
DV_CW     :: f32(104)
DV_CH     :: f32(140)
DV_GAP    :: f32(10)
DV_TOP    :: f32(176)
DV_BOTTOM :: f32(64)
