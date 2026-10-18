package main

import rl "vendor:raylib"
import "core:fmt"
import "core:math"
// ----------------------------------------------------------------------------
// Opening tutorial hints
//
// One short hint per turn for the first few turns, shown in a box the player
// can click away. Kept purely advisory — nothing is gated behind it.
// ----------------------------------------------------------------------------
tutorial_rect :: proc() -> rl.Rectangle {
	sw := f32(screen_w())
	return rl.Rectangle{sw / 2 - 330, 132, 660, 62}
}

TUTORIAL_HINTS := [?]string{
	"Press B and click a tile to build. A Farm feeds your monsters - they eat every turn.",
	"Click a tile next to your monster to move it. Right-drag or WASD pans, the wheel zooms.",
	"Click a wild monster beside you to attack it. Click your own tile to pick a different monster.",
	"Build a Granary or Silo near your Farms so the food actually reaches your stockpile.",
	"Winning a fight drops loot and offers a new card. Press V to see the deck.",
	"Press T on a Trading Post tile to heal, buy capture cards or recruit monsters.",
	"Press M for the monster dex, L for the move dex, I for improvements, K for every control.",
	"That is the basics - the tips stop here. K brings the full control list back any time.",
}

// The hint for this turn, if the tips are still running.
tutorial_hint :: proc(turn: int) -> (string, bool) {
	if turn < 0 || turn >= len(TUTORIAL_HINTS) {
		return "", false
	}
	return TUTORIAL_HINTS[turn], true
}

draw_colony :: proc(g: ^Game) {
	rl.ClearBackground(rl.Color{10, 12, 16, 255})

	sw := f32(screen_w())
	sh := f32(screen_h())
	margin := f32(100) * g.renderer.zoom
	now := f32(rl.GetTime())
	z := g.renderer.zoom

	// Tremor shake from a world event.
	if g.colony.tremor > 0 {
		f := clamp(g.colony.tremor / TREMOR_DUR, 0, 1)
		mag := 7.0 * f * z
		g.renderer.shake_x = math.sin(now * 71.0) * mag
		g.renderer.shake_y = math.cos(now * 83.0) * mag
	} else {
		g.renderer.shake_x, g.renderer.shake_y = 0, 0
	}

	// Tiles (fog of war). Unexplored tiles get a dim "unknown" hex so the map
	// reads as fog rather than holes in the dark background. The map is infinite,
	// so visit only the hexes currently on screen (via the tile index) rather
	// than every materialized tile.
	min_q, max_q, min_r, max_r := visible_hex_bounds(&g.renderer)
	for q in min_q..=max_q {
		for r in min_r..=max_r {
			t := tile_at(&g.colony, Hex{q, r})
			if t == nil {
				continue
			}
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
			draw_tile_ambient(t.terrain, t.hex, cx, cy, z, now)

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
				if t.improvement == .NONE || t.overlay == .ROAD {
					// Alone on the tile, or a ground overlay under the building.
					draw_improvement_icon(t.overlay, cx + sx, cy + sy, g.renderer.zoom)
				} else {
					// A fortification sharing the tile: draw it smaller, offset, so
					// it doesn't hide behind the building icon.
					off := 0.42 * g.renderer.hex_size * g.renderer.zoom
					draw_improvement_icon(t.overlay, cx + sx + off, cy + sy + off, g.renderer.zoom * 0.62)
				}
			}
			if t.improvement != .NONE {
				draw_improvement_icon(t.improvement, cx + sx, cy + sy, g.renderer.zoom)
				#partial switch t.improvement {
				case .TURRET:
					draw_charge_bar(t, cx + sx, cy + sy, g.renderer.zoom, TURRET_CAP + upgrade_turret_cap(&g.colony))
				case .MENDER:
					draw_charge_bar(t, cx + sx, cy + sy, g.renderer.zoom, MENDER_CAP)
				case .BATTERY:
					draw_charge_bar(t, cx + sx, cy + sy, g.renderer.zoom, BATTERY_CAP)
				case:
				}
			}
		}
	}

	draw_inspect_radii(g)
	draw_build_selection(g)
	draw_move_highlights(g)
	draw_map_monsters(g)
	draw_scuffles(g)
	draw_carrion(g)
	draw_tile_floats(g)
	draw_hover_marker(&g.renderer, hex_renderer_hovered(&g.renderer), true)
	draw_colony_hud(g)
	draw_roster_panel(g)
	draw_end_turn_button(g)
	if g.show_terrain_legend {
		draw_terrain_legend()
	}
	draw_minimap(g)
	draw_poi_markers(g)
	draw_tile_hover_tooltip(g)
}

// Edge arrows pointing to nearby points of interest that are off-screen, so
// known Arenas / Boss Rooms / Trading Posts are easy to find again.
POI_MARKER_RANGE :: 28
POI_MARKER_MAX   :: 6

