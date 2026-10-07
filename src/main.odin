package main

import rl "vendor:raylib"
import "core:time"
import "core:math"
import "core:fmt"

Game_Mode :: enum { STARTER, MAP, GAME_OVER }

Game :: struct {
	mode:     Game_Mode,
	renderer: Hex_Renderer,
	colony:   Colony,
	has_colony: bool,
	selected: int, // roster index of the selected monster, or -1

	// deck viewer overlay
	show_deck:   bool,
	view_index:  int,
	view_scroll: f32,

	status:       cstring,
	status_timer: f32,

	// build / trade overlays
	build_mode: bool,
	build_hex:  Hex,
	has_build:  bool,
	trade_open: bool,

	seed_rng: Rng,
}

main :: proc() {
	rl.SetConfigFlags({.WINDOW_RESIZABLE, .MSAA_4X_HINT})
	rl.InitWindow(1280, 720, "Vibegambling - Colony")
	defer rl.CloseWindow()
	rl.SetTargetFPS(60)

	g: Game
	g.seed_rng = rng_make(u64(time.now()._nsec))
	g.selected = -1

	hex_renderer_init(&g.renderer, 46.0, int(rl.GetScreenWidth()), int(rl.GetScreenHeight()))

	reset_to_starter(&g)
	defer end_run(&g)

	for !rl.WindowShouldClose() {
		dt := rl.GetFrameTime()

		g.renderer.origin_x = f32(rl.GetScreenWidth()) / 2
		g.renderer.origin_y = f32(rl.GetScreenHeight()) / 2

		game_update(&g, dt)

		rl.BeginDrawing()
		game_draw(&g)
		rl.EndDrawing()
	}
}

// ----------------------------------------------------------------------------
// Lifecycle
// ----------------------------------------------------------------------------

end_run :: proc(g: ^Game) {
	if g.has_colony {
		colony_free(&g.colony)
		g.has_colony = false
	}
}

reset_to_starter :: proc(g: ^Game) {
	end_run(g)
	g.show_deck = false
	g.mode = .STARTER
}

choose_starter :: proc(g: ^Game, species_idx: int) {
	end_run(g)
	g.colony = colony_generate(rng_next_u64(&g.seed_rng), 11, 8)
	g.has_colony = true
	g.selected = colony_add_starter(&g.colony, species_idx)
	g.mode = .MAP
	g.status = "Click an adjacent tile to move your monster. Space ends the turn."
	g.status_timer = 6
	center_camera_on(&g.renderer, g.colony.start_hex)
}

set_status :: proc(g: ^Game, msg: cstring) {
	g.status = msg
	g.status_timer = 3.0
}

// ----------------------------------------------------------------------------
// Update
// ----------------------------------------------------------------------------

game_update :: proc(g: ^Game, dt: f32) {
	if g.status_timer > 0 {
		g.status_timer -= dt
	}

	if g.show_deck {
		update_deck_viewer(g, dt)
		return
	}
	if g.mode == .MAP && len(g.colony.roster) > 0 && rl.IsKeyPressed(.V) {
		g.show_deck = true
		g.view_index = clamp(g.selected, 0, len(g.colony.roster) - 1)
		g.view_scroll = 0
		return
	}

	switch g.mode {
	case .STARTER:
		update_starter(g)
	case .MAP:
		update_colony(g, dt)
	case .GAME_OVER:
		if rl.IsKeyPressed(.N) {
			reset_to_starter(g)
		}
	}
}

update_starter :: proc(g: ^Game) {
	if !rl.IsMouseButtonPressed(.LEFT) {
		return
	}
	mp := rl.GetMousePosition()
	for i in 0..<len(STARTER_SPECIES) {
		if rl.CheckCollisionPointRec(mp, starter_rect(i)) {
			choose_starter(g, STARTER_SPECIES[i])
			return
		}
	}
}

