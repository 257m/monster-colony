package main

import rl "vendor:raylib"
import "core:time"
import "core:math"
import "core:fmt"

Game_Mode :: enum { TITLE, STARTER, MAP, BATTLE, GAME_OVER }

Battle_Results :: struct {
	gold:    int,
	xp:      int,
	food:    int,
	kills:   int,
	reward:  bool, // a reward card choice is pending
	item:    Item,
	crystals: int,
	leveled: bool,
	has_relic: bool, // a boss dropped a relic
	relic:     Relic,
}

Game :: struct {
	mode:     Game_Mode,
	renderer: Hex_Renderer,
	colony:   Colony,
	has_colony: bool,
	selected: int, // roster index of the selected monster, or -1
	quit:     bool, // set by the title screen's Quit button

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
	arena_open: bool,

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

	// crystal progression panel
	show_upgrades: bool,
	upgrade_scroll: f32,

	// quest board (milestones) — Phase 22
	show_quests: bool,

	// relics panel (Phase 25)
	show_relics: bool,

	// hall of the fallen (graveyard) — Phase 22
	show_graveyard: bool,
	grave_first:    int,

	// nursery (breeding) panel — Phase 8/10
	show_nursery:  bool,
	nursery_sel:   int, // selected Nursery index
	nursery_first: int, // scroll for the candidate list

	// monster storage panel (Dens) — Phase 10
	show_storage:  bool,
	storage_sel:   int,
	storage_first: int,

	// save / load panel
	show_save:     bool,
	new_run_armed: f32, // >0 = "New Run" is waiting for a confirm click

	// help overlay + minimap toggle (Phase 24)
	show_help:    bool,
	show_minimap: bool,

	// settings panel (Phase 24)
	show_settings: bool,
	tooltips_on:   bool,
	autosave_on:   bool,
	show_fps:      bool,

	// modal yes/no confirmation for destructive actions
	confirm_kind: Confirm_Kind,
	confirm_int:  int,
	confirm_aux:  int,
	confirm_hex:  Hex,

	// unit picker: choose which of your monsters to control on a shared tile
	unit_picker_open: bool,
	unit_picker_hex:  Hex,
	unit_picker_ids:  [dynamic]int,

	// smooth camera tween (world coords); when tween > 0 the camera eases there
	cam_tween:  f32,
	cam_from_x: f32,
	cam_from_y: f32,
	cam_to_x:   f32,
	cam_to_y:   f32,

	// short "last turn" digest, shown in the settings panel
	summary: [dynamic]string,

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

	// Scratch maps reused by draw_map_monsters so it stays O(roster) per frame
	// instead of rescanning the roster for every monster. Cleared each call.
	ring_total: map[u64]int,
	ring_seen:  map[u64]int,
}

// Desktop entry point. Web uses the exported hooks in web.odin instead.
when ODIN_ARCH != .wasm32 && ODIN_ARCH != .wasm64p32 {

main :: proc() {
	rl.SetConfigFlags({.WINDOW_RESIZABLE, .MSAA_4X_HINT})
	rl.InitWindow(1280, 720, "Monster Colony")
	defer rl.CloseWindow()
	// Escape is raylib's default exit key; we use it to close panels instead.
	rl.SetExitKey(.KEY_NULL)
	rl.SetTargetFPS(60)

	audio_init()
	defer audio_shutdown()

	g: Game
	g.seed_rng = rng_make(u64(time.now()._nsec))
	g.selected = -1
	g.attack_ids = make([dynamic]int, 0)
	g.attack_chosen = make([dynamic]bool, 0)
	g.unit_picker_ids = make([dynamic]int, 0)
	g.summary = make([dynamic]string, 0)
	g.show_minimap = true
	g.tooltips_on = true
	g.autosave_on = true
	g.ring_total = make(map[u64]int)
	g.ring_seen = make(map[u64]int)
	defer {
		delete(g.attack_ids)
		delete(g.attack_chosen)
		delete(g.unit_picker_ids)
		for s in g.summary { delete(s) }
		delete(g.summary)
		delete(g.ring_total)
		delete(g.ring_seen)
	}

	hex_renderer_init(&g.renderer, 46.0, int(rl.GetScreenWidth()), int(rl.GetScreenHeight()))

	goto_title(&g)
	defer end_run(&g)

	for !rl.WindowShouldClose() && !g.quit {
		dt := rl.GetFrameTime()

		g.renderer.origin_x = f32(rl.GetScreenWidth()) / 2
		g.renderer.origin_y = f32(rl.GetScreenHeight()) / 2

		audio_update()
		game_update(&g, dt)

		rl.BeginDrawing()
		game_draw(&g)
		rl.EndDrawing()
	}
}

} // when ODIN_ARCH != wasm

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

