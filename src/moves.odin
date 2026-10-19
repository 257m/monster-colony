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
	Guard,
	Ember_Strike,
	Aqua_Jet,
	Vine_Whip,
	Snowball,
	Sand_Attack,
	Zap,
	Gust,
	Sting,
	Haze,
	// Powers (played once, then the effect lasts the fight)
	Barricade,
	Juggernaut,
	Demon_Form,
	// Pool
	Hone,
	Mark,
	Overwhelm,
	Fang_Flurry,
	Sanguine,
	Fortify,
	Shield_Bash,
	Body_Press,
	Envenom,
	Blade_Dance,
	Shiv,
	// Speed, doublers, junk
	Agility,
	Dragon_Dance,
	Catalyst,
	Entrench,
	Amplify,
	Finale,
	Sabotage,
	Dazed,
	Wound,
	// Pool wave 2 — elemental attacks, utility, teamwork, risk/payoff, powers.
	Slash,
	Flame_Burst,
	Aqua_Cutter,
	Leech,
	Frost_Bite,
	Rock_Throw,
	Cyclone,
	Venom,
	Thunderbolt,
	Meteor,
	Insight,
	Study,
	Iron_Skin,
	Barrier,
	Bramble_Armor,
	Spike_Shell,
	Expose,
	Channel,
	Siphon,
	Rally,
	Blood_Pact,
	Reckoning,
	Cull,
	Concuss,
	Rage,
	// Pool wave 3 — X-cost, retain, ethereal, hand manipulation, energy, powers.
	All_In,
	Bulwark,
	Hold_the_Line,
	Meditate,
	Fuse,
	Ember_Coil,
	Gambit,
	Purge,
	Adrenaline,
	Overclock,
	Blackout,
	Combustion,
	Toxic,
	Bastion,
	Bash,
	Rampart,
	Followup,
	Warcry,
	Cleave,
	Sunder,
	Footwork,
	Flow,
	Depower,
	Disarm,
	// Boss signature moves.
	Maelstrom,
	Hellfire,
	Cataclysm,
	Decree,
	Devour,
	Antidote,
	Purify,
	// Reward-only utility cards.
	Dazzle,
	Metronome,
	Scavenger,
	Slime_Spit,
	// Elemental top-ups: Electric, Flora, Ice and Air were thin on cards.
	Jolt,
	Static_Shock,
	Overcharge,
	Short_Circuit,
	Chain_Lightning,
	Capacitor,
	Thorn_Volley,
	Photosynthesis,
	Frost_Nova,
	Ice_Wall,
	Updraft,
	Tailwind,
	// Aqua top-up + a premium attack for every element.
	Riptide,
	Firestorm,
	Tidal_Crash,
	Bramble_Crush,
	Avalanche,
	Fault_Line,
	Supercell,
	Gale_Force,
	Venom_Fang,
	Earthquake,
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

// Where a card puts any cards it creates. HAND/DRAW/DISCARD last for this battle;
// DECK is permanent (it's the saved deck).
Add_Where :: enum { HAND, DRAW, DISCARD, DECK }

// StS-style card classification. Descriptive: the UI shows it, and rules like
// "exhaust all Attacks" or "when you play a Skill" can key off it.
Card_Kind :: enum { ATTACK, SKILL, POWER }

card_kind_name :: proc(k: Card_Kind) -> cstring {
	switch k {
	case .ATTACK: return "Attack"
	case .SKILL:  return "Skill"
	case .POWER:  return "Power"
	}
	return "?"
}

card_kind_color :: proc(k: Card_Kind) -> rl.Color {
	switch k {
	case .ATTACK: return rl.Color{226, 96, 72, 255}
	case .SKILL:  return rl.Color{96, 150, 226, 255}
	case .POWER:  return rl.Color{176, 120, 226, 255}
	}
	return rl.Color{158, 158, 172, 255}
}

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
	dexterity:  int, // grant Dexterity: adds to every Block gain
	speed:      f32, // grant Speed for initiative
	heal_pct:   f32, // heal = this fraction of the caster's max HP
	leech_pct:  f32, // heal = this fraction of the damage the card dealt
	draw:       int,

	// Debuffs applied to the target
	strength_down:  int,
	dexterity_down: int,
	defense_down:   f32,

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
	scale_per_exhausted: int, // + this damage per card exhausted this battle
	// Doublers: the Balatro-style "double X" effects (usually high cost).
	double_block:    bool,
	double_strength: bool,
	double_poison:   bool,
	double_burn:     bool,
	// Offense: which creature stat it attacks with.
	offense_stat: Offense_Stat,

	// Utility
	clear_boosts:  bool, // wipe every battle *stat* modifier on the target (Haze)
	cleanse_status: bool, // remove Poison / Burn / Stun from the beneficiary
	aoe:           bool, // hits every foe at once instead of the chosen target

	// Classification + powers
	kind:         Card_Kind, // ATTACK (default), SKILL, or POWER
	grant_power:  Power,     // POWER cards: the effect they grant
	power_stacks: int,       // how many stacks of it

	// Deck interaction
	exhaust:   bool,      // spent for the rest of the battle instead of discarded
	add_move:  Move_Id,   // a card this one creates
	add_count: int,       // copies to create (0 = none)
	add_where: Add_Where, // where they go (DECK = permanent)
	unplayable:    bool,  // can't be played; just clogs a hand (Wound)
	add_to_target: bool,  // created cards go to the target's piles, not the caster's
	hand_damage:   int,   // if this card is still in hand at end of turn, its holder takes this
	energy_burn:   int,   // strip this much energy from the target (no gain, unlike drain)

	// Cost / hand behaviour
	x_cost:       bool, // spends ALL the caster's energy; damage & block scale per energy
	retain:       bool, // stays in hand at the end of the round instead of discarding
	ethereal:     bool, // exhausts at the end of the round if still in hand
	discard_hand: bool, // discard the rest of your hand
	exhaust_hand: bool, // exhaust the rest of your hand

	// Self-costs (paid by the caster whatever the target)
	self_strength_down: int,
	self_defense_down:  f32,
	self_damage:        int,
}