update_colony :: proc(g: ^Game, dt: f32) {
	hex_renderer_update_camera(&g.renderer, dt)

	if rl.IsMouseButtonDown(.RIGHT) {
		d := rl.GetMouseDelta()
		g.renderer.camera_x -= d.x / g.renderer.zoom
		g.renderer.camera_y -= d.y / g.renderer.zoom
	}
	if rl.IsKeyPressed(.R) {
		center_camera_on(&g.renderer, g.colony.start_hex)
	}

	// Build mode toggles.
	if rl.IsKeyPressed(.B) {
		g.build_mode = !g.build_mode
		g.trade_open = false
		g.has_build = false
		if g.build_mode {
			set_status(g, "Build mode: click a tile, then pick an improvement. B/Esc exits.")
		}
		return
	}
	if g.build_mode {
		update_build(g)
		return
	}

	// Trading Post UI.
	if g.trade_open {
		update_trade(g)
		return
	}
	if rl.IsKeyPressed(.T) && selected_on_trading_post(g) {
		g.trade_open = true
		return
	}

	// End turn.
	if rl.IsKeyPressed(.SPACE) || rl.IsKeyPressed(.E) {
		do_end_turn(g)
		return
	}

	// Cycle selection through the roster.
	if rl.IsKeyPressed(.TAB) {
		n := len(g.colony.roster)
		if n > 0 {
			next := g.selected + 1
			if g.selected < 0 || next >= n {
				next = 0
			}
			g.selected = next
		}
		return
	}

	mp := rl.GetMousePosition()
	if rl.IsMouseButtonPressed(.LEFT) {
		if rl.CheckCollisionPointRec(mp, colony_end_turn_rect()) {
			do_end_turn(g)
			return
		}
		for i in 0..<len(g.colony.roster) {
			if rl.CheckCollisionPointRec(mp, roster_entry_rect(i)) {
				g.selected = i
				return
			}
		}
	}

	hovered := hex_renderer_hovered(&g.renderer)

	if g.selected >= 0 && g.selected < len(g.colony.roster) {
		m := &g.colony.roster[g.selected]
		if rl.IsMouseButtonPressed(.LEFT) && hex_distance(m.pos, hovered) == 1 {
			res := colony_move(&g.colony, g.selected, hovered)
			switch res {
			case 0:
				set_status(g, "Moved.")
			case 2:
				set_status(g, "Blocked (water needs a water monster or bridge).")
			case 3:
				set_status(g, "That tile is full (max 6).")
			case 4:
				set_status(g, "Not enough movement energy.")
			case:
				set_status(g, "Can't move there.")
			}
			return
		}
	}

	if rl.IsMouseButtonPressed(.LEFT) {
		idx := first_player_monster_on(&g.colony, hovered)
		g.selected = idx
	}
}

selected_on_trading_post :: proc(g: ^Game) -> bool {
	if g.selected < 0 || g.selected >= len(g.colony.roster) {
		return false
	}
	t := tile_at(&g.colony, g.colony.roster[g.selected].pos)
	return t != nil && t.terrain == .TRADING_POST
}

update_build :: proc(g: ^Game) {
	if rl.IsKeyPressed(.ESCAPE) {
		g.build_mode = false
		g.has_build = false
		return
	}
	if !rl.IsMouseButtonPressed(.LEFT) {
		return
	}
	mp := rl.GetMousePosition()

	if g.has_build {
		if t := tile_at(&g.colony, g.build_hex); t != nil {
			opts: [8]Improvement
			n := buildable_improvements(t.terrain, opts[:])
			for i in 0..<n {
				if rl.CheckCollisionPointRec(mp, build_option_rect(i)) {
					res := colony_build(&g.colony, g.build_hex, opts[i])
					switch res {
					case 0: set_status(g, "Improvement built.")
					case 1: set_status(g, "Can't build that on this terrain.")
					case 2: set_status(g, "Tile already improved.")
					case 3: set_status(g, "Not enough gold.")
					}
					return
				}
			}
		}
	}

	hovered := hex_renderer_hovered(&g.renderer)
	if t := tile_at(&g.colony, hovered); t != nil && t.revealed {
		g.build_hex = hovered
		g.has_build = true
	}
}

update_trade :: proc(g: ^Game) {
	if rl.IsKeyPressed(.ESCAPE) || rl.IsKeyPressed(.T) {
		g.trade_open = false
		return
	}
	if !rl.IsMouseButtonPressed(.LEFT) {
		return
	}
	mp := rl.GetMousePosition()
	s := g.selected

	if s >= 0 && s < len(g.colony.roster) {
		if rl.CheckCollisionPointRec(mp, trade_heal_rect()) {
			res := colony_heal(&g.colony, s)
			set_status(g, res == 0 ? "Healed." : res == 2 ? "Not enough gold." : "Already at full HP.")
			return
		}
		if rl.CheckCollisionPointRec(mp, trade_energy_rect()) {
			res := colony_refill_energy(&g.colony, s)
			set_status(g, res == 0 ? "Energy refilled." : "Not enough gold.")
			return
		}
	}
	for i in 0..<len(g.colony.graveyard) {
		if rl.CheckCollisionPointRec(mp, trade_revive_rect(i)) {
			res := colony_revive(&g.colony, i)
			set_status(g, res == 0 ? "Revived." : res == 2 ? "Not enough gold." : "Start tile is full.")
			return
		}
	}
	g.trade_open = false
}

