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
	Body_Press,
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

	// Teamwork (support / energy)
	Channel,
	Shared_Ward,
	Field_Mend,
	Siphon,
	Cull,
	Coordinated_Strike,
	Overexert,
	Kindle,
	Conduit,
	Ward,
	Shield_Bash,
	Iron_Slam,
	Vital_Strike,
	Last_Stand,
	Reckoning,
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
	.Jab          = {name = "Jab",          desc = "2 dmg",                     cost = 0.1, element = .NEUTRAL, damage = 2, hits = 1},
	.Brace        = {name = "Brace",        desc = "3 block",                   cost = 0.5, element = .NEUTRAL, block = 3},
	.Body_Slam    = {name = "Body Slam",    desc = "9 dmg",                     cost = 1.5, element = .NEUTRAL, damage = 9, hits = 1},
	.Body_Press   = {name = "Body Press",   desc = "6 dmg, uses def",           cost = 1.5, element = .NEUTRAL, rarity = .UNCOMMON, damage = 6, hits = 1, offense_stat = .DEFENSE},
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

	// Teamwork: cards that act on an ally, on yourself, or punish a weakened foe.
	.Channel      = {name = "Channel",      desc = "ally +3 energy",            cost = 0.5, element = .NEUTRAL, targets = {.ALLY},  rarity = .COMMON, energy_give = 3},
	.Shared_Ward  = {name = "Shared Ward",  desc = "ally +9 block",             cost = 1.0, element = .NEUTRAL, targets = {.ALLY},  rarity = .COMMON, block = 9},
	.Field_Mend   = {name = "Field Mend",   desc = "ally heal 22%",             cost = 1.0, element = .NEUTRAL, targets = {.ALLY},  rarity = .UNCOMMON, heal_pct = 0.22},
	.Siphon       = {name = "Siphon",       desc = "3 dmg, steal 3 en",        cost = 1.0, element = .NEUTRAL, rarity = .UNCOMMON, damage = 3, hits = 1, energy_drain = 3},
	.Cull         = {name = "Cull",         desc = "6 dmg, +10 low hp",         cost = 1.5, element = .NEUTRAL, rarity = .UNCOMMON, damage = 6, hits = 1, execute_bonus = 10, execute_pct = 0.4},
	.Coordinated_Strike = {name = "Coordinated Strike", desc = "4 dmg, +2 per ally", cost = 1.0, element = .NEUTRAL, rarity = .UNCOMMON, damage = 4, hits = 1, ally_bonus = 2},
	.Overexert    = {name = "Overexert",    desc = "+5 str, -2 def",             cost = 0.5, element = .NEUTRAL, targets = {.SELF},  rarity = .COMMON, strength = 5, self_defense_down = 2},
	// Flexible targets: the same card reads differently depending on what it hits.
	.Kindle       = {name = "Kindle",       desc = "6 dmg / +3 str",             cost = 1.0, element = .EMBER, rarity = .UNCOMMON, targets = {.ENEMY, .SELF, .ALLY}, damage = 6, hits = 1, strength = 3},
	.Conduit      = {name = "Conduit",      desc = "give 3 en / steal 3",        cost = 1.0, element = .NEUTRAL, targets = {.ALLY, .ENEMY}, rarity = .UNCOMMON, energy_give = 3, energy_drain = 3},
	.Ward         = {name = "Ward",         desc = "8 block to a friend",        cost = 1.0, element = .NEUTRAL, targets = {.ALLY, .SELF}, rarity = .COMMON, block = 8},
	// Stat-scaling attacks: the caster's own block / defense feeds the damage.
	.Shield_Bash  = {name = "Shield Bash",  desc = "dmg = your block",           cost = 1.0, element = .NEUTRAL, rarity = .UNCOMMON, damage = 0, hits = 1, scale_block = 1.0},
	.Iron_Slam    = {name = "Iron Slam",    desc = "3 dmg + 2x def",             cost = 1.5, element = .NEUTRAL, rarity = .UNCOMMON, damage = 3, hits = 1, scale_defense = 2.0},
	.Vital_Strike = {name = "Vital Strike", desc = "4 dmg +10% max hp",          cost = 1.5, element = .NEUTRAL, rarity = .UNCOMMON, damage = 4, hits = 1, scale_max_hp = 0.10},
	.Last_Stand   = {name = "Last Stand",   desc = "2 dmg, more if hurt",        cost = 1.0, element = .NEUTRAL, rarity = .UNCOMMON, damage = 2, hits = 1, scale_missing_hp = 0.20},
	// Multiplier form: the whole hit is scaled by how hurt the caster is.
	.Reckoning    = {name = "Reckoning",    desc = "6 dmg, up to x2",            cost = 1.5, element = .NEUTRAL, rarity = .UNCOMMON, damage = 6, hits = 1, mult_missing_hp = 1.0},
	// Haze: wipe every battle modifier off a creature (any target).
	.Haze         = {name = "Haze",         desc = "clear all boosts",           cost = 1.0, element = .ICE, rarity = .UNCOMMON, targets = {.ENEMY, .SELF, .ALLY}, clear_boosts = true},
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