draw_poi_markers :: proc(g: ^Game) {
	sw := f32(screen_w())
	sh := f32(screen_h())
	center := screen_to_hex(&g.renderer, g.renderer.origin_x, g.renderer.origin_y)

	best_d: [POI_MARKER_MAX]int
	best_h: [POI_MARKER_MAX]Hex
	best_c: [POI_MARKER_MAX]rl.Color
	best_l: [POI_MARKER_MAX]cstring
	n := 0
	for t in g.colony.tiles {
		if !t.revealed {
			continue
		}
		col: rl.Color
		label: cstring
		#partial switch t.terrain {
		case .ARENA:        col = rl.Color{245, 95, 95, 255}; label = "Arena"
		case .BOSS_ROOM:    col = rl.Color{235, 120, 210, 255}; label = "Boss"
		case .TRADING_POST: col = rl.Color{245, 210, 95, 255}; label = "Trade"
		case .CRYSTAL_COVE: col = rl.Color{150, 210, 255, 255}; label = "Crystal"
		case:               continue
		}
		cx, cy := hex_to_screen(&g.renderer, t.hex)
		if cx >= 0 && cx <= sw && cy >= 0 && cy <= sh {
			continue // on screen: the tile itself shows it
		}
		d := hex_distance(center, t.hex)
		if d > POI_MARKER_RANGE {
			continue
		}
		if n < POI_MARKER_MAX {
			best_d[n], best_h[n], best_c[n], best_l[n] = d, t.hex, col, label
			n += 1
		} else {
			far := 0
			for k in 1..<POI_MARKER_MAX {
				if best_d[k] > best_d[far] {
					far = k
				}
			}
			if d < best_d[far] {
				best_d[far], best_h[far], best_c[far], best_l[far] = d, t.hex, col, label
			}
		}
	}

	for k in 0..<n {
		cx, cy := hex_to_screen(&g.renderer, best_h[k])
		ex := clamp(cx, 26, sw - 26)
		ey := clamp(cy, 26, sh - 26)
		ang := math.atan2(cy - ey, cx - ex) * 180.0 / math.PI
		rl.DrawPoly(rl.Vector2{ex, ey}, 3, 11, ang, best_c[k])
		lw := rl.MeasureText(best_l[k], 12)
		rl.DrawText(best_l[k], i32(ex) - lw / 2, i32(ey) + 14, 12, best_c[k])
	}
}

// Tooltip for the tile under the cursor, when the cursor is over the map (not
// the HUD panels). Shows terrain, any building/overlay, and who's standing here.
draw_tile_hover_tooltip :: proc(g: ^Game) {
	if g.build_mode {
		return
	}
	sw := f32(screen_w())
	sh := f32(screen_h())
	mp := mouse_pos()
	if mp.x > sw - 248 || mp.y > sh - 136 || rl.CheckCollisionPointRec(mp, minimap_rect()) {
		return // over the roster / end-turn controls / minimap
	}
	mh := hex_renderer_hovered(&g.renderer)
	t := tile_at(&g.colony, mh)
	if t == nil || !t.revealed {
		return
	}
	wilds, mine := 0, 0
	for m in g.colony.roster {
		if hex_equal(m.pos, mh) {
			if m.wild {
				wilds += 1
			} else {
				mine += 1
			}
		}
	}
	imp_txt := t.improvement != .NONE ? fmt.aprintf("  |  %s (%d/%d hp)", improvement_name(t.improvement), t.improvement_hp, improvement_hp_cap(&g.colony, t.improvement)) : ""
	oc_txt := t.overlay != .NONE ? fmt.aprintf("  |  overlay: %s", improvement_name(t.overlay)) : ""
	units := fmt.aprintf("  |  %d wild, %d yours", wilds, mine)
	tooltip_set("%s%s%s%s", terrain_name(t.terrain), imp_txt, oc_txt, units)
	delete(imp_txt)
	delete(oc_txt)
	delete(units)
}

// A bold, pulsing marker on the tile you've picked in build mode, so it's
// obvious which hex the build panel is acting on.
// Effect radius of an improvement (0 = none), for the build-mode preview.
improvement_effect_radius :: proc(g: ^Game, im: Improvement) -> int {
	#partial switch im {
	case .FOUNTAIN:   return FOUNTAIN_RANGE + upgrade_fountain_range(&g.colony)
	case .BEACON:     return BEACON_GUARD
	case .WATCHTOWER: return WATCHTOWER_DETER + upgrade_vigilance(&g.colony)
	case .TURRET:     return TURRET_RANGE + upgrade_turret_range(&g.colony)
	case .SCARECROW:  return SCARECROW_PANIC + upgrade_warding(&g.colony)
	case .MENDER:     return MENDER_REPAIR_RANGE + upgrade_mender_range(&g.colony)
	case:             return 0
	}
	return 0
}

draw_build_selection :: proc(g: ^Game) {
	if !g.build_mode || !g.has_build {
		return
	}
	z := g.renderer.zoom
	pulse := 0.5 + 0.5 * math.sin(f32(rl.GetTime()) * 4.0)

	// Preview the hovered improvement's effect radius on the map.
	if g.build_preview != .NONE {
		if r := improvement_effect_radius(g, g.build_preview); r > 0 {
			disk := make([dynamic]Hex, 0); defer delete(disk)
			hex_range(g.build_hex, r, &disk)
			for h in disk {
				if t := tile_at(&g.colony, h); t != nil {
					draw_hex_outline(&g.renderer, h, rl.Color{140, 200, 255, u8(70 + 40 * pulse)}, 1.5 * z)
				}
			}
		}
	}

	draw_hex_filled(&g.renderer, g.build_hex, rl.Color{140, 235, 165, u8(30 + 24 * pulse)})
	draw_hex_outline(&g.renderer, g.build_hex, rl.Color{150, 250, 190, 255}, 5.0 * z)
	cx, cy := hex_to_screen(&g.renderer, g.build_hex)
	label := cstring("BUILD HERE")
	lw := rl.MeasureText(label, 15)
	rl.DrawText(label, i32(cx) - lw / 2, i32(cy - 40 * z), 15, rl.Color{190, 255, 210, 245})
}