// Shared lose condition: no living monsters, whether from starvation or battle.
check_game_over :: proc(g: ^Game) {
	if g.mode == .MAP && player_monster_count(&g.colony) == 0 {
		g.mode = .GAME_OVER
	}
}

do_end_turn :: proc(g: ^Game) {
	colony_end_turn(&g.colony)
	if player_monster_count(&g.colony) == 0 {
		g.mode = .GAME_OVER
	} else {
		set_status(g, "Turn advanced.")
	}
}

player_monster_count :: proc(c: ^Colony) -> int {
	n := 0
	for m in c.roster {
		if !m.wild {
			n += 1
		}
	}
	return n
}

// ----------------------------------------------------------------------------
// Draw
// ----------------------------------------------------------------------------

game_draw :: proc(g: ^Game) {
	switch g.mode {
	case .STARTER:
		draw_starter()
	case .MAP:
		draw_colony(g)
		if g.build_mode {
			draw_build_panel(g)
		}
		if g.trade_open {
			draw_trade_panel(g)
		}
	case .GAME_OVER:
		draw_colony_game_over(g.colony.turn)
	}

	if g.show_deck {
		draw_deck_viewer(g)
	}
}

draw_colony :: proc(g: ^Game) {
	rl.ClearBackground(rl.Color{10, 12, 16, 255})

	// Tiles (fog of war: only explored tiles are drawn).
	for t in g.colony.tiles {
		if !t.revealed {
			continue
		}
		draw_hex(&g.renderer, t.hex, terrain_color(t.terrain), HEX_BORDER, 2.0 * g.renderer.zoom)

		if t.improvement != .NONE {
			cx, cy := hex_to_screen(&g.renderer, t.hex)
			label := improvement_label(t.improvement)
			lw := rl.MeasureText(label, 20)
			rl.DrawText(label, i32(cx) - lw / 2, i32(cy) - 10, 20, rl.Color{20, 20, 20, 255})
		}
	}

	draw_move_highlights(g)
	draw_map_monsters(g)
	draw_hover_marker(&g.renderer, hex_renderer_hovered(&g.renderer), true)
	draw_colony_hud(g)
	draw_roster_panel(g)
	draw_end_turn_button(g)
	draw_terrain_legend()
}

draw_map_monsters :: proc(g: ^Game) {
	for i in 0..<len(g.colony.roster) {
		m := &g.colony.roster[i]
		t := tile_at(&g.colony, m.pos)
		if t == nil || !t.revealed {
			continue
		}
		idx := 0
		for j in 0..<i {
			if !g.colony.roster[j].wild && hex_equal(g.colony.roster[j].pos, m.pos) {
				idx += 1
			}
		}
		n := max(monsters_on_tile(&g.colony, m.pos, false), 1)
		cx, cy := hex_to_screen(&g.renderer, m.pos)
		px, py := f32(cx), f32(cy)
		if n > 1 {
			angle := f32(idx) / f32(n) * 2.0 * math.PI - math.PI / 2.0
			px += math.cos(angle) * 15.0 * g.renderer.zoom
			py += math.sin(angle) * 15.0 * g.renderer.zoom
		}
		radius := 9.0 * g.renderer.zoom
		rl.DrawCircleV(rl.Vector2{px, py}, radius, creature_color(&m.creature))
		rl.DrawCircleLinesV(rl.Vector2{px, py}, radius, element_color(creature_element(&m.creature)))
		if i == g.selected {
			rl.DrawCircleLinesV(rl.Vector2{px, py}, radius + 3 * g.renderer.zoom, rl.Color{255, 245, 140, 255})
		}
		if m.food < 40 {
			rl.DrawCircleV(rl.Vector2{px + 7 * g.renderer.zoom, py - 7 * g.renderer.zoom}, 4 * g.renderer.zoom, rl.Color{220, 70, 70, 255})
		}
	}
}

draw_hover_marker :: proc(r: ^Hex_Renderer, hex: Hex, active: bool) {
	if !active {
		return
	}
	t := f32(rl.GetTime())
	pulse := 0.5 + 0.5 * abs(math.sin(t * 4.0))
	color := rl.Color{255, 245, 140, u8(120 + 100 * pulse)}
	draw_hex_outline(r, hex, color, (3.0 + 2.0 * pulse) * r.zoom)
}

