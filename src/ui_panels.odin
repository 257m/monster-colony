package main

import rl "vendor:raylib"
import "core:fmt"
import "core:math"
build_panel_rect :: proc() -> rl.Rectangle {
	return rl.Rectangle{20, 150, 360, 540}
}

BUILD_OPT_START     :: f32(96)
BUILD_REPLACE_START :: f32(216)

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
	half := (p.width - 24 - 8) / 2
	return rl.Rectangle{p.x + 12, p.y + 136, half, 46}
}

// Demolish the building/overlay here, refunding part of its cost.
build_demolish_rect :: proc() -> rl.Rectangle {
	p := build_panel_rect()
	half := (p.width - 24 - 8) / 2
	return rl.Rectangle{p.x + 12 + half + 8, p.y + 136, half, 46}
}

draw_build_panel :: proc(g: ^Game) {
	p := build_panel_rect()
	draw_panel(p, rl.Color{18, 18, 26, 240}, rl.Color{120, 120, 150, 255})
	draw_text("BUILD", i32(p.x) + 16, i32(p.y) + 12, 22, rl.Color{220, 220, 235, 255})

	if !g.has_build {
		draw_text("Click a revealed tile", i32(p.x) + 16, i32(p.y) + 52, 16, rl.Color{150, 150, 170, 255})
		draw_text("B / Esc to exit", i32(p.x) + 16, i32(p.y) + 74, 15, rl.Color{120, 120, 140, 255})
		return
	}

	t := tile_at(&g.colony, g.build_hex)
	if t == nil {
		return
	}
	info := fmt.ctprintf("Tile: %s", terrain_name(t.terrain))
	draw_text(info, i32(p.x) + 16, i32(p.y) + 46, 16, rl.Color{180, 180, 200, 255})
	gold := fmt.ctprintf("Gold: %d", colony_total_gold(&g.colony))
	draw_text(gold, i32(p.x) + 16, i32(p.y) + 68, 16, rl.Color{240, 205, 90, 255})

	if t.improvement != .NONE || t.overlay != .NONE {
		y := i32(p.y) + 92
		if t.improvement != .NONE {
			draw_text(fmt.ctprintf("Built: %s  (hp %d/%d)", improvement_name(t.improvement), t.improvement_hp, improvement_hp_cap(&g.colony, t.improvement)), i32(p.x) + 16, y, 16, rl.Color{140, 220, 150, 255})
			y += 22
		}
		if t.overlay != .NONE {
			draw_text(fmt.ctprintf("Overlay: %s  (hp %d/%d)", improvement_name(t.overlay), t.overlay_hp, improvement_max_hp(t.overlay)), i32(p.x) + 16, y, 16, rl.Color{150, 210, 235, 255})
			y += 22
		}

		// Repair + demolish, side by side.
		rim, rhp, rcap := tile_repair_target(&g.colony, t)
		can_repair := rim != .NONE
		rcost := can_repair ? improvement_repair_cost(&g.colony, rim, rhp) : 0
		afford := can_repair && colony_total_gold(&g.colony) >= rcost
		rep := build_repair_rect()
		draw_button(rep, can_repair ? fmt.ctprintf("Repair %dg", rcost) : cstring("Full HP"), afford, BUTTON_PANEL, 15)
		if rl.CheckCollisionPointRec(rl.GetMousePosition(), rep) {
			tooltip_set("%s", can_repair ? fmt.ctprintf("Repair to %d HP for %dg.", rcap, rcost) : cstring("Already at full HP."))
		}
		dem := build_demolish_rect()
		refund := improvement_refund(t.overlay != .NONE ? t.overlay : t.improvement)
		draw_button(dem, fmt.ctprintf("Demolish +%dg", refund), true, BUTTON_PANEL, 15)
		if rl.CheckCollisionPointRec(rl.GetMousePosition(), dem) {
			tooltip_set("Tear this down and refund %dg (half its base cost).", refund)
		}

		// You can overwrite a built improvement, or add a stackable overlay.
		opts: [32]Improvement
		n := buildable_improvements(&g.colony, g.build_hex, opts[:])
		if n > 0 {
			draw_text("Add / replace:", i32(p.x) + 16, i32(p.y) + 196, 15, rl.Color{150, 150, 170, 255})
			draw_build_options(g, opts[:], n, BUILD_REPLACE_START)
		}
		return
	}

	opts: [32]Improvement
	n := buildable_improvements(&g.colony, g.build_hex, opts[:])
	if n == 0 {
		draw_text("No improvements available here", i32(p.x) + 16, i32(p.y) + 100, 15, rl.Color{200, 150, 150, 255})
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

		draw_text(improvement_name(im), i32(rec.x) + 8, i32(rec.y) + 4, 15, rl.Color{225, 225, 240, 255})
		cst := fmt.ctprintf("%dg", cost)
		cw := measure_text(cst, 15)
		draw_text(cst, i32(rec.x + rec.width) - 8 - cw, i32(rec.y) + 4, 15, afford ? rl.Color{240, 205, 90, 255} : rl.Color{200, 120, 120, 255})
		draw_text(fmt.ctprintf("%d hp", improvement_hp_cap(&g.colony, im)), i32(rec.x) + 8, i32(rec.y) + 23, 11, rl.Color{150, 150, 170, 255})
		if improvement_stacks(im) {
			tag := cstring("+stack")
			tw := measure_text(tag, 11)
			draw_text(tag, i32(rec.x + rec.width) - 8 - tw, i32(rec.y) + 23, 11, rl.Color{130, 210, 235, 255})
		}
		if hover {
			tooltip_set("%s  -  %s\n%s", improvement_name(im), improvement_effect(im), improvement_detail(im))
		}
	}
	g.build_preview = hovered

	// Hovered improvement's effect, along the bottom of the panel.
	p := build_panel_rect()
	if hovered != .NONE {
		draw_text(improvement_effect(hovered), i32(p.x) + 12, i32(p.y + p.height) - 26, 12, rl.Color{175, 175, 195, 255})
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
	draw_text(label, i32(rec.x) + 12, i32(rec.y) + 14, 18, enabled ? rl.Color{235, 235, 245, 255} : rl.Color{140, 140, 150, 255})
	if cost_text != "" {
		cw := measure_text(cost_text, 16)
		draw_text(cost_text, i32(rec.x + rec.width) - 12 - cw, i32(rec.y) + 15, 16, enabled ? rl.Color{240, 205, 90, 255} : rl.Color{150, 120, 120, 255})
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
	draw_text(name, i32(rec.x) + 12, i32(rec.y) + 8, 18, enabled ? rl.Color{235, 235, 245, 255} : rl.Color{140, 140, 150, 255})
	draw_text(rarity_name(species_rarity(offer.species)), i32(rec.x) + 12, i32(rec.y) + 28, 13, enabled ? rar : rl.Color{130, 130, 140, 255})
	cost := fmt.ctprintf("%dg", offer.price)
	cw := measure_text(cost, 16)
	draw_text(cost, i32(rec.x + rec.width) - 12 - cw, i32(rec.y) + 16, 16, enabled ? rl.Color{240, 205, 90, 255} : rl.Color{150, 120, 120, 255})
}

draw_trade_panel :: proc(g: ^Game) {
	sw := f32(rl.GetScreenWidth())
	sh := f32(rl.GetScreenHeight())
	rl.DrawRectangle(0, 0, i32(sw), i32(sh), rl.Color{0, 0, 0, 160})

	p := trade_panel_rect()
	draw_panel(p, rl.Color{20, 20, 30, 245}, rl.Color{180, 160, 90, 255}, 0.05, 8, 2)
	draw_text("TRADING POST", i32(p.x) + 20, i32(p.y) + 16, 24, rl.Color{240, 210, 120, 255})
	gold := fmt.ctprintf("Gold: %d", colony_total_gold(&g.colony))
	draw_text(gold, i32(p.x) + 20, i32(p.y) + 48, 16, rl.Color{220, 200, 120, 255})

	// Monsters for sale — rerolled each turn by the Trading Post.
	draw_text("MONSTERS FOR SALE   (restocks each turn)", i32(p.x) + 20, i32(p.y) + 74, 15, rl.Color{180, 150, 150, 255})
	if len(g.colony.shop) == 0 {
		draw_text("Sold out - restocks next turn.", i32(p.x) + 20, i32(p.y) + 112, 16, rl.Color{130, 130, 145, 255})
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
	if rl.CheckCollisionPointRec(rl.GetMousePosition(), trade_heal_rect()) {
		tooltip_set("Heal the selected monster to full HP. The price scales with the HP it is missing.")
	}

	ec := have_sel ? energy_cost(&g.colony.roster[s]) : 0
	draw_trade_button(trade_energy_rect(), cstring("Refill movement energy"), have_sel && colony_total_gold(&g.colony) >= ec, have_sel ? fmt.ctprintf("%dg", ec) : "")
	if rl.CheckCollisionPointRec(rl.GetMousePosition(), trade_energy_rect()) {
		tooltip_set("Top the selected monster's movement energy back up to its bank. Energy is shared with battle.")
	}

	ccost := capture_card_cost()
	draw_trade_button(trade_capture_rect(), fmt.ctprintf("Buy Capture Card (have %d)", g.colony.capture_cards), colony_total_gold(&g.colony) >= ccost, fmt.ctprintf("%dg", ccost))
	if rl.CheckCollisionPointRec(rl.GetMousePosition(), trade_capture_rect()) {
		tooltip_set("Capture cards let you recruit a wild mid-battle instead of defeating it. Scout upgrades improve the odds.")
	}

	draw_text("FALLEN (revive)", i32(p.x) + 20, i32(p.y) + 430, 15, rl.Color{180, 150, 150, 255})
	if len(g.colony.graveyard) == 0 {
		draw_text("None", i32(p.x) + 20, i32(p.y) + 456, 15, rl.Color{130, 130, 145, 255})
	} else {
		for i in 0..<min(len(g.colony.graveyard), 2) {
			m := &g.colony.graveyard[i]
			cost := revive_cost(m)
			label := fmt.ctprintf("Revive %s  Lvl %d", m.creature.name, m.creature.level)
			draw_trade_button(trade_revive_rect(i), label, colony_total_gold(&g.colony) >= cost, fmt.ctprintf("%dg", cost))
		}
	}

	hint := cstring("T / Esc to close")
	hw := measure_text(hint, 16)
	draw_text(hint, i32(p.x) + i32(p.width / 2) - hw / 2, i32(p.y + p.height) - 30, 16, rl.Color{150, 150, 170, 255})
}

Terrain_Legend_Entry :: struct {
	terrain: Terrain,
	label:   cstring,
}

// Screen rectangle of deck card `i` in the deck viewer, honouring scroll.
deck_card_rect :: proc(g: ^Game, i: int) -> rl.Rectangle {
	sw := f32(rl.GetScreenWidth())
	total_w := f32(DV_COLS) * DV_CW + f32(DV_COLS - 1) * DV_GAP
	start_x := sw / 2 - total_w / 2
	base_y := DV_TOP - g.view_scroll
	col := i % DV_COLS
	row := i / DV_COLS
	return rl.Rectangle{start_x + f32(col) * (DV_CW + DV_GAP), base_y + f32(row) * (DV_CH + DV_GAP), DV_CW, DV_CH}
}

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
	// Right-click a card to forget it (deck thinning) for gold — with a confirm.
	if !m.wild && rl.IsMouseButtonPressed(.RIGHT) {
		mp := rl.GetMousePosition()
		for i in 0..<len(m.creature.deck) {
			if rl.CheckCollisionPointRec(mp, deck_card_rect(g, i)) {
				ask_confirm(g, .FORGET_CARD, g.view_index, i, Hex{})
				return
			}
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

draw_deck_viewer :: proc(g: ^Game) {
	sw := f32(rl.GetScreenWidth())
	sh := f32(rl.GetScreenHeight())
	rl.DrawRectangle(0, 0, i32(sw), i32(sh), rl.Color{0, 0, 0, 205})

	c := &g.colony.roster[g.view_index].creature
	element := creature_element(c)

	name := fmt.ctprintf("%s's Deck", c.name)
	draw_text(name, 40, 26, 34, rl.Color{235, 235, 245, 255})
	sub := fmt.ctprintf("Lvl %d   %s   HP %d/%d   XP %d/%d   PWR x%s   DEF %s   SPD %s   Energy %s max (%s regen)   %d cards",
		c.level, element_label(c), c.hp, c.max_hp, c.xp, xp_to_next(c.level),
		fmt_num(c.power), fmt_num(creature_defense(c)), fmt_num(c.speed),
		fmt_num(c.energy_max), fmt_num(c.energy_regen), len(c.deck))
	draw_text(sub, 40, 68, 18, element_color(element))
	if c.ability != .NONE {
		ab_line := fmt.ctprintf("Ability: %s - %s", ability_name(c.ability), ability_desc(c.ability))
		draw_text(ab_line, 40, 92, 16, rl.Color{200, 180, 240, 255})
	} else {
		draw_text("Ability: none", 40, 92, 16, rl.Color{140, 140, 160, 255})
	}
	item_line := c.item != .NONE ? fmt.ctprintf("Item: %s - %s", item_name(c.item), item_desc(c.item)) : cstring("Item: none")
	draw_text(item_line, 40, 112, 16, rl.Color{180, 240, 200, 255})
	gene_line := fmt.ctprintf("Genes: %s   (total %d)", genes_label(c.genes), genes_total(c.genes))
	draw_text(gene_line, 40, 134, 16, rl.Color{170, 210, 230, 255})
	pager := fmt.ctprintf("monster %d / %d   -   Left/Right or Q/E to switch", g.view_index + 1, len(g.colony.roster))
	draw_text(pager, 40, 154, 16, rl.Color{150, 150, 170, 255})

	// Item slot + bag.
	m := &g.colony.roster[g.view_index]
	can_gear := !m.wild
	draw_button(deck_equip_rect(), fmt.ctprintf("Equip item   (bag: %d)", len(g.colony.items)), can_gear && len(g.colony.items) > 0)
	draw_button(deck_unequip_rect(), cstring("Unequip"), can_gear && c.item != .NONE)

	n := len(c.deck)
	mp := rl.GetMousePosition()

	// Leave headroom above the grid so a hovered (lifted) top-row card is not
	// clipped by the scissor region.
	clip_top := i32(DV_TOP) - 36
	clip_bottom := i32(sh - DV_BOTTOM) + 8
	rl.BeginScissorMode(0, clip_top, i32(sw), clip_bottom - clip_top)
	for i in 0..<n {
		rec := deck_card_rect(g, i)
		if rec.y + DV_CH < f32(clip_top) - 4 || rec.y > f32(clip_bottom) + 4 {
			continue
		}
		hovered := rl.CheckCollisionPointRec(mp, rec)
		draw_card(c.deck[i], rec, true, hovered)
	}
	rl.EndScissorMode()

	hint := cstring("V / Esc close   |   wheel or Up/Down scroll   |   right-click a card to forget it (gold)")
	hw := measure_text(hint, 16)
	draw_text(hint, i32(sw) / 2 - hw / 2, i32(sh) - 32, 16, rl.Color{140, 140, 160, 255})
}

// ----------------------------------------------------------------------------
// Nursery (breeding) & monster storage panels (Phase 8/10)
// ----------------------------------------------------------------------------

NURSERY_LIST_ROWS   :: 8
NURSERY_CAND_ROWS   :: 12
STORAGE_LIST_ROWS   :: 10
STORAGE_NEAR_ROWS   :: 8
STORAGE_STORED_ROWS :: 8

// A small slot showing a stored monster (or an empty hint) with an action label.
draw_stored_slot :: proc(rec: rl.Rectangle, c: ^Colony, si: int, empty_label, action: cstring, col: rl.Color) {
	hover := rl.CheckCollisionPointRec(rl.GetMousePosition(), rec)
	if si < 0 {
		rl.DrawRectangleRounded(rec, 0.18, 4, rl.Color{24, 24, 30, 255})
		rl.DrawRectangleRoundedLinesEx(rec, 0.18, 4, 1.5, rl.Color{70, 70, 82, 255})
		draw_text(empty_label, i32(rec.x) + 10, i32(rec.y) + 7, 14, rl.Color{120, 120, 140, 255})
		return
	}
	m := &c.storage[si]
	bg := hover ? rl.Color{44, 58, 50, 255} : rl.Color{28, 36, 32, 255}
	rl.DrawRectangleRounded(rec, 0.18, 4, bg)
	rl.DrawRectangleRoundedLinesEx(rec, 0.18, 4, 1.5, col)
	draw_text(fmt.ctprintf("Lvl %d  %s", m.creature.level, m.creature.name), i32(rec.x) + 10, i32(rec.y) + 7, 15, rl.Color{225, 235, 225, 255})
	aw := measure_text(action, 13)
	draw_text(action, i32(rec.x + rec.width) - 10 - aw, i32(rec.y) + 8, 13, rl.Color{230, 200, 200, 255})
}

// ---- Nursery panel (C) ----

nursery_row_rect :: proc(row: int) -> rl.Rectangle {
	return rl.Rectangle{40, 150 + f32(row) * 30, 340, 28}
}

nursery_slot_rect :: proc(kind: Stored_In, i: int) -> rl.Rectangle {
	x := f32(410)
	y := f32(146)
	if kind == .NURSERY_BABY {
		y = 146 + f32(NURSERY_PARENTS) * 34 + 34
	}
	return rl.Rectangle{x, y + f32(i) * 34, 360, 30}
}

nursery_cand_rect :: proc(row: int) -> rl.Rectangle {
	return rl.Rectangle{800, 180 + f32(row) * 28, 440, 26}
}

update_nursery :: proc(g: ^Game) {
	if rl.IsKeyPressed(.C) || rl.IsKeyPressed(.ESCAPE) {
		g.show_nursery = false
		return
	}
	n := nursery_count(&g.colony)
	if g.nursery_sel >= n {
		g.nursery_sel = max(n - 1, 0)
	}
	max_first := max(0, n - NURSERY_LIST_ROWS)
	if rl.IsKeyPressed(.DOWN) || rl.IsKeyPressed(.S) {
		g.nursery_first = min(g.nursery_first + 1, max_first)
	}
	if rl.IsKeyPressed(.UP) || rl.IsKeyPressed(.W) {
		g.nursery_first = max(g.nursery_first - 1, 0)
	}
	if w := rl.GetMouseWheelMove(); w != 0 {
		g.nursery_first = clamp(g.nursery_first - int(w * 3), 0, max_first)
	}
	if n == 0 || !rl.IsMouseButtonPressed(.LEFT) {
		return
	}
	mp := rl.GetMousePosition()
	hex := nursery_hex_at(&g.colony, g.nursery_sel)

	for row in 0..<min(NURSERY_LIST_ROWS, n) {
		k := g.nursery_first + row
		if k >= n {
			break
		}
		if rl.CheckCollisionPointRec(mp, nursery_row_rect(row)) {
			g.nursery_sel = k
			return
		}
	}

	// Remove a parent (returns it to the map).
	for i in 0..<NURSERY_PARENTS {
		if rl.CheckCollisionPointRec(mp, nursery_slot_rect(.NURSERY_PARENT, i)) {
			if si := stored_slot_index(&g.colony, hex, .NURSERY_PARENT, i); si >= 0 {
				res := colony_deploy_stored(&g.colony, si)
				set_status(g, res == 0 ? "Parent returned to the map." : "No room beside the Nursery.")
			}
			return
		}
	}
	// Take a baby.
	for i in 0..<NURSERY_BABIES {
		if rl.CheckCollisionPointRec(mp, nursery_slot_rect(.NURSERY_BABY, i)) {
			if si := stored_slot_index(&g.colony, hex, .NURSERY_BABY, i); si >= 0 {
				res := colony_deploy_stored(&g.colony, si)
				set_status(g, res == 0 ? "Baby taken out." : "No room beside the Nursery.")
			}
			return
		}
	}

	// Assign a nearby map monster as a parent.
	for row in 0..<NURSERY_CAND_ROWS {
		if !rl.CheckCollisionPointRec(mp, nursery_cand_rect(row)) {
			continue
		}
		idx := nearby_map_monster_at(&g.colony, hex, row)
		if idx < 0 {
			break
		}
		if nursery_accepts(&g.colony, idx, hex) {
			res := colony_assign_parent(&g.colony, idx, hex)
			set_status(g, res == 0 ? "Monster moved into the Nursery." : "Can't add that monster.")
		} else {
			set_status(g, "Needs a nearby monster: Lvl 5+, same species as the other parent.")
		}
		return
	}
}

draw_nursery :: proc(g: ^Game) {
	sw := f32(rl.GetScreenWidth())
	sh := f32(rl.GetScreenHeight())
	rl.DrawRectangle(0, 0, i32(sw), i32(sh), rl.Color{0, 0, 0, 205})

	draw_text(cstring("Nurseries"), 40, 26, 34, rl.Color{235, 235, 245, 255})
	sub := cstring("Move two nearby monsters of the same species (Lvl 5+) in as the breeding pair. A fed Nursery hatches a level 1 baby every 8 turns, up to 4 stored.")
	draw_text(sub, 40, 68, 16, rl.Color{180, 190, 210, 255})

	n := nursery_count(&g.colony)
	draw_text(fmt.ctprintf("Your Nurseries (%d):", n), 40, 118, 16, rl.Color{150, 150, 170, 255})

	mp := rl.GetMousePosition()
	for row in 0..<min(NURSERY_LIST_ROWS, n) {
		k := g.nursery_first + row
		if k >= n {
			break
		}
		hex := nursery_hex_at(&g.colony, k)
		rec := nursery_row_rect(row)
		sel := k == g.nursery_sel
		hover := rl.CheckCollisionPointRec(mp, rec)
		draw_row(rec, sel, hover, rl.Color{140, 220, 160, 255})
		p := nursery_parent_count(&g.colony, hex)
		b := nursery_baby_count(&g.colony, hex)
		prog := 0
		if t := tile_at(&g.colony, hex); t != nil {
			prog = t.stored
		}
		draw_text(fmt.ctprintf("Nursery (%d,%d)  pair %d/%d  babies %d/%d  %d/%d", hex.q, hex.r, p, NURSERY_PARENTS, b, NURSERY_BABIES, prog, NURSERY_PERIOD), i32(rec.x) + 10, i32(rec.y) + 6, 15, rl.Color{225, 230, 240, 255})
	}

	if n == 0 {
		draw_text(cstring("No Nurseries yet - build one with B (Cave/Grove/Mushroom/Jungle)."), 40, 154, 16, rl.Color{210, 180, 180, 255})
		hint := cstring("C / Esc close")
		hw := measure_text(hint, 16)
		draw_text(hint, i32(sw) / 2 - hw / 2, i32(sh) - 28, 16, rl.Color{140, 140, 160, 255})
		return
	}

	hex := nursery_hex_at(&g.colony, g.nursery_sel)

	draw_text(cstring("Breeding pair (click to remove):"), 410, 118, 16, rl.Color{190, 220, 200, 255})
	for i in 0..<NURSERY_PARENTS {
		si := stored_slot_index(&g.colony, hex, .NURSERY_PARENT, i)
		draw_stored_slot(nursery_slot_rect(.NURSERY_PARENT, i), &g.colony, si, cstring("Empty - add a nearby monster"), cstring("Remove"), rl.Color{140, 220, 160, 255})
	}
	draw_text(cstring("Babies (click to take):"), 410, 258, 16, rl.Color{210, 200, 160, 255})
	for i in 0..<NURSERY_BABIES {
		si := stored_slot_index(&g.colony, hex, .NURSERY_BABY, i)
		draw_stored_slot(nursery_slot_rect(.NURSERY_BABY, i), &g.colony, si, cstring("Empty"), cstring("Take"), rl.Color{230, 210, 150, 255})
	}

	draw_text(cstring("Add a parent - nearby monsters (within 1, Lvl 5+, same species):"), 800, 140, 16, rl.Color{180, 190, 210, 255})
	cand := 0
	for row in 0..<NURSERY_CAND_ROWS {
		idx := nearby_map_monster_at(&g.colony, hex, row)
		if idx < 0 {
			break
		}
		m := &g.colony.roster[idx]
		rec := nursery_cand_rect(cand)
		ok := nursery_accepts(&g.colony, idx, hex)
		hover := rl.CheckCollisionPointRec(mp, rec)
		bg := ok ? (hover ? rl.Color{44, 64, 50, 255} : rl.Color{28, 40, 34, 255}) : (hover ? rl.Color{34, 30, 34, 255} : rl.Color{24, 24, 28, 255})
		rl.DrawRectangleRounded(rec, 0.2, 4, bg)
		rl.DrawRectangleRoundedLinesEx(rec, 0.2, 4, 1.5, ok ? rl.Color{110, 180, 130, 255} : rl.Color{70, 66, 70, 255})
		draw_text(fmt.ctprintf("Lvl %d  %s", m.creature.level, m.creature.name), i32(rec.x) + 10, i32(rec.y) + 5, 15, ok ? rl.Color{225, 235, 225, 255} : rl.Color{150, 145, 150, 255})
		gl := genes_label(m.creature.genes)
		gw := measure_text(gl, 13)
		draw_text(gl, i32(rec.x + rec.width) - 10 - gw, i32(rec.y) + 6, 13, rl.Color{170, 200, 220, 255})
		cand += 1
	}
	if cand == 0 {
		draw_text(cstring("No monsters next to this Nursery."), 800, 184, 15, rl.Color{150, 150, 170, 255})
	}

	hint := cstring("Click a Nursery, then a nearby monster to add it   |   C / Esc close")
	hw := measure_text(hint, 16)
	draw_text(hint, i32(sw) / 2 - hw / 2, i32(sh) - 28, 16, rl.Color{140, 140, 160, 255})
}

// ---- Monster storage panel (H) ----

storage_den_rect :: proc(row: int) -> rl.Rectangle {
	return rl.Rectangle{40, 150 + f32(row) * 30, 340, 28}
}

storage_near_rect :: proc(row: int) -> rl.Rectangle {
	return rl.Rectangle{410, 180 + f32(row) * 30, 380, 28}
}

storage_hold_rect :: proc(row: int) -> rl.Rectangle {
	return rl.Rectangle{820, 180 + f32(row) * 30, 420, 28}
}

update_storage :: proc(g: ^Game) {
	if rl.IsKeyPressed(.H) || rl.IsKeyPressed(.ESCAPE) {
		g.show_storage = false
		return
	}
	n := den_count(&g.colony)
	if g.storage_sel >= n {
		g.storage_sel = max(n - 1, 0)
	}
	max_first := max(0, n - STORAGE_LIST_ROWS)
	if rl.IsKeyPressed(.DOWN) || rl.IsKeyPressed(.S) {
		g.storage_first = min(g.storage_first + 1, max_first)
	}
	if rl.IsKeyPressed(.UP) || rl.IsKeyPressed(.W) {
		g.storage_first = max(g.storage_first - 1, 0)
	}
	if w := rl.GetMouseWheelMove(); w != 0 {
		g.storage_first = clamp(g.storage_first - int(w * 3), 0, max_first)
	}
	if n == 0 || !rl.IsMouseButtonPressed(.LEFT) {
		return
	}
	mp := rl.GetMousePosition()
	hex := den_hex_at(&g.colony, g.storage_sel)

	for row in 0..<min(STORAGE_LIST_ROWS, n) {
		k := g.storage_first + row
		if k >= n {
			break
		}
		if rl.CheckCollisionPointRec(mp, storage_den_rect(row)) {
			g.storage_sel = k
			return
		}
	}

	for row in 0..<STORAGE_NEAR_ROWS {
		if !rl.CheckCollisionPointRec(mp, storage_near_rect(row)) {
			continue
		}
		idx := nearby_map_monster_at(&g.colony, hex, row)
		if idx < 0 {
			break
		}
		switch colony_store_monster(&g.colony, idx, hex) {
		case 0:
			set_status(g, "Monster put into stasis.")
		case 2:
			set_status(g, "That Den is full.")
		case 3:
			set_status(g, "Move the monster next to the Den first.")
		case:
			set_status(g, "Can't store that.")
		}
		return
	}

	for row in 0..<STORAGE_STORED_ROWS {
		if !rl.CheckCollisionPointRec(mp, storage_hold_rect(row)) {
			continue
		}
		si := stored_slot_index(&g.colony, hex, .DEN, row)
		if si < 0 {
			break
		}
		res := colony_deploy_stored(&g.colony, si)
		set_status(g, res == 0 ? "Monster deployed." : "No room beside the Den.")
		return
	}
}

draw_storage :: proc(g: ^Game) {
	sw := f32(rl.GetScreenWidth())
	sh := f32(rl.GetScreenHeight())
	rl.DrawRectangle(0, 0, i32(sw), i32(sh), rl.Color{0, 0, 0, 205})

	draw_text(cstring("Monster Storage"), 40, 26, 34, rl.Color{235, 235, 245, 255})
	sub := cstring("Walk a monster next to a Den, then click it here to put it in stasis: no food upkeep, no heat, off the map. Up to 32 per Den.")
	draw_text(sub, 40, 68, 16, rl.Color{180, 190, 210, 255})

	n := den_count(&g.colony)
	draw_text(fmt.ctprintf("Your Dens (%d):", n), 40, 118, 16, rl.Color{150, 150, 170, 255})

	mp := rl.GetMousePosition()
	for row in 0..<min(STORAGE_LIST_ROWS, n) {
		k := g.storage_first + row
		if k >= n {
			break
		}
		hex := den_hex_at(&g.colony, k)
		rec := storage_den_rect(row)
		sel := k == g.storage_sel
		hover := rl.CheckCollisionPointRec(mp, rec)
		draw_row(rec, sel, hover, rl.Color{140, 220, 160, 255})
		draw_text(fmt.ctprintf("Den (%d,%d)   %d/%d", hex.q, hex.r, den_occupancy(&g.colony, hex), den_capacity(&g.colony)), i32(rec.x) + 10, i32(rec.y) + 6, 15, rl.Color{225, 230, 240, 255})
	}

	if n == 0 {
		draw_text(cstring("No Dens yet - build one with B (Cave/Grove/Ruins/Mushroom/Desert)."), 40, 154, 16, rl.Color{210, 180, 180, 255})
		hint := cstring("H / Esc close")
		hw := measure_text(hint, 16)
		draw_text(hint, i32(sw) / 2 - hw / 2, i32(sh) - 28, 16, rl.Color{140, 140, 160, 255})
		return
	}

	hex := den_hex_at(&g.colony, g.storage_sel)

	draw_text(cstring("Nearby (within 1) - click to store:"), 410, 150, 16, rl.Color{190, 220, 200, 255})
	near := 0
	for i in 0..<len(g.colony.roster) {
		m := &g.colony.roster[i]
		if m.wild || hex_distance(m.pos, hex) > STORE_RANGE {
			continue
		}
		if near >= STORAGE_NEAR_ROWS {
			break
		}
		rec := storage_near_rect(near)
		hover := rl.CheckCollisionPointRec(mp, rec)
		rl.DrawRectangleRounded(rec, 0.18, 4, hover ? rl.Color{44, 64, 50, 255} : rl.Color{28, 40, 34, 255})
		rl.DrawRectangleRoundedLinesEx(rec, 0.18, 4, 1.5, rl.Color{110, 180, 130, 255})
		draw_text(fmt.ctprintf("Lvl %d  %s", m.creature.level, m.creature.name), i32(rec.x) + 10, i32(rec.y) + 5, 15, rl.Color{225, 235, 225, 255})
		near += 1
	}
	if near == 0 {
		draw_text(cstring("No monsters next to this Den."), 410, 184, 15, rl.Color{150, 150, 170, 255})
	}

	draw_text(fmt.ctprintf("In stasis (%d/%d) - click to deploy:", den_occupancy(&g.colony, hex), den_capacity(&g.colony)), 820, 150, 16, rl.Color{210, 200, 160, 255})
	hold := 0
	for i in 0..<len(g.colony.storage) {
		m := &g.colony.storage[i]
		if m.stored != .DEN || !hex_equal(m.stored_hex, hex) {
			continue
		}
		if hold >= STORAGE_STORED_ROWS {
			break
		}
		rec := storage_hold_rect(hold)
		hover := rl.CheckCollisionPointRec(mp, rec)
		rl.DrawRectangleRounded(rec, 0.18, 4, hover ? rl.Color{48, 52, 64, 255} : rl.Color{28, 30, 38, 255})
		rl.DrawRectangleRoundedLinesEx(rec, 0.18, 4, 1.5, rl.Color{120, 140, 180, 255})
		draw_text(fmt.ctprintf("Lvl %d  %s", m.creature.level, m.creature.name), i32(rec.x) + 10, i32(rec.y) + 5, 15, rl.Color{220, 225, 235, 255})
		hold += 1
	}
	if hold == 0 {
		draw_text(cstring("Nothing stored here."), 820, 184, 15, rl.Color{150, 150, 170, 255})
	}

	hint := cstring("Click a Den, then a nearby monster to store it, or a stored one to deploy   |   H / Esc close")
	hw := measure_text(hint, 16)
	draw_text(hint, i32(sw) / 2 - hw / 2, i32(sh) - 28, 16, rl.Color{140, 140, 160, 255})
}

// ----------------------------------------------------------------------------
// Save / load panel (O)
// ----------------------------------------------------------------------------

SAVE_ROW_H :: f32(100)

save_slot_rect :: proc(slot: int) -> rl.Rectangle {
	return rl.Rectangle{120, 170 + f32(slot) * SAVE_ROW_H, 1040, SAVE_ROW_H - 16}
}

save_slot_save_rect :: proc(slot: int) -> rl.Rectangle {
	rec := save_slot_rect(slot)
	return rl.Rectangle{rec.x + rec.width - 260, rec.y + 18, 110, 44}
}

save_slot_load_rect :: proc(slot: int) -> rl.Rectangle {
	rec := save_slot_rect(slot)
	return rl.Rectangle{rec.x + rec.width - 140, rec.y + 18, 110, 44}
}

// A wide "New Run" button below the slots: back to the starter picker for a
// fresh run (and a fresh seed).
save_new_run_rect :: proc() -> rl.Rectangle {
	sw := f32(rl.GetScreenWidth())
	return rl.Rectangle{sw / 2 - 170, 170 + f32(SAVE_SLOTS + 1) * SAVE_ROW_H + 8, 340, 52}
}

// Start a new run from the save panel: back to the starter picker for a fresh
// seed. If a run is in progress, the first press/click arms a confirm so an
// accidental one can't wipe it.
try_new_run :: proc(g: ^Game) {
	if !g.has_colony || g.new_run_armed > 0 {
		reset_to_starter(g)
	} else {
		g.new_run_armed = 3.0
	}
}

update_save_panel :: proc(g: ^Game) {
	if rl.IsKeyPressed(.O) || rl.IsKeyPressed(.ESCAPE) {
		g.show_save = false
		return
	}
	// Quick key: N starts a new run (same as the button).
	if rl.IsKeyPressed(.N) {
		try_new_run(g)
		return
	}
	if !rl.IsMouseButtonPressed(.LEFT) {
		return
	}
	mp := rl.GetMousePosition()

	if rl.CheckCollisionPointRec(mp, save_new_run_rect()) {
		try_new_run(g)
		return
	}

	if !save_supported() {
		return
	}
	for slot in 0 ..< SAVE_SLOTS {
		if rl.CheckCollisionPointRec(mp, save_slot_save_rect(slot)) {
			set_status(g, save_game(g, slot) ? "Game saved." : "Could not save.")
			return
		}
		if rl.CheckCollisionPointRec(mp, save_slot_load_rect(slot)) {
			if !save_read_meta(slot).exists {
				set_status(g, "That slot is empty.")
				return
			}
			if load_game(g, slot) {
				g.show_save = false
				set_status(g, "Game loaded.")
			} else {
				set_status(g, "Could not load that save.")
			}
			return
		}
	}
	// Autosave: load only.
	if rl.CheckCollisionPointRec(mp, save_slot_load_rect(AUTOSAVE_SLOT)) {
		if !save_read_meta(AUTOSAVE_SLOT).exists {
			set_status(g, "No autosave yet.")
			return
		}
		if load_game(g, AUTOSAVE_SLOT) {
			g.show_save = false
			set_status(g, "Autosave loaded.")
		} else {
			set_status(g, "Could not load the autosave.")
		}
		return
	}
}

draw_new_run_button :: proc(g: ^Game) {
	rec := save_new_run_rect()
	mp := rl.GetMousePosition()
	armed := g.new_run_armed > 0
	hover := rl.CheckCollisionPointRec(mp, rec)
	bg := armed ? rl.Color{96, 44, 40, 255} : (hover ? rl.Color{52, 62, 84, 255} : rl.Color{28, 32, 44, 255})
	border := armed ? rl.Color{235, 130, 110, 255} : (hover ? rl.Color{150, 180, 235, 255} : rl.Color{84, 94, 120, 255})
	rl.DrawRectangleRounded(rec, 0.2, 8, bg)
	rl.DrawRectangleRoundedLinesEx(rec, 0.2, 8, 2, border)
	label := armed ? cstring("Confirm?  click or press N") : cstring("New Run  (N)")
	w := measure_text(label, 22)
	draw_text(label, i32(rec.x + rec.width / 2) - w / 2, i32(rec.y + rec.height / 2) - 12, 22, armed ? rl.Color{255, 210, 200, 255} : rl.Color{210, 220, 240, 255})
}

draw_save_panel :: proc(g: ^Game) {
	sw := f32(rl.GetScreenWidth())
	sh := f32(rl.GetScreenHeight())
	rl.DrawRectangle(0, 0, i32(sw), i32(sh), rl.Color{0, 0, 0, 210})

	draw_text(cstring("Save / Load"), 120, 40, 34, rl.Color{235, 235, 245, 255})
	if g.mode == .MAP {
		draw_text(cstring("F quick-saves slot 1   |   N: new run   |   O / Esc to close"), 120, 86, 16, rl.Color{160, 170, 190, 255})
	} else {
		draw_text(cstring("Choose a slot to load   |   N: new run   |   Esc to go back"), 120, 86, 16, rl.Color{160, 170, 190, 255})
	}

	draw_new_run_button(g)

	if !save_supported() {
		draw_text(cstring("Saving is not available in the browser build."), 120, 180, 18, rl.Color{220, 170, 170, 255})
		return
	}

	mp := rl.GetMousePosition()
	for slot in 0 ..< SAVE_SLOTS {
		rec := save_slot_rect(slot)
		meta := save_read_meta(slot)
		hover := rl.CheckCollisionPointRec(mp, rec)
		bg := hover ? rl.Color{30, 34, 44, 255} : rl.Color{22, 24, 32, 255}
		rl.DrawRectangleRounded(rec, 0.06, 6, bg)
		rl.DrawRectangleRoundedLinesEx(rec, 0.06, 6, 2, rl.Color{70, 78, 96, 255})

		draw_text(fmt.ctprintf("Slot %d", slot + 1), i32(rec.x) + 20, i32(rec.y) + 12, 22, rl.Color{220, 226, 240, 255})

		if meta.exists {
			buf: [32]u8
			age := save_age_label(meta.saved_at, buf[:])
			info := fmt.ctprintf("Turn %d   Gold %d   Monsters %d   Crystals %d", meta.turn, meta.gold, meta.monsters, meta.crystals)
			draw_text(info, i32(rec.x) + 20, i32(rec.y) + 46, 16, rl.Color{180, 195, 215, 255})
			draw_text(fmt.ctprintf("%s", age), i32(rec.x) + 20, i32(rec.y) + 68, 14, rl.Color{140, 150, 170, 255})
		} else {
			draw_text(cstring("Empty"), i32(rec.x) + 20, i32(rec.y) + 46, 16, rl.Color{130, 130, 150, 255})
		}

		draw_button(save_slot_save_rect(slot), cstring("Save"), g.has_colony && g.mode == .MAP)
		draw_button(save_slot_load_rect(slot), cstring("Load"), meta.exists)
	}

	// Autosave: a special, load-only slot the game writes on its own.
	{
		rec := save_slot_rect(AUTOSAVE_SLOT)
		meta := save_read_meta(AUTOSAVE_SLOT)
		rl.DrawRectangleRounded(rec, 0.06, 6, rl.Color{22, 26, 34, 255})
		rl.DrawRectangleRoundedLinesEx(rec, 0.06, 6, 2, rl.Color{96, 130, 102, 255})
		draw_text(cstring("Autosave"), i32(rec.x) + 20, i32(rec.y) + 12, 22, rl.Color{205, 240, 210, 255})
		draw_text(fmt.ctprintf("auto-written every %d turns", AUTOSAVE_EVERY), i32(rec.x) + 170, i32(rec.y) + 18, 14, rl.Color{140, 165, 150, 255})
		if meta.exists {
			buf: [32]u8
			age := save_age_label(meta.saved_at, buf[:])
			info := fmt.ctprintf("Turn %d   Gold %d   Monsters %d   Crystals %d", meta.turn, meta.gold, meta.monsters, meta.crystals)
			draw_text(info, i32(rec.x) + 20, i32(rec.y) + 46, 16, rl.Color{180, 205, 190, 255})
			draw_text(fmt.ctprintf("%s", age), i32(rec.x) + 20, i32(rec.y) + 68, 14, rl.Color{140, 150, 170, 255})
		} else {
			draw_text(cstring("Empty"), i32(rec.x) + 20, i32(rec.y) + 46, 16, rl.Color{130, 130, 150, 255})
		}
		draw_button(save_slot_load_rect(AUTOSAVE_SLOT), cstring("Load"), meta.exists)
	}
}

// ----------------------------------------------------------------------------
// Monster encyclopedia
// ----------------------------------------------------------------------------

ENCY_ROWS :: 21

ENCYCLOPEDIA_LIST :: List_View{rows = ENCY_ROWS, row_h = 26, x = 40, y = 120, w = 300}

update_encyclopedia :: proc(g: ^Game) {
	if rl.IsKeyPressed(.ESCAPE) || rl.IsKeyPressed(.M) {
		g.show_encyclopedia = false
		return
	}
	v := ENCYCLOPEDIA_LIST
	v.index = g.encyclopedia_index
	v.first = g.encyclopedia_first
	list_navigate(&v, len(SPECIES))
	g.encyclopedia_index = v.index
	g.encyclopedia_first = v.first
}

draw_encyclopedia :: proc(g: ^Game) {
	sh := f32(rl.GetScreenHeight())
	draw_list_screen_header("MONSTER ENCYCLOPEDIA", "Up/Down, wheel or click to browse   |   M / Esc to close")

	n := len(SPECIES)

	// Left: the list.
	v := ENCYCLOPEDIA_LIST
	v.index = g.encyclopedia_index
	v.first = g.encyclopedia_first
	panel := rl.Rectangle{30, 108, 320, f32(ENCY_ROWS) * 26 + 12}
	draw_list_chrome(v, n, panel)
	mp := rl.GetMousePosition()
	for row in 0..<v.rows {
		i := v.first + row
		if i >= n {
			break
		}
		rec := list_row_rect(v, row)
		sel := i == v.index
		draw_list_row_bg(rec, sel, rl.CheckCollisionPointRec(mp, rec))
		sp := SPECIES[Species_Id(i)]
		rl.DrawCircleV(rl.Vector2{rec.x + 14, rec.y + 12}, 8, sp.color)
		draw_text(fmt.ctprintf("%s", sp.name), i32(rec.x) + 30, i32(rec.y) + 4, 16, sel ? rl.Color{235, 245, 235, 255} : rl.Color{200, 200, 215, 255})
		label := elements_label(sp.elements)
		ew := measure_text(label, 13)
		draw_text(label, i32(rec.x + rec.width) - 12 - ew, i32(rec.y) + 6, 13, element_color(sp.elements[0]))
	}

	if g.encyclopedia_index < 0 || g.encyclopedia_index >= n {
		return
	}
	sp := SPECIES[Species_Id(g.encyclopedia_index)]
	dx := f32(390)
	dy := f32(120)

	rl.DrawCircleV(rl.Vector2{dx + 40, dy + 40}, 38, sp.color)
	rl.DrawCircleLinesV(rl.Vector2{dx + 40, dy + 40}, 38, rl.Color{235, 235, 245, 255})
	initial := fmt.ctprintf("%c", sp.name[0])
	iw := measure_text(initial, 36)
	draw_text(initial, i32(dx + 40) - iw / 2, i32(dy + 40) - 18, 36, rl.Color{255, 255, 255, 255})

	draw_text(fmt.ctprintf("%s", sp.name), i32(dx + 96), i32(dy) + 6, 30, rl.Color{235, 235, 245, 255})
	type_label := elements_label(sp.elements)
	draw_text(type_label, i32(dx + 96), i32(dy) + 44, 20, element_color(sp.elements[0]))
	draw_text(fmt.ctprintf("Role: %s", role_name(sp.role)), i32(dx + 96), i32(dy) + 70, 16, rl.Color{170, 170, 190, 255})
	draw_text(rarity_name(sp.rarity), i32(dx + 210), i32(dy) + 70, 16, rarity_color(sp.rarity))

	// Stats (drawn one at a time; ctprintf shares one buffer).
	sx := i32(dx)
	sy := i32(dy) + 112
	step := i32(26)
	draw_text(fmt.ctprintf("HP %d", sp.base_hp), sx, sy, 18, rl.Color{205, 205, 220, 255})
	draw_text(fmt.ctprintf("PWR x%s", fmt_num(sp.base_power)), sx, sy + step, 18, rl.Color{205, 205, 220, 255})
	draw_text(fmt.ctprintf("DEF %s", fmt_num(sp.base_defense)), sx, sy + step * 2, 18, rl.Color{205, 205, 220, 255})
	draw_text(fmt.ctprintf("SPD %s", fmt_num(sp.base_speed)), sx, sy + step * 3, 18, rl.Color{205, 205, 220, 255})
	draw_text(fmt.ctprintf("Energy %d regen / %d max", sp.base_energy, sp.base_energy_max), sx, sy + step * 4, 18, rl.Color{205, 205, 220, 255})
	draw_text(fmt.ctprintf("Satiety %d   Upkeep %d", sp.base_satiety, sp.base_upkeep), sx, sy + step * 5, 18, rl.Color{205, 205, 220, 255})

	// Starter deck (unique moves with counts).
	cy := i32(dy) + 296
	draw_text("STARTS WITH", sx, cy, 16, rl.Color{150, 150, 170, 255})
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
		draw_text(fmt.ctprintf("%s x%d", MOVE_DATA[m].name, counts[m]), sx, cy, 15, element_color(MOVE_DATA[m].element))
		cy += 20
	}

	// Learnset by level.
	lx := i32(760)
	ly := i32(dy) + 112
	draw_text("LEARNSET", lx, ly - 28, 16, rl.Color{150, 150, 170, 255})
	for e in sp.learnset {
		draw_text(fmt.ctprintf("Lvl %d   %s", e.level, MOVE_DATA[e.move].name), lx, ly, 15, element_color(MOVE_DATA[e.move].element))
		ly += 20
	}

	// Ability pool: a creature rolls one of these at spawn.
	ly += 12
	draw_text("ABILITIES  (one rolled at spawn)", lx, ly, 16, rl.Color{150, 150, 170, 255})
	ly += 24
	for a in species_abilities(Species_Id(g.encyclopedia_index)) {
		draw_text(fmt.ctprintf("%s - %s", ability_name(a), ability_desc(a)), lx, ly, 15, rl.Color{200, 180, 240, 255})
		ly += 20
	}

	draw_text(fmt.ctprintf("%d species in the underground", n), 40, i32(sh) - 32, 16, rl.Color{130, 130, 150, 255})
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
		if blen > 0 && measure_text(cstring(&cand[0]), size) > max_w {
			buf[blen] = 0
			draw_text(cstring(&buf[0]), x, cy, size, col)
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
		draw_text(cstring(&buf[0]), x, cy, size, col)
		cy += size + 6
	}
	return cy
}

IMPROV_ROWS :: 23

ALL_TERRAINS := [?]Terrain{.CAVE, .WATER, .DUNGEON, .GROVE, .MUSHROOM, .RUINS, .TUNDRA, .JUNGLE, .LAVA, .DESERT, .QUICKSAND, .TRADING_POST, .BOSS_ROOM}

IMPROVEMENTS_LIST :: List_View{rows = IMPROV_ROWS, row_h = 24, x = 40, y = 120, w = 300}

update_improvements :: proc(g: ^Game) {
	if rl.IsKeyPressed(.ESCAPE) || rl.IsKeyPressed(.I) {
		g.show_improvements = false
		return
	}
	v := IMPROVEMENTS_LIST
	v.index = g.improvement_index
	v.first = g.improvement_first
	list_navigate(&v, len(ALL_IMPROVEMENTS))
	g.improvement_index = v.index
	g.improvement_first = v.first
}

draw_improvements :: proc(g: ^Game) {
	sw := f32(rl.GetScreenWidth())
	sh := f32(rl.GetScreenHeight())
	draw_list_screen_header("IMPROVEMENTS", "Up/Down, wheel or click to browse   |   I / Esc to close")

	n := len(ALL_IMPROVEMENTS)

	// Left: the list.
	v := IMPROVEMENTS_LIST
	v.index = g.improvement_index
	v.first = g.improvement_first
	panel := rl.Rectangle{30, 108, 320, f32(IMPROV_ROWS) * 24 + 12}
	draw_list_chrome(v, n, panel)
	mp := rl.GetMousePosition()
	for row in 0 ..< v.rows {
		i := v.first + row
		if i >= n {
			break
		}
		im := ALL_IMPROVEMENTS[i]
		rec := list_row_rect(v, row)
		sel := i == v.index
		draw_list_row_bg(rec, sel, rl.CheckCollisionPointRec(mp, rec))
		draw_text(fmt.ctprintf("%s", improvement_name(im)), i32(rec.x) + 12, i32(rec.y) + 3, 16, sel ? rl.Color{235, 245, 235, 255} : rl.Color{200, 200, 215, 255})
		cat := improvement_category(im)
		cw := measure_text(cat, 13)
		draw_text(cat, i32(rec.x + rec.width) - 10 - cw, i32(rec.y) + 5, 13, rl.Color{150, 160, 180, 255})
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
	draw_text(fmt.ctprintf("%s", improvement_name(im)), i32(dx + 148), i32(dy) + 6, 30, rl.Color{235, 235, 245, 255})
	head := fmt.ctprintf("%s   |   Cost %dg   |   HP %d", improvement_category(im), improvement_cost(im), improvement_hp_cap(&g.colony, im))
	draw_text(head, i32(dx + 148), i32(dy) + 44, 18, rl.Color{210, 200, 160, 255})
	if improvement_stacks(im) {
		draw_text("STACKABLE (overlay slot)", i32(dx + 148), i32(dy) + 68, 15, rl.Color{150, 220, 170, 255})
	}

	// Built-on terrain chips.
	draw_text("BUILT ON", i32(dx), i32(dy) + 140, 15, rl.Color{150, 150, 170, 255})
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
		w := measure_text(label, 14) + 18
		if cx + w > right {
			cx = i32(dx)
			cy += 28
		}
		rec := rl.Rectangle{f32(cx), f32(cy), f32(w), 23}
		rl.DrawRectangleRounded(rec, 0.4, 4, rl.Color{26, 28, 36, 255})
		rl.DrawRectangleRoundedLinesEx(rec, 0.4, 4, 1, terrain_color(t))
		draw_text(label, cx + 9, cy + 3, 14, terrain_color(t))
		cx += w + 6
	}
	if !any {
		draw_text("any land tile", i32(dx), cy + 3, 15, rl.Color{140, 140, 155, 255})
	}
	cy += 28

	// Effect (short) + detail (long, wrapped).
	ey := cy + 20
	draw_text("EFFECT", i32(dx), ey, 15, rl.Color{150, 150, 170, 255})
	ey = draw_text_wrapped(improvement_effect(im), i32(dx), ey + 24, 17, right - i32(dx), rl.Color{210, 210, 225, 255})
	ey += 14
	draw_text("DETAIL", i32(dx), ey, 15, rl.Color{150, 150, 170, 255})
	draw_text_wrapped(improvement_detail(im), i32(dx), ey + 24, 16, right - i32(dx), rl.Color{180, 180, 198, 255})

	draw_text(fmt.ctprintf("%d improvements", n), 40, i32(sh) - 32, 16, rl.Color{130, 130, 150, 255})
}

// ----------------------------------------------------------------------------
// Item bag viewer
// ----------------------------------------------------------------------------

BAG_ROWS :: 20

BAG_LIST :: List_View{rows = BAG_ROWS, row_h = 24, x = 40, y = 120, w = 320}

bag_equip_rect :: proc() -> rl.Rectangle {
	sh := f32(rl.GetScreenHeight())
	return rl.Rectangle{390, sh - 96, 320, 46}
}

// Draw one line per active effect field. Returns the next y.
draw_item_effects :: proc(it: Item, x, y: i32, size: i32) -> i32 {
	info := ITEM_DATA[it]
	yy := y
	step := size + 6
	if info.strength != 0 { draw_text(fmt.ctprintf("Battle start:   +%d Strength", info.strength), x, yy, size, rl.Color{240, 170, 120, 255}); yy += step }
	if info.defense != 0 { draw_text(fmt.ctprintf("Battle start:   +%s Defense", fmt_num(info.defense)), x, yy, size, rl.Color{120, 220, 190, 255}); yy += step }
	if info.speed != 0 { draw_text(fmt.ctprintf("Battle start:   +%s Speed", fmt_num(info.speed)), x, yy, size, rl.Color{140, 190, 250, 255}); yy += step }
	if info.block != 0 { draw_text(fmt.ctprintf("Battle start:   +%d Block", info.block), x, yy, size, rl.Color{130, 180, 245, 255}); yy += step }
	if info.draw != 0 { draw_text(fmt.ctprintf("Each turn:   draw +%d card", info.draw), x, yy, size, rl.Color{140, 190, 250, 255}); yy += step }
	if info.on_hit_leech_pct != 0 { draw_text(fmt.ctprintf("On dealing damage:   drain %d%%", int(info.on_hit_leech_pct * 100)), x, yy, size, rl.Color{140, 230, 150, 255}); yy += step }
	if info.energy_regen != 0 { draw_text(fmt.ctprintf("Each turn:   +%s energy regen", fmt_num(info.energy_regen)), x, yy, size, rl.Color{240, 210, 110, 255}); yy += step }
	if info.energy_max != 0 { draw_text(fmt.ctprintf("Energy bank:   +%s", fmt_num(info.energy_max)), x, yy, size, rl.Color{240, 210, 110, 255}); yy += step }
	if info.hp_pct != 0 { draw_text(fmt.ctprintf("Max HP:   +%d%%", int(info.hp_pct * 100)), x, yy, size, rl.Color{140, 230, 150, 255}); yy += step }
	if info.power != 0 { draw_text(fmt.ctprintf("Power:   +%s", fmt_num(info.power)), x, yy, size, rl.Color{240, 170, 120, 255}); yy += step }
	if info.gold_per_turn != 0 { draw_text(fmt.ctprintf("Each turn:   +%d gold", info.gold_per_turn), x, yy, size, rl.Color{240, 205, 90, 255}); yy += step }
	if info.capture_pct != 0 { draw_text(fmt.ctprintf("Capture chance:   +%d%%", int(info.capture_pct * 100)), x, yy, size, rl.Color{180, 220, 255, 255}); yy += step }
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
	if rl.IsKeyPressed(.ESCAPE) || rl.IsKeyPressed(.G) {
		g.show_bag = false
		return
	}
	n := len(g.colony.items)
	v := BAG_LIST
	v.index = g.bag_index
	v.first = g.bag_first
	list_navigate(&v, n)
	g.bag_index = v.index
	g.bag_first = v.first

	// Equip the selected item onto the map-selected monster (bag-specific).
	if n > 0 && rl.IsMouseButtonPressed(.LEFT) && rl.CheckCollisionPointRec(rl.GetMousePosition(), bag_equip_rect()) {
		if equip_bag_item(g, g.bag_index) {
			set_status(g, "Item equipped.")
			g.bag_index = clamp(g.bag_index, 0, max(len(g.colony.items) - 1, 0))
		} else {
			set_status(g, "Select one of your monsters on the map first.")
		}
	}
}

draw_bag :: proc(g: ^Game) {
	sh := f32(rl.GetScreenHeight())
	draw_list_screen_header(fmt.ctprintf("ITEM BAG   (%d / %d)", len(g.colony.items), colony_item_cap(&g.colony)), "Up/Down, wheel or click to browse   |   G / Esc to close")

	n := len(g.colony.items)

	// Left: the list.
	v := BAG_LIST
	v.index = g.bag_index
	v.first = g.bag_first
	panel := rl.Rectangle{30, 108, 320, f32(BAG_ROWS) * 24 + 12}
	draw_list_chrome(v, n, panel)
	mp := rl.GetMousePosition()
	for row in 0 ..< v.rows {
		i := v.first + row
		if i >= n {
			break
		}
		it := g.colony.items[i]
		rec := list_row_rect(v, row)
		sel := i == v.index
		draw_list_row_bg(rec, sel, rl.CheckCollisionPointRec(mp, rec))
		rl.DrawCircleV(rl.Vector2{rec.x + 11, rec.y + 11}, 6, item_color(it))
		draw_text(item_name(it), i32(rec.x) + 26, i32(rec.y) + 3, 16, sel ? rl.Color{240, 240, 250, 255} : rl.Color{200, 200, 215, 255})
	}

	draw_text(fmt.ctprintf("%d item%s in the bag", n, n == 1 ? "" : "s"), 40, i32(sh) - 32, 16, rl.Color{130, 130, 150, 255})

	dx := f32(390)
	dy := f32(120)
	if n == 0 {
		draw_text("Your bag is empty.", i32(dx), i32(dy), 22, rl.Color{170, 170, 190, 255})
		draw_text("Items drop from winning battles - equip them in the deck viewer (V).", i32(dx), i32(dy) + 34, 16, rl.Color{140, 140, 160, 255})
		return
	}

	idx := clamp(g.bag_index, 0, n - 1)
	it := g.colony.items[idx]

	// Icon (coloured disc with the initial).
	col := item_color(it)
	rl.DrawCircleV(rl.Vector2{dx + 44, dy + 40}, 36, rl.Color{col[0] / 3, col[1] / 3, col[2] / 3, 255})
	rl.DrawCircleLinesV(rl.Vector2{dx + 44, dy + 40}, 36, rl.Color{235, 235, 245, 255})
	initial := fmt.ctprintf("%c", item_info(it).name[0])
	iw := measure_text(initial, 34)
	draw_text(initial, i32(dx + 44) - iw / 2, i32(dy + 40) - 17, 34, rl.Color{255, 255, 255, 255})

	draw_text(item_name(it), i32(dx + 100), i32(dy) + 4, 30, rl.Color{235, 235, 245, 255})
	draw_text(item_desc(it), i32(dx + 100), i32(dy) + 42, 17, col)

	// Effect breakdown.
	ey := i32(dy) + 96
	draw_text("EFFECTS", i32(dx), ey, 15, rl.Color{150, 150, 170, 255})
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
	draw_text(fmt.ctprintf("Equip to: %s", target_name), i32(dx), i32(sh) - 138, 16, rl.Color{180, 180, 200, 255})

	btn := bag_equip_rect()
	hover := can_equip && rl.CheckCollisionPointRec(mp, btn)
	bg := can_equip ? (hover ? rl.Color{60, 100, 78, 255} : rl.Color{44, 74, 58, 255}) : rl.Color{34, 34, 42, 255}
	rl.DrawRectangleRounded(btn, 0.24, 8, bg)
	rl.DrawRectangleRoundedLinesEx(btn, 0.24, 8, 2, can_equip ? rl.Color{150, 220, 180, 255} : rl.Color{80, 80, 92, 255})
	lab := cstring("Equip to selected monster")
	lw := measure_text(lab, 18)
	draw_text(lab, i32(btn.x + btn.width / 2) - lw / 2, i32(btn.y + btn.height / 2) - 9, 18, can_equip ? rl.Color{235, 250, 240, 255} : rl.Color{130, 130, 142, 255})
}

// ----------------------------------------------------------------------------
// Crystal progression panel (a tree, shown in two columns)
// ----------------------------------------------------------------------------

UPGRADE_ROWS :: 12 // rows per column; 3 columns hold up to 36 nodes

upgrade_panel_rect :: proc() -> rl.Rectangle {
	sw := f32(rl.GetScreenWidth())
	sh := f32(rl.GetScreenHeight())
	w := f32(1230)
	h := f32(692)
	return rl.Rectangle{sw / 2 - w / 2, sh / 2 - h / 2, w, h}
}

// Total scrollable height of the upgrade grid (rows of cells).
upgrade_content_h :: proc() -> f32 {
	return f32(UPGRADE_ROWS) * 62
}

upgrade_max_scroll :: proc() -> f32 {
	p := upgrade_panel_rect()
	visible := p.height - 100 - 40
	return max(f32(0), upgrade_content_h() - visible)
}

upgrade_cell_rect :: proc(i: int, scroll: f32 = 0) -> rl.Rectangle {
	p := upgrade_panel_rect()
	cw := (p.width - 40 - 2 * 16) / 3
	col := i / UPGRADE_ROWS
	row := i % UPGRADE_ROWS
	return rl.Rectangle{p.x + 20 + f32(col) * (cw + 16), p.y + 100 + f32(row) * 62 - scroll, cw, 56}
}

upgrade_buy_rect :: proc(i: int, scroll: f32 = 0) -> rl.Rectangle {
	r := upgrade_cell_rect(i, scroll)
	return rl.Rectangle{r.x + r.width - 96, r.y + 13, 86, 30}
}

update_upgrades :: proc(g: ^Game) {
	if rl.IsKeyPressed(.ESCAPE) || rl.IsKeyPressed(.U) {
		g.show_upgrades = false
		return
	}
	g.upgrade_scroll -= rl.GetMouseWheelMove() * 70
	g.upgrade_scroll = clamp(g.upgrade_scroll, 0, upgrade_max_scroll())
	if !rl.IsMouseButtonPressed(.LEFT) {
		return
	}
	mp := rl.GetMousePosition()
	for i in 0..<len(UPGRADE_ORDER) {
		if rl.CheckCollisionPointRec(mp, upgrade_buy_rect(i, g.upgrade_scroll)) {
			u := UPGRADE_ORDER[i]
			switch colony_buy_upgrade(&g.colony, u) {
			case 0: set_status(g, fmt.ctprintf("%s upgraded!", upgrade_name(u)))
			case 1: set_status(g, "Already at the maximum level.")
			case 2: set_status(g, "Not enough crystals.")
			case 3:
				info := UPGRADES[u]
				set_status(g, fmt.ctprintf("Locked - needs %s Lv %d first.", upgrade_name(info.prereq), info.req_level))
			}
			return
		}
	}
}

draw_upgrades :: proc(g: ^Game) {
	sw := f32(rl.GetScreenWidth())
	sh := f32(rl.GetScreenHeight())
	rl.DrawRectangle(0, 0, i32(sw), i32(sh), rl.Color{8, 10, 16, 245})

	p := upgrade_panel_rect()
	rl.DrawRectangleRounded(p, 0.03, 8, rl.Color{18, 20, 30, 248})
	rl.DrawRectangleRoundedLinesEx(p, 0.03, 8, 3, rl.Color{150, 120, 235, 255})

	draw_text("CRYSTAL PROGRESSION", i32(p.x) + 24, i32(p.y) + 18, 30, rl.Color{210, 190, 250, 255})
	draw_text(fmt.ctprintf("Crystals: %d    -    permanent upgrades; fight the Arena and Boss Rooms for more", g.colony.crystals), i32(p.x) + 24, i32(p.y) + 58, 16, rl.Color{190, 175, 220, 255})

	mp := rl.GetMousePosition()
	clip := rl.Rectangle{p.x + 12, p.y + 96, p.width - 24, p.height - 100 - 34}
	rl.BeginScissorMode(i32(clip.x), i32(clip.y), i32(clip.width), i32(clip.height))
	for i in 0..<len(UPGRADE_ORDER) {
		u := UPGRADE_ORDER[i]
		info := UPGRADES[u]
		rec := upgrade_cell_rect(i, g.upgrade_scroll)
		if rec.y + rec.height < clip.y || rec.y > clip.y + clip.height {
			continue
		}
		level := g.colony.upgrades[u]
		maxed := level >= info.max_level
		unlocked := upgrade_unlocked(&g.colony, u)
		child := info.prereq != .NONE
		indent := child ? f32(18) : f32(0)

		bg := rl.Color{24, 24, 34, 255}
		if level > 0 { bg = rl.Color{30, 26, 44, 255} }
		if !unlocked { bg = rl.Color{20, 19, 24, 255} }
		rl.DrawRectangleRounded(rec, 0.08, 6, bg)
		border := maxed ? rl.Color{150, 120, 235, 255} : (unlocked ? rl.Color{70, 66, 92, 255} : rl.Color{46, 44, 54, 255})
		rl.DrawRectangleRoundedLinesEx(rec, 0.08, 6, 2, border)

		// A little "tree" tick joining a child to its column.
		if child {
			rl.DrawLineEx(rl.Vector2{rec.x + 8, rec.y + 20}, rl.Vector2{rec.x + 15, rec.y + 20}, 2, rl.Color{90, 84, 120, 255})
		}

		name_col := unlocked ? rl.Color{235, 232, 250, 255} : rl.Color{130, 128, 145, 255}
		draw_text(upgrade_name(u), i32(rec.x + indent) + 14, i32(rec.y) + 5, 15, name_col)

		// Level pips after the name.
		nw := measure_text(upgrade_name(u), 15)
		for lv in 0..<info.max_level {
			cx := rec.x + indent + 14 + f32(nw) + 12 + f32(lv) * 13
			col := lv < level ? rl.Color{170, 140, 245, 255} : rl.Color{58, 56, 74, 255}
			rl.DrawCircleV(rl.Vector2{cx, rec.y + 12}, 4.5, col)
		}

		if unlocked {
			draw_text(upgrade_desc(u), i32(rec.x + indent) + 14, i32(rec.y) + 24, 11, rl.Color{185, 185, 205, 255})
			draw_text("unlocked", i32(rec.x + indent) + 14, i32(rec.y) + 40, 11, rl.Color{110, 130, 118, 255})
		} else {
			draw_text(fmt.ctprintf("Needs %s Lv %d", upgrade_name(info.prereq), info.req_level), i32(rec.x + indent) + 14, i32(rec.y) + 30, 11, rl.Color{225, 175, 110, 255})
		}

		// Buy button.
		btn := upgrade_buy_rect(i, g.upgrade_scroll)
		cost := upgrade_cost(u, level)
		afford := g.colony.crystals >= cost
		enabled := !maxed && unlocked && afford
		hover := enabled && rl.CheckCollisionPointRec(mp, btn)
		bbg := !enabled ? rl.Color{30, 28, 38, 255} : (hover ? rl.Color{64, 50, 104, 255} : rl.Color{48, 40, 78, 255})
		rl.DrawRectangleRounded(btn, 0.3, 8, bbg)
		bborder := maxed ? rl.Color{120, 100, 170, 255} : (enabled ? rl.Color{170, 140, 245, 255} : rl.Color{84, 76, 104, 255})
		rl.DrawRectangleRoundedLinesEx(btn, 0.3, 8, 2, bborder)
		label: cstring
		switch {
		case !unlocked: label = "Locked"
		case maxed:     label = "MAX"
		case:           label = fmt.ctprintf("Buy %d", cost)
		}
		lw := measure_text(label, 14)
		lc := maxed ? rl.Color{160, 150, 190, 255} : (enabled ? rl.Color{235, 230, 255, 255} : rl.Color{140, 132, 158, 255})
		draw_text(label, i32(btn.x + btn.width / 2) - lw / 2, i32(btn.y + btn.height / 2) - 7, 14, lc)

		if rl.CheckCollisionPointRec(mp, rec) {
			if !unlocked {
				tooltip_set("%s - %s\nLocked: needs %s Lv %d first.", upgrade_name(u), upgrade_desc(u), upgrade_name(info.prereq), info.req_level)
			} else if maxed {
				tooltip_set("%s - %s\nMaxed at level %d.", upgrade_name(u), upgrade_desc(u), info.max_level)
			} else {
				tooltip_set("%s - %s\nLevel %d/%d. Next level: %d crystals.", upgrade_name(u), upgrade_desc(u), level, info.max_level, upgrade_cost(u, level))
			}
		}
	}
	rl.EndScissorMode()

	draw_text("U / Esc to close   -   wheel to scroll   -   children unlock when their parent reaches the shown level", i32(p.x) + 24, i32(p.y + p.height) - 24, 13, rl.Color{140, 140, 160, 255})
}

// ----------------------------------------------------------------------------
// Arena panel (pay gold -> fight a strong team for crystals)
// ----------------------------------------------------------------------------

arena_panel_rect :: proc() -> rl.Rectangle {
	sw := f32(rl.GetScreenWidth())
	sh := f32(rl.GetScreenHeight())
	return rl.Rectangle{sw / 2 - 260, sh / 2 - 170, 520, 340}
}

arena_fight_rect :: proc() -> rl.Rectangle {
	p := arena_panel_rect()
	return rl.Rectangle{p.x + 30, p.y + 220, p.width - 60, 52}
}

arena_leave_rect :: proc() -> rl.Rectangle {
	p := arena_panel_rect()
	return rl.Rectangle{p.x + 30, p.y + 282, p.width - 60, 40}
}

// The Arena resets if you lose: the team leaves so you can try again.
arena_reset :: proc(g: ^Game) {
	i := 0
	for i < len(g.colony.roster) {
		m := &g.colony.roster[i]
		if m.wild && hex_equal(m.pos, g.battle_hex) {
			remove_monster_at(&g.colony, i, false)
			continue
		}
		i += 1
	}
}

update_arena :: proc(g: ^Game) {
	if rl.IsKeyPressed(.ESCAPE) || rl.IsKeyPressed(.T) {
		g.arena_open = false
		return
	}
	if !rl.IsMouseButtonPressed(.LEFT) {
		return
	}
	mp := rl.GetMousePosition()
	if rl.CheckCollisionPointRec(mp, arena_leave_rect()) {
		g.arena_open = false
		return
	}
	if rl.CheckCollisionPointRec(mp, arena_fight_rect()) {
		if colony_total_gold(&g.colony) < ARENA_ENTRY_COST {
			set_status(g, "Not enough gold to enter the Arena.")
			return
		}
		hex := g.colony.roster[g.selected].pos
		_ = colony_spend_gold(&g.colony, ARENA_ENTRY_COST)
		colony_spawn_arena_team(&g.colony, hex)
		g.arena_open = false
		g.battle_hex = hex
		g.battle_forced = true
		build_attack(g, hex, 1)
		g.battle_choice_open = true
		set_status(g, "The Arena answers your challenge!")
	}
}

draw_arena :: proc(g: ^Game) {
	sw := f32(rl.GetScreenWidth())
	sh := f32(rl.GetScreenHeight())
	rl.DrawRectangle(0, 0, i32(sw), i32(sh), rl.Color{0, 0, 0, 165})

	p := arena_panel_rect()
	rl.DrawRectangleRounded(p, 0.05, 8, rl.Color{30, 24, 18, 248})
	rl.DrawRectangleRoundedLinesEx(p, 0.05, 8, 3, rl.Color{210, 170, 90, 255})

	draw_text("THE ARENA", i32(p.x) + 28, i32(p.y) + 20, 30, rl.Color{240, 210, 130, 255})
	draw_text(fmt.ctprintf("%d challengers await - skilled, and above your level.", ARENA_TEAM_SIZE), i32(p.x) + 28, i32(p.y) + 62, 17, rl.Color{215, 200, 175, 255})
	draw_text(fmt.ctprintf("Entry costs %d gold. Win and the crowd pays you %d crystals.", ARENA_ENTRY_COST, ARENA_CRYSTAL_REWARD), i32(p.x) + 28, i32(p.y) + 88, 16, rl.Color{210, 190, 150, 255})
	draw_text("Bring a full party - their numbers match yours only if you do.", i32(p.x) + 28, i32(p.y) + 114, 16, rl.Color{190, 175, 150, 255})
	draw_text(fmt.ctprintf("Gold: %d      Crystals: %d", colony_total_gold(&g.colony), g.colony.crystals), i32(p.x) + 28, i32(p.y) + 150, 18, rl.Color{235, 210, 120, 255})

	mp := rl.GetMousePosition()
	afford := colony_total_gold(&g.colony) >= ARENA_ENTRY_COST

	btn := arena_fight_rect()
	hover := afford && rl.CheckCollisionPointRec(mp, btn)
	bg := afford ? (hover ? rl.Color{120, 60, 40, 255} : rl.Color{88, 46, 32, 255}) : rl.Color{40, 36, 34, 255}
	rl.DrawRectangleRounded(btn, 0.22, 8, bg)
	rl.DrawRectangleRoundedLinesEx(btn, 0.22, 8, 2, afford ? rl.Color{230, 150, 90, 255} : rl.Color{100, 90, 80, 255})
	fl := fmt.ctprintf("Fight   (%d gold)", ARENA_ENTRY_COST)
	fw := measure_text(fl, 20)
	draw_text(fl, i32(btn.x + btn.width / 2) - fw / 2, i32(btn.y + btn.height / 2) - 11, 20, afford ? rl.Color{250, 235, 220, 255} : rl.Color{150, 140, 130, 255})

	lr := arena_leave_rect()
	lhover := rl.CheckCollisionPointRec(mp, lr)
	rl.DrawRectangleRounded(lr, 0.3, 8, lhover ? rl.Color{46, 44, 52, 255} : rl.Color{34, 32, 38, 255})
	ll := cstring("Walk away")
	lw := measure_text(ll, 16)
	draw_text(ll, i32(lr.x + lr.width / 2) - lw / 2, i32(lr.y + lr.height / 2) - 8, 16, rl.Color{190, 185, 200, 255})
}

// ----------------------------------------------------------------------------
// Move-choice overlay (level-ups & battle rewards)
//
// When a level unlocks several moves, or a battle drops a reward card, the
// player picks one here. Choices queue up on `Colony.choices` and are shown one
// at a time, on top of whatever screen raised them.
// ----------------------------------------------------------------------------

CHOICE_CARD_W :: f32(150)
CHOICE_CARD_H :: f32(190)

move_choice_card_rect :: proc(i, n: int) -> rl.Rectangle {
	sw := f32(rl.GetScreenWidth())
	sh := f32(rl.GetScreenHeight())
	gap := f32(20)
	total := f32(n) * CHOICE_CARD_W + f32(n - 1) * gap
	start := sw / 2 - total / 2
	y := sh / 2 - CHOICE_CARD_H / 2 + 10
	return rl.Rectangle{start + f32(i) * (CHOICE_CARD_W + gap), y, CHOICE_CARD_W, CHOICE_CARD_H}
}

move_choice_skip_rect :: proc() -> rl.Rectangle {
	sw := f32(rl.GetScreenWidth())
	sh := f32(rl.GetScreenHeight())
	return rl.Rectangle{sw / 2 - 90, sh / 2 + CHOICE_CARD_H / 2 + 28, 180, 44}
}

// Learns the chosen option and pops the front choice.
take_choice :: proc(c: ^Colony, option: int) {
	if len(c.choices) == 0 {
		return
	}
	ch := c.choices[0]
	if mi := monster_by_id(c, ch.monster_id); mi >= 0 {
		append(&c.roster[mi].creature.deck, ch.options[option])
	}
	ordered_remove(&c.choices, 0)
}

update_move_choice :: proc(g: ^Game) {
	if len(g.colony.choices) == 0 {
		return
	}
	// Drop a choice whose monster is gone (died before it could be resolved).
	if monster_by_id(&g.colony, g.colony.choices[0].monster_id) < 0 {
		ordered_remove(&g.colony.choices, 0)
		return
	}
	ch := g.colony.choices[0]
	if rl.IsMouseButtonPressed(.LEFT) {
		mp := rl.GetMousePosition()
		for i in 0..<ch.count {
			if rl.CheckCollisionPointRec(mp, move_choice_card_rect(i, ch.count)) {
				take_choice(&g.colony, i)
				audio_play(.CONFIRM)
				return
			}
		}
		if rl.CheckCollisionPointRec(mp, move_choice_skip_rect()) {
			ordered_remove(&g.colony.choices, 0)
			audio_play(.CANCEL)
			return
		}
	}
	for i in 0..<min(ch.count, len(DIGIT_KEYS)) {
		if rl.IsKeyPressed(DIGIT_KEYS[i]) {
			take_choice(&g.colony, i)
			audio_play(.CONFIRM)
			return
		}
	}
}

draw_move_choice :: proc(g: ^Game) {
	if len(g.colony.choices) == 0 {
		return
	}
	ch := g.colony.choices[0]
	mi := monster_by_id(&g.colony, ch.monster_id)
	if mi < 0 {
		return
	}
	sw := f32(rl.GetScreenWidth())
	sh := f32(rl.GetScreenHeight())
	rl.DrawRectangle(0, 0, i32(sw), i32(sh), rl.Color{0, 0, 0, 205})

	m := &g.colony.roster[mi]
	title := ch.kind == .LEVEL ? cstring("LEVEL UP!") : cstring("REWARD CARD")
	tcol := ch.kind == .LEVEL ? rl.Color{255, 235, 140, 255} : rl.Color{210, 160, 255, 255}
	tw := measure_text(title, 40)
	draw_text(title, i32(sw) / 2 - tw / 2, 120, 40, tcol)

	sub: cstring
	if ch.kind == .LEVEL {
		sub = fmt.ctprintf("%s reached Lvl %d - choose a move to learn", m.creature.name, m.creature.level)
	} else {
		sub = fmt.ctprintf("%s earned a reward - choose a card", m.creature.name)
	}
	sw2 := measure_text(sub, 18)
	draw_text(sub, i32(sw) / 2 - sw2 / 2, 172, 18, rl.Color{200, 200, 215, 255})

	mp := rl.GetMousePosition()
	for i in 0..<ch.count {
		rec := move_choice_card_rect(i, ch.count)
		hovered := rl.CheckCollisionPointRec(mp, rec)
		draw_card(ch.options[i], rec, true, hovered)
		// Rarity tag above the card. A hovered card lifts, so raise the tag
		// with it or the card would cover it.
		tag_y := rec.y - 22 - (hovered ? CARD_HOVER_LIFT : 0)
		r := MOVE_DATA[ch.options[i]].rarity
		rt := card_rarity_name(r)
		rc := card_rarity_color(r)
		rw := measure_text(rt, 15)
		draw_text(rt, i32(rec.x) + i32(rec.width) / 2 - rw / 2, i32(tag_y), 15, rc)
	}

	draw_button(move_choice_skip_rect(), cstring("Skip"), true, BUTTON_PANEL, 18)
	hint := cstring("Click a card or press 1-3 to learn it")
	hw := measure_text(hint, 15)
	draw_text(hint, i32(sw) / 2 - hw / 2, i32(sh) - 44, 15, rl.Color{140, 140, 160, 255})
}

// ----------------------------------------------------------------------------
// Quest board: milestones + the run goal (Phase 22)
// ----------------------------------------------------------------------------

quest_panel_rect :: proc() -> rl.Rectangle {
	sw := f32(rl.GetScreenWidth())
	sh := f32(rl.GetScreenHeight())
	w := f32(700)
	h := f32(min(sh - 60, 640))
	return rl.Rectangle{sw / 2 - w / 2, sh / 2 - h / 2, w, h}
}

update_quests :: proc(g: ^Game) {
	if rl.IsKeyPressed(.ESCAPE) || rl.IsKeyPressed(.Q) {
		g.show_quests = false
	}
}

draw_quests :: proc(g: ^Game) {
	sw := f32(rl.GetScreenWidth())
	sh := f32(rl.GetScreenHeight())
	rl.DrawRectangle(0, 0, i32(sw), i32(sh), rl.Color{8, 10, 16, 245})

	p := quest_panel_rect()
	rl.DrawRectangleRounded(p, 0.03, 8, rl.Color{18, 20, 28, 248})
	rl.DrawRectangleRoundedLinesEx(p, 0.03, 8, 3, rl.Color{120, 200, 160, 255})

	done := milestones_done_count(&g.colony)
	total := len(MILESTONES)
	draw_text("COLONY JOURNAL", i32(p.x) + 24, i32(p.y) + 16, 28, rl.Color{180, 235, 200, 255})
	draw_text(fmt.ctprintf("Milestones %d / %d  -  each pays a small crystal bounty; finish them all to complete the run", done, total),
		i32(p.x) + 24, i32(p.y) + 52, 15, rl.Color{180, 190, 200, 255})

	row_h := f32(42)
	y := p.y + 88
	for k in Milestone_Kind {
		is_done := g.colony.milestones[k]
		prog := min(milestone_progress(&g.colony, k), MILESTONES[k].target)
		tgt := MILESTONES[k].target
		rec := rl.Rectangle{p.x + 20, y, p.width - 40, row_h - 6}
		bg := is_done ? rl.Color{26, 40, 30, 255} : rl.Color{24, 24, 32, 255}
		rl.DrawRectangleRounded(rec, 0.12, 6, bg)
		rl.DrawRectangleRoundedLinesEx(rec, 0.12, 6, 2, is_done ? rl.Color{120, 210, 150, 255} : rl.Color{56, 56, 70, 255})

		draw_text(MILESTONES[k].desc, i32(rec.x) + 46, i32(rec.y) + 5, 17,
			is_done ? rl.Color{190, 240, 205, 255} : rl.Color{225, 225, 235, 255})
		bar := rl.Rectangle{rec.x + 46, rec.y + 26, rec.width - 210, 5}
		rl.DrawRectangleRounded(bar, 0.5, 3, rl.Color{40, 40, 50, 255})
		f := tgt > 0 ? clamp(f32(prog) / f32(tgt), 0, 1) : 0
		if f > 0 {
			rl.DrawRectangleRounded(rl.Rectangle{bar.x, bar.y, bar.width * f, bar.height}, 0.5, 3,
				is_done ? rl.Color{120, 210, 150, 255} : rl.Color{120, 170, 235, 255})
		}
		mark := is_done ? cstring("DONE") : fmt.ctprintf("%d/%d", prog, tgt)
		rew := fmt.ctprintf("+%d cr", MILESTONES[k].reward)
		rew_w := measure_text(rew, 14)
		mark_w := measure_text(mark, 15)
		rew_x := i32(rec.x + rec.width) - 12 - rew_w
		mark_x := rew_x - 14 - mark_w
		draw_text(mark, mark_x, i32(rec.y) + 8, 15,
			is_done ? rl.Color{150, 230, 175, 255} : rl.Color{170, 175, 190, 255})
		draw_text(rew, rew_x, i32(rec.y) + 8, 14, rl.Color{180, 150, 240, 255})

		cx, cy := rec.x + 24, rec.y + 16
		if is_done {
			rl.DrawCircleV(rl.Vector2{cx, cy}, 9, rl.Color{80, 170, 110, 255})
			draw_text("v", i32(cx) - 4, i32(cy) - 9, 16, rl.Color{235, 255, 240, 255})
		} else {
			rl.DrawCircleLinesV(rl.Vector2{cx, cy}, 9, rl.Color{90, 90, 105, 255})
		}
		y += row_h
	}

	if g.colony.goal_done {
		banner := cstring("OBJECTIVE COMPLETE - the colony is ascendant")
		bw := measure_text(banner, 20)
		draw_text(banner, i32(p.x + p.width / 2) - bw / 2, i32(p.y + p.height) - 60, 20, rl.Color{255, 225, 130, 255})
	}

	hint := cstring("Q / Esc to close")
	hw := measure_text(hint, 16)
	draw_text(hint, i32(p.x + p.width / 2) - hw / 2, i32(p.y + p.height) - 28, 16, rl.Color{150, 150, 170, 255})
}

// ----------------------------------------------------------------------------
// Hall of the Fallen: the graveyard, with revive + item salvage (Phase 22)
// ----------------------------------------------------------------------------

GRAVE_ROWS :: 8

grave_panel_rect :: proc() -> rl.Rectangle {
	sw := f32(rl.GetScreenWidth())
	sh := f32(rl.GetScreenHeight())
	w := f32(740)
	h := f32(min(sh - 60, 600))
	return rl.Rectangle{sw / 2 - w / 2, sh / 2 - h / 2, w, h}
}

grave_row_rect :: proc(i, first: int) -> rl.Rectangle {
	p := grave_panel_rect()
	row := i - first
	return rl.Rectangle{p.x + 20, p.y + 96 + f32(row) * 56, p.width - 40, 50}
}

grave_revive_rect :: proc(i, first: int) -> rl.Rectangle {
	rec := grave_row_rect(i, first)
	return rl.Rectangle{rec.x + rec.width - 216, rec.y + 8, 112, 34}
}

grave_salvage_rect :: proc(i, first: int) -> rl.Rectangle {
	rec := grave_row_rect(i, first)
	return rl.Rectangle{rec.x + rec.width - 100, rec.y + 8, 100, 34}
}

update_graveyard :: proc(g: ^Game) {
	if rl.IsKeyPressed(.ESCAPE) || rl.IsKeyPressed(.Y) {
		g.show_graveyard = false
		return
	}
	n := len(g.colony.graveyard)
	max_first := max(n - GRAVE_ROWS, 0)
	if rl.IsKeyPressed(.DOWN) { g.grave_first += 1 }
	if rl.IsKeyPressed(.UP)   { g.grave_first -= 1 }
	g.grave_first = clamp(g.grave_first, 0, max_first)
	if !rl.IsMouseButtonPressed(.LEFT) {
		return
	}
	mp := rl.GetMousePosition()
	for i in g.grave_first..<min(g.grave_first + GRAVE_ROWS, n) {
		if rl.CheckCollisionPointRec(mp, grave_revive_rect(i, g.grave_first)) {
			switch colony_revive(&g.colony, i) {
			case 0: set_status(g, "Revived.")
			case 2: set_status(g, "Not enough gold.")
			case 3: set_status(g, "The start tile is full.")
			}
			return
		}
		if rl.CheckCollisionPointRec(mp, grave_salvage_rect(i, g.grave_first)) {
			switch colony_salvage_grave(&g.colony, i) {
			case 0: set_status(g, "Salvaged the item into your bag.")
			case 2: set_status(g, "That one carried no item.")
			case 3: set_status(g, "Your item bag is full.")
			}
			return
		}
	}
}

draw_graveyard :: proc(g: ^Game) {
	sw := f32(rl.GetScreenWidth())
	sh := f32(rl.GetScreenHeight())
	rl.DrawRectangle(0, 0, i32(sw), i32(sh), rl.Color{8, 10, 16, 245})

	p := grave_panel_rect()
	rl.DrawRectangleRounded(p, 0.03, 8, rl.Color{20, 18, 24, 248})
	rl.DrawRectangleRoundedLinesEx(p, 0.03, 8, 3, rl.Color{150, 130, 170, 255})

	draw_text("HALL OF THE FALLEN", i32(p.x) + 24, i32(p.y) + 16, 28, rl.Color{210, 195, 225, 255})
	draw_text(fmt.ctprintf("Gold: %d   -   revive the fallen, or salvage the gear they carried", colony_total_gold(&g.colony)),
		i32(p.x) + 24, i32(p.y) + 52, 15, rl.Color{180, 175, 195, 255})

	n := len(g.colony.graveyard)
	if n == 0 {
		draw_text("No monsters have fallen. Yet.", i32(p.x) + 24, i32(p.y) + 104, 18, rl.Color{150, 150, 165, 255})
	} else {
		for i in g.grave_first..<min(g.grave_first + GRAVE_ROWS, n) {
			m := &g.colony.graveyard[i]
			rec := grave_row_rect(i, g.grave_first)
			rl.DrawRectangleRounded(rec, 0.12, 6, rl.Color{28, 24, 30, 255})
			rl.DrawRectangleRoundedLinesEx(rec, 0.12, 6, 2, rl.Color{70, 60, 74, 255})
			draw_text(fmt.ctprintf("%s  Lvl %d", m.creature.name, m.creature.level),
				i32(rec.x) + 14, i32(rec.y) + 6, 18, rl.Color{225, 215, 225, 255})
			draw_text(elements_label(creature_elements(&m.creature)), i32(rec.x) + 14, i32(rec.y) + 27, 13,
				element_color(creature_element(&m.creature)))
			item_txt := m.creature.item != .NONE ? fmt.ctprintf("item: %s", item_name(m.creature.item)) : cstring("no item")
			draw_text(item_txt, i32(rec.x) + 150, i32(rec.y) + 27, 13, rl.Color{150, 210, 170, 255})

			cost := revive_cost(m)
			draw_button(grave_revive_rect(i, g.grave_first), fmt.ctprintf("Revive %dg", cost),
				colony_total_gold(&g.colony) >= cost, BUTTON_PANEL, 14)
			draw_button(grave_salvage_rect(i, g.grave_first), cstring("Salvage"),
				m.creature.item != .NONE && len(g.colony.items) < colony_item_cap(&g.colony), BUTTON_PANEL, 14)
		}
	}

	hint := cstring("Y / Esc close   |   Up/Down scroll")
	hw := measure_text(hint, 16)
	draw_text(hint, i32(p.x + p.width / 2) - hw / 2, i32(p.y + p.height) - 28, 16, rl.Color{150, 150, 170, 255})
}

// ----------------------------------------------------------------------------
// Unit picker (Phase 24)
//
// When you click a tile holding several of your monsters, ask which one to
// control instead of silently cycling with Tab.
// ----------------------------------------------------------------------------

UNIT_PICKER_ROW_H :: f32(46)

unit_picker_rect :: proc(g: ^Game) -> rl.Rectangle {
	n := len(g.unit_picker_ids)
	w := f32(320)
	h := f32(40) + f32(n) * UNIT_PICKER_ROW_H
	x, y := hex_to_screen(&g.renderer, g.unit_picker_hex)
	x = clamp(x + 44, 16, f32(rl.GetScreenWidth()) - w - 16)
	y = clamp(y - h / 2, 60, f32(rl.GetScreenHeight()) - h - 16)
	return rl.Rectangle{x, y, w, h}
}

unit_picker_row_rect :: proc(g: ^Game, i: int) -> rl.Rectangle {
	p := unit_picker_rect(g)
	return rl.Rectangle{p.x + 8, p.y + 38 + f32(i) * UNIT_PICKER_ROW_H, p.width - 16, UNIT_PICKER_ROW_H - 4}
}

// Select the sole monster on `hex`, or open the picker when there are several.
select_or_pick_on_tile :: proc(g: ^Game, hex: Hex) {
	ids := make([dynamic]int, 0, 8); defer delete(ids)
	for m, i in g.colony.roster {
		if !m.wild && m.creature.hp > 0 && hex_equal(m.pos, hex) {
			append(&ids, i)
		}
	}
	if len(ids) == 0 {
		return
	}
	if len(ids) == 1 {
		g.selected = ids[0]
		return
	}
	clear(&g.unit_picker_ids)
	for i in ids {
		append(&g.unit_picker_ids, i)
	}
	g.unit_picker_hex = hex
	g.unit_picker_open = true
	audio_play(.CLICK, 0.5)
}

update_unit_picker :: proc(g: ^Game) {
	if rl.IsKeyPressed(.ESCAPE) {
		g.unit_picker_open = false
		return
	}
	for i in 0..<min(len(g.unit_picker_ids), len(DIGIT_KEYS)) {
		if rl.IsKeyPressed(DIGIT_KEYS[i]) {
			g.selected = g.unit_picker_ids[i]
			g.unit_picker_open = false
			audio_play(.CLICK, 0.6)
			return
		}
	}
	if rl.IsMouseButtonPressed(.LEFT) {
		mp := rl.GetMousePosition()
		for i in 0..<len(g.unit_picker_ids) {
			if rl.CheckCollisionPointRec(mp, unit_picker_row_rect(g, i)) {
				g.selected = g.unit_picker_ids[i]
				g.unit_picker_open = false
				audio_play(.CLICK, 0.6)
				return
			}
		}
		if !rl.CheckCollisionPointRec(mp, unit_picker_rect(g)) {
			g.unit_picker_open = false
		}
	}
}

draw_unit_picker :: proc(g: ^Game) {
	if !g.unit_picker_open || len(g.unit_picker_ids) == 0 {
		return
	}
	p := unit_picker_rect(g)
	draw_panel(p, rl.Color{18, 20, 28, 248}, rl.Color{120, 200, 160, 255})
	draw_text(fmt.ctprintf("Choose a monster  (%d here)", len(g.unit_picker_ids)),
		i32(p.x) + 12, i32(p.y) + 10, 16, rl.Color{200, 235, 210, 255})
	mp := rl.GetMousePosition()
	for id, i in g.unit_picker_ids {
		mi := id // stored as a roster index, not a monster id
		if mi < 0 || mi >= len(g.colony.roster) {
			continue
		}
		m := &g.colony.roster[mi]
		rec := unit_picker_row_rect(g, i)
		hover := rl.CheckCollisionPointRec(mp, rec)
		draw_row(rec, false, hover, rl.Color{140, 230, 160, 255})
		rl.DrawCircleV(rl.Vector2{rec.x + 18, rec.y + rec.height / 2}, 12, creature_color(&m.creature))
		rl.DrawCircleLinesV(rl.Vector2{rec.x + 18, rec.y + rec.height / 2}, 12, element_color(creature_element(&m.creature)))
		draw_text(fmt.ctprintf("%d. %s  Lvl %d", i + 1, m.creature.name, m.creature.level),
			i32(rec.x) + 40, i32(rec.y) + 5, 15, rl.Color{230, 235, 245, 255})
		draw_text(fmt.ctprintf("HP %d/%d   En %s/%s", m.creature.hp, m.creature.max_hp, fmt_num(m.creature.energy), fmt_num(m.creature.energy_max)),
			i32(rec.x) + 40, i32(rec.y) + 23, 12, rl.Color{190, 200, 215, 255})
	}
}

// ----------------------------------------------------------------------------
// Help overlay (Phase 24)
// ----------------------------------------------------------------------------

Help_Line :: struct {
	key:    cstring,
	action: cstring,
}

HELP_LEFT := [?]Help_Line{
	{"Left click adjacent tile", "move the selected monster"},
	{"Left click your tile", "pick which monster to control"},
	{"Tab", "cycle through your monsters"},
	{"Space / E", "end the turn"},
	{"Right drag / WASD", "pan the camera"},
	{"Wheel", "zoom (around the cursor)"},
	{"R", "recenter on the entrance"},
	{"B", "build mode (click a tile, then pick)"},
	{"T", "Trading Post / Arena on the tile"},
	{"F", "quick-save to slot 1"},
}

HELP_RIGHT := [?]Help_Line{
	{"V", "deck viewer (right-click a card to forget it)"},
	{"M", "monster encyclopedia"},
	{"I", "improvements reference"},
	{"G", "item bag"},
	{"U", "crystal progression tree"},
	{"Q", "quest journal / milestones"},
	{"J", "relics (boss-dropped passives)"},
	{"Y", "Hall of the Fallen (graveyard)"},
	{"C", "Nursery (breeding)"},
	{"H", "monster storage (Dens)"},
	{"O", "save / load (incl. autosave)"},
	{"Z", "toggle the minimap"},
	{"K", "this help"},
	{"P", "settings (sound, display, last turn)"},
	{"X", "mute / unmute sound"},
	{"Esc", "close the current panel"},
}

update_help :: proc(g: ^Game) {
	if rl.IsKeyPressed(.K) || rl.IsKeyPressed(.ESCAPE) {
		g.show_help = false
	}
}

draw_help :: proc(g: ^Game) {
	sw := f32(rl.GetScreenWidth())
	sh := f32(rl.GetScreenHeight())
	rl.DrawRectangle(0, 0, i32(sw), i32(sh), rl.Color{8, 10, 16, 246})

	p := rl.Rectangle{sw / 2 - 500, sh / 2 - 300, 1000, 600}
	draw_panel(p, rl.Color{18, 20, 28, 248}, rl.Color{150, 170, 220, 255})
	draw_text("CONTROLS", i32(p.x) + 26, i32(p.y) + 16, 30, rl.Color{220, 228, 245, 255})
	draw_text("Most panels close with their key or Esc. Esc never quits.", i32(p.x) + 26, i32(p.y) + 54, 15, rl.Color{170, 180, 200, 255})

	key_w := f32(200)
	y0 := p.y + 92
	row_h := f32(30)
	for line, i in HELP_LEFT {
		draw_help_row(p.x + 26, y0 + f32(i) * row_h, key_w, line)
	}
	for line, i in HELP_RIGHT {
		draw_help_row(p.x + 500, y0 + f32(i) * row_h, key_w, line)
	}

	hint := cstring("K / Esc to close")
	hw := measure_text(hint, 16)
	draw_text(hint, i32(p.x + p.width / 2) - hw / 2, i32(p.y + p.height) - 30, 16, rl.Color{150, 150, 170, 255})
}

draw_help_row :: proc(x, y, key_w: f32, line: Help_Line) {
	draw_text(line.key, i32(x), i32(y), 16, rl.Color{235, 225, 170, 255})
	draw_text(line.action, i32(x + key_w), i32(y), 15, rl.Color{195, 200, 215, 255})
}

// ----------------------------------------------------------------------------
// Confirmation dialog (Phase 24)
//
// A small modal yes/no for destructive actions (forgetting a card, overwriting a
// building). Enter / click Confirm accepts; Esc / N / Cancel declines.
// ----------------------------------------------------------------------------

Confirm_Kind :: enum { NONE, FORGET_CARD, OVERWRITE_BUILD, DEMOLISH }

confirm_panel_rect :: proc() -> rl.Rectangle {
	sw := f32(rl.GetScreenWidth())
	sh := f32(rl.GetScreenHeight())
	return rl.Rectangle{sw / 2 - 280, sh / 2 - 100, 560, 200}
}

confirm_yes_rect :: proc() -> rl.Rectangle {
	p := confirm_panel_rect()
	return rl.Rectangle{p.x + p.width - 260, p.y + p.height - 66, 110, 46}
}

confirm_no_rect :: proc() -> rl.Rectangle {
	p := confirm_panel_rect()
	return rl.Rectangle{p.x + p.width - 138, p.y + p.height - 66, 110, 46}
}

ask_confirm :: proc(g: ^Game, kind: Confirm_Kind, arg, aux: int, hex: Hex) {
	g.confirm_kind = kind
	g.confirm_int = arg
	g.confirm_aux = aux
	g.confirm_hex = hex
}

confirm_message :: proc(g: ^Game) -> cstring {
	#partial switch g.confirm_kind {
	case .FORGET_CARD:
		if g.confirm_int >= 0 && g.confirm_int < len(g.colony.roster) {
			deck := g.colony.roster[g.confirm_int].creature.deck
			if g.confirm_aux >= 0 && g.confirm_aux < len(deck) {
				id := deck[g.confirm_aux]
				return fmt.ctprintf("Forget %s for %d gold? This cannot be undone.", MOVE_DATA[id].name, forget_card_cost(id))
			}
		}
		return "Forget that card?"
	case .OVERWRITE_BUILD:
		return fmt.ctprintf("Replace the building here with %s? Anything stored is lost.", improvement_name(Improvement(g.confirm_int)))
	case .DEMOLISH:
		if t := tile_at(&g.colony, g.confirm_hex); t != nil {
			im := t.overlay != .NONE ? t.overlay : t.improvement
			return fmt.ctprintf("Demolish %s here? You get %dg back.", improvement_name(im), improvement_refund(im))
		}
		return "Demolish this?"
	case .NONE:
	}
	return ""
}

update_confirm :: proc(g: ^Game) {
	yes := rl.IsKeyPressed(.ENTER) || rl.IsKeyPressed(.KP_ENTER)
	no := rl.IsKeyPressed(.ESCAPE) || rl.IsKeyPressed(.N)
	if rl.IsMouseButtonPressed(.LEFT) {
		mp := rl.GetMousePosition()
		if rl.CheckCollisionPointRec(mp, confirm_yes_rect()) {
			yes = true
		}
		if rl.CheckCollisionPointRec(mp, confirm_no_rect()) {
			no = true
		}
	}
	if no {
		g.confirm_kind = .NONE
		return
	}
	if !yes {
		return
	}
	#partial switch g.confirm_kind {
	case .FORGET_CARD:
		switch colony_forget_card(&g.colony, g.confirm_int, g.confirm_aux) {
		case 0: set_status(g, "Card forgotten.")
		case 2: set_status(g, "Not enough gold.")
		case 3: set_status(g, "A deck must keep at least one card.")
		}
	case .OVERWRITE_BUILD:
		switch colony_build(&g.colony, g.confirm_hex, Improvement(g.confirm_int)) {
		case 0:
			audio_play(.BUILD)
			set_status(g, "Improvement replaced.")
		case 3:
			audio_play(.ERROR)
			set_status(g, "Not enough gold.")
		case:
			audio_play(.ERROR)
			set_status(g, "Can't build there.")
		}
	case .DEMOLISH:
		res, _ := colony_demolish(&g.colony, g.confirm_hex)
		switch res {
		case 0:
			audio_play(.BUILD)
			set_status(g, "Demolished.")
		case:
			set_status(g, "Nothing to demolish.")
		}
	case .NONE:
	}
	g.confirm_kind = .NONE
}

draw_confirm :: proc(g: ^Game) {
	if g.confirm_kind == .NONE {
		return
	}
	sw := f32(rl.GetScreenWidth())
	sh := f32(rl.GetScreenHeight())
	rl.DrawRectangle(0, 0, i32(sw), i32(sh), rl.Color{0, 0, 0, 175})
	p := confirm_panel_rect()
	draw_panel(p, rl.Color{22, 20, 26, 250}, rl.Color{220, 160, 120, 255})
	draw_text("Are you sure?", i32(p.x) + 24, i32(p.y) + 18, 24, rl.Color{245, 220, 200, 255})
	draw_text_wrapped(confirm_message(g), i32(p.x) + 24, i32(p.y) + 60, 16, i32(p.width) - 48, rl.Color{210, 205, 215, 255})
	draw_button(confirm_yes_rect(), cstring("Confirm"), true, BUTTON_GO, 18)
	draw_button(confirm_no_rect(), cstring("Cancel"), true, BUTTON_PANEL, 18)
}

// ----------------------------------------------------------------------------
// Settings panel (Phase 24)
//
// Sound, display toggles, autosave, and a read-out of the last turn (moved here
// from the old pop-up toast).
// ----------------------------------------------------------------------------

settings_panel_rect :: proc() -> rl.Rectangle {
	sw := f32(rl.GetScreenWidth())
	sh := f32(rl.GetScreenHeight())
	w := f32(640)
	h := f32(560)
	return rl.Rectangle{sw / 2 - w / 2, sh / 2 - h / 2, w, h}
}

settings_volume_rect :: proc() -> rl.Rectangle {
	p := settings_panel_rect()
	return rl.Rectangle{p.x + 200, p.y + 196, 340, 14}
}

settings_mute_rect :: proc() -> rl.Rectangle {
	p := settings_panel_rect()
	return rl.Rectangle{p.x + 200, p.y + 222, 170, 38}
}

settings_toggle_rect :: proc(i: int) -> rl.Rectangle {
	p := settings_panel_rect()
	return rl.Rectangle{p.x + 200, p.y + 300 + f32(i) * 46, 170, 38}
}

settings_autosave_rect :: proc() -> rl.Rectangle {
	p := settings_panel_rect()
	return rl.Rectangle{p.x + 200, p.y + 474, 170, 38}
}

update_settings :: proc(g: ^Game) {
	if rl.IsKeyPressed(.P) || rl.IsKeyPressed(.ESCAPE) {
		g.show_settings = false
		return
	}
	mp := rl.GetMousePosition()

	// Volume slider: click or drag anywhere on the bar.
	vr := settings_volume_rect()
	if rl.IsMouseButtonDown(.LEFT) && rl.CheckCollisionPointRec(mp, rl.Rectangle{vr.x - 8, vr.y - 10, vr.width + 16, vr.height + 20}) {
		audio_set_volume(clamp((mp.x - vr.x) / vr.width, 0, 1))
		return
	}
	if !rl.IsMouseButtonPressed(.LEFT) {
		return
	}
	if rl.CheckCollisionPointRec(mp, settings_mute_rect()) {
		_ = audio_toggle_mute()
		return
	}
	if rl.CheckCollisionPointRec(mp, settings_toggle_rect(0)) { g.show_minimap = !g.show_minimap; return }
	if rl.CheckCollisionPointRec(mp, settings_toggle_rect(1)) { g.tooltips_on = !g.tooltips_on; return }
	if rl.CheckCollisionPointRec(mp, settings_toggle_rect(2)) { g.show_fps = !g.show_fps; return }
	if rl.CheckCollisionPointRec(mp, settings_autosave_rect()) { g.autosave_on = !g.autosave_on; return }
}

draw_settings :: proc(g: ^Game) {
	sw := f32(rl.GetScreenWidth())
	sh := f32(rl.GetScreenHeight())
	rl.DrawRectangle(0, 0, i32(sw), i32(sh), rl.Color{8, 10, 16, 246})

	p := settings_panel_rect()
	draw_panel(p, rl.Color{18, 20, 28, 248}, rl.Color{150, 170, 220, 255})
	draw_text("SETTINGS", i32(p.x) + 26, i32(p.y) + 16, 30, rl.Color{220, 228, 245, 255})

	// Last turn read-out.
	draw_text("LAST TURN", i32(p.x) + 26, i32(p.y) + 62, 15, rl.Color{150, 160, 185, 255})
	if len(g.summary) == 0 {
		draw_text("No turns played yet.", i32(p.x) + 200, i32(p.y) + 62, 15, rl.Color{140, 140, 160, 255})
	} else {
		for s, i in g.summary {
			draw_text(fmt.ctprintf("%s", s), i32(p.x) + 200, i32(p.y) + 62 + i32(i) * 20, 15, rl.Color{200, 205, 220, 255})
		}
	}

	// Sound.
	draw_text("SOUND", i32(p.x) + 26, i32(p.y) + 170, 15, rl.Color{150, 160, 185, 255})
	vr := settings_volume_rect()
	rl.DrawRectangleRounded(vr, 0.5, 4, rl.Color{40, 40, 52, 255})
	frac := clamp(audio.volume, 0, 1)
	if frac > 0 {
		rl.DrawRectangleRounded(rl.Rectangle{vr.x, vr.y, vr.width * frac, vr.height}, 0.5, 4, rl.Color{120, 180, 235, 255})
	}
	rl.DrawCircleV(rl.Vector2{vr.x + vr.width * frac, vr.y + vr.height / 2}, 9, rl.Color{220, 232, 245, 255})
	draw_text(fmt.ctprintf("Volume %d%%", int(frac * 100)), i32(p.x) + 200, i32(p.y) + 170, 15, rl.Color{200, 205, 220, 255})
	draw_button(settings_mute_rect(), audio.muted ? cstring("Sound: MUTED") : cstring("Sound: ON"), true, BUTTON_PANEL, 16)

	// Display.
	draw_text("DISPLAY", i32(p.x) + 26, i32(p.y) + 276, 15, rl.Color{150, 160, 185, 255})
	draw_button(settings_toggle_rect(0), fmt.ctprintf("Minimap: %s", g.show_minimap ? "ON" : "OFF"), true, BUTTON_PANEL, 16)
	draw_button(settings_toggle_rect(1), fmt.ctprintf("Tooltips: %s", g.tooltips_on ? "ON" : "OFF"), true, BUTTON_PANEL, 16)
	draw_button(settings_toggle_rect(2), fmt.ctprintf("FPS counter: %s", g.show_fps ? "ON" : "OFF"), true, BUTTON_PANEL, 16)

	// Autosave.
	draw_text("AUTOSAVE", i32(p.x) + 26, i32(p.y) + 448, 15, rl.Color{150, 160, 185, 255})
	draw_button(settings_autosave_rect(), fmt.ctprintf("Autosave: %s", g.autosave_on ? "ON" : "OFF"), true, BUTTON_PANEL, 16)
	draw_text(fmt.ctprintf("every %d turns", AUTOSAVE_EVERY), i32(p.x) + 384, i32(p.y) + 484, 14, rl.Color{150, 150, 170, 255})

	hint := cstring("P / Esc to close")
	hw := measure_text(hint, 16)
	draw_text(hint, i32(p.x + p.width / 2) - hw / 2, i32(p.y + p.height) - 28, 16, rl.Color{150, 150, 170, 255})
}

// ----------------------------------------------------------------------------
// Relics panel (Phase 25)
// ----------------------------------------------------------------------------

relic_panel_rect :: proc() -> rl.Rectangle {
	sw := f32(rl.GetScreenWidth())
	sh := f32(rl.GetScreenHeight())
	w := f32(780)
	h := f32(584)
	return rl.Rectangle{sw / 2 - w / 2, sh / 2 - h / 2, w, h}
}

relic_row_rect :: proc(i: int) -> rl.Rectangle {
	p := relic_panel_rect()
	return rl.Rectangle{p.x + 20, p.y + 96 + f32(i) * 44, p.width - 40, 40}
}

update_relics :: proc(g: ^Game) {
	if rl.IsKeyPressed(.ESCAPE) || rl.IsKeyPressed(.J) {
		g.show_relics = false
	}
}

draw_relics :: proc(g: ^Game) {
	sw := f32(rl.GetScreenWidth())
	sh := f32(rl.GetScreenHeight())
	rl.DrawRectangle(0, 0, i32(sw), i32(sh), rl.Color{8, 10, 16, 245})

	p := relic_panel_rect()
	rl.DrawRectangleRounded(p, 0.03, 8, rl.Color{20, 18, 26, 248})
	rl.DrawRectangleRoundedLinesEx(p, 0.03, 8, 3, rl.Color{235, 195, 110, 255})
	draw_text("RELICS", i32(p.x) + 24, i32(p.y) + 16, 30, rl.Color{245, 220, 150, 255})
	total := relic_total(&g.colony)
	draw_text(fmt.ctprintf("%d relic%s owned  -  colony-wide passives dropped by bosses; they STACK", total, total == 1 ? "" : "s"),
		i32(p.x) + 24, i32(p.y) + 54, 15, rl.Color{200, 190, 170, 255})

	for r, i in RELIC_ORDER {
		rec := relic_row_rect(i)
		n := g.colony.relics[r]
		owned := n > 0
		gold := rl.Color{240, 205, 120, 255}
		dim := rl.Color{60, 62, 76, 255}
		// Shader panel: gold foil when owned, dim slate otherwise.
		if !shader_panel(rec, owned ? rl.Color{126, 96, 32, 255} : rl.Color{40, 42, 52, 255}, owned ? gold : dim, owned ? 0.55 : 0, 0) {
			rl.DrawRectangleRounded(rec, 0.12, 6, owned ? rl.Color{44, 36, 20, 255} : rl.Color{24, 24, 30, 255})
			rl.DrawRectangleRoundedLinesEx(rec, 0.12, 6, 2, owned ? gold : dim)
		}
		// Gem.
		gc := rl.Vector2{rec.x + 22, rec.y + rec.height / 2}
		rl.DrawPoly(gc, 4, 12, 0, owned ? rl.Color{126, 96, 32, 255} : rl.Color{34, 34, 42, 255})
		rl.DrawPolyLinesEx(gc, 4, 12, 0, 2, owned ? gold : dim)
		rl.DrawPoly(rl.Vector2{gc.x, gc.y - 4}, 4, 4.5, 0, owned ? rl.Color{255, 240, 190, 220} : rl.Color{48, 48, 58, 255})
		draw_text(relic_name(r), i32(rec.x) + 44, i32(rec.y) + 5, 17, owned ? rl.Color{255, 246, 216, 255} : rl.Color{150, 150, 165, 255})
		draw_text(relic_desc(r), i32(rec.x) + 44, i32(rec.y) + 24, 12, rl.Color{190, 184, 194, 255})
		owned_txt := fmt.ctprintf("x%d", n)
		ow := measure_text(owned_txt, 18)
		draw_text(owned_txt, i32(rec.x + rec.width) - 16 - ow, i32(rec.y) + 10, 18, owned ? rl.Color{250, 228, 160, 255} : rl.Color{110, 110, 125, 255})
	}

	hint := cstring("J / Esc to close   -   defeat bosses in Boss Rooms to earn more")
	hw := measure_text(hint, 16)
	draw_text(hint, i32(p.x + p.width / 2) - hw / 2, i32(p.y + p.height) - 28, 16, rl.Color{150, 150, 170, 255})
}