MOVE_DATA := [Move_Id]Move{
	.Tackle       = {name = "Tackle",       desc = "5 dmg",                     cost = 1.0, element = .NEUTRAL, damage = 5, hits = 1},
	.Guard        = {name = "Guard",        desc = "5 block",                   cost = 1.0, element = .NEUTRAL, kind = .SKILL, targets = {.SELF}, block = 5},
	.Ember_Strike = {name = "Ember Strike", desc = "5 dmg",                     cost = 1.0, element = .EMBER, damage = 5, hits = 1},
	.Aqua_Jet     = {name = "Aqua Jet",     desc = "5 dmg",                     cost = 1.0, element = .AQUA, damage = 5, hits = 1},
	.Vine_Whip    = {name = "Vine Whip",    desc = "5 dmg",                     cost = 1.0, element = .FLORA, damage = 5, hits = 1},
	.Snowball     = {name = "Snowball",     desc = "5 dmg",                     cost = 1.0, element = .ICE, damage = 5, hits = 1},
	.Sand_Attack  = {name = "Sand Attack",  desc = "5 dmg",                     cost = 1.0, element = .GROUND, damage = 5, hits = 1},
	.Zap          = {name = "Zap",          desc = "5 dmg",                     cost = 1.0, element = .ELECTRIC, damage = 5, hits = 1},
	.Gust         = {name = "Gust",         desc = "5 dmg",                     cost = 1.0, element = .AIR, damage = 5, hits = 1},
	.Sting        = {name = "Sting",       desc = "5 dmg",                     cost = 1.0, element = .POISON, damage = 5, hits = 1},
	.Haze         = {name = "Haze",         desc = "clear all boosts",          cost = 1.0, element = .ICE, rarity = .UNCOMMON, targets = {.ENEMY, .SELF, .ALLY}, clear_boosts = true},
	// Powers: played once, exhaust, and their effect lasts the rest of the fight.
	.Barricade    = {name = "Barricade",    desc = "block persists",            cost = 3.0, element = .NEUTRAL, rarity = .RARE, kind = .POWER, targets = {.SELF}, grant_power = .Barricade, power_stacks = 1, exhaust = true},
	.Juggernaut   = {name = "Juggernaut",   desc = "block -> damage",           cost = 2.0, element = .NEUTRAL, rarity = .RARE, kind = .POWER, targets = {.SELF}, grant_power = .Juggernaut, power_stacks = 1, exhaust = true},
	.Demon_Form   = {name = "Demon Form",   desc = "+2 str each turn",          cost = 3.0, element = .NEUTRAL, rarity = .RARE, kind = .POWER, targets = {.SELF}, grant_power = .Demon_Form, power_stacks = 1, exhaust = true},

	// ------------------------------------------------------------------------
	// Pool — a spread of archetypes. Everything here uses existing mechanics.
	// ------------------------------------------------------------------------
	// Strength engine: Strength is a flat +10% damage multiplier per point, so
	// stacking it multiplies *everything*.
	.Hone         = {name = "Hone",         desc = "+5 str",                    cost = 1.0, element = .NEUTRAL, rarity = .COMMON,   kind = .SKILL, targets = {.SELF}, strength = 5},
	// Vulnerable setup -> Overwhelm payoff.
	.Mark         = {name = "Mark",         desc = "vuln 3 turns",              cost = 0.5, element = .NEUTRAL, rarity = .COMMON,   kind = .SKILL, vulnerable = 3},
	.Overwhelm    = {name = "Overwhelm",    desc = "8 dmg, +8 vs vuln",         cost = 2.0, element = .NEUTRAL, rarity = .UNCOMMON, damage = 8, hits = 1, vuln_bonus = 8},
	// Multi-hit: each hit rolls lifesteal / on-hit powers separately.
	.Fang_Flurry  = {name = "Fang Flurry",  desc = "3 dmg x3",                  cost = 1.5, element = .NEUTRAL, rarity = .UNCOMMON, damage = 3, hits = 3},
	// Powers the multi-hit build (Sanguine heals per hit).
	.Sanguine     = {name = "Sanguine",     desc = "heal 2 per hit",            cost = 2.0, element = .NEUTRAL, rarity = .RARE, kind = .POWER, targets = {.SELF}, grant_power = .Sanguine, power_stacks = 1, exhaust = true},
	// Block / defense engine: build the stat, then swing with it.
	.Fortify      = {name = "Fortify",      desc = "12 block",                  cost = 1.5, element = .NEUTRAL, rarity = .COMMON,   kind = .SKILL, targets = {.SELF}, block = 12},
	.Shield_Bash  = {name = "Shield Bash",  desc = "dmg = block",               cost = 1.0, element = .GROUND,  rarity = .UNCOMMON, damage = 0, hits = 1, scale_block = 1.0},
	.Body_Press   = {name = "Body Press",   desc = "6 dmg, uses def",           cost = 1.5, element = .GROUND,  rarity = .UNCOMMON, damage = 6, hits = 1, offense_stat = .DEFENSE},
	// Poison engine: DoT is a % of max HP, so it scales on its own.
	.Envenom      = {name = "Envenom",      desc = "4 dmg, 2 poison",           cost = 1.0, element = .POISON,  rarity = .UNCOMMON, damage = 4, hits = 1, poison = 2},
	// Deck engine: make cards, then exhaust them for value.
	.Blade_Dance  = {name = "Blade Dance",  desc = "add 3 Shiv",                cost = 1.0, element = .NEUTRAL, rarity = .UNCOMMON, kind = .SKILL, targets = {.SELF}, add_move = .Shiv, add_count = 3, add_where = .HAND},
	.Shiv         = {name = "Shiv",         desc = "2 dmg, exhaust",            cost = 0.0, element = .NEUTRAL, rarity = .COMMON,   damage = 4, hits = 1, exhaust = true},

	// Speed, doublers and junk. Doublers are deliberately expensive — they're the
	// "the build came together" payoffs.
	.Agility      = {name = "Agility",      desc = "+3 speed",                  cost = 0.5, element = .AIR,     rarity = .COMMON,   kind = .SKILL, targets = {.SELF}, speed = 3},
	.Dragon_Dance = {name = "Dragon Dance", desc = "+2 str, +2 speed",          cost = 1.5, element = .NEUTRAL, rarity = .UNCOMMON, kind = .SKILL, targets = {.SELF}, strength = 2, speed = 2},
	.Catalyst     = {name = "Catalyst",     desc = "double poison",             cost = 2.0, element = .POISON,  rarity = .RARE,     kind = .SKILL, double_poison = true},
	.Entrench     = {name = "Entrench",     desc = "double block",              cost = 2.0, element = .GROUND,  rarity = .RARE,     kind = .SKILL, targets = {.SELF}, double_block = true},
	.Amplify      = {name = "Amplify",      desc = "double strength",           cost = 3.0, element = .NEUTRAL, rarity = .RARE,     kind = .SKILL, targets = {.SELF}, double_strength = true},
	.Finale       = {name = "Finale",       desc = "+4 per exhausted",          cost = 2.5, element = .NEUTRAL, rarity = .RARE,     damage = 2, hits = 1, scale_per_exhausted = 4},
	.Sabotage     = {name = "Sabotage",     desc = "add 2 Wound to foe",        cost = 1.0, element = .POISON,  rarity = .UNCOMMON, kind = .SKILL, add_move = .Wound, add_count = 2, add_where = .HAND, add_to_target = true},
	.Dazed        = {name = "Dazed",        desc = "1 en: nothing",              cost = 1.0, element = .NEUTRAL, rarity = .COMMON,   kind = .SKILL, exhaust = true},
	.Wound        = {name = "Wound",        desc = "unplayable, 3 dmg",          cost = 0.0, element = .NEUTRAL, rarity = .COMMON,   kind = .SKILL, unplayable = true, hand_damage = 3},

	// ------------------------------------------------------------------------
	// Pool wave 2.
	// ------------------------------------------------------------------------
	// Elemental attacks. A move whose element matches the monster's gets STAB
	// (x1.5), and hitting a weakness is x2 — so a mono-type monster wants its own
	// element's attacks, and a dual-type can cover two.
	.Slash        = {name = "Slash",        desc = "7 dmg",                     cost = 1.0, element = .NEUTRAL,  rarity = .COMMON,   damage = 7, hits = 1},
	.Flame_Burst  = {name = "Flame Burst",  desc = "6 dmg, 2 burn",             cost = 1.5, element = .EMBER,    rarity = .UNCOMMON, damage = 6, hits = 1, burn = 2},
	.Aqua_Cutter  = {name = "Aqua Cutter",  desc = "5 dmg, draw 1",             cost = 1.0, element = .AQUA,     rarity = .COMMON,   damage = 5, hits = 1, draw = 1},
	.Leech        = {name = "Leech",        desc = "4 dmg, drain",              cost = 1.0, element = .FLORA,    rarity = .UNCOMMON, damage = 4, hits = 1, leech_pct = 0.5},
	.Frost_Bite   = {name = "Frost Bite",   desc = "5 dmg, 2 vuln",             cost = 1.0, element = .ICE,      rarity = .UNCOMMON, damage = 5, hits = 1, vulnerable = 2},
	.Rock_Throw   = {name = "Rock Throw",   desc = "6 dmg, -1 def",             cost = 1.0, element = .GROUND,   rarity = .COMMON,   damage = 6, hits = 1, defense_down = 1},
	.Cyclone      = {name = "Cyclone",      desc = "3 dmg x3",                  cost = 1.5, element = .AIR,      rarity = .UNCOMMON, damage = 3, hits = 3},
	.Venom        = {name = "Venom",        desc = "3 dmg, 3 poison",           cost = 1.0, element = .POISON,   rarity = .UNCOMMON, damage = 3, hits = 1, poison = 3},
	.Thunderbolt  = {name = "Thunderbolt",  desc = "12 dmg",                    cost = 2.0, element = .ELECTRIC, rarity = .UNCOMMON, damage = 12, hits = 1},
	.Meteor       = {name = "Meteor",       desc = "18 dmg",                    cost = 3.0, element = .EMBER,    rarity = .RARE,     damage = 18, hits = 1},
	// Utility.
	.Insight      = {name = "Insight",      desc = "draw 2",                    cost = 0.5, element = .NEUTRAL,  rarity = .COMMON,   kind = .SKILL, targets = {.SELF}, draw = 2},
	.Study        = {name = "Study",        desc = "draw 3, exhaust",           cost = 1.0, element = .NEUTRAL,  rarity = .UNCOMMON, kind = .SKILL, targets = {.SELF}, draw = 3, exhaust = true},
	.Iron_Skin    = {name = "Iron Skin",    desc = "+3 def",                    cost = 1.0, element = .NEUTRAL,  rarity = .COMMON,   kind = .SKILL, targets = {.SELF}, defense = 3},
	.Barrier      = {name = "Barrier",      desc = "18 block",                  cost = 2.0, element = .NEUTRAL,  rarity = .UNCOMMON, kind = .SKILL, targets = {.SELF}, block = 18},
	.Bramble_Armor = {name = "Bramble Armor", desc = "thorns 3",                cost = 1.0, element = .FLORA,    rarity = .UNCOMMON, kind = .SKILL, targets = {.SELF}, thorns = 3},
	.Spike_Shell  = {name = "Spike Shell",  desc = "thorns 2, 6 block",         cost = 1.5, element = .NEUTRAL,  rarity = .RARE,     kind = .SKILL, targets = {.SELF}, thorns = 2, block = 6},
	// Setup: Vulnerable + defense shred, the classic "make the big hit land".
	.Expose       = {name = "Expose",       desc = "2 vuln, -2 def",            cost = 1.0, element = .NEUTRAL,  rarity = .UNCOMMON, kind = .SKILL, vulnerable = 2, defense_down = 2},
	// Energy / teamwork.
	.Channel      = {name = "Channel",      desc = "ally +3 energy",            cost = 0.5, element = .NEUTRAL,  rarity = .COMMON,   kind = .SKILL, targets = {.ALLY}, energy_give = 3},
	.Siphon       = {name = "Siphon",       desc = "3 dmg, steal 3 en",         cost = 1.0, element = .NEUTRAL,  rarity = .UNCOMMON, damage = 3, hits = 1, energy_drain = 3},
	.Rally        = {name = "Rally",        desc = "ally +2 str",               cost = 1.5, element = .NEUTRAL,  rarity = .UNCOMMON, kind = .SKILL, targets = {.ALLY}, strength = 2},
	// Risk / payoff.
	.Blood_Pact   = {name = "Blood Pact",   desc = "-6 hp, +3 str",             cost = 0.0, element = .NEUTRAL,  rarity = .UNCOMMON, kind = .SKILL, targets = {.SELF}, strength = 3, self_damage = 6},
	.Reckoning    = {name = "Reckoning",    desc = "6 dmg, up to x2",           cost = 1.5, element = .NEUTRAL,  rarity = .UNCOMMON, damage = 6, hits = 1, mult_missing_hp = 1.0},
	.Cull         = {name = "Cull",         desc = "6 dmg, +10 low hp",         cost = 1.5, element = .NEUTRAL,  rarity = .UNCOMMON, damage = 6, hits = 1, execute_bonus = 10, execute_pct = 0.4},
	.Concuss      = {name = "Concuss",      desc = "4 dmg, stun 1",             cost = 1.5, element = .NEUTRAL,  rarity = .UNCOMMON, damage = 4, hits = 1, stun = 1},
	// Power.
	.Rage         = {name = "Rage",         desc = "attacks: +3 block",         cost = 1.5, element = .NEUTRAL,  rarity = .RARE, kind = .POWER, targets = {.SELF}, grant_power = .Rage, power_stacks = 1, exhaust = true},

	// ------------------------------------------------------------------------
	// Pool wave 3 — decision-dense mechanics.
	// ------------------------------------------------------------------------
	// X-cost: spends the whole energy bank; damage/block are PER ENERGY. Trades
	// the turn (and map movement) for one big swing.
	.All_In       = {name = "All-In",       desc = "10 dmg x energy",           cost = 0.0, element = .NEUTRAL, rarity = .RARE, x_cost = true, damage = 10, hits = 1, exhaust = true},
	.Bulwark      = {name = "Bulwark",      desc = "8 block x energy",          cost = 0.0, element = .NEUTRAL, rarity = .RARE, x_cost = true, kind = .SKILL, targets = {.SELF}, block = 8},
	// Retain: stays in hand so you can replay it next turn.
	.Hold_the_Line = {name = "Hold the Line", desc = "8 block, retain",         cost = 1.0, element = .NEUTRAL, rarity = .UNCOMMON, kind = .SKILL, targets = {.SELF}, block = 8, retain = true},
	.Meditate     = {name = "Meditate",     desc = "+1 en, draw 1, retain",     cost = 0.5, element = .NEUTRAL, rarity = .COMMON, kind = .SKILL, targets = {.SELF}, energy_give = 1, draw = 1, retain = true},
	// Ethereal: use it this turn or it's gone.
	.Fuse         = {name = "Fuse",         desc = "14 dmg, ethereal",          cost = 1.0, element = .NEUTRAL, rarity = .UNCOMMON, damage = 14, hits = 1, ethereal = true},
	.Ember_Coil   = {name = "Ember Coil",   desc = "6 dmg, 3 burn, ethereal",   cost = 1.0, element = .EMBER,   rarity = .UNCOMMON, damage = 6, hits = 1, burn = 3, ethereal = true},
	// Hand manipulation.
	.Gambit       = {name = "Gambit",       desc = "discard, draw +4",          cost = 0.0, element = .NEUTRAL, rarity = .UNCOMMON, kind = .SKILL, discard_hand = true, draw = 4, exhaust = true},
	.Purge        = {name = "Purge",        desc = "exhaust your hand",         cost = 1.0, element = .NEUTRAL, rarity = .UNCOMMON, kind = .SKILL, exhaust_hand = true, exhaust = true},
	// Energy — to yourself.
	.Adrenaline   = {name = "Adrenaline",   desc = "+2 energy",                 cost = 0.0, element = .NEUTRAL, rarity = .UNCOMMON, kind = .SKILL, targets = {.SELF}, energy_give = 2, exhaust = true},
	.Overclock    = {name = "Overclock",    desc = "+3 en, -5 hp",              cost = 0.5, element = .NEUTRAL, rarity = .UNCOMMON, kind = .SKILL, targets = {.SELF}, energy_give = 3, self_damage = 5},
	// Energy sabotage: strips the foe's energy without gaining it.
	.Blackout     = {name = "Blackout",     desc = "foe -3 energy",             cost = 1.0, element = .NEUTRAL, rarity = .UNCOMMON, kind = .SKILL, energy_burn = 3},
	// More powers.
	.Combustion   = {name = "Combustion",   desc = "burn all foes",             cost = 2.0, element = .EMBER,   rarity = .RARE, kind = .POWER, targets = {.SELF}, grant_power = .Combustion, power_stacks = 1, exhaust = true},
	.Toxic        = {name = "Toxic",        desc = "your hits poison",          cost = 2.0, element = .POISON,  rarity = .RARE, kind = .POWER, targets = {.SELF}, grant_power = .Toxic, power_stacks = 1, exhaust = true},
	.Bastion      = {name = "Bastion",      desc = "+4 block/turn",             cost = 2.0, element = .GROUND,  rarity = .RARE, kind = .POWER, targets = {.SELF}, grant_power = .Bastion, power_stacks = 1, exhaust = true},
	// Bread and butter.
	.Bash         = {name = "Bash",         desc = "10 dmg, 2 vuln",            cost = 2.0, element = .NEUTRAL,  rarity = .UNCOMMON, damage = 10, hits = 1, vulnerable = 2},
	.Rampart      = {name = "Rampart",      desc = "10 block",                  cost = 1.0, element = .NEUTRAL,  rarity = .COMMON,   kind = .SKILL, targets = {.SELF}, block = 10},
	.Followup     = {name = "Followup",     desc = "5 dmg, +5 combo",           cost = 1.0, element = .NEUTRAL,  rarity = .COMMON,   damage = 5, hits = 1, combo_bonus = 5},
	.Warcry       = {name = "Warcry",       desc = "+2 str, draw 1",            cost = 0.5, element = .NEUTRAL,  rarity = .COMMON,   kind = .SKILL, targets = {.SELF}, strength = 2, draw = 1},
	.Cleave       = {name = "Cleave",       desc = "9 dmg",                     cost = 1.5, element = .NEUTRAL,  rarity = .COMMON,   damage = 9, hits = 1},
	.Sunder       = {name = "Sunder",       desc = "4 dmg, -3 def",             cost = 1.0, element = .GROUND,   rarity = .UNCOMMON, damage = 4, hits = 1, defense_down = 3},
	// Dexterity: flat Block added to every Block gain (StS-style).
	.Footwork     = {name = "Footwork",     desc = "+2 dexterity",              cost = 1.0, element = .NEUTRAL,  rarity = .UNCOMMON, kind = .SKILL, targets = {.SELF}, dexterity = 2},
	.Flow         = {name = "Flow",         desc = "+1 dex/turn",               cost = 3.0, element = .AQUA,     rarity = .RARE, kind = .POWER, targets = {.SELF}, grant_power = .Flow, power_stacks = 1, exhaust = true},
	// Strip a foe's buffs. Haze wipes everything; these are surgical.
	.Depower      = {name = "Depower",      desc = "-2 str, -2 dex",            cost = 1.0, element = .NEUTRAL,  rarity = .UNCOMMON, kind = .SKILL, strength_down = 2, dexterity_down = 2},
	.Disarm       = {name = "Disarm",       desc = "-3 dexterity",              cost = 1.0, element = .GROUND,   rarity = .UNCOMMON, kind = .SKILL, dexterity_down = 3},

	// ------------------------------------------------------------------------
	// Boss signatures — one per boss, each built around its own ability.
	// ------------------------------------------------------------------------
	// Leviathan (Abyssal): multi-hit + heavy lifesteal, so it out-sustains you.
	.Maelstrom    = {name = "Maelstrom",    desc = "6 dmg x3, drain",            cost = 3.0, element = .AQUA,     rarity = .RARE, damage = 6, hits = 3, leech_pct = 0.5},
	// Infernal (Inferno): doubles the Burn it has already piled on.
	.Hellfire     = {name = "Hellfire",     desc = "8 dmg, burn x2",             cost = 3.0, element = .EMBER,    rarity = .RARE, damage = 8, hits = 1, burn = 4, double_burn = true},
	// Titan (Colossus): keeps Block forever, then swings with it.
	.Cataclysm    = {name = "Cataclysm",    desc = "dmg = block + 12",          cost = 3.0, element = .GROUND,   rarity = .RARE, damage = 0, hits = 1, scale_block = 1.0, block = 12},
	// Sovereign (Dominion): hits and strips every buff the target has.
	.Decree       = {name = "Decree",       desc = "12 dmg, dispel",            cost = 3.0, element = .NEUTRAL,  rarity = .RARE, damage = 12, hits = 1, clear_boosts = true},
	// Deep One (no signature element): it simply eats you.
	.Devour       = {name = "Devour",       desc = "12 dmg, devour",            cost = 3.0, element = .NEUTRAL,  rarity = .RARE, damage = 12, hits = 1, leech_pct = 0.6, heal_pct = 0.08},
	// Status healing (distinct from Haze, which only touches stats).
	.Antidote     = {name = "Antidote",     desc = "cleanse self/ally",         cost = 0.5, element = .NEUTRAL,  rarity = .COMMON,   kind = .SKILL, targets = {.SELF, .ALLY}, cleanse_status = true},
	.Purify       = {name = "Purify",       desc = "cleanse an ally",           cost = 1.0, element = .NEUTRAL,  rarity = .UNCOMMON, kind = .SKILL, targets = {.ALLY}, cleanse_status = true, heal_pct = 0.08},
	// Reward-only utility cards (no learnset grants them; they come from
	// `move_pool` rewards).
	.Dazzle       = {name = "Dazzle",       desc = "1 stun, add 2 Dazed",       cost = 1.5, element = .NEUTRAL,  rarity = .UNCOMMON, kind = .SKILL, stun = 1, add_move = .Dazed, add_count = 2, add_where = .HAND, add_to_target = true},
	.Metronome    = {name = "Metronome",    desc = "+1 STR at 3 cards",        cost = 2.0, element = .NEUTRAL,  rarity = .RARE,     kind = .POWER, targets = {.SELF}, grant_power = .Metronome, power_stacks = 1, exhaust = true},
	.Scavenger    = {name = "Scavenger",    desc = "draw on exhaust",           cost = 2.0, element = .NEUTRAL,  rarity = .UNCOMMON, kind = .POWER, targets = {.SELF}, grant_power = .Scavenger, power_stacks = 1, exhaust = true},
	.Slime_Spit   = {name = "Slime Spit",   desc = "5 dmg, 2 Dazed",            cost = 1.5, element = .POISON,   rarity = .UNCOMMON, damage = 5, hits = 1, add_move = .Dazed, add_count = 2, add_where = .HAND, add_to_target = true},
	// Elemental top-ups.
	.Jolt            = {name = "Jolt",            desc = "3 dmg",                 cost = 0.5, element = .ELECTRIC, rarity = .COMMON,   damage = 3, hits = 1},
	.Static_Shock    = {name = "Static Shock",    desc = "5 dmg, 1 stun",         cost = 1.5, element = .ELECTRIC, rarity = .UNCOMMON, damage = 5, hits = 1, stun = 1},
	.Overcharge      = {name = "Overcharge",      desc = "10 dmg x energy",       cost = 0.0, element = .ELECTRIC, rarity = .RARE,     x_cost = true, damage = 10, hits = 1, exhaust = true},
	.Short_Circuit   = {name = "Short Circuit",   desc = "4 dmg, burn 2 energy",  cost = 1.0, element = .ELECTRIC, rarity = .UNCOMMON, damage = 4, hits = 1, energy_burn = 2},
	.Chain_Lightning = {name = "Chain Lightning", desc = "4 dmg x3",             cost = 2.0, element = .ELECTRIC, rarity = .RARE,     damage = 4, hits = 3},
	.Capacitor       = {name = "Capacitor",       desc = "+3 en, draw 1",         cost = 1.0, element = .ELECTRIC, rarity = .UNCOMMON, kind = .SKILL, targets = {.SELF}, energy_give = 3, draw = 1},
	.Thorn_Volley    = {name = "Thorn Volley",    desc = "4 dmg x2, +1 thorns",   cost = 1.5, element = .FLORA,    rarity = .UNCOMMON, damage = 4, hits = 2, thorns = 1},
	.Photosynthesis  = {name = "Photosynthesis",  desc = "+2 regen, draw 1",      cost = 1.0, element = .FLORA,    rarity = .UNCOMMON, kind = .SKILL, targets = {.SELF}, regen = 2, draw = 1},
	.Frost_Nova      = {name = "Frost Nova",      desc = "8 dmg, 2 vuln",         cost = 1.5, element = .ICE,      rarity = .UNCOMMON, damage = 8, hits = 1, vulnerable = 2},
	.Ice_Wall        = {name = "Ice Wall",        desc = "8 block, +1 thorns",    cost = 1.0, element = .ICE,      rarity = .UNCOMMON, kind = .SKILL, targets = {.SELF}, block = 8, thorns = 1},
	.Updraft         = {name = "Updraft",         desc = "5 block, +2 speed",     cost = 1.0, element = .AIR,      rarity = .COMMON,   kind = .SKILL, targets = {.SELF}, block = 5, speed = 2},
	.Tailwind        = {name = "Tailwind",        desc = "draw 2, +2 speed",      cost = 1.0, element = .AIR,      rarity = .UNCOMMON, kind = .SKILL, targets = {.SELF}, draw = 2, speed = 2},
	// Premium attacks: every element gets one heavy hitter at the 6-damage-per-
	// energy rate, with a twist that matches its identity.
	.Riptide         = {name = "Riptide",         desc = "4 dmg x2, drain",       cost = 1.5, element = .AQUA,     rarity = .UNCOMMON, damage = 4, hits = 2, leech_pct = 0.3},
	.Firestorm       = {name = "Firestorm",       desc = "15 dmg, 3 burn",        cost = 3.0, element = .EMBER,    rarity = .RARE,     damage = 15, hits = 1, burn = 3},
	.Tidal_Crash     = {name = "Tidal Crash",     desc = "18 dmg",                cost = 3.0, element = .AQUA,     rarity = .RARE,     damage = 18, hits = 1},
	.Bramble_Crush   = {name = "Bramble Crush",   desc = "16 dmg, +2 thorns",     cost = 3.0, element = .FLORA,    rarity = .RARE,     damage = 16, hits = 1, thorns = 2},
	.Avalanche       = {name = "Avalanche",       desc = "15 dmg, 3 vuln",        cost = 3.0, element = .ICE,      rarity = .RARE,     damage = 15, hits = 1, vulnerable = 3},
	.Fault_Line      = {name = "Fault Line",      desc = "16 dmg, -3 def",        cost = 3.0, element = .GROUND,   rarity = .RARE,     damage = 16, hits = 1, defense_down = 3},
	.Supercell       = {name = "Supercell",       desc = "15 dmg, 1 stun",        cost = 3.0, element = .ELECTRIC, rarity = .RARE,     damage = 15, hits = 1, stun = 1},
	.Gale_Force      = {name = "Gale Force",      desc = "6 dmg x3",              cost = 3.0, element = .AIR,      rarity = .RARE,     damage = 6, hits = 3},
	.Venom_Fang      = {name = "Venom Fang",      desc = "12 dmg, 4 poison",      cost = 3.0, element = .POISON,   rarity = .RARE,     damage = 12, hits = 1, poison = 4},
	// AoE: hits every foe at once.
	.Earthquake      = {name = "Earthquake",      desc = "12 dmg to all foes",   cost = 3.0, element = .GROUND,   rarity = .RARE,     damage = 12, hits = 1, aoe = true},
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
	if m.aoe {
		return "every foe"
	}
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
		(m.offense_stat == .DEFENSE ? 6 : 0) + (m.clear_boosts ? 8 : 0) +
		m.add_count * (m.add_where == .DECK ? 6 : 4) + (m.grant_power != .NONE ? 12 * max(m.power_stacks, 1) : 0) +
		int(m.speed) * 4 + m.scale_per_exhausted * 3 + m.dexterity * 5 + m.dexterity_down * 4 +
		(m.double_block ? 10 : 0) + (m.double_strength ? 12 : 0) + (m.double_poison ? 10 : 0) + (m.double_burn ? 10 : 0) +
		(m.aoe ? 28 : 0) + (m.x_cost ? 6 : 0) + (m.retain ? 4 : 0) + (m.ethereal ? 2 : 0) + m.energy_burn * 4 +
		(m.discard_hand ? 6 : 0) + (m.exhaust_hand ? 4 : 0) + (m.cleanse_status ? 6 : 0) -
		(m.exhaust ? 4 : 0) -
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

// ----------------------------------------------------------------------------
// Move dex breakdown
//
// One clause per line, generated only from the fields a card actually sets, so
// the dex can explain a card without hand-written prose per move. Each line
// keeps its own buffer, so the whole block can be drawn in a single frame.
// ----------------------------------------------------------------------------
Move_Lines :: struct {
	bufs: [26][96]u8,
	n:    int,
}

move_lines :: proc(m: Move) -> Move_Lines {
	out: Move_Lines
	add := proc(o: ^Move_Lines, format: string, args: ..any) {
		if o.n >= len(o.bufs) {
			return
		}
		_ = fmt.bprintf(o.bufs[o.n][:], format, ..args)
		o.n += 1
	}

	if m.x_cost {
		add(&out, "Cost: all your energy (scales with what you spend)")
	} else {
		add(&out, "Cost: %s energy", fmt_num(m.cost))
	}
	add(&out, "Targets: %s", move_target_label(m))
	if m.aoe {
		add(&out, "Hits every foe at once")
	}
	add(&out, "Type: %s   Rarity: %s", card_kind_name(m.kind), card_rarity_name(m.rarity))

	if move_has_damage(m) {
		if max(m.hits, 1) > 1 {
			add(&out, "%d damage x%d hits", m.damage, max(m.hits, 1))
		} else {
			add(&out, "%d damage", m.damage)
		}
		if m.offense_stat == .DEFENSE {
			add(&out, "Attacks with Defense instead of Power")
		}
	}
	if m.block > 0 { add(&out, "+%d Block", m.block) }
	if m.double_block { add(&out, "Double the beneficiary's Block") }
	if m.vulnerable > 0 { add(&out, "+%d Vulnerable (turns)", m.vulnerable) }
	if m.strength > 0 { add(&out, "+%d Strength", m.strength) }
	if m.strength_down > 0 { add(&out, "-%d enemy Strength", m.strength_down) }
	if m.defense > 0 { add(&out, "+%s Defense", fmt_num(m.defense)) }
	if m.defense_down > 0 { add(&out, "-%s enemy Defense", fmt_num(m.defense_down)) }
	if m.dexterity > 0 { add(&out, "+%d Dexterity (+Block per card)", m.dexterity) }
	if m.dexterity_down > 0 { add(&out, "-%d enemy Dexterity", m.dexterity_down) }
	if m.speed > 0 { add(&out, "+%s Speed for initiative", fmt_num(m.speed)) }
	if m.double_strength { add(&out, "Double the beneficiary's Strength") }
	if m.heal_pct > 0 { add(&out, "Heal %d%% of max HP", int(m.heal_pct * 100)) }
	if m.leech_pct > 0 { add(&out, "Heal %d%% of damage dealt", int(m.leech_pct * 100)) }
	if m.regen > 0 { add(&out, "+%d Regen", m.regen) }
	if m.thorns > 0 { add(&out, "+%d Thorns", m.thorns) }
	if m.draw > 0 { add(&out, "Draw %d", m.draw) }
	if m.poison > 0 { add(&out, "+%d Poison", m.poison) }
	if m.double_poison { add(&out, "Double the target's Poison") }
	if m.burn > 0 { add(&out, "+%d Burn", m.burn) }
	if m.double_burn { add(&out, "Double the target's Burn") }
	if m.stun > 0 { add(&out, "+%d Stun", m.stun) }
	if m.vuln_bonus > 0 { add(&out, "+%d damage if the target is Vulnerable", m.vuln_bonus) }
	if m.block_bonus > 0 { add(&out, "+%d damage if you have Block", m.block_bonus) }
	if m.combo_bonus > 0 { add(&out, "+%d damage if you already played a card", m.combo_bonus) }
	if m.execute_bonus > 0 && m.execute_pct > 0 {
		add(&out, "+%d damage below %d%% HP", m.execute_bonus, int(m.execute_pct * 100))
	}
	if m.ally_bonus > 0 { add(&out, "+%d damage per other ally", m.ally_bonus) }
	if m.energy_give > 0 { add(&out, "+%d Energy to the beneficiary", m.energy_give) }
	if m.energy_drain > 0 { add(&out, "Drain %d Energy from the target", m.energy_drain) }
	if m.energy_burn > 0 { add(&out, "Burn %d of the target's Energy", m.energy_burn) }
	if m.scale_block > 0 { add(&out, "+ damage equal to %d%% of your Block", int(m.scale_block * 100)) }
	if m.scale_defense > 0 { add(&out, "+ damage equal to %d%% of your Defense", int(m.scale_defense * 100)) }
	if m.scale_max_hp > 0 { add(&out, "+ damage equal to %d%% of your max HP", int(m.scale_max_hp * 100)) }
	if m.scale_missing_hp > 0 { add(&out, "+ damage equal to %d%% of the HP you have lost", int(m.scale_missing_hp * 100)) }
	if m.mult_missing_hp > 0 { add(&out, "+%d%% damage per 100%% HP lost", int(m.mult_missing_hp * 100)) }
	if m.scale_per_exhausted > 0 { add(&out, "+%d damage per card exhausted", m.scale_per_exhausted) }
	if m.clear_boosts { add(&out, "Wipe the target's stat boosts and debuffs") }
	if m.cleanse_status { add(&out, "Cleanse Poison / Burn / Stun") }
	if m.grant_power != .NONE {
		add(&out, "Power: %s x%d (lasts the battle)", power_name(m.grant_power), max(m.power_stacks, 1))
	}
	if m.add_count > 0 {
		if m.add_to_target {
			add(&out, "Adds %d %s to the target's %s", m.add_count, MOVE_DATA[m.add_move].name, add_where_name(m.add_where))
		} else {
			add(&out, "Adds %d %s to your %s", m.add_count, MOVE_DATA[m.add_move].name, add_where_name(m.add_where))
		}
	}
	if m.unplayable { add(&out, "Unplayable - it only clogs a hand") }
	if m.hand_damage > 0 { add(&out, "%d damage if still in hand at end of turn", m.hand_damage) }
	if m.discard_hand { add(&out, "Discard the rest of your hand") }
	if m.exhaust_hand { add(&out, "Exhaust the rest of your hand") }
	if m.exhaust { add(&out, "Exhaust (gone for the rest of the battle)") }
	if m.retain { add(&out, "Retain (stays in hand between turns)") }
	if m.ethereal { add(&out, "Ethereal (exhausts if still in hand)") }
	if m.self_damage > 0 { add(&out, "You take %d damage", m.self_damage) }
	if m.self_strength_down > 0 { add(&out, "You lose %d Strength", m.self_strength_down) }
	if m.self_defense_down > 0 { add(&out, "You lose %s Defense", fmt_num(m.self_defense_down)) }
	return out
}

add_where_name :: proc(w: Add_Where) -> string {
	switch w {
	case .HAND:    return "hand"
	case .DRAW:    return "draw pile"
	case .DISCARD: return "discard pile"
	case .DECK:    return "deck (permanently)"
	}
	return "hand"
}
