package main

// ============================================================================
// RELICS (Phase 25, reworked in Phase 44)
//
// Relics are boss-dropped passives, but they are no longer colony-wide: each
// one must be slotted into a **Relic Tower**, and it then projects its effect
// over a **radius** around that tower. So relics are a base-building decision —
// towers defend and enrich the ground they stand on.
//
// They stack: several copies in range of the same tile add up.
//
// Split by what "in range" means:
//   * BATTLE relics buff your party for a fight that happens inside the radius.
//   * ECONOMY relics boost the improvements inside the radius.
//   * POST-BATTLE relics pay out when a fight inside the radius is won.
// ============================================================================

RELIC_RADIUS :: 5   // tiles a tower projects its relics over
RELIC_SLOTS  :: 3   // relics a single Relic Tower can hold

Relic :: enum {
	War_Banner,     // battle: +2 Strength
	Iron_Idol,      // battle: +10 Block
	Swift_Totem,    // battle: +4 Speed
	Mana_Shard,     // battle: +1 energy regen
	Wardens_Seal,   // battle: +2 Thorns
	Coin_of_Plenty, // economy: Mines and Quarries yield more gold
	Harvest_Charm,  // economy: Farms, Wells and Mills yield more food
	Siege_Core,     // economy: Turrets deal more damage
	Crystal_Prism,  // post-battle: +1 crystal per Arena / Boss win
	Beast_Fang,     // post-battle: +25% XP from kills
}

Relic_Info :: struct {
	name: cstring,
	desc: cstring,
}

@(rodata)
RELIC_INFO := [Relic]Relic_Info{
	.War_Banner     = {"War Banner",     "Your monsters start fights in range with +2 Strength."},
	.Iron_Idol      = {"Iron Idol",      "Your monsters start fights in range with +10 Block."},
	.Swift_Totem    = {"Swift Totem",    "Your monsters start fights in range with +4 Speed."},
	.Mana_Shard     = {"Mana Shard",     "Your monsters start fights in range with +1 energy regen."},
	.Wardens_Seal   = {"Warden's Seal",  "Your monsters start fights in range with +2 Thorns."},
	.Coin_of_Plenty = {"Coin of Plenty", "Mines and Quarries in range yield +25% gold."},
	.Harvest_Charm  = {"Harvest Charm",  "Farms, Wells and Mills in range yield +25% food."},
	.Siege_Core     = {"Siege Core",     "Turrets in range deal +25% damage."},
	.Crystal_Prism  = {"Crystal Prism",  "+1 crystal from Arena and Boss wins in range."},
	.Beast_Fang     = {"Beast Fang",     "+25% XP from kills made in range."},
}

RELIC_ORDER := [?]Relic{
	.War_Banner, .Iron_Idol, .Swift_Totem, .Mana_Shard, .Wardens_Seal,
	.Coin_of_Plenty, .Harvest_Charm, .Siege_Core, .Crystal_Prism, .Beast_Fang,
}

relic_name :: proc(r: Relic) -> cstring { return RELIC_INFO[r].name }
relic_desc :: proc(r: Relic) -> cstring { return RELIC_INFO[r].desc }

// Owned relics, whether bagged or already slotted into a tower.
relic_total :: proc(c: ^Colony) -> int {
	placed := 0
	for t in c.tiles {
		if t.improvement == .RELIC_TOWER {
			placed += int(t.relic_count)
		}
	}
	return len(c.relic_bag) + placed
}

// --- placement ---------------------------------------------------------------

// How many of each relic are currently slotted into towers.
relics_placed :: proc(c: ^Colony) -> [Relic]int {
	out: [Relic]int
	for t in c.tiles {
		if t.improvement != .RELIC_TOWER {
			continue
		}
		for i in 0..<int(t.relic_count) {
			out[t.relics[i]] += 1
		}
	}
	return out
}

// Copies of `r` still in the bag (not slotted into a tower).
relics_unplaced :: proc(c: ^Colony, r: Relic) -> int {
	n := 0
	for b in c.relic_bag {
		if b == r {
			n += 1
		}
	}
	return n
}

// Tally the relics projecting onto `hex` — every tower within RELIC_RADIUS.
// Effects stack, so callers multiply by the count.
relics_in_range :: proc(c: ^Colony, hex: Hex) -> [Relic]int {
	out: [Relic]int
	for t in c.tiles {
		if t.improvement != .RELIC_TOWER || t.relic_count == 0 {
			continue
		}
		if hex_distance(t.hex, hex) > RELIC_RADIUS {
			continue
		}
		for i in 0..<int(t.relic_count) {
			out[t.relics[i]] += 1
		}
	}
	return out
}