close_all_panels :: proc(g: ^Game) {
	g.show_deck = false
	g.show_encyclopedia = false
	g.show_improvements = false
	g.show_bag = false
	g.show_upgrades = false
	g.show_quests = false
	g.show_graveyard = false
	g.show_nursery = false
	g.nursery_sel = 0
	g.nursery_first = 0
	g.show_storage = false
	g.storage_sel = 0
	g.storage_first = 0
	g.show_save = false
	g.new_run_armed = 0
	g.battle_choice_open = false
	g.battle_forced = false
	g.attack_select_open = false
	g.build_preview = .NONE
	clear(&g.attack_ids)
	clear(&g.attack_chosen)
	g.results_open = false
}

// Back to the main menu (drops any run in progress).
goto_title :: proc(g: ^Game) {
	end_run(g)
	close_all_panels(g)
	g.mode = .TITLE
}

// Start a fresh run: to the starter picker with a clean slate.
reset_to_starter :: proc(g: ^Game) {
	end_run(g)
	close_all_panels(g)
	g.mode = .STARTER
}

// Generate a fresh colony for `species_idx` with a new seed and drop onto the map.
start_run :: proc(g: ^Game, species_idx: Species_Id) {
	end_run(g)
	g.colony = colony_generate(rng_next_u64(&g.seed_rng), 11, 8)
	g.has_colony = true
	g.selected = colony_add_starter(&g.colony, species_idx)
	g.mode = .MAP
	g.status = "Click an adjacent tile to move your monster. Space ends the turn."
	g.status_timer = 6
	center_camera_on(&g.renderer, g.colony.start_hex)
}

