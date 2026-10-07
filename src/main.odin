package main

import rl "vendor:raylib"
import "core:time"
import "core:math"
import "core:fmt"

Game_Mode :: enum { STARTER, MAP, BATTLE, REWARD, GAME_OVER }

Game :: struct {
	mode:     Game_Mode,
	renderer: Hex_Renderer,
	graph:    Map_Graph,
	battle:   Battle,
	party:    [dynamic]Creature,
	active:   int,
	moves:    int,
	cleared:  bool,
	seed_rng: Rng,
	cfg:      Map_Config,

	// deck viewer overlay
	show_deck:   bool,
	view_index:  int,
	view_scroll: f32,

	// card reward screen
	reward_options: [dynamic]Move_Id,
	pending_cleared: bool,

	// the tile whose encounter is currently being resolved
	pending_node: Hex,
	has_pending:  bool,
}

main :: proc() {
	rl.SetConfigFlags({.WINDOW_RESIZABLE, .MSAA_4X_HINT})
	rl.InitWindow(1280, 720, "Vibegambling - Hex Dungeon")
	defer rl.CloseWindow()
	rl.SetTargetFPS(60)

	g: Game
	g.cfg = default_map_config()
	g.seed_rng = rng_make(u64(time.now()._nsec))
	g.party = make([dynamic]Creature, 0)
	g.reward_options = make([dynamic]Move_Id, 0)

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
// Run lifecycle
// ----------------------------------------------------------------------------

end_run :: proc(g: ^Game) {
	map_free(&g.graph)
	g.graph = Map_Graph{}
	battle_free(&g.battle)
	g.battle = Battle{}
	party_free(&g.party)
	delete(g.reward_options)
	g.reward_options = make([dynamic]Move_Id, 0)
	g.show_deck = false
}

reset_to_starter :: proc(g: ^Game) {
	end_run(g)
	g.mode = .STARTER
}

choose_starter :: proc(g: ^Game, species_idx: int) {
	party_free(&g.party)
	append(&g.party, creature_make(species_idx, 1, SPECIES[species_idx].name))
	g.active = 0
	g.graph = generate_map(rng_next_u64(&g.seed_rng), g.cfg)
	g.moves = 0
	g.cleared = false
	g.mode = .MAP
	center_camera_on(&g.renderer, g.graph.current_hex)
}

// ----------------------------------------------------------------------------
// Update
// ----------------------------------------------------------------------------

game_update :: proc(g: ^Game, dt: f32) {
	// Deck viewer is a modal pause over whichever scene is active.
	if g.show_deck {
		update_deck_viewer(g, dt)
		return
	}
	if (g.mode == .MAP || g.mode == .BATTLE) && len(g.party) > 0 && rl.IsKeyPressed(.V) {
		g.show_deck = true
		g.view_index = clamp(g.active, 0, len(g.party) - 1)
		g.view_scroll = 0
		return
	}

	switch g.mode {
	case .STARTER:
		update_starter(g)
	case .MAP:
		update_map(g, dt)
	case .BATTLE:
		update_battle(g, dt)
	case .REWARD:
		update_reward(g)
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

update_map :: proc(g: ^Game, dt: f32) {
	hex_renderer_update_camera(&g.renderer, dt)

	if rl.IsMouseButtonDown(.RIGHT) {
		d := rl.GetMouseDelta()
		g.renderer.camera_x -= d.x / g.renderer.zoom
		g.renderer.camera_y -= d.y / g.renderer.zoom
	}

	if rl.IsKeyPressed(.N) {
		reset_to_starter(g)
		return
	}
	if rl.IsKeyPressed(.R) {
		center_camera_on(&g.renderer, g.graph.current_hex)
	}

	if g.cleared {
		return
	}

	hovered := hex_renderer_hovered(&g.renderer)
	if !rl.IsMouseButtonPressed(.LEFT) || !can_travel_to(&g.graph, hovered) {
		return
	}

	if !travel_to(&g.graph, hovered) {
		return
	}
	g.moves += 1
	center_camera_on(&g.renderer, g.graph.current_hex)

	node := map_get(&g.graph, hovered)
	if node == nil || node.cleared {
		return
	}

	// Resolve the tile's encounter (once).
	#partial switch node.kind {
	case .COMBAT, .ELITE, .BOSS:
		g.pending_node = hovered
		g.has_pending = true
		g.pending_cleared = false
		battle_free(&g.battle)
		g.battle = battle_start(&g.party, g.active, node.kind, node.depth, &g.seed_rng)
		g.mode = .BATTLE
	case .REST:
		party_heal(&g.party, 1.0 / 3.0)
		node.cleared = true
	case:
		node.cleared = true // START / SHOP / EVENT (no effect yet)
	}
}

update_battle :: proc(g: ^Game, dt: f32) {
	battle_update(&g.battle, dt)
	battle_input(&g.battle)

	if g.battle.timer <= 0.4 {
		return
	}
	continue_pressed := rl.IsMouseButtonPressed(.LEFT) ||
		rl.IsKeyPressed(.SPACE) || rl.IsKeyPressed(.ENTER)
	if !continue_pressed {
		return
	}

	#partial switch g.battle.phase {
	case .WON:
		if g.battle.active >= 0 && g.battle.active < len(g.party) {
			creature_level_up(&g.party[g.battle.active])
		}
		if g.has_pending {
			g.pending_cleared = map_node_kind(&g.graph, g.pending_node) == .BOSS
			clear_node(&g.graph, g.pending_node)
			g.has_pending = false
		}
		open_reward(g)
	case .CAPTURED:
		if g.has_pending {
			clear_node(&g.graph, g.pending_node)
			g.has_pending = false
		}
		g.mode = .MAP
		center_camera_on(&g.renderer, g.graph.current_hex)
	case .LOST:
		g.mode = .GAME_OVER
	case:
	}
}

// ----------------------------------------------------------------------------
// Draw
// ----------------------------------------------------------------------------

game_draw :: proc(g: ^Game) {
	switch g.mode {
	case .STARTER:
		draw_starter()
	case .MAP:
		draw_map(g)
	case .BATTLE:
		draw_battle(&g.battle)
	case .REWARD:
		draw_reward(g)
	case .GAME_OVER:
		draw_game_over(g.moves)
	}

	if g.show_deck {
		draw_deck_viewer(g)
	}
}

// ----------------------------------------------------------------------------
// Card reward screen
// ----------------------------------------------------------------------------

reward_card_rect :: proc(i, count: int) -> rl.Rectangle {
	sw := f32(rl.GetScreenWidth())
	sh := f32(rl.GetScreenHeight())
	w := f32(184)
	h := f32(258)
	gap := f32(34)
	total := f32(count) * w + f32(count - 1) * gap
	start := sw / 2 - total / 2
	return rl.Rectangle{start + f32(i) * (w + gap), sh / 2 - h / 2 - 24, w, h}
}

reward_skip_rect :: proc() -> rl.Rectangle {
	sw := f32(rl.GetScreenWidth())
	sh := f32(rl.GetScreenHeight())
	return rl.Rectangle{sw / 2 - 90, sh - 96, 180, 48}
}

open_reward :: proc(g: ^Game) {
	delete(g.reward_options)
	g.reward_options = make([dynamic]Move_Id, 0)

	if len(g.party) == 0 || g.battle.active < 0 || g.battle.active >= len(g.party) {
		g.mode = .MAP
		return
	}

	c := &g.party[g.battle.active]
	sp := SPECIES[c.species]

	// Reward picks are limited to this species' move pool. Moves in the pool
	// but not in the level learnset can ONLY be obtained here.
	avail := make([dynamic]Move_Id, 0)
	defer delete(avail)
	for id in sp.move_pool {
		if !contains_move(avail[:], id) {
			append(&avail, id)
		}
	}

	// Prefer moves the creature does not already have; fall back to repeats.
	unknown := make([dynamic]Move_Id, 0)
	defer delete(unknown)
	known := make([dynamic]Move_Id, 0)
	defer delete(known)
	for id in avail {
		if creature_knows(c, id) {
			append(&known, id)
		} else {
			append(&unknown, id)
		}
	}
	shuffle_cards(&unknown, &g.seed_rng)
	shuffle_cards(&known, &g.seed_rng)

	for id in unknown {
		if len(g.reward_options) >= 3 { break }
		append(&g.reward_options, id)
	}
	for id in known {
		if len(g.reward_options) >= 3 { break }
		append(&g.reward_options, id)
	}

	g.mode = .REWARD
}

contains_move :: proc(haystack: []Move_Id, needle: Move_Id) -> bool {
	for m in haystack {
		if m == needle {
			return true
		}
	}
	return false
}

finish_reward :: proc(g: ^Game, choice: int) {
	if choice >= 0 && choice < len(g.reward_options) && len(g.party) > 0 {
		idx := clamp(g.battle.active, 0, len(g.party) - 1)
		append(&g.party[idx].deck, g.reward_options[choice])
	}

	delete(g.reward_options)
	g.reward_options = make([dynamic]Move_Id, 0)

	if g.pending_cleared {
		g.cleared = true
		g.pending_cleared = false
	}

	g.mode = .MAP
	center_camera_on(&g.renderer, g.graph.current_hex)
}

update_reward :: proc(g: ^Game) {
	if len(g.reward_options) == 0 {
		return
	}
	if rl.IsKeyPressed(.S) || rl.IsKeyPressed(.ESCAPE) {
		finish_reward(g, -1)
		return
	}
	for key, i in DIGIT_KEYS {
		if i < len(g.reward_options) && rl.IsKeyPressed(key) {
			finish_reward(g, i)
			return
		}
	}
	if rl.IsMouseButtonPressed(.LEFT) {
		mp := rl.GetMousePosition()
		for i in 0..<len(g.reward_options) {
			if rl.CheckCollisionPointRec(mp, reward_card_rect(i, len(g.reward_options))) {
				finish_reward(g, i)
				return
			}
		}
		if rl.CheckCollisionPointRec(mp, reward_skip_rect()) {
			finish_reward(g, -1)
			return
		}
	}
}

draw_reward :: proc(g: ^Game) {
	sw := f32(rl.GetScreenWidth())
	sh := f32(rl.GetScreenHeight())
	rl.ClearBackground(rl.Color{12, 14, 22, 255})

	title := cstring("CHOOSE A CARD")
	tw := rl.MeasureText(title, 40)
	rl.DrawText(title, i32(sw) / 2 - tw / 2, 58, 40, rl.Color{230, 230, 245, 255})

	if len(g.party) > 0 {
		idx := clamp(g.battle.active, 0, len(g.party) - 1)
		c := &g.party[idx]
		note := fmt.ctprintf("%s reached Lv %d   -   HP max %d   PWR +%d   DEF %d   SPD %d", c.name, c.level, c.max_hp, c.power, c.defense, c.speed)
		nw := rl.MeasureText(note, 20)
		rl.DrawText(note, i32(sw) / 2 - nw / 2, 112, 20, element_color(creature_element(c)))
	}

	mp := rl.GetMousePosition()
	for card, i in g.reward_options {
		rec := reward_card_rect(i, len(g.reward_options))
		hovered := rl.CheckCollisionPointRec(mp, rec)
		draw_card(card, rec, true, hovered)
		num := fmt.ctprintf("%d", i + 1)
		rl.DrawText(num, i32(rec.x) + 8, i32(rec.y) + i32(rec.height) - 20, 14, rl.Color{190, 190, 210, 255})
	}

	skip := reward_skip_rect()
	hover := rl.CheckCollisionPointRec(mp, skip)
	col := rl.Color{48, 48, 58, 255}
	if hover {
		col = rl.Color{70, 70, 86, 255}
	}
	rl.DrawRectangleRounded(skip, 0.3, 8, col)
	rl.DrawRectangleRoundedLinesEx(skip, 0.3, 8, 2, rl.Color{120, 120, 140, 255})
	st := cstring("Skip (S)")
	stw := rl.MeasureText(st, 18)
	rl.DrawText(st, i32(skip.x + skip.width / 2) - stw / 2, i32(skip.y + skip.height / 2) - 9, 18, rl.Color{200, 200, 215, 255})

	hint := cstring("Click a card, or press 1-3")
	hw := rl.MeasureText(hint, 16)
	rl.DrawText(hint, i32(sw) / 2 - hw / 2, i32(sh) - 32, 16, rl.Color{140, 140, 160, 255})
}

// ----------------------------------------------------------------------------
// Deck viewer
// ----------------------------------------------------------------------------

DV_COLS   :: 7
DV_CW     :: f32(104)
DV_CH     :: f32(140)
DV_GAP    :: f32(10)
DV_TOP    :: f32(176)
DV_BOTTOM :: f32(64)

deck_max_scroll :: proc(g: ^Game) -> f32 {
	if len(g.party) == 0 {
		return 0
	}
	n := len(g.party[g.view_index].deck)
	rows := (n + DV_COLS - 1) / DV_COLS
	content := f32(rows) * (DV_CH + DV_GAP) - DV_GAP
	visible := f32(rl.GetScreenHeight()) - DV_TOP - DV_BOTTOM
	return max(f32(0), content - visible)
}

update_deck_viewer :: proc(g: ^Game, dt: f32) {
	if len(g.party) == 0 {
		g.show_deck = false
		return
	}
	if g.view_index < 0 || g.view_index >= len(g.party) {
		g.view_index = 0
	}

	if rl.IsKeyPressed(.V) || rl.IsKeyPressed(.ESCAPE) {
		g.show_deck = false
		return
	}

	n := len(g.party)
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

	c := &g.party[g.view_index]
	element := creature_element(c)

	name := fmt.ctprintf("%s's Deck", c.name)
	rl.DrawText(name, 40, 26, 34, rl.Color{235, 235, 245, 255})
	sub := fmt.ctprintf("Lv %d   %s   HP %d/%d   PWR +%d   DEF %d   SPD %d   Energy %s max (%s regen)   %d cards",
		c.level, element_name(element), c.hp, c.max_hp, c.power, creature_defense(c), c.speed, fmt_num(c.energy_max), fmt_num(c.energy_regen), len(c.deck))
	rl.DrawText(sub, 40, 68, 18, element_color(element))
	pager := fmt.ctprintf("creature %d / %d   -   Left/Right or Q/E to switch", g.view_index + 1, len(g.party))
	rl.DrawText(pager, 40, 96, 16, rl.Color{150, 150, 170, 255})

	n := len(c.deck)
	total_w := f32(DV_COLS) * DV_CW + f32(DV_COLS - 1) * DV_GAP
	start_x := sw / 2 - total_w / 2
	base_y := DV_TOP - g.view_scroll
	mp := rl.GetMousePosition()

	rl.BeginScissorMode(0, i32(DV_TOP) - 4, i32(sw), i32(sh - DV_TOP - DV_BOTTOM) + 8)
	for i in 0..<n {
		col := i % DV_COLS
		row := i / DV_COLS
		rec := rl.Rectangle{start_x + f32(col) * (DV_CW + DV_GAP), base_y + f32(row) * (DV_CH + DV_GAP), DV_CW, DV_CH}
		if rec.y + DV_CH < DV_TOP - 8 || rec.y > sh - DV_BOTTOM + 8 {
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
	sub := cstring("Each has its own deck, a per-level learnset (auto-learned) and a wider move pool (reward choices)")
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

draw_map :: proc(g: ^Game) {
	rl.ClearBackground(rl.Color{13, 13, 20, 255})

	draw_connections(&g.renderer, &g.graph)

	hovered := hex_renderer_hovered(&g.renderer)
	is_move := !g.cleared && can_travel_to(&g.graph, hovered)

	for n in g.graph.nodes {
		if is_current(&g.graph, n.hex) {
			continue
		}
		if !n.revealed {
			continue // fog of war: unexplored tiles are hidden
		}
		draw_map_node(&g.renderer, n.hex, n.kind, n.revealed, n.visited, false, is_move && hex_equal(n.hex, hovered))
	}
	for n in g.graph.nodes {
		if !is_current(&g.graph, n.hex) {
			continue
		}
		draw_map_node(&g.renderer, n.hex, n.kind, n.revealed, n.visited, true, false)
	}

	draw_hover_marker(&g.renderer, hovered, is_move)
	draw_hud(g)
}

draw_connections :: proc(r: ^Hex_Renderer, g: ^Map_Graph) {
	for n in g.nodes {
		ax, ay := hex_to_screen(r, n.hex)
		for c in n.connections {
			if !hex_less(n.hex, c) {
				continue
			}
			dst, ok := map_node_at(g, c)
			if !ok {
				continue
			}
			// Only draw links between explored tiles (fog of war).
			if !n.revealed || !dst.revealed {
				continue
			}
			bx, by := hex_to_screen(r, c)

			color := rl.Color{38, 38, 52, 255}
			thick := 3.0 * r.zoom
			if n.visited && dst.visited {
				color = rl.Color{70, 130, 100, 255}
				thick = 5.0 * r.zoom
			} else {
				color = rl.Color{55, 55, 74, 255}
			}
			rl.DrawLineEx(rl.Vector2{ax, ay}, rl.Vector2{bx, by}, thick, color)
		}
	}
}

// Deterministic ordering so shared edges are only drawn once.
hex_less :: proc(a, b: Hex) -> bool {
	if a.r != b.r {
		return a.r < b.r
	}
	return a.q < b.q
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

draw_hud :: proc(g: ^Game) {
	sw := f32(rl.GetScreenWidth())
	sh := f32(rl.GetScreenHeight())

	rl.DrawText("THE UNDERGROUND", 20, 18, 28, rl.Color{210, 210, 230, 255})
	revealed_count := 0
	for n in g.graph.nodes {
		if n.revealed {
			revealed_count += 1
		}
	}
	seed_text := fmt.ctprintf("seed %d   depth %d / %d   moves %d   explored %d / %d", g.graph.seed, depth_of(&g.graph), g.graph.max_depth, g.moves, revealed_count, len(g.graph.nodes))
	rl.DrawText(seed_text, 20, 52, 18, rl.Color{120, 120, 145, 255})

	cur_kind := map_node_kind(&g.graph, g.graph.current_hex)
	here := fmt.ctprintf("You are here: %s", node_type_name(cur_kind))
	rl.DrawText(here, 20, 76, 18, node_type_color(cur_kind))

	// Party list.
	y := i32(108)
	for &c, i in g.party {
		active := i == g.active
		col := rl.Color{170, 170, 190, 255}
		if active {
			col = rl.Color{140, 240, 190, 255}
		}
		mark := "  "
		if active {
			mark = "> "
		}
		line := fmt.ctprintf("%s%s  Lv%d  %d/%d  %s", mark, c.name, c.level, c.hp, c.max_hp, element_name(creature_element(&c)))
		rl.DrawText(line, 20, y + i32(i) * 22, 16, col)
	}

	rl.DrawText("LMB move to any adjacent tile (backtracking allowed)  |  RMB/WASD pan  |  wheel zoom  |  R recenter", 20, i32(sh) - 74, 16, rl.Color{110, 110, 130, 255})
	rl.DrawText("V view deck  |  N new run", 20, i32(sh) - 50, 16, rl.Color{110, 110, 130, 255})

	if g.cleared {
		msg := cstring("DUNGEON CLEARED - press N to descend again")
		w := rl.MeasureText(msg, 30)
		rl.DrawText(msg, i32(sw) / 2 - w / 2, i32(sh) - 130, 30, rl.Color{255, 220, 120, 255})
	}

	draw_legend(sw, sh)

	mini := rl.Rectangle{sw - 250, 20, 230, 170}
	hexes := make([dynamic]Hex, 0)
	defer delete(hexes)
	for n in g.graph.nodes {
		if n.revealed {
			append(&hexes, n.hex)
		}
	}
	draw_minimap(&g.renderer, hexes[:], g.graph.current_hex, mini)
}

depth_of :: proc(g: ^Map_Graph) -> int {
	if n := map_get(g, g.current_hex); n != nil {
		return n.depth
	}
	return 0
}

Legend_Entry :: struct {
	kind:  Node_Type,
	label: cstring,
}

draw_legend :: proc(sw, sh: f32) {
	entries := [?]Legend_Entry{
		{.START,  "Entrance"},
		{.COMBAT, "Combat"},
		{.ELITE,  "Elite"},
		{.REST,   "Campfire"},
		{.SHOP,   "Shop"},
		{.EVENT,  "Event"},
		{.BOSS,   "Boss"},
	}

	x := i32(20)
	y := i32(sh) - 268
	rl.DrawText("LEGEND", x, y - 24, 16, rl.Color{150, 150, 170, 255})
	for e, i in entries {
		ey := y + i32(i) * 24
		rl.DrawRectangle(x, ey, 16, 16, node_type_color(e.kind))
		rl.DrawRectangleLines(x, ey, 16, 16, rl.Color{20, 20, 20, 255})
		rl.DrawText(e.label, x + 26, ey - 1, 16, rl.Color{170, 170, 190, 255})
	}
}
