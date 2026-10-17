package main

import rl "vendor:raylib"
import "core:fmt"
import "core:math"

// Compact number formatting: 3 -> "3", 2.5 -> "2.5", 1.25 -> "1.25".
fmt_num :: proc(v: f32) -> cstring {
	r := math.round(v * 100.0) / 100.0
	if r == f32(int(r)) {
		return fmt.ctprintf("%d", int(r))
	}
	tenths := r * 10.0
	if abs(tenths-math.round(tenths)) < 0.0001 {
		return fmt.ctprintf("%.1f", r)
	}
	return fmt.ctprintf("%.2f", r)
}

// ============================================================================
// ELEMENTS
// ============================================================================

Element :: enum { NEUTRAL, EMBER, AQUA, FLORA, ICE, GROUND, ELECTRIC, AIR, POISON }

element_name :: proc(e: Element) -> cstring {
	switch e {
	case .NEUTRAL:  return "Neutral"
	case .EMBER:    return "Ember"
	case .AQUA:     return "Aqua"
	case .FLORA:    return "Flora"
	case .ICE:      return "Ice"
	case .GROUND:   return "Ground"
	case .ELECTRIC: return "Electric"
	case .AIR:      return "Air"
	case .POISON:   return "Poison"
	}
	return "?"
}

element_color :: proc(e: Element) -> rl.Color {
	switch e {
	case .NEUTRAL:  return rl.Color{158, 158, 172, 255}
	case .EMBER:    return rl.Color{226, 96, 62, 255}
	case .AQUA:     return rl.Color{74, 146, 226, 255}
	case .FLORA:    return rl.Color{92, 186, 104, 255}
	case .ICE:      return rl.Color{150, 220, 240, 255}
	case .GROUND:   return rl.Color{156, 124, 82, 255}
	case .ELECTRIC: return rl.Color{242, 214, 70, 255}
	case .AIR:      return rl.Color{200, 210, 228, 255}
	case .POISON:   return rl.Color{166, 82, 182, 255}
	}
	return rl.Color{158, 158, 172, 255}
}

// Weakness = 2x, resistance = 0.5x.
element_multiplier :: proc(atk, def: Element) -> f32 {
	if element_super(atk, def) {
		return 2.0
	}
	if element_weak(atk, def) {
		return 0.5
	}
	return 1.0
}

element_super :: proc(atk, def: Element) -> bool {
	switch atk {
	case .EMBER:    return def == .FLORA || def == .ICE
	case .AQUA:     return def == .EMBER || def == .GROUND
	case .FLORA:    return def == .AQUA || def == .GROUND
	case .ICE:      return def == .FLORA || def == .GROUND || def == .AIR
	case .GROUND:   return def == .EMBER || def == .ELECTRIC || def == .POISON
	case .ELECTRIC: return def == .AQUA || def == .AIR
	case .AIR:      return def == .FLORA || def == .GROUND
	case .POISON:   return def == .FLORA || def == .AQUA
	case .NEUTRAL:  return false
	}
	return false
}

element_weak :: proc(atk, def: Element) -> bool {
	switch atk {
	case .EMBER:    return def == .EMBER || def == .AQUA || def == .GROUND
	case .AQUA:     return def == .AQUA || def == .FLORA || def == .ELECTRIC
	case .FLORA:    return def == .FLORA || def == .EMBER || def == .AIR || def == .POISON
	case .ICE:      return def == .ICE || def == .EMBER || def == .AQUA
	case .GROUND:   return def == .GROUND || def == .FLORA || def == .AIR
	case .ELECTRIC: return def == .ELECTRIC || def == .FLORA || def == .GROUND
	case .AIR:      return def == .AIR || def == .ELECTRIC || def == .ICE
	case .POISON:   return def == .POISON || def == .GROUND
	case .NEUTRAL:  return false
	}
	return false
}

// ============================================================================
// MOVES
//
// Every move is identified by an enum value; all data lives in MOVE_DATA.
// Decks, hands, draw piles and rewards all store Move_Ids. Costs are in
// half-point steps (0.5) because energy is granular.
// ============================================================================

Move_Id :: enum {
	// Neutral
	Tackle,
	Ember_Strike,
	Aqua_Jet,
	Vine_Whip,
	Snowball,
	Sand_Attack,
	Zap,
	Gust,
	Sting,
	Haze,
}

// Card rarity drives how often a reward pick offers it (see `Rarity` in
// creature.odin). Premium cards are always RARE, so they show up as the rare
// third option.
// Who a card acts on. `ENEMY` is the default (and the zero value, so existing
// offensive cards need no annotation); `SELF` and `ALLY` cards are support. The
// player picks the enemy or ally target the same way (click the creature), and
// `SELF` needs no target.
Move_Target :: enum { ENEMY, SELF, ALLY }