draw_move_highlights :: proc(g: ^Game) {
	if g.selected < 0 || g.selected >= len(g.colony.roster) {
		return
	}
	m := &g.colony.roster[g.selected]
	for n in hex_neighbors(m.pos) {
		t := tile_at(&g.colony, n)
		if t == nil {
			continue
		}
		passable := tile_passable(&g.colony, m, n)
		cost := monster_move_cost(m, t.terrain)
		affordable := m.energy >= cost
		full := monsters_on_tile(&g.colony, n, false) >= MAX_MONSTERS_PER_TILE

		col := rl.Color{120, 220, 150, 70}
		if !passable || full {
			col = rl.Color{220, 90, 90, 70}
		} else if !affordable {
			col = rl.Color{220, 180, 90, 70}
		}
		draw_hex_filled(&g.renderer, n, col)

		if t.revealed && passable && !full {
			cx, cy := hex_to_screen(&g.renderer, n)
			label := fmt.ctprintf("%s", fmt_num(cost))
			lw := rl.MeasureText(label, 14)
			rl.DrawText(label, i32(cx) - lw / 2, i32(cy) + 14, 14, rl.Color{230, 240, 210, 255})
		}
	}
}

draw_colony_hud :: proc(g: ^Game) {
	sw := f32(rl.GetScreenWidth())
	sh := f32(rl.GetScreenHeight())

	rl.DrawText("THE COLONY", 20, 16, 26, rl.Color{215, 215, 235, 255})
	res := fmt.ctprintf("Floor %d    Turn %d", g.colony.floor, g.colony.turn)
	rl.DrawText(res, 20, 48, 18, rl.Color{140, 140, 165, 255})

	x := i32(20)
	gold := fmt.ctprintf("Gold %d / %d", colony_total_gold(&g.colony), g.colony.gold_cap)
	rl.DrawText(gold, x, 78, 20, rl.Color{240, 205, 90, 255})
	x += rl.MeasureText(gold, 20) + 30

	if granary_count(&g.colony) == 0 {
		rl.DrawText("Food: no granary", x, 78, 20, rl.Color{150, 170, 150, 255})
		x += rl.MeasureText("Food: no granary", 20) + 30
	} else {
		food := fmt.ctprintf("Food stored %d / %d", colony_total_food(&g.colony), g.colony.food_cap)
		rl.DrawText(food, x, 78, 20, rl.Color{140, 220, 130, 255})
		x += rl.MeasureText(food, 20) + 30
	}

	cryst := fmt.ctprintf("Crystals %d", g.colony.crystals)
	rl.DrawText(cryst, x, 78, 20, rl.Color{150, 210, 255, 255})

	upkeep := 0
	for &m in g.colony.roster {
		if !m.wild {
			upkeep += monster_upkeep(&m)
		}
	}
	up := fmt.ctprintf("Upkeep %d food/turn    Monsters %d", upkeep, player_monster_count(&g.colony))
	rl.DrawText(up, 20, 106, 16, rl.Color{150, 150, 175, 255})

	// Hovered tile info + selected monster.
	hovered := hex_renderer_hovered(&g.renderer)
	if t := tile_at(&g.colony, hovered); t != nil && t.revealed {
		info := fmt.ctprintf("Tile: %s%s", terrain_name(t.terrain), t.improvement != .NONE ? " (improved)" : "")
		rl.DrawText(info, 20, 130, 16, rl.Color{180, 180, 200, 255})
	}

	rl.DrawText("Move: click adjacent tile | select: click own tile / TAB | Space end turn | B build | T trade | V deck", 20, i32(sh) - 70, 16, rl.Color{120, 120, 145, 255})
	rl.DrawText("RMB/WASD pan  |  wheel zoom  |  R recenter  |  N new run", 20, i32(sh) - 46, 16, rl.Color{120, 120, 145, 255})

	if g.status_timer > 0 {
		w := rl.MeasureText(g.status, 22)
		rl.DrawText(g.status, i32(sw) / 2 - w / 2, i32(sh) - 110, 22, rl.Color{235, 235, 250, 255})
	}
}

// ----------------------------------------------------------------------------
// Roster panel
// ----------------------------------------------------------------------------

roster_entry_rect :: proc(i: int) -> rl.Rectangle {
	sw := f32(rl.GetScreenWidth())
	return rl.Rectangle{sw - 240, 180 + f32(i) * 60, 224, 56}
}

