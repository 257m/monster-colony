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

Element :: enum { NEUTRAL, EMBER, AQUA, FLORA }

element_name :: proc(e: Element) -> cstring {
	switch e {
	case .NEUTRAL: return "Neutral"
	case .EMBER:   return "Ember"
	case .AQUA:    return "Aqua"
	case .FLORA:   return "Flora"
	}
	return "?"
}

element_color :: proc(e: Element) -> rl.Color {
	switch e {
	case .NEUTRAL: return rl.Color{158, 158, 172, 255}
	case .EMBER:   return rl.Color{226, 96, 62, 255}
	case .AQUA:    return rl.Color{74, 146, 226, 255}
	case .FLORA:   return rl.Color{92, 186, 104, 255}
	}
	return rl.Color{158, 158, 172, 255}
}

// Rock-paper-scissors chart: Ember > Flora > Aqua > Ember.
element_multiplier :: proc(atk, def: Element) -> f32 {
	switch atk {
	case .EMBER:
		if def == .FLORA { return 1.5 }
		if def == .AQUA { return 0.7 }
	case .AQUA:
		if def == .EMBER { return 1.5 }
		if def == .FLORA { return 0.7 }
	case .FLORA:
		if def == .AQUA { return 1.5 }
		if def == .EMBER { return 0.7 }
	case .NEUTRAL:
	}
	return 1.0
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
	defense:    int,
	heal:       int,
	draw:       int,
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
	.Iron_Skin    = {name = "Iron Skin",    desc = "+2 def",           cost = 1.0, element = .NEUTRAL, defense = 2},

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
	.Bark_Skin    = {name = "Bark Skin",    desc = "6 block, +1 def",  cost = 1.0, element = .FLORA, block = 6, defense = 1},
}

move_data :: proc(id: Move_Id) -> Move {
	return MOVE_DATA[id]
}

// Rough heuristic used by the enemy AI.
move_value :: proc(id: Move_Id) -> int {
	m := MOVE_DATA[id]
	return m.damage * max(m.hits, 1) * 2 + m.block + m.heal * 2 + m.strength * 4 + m.vulnerable * 3 + m.defense * 4 + m.draw * 2
}