// ----------------------------------------------------------------------------
// MOVES
//
// Vocabulary used throughout the battle code:
//
//   creature stat  - a live number on a `Creature`: power, strength, defense,
//                    block, hp, max_hp, speed, energy.
//   move data      - the card's own numbers, on `Move`: cost, damage, hits,
//                    plus effect payloads named after the creature stat they
//                    touch (`strength` grants Strength, `strength_down` strips
//                    it, `self_defense_down` costs the caster Defense).
//   multiplier     - a computed factor in the damage formula. Always ends in
//                    `_mult`: offense_mult, type_mult, stab_mult, vuln_mult,
//                    defense_mult.
//
// Damage scaling on a move comes in two forms: `scale_<stat>` is additive
// (adds to the hit's base), `mult_<stat>` is multiplicative.
// ----------------------------------------------------------------------------

// Which creature stat a card attacks with. POWER (the default) = the caster's
// power, with the strength bonus; DEFENSE = Body Press, which uses the caster's
// defense for both the stat and the bonus.
Offense_Stat :: enum { POWER, DEFENSE }

Move :: struct {
	name:       string,
	desc:       string,
	cost:       f32,
	element:    Element,
	rarity:     Rarity,
	// The kinds this card can be played on. Empty = enemy-only (the default),
	// so plain attack cards don't have to annotate anything.
	targets: bit_set[Move_Target],
	damage:     int,
	block:      int,
	hits:       int,
	vulnerable: int,
	strength:   int,
	defense:    f32,
	heal_pct:   f32, // heal = this fraction of the caster's max HP
	leech_pct:  f32, // heal = this fraction of the damage the card dealt
	draw:       int,

	// Debuffs applied to the target
	strength_down: int,
	defense_down:  f32,

	// Status effects (Phase 21)
	poison: int, // apply Poison stacks to the target
	burn:   int, // apply Burn stacks to the target
	stun:   int, // apply Stun rounds to the target
	regen:  int, // apply Regen stacks to the caster
	thorns: int, // apply Thorns to the caster

	// Synergies
	vuln_bonus:  int, // extra damage if the target is Vulnerable
	block_bonus: int, // extra damage if the attacker has Block
	combo_bonus: int, // extra damage if the attacker already played a card this turn

	// Teamwork & energy
	energy_give:  int, // give energy to the beneficiary
	energy_drain: int, // drain energy from the victim (the caster gains it)
	execute_bonus: int, // extra damage when the victim is low
	execute_pct:   f32, // the "low" threshold, as a fraction of max HP
	ally_bonus:    int, // extra damage per other living ally

	// Damage scaling (see the header): scale_* adds, mult_* multiplies.
	scale_block:      f32, // + caster's block x this
	scale_defense:    f32, // + caster's defense x this
	scale_max_hp:     f32, // + caster's max HP x this
	scale_missing_hp: f32, // + the HP the caster has lost x this
	mult_missing_hp:  f32, // x (1 + this x the fraction of HP the caster has lost)
	// Offense: which creature stat it attacks with.
	offense_stat: Offense_Stat,

	// Utility
	clear_boosts: bool, // wipe every battle modifier on the target (Haze)

	// Self-costs (paid by the caster whatever the target)
	self_strength_down: int,
	self_defense_down:  f32,
	self_damage:        int,
}

MOVE_DATA := [Move_Id]Move{
	.Tackle       = {name = "Tackle",       desc = "5 dmg",                     cost = 1.0, element = .NEUTRAL, damage = 5, hits = 1},
	.Ember_Strike = {name = "Ember Strike", desc = "5 dmg",                     cost = 1.0, element = .EMBER, damage = 5, hits = 1},
	.Aqua_Jet     = {name = "Aqua Jet",     desc = "5 dmg",                     cost = 1.0, element = .AQUA, damage = 5, hits = 1},
	.Vine_Whip    = {name = "Vine Whip",    desc = "5 dmg",                     cost = 1.0, element = .FLORA, damage = 5, hits = 1},
	.Snowball     = {name = "Snowball",     desc = "5 dmg",                     cost = 1.0, element = .ICE, damage = 5, hits = 1},
	.Sand_Attack  = {name = "Sand Attack",  desc = "5 dmg",                     cost = 1.0, element = .GROUND, damage = 5, hits = 1},
	.Zap          = {name = "Zap",          desc = "5 dmg",                     cost = 1.0, element = .ELECTRIC, damage = 5, hits = 1},
	.Gust         = {name = "Gust",         desc = "5 dmg",                     cost = 1.0, element = .AIR, damage = 5, hits = 1},
	.Sting        = {name = "String",       desc = "5 dmg",                     cost = 1.0, element = .POISON, damage = 5, hits = 1},
	.Haze         = {name = "Haze",         desc = "clear all boosts",          cost = 1.0, element = .ICE, rarity = .UNCOMMON, targets = {.ENEMY, .SELF, .ALLY}, clear_boosts = true},
}