// A raid alpha gets a gold halo, a thick pulsing ring, a crown and a label so
// it's unmistakable among the rank-and-file raiders.
draw_alpha_marker :: proc(px, by, radius, z, pulse: f32) {
	for k in 0..<3 {
		rr := radius + (2.0 + f32(k) * 3.0 + 2.0 * pulse) * z
		rl.DrawCircleLinesV(rl.Vector2{px, by}, rr, rl.Color{255, 175, 60, u8(170 - k * 50)})
	}
	rl.DrawCircleLinesV(rl.Vector2{px, by}, radius + (2.5 + 1.5 * pulse) * z, rl.Color{255, 225, 120, 255})

	// A little crown above the head.
	top := by - radius - (9.0 + 1.5 * pulse) * z
	w := 7.5 * z
	h := 8.5 * z
	gold := rl.Color{255, 205, 80, 255}
	light := rl.Color{255, 240, 150, 255}
	rl.DrawTriangle(rl.Vector2{px - w, top + h}, rl.Vector2{px - w * 0.6, top}, rl.Vector2{px - w * 0.18, top + h}, gold)
	rl.DrawTriangle(rl.Vector2{px - w * 0.5, top + h}, rl.Vector2{px, top - h * 0.4}, rl.Vector2{px + w * 0.5, top + h}, light)
	rl.DrawTriangle(rl.Vector2{px + w * 0.18, top + h}, rl.Vector2{px + w * 0.6, top}, rl.Vector2{px + w, top + h}, gold)
	rl.DrawRectangleRec(rl.Rectangle{px - w, top + h, w * 2, 3.0 * z}, light)

	// Label (kept legible by scaling with zoom).
	fs := i32(clamp(11.0 * z, 9.0, 16.0))
	lbl := cstring("ALPHA")
	lw := rl.MeasureText(lbl, fs)
	ly := i32(top - h * 0.5 - f32(fs) - 2 * z)
	rl.DrawText(lbl, i32(px) - lw / 2 + 1, ly + 1, fs, rl.Color{40, 20, 0, 200})
	rl.DrawText(lbl, i32(px) - lw / 2, ly, fs, rl.Color{255, 235, 150, 255})
}

