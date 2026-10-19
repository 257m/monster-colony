package main

import rl "vendor:raylib"

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
	// Regular
	Momentum,    // +Strength at the start of each turn
	Ironclad,    // +Dexterity at the start of each turn
	Aftershock,  // your first Attack each turn hits twice
	Envenom,     // your Attacks apply Poison
	Predator,    // +damage against foes below half HP
	Vengeance,   // +Strength whenever you take a hit
	Resilient,   // once a battle, survive a lethal blow
	// Boss-only
	Abyssal,     // takes less damage while above half HP
	Inferno,     // burn every foe at the end of each turn
	Colossus,    // Block is not cleared between rounds
	Dominion,    // strip Strength from every foe each turn
}

ABILITY_BERSERK_STR    :: 3
ABILITY_GUARDIAN_BLOCK :: 8
ABILITY_THICK_HIDE_DEF :: f32(3.0)
ABILITY_SWIFT_SPEED    :: f32(4.0)
ABILITY_LUCKY_DRAW     :: 1
ABILITY_VAMPIRIC_PCT   :: f32(0.25) // heal as a fraction of damage dealt
ABILITY_REGENERATOR_PCT :: f32(0.06) // heal as a fraction of max HP each turn
ABILITY_INTIMIDATE_STR :: 3
ABILITY_MOMENTUM_STR   :: 1
ABILITY_IRONCLAD_DEX   :: 1
ABILITY_ENVENOM_POISON :: 1
ABILITY_PREDATOR_MULT  :: f32(1.25)
ABILITY_VENGEANCE_STR  :: 1
ABILITY_RESILIENT_PCT  :: f32(0.25) // survive at this fraction of max HP
ABILITY_ABYSSAL_MULT   :: f32(0.70) // damage taken while above half HP
ABILITY_INFERNO_BURN   :: 2
ABILITY_DOMINION_STR   :: 1

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
	case .Momentum:    return "Momentum"
	case .Ironclad:    return "Ironclad"
	case .Aftershock:  return "Aftershock"
	case .Envenom:     return "Envenom"
	case .Predator:    return "Predator"
	case .Vengeance:   return "Vengeance"
	case .Resilient:   return "Resilient"
	case .Abyssal:     return "Abyssal"
	case .Inferno:     return "Inferno"
	case .Colossus:    return "Colossus"
	case .Dominion:    return "Dominion"
	}
	return "?"
}

ability_desc :: proc(a: Ability) -> cstring {
	switch a {
	case .NONE:        return "No ability."
	case .Berserk:     return "Starts a fight with +3 Strength."
	case .Guardian:    return "Starts a fight with +8 Block."
	case .Thick_Hide:  return "Starts a fight with +3 Defense."
	case .Swift:       return "Acts with +4 Speed for initiative."
	case .Lucky:       return "Draws 1 extra card each turn."
	case .Vampiric:    return "Heals 25% of the damage it deals."
	case .Regenerator: return "Heals 6% of its max HP each turn."
	case .Intimidate:  return "Enemies start a fight with -3 Strength."
	case .Momentum:    return "+1 Strength at the start of each turn."
	case .Ironclad:    return "+1 Dexterity at the start of each turn."
	case .Aftershock:  return "Its first Attack each turn hits twice."
	case .Envenom:     return "Its Attacks apply 1 Poison per hit."
	case .Predator:    return "+25% damage against foes below half HP."
	case .Vengeance:   return "+1 Strength whenever it takes a hit."
	case .Resilient:   return "Once a battle, survives a lethal blow at 25% HP."
	case .Abyssal:     return "Takes 30% less damage while above half HP."
	case .Inferno:     return "Burns every foe for 2 at the end of each turn."
	case .Colossus:    return "Block is not cleared between rounds."
	case .Dominion:    return "Strips 1 Strength from every foe each turn."
	}
	return ""
}