choose_starter :: proc(g: ^Game, species_idx: Species_Id) {
	audio_play(.CONFIRM)
	start_run(g, species_idx)
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
	if g.new_run_armed > 0 {
		g.new_run_armed -= dt
	}

	// Sound toggle (any mode).
	if rl.IsKeyPressed(.X) {
		set_status(g, audio_toggle_mute() ? "Sound muted." : "Sound on.")
	}

	// A pending move choice (level-up / battle reward) blocks everything else.
	if len(g.colony.choices) > 0 {
		update_move_choice(g)
		return
	}

	if g.confirm_kind != .NONE {
		update_confirm(g)
		return
	}
	if g.show_help {
		update_help(g)
		return
	}
	if g.show_settings {
		update_settings(g)
		return
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
	if g.show_upgrades {
		update_upgrades(g)
		return
	}
	if g.show_quests {
		update_quests(g)
		return
	}
	if g.show_relics {
		update_relics(g)
		return
	}
	if g.show_graveyard {
		update_graveyard(g)
		return
	}
	if g.show_nursery {
		update_nursery(g)
		return
	}
	if g.show_storage {
		update_storage(g)
		return
	}
	if g.show_save {
		update_save_panel(g)
		return
	}
	if g.unit_picker_open {
		update_unit_picker(g)
		return
	}
	if (g.mode == .MAP || g.mode == .STARTER) && rl.IsKeyPressed(.K) {
		g.show_help = true
		return
	}
	if (g.mode == .MAP || g.mode == .STARTER) && rl.IsKeyPressed(.P) {
		g.show_settings = true
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
	if g.mode == .MAP && rl.IsKeyPressed(.U) {
		g.show_upgrades = true
		return
	}
	if g.mode == .MAP && rl.IsKeyPressed(.Q) {
		g.show_quests = true
		return
	}
	if g.mode == .MAP && rl.IsKeyPressed(.J) {
		g.show_relics = true
		return
	}
	if g.mode == .MAP && rl.IsKeyPressed(.Z) {
		g.show_minimap = !g.show_minimap
		return
	}
	if g.mode == .MAP && rl.IsKeyPressed(.Y) {
		g.show_graveyard = true
		g.grave_first = 0
		return
	}
	if g.mode == .MAP && rl.IsKeyPressed(.C) {
		g.show_nursery = true
		g.nursery_sel = 0
		g.nursery_first = 0
		return
	}
	if g.mode == .MAP && rl.IsKeyPressed(.H) {
		g.show_storage = true
		g.storage_sel = 0
		g.storage_first = 0
		return
	}
	if g.mode == .MAP && rl.IsKeyPressed(.O) {
		g.show_save = true
		return
	}
	if g.mode == .MAP && g.has_colony && rl.IsKeyPressed(.F) {
		set_status(g, save_game(g, 0) ? "Quick-saved to slot 1." : "Could not save.")
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
	case .TITLE:
		update_title(g)
	case .STARTER:
		update_starter(g)
	case .MAP:
		update_colony(g, dt)
	case .BATTLE:
		update_battle(g, dt)
	case .GAME_OVER:
		if rl.IsKeyPressed(.N) {
			reset_to_starter(g)
		} else if rl.IsKeyPressed(.ESCAPE) {
			goto_title(g)
		}
	}
}

update_starter :: proc(g: ^Game) {
	// Number keys pick a starter directly (1 = the first card, and so on).
	for i in 0 ..< min(len(STARTER_SPECIES), len(DIGIT_KEYS)) {
		if rl.IsKeyPressed(DIGIT_KEYS[i]) {
			choose_starter(g, STARTER_SPECIES[i])
			return
		}
	}

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
	// Manual pan/zoom cancels any in-flight camera tween.
	if rl.IsKeyDown(.RIGHT) || rl.IsKeyDown(.LEFT) || rl.IsKeyDown(.UP) || rl.IsKeyDown(.DOWN) ||
	   rl.IsKeyDown(.W) || rl.IsKeyDown(.A) || rl.IsKeyDown(.S) || rl.IsKeyDown(.D) ||
	   rl.GetMouseWheelMove() != 0 || rl.IsMouseButtonDown(.RIGHT) {
		g.cam_tween = 0
	}
	hex_renderer_update_camera(&g.renderer, dt)
	update_camera_tween(g, dt)

	if rl.IsMouseButtonDown(.RIGHT) {
		d := rl.GetMouseDelta()
		g.renderer.camera_x -= d.x / g.renderer.zoom
		g.renderer.camera_y -= d.y / g.renderer.zoom
	}
	if rl.IsKeyPressed(.R) {
		tween_camera(g, g.colony.start_hex)
	}

	// Build mode toggles.
	if rl.IsKeyPressed(.B) {
		g.build_mode = !g.build_mode
		g.trade_open = false
		g.arena_open = false
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
	if g.arena_open {
		update_arena(g)
		return
	}
	if rl.IsKeyPressed(.T) && selected_on_trading_post(g) {
		g.trade_open = true
		return
	}
	if rl.IsKeyPressed(.T) && selected_on_arena(g) {
		g.arena_open = true
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
		if h, ok := minimap_hex_at(g, mp); ok {
			tween_camera(g, h)
			return
		}
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
				if g.selected == i {
					tween_camera(g, g.colony.roster[i].pos) // click the selected one to focus
				} else {
					g.selected = i
				}
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
					build_attack(g, hovered, 1)
					if len(g.attack_ids) == 0 {
						set_status(g, "No monsters here are ready to attack.")
						return
					}
					g.battle_hex = hovered
					g.battle_forced = false
					g.attack_select_open = true
				} else {
					// Otherwise, choose which of your monsters here to control.
					select_or_pick_on_tile(g, hovered)
				}
				return
			}
			if hex_distance(m.pos, hovered) == 1 {
				// Attacking an adjacent tile opens the attacker picker first.
				// The move only happens if you go through with the attack, so
				// backing out leaves your monster where it was.
				if monsters_on_tile(&g.colony, hovered, true) > 0 {
					if m.acted {
						set_status(g, "That monster has already acted this turn.")
						return
					}
					build_attack(g, hovered, 1)
					if len(g.attack_ids) == 0 {
						set_status(g, "No monsters are ready to attack.")
						return
					}
					g.battle_hex = hovered
					g.battle_forced = false
					g.attack_select_open = true
					return
				}
				res := colony_move(&g.colony, g.selected, hovered)
				switch res {
				case 0:
					set_status(g, "Moved.")
				case 2:
					set_status(g, move_block_reason(&g.colony, m, hovered))
				case 3:
					set_status(g, "That tile is full (max 6).")
				case 4:
					set_status(g, "Not enough movement energy.")
				case 5:
					set_status(g, "That monster has already acted this turn.")
				case:
					set_status(g, "Can't move there.")
				}
				return
			}
		}
	}

	if rl.IsMouseButtonPressed(.LEFT) {
		// Clicking a tile: pick (or select) one of your monsters standing there.
		select_or_pick_on_tile(g, hovered)
	}
}