draw_roster_panel :: proc(g: ^Game) {
	sw := f32(rl.GetScreenWidth())
	rl.DrawText("MONSTERS", i32(sw) - 236, 152, 18, rl.Color{170, 170, 190, 255})

	for &m, i in g.colony.roster {
		if m.wild {
			continue
		}
		rec := roster_entry_rect(i)
		sel := i == g.selected
		bg := rl.Color{24, 24, 34, 255}
		if sel {
			bg = rl.Color{36, 46, 40, 255}
		}
		rl.DrawRectangleRounded(rec, 0.16, 6, bg)
		border := rl.Color{60, 60, 78, 255}
		if sel {
			border = rl.Color{120, 230, 180, 255}
		}
		rl.DrawRectangleRoundedLinesEx(rec, 0.16, 6, 2, border)

		rl.DrawCircleV(rl.Vector2{rec.x + 24, rec.y + 26}, 16, creature_color(&m.creature))
		rl.DrawCircleLinesV(rl.Vector2{rec.x + 24, rec.y + 26}, 16, element_color(creature_element(&m.creature)))

		name := fmt.ctprintf("%s  Lv%d", m.creature.name, m.creature.level)
		rl.DrawText(name, i32(rec.x) + 48, i32(rec.y) + 5, 15, rl.Color{225, 225, 240, 255})

		hp := fmt.ctprintf("HP %d/%d", m.creature.hp, m.creature.max_hp)
		rl.DrawText(hp, i32(rec.x) + 48, i32(rec.y) + 23, 13, rl.Color{210, 130, 130, 255})

		pct := int(m.food / max(monster_satiety_max(&m), 1.0) * 100)
		food := fmt.ctprintf("Food %d%%   En %s", pct, fmt_num(m.energy))
		rl.DrawText(food, i32(rec.x) + 48, i32(rec.y) + 39, 12, rl.Color{150, 210, 150, 255})
	}
}

// ----------------------------------------------------------------------------
// End turn button + legends
// ----------------------------------------------------------------------------

colony_end_turn_rect :: proc() -> rl.Rectangle {
	sw := f32(rl.GetScreenWidth())
	sh := f32(rl.GetScreenHeight())
	return rl.Rectangle{sw - 240, sh - 120, 224, 48}
}

draw_end_turn_button :: proc(g: ^Game) {
	rec := colony_end_turn_rect()
	hover := rl.CheckCollisionPointRec(rl.GetMousePosition(), rec)
	col := rl.Color{70, 130, 100, 255}
	if hover {
		col = rl.Color{95, 175, 130, 255}
	}
	rl.DrawRectangleRounded(rec, 0.25, 8, col)
	rl.DrawRectangleRoundedLinesEx(rec, 0.25, 8, 2, rl.Color{210, 230, 220, 255})
	lbl := cstring("End Turn (Space)")
	w := rl.MeasureText(lbl, 18)
	rl.DrawText(lbl, i32(rec.x + rec.width / 2) - w / 2, i32(rec.y + rec.height / 2) - 9, 18, rl.Color{240, 255, 245, 255})
}

// ----------------------------------------------------------------------------
// Phase 2: build panel + Trading Post
// ----------------------------------------------------------------------------

build_panel_rect :: proc() -> rl.Rectangle {
	return rl.Rectangle{20, 210, 360, 350}
}

build_option_rect :: proc(i: int) -> rl.Rectangle {
	p := build_panel_rect()
	return rl.Rectangle{p.x + 12, p.y + 120 + f32(i) * 58, p.width - 24, 52}
}

draw_build_panel :: proc(g: ^Game) {
	p := build_panel_rect()
	rl.DrawRectangleRounded(p, 0.04, 8, rl.Color{18, 18, 26, 240})
	rl.DrawRectangleRoundedLinesEx(p, 0.04, 8, 2, rl.Color{120, 120, 150, 255})
	rl.DrawText("BUILD", i32(p.x) + 16, i32(p.y) + 12, 22, rl.Color{220, 220, 235, 255})

	if !g.has_build {
		rl.DrawText("Click a revealed tile", i32(p.x) + 16, i32(p.y) + 52, 16, rl.Color{150, 150, 170, 255})
		rl.DrawText("B / Esc to exit", i32(p.x) + 16, i32(p.y) + 74, 15, rl.Color{120, 120, 140, 255})
		return
	}

	t := tile_at(&g.colony, g.build_hex)
	if t == nil {
		return
	}
	info := fmt.ctprintf("Tile: %s", terrain_name(t.terrain))
	rl.DrawText(info, i32(p.x) + 16, i32(p.y) + 46, 16, rl.Color{180, 180, 200, 255})
	gold := fmt.ctprintf("Gold: %d", colony_total_gold(&g.colony))
	rl.DrawText(gold, i32(p.x) + 16, i32(p.y) + 68, 16, rl.Color{240, 205, 90, 255})

	if t.improvement != .NONE {
		cur := fmt.ctprintf("Built: %s (hp %d)", improvement_name(t.improvement), t.improvement_hp)
		rl.DrawText(cur, i32(p.x) + 16, i32(p.y) + 96, 16, rl.Color{140, 220, 150, 255})
		return
	}

	opts: [8]Improvement
	n := buildable_improvements(t.terrain, opts[:])
	if n == 0 {
		rl.DrawText("No improvements available here", i32(p.x) + 16, i32(p.y) + 100, 15, rl.Color{200, 150, 150, 255})
		return
	}

	mp := rl.GetMousePosition()
	for i in 0..<n {
		im := opts[i]
		rec := build_option_rect(i)
		cost := improvement_cost(im)
		afford := colony_total_gold(&g.colony) >= cost
		hover := rl.CheckCollisionPointRec(mp, rec)

		bg := rl.Color{28, 28, 40, 255}
		if !afford {
			bg = rl.Color{30, 24, 26, 255}
		} else if hover {
			bg = rl.Color{40, 42, 56, 255}
		}
		rl.DrawRectangleRounded(rec, 0.14, 6, bg)
		rl.DrawRectangleRoundedLinesEx(rec, 0.14, 6, 2, afford ? rl.Color{120, 180, 120, 255} : rl.Color{120, 80, 80, 255})

		rl.DrawText(improvement_name(im), i32(rec.x) + 10, i32(rec.y) + 6, 16, rl.Color{225, 225, 240, 255})
		rl.DrawText(improvement_effect(im), i32(rec.x) + 10, i32(rec.y) + 28, 13, rl.Color{160, 160, 180, 255})
		cst := fmt.ctprintf("%dg", cost)
		cw := rl.MeasureText(cst, 16)
		rl.DrawText(cst, i32(rec.x + rec.width) - 10 - cw, i32(rec.y) + 6, 16, afford ? rl.Color{240, 205, 90, 255} : rl.Color{200, 120, 120, 255})
	}
}

