package main

import rl "vendor:raylib"
import "core:fmt"
import "core:math"
build_panel_rect :: proc() -> rl.Rectangle {
	return rl.Rectangle{20, 150, 360, 540}
}

BUILD_OPT_START     :: f32(96)
BUILD_REPLACE_START :: f32(216)
BUILD_ROW_H         :: f32(40)

build_option_rect_at :: proc(start_y: f32, i: int, scroll: f32 = 0) -> rl.Rectangle {
	p := build_panel_rect()
	col := i % 2
	row := i / 2
	gap := f32(8)
	w := (p.width - 24 - gap) / 2
	return rl.Rectangle{p.x + 12 + f32(col) * (w + gap), p.y + start_y + f32(row) * BUILD_ROW_H - scroll, w, 38}
}

// The scrollable region the option grid is clipped to.
build_options_area :: proc(start_y: f32) -> rl.Rectangle {
	p := build_panel_rect()
	top := p.y + start_y - 6
	return rl.Rectangle{p.x + 6, top, p.width - 12, (p.y + p.height - 34) - top}
}

build_options_rows :: proc(n: int) -> int {
	return (n + 1) / 2
}

build_max_scroll :: proc(start_y: f32, n: int) -> f32 {
	area := build_options_area(start_y)
	content := f32(build_options_rows(n)) * BUILD_ROW_H
	return max(0, content - area.height + 6)
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

	if t.improvement != .NONE || t.overlay != .NONE {
		y := i32(p.y) + 92
		if t.improvement != .NONE {
			rl.DrawText(fmt.ctprintf("Built: %s  (hp %d/%d)", improvement_name(t.improvement), t.improvement_hp, improvement_hp_cap(&g.colony, t.improvement)), i32(p.x) + 16, y, 16, rl.Color{140, 220, 150, 255})
			y += 22
		}
		if t.overlay != .NONE {
			rl.DrawText(fmt.ctprintf("Overlay: %s  (hp %d/%d)", improvement_name(t.overlay), t.overlay_hp, improvement_max_hp(t.overlay)), i32(p.x) + 16, y, 16, rl.Color{150, 210, 235, 255})
			y += 22
		}

		// Repair + demolish, side by side.
		rim, rhp, rcap := tile_repair_target(&g.colony, t)
		can_repair := rim != .NONE
		rcost := can_repair ? improvement_repair_cost(&g.colony, rim, rhp) : 0
		afford := can_repair && colony_total_gold(&g.colony) >= rcost
		rep := build_repair_rect()
		draw_button(rep, can_repair ? fmt.ctprintf("Repair %dg", rcost) : cstring("Full HP"), afford, BUTTON_PANEL, 15)
		if rl.CheckCollisionPointRec(mouse_pos(), rep) {
			tooltip_set("%s", can_repair ? fmt.ctprintf("Repair to %d HP for %dg.", rcap, rcost) : cstring("Already at full HP."))
		}
		dem := build_demolish_rect()
		refund := improvement_refund(t.overlay != .NONE ? t.overlay : t.improvement)
		draw_button(dem, fmt.ctprintf("Demolish +%dg", refund), true, BUTTON_PANEL, 15)
		if rl.CheckCollisionPointRec(mouse_pos(), dem) {
			tooltip_set("Tear this down and refund %dg (half its base cost).", refund)
		}

		// You can overwrite a built improvement, or add a stackable overlay.
		opts: [32]Improvement
		n := buildable_improvements(&g.colony, g.build_hex, opts[:])
		if n > 0 {
			rl.DrawText("Add / replace:", i32(p.x) + 16, i32(p.y) + 196, 15, rl.Color{150, 150, 170, 255})
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
	area := build_options_area(start_y)
	mp := mouse_pos()
	in_area := rl.CheckCollisionPointRec(mp, area)
	hovered := Improvement.NONE
	scissor_begin(area)
	for i in 0..<n {
		im := opts[i]
		rec := build_option_rect_at(start_y, i, g.build_scroll)
		if rec.y + rec.height < area.y || rec.y > area.y + area.height {
			continue
		}
		cost := improvement_cost_scaled(&g.colony, im)
		afford := colony_total_gold(&g.colony) >= cost
		hover := in_area && rl.CheckCollisionPointRec(mp, rec)
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
		rl.DrawText(fmt.ctprintf("%d hp", improvement_hp_cap(&g.colony, im)), i32(rec.x) + 8, i32(rec.y) + 23, 11, rl.Color{150, 150, 170, 255})
		if improvement_stacks(im) {
			tag := cstring("+stack")
			tw := rl.MeasureText(tag, 11)
			rl.DrawText(tag, i32(rec.x + rec.width) - 8 - tw, i32(rec.y) + 23, 11, rl.Color{130, 210, 235, 255})
		}
		if hover {
			tooltip_set("%s  -  %s\n%s", improvement_name(im), improvement_effect(im), improvement_detail(im))
		}
	}
	scissor_end()
	g.build_preview = hovered

	// Scrollbar when the list is longer than the visible area.
	if max_s := build_max_scroll(start_y, n); max_s > 0 {
		track := rl.Rectangle{area.x + area.width - 6, area.y, 4, area.height}
		rl.DrawRectangleRounded(track, 0.5, 4, rl.Color{30, 32, 44, 220})
		kh := max(area.height * area.height / (area.height + max_s), 24)
		ky := area.y + (area.height - kh) * (g.build_scroll / max_s)
		rl.DrawRectangleRounded(rl.Rectangle{track.x, ky, 4, kh}, 0.5, 4, rl.Color{120, 130, 160, 235})
	}

	// Hovered improvement's effect, along the bottom of the panel.
	p := build_panel_rect()
	if hovered != .NONE {
		rl.DrawText(improvement_effect(hovered), i32(p.x) + 12, i32(p.y + p.height) - 26, 12, rl.Color{175, 175, 195, 255})
	}
}

trade_panel_rect :: proc() -> rl.Rectangle {
	sw := f32(screen_w())
	sh := f32(screen_h())
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
	hover := rl.CheckCollisionPointRec(mouse_pos(), rec)
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
	hover := rl.CheckCollisionPointRec(mouse_pos(), rec)
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
	sw := f32(screen_w())
	sh := f32(screen_h())
	rl.DrawRectangle(0, 0, i32(sw), i32(sh), rl.Color{0, 0, 0, 160})

	p := trade_panel_rect()
	draw_panel(p, rl.Color{20, 20, 30, 245}, rl.Color{180, 160, 90, 255}, 0.05, 8, 2)
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
	if rl.CheckCollisionPointRec(mouse_pos(), trade_heal_rect()) {
		tooltip_set("Heal the selected monster to full HP. The price scales with the HP it is missing.")
	}

	ec := have_sel ? energy_cost(&g.colony.roster[s]) : 0
	draw_trade_button(trade_energy_rect(), cstring("Refill movement energy"), have_sel && colony_total_gold(&g.colony) >= ec, have_sel ? fmt.ctprintf("%dg", ec) : "")
	if rl.CheckCollisionPointRec(mouse_pos(), trade_energy_rect()) {
		tooltip_set("Top the selected monster's movement energy back up to its bank. Energy is shared with battle.")
	}

	ccost := capture_card_cost()
	draw_trade_button(trade_capture_rect(), fmt.ctprintf("Buy Capture Card (have %d)", g.colony.capture_cards), colony_total_gold(&g.colony) >= ccost, fmt.ctprintf("%dg", ccost))
	if rl.CheckCollisionPointRec(mouse_pos(), trade_capture_rect()) {
		tooltip_set("Capture cards let you recruit a wild mid-battle instead of defeating it. Scout upgrades improve the odds.")
	}

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

// Screen rectangle of deck card `i` in the deck viewer, honouring scroll.
deck_card_rect :: proc(g: ^Game, i: int) -> rl.Rectangle {
	sw := f32(screen_w())
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
	visible := f32(screen_h()) - DV_TOP - DV_BOTTOM
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
	// Item slot: the old button silently took `items[0]`, which is why gearing
	// read as "there is just an Equip option". It hands off to the inventory
	// instead, where the item is actually chosen.
	if !m.wild && rl.IsMouseButtonPressed(.LEFT) {
		mp := mouse_pos()
		if rl.CheckCollisionPointRec(mp, deck_equip_rect()) {
			g.selected = g.view_index
			open_inventory(g, arena = g.mode == .ARENA)
			return
		}
		if rl.CheckCollisionPointRec(mp, deck_unequip_rect()) && m.creature.item != .NONE {
			bag := g.mode == .ARENA ? &g.colony.arena_items : &g.colony.items
			append(bag, m.creature.item)
			creature_equip_item(&m.creature, .NONE)
		}
	}
	// Right-click a card to forget it (deck thinning) for gold — with a confirm.
	if !m.wild && rl.IsMouseButtonPressed(.RIGHT) {
		mp := mouse_pos()
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
	sw := f32(screen_w())
	return rl.Rectangle{sw - 330, 30, 290, 42}
}

deck_unequip_rect :: proc() -> rl.Rectangle {
	sw := f32(screen_w())
	return rl.Rectangle{sw - 330, 78, 290, 42}
}

draw_deck_viewer :: proc(g: ^Game) {
	sw := f32(screen_w())
	sh := f32(screen_h())
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
	gene_line := fmt.ctprintf("Genes: %s   (total %d)", genes_label(c.genes), genes_total(c.genes))
	rl.DrawText(gene_line, 40, 134, 16, rl.Color{170, 210, 230, 255})
	pager := fmt.ctprintf("monster %d / %d   -   Left/Right or Q/E to switch", g.view_index + 1, len(g.colony.roster))
	rl.DrawText(pager, 40, 154, 16, rl.Color{150, 150, 170, 255})

	// Item slot + bag.
	m := &g.colony.roster[g.view_index]
	can_gear := !m.wild
	bag_n := len(g.colony.items)
	if g.mode == .ARENA {
		bag_n = len(g.colony.arena_items)
	}
	draw_button(deck_equip_rect(), fmt.ctprintf("Change item   (bag: %d)", bag_n), can_gear)
	draw_button(deck_unequip_rect(), cstring("Unequip"), can_gear && c.item != .NONE)

	n := len(c.deck)
	mp := mouse_pos()

	// Leave headroom above the grid so a hovered (lifted) top-row card is not
	// clipped by the scissor region.
	clip_top := i32(DV_TOP) - 36
	clip_bottom := i32(sh - DV_BOTTOM) + 8
	scissor_begin(rl.Rectangle{0, f32(clip_top), sw, f32(clip_bottom - clip_top)})
	for i in 0..<n {
		rec := deck_card_rect(g, i)
		if rec.y + DV_CH < f32(clip_top) - 4 || rec.y > f32(clip_bottom) + 4 {
			continue
		}
		hovered := rl.CheckCollisionPointRec(mp, rec)
		draw_card(c.deck[i], rec, true, hovered)
	}
	scissor_end()

	hint := cstring("V / Esc close   |   wheel or Up/Down scroll   |   right-click a card to forget it (gold)")
	hw := rl.MeasureText(hint, 16)
	rl.DrawText(hint, i32(sw) / 2 - hw / 2, i32(sh) - 32, 16, rl.Color{140, 140, 160, 255})
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
	hover := rl.CheckCollisionPointRec(mouse_pos(), rec)
	if si < 0 {
		rl.DrawRectangleRounded(rec, 0.18, 4, rl.Color{24, 24, 30, 255})
		rl.DrawRectangleRoundedLinesEx(rec, 0.18, 4, 1.5, rl.Color{70, 70, 82, 255})
		rl.DrawText(empty_label, i32(rec.x) + 10, i32(rec.y) + 7, 14, rl.Color{120, 120, 140, 255})
		return
	}
	m := &c.storage[si]
	bg := hover ? rl.Color{44, 58, 50, 255} : rl.Color{28, 36, 32, 255}
	rl.DrawRectangleRounded(rec, 0.18, 4, bg)
	rl.DrawRectangleRoundedLinesEx(rec, 0.18, 4, 1.5, col)
	rl.DrawText(fmt.ctprintf("Lvl %d  %s", m.creature.level, m.creature.name), i32(rec.x) + 10, i32(rec.y) + 7, 15, rl.Color{225, 235, 225, 255})
	aw := rl.MeasureText(action, 13)
	rl.DrawText(action, i32(rec.x + rec.width) - 10 - aw, i32(rec.y) + 8, 13, rl.Color{230, 200, 200, 255})
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
	mp := mouse_pos()
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
	sw := f32(screen_w())
	sh := f32(screen_h())
	rl.DrawRectangle(0, 0, i32(sw), i32(sh), rl.Color{0, 0, 0, 205})

	rl.DrawText(cstring("Nurseries"), 40, 26, 34, rl.Color{235, 235, 245, 255})
	sub := cstring("Move two nearby monsters of the same species (Lvl 5+) in as the breeding pair. A fed Nursery hatches a level 1 baby every 8 turns, up to 4 stored.")
	rl.DrawText(sub, 40, 68, 16, rl.Color{180, 190, 210, 255})

	n := nursery_count(&g.colony)
	rl.DrawText(fmt.ctprintf("Your Nurseries (%d):", n), 40, 118, 16, rl.Color{150, 150, 170, 255})

	mp := mouse_pos()
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
		rl.DrawText(fmt.ctprintf("Nursery (%d,%d)  pair %d/%d  babies %d/%d  %d/%d", hex.q, hex.r, p, NURSERY_PARENTS, b, NURSERY_BABIES, prog, NURSERY_PERIOD), i32(rec.x) + 10, i32(rec.y) + 6, 15, rl.Color{225, 230, 240, 255})
	}

	if n == 0 {
		rl.DrawText(cstring("No Nurseries yet - build one with B (Cave/Grove/Mushroom/Jungle)."), 40, 154, 16, rl.Color{210, 180, 180, 255})
		hint := cstring("C / Esc close")
		hw := rl.MeasureText(hint, 16)
		rl.DrawText(hint, i32(sw) / 2 - hw / 2, i32(sh) - 28, 16, rl.Color{140, 140, 160, 255})
		return
	}

	hex := nursery_hex_at(&g.colony, g.nursery_sel)

	rl.DrawText(cstring("Breeding pair (click to remove):"), 410, 118, 16, rl.Color{190, 220, 200, 255})
	for i in 0..<NURSERY_PARENTS {
		si := stored_slot_index(&g.colony, hex, .NURSERY_PARENT, i)
		draw_stored_slot(nursery_slot_rect(.NURSERY_PARENT, i), &g.colony, si, cstring("Empty - add a nearby monster"), cstring("Remove"), rl.Color{140, 220, 160, 255})
	}
	rl.DrawText(cstring("Babies (click to take):"), 410, 258, 16, rl.Color{210, 200, 160, 255})
	for i in 0..<NURSERY_BABIES {
		si := stored_slot_index(&g.colony, hex, .NURSERY_BABY, i)
		draw_stored_slot(nursery_slot_rect(.NURSERY_BABY, i), &g.colony, si, cstring("Empty"), cstring("Take"), rl.Color{230, 210, 150, 255})
	}

	rl.DrawText(cstring("Add a parent - nearby monsters (within 1, Lvl 5+, same species):"), 800, 140, 16, rl.Color{180, 190, 210, 255})
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
		rl.DrawText(fmt.ctprintf("Lvl %d  %s", m.creature.level, m.creature.name), i32(rec.x) + 10, i32(rec.y) + 5, 15, ok ? rl.Color{225, 235, 225, 255} : rl.Color{150, 145, 150, 255})
		gl := genes_label(m.creature.genes)
		gw := rl.MeasureText(gl, 13)
		rl.DrawText(gl, i32(rec.x + rec.width) - 10 - gw, i32(rec.y) + 6, 13, rl.Color{170, 200, 220, 255})
		cand += 1
	}
	if cand == 0 {
		rl.DrawText(cstring("No monsters next to this Nursery."), 800, 184, 15, rl.Color{150, 150, 170, 255})
	}

	hint := cstring("Click a Nursery, then a nearby monster to add it   |   C / Esc close")
	hw := rl.MeasureText(hint, 16)
	rl.DrawText(hint, i32(sw) / 2 - hw / 2, i32(sh) - 28, 16, rl.Color{140, 140, 160, 255})
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
	mp := mouse_pos()
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
	sw := f32(screen_w())
	sh := f32(screen_h())
	rl.DrawRectangle(0, 0, i32(sw), i32(sh), rl.Color{0, 0, 0, 205})

	rl.DrawText(cstring("Monster Storage"), 40, 26, 34, rl.Color{235, 235, 245, 255})
	sub := cstring("Walk a monster next to a Den, then click it here to put it in stasis: no food upkeep, no heat, off the map. Up to 32 per Den.")
	rl.DrawText(sub, 40, 68, 16, rl.Color{180, 190, 210, 255})

	n := den_count(&g.colony)
	rl.DrawText(fmt.ctprintf("Your Dens (%d):", n), 40, 118, 16, rl.Color{150, 150, 170, 255})

	mp := mouse_pos()
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
		rl.DrawText(fmt.ctprintf("Den (%d,%d)   %d/%d", hex.q, hex.r, den_occupancy(&g.colony, hex), den_capacity(&g.colony)), i32(rec.x) + 10, i32(rec.y) + 6, 15, rl.Color{225, 230, 240, 255})
	}

	if n == 0 {
		rl.DrawText(cstring("No Dens yet - build one with B (Cave/Grove/Ruins/Mushroom/Desert)."), 40, 154, 16, rl.Color{210, 180, 180, 255})
		hint := cstring("H / Esc close")
		hw := rl.MeasureText(hint, 16)
		rl.DrawText(hint, i32(sw) / 2 - hw / 2, i32(sh) - 28, 16, rl.Color{140, 140, 160, 255})
		return
	}

	hex := den_hex_at(&g.colony, g.storage_sel)

	rl.DrawText(cstring("Nearby (within 1) - click to store:"), 410, 150, 16, rl.Color{190, 220, 200, 255})
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
		rl.DrawText(fmt.ctprintf("Lvl %d  %s", m.creature.level, m.creature.name), i32(rec.x) + 10, i32(rec.y) + 5, 15, rl.Color{225, 235, 225, 255})
		near += 1
	}
	if near == 0 {
		rl.DrawText(cstring("No monsters next to this Den."), 410, 184, 15, rl.Color{150, 150, 170, 255})
	}

	rl.DrawText(fmt.ctprintf("In stasis (%d/%d) - click to deploy:", den_occupancy(&g.colony, hex), den_capacity(&g.colony)), 820, 150, 16, rl.Color{210, 200, 160, 255})
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
		rl.DrawText(fmt.ctprintf("Lvl %d  %s", m.creature.level, m.creature.name), i32(rec.x) + 10, i32(rec.y) + 5, 15, rl.Color{220, 225, 235, 255})
		hold += 1
	}
	if hold == 0 {
		rl.DrawText(cstring("Nothing stored here."), 820, 184, 15, rl.Color{150, 150, 170, 255})
	}

	hint := cstring("Click a Den, then a nearby monster to store it, or a stored one to deploy   |   H / Esc close")
	hw := rl.MeasureText(hint, 16)
	rl.DrawText(hint, i32(sw) / 2 - hw / 2, i32(sh) - 28, 16, rl.Color{140, 140, 160, 255})
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
	sw := f32(screen_w())
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
	mp := mouse_pos()

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
	mp := mouse_pos()
	armed := g.new_run_armed > 0
	hover := rl.CheckCollisionPointRec(mp, rec)
	bg := armed ? rl.Color{96, 44, 40, 255} : (hover ? rl.Color{52, 62, 84, 255} : rl.Color{28, 32, 44, 255})
	border := armed ? rl.Color{235, 130, 110, 255} : (hover ? rl.Color{150, 180, 235, 255} : rl.Color{84, 94, 120, 255})
	rl.DrawRectangleRounded(rec, 0.2, 8, bg)
	rl.DrawRectangleRoundedLinesEx(rec, 0.2, 8, 2, border)
	label := armed ? cstring("Confirm?  click or press N") : cstring("New Run  (N)")
	w := rl.MeasureText(label, 22)
	rl.DrawText(label, i32(rec.x + rec.width / 2) - w / 2, i32(rec.y + rec.height / 2) - 12, 22, armed ? rl.Color{255, 210, 200, 255} : rl.Color{210, 220, 240, 255})
}