selected_on_trading_post :: proc(g: ^Game) -> bool {
	if g.selected < 0 || g.selected >= len(g.colony.roster) {
		return false
	}
	t := tile_at(&g.colony, g.colony.roster[g.selected].pos)
	return t != nil && t.terrain == .TRADING_POST
}

selected_on_arena :: proc(g: ^Game) -> bool {
	if g.selected < 0 || g.selected >= len(g.colony.roster) {
		return false
	}
	t := tile_at(&g.colony, g.colony.roster[g.selected].pos)
	return t != nil && t.terrain == .ARENA
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
			improved := t.improvement != .NONE || t.overlay != .NONE
			// Repair a damaged building or overlay.
			rim, rhp, _ := tile_repair_target(&g.colony, t)
			if rim != .NONE && improvement_repair_cost(&g.colony, rim, rhp) > 0 {
				if rl.CheckCollisionPointRec(mp, build_repair_rect()) {
					res := colony_repair(&g.colony, g.build_hex)
					switch res {
					case 0:
						audio_play(.BUILD)
						set_status(g, "Improvement repaired.")
					case 1:
						set_status(g, "Nothing to repair.")
					case 2:
						audio_play(.ERROR)
						set_status(g, "Not enough gold.")
					}
					return
				}
			}
			// Demolish (with a confirm), refunding part of the cost. Only when
			// there is actually something here (the button only shows then).
			if improved && rl.CheckCollisionPointRec(mp, build_demolish_rect()) {
				ask_confirm(g, .DEMOLISH, 0, 0, g.build_hex)
				return
			}
			opts: [32]Improvement
			n := buildable_improvements(&g.colony, g.build_hex, opts[:])
			start := improved ? BUILD_REPLACE_START : BUILD_OPT_START
			for i in 0..<n {
				if rl.CheckCollisionPointRec(mp, build_option_rect_at(start, i)) {
					// Replacing a non-stackable building asks first.
					if improved && !improvement_stacks(opts[i]) {
						ask_confirm(g, .OVERWRITE_BUILD, int(opts[i]), 0, g.build_hex)
						return
					}
					res := colony_build(&g.colony, g.build_hex, opts[i])
					switch res {
					case 0:
						audio_play(.BUILD)
						if improvement_stacks(opts[i]) {
							set_status(g, "Added on top of the building.")
						} else {
							set_status(g, improved ? "Improvement replaced." : "Improvement built.")
						}
					case 1:
						audio_play(.ERROR)
						set_status(g, "Can't build that on this terrain.")
					case 3:
						audio_play(.ERROR)
						set_status(g, "Not enough gold.")
					case:
						audio_play(.ERROR)
						set_status(g, "Can't build there.")
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
	g.arena_open = false
}

do_end_turn :: proc(g: ^Game) {
	audio_play(.TURN)
	colony_end_turn(&g.colony)
	if player_monster_count(&g.colony) == 0 {
		g.mode = .GAME_OVER
		return
	}
	// Autosave into the special slot every AUTOSAVE_EVERY turns (desktop only).
	if g.autosave_on && g.colony.turn > 0 && g.colony.turn % AUTOSAVE_EVERY == 0 {
		if save_supported() && save_game(g, AUTOSAVE_SLOT) {
			colony_notify(&g.colony, "Autosaved (turn %d).", g.colony.turn)
		}
	}
	set_status(g, "Turn advanced.")
	build_turn_summary(g)
	start_next_attack(g)
}

// A short digest of the state after a turn, shown as a fading toast.
build_turn_summary :: proc(g: ^Game) {
	for s in g.summary {
		delete(s)
	}
	clear(&g.summary)
	fp := colony_food_production(&g.colony)
	upk := 0
	for &m in g.colony.roster {
		if !m.wild {
			upk += monster_upkeep(&m)
		}
	}
	append(&g.summary, fmt.aprintf("Turn %d", g.colony.turn))
	append(&g.summary, fmt.aprintf("Gold +%d/turn", colony_gold_production(&g.colony)))
	append(&g.summary, fmt.aprintf("Food +%d  (net %+d, upkeep %d)", fp, fp - upk, upk))
	append(&g.summary, fmt.aprintf("Monsters %d   stored %d", player_monster_count(&g.colony), len(g.colony.storage)))
	append(&g.summary, fmt.aprintf("Heat %d   raids %d", g.colony.heat, g.colony.raids))
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

// Candidate attackers for a strike on `hex`: your monsters on it and (within 1)
// around it. Everyone starts selected.
player_monster_count :: proc(c: ^Colony) -> int {
	n := len(c.storage) // monsters in Dens/Nurseries still count as yours
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
	tooltip_clear()
	ui_cursor_reset()
	ui_set_tooltips(g.tooltips_on)
	switch g.mode {
	case .TITLE:
		draw_title(g)
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
		if g.arena_open {
			draw_arena(g)
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
	if g.show_help {
		draw_help(g)
	}
	if g.show_settings {
		draw_settings(g)
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
	if g.show_upgrades {
		draw_upgrades(g)
	}
	if g.show_quests {
		draw_quests(g)
	}
	if g.show_relics {
		draw_relics(g)
	}
	if g.show_graveyard {
		draw_graveyard(g)
	}
	if g.show_nursery {
		draw_nursery(g)
	}
	if g.show_storage {
		draw_storage(g)
	}
	if g.show_save {
		draw_save_panel(g)
	}
	if g.unit_picker_open {
		draw_unit_picker(g)
	}
	if len(g.colony.choices) > 0 {
		draw_move_choice(g)
	}
	if g.confirm_kind != .NONE {
		draw_confirm(g)
	}
	tooltip_draw()
	ui_cursor_apply()
	if g.show_fps {
		rl.DrawFPS(i32(rl.GetScreenWidth()) - 96, i32(rl.GetScreenHeight()) - 26)
	}
}