draw_map_monsters :: proc(g: ^Game) {
	now := f32(rl.GetTime())
	z := g.renderer.zoom

	// One pass to count monsters per tile, then a running index per tile, so the
	// "which of N on this hex am I" ring placement is O(roster) not O(roster^2).
	clear(&g.ring_total)
	clear(&g.ring_seen)
	for m in g.colony.roster {
		tile := tile_at(&g.colony, m.pos)
		if tile == nil || !tile.revealed {
			continue
		}
		g.ring_total[hex_key(m.pos)] += 1
	}

	for i in 0..<len(g.colony.roster) {
		m := &g.colony.roster[i]
		tile := tile_at(&g.colony, m.pos)
		if tile == nil || !tile.revealed {
			continue
		}
		// Ring position among ALL monsters on the tile (yours and wilds).
		key := hex_key(m.pos)
		idx := g.ring_seen[key]
		g.ring_seen[key] = idx + 1
		n := max(g.ring_total[key], 1)
		px, py := world_to_screen(&g.renderer, m.anim_x, m.anim_y)
		if n > 1 {
			angle := f32(idx) / f32(n) * 2.0 * math.PI - math.PI / 2.0
			px += math.cos(angle) * 15.0 * z
			py += math.sin(angle) * 15.0 * z
		}
		radius := (7.5 + min(f32(m.creature.level), 14) * 0.45) * z
		bob := math.sin(now * 3.0 + f32(i) * 0.7) * 1.6 * z
		px += math.sin(now * 1.3 + f32(i) * 1.1) * 1.2 * z // slow idle drift
		by := py + bob

		// Ground shadow stays put while the body bobs.
		rl.DrawEllipse(i32(px), i32(py + radius * 0.9), radius * 0.9, radius * 0.35, rl.Color{0, 0, 0, 90})
		rl.DrawCircleV(rl.Vector2{px, by}, radius, creature_color(&m.creature))
		rl.DrawCircleV(rl.Vector2{px - radius * 0.3, by - radius * 0.3}, radius * 0.32, rl.Color{255, 255, 255, 45})

		// Arrival burst for a newly-spawned monster.
		if age := now - m.spawn_t0; age >= 0 && age < SPAWN_BURST {
			q := age / SPAWN_BURST
			rl.DrawCircleLinesV(rl.Vector2{px, by}, radius + q * 26.0 * z, rl.Color{220, 235, 255, u8((1.0 - q) * 180)})
		}
		if m.wild {
			// Wilds: pulsing red ring so they read as hostile.
			pulse := 0.5 + 0.5 * math.sin(now * 4.0 + f32(i))
			rl.DrawCircleLinesV(rl.Vector2{px, by}, radius, rl.Color{240, 70, 70, 255})
			rl.DrawCircleLinesV(rl.Vector2{px, by}, radius + (2.0 + 1.5 * pulse) * z, rl.Color{120, 20, 20, 255})
			switch m.role {
			case .RAIDER:
				// A raid member: a warm ring between a plain wild and an alpha.
				rl.DrawCircleLinesV(rl.Vector2{px, by}, radius + (3.0 + 1.5 * pulse) * z, rl.Color{255, 120, 70, 230})
			case .SIEGE:
				// A siege beast: a heavy, double red ring aimed at your buildings.
				rl.DrawCircleLinesV(rl.Vector2{px, by}, radius + (3.0 + 1.5 * pulse) * z, rl.Color{255, 80, 60, 240})
				rl.DrawCircleLinesV(rl.Vector2{px, by}, radius + (6.0 + 1.5 * pulse) * z, rl.Color{255, 150, 60, 200})
			case .STALKER:
				// A stalker: a pale, flickering ring that ghosts through walls.
				alpha := u8(120 + 100 * pulse)
				rl.DrawCircleLinesV(rl.Vector2{px, by}, radius + (3.0 + 2.5 * pulse) * z, rl.Color{150, 240, 235, alpha})
			case .ALPHA:
				draw_alpha_marker(px, by, radius, z, pulse)
			case .BOSS:
				// A boss: a thick, pulsing gold-and-crimson halo.
				for k in 0..<3 {
					rr := radius + (4.0 + f32(k) * 3.5 + 2.0 * pulse) * z
					rl.DrawCircleLinesV(rl.Vector2{px, by}, rr, rl.Color{255, 200, 70, u8(200 - k * 45)})
				}
			case .CRONY:
				rl.DrawCircleLinesV(rl.Vector2{px, by}, radius + (3.0 + 1.5 * pulse) * z, rl.Color{200, 170, 90, 180})
			case .WILD:
			}
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

// Remains left where a wild was killed — scavengers drift toward it.
draw_carrion :: proc(g: ^Game) {
	for t in g.colony.tiles {
		if !t.revealed || t.carrion <= 0 {
			continue
		}
		cx, cy := hex_to_screen(&g.renderer, t.hex)
		z := g.renderer.zoom
		rl.DrawCircleV(rl.Vector2{cx, cy + 2 * z}, 9 * z, rl.Color{70, 44, 44, 70})
		rl.DrawLineEx(rl.Vector2{cx - 6 * z, cy + 4 * z}, rl.Vector2{cx + 5 * z, cy - 2 * z}, 2.0 * z, rl.Color{222, 216, 198, 215})
		rl.DrawCircleV(rl.Vector2{cx - 6 * z, cy + 4 * z}, 1.9 * z, rl.Color{232, 228, 212, 230})
		rl.DrawCircleV(rl.Vector2{cx + 5 * z, cy - 2 * z}, 1.9 * z, rl.Color{232, 228, 212, 230})
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
		case .HEAL:
			text = fmt.ctprintf("+%dhp", f.amount)
			col = rl.Color{150, 240, 165, alpha}
		case .GROW:
			text = cstring("grows!")
			col = rl.Color{235, 200, 255, alpha}
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

// A tiny charge bar under an energy building (Turret / Mender / Battery), so you
// can see at a glance whether it is full or running dry.
draw_charge_bar :: proc(t: ^Tile, cx, cy, z: f32, cap: int) {
	if cap <= 0 {
		return
	}
	w := 22 * z
	h := max(3 * z, 2)
	x := cx - w / 2
	y := cy + 16 * z
	rl.DrawRectangleRounded(rl.Rectangle{x, y, w, h}, 0.5, 3, rl.Color{22, 22, 30, 210})
	f := clamp(f32(t.stored) / f32(cap), 0, 1)
	if f > 0 {
		rl.DrawRectangleRounded(rl.Rectangle{x, y, w * f, h}, 0.5, 3, rl.Color{242, 200, 70, 255})
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
	case .BATTERY:
		return {Coverage_Ring{BATTERY_RANGE, rl.Color{242, 200, 70, 34}}, Coverage_Ring{}}, 1
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
	// A monster that has already acted can't move this turn.
	acted := m.acted
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
		if acted || !passable || full {
			edge = rl.Color{245, 105, 105, 235}
		} else if !affordable {
			edge = rl.Color{245, 205, 120, 235}
		}
		draw_hex_outline(&g.renderer, n, edge, 3.5 * g.renderer.zoom)

		if t.revealed && passable && !full && !acted {
			cx, cy := hex_to_screen(&g.renderer, n)
			label := fmt.ctprintf("%s", fmt_num(cost))
			lw := rl.MeasureText(label, 14)
			rl.DrawText(label, i32(cx) - lw / 2, i32(cy) + 14, 14, rl.Color{230, 240, 210, 255})
		}
	}
}

// Hit test for a HUD text run at (x, y) of the given pixel width.
hud_hit :: proc(x: i32, w: i32, y: i32) -> bool {
	return rl.CheckCollisionPointRec(mouse_pos(), rl.Rectangle{f32(x), f32(y) - 2, f32(w), 28})
}

draw_colony_hud :: proc(g: ^Game) {
	sw := f32(screen_w())
	sh := f32(screen_h())

	rl.DrawText("THE COLONY", 20, 16, 26, rl.Color{215, 215, 235, 255})
	res := fmt.ctprintf("Floor %d    Turn %d    Threat %d    Milestones %d/%d    Relics %d",
		g.colony.floor, g.colony.turn, colony_escalation(&g.colony), milestones_done_count(&g.colony), len(MILESTONES), relic_total(&g.colony))
	rl.DrawText(res, 20, 48, 18, rl.Color{140, 140, 165, 255})
	if g.colony.goal_done {
		gw := rl.MeasureText("OBJECTIVE COMPLETE", 18)
		rl.DrawText("OBJECTIVE COMPLETE", i32(sw) - gw - 256, 48, 18, rl.Color{255, 225, 130, 255})
	}

	x := i32(20)
	nb1, nb2: [24]u8
	gold := fmt.ctprintf("Gold %s / %s", fmt_thousands(nb1[:], colony_total_gold(&g.colony)), fmt_thousands(nb2[:], g.colony.gold_cap))
	rl.DrawText(gold, x, 78, 20, rl.Color{240, 205, 90, 255})
	if hud_hit(x, rl.MeasureText(gold, 20), 78) {
		tooltip_set("Gold %s / %s. Mines, Quarries and defeated wilds pay it in; buildings, recruits and repairs spend it.", fmt_thousands(nb1[:], colony_total_gold(&g.colony)), fmt_thousands(nb2[:], g.colony.gold_cap))
	}
	x += rl.MeasureText(gold, 20) + 30

	if g.colony.food_cap == 0 {
		rl.DrawText("Food: no storage", x, 78, 20, rl.Color{150, 170, 150, 255})
		if hud_hit(x, rl.MeasureText("Food: no storage", 20), 78) {
			tooltip_set("No food storage yet - build a Granary or Silo so Farms can stockpile food.")
		}
		x += rl.MeasureText("Food: no storage", 20) + 30
	} else {
		food := fmt.ctprintf("Food stored %s / %s", fmt_thousands(nb1[:], colony_total_food(&g.colony)), fmt_thousands(nb2[:], g.colony.food_cap))
		rl.DrawText(food, x, 78, 20, rl.Color{140, 220, 130, 255})
		if hud_hit(x, rl.MeasureText(food, 20), 78) {
			tooltip_set("Food stored %s / %s. Your monsters eat each turn (upkeep); a starving colony loses HP.", fmt_thousands(nb1[:], colony_total_food(&g.colony)), fmt_thousands(nb2[:], g.colony.food_cap))
		}
		x += rl.MeasureText(food, 20) + 30
	}

	cryst := fmt.ctprintf("Crystals %s", fmt_thousands(nb1[:], g.colony.crystals))
	rl.DrawText(cryst, x, 78, 20, rl.Color{150, 210, 255, 255})
	if hud_hit(x, rl.MeasureText(cryst, 20), 78) {
		tooltip_set("Crystals %s. Spend them in the progression tree (U). Mostly won from the Arena and Boss Rooms.", fmt_thousands(nb1[:], g.colony.crystals))
	}
	x += rl.MeasureText(cryst, 20) + 30

	// Heat (Phase D): raid pressure. Turns shown once a raid is possible.
	heat_col := g.colony.heat >= RAID_MIN_HEAT * 2 ? rl.Color{235, 120, 100, 255} : rl.Color{220, 170, 120, 255}
	heat := fmt.ctprintf("Heat %d", g.colony.heat)
	rl.DrawText(heat, x, 78, 20, heat_col)
	if hud_hit(x, rl.MeasureText(heat, 20), 78) {
		tooltip_set("Heat %d. Every improvement and monster level adds heat, and nothing lowers it. Higher heat means bigger, tougher raids.", g.colony.heat)
	}
	x += rl.MeasureText(heat, 20) + 30
	if g.colony.turn >= RAID_GRACE && g.colony.heat >= RAID_MIN_HEAT {
		raid := fmt.ctprintf("Raid in %d", g.colony.raid_timer)
		rl.DrawText(raid, x, 78, 20, rl.Color{235, 150, 120, 255})
		x += rl.MeasureText(raid, 20) + 30
	} else if g.colony.turn < RAID_GRACE {
		raid := fmt.ctprintf("Raids from turn %d", RAID_GRACE)
		rl.DrawText(raid, x, 78, 20, rl.Color{170, 170, 190, 255})
		x += rl.MeasureText(raid, 20) + 30
	} else {
		rl.DrawText("Raid calm (low heat)", x, 78, 20, rl.Color{170, 190, 170, 255})
		x += rl.MeasureText("Raid calm (low heat)", 20) + 30
	}

	upkeep := 0
	for &m in g.colony.roster {
		if !m.wild {
			upkeep += monster_upkeep(&m)
		}
	}
	// Global per-turn production, shown as gross + net (after upkeep). Net food
	// goes red when the colony is starving.
	x = 20
	fp := colony_food_production(&g.colony)
	net_food := fp - upkeep
	food_prod := fmt.ctprintf("Food +%d/turn (net %+d)", fp, net_food)
	rl.DrawText(food_prod, x, 106, 16, net_food < 0 ? rl.Color{235, 120, 110, 255} : rl.Color{140, 220, 130, 255})
	x += rl.MeasureText(food_prod, 16) + 24
	gold_prod := fmt.ctprintf("Gold +%d/turn", colony_gold_production(&g.colony))
	rl.DrawText(gold_prod, x, 106, 16, rl.Color{240, 205, 90, 255})
	x += rl.MeasureText(gold_prod, 16) + 24
	up := fmt.ctprintf("Upkeep %d food/turn   Monsters %d (%d stored)   Capture cards %d", upkeep, player_monster_count(&g.colony), len(g.colony.storage), g.colony.capture_cards)
	rl.DrawText(up, x, 106, 16, rl.Color{150, 150, 175, 255})

	// Hovered tile info + occupants (inspect without attacking).
	hovered := hex_renderer_hovered(&g.renderer)
	if t := tile_at(&g.colony, hovered); t != nil && t.revealed {
		info: cstring
		if t.improvement != .NONE {
			if t.overlay != .NONE {
				info = fmt.ctprintf("Tile: %s  -  %s HP %d/%d  (+ %s HP %d/%d)", terrain_name(t.terrain), improvement_name(t.improvement), t.improvement_hp, improvement_hp_cap(&g.colony, t.improvement), improvement_name(t.overlay), t.overlay_hp, improvement_max_hp(t.overlay))
			} else {
				info = fmt.ctprintf("Tile: %s  -  %s HP %d/%d", terrain_name(t.terrain), improvement_name(t.improvement), t.improvement_hp, improvement_hp_cap(&g.colony, t.improvement))
			}
		} else if t.overlay != .NONE {
			info = fmt.ctprintf("Tile: %s  -  %s HP %d/%d", terrain_name(t.terrain), improvement_name(t.overlay), t.overlay_hp, improvement_max_hp(t.overlay))
		} else {
			info = fmt.ctprintf("Tile: %s", terrain_name(t.terrain))
		}
		rl.DrawText(info, 236, 130, 16, rl.Color{180, 180, 200, 255})

		// Special tiles: say what you can actually do standing here.
		special := i32(0)
		#partial switch t.terrain {
		case .ARENA:
			rl.DrawText("Arena: stand a monster here, then press T to challenge it (gold in, crystals out).", 236, 148, 14, rl.Color{235, 205, 130, 255})
			special = 18
		case .TRADING_POST:
			rl.DrawText("Trading Post: stand a monster here, then press T to heal, recruit or buy capture cards.", 236, 148, 14, rl.Color{200, 220, 160, 255})
			special = 18
		case .BOSS_ROOM:
			rl.DrawText("Boss Room: a boss pack lairs here - beat it for crystals and a relic.", 236, 148, 14, rl.Color{235, 150, 150, 255})
			special = 18
		case:
		}

		oy := i32(152) + special
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
			rl.DrawText(line, 236, oy, 14, staffed ? green : amber)
			oy += 18
		case .FARM:
			staffed := monsters_on_tile(&g.colony, hovered, false) > 0
			line: cstring
			if staffed {
				line = "Farm: feeding your monsters within 4 tiles"
			} else {
				line = "Farm: idle - put a monster here to work it"
			}
			rl.DrawText(line, 236, oy, 14, staffed ? green : amber)
			oy += 18
		case .RELIC_TOWER:
			ht := tile_at(&g.colony, hovered)
			if ht != nil {
				line := fmt.ctprintf("Relic Tower: %d/%d slots, projecting %d tiles", int(ht.relic_count), RELIC_SLOTS, RELIC_RADIUS)
				rl.DrawText(line, 236, oy, 14, rl.Color{235, 195, 110, 255})
				oy += 18
				for k in 0..<int(ht.relic_count) {
					rl.DrawText(fmt.ctprintf("  %s", relic_name(ht.relics[k])), 236, oy, 14, rl.Color{220, 210, 180, 255})
					oy += 16
				}
			}
		case:
		}

		// Occupants on this tile.
		count := monsters_on_tile(&g.colony, hovered, false) + monsters_on_tile(&g.colony, hovered, true)
		if count == 0 {
			rl.DrawText("no monsters here", 236, oy, 14, rl.Color{120, 120, 140, 255})
		} else {
			for &m in g.colony.roster {
				if !hex_equal(m.pos, hovered) {
					continue
				}
				col := m.wild ? rl.Color{240, 110, 110, 255} : rl.Color{140, 230, 160, 255}
				tag := m.wild ? "wild" : "yours"
				line := fmt.ctprintf("%s Lvl %d  %d/%d  XP %d/%d  (%s)", m.creature.name, m.creature.level, m.creature.hp, m.creature.max_hp, m.creature.xp, xp_to_next(m.creature.level), tag)
				rl.DrawText(line, 236, oy, 14, col)
				oy += 18
			}
		}
	}

	// Relic placement banner.
	if g.relic_place_active {
		msg := fmt.ctprintf("Placing %s  -  click a Relic Tower to slot it   (Esc cancels)", relic_name(g.relic_place))
		mw := rl.MeasureText(msg, 20)
		br := rl.Rectangle{sw / 2 - f32(mw) / 2 - 18, 150, f32(mw) + 36, 42}
		rl.DrawRectangleRounded(br, 0.4, 6, rl.Color{32, 28, 16, 240})
		rl.DrawRectangleRoundedLinesEx(br, 0.4, 6, 2, rl.Color{235, 195, 110, 255})
		rl.DrawText(msg, i32(br.x) + 18, i32(br.y) + 10, 20, rl.Color{245, 220, 150, 255})
	}

	if g.show_key_hints {
		hint := cstring("Space end turn  ·  B build  ·  T trade  ·  V deck  ·  M dex  ·  L moves  ·  K all controls")
		hw := rl.MeasureText(hint, 15)
		rl.DrawText(hint, i32(sw) / 2 - hw / 2, i32(sh) - 32, 15, rl.Color{120, 120, 145, 255})
	}

	// First-turns tutorial: one short contextual hint at a time, click to
	// dismiss for good.
	if !g.tutorial_done {
		if text, ok := tutorial_hint(g.colony.turn); ok {
			box := tutorial_rect()
			draw_panel(box, rl.Color{20, 26, 34, 240}, rl.Color{140, 190, 235, 255})
			rl.DrawText("TIP", i32(box.x) + 16, i32(box.y) + 14, 14, rl.Color{140, 190, 235, 255})
			draw_text_wrapped(fmt.ctprintf("%s", text), i32(box.x) + 62, i32(box.y) + 10, 16, i32(box.width) - 190, rl.Color{220, 230, 245, 255})
			more := cstring("click for all tips")
			mw := rl.MeasureText(more, 13)
			rl.DrawText(more, i32(box.x + box.width) - 16 - mw, i32(box.y + box.height) - 24, 13, rl.Color{130, 140, 165, 255})
			if rl.IsMouseButtonPressed(.LEFT) && rl.CheckCollisionPointRec(mouse_pos(), box) {
				g.show_tips = true
			}
		}
	}

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
	sw := f32(screen_w())
	return rl.Rectangle{sw - 240, 180 + f32(i) * 70, 224, 66}
}

draw_roster_panel :: proc(g: ^Game) {
	sw := f32(screen_w())
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

		name := fmt.ctprintf("%s  Lvl %d%s", m.creature.name, m.creature.level, m.acted ? "  (done)" : "")
		rl.DrawText(name, i32(rec.x) + 48, i32(rec.y) + 4, 15, m.acted ? rl.Color{150, 150, 165, 255} : rl.Color{225, 225, 240, 255})

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

		if rl.CheckCollisionPointRec(mouse_pos(), rec) {
			ui_want_hand()
			tooltip_set("%s  Lvl %d  %s  -  PWR x%s, DEF %s, SPD %s, ability: %s",
				m.creature.name, m.creature.level, elements_label(creature_elements(&m.creature)),
				fmt_num(m.creature.power), fmt_num(creature_defense(&m.creature)), fmt_num(m.creature.speed),
				ability_name(m.creature.ability))
		}
	}
}

// ----------------------------------------------------------------------------
// End turn button + legends
// ----------------------------------------------------------------------------

colony_end_turn_rect :: proc() -> rl.Rectangle {
	sw := f32(screen_w())
	sh := f32(screen_h())
	return rl.Rectangle{sw - 240, sh - 120, 224, 48}
}

draw_end_turn_button :: proc(g: ^Game) {
	rec := colony_end_turn_rect()
	hover := rl.CheckCollisionPointRec(mouse_pos(), rec)
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

draw_terrain_legend :: proc() {
	entries := [?]Terrain_Legend_Entry{
		{.CAVE,         "Cave"},
		{.WATER,        "Water"},
		{.DUNGEON,      "Dungeon"},
		{.GROVE,        "Grove"},
		{.TRADING_POST, "Trading Post"},
		{.BOSS_ROOM,    "Boss Room"},
		{.ARENA,        "Arena"},
		{.CRYSTAL_COVE, "Crystal Cove"},
		{.MUSHROOM,     "Mushroom Grove"},
		{.RUINS,        "Ruins"},
		{.TUNDRA,       "Tundra"},
		{.JUNGLE,       "Jungle (Flora)"},
		{.LAVA,         "Lava (Ember)"},
		{.DESERT,       "Desert"},
		{.QUICKSAND,    "Quicksand (Ground)"},
	}
	sh := f32(screen_h())
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
// Title screen
// ----------------------------------------------------------------------------

// ----------------------------------------------------------------------------
// Minimap (Phase 24)
//
// A small overview of every explored tile, with your colony, wilds, raids,
// points of interest and the current viewport. Click it to jump the camera.
// ----------------------------------------------------------------------------

minimap_rect :: proc() -> rl.Rectangle {
	// Top-left, under the HUD (the hovered-tile readout sits to its right).
	return rl.Rectangle{20, 128, 200, 200}
}

minimap_inner :: proc() -> rl.Rectangle {
	p := minimap_rect()
	return rl.Rectangle{p.x + 6, p.y + 22, p.width - 12, p.height - 28}
}

Minimap_View :: struct {
	minx, miny, scale, offx, offy: f32,
	ok:                            bool,
}

minimap_view :: proc(g: ^Game) -> Minimap_View {
	v: Minimap_View
	minx, miny, maxx, maxy, ok := f32(0), f32(0), f32(0), f32(0), false
	for t in g.colony.tiles {
		if !t.revealed {
			continue
		}
		wx, wy := hex_world(&g.renderer, t.hex)
		if !ok {
			minx, miny, maxx, maxy, ok = wx, wy, wx, wy, true
			continue
		}
		minx = min(minx, wx); maxx = max(maxx, wx)
		miny = min(miny, wy); maxy = max(maxy, wy)
	}
	if !ok {
		return v
	}
	inner := minimap_inner()
	spanx := max(maxx - minx, 1)
	spany := max(maxy - miny, 1)
	v.scale = min(inner.width / spanx, inner.height / spany)
	v.offx = inner.x + (inner.width - spanx * v.scale) / 2
	v.offy = inner.y + (inner.height - spany * v.scale) / 2
	v.minx = minx
	v.miny = miny
	v.ok = true
	return v
}

minimap_project :: proc(v: Minimap_View, wx, wy: f32) -> (f32, f32) {
	return v.offx + (wx - v.minx) * v.scale, v.offy + (wy - v.miny) * v.scale
}

draw_minimap :: proc(g: ^Game) {
	if !g.show_minimap {
		return
	}
	p := minimap_rect()
	rl.DrawRectangleRounded(p, 0.04, 6, rl.Color{12, 14, 20, 232})
	rl.DrawRectangleRoundedLinesEx(p, 0.04, 6, 2, rl.Color{72, 82, 102, 255})
	rl.DrawText("MAP", i32(p.x) + 8, i32(p.y) + 4, 13, rl.Color{150, 160, 180, 255})
	rl.DrawText("Z", i32(p.x + p.width) - 16, i32(p.y) + 4, 13, rl.Color{110, 120, 140, 255})

	v := minimap_view(g)
	if !v.ok {
		rl.DrawText("unexplored", i32(p.x) + 8, i32(p.y) + 26, 13, rl.Color{120, 120, 140, 255})
		return
	}
	if rl.CheckCollisionPointRec(mouse_pos(), minimap_inner()) {
		ui_want_hand()
	}
	inner := minimap_inner()
	scissor_begin(inner)
	cell := max(v.scale * 0.9, 2.0)
	for t in g.colony.tiles {
		if !t.revealed {
			continue
		}
		wx, wy := hex_world(&g.renderer, t.hex)
		mx, my := minimap_project(v, wx, wy)
		col := terrain_color(t.terrain)
		rl.DrawRectangle(i32(mx - cell / 2), i32(my - cell / 2), i32(cell), i32(cell),
			rl.Color{u8(f32(col[0]) * 0.72), u8(f32(col[1]) * 0.72), u8(f32(col[2]) * 0.72), 255})
	}
	for t in g.colony.tiles {
		if !t.revealed {
			continue
		}
		col: rl.Color
		show := true
		#partial switch t.terrain {
		case .ARENA:        col = rl.Color{245, 95, 95, 255}
		case .BOSS_ROOM:    col = rl.Color{235, 120, 210, 255}
		case .TRADING_POST: col = rl.Color{245, 210, 95, 255}
		case .CRYSTAL_COVE: col = rl.Color{150, 210, 255, 255}
		case:               show = false
		}
		if show {
			wx, wy := hex_world(&g.renderer, t.hex)
			mx, my := minimap_project(v, wx, wy)
			rl.DrawRectangle(i32(mx) - 3, i32(my) - 3, 6, 6, col)
		}
	}
	for m in g.colony.roster {
		col := rl.Color{120, 230, 150, 255}
		if m.wild {
			col = m.role != .WILD ? rl.Color{255, 140, 60, 255} : rl.Color{235, 80, 80, 255}
		}
		wx, wy := hex_world(&g.renderer, m.pos)
		mx, my := minimap_project(v, wx, wy)
		rl.DrawCircleV(rl.Vector2{mx, my}, 2.6, col)
	}
	minq, maxq, minr, maxr := visible_hex_bounds(&g.renderer)
	ax, ay := hex_world(&g.renderer, Hex{minq, minr})
	bx, by := hex_world(&g.renderer, Hex{maxq, maxr})
	p1x, p1y := minimap_project(v, ax, ay)
	p2x, p2y := minimap_project(v, bx, by)
	rl.DrawRectangleLinesEx(rl.Rectangle{min(p1x, p2x), min(p1y, p2y), abs(p2x - p1x), abs(p2y - p1y)}, 1, rl.Color{255, 255, 255, 165})
	scissor_end()
}

// The hex under a minimap click, if the minimap is shown and the point is in it.
minimap_hex_at :: proc(g: ^Game, mp: rl.Vector2) -> (Hex, bool) {
	if !g.show_minimap || !rl.CheckCollisionPointRec(mp, minimap_inner()) {
		return {}, false
	}
	v := minimap_view(g)
	if !v.ok {
		return {}, false
	}
	wx := v.minx + (mp.x - v.offx) / max(v.scale, 0.0001)
	wy := v.miny + (mp.y - v.offy) / max(v.scale, 0.0001)
	q := wx / max(g.renderer.horiz_spacing, 0.0001)
	r := wy / max(g.renderer.vert_spacing, 0.0001) - 0.5 * q
	return Hex{int(math.round(q)), int(math.round(r))}, true
}

// ----------------------------------------------------------------------------
// Camera tween: ease the camera toward a hex instead of snapping.
// ----------------------------------------------------------------------------

tween_camera :: proc(g: ^Game, hex: Hex) {
	wx, wy := hex_world(&g.renderer, hex)
	g.cam_from_x = g.renderer.camera_x
	g.cam_from_y = g.renderer.camera_y
	g.cam_to_x = wx
	g.cam_to_y = wy
	g.cam_tween = 1.0
}

update_camera_tween :: proc(g: ^Game, dt: f32) {
	if g.cam_tween <= 0 {
		return
	}
	g.cam_tween = max(g.cam_tween - dt * 3.5, 0)
	t := 1.0 - g.cam_tween
	e := t * (2.0 - t) // ease-out
	g.renderer.camera_x = g.cam_from_x + (g.cam_to_x - g.cam_from_x) * e
	g.renderer.camera_y = g.cam_from_y + (g.cam_to_y - g.cam_from_y) * e
}
