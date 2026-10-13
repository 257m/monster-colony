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
ABILITY_POOLS := [Species_Id][3]Ability{
	.Emberling     = {.Berserk, .Vampiric, .Regenerator},
	.Tidepup       = {.Regenerator, .Guardian, .Lucky},
	.Sproutle      = {.Regenerator, .Thick_Hide, .Lucky},
	.Cave_Bat      = {.Swift, .Vampiric, .Lucky},
	.Magmite       = {.Thick_Hide, .Berserk, .Regenerator},
	.Bubblet       = {.Regenerator, .Guardian, .Thick_Hide},
	.Thornkit      = {.Vampiric, .Lucky, .Regenerator},
	.Elite_Sentinel = {.Guardian, .Intimidate, .Thick_Hide},
	.Deep_One      = {.Intimidate, .Regenerator, .Guardian},
	.Gloomling     = {.Intimidate, .Regenerator, .Lucky},
	.Pyrelord      = {.Berserk, .Intimidate, .Vampiric},
	.Krakling      = {.Berserk, .Regenerator, .Swift},
	.Swampbeast    = {.Regenerator, .Guardian, .Thick_Hide},
	.Wispling      = {.Lucky, .Swift, .Intimidate},
	.Cindermaw     = {.Berserk, .Swift, .Vampiric},
	.Rimescale     = {.Thick_Hide, .Guardian, .Regenerator},
	.Mosshide      = {.Regenerator, .Thick_Hide, .Guardian},
	.Emberbloom    = {.Berserk, .Regenerator, .Vampiric},
	.Bogfang       = {.Vampiric, .Thick_Hide, .Regenerator},
	.Cinderwing    = {.Swift, .Berserk, .Lucky},
	.Frostmoss     = {.Thick_Hide, .Regenerator, .Guardian},
	.Frostfang     = {.Berserk, .Thick_Hide, .Swift},
	.Stonepaw      = {.Thick_Hide, .Guardian, .Intimidate},
	.Sparkit       = {.Swift, .Berserk, .Lucky},
	.Galebeast     = {.Swift, .Lucky, .Berserk},
	.Venomtail     = {.Vampiric, .Intimidate, .Lucky},
	.Blizzard      = {.Swift, .Guardian, .Thick_Hide},
}

DEFAULT_ABILITY_POOL := [3]Ability{.Berserk, .Guardian, .Thick_Hide}

species_abilities :: proc(species: Species_Id) -> []Ability {
	return ABILITY_POOLS[species][:]
}

creature_roll_ability :: proc(species: Species_Id, rng: ^Rng) -> Ability {
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