trade_panel_rect :: proc() -> rl.Rectangle {
	sw := f32(rl.GetScreenWidth())
	sh := f32(rl.GetScreenHeight())
	return rl.Rectangle{sw / 2 - 230, sh / 2 - 210, 460, 420}
}

trade_heal_rect :: proc() -> rl.Rectangle {
	p := trade_panel_rect()
	return rl.Rectangle{p.x + 20, p.y + 84, p.width - 40, 50}
}

trade_energy_rect :: proc() -> rl.Rectangle {
	p := trade_panel_rect()
	return rl.Rectangle{p.x + 20, p.y + 144, p.width - 40, 50}
}

trade_revive_rect :: proc(i: int) -> rl.Rectangle {
	p := trade_panel_rect()
	return rl.Rectangle{p.x + 20, p.y + 220 + f32(i) * 58, p.width - 40, 52}
}

draw_trade_button :: proc(rec: rl.Rectangle, label: cstring, enabled: bool, cost_text: cstring) {
	hover := rl.CheckCollisionPointRec(rl.GetMousePosition(), rec)
	bg := rl.Color{30, 30, 42, 255}
	if !enabled {
		bg = rl.Color{26, 24, 26, 255}
	} else if hover {
		bg = rl.Color{44, 44, 58, 255}
	}
	rl.DrawRectangleRounded(rec, 0.16, 6, bg)
	rl.DrawRectangleRoundedLinesEx(rec, 0.16, 6, 2, enabled ? rl.Color{180, 160, 90, 255} : rl.Color{90, 80, 80, 255})
	rl.DrawText(label, i32(rec.x) + 12, i32(rec.y) + 14, 18, enabled ? rl.Color{235, 235, 245, 255} : rl.Color{140, 140, 150, 255})
	if cost_text != "" {
		cw := rl.MeasureText(cost_text, 16)
		rl.DrawText(cost_text, i32(rec.x + rec.width) - 12 - cw, i32(rec.y) + 15, 16, enabled ? rl.Color{240, 205, 90, 255} : rl.Color{150, 120, 120, 255})
	}
}

