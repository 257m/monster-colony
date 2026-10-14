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
	Jab,
	Brace,
	Body_Slam,
	Guard,
	Fortify,
	Hone,
	Screech,
	Flurry,
	Mend,
	Insight,
	Crush,
	Iron_Skin,

	// Ember
	Ember_Strike,
	Flame_Burst,
	Cinder,
	Inferno,
	Ash_Screen,
	Blaze,

	// Aqua
	Aqua_Jet,
	Tidal_Slam,
	Undertow,
	Bubble_Shield,
	Torrent,
	Heal_Spring,

	// Flora
	Vine_Whip,
	Thorn_Crash,
	Leech,
	Bloom,
	Overgrowth,
	Bark_Skin,

	// Content (Phase 4): synergy moves
	Fang,
	Exploit,
	Payback,
	Followup,
	Second_Wind,
	Combust,
	Rampage,
	Frost_Bite,
	Lash,

	// Content (Phase 4) wave 2
	Gnaw,
	Warcry,
	Twin_Fangs,
	Feint,
	Flare,
	Tidecall,
	Bramble,
	Regrowth,

	// New elements
	Frost_Shard,
	Glacier_Slam,
	Rock_Toss,
	Quake,
	Spark,
	Thunderbolt,
	Gust,
	Cyclone,
	Toxic_Bite,
	Venom,

	// Debuffs
	Weaken,
	Disarm,
	Sunder,
	Corrode,

	// Premium reward cards: expensive, high-impact energy sinks.
	Meteor,
	Tsunami,
	Maelstrom,
	Cataclysm,
	Aegis,
	Phoenix,

	// Status-effect cards (Phase 21)
	Toxic_Cloud,
	Envenom,
	Plague,
	Ember_Coil,
	Immolate,
	Wildfire,
	Concuss,
	Static_Shock,
	Paralyze,
	Photosynth,
	Rejuvenate,
	Bramble_Armor,
	Spike_Shell,
}

// Card rarity drives how often a reward pick offers it (see `Rarity` in
// creature.odin). Premium cards are always RARE, so they show up as the rare
// third option.
Move :: struct {
	name:       string,
	desc:       string,
	cost:       f32,
	element:    Element,
	rarity:     Rarity,
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
}

