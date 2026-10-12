package main

import rl "vendor:raylib"
import "core:time"
import "core:math"
import "core:fmt"

Game_Mode :: enum { STARTER, MAP, BATTLE, GAME_OVER }

Battle_Results :: struct {
	gold:    int,
	xp:      int,
	food:    int,
	kills:   int,
	card:    string,
	item:    Item,
	leveled: bool,
}

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
	build_preview: Improvement, // hovered build option (for radius preview)
	trade_open: bool,

	// monster encyclopedia
	show_encyclopedia:  bool,
	encyclopedia_index: int,
	encyclopedia_first: int,

	// improvements dex
	show_improvements:  bool,
	improvement_index:  int,
	improvement_first:  int,

	// item bag viewer
	show_bag:  bool,
	bag_index: int,
	bag_first: int,

	// Phase 3: wild attacks -> battles
	battle:             Battle,
	has_battle:         bool,
	battle_choice_open: bool,
	battle_hex:         Hex,
	battle_forced:      bool, // true when a wild is attacking you (can't back out)
	battle_auto:        bool,
	results_open:       bool,
	results:            Battle_Results,

	// player-initiated attack: choose which monsters join
	attack_select_open: bool,
	attack_ids:         [dynamic]int,
	attack_chosen:      [dynamic]bool,

	seed_rng: Rng,
}

main :: proc() {
	rl.SetConfigFlags({.WINDOW_RESIZABLE, .MSAA_4X_HINT})
	rl.InitWindow(1280, 720, "Monster Colony")
	defer rl.CloseWindow()
	// Escape is raylib's default exit key; we use it to close panels instead.
	rl.SetExitKey(.KEY_NULL)
	rl.SetTargetFPS(60)

	g: Game
	g.seed_rng = rng_make(u64(time.now()._nsec))
	g.selected = -1
	g.attack_ids = make([dynamic]int, 0)
	g.attack_chosen = make([dynamic]bool, 0)
	defer {
		delete(g.attack_ids)
		delete(g.attack_chosen)
	}

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
	if g.has_battle {
		battle_free(&g.battle)
		g.battle = Battle{}
		g.has_battle = false
	}
	if g.has_colony {
		colony_free(&g.colony)
		g.has_colony = false
	}
}

