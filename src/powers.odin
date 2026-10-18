package main

// ============================================================================
// POWERS
//
// Temporary per-battle effects granted by POWER cards. They stack, live on the
// creature for the rest of the fight, and are wiped when the battle ends.
// Abilities are their permanent cousins: a passive rolled from the species at
// spawn, kept for the creature's whole life.
//
// The hooks here are called from the battle code (`creature_begin_round`,
// `creature_end_round`, the damage loop, the exhaust path).
// ============================================================================

Power :: enum {
	NONE,
	Barricade,  // Block is not cleared at the end of the round
	Juggernaut, // gaining Block deals that much damage to a random foe
	Demon_Form, // +Strength at the start of each turn
	Metronome,  // +Strength on any turn you play 3+ cards
	Sanguine,   // heal per hit you land
	Scavenger,  // draw a card whenever a card exhausts
	Rage,       // gain Block whenever you play an Attack
	Combustion, // deal damage to every foe at the end of each turn
	Toxic,      // your Attacks apply Poison
	Bastion,    // gain Block at the start of each turn
	Flow,       // gain Dexterity at the start of each turn
}

POWER_DEMON_FORM_STR  :: 2
POWER_METRONOME_STR   :: 1
POWER_METRONOME_CARDS :: 3
POWER_SANGUINE_HEAL   :: 2
POWER_RAGE_BLOCK      :: 3
POWER_COMBUSTION_DMG  :: 3
POWER_TOXIC_POISON    :: 1
POWER_BASTION_BLOCK   :: 4
POWER_FLOW_DEX        :: 1

power_name :: proc(p: Power) -> cstring {
	switch p {
	case .NONE:       return "-"
	case .Barricade:  return "Barricade"
	case .Juggernaut: return "Juggernaut"
	case .Demon_Form: return "Demon Form"
	case .Metronome:  return "Metronome"
	case .Sanguine:   return "Sanguine"
	case .Scavenger:  return "Scavenger"
	case .Rage:       return "Rage"
	case .Combustion: return "Combustion"
	case .Toxic:      return "Toxic"
	case .Bastion:    return "Bastion"
	case .Flow:       return "Flow"
	}
	return "?"
}

power_desc :: proc(p: Power) -> cstring {
	switch p {
	case .NONE:       return "No power."
	case .Barricade:  return "Block is not cleared at the end of the round."
	case .Juggernaut: return "When you gain Block, deal that much damage to a random foe."
	case .Demon_Form: return "+2 Strength at the start of each turn."
	case .Metronome:  return "+1 Strength on any turn you play 3 or more cards."
	case .Sanguine:   return "Heal 2 per hit you land."
	case .Scavenger:  return "Draw a card whenever a card exhausts."
	case .Rage:       return "Gain 3 Block whenever you play an Attack."
	case .Combustion: return "Deal 3 damage to every foe at the end of each turn."
	case .Toxic:      return "Your Attacks apply 1 Poison per hit."
	case .Bastion:    return "Gain 4 Block at the start of each turn."
	case .Flow:       return "+1 Dexterity at the start of each turn."
	}
	return ""
}

// ----------------------------------------------------------------------------
// Hooks
// ----------------------------------------------------------------------------

// Start of a round (from `creature_begin_round`).
power_begin_round :: proc(b: ^Battle, c: ^Creature) {
	side := side_of(b, c)
	if n := c.powers[.Demon_Form]; n > 0 {
		gain := POWER_DEMON_FORM_STR * n
		c.strength += gain
		spawn_popup(b, side, .BUFF, gain)
		creature_burst(c, popup_color(.BUFF), 0.5)
		battle_sfx(.BUFF, 0.5)
	}
	if n := c.powers[.Bastion]; n > 0 {
		gain := POWER_BASTION_BLOCK * n
		c.block += gain
		spawn_popup(b, side, .BLOCK, gain)
		creature_burst(c, popup_color(.BLOCK), 0.5)
		battle_sfx(.BLOCK, 0.5)
	}
	if n := c.powers[.Flow]; n > 0 {
		gain := POWER_FLOW_DEX * n
		c.dexterity += gain
		spawn_popup(b, side, .DEFEND, gain)
		creature_burst(c, popup_color(.DEFEND), 0.55)
		battle_sfx(.BUFF, 0.5)
	}
}

// End of a round (from `creature_end_round`): Metronome and whether Block is
// kept (Barricade).
power_end_round :: proc(b: ^Battle, c: ^Creature) {
	if n := c.powers[.Metronome]; n > 0 && c.played >= POWER_METRONOME_CARDS {
		gain := POWER_METRONOME_STR * n
		c.strength += gain
		spawn_popup(b, side_of(b, c), .BUFF, gain)
		creature_burst(c, popup_color(.BUFF), 0.5)
		battle_sfx(.BUFF, 0.5)
	}
}

power_keeps_block :: proc(c: ^Creature) -> bool {
	return c.powers[.Barricade] > 0
}

// Heal per hit landed (Sanguine).
power_on_hit_heal :: proc(c: ^Creature) -> int {
	return POWER_SANGUINE_HEAL * c.powers[.Sanguine]
}

// Cards drawn when a card exhausts (Scavenger).
power_on_exhaust_draw :: proc(c: ^Creature) -> int {
	return c.powers[.Scavenger]
}

// Block gained when the creature plays an Attack (Rage).
power_rage_block :: proc(c: ^Creature) -> int {
	return POWER_RAGE_BLOCK * c.powers[.Rage]
}

// Poison applied by each hit (Toxic).
power_toxic_poison :: proc(c: ^Creature) -> int {
	return POWER_TOXIC_POISON * c.powers[.Toxic]
}