// Per-species pools, themed by role. Rolled once at spawn.
ABILITY_POOLS := [Species_Id][3]Ability{
	// Starter lines.
	.Emberling     = {.Berserk, .Momentum, .Vengeance},
	.Cinderscale     = {.Berserk, .Momentum, .Predator},
	.Magmalisk      = {.Berserk, .Momentum, .Predator},
	.Tidepup       = {.Regenerator, .Ironclad, .Guardian},
	.Ripfin        = {.Ironclad, .Guardian, .Regenerator},
	.Tidewyrm     = {.Ironclad, .Guardian, .Resilient},
	.Sproutle      = {.Regenerator, .Ironclad, .Envenom},
	.Thornbud      = {.Regenerator, .Envenom, .Ironclad},
	.Blightbloom   = {.Envenom, .Regenerator, .Vengeance},
	.Grubling       = {.Vengeance, .Resilient, .Momentum},
	.Vesperling     = {.Vampiric, .Aftershock, .Swift},
	.Rockmite       = {.Guardian, .Ironclad, .Thick_Hide},
	.Dustwing       = {.Swift, .Lucky, .Aftershock},
	.Thornkit       = {.Vengeance, .Regenerator, .Ironclad},
	.Mossling       = {.Regenerator, .Ironclad, .Guardian},
	.Bloomcap       = {.Envenom, .Regenerator, .Vengeance},
	.Barkhound      = {.Thick_Hide, .Ironclad, .Predator},
	.Bubblet        = {.Guardian, .Ironclad, .Regenerator},
	.Ripjaw         = {.Vampiric, .Aftershock, .Predator},
	.Tidecaller     = {.Ironclad, .Resilient, .Guardian},
	.Abyssal_Fry    = {.Envenom, .Vampiric, .Vengeance},
	.Gloomling      = {.Predator, .Momentum, .Vengeance},
	.Crypt_Rat      = {.Vampiric, .Envenom, .Vengeance},
	.Wispling       = {.Swift, .Lucky, .Aftershock},
	.Sporeling      = {.Envenom, .Regenerator, .Resilient},
	.Capmaw         = {.Envenom, .Vampiric, .Regenerator},
	.Sentinel       = {.Guardian, .Intimidate, .Resilient},
	.Relic_Hound    = {.Thick_Hide, .Ironclad, .Predator},
	.Hexling        = {.Swift, .Aftershock, .Lucky},
	.Snowpup        = {.Swift, .Momentum, .Predator},
	.Frostmaw       = {.Thick_Hide, .Predator, .Ironclad},
	.Glacierling    = {.Ironclad, .Guardian, .Resilient},
	.Vinecat        = {.Aftershock, .Swift, .Predator},
	.Venomtail      = {.Envenom, .Aftershock, .Vampiric},
	.Pouncer        = {.Swift, .Aftershock, .Predator},
	.Magmite        = {.Berserk, .Momentum, .Vengeance},
	.Cinderwing     = {.Swift, .Aftershock, .Berserk},
	.Slagbeast      = {.Thick_Hide, .Berserk, .Intimidate},
	.Sandfang       = {.Predator, .Momentum, .Thick_Hide},
	.Sparkit        = {.Swift, .Aftershock, .Lucky},
	.Crystalfin     = {.Ironclad, .Swift, .Aftershock},
	.Rotshell       = {.Vengeance, .Envenom, .Resilient},
	.Nightwing      = {.Vampiric, .Aftershock, .Swift},
	.Thornmaw       = {.Vengeance, .Ironclad, .Thick_Hide},
	.Bubblord       = {.Guardian, .Ironclad, .Regenerator},
	.Frostfang      = {.Swift, .Predator, .Thick_Hide},
	.Magmaw         = {.Berserk, .Momentum, .Thick_Hide},
	.Sporelord      = {.Envenom, .Regenerator, .Vampiric},
	.Voltail        = {.Swift, .Aftershock, .Lucky},
	// Bosses: the first entry is their signature, and bosses always roll it.
	.Deep_One       = {.Vengeance, .Regenerator, .Guardian},
	.Boss_Leviathan = {.Abyssal, .Regenerator, .Guardian},
	.Boss_Infernal  = {.Inferno, .Berserk, .Vampiric},
	.Boss_Titan     = {.Colossus, .Guardian, .Thick_Hide},
	.Boss_Sovereign = {.Dominion, .Swift, .Berserk},
	// Strong wilds: no signature, but all three are good.
	.Ashfang    = {.Swift, .Aftershock, .Momentum},
	.Stormwing  = {.Swift, .Lucky, .Aftershock},
	.Bogmaw     = {.Envenom, .Regenerator, .Vampiric},
	.Dreadhorn  = {.Berserk, .Momentum, .Predator},
	.Rimewarden = {.Thick_Hide, .Guardian, .Ironclad},
	.Gravemaw   = {.Vengeance, .Resilient, .Thick_Hide},
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
	// Bosses always roll their signature (the first entry in their pool).
	if SPECIES[species].role == .BOSS {
		return pool[0]
	}
	return pool[rng_below(rng, len(pool))]
}

