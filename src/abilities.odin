package main

// ============================================================================
// SPECIES ABILITIES (Phase C)
//
// Every species has a small pool of passive abilities. When a creature spawns it
// rolls one at random, so two Emberlings can play differently. Abilities fire at
// battle start, each turn, or on dealing damage — see the hooks below.
// ============================================================================

Ability :: enum {
	NONE,
	Berserk,     // +Strength at battle start
	Guardian,    // +Block at battle start
	Thick_Hide,  // +Defense at battle start
	Swift,       // +Speed for initiative
	Lucky,       // draws an extra card each turn
	Vampiric,    // heals on dealing damage
	Regenerator, // heals at the end of each turn
	Intimidate,  // enemies start weaker
}

ABILITY_BERSERK_STR    :: 2
ABILITY_GUARDIAN_BLOCK :: 8
ABILITY_THICK_HIDE_DEF :: f32(2.0)
ABILITY_SWIFT_SPEED    :: f32(2.0)
ABILITY_LUCKY_DRAW     :: 1
ABILITY_VAMPIRIC_HEAL  :: 2
ABILITY_REGENERATOR_HP :: 4
ABILITY_INTIMIDATE_STR :: 2

ability_name :: proc(a: Ability) -> cstring {
	switch a {
	case .NONE:        return "-"
	case .Berserk:     return "Berserk"
	case .Guardian:    return "Guardian"
	case .Thick_Hide:  return "Thick Hide"
	case .Swift:       return "Swift"
	case .Lucky:       return "Lucky"
	case .Vampiric:    return "Vampiric"
	case .Regenerator: return "Regenerator"
	case .Intimidate:  return "Intimidate"
	}
	return "?"
}

ability_desc :: proc(a: Ability) -> cstring {
	switch a {
	case .NONE:        return "No ability."
	case .Berserk:     return "Starts a fight with +2 Strength."
	case .Guardian:    return "Starts a fight with +8 Block."
	case .Thick_Hide:  return "Starts a fight with +2 Defense."
	case .Swift:       return "Acts with +2 Speed for initiative."
	case .Lucky:       return "Draws 1 extra card each turn."
	case .Vampiric:    return "Heals 2 whenever it deals card damage."
	case .Regenerator: return "Heals 4 at the end of each turn."
	case .Intimidate:  return "Enemies start a fight with -2 Strength."
	}
	return ""
}

// Per-species pools, themed by role. Rolled once at spawn.
ABILITY_POOLS := [27][3]Ability{
	{.Berserk, .Vampiric, .Regenerator},    // 0 Emberling
	{.Regenerator, .Guardian, .Lucky},      // 1 Tidepup
	{.Regenerator, .Thick_Hide, .Lucky},    // 2 Sproutle
	{.Swift, .Vampiric, .Lucky},            // 3 Cave Bat
	{.Thick_Hide, .Berserk, .Regenerator},  // 4 Magmite
	{.Regenerator, .Guardian, .Thick_Hide}, // 5 Bubblet
	{.Vampiric, .Lucky, .Regenerator},      // 6 Thornkit
	{.Guardian, .Intimidate, .Thick_Hide},  // 7 Elite Sentinel
	{.Intimidate, .Regenerator, .Guardian}, // 8 The Deep One
	{.Intimidate, .Regenerator, .Lucky},    // 9 Gloomling
	{.Berserk, .Intimidate, .Vampiric},     // 10 Pyrelord
	{.Berserk, .Regenerator, .Swift},       // 11 Krakling
	{.Regenerator, .Guardian, .Thick_Hide}, // 12 Swampbeast
	{.Lucky, .Swift, .Intimidate},          // 13 Wispling
	{.Berserk, .Swift, .Vampiric},          // 14 Cindermaw
	{.Thick_Hide, .Guardian, .Regenerator}, // 15 Rimescale
	{.Regenerator, .Thick_Hide, .Guardian}, // 16 Mosshide
	{.Berserk, .Regenerator, .Vampiric},    // 17 Emberbloom
	{.Vampiric, .Thick_Hide, .Regenerator}, // 18 Bogfang
	{.Swift, .Berserk, .Lucky},             // 19 Cinderwing
	{.Thick_Hide, .Regenerator, .Guardian}, // 20 Frostmoss
	{.Berserk, .Thick_Hide, .Swift},        // 21 Frostfang
	{.Thick_Hide, .Guardian, .Intimidate},  // 22 Stonepaw
	{.Swift, .Berserk, .Lucky},             // 23 Sparkit
	{.Swift, .Lucky, .Berserk},             // 24 Galebeast
	{.Vampiric, .Intimidate, .Lucky},       // 25 Venomtail
	{.Swift, .Guardian, .Thick_Hide},       // 26 Blizzard
}

DEFAULT_ABILITY_POOL := [3]Ability{.Berserk, .Guardian, .Thick_Hide}

species_abilities :: proc(species: int) -> []Ability {
	if species < 0 || species >= len(ABILITY_POOLS) {
		return DEFAULT_ABILITY_POOL[:]
	}
	return ABILITY_POOLS[species][:]
}

creature_roll_ability :: proc(species: int, rng: ^Rng) -> Ability {
	pool := species_abilities(species)
	if len(pool) == 0 {
		return .NONE
	}
	return pool[rng_below(rng, len(pool))]
}

// Fires once when a battle begins. `foes` is the opposing side, for debuffs.
ability_battle_start :: proc(self: ^Creature, foes: []^Creature) {
	switch self.ability {
	case .Berserk:    self.strength += ABILITY_BERSERK_STR
	case .Guardian:   self.block += ABILITY_GUARDIAN_BLOCK
	case .Thick_Hide: self.defense_buff += ABILITY_THICK_HIDE_DEF
	case .Swift:      self.speed_buff += ABILITY_SWIFT_SPEED
	case .Intimidate:
		for f in foes {
			f.strength -= ABILITY_INTIMIDATE_STR
		}
	case .NONE, .Lucky, .Vampiric, .Regenerator:
	}
}

// One-line summary used by the colony/battle UI.
ability_label :: proc(a: Ability) -> cstring {
	if a == .NONE {
		return "-"
	}
	return ability_name(a)
}
