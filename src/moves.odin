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
}

Move :: struct {
	name:       string,
	desc:       string,
	cost:       f32,
	element:    Element,
	damage:     int,
	block:      int,
	hits:       int,
	vulnerable: int,
	strength:   int,
	defense:    f32,
	heal:       int,
	draw:       int,

	// Debuffs applied to the target
	strength_down: int,
	defense_down:  f32,

	// Synergies
	vuln_bonus:  int, // extra damage if the target is Vulnerable
	block_bonus: int, // extra damage if the attacker has Block
	combo_bonus: int, // extra damage if the attacker already played a card this turn
}

MOVE_DATA := [Move_Id]Move{
	.Tackle       = {name = "Tackle",       desc = "6 dmg",            cost = 1.0, element = .NEUTRAL, damage = 6, hits = 1},
	.Jab          = {name = "Jab",          desc = "3 dmg",            cost = 0.5, element = .NEUTRAL, damage = 3, hits = 1},
	.Brace        = {name = "Brace",        desc = "3 block",          cost = 0.5, element = .NEUTRAL, block = 3},
	.Body_Slam    = {name = "Body Slam",    desc = "11 dmg",           cost = 1.5, element = .NEUTRAL, damage = 11, hits = 1},
	.Guard        = {name = "Guard",        desc = "5 block",          cost = 1.0, element = .NEUTRAL, block = 5},
	.Fortify      = {name = "Fortify",      desc = "12 block",         cost = 1.5, element = .NEUTRAL, block = 12},
	.Hone         = {name = "Hone",         desc = "+2 str",           cost = 1.0, element = .NEUTRAL, strength = 2},
	.Screech      = {name = "Screech",      desc = "+2 vuln",          cost = 1.0, element = .NEUTRAL, vulnerable = 2},
	.Flurry       = {name = "Flurry",       desc = "4 dmg x2",         cost = 0.75, element = .NEUTRAL, damage = 4, hits = 2},
	.Mend         = {name = "Mend",         desc = "heal 8",           cost = 1.0, element = .NEUTRAL, heal = 8},
	.Insight      = {name = "Insight",      desc = "draw 2",           cost = 0.75, element = .NEUTRAL, draw = 2},
	.Crush        = {name = "Crush",        desc = "8 dmg, +2 vuln",   cost = 1.5, element = .NEUTRAL, damage = 8, hits = 1, vulnerable = 2},
	.Iron_Skin    = {name = "Iron Skin",    desc = "+2 def",           cost = 1.0, element = .NEUTRAL, defense = 2.0},

	.Ember_Strike = {name = "Ember Strike", desc = "6 dmg",            cost = 1.0, element = .EMBER, damage = 6, hits = 1},
	.Flame_Burst  = {name = "Flame Burst",  desc = "11 dmg",           cost = 1.5, element = .EMBER, damage = 11, hits = 1},
	.Cinder       = {name = "Cinder",       desc = "5 dmg, +1 vuln",   cost = 1.0, element = .EMBER, damage = 5, hits = 1, vulnerable = 1},
	.Inferno      = {name = "Inferno",      desc = "13 dmg",           cost = 2.0, element = .EMBER, damage = 13, hits = 1},
	.Ash_Screen   = {name = "Ash Screen",   desc = "6 block",          cost = 1.0, element = .EMBER, block = 6},
	.Blaze        = {name = "Blaze",        desc = "18 dmg",           cost = 2.5, element = .EMBER, damage = 18, hits = 1},

	.Aqua_Jet     = {name = "Aqua Jet",     desc = "6 dmg",            cost = 1.0, element = .AQUA, damage = 6, hits = 1},
	.Tidal_Slam   = {name = "Tidal Slam",   desc = "11 dmg",           cost = 1.5, element = .AQUA, damage = 11, hits = 1},
	.Undertow     = {name = "Undertow",     desc = "4 dmg, +1 vuln",   cost = 1.0, element = .AQUA, damage = 4, hits = 1, vulnerable = 1},
	.Bubble_Shield = {name = "Bubble Shield", desc = "6 block, draw 1", cost = 1.0, element = .AQUA, block = 6, draw = 1},
	.Torrent      = {name = "Torrent",      desc = "9 dmg x2",         cost = 2.5, element = .AQUA, damage = 9, hits = 2},
	.Heal_Spring  = {name = "Heal Spring",  desc = "heal 6",           cost = 1.0, element = .AQUA, heal = 6},

	.Vine_Whip    = {name = "Vine Whip",    desc = "6 dmg",            cost = 1.0, element = .FLORA, damage = 6, hits = 1},
	.Thorn_Crash  = {name = "Thorn Crash",  desc = "11 dmg",           cost = 1.5, element = .FLORA, damage = 11, hits = 1},
	.Leech        = {name = "Leech",        desc = "4 dmg, heal 4",    cost = 1.0, element = .FLORA, damage = 4, hits = 1, heal = 4},
	.Bloom        = {name = "Bloom",        desc = "heal 5, 3 block",  cost = 1.0, element = .FLORA, block = 3, heal = 5},
	.Overgrowth   = {name = "Overgrowth",   desc = "10 dmg, 4 block",  cost = 1.5, element = .FLORA, damage = 10, hits = 1, block = 4},
	.Bark_Skin    = {name = "Bark Skin",    desc = "6 block, +1 def",  cost = 1.0, element = .FLORA, block = 6, defense = 1.0},

	.Fang         = {name = "Fang",         desc = "7 dmg",            cost = 1.0, element = .NEUTRAL, damage = 7, hits = 1},
	.Exploit      = {name = "Exploit",      desc = "5 dmg, +6 vs vuln", cost = 1.0, element = .NEUTRAL, damage = 5, hits = 1, vuln_bonus = 6},
	.Payback      = {name = "Payback",      desc = "4 dmg, +6 if Blk", cost = 1.0, element = .NEUTRAL, damage = 4, hits = 1, block_bonus = 6},
	.Followup     = {name = "Followup",     desc = "3 dmg, +4 combo",  cost = 0.5, element = .NEUTRAL, damage = 3, hits = 1, combo_bonus = 4},
	.Second_Wind  = {name = "Second Wind",  desc = "heal 5, 5 block", cost = 1.0, element = .NEUTRAL, block = 5, heal = 5},
	.Combust      = {name = "Combust",      desc = "4 dmg, +5 vs vuln", cost = 1.0, element = .EMBER, damage = 4, hits = 1, vuln_bonus = 5},
	.Rampage      = {name = "Rampage",      desc = "8 dmg, +6 combo",  cost = 1.5, element = .EMBER, damage = 8, hits = 1, combo_bonus = 6},
	.Frost_Bite   = {name = "Frost Bite",   desc = "5 dmg, +4 if Blk", cost = 1.0, element = .AQUA, damage = 5, hits = 1, block_bonus = 4},
	.Lash         = {name = "Lash",         desc = "4 dmg, +5 combo",  cost = 1.0, element = .FLORA, damage = 4, hits = 1, combo_bonus = 5},

	.Gnaw         = {name = "Gnaw",         desc = "5 dmg, heal 3",   cost = 1.0, element = .NEUTRAL, damage = 5, hits = 1, heal = 3},
	.Warcry       = {name = "Warcry",       desc = "+2 str, +1 def",  cost = 1.0, element = .NEUTRAL, strength = 2, defense = 1.0},
	.Twin_Fangs   = {name = "Twin Fangs",   desc = "5 dmg x2",        cost = 1.5, element = .NEUTRAL, damage = 5, hits = 2},
	.Feint        = {name = "Feint",        desc = "draw 1",          cost = 0.5, element = .NEUTRAL, draw = 1},
	.Flare        = {name = "Flare",        desc = "3 dmg, +1 vuln, +3 combo", cost = 1.0, element = .EMBER, damage = 3, hits = 1, vulnerable = 1, combo_bonus = 3},
	.Tidecall     = {name = "Tidecall",     desc = "draw 1, heal 4",  cost = 1.0, element = .AQUA, draw = 1, heal = 4},
	.Bramble      = {name = "Bramble",      desc = "4 dmg, +4 vs vuln", cost = 1.0, element = .FLORA, damage = 4, hits = 1, vuln_bonus = 4},
	.Regrowth     = {name = "Regrowth",     desc = "heal 8, 4 block", cost = 1.5, element = .FLORA, heal = 8, block = 4},

	.Frost_Shard  = {name = "Frost Shard",  desc = "6 dmg",           cost = 1.0, element = .ICE, damage = 6, hits = 1},
	.Glacier_Slam = {name = "Glacier Slam", desc = "12 dmg",          cost = 2.0, element = .ICE, damage = 12, hits = 1},
	.Rock_Toss    = {name = "Rock Toss",    desc = "6 dmg",           cost = 1.0, element = .GROUND, damage = 6, hits = 1},
	.Quake        = {name = "Quake",        desc = "13 dmg",          cost = 2.0, element = .GROUND, damage = 13, hits = 1},
	.Spark        = {name = "Spark",        desc = "5 dmg, +3 combo", cost = 1.0, element = .ELECTRIC, damage = 5, hits = 1, combo_bonus = 3},
	.Thunderbolt  = {name = "Thunderbolt",  desc = "13 dmg",          cost = 2.0, element = .ELECTRIC, damage = 13, hits = 1},
	.Gust         = {name = "Gust",         desc = "4 dmg x2",        cost = 1.0, element = .AIR, damage = 4, hits = 2},
	.Cyclone      = {name = "Cyclone",      desc = "12 dmg",          cost = 2.0, element = .AIR, damage = 12, hits = 1},
	.Toxic_Bite   = {name = "Toxic Bite",   desc = "5 dmg, +1 vuln",  cost = 1.0, element = .POISON, damage = 5, hits = 1, vulnerable = 1},
	.Venom        = {name = "Venom",        desc = "10 dmg, +2 vuln", cost = 2.0, element = .POISON, damage = 10, hits = 1, vulnerable = 2},

	// Debuffs: weaken the enemy instead of buffing yourself.
	.Weaken       = {name = "Weaken",       desc = "-2 enemy str",     cost = 1.0, element = .NEUTRAL, strength_down = 2},
	.Disarm       = {name = "Disarm",       desc = "4 dmg, -2 str",    cost = 1.25, element = .NEUTRAL, damage = 4, hits = 1, strength_down = 2},
	.Sunder       = {name = "Sunder",       desc = "6 dmg, -2 def",    cost = 1.5, element = .NEUTRAL, damage = 6, hits = 1, defense_down = 2.0},
	.Corrode      = {name = "Corrode",      desc = "-3 enemy def",     cost = 1.0, element = .POISON, defense_down = 3.0},
}

move_data :: proc(id: Move_Id) -> Move {
	return MOVE_DATA[id]
}

// Rough heuristic used by the enemy AI.
move_value :: proc(id: Move_Id) -> int {
	m := MOVE_DATA[id]
	return m.damage * max(m.hits, 1) * 2 + m.block + m.heal * 2 + m.strength * 4 + m.vulnerable * 3 + int(m.defense) * 4 + m.draw * 2 +
		m.strength_down * 4 + int(m.defense_down) * 4 +
		(m.vuln_bonus + m.block_bonus + m.combo_bonus) / 2
}
