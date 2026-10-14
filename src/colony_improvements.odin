package main

import rl "vendor:raylib"
improvement_name :: proc(im: Improvement) -> cstring {
	return IMPROVEMENT_INFO[im].name
}

// Health per improvement. Gates are deliberately frailer than Walls.
improvement_max_hp :: proc(im: Improvement) -> int {
	return IMPROVEMENT_INFO[im].hp
}

improvement_cost :: proc(im: Improvement) -> int {
	return IMPROVEMENT_INFO[im].cost
}

improvement_valid_on :: proc(im: Improvement, t: Terrain) -> bool {
	return t in IMPROVEMENT_INFO[im].terrains
}

improvement_effect :: proc(im: Improvement) -> cstring {
	return IMPROVEMENT_INFO[im].effect
}

improvement_detail :: proc(im: Improvement) -> cstring {
	return IMPROVEMENT_INFO[im].detail
}

improvement_category :: proc(im: Improvement) -> cstring {
	return IMPROVEMENT_INFO[im].category
}

// Stackable improvements sit in a tile's `overlay` slot instead of replacing the
// building, so a Road / Scarecrow / Spike Trap can share a tile with a Farm,
// a Mine, etc. Only one overlay can occupy a tile at a time.
improvement_stacks :: proc(im: Improvement) -> bool {
	return IMPROVEMENT_INFO[im].stacks
}

Tile :: struct {
	hex:            Hex,
	terrain:        Terrain,
	revealed:       bool,
	improvement:    Improvement,
	overlay:        Improvement, // a stackable improvement (e.g. Road) on top of the building
	improvement_hp: int,
	overlay_hp:     int,   // health of the overlay (Road / Scarecrow / Spike Trap)
	stored:         int,   // food (Granary) / gold (Treasury) / charge (Turret)
	scuffle:        int,   // turns a "fight happened here" marker lingers
	hit_t0:         f32,   // rl.GetTime of the last damage (for hit shake/flash)
	drawbridge_down: bool, // false = raised (blocks wilds), true = lowered (bridge)
}

// Does this tile contain the given improvement (as building or overlay)?
improvement_blocks_wilds :: proc(t: ^Tile) -> bool {
	if t.improvement == .DRAWBRIDGE {
		return !t.drawbridge_down // a raised drawbridge blocks; a lowered one doesn't
	}
	return IMPROVEMENT_INFO[t.improvement].blocks
}

// Human-readable reason a move is blocked, for the status line. tile_passable
// returns a single "blocked" result, so explain it from the tile itself.
adjacent_to_water :: proc(c: ^Colony, hex: Hex) -> bool {
	for n in hex_neighbors(hex) {
		if t := tile_at(c, n); t != nil && t.terrain == .WATER {
			return true
		}
	}
	return false
}

// Whether an improvement can be placed here (terrain + extra placement rules).
can_build :: proc(c: ^Colony, hex: Hex, im: Improvement) -> bool {
	t := tile_at(c, hex)
	if t == nil || !improvement_valid_on(im, t.terrain) {
		return false
	}
	if (im == .WELL || im == .LUMBER_MILL) && !adjacent_to_water(c, hex) {
		return false
	}
	if improvement_stacks(im) && (t.overlay == im || t.improvement == im) {
		return false // already on this tile
	}
	return true
}

// Counts only improvements that currently stand (building or overlay). Destroyed
// ones are reset to `.NONE`, so a replacement after a raid costs the same as
// building a fresh one would have.
improvement_count :: proc(c: ^Colony, im: Improvement) -> int {
	n := 0
	for t in c.tiles {
		if tile_has(t, im) {
			n += 1
		}
	}
	return n
}

improvement_cost_scaled :: proc(c: ^Colony, im: Improvement) -> int {
	base := improvement_cost(im)
	scaled := base + (base * improvement_count(c, im)) / improvement_cost_divisor(im)
	cost := f32(scaled) * upgrade_masonry_mult(c)
	if im == .TURRET {
		cost *= upgrade_turret_cost_mult(c)
	}
	return max(int(cost), 1)
}

// Repeated builds get pricier; how fast depends on the improvement (Walls and
// other bulk items climb slowly, see `IMPROVEMENT_INFO.cost_divisor`).
improvement_cost_divisor :: proc(im: Improvement) -> int {
	return IMPROVEMENT_INFO[im].cost_divisor
}

// Demolishing refunds a fraction of an improvement's BASE cost (not the scaled
// price), so repeatedly building and tearing down can't be farmed.
IMPROVEMENT_REFUND_PCT :: 0.5

improvement_refund :: proc(im: Improvement) -> int {
	return int(f32(improvement_cost(im)) * IMPROVEMENT_REFUND_PCT)
}

// Tear down the overlay (preferred) or building on `hex`, refunding part of its
// cost. 0 ok, 1 nothing there.
colony_demolish :: proc(c: ^Colony, hex: Hex) -> (res: int, refund: int) {
	t := tile_at(c, hex)
	if t == nil || (t.improvement == .NONE && t.overlay == .NONE) {
		return 1, 0
	}
	// Prefer the overlay (the topmost thing), so a Road can be peeled off a
	// building without losing the building.
	if t.overlay != .NONE {
		refund = improvement_refund(t.overlay)
		t.overlay = .NONE
		t.overlay_hp = 0
	} else {
		im := t.improvement
		refund = improvement_refund(im)
		if im == .DEN || im == .NURSERY {
			colony_evacuate_storage(c, hex)
		}
		t.improvement = .NONE
		t.improvement_hp = 0
		t.stored = 0
		colony_recompute_caps(c)
	}
	if refund > 0 {
		c.gold += refund
		colony_add_float(c, hex, .GOLD, refund)
	}
	return 0, refund
}