// The kinds a card can be played on. An empty set means enemy-only (the
// default), so `targets = {.ENEMY}` is the same as leaving it blank.
move_targets :: proc(m: Move) -> bit_set[Move_Target] {
	if card(m.targets) == 0 {
		return {.ENEMY}
	}
	return m.targets
}

// Does this card deal damage (flat, or scaled off a stat)?
move_has_damage :: proc(m: Move) -> bool {
	return m.damage > 0 || m.scale_block > 0 || m.scale_defense > 0 || m.scale_max_hp > 0 || m.scale_missing_hp > 0
}

// Short label for the kinds a card can be played on (shown in the tooltip).
move_target_label :: proc(m: Move) -> string {
	t := move_targets(m)
	switch {
	case t == {.ENEMY}:
		return "enemy"
	case t == {.SELF}:
		return "self"
	case t == {.ALLY}:
		return "ally"
	case .ENEMY in t && .ALLY in t && .SELF in t:
		return "any target"
	case .ALLY in t && .SELF in t:
		return "self or ally"
	case .ENEMY in t && .ALLY in t:
		return "enemy or ally"
	}
	return "target"
}

move_data :: proc(id: Move_Id) -> Move {
	return MOVE_DATA[id]
}

// Rough heuristic used by the enemy AI.
move_value :: proc(id: Move_Id) -> int {
	m := MOVE_DATA[id]
	return m.damage * max(m.hits, 1) * 2 + m.block + int(m.heal_pct * 140) + int(m.leech_pct * 40) + m.strength * 4 + m.vulnerable * 3 + int(m.defense) * 4 + m.draw * 2 +
		m.strength_down * 4 + int(m.defense_down) * 4 +
		m.poison * 3 + m.burn * 3 + m.stun * 8 + m.regen * 3 + m.thorns * 2 +
		(m.vuln_bonus + m.block_bonus + m.combo_bonus) / 2 +
		m.energy_give * 5 + m.energy_drain * 5 +
		(m.execute_bonus + m.ally_bonus) / 2 +
		int((m.scale_block + m.scale_defense) * 6) + int((m.scale_max_hp + m.scale_missing_hp) * 60) + int(m.mult_missing_hp * 8) +
		(m.offense_stat == .DEFENSE ? 6 : 0) + (m.clear_boosts ? 8 : 0) -
		m.self_strength_down * 4 - int(m.self_defense_down) * 4 - m.self_damage * 2
}

// Relative likelihood of a card appearing in a reward offer. Only COMMON,
// UNCOMMON and RARE are used for cards.
card_rarity_weight :: proc(r: Rarity) -> int {
	switch r {
	case .COMMON:    return 8
	case .UNCOMMON:  return 4
	case .RARE:      return 1
	case .EPIC:      return 0
	case .LEGENDARY: return 0
	}
	return 1
}

card_rarity_name :: proc(r: Rarity) -> cstring {
	switch r {
	case .COMMON:    return "Common"
	case .UNCOMMON:  return "Uncommon"
	case .RARE:      return "Rare"
	case .EPIC:      return "Epic"
	case .LEGENDARY: return "Legendary"
	}
	return "?"
}

card_rarity_color :: proc(r: Rarity) -> rl.Color {
	switch r {
	case .COMMON:    return rl.Color{190, 196, 210, 255}
	case .UNCOMMON:  return rl.Color{120, 210, 150, 255}
	case .RARE:      return rl.Color{235, 190, 90, 255}
	case .EPIC:      return rl.Color{200, 140, 250, 255}
	case .LEGENDARY: return rl.Color{250, 200, 90, 255}
	}
	return rl.Color{190, 196, 210, 255}
}

// Gold cost to forget (permanently remove) a card from a deck. Rarer cards are
// pricier to shed, so thinning a deck is a real economic choice.
forget_card_cost :: proc(id: Move_Id) -> int {
	switch MOVE_DATA[id].rarity {
	case .COMMON:    return 20
	case .UNCOMMON:  return 45
	case .RARE:      return 90
	case .EPIC:      return 150
	case .LEGENDARY: return 250
	}
	return 20
}