// Slot one unplaced relic into `t`. Returns false if it can't (no stock, full).
place_relic :: proc(c: ^Colony, t: ^Tile, r: Relic) -> bool {
	if t == nil || t.improvement != .RELIC_TOWER || int(t.relic_count) >= RELIC_SLOTS {
		return false
	}
	idx := -1
	for b, i in c.relic_bag {
		if b == r {
			idx = i
			break
		}
	}
	if idx < 0 {
		return false
	}
	ordered_remove(&c.relic_bag, idx)
	t.relics[t.relic_count] = r
	t.relic_count += 1
	colony_notify(c, "%s slotted into a Relic Tower.", relic_name(r))
	audio_play(.CONFIRM)
	return true
}

// Pull the relic at slot `i` back out of a tower.
remove_relic :: proc(c: ^Colony, t: ^Tile, i: int) -> bool {
	if t == nil || t.improvement != .RELIC_TOWER || i < 0 || i >= int(t.relic_count) {
		return false
	}
	r := t.relics[i]
	for k in i..<int(t.relic_count) - 1 {
		t.relics[k] = t.relics[k + 1]
	}
	t.relic_count -= 1
	t.relics[t.relic_count] = .War_Banner
	append(&c.relic_bag, r)
	colony_notify(c, "%s returned to the bag.", relic_name(r))
	audio_play(.CANCEL)
	return true
}

// --- battle relics -----------------------------------------------------------

// Apply every BATTLE relic projecting onto a fight. Called once when the battle
// starts, so relics defend the ground they are built on rather than the whole
// colony.
battle_apply_relics :: proc(b: ^Battle, relics: [Relic]int) {
	for p in b.party {
		side := side_of(b, p)
		if n := relics[.War_Banner]; n > 0 {
			p.strength += 2 * n
			spawn_popup(b, side, .BUFF, 2 * n)
			creature_burst(p, popup_color(.BUFF), 0.6)
		}
		if n := relics[.Iron_Idol]; n > 0 {
			p.block += 10 * n
			spawn_popup(b, side, .BLOCK, 10 * n)
			creature_burst(p, popup_color(.BLOCK), 0.6)
		}
		if n := relics[.Swift_Totem]; n > 0 {
			p.speed_buff += f32(4 * n)
			spawn_popup(b, side, .BUFF, 4 * n)
			creature_burst(p, popup_color(.BUFF), 0.6)
		}
		if n := relics[.Mana_Shard]; n > 0 {
			p.energy_regen_buff += f32(n)
			spawn_popup(b, side, .ENERGY, n)
			creature_burst(p, popup_color(.ENERGY), 0.6)
		}
		if n := relics[.Wardens_Seal]; n > 0 {
			p.thorns += 2 * n
			spawn_popup(b, side, .THORNS, 2 * n)
			creature_burst(p, popup_color(.THORNS), 0.6)
		}
	}
}

// --- economy relics ----------------------------------------------------------

// Multipliers from the ECONOMY relics projecting onto a tile.
relic_gold_mult_at :: proc(c: ^Colony, hex: Hex) -> f32 {
	return 1.0 + 0.25 * f32(relics_in_range(c, hex)[.Coin_of_Plenty])
}

relic_food_mult_at :: proc(c: ^Colony, hex: Hex) -> f32 {
	return 1.0 + 0.25 * f32(relics_in_range(c, hex)[.Harvest_Charm])
}

relic_turret_mult_at :: proc(c: ^Colony, hex: Hex) -> f32 {
	return 1.0 + 0.25 * f32(relics_in_range(c, hex)[.Siege_Core])
}

// --- post-battle relics ------------------------------------------------------

relic_crystal_bonus_at :: proc(c: ^Colony, hex: Hex) -> int {
	return relics_in_range(c, hex)[.Crystal_Prism]
}

relic_xp_mult_at :: proc(c: ^Colony, hex: Hex) -> f32 {
	return 1.0 + 0.25 * f32(relics_in_range(c, hex)[.Beast_Fang])
}

// --- drops -------------------------------------------------------------------

// Award a relic (stacking it). It sits unplaced until slotted into a tower.
grant_relic :: proc(c: ^Colony, r: Relic) {
	append(&c.relic_bag, r)
	colony_notify(c, "Relic gained: %s! Slot it into a Relic Tower.", relic_name(r))
	audio_play(.CRYSTAL)
}

// A random relic, for boss drops.
random_relic :: proc(rng: ^Rng) -> Relic {
	return RELIC_ORDER[rng_below(rng, len(RELIC_ORDER))]
}

// Pull one copy of `r` out of the nearest tower holding it (the relic panel's
// Take button). Returns false if no tower holds one.
remove_relic_nearest :: proc(c: ^Colony, from: Hex, r: Relic) -> bool {
	best: ^Tile
	best_d := 1 << 30
	best_i := -1
	for t in c.tiles {
		if t.improvement != .RELIC_TOWER {
			continue
		}
		for i in 0..<int(t.relic_count) {
			if t.relics[i] != r {
				continue
			}
			d := hex_distance(t.hex, from)
			if d < best_d {
				best_d = d
				best = t
				best_i = i
			}
		}
	}
	if best == nil {
		return false
	}
	return remove_relic(c, best, best_i)
}
