package main

// ============================================================================
// RELICS (Phase 25)
//
// Rare, colony-wide passives dropped by bosses. Unlike items (one per monster),
// a relic applies to *everything* you own and they STACK: you're meant to farm
// bosses and pile them up to keep pace with the runaway late-game difficulty.
// ============================================================================

Relic :: enum {
	War_Banner,     // +8% monster power
	Iron_Idol,      // +8% max HP
	Swift_Totem,    // +8% speed
	Mana_Shard,     // +0.5 energy regen
	Coin_of_Plenty, // +15% gold from kills
	Harvest_Charm,  // +15% food production
	Wardens_Seal,   // +3 Block at battle start
	Siege_Core,     // +20% turret damage
	Crystal_Prism,  // +1 crystal per Arena/Boss win
	Beast_Fang,     // +10% XP from kills
}

Relic_Info :: struct {
	name: cstring,
	desc: cstring,
}

@(rodata)
RELIC_INFO := [Relic]Relic_Info{
	.War_Banner     = {"War Banner",     "+8% Power to all your monsters, per relic."},
	.Iron_Idol      = {"Iron Idol",      "+8% max HP to all your monsters, per relic."},
	.Swift_Totem    = {"Swift Totem",    "+8% Speed to all your monsters, per relic."},
	.Mana_Shard     = {"Mana Shard",     "+0.5 energy regen to all your monsters, per relic."},
	.Coin_of_Plenty = {"Coin of Plenty", "+15% gold from defeated wilds, per relic."},
	.Harvest_Charm  = {"Harvest Charm",  "+15% food from Farms / Wells / Mills, per relic."},
	.Wardens_Seal   = {"Warden's Seal",  "Your defenders start battles with +3 Block, per relic."},
	.Siege_Core     = {"Siege Core",     "+20% Turret damage, per relic."},
	.Crystal_Prism  = {"Crystal Prism",  "+1 crystal per Arena / Boss win, per relic."},
	.Beast_Fang     = {"Beast Fang",     "+10% XP from kills, per relic."},
}

RELIC_ORDER := [?]Relic{
	.War_Banner, .Iron_Idol, .Swift_Totem, .Mana_Shard, .Coin_of_Plenty,
	.Harvest_Charm, .Wardens_Seal, .Siege_Core, .Crystal_Prism, .Beast_Fang,
}

relic_name :: proc(r: Relic) -> cstring { return RELIC_INFO[r].name }
relic_desc :: proc(r: Relic) -> cstring { return RELIC_INFO[r].desc }

relic_total :: proc(c: ^Colony) -> int {
	n := 0
	for r in Relic {
		n += c.relics[r]
	}
	return n
}

// --- stacking effect readers -----------------------------------------------

relic_power_mult :: proc(c: ^Colony) -> f32 { return 1.0 + 0.08 * f32(c.relics[.War_Banner]) }
relic_hp_mult :: proc(c: ^Colony) -> f32 { return 1.0 + 0.08 * f32(c.relics[.Iron_Idol]) }
relic_speed_mult :: proc(c: ^Colony) -> f32 { return 1.0 + 0.08 * f32(c.relics[.Swift_Totem]) }
relic_energy_regen :: proc(c: ^Colony) -> f32 { return 0.5 * f32(c.relics[.Mana_Shard]) }
relic_gold_mult :: proc(c: ^Colony) -> f32 { return 1.0 + 0.15 * f32(c.relics[.Coin_of_Plenty]) }
relic_food_mult :: proc(c: ^Colony) -> f32 { return 1.0 + 0.15 * f32(c.relics[.Harvest_Charm]) }
relic_block :: proc(c: ^Colony) -> int { return 3 * c.relics[.Wardens_Seal] }
relic_turret_mult :: proc(c: ^Colony) -> f32 { return 1.0 + 0.20 * f32(c.relics[.Siege_Core]) }
relic_crystal_bonus :: proc(c: ^Colony) -> int { return c.relics[.Crystal_Prism] }
relic_xp_mult :: proc(c: ^Colony) -> f32 { return 1.0 + 0.10 * f32(c.relics[.Beast_Fang]) }

// --- stat relics -----------------------------------------------------------
//
// `creature_recompute_stats` has no colony, so the stat multipliers are mirrored
// into a package global that only player creatures read.

Relic_State :: struct {
	power, hp, speed, energy_regen: f32,
}

@(private)
relic_state := Relic_State{power = 1, hp = 1, speed = 1}

colony_sync_relic_state :: proc(c: ^Colony) {
	relic_state = Relic_State{
		power        = relic_power_mult(c),
		hp           = relic_hp_mult(c),
		speed        = relic_speed_mult(c),
		energy_regen = relic_energy_regen(c),
	}
}

// Recompute every monster you own so stat relics apply immediately (wilds are
// untouched — the global is only read for `player` creatures).
colony_apply_relics :: proc(c: ^Colony) {
	colony_sync_relic_state(c)
	for &m in c.roster {
		if !m.wild {
			creature_recompute_stats(&m.creature)
		}
	}
	for &m in c.storage {
		creature_recompute_stats(&m.creature)
	}
}

// Award a relic (stacking it) and refresh the colony.
grant_relic :: proc(c: ^Colony, r: Relic) {
	c.relics[r] += 1
	colony_notify(c, "Relic gained: %s!", relic_name(r))
	audio_play(.CRYSTAL)
	colony_apply_relics(c)
}

// A random relic, for boss drops.
random_relic :: proc(rng: ^Rng) -> Relic {
	return RELIC_ORDER[rng_below(rng, len(RELIC_ORDER))]
}
