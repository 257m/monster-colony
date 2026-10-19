package main

import rl "vendor:raylib"
import "core:fmt"
build_attack :: proc(g: ^Game, hex: Hex, radius: int) {
	clear(&g.attack_ids)
	clear(&g.attack_chosen)
	for &m in g.colony.roster {
		if m.wild || m.creature.hp <= 0 || m.acted {
			continue // already acted this turn
		}
		if hex_distance(m.pos, hex) <= radius {
			append(&g.attack_ids, m.id)
			append(&g.attack_chosen, true)
		}
	}
}

// Move the chosen attackers that are adjacent onto the contested tile, paying
// movement energy. The click that opened the picker no longer moves anyone, so
// backing out costs nothing — the move happens here, on commit. A monster that
// can't afford it simply fights from where it stands.
attack_move_attackers :: proc(g: ^Game) {
	hex := g.battle_hex
	for id, i in g.attack_ids {
		if i >= len(g.attack_chosen) || !g.attack_chosen[i] {
			continue
		}
		mi := monster_by_id(&g.colony, id)
		if mi < 0 {
			continue
		}
		m := &g.colony.roster[mi]
		if hex_equal(m.pos, hex) || hex_distance(m.pos, hex) != 1 {
			continue
		}
		if monsters_on_tile(&g.colony, hex, false) >= MAX_MONSTERS_PER_TILE {
			break
		}
		_ = colony_move(&g.colony, mi, hex)
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
	sw := f32(screen_w())
	sh := f32(screen_h())
	return rl.Rectangle{sw / 2 - 390, sh / 2 - 290, 780, 580}
}

ATTACK_MAX_ROWS :: 12
// Your monsters get two-line rows (name, then its numbers) so a long name can
// never run into the HP and distance beside it.
ATTACK_ROW_H :: f32(40)

attack_row_rect :: proc(i: int) -> rl.Rectangle {
	p := attack_panel_rect()
	return rl.Rectangle{p.x + 24, p.y + 100 + f32(i) * ATTACK_ROW_H, 340, ATTACK_ROW_H - 6}
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
	mp := mouse_pos()
	for i in 0..<len(g.attack_ids) {
		if i >= ATTACK_MAX_ROWS {
			break
		}
		if rl.CheckCollisionPointRec(mp, attack_row_rect(i)) {
			// A fight is fought by at most PARTY_MAX monsters, so don't let a
			// seventh be ticked and then silently dropped.
			if !g.attack_chosen[i] && attack_chosen_count(g) >= PARTY_MAX {
				set_status(g, "A party is six monsters. Untick one first.")
				return
			}
			g.attack_chosen[i] = !g.attack_chosen[i]
			return
		}
	}
	if attack_chosen_count(g) == 0 {
		return // need at least one attacker
	}
	if rl.CheckCollisionPointRec(mp, attack_auto_rect()) {
		attack_move_attackers(g)
		begin_battle(g, true)
		return
	}
	if rl.CheckCollisionPointRec(mp, attack_manual_rect()) {
		attack_move_attackers(g)
		begin_battle(g, false)
		return
	}
}

draw_attack_select :: proc(g: ^Game) {
	sw := f32(screen_w())
	sh := f32(screen_h())
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

	mp := mouse_pos()
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

		// Name on the first line, clipped so it can never overrun the row.
		rl.DrawText(fit_text(m.creature.name, 16, i32(rec.width) - 46), i32(rec.x) + 34, i32(rec.y) + 2, 16, rl.Color{225, 225, 240, 255})
		// Its numbers on the second.
		dist := hex_distance(m.pos, g.battle_hex)
		loc := dist == 0 ? cstring("on tile") : fmt.ctprintf("%d away", dist)
		rl.DrawText(fmt.ctprintf("Lvl %d    %d/%d hp", m.creature.level, m.creature.hp, m.creature.max_hp),
			i32(rec.x) + 34, i32(rec.y) + 20, 14, rl.Color{200, 200, 220, 255})
		lw := rl.MeasureText(loc, 14)
		rl.DrawText(loc, i32(rec.x + rec.width) - lw - 10, i32(rec.y) + 20, 14, rl.Color{150, 150, 170, 255})
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
		border := m.role == .ALPHA ? rl.Color{255, 205, 80, 255} : rarity_color(rar)
		rl.DrawRectangleRounded(rec, 0.18, 5, rl.Color{46, 28, 28, 255})
		rl.DrawRectangleRoundedLinesEx(rec, 0.18, 5, 2, border)
		name_col := m.role == .ALPHA ? rl.Color{255, 215, 95, 255} : rl.Color{240, 222, 212, 255}
		suffix := wild_role_tag(m.role)
		el := elements_label(creature_elements(&m.creature))
		ew := rl.MeasureText(el, 14)
		head := fmt.ctprintf("%s  Lvl %d%s", m.creature.name, m.creature.level, suffix)
		rl.DrawText(fit_text(string(head), 16, i32(rec.width) - 24 - ew - 10), i32(rec.x) + 12, i32(rec.y) + 5, 16, name_col)
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
	sw := f32(screen_w())
	sh := f32(screen_h())
	return rl.Rectangle{sw / 2 - 310, sh / 2 - 190, 620, 380}
}

// The name lists are laid out in a grid, so a full party of six can never run
// off the side of the panel.
CHOICE_COLS :: 3
CHOICE_COL_W :: 190
CHOICE_ROW_H :: 22

// Draw up to CHOICE_COLS x 2 names starting at (x, y).
draw_choice_names :: proc(x, y: i32, names: []cstring, n: int, col: rl.Color) {
	for i in 0..<n {
		c := i % CHOICE_COLS
		r := i / CHOICE_COLS
		rl.DrawText(names[i], x + i32(c*CHOICE_COL_W), y + i32(r*CHOICE_ROW_H), 15, col)
	}
}

choice_auto_rect :: proc() -> rl.Rectangle {
	p := choice_panel_rect()
	return rl.Rectangle{p.x + 30, p.y + 248, 260, 58}
}

choice_manual_rect :: proc() -> rl.Rectangle {
	p := choice_panel_rect()
	return rl.Rectangle{p.x + p.width - 290, p.y + 248, 260, 58}
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
	mp := mouse_pos()
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
	// Relic Towers in range of this fight project their battle relics onto the
	// party (see `battle_apply_relics`) — but not in the Arena, which is meant to
	// be a fair fight. The Arena projects only the boons you picked up on the way
	// up, and those die with the run.
	if g.battle_arena {
		battle_apply_relics(&g.battle, arena_boon_counts(&g.colony))
	} else {
		battle_apply_relics(&g.battle, relics_in_range(&g.colony, g.battle_hex))
	}
	// Fighting ends the turn for the monsters that take part, so you can't
	// chain fights to keep moving on battle-refilled energy.
	for &m in g.colony.roster {
		if m.wild {
			continue
		}
		for d in defs {
			if d == &m.creature {
				m.acted = true
				break
			}
		}
	}
	// Everything below is the colony helping its own side: Watchtower guard
	// Block, Drills, the Beacon's mark, the Kitchen's rations and the Scouts'
	// capture edge. An **Arena** fight skips all of it — it is meant to be a
	// fair fight where only monsters, decks, abilities and items decide it.
	if !g.battle_arena {
		// Watchtower guard bonus: applied after the opening draw/reset.
		// Drills: the colony's defenders start every fight with some Block.
		drills := upgrade_drills_block(&g.colony)
		for p, i in g.battle.party {
			p.block += blocks[i] + drills
		}
		g.battle.capture_bonus = upgrade_capture_bonus(&g.colony)
		// Beacon: wilds attacking within its guard radius start Vulnerable.
		if near_improvement(&g.colony, hex, BEACON_GUARD, .BEACON) {
			vuln := BEACON_VULN + upgrade_beacon_vuln(&g.colony)
			for e in g.battle.enemies {
				e.vulnerable += vuln
			}
		}
		// Kitchen: spend rations to give the defenders +Strength for this fight.
		if ki := nearest_improvement_within(&g.colony, hex, KITCHEN_RADIUS, .KITCHEN); ki >= 0 {
			if gi := nearest_food_store_with(&g.colony, g.colony.tiles[ki].hex, DELIVER_RADIUS, KITCHEN_FOOD_COST); gi >= 0 {
				g.colony.tiles[gi].stored -= KITCHEN_FOOD_COST
				str := KITCHEN_STRENGTH + upgrade_kitchen_strength(&g.colony)
				for p in g.battle.party {
					p.strength += str
				}
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
	// An auto-fight has nobody at the keyboard, so it settles itself rather than
	// waiting for a click that will never come.
	if !g.battle.auto_play {
		cont := rl.IsMouseButtonPressed(.LEFT) ||
			rl.IsKeyPressed(.SPACE) || rl.IsKeyPressed(.ENTER)
		if !cont {
			return
		}
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
	g.battle_arena = false
	g.colony.capture_cards = g.battle.capture_cards
	battle_free(&g.battle)
	g.battle = Battle{}
	g.has_battle = false
}

// Queues up to MAX_CHOICE_OPTIONS reward cards the defender on `hex` doesn't
// know, for the player to pick from. Returns the option count (0 = nothing).
grant_card_to_defender :: proc(g: ^Game, hex: Hex) -> int {
	idx := -1
	for &m, i in g.colony.roster {
		if !m.wild && hex_equal(m.pos, hex) && m.creature.hp > 0 {
			idx = i
			break
		}
	}
	if idx < 0 {
		return 0
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
	n := min(len(unknown), MAX_CHOICE_OPTIONS)
	if n == 0 {
		return 0
	}
	// Weighted pick of n distinct options: commons show up far more often than
	// rares, so a RARE card in the offer is a genuine treat.
	opts: [MAX_CHOICE_OPTIONS]Move_Id
	for i in 0..<n {
		total := 0
		for u in unknown {
			total += card_rarity_weight(MOVE_DATA[u].rarity)
		}
		if total <= 0 {
			break
		}
		roll := rng_below(&g.colony.rng, total)
		acc := 0
		pick := 0
		for u, k in unknown {
			acc += card_rarity_weight(MOVE_DATA[u].rarity)
			if roll < acc {
				pick = k
				break
			}
		}
		opts[i] = unknown[pick]
		unordered_remove(&unknown, pick)
	}
	enqueue_choice(&g.colony, g.colony.roster[idx].id, opts, n, .REWARD)
	return n
}

resolve_won :: proc(g: ^Game) {
	audio_play(.VICTORY)
	hex := g.battle_hex
	// `finish_battle` clears this partway through, so remember it up front.
	was_arena := g.battle_arena

	// Tally results from the wilds on the tile before anything is removed.
	res: Battle_Results
	food_amt := 0
	killed_levels := 0
	boss_killed := false
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
		if m.role == .ALPHA {
			g.colony.alphas_slain += 1
		}
		if m.role == .BOSS {
			g.colony.bosses_slain[m.creature.species] = true
			boss_killed = true
		}
		loot := species_loot_gold(m.creature.species, lv) + rng_below(&g.colony.rng, lv + 1)
		res.gold += int(f32(loot) * upgrade_bounty_mult(&g.colony))
		killed_levels += lv
		food_amt += lv * 2 + upgrade_forage_food(&g.colony)
	}
	res.xp = int(f32(killed_levels * 10) * upgrade_xp_mult(&g.colony) * relic_xp_mult_at(&g.colony, hex))
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

	// Food drops go to food stores within range, spilling over when one fills.
	res.food = colony_store_food(&g.colony, hex, food_amt)

	// XP to surviving defenders on the tile.
	for &m in g.colony.roster {
		if !m.wild && hex_equal(m.pos, hex) && m.creature.hp > 0 {
			if monster_add_xp(&g.colony, &m, res.xp) {
				res.leveled = true
			}
		}
	}

	// Rare reward card: offer the defender a choice.
	if rng_f32(&g.colony.rng) < 0.18 {
		if grant_card_to_defender(g, hex) > 0 {
			res.reward = true
		}
	}

	// Item drop: a slain boss always drops one, normal fights sometimes. Arena
	// floors deliberately do *not*: a tower climb would otherwise be an item
	// faucet, and the trial floors are where the run hands out gear.
	if boss_killed || rng_f32(&g.colony.rng) < 0.22 {
		// Only fits while the bag has room; build a Vault to hold more.
		if len(g.colony.items) < colony_item_cap(&g.colony) {
			it := random_item(&g.colony.rng)
			append(&g.colony.items, it)
			res.item = it
		}
	}

	// Arena and Boss rewards belong to the *fight*, not the tile: an ordinary
	// wild that happens to be standing on an Arena or Boss Room pays nothing
	// extra, or you could farm the tile's bounty off wandering mobs.
	if t := tile_at(&g.colony, hex); t != nil {
		bonus := upgrade_crystal_bonus(&g.colony) + relic_crystal_bonus_at(&g.colony, hex)
		if t.terrain == .ARENA && was_arena {
			floor := max(g.colony.arena_floor, 1)
			// The floor's purse is *banked*, not paid: the run pays out when you
			// cash out, and a wipe loses it.
			purse, gold := arena_clear_floor(&g.colony, hex, floor)
			res.crystals = purse + bonus
			g.colony.arena_run_crystals += bonus
			res.gold += gold
			colony_notify(&g.colony, "Arena floor %d cleared - %d crystals banked.", floor, purse)
			audio_play(.CRYSTAL)
		} else if boss_killed {
			g.colony.crystals += BOSS_CRYSTAL_REWARD + bonus
			g.colony.crystals_earned += BOSS_CRYSTAL_REWARD + bonus
			res.crystals = BOSS_CRYSTAL_REWARD + bonus
			audio_play(.CRYSTAL)
			// Bosses always drop a relic; it stacks.
			r := random_relic(&g.colony.rng)
			grant_relic(&g.colony, r)
			res.relic = r
			res.has_relic = true
		}
	}

	g.colony.fights_won += 1
	milestones_check(&g.colony)

	g.results = res
	g.results_open = true
	// A run in progress has its own screen, so a won floor drops you back there
	// rather than onto the map where the party could be rearranged.
	if g.colony.arena_run {
		g.mode = .ARENA
		// A run is a long thing; bank it after every floor.
		if g.autosave_on && save_supported() {
			_ = save_game(g, AUTOSAVE_SLOT)
		}
	} else {
		g.mode = .MAP
	}
}

results_continue_rect :: proc() -> rl.Rectangle {
	sw := f32(screen_w())
	sh := f32(screen_h())
	return rl.Rectangle{sw / 2 - 90, sh / 2 + 130, 180, 50}
}

update_results :: proc(g: ^Game) {
	if rl.IsKeyPressed(.SPACE) || rl.IsKeyPressed(.ENTER) {
		g.results_open = false
		start_next_attack(g)
		return
	}
	if rl.IsMouseButtonPressed(.LEFT) && rl.CheckCollisionPointRec(mouse_pos(), results_continue_rect()) {
		g.results_open = false
		start_next_attack(g)
	}
}

draw_results :: proc(g: ^Game) {
	sw := f32(screen_w())
	sh := f32(screen_h())
	rl.DrawRectangle(0, 0, i32(sw), i32(sh), rl.Color{0, 0, 0, 170})

	w := f32(420)
	h := f32(400)
	p := rl.Rectangle{sw / 2 - w / 2, sh / 2 - h / 2 - 20, w, h}
	draw_panel(p, rl.Color{20, 26, 22, 248}, rl.Color{120, 220, 150, 255}, 0.05, 8, 3)

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
	if r.reward {
		rl.DrawText("Reward card - choose one!", i32(p.x) + 30, y, 20, rl.Color{210, 160, 255, 255}); y += 28
	}
	if r.leveled {
		rl.DrawText("A monster levelled up!", i32(p.x) + 30, y, 20, rl.Color{255, 235, 140, 255}); y += 28
	}
	if r.item != .NONE {
		rl.DrawText(fmt.ctprintf("Item found: %s", item_name(r.item)), i32(p.x) + 30, y, 20, rl.Color{180, 240, 200, 255}); y += 24
		rl.DrawText("Equip it from the deck viewer (V).", i32(p.x) + 30, y, 14, rl.Color{150, 190, 165, 255}); y += 24
	}
	if r.crystals > 0 {
		rl.DrawText(fmt.ctprintf("Arena prize: +%d crystals", r.crystals), i32(p.x) + 30, y, 20, rl.Color{210, 170, 250, 255}); y += 28
	}
	if r.has_relic {
		rl.DrawText(fmt.ctprintf("Relic: %s", relic_name(r.relic)), i32(p.x) + 30, y, 20, rl.Color{245, 215, 140, 255}); y += 22
		rl.DrawText("Colony-wide passive - it stacks! (J)", i32(p.x) + 30, y, 14, rl.Color{200, 180, 130, 255}); y += 24
	}

	btn := results_continue_rect()
	draw_button(btn, cstring("Continue"), true, BUTTON_GO, 20, 8)
}

resolve_lost :: proc(g: ^Game) {
	audio_play(.DEFEAT)
	finish_battle(g)
	i := 0
	for i < len(g.colony.roster) {
		if !g.colony.roster[i].wild && g.colony.roster[i].creature.hp <= 0 {
			remove_monster_at(&g.colony, i, true)
			continue
		}
		i += 1
	}
	// A lost Arena match ends the run: the team leaves, the winnings are lost,
	// and you start again from floor 1 (your best floor is kept as the record).
	if t := tile_at(&g.colony, g.battle_hex); t != nil && t.terrain == .ARENA {
		arena_reset(g)
		if g.colony.arena_run && g.colony.arena_run_crystals > 0 {
			colony_notify(&g.colony, "The run ends here - %d crystals lost.", g.colony.arena_run_crystals)
		}
		g.colony.arena_run = false
		g.colony.arena_run_crystals = 0
		g.colony.arena_floor = 1
		clear(&g.colony.arena_boons)
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
	sw := f32(screen_w())
	sh := f32(screen_h())
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

	atk: [CHOICE_COLS * 2]cstring
	na := 0
	for &m in g.colony.roster {
		if !m.wild || !hex_equal(m.pos, hex) || na >= len(atk) {
			continue
		}
		atk[na] = fmt.ctprintf("%s Lvl %d", m.creature.name, m.creature.level)
		na += 1
	}
	rl.DrawText("Attackers:", i32(p.x) + 24, i32(p.y) + 88, 16, rl.Color{220, 150, 150, 255})
	draw_choice_names(i32(p.x) + 24, i32(p.y) + 110, atk[:], na, rl.Color{235, 180, 180, 255})

	def: [CHOICE_COLS * 2]cstring
	nd := 0
	for &m in g.colony.roster {
		if m.wild || !hex_equal(m.pos, hex) || nd >= len(def) {
			continue
		}
		def[nd] = fmt.ctprintf("%s Lvl %d", m.creature.name, m.creature.level)
		nd += 1
	}
	rl.DrawText("Defenders:", i32(p.x) + 24, i32(p.y) + 164, 16, rl.Color{170, 190, 170, 255})
	draw_choice_names(i32(p.x) + 24, i32(p.y) + 186, def[:], nd, rl.Color{200, 220, 200, 255})
	_ = sh

	mp := mouse_pos()
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