MOVE_DATA := [Move_Id]Move{
	.Tackle       = {name = "Tackle",       desc = "5 dmg",                     cost = 1.0, element = .NEUTRAL, damage = 5, hits = 1},
	.Jab          = {name = "Jab",          desc = "2 dmg",                     cost = 0.5, element = .NEUTRAL, damage = 2, hits = 1},
	.Brace        = {name = "Brace",        desc = "3 block",                   cost = 0.5, element = .NEUTRAL, block = 3},
	.Body_Slam    = {name = "Body Slam",    desc = "9 dmg",                     cost = 1.5, element = .NEUTRAL, damage = 9, hits = 1},
	.Guard        = {name = "Guard",        desc = "5 block",                   cost = 1.0, element = .NEUTRAL, block = 5},
	.Fortify      = {name = "Fortify",      desc = "12 block",                  cost = 1.5, element = .NEUTRAL, block = 12},
	.Hone         = {name = "Hone",         desc = "+5 str",                    cost = 1.0, element = .NEUTRAL, strength = 5},
	.Screech      = {name = "Screech",      desc = "+2 vuln",                   cost = 1.0, element = .NEUTRAL, vulnerable = 2},
	.Flurry       = {name = "Flurry",       desc = "3 dmg x2",                  cost = 0.75, element = .NEUTRAL, damage = 3, hits = 2},
	.Mend         = {name = "Mend",         desc = "heal 13% HP",               cost = 1.0, element = .NEUTRAL, heal_pct = 0.13},
	.Insight      = {name = "Insight",      desc = "draw 2",                    cost = 0.75, element = .NEUTRAL, draw = 2},
	.Crush        = {name = "Crush",        desc = "6 dmg, +2 vuln",            cost = 1.5, element = .NEUTRAL, rarity = .UNCOMMON, damage = 6, hits = 1, vulnerable = 2},
	.Iron_Skin    = {name = "Iron Skin",    desc = "+2 def",                    cost = 1.0, element = .NEUTRAL, rarity = .UNCOMMON, defense = 2.0},

	.Ember_Strike = {name = "Ember Strike", desc = "5 dmg",                     cost = 1.0, element = .EMBER, damage = 5, hits = 1},
	.Flame_Burst  = {name = "Flame Burst",  desc = "9 dmg",                     cost = 1.5, element = .EMBER, rarity = .UNCOMMON, damage = 9, hits = 1},
	.Cinder       = {name = "Cinder",       desc = "4 dmg, +1 vuln",            cost = 1.0, element = .EMBER, damage = 4, hits = 1, vulnerable = 1},
	.Inferno      = {name = "Inferno",      desc = "10 dmg",                    cost = 2.0, element = .EMBER, rarity = .RARE, damage = 10, hits = 1},
	.Ash_Screen   = {name = "Ash Screen",   desc = "6 block",                   cost = 1.0, element = .EMBER, block = 6},
	.Blaze        = {name = "Blaze",        desc = "14 dmg",                    cost = 2.5, element = .EMBER, rarity = .RARE, damage = 14, hits = 1},

	.Aqua_Jet     = {name = "Aqua Jet",     desc = "5 dmg",                     cost = 1.0, element = .AQUA, damage = 5, hits = 1},
	.Tidal_Slam   = {name = "Tidal Slam",   desc = "9 dmg",                     cost = 1.5, element = .AQUA, rarity = .UNCOMMON, damage = 9, hits = 1},
	.Undertow     = {name = "Undertow",     desc = "3 dmg, +1 vuln",            cost = 1.0, element = .AQUA, damage = 3, hits = 1, vulnerable = 1},
	.Bubble_Shield = {name = "Bubble Shield", desc = "6 block, draw 1",         cost = 1.0, element = .AQUA, block = 6, draw = 1},
	.Torrent      = {name = "Torrent",      desc = "7 dmg x2",                  cost = 2.5, element = .AQUA, rarity = .RARE, damage = 7, hits = 2},
	.Heal_Spring  = {name = "Heal Spring",  desc = "heal 10% HP",               cost = 1.0, element = .AQUA, heal_pct = 0.10},

	.Vine_Whip    = {name = "Vine Whip",    desc = "5 dmg",                     cost = 1.0, element = .FLORA, damage = 5, hits = 1},
	.Thorn_Crash  = {name = "Thorn Crash",  desc = "9 dmg",                     cost = 1.5, element = .FLORA, rarity = .UNCOMMON, damage = 9, hits = 1},
	.Leech        = {name = "Leech",        desc = "3 dmg, drain 60%",          cost = 1.0, element = .FLORA, damage = 3, hits = 1, leech_pct = 0.60},
	.Bloom        = {name = "Bloom",        desc = "heal 8% HP, 3 block",        cost = 1.0, element = .FLORA, block = 3, heal_pct = 0.08},
	.Overgrowth   = {name = "Overgrowth",   desc = "8 dmg, 4 block",            cost = 1.5, element = .FLORA, rarity = .RARE, damage = 8, hits = 1, block = 4},
	.Bark_Skin    = {name = "Bark Skin",    desc = "6 block, +1 def",           cost = 1.0, element = .FLORA, rarity = .UNCOMMON, block = 6, defense = 1.0},

	.Fang         = {name = "Fang",         desc = "6 dmg",                     cost = 1.0, element = .NEUTRAL, rarity = .UNCOMMON, damage = 6, hits = 1},
	.Exploit      = {name = "Exploit",      desc = "4 dmg, +6 vs vuln",         cost = 1.0, element = .NEUTRAL, rarity = .UNCOMMON, damage = 4, hits = 1, vuln_bonus = 6},
	.Payback      = {name = "Payback",      desc = "3 dmg, +6 if Blk",          cost = 1.0, element = .NEUTRAL, rarity = .UNCOMMON, damage = 3, hits = 1, block_bonus = 6},
	.Followup     = {name = "Followup",     desc = "2 dmg, +4 combo",           cost = 0.5, element = .NEUTRAL, damage = 2, hits = 1, combo_bonus = 4},
	.Second_Wind  = {name = "Second Wind",  desc = "heal 8% HP, 5 block",       cost = 1.0, element = .NEUTRAL, rarity = .UNCOMMON, block = 5, heal_pct = 0.08},
	.Combust      = {name = "Combust",      desc = "3 dmg, +5 vs vuln",         cost = 1.0, element = .EMBER, rarity = .UNCOMMON, damage = 3, hits = 1, vuln_bonus = 5},
	.Rampage      = {name = "Rampage",      desc = "6 dmg, +6 combo",           cost = 1.5, element = .EMBER, rarity = .UNCOMMON, damage = 6, hits = 1, combo_bonus = 6},
	.Frost_Bite   = {name = "Frost Bite",   desc = "4 dmg, +4 if Blk",          cost = 1.0, element = .AQUA, rarity = .UNCOMMON, damage = 4, hits = 1, block_bonus = 4},
	.Lash         = {name = "Lash",         desc = "3 dmg, +5 combo",           cost = 1.0, element = .FLORA, rarity = .UNCOMMON, damage = 3, hits = 1, combo_bonus = 5},

	.Gnaw         = {name = "Gnaw",         desc = "4 dmg, drain 50%",          cost = 1.0, element = .NEUTRAL, damage = 4, hits = 1, leech_pct = 0.50},
	.Warcry       = {name = "Warcry",       desc = "+4 str, +1 def",            cost = 1.0, element = .NEUTRAL, rarity = .UNCOMMON, strength = 4, defense = 1.0},
	.Twin_Fangs   = {name = "Twin Fangs",   desc = "4 dmg x2",                  cost = 1.5, element = .NEUTRAL, rarity = .UNCOMMON, damage = 4, hits = 2},
	.Feint        = {name = "Feint",        desc = "draw 1",                    cost = 0.5, element = .NEUTRAL, draw = 1},
	.Flare        = {name = "Flare",        desc = "2 dmg, +1 vuln, +3 combo",  cost = 1.0, element = .EMBER, rarity = .UNCOMMON, damage = 2, hits = 1, vulnerable = 1, combo_bonus = 3},
	.Tidecall     = {name = "Tidecall",     desc = "draw 1, heal 7% HP",        cost = 1.0, element = .AQUA, rarity = .UNCOMMON, draw = 1, heal_pct = 0.07},
	.Bramble      = {name = "Bramble",      desc = "3 dmg, +4 vs vuln",         cost = 1.0, element = .FLORA, rarity = .UNCOMMON, damage = 3, hits = 1, vuln_bonus = 4},
	.Regrowth     = {name = "Regrowth",     desc = "heal 13% HP, 4 block",      cost = 1.5, element = .FLORA, rarity = .UNCOMMON, heal_pct = 0.13, block = 4},

	.Frost_Shard  = {name = "Frost Shard",  desc = "5 dmg",                     cost = 1.0, element = .ICE, damage = 5, hits = 1},
	.Glacier_Slam = {name = "Glacier Slam", desc = "10 dmg",                    cost = 2.0, element = .ICE, rarity = .UNCOMMON, damage = 10, hits = 1},
	.Rock_Toss    = {name = "Rock Toss",    desc = "5 dmg",                     cost = 1.0, element = .GROUND, damage = 5, hits = 1},
	.Quake        = {name = "Quake",        desc = "10 dmg",                    cost = 2.0, element = .GROUND, rarity = .UNCOMMON, damage = 10, hits = 1},
	.Spark        = {name = "Spark",        desc = "4 dmg, +3 combo",           cost = 1.0, element = .ELECTRIC, damage = 4, hits = 1, combo_bonus = 3},
	.Thunderbolt  = {name = "Thunderbolt",  desc = "10 dmg",                    cost = 2.0, element = .ELECTRIC, rarity = .UNCOMMON, damage = 10, hits = 1},
	.Gust         = {name = "Gust",         desc = "3 dmg x2",                  cost = 1.0, element = .AIR, damage = 3, hits = 2},
	.Cyclone      = {name = "Cyclone",      desc = "10 dmg",                    cost = 2.0, element = .AIR, rarity = .UNCOMMON, damage = 10, hits = 1},
	.Toxic_Bite   = {name = "Toxic Bite",   desc = "4 dmg, +1 vuln",            cost = 1.0, element = .POISON, damage = 4, hits = 1, vulnerable = 1},
	.Venom        = {name = "Venom",        desc = "8 dmg, +2 vuln",            cost = 2.0, element = .POISON, rarity = .UNCOMMON, damage = 8, hits = 1, vulnerable = 2},

	// Debuffs: weaken the enemy instead of buffing yourself.
	.Weaken       = {name = "Weaken",       desc = "-2 enemy str",              cost = 1.0, element = .NEUTRAL, strength_down = 2},
	.Disarm       = {name = "Disarm",       desc = "3 dmg, -2 str",             cost = 1.25, element = .NEUTRAL, rarity = .UNCOMMON, damage = 3, hits = 1, strength_down = 2},
	.Sunder       = {name = "Sunder",       desc = "5 dmg, -2 def",             cost = 1.5, element = .NEUTRAL, rarity = .UNCOMMON, damage = 5, hits = 1, defense_down = 2.0},
	.Corrode      = {name = "Corrode",      desc = "-3 enemy def",              cost = 1.0, element = .POISON, rarity = .UNCOMMON, defense_down = 3.0},

	// Premium reward cards: costly, high-impact — the energy sinks.
	.Meteor       = {name = "Meteor",       desc = "20 dmg",                    cost = 3.0, element = .EMBER, rarity = .RARE, damage = 20, hits = 1},
	.Tsunami      = {name = "Tsunami",      desc = "9 dmg x2",                  cost = 3.0, element = .AQUA, rarity = .RARE, damage = 9, hits = 2},
	.Maelstrom    = {name = "Maelstrom",    desc = "6 dmg x3",                  cost = 3.0, element = .AIR, rarity = .RARE, damage = 6, hits = 3},
	.Cataclysm    = {name = "Cataclysm",    desc = "22 dmg",                    cost = 3.5, element = .GROUND, rarity = .RARE, damage = 22, hits = 1},
	.Aegis        = {name = "Aegis",        desc = "24 block",                  cost = 3.0, element = .NEUTRAL, rarity = .RARE, block = 24},
	.Phoenix      = {name = "Phoenix",      desc = "12 dmg, drain 60%",         cost = 3.5, element = .EMBER, rarity = .RARE, damage = 12, hits = 1, leech_pct = 0.60},

	// Status-effect cards: poison/burn (DoT), stun, regen and thorns.
	.Toxic_Cloud  = {name = "Toxic Cloud",  desc = "2 poison",                  cost = 1.0, element = .POISON, rarity = .UNCOMMON, poison = 2},
	.Envenom      = {name = "Envenom",      desc = "3 dmg, 2 poison",           cost = 1.0, element = .POISON, rarity = .UNCOMMON, damage = 3, hits = 1, poison = 2},
	.Plague       = {name = "Plague",       desc = "4 poison",                  cost = 1.5, element = .POISON, rarity = .RARE, poison = 4},
	.Ember_Coil   = {name = "Ember Coil",   desc = "2 burn",                    cost = 1.0, element = .EMBER, rarity = .UNCOMMON, burn = 2},
	.Immolate     = {name = "Immolate",     desc = "5 dmg, 3 burn",             cost = 1.5, element = .EMBER, rarity = .UNCOMMON, damage = 5, hits = 1, burn = 3},
	.Wildfire     = {name = "Wildfire",     desc = "4 burn",                    cost = 2.0, element = .EMBER, rarity = .RARE, burn = 4},
	.Concuss      = {name = "Concuss",      desc = "4 dmg, stun 1",             cost = 1.5, element = .NEUTRAL, rarity = .UNCOMMON, damage = 4, hits = 1, stun = 1},
	.Static_Shock = {name = "Static Shock", desc = "2 dmg, stun 1",             cost = 1.0, element = .ELECTRIC, rarity = .UNCOMMON, damage = 2, hits = 1, stun = 1},
	.Paralyze     = {name = "Paralyze",     desc = "stun 2",                    cost = 2.5, element = .ELECTRIC, rarity = .RARE, stun = 2},
	.Photosynth   = {name = "Photosynth",   desc = "regen 3",                   cost = 1.0, element = .FLORA, rarity = .UNCOMMON, regen = 3},
	.Rejuvenate   = {name = "Rejuvenate",   desc = "regen 2, 5 block",          cost = 1.5, element = .FLORA, rarity = .RARE, block = 5, regen = 2},
	.Bramble_Armor = {name = "Bramble Armor", desc = "thorns 3",                cost = 1.0, element = .FLORA, rarity = .UNCOMMON, thorns = 3},
	.Spike_Shell  = {name = "Spike Shell",  desc = "thorns 2, 6 block",         cost = 1.5, element = .NEUTRAL, rarity = .RARE, block = 6, thorns = 2},
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
		(m.vuln_bonus + m.block_bonus + m.combo_bonus) / 2
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