reset_to_starter :: proc(g: ^Game) {
	end_run(g)
	g.show_deck = false
	g.show_encyclopedia = false
	g.show_improvements = false
	g.show_bag = false
	g.battle_choice_open = false
	g.battle_forced = false
	g.attack_select_open = false
	g.build_preview = .NONE
	clear(&g.attack_ids)
	clear(&g.attack_chosen)
	g.results_open = false
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
	if g.show_encyclopedia {
		update_encyclopedia(g)
		return
	}
	if g.show_improvements {
		update_improvements(g)
		return
	}
	if g.show_bag {
		update_bag(g)
		return
	}
	if (g.mode == .MAP || g.mode == .STARTER) && rl.IsKeyPressed(.M) {
		g.show_encyclopedia = true
		g.encyclopedia_index = 0
		g.encyclopedia_first = 0
		return
	}
	if g.mode == .MAP && rl.IsKeyPressed(.I) {
		g.show_improvements = true
		g.improvement_index = 0
		g.improvement_first = 0
		return
	}
	if g.mode == .MAP && rl.IsKeyPressed(.G) {
		g.show_bag = true
		g.bag_index = 0
		g.bag_first = 0
		return
	}
	if g.attack_select_open {
		update_attack_select(g)
		return
	}
	if g.battle_choice_open {
		update_battle_choice(g)
		return
	}
	if g.results_open {
		update_results(g)
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
	case .BATTLE:
		update_battle(g, dt)
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
		g.build_preview = .NONE
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

	// Cycle selection through the monsters you own.
	if rl.IsKeyPressed(.TAB) {
		g.selected = next_player_monster(&g.colony, g.selected)
		return
	}

	mp := rl.GetMousePosition()
	if rl.IsMouseButtonPressed(.LEFT) {
		if rl.CheckCollisionPointRec(mp, colony_end_turn_rect()) {
			do_end_turn(g)
			return
		}
		slot := 0
		for i in 0..<len(g.colony.roster) {
			if g.colony.roster[i].wild {
				continue
			}
			if rl.CheckCollisionPointRec(mp, roster_entry_rect(slot)) {
				g.selected = i
				return
			}
			slot += 1
		}
	}

	hovered := hex_renderer_hovered(&g.renderer)

	if g.selected >= 0 && g.selected < len(g.colony.roster) {
		m := &g.colony.roster[g.selected]
		if rl.IsMouseButtonPressed(.LEFT) {
			if hex_equal(m.pos, hovered) {
				// Clicking your own tile: if a wild shares it, you can pick your
				// attackers and start the fight (they can also ambush you).
				if monsters_on_tile(&g.colony, hovered, true) > 0 {
					g.battle_hex = hovered
					g.battle_forced = false
					build_attack(g, hovered, 1)
					g.attack_select_open = true
				} else {
					// Otherwise, cycle through your monsters standing here.
					g.selected = cycle_player_monster_on(&g.colony, hovered, g.selected)
				}
				return
			}
			if hex_distance(m.pos, hovered) == 1 {
				res := colony_move(&g.colony, g.selected, hovered)
				switch res {
				case 0:
					set_status(g, "Moved.")
					// Moving into a tile with wilds opens the attack setup.
					if monsters_on_tile(&g.colony, hovered, true) > 0 {
						g.battle_hex = hovered
						g.battle_forced = false
						build_attack(g, hovered, 1)
						g.attack_select_open = true
					}
				case 2:
					set_status(g, move_block_reason(&g.colony, m, hovered))
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
	}

	if rl.IsMouseButtonPressed(.LEFT) {
		// Clicking a tile: if the selected monster is already here, cycle through
		// the monsters you own on this tile; otherwise select the first one here.
		after := -1
		if g.selected >= 0 && g.selected < len(g.colony.roster) && hex_equal(g.colony.roster[g.selected].pos, hovered) {
			after = g.selected
		}
		g.selected = cycle_player_monster_on(&g.colony, hovered, after)
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
			improved := t.improvement != .NONE
			// Repair an existing, damaged improvement.
			if improved && improvement_repair_cost(t.improvement, t.improvement_hp) > 0 {
				if rl.CheckCollisionPointRec(mp, build_repair_rect()) {
					res := colony_repair(&g.colony, g.build_hex)
					switch res {
					case 0: set_status(g, "Improvement repaired.")
					case 1: set_status(g, "Nothing to repair.")
					case 2: set_status(g, "Not enough gold.")
					}
					return
				}
			}
			opts: [32]Improvement
			n := buildable_improvements(&g.colony, g.build_hex, opts[:])
			start := improved ? BUILD_REPLACE_START : BUILD_OPT_START
			for i in 0..<n {
				if rl.CheckCollisionPointRec(mp, build_option_rect_at(start, i)) {
					res := colony_build(&g.colony, g.build_hex, opts[i])
					switch res {
					case 0:
						if improvement_stacks(opts[i]) {
							set_status(g, "Added on top of the building.")
						} else {
							set_status(g, improved ? "Improvement replaced." : "Improvement built.")
						}
					case 1: set_status(g, "Can't build that on this terrain.")
					case 3: set_status(g, "Not enough gold.")
					case: set_status(g, "Can't build there.")
					}
					return
				}
			}
		}
	}

	hovered := hex_renderer_hovered(&g.renderer)
	if t := tile_at(&g.colony, hovered); t != nil && t.revealed {
		// Click an already-selected Drawbridge again to raise/lower it.
		if g.has_build && hex_equal(g.build_hex, hovered) && t.improvement == .DRAWBRIDGE {
			_ = colony_toggle_drawbridge(&g.colony, hovered)
			set_status(g, t.drawbridge_down ? "Drawbridge lowered - it's a bridge." : "Drawbridge raised - wilds are blocked.")
		}
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

	// Recruit a monster from the stock.
	for i in 0..<len(g.colony.shop) {
		if rl.CheckCollisionPointRec(mp, trade_recruit_rect(i)) {
			res := colony_buy_recruit(&g.colony, i)
			set_status(g, res == 0 ? "Recruited a monster!" : res == 2 ? "Not enough gold." : res == 3 ? "No room at the entrance." : "Unavailable.")
			return
		}
	}

	if s >= 0 && s < len(g.colony.roster) && !g.colony.roster[s].wild {
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
	if rl.CheckCollisionPointRec(mp, trade_capture_rect()) {
		res := colony_buy_capture_card(&g.colony)
		set_status(g, res == 0 ? "Bought a capture card." : "Not enough gold.")
		return
	}
	for i in 0..<min(len(g.colony.graveyard), 2) {
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
		return
	}
	set_status(g, "Turn advanced.")
	start_next_attack(g)
}

// ----------------------------------------------------------------------------
// Phase 3: wild attacks -> battles
// ----------------------------------------------------------------------------

// Players you command (never wilds), used by TAB / tile-cycling.
next_player_monster :: proc(c: ^Colony, from: int) -> int {
	n := len(c.roster)
	if n == 0 {
		return -1
	}
	for k in 1..=n {
		i := (from + k) % n
		if i < 0 {
			i += n
		}
		if !c.roster[i].wild {
			return i
		}
	}
	return from
}

// Next player monster standing on `hex` after index `after` (wraps), or -1.
cycle_player_monster_on :: proc(c: ^Colony, hex: Hex, after: int) -> int {
	n := len(c.roster)
	for k in 1..=n {
		i := (after + k) % n
		if i < 0 {
			i += n
		}
		if !c.roster[i].wild && hex_equal(c.roster[i].pos, hex) {
			return i
		}
	}
	return -1
}

// Candidate attackers for a strike on `hex`: your monsters on it and (within 1)
// around it. Everyone starts selected.
build_attack :: proc(g: ^Game, hex: Hex, radius: int) {
	clear(&g.attack_ids)
	clear(&g.attack_chosen)
	for &m in g.colony.roster {
		if m.wild || m.creature.hp <= 0 {
			continue
		}
		if hex_distance(m.pos, hex) <= radius {
			append(&g.attack_ids, m.id)
			append(&g.attack_chosen, true)
		}
	}
}

attack_chosen_count :: proc(g: ^Game) -> int {
	n := 0
	for c in g.attack_chosen {
		if c {
			n += 1
		}
	}
	return n
}

attack_panel_rect :: proc() -> rl.Rectangle {
	sw := f32(rl.GetScreenWidth())
	sh := f32(rl.GetScreenHeight())
	return rl.Rectangle{sw / 2 - 390, sh / 2 - 290, 780, 580}
}

ATTACK_MAX_ROWS :: 12

attack_row_rect :: proc(i: int) -> rl.Rectangle {
	p := attack_panel_rect()
	return rl.Rectangle{p.x + 24, p.y + 100 + f32(i) * 30, 340, 26}
}

enemy_row_rect :: proc(i: int) -> rl.Rectangle {
	p := attack_panel_rect()
	return rl.Rectangle{p.x + 416, p.y + 100 + f32(i) * 46, 340, 42}
}

attack_auto_rect :: proc() -> rl.Rectangle {
	p := attack_panel_rect()
	return rl.Rectangle{p.x + 24, p.y + p.height - 74, (p.width - 72) / 2, 50}
}

attack_manual_rect :: proc() -> rl.Rectangle {
	r := attack_auto_rect()
	return rl.Rectangle{r.x + r.width + 24, r.y, r.width, 50}
}

update_attack_select :: proc(g: ^Game) {
	if rl.IsKeyPressed(.ESCAPE) {
		g.attack_select_open = false
		set_status(g, "You hold back.")
		return
	}
	if !rl.IsMouseButtonPressed(.LEFT) {
		return
	}
	mp := rl.GetMousePosition()
	for i in 0..<len(g.attack_ids) {
		if i >= ATTACK_MAX_ROWS {
			break
		}
		if rl.CheckCollisionPointRec(mp, attack_row_rect(i)) {
			g.attack_chosen[i] = !g.attack_chosen[i]
			return
		}
	}
	if attack_chosen_count(g) == 0 {
		return // need at least one attacker
	}
	if rl.CheckCollisionPointRec(mp, attack_auto_rect()) {
		begin_battle(g, true)
		return
	}
	if rl.CheckCollisionPointRec(mp, attack_manual_rect()) {
		begin_battle(g, false)
		return
	}
}

draw_attack_select :: proc(g: ^Game) {
	sw := f32(rl.GetScreenWidth())
	sh := f32(rl.GetScreenHeight())
	rl.DrawRectangle(0, 0, i32(sw), i32(sh), rl.Color{0, 0, 0, 175})

	p := attack_panel_rect()
	rl.DrawRectangleRounded(p, 0.04, 8, rl.Color{22, 20, 28, 248})
	rl.DrawRectangleRoundedLinesEx(p, 0.04, 8, 3, rl.Color{220, 90, 90, 255})

	rl.DrawText("CHOOSE ATTACKERS", i32(p.x) + 24, i32(p.y) + 16, 26, rl.Color{240, 150, 110, 255})

	// Target info.
	wilds := 0
	for m in g.colony.roster {
		if m.wild && hex_equal(m.pos, g.battle_hex) {
			wilds += 1
		}
	}
	terr := cstring("the target")
	if t := tile_at(&g.colony, g.battle_hex); t != nil {
		terr = terrain_name(t.terrain)
	}
	info := fmt.ctprintf("%d wild%s on %s  -  click your monsters to include them", wilds, wilds == 1 ? "" : "s", terr)
	rl.DrawText(info, i32(p.x) + 24, i32(p.y) + 54, 16, rl.Color{180, 180, 200, 255})

	rl.DrawText("YOUR MONSTERS", i32(p.x) + 24, i32(p.y) + 78, 15, rl.Color{150, 160, 180, 255})
	rl.DrawText("ENEMIES ON THE TILE", i32(p.x) + 416, i32(p.y) + 78, 15, rl.Color{220, 150, 130, 255})

	mp := rl.GetMousePosition()
	for id, i in g.attack_ids {
		if i >= ATTACK_MAX_ROWS {
			break
		}
		idx := monster_by_id(&g.colony, id)
		if idx < 0 {
			continue
		}
		m := &g.colony.roster[idx]
		rec := attack_row_rect(i)
		hover := rl.CheckCollisionPointRec(mp, rec)
		chosen := g.attack_chosen[i]
		bg := rl.Color{30, 30, 40, 255}
		if chosen {
			bg = rl.Color{34, 52, 42, 255}
		} else if hover {
			bg = rl.Color{40, 40, 52, 255}
		}
		rl.DrawRectangleRounded(rec, 0.2, 5, bg)
		rl.DrawRectangleRoundedLinesEx(rec, 0.2, 5, 2, chosen ? rl.Color{120, 220, 160, 255} : rl.Color{80, 80, 96, 255})

		// checkbox
		box := rl.Rectangle{rec.x + 8, rec.y + 5, 16, 16}
		rl.DrawRectangleRec(box, rl.Color{14, 14, 20, 255})
		rl.DrawRectangleLinesEx(box, 2, rl.Color{140, 140, 160, 255})
		if chosen {
			rl.DrawRectangleRec(rl.Rectangle{box.x + 4, box.y + 4, 8, 8}, rl.Color{130, 235, 170, 255})
		}

		line := fmt.ctprintf("%s  Lvl %d", m.creature.name, m.creature.level)
		rl.DrawText(line, i32(rec.x) + 34, i32(rec.y) + 4, 16, rl.Color{225, 225, 240, 255})
		hp := fmt.ctprintf("%d/%d hp", m.creature.hp, m.creature.max_hp)
		rl.DrawText(hp, i32(rec.x + rec.width) - 150, i32(rec.y) + 5, 14, rl.Color{210, 140, 140, 255})
		dist := hex_distance(m.pos, g.battle_hex)
		loc := dist == 0 ? cstring("on tile") : fmt.ctprintf("%d away", dist)
		rl.DrawText(loc, i32(rec.x + rec.width) - 74, i32(rec.y) + 5, 14, rl.Color{150, 150, 170, 255})
	}

	// The wilds you would actually be fighting.
	ei := 0
	for &m in g.colony.roster {
		if !m.wild || !hex_equal(m.pos, g.battle_hex) {
			continue
		}
		if ei >= ATTACK_MAX_ROWS {
			break
		}
		rec := enemy_row_rect(ei)
		ei += 1
		rar := species_rarity(m.creature.species)
		rl.DrawRectangleRounded(rec, 0.18, 5, rl.Color{46, 28, 28, 255})
		rl.DrawRectangleRoundedLinesEx(rec, 0.18, 5, 2, rarity_color(rar))
		rl.DrawText(fmt.ctprintf("%s  Lvl %d", m.creature.name, m.creature.level), i32(rec.x) + 12, i32(rec.y) + 5, 16, rl.Color{240, 222, 212, 255})
		el := elements_label(creature_elements(&m.creature))
		ew := rl.MeasureText(el, 14)
		rl.DrawText(el, i32(rec.x + rec.width) - 12 - ew, i32(rec.y) + 7, 14, element_color(creature_element(&m.creature)))
		rl.DrawText(fmt.ctprintf("%d/%d hp", m.creature.hp, m.creature.max_hp), i32(rec.x) + 12, i32(rec.y) + 25, 13, rl.Color{215, 150, 150, 255})
		if m.creature.ability != .NONE {
			ab := ability_name(m.creature.ability)
			aw := rl.MeasureText(ab, 13)
			rl.DrawText(ab, i32(rec.x + rec.width / 2) - aw / 2, i32(rec.y) + 25, 13, rl.Color{200, 180, 240, 255})
		}
		rs := rarity_name(rar)
		rw := rl.MeasureText(rs, 13)
		rl.DrawText(rs, i32(rec.x + rec.width) - 12 - rw, i32(rec.y) + 25, 13, rarity_color(rar))
	}
	if ei == 0 {
		rl.DrawText("(none)", i32(p.x) + 416, i32(p.y) + 104, 15, rl.Color{150, 150, 165, 255})
	}

	// Buttons.
	has_attacker := attack_chosen_count(g) > 0
	auto_rec := attack_auto_rect()
	auto_hover := rl.CheckCollisionPointRec(mp, auto_rec)
	auto_col := rl.Color{50, 80, 62, 255}
	if !has_attacker {
		auto_col = rl.Color{40, 40, 46, 255}
	} else if auto_hover {
		auto_col = rl.Color{70, 120, 90, 255}
	}
	rl.DrawRectangleRounded(auto_rec, 0.22, 8, auto_col)
	rl.DrawRectangleRoundedLinesEx(auto_rec, 0.22, 8, 2, rl.Color{180, 220, 190, 255})
	at := cstring("Auto-fight")
	aw := rl.MeasureText(at, 20)
	rl.DrawText(at, i32(auto_rec.x + auto_rec.width / 2) - aw / 2, i32(auto_rec.y + auto_rec.height / 2) - 11, 20, rl.Color{235, 245, 240, 255})

	man_rec := attack_manual_rect()
	man_hover := rl.CheckCollisionPointRec(mp, man_rec)
	man_col := rl.Color{60, 60, 86, 255}
	if !has_attacker {
		man_col = rl.Color{40, 40, 46, 255}
	} else if man_hover {
		man_col = rl.Color{90, 90, 130, 255}
	}
	rl.DrawRectangleRounded(man_rec, 0.22, 8, man_col)
	rl.DrawRectangleRoundedLinesEx(man_rec, 0.22, 8, 2, rl.Color{200, 200, 240, 255})
	mt := cstring("Fight myself")
	mw := rl.MeasureText(mt, 20)
	rl.DrawText(mt, i32(man_rec.x + man_rec.width / 2) - mw / 2, i32(man_rec.y + man_rec.height / 2) - 11, 20, rl.Color{235, 235, 250, 255})

	rl.DrawText(fmt.ctprintf("%d attacker%s selected", attack_chosen_count(g), attack_chosen_count(g) == 1 ? "" : "s"), i32(p.x) + 24, i32(auto_rec.y) - 22, 15, rl.Color{160, 170, 180, 255})
	hint := cstring("Esc to back out")
	hw := rl.MeasureText(hint, 15)
	rl.DrawText(hint, i32(p.x + p.width) - 24 - hw, i32(auto_rec.y) - 22, 15, rl.Color{150, 150, 170, 255})
}


start_next_attack :: proc(g: ^Game) {
	for len(g.colony.pending_tiles) > 0 {
		hex := pop(&g.colony.pending_tiles)
		if monsters_on_tile(&g.colony, hex, false) == 0 || monsters_on_tile(&g.colony, hex, true) == 0 {
			continue
		}
		g.battle_hex = hex
		g.battle_forced = true
		build_attack(g, hex, 0) // ambush: only monsters on the tile defend
		g.battle_choice_open = true
		return
	}
	g.battle_choice_open = false
}

choice_panel_rect :: proc() -> rl.Rectangle {
	sw := f32(rl.GetScreenWidth())
	sh := f32(rl.GetScreenHeight())
	return rl.Rectangle{sw / 2 - 250, sh / 2 - 160, 500, 320}
}

choice_auto_rect :: proc() -> rl.Rectangle {
	p := choice_panel_rect()
	return rl.Rectangle{p.x + 30, p.y + 190, 200, 58}
}

choice_manual_rect :: proc() -> rl.Rectangle {
	p := choice_panel_rect()
	return rl.Rectangle{p.x + p.width - 230, p.y + 190, 200, 58}
}

update_battle_choice :: proc(g: ^Game) {
	if rl.IsKeyPressed(.ESCAPE) && !g.battle_forced {
		g.battle_choice_open = false
		set_status(g, "You hold back.")
		return
	}
	if !rl.IsMouseButtonPressed(.LEFT) {
		return
	}
	mp := rl.GetMousePosition()
	if rl.CheckCollisionPointRec(mp, choice_auto_rect()) {
		begin_battle(g, true)
		return
	}
	if rl.CheckCollisionPointRec(mp, choice_manual_rect()) {
		begin_battle(g, false)
		return
	}
}

// Starting Block from a nearby Watchtower (the Beacon debuffs the attackers
// instead, applied separately in begin_battle).
guard_block_at :: proc(g: ^Game, pos: Hex) -> int {
	if near_improvement(&g.colony, pos, WATCHTOWER_GUARD, .WATCHTOWER) {
		return WATCHTOWER_GUARD_BLOCK
	}
	return 0
}

// Both parties come from the contested tile: your monsters vs the wilds on it.
begin_battle :: proc(g: ^Game, auto: bool) {	hex := g.battle_hex
	defs := make([dynamic]^Creature, 0)
	defer delete(defs)
	enemies := make([dynamic]^Creature, 0)
	defer delete(enemies)
	ids := make([dynamic]int, 0)
	defer delete(ids)
	// Starting Block each defender gets from a nearby Watchtower (parallel to defs).
	blocks := make([dynamic]int, 0)
	defer delete(blocks)

	// Defenders: the chosen attackers if we have a list, else everyone on the tile.
	if len(g.attack_ids) > 0 {
		for id, i in g.attack_ids {
			if !g.attack_chosen[i] {
				continue
			}
			idx := monster_by_id(&g.colony, id)
			if idx < 0 {
				continue
			}
			m := &g.colony.roster[idx]
			if m.wild || m.creature.hp <= 0 {
				continue
			}
			append(&defs, &m.creature)
			b := guard_block_at(g, m.pos)
			append(&blocks, b)
		}
	} else {
		for &m in g.colony.roster {
			if !hex_equal(m.pos, hex) || m.wild || m.creature.hp <= 0 {
				continue
			}
			append(&defs, &m.creature)
			b := guard_block_at(g, m.pos)
			append(&blocks, b)
		}
	}

	// Enemies: the wilds on the contested tile.
	for &m in g.colony.roster {
		if m.wild && hex_equal(m.pos, hex) {
			append(&enemies, &m.creature)
			append(&ids, m.id)
		}
	}
	if len(defs) == 0 || len(enemies) == 0 {
		g.battle_choice_open = false
		g.attack_select_open = false
		clear(&g.attack_ids)
		start_next_attack(g)
		return
	}

	g.battle = battle_start(defs[:], enemies[:], ids[:], &g.seed_rng)
	// Watchtower guard bonus: applied after the opening draw/reset.
	for p, i in g.battle.party {
		p.block += blocks[i]
	}
	// Beacon: wilds attacking within its guard radius start Vulnerable.
	if near_improvement(&g.colony, hex, BEACON_GUARD, .BEACON) {
		for e in g.battle.enemies {
			e.vulnerable += BEACON_VULN
		}
	}
	// Kitchen: spend rations to give the defenders +Strength for this fight.
	if ki := nearest_improvement_within(&g.colony, hex, KITCHEN_RADIUS, .KITCHEN); ki >= 0 {
		if gi := nearest_improvement_within(&g.colony, g.colony.tiles[ki].hex, DELIVER_RADIUS, .GRANARY); gi >= 0 && g.colony.tiles[gi].stored >= KITCHEN_FOOD_COST {
			g.colony.tiles[gi].stored -= KITCHEN_FOOD_COST
			for p in g.battle.party {
				p.strength += KITCHEN_STRENGTH
			}
		}
	}
	g.battle.capture_cards = g.colony.capture_cards
	g.battle.auto_play = auto
	g.has_battle = true
	g.battle_auto = auto
	g.battle_choice_open = false
	g.attack_select_open = false
	g.mode = .BATTLE
	set_status(g, auto ? "Auto-fighting..." : "Battle!")
}

update_battle :: proc(g: ^Game, dt: f32) {
	battle_update(&g.battle, dt)
	battle_input(&g.battle)

	if g.battle.timer <= 0.4 {
		return
	}
	cont := rl.IsMouseButtonPressed(.LEFT) ||
		rl.IsKeyPressed(.SPACE) || rl.IsKeyPressed(.ENTER)
	if !cont {
		return
	}
	#partial switch g.battle.phase {
	case .WON:
		resolve_won(g)
	case .LOST:
		resolve_lost(g)
	case:
	}
}

finish_battle :: proc(g: ^Game) {
	g.colony.capture_cards = g.battle.capture_cards
	battle_free(&g.battle)
	g.battle = Battle{}
	g.has_battle = false
}

grant_card_to_defender :: proc(g: ^Game, hex: Hex) -> (string, bool) {
	idx := -1
	for &m, i in g.colony.roster {
		if !m.wild && hex_equal(m.pos, hex) && m.creature.hp > 0 {
			idx = i
			break
		}
	}
	if idx < 0 {
		return "", false
	}
	c := &g.colony.roster[idx].creature
	unknown := make([dynamic]Move_Id, 0)
	defer delete(unknown)
	consider := proc(unknown: ^[dynamic]Move_Id, c: ^Creature, id: Move_Id) {
		if creature_knows(c, id) {
			return
		}
		for u in unknown {
			if u == id {
				return
			}
		}
		append(unknown, id)
	}
	for id in SPECIES[c.species].move_pool {
		consider(&unknown, c, id)
	}
	for id in COMMON_MOVES {
		consider(&unknown, c, id)
	}
	if len(unknown) > 0 {
		id := unknown[rng_below(&g.colony.rng, len(unknown))]
		append(&c.deck, id)
		return MOVE_DATA[id].name, true
	}
	return "", false
}

resolve_won :: proc(g: ^Game) {
	hex := g.battle_hex

	// Tally results from the wilds on the tile before anything is removed.
	res: Battle_Results
	food_amt := 0
	killed_levels := 0
	for m in g.colony.roster {
		if !m.wild || !hex_equal(m.pos, hex) {
			continue
		}
		// Skip ones we captured (they live).
		captured := false
		for id in g.battle.captured_ids {
			if id == m.id {
				captured = true
				break
			}
		}
		if captured {
			continue
		}
		lv := m.creature.level
		res.kills += 1
		res.gold += species_loot_gold(m.creature.species, lv) + rng_below(&g.colony.rng, lv + 1)
		killed_levels += lv
		food_amt += lv * 2
	}
	res.xp = killed_levels * 10
	res.gold = colony_deposit_gold(&g.colony, hex, res.gold)

	// Captured enemies become yours.
	for id in g.battle.captured_ids {
		colony_capture(&g.colony, id)
	}

	// Free the battle BEFORE reaping the dead so no stale enemy pointer is used.
	finish_battle(g)

	// Reap the defeated wilds.
	i := 0
	for i < len(g.colony.roster) {
		m := &g.colony.roster[i]
		if m.wild && hex_equal(m.pos, hex) {
			remove_monster_at(&g.colony, i, false)
			continue
		}
		i += 1
	}

	// Food drops go to a granary within range.
	if gi := nearest_improvement_within(&g.colony, hex, DELIVER_RADIUS, .GRANARY); gi >= 0 {
		amt := min(food_amt, STORAGE_CAP - g.colony.tiles[gi].stored)
		if amt > 0 {
			g.colony.tiles[gi].stored += amt
			res.food = amt
		}
	}

	// XP to surviving defenders on the tile.
	for &m in g.colony.roster {
		if !m.wild && hex_equal(m.pos, hex) && m.creature.hp > 0 {
			if monster_add_xp(&m, res.xp) {
				res.leveled = true
			}
		}
	}

	// Rare reward card.
	if rng_f32(&g.colony.rng) < 0.18 {
		if name, ok := grant_card_to_defender(g, hex); ok {
			res.card = name
		}
	}

	// Item drop: Boss Rooms always drop one, normal fights sometimes. Items go
	// to the shared inventory, equipped from the deck viewer.
	boss_room := false
	if t := tile_at(&g.colony, hex); t != nil && t.terrain == .BOSS_ROOM {
		boss_room = true
	}
	if boss_room || rng_f32(&g.colony.rng) < 0.22 {
		it := random_item(&g.colony.rng)
		append(&g.colony.items, it)
		res.item = it
	}

	g.results = res
	g.results_open = true
	g.mode = .MAP
}

results_continue_rect :: proc() -> rl.Rectangle {
	sw := f32(rl.GetScreenWidth())
	sh := f32(rl.GetScreenHeight())
	return rl.Rectangle{sw / 2 - 90, sh / 2 + 130, 180, 50}
}

update_results :: proc(g: ^Game) {
	if rl.IsKeyPressed(.SPACE) || rl.IsKeyPressed(.ENTER) {
		g.results_open = false
		start_next_attack(g)
		return
	}
	if rl.IsMouseButtonPressed(.LEFT) && rl.CheckCollisionPointRec(rl.GetMousePosition(), results_continue_rect()) {
		g.results_open = false
		start_next_attack(g)
	}
}

draw_results :: proc(g: ^Game) {
	sw := f32(rl.GetScreenWidth())
	sh := f32(rl.GetScreenHeight())
	rl.DrawRectangle(0, 0, i32(sw), i32(sh), rl.Color{0, 0, 0, 170})

	w := f32(420)
	h := f32(360)
	p := rl.Rectangle{sw / 2 - w / 2, sh / 2 - h / 2 - 20, w, h}
	rl.DrawRectangleRounded(p, 0.05, 8, rl.Color{20, 26, 22, 248})
	rl.DrawRectangleRoundedLinesEx(p, 0.05, 8, 3, rl.Color{120, 220, 150, 255})

	title := cstring("VICTORY")
	tw := rl.MeasureText(title, 32)
	rl.DrawText(title, i32(p.x + p.width / 2) - tw / 2, i32(p.y) + 18, 32, rl.Color{130, 235, 160, 255})

	r := g.results
	y := i32(p.y) + 74
	rl.DrawText(fmt.ctprintf("Wilds defeated: %d", r.kills), i32(p.x) + 30, y, 20, rl.Color{220, 220, 235, 255}); y += 30
	rl.DrawText(fmt.ctprintf("Gold  +%d", r.gold), i32(p.x) + 30, y, 20, rl.Color{240, 205, 90, 255}); y += 28
	rl.DrawText(fmt.ctprintf("XP    +%d", r.xp), i32(p.x) + 30, y, 20, rl.Color{150, 210, 255, 255}); y += 28
	if r.food > 0 {
		rl.DrawText(fmt.ctprintf("Food  +%d (to granary)", r.food), i32(p.x) + 30, y, 20, rl.Color{140, 220, 130, 255}); y += 28
	}
	if r.card != "" {
		rl.DrawText(fmt.ctprintf("New move: %s", r.card), i32(p.x) + 30, y, 20, rl.Color{210, 160, 255, 255}); y += 28
	}
	if r.leveled {
		rl.DrawText("A monster levelled up!", i32(p.x) + 30, y, 20, rl.Color{255, 235, 140, 255}); y += 28
	}
	if r.item != .NONE {
		rl.DrawText(fmt.ctprintf("Item found: %s", item_name(r.item)), i32(p.x) + 30, y, 20, rl.Color{180, 240, 200, 255}); y += 24
		rl.DrawText("Equip it from the deck viewer (V).", i32(p.x) + 30, y, 14, rl.Color{150, 190, 165, 255}); y += 24
	}

	btn := results_continue_rect()
	hover := rl.CheckCollisionPointRec(rl.GetMousePosition(), btn)
	rl.DrawRectangleRounded(btn, 0.25, 8, hover ? rl.Color{95, 175, 130, 255} : rl.Color{70, 130, 100, 255})
	rl.DrawRectangleRoundedLinesEx(btn, 0.25, 8, 2, rl.Color{210, 230, 220, 255})
	bt := cstring("Continue")
	bw := rl.MeasureText(bt, 20)
	rl.DrawText(bt, i32(btn.x + btn.width / 2) - bw / 2, i32(btn.y + btn.height / 2) - 10, 20, rl.Color{240, 255, 245, 255})
}

resolve_lost :: proc(g: ^Game) {
	finish_battle(g)
	i := 0
	for i < len(g.colony.roster) {
		if !g.colony.roster[i].wild && g.colony.roster[i].creature.hp <= 0 {
			remove_monster_at(&g.colony, i, true)
			continue
		}
		i += 1
	}
	g.mode = .MAP
	if player_monster_count(&g.colony) == 0 {
		g.mode = .GAME_OVER
		g.battle_choice_open = false
	} else {
		start_next_attack(g)
		set_status(g, "Your defenders fell...")
	}
}

draw_battle_choice :: proc(g: ^Game) {
	sw := f32(rl.GetScreenWidth())
	sh := f32(rl.GetScreenHeight())
	rl.DrawRectangle(0, 0, i32(sw), i32(sh), rl.Color{0, 0, 0, 175})

	p := choice_panel_rect()
	rl.DrawRectangleRounded(p, 0.04, 8, rl.Color{22, 18, 24, 248})
	rl.DrawRectangleRoundedLinesEx(p, 0.04, 8, 3, rl.Color{220, 90, 90, 255})

	title := g.battle_forced ? cstring("AMBUSH!") : cstring("ATTACK!")
	rl.DrawText(title, i32(p.x) + 24, i32(p.y) + 16, 26, rl.Color{240, 120, 110, 255})

	hex := g.battle_hex
	wilds := 0
	for m in g.colony.roster {
		if m.wild && hex_equal(m.pos, hex) {
			wilds += 1
		}
	}
	line := fmt.ctprintf("%d wild%s on this tile!", wilds, wilds == 1 ? "" : "s")
	rl.DrawText(line, i32(p.x) + 24, i32(p.y) + 60, 20, rl.Color{230, 230, 240, 255})

	rl.DrawText("Attackers:", i32(p.x) + 24, i32(p.y) + 96, 16, rl.Color{220, 150, 150, 255})
	ax := i32(p.x) + 24
	for &m in g.colony.roster {
		if m.wild && hex_equal(m.pos, hex) {
			label := fmt.ctprintf("%s Lvl %d", m.creature.name, m.creature.level)
			rl.DrawText(label, ax, i32(p.y) + 118, 15, rl.Color{235, 180, 180, 255})
			ax += rl.MeasureText("XXXXXXXXXXXXXXXXXX", 15) + 8
		}
	}

	rl.DrawText("Defenders:", i32(p.x) + 24, i32(p.y) + 142, 16, rl.Color{170, 190, 170, 255})
	dx := i32(p.x) + 24
	for &m in g.colony.roster {
		if !m.wild && hex_equal(m.pos, hex) {
			label := fmt.ctprintf("%s Lvl %d", m.creature.name, m.creature.level)
			rl.DrawText(label, dx, i32(p.y) + 164, 15, rl.Color{200, 220, 200, 255})
			dx += rl.MeasureText("XXXXXXXXXXXXXXXXXX", 15) + 8
		}
	}
	_ = sh

	mp := rl.GetMousePosition()
	auto_rec := choice_auto_rect()
	manual_rec := choice_manual_rect()
	auto_hover := rl.CheckCollisionPointRec(mp, auto_rec)
	manual_hover := rl.CheckCollisionPointRec(mp, manual_rec)

	rl.DrawRectangleRounded(auto_rec, 0.22, 8, auto_hover ? rl.Color{70, 120, 90, 255} : rl.Color{50, 80, 62, 255})
	rl.DrawRectangleRoundedLinesEx(auto_rec, 0.22, 8, 2, rl.Color{180, 220, 190, 255})
	at := cstring("Auto-fight")
	aw := rl.MeasureText(at, 20)
	rl.DrawText(at, i32(auto_rec.x + auto_rec.width / 2) - aw / 2, i32(auto_rec.y + auto_rec.height / 2) - 12, 20, rl.Color{235, 245, 240, 255})

	rl.DrawRectangleRounded(manual_rec, 0.22, 8, manual_hover ? rl.Color{90, 90, 130, 255} : rl.Color{60, 60, 86, 255})
	rl.DrawRectangleRoundedLinesEx(manual_rec, 0.22, 8, 2, rl.Color{200, 200, 240, 255})
	mt := cstring("Fight myself")
	mw := rl.MeasureText(mt, 20)
	rl.DrawText(mt, i32(manual_rec.x + manual_rec.width / 2) - mw / 2, i32(manual_rec.y + manual_rec.height / 2) - 12, 20, rl.Color{235, 235, 250, 255})

	hint := g.battle_forced ? cstring("You are under attack - choose your response") : cstring("Esc to back out")
	hw := rl.MeasureText(hint, 16)
	rl.DrawText(hint, i32(p.x + p.width / 2) - hw / 2, i32(p.y + p.height) - 30, 16, g.battle_forced ? rl.Color{230, 150, 150, 255} : rl.Color{150, 150, 170, 255})
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
	case .BATTLE:
		draw_battle(&g.battle)
	case .GAME_OVER:
		draw_colony_game_over(g.colony.turn)
	}

	if g.attack_select_open {
		draw_attack_select(g)
	}
	if g.battle_choice_open {
		draw_battle_choice(g)
	}
	if g.results_open {
		draw_results(g)
	}
	if g.show_deck {
		draw_deck_viewer(g)
	}
	if g.show_encyclopedia {
		draw_encyclopedia(g)
	}
	if g.show_improvements {
		draw_improvements(g)
	}
	if g.show_bag {
		draw_bag(g)
	}
}

draw_colony :: proc(g: ^Game) {
	rl.ClearBackground(rl.Color{10, 12, 16, 255})

	sw := f32(rl.GetScreenWidth())
	sh := f32(rl.GetScreenHeight())
	margin := f32(100) * g.renderer.zoom
	now := f32(rl.GetTime())
	z := g.renderer.zoom

	// Tiles (fog of war). Unexplored tiles get a dim "unknown" hex so the map
	// reads as fog rather than holes in the dark background. The map is infinite
	// so only on-screen materialized tiles are drawn.
	for t in g.colony.tiles {
		cx, cy := hex_to_screen(&g.renderer, t.hex)
		if cx < -margin || cx > sw + margin || cy < -margin || cy > sh + margin {
			continue
		}
		if !t.revealed {
			draw_hex(&g.renderer, t.hex, rl.Color{15, 16, 24, 255}, rl.Color{30, 32, 44, 255}, 1.5 * g.renderer.zoom)
			continue
		}
		draw_hex(&g.renderer, t.hex, terrain_color(t.terrain), HEX_BORDER, 2.0 * g.renderer.zoom)
		draw_tile_detail(t.terrain, t.hex, cx, cy, z)

		// Improvement damage: a brief shake + red flash + "-N" float.
		sx, sy := f32(0), f32(0)
		hit_age := now - t.hit_t0
		if t.hit_t0 > 0 && hit_age >= 0 && hit_age < HIT_LIFE {
			decay := 1.0 - hit_age / HIT_LIFE
			sx = math.sin(hit_age * 90.0) * 4.0 * z * decay
			sy = math.cos(hit_age * 80.0) * 3.0 * z * decay
			rl.DrawCircleV(rl.Vector2{cx, cy}, 18 * z, rl.Color{255, 70, 70, u8(125 * decay)})
			rl.DrawCircleLinesV(rl.Vector2{cx, cy}, (10.0 + (1.0 - decay) * 12.0) * z, rl.Color{255, 130, 120, u8(180 * decay)})
		}

		if t.overlay != .NONE {
			draw_improvement_icon(t.overlay, cx + sx, cy + sy, g.renderer.zoom)
		}
		if t.improvement != .NONE {
			draw_improvement_icon(t.improvement, cx + sx, cy + sy, g.renderer.zoom)
		}
	}

	draw_inspect_radii(g)
	draw_move_highlights(g)
	draw_map_monsters(g)
	draw_scuffles(g)
	draw_tile_floats(g)
	draw_hover_marker(&g.renderer, hex_renderer_hovered(&g.renderer), true)
	draw_colony_hud(g)
	draw_roster_panel(g)
	draw_end_turn_button(g)
	draw_terrain_legend()
}

draw_map_monsters :: proc(g: ^Game) {
	now := f32(rl.GetTime())
	z := g.renderer.zoom
	for i in 0..<len(g.colony.roster) {
		m := &g.colony.roster[i]
		tile := tile_at(&g.colony, m.pos)
		if tile == nil || !tile.revealed {
			continue
		}
		// Ring position among ALL monsters on the tile (yours and wilds).
		idx := 0
		for j in 0..<i {
			if hex_equal(g.colony.roster[j].pos, m.pos) {
				idx += 1
			}
		}
		n := max(monsters_on_tile(&g.colony, m.pos, false) + monsters_on_tile(&g.colony, m.pos, true), 1)
		cx, cy := hex_to_screen(&g.renderer, m.pos)
		px, py := f32(cx), f32(cy)
		if n > 1 {
			angle := f32(idx) / f32(n) * 2.0 * math.PI - math.PI / 2.0
			px += math.cos(angle) * 15.0 * z
			py += math.sin(angle) * 15.0 * z
		}
		radius := 9.0 * z
		bob := math.sin(now * 3.0 + f32(i) * 0.7) * 1.6 * z
		by := py + bob

		// Ground shadow stays put while the body bobs.
		rl.DrawEllipse(i32(px), i32(py + radius * 0.9), radius * 0.9, radius * 0.35, rl.Color{0, 0, 0, 90})
		rl.DrawCircleV(rl.Vector2{px, by}, radius, creature_color(&m.creature))
		rl.DrawCircleV(rl.Vector2{px - radius * 0.3, by - radius * 0.3}, radius * 0.32, rl.Color{255, 255, 255, 45})
		if m.wild {
			// Wilds: pulsing red ring so they read as hostile.
			pulse := 0.5 + 0.5 * math.sin(now * 4.0 + f32(i))
			rl.DrawCircleLinesV(rl.Vector2{px, by}, radius, rl.Color{240, 70, 70, 255})
			rl.DrawCircleLinesV(rl.Vector2{px, by}, radius + (2.0 + 1.5 * pulse) * z, rl.Color{120, 20, 20, 255})
		} else {
			rl.DrawCircleLinesV(rl.Vector2{px, by}, radius, element_color(creature_element(&m.creature)))
			if i == g.selected {
				ring := radius + (3.0 + 1.5 * abs(math.sin(now * 4.0))) * z
				rl.DrawCircleLinesV(rl.Vector2{px, by}, ring, rl.Color{255, 245, 140, 255})
			}
			if m.food < 40 {
				rl.DrawCircleV(rl.Vector2{px + 7 * z, by - 7 * z}, 4 * z, rl.Color{220, 70, 70, 255})
			}
		}
	}
}

// "Signs of a scuffle": a lingering marker where wilds fought each other.
draw_scuffles :: proc(g: ^Game) {
	for t in g.colony.tiles {
		if !t.revealed || t.scuffle <= 0 {
			continue
		}
		cx, cy := hex_to_screen(&g.renderer, t.hex)
		z := g.renderer.zoom
		// dim red splat + a small mark
		rl.DrawCircleV(rl.Vector2{cx - 5 * z, cy + 4 * z}, 4 * z, rl.Color{150, 40, 40, 170})
		rl.DrawCircleV(rl.Vector2{cx + 6 * z, cy + 7 * z}, 3 * z, rl.Color{150, 40, 40, 150})
		rl.DrawCircleV(rl.Vector2{cx + 2 * z, cy - 6 * z}, 3 * z, rl.Color{150, 40, 40, 150})
		lbl := cstring("x")
		lw := rl.MeasureText(lbl, 18)
		rl.DrawText(lbl, i32(cx) - lw / 2, i32(cy) - 9, 18, rl.Color{220, 100, 100, 220})
	}
}

// Transient "+N gold/food" popups spawned by production during a turn. Each
// rises and fades over FLOAT_LIFE seconds; produce gets an expanding ring burst.
draw_tile_floats :: proc(g: ^Game) {
	now := f32(rl.GetTime())
	z := g.renderer.zoom
	for f in g.colony.floats {
		age := now - f.t0
		if age < 0 || age > FLOAT_LIFE {
			continue
		}
		p := age / FLOAT_LIFE
		cx, cy := hex_to_screen(&g.renderer, f.hex)
		jitter := f32(int(hex_key(f.hex) % 9) - 4) * 1.6 * z
		x := cx + jitter
		y := cy - 12 * z - p * 32 * z
		alpha := u8(max(f32(0), 1.0 - p * p) * 255)

		text: cstring
		col: rl.Color
		switch f.kind {
		case .GOLD:
			text = fmt.ctprintf("+%dg", f.amount)
			col = rl.Color{245, 205, 90, alpha}
		case .FOOD, .FOOD_IN:
			text = fmt.ctprintf("+%df", f.amount)
			col = rl.Color{140, 225, 130, alpha}
		case .FOOD_OUT:
			text = fmt.ctprintf("-%df", f.amount)
			col = rl.Color{235, 175, 110, alpha}
		case .CRYSTAL:
			text = fmt.ctprintf("+%dc", f.amount)
			col = rl.Color{150, 225, 250, alpha}
		case .DAMAGE:
			text = fmt.ctprintf("-%d", f.amount)
			col = rl.Color{255, 110, 100, alpha}
		case .FLEE:
			text = cstring("flees!")
			col = rl.Color{200, 235, 255, alpha}
		case .ENERGY:
			text = fmt.ctprintf("+%de", f.amount)
			col = rl.Color{245, 220, 120, alpha}
		}
		w := rl.MeasureText(text, 15)
		rl.DrawText(text, i32(x) - w / 2 + 1, i32(y) + 1, 15, rl.Color{0, 0, 0, alpha})
		rl.DrawText(text, i32(x) - w / 2, i32(y), 15, col)

		// Expanding ring for things that were created (not consumed/damaged).
		if f.kind != .FOOD_OUT && f.kind != .DAMAGE {
			r := (5.0 + p * 16.0) * z
			rl.DrawCircleLinesV(rl.Vector2{cx, cy}, r, rl.Color{col[0], col[1], col[2], u8((1.0 - p) * 130)})
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
// ----------------------------------------------------------------------------
// Inspection overlays: coverage radii (build preview / hovering a built tile)
// ----------------------------------------------------------------------------

Coverage_Ring :: struct {
	radius: int,
	color:  rl.Color,
}

// Up to two coverage rings for an improvement (radius + tint).
improvement_rings :: proc(im: Improvement) -> ([2]Coverage_Ring, int) {
	#partial switch im {
	case .WATCHTOWER:
		return {Coverage_Ring{WATCHTOWER_REVEAL, rl.Color{90, 180, 255, 34}}, Coverage_Ring{WATCHTOWER_DETER, rl.Color{255, 175, 80, 42}}}, 2
	case .FARM, .GRANARY, .WELL:
		return {Coverage_Ring{FEED_RADIUS, rl.Color{110, 225, 130, 34}}, Coverage_Ring{}}, 1
	case .MINE, .TREASURY:
		return {Coverage_Ring{DELIVER_RADIUS, rl.Color{240, 205, 90, 34}}, Coverage_Ring{}}, 1
	case .SCARECROW:
		return {Coverage_Ring{SCARECROW_PANIC, rl.Color{255, 110, 110, 32}}, Coverage_Ring{SCARECROW_DETER, rl.Color{255, 175, 80, 42}}}, 2
	case .FOUNTAIN:
		return {Coverage_Ring{FOUNTAIN_RANGE, rl.Color{245, 220, 120, 34}}, Coverage_Ring{}}, 1
	case .TURRET:
		return {Coverage_Ring{TURRET_RANGE, rl.Color{255, 200, 90, 34}}, Coverage_Ring{}}, 1
	case .MARKETPLACE:
		return {Coverage_Ring{MARKET_RADIUS, rl.Color{240, 205, 90, 34}}, Coverage_Ring{}}, 1
	case .KITCHEN:
		return {Coverage_Ring{KITCHEN_RADIUS, rl.Color{255, 130, 90, 30}}, Coverage_Ring{}}, 1
	case .BARRACKS:
		return {Coverage_Ring{BARRACKS_RANGE, rl.Color{160, 220, 150, 34}}, Coverage_Ring{}}, 1
	case .BEACON:
		return {Coverage_Ring{BEACON_REVEAL, rl.Color{90, 180, 255, 34}}, Coverage_Ring{BEACON_DETER, rl.Color{255, 175, 80, 42}}}, 2
	}
	return {Coverage_Ring{}, Coverage_Ring{}}, 0
}

draw_coverage :: proc(g: ^Game, center: Hex, radius: int, color: rl.Color) {
	edge := rl.Color{color[0], color[1], color[2], 200}
	for dq in -radius..=radius {
		lo := max(-radius, -dq - radius)
		hi := min(radius, -dq + radius)
		for dr in lo..=hi {
			h := Hex{center.q + dq, center.r + dr}
			draw_hex_filled(&g.renderer, h, color)
			if hex_distance(h, center) == radius {
				draw_hex_outline(&g.renderer, h, edge, 2.0 * g.renderer.zoom)
			}
		}
	}
}

draw_improvement_rings :: proc(g: ^Game, center: Hex, im: Improvement) {
	rings, n := improvement_rings(im)
	for i in 0..<n {
		draw_coverage(g, center, rings[i].radius, rings[i].color)
	}
}

draw_inspect_radii :: proc(g: ^Game) {
	if g.build_mode {
		if !g.has_build {
			return
		}
		if g.build_preview != .NONE {
			draw_improvement_rings(g, g.build_hex, g.build_preview)
			return
		}
		if t := tile_at(&g.colony, g.build_hex); t != nil {
			if t.improvement != .NONE {
				draw_improvement_rings(g, g.build_hex, t.improvement)
			}
			if t.overlay != .NONE {
				draw_improvement_rings(g, g.build_hex, t.overlay)
			}
		}
		return
	}
	// Inspect: hovering a built tile shows its coverage.
	h := hex_renderer_hovered(&g.renderer)
	if t := tile_at(&g.colony, h); t != nil && t.revealed {
		if t.improvement != .NONE {
			draw_improvement_rings(g, h, t.improvement)
		}
		if t.overlay != .NONE {
			draw_improvement_rings(g, h, t.overlay)
		}
	}
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
		cost := monster_step_cost(&g.colony, m, n)
		affordable := m.creature.energy >= cost
		full := monsters_on_tile(&g.colony, n, false) >= MAX_MONSTERS_PER_TILE

		// Outline only, so the tile's own colour shows through (a fill just
		// turned pale terrain pink). Green = valid, red = blocked, amber = too
		// expensive.
		edge := rl.Color{120, 235, 165, 235}
		if !passable || full {
			edge = rl.Color{245, 105, 105, 235}
		} else if !affordable {
			edge = rl.Color{245, 205, 120, 235}
		}
		draw_hex_outline(&g.renderer, n, edge, 3.5 * g.renderer.zoom)

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

	if g.colony.food_cap == 0 {
		rl.DrawText("Food: no storage", x, 78, 20, rl.Color{150, 170, 150, 255})
		x += rl.MeasureText("Food: no storage", 20) + 30
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
	// Global per-turn production (gross potential) + upkeep summary.
	x = 20
	food_prod := fmt.ctprintf("Food +%d/turn", colony_food_production(&g.colony))
	rl.DrawText(food_prod, x, 106, 16, rl.Color{140, 220, 130, 255})
	x += rl.MeasureText(food_prod, 16) + 24
	gold_prod := fmt.ctprintf("Gold +%d/turn", colony_gold_production(&g.colony))
	rl.DrawText(gold_prod, x, 106, 16, rl.Color{240, 205, 90, 255})
	x += rl.MeasureText(gold_prod, 16) + 24
	up := fmt.ctprintf("Upkeep %d food/turn   Monsters %d   Capture cards %d", upkeep, player_monster_count(&g.colony), g.colony.capture_cards)
	rl.DrawText(up, x, 106, 16, rl.Color{150, 150, 175, 255})

	// Hovered tile info + occupants (inspect without attacking).
	hovered := hex_renderer_hovered(&g.renderer)
	if t := tile_at(&g.colony, hovered); t != nil && t.revealed {
		info: cstring
		if t.improvement != .NONE {
			if t.overlay != .NONE {
				info = fmt.ctprintf("Tile: %s  -  %s HP %d/%d  (+%s)", terrain_name(t.terrain), improvement_name(t.improvement), t.improvement_hp, improvement_max_hp(t.improvement), improvement_name(t.overlay))
			} else {
				info = fmt.ctprintf("Tile: %s  -  %s HP %d/%d", terrain_name(t.terrain), improvement_name(t.improvement), t.improvement_hp, improvement_max_hp(t.improvement))
			}
		} else if t.overlay != .NONE {
			info = fmt.ctprintf("Tile: %s  -  %s", terrain_name(t.terrain), improvement_name(t.overlay))
		} else {
			info = fmt.ctprintf("Tile: %s", terrain_name(t.terrain))
		}
		rl.DrawText(info, 20, 130, 16, rl.Color{180, 180, 200, 255})

		oy := i32(152)
		// Improvement production status (explains why it may be idle).
		green := rl.Color{150, 220, 150, 255}
		amber := rl.Color{235, 185, 120, 255}
		#partial switch t.improvement {
		case .MINE:
			staffed := monsters_on_tile(&g.colony, hovered, false) > 0
			near := nearest_improvement_within(&g.colony, hovered, DELIVER_RADIUS, .TREASURY) >= 0
			line: cstring
			if !staffed {
				line = "Mine: idle - put a monster here to work it"
			} else if near {
				line = "Mine: +4 gold/turn (to treasury)"
			} else {
				line = fmt.ctprintf("Mine: +4 gold/turn to stockpile (%d/%d - build a Treasury near the mine)", g.colony.gold, BASE_GOLD_CAP)
			}
			rl.DrawText(line, 20, oy, 14, staffed ? green : amber)
			oy += 18
		case .FARM:
			staffed := monsters_on_tile(&g.colony, hovered, false) > 0
			line: cstring
			if staffed {
				line = "Farm: feeding your monsters within 4 tiles"
			} else {
				line = "Farm: idle - put a monster here to work it"
			}
			rl.DrawText(line, 20, oy, 14, staffed ? green : amber)
			oy += 18
		case:
		}

		// Occupants on this tile.
		count := monsters_on_tile(&g.colony, hovered, false) + monsters_on_tile(&g.colony, hovered, true)
		if count == 0 {
			rl.DrawText("no monsters here", 20, oy, 14, rl.Color{120, 120, 140, 255})
		} else {
			for &m in g.colony.roster {
				if !hex_equal(m.pos, hovered) {
					continue
				}
				col := m.wild ? rl.Color{240, 110, 110, 255} : rl.Color{140, 230, 160, 255}
				tag := m.wild ? "wild" : "yours"
				line := fmt.ctprintf("%s Lvl %d  %d/%d  XP %d/%d  (%s)", m.creature.name, m.creature.level, m.creature.hp, m.creature.max_hp, m.creature.xp, xp_to_next(m.creature.level), tag)
				rl.DrawText(line, 20, oy, 14, col)
				oy += 18
			}
		}
	}

	rl.DrawText("Move: click adjacent tile | select: click own tile / TAB | Space end turn | B build | T trade | V deck | M dex | I improvements | G bag", 20, i32(sh) - 70, 16, rl.Color{120, 120, 145, 255})
	rl.DrawText("RMB/WASD pan  |  wheel zoom  |  R recenter  |  M monsterdex  |  N new run", 20, i32(sh) - 46, 16, rl.Color{120, 120, 145, 255})

	// World notifications (scuffles in the distance, things slipping away).
	my := i32(sh) - 130 - i32(len(g.colony.messages)) * 22
	for msg, i in g.colony.messages {
		text := fmt.ctprintf("%s", msg)
		w := rl.MeasureText(text, 18)
		rl.DrawText(text, i32(sw) / 2 - w / 2, my + i32(i) * 22, 18, rl.Color{225, 195, 150, 255})
	}

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
	return rl.Rectangle{sw - 240, 180 + f32(i) * 70, 224, 66}
}

draw_roster_panel :: proc(g: ^Game) {
	sw := f32(rl.GetScreenWidth())
	rl.DrawText("MONSTERS", i32(sw) - 236, 152, 18, rl.Color{170, 170, 190, 255})

	slot := 0
	for &m, i in g.colony.roster {
		if m.wild {
			continue
		}
		rec := roster_entry_rect(slot)
		sel := i == g.selected
		slot += 1
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

		name := fmt.ctprintf("%s  Lvl %d", m.creature.name, m.creature.level)
		rl.DrawText(name, i32(rec.x) + 48, i32(rec.y) + 4, 15, rl.Color{225, 225, 240, 255})

		hp := fmt.ctprintf("HP %d/%d", m.creature.hp, m.creature.max_hp)
		rl.DrawText(hp, i32(rec.x) + 48, i32(rec.y) + 22, 13, rl.Color{210, 130, 130, 255})

		if m.creature.ability != .NONE {
			ab := ability_name(m.creature.ability)
			aw := rl.MeasureText(ab, 12)
			rl.DrawText(ab, i32(rec.x + rec.width) - aw - 8, i32(rec.y) + 23, 12, rl.Color{200, 180, 240, 255})
		}

		pct := int(m.food / max(monster_satiety_max(&m), 1.0) * 100)
		food := fmt.ctprintf("Food %d%%   En %s/%s", pct, fmt_num(m.creature.energy), fmt_num(m.creature.energy_max))
		rl.DrawText(food, i32(rec.x) + 48, i32(rec.y) + 38, 12, rl.Color{150, 210, 150, 255})

		// XP progress: bar + "XP cur / next".
		need := xp_to_next(m.creature.level)
		frac := clamp(f32(m.creature.xp) / f32(max(need, 1)), 0, 1)
		xp_rec := rl.Rectangle{rec.x + 8, rec.y + 54, rec.width - 16 - 58, 5}
		rl.DrawRectangleRec(xp_rec, rl.Color{44, 44, 58, 255})
		if frac > 0 {
			rl.DrawRectangleRec(rl.Rectangle{xp_rec.x, xp_rec.y, xp_rec.width * frac, xp_rec.height}, rl.Color{150, 210, 255, 255})
		}
		xptxt := fmt.ctprintf("XP %d/%d", m.creature.xp, need)
		rl.DrawText(xptxt, i32(rec.x) + i32(rec.width) - 60, i32(rec.y) + 49, 12, rl.Color{150, 210, 255, 255})
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
	return rl.Rectangle{20, 150, 360, 540}
}

BUILD_OPT_START     :: f32(96)
BUILD_REPLACE_START :: f32(200)

build_option_rect_at :: proc(start_y: f32, i: int) -> rl.Rectangle {
	p := build_panel_rect()
	col := i % 2
	row := i / 2
	gap := f32(8)
	w := (p.width - 24 - gap) / 2
	return rl.Rectangle{p.x + 12 + f32(col) * (w + gap), p.y + start_y + f32(row) * 40, w, 38}
}

build_repair_rect :: proc() -> rl.Rectangle {
	p := build_panel_rect()
	return rl.Rectangle{p.x + 12, p.y + 124, p.width - 24, 46}
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
		cur := fmt.ctprintf("Built: %s (hp %d/%d)", improvement_name(t.improvement), t.improvement_hp, improvement_max_hp(t.improvement))
		rl.DrawText(cur, i32(p.x) + 16, i32(p.y) + 92, 16, rl.Color{140, 220, 150, 255})

		cost := improvement_repair_cost(t.improvement, t.improvement_hp)
		if cost > 0 {
			rec := build_repair_rect()
			afford := colony_total_gold(&g.colony) >= cost
			hover := rl.CheckCollisionPointRec(rl.GetMousePosition(), rec)
			bg := rl.Color{28, 40, 34, 255}
			if !afford {
				bg = rl.Color{30, 24, 26, 255}
			} else if hover {
				bg = rl.Color{44, 64, 50, 255}
			}
			rl.DrawRectangleRounded(rec, 0.14, 6, bg)
			rl.DrawRectangleRoundedLinesEx(rec, 0.14, 6, 2, afford ? rl.Color{120, 200, 150, 255} : rl.Color{120, 80, 80, 255})
			rl.DrawText("Repair", i32(rec.x) + 10, i32(rec.y) + 6, 16, rl.Color{225, 240, 225, 255})
			rl.DrawText(fmt.ctprintf("restores to %d hp", improvement_max_hp(t.improvement)), i32(rec.x) + 10, i32(rec.y) + 27, 12, rl.Color{160, 185, 165, 255})
			cst := fmt.ctprintf("%dg", cost)
			cw := rl.MeasureText(cst, 16)
			rl.DrawText(cst, i32(rec.x + rec.width) - 10 - cw, i32(rec.y) + 6, 16, afford ? rl.Color{240, 205, 90, 255} : rl.Color{200, 120, 120, 255})
		} else {
			rl.DrawText("Fully repaired", i32(p.x) + 16, i32(p.y) + 128, 15, rl.Color{140, 180, 150, 255})
		}

		// You can overwrite a built improvement with a different one.
		opts: [32]Improvement
		n := buildable_improvements(&g.colony, g.build_hex, opts[:])
		if n > 0 {
			rl.DrawText("Add / replace:", i32(p.x) + 16, i32(p.y) + 180, 15, rl.Color{150, 150, 170, 255})
			draw_build_options(g, opts[:], n, BUILD_REPLACE_START)
		}
		return
	}

	opts: [32]Improvement
	n := buildable_improvements(&g.colony, g.build_hex, opts[:])
	if n == 0 {
		rl.DrawText("No improvements available here", i32(p.x) + 16, i32(p.y) + 100, 15, rl.Color{200, 150, 150, 255})
		return
	}
	draw_build_options(g, opts[:], n, BUILD_OPT_START)
}

draw_build_options :: proc(g: ^Game, opts: []Improvement, n: int, start_y: f32) {
	mp := rl.GetMousePosition()
	hovered := Improvement.NONE
	for i in 0..<n {
		im := opts[i]
		rec := build_option_rect_at(start_y, i)
		cost := improvement_cost_scaled(&g.colony, im)
		afford := colony_total_gold(&g.colony) >= cost
		hover := rl.CheckCollisionPointRec(mp, rec)
		if hover {
			hovered = im
		}

		bg := rl.Color{28, 28, 40, 255}
		if !afford {
			bg = rl.Color{30, 24, 26, 255}
		} else if hover {
			bg = rl.Color{42, 44, 60, 255}
		}
		rl.DrawRectangleRounded(rec, 0.16, 6, bg)
		rl.DrawRectangleRoundedLinesEx(rec, 0.16, 6, 2, afford ? rl.Color{120, 180, 120, 255} : rl.Color{120, 80, 80, 255})

		rl.DrawText(improvement_name(im), i32(rec.x) + 8, i32(rec.y) + 4, 15, rl.Color{225, 225, 240, 255})
		cst := fmt.ctprintf("%dg", cost)
		cw := rl.MeasureText(cst, 15)
		rl.DrawText(cst, i32(rec.x + rec.width) - 8 - cw, i32(rec.y) + 4, 15, afford ? rl.Color{240, 205, 90, 255} : rl.Color{200, 120, 120, 255})
		rl.DrawText(fmt.ctprintf("%d hp", improvement_max_hp(im)), i32(rec.x) + 8, i32(rec.y) + 23, 11, rl.Color{150, 150, 170, 255})
		if improvement_stacks(im) {
			tag := cstring("+stack")
			tw := rl.MeasureText(tag, 11)
			rl.DrawText(tag, i32(rec.x + rec.width) - 8 - tw, i32(rec.y) + 23, 11, rl.Color{130, 210, 235, 255})
		}
	}
	g.build_preview = hovered

	// Hovered improvement's effect, along the bottom of the panel.
	p := build_panel_rect()
	if hovered != .NONE {
		rl.DrawText(improvement_effect(hovered), i32(p.x) + 12, i32(p.y + p.height) - 26, 12, rl.Color{175, 175, 195, 255})
	}
}

trade_panel_rect :: proc() -> rl.Rectangle {
	sw := f32(rl.GetScreenWidth())
	sh := f32(rl.GetScreenHeight())
	return rl.Rectangle{sw / 2 - 240, sh / 2 - 292, 480, 584}
}

trade_recruit_rect :: proc(i: int) -> rl.Rectangle {
	p := trade_panel_rect()
	return rl.Rectangle{p.x + 20, p.y + 96 + f32(i) * 54, p.width - 40, 50}
}

trade_heal_rect :: proc() -> rl.Rectangle {
	p := trade_panel_rect()
	return rl.Rectangle{p.x + 20, p.y + 268, p.width - 40, 46}
}

trade_energy_rect :: proc() -> rl.Rectangle {
	p := trade_panel_rect()
	return rl.Rectangle{p.x + 20, p.y + 320, p.width - 40, 46}
}

trade_capture_rect :: proc() -> rl.Rectangle {
	p := trade_panel_rect()
	return rl.Rectangle{p.x + 20, p.y + 372, p.width - 40, 46}
}

trade_revive_rect :: proc(i: int) -> rl.Rectangle {
	p := trade_panel_rect()
	return rl.Rectangle{p.x + 20, p.y + 452 + f32(i) * 50, p.width - 40, 46}
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

draw_recruit_button :: proc(rec: rl.Rectangle, offer: Shop_Offer, enabled: bool) {
	hover := rl.CheckCollisionPointRec(rl.GetMousePosition(), rec)
	bg := rl.Color{30, 30, 42, 255}
	if !enabled {
		bg = rl.Color{26, 24, 26, 255}
	} else if hover {
		bg = rl.Color{44, 44, 58, 255}
	}
	rar := rarity_color(species_rarity(offer.species))
	rl.DrawRectangleRounded(rec, 0.16, 6, bg)
	rl.DrawRectangleRoundedLinesEx(rec, 0.16, 6, 2, enabled ? rar : rl.Color{90, 80, 80, 255})
	name := fmt.ctprintf("%s   Lvl %d", SPECIES[offer.species].name, offer.level)
	rl.DrawText(name, i32(rec.x) + 12, i32(rec.y) + 8, 18, enabled ? rl.Color{235, 235, 245, 255} : rl.Color{140, 140, 150, 255})
	rl.DrawText(rarity_name(species_rarity(offer.species)), i32(rec.x) + 12, i32(rec.y) + 28, 13, enabled ? rar : rl.Color{130, 130, 140, 255})
	cost := fmt.ctprintf("%dg", offer.price)
	cw := rl.MeasureText(cost, 16)
	rl.DrawText(cost, i32(rec.x + rec.width) - 12 - cw, i32(rec.y) + 16, 16, enabled ? rl.Color{240, 205, 90, 255} : rl.Color{150, 120, 120, 255})
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

	// Monsters for sale — rerolled each turn by the Trading Post.
	rl.DrawText("MONSTERS FOR SALE   (restocks each turn)", i32(p.x) + 20, i32(p.y) + 74, 15, rl.Color{180, 150, 150, 255})
	if len(g.colony.shop) == 0 {
		rl.DrawText("Sold out - restocks next turn.", i32(p.x) + 20, i32(p.y) + 112, 16, rl.Color{130, 130, 145, 255})
	} else {
		for i in 0..<len(g.colony.shop) {
			offer := g.colony.shop[i]
			draw_recruit_button(trade_recruit_rect(i), offer, colony_total_gold(&g.colony) >= offer.price)
		}
	}

	// Services for the selected monster.
	s := g.selected
	have_sel := s >= 0 && s < len(g.colony.roster) && !g.colony.roster[s].wild
	hc := have_sel ? heal_cost(&g.colony.roster[s]) : 0
	heal_label: cstring
	switch {
	case !have_sel:   heal_label = "Heal (select a monster)"
	case hc <= 0:     heal_label = "Already at full HP"
	case:             heal_label = fmt.ctprintf("Heal %s", g.colony.roster[s].creature.name)
	}
	draw_trade_button(trade_heal_rect(), heal_label, hc > 0 && colony_total_gold(&g.colony) >= hc, hc > 0 ? fmt.ctprintf("%dg", hc) : "")

	ec := have_sel ? energy_cost(&g.colony.roster[s]) : 0
	draw_trade_button(trade_energy_rect(), cstring("Refill movement energy"), have_sel && colony_total_gold(&g.colony) >= ec, have_sel ? fmt.ctprintf("%dg", ec) : "")

	ccost := capture_card_cost()
	draw_trade_button(trade_capture_rect(), fmt.ctprintf("Buy Capture Card (have %d)", g.colony.capture_cards), colony_total_gold(&g.colony) >= ccost, fmt.ctprintf("%dg", ccost))

	rl.DrawText("FALLEN (revive)", i32(p.x) + 20, i32(p.y) + 430, 15, rl.Color{180, 150, 150, 255})
	if len(g.colony.graveyard) == 0 {
		rl.DrawText("None", i32(p.x) + 20, i32(p.y) + 456, 15, rl.Color{130, 130, 145, 255})
	} else {
		for i in 0..<min(len(g.colony.graveyard), 2) {
			m := &g.colony.graveyard[i]
			cost := revive_cost(m)
			label := fmt.ctprintf("Revive %s  Lvl %d", m.creature.name, m.creature.level)
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
		{.MUSHROOM,     "Mushroom Grove"},
		{.RUINS,        "Ruins"},
		{.TUNDRA,       "Tundra"},
		{.JUNGLE,       "Jungle (Flora)"},
		{.LAVA,         "Lava (Ember)"},
		{.DESERT,       "Desert"},
		{.QUICKSAND,    "Quicksand (Ground)"},
	}
	sh := f32(rl.GetScreenHeight())
	x := i32(20)
	y := i32(sh) - 250
	rl.DrawText("TERRAIN", x, y - 24, 16, rl.Color{150, 150, 170, 255})
	for e, i in entries {
		col := i / 7
		row := i % 7
		ex := x + i32(col) * 210
		ey := y + i32(row) * 24
		rl.DrawRectangle(ex, ey, 16, 16, terrain_color(e.terrain))
		rl.DrawRectangleLines(ex, ey, 16, 16, rl.Color{20, 20, 20, 255})
		rl.DrawText(e.label, ex + 26, ey - 1, 15, rl.Color{170, 170, 190, 255})
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
	m := &g.colony.roster[g.view_index]
	// Item slot: equip-from-bag / unequip (your monsters only).
	if !m.wild && rl.IsMouseButtonPressed(.LEFT) {
		mp := rl.GetMousePosition()
		if rl.CheckCollisionPointRec(mp, deck_equip_rect()) && len(g.colony.items) > 0 {
			old := m.creature.item
			next := g.colony.items[0]
			ordered_remove(&g.colony.items, 0)
			creature_equip_item(&m.creature, next)
			if old != .NONE {
				append(&g.colony.items, old)
			}
		}
		if rl.CheckCollisionPointRec(mp, deck_unequip_rect()) && m.creature.item != .NONE {
			append(&g.colony.items, m.creature.item)
			creature_equip_item(&m.creature, .NONE)
		}
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

deck_equip_rect :: proc() -> rl.Rectangle {
	sw := f32(rl.GetScreenWidth())
	return rl.Rectangle{sw - 330, 30, 290, 42}
}

deck_unequip_rect :: proc() -> rl.Rectangle {
	sw := f32(rl.GetScreenWidth())
	return rl.Rectangle{sw - 330, 78, 290, 42}
}

draw_deck_button :: proc(rec: rl.Rectangle, label: cstring, enabled: bool) {
	hover := enabled && rl.CheckCollisionPointRec(rl.GetMousePosition(), rec)
	bg := enabled ? (hover ? rl.Color{70, 80, 100, 255} : rl.Color{44, 48, 60, 255}) : rl.Color{30, 30, 38, 255}
	rl.DrawRectangleRounded(rec, 0.2, 6, bg)
	rl.DrawRectangleRoundedLinesEx(rec, 0.2, 6, 2, enabled ? rl.Color{150, 170, 210, 255} : rl.Color{80, 80, 92, 255})
	w := rl.MeasureText(label, 16)
	rl.DrawText(label, i32(rec.x + rec.width / 2) - w / 2, i32(rec.y + rec.height / 2) - 8, 16, enabled ? rl.Color{225, 230, 245, 255} : rl.Color{130, 130, 142, 255})
}

draw_deck_viewer :: proc(g: ^Game) {
	sw := f32(rl.GetScreenWidth())
	sh := f32(rl.GetScreenHeight())
	rl.DrawRectangle(0, 0, i32(sw), i32(sh), rl.Color{0, 0, 0, 205})

	c := &g.colony.roster[g.view_index].creature
	element := creature_element(c)

	name := fmt.ctprintf("%s's Deck", c.name)
	rl.DrawText(name, 40, 26, 34, rl.Color{235, 235, 245, 255})
	sub := fmt.ctprintf("Lvl %d   %s   HP %d/%d   XP %d/%d   PWR x%s   DEF %s   SPD %s   Energy %s max (%s regen)   %d cards",
		c.level, element_label(c), c.hp, c.max_hp, c.xp, xp_to_next(c.level),
		fmt_num(c.power), fmt_num(creature_defense(c)), fmt_num(c.speed),
		fmt_num(c.energy_max), fmt_num(c.energy_regen), len(c.deck))
	rl.DrawText(sub, 40, 68, 18, element_color(element))
	if c.ability != .NONE {
		ab_line := fmt.ctprintf("Ability: %s - %s", ability_name(c.ability), ability_desc(c.ability))
		rl.DrawText(ab_line, 40, 92, 16, rl.Color{200, 180, 240, 255})
	} else {
		rl.DrawText("Ability: none", 40, 92, 16, rl.Color{140, 140, 160, 255})
	}
	item_line := c.item != .NONE ? fmt.ctprintf("Item: %s - %s", item_name(c.item), item_desc(c.item)) : cstring("Item: none")
	rl.DrawText(item_line, 40, 112, 16, rl.Color{180, 240, 200, 255})
	pager := fmt.ctprintf("monster %d / %d   -   Left/Right or Q/E to switch", g.view_index + 1, len(g.colony.roster))
	rl.DrawText(pager, 40, 134, 16, rl.Color{150, 150, 170, 255})

	// Item slot + bag.
	m := &g.colony.roster[g.view_index]
	can_gear := !m.wild
	draw_deck_button(deck_equip_rect(), fmt.ctprintf("Equip item   (bag: %d)", len(g.colony.items)), can_gear && len(g.colony.items) > 0)
	draw_deck_button(deck_unequip_rect(), cstring("Unequip"), can_gear && c.item != .NONE)

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

// ----------------------------------------------------------------------------
// Monster encyclopedia
// ----------------------------------------------------------------------------

ENCY_ROWS :: 21

ency_row_rect :: proc(row: int) -> rl.Rectangle {
	return rl.Rectangle{40, 120 + f32(row) * 26, 300, 24}
}

update_encyclopedia :: proc(g: ^Game) {
	n := len(SPECIES)
	if rl.IsKeyPressed(.ESCAPE) || rl.IsKeyPressed(.M) {
		g.show_encyclopedia = false
		return
	}

	index_changed := false
	if rl.IsKeyPressed(.DOWN) || rl.IsKeyPressed(.S) {
		g.encyclopedia_index = min(g.encyclopedia_index + 1, n - 1)
		index_changed = true
	}
	if rl.IsKeyPressed(.UP) || rl.IsKeyPressed(.W) {
		g.encyclopedia_index = max(g.encyclopedia_index - 1, 0)
		index_changed = true
	}
	if rl.IsMouseButtonPressed(.LEFT) {
		mp := rl.GetMousePosition()
		for row in 0..<ENCY_ROWS {
			i := g.encyclopedia_first + row
			if i >= n {
				break
			}
			if rl.CheckCollisionPointRec(mp, ency_row_rect(row)) {
				g.encyclopedia_index = i
				index_changed = true
			}
		}
	}

	// Only force the selection into view when it actually changed (so the mouse
	// wheel can scroll freely).
	if index_changed {
		if g.encyclopedia_index < g.encyclopedia_first {
			g.encyclopedia_first = g.encyclopedia_index
		}
		if g.encyclopedia_index >= g.encyclopedia_first + ENCY_ROWS {
			g.encyclopedia_first = g.encyclopedia_index - ENCY_ROWS + 1
		}
	}

	// Mouse wheel scrolls the list.
	if wheel := rl.GetMouseWheelMove(); wheel != 0 {
		g.encyclopedia_first -= int(wheel)
	}
	max_first := max(0, n - ENCY_ROWS)
	g.encyclopedia_first = clamp(g.encyclopedia_first, 0, max_first)
}

draw_encyclopedia :: proc(g: ^Game) {
	sw := f32(rl.GetScreenWidth())
	sh := f32(rl.GetScreenHeight())
	rl.DrawRectangle(0, 0, i32(sw), i32(sh), rl.Color{8, 10, 16, 245})

	rl.DrawText("MONSTER ENCYCLOPEDIA", 40, 38, 32, rl.Color{225, 225, 240, 255})
	rl.DrawText("Up/Down, wheel or click to browse   |   M / Esc to close", 40, 80, 16, rl.Color{140, 140, 160, 255})

	n := len(SPECIES)

	// Left: the list.
	panel := rl.Rectangle{30, 108, 320, f32(ENCY_ROWS) * 26 + 12}
	rl.DrawRectangleRounded(panel, 0.03, 6, rl.Color{18, 20, 28, 255})
	rl.DrawRectangleRoundedLinesEx(panel, 0.03, 6, 2, rl.Color{60, 62, 80, 255})
	mp := rl.GetMousePosition()
	for row in 0..<ENCY_ROWS {
		i := g.encyclopedia_first + row
		if i >= n {
			break
		}
		rec := ency_row_rect(row)
		sel := i == g.encyclopedia_index
		hover := rl.CheckCollisionPointRec(mp, rec)
		if sel {
			rl.DrawRectangleRounded(rec, 0.3, 6, rl.Color{40, 50, 44, 255})
		} else if hover {
			rl.DrawRectangleRounded(rec, 0.3, 6, rl.Color{28, 30, 40, 255})
		}
		sp := SPECIES[i]
		rl.DrawCircleV(rl.Vector2{rec.x + 14, rec.y + 12}, 8, sp.color)
		rl.DrawText(fmt.ctprintf("%s", sp.name), i32(rec.x) + 30, i32(rec.y) + 4, 16, sel ? rl.Color{235, 245, 235, 255} : rl.Color{200, 200, 215, 255})
		label := elements_label(sp.elements)
		ew := rl.MeasureText(label, 13)
		rl.DrawText(label, i32(rec.x + rec.width) - 12 - ew, i32(rec.y) + 6, 13, element_color(sp.elements[0]))
	}

	// Scrollbar (only when the list overflows).
	if n > ENCY_ROWS {
		track := rl.Rectangle{panel.x + panel.width - 9, panel.y + 8, 5, panel.height - 16}
		rl.DrawRectangleRounded(track, 0.5, 4, rl.Color{40, 42, 54, 255})
		max_first := n - ENCY_ROWS
		frac := f32(g.encyclopedia_first) / f32(max_first)
		thumb_h := track.height * f32(ENCY_ROWS) / f32(n)
		thumb := rl.Rectangle{track.x, track.y + (track.height - thumb_h) * frac, track.width, thumb_h}
		rl.DrawRectangleRounded(thumb, 0.5, 4, rl.Color{130, 140, 170, 255})
		rl.DrawText(fmt.ctprintf("%d / %d", g.encyclopedia_index + 1, n), 40, i32(panel.y + panel.height) + 6, 15, rl.Color{150, 150, 170, 255})
	}

	if g.encyclopedia_index < 0 || g.encyclopedia_index >= n {
		return
	}
	sp := SPECIES[g.encyclopedia_index]
	dx := f32(390)
	dy := f32(120)

	rl.DrawCircleV(rl.Vector2{dx + 40, dy + 40}, 38, sp.color)
	rl.DrawCircleLinesV(rl.Vector2{dx + 40, dy + 40}, 38, rl.Color{235, 235, 245, 255})
	initial := fmt.ctprintf("%c", sp.name[0])
	iw := rl.MeasureText(initial, 36)
	rl.DrawText(initial, i32(dx + 40) - iw / 2, i32(dy + 40) - 18, 36, rl.Color{255, 255, 255, 255})

	rl.DrawText(fmt.ctprintf("%s", sp.name), i32(dx + 96), i32(dy) + 6, 30, rl.Color{235, 235, 245, 255})
	type_label := elements_label(sp.elements)
	rl.DrawText(type_label, i32(dx + 96), i32(dy) + 44, 20, element_color(sp.elements[0]))
	rl.DrawText(fmt.ctprintf("Role: %s", role_name(sp.role)), i32(dx + 96), i32(dy) + 70, 16, rl.Color{170, 170, 190, 255})
	rl.DrawText(rarity_name(sp.rarity), i32(dx + 210), i32(dy) + 70, 16, rarity_color(sp.rarity))

	// Stats (drawn one at a time; ctprintf shares one buffer).
	sx := i32(dx)
	sy := i32(dy) + 112
	step := i32(26)
	rl.DrawText(fmt.ctprintf("HP %d", sp.base_hp), sx, sy, 18, rl.Color{205, 205, 220, 255})
	rl.DrawText(fmt.ctprintf("PWR x%s", fmt_num(sp.base_power)), sx, sy + step, 18, rl.Color{205, 205, 220, 255})
	rl.DrawText(fmt.ctprintf("DEF %s", fmt_num(sp.base_defense)), sx, sy + step * 2, 18, rl.Color{205, 205, 220, 255})
	rl.DrawText(fmt.ctprintf("SPD %s", fmt_num(sp.base_speed)), sx, sy + step * 3, 18, rl.Color{205, 205, 220, 255})
	rl.DrawText(fmt.ctprintf("Energy %d regen / %d max", sp.base_energy, sp.base_energy_max), sx, sy + step * 4, 18, rl.Color{205, 205, 220, 255})
	rl.DrawText(fmt.ctprintf("Satiety %d   Upkeep %d", sp.base_satiety, sp.base_upkeep), sx, sy + step * 5, 18, rl.Color{205, 205, 220, 255})

	// Starter deck (unique moves with counts).
	cy := i32(dy) + 296
	rl.DrawText("STARTS WITH", sx, cy, 16, rl.Color{150, 150, 170, 255})
	cy += 24
	counts: [Move_Id]int
	shown: [Move_Id]bool
	for m in sp.starter {
		counts[m] += 1
	}
	for m in sp.starter {
		if shown[m] {
			continue
		}
		shown[m] = true
		rl.DrawText(fmt.ctprintf("%s x%d", MOVE_DATA[m].name, counts[m]), sx, cy, 15, element_color(MOVE_DATA[m].element))
		cy += 20
	}

	// Learnset by level.
	lx := i32(760)
	ly := i32(dy) + 112
	rl.DrawText("LEARNSET", lx, ly - 28, 16, rl.Color{150, 150, 170, 255})
	for e in sp.learnset {
		rl.DrawText(fmt.ctprintf("Lvl %d   %s", e.level, MOVE_DATA[e.move].name), lx, ly, 15, element_color(MOVE_DATA[e.move].element))
		ly += 20
	}

	// Ability pool: a creature rolls one of these at spawn.
	ly += 12
	rl.DrawText("ABILITIES  (one rolled at spawn)", lx, ly, 16, rl.Color{150, 150, 170, 255})
	ly += 24
	for a in species_abilities(g.encyclopedia_index) {
		rl.DrawText(fmt.ctprintf("%s - %s", ability_name(a), ability_desc(a)), lx, ly, 15, rl.Color{200, 180, 240, 255})
		ly += 20
	}

	rl.DrawText(fmt.ctprintf("%d species in the underground", n), 40, i32(sh) - 32, 16, rl.Color{130, 130, 150, 255})
}

// ----------------------------------------------------------------------------
// Improvements dex
// ----------------------------------------------------------------------------

// Word-wrap `text` inside `max_w`, drawing lines from (x, y). Returns the next y.
cstring_bytes :: proc(cs: cstring) -> []u8 {
	p := transmute([^]u8)cs
	n := 0
	if p != nil {
		for p[n] != 0 {
			n += 1
		}
	}
	return p[:n]
}

draw_text_wrapped :: proc(cs: cstring, x, y: i32, size: i32, max_w: i32, col: rl.Color) -> i32 {
	text := cstring_bytes(cs)
	buf: [1024]u8
	blen := 0
	cy := y
	pos := 0
	for {
		j := pos
		for j < len(text) && text[j] != 32 {
			j += 1
		}
		word := text[pos:j]
		cand: [1024]u8
		clen := 0
		for k in 0 ..< blen {
			cand[k] = buf[k]
			clen += 1
		}
		if clen > 0 {
			cand[clen] = 32
			clen += 1
		}
		for k in 0 ..< len(word) {
			cand[clen] = word[k]
			clen += 1
		}
		cand[clen] = 0
		if blen > 0 && rl.MeasureText(cstring(&cand[0]), size) > max_w {
			buf[blen] = 0
			rl.DrawText(cstring(&buf[0]), x, cy, size, col)
			cy += size + 6
			for k in 0 ..< len(word) {
				buf[k] = word[k]
			}
			blen = len(word)
		} else {
			for k in 0 ..< clen {
				buf[k] = cand[k]
			}
			blen = clen
		}
		if j >= len(text) {
			break
		}
		pos = j + 1
	}
	if blen > 0 {
		buf[blen] = 0
		rl.DrawText(cstring(&buf[0]), x, cy, size, col)
		cy += size + 6
	}
	return cy
}

IMPROV_ROWS :: 23

ALL_TERRAINS := [?]Terrain{.CAVE, .WATER, .DUNGEON, .GROVE, .MUSHROOM, .RUINS, .TUNDRA, .JUNGLE, .LAVA, .DESERT, .QUICKSAND, .TRADING_POST, .BOSS_ROOM}

improvement_row_rect :: proc(row: int) -> rl.Rectangle {
	return rl.Rectangle{40, 120 + f32(row) * 24, 300, 22}
}

update_improvements :: proc(g: ^Game) {
	n := len(ALL_IMPROVEMENTS)
	if rl.IsKeyPressed(.ESCAPE) || rl.IsKeyPressed(.I) {
		g.show_improvements = false
		return
	}
	index_changed := false
	if rl.IsKeyPressed(.DOWN) || rl.IsKeyPressed(.S) {
		g.improvement_index = min(g.improvement_index + 1, n - 1)
		index_changed = true
	}
	if rl.IsKeyPressed(.UP) || rl.IsKeyPressed(.W) {
		g.improvement_index = max(g.improvement_index - 1, 0)
		index_changed = true
	}
	if rl.IsMouseButtonPressed(.LEFT) {
		mp := rl.GetMousePosition()
		for row in 0 ..< IMPROV_ROWS {
			i := g.improvement_first + row
			if i >= n {
				break
			}
			if rl.CheckCollisionPointRec(mp, improvement_row_rect(row)) {
				g.improvement_index = i
				index_changed = true
			}
		}
	}
	if index_changed {
		if g.improvement_index < g.improvement_first {
			g.improvement_first = g.improvement_index
		}
		if g.improvement_index >= g.improvement_first + IMPROV_ROWS {
			g.improvement_first = g.improvement_index - IMPROV_ROWS + 1
		}
	}
	if wheel := rl.GetMouseWheelMove(); wheel != 0 {
		g.improvement_first -= int(wheel)
	}
	g.improvement_first = clamp(g.improvement_first, 0, max(0, n - IMPROV_ROWS))
}

draw_improvements :: proc(g: ^Game) {
	sw := f32(rl.GetScreenWidth())
	sh := f32(rl.GetScreenHeight())
	rl.DrawRectangle(0, 0, i32(sw), i32(sh), rl.Color{8, 10, 16, 245})

	rl.DrawText("IMPROVEMENTS", 40, 38, 32, rl.Color{225, 225, 240, 255})
	rl.DrawText("Up/Down, wheel or click to browse   |   I / Esc to close", 40, 80, 16, rl.Color{140, 140, 160, 255})

	n := len(ALL_IMPROVEMENTS)

	// Left: the list.
	panel := rl.Rectangle{30, 108, 320, f32(IMPROV_ROWS) * 24 + 12}
	rl.DrawRectangleRounded(panel, 0.03, 6, rl.Color{18, 20, 28, 255})
	rl.DrawRectangleRoundedLinesEx(panel, 0.03, 6, 2, rl.Color{60, 62, 80, 255})
	mp := rl.GetMousePosition()
	for row in 0 ..< IMPROV_ROWS {
		i := g.improvement_first + row
		if i >= n {
			break
		}
		im := ALL_IMPROVEMENTS[i]
		rec := improvement_row_rect(row)
		sel := i == g.improvement_index
		hover := rl.CheckCollisionPointRec(mp, rec)
		if sel {
			rl.DrawRectangleRounded(rec, 0.3, 6, rl.Color{40, 50, 44, 255})
		} else if hover {
			rl.DrawRectangleRounded(rec, 0.3, 6, rl.Color{28, 30, 40, 255})
		}
		rl.DrawText(fmt.ctprintf("%s", improvement_name(im)), i32(rec.x) + 12, i32(rec.y) + 3, 16, sel ? rl.Color{235, 245, 235, 255} : rl.Color{200, 200, 215, 255})
		cat := improvement_category(im)
		cw := rl.MeasureText(cat, 13)
		rl.DrawText(cat, i32(rec.x + rec.width) - 10 - cw, i32(rec.y) + 5, 13, rl.Color{150, 160, 180, 255})
	}

	if n > IMPROV_ROWS {
		track := rl.Rectangle{panel.x + panel.width - 9, panel.y + 8, 5, panel.height - 16}
		rl.DrawRectangleRounded(track, 0.5, 4, rl.Color{40, 42, 54, 255})
		max_first := n - IMPROV_ROWS
		frac := f32(g.improvement_first) / f32(max_first)
		thumb_h := track.height * f32(IMPROV_ROWS) / f32(n)
		thumb := rl.Rectangle{track.x, track.y + (track.height - thumb_h) * frac, track.width, thumb_h}
		rl.DrawRectangleRounded(thumb, 0.5, 4, rl.Color{130, 140, 170, 255})
	}

	if g.improvement_index < 0 || g.improvement_index >= n {
		return
	}
	im := ALL_IMPROVEMENTS[g.improvement_index]
	dx := f32(390)
	dy := f32(120)

	// Animated icon.
	draw_improvement_icon(im, dx + 64, dy + 66, 2.0)

	// Name + headline stats.
	rl.DrawText(fmt.ctprintf("%s", improvement_name(im)), i32(dx + 148), i32(dy) + 6, 30, rl.Color{235, 235, 245, 255})
	head := fmt.ctprintf("%s   |   Cost %dg   |   HP %d", improvement_category(im), improvement_cost(im), improvement_max_hp(im))
	rl.DrawText(head, i32(dx + 148), i32(dy) + 44, 18, rl.Color{210, 200, 160, 255})
	if improvement_stacks(im) {
		rl.DrawText("STACKABLE (overlay slot)", i32(dx + 148), i32(dy) + 68, 15, rl.Color{150, 220, 170, 255})
	}

	// Built-on terrain chips.
	rl.DrawText("BUILT ON", i32(dx), i32(dy) + 140, 15, rl.Color{150, 150, 170, 255})
	cx := i32(dx)
	cy := i32(dy) + 162
	right := i32(sw) - 40
	any := false
	for t in ALL_TERRAINS {
		if !improvement_valid_on(im, t) {
			continue
		}
		any = true
		label := terrain_name(t)
		w := rl.MeasureText(label, 14) + 18
		if cx + w > right {
			cx = i32(dx)
			cy += 28
		}
		rec := rl.Rectangle{f32(cx), f32(cy), f32(w), 23}
		rl.DrawRectangleRounded(rec, 0.4, 4, rl.Color{26, 28, 36, 255})
		rl.DrawRectangleRoundedLinesEx(rec, 0.4, 4, 1, terrain_color(t))
		rl.DrawText(label, cx + 9, cy + 3, 14, terrain_color(t))
		cx += w + 6
	}
	if !any {
		rl.DrawText("any land tile", i32(dx), cy + 3, 15, rl.Color{140, 140, 155, 255})
	}
	cy += 28

	// Effect (short) + detail (long, wrapped).
	ey := cy + 20
	rl.DrawText("EFFECT", i32(dx), ey, 15, rl.Color{150, 150, 170, 255})
	ey = draw_text_wrapped(improvement_effect(im), i32(dx), ey + 24, 17, right - i32(dx), rl.Color{210, 210, 225, 255})
	ey += 14
	rl.DrawText("DETAIL", i32(dx), ey, 15, rl.Color{150, 150, 170, 255})
	draw_text_wrapped(improvement_detail(im), i32(dx), ey + 24, 16, right - i32(dx), rl.Color{180, 180, 198, 255})

	rl.DrawText(fmt.ctprintf("%d improvements", n), 40, i32(sh) - 32, 16, rl.Color{130, 130, 150, 255})
}

// ----------------------------------------------------------------------------
// Item bag viewer
// ----------------------------------------------------------------------------

BAG_ROWS :: 20

bag_row_rect :: proc(row: int) -> rl.Rectangle {
	return rl.Rectangle{40, 120 + f32(row) * 24, 320, 22}
}

bag_equip_rect :: proc() -> rl.Rectangle {
	sh := f32(rl.GetScreenHeight())
	return rl.Rectangle{390, sh - 96, 320, 46}
}

// Draw one line per active effect field. Returns the next y.
draw_item_effects :: proc(it: Item, x, y: i32, size: i32) -> i32 {
	info := ITEM_DATA[it]
	yy := y
	step := size + 6
	if info.strength != 0 { rl.DrawText(fmt.ctprintf("Battle start:   +%d Strength", info.strength), x, yy, size, rl.Color{240, 170, 120, 255}); yy += step }
	if info.defense != 0 { rl.DrawText(fmt.ctprintf("Battle start:   +%s Defense", fmt_num(info.defense)), x, yy, size, rl.Color{120, 220, 190, 255}); yy += step }
	if info.speed != 0 { rl.DrawText(fmt.ctprintf("Battle start:   +%s Speed", fmt_num(info.speed)), x, yy, size, rl.Color{140, 190, 250, 255}); yy += step }
	if info.block != 0 { rl.DrawText(fmt.ctprintf("Battle start:   +%d Block", info.block), x, yy, size, rl.Color{130, 180, 245, 255}); yy += step }
	if info.draw != 0 { rl.DrawText(fmt.ctprintf("Each turn:   draw +%d card", info.draw), x, yy, size, rl.Color{140, 190, 250, 255}); yy += step }
	if info.on_hit_heal != 0 { rl.DrawText(fmt.ctprintf("On dealing damage:   heal %d", info.on_hit_heal), x, yy, size, rl.Color{140, 230, 150, 255}); yy += step }
	if info.energy_regen != 0 { rl.DrawText(fmt.ctprintf("Each turn:   +%s energy regen", fmt_num(info.energy_regen)), x, yy, size, rl.Color{240, 210, 110, 255}); yy += step }
	if info.energy_max != 0 { rl.DrawText(fmt.ctprintf("Energy bank:   +%s", fmt_num(info.energy_max)), x, yy, size, rl.Color{240, 210, 110, 255}); yy += step }
	if info.hp_pct != 0 { rl.DrawText(fmt.ctprintf("Max HP:   +%d%%", int(info.hp_pct * 100)), x, yy, size, rl.Color{140, 230, 150, 255}); yy += step }
	if info.power != 0 { rl.DrawText(fmt.ctprintf("Power:   +%s", fmt_num(info.power)), x, yy, size, rl.Color{240, 170, 120, 255}); yy += step }
	if info.gold_per_turn != 0 { rl.DrawText(fmt.ctprintf("Each turn:   +%d gold", info.gold_per_turn), x, yy, size, rl.Color{240, 205, 90, 255}); yy += step }
	if info.capture_pct != 0 { rl.DrawText(fmt.ctprintf("Capture chance:   +%d%%", int(info.capture_pct * 100)), x, yy, size, rl.Color{180, 220, 255, 255}); yy += step }
	return yy
}

// Move a bagged item onto the currently selected monster (old item returns to
// the bag). Returns true on success.
equip_bag_item :: proc(g: ^Game, bag_index: int) -> bool {
	s := g.selected
	if s < 0 || s >= len(g.colony.roster) || g.colony.roster[s].wild {
		return false
	}
	if bag_index < 0 || bag_index >= len(g.colony.items) {
		return false
	}
	item := g.colony.items[bag_index]
	ordered_remove(&g.colony.items, bag_index)
	old := g.colony.roster[s].creature.item
	creature_equip_item(&g.colony.roster[s].creature, item)
	if old != .NONE {
		append(&g.colony.items, old)
	}
	return true
}

update_bag :: proc(g: ^Game) {
	n := len(g.colony.items)
	if rl.IsKeyPressed(.ESCAPE) || rl.IsKeyPressed(.G) {
		g.show_bag = false
		return
	}
	index_changed := false
	if rl.IsKeyPressed(.DOWN) || rl.IsKeyPressed(.S) {
		g.bag_index = min(g.bag_index + 1, max(n - 1, 0))
		index_changed = true
	}
	if rl.IsKeyPressed(.UP) || rl.IsKeyPressed(.W) {
		g.bag_index = max(g.bag_index - 1, 0)
		index_changed = true
	}
	if rl.IsMouseButtonPressed(.LEFT) {
		mp := rl.GetMousePosition()
		for row in 0 ..< BAG_ROWS {
			i := g.bag_first + row
			if i >= n {
				break
			}
			if rl.CheckCollisionPointRec(mp, bag_row_rect(row)) {
				g.bag_index = i
				index_changed = true
			}
		}
		if rl.CheckCollisionPointRec(mp, bag_equip_rect()) && n > 0 {
			if equip_bag_item(g, g.bag_index) {
				set_status(g, "Item equipped.")
				g.bag_index = clamp(g.bag_index, 0, max(len(g.colony.items) - 1, 0))
			} else {
				set_status(g, "Select one of your monsters on the map first.")
			}
		}
	}
	if index_changed {
		if g.bag_index < g.bag_first {
			g.bag_first = g.bag_index
		}
		if g.bag_index >= g.bag_first + BAG_ROWS {
			g.bag_first = g.bag_index - BAG_ROWS + 1
		}
	}
	if wheel := rl.GetMouseWheelMove(); wheel != 0 {
		g.bag_first -= int(wheel)
	}
	g.bag_first = clamp(g.bag_first, 0, max(0, n - BAG_ROWS))
}

draw_bag :: proc(g: ^Game) {
	sw := f32(rl.GetScreenWidth())
	sh := f32(rl.GetScreenHeight())
	rl.DrawRectangle(0, 0, i32(sw), i32(sh), rl.Color{8, 10, 16, 245})

	rl.DrawText("ITEM BAG", 40, 38, 32, rl.Color{225, 225, 240, 255})
	rl.DrawText("Up/Down, wheel or click to browse   |   G / Esc to close", 40, 80, 16, rl.Color{140, 140, 160, 255})

	n := len(g.colony.items)

	// Left: the list.
	panel := rl.Rectangle{30, 108, 320, f32(BAG_ROWS) * 24 + 12}
	rl.DrawRectangleRounded(panel, 0.03, 6, rl.Color{18, 20, 28, 255})
	rl.DrawRectangleRoundedLinesEx(panel, 0.03, 6, 2, rl.Color{60, 62, 80, 255})
	mp := rl.GetMousePosition()
	for row in 0 ..< BAG_ROWS {
		i := g.bag_first + row
		if i >= n {
			break
		}
		it := g.colony.items[i]
		rec := bag_row_rect(row)
		sel := i == g.bag_index
		hover := rl.CheckCollisionPointRec(mp, rec)
		if sel {
			rl.DrawRectangleRounded(rec, 0.3, 6, rl.Color{44, 44, 58, 255})
		} else if hover {
			rl.DrawRectangleRounded(rec, 0.3, 6, rl.Color{28, 30, 40, 255})
		}
		rl.DrawCircleV(rl.Vector2{rec.x + 11, rec.y + 11}, 6, item_color(it))
		rl.DrawText(item_name(it), i32(rec.x) + 26, i32(rec.y) + 3, 16, sel ? rl.Color{240, 240, 250, 255} : rl.Color{200, 200, 215, 255})
	}
	if n > BAG_ROWS {
		track := rl.Rectangle{panel.x + panel.width - 9, panel.y + 8, 5, panel.height - 16}
		rl.DrawRectangleRounded(track, 0.5, 4, rl.Color{40, 42, 54, 255})
		max_first := n - BAG_ROWS
		frac := f32(g.bag_first) / f32(max_first)
		thumb_h := track.height * f32(BAG_ROWS) / f32(n)
		thumb := rl.Rectangle{track.x, track.y + (track.height - thumb_h) * frac, track.width, thumb_h}
		rl.DrawRectangleRounded(thumb, 0.5, 4, rl.Color{130, 140, 170, 255})
	}

	rl.DrawText(fmt.ctprintf("%d item%s in the bag", n, n == 1 ? "" : "s"), 40, i32(sh) - 32, 16, rl.Color{130, 130, 150, 255})

	dx := f32(390)
	dy := f32(120)
	if n == 0 {
		rl.DrawText("Your bag is empty.", i32(dx), i32(dy), 22, rl.Color{170, 170, 190, 255})
		rl.DrawText("Items drop from winning battles - equip them in the deck viewer (V).", i32(dx), i32(dy) + 34, 16, rl.Color{140, 140, 160, 255})
		return
	}

	idx := clamp(g.bag_index, 0, n - 1)
	it := g.colony.items[idx]

	// Icon (coloured disc with the initial).
	col := item_color(it)
	rl.DrawCircleV(rl.Vector2{dx + 44, dy + 40}, 36, rl.Color{col[0] / 3, col[1] / 3, col[2] / 3, 255})
	rl.DrawCircleLinesV(rl.Vector2{dx + 44, dy + 40}, 36, rl.Color{235, 235, 245, 255})
	initial := fmt.ctprintf("%c", item_info(it).name[0])
	iw := rl.MeasureText(initial, 34)
	rl.DrawText(initial, i32(dx + 44) - iw / 2, i32(dy + 40) - 17, 34, rl.Color{255, 255, 255, 255})

	rl.DrawText(item_name(it), i32(dx + 100), i32(dy) + 4, 30, rl.Color{235, 235, 245, 255})
	rl.DrawText(item_desc(it), i32(dx + 100), i32(dy) + 42, 17, col)

	// Effect breakdown.
	ey := i32(dy) + 96
	rl.DrawText("EFFECTS", i32(dx), ey, 15, rl.Color{150, 150, 170, 255})
	draw_item_effects(it, i32(dx), ey + 24, 17)

	// Equip target.
	target_name: cstring = "select a monster on the map"
	can_equip := false
	s := g.selected
	if s >= 0 && s < len(g.colony.roster) && !g.colony.roster[s].wild {
		m := &g.colony.roster[s]
		can_equip = m.creature.hp > 0
		cur := m.creature.item != .NONE ? item_name(m.creature.item) : cstring("nothing")
		target_name = fmt.ctprintf("%s  (wearing: %s)", m.creature.name, cur)
	}
	rl.DrawText(fmt.ctprintf("Equip to: %s", target_name), i32(dx), i32(sh) - 138, 16, rl.Color{180, 180, 200, 255})

	btn := bag_equip_rect()
	hover := can_equip && rl.CheckCollisionPointRec(mp, btn)
	bg := can_equip ? (hover ? rl.Color{60, 100, 78, 255} : rl.Color{44, 74, 58, 255}) : rl.Color{34, 34, 42, 255}
	rl.DrawRectangleRounded(btn, 0.24, 8, bg)
	rl.DrawRectangleRoundedLinesEx(btn, 0.24, 8, 2, can_equip ? rl.Color{150, 220, 180, 255} : rl.Color{80, 80, 92, 255})
	lab := cstring("Equip to selected monster")
	lw := rl.MeasureText(lab, 18)
	rl.DrawText(lab, i32(btn.x + btn.width / 2) - lw / 2, i32(btn.y + btn.height / 2) - 9, 18, can_equip ? rl.Color{235, 250, 240, 255} : rl.Color{130, 130, 142, 255})
}