draw_trade_panel :: proc(g: ^Game) {
	sw := f32(rl.GetScreenWidth())
	sh := f32(rl.GetScreenHeight())
	rl.DrawRectangle(0, 0, i32(sw), i32(sh), rl.Color{0, 0, 0, 160})

	p := trade_panel_rect()
	rl.DrawRectangleRounded(p, 0.05, 8, rl.Color{20, 20, 30, 245})
	rl.DrawRectangleRoundedLinesEx(p, 0.05, 8, 2, rl.Color{180, 160, 90, 255})
	rl.DrawText("TRADING POST", i32(p.x) + 20, i32(p.y) + 16, 24, rl.Color{240, 210, 120, 255})
	gold := fmt.ctprintf("Gold: %d", colony_total_gold(&g.colony))
	rl.DrawText(gold, i32(p.x) + 20, i32(p.y) + 48, 16, rl.Color{220, 200, 120, 255})

	if g.selected >= 0 && g.selected < len(g.colony.roster) {
		m := &g.colony.roster[g.selected]

		hc := heal_cost(m)
		heal_label := hc > 0 ? fmt.ctprintf("Heal %s", m.creature.name) : cstring("Already at full HP")
		draw_trade_button(trade_heal_rect(), heal_label, hc > 0 && colony_total_gold(&g.colony) >= hc, hc > 0 ? fmt.ctprintf("%dg", hc) : "")

		ec := energy_cost(m)
		draw_trade_button(trade_energy_rect(), fmt.ctprintf("Refill movement energy"), colony_total_gold(&g.colony) >= ec, fmt.ctprintf("%dg", ec))
	}

	rl.DrawText("FALLEN (revive)", i32(p.x) + 20, i32(p.y) + 202, 15, rl.Color{180, 150, 150, 255})
	if len(g.colony.graveyard) == 0 {
		rl.DrawText("None", i32(p.x) + 20, i32(p.y) + 226, 15, rl.Color{130, 130, 145, 255})
	} else {
		for i in 0..<len(g.colony.graveyard) {
			m := &g.colony.graveyard[i]
			cost := revive_cost(m)
			label := fmt.ctprintf("Revive %s  Lv%d", m.creature.name, m.creature.level)
			draw_trade_button(trade_revive_rect(i), label, colony_total_gold(&g.colony) >= cost, fmt.ctprintf("%dg", cost))
		}
	}

	hint := cstring("T / Esc to close")
	hw := rl.MeasureText(hint, 16)
	rl.DrawText(hint, i32(p.x) + i32(p.width / 2) - hw / 2, i32(p.y + p.height) - 30, 16, rl.Color{150, 150, 170, 255})
}

Terrain_Legend_Entry :: struct {
	terrain: Terrain,
	label:   cstring,
}