// Fires once when a battle begins. `foes` is the opposing side, for debuffs.
ability_battle_start :: proc(b: ^Battle, self: ^Creature, foes: []^Creature) {
	side := side_of(b, self)
	switch self.ability {
	case .Berserk:
		self.strength += ABILITY_BERSERK_STR
		spawn_popup(b, side, .BUFF, ABILITY_BERSERK_STR)
		creature_burst(self, popup_color(.BUFF), 0.6)
		battle_sfx(.BUFF, 0.6)
	case .Guardian:
		self.block += ABILITY_GUARDIAN_BLOCK
		spawn_popup(b, side, .BLOCK, ABILITY_GUARDIAN_BLOCK)
		creature_burst(self, popup_color(.BLOCK), 0.6)
		battle_sfx(.BLOCK, 0.6)
	case .Thick_Hide:
		self.defense_buff += ABILITY_THICK_HIDE_DEF
		spawn_popup(b, side, .DEFEND, int(ABILITY_THICK_HIDE_DEF))
		creature_burst(self, popup_color(.DEFEND), 0.6)
		battle_sfx(.BUFF, 0.6)
	case .Swift:
		self.speed_buff += ABILITY_SWIFT_SPEED
		spawn_popup(b, side, .BUFF, int(ABILITY_SWIFT_SPEED))
		creature_burst(self, popup_color(.BUFF), 0.6)
		battle_sfx(.BUFF, 0.6)
	case .Intimidate:
		for f in foes {
			f.strength -= ABILITY_INTIMIDATE_STR
			spawn_popup(b, side_of(b, f), .WEAKEN, ABILITY_INTIMIDATE_STR)
			creature_burst(f, popup_color(.WEAKEN), 0.5)
		}
		battle_sfx(.BUFF, 0.6)
	case .NONE, .Lucky, .Vampiric, .Regenerator, .Momentum, .Ironclad, .Aftershock,
	     .Envenom, .Predator, .Vengeance, .Resilient, .Abyssal, .Inferno, .Colossus, .Dominion:
	}
}

// ----------------------------------------------------------------------------
// Ability hooks
// ----------------------------------------------------------------------------

// Start of each round.
ability_begin_round :: proc(b: ^Battle, self: ^Creature) {
	side := side_of(b, self)
	#partial switch self.ability {
	case .Momentum:
		self.strength += ABILITY_MOMENTUM_STR
		spawn_popup(b, side, .BUFF, ABILITY_MOMENTUM_STR)
		creature_burst(self, popup_color(.BUFF), 0.45)
		battle_sfx(.BUFF, 0.4)
	case .Ironclad:
		self.dexterity += ABILITY_IRONCLAD_DEX
		spawn_popup(b, side, .DEFEND, ABILITY_IRONCLAD_DEX)
		creature_burst(self, popup_color(.DEFEND), 0.45)
		battle_sfx(.BUFF, 0.4)
	case:
	}
}

// Does this creature keep its Block between rounds?
ability_keeps_block :: proc(self: ^Creature) -> bool {
	return self.ability == .Colossus
}

// Damage multiplier the attacker's ability applies against the target.
ability_attack_mult :: proc(attacker, target: ^Creature) -> f32 {
	if attacker.ability == .Predator && target.hp*2 < target.max_hp {
		return ABILITY_PREDATOR_MULT
	}
	return 1
}

// Damage-taken multiplier from the target's ability.
ability_defense_mult :: proc(target: ^Creature) -> f32 {
	if target.ability == .Abyssal && target.hp*2 > target.max_hp {
		return ABILITY_ABYSSAL_MULT
	}
	return 1
}

// Poison applied per hit by the attacker's ability.
ability_on_hit_poison :: proc(self: ^Creature) -> int {
	if self.ability == .Envenom {
		return ABILITY_ENVENOM_POISON
	}
	return 0
}

// Strength gained when this creature takes a hit (Vengeance).
ability_on_hit_taken :: proc(b: ^Battle, self: ^Creature) {
	if self.ability == .Vengeance {
		self.strength += ABILITY_VENGEANCE_STR
		spawn_popup(b, side_of(b, self), .BUFF, ABILITY_VENGEANCE_STR)
		creature_burst(self, popup_color(.BUFF), 0.45)
		battle_sfx(.BUFF, 0.4)
	}
}

// Aftershock: the first Attack each turn hits twice.
ability_first_attack_doubles :: proc(self: ^Creature) -> bool {
	return self.ability == .Aftershock
}

// Resilient: survive one lethal blow per battle.
ability_try_survive :: proc(b: ^Battle, self: ^Creature) -> bool {
	if self.ability != .Resilient || self.resilient_used || self.hp > 0 {
		return false
	}
	self.resilient_used = true
	self.hp = max(int(f32(self.max_hp) * ABILITY_RESILIENT_PCT), 1)
	spawn_popup(b, side_of(b, self), .HEAL, self.hp)
	creature_burst(self, rl.Color{255, 245, 180, 255}, 0.75)
	battle_sfx(.NOTIFY, 0.8)
	battle_log(b, "%s clings to life!", self.name)
	return true
}