draw_save_panel :: proc(g: ^Game) {
	sw := f32(screen_w())
	sh := f32(screen_h())
	rl.DrawRectangle(0, 0, i32(sw), i32(sh), rl.Color{0, 0, 0, 210})

	rl.DrawText(cstring("Save / Load"), 120, 40, 34, rl.Color{235, 235, 245, 255})
	if g.mode == .MAP {
		rl.DrawText(cstring("F quick-saves slot 1   |   N: new run   |   O / Esc to close"), 120, 86, 16, rl.Color{160, 170, 190, 255})
	} else {
		rl.DrawText(cstring("Choose a slot to load   |   N: new run   |   Esc to go back"), 120, 86, 16, rl.Color{160, 170, 190, 255})
	}

	draw_new_run_button(g)

	if !save_supported() {
		rl.DrawText(cstring("Saving is not available in the browser build."), 120, 180, 18, rl.Color{220, 170, 170, 255})
		return
	}

	mp := mouse_pos()
	for slot in 0 ..< SAVE_SLOTS {
		rec := save_slot_rect(slot)
		meta := save_read_meta(slot)
		hover := rl.CheckCollisionPointRec(mp, rec)
		bg := hover ? rl.Color{30, 34, 44, 255} : rl.Color{22, 24, 32, 255}
		rl.DrawRectangleRounded(rec, 0.06, 6, bg)
		rl.DrawRectangleRoundedLinesEx(rec, 0.06, 6, 2, rl.Color{70, 78, 96, 255})

		rl.DrawText(fmt.ctprintf("Slot %d", slot + 1), i32(rec.x) + 20, i32(rec.y) + 12, 22, rl.Color{220, 226, 240, 255})

		if meta.exists {
			buf: [32]u8
			age := save_age_label(meta.saved_at, buf[:])
			info := fmt.ctprintf("Turn %d   Gold %d   Monsters %d   Crystals %d", meta.turn, meta.gold, meta.monsters, meta.crystals)
			rl.DrawText(info, i32(rec.x) + 20, i32(rec.y) + 46, 16, rl.Color{180, 195, 215, 255})
			rl.DrawText(fmt.ctprintf("%s", age), i32(rec.x) + 20, i32(rec.y) + 68, 14, rl.Color{140, 150, 170, 255})
		} else {
			rl.DrawText(cstring("Empty"), i32(rec.x) + 20, i32(rec.y) + 46, 16, rl.Color{130, 130, 150, 255})
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
		rl.DrawText(cstring("Autosave"), i32(rec.x) + 20, i32(rec.y) + 12, 22, rl.Color{205, 240, 210, 255})
		rl.DrawText(fmt.ctprintf("auto-written every %d turns", AUTOSAVE_EVERY), i32(rec.x) + 170, i32(rec.y) + 18, 14, rl.Color{140, 165, 150, 255})
		if meta.exists {
			buf: [32]u8
			age := save_age_label(meta.saved_at, buf[:])
			info := fmt.ctprintf("Turn %d   Gold %d   Monsters %d   Crystals %d", meta.turn, meta.gold, meta.monsters, meta.crystals)
			rl.DrawText(info, i32(rec.x) + 20, i32(rec.y) + 46, 16, rl.Color{180, 205, 190, 255})
			rl.DrawText(fmt.ctprintf("%s", age), i32(rec.x) + 20, i32(rec.y) + 68, 14, rl.Color{140, 150, 170, 255})
		} else {
			rl.DrawText(cstring("Empty"), i32(rec.x) + 20, i32(rec.y) + 46, 16, rl.Color{130, 130, 150, 255})
		}
		draw_button(save_slot_load_rect(AUTOSAVE_SLOT), cstring("Load"), meta.exists)
	}
}

// ----------------------------------------------------------------------------
// Monster encyclopedia
// ----------------------------------------------------------------------------

ENCY_ROWS :: 21
// Width of one build-column slot in the encyclopedia learnset grid.
LEARN_COL_W :: 128

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
	sh := f32(screen_h())
	draw_list_screen_header("MONSTER ENCYCLOPEDIA", "Up/Down, wheel or click to browse   |   M / Esc to close")

	n := len(SPECIES)

	// Left: the list.
	v := ENCYCLOPEDIA_LIST
	v.index = g.encyclopedia_index
	v.first = g.encyclopedia_first
	panel := rl.Rectangle{30, 108, 320, f32(ENCY_ROWS) * 26 + 12}
	draw_list_chrome(v, n, panel)
	mp := mouse_pos()
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
		rl.DrawText(fmt.ctprintf("%s", sp.name), i32(rec.x) + 30, i32(rec.y) + 4, 16, sel ? rl.Color{235, 245, 235, 255} : rl.Color{200, 200, 215, 255})
		label := elements_label(sp.elements)
		ew := rl.MeasureText(label, 13)
		rl.DrawText(label, i32(rec.x + rec.width) - 12 - ew, i32(rec.y) + 6, 13, element_color(sp.elements[0]))
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
	iw := rl.MeasureText(initial, 36)
	rl.DrawText(initial, i32(dx + 40) - iw / 2, i32(dy + 40) - 18, 36, rl.Color{255, 255, 255, 255})

	rl.DrawText(fmt.ctprintf("%s", sp.name), i32(dx + 96), i32(dy) + 6, 30, rl.Color{235, 235, 245, 255})
	type_label := elements_label(sp.elements)
	rl.DrawText(type_label, i32(dx + 96), i32(dy) + 44, 20, element_color(sp.elements[0]))
	rl.DrawText(fmt.ctprintf("Role: %s", role_name(sp.role)), i32(dx + 96), i32(dy) + 70, 16, rl.Color{170, 170, 190, 255})
	rl.DrawText(rarity_name(sp.rarity), i32(dx + 210), i32(dy) + 70, 16, rarity_color(sp.rarity))

	// Evolution chain: the whole line at a glance, current stage highlighted.
	{
		chain, levels, count := evolution_line(Species_Id(g.encyclopedia_index))
		cx := i32(dx)
		cy := i32(dy) + 92
		if count > 1 {
			for i in 0 ..< count {
				stage := SPECIES[chain[i]]
				cur := chain[i] == Species_Id(g.encyclopedia_index)
				nm := fmt.ctprintf("%s", stage.name)
				w := rl.MeasureText(nm, 15)
				rl.DrawText(nm, cx, cy, 15, cur ? rl.Color{255, 255, 255, 255} : rl.Color{150, 220, 180, 255})
				cx += w
				if i < count - 1 {
					arrow := fmt.ctprintf("  >%d  ", levels[i + 1])
					aw := rl.MeasureText(arrow, 15)
					rl.DrawText(arrow, cx, cy, 15, rl.Color{150, 150, 170, 255})
					cx += aw
				}
			}
		} else {
			rl.DrawText("No evolution line", cx, cy, 15, rl.Color{120, 120, 140, 255})
		}
	}

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

	// Learnset by level. The three cards offered at a level are the build
	// columns, so they share a row — the whole menu fits in a few lines.
	lx := i32(760)
	ly := i32(dy) + 112
	rl.DrawText("LEARNSET  (one per level)", lx, ly - 28, 16, rl.Color{150, 150, 170, 255})
	{
		i := 0
		for i < len(sp.learnset) {
			lvl := sp.learnset[i].level
			rl.DrawText(fmt.ctprintf("Lvl %d", lvl), lx, ly, 15, rl.Color{150, 150, 170, 255})
			cx := lx + LEARN_COL_W / 2
			for i < len(sp.learnset) && sp.learnset[i].level == lvl {
				mv := sp.learnset[i].move
				rl.DrawText(fmt.ctprintf("%s", MOVE_DATA[mv].name), cx, ly, 15, element_color(MOVE_DATA[mv].element))
				cx += LEARN_COL_W
				i += 1
			}
			ly += 20
		}
	}

	// Ability pool: a creature rolls one of these at spawn.
	ly += 12
	rl.DrawText("ABILITIES  (one rolled at spawn)", lx, ly, 16, rl.Color{150, 150, 170, 255})
	ly += 24
	for a in species_abilities(Species_Id(g.encyclopedia_index)) {
		rl.DrawText(fmt.ctprintf("%s - %s", ability_name(a), ability_desc(a)), lx, ly, 15, rl.Color{200, 180, 240, 255})
		ly += 20
	}

	rl.DrawText(fmt.ctprintf("%d species in the underground", n), 40, i32(sh) - 32, 16, rl.Color{130, 130, 150, 255})

	// Dex blurb, under the detail column so it can never collide with the list.
	draw_text_wrapped(fmt.ctprintf("%s", sp.desc), i32(dx), i32(sh) - 96, 16, i32(f32(screen_w()) - dx - 40), rl.Color{190, 190, 212, 255})
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

// A string clipped to a pixel width, with an ellipsis, so a long name can never
// run into the numbers drawn beside it.
fit_text :: proc(text: string, size: i32, max_w: i32) -> cstring {
	if rl.MeasureText(fmt.ctprintf("%s", text), size) <= max_w {
		return fmt.ctprintf("%s", text)
	}
	n := len(text)
	for n > 1 {
		n -= 1
		cand := fmt.ctprintf("%s...", text[:n])
		if rl.MeasureText(cand, size) <= max_w {
			return cand
		}
	}
	return cstring("...")
}

// `fit_text` for a line built with fmt.
fit_textf :: proc(size: i32, max_w: i32, format: string, args: ..any) -> cstring {
	return fit_text(string(fmt.ctprintf(format, ..args)), size, max_w)
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
	sw := f32(screen_w())
	sh := f32(screen_h())
	draw_list_screen_header("IMPROVEMENTS", "Up/Down, wheel or click to browse   |   I / Esc to close")

	n := len(ALL_IMPROVEMENTS)

	// Left: the list.
	v := IMPROVEMENTS_LIST
	v.index = g.improvement_index
	v.first = g.improvement_first
	panel := rl.Rectangle{30, 108, 320, f32(IMPROV_ROWS) * 24 + 12}
	draw_list_chrome(v, n, panel)
	mp := mouse_pos()
	for row in 0 ..< v.rows {
		i := v.first + row
		if i >= n {
			break
		}
		im := ALL_IMPROVEMENTS[i]
		rec := list_row_rect(v, row)
		sel := i == v.index
		draw_list_row_bg(rec, sel, rl.CheckCollisionPointRec(mp, rec))
		rl.DrawText(fmt.ctprintf("%s", improvement_name(im)), i32(rec.x) + 12, i32(rec.y) + 3, 16, sel ? rl.Color{235, 245, 235, 255} : rl.Color{200, 200, 215, 255})
		cat := improvement_category(im)
		cw := rl.MeasureText(cat, 13)
		rl.DrawText(cat, i32(rec.x + rec.width) - 10 - cw, i32(rec.y) + 5, 13, rl.Color{150, 160, 180, 255})
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
	head := fmt.ctprintf("%s   |   Cost %dg   |   HP %d", improvement_category(im), improvement_cost(im), improvement_hp_cap(&g.colony, im))
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
// Move dex
//
// Every card in the game, with a breakdown generated from its own data (see
// `move_lines`), plus who can learn it.
// ----------------------------------------------------------------------------

MOVE_ROWS :: 22

MOVE_LIST :: List_View{rows = MOVE_ROWS, row_h = 24, x = 40, y = 120, w = 340}

// The dex: cards, abilities and items in one browsable reference. Opened with L
// from the map *or* the tower, since looking things up between Arena floors is
// half the point of it.
DEX_TAB_MOVES     :: 0
DEX_TAB_ABILITIES :: 1
DEX_TAB_ITEMS     :: 2
DEX_TABS          :: 3

dex_ability_count :: proc() -> int {
	n := 0
	for a in Ability {
		if a != .NONE {
			n += 1
		}
	}
	return n
}

dex_ability_at :: proc(k: int) -> Ability {
	n := 0
	for a in Ability {
		if a == .NONE {
			continue
		}
		if n == k {
			return a
		}
		n += 1
	}
	return .NONE
}

dex_item_count :: proc() -> int {
	n := 0
	for it in Item {
		if it != .NONE {
			n += 1
		}
	}
	return n
}

dex_item_at :: proc(k: int) -> Item {
	n := 0
	for it in Item {
		if it == .NONE {
			continue
		}
		if n == k {
			return it
		}
		n += 1
	}
	return .NONE
}

// Entries in the tab on show.
dex_count :: proc(g: ^Game) -> int {
	switch g.dex_tab {
	case DEX_TAB_ABILITIES: return dex_ability_count()
	case DEX_TAB_ITEMS:     return dex_item_count()
	case:                   return len(Move_Id)
	}
}

dex_tab_rect :: proc(i: int) -> rl.Rectangle {
	return rl.Rectangle{30 + f32(i) * 150, 62, 142, 34}
}

update_moves :: proc(g: ^Game) {
	if rl.IsKeyPressed(.ESCAPE) || rl.IsKeyPressed(.L) {
		g.show_moves = false
		return
	}
	if rl.IsKeyPressed(.TAB) || rl.IsKeyPressed(.RIGHT) {
		g.dex_tab = (g.dex_tab + 1) % DEX_TABS
		g.dex_index = 0
		g.move_first = 0
	}
	if rl.IsKeyPressed(.LEFT) {
		g.dex_tab = (g.dex_tab + DEX_TABS - 1) % DEX_TABS
		g.dex_index = 0
		g.move_first = 0
	}
	if rl.IsMouseButtonPressed(.LEFT) {
		mp := mouse_pos()
		for i in 0..<DEX_TABS {
			if rl.CheckCollisionPointRec(mp, dex_tab_rect(i)) {
				g.dex_tab = i
				g.dex_index = 0
				g.move_first = 0
				return
			}
		}
	}
	// Up/down (or the wheel) walks whichever list is on show.
	if g.dex_tab == DEX_TAB_MOVES {
		v := MOVE_LIST
		v.index = g.move_index
		v.first = g.move_first
		list_navigate(&v, len(Move_Id))
		g.move_index = v.index
		g.move_first = v.first
	} else {
		n := dex_count(g)
		step := 0
		if rl.IsKeyPressed(.DOWN) { step = 1 }
		if rl.IsKeyPressed(.UP) { step = -1 }
		w := rl.GetMouseWheelMove()
		if w != 0 { step = w > 0 ? -1 : 1 }
		g.dex_index = clamp(g.dex_index + step, 0, max(n - 1, 0))
	}
}

draw_moves :: proc(g: ^Game) {
	sw := f32(screen_w())
	sh := f32(screen_h())
	draw_list_screen_header("DEX", "Tab / Left-Right to switch   |   Up/Down or wheel to browse   |   L / Esc to close")

	// Tabs.
	mp := mouse_pos()
	labels := [DEX_TABS]cstring{"CARDS", "ABILITIES", "ITEMS"}
	for i in 0..<DEX_TABS {
		r := dex_tab_rect(i)
		on := i == g.dex_tab
		hover := rl.CheckCollisionPointRec(mp, r)
		bg := rl.Color{24, 26, 34, 240}
		if on {
			bg = rl.Color{40, 52, 46, 240}
		} else if hover {
			bg = rl.Color{32, 34, 46, 240}
		}
		rl.DrawRectangleRounded(r, 0.24, 6, bg)
		rl.DrawRectangleRoundedLinesEx(r, 0.24, 6, on ? 3 : 2, on ? rl.Color{150, 230, 180, 255} : rl.Color{60, 64, 80, 255})
		lw := rl.MeasureText(labels[i], 15)
		rl.DrawText(labels[i], i32(r.x + r.width / 2) - lw / 2, i32(r.y + r.height / 2) - 8, 15,
			on ? rl.Color{225, 245, 230, 255} : rl.Color{170, 175, 195, 255})
	}

	n := dex_count(g)
	panel := rl.Rectangle{30, 108, 350, f32(MOVE_ROWS) * 24 + 12}

	// ---- the list ----
	first := 0
	index := 0
	if g.dex_tab == DEX_TAB_MOVES {
		v := MOVE_LIST
		v.index = g.move_index
		v.first = g.move_first
		draw_list_chrome(v, n, panel)
		first = v.first
		index = v.index
		for row in 0 ..< v.rows {
			i := v.first + row
			if i >= n { break }
			m := MOVE_DATA[Move_Id(i)]
			rec := list_row_rect(v, row)
			sel := i == v.index
			draw_list_row_bg(rec, sel, rl.CheckCollisionPointRec(mp, rec))
			rl.DrawText(fmt.ctprintf("%s", m.name), i32(rec.x) + 12, i32(rec.y) + 3, 16, sel ? rl.Color{235, 245, 235, 255} : element_color(m.element))
			cost := m.x_cost ? cstring("X") : fmt.ctprintf("%s", fmt_num(m.cost))
			cw := rl.MeasureText(cost, 14)
			rl.DrawText(cost, i32(rec.x + rec.width) - 14 - cw, i32(rec.y) + 5, 14, rl.Color{240, 210, 130, 255})
		}
	} else {
		// The ability and item lists are short enough to show whole.
		index = clamp(g.dex_index, 0, max(n - 1, 0))
		rl.DrawRectangleRounded(panel, 0.03, 8, rl.Color{20, 22, 30, 240})
		rl.DrawRectangleRoundedLinesEx(panel, 0.03, 8, 2, rl.Color{50, 54, 68, 255})
		for i in 0 ..< min(n, MOVE_ROWS) {
			rec := rl.Rectangle{panel.x + 6, panel.y + 6 + f32(i) * 24, panel.width - 12, 22}
			sel := i == index
			draw_list_row_bg(rec, sel, rl.CheckCollisionPointRec(mp, rec))
			col := rl.Color{235, 245, 235, 255}
			name: cstring
			if g.dex_tab == DEX_TAB_ABILITIES {
				a := dex_ability_at(i)
				name = ability_name(a)
				col = rl.Color{200, 180, 240, 255}
			} else {
				it := dex_item_at(i)
				name = item_name(it)
				col = item_color(it)
			}
			rl.DrawText(fmt.ctprintf("%s", name), i32(rec.x) + 12, i32(rec.y) + 2, 16, sel ? rl.Color{235, 245, 235, 255} : col)
		}
		if n == 0 {
			rl.DrawText("(nothing here)", i32(panel.x) + 12, i32(panel.y) + 10, 15, rl.Color{150, 150, 170, 255})
		}
	}

	// ---- the detail ----
	dx := f32(410)
	dy := f32(120)
	right := f32(sw) - 40
	if index < 0 || index >= n {
		rl.DrawText("Nothing selected.", i32(dx), i32(dy), 20, rl.Color{160, 160, 180, 255})
		return
	}

	if g.dex_tab == DEX_TAB_ABILITIES {
		a := dex_ability_at(index)
		rl.DrawText(ability_name(a), i32(dx), i32(dy) + 2, 30, rl.Color{225, 210, 250, 255})
		cy := dy + 48
		cx := dx
		cx += draw_effect_chip(cx, cy, cstring("PASSIVE"), rl.Color{200, 180, 240, 255}) + 8
		cy += 34
		cy = f32(draw_text_wrapped(ability_desc(a), i32(dx), i32(cy), 18, i32(right - dx), rl.Color{210, 210, 225, 255}))
		cy += 20
		rl.DrawText("SPECIES WITH IT", i32(dx), i32(cy), 15, rl.Color{150, 150, 170, 255})
		cy += 24
		buf: [1024]u8
		used, shown, total := 0, 0, 0
		for sid in Species_Id {
			has := false
			for pool in species_abilities(sid) {
				if pool == a {
					has = true
					break
				}
			}
			if !has { continue }
			total += 1
			if shown >= 18 { continue }
			name := SPECIES[sid].name
			if used + len(name) + 3 >= len(buf) { break }
			if shown > 0 {
				buf[used] = ','; buf[used+1] = ' '
				used += 2
			}
			for ch in name {
				buf[used] = u8(ch)
				used += 1
			}
			shown += 1
		}
		buf[used] = 0
		text: cstring
		if total == 0 {
			text = "nothing - boss-only, or unused"
		} else if total > shown {
			text = fmt.ctprintf("%s and %d more", cstring(&buf[0]), total - shown)
		} else {
			text = cstring(&buf[0])
		}
		draw_text_wrapped(text, i32(dx), i32(cy), 15, i32(right - dx), rl.Color{170, 180, 200, 255})
		rl.DrawText(fmt.ctprintf("%d abilities", n), 40, i32(sh) - 32, 16, rl.Color{130, 130, 150, 255})
		return
	}

	if g.dex_tab == DEX_TAB_ITEMS {
		it := dex_item_at(index)
		col := item_color(it)
		draw_item_icon(it, dx + 20, dy + 20, 1.4)
		rl.DrawText(item_name(it), i32(dx) + 58, i32(dy) + 2, 30, rl.Color{235, 235, 245, 255})
		cy := dy + 48
		rl.DrawText("Held item  -  one per monster", i32(dx), i32(cy), 15, col)
		cy += 32
		cy = f32(draw_text_wrapped(item_desc(it), i32(dx), i32(cy), 18, i32(right - dx), rl.Color{210, 210, 225, 255}))
		cy += 12
		rl.DrawText("EFFECTS", i32(dx), i32(cy), 15, rl.Color{150, 150, 170, 255})
		cy += 24
		draw_item_effects(it, i32(dx), i32(cy), 15)
		rl.DrawText(fmt.ctprintf("%d items", n), 40, i32(sh) - 32, 16, rl.Color{130, 130, 150, 255})
		return
	}

	// ---- cards ----
	id := Move_Id(index)
	m := MOVE_DATA[id]
	rl.DrawText(fmt.ctprintf("%s", m.name), i32(dx), i32(dy) + 2, 30, rl.Color{235, 235, 245, 255})
	cy := dy + 44
	cx := dx
	cx += draw_effect_chip(cx, cy, element_name(m.element), element_color(m.element)) + 8
	cx += draw_effect_chip(cx, cy, card_rarity_name(m.rarity), card_rarity_color(m.rarity)) + 8
	cx += draw_effect_chip(cx, cy, card_kind_name(m.kind), card_kind_color(m.kind)) + 8
	cy += 34
	cy = f32(draw_text_wrapped(fmt.ctprintf("%s", m.desc), i32(dx), i32(cy), 18, i32(right - dx), rl.Color{210, 210, 225, 255}))
	cy += 12
	rl.DrawText("EFFECTS", i32(dx), i32(cy), 15, rl.Color{150, 150, 170, 255})
	cy += 24
	ml := move_lines(m)
	for i in 0 ..< ml.n {
		if cy > f32(sh) - 60 { break }
		rl.DrawText(cstring(&ml.bufs[i][0]), i32(dx), i32(cy), 15, rl.Color{195, 200, 215, 255})
		cy += 20
	}
	{
		buf: [768]u8
		used, shown, total := 0, 0, 0
		for sid in Species_Id {
			knows := false
			for mid in SPECIES[sid].move_pool {
				if mid == id {
					knows = true
					break
				}
			}
			if !knows { continue }
			total += 1
			if shown >= 14 { continue }
			name := SPECIES[sid].name
			if used + len(name) + 3 >= len(buf) { break }
			if shown > 0 {
				buf[used] = ','; buf[used+1] = ' '
				used += 2
			}
			for ch in name {
				buf[used] = u8(ch)
				used += 1
			}
			shown += 1
		}
		buf[used] = 0
		text: cstring
		if total == 0 {
			text = "nobody - it only comes from junk cards"
		} else if total > shown {
			text = fmt.ctprintf("%s and %d more", cstring(&buf[0]), total - shown)
		} else {
			text = cstring(&buf[0])
		}
		rl.DrawText("LEARNED BY", i32(dx), i32(sh) - 84, 15, rl.Color{150, 150, 170, 255})
		draw_text_wrapped(text, i32(dx), i32(sh) - 62, 15, i32(right - dx), rl.Color{170, 180, 200, 255})
	}
	rl.DrawText(fmt.ctprintf("%d cards", n), 40, i32(sh) - 32, 16, rl.Color{130, 130, 150, 255})
}

// ----------------------------------------------------------------------------
// Draw one line per active effect field. Returns the next y.
draw_item_effects :: proc(it: Item, x, y: i32, size: i32) -> i32 {
	info := ITEM_DATA[it]
	yy := y
	step := size + 6
	if info.damage_mult != 0 { rl.DrawText(fmt.ctprintf("Damage dealt:   +%d%%", int(info.damage_mult * 100)), x, yy, size, rl.Color{240, 170, 120, 255}); yy += step }
	if info.self_damage_pct != 0 { rl.DrawText(fmt.ctprintf("Recoil:   %d%% of max HP per Attack", int(info.self_damage_pct * 100)), x, yy, size, rl.Color{240, 130, 130, 255}); yy += step }
	if info.super_mult != 0 { rl.DrawText(fmt.ctprintf("Super-effective hits:   +%d%% damage", int(info.super_mult * 100)), x, yy, size, rl.Color{240, 170, 120, 255}); yy += step }
	if info.extra_hits != 0 { rl.DrawText(fmt.ctprintf("Multi-hit Attacks:   +%d hit", info.extra_hits), x, yy, size, rl.Color{240, 170, 120, 255}); yy += step }
	if info.drain_mult != 0 { rl.DrawText(fmt.ctprintf("Drain and lifesteal:   +%d%% healing", int(info.drain_mult * 100)), x, yy, size, rl.Color{200, 150, 240, 255}); yy += step }
	if info.status_bonus != 0 { rl.DrawText(fmt.ctprintf("Poison and Burn:   +%d stack", info.status_bonus), x, yy, size, rl.Color{200, 150, 240, 255}); yy += step }
	if info.thorns != 0 { rl.DrawText(fmt.ctprintf("Battle start:   +%d Thorns", info.thorns), x, yy, size, rl.Color{150, 220, 150, 255}); yy += step }
	if info.turn_heal_pct != 0 { rl.DrawText(fmt.ctprintf("Each turn:   heal %d%% of max HP", int(info.turn_heal_pct * 100)), x, yy, size, rl.Color{140, 230, 150, 255}); yy += step }
	if info.low_hp_heal_pct != 0 { rl.DrawText(fmt.ctprintf("Below half HP:   heal %d%% (once per battle)", int(info.low_hp_heal_pct * 100)), x, yy, size, rl.Color{140, 230, 150, 255}); yy += step }
	if info.sash { rl.DrawText("Lethal blow:   survive at 1 HP (once per battle)", x, yy, size, rl.Color{140, 230, 150, 255}); yy += step }
	if info.weakness_str != 0 { rl.DrawText(fmt.ctprintf("Hit super-effectively:   +%d Strength", info.weakness_str), x, yy, size, rl.Color{240, 170, 120, 255}); yy += step }
	if info.cleanse_turn { rl.DrawText("Each turn:   cleanse Poison / Burn / Stun", x, yy, size, rl.Color{140, 230, 150, 255}); yy += step }
	if info.energy_regen != 0 { rl.DrawText(fmt.ctprintf("Each turn:   +%s energy regen", fmt_num(info.energy_regen)), x, yy, size, rl.Color{240, 210, 110, 255}); yy += step }
	if info.gold_per_turn != 0 { rl.DrawText(fmt.ctprintf("Each turn:   +%d gold", info.gold_per_turn), x, yy, size, rl.Color{240, 205, 90, 255}); yy += step }
	if info.capture_pct != 0 { rl.DrawText(fmt.ctprintf("Capture chance:   +%d%%", int(info.capture_pct * 100)), x, yy, size, rl.Color{180, 220, 255, 255}); yy += step }
	return yy
}

// ----------------------------------------------------------------------------
// Inventory (items + relics)
//
// Two columns: your monsters on the left, your bag on the right. Pick a monster,
// then pick an item, and it is worn — a swap sends whatever it was wearing back
// to the bag, and Unequip strips it. Relics slot into a Relic Tower instead.
//
// Opened from the Arena screen it shows something else entirely: only the
// monsters standing on the tower tile, and only the run's own pack
// (`Colony.arena_items`), which is unbounded and dies with the run. The colony's
// bag is out of reach mid-climb.
// ----------------------------------------------------------------------------

INV_COLS :: 7
INV_SLOT :: f32(74)
INV_GAP  :: f32(10)

inv_panel_rect :: proc() -> rl.Rectangle {
	sw := f32(screen_w())
	sh := f32(screen_h())
	w := f32(1020)
	h := f32(700)
	return rl.Rectangle{sw / 2 - w / 2, sh / 2 - h / 2, w, h}
}

// --- the monster column ---
INV_MON_W       :: f32(340)
INV_MON_ROW     :: f32(44)
INV_MON_VISIBLE :: 10

inv_mon_x :: proc() -> f32 {
	return inv_panel_rect().x + 24
}

inv_mon_rect :: proc(i: int, scroll: f32 = 0) -> rl.Rectangle {
	p := inv_panel_rect()
	return rl.Rectangle{inv_mon_x(), p.y + 122 + f32(i)*INV_MON_ROW - scroll, INV_MON_W, INV_MON_ROW - 4}
}

// The tile the Arena party is standing on (the selected monster's).
arena_inv_hex :: proc(g: ^Game) -> Hex {
	if g.selected >= 0 && g.selected < len(g.colony.roster) {
		return g.colony.roster[g.selected].pos
	}
	return g.colony.start_hex
}

inv_mon_count :: proc(g: ^Game) -> int {
	if g.bag_arena {
		_, n := arena_party_members(&g.colony, arena_inv_hex(g))
		return n
	}
	n := 0
	for m in g.colony.roster {
		if !m.wild {
			n += 1
		}
	}
	return n
}

// The roster index of the Nth monster in the list (-1 if there is none).
inv_mon_roster :: proc(g: ^Game, i: int) -> int {
	if g.bag_arena {
		party, n := arena_party_members(&g.colony, arena_inv_hex(g))
		if i < 0 || i >= n {
			return -1
		}
		return party[i]
	}
	n := 0
	for m, j in g.colony.roster {
		if m.wild {
			continue
		}
		if n == i {
			return j
		}
		n += 1
	}
	return -1
}

inv_mon_max_scroll :: proc(g: ^Game) -> f32 {
	n := max(inv_mon_count(g) - INV_MON_VISIBLE, 0)
	return f32(n) * INV_MON_ROW
}

// --- the bag column ---
inv_bag_x :: proc() -> f32 {
	return inv_panel_rect().x + 384
}

inv_bag_w :: proc() -> f32 {
	p := inv_panel_rect()
	return p.x + p.width - 24 - inv_bag_x()
}

inv_slot_rect :: proc(i: int) -> rl.Rectangle {
	p := inv_panel_rect()
	col := i % INV_COLS
	row := i / INV_COLS
	return rl.Rectangle{
		inv_bag_x() + f32(col) * (INV_SLOT + INV_GAP),
		p.y + 122 + f32(row) * (INV_SLOT + INV_GAP),
		INV_SLOT,
		INV_SLOT,
	}
}

inv_detail_rect :: proc() -> rl.Rectangle {
	p := inv_panel_rect()
	return rl.Rectangle{inv_bag_x(), p.y + 466, inv_bag_w(), 140}
}

inv_action_rect :: proc() -> rl.Rectangle {
	p := inv_panel_rect()
	return rl.Rectangle{inv_bag_x(), p.y + p.height - 84, inv_bag_w(), 30}
}

inv_unequip_rect :: proc() -> rl.Rectangle {
	p := inv_panel_rect()
	return rl.Rectangle{inv_bag_x(), p.y + p.height - 46, inv_bag_w(), 30}
}

// A slot in the grid is either an item or a relic.
Inv_Entry :: struct {
	is_relic: bool,
	item:     Item,
	relic:    Relic,
}

// The bag on show: the run's pack, or the colony's items and relics.
inv_count :: proc(g: ^Game) -> int {
	if g.bag_arena {
		return len(g.colony.arena_items)
	}
	return len(g.colony.items) + len(g.colony.relic_bag)
}

inv_entry_at :: proc(g: ^Game, i: int) -> (Inv_Entry, bool) {
	if i < 0 {
		return {}, false
	}
	if g.bag_arena {
		if i < len(g.colony.arena_items) {
			return Inv_Entry{item = g.colony.arena_items[i]}, true
		}
		return {}, false
	}
	if i < len(g.colony.items) {
		return Inv_Entry{item = g.colony.items[i]}, true
	}
	j := i - len(g.colony.items)
	if j < len(g.colony.relic_bag) {
		return Inv_Entry{is_relic = true, relic = g.colony.relic_bag[j]}, true
	}
	return {}, false
}

// The list position of the monster selected on the map, if it is in the list.
inv_focus_monster :: proc(g: ^Game) -> int {
	for i in 0..<inv_mon_count(g) {
		if inv_mon_roster(g, i) == g.selected {
			return i
		}
	}
	return 0
}

// Open the inventory. `arena` shows the run's pack and the tower party instead.
open_inventory :: proc(g: ^Game, arena := false) {
	g.show_bag = true
	g.bag_arena = arena
	g.bag_index = 0
	g.bag_first = 0
	g.bag_mon_scroll = 0
	g.bag_mon = inv_focus_monster(g)
}

// Equip a bag item onto the Nth monster in the list. A swap returns the old item
// to the same bag it came from.
equip_bag_item_to :: proc(g: ^Game, bag_index, list_pos: int) -> bool {
	s := inv_mon_roster(g, list_pos)
	if s < 0 {
		return false
	}
	c := &g.colony
	bag := g.bag_arena ? &c.arena_items : &c.items
	if bag_index < 0 || bag_index >= len(bag) {
		return false
	}
	item := bag[bag_index]
	ordered_remove(bag, bag_index)
	old := c.roster[s].creature.item
	creature_equip_item(&c.roster[s].creature, item)
	if old != .NONE {
		append(bag, old)
	}
	return true
}

// Take whatever the Nth monster is wearing back into the bag.
unequip_monster :: proc(g: ^Game, list_pos: int) -> bool {
	s := inv_mon_roster(g, list_pos)
	if s < 0 || g.colony.roster[s].creature.item == .NONE {
		return false
	}
	c := &g.colony
	bag := g.bag_arena ? &c.arena_items : &c.items
	append(bag, c.roster[s].creature.item)
	creature_equip_item(&c.roster[s].creature, .NONE)
	return true
}

// The name of the monster the inventory is pointed at, for button labels.
inv_target_name :: proc(g: ^Game) -> cstring {
	s := inv_mon_roster(g, g.bag_mon)
	if s < 0 {
		return cstring("nobody")
	}
	return fmt.ctprintf("%s", g.colony.roster[s].creature.name)
}

update_inventory :: proc(g: ^Game) {
	if rl.IsKeyPressed(.ESCAPE) || rl.IsKeyPressed(.G) || rl.IsKeyPressed(.J) {
		g.show_bag = false
		return
	}
	nmon := inv_mon_count(g)
	g.bag_mon = clamp(g.bag_mon, 0, max(nmon - 1, 0))
	g.bag_mon_scroll -= rl.GetMouseWheelMove() * 60
	g.bag_mon_scroll = clamp(g.bag_mon_scroll, 0, inv_mon_max_scroll(g))
	n := inv_count(g)
	g.bag_index = clamp(g.bag_index, 0, max(n - 1, 0))
	if !rl.IsMouseButtonPressed(.LEFT) {
		return
	}
	mp := mouse_pos()

	// Pick a monster.
	for i in 0..<min(nmon, INV_MON_VISIBLE) {
		if rl.CheckCollisionPointRec(mp, inv_mon_rect(i, g.bag_mon_scroll)) {
			g.bag_mon = i
			return
		}
	}

	// Pick a bag slot.
	for i in 0..<n {
		if i >= INV_COLS * 4 {
			break
		}
		if rl.CheckCollisionPointRec(mp, inv_slot_rect(i)) {
			g.bag_index = i
			return
		}
	}

	entry, ok := inv_entry_at(g, g.bag_index)
	// The action button: wear the selected item, or arm relic placement.
	if rl.CheckCollisionPointRec(mp, inv_action_rect()) {
		if !ok {
			return
		}
		if entry.is_relic {
			g.relic_place = entry.relic
			g.relic_place_active = true
			g.show_bag = false
			set_status(g, "Click a Relic Tower to slot it. Esc cancels.")
		} else if equip_bag_item_to(g, g.bag_index, g.bag_mon) {
			set_status(g, fmt.ctprintf("Equipped to %s.", inv_target_name(g)))
			g.bag_index = clamp(g.bag_index, 0, max(inv_count(g) - 1, 0))
		} else {
			set_status(g, "No monster to equip.")
		}
		return
	}
	// The second button: pull a relic out of a tower, or strip the monster. It
	// works with an empty bag, which is exactly when you want it.
	if rl.CheckCollisionPointRec(mp, inv_unequip_rect()) {
		if ok && entry.is_relic {
			if !remove_relic_nearest(&g.colony, g.colony.start_hex, entry.relic) {
				set_status(g, "No tower holds that relic.")
			}
		} else if unequip_monster(g, g.bag_mon) {
			set_status(g, fmt.ctprintf("%s is no longer wearing anything.", inv_target_name(g)))
		} else {
			set_status(g, "That monster has nothing equipped.")
		}
		return
	}
}

draw_inventory :: proc(g: ^Game) {
	sw := f32(screen_w())
	sh := f32(screen_h())
	rl.DrawRectangle(0, 0, i32(sw), i32(sh), rl.Color{8, 10, 16, 246})

	p := inv_panel_rect()
	draw_panel(p, rl.Color{18, 20, 28, 248}, rl.Color{150, 170, 220, 255})
	title := g.bag_arena ? cstring("THE PACK") : cstring("INVENTORY")
	rl.DrawText(title, i32(p.x) + 24, i32(p.y) + 16, 30, rl.Color{220, 228, 245, 255})
	sub := g.bag_arena ? cstring("This run's pack. Click a monster, then an item, then Equip. It comes home if you cash out.") : cstring("Click a monster, then an item, then Equip.")
	rl.DrawText(fit_text(string(sub), 15, i32(p.width) - 48), i32(p.x) + 24, i32(p.y) + 56, 15, rl.Color{170, 180, 200, 255})

	mp := mouse_pos()

	// ---- left: the monsters ----
	mon_head := g.bag_arena ? cstring("AT THE TOWER") : cstring("YOUR MONSTERS")
	rl.DrawText(mon_head, i32(inv_mon_x()), i32(p.y) + 96, 15, rl.Color{150, 160, 180, 255})
	nmon := inv_mon_count(g)
	lo := int(g.bag_mon_scroll / INV_MON_ROW)
	for k in 0..<INV_MON_VISIBLE {
		i := lo + k
		if i >= nmon {
			break
		}
		s := inv_mon_roster(g, i)
		if s < 0 {
			continue
		}
		cr := &g.colony.roster[s].creature
		rec := inv_mon_rect(k, g.bag_mon_scroll - f32(lo)*INV_MON_ROW)
		sel := i == g.bag_mon
		hover := rl.CheckCollisionPointRec(mp, rec)
		bg := rl.Color{26, 28, 38, 240}
		if sel {
			bg = rl.Color{34, 48, 40, 240}
		} else if hover {
			bg = rl.Color{32, 34, 46, 240}
		}
		rl.DrawRectangleRounded(rec, 0.14, 6, bg)
		rl.DrawRectangleRoundedLinesEx(rec, 0.14, 6, sel ? 2 : 1, sel ? rl.Color{150, 230, 180, 255} : rl.Color{54, 58, 74, 255})
		rl.DrawText(fit_textf(15, i32(INV_MON_W) - 150, "%s   Lvl %d", cr.name, cr.level),
			i32(rec.x) + 10, i32(rec.y) + 11, 15, rl.Color{225, 228, 240, 255})
		worn := cr.item == .NONE ? cstring("-") : item_name(cr.item)
		ww := rl.MeasureText(worn, 13)
		rl.DrawText(worn, i32(rec.x + rec.width) - ww - 10, i32(rec.y) + 13, 13,
			cr.item == .NONE ? rl.Color{120, 120, 140, 255} : item_color(cr.item))
	}
	if nmon == 0 {
		rl.DrawText(g.bag_arena ? "Nobody is at the tower." : "No monsters yet.",
			i32(inv_mon_x()), i32(p.y) + 130, 15, rl.Color{150, 150, 170, 255})
	} else if inv_mon_max_scroll(g) > 0 {
		rl.DrawText(fmt.ctprintf("%d of %d   (wheel to scroll)", lo + 1, nmon),
			i32(inv_mon_x()), i32(p.y + p.height) - 40, 13, rl.Color{140, 140, 160, 255})
	}

	// ---- right: the bag ----
	n := inv_count(g)
	head := g.bag_arena ? fmt.ctprintf("PACK   (%d items - unbounded)", len(g.colony.arena_items)) : fmt.ctprintf("BAG   (%d items, %d relics)", len(g.colony.items), len(g.colony.relic_bag))
	rl.DrawText(head, i32(inv_bag_x()), i32(p.y) + 96, 15, rl.Color{150, 160, 180, 255})
	for i in 0..<n {
		if i >= INV_COLS * 4 {
			break
		}
		entry, _ := inv_entry_at(g, i)
		rec := inv_slot_rect(i)
		sel := i == g.bag_index
		hover := rl.CheckCollisionPointRec(mp, rec)
		col := entry.is_relic ? rl.Color{235, 195, 110, 255} : item_color(entry.item)
		bg := rl.Color{26, 28, 38, 255}
		if sel {
			bg = rl.Color{38, 46, 42, 255}
		} else if hover {
			bg = rl.Color{32, 34, 46, 255}
		}
		rl.DrawRectangleRounded(rec, 0.18, 6, bg)
		rl.DrawRectangleRoundedLinesEx(rec, 0.18, 6, sel ? 3 : 2, sel ? rl.Color{150, 230, 180, 255} : col)
		cx := rec.x + rec.width / 2
		cy := rec.y + rec.height / 2 - 4
		if entry.is_relic {
			draw_relic_icon(entry.relic, cx, cy, 1.0)
		} else {
			draw_item_icon(entry.item, cx, cy, 1.0)
		}
		name := entry.is_relic ? relic_name(entry.relic) : item_name(entry.item)
		nw := rl.MeasureText(name, 11)
		rl.DrawText(name, i32(cx) - nw / 2, i32(rec.y + rec.height) - 16, 11, rl.Color{205, 210, 225, 255})
	}

	// ---- the selected slot's breakdown ----
	dr := inv_detail_rect()
	entry, ok := inv_entry_at(g, g.bag_index)
	if ok {
		col := entry.is_relic ? rl.Color{235, 195, 110, 255} : item_color(entry.item)
		rl.DrawRectangleRounded(dr, 0.03, 8, rl.Color{22, 24, 32, 255})
		rl.DrawRectangleRoundedLinesEx(dr, 0.03, 8, 2, rl.Color{54, 58, 74, 255})
		if entry.is_relic {
			draw_relic_icon(entry.relic, dr.x + 34, dr.y + 50, 1.1)
		} else {
			draw_item_icon(entry.item, dr.x + 34, dr.y + 50, 1.1)
		}
		name := entry.is_relic ? relic_name(entry.relic) : item_name(entry.item)
		kind := entry.is_relic ? cstring("Relic  -  slot into a Relic Tower") : cstring("Held item  -  one per monster")
		rl.DrawText(name, i32(dr.x) + 70, i32(dr.y) + 10, 20, rl.Color{235, 235, 245, 255})
		rl.DrawText(kind, i32(dr.x) + 70, i32(dr.y) + 34, 14, col)
		if entry.is_relic {
			draw_text_wrapped(relic_desc(entry.relic), i32(dr.x) + 70, i32(dr.y) + 56, 15, i32(dr.width) - 90,
				rl.Color{200, 205, 220, 255})
			placed := relics_placed(&g.colony)
			rl.DrawText(fmt.ctprintf("In the bag: %d    slotted in towers: %d    (copies stack)",
				relics_unplaced(&g.colony, entry.relic), placed[entry.relic]),
				i32(dr.x) + 70, i32(dr.y) + 112, 14, rl.Color{180, 185, 205, 255})
		} else {
			draw_item_effects(entry.item, i32(dr.x) + 70, i32(dr.y) + 56, 15)
		}
	} else {
		msg := g.bag_arena ? cstring("The pack is empty. Trial floors are where a run hands out gear.") : cstring("The bag is empty. Items drop from battles; relics from bosses.")
		rl.DrawText(msg, i32(dr.x), i32(dr.y) + 40, 15, rl.Color{150, 150, 170, 255})
	}

	// ---- actions (drawn even with an empty bag: that is when Unequip matters) ----
	s := inv_mon_roster(g, g.bag_mon)
	worn: cstring = "nothing"
	if s >= 0 && g.colony.roster[s].creature.item != .NONE {
		worn = item_name(g.colony.roster[s].creature.item)
	}
	if ok && entry.is_relic {
		draw_button(inv_action_rect(), "Place in a Relic Tower", true, BUTTON_PANEL, 16)
		if rl.CheckCollisionPointRec(mp, inv_action_rect()) {
			tooltip_set("Close the inventory and click a Relic Tower to slot this relic into it.")
		}
		draw_button(inv_unequip_rect(), "Take back (nearest tower)", relics_placed(&g.colony)[entry.relic] > 0, BUTTON_PANEL, 16)
	} else {
		draw_button(inv_action_rect(), fmt.ctprintf("Equip to %s", inv_target_name(g)), ok && s >= 0, BUTTON_PANEL, 16)
		draw_button(inv_unequip_rect(), fmt.ctprintf("Unequip %s  (wearing: %s)", inv_target_name(g), worn),
			s >= 0 && g.colony.roster[s].creature.item != .NONE, BUTTON_PANEL, 16)
	}
	rl.DrawText("G / Esc to close", i32(p.x) + 24, i32(p.y + p.height) - 30, 15, rl.Color{150, 150, 170, 255})
}

// A little procedural icon per item and per relic, so the grid reads at a
// glance without any art assets.
draw_item_icon :: proc(it: Item, cx, cy, s: f32) {
	col := item_color(it)
	dark := rl.Color{col[0] / 3, col[1] / 3, col[2] / 3, 255}
	white := rl.Color{240, 240, 250, 255}
	switch it {
	case .Bloodstone:
		rl.DrawTriangle(rl.Vector2{cx, cy - 11 * s}, rl.Vector2{cx - 11 * s, cy + 2 * s}, rl.Vector2{cx + 11 * s, cy + 2 * s}, col)
		rl.DrawTriangle(rl.Vector2{cx - 11 * s, cy + 2 * s}, rl.Vector2{cx + 11 * s, cy + 2 * s}, rl.Vector2{cx, cy + 12 * s}, dark)
		rl.DrawCircleV(rl.Vector2{cx, cy + 14 * s}, 2.4 * s, rl.Color{220, 60, 60, 255})
	case .Weakpoint_Lens:
		rl.DrawCircleV(rl.Vector2{cx, cy}, 11 * s, dark)
		rl.DrawCircleLinesV(rl.Vector2{cx, cy}, 11 * s, col)
		rl.DrawLineEx(rl.Vector2{cx - 16 * s, cy}, rl.Vector2{cx + 16 * s, cy}, 1.6 * s, col)
		rl.DrawLineEx(rl.Vector2{cx, cy - 16 * s}, rl.Vector2{cx, cy + 16 * s}, 1.6 * s, col)
		rl.DrawCircleV(rl.Vector2{cx, cy}, 3.2 * s, white)
	case .Ricochet_Charm:
		rl.DrawRectangleRounded(rl.Rectangle{cx - 12 * s, cy - 12 * s, 24 * s, 24 * s}, 0.25, 4, dark)
		rl.DrawRectangleRoundedLinesEx(rl.Rectangle{cx - 12 * s, cy - 12 * s, 24 * s, 24 * s}, 0.25, 4, 1.6 * s, col)
		for dy in -1..=1 {
			for dx in -1..=1 {
				rl.DrawCircleV(rl.Vector2{cx + f32(dx) * 6 * s, cy + f32(dy) * 6 * s}, 2.1 * s, white)
			}
		}
	case .Siphon_Gland:
		rl.DrawTriangle(rl.Vector2{cx, cy - 13 * s}, rl.Vector2{cx - 10 * s, cy + 4 * s}, rl.Vector2{cx + 10 * s, cy + 4 * s}, col)
		rl.DrawCircleV(rl.Vector2{cx, cy + 4 * s}, 10 * s, col)
		rl.DrawCircleV(rl.Vector2{cx - 3 * s, cy}, 2.6 * s, white)
	case .Venom_Sac:
		rl.DrawCircleV(rl.Vector2{cx, cy - 2 * s}, 11 * s, col)
		rl.DrawTriangle(rl.Vector2{cx - 5 * s, cy + 8 * s}, rl.Vector2{cx + 5 * s, cy + 8 * s}, rl.Vector2{cx, cy + 16 * s}, col)
		rl.DrawCircleV(rl.Vector2{cx - 4 * s, cy - 5 * s}, 3 * s, dark)
	case .Spiked_Carapace:
		rl.DrawCircleV(rl.Vector2{cx, cy}, 10 * s, dark)
		rl.DrawCircleLinesV(rl.Vector2{cx, cy}, 10 * s, col)
		for k in 0..<6 {
			a := f32(k) / 6 * 6.28318
			rl.DrawTriangle(
				rl.Vector2{cx + math.cos(a) * 10 * s, cy + math.sin(a) * 10 * s},
				rl.Vector2{cx + math.cos(a + 0.5) * 10 * s, cy + math.sin(a + 0.5) * 10 * s},
				rl.Vector2{cx + math.cos(a + 0.25) * 18 * s, cy + math.sin(a + 0.25) * 18 * s},
				col,
			)
		}
	case .Ration_Pouch:
		rl.DrawRectangleRounded(rl.Rectangle{cx - 12 * s, cy - 6 * s, 24 * s, 20 * s}, 0.35, 5, dark)
		rl.DrawRectangleRoundedLinesEx(rl.Rectangle{cx - 12 * s, cy - 6 * s, 24 * s, 20 * s}, 0.35, 5, 1.6 * s, col)
		rl.DrawLineEx(rl.Vector2{cx - 9 * s, cy - 6 * s}, rl.Vector2{cx + 9 * s, cy - 6 * s}, 3 * s, col)
		rl.DrawCircleV(rl.Vector2{cx, cy + 4 * s}, 3.2 * s, white)
	case .Amber_Fruit:
		rl.DrawCircleV(rl.Vector2{cx, cy + 2 * s}, 11 * s, col)
		rl.DrawCircleV(rl.Vector2{cx - 3 * s, cy - 2 * s}, 3 * s, rl.Color{255, 235, 200, 200})
		rl.DrawLineEx(rl.Vector2{cx, cy - 9 * s}, rl.Vector2{cx + 2 * s, cy - 16 * s}, 2 * s, rl.Color{110, 90, 60, 255})
		rl.DrawEllipse(i32(cx + 7 * s), i32(cy - 14 * s), 6 * s, 3 * s, rl.Color{120, 200, 120, 255})
	case .Cleansing_Bloom:
		for k in 0..<5 {
			a := f32(k) / 5 * 6.28318
			rl.DrawCircleV(rl.Vector2{cx + math.cos(a) * 8 * s, cy + math.sin(a) * 8 * s}, 6 * s, col)
		}
		rl.DrawCircleV(rl.Vector2{cx, cy}, 4.5 * s, rl.Color{255, 245, 190, 255})
	case .Grit_Charm:
		rl.DrawRectangleRounded(rl.Rectangle{cx - 10 * s, cy - 12 * s, 20 * s, 22 * s}, 0.35, 5, dark)
		rl.DrawTriangle(rl.Vector2{cx - 10 * s, cy + 8 * s}, rl.Vector2{cx + 10 * s, cy + 8 * s}, rl.Vector2{cx, cy + 16 * s}, dark)
		rl.DrawRectangleRoundedLinesEx(rl.Rectangle{cx - 10 * s, cy - 12 * s, 20 * s, 22 * s}, 0.35, 5, 1.6 * s, col)
		rl.DrawLineEx(rl.Vector2{cx, cy - 6 * s}, rl.Vector2{cx, cy + 4 * s}, 2.6 * s, col)
		rl.DrawLineEx(rl.Vector2{cx - 5 * s, cy - 1 * s}, rl.Vector2{cx + 5 * s, cy - 1 * s}, 2.6 * s, col)
	case .Grudge_Idol:
		rl.DrawRectangleRounded(rl.Rectangle{cx - 7 * s, cy - 12 * s, 14 * s, 24 * s}, 0.25, 4, dark)
		rl.DrawRectangleRoundedLinesEx(rl.Rectangle{cx - 7 * s, cy - 12 * s, 14 * s, 24 * s}, 0.25, 4, 1.6 * s, col)
		rl.DrawCircleV(rl.Vector2{cx - 3 * s, cy - 5 * s}, 1.8 * s, col)
		rl.DrawCircleV(rl.Vector2{cx + 3 * s, cy - 5 * s}, 1.8 * s, col)
		rl.DrawLineEx(rl.Vector2{cx - 3 * s, cy + 4 * s}, rl.Vector2{cx + 3 * s, cy + 4 * s}, 2 * s, col)
	case .Snare_Kit:
		rl.DrawCircleLinesV(rl.Vector2{cx, cy}, 11 * s, col)
		rl.DrawLineEx(rl.Vector2{cx - 11 * s, cy - 6 * s}, rl.Vector2{cx + 11 * s, cy + 6 * s}, 1.4 * s, col)
		rl.DrawLineEx(rl.Vector2{cx - 11 * s, cy + 6 * s}, rl.Vector2{cx + 11 * s, cy - 6 * s}, 1.4 * s, col)
		rl.DrawLineEx(rl.Vector2{cx - 11 * s, cy}, rl.Vector2{cx + 11 * s, cy}, 1.4 * s, col)
		rl.DrawLineEx(rl.Vector2{cx, cy - 11 * s}, rl.Vector2{cx, cy + 11 * s}, 1.4 * s, col)
		rl.DrawCircleV(rl.Vector2{cx, cy}, 2.6 * s, white)
	case .NONE:
	}
}

// A relic's mark: a small faceted core (relics share one icon; the colour and
// label carry the identity).
draw_relic_icon :: proc(r: Relic, cx, cy, s: f32) {
	col := rl.Color{235, 195, 110, 255}
	dark := rl.Color{78, 62, 26, 255}
	rl.DrawTriangle(rl.Vector2{cx, cy - 13 * s}, rl.Vector2{cx - 11 * s, cy + 3 * s}, rl.Vector2{cx + 11 * s, cy + 3 * s}, col)
	rl.DrawTriangle(rl.Vector2{cx - 11 * s, cy + 3 * s}, rl.Vector2{cx + 11 * s, cy + 3 * s}, rl.Vector2{cx, cy + 14 * s}, dark)
	rl.DrawTriangleLines(rl.Vector2{cx, cy - 13 * s}, rl.Vector2{cx - 11 * s, cy + 3 * s}, rl.Vector2{cx + 11 * s, cy + 3 * s}, rl.Color{255, 235, 170, 255})
	rl.DrawCircleV(rl.Vector2{cx, cy}, 3 * s, rl.Color{255, 245, 200, 255})
	_ = r
}

// ----------------------------------------------------------------------------
// Crystal progression panel (a tree, shown in two columns)
// ----------------------------------------------------------------------------

UPGRADE_ROWS :: 12 // rows per column; 3 columns hold up to 36 nodes

upgrade_panel_rect :: proc() -> rl.Rectangle {
	sw := f32(screen_w())
	sh := f32(screen_h())
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
	mp := mouse_pos()
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
	sw := f32(screen_w())
	sh := f32(screen_h())
	rl.DrawRectangle(0, 0, i32(sw), i32(sh), rl.Color{8, 10, 16, 245})

	p := upgrade_panel_rect()
	rl.DrawRectangleRounded(p, 0.03, 8, rl.Color{18, 20, 30, 248})
	rl.DrawRectangleRoundedLinesEx(p, 0.03, 8, 3, rl.Color{150, 120, 235, 255})

	rl.DrawText("CRYSTAL PROGRESSION", i32(p.x) + 24, i32(p.y) + 18, 30, rl.Color{210, 190, 250, 255})
	rl.DrawText(fmt.ctprintf("Crystals: %d    -    permanent upgrades; fight the Arena and Boss Rooms for more", g.colony.crystals), i32(p.x) + 24, i32(p.y) + 58, 16, rl.Color{190, 175, 220, 255})

	mp := mouse_pos()
	clip := rl.Rectangle{p.x + 12, p.y + 96, p.width - 24, p.height - 100 - 34}
	scissor_begin(clip)
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
		rl.DrawText(upgrade_name(u), i32(rec.x + indent) + 14, i32(rec.y) + 5, 15, name_col)

		// Level pips after the name. Uncapped nodes show at most 8 pips plus a
		// numeric level, so the row never overruns its cell.
		nw := rl.MeasureText(upgrade_name(u), 15)
		pips := min(info.max_level, 8)
		for lv in 0..<pips {
			cx := rec.x + indent + 14 + f32(nw) + 12 + f32(lv) * 13
			col := lv < level ? rl.Color{170, 140, 245, 255} : rl.Color{58, 56, 74, 255}
			rl.DrawCircleV(rl.Vector2{cx, rec.y + 12}, 4.5, col)
		}
		if info.max_level > 8 {
			rl.DrawText(fmt.ctprintf("Lv %d", level), i32(rec.x + indent + 14 + f32(nw) + 12 + f32(pips) * 13), i32(rec.y) + 5, 13, rl.Color{200, 185, 245, 255})
		}

		if unlocked {
			rl.DrawText(upgrade_desc(u), i32(rec.x + indent) + 14, i32(rec.y) + 24, 11, rl.Color{185, 185, 205, 255})
			rl.DrawText("unlocked", i32(rec.x + indent) + 14, i32(rec.y) + 40, 11, rl.Color{110, 130, 118, 255})
		} else {
			rl.DrawText(fmt.ctprintf("Needs %s Lv %d", upgrade_name(info.prereq), info.req_level), i32(rec.x + indent) + 14, i32(rec.y) + 30, 11, rl.Color{225, 175, 110, 255})
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
		lw := rl.MeasureText(label, 14)
		lc := maxed ? rl.Color{160, 150, 190, 255} : (enabled ? rl.Color{235, 230, 255, 255} : rl.Color{140, 132, 158, 255})
		rl.DrawText(label, i32(btn.x + btn.width / 2) - lw / 2, i32(btn.y + btn.height / 2) - 7, 14, lc)

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
	scissor_end()

	rl.DrawText("U / Esc to close   -   wheel to scroll   -   children unlock when their parent reaches the shown level", i32(p.x) + 24, i32(p.y + p.height) - 24, 13, rl.Color{140, 140, 160, 255})
}

// ----------------------------------------------------------------------------
// The Arena screen
//
// A run has its own screen, not the colony map. One flat entry fee buys a chain
// of floors starting at floor 1; each cleared floor banks its purse; cash out to
// keep the winnings, or wipe and lose them. While a run is on, this is where you
// are — the colony is out of reach until you settle up, so the party you brought
// is the party you climb with.
// ----------------------------------------------------------------------------

arena_panel_rect :: proc() -> rl.Rectangle {
	sw := f32(screen_w())
	sh := f32(screen_h())
	return rl.Rectangle{sw / 2 - 450, sh / 2 - 260, 900, 520}
}

// The left column runs from p.x + 28 to the party column at p.x + 460.
ARENA_COL_W :: f32(430)

arena_fight_rect :: proc() -> rl.Rectangle {
	p := arena_panel_rect()
	return rl.Rectangle{p.x + 28, p.y + 380, p.width - 56, 46}
}

arena_cashout_rect :: proc() -> rl.Rectangle {
	p := arena_panel_rect()
	w := (p.width - 56 - 48) / 5
	return rl.Rectangle{p.x + 28, p.y + 434, w, 34}
}

arena_save_rect :: proc() -> rl.Rectangle {
	r := arena_cashout_rect()
	return rl.Rectangle{r.x + r.width + 12, r.y, r.width, r.height}
}

arena_items_rect :: proc() -> rl.Rectangle {
	r := arena_save_rect()
	return rl.Rectangle{r.x + r.width + 12, r.y, r.width, r.height}
}

arena_decks_rect :: proc() -> rl.Rectangle {
	r := arena_items_rect()
	return rl.Rectangle{r.x + r.width + 12, r.y, r.width, r.height}
}

arena_leave_rect :: proc() -> rl.Rectangle {
	r := arena_decks_rect()
	return rl.Rectangle{r.x + r.width + 12, r.y, r.width, r.height}
}

// Where a run begins: settle up, or (with no run on) walk back out to the colony.
update_arena :: proc(g: ^Game) {
	c := &g.colony
	// Esc only lets you out when there is nothing at stake; mid-run you settle
	// up or abandon, so the party can't be rearranged between floors.
	if rl.IsKeyPressed(.ESCAPE) && !c.arena_run {
		g.mode = .MAP
		return
	}
	if !rl.IsMouseButtonPressed(.LEFT) {
		return
	}
	mp := mouse_pos()
	if !c.arena_run && rl.CheckCollisionPointRec(mp, arena_leave_rect()) {
		g.mode = .MAP
		return
	}
	// Cash out: bank everything the run has earned and end it.
	if c.arena_run && rl.CheckCollisionPointRec(mp, arena_cashout_rect()) {
		banked := c.arena_run_crystals
		c.crystals += banked
		c.crystals_earned += banked
		colony_notify(c, "Cashed out: %d crystals banked.", banked)
		audio_play(.CRYSTAL)
		arena_keep_pack(c)
		c.arena_run = false
		c.arena_run_crystals = 0
		c.arena_floor = 1
		clear(&c.arena_boons)
		g.mode = .MAP
		return
	}
	if c.arena_run && rl.CheckCollisionPointRec(mp, arena_save_rect()) {
		set_status(g, save_game(g, AUTOSAVE_SLOT) ? "Run saved." : "Could not save.")
		return
	}
	// Re-gear between floors: the inventory opens right over the tower screen,
	// showing only this run's pack and the monsters on the tile.
	if rl.CheckCollisionPointRec(mp, arena_items_rect()) {
		open_inventory(g, arena = true)
		return
	}
	// And look at what the party is actually carrying into the next floor.
	if rl.CheckCollisionPointRec(mp, arena_decks_rect()) {
		g.show_deck = true
		g.view_index = clamp(g.selected, 0, max(len(c.roster) - 1, 0))
		g.view_scroll = 0
		return
	}
	// Abandon: the same as a wipe, but on your own terms.
	if c.arena_run && rl.CheckCollisionPointRec(mp, arena_leave_rect()) {
		colony_notify(c, "Run abandoned - %d crystals and the pack are lost.", c.arena_run_crystals)
		c.arena_run = false
		c.arena_run_crystals = 0
		c.arena_floor = 1
		clear(&c.arena_boons)
		clear(&c.arena_items)
		g.mode = .MAP
		return
	}
	if rl.CheckCollisionPointRec(mp, arena_fight_rect()) {
		hex := c.roster[g.selected].pos
		// The fee is flat and only paid once, when the run starts.
		if !c.arena_run {
			if colony_total_gold(c) < ARENA_ENTRY_COST {
				set_status(g, "Not enough gold to enter the Arena.")
				return
			}
			_ = colony_spend_gold(c, ARENA_ENTRY_COST)
			c.arena_run = true
			c.arena_floor = 1
			c.arena_run_crystals = 0
			// Everything the tower fields is scaled off the party you walked in
			// with, so it neither drifts up under you nor responds to how you
			// level while you're inside.
			c.arena_base_level = arena_party_level(c, hex)
			// Each run gets its own seed: its gym order and its event offers are
			// derived from it, so they hold for the whole climb and differ next
			// time out.
			c.arena_run_seed = rng_next_u64(&c.rng)
			clear(&c.arena_boons)
			// Walking here spent energy from the same pool the fights draw on.
			// Starting the climb tops everyone back up, so travel costs nothing.
			arena_refill_party(c, hex)
		}
		// A trial floor that is an event is settled by a decision, not a fight.
		if arena_is_event_floor(max(c.arena_floor, 1)) {
			arena_make_event(c, hex, max(c.arena_floor, 1))
			g.arena_event_open = true
			return
		}
		colony_spawn_arena_team(c, hex)
		g.battle_hex = hex
		g.battle_forced = true
		g.battle_arena = true
		// The Arena is a formal challenge: only the monsters standing on the tile
		// come in, so the party is capped at six and nobody is dragged in from a
		// neighbouring hex.
		build_attack(g, hex, 0)
		g.battle_choice_open = true
		set_status(g, "The Arena answers your challenge!")
	}
}

// Your party, as brought.
// A party row, laid out in three clear bands so nothing overlaps: name and
// ability on top, then the HP bar with its number inside it, then a short energy
// bar with the held item to its right.
ARENA_ROW_H :: f32(50)

draw_arena_party :: proc(g: ^Game, x, y, w: f32) {
	rl.DrawText("YOUR PARTY", i32(x), i32(y), 15, rl.Color{150, 160, 180, 255})
	hex := g.colony.roster[g.selected].pos
	row := y + 26
	for i in 0 ..< len(g.colony.roster) {
		m := &g.colony.roster[i]
		if m.wild || !hex_equal(m.pos, hex) {
			continue
		}
		cr := &m.creature
		rl.DrawRectangleRounded(rl.Rectangle{x, row, w, ARENA_ROW_H}, 0.12, 6, rl.Color{26, 28, 36, 240})
		rl.DrawRectangleRoundedLinesEx(rl.Rectangle{x, row, w, ARENA_ROW_H}, 0.12, 6, 1, rl.Color{58, 60, 74, 255})
		// Band 1: name and ability.
		rl.DrawText(fit_textf(15, i32(w) - 120, "%s   Lvl %d", cr.name, cr.level),
			i32(x) + 10, i32(row) + 4, 15, rl.Color{225, 228, 240, 255})
		ab := ability_name(cr.ability)
		aw := rl.MeasureText(ab, 12)
		rl.DrawText(ab, i32(x + w) - aw - 10, i32(row) + 6, 12, rl.Color{200, 180, 240, 255})
		// Band 2: the HP bar, with its number centred inside it (shadowed so it
		// stays readable over the fill).
		hp_rec := rl.Rectangle{x + 10, row + 23, w - 20, 12}
		draw_bar(hp_rec, cr.hp, cr.max_hp, COL_HP)
		hp_txt := fmt.ctprintf("%d/%d", cr.hp, cr.max_hp)
		hw := rl.MeasureText(hp_txt, 10)
		rl.DrawText(hp_txt, i32(hp_rec.x + hp_rec.width / 2) - hw / 2 + 1, i32(hp_rec.y) + 2, 10, rl.Color{0, 0, 0, 200})
		rl.DrawText(hp_txt, i32(hp_rec.x + hp_rec.width / 2) - hw / 2, i32(hp_rec.y) + 1, 10, rl.Color{245, 245, 250, 255})
		// Band 3: a short energy bar, with the held item to its right.
		draw_bar(rl.Rectangle{x + 10, row + 40, 120, 6}, int(cr.energy * 100), int(max(cr.energy_max, 0.01) * 100), COL_ENERGY)
		en_txt := fmt.ctprintf("En %s/%s", fmt_num(cr.energy), fmt_num(cr.energy_max))
		rl.DrawText(en_txt, i32(x) + 138, i32(row) + 36, 11, rl.Color{150, 190, 235, 255})
		it := item_name(cr.item)
		iw := rl.MeasureText(it, 11)
		rl.DrawText(it, i32(x + w) - iw - 10, i32(row) + 36, 11, rl.Color{190, 190, 205, 255})
		row += ARENA_ROW_H + 4
	}
}

draw_arena :: proc(g: ^Game) {
	sw := f32(screen_w())
	sh := f32(screen_h())
	rl.ClearBackground(rl.Color{10, 10, 14, 255})
	rl.DrawRectangle(0, 0, i32(sw), i32(sh), rl.Color{0, 0, 0, 90})

	p := arena_panel_rect()
	rl.DrawRectangleRounded(p, 0.04, 8, rl.Color{30, 24, 18, 250})
	rl.DrawRectangleRoundedLinesEx(p, 0.04, 8, 3, rl.Color{210, 170, 90, 255})

	floor := max(g.colony.arena_floor, 1)
	running := g.colony.arena_run
	rl.DrawText("THE ARENA", i32(p.x) + 28, i32(p.y) + 16, 30, rl.Color{240, 210, 130, 255})
	rl.DrawText(fmt.ctprintf("FLOOR %d      best ever: %d", floor, g.colony.arena_best_floor),
		i32(p.x) + 28, i32(p.y) + 56, 22, rl.Color{240, 215, 150, 255})

	heal_iv := arena_heal_interval(floor)
	if running {
		rl.DrawText(fit_textf(17, i32(ARENA_COL_W), "Winnings: %d crystals banked.", g.colony.arena_run_crystals),
			i32(p.x) + 28, i32(p.y) + 88, 17, rl.Color{150, 225, 170, 255})
		rl.DrawText(fit_text("Lose the party and the run - and the winnings - are gone.", 14, i32(ARENA_COL_W)),
			i32(p.x) + 28, i32(p.y) + 110, 14, rl.Color{225, 165, 140, 255})
	} else {
		rl.DrawText(fit_textf(17, i32(ARENA_COL_W), "Entry: %d gold for one run.", ARENA_ENTRY_COST),
			i32(p.x) + 28, i32(p.y) + 88, 17, rl.Color{215, 200, 175, 255})
		rl.DrawText(fit_text("Climb as far as you can, then cash out.", 14, i32(ARENA_COL_W)),
			i32(p.x) + 28, i32(p.y) + 110, 14, rl.Color{200, 185, 160, 255})
	}
	if arena_is_event_floor(floor) {
		rl.DrawText(fit_text("A trial floor: no fight, but a choice to make.", 15, i32(ARENA_COL_W)),
			i32(p.x) + 28, i32(p.y) + 134, 15, rl.Color{225, 210, 150, 255})
	} else if arena_is_trial_floor(floor) {
		rl.DrawText(fit_textf(15, i32(ARENA_COL_W), "A trial floor: the gym %s.", arena_gym_for(&g.colony, floor).name),
			i32(p.x) + 28, i32(p.y) + 134, 15, rl.Color{225, 210, 150, 255})
	} else {
		rl.DrawText(fit_textf(15, i32(ARENA_COL_W), "Next: %d challengers around level %d.",
			arena_team_size_for(floor), arena_challenger_level(&g.colony, g.colony.roster[g.selected].pos)),
			i32(p.x) + 28, i32(p.y) + 134, 15, rl.Color{215, 200, 175, 255})
	}
	rl.DrawText(fit_text(string(arena_trials_ahead(&g.colony, floor)), 13, i32(ARENA_COL_W)),
		i32(p.x) + 28, i32(p.y) + 156, 13, rl.Color{190, 195, 215, 255})
	rl.DrawText(fit_textf(14, i32(ARENA_COL_W), "A heal every %d floor%s.   Gold %d   Crystals %d",
		heal_iv, heal_iv == 1 ? "" : "s", colony_total_gold(&g.colony), g.colony.crystals),
		i32(p.x) + 28, i32(p.y) + 178, 14, rl.Color{210, 205, 175, 255})
	if boons := arena_boons_label(&g.colony); len(boons) > 0 {
		rl.DrawText(fit_text(string(boons), 13, i32(ARENA_COL_W)), i32(p.x) + 28, i32(p.y) + 198, 13, rl.Color{200, 185, 235, 255})
	}
	draw_arena_party(g, p.x + 468, p.y + 16, p.width - 496)

	mp := mouse_pos()
	// Fight / enter.
	btn := arena_fight_rect()
	afford := running || colony_total_gold(&g.colony) >= ARENA_ENTRY_COST
	hover := afford && rl.CheckCollisionPointRec(mp, btn)
	bg := afford ? (hover ? rl.Color{120, 60, 40, 255} : rl.Color{88, 46, 32, 255}) : rl.Color{40, 36, 34, 255}
	rl.DrawRectangleRounded(btn, 0.22, 8, bg)
	rl.DrawRectangleRoundedLinesEx(btn, 0.22, 8, 2, afford ? rl.Color{230, 150, 90, 255} : rl.Color{100, 90, 80, 255})
	fl := fmt.ctprintf("Enter the tower   (%d gold)", ARENA_ENTRY_COST)
	if running {
		switch {
		case arena_is_event_floor(floor):
			fl = fmt.ctprintf("Floor %d  -  a decision", floor)
		case arena_is_trial_floor(floor):
			fl = fmt.ctprintf("Floor %d  -  the gym %s", floor, arena_gym_for(&g.colony, floor).name)
		case:
			fl = fmt.ctprintf("Fight floor %d", floor)
		}
	}
	fw := rl.MeasureText(fl, 20)
	rl.DrawText(fl, i32(btn.x + btn.width / 2) - fw / 2, i32(btn.y + btn.height / 2) - 11, 20, afford ? rl.Color{250, 235, 220, 255} : rl.Color{150, 140, 130, 255})

	// The row beneath: settle up, save, and get out.
	cr := arena_cashout_rect()
	if running {
		chover := rl.CheckCollisionPointRec(mp, cr)
		rl.DrawRectangleRounded(cr, 0.28, 8, chover ? rl.Color{52, 92, 66, 255} : rl.Color{38, 68, 50, 255})
		rl.DrawRectangleRoundedLinesEx(cr, 0.28, 8, 2, rl.Color{140, 220, 170, 255})
		cl := fmt.ctprintf("Cash out  (%d crystals)", g.colony.arena_run_crystals)
		cw := rl.MeasureText(cl, 16)
		rl.DrawText(cl, i32(cr.x + cr.width / 2) - cw / 2, i32(cr.y + cr.height / 2) - 8, 16, rl.Color{225, 250, 235, 255})
	}
	sr := arena_save_rect()
	if running {
		shover := rl.CheckCollisionPointRec(mp, sr)
		rl.DrawRectangleRounded(sr, 0.28, 8, shover ? rl.Color{44, 50, 66, 255} : rl.Color{32, 36, 48, 255})
		rl.DrawRectangleRoundedLinesEx(sr, 0.28, 8, 2, rl.Color{130, 160, 220, 255})
		sl := cstring("Save the run")
		sw2 := rl.MeasureText(sl, 16)
		rl.DrawText(sl, i32(sr.x + sr.width / 2) - sw2 / 2, i32(sr.y + sr.height / 2) - 8, 16, rl.Color{200, 215, 240, 255})
	}
	dr := arena_decks_rect()
	dhover := rl.CheckCollisionPointRec(mp, dr)
	rl.DrawRectangleRounded(dr, 0.28, 8, dhover ? rl.Color{44, 52, 62, 255} : rl.Color{32, 38, 46, 255})
	rl.DrawRectangleRoundedLinesEx(dr, 0.28, 8, 2, rl.Color{150, 210, 220, 255})
	dl := cstring("Decks")
	dlw := rl.MeasureText(dl, 16)
	rl.DrawText(dl, i32(dr.x + dr.width / 2) - dlw / 2, i32(dr.y + dr.height / 2) - 8, 16, rl.Color{205, 235, 240, 255})

	ir := arena_items_rect()
	ihover := rl.CheckCollisionPointRec(mp, ir)
	rl.DrawRectangleRounded(ir, 0.28, 8, ihover ? rl.Color{52, 48, 66, 255} : rl.Color{38, 36, 48, 255})
	rl.DrawRectangleRoundedLinesEx(ir, 0.28, 8, 2, rl.Color{190, 175, 235, 255})
	il := cstring("Items")
	iw := rl.MeasureText(il, 16)
	rl.DrawText(il, i32(ir.x + ir.width / 2) - iw / 2, i32(ir.y + ir.height / 2) - 8, 16, rl.Color{215, 205, 245, 255})

	lr := arena_leave_rect()
	lhover := rl.CheckCollisionPointRec(mp, lr)
	rl.DrawRectangleRounded(lr, 0.28, 8, lhover ? rl.Color{46, 44, 52, 255} : rl.Color{34, 32, 38, 255})
	ll := running ? cstring("Abandon") : cstring("Walk away")
	lw := rl.MeasureText(ll, 16)
	rl.DrawText(ll, i32(lr.x + lr.width / 2) - lw / 2, i32(lr.y + lr.height / 2) - 8, 16, rl.Color{190, 185, 200, 255})

	hint := running ? cstring("The colony is out of reach until this run is settled - but Items re-gears the party.") : cstring("Esc or Walk away returns to the colony.")
	hw := rl.MeasureText(hint, 14)
	rl.DrawText(hint, i32(p.x + p.width / 2) - hw / 2, i32(p.y + p.height) - 32, 14, rl.Color{140, 140, 160, 255})
}

// ----------------------------------------------------------------------------
// Arena trial: the event floor
//
// A decision floor. Three concrete offers, each a change to the team you
// brought, and always the option to walk on unchanged.
// ----------------------------------------------------------------------------

arena_event_panel_rect :: proc() -> rl.Rectangle {
	sw := f32(screen_w())
	sh := f32(screen_h())
	return rl.Rectangle{sw / 2 - 330, sh / 2 - 200, 660, 400}
}

arena_event_option_rect :: proc(i: int) -> rl.Rectangle {
	p := arena_event_panel_rect()
	return rl.Rectangle{p.x + 30, p.y + 168 + f32(i) * 56, p.width - 60, 48}
}

arena_event_skip_rect :: proc() -> rl.Rectangle {
	p := arena_event_panel_rect()
	return rl.Rectangle{p.x + 30, p.y + 344, p.width - 60, 34}
}

update_arena_event :: proc(g: ^Game) {
	if rl.IsKeyPressed(.ESCAPE) {
		g.arena_event_open = false
		return
	}
	if !rl.IsMouseButtonPressed(.LEFT) {
		return
	}
	mp := mouse_pos()
	ev := &g.colony.arena_event
	for i in 0..<ev.count {
		if rl.CheckCollisionPointRec(mp, arena_event_option_rect(i)) {
			hex := g.colony.roster[g.selected].pos
			arena_apply_event_option(&g.colony, hex, ev.options[i])
			_, gold := arena_clear_floor(&g.colony, hex, max(ev.floor, 1))
			colony_notify(&g.colony, "The trial is settled. %d gold.", gold)
			g.arena_event_open = false
			// A run is a long thing; bank it after every floor.
			if g.autosave_on && save_supported() {
				_ = save_game(g, AUTOSAVE_SLOT)
			}
			return
		}
	}
	if rl.CheckCollisionPointRec(mp, arena_event_skip_rect()) {
		hex := g.colony.roster[g.selected].pos
		_, gold := arena_clear_floor(&g.colony, hex, max(ev.floor, 1))
		colony_notify(&g.colony, "You walk on. %d gold.", gold)
		g.arena_event_open = false
		if g.autosave_on && save_supported() {
			_ = save_game(g, AUTOSAVE_SLOT)
		}
		return
	}
}

draw_arena_event :: proc(g: ^Game) {
	sw := f32(screen_w())
	sh := f32(screen_h())
	rl.DrawRectangle(0, 0, i32(sw), i32(sh), rl.Color{0, 0, 0, 180})

	p := arena_event_panel_rect()
	rl.DrawRectangleRounded(p, 0.05, 8, rl.Color{28, 24, 20, 250})
	rl.DrawRectangleRoundedLinesEx(p, 0.05, 8, 3, rl.Color{210, 180, 110, 255})

	ev := &g.colony.arena_event
	rl.DrawText(fmt.ctprintf("FLOOR %d  -  %s", ev.floor, ev.title),
		i32(p.x) + 28, i32(p.y) + 18, 24, rl.Color{240, 215, 140, 255})
	draw_text_wrapped(fmt.ctprintf("%s", ev.text), i32(p.x) + 28, i32(p.y) + 56, 16, i32(p.width) - 56,
		rl.Color{205, 200, 190, 255})

	mp := mouse_pos()
	for i in 0..<ev.count {
		r := arena_event_option_rect(i)
		hover := rl.CheckCollisionPointRec(mp, r)
		rl.DrawRectangleRounded(r, 0.18, 8, hover ? rl.Color{70, 60, 40, 255} : rl.Color{44, 40, 32, 255})
		rl.DrawRectangleRoundedLinesEx(r, 0.18, 8, 2, hover ? rl.Color{240, 200, 120, 255} : rl.Color{140, 124, 88, 255})
		label := event_option_label(&g.colony, ev.options[i])
		rl.DrawText(label, i32(r.x) + 16, i32(r.y + r.height / 2) - 9, 17, rl.Color{245, 235, 215, 255})
	}

	sr := arena_event_skip_rect()
	shover := rl.CheckCollisionPointRec(mp, sr)
	rl.DrawRectangleRounded(sr, 0.3, 8, shover ? rl.Color{46, 44, 52, 255} : rl.Color{34, 32, 38, 255})
	sl := cstring("Walk on unchanged")
	sw2 := rl.MeasureText(sl, 16)
	rl.DrawText(sl, i32(sr.x + sr.width / 2) - sw2 / 2, i32(sr.y + sr.height / 2) - 8, 16, rl.Color{190, 185, 200, 255})
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
	sw := f32(screen_w())
	sh := f32(screen_h())
	gap := f32(20)
	total := f32(n) * CHOICE_CARD_W + f32(n - 1) * gap
	start := sw / 2 - total / 2
	y := sh / 2 - CHOICE_CARD_H / 2 + 10
	return rl.Rectangle{start + f32(i) * (CHOICE_CARD_W + gap), y, CHOICE_CARD_W, CHOICE_CARD_H}
}

move_choice_skip_rect :: proc() -> rl.Rectangle {
	sw := f32(screen_w())
	sh := f32(screen_h())
	return rl.Rectangle{sw / 2 - 194, sh / 2 + CHOICE_CARD_H / 2 + 28, 180, 44}
}

// "What do I already run?" — the deck is right there while you pick.
move_choice_deck_rect :: proc() -> rl.Rectangle {
	r := move_choice_skip_rect()
	return rl.Rectangle{r.x + r.width + 16, r.y, r.width, r.height}
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
		mp := mouse_pos()
		for i in 0..<ch.count {
			if rl.CheckCollisionPointRec(mp, move_choice_card_rect(i, ch.count)) {
				take_choice(&g.colony, i)
				audio_play(.CONFIRM)
				return
			}
		}
		if rl.CheckCollisionPointRec(mp, move_choice_deck_rect()) {
			g.show_deck = true
			g.view_index = clamp(monster_by_id(&g.colony, ch.monster_id), 0, max(len(g.colony.roster)-1, 0))
			g.view_scroll = 0
			return
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
	sw := f32(screen_w())
	sh := f32(screen_h())
	rl.DrawRectangle(0, 0, i32(sw), i32(sh), rl.Color{0, 0, 0, 205})

	m := &g.colony.roster[mi]
	title := ch.kind == .LEVEL ? cstring("LEVEL UP!") : cstring("REWARD CARD")
	tcol := ch.kind == .LEVEL ? rl.Color{255, 235, 140, 255} : rl.Color{210, 160, 255, 255}
	tw := rl.MeasureText(title, 40)
	rl.DrawText(title, i32(sw) / 2 - tw / 2, 120, 40, tcol)

	sub: cstring
	if ch.kind == .LEVEL {
		sub = fmt.ctprintf("%s reached Lvl %d - choose a move to learn", m.creature.name, m.creature.level)
	} else {
		sub = fmt.ctprintf("%s earned a reward - choose a card", m.creature.name)
	}
	sw2 := rl.MeasureText(sub, 18)
	rl.DrawText(sub, i32(sw) / 2 - sw2 / 2, 172, 18, rl.Color{200, 200, 215, 255})

	mp := mouse_pos()
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
		rw := rl.MeasureText(rt, 15)
		rl.DrawText(rt, i32(rec.x) + i32(rec.width) / 2 - rw / 2, i32(tag_y), 15, rc)
	}

	draw_button(move_choice_skip_rect(), cstring("Skip"), true, BUTTON_PANEL, 18)
	draw_button(move_choice_deck_rect(), cstring("View deck"), true, BUTTON_PANEL, 18)
	hint := cstring("Click a card or press 1-3 to learn it   -   View deck shows what it already runs")
	hw := rl.MeasureText(hint, 15)
	rl.DrawText(hint, i32(sw) / 2 - hw / 2, i32(sh) - 44, 15, rl.Color{140, 140, 160, 255})
}

// ----------------------------------------------------------------------------
// Quest board: milestones + the run goal (Phase 22)
// ----------------------------------------------------------------------------

QUEST_ROWS_PER_COL :: 9

quest_panel_rect :: proc() -> rl.Rectangle {
	sw := f32(screen_w())
	sh := f32(screen_h())
	w := f32(1256)
	h := f32(560)
	return rl.Rectangle{sw / 2 - w / 2, sh / 2 - h / 2, w, h}
}

// The board runs to 20 entries, so it is laid out in two columns.
quest_row_rect :: proc(i: int) -> rl.Rectangle {
	p := quest_panel_rect()
	col := i / QUEST_ROWS_PER_COL
	row := i % QUEST_ROWS_PER_COL
	cw := (p.width - 40) / 3
	return rl.Rectangle{p.x + 20 + f32(col) * cw, p.y + 92 + f32(row) * 47, cw - 12, 43}
}

update_quests :: proc(g: ^Game) {
	if rl.IsKeyPressed(.ESCAPE) || rl.IsKeyPressed(.Q) {
		g.show_quests = false
	}
}

draw_quests :: proc(g: ^Game) {
	sw := f32(screen_w())
	sh := f32(screen_h())
	rl.DrawRectangle(0, 0, i32(sw), i32(sh), rl.Color{8, 10, 16, 245})

	p := quest_panel_rect()
	rl.DrawRectangleRounded(p, 0.03, 8, rl.Color{18, 20, 28, 248})
	rl.DrawRectangleRoundedLinesEx(p, 0.03, 8, 3, rl.Color{120, 200, 160, 255})

	done := milestones_done_count(&g.colony)
	total := len(MILESTONES)
	rl.DrawText("COLONY JOURNAL", i32(p.x) + 24, i32(p.y) + 16, 28, rl.Color{180, 235, 200, 255})
	rl.DrawText(fmt.ctprintf("Milestones %d / %d  -  each pays a crystal bounty; the board runs all the way to the five bosses", done, total),
		i32(p.x) + 24, i32(p.y) + 52, 15, rl.Color{180, 190, 200, 255})

	for k, i in Milestone_Kind {
		rec := quest_row_rect(i)
		is_done := g.colony.milestones[k]
		prog := min(milestone_progress(&g.colony, k), MILESTONES[k].target)
		tgt := MILESTONES[k].target
		bg := is_done ? rl.Color{26, 40, 30, 255} : rl.Color{24, 24, 32, 255}
		rl.DrawRectangleRounded(rec, 0.12, 6, bg)
		rl.DrawRectangleRoundedLinesEx(rec, 0.12, 6, 2, is_done ? rl.Color{120, 210, 150, 255} : rl.Color{56, 56, 70, 255})

		rl.DrawText(MILESTONES[k].desc, i32(rec.x) + 44, i32(rec.y) + 5, 16,
			is_done ? rl.Color{190, 240, 205, 255} : rl.Color{225, 225, 235, 255})

		bar := rl.Rectangle{rec.x + 44, rec.y + 27, rec.width - 200, 5}
		rl.DrawRectangleRounded(bar, 0.5, 3, rl.Color{40, 40, 50, 255})
		f := tgt > 0 ? clamp(f32(prog) / f32(tgt), 0, 1) : 0
		if f > 0 {
			rl.DrawRectangleRounded(rl.Rectangle{bar.x, bar.y, bar.width * f, bar.height}, 0.5, 3,
				is_done ? rl.Color{120, 210, 150, 255} : rl.Color{120, 170, 235, 255})
		}

		mark := is_done ? cstring("DONE") : fmt.ctprintf("%d/%d", prog, tgt)
		rew := fmt.ctprintf("+%d cr", MILESTONES[k].reward)
		rew_w := rl.MeasureText(rew, 14)
		mark_w := rl.MeasureText(mark, 15)
		rew_x := i32(rec.x + rec.width) - 12 - rew_w
		mark_x := rew_x - 12 - mark_w
		rl.DrawText(mark, mark_x, i32(rec.y) + 8, 15,
			is_done ? rl.Color{150, 230, 175, 255} : rl.Color{170, 175, 190, 255})
		rl.DrawText(rew, rew_x, i32(rec.y) + 8, 14, rl.Color{180, 150, 240, 255})

		cx, cy := rec.x + 22, rec.y + 21
		if is_done {
			rl.DrawCircleV(rl.Vector2{cx, cy}, 9, rl.Color{80, 170, 110, 255})
			rl.DrawText("v", i32(cx) - 4, i32(cy) - 9, 16, rl.Color{235, 255, 240, 255})
		} else {
			rl.DrawCircleLinesV(rl.Vector2{cx, cy}, 9, rl.Color{90, 90, 105, 255})
		}
	}

	if g.colony.goal_done {
		banner := cstring("OBJECTIVE COMPLETE - the colony is ascendant")
		bw := rl.MeasureText(banner, 20)
		rl.DrawText(banner, i32(p.x + p.width / 2) - bw / 2, i32(p.y + p.height) - 58, 20, rl.Color{255, 225, 130, 255})
	}

	hint := cstring("Q / Esc to close")
	hw := rl.MeasureText(hint, 16)
	rl.DrawText(hint, i32(p.x + p.width / 2) - hw / 2, i32(p.y + p.height) - 30, 16, rl.Color{150, 150, 170, 255})
}

GRAVE_ROWS :: 8

grave_panel_rect :: proc() -> rl.Rectangle {
	sw := f32(screen_w())
	sh := f32(screen_h())
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
	mp := mouse_pos()
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
	sw := f32(screen_w())
	sh := f32(screen_h())
	rl.DrawRectangle(0, 0, i32(sw), i32(sh), rl.Color{8, 10, 16, 245})

	p := grave_panel_rect()
	rl.DrawRectangleRounded(p, 0.03, 8, rl.Color{20, 18, 24, 248})
	rl.DrawRectangleRoundedLinesEx(p, 0.03, 8, 3, rl.Color{150, 130, 170, 255})

	rl.DrawText("HALL OF THE FALLEN", i32(p.x) + 24, i32(p.y) + 16, 28, rl.Color{210, 195, 225, 255})
	rl.DrawText(fmt.ctprintf("Gold: %d   -   revive the fallen, or salvage the gear they carried", colony_total_gold(&g.colony)),
		i32(p.x) + 24, i32(p.y) + 52, 15, rl.Color{180, 175, 195, 255})

	n := len(g.colony.graveyard)
	if n == 0 {
		rl.DrawText("No monsters have fallen. Yet.", i32(p.x) + 24, i32(p.y) + 104, 18, rl.Color{150, 150, 165, 255})
	} else {
		for i in g.grave_first..<min(g.grave_first + GRAVE_ROWS, n) {
			m := &g.colony.graveyard[i]
			rec := grave_row_rect(i, g.grave_first)
			rl.DrawRectangleRounded(rec, 0.12, 6, rl.Color{28, 24, 30, 255})
			rl.DrawRectangleRoundedLinesEx(rec, 0.12, 6, 2, rl.Color{70, 60, 74, 255})
			rl.DrawText(fmt.ctprintf("%s  Lvl %d", m.creature.name, m.creature.level),
				i32(rec.x) + 14, i32(rec.y) + 6, 18, rl.Color{225, 215, 225, 255})
			rl.DrawText(elements_label(creature_elements(&m.creature)), i32(rec.x) + 14, i32(rec.y) + 27, 13,
				element_color(creature_element(&m.creature)))
			item_txt := m.creature.item != .NONE ? fmt.ctprintf("item: %s", item_name(m.creature.item)) : cstring("no item")
			rl.DrawText(item_txt, i32(rec.x) + 150, i32(rec.y) + 27, 13, rl.Color{150, 210, 170, 255})

			cost := revive_cost(m)
			draw_button(grave_revive_rect(i, g.grave_first), fmt.ctprintf("Revive %dg", cost),
				colony_total_gold(&g.colony) >= cost, BUTTON_PANEL, 14)
			draw_button(grave_salvage_rect(i, g.grave_first), cstring("Salvage"),
				m.creature.item != .NONE && len(g.colony.items) < colony_item_cap(&g.colony), BUTTON_PANEL, 14)
		}
	}

	hint := cstring("Y / Esc close   |   Up/Down scroll")
	hw := rl.MeasureText(hint, 16)
	rl.DrawText(hint, i32(p.x + p.width / 2) - hw / 2, i32(p.y + p.height) - 28, 16, rl.Color{150, 150, 170, 255})
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
	x = clamp(x + 44, 16, f32(screen_w()) - w - 16)
	y = clamp(y - h / 2, 60, f32(screen_h()) - h - 16)
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
		mp := mouse_pos()
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
	rl.DrawText(fmt.ctprintf("Choose a monster  (%d here)", len(g.unit_picker_ids)),
		i32(p.x) + 12, i32(p.y) + 10, 16, rl.Color{200, 235, 210, 255})
	mp := mouse_pos()
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
		rl.DrawText(fmt.ctprintf("%d. %s  Lvl %d", i + 1, m.creature.name, m.creature.level),
			i32(rec.x) + 40, i32(rec.y) + 5, 15, rl.Color{230, 235, 245, 255})
		rl.DrawText(fmt.ctprintf("HP %d/%d   En %s/%s", m.creature.hp, m.creature.max_hp, fmt_num(m.creature.energy), fmt_num(m.creature.energy_max)),
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
	{"L", "move dex (every card, and who learns it)"},
	{"I", "improvements reference"},
	{"G", "inventory (held items and boss relics)"},
	{"U", "crystal progression tree"},
	{"Q", "quest journal / milestones"},
	{"J", "inventory (same as G)"},
	{"Y", "Hall of the Fallen (graveyard)"},
	{"C", "Nursery (breeding)"},
	{"H", "monster storage (Dens)"},
	{"O", "save / load (incl. autosave)"},
	{"Z", "toggle the minimap"},
	{"K", "this help"},
	{"P", "settings (sound, display, last turn)"},
	{"X", "mute / unmute sound"},
	{"`", "sample team (for testing the Arena tower)"},
	{"Esc", "close the current panel"},
}

help_panel_rect :: proc() -> rl.Rectangle {
	sw := f32(screen_w())
	sh := f32(screen_h())
	return rl.Rectangle{sw / 2 - 500, sh / 2 - 300, 1000, 600}
}

help_tips_rect :: proc() -> rl.Rectangle {
	p := help_panel_rect()
	return rl.Rectangle{p.x + 26, p.y + p.height - 66, 260, 42}
}

update_help :: proc(g: ^Game) {
	if rl.IsKeyPressed(.K) || rl.IsKeyPressed(.ESCAPE) {
		g.show_help = false
		return
	}
	// The tips window holds the opening hints again, in order.
	if rl.IsMouseButtonPressed(.LEFT) && rl.CheckCollisionPointRec(mouse_pos(), help_tips_rect()) {
		g.show_help = false
		g.show_tips = true
	}
}

draw_help :: proc(g: ^Game) {
	sw := f32(screen_w())
	sh := f32(screen_h())
	rl.DrawRectangle(0, 0, i32(sw), i32(sh), rl.Color{8, 10, 16, 246})

	p := help_panel_rect()
	draw_panel(p, rl.Color{18, 20, 28, 248}, rl.Color{150, 170, 220, 255})
	rl.DrawText("CONTROLS", i32(p.x) + 26, i32(p.y) + 16, 30, rl.Color{220, 228, 245, 255})
	rl.DrawText("Most panels close with their key or Esc. Esc never quits.", i32(p.x) + 26, i32(p.y) + 54, 15, rl.Color{170, 180, 200, 255})

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
	hw := rl.MeasureText(hint, 16)
	rl.DrawText(hint, i32(p.x + p.width / 2) - hw / 2, i32(p.y + p.height) - 30, 16, rl.Color{150, 150, 170, 255})
	draw_button(help_tips_rect(), "Tutorial tips", true, BUTTON_PANEL, 16)
}

// ----------------------------------------------------------------------------
// Tutorial tips window
//
// The opening hints again, in order, so they can be re-read (or turned off)
// once the first-turns box has gone.
// ----------------------------------------------------------------------------
TIPS_PANEL_H :: f32(500)

tips_panel_rect :: proc() -> rl.Rectangle {
	sw := f32(screen_w())
	sh := f32(screen_h())
	return rl.Rectangle{sw / 2 - 450, sh / 2 - TIPS_PANEL_H / 2, 900, TIPS_PANEL_H}
}

tips_toggle_rect :: proc() -> rl.Rectangle {
	p := tips_panel_rect()
	return rl.Rectangle{p.x + 26, p.y + p.height - 68, 330, 42}
}

update_tips :: proc(g: ^Game) {
	if rl.IsKeyPressed(.ESCAPE) || rl.IsKeyPressed(.K) {
		g.show_tips = false
		return
	}
	if rl.IsMouseButtonPressed(.LEFT) && rl.CheckCollisionPointRec(mouse_pos(), tips_toggle_rect()) {
		g.tutorial_done = !g.tutorial_done
	}
}

draw_tips :: proc(g: ^Game) {
	sw := f32(screen_w())
	sh := f32(screen_h())
	rl.DrawRectangle(0, 0, i32(sw), i32(sh), rl.Color{8, 10, 16, 246})

	p := tips_panel_rect()
	draw_panel(p, rl.Color{18, 20, 28, 248}, rl.Color{140, 190, 235, 255})
	rl.DrawText("TIPS", i32(p.x) + 26, i32(p.y) + 16, 30, rl.Color{220, 228, 245, 255})
	rl.DrawText("The opening hints, in order - one per turn for the first eight turns.", i32(p.x) + 26, i32(p.y) + 54, 15, rl.Color{170, 180, 200, 255})

	y := p.y + 94
	for text, i in TUTORIAL_HINTS {
		rl.DrawText(fmt.ctprintf("%d.", i + 1), i32(p.x) + 26, i32(y), 16, rl.Color{140, 190, 235, 255})
		y = f32(draw_text_wrapped(fmt.ctprintf("%s", text), i32(p.x) + 54, i32(y), 16, i32(p.width) - 104, rl.Color{212, 220, 238, 255}))
		y += 8
	}

	draw_button(tips_toggle_rect(), g.tutorial_done ? cstring("Show tips at start: OFF") : cstring("Show tips at start: ON"), true, BUTTON_PANEL, 16)
	hint := cstring("K / Esc to close")
	hw := rl.MeasureText(hint, 16)
	rl.DrawText(hint, i32(p.x + p.width / 2) - hw / 2, i32(p.y + p.height) - 30, 16, rl.Color{150, 150, 170, 255})
}

draw_help_row :: proc(x, y, key_w: f32, line: Help_Line) {
	rl.DrawText(line.key, i32(x), i32(y), 16, rl.Color{235, 225, 170, 255})
	rl.DrawText(line.action, i32(x + key_w), i32(y), 15, rl.Color{195, 200, 215, 255})
}

// ----------------------------------------------------------------------------
// Confirmation dialog (Phase 24)
//
// A small modal yes/no for destructive actions (forgetting a card, overwriting a
// building). Enter / click Confirm accepts; Esc / N / Cancel declines.
// ----------------------------------------------------------------------------

Confirm_Kind :: enum { NONE, FORGET_CARD, OVERWRITE_BUILD, DEMOLISH }

confirm_panel_rect :: proc() -> rl.Rectangle {
	sw := f32(screen_w())
	sh := f32(screen_h())
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
		mp := mouse_pos()
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
	sw := f32(screen_w())
	sh := f32(screen_h())
	rl.DrawRectangle(0, 0, i32(sw), i32(sh), rl.Color{0, 0, 0, 175})
	p := confirm_panel_rect()
	draw_panel(p, rl.Color{22, 20, 26, 250}, rl.Color{220, 160, 120, 255})
	rl.DrawText("Are you sure?", i32(p.x) + 24, i32(p.y) + 18, 24, rl.Color{245, 220, 200, 255})
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
	sw := f32(screen_w())
	sh := f32(screen_h())
	w := f32(640)
	h := f32(660)
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
	return rl.Rectangle{p.x + 200, p.y + 564, 170, 38}
}

update_settings :: proc(g: ^Game) {
	if rl.IsKeyPressed(.P) || rl.IsKeyPressed(.ESCAPE) {
		g.show_settings = false
		return
	}
	mp := mouse_pos()

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
	if rl.CheckCollisionPointRec(mp, settings_toggle_rect(3)) { g.show_terrain_legend = !g.show_terrain_legend; return }
	if rl.CheckCollisionPointRec(mp, settings_toggle_rect(4)) { g.show_key_hints = !g.show_key_hints; return }
	if rl.CheckCollisionPointRec(mp, settings_autosave_rect()) { g.autosave_on = !g.autosave_on; return }
}

draw_settings :: proc(g: ^Game) {
	sw := f32(screen_w())
	sh := f32(screen_h())
	rl.DrawRectangle(0, 0, i32(sw), i32(sh), rl.Color{8, 10, 16, 246})

	p := settings_panel_rect()
	draw_panel(p, rl.Color{18, 20, 28, 248}, rl.Color{150, 170, 220, 255})
	rl.DrawText("SETTINGS", i32(p.x) + 26, i32(p.y) + 16, 30, rl.Color{220, 228, 245, 255})

	// Last turn read-out.
	rl.DrawText("LAST TURN", i32(p.x) + 26, i32(p.y) + 62, 15, rl.Color{150, 160, 185, 255})
	if len(g.summary) == 0 {
		rl.DrawText("No turns played yet.", i32(p.x) + 200, i32(p.y) + 62, 15, rl.Color{140, 140, 160, 255})
	} else {
		for s, i in g.summary {
			rl.DrawText(fmt.ctprintf("%s", s), i32(p.x) + 200, i32(p.y) + 62 + i32(i) * 20, 15, rl.Color{200, 205, 220, 255})
		}
	}

	// Sound.
	rl.DrawText("SOUND", i32(p.x) + 26, i32(p.y) + 170, 15, rl.Color{150, 160, 185, 255})
	vr := settings_volume_rect()
	rl.DrawRectangleRounded(vr, 0.5, 4, rl.Color{40, 40, 52, 255})
	frac := clamp(audio.volume, 0, 1)
	if frac > 0 {
		rl.DrawRectangleRounded(rl.Rectangle{vr.x, vr.y, vr.width * frac, vr.height}, 0.5, 4, rl.Color{120, 180, 235, 255})
	}
	rl.DrawCircleV(rl.Vector2{vr.x + vr.width * frac, vr.y + vr.height / 2}, 9, rl.Color{220, 232, 245, 255})
	rl.DrawText(fmt.ctprintf("Volume %d%%", int(frac * 100)), i32(p.x) + 200, i32(p.y) + 170, 15, rl.Color{200, 205, 220, 255})
	draw_button(settings_mute_rect(), audio.muted ? cstring("Sound: MUTED") : cstring("Sound: ON"), true, BUTTON_PANEL, 16)

	// Display.
	rl.DrawText("DISPLAY", i32(p.x) + 26, i32(p.y) + 276, 15, rl.Color{150, 160, 185, 255})
	draw_button(settings_toggle_rect(0), fmt.ctprintf("Minimap: %s", g.show_minimap ? "ON" : "OFF"), true, BUTTON_PANEL, 16)
	draw_button(settings_toggle_rect(1), fmt.ctprintf("Tooltips: %s", g.tooltips_on ? "ON" : "OFF"), true, BUTTON_PANEL, 16)
	draw_button(settings_toggle_rect(2), fmt.ctprintf("FPS counter: %s", g.show_fps ? "ON" : "OFF"), true, BUTTON_PANEL, 16)
	draw_button(settings_toggle_rect(3), fmt.ctprintf("Terrain legend: %s", g.show_terrain_legend ? "ON" : "OFF"), true, BUTTON_PANEL, 16)
	draw_button(settings_toggle_rect(4), fmt.ctprintf("Key hints: %s", g.show_key_hints ? "ON" : "OFF"), true, BUTTON_PANEL, 16)

	// Autosave.
	rl.DrawText("AUTOSAVE", i32(p.x) + 26, i32(p.y) + 540, 15, rl.Color{150, 160, 185, 255})
	draw_button(settings_autosave_rect(), fmt.ctprintf("Autosave: %s", g.autosave_on ? "ON" : "OFF"), true, BUTTON_PANEL, 16)
	rl.DrawText(fmt.ctprintf("every %d turns", AUTOSAVE_EVERY), i32(p.x) + 384, i32(p.y) + 574, 14, rl.Color{150, 150, 170, 255})

	hint := cstring("P / Esc to close")
	hw := rl.MeasureText(hint, 16)
	rl.DrawText(hint, i32(p.x + p.width / 2) - hw / 2, i32(p.y + p.height) - 28, 16, rl.Color{150, 150, 170, 255})
}