draw_terrain_legend :: proc() {
	entries := [?]Terrain_Legend_Entry{
		{.CAVE,         "Cave"},
		{.WATER,        "Water"},
		{.DUNGEON,      "Dungeon"},
		{.GROVE,        "Grove"},
		{.TRADING_POST, "Trading Post"},
		{.BOSS_ROOM,    "Boss Room"},
	}
	sh := f32(rl.GetScreenHeight())
	x := i32(20)
	y := i32(sh) - 250
	rl.DrawText("TERRAIN", x, y - 24, 16, rl.Color{150, 150, 170, 255})
	for e, i in entries {
		ey := y + i32(i) * 22
		rl.DrawRectangle(x, ey, 16, 16, terrain_color(e.terrain))
		rl.DrawRectangleLines(x, ey, 16, 16, rl.Color{20, 20, 20, 255})
		rl.DrawText(e.label, x + 26, ey - 1, 15, rl.Color{170, 170, 190, 255})
	}
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

		circle := rl.Vector2{rec.x + rec.width / 2, rec.y + 74}
		rl.DrawCircleV(circle, 46, sp.color)
		rl.DrawCircleLinesV(circle, 46, rl.Color{235, 235, 245, 255})
		initial := fmt.ctprintf("%c", sp.name[0])
		iw := rl.MeasureText(initial, 44)
		rl.DrawText(initial, i32(circle.x) - iw / 2, i32(circle.y) - 22, 44, rl.Color{255, 255, 255, 255})

		name := fmt.ctprintf("%s", sp.name)
		nw := rl.MeasureText(name, 26)
		rl.DrawText(name, i32(rec.x + rec.width / 2) - nw / 2, i32(rec.y) + 126, 26, rl.Color{235, 235, 245, 255})

		elem := element_name(sp.element)
		ew := rl.MeasureText(elem, 17)
		rl.DrawText(elem, i32(rec.x + rec.width / 2) - ew / 2, i32(rec.y) + 158, 17, sp.color)

		line1 := fmt.ctprintf("HP %d   PWR %d   DEF %d", sp.base_hp, sp.base_power, sp.base_defense)
		l1w := rl.MeasureText(line1, 15)
		rl.DrawText(line1, i32(rec.x + rec.width / 2) - l1w / 2, i32(rec.y) + 184, 15, rl.Color{192, 192, 212, 255})

		line2 := fmt.ctprintf("SPD %d   Learnset %d moves", sp.base_speed, len(sp.learnset))
		l2w := rl.MeasureText(line2, 15)
		rl.DrawText(line2, i32(rec.x + rec.width / 2) - l2w / 2, i32(rec.y) + 204, 15, rl.Color{192, 192, 212, 255})

		line3 := fmt.ctprintf("Energy %d regen / %d max", sp.base_energy, sp.base_energy_max)
		l3w := rl.MeasureText(line3, 15)
		rl.DrawText(line3, i32(rec.x + rec.width / 2) - l3w / 2, i32(rec.y) + 224, 15, rl.Color{192, 192, 212, 255})

		rl.DrawText("STARTS WITH", i32(rec.x) + 20, i32(rec.y) + 252, 14, rl.Color{150, 150, 170, 255})

		counts: [Move_Id]int
		shown: [Move_Id]bool
		for m in sp.starter {
			counts[m] += 1
		}
		ly := i32(rec.y) + 274
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

		pick := cstring("Click to choose")
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

	hint := cstring("Press N to begin again")
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

deck_max_scroll :: proc(g: ^Game) -> f32 {
	if len(g.colony.roster) == 0 {
		return 0
	}
	n := len(g.colony.roster[g.view_index].creature.deck)
	rows := (n + DV_COLS - 1) / DV_COLS
	content := f32(rows) * (DV_CH + DV_GAP) - DV_GAP
	visible := f32(rl.GetScreenHeight()) - DV_TOP - DV_BOTTOM
	return max(f32(0), content - visible)
}

update_deck_viewer :: proc(g: ^Game, dt: f32) {
	if len(g.colony.roster) == 0 {
		g.show_deck = false
		return
	}
	if g.view_index < 0 || g.view_index >= len(g.colony.roster) {
		g.view_index = 0
	}
	if rl.IsKeyPressed(.V) || rl.IsKeyPressed(.ESCAPE) {
		g.show_deck = false
		return
	}
	n := len(g.colony.roster)
	if rl.IsKeyPressed(.RIGHT) || rl.IsKeyPressed(.E) {
		g.view_index = (g.view_index + 1) % n
		g.view_scroll = 0
	}
	if rl.IsKeyPressed(.LEFT) || rl.IsKeyPressed(.Q) {
		g.view_index = (g.view_index - 1 + n) % n
		g.view_scroll = 0
	}
	g.view_scroll -= rl.GetMouseWheelMove() * 60
	if rl.IsKeyDown(.DOWN) { g.view_scroll += 600 * dt }
	if rl.IsKeyDown(.UP) { g.view_scroll -= 600 * dt }
	g.view_scroll = clamp(g.view_scroll, 0, deck_max_scroll(g))
}

draw_deck_viewer :: proc(g: ^Game) {
	sw := f32(rl.GetScreenWidth())
	sh := f32(rl.GetScreenHeight())
	rl.DrawRectangle(0, 0, i32(sw), i32(sh), rl.Color{0, 0, 0, 205})

	c := &g.colony.roster[g.view_index].creature
	element := creature_element(c)

	name := fmt.ctprintf("%s's Deck", c.name)
	rl.DrawText(name, 40, 26, 34, rl.Color{235, 235, 245, 255})
	sub := fmt.ctprintf("Lv %d   %s   HP %d/%d   PWR +%d   DEF %d   SPD %d   Energy %s max (%s regen)   %d cards",
		c.level, element_name(element), c.hp, c.max_hp, c.power, creature_defense(c), c.speed,
		fmt_num(c.energy_max), fmt_num(c.energy_regen), len(c.deck))
	rl.DrawText(sub, 40, 68, 18, element_color(element))
	pager := fmt.ctprintf("monster %d / %d   -   Left/Right or Q/E to switch", g.view_index + 1, len(g.colony.roster))
	rl.DrawText(pager, 40, 96, 16, rl.Color{150, 150, 170, 255})

	n := len(c.deck)
	total_w := f32(DV_COLS) * DV_CW + f32(DV_COLS - 1) * DV_GAP
	start_x := sw / 2 - total_w / 2
	base_y := DV_TOP - g.view_scroll
	mp := rl.GetMousePosition()

	// Leave headroom above the grid so a hovered (lifted) top-row card is not
	// clipped by the scissor region.
	clip_top := i32(DV_TOP) - 36
	clip_bottom := i32(sh - DV_BOTTOM) + 8
	rl.BeginScissorMode(0, clip_top, i32(sw), clip_bottom - clip_top)
	for i in 0..<n {
		col := i % DV_COLS
		row := i / DV_COLS
		rec := rl.Rectangle{start_x + f32(col) * (DV_CW + DV_GAP), base_y + f32(row) * (DV_CH + DV_GAP), DV_CW, DV_CH}
		if rec.y + DV_CH < f32(clip_top) - 4 || rec.y > f32(clip_bottom) + 4 {
			continue
		}
		hovered := rl.CheckCollisionPointRec(mp, rec)
		draw_card(c.deck[i], rec, true, hovered)
	}
	rl.EndScissorMode()

	hint := cstring("V / Esc close   |   wheel or Up/Down to scroll")
	hw := rl.MeasureText(hint, 16)
	rl.DrawText(hint, i32(sw) / 2 - hw / 2, i32(sh) - 32, 16, rl.Color{140, 140, 160, 255})
}