colony_build :: proc(c: ^Colony, hex: Hex, im: Improvement) -> int {
	t := tile_at(c, hex)
	if !can_build(c, hex, im) {
		return 1
	}
	cost := improvement_cost_scaled(c, im)
	if !colony_spend_gold(c, cost) {
		return 3
	}
	if improvement_stacks(im) {
		// Stackable: lay it in the overlay slot and keep the building. The
		// overlay carries its own health, so wilds can tear it up too.
		t.overlay = im
		t.overlay_hp = improvement_max_hp(im)
		c.improvements_built += 1
		return 0
	}
	// Replaces the building (stored contents are lost); any overlay survives.
	if t.improvement == .DEN || t.improvement == .NURSERY {
		colony_evacuate_storage(c, hex)
	}
	t.improvement = im
	t.improvement_hp = improvement_hp_cap(c, im)
	t.stored = 0
	c.improvements_built += 1
	colony_recompute_caps(c)
	return 0
}

buildable_improvements :: proc(c: ^Colony, hex: Hex, out: []Improvement) -> int {
	n := 0
	for im in Improvement {
		if im != .NONE && can_build(c, hex, im) {
			if n < len(out) {
				out[n] = im
			}
			n += 1
		}
	}
	return n
}

// Repairs cost half the improvement's base cost when fully damaged, prorated by
// the missing HP. Repairs never scale with how many you own.
improvement_repair_cost :: proc(c: ^Colony, im: Improvement, hp: int) -> int {
	max_hp := improvement_max_hp(im)
	if im == .NONE || max_hp <= 0 || hp >= max_hp {
		return 0
	}
	missing := max_hp - hp
	base := max(1, (improvement_cost(im) * missing) / (2 * max_hp))
	return max(int(f32(base) * upgrade_masonry_mult(c)), 1)
}

// 0 ok, 1 nothing to repair, 2 not enough gold.
colony_repair :: proc(c: ^Colony, hex: Hex) -> int {
	t := tile_at(c, hex)
	if t == nil {
		return 1
	}
	// The building first, then the overlay.
	if t.improvement != .NONE && t.improvement_hp < improvement_hp_cap(c, t.improvement) {
		cost := improvement_repair_cost(c, t.improvement, t.improvement_hp)
		if !colony_spend_gold(c, cost) {
			return 2
		}
		t.improvement_hp = improvement_hp_cap(c, t.improvement)
		return 0
	}
	if t.overlay != .NONE && t.overlay_hp < improvement_max_hp(t.overlay) {
		cost := improvement_repair_cost(c, t.overlay, t.overlay_hp)
		if !colony_spend_gold(c, cost) {
			return 2
		}
		t.overlay_hp = improvement_max_hp(t.overlay)
		return 0
	}
	return 1
}

// The improvement on this tile that wants repairing (building first, else
// overlay), with its current and max HP. `im == .NONE` means nothing to fix.
tile_repair_target :: proc(c: ^Colony, t: ^Tile) -> (im: Improvement, hp, cap: int) {
	if t.improvement != .NONE && t.improvement_hp < improvement_hp_cap(c, t.improvement) {
		return t.improvement, t.improvement_hp, improvement_hp_cap(c, t.improvement)
	}
	if t.overlay != .NONE && t.overlay_hp < improvement_max_hp(t.overlay) {
		return t.overlay, t.overlay_hp, improvement_max_hp(t.overlay)
	}
	return .NONE, 0, 0
}

// Toggle a Drawbridge: raised blocks wilds, lowered acts as a bridge.
colony_toggle_drawbridge :: proc(c: ^Colony, hex: Hex) -> bool {
	t := tile_at(c, hex)
	if t == nil || t.improvement != .DRAWBRIDGE {
		return false
	}
	t.drawbridge_down = !t.drawbridge_down
	return true
}

// ----------------------------------------------------------------------------
// Gold (global; treasuries hold part of it and lose it if destroyed)
// ----------------------------------------------------------------------------

improvement_heat :: proc(im: Improvement) -> int {
	return IMPROVEMENT_INFO[im].heat
}

// Total heat drawn by every standing improvement (building + overlay).
colony_improvement_heat :: proc(c: ^Colony) -> int {
	n := 0
	for t in c.tiles {
		n += improvement_heat(t.improvement)
		n += improvement_heat(t.overlay)
	}
	return n
}

colony_heat :: proc(c: ^Colony) -> int {
	offense := colony_improvement_heat(c) / 3 + total_monster_levels(c) / 6
	return clamp(offense, 0, HEAT_MAX)
}

colony_item_cap :: proc(c: ^Colony) -> int {
	cap := BASE_ITEM_CAP
	vault_bonus := VAULT_ITEM_CAP + upgrade_vault_cap(c)
	for t in c.tiles {
		if t.improvement == .VAULT {
			cap += vault_bonus
		}
	}
	return cap
}

// --- building lists (for the panels) ---
