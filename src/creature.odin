package main

import rl "vendor:raylib"

// ============================================================================
// SPECIES + CREATURES
//
// Each species has:
//   starter    - the deck it begins with
//   learnset   - moves learned automatically at specific levels (per-level)
//   move_pool  - every move it can ever learn; reward picks come only from
//                here. Moves in move_pool but not in learnset can ONLY be
//                obtained through rewards.
//
// Player party members and wild monsters are the same type, so rules are
// symmetric.
// ============================================================================

Species_Role :: enum { STARTER, WILD, ELITE, BOSS }

Learn_Entry :: struct {
	move:  Move_Id,
	level: int,
}

Species :: struct {
	name:         string,
	element:      Element,
	base_hp:      int,
	base_energy:  int, // energy generated per turn
	base_energy_max: int, // energy bank cap
	base_power:   int,
	base_defense: int,
	base_speed:   int,
	color:        rl.Color,
	role:         Species_Role,
	starter:      []Move_Id,
	learnset:     []Learn_Entry,
	move_pool:    []Move_Id,
}

// Neutral moves any creature can pick up as a reward but that no learnset
// grants — i.e. reward-only options.
COMMON_MOVES := []Move_Id{.Jab, .Brace, .Body_Slam, .Fortify, .Flurry, .Mend, .Insight, .Crush, .Iron_Skin}

SPECIES := [?]Species{
	// 0 - Emberling
	{
		name = "Emberling", element = .EMBER, base_hp = 60, base_energy = 3, base_energy_max = 4, base_power = 2, base_defense = 1, base_speed = 9,
		color = rl.Color{226, 110, 72, 255}, role = .STARTER,
		starter = []Move_Id{.Ember_Strike, .Ember_Strike, .Ember_Strike, .Ember_Strike, .Guard, .Guard, .Guard, .Flame_Burst, .Hone, .Screech},
		learnset = []Learn_Entry{
			{.Ember_Strike, 1}, {.Guard, 1}, {.Hone, 1}, {.Screech, 1},
			{.Flame_Burst, 2}, {.Cinder, 3}, {.Iron_Skin, 4}, {.Inferno, 5},
			{.Flurry, 6}, {.Insight, 6}, {.Mend, 7}, {.Fortify, 8}, {.Blaze, 9},
		},
		move_pool = []Move_Id{.Ember_Strike, .Flame_Burst, .Cinder, .Inferno, .Blaze, .Ash_Screen, .Guard, .Hone, .Screech, .Jab, .Brace, .Body_Slam, .Fortify, .Flurry, .Mend, .Insight, .Crush, .Iron_Skin},
	},
	// 1 - Tidepup
	{
		name = "Tidepup", element = .AQUA, base_hp = 62, base_energy = 3, base_energy_max = 4, base_power = 2, base_defense = 1, base_speed = 8,
		color = rl.Color{86, 150, 226, 255}, role = .STARTER,
		starter = []Move_Id{.Aqua_Jet, .Aqua_Jet, .Aqua_Jet, .Aqua_Jet, .Guard, .Guard, .Guard, .Tidal_Slam, .Hone, .Undertow},
		learnset = []Learn_Entry{
			{.Aqua_Jet, 1}, {.Guard, 1}, {.Hone, 1}, {.Undertow, 1},
			{.Tidal_Slam, 2}, {.Bubble_Shield, 3}, {.Heal_Spring, 4}, {.Iron_Skin, 5},
			{.Torrent, 5}, {.Insight, 6}, {.Mend, 7}, {.Fortify, 8},
		},
		move_pool = []Move_Id{.Aqua_Jet, .Tidal_Slam, .Undertow, .Bubble_Shield, .Torrent, .Heal_Spring, .Guard, .Hone, .Jab, .Brace, .Body_Slam, .Fortify, .Flurry, .Mend, .Insight, .Crush, .Iron_Skin},
	},
	// 2 - Sproutle
	{
		name = "Sproutle", element = .FLORA, base_hp = 58, base_energy = 3, base_energy_max = 4, base_power = 2, base_defense = 1, base_speed = 7,
		color = rl.Color{102, 188, 112, 255}, role = .STARTER,
		starter = []Move_Id{.Vine_Whip, .Vine_Whip, .Vine_Whip, .Vine_Whip, .Guard, .Guard, .Guard, .Thorn_Crash, .Hone, .Screech},
		learnset = []Learn_Entry{
			{.Vine_Whip, 1}, {.Guard, 1}, {.Hone, 1}, {.Screech, 1},
			{.Thorn_Crash, 2}, {.Leech, 3}, {.Bark_Skin, 4}, {.Bloom, 5},
			{.Iron_Skin, 5}, {.Flurry, 6}, {.Overgrowth, 6}, {.Mend, 7}, {.Fortify, 8},
		},
		move_pool = []Move_Id{.Vine_Whip, .Thorn_Crash, .Leech, .Bloom, .Overgrowth, .Bark_Skin, .Guard, .Hone, .Screech, .Jab, .Brace, .Body_Slam, .Fortify, .Flurry, .Mend, .Insight, .Crush, .Iron_Skin},
	},
	// 3 - Cave Bat
	{
		name = "Cave Bat", element = .NEUTRAL, base_hp = 36, base_energy = 3, base_energy_max = 4, base_power = 1, base_defense = 0, base_speed = 13,
		color = rl.Color{158, 146, 178, 255}, role = .WILD,
		starter = []Move_Id{.Tackle, .Tackle, .Tackle, .Tackle, .Guard, .Guard, .Guard, .Flurry, .Screech, .Hone},
		learnset = []Learn_Entry{
			{.Tackle, 1}, {.Guard, 1}, {.Hone, 1}, {.Screech, 1},
			{.Flurry, 2}, {.Crush, 3}, {.Insight, 4}, {.Mend, 4},
			{.Iron_Skin, 5}, {.Body_Slam, 5}, {.Fortify, 6},
		},
		move_pool = []Move_Id{.Tackle, .Flurry, .Crush, .Body_Slam, .Guard, .Fortify, .Hone, .Screech, .Iron_Skin, .Mend, .Insight, .Jab, .Brace},
	},
	// 4 - Magmite
	{
		name = "Magmite", element = .EMBER, base_hp = 42, base_energy = 3, base_energy_max = 4, base_power = 1, base_defense = 1, base_speed = 6,
		color = rl.Color{214, 92, 62, 255}, role = .WILD,
		starter = []Move_Id{.Ember_Strike, .Ember_Strike, .Ember_Strike, .Ember_Strike, .Guard, .Guard, .Guard, .Cinder, .Flame_Burst, .Screech},
		learnset = []Learn_Entry{
			{.Ember_Strike, 1}, {.Guard, 1}, {.Screech, 1}, {.Cinder, 1},
			{.Flame_Burst, 2}, {.Ash_Screen, 2}, {.Inferno, 4}, {.Iron_Skin, 5},
			{.Mend, 5}, {.Fortify, 6}, {.Blaze, 7},
		},
		move_pool = []Move_Id{.Ember_Strike, .Cinder, .Flame_Burst, .Inferno, .Ash_Screen, .Blaze, .Tackle, .Body_Slam, .Guard, .Fortify, .Flurry, .Iron_Skin, .Mend, .Crush, .Jab, .Brace},
	},
	// 5 - Bubblet
	{
		name = "Bubblet", element = .AQUA, base_hp = 44, base_energy = 3, base_energy_max = 4, base_power = 1, base_defense = 1, base_speed = 8,
		color = rl.Color{72, 134, 214, 255}, role = .WILD,
		starter = []Move_Id{.Aqua_Jet, .Aqua_Jet, .Aqua_Jet, .Aqua_Jet, .Guard, .Guard, .Guard, .Bubble_Shield, .Tidal_Slam, .Undertow},
		learnset = []Learn_Entry{
			{.Aqua_Jet, 1}, {.Guard, 1}, {.Undertow, 1}, {.Bubble_Shield, 1},
			{.Tidal_Slam, 2}, {.Heal_Spring, 3}, {.Iron_Skin, 4}, {.Insight, 5},
			{.Torrent, 5}, {.Mend, 6}, {.Fortify, 7},
		},
		move_pool = []Move_Id{.Aqua_Jet, .Undertow, .Tidal_Slam, .Bubble_Shield, .Heal_Spring, .Torrent, .Tackle, .Guard, .Fortify, .Flurry, .Iron_Skin, .Insight, .Mend, .Jab, .Brace},
	},
	// 6 - Thornkit
	{
		name = "Thornkit", element = .FLORA, base_hp = 40, base_energy = 3, base_energy_max = 4, base_power = 1, base_defense = 1, base_speed = 9,
		color = rl.Color{88, 172, 98, 255}, role = .WILD,
		starter = []Move_Id{.Vine_Whip, .Vine_Whip, .Vine_Whip, .Vine_Whip, .Guard, .Guard, .Guard, .Leech, .Thorn_Crash, .Screech},
		learnset = []Learn_Entry{
			{.Vine_Whip, 1}, {.Guard, 1}, {.Screech, 1}, {.Leech, 1},
			{.Thorn_Crash, 2}, {.Bark_Skin, 2}, {.Bloom, 4}, {.Iron_Skin, 5},
			{.Overgrowth, 5}, {.Mend, 6}, {.Fortify, 7},
		},
		move_pool = []Move_Id{.Vine_Whip, .Leech, .Thorn_Crash, .Bark_Skin, .Bloom, .Overgrowth, .Tackle, .Guard, .Fortify, .Screech, .Iron_Skin, .Mend, .Crush, .Jab, .Brace},
	},
	// 7 - Elite Sentinel
	{
		name = "Elite Sentinel", element = .NEUTRAL, base_hp = 66, base_energy = 4, base_energy_max = 5, base_power = 3, base_defense = 2, base_speed = 6,
		color = rl.Color{206, 122, 62, 255}, role = .ELITE,
		starter = []Move_Id{.Tackle, .Tackle, .Tackle, .Tackle, .Body_Slam, .Body_Slam, .Guard, .Guard, .Fortify, .Crush},
		learnset = []Learn_Entry{
			{.Tackle, 1}, {.Guard, 1}, {.Crush, 1}, {.Body_Slam, 1},
			{.Fortify, 2}, {.Iron_Skin, 3}, {.Screech, 3}, {.Flurry, 4},
			{.Hone, 4}, {.Mend, 5}, {.Insight, 5}, {.Blaze, 8},
		},
		move_pool = []Move_Id{.Tackle, .Body_Slam, .Crush, .Guard, .Fortify, .Iron_Skin, .Screech, .Flurry, .Hone, .Mend, .Insight, .Blaze, .Jab, .Brace},
	},
	// 8 - The Deep One
	{
		name = "The Deep One", element = .NEUTRAL, base_hp = 120, base_energy = 4, base_energy_max = 5, base_power = 5, base_defense = 3, base_speed = 5,
		color = rl.Color{150, 42, 62, 255}, role = .BOSS,
		starter = []Move_Id{.Body_Slam, .Body_Slam, .Body_Slam, .Body_Slam, .Fortify, .Fortify, .Fortify, .Crush, .Iron_Skin, .Hone},
		learnset = []Learn_Entry{
			{.Body_Slam, 1}, {.Fortify, 1}, {.Crush, 1}, {.Iron_Skin, 1}, {.Hone, 1},
			{.Blaze, 2}, {.Screech, 2}, {.Torrent, 4}, {.Inferno, 4},
			{.Overgrowth, 5}, {.Insight, 6}, {.Mend, 7},
		},
		move_pool = []Move_Id{.Body_Slam, .Fortify, .Crush, .Iron_Skin, .Hone, .Blaze, .Screech, .Torrent, .Inferno, .Overgrowth, .Insight, .Mend, .Guard, .Jab, .Brace},
	},
}

STARTER_SPECIES := [?]int{0, 1, 2}

Creature :: struct {
	species:      int,
	name:         string,
	level:        int,
	hp:           int,
	max_hp:       int,
	block:        int,
	vulnerable:   int,
	strength:     int,
	power:        int, // permanent bonus damage from leveling
	defense:      int, // permanent damage reduction from leveling
	defense_buff: int, // temporary, from moves (resets each battle)
	speed:        int, // initiative
	energy:       f32, // current bank (carries over between turns)
	energy_regen: f32, // gained at the start of each turn
	energy_max:   f32, // cap on the bank

	deck:       [dynamic]Move_Id, // persistent, owned by this creature
	draw_pile:  [dynamic]Move_Id, // per-battle
	hand:       [dynamic]Move_Id, // per-battle
	discard:    [dynamic]Move_Id, // per-battle

	// transient hit feedback (decays each frame, not saved)
	shake: f32,
	flash: f32,
}

creature_element :: proc(c: ^Creature) -> Element {
	return SPECIES[c.species].element
}

creature_color :: proc(c: ^Creature) -> rl.Color {
	return SPECIES[c.species].color
}

creature_defense :: proc(c: ^Creature) -> int {
	return c.defense + c.defense_buff
}

creature_knows :: proc(c: ^Creature, id: Move_Id) -> bool {
	for m in c.deck {
		if m == id {
			return true
		}
	}
	return false
}

// Pokémon-style: every stat is the species base multiplied by a level factor.
// Level 1 is exactly the base; each level adds 15% of the base.
level_scale :: proc(level: int) -> f32 {
	return 1.0 + 0.15 * f32(level - 1)
}

creature_stats_for_level :: proc(species_idx, level: int) -> (max_hp, power, defense, speed: int, energy_regen, energy_max: f32) {
	sp := SPECIES[species_idx]
	scale := level_scale(level)
	max_hp = int(f32(sp.base_hp) * scale)
	power = int(f32(sp.base_power) * scale)
	defense = int(f32(sp.base_defense) * scale)
	speed = int(f32(sp.base_speed) * scale)
	// Energy is continuous (no rounding), so costs can be any value the
	// designer wants. Regen is the per-turn income; max is the bank cap.
	energy_regen = clamp(f32(sp.base_energy) * scale, f32(sp.base_energy), 6.0)
	energy_max = clamp(f32(sp.base_energy_max) * scale, energy_regen, 8.0)
	return
}

creature_make :: proc(species_idx, level: int, name: string) -> Creature {
	sp := SPECIES[species_idx]
	max_hp, power, defense, speed, energy_regen, energy_max := creature_stats_for_level(species_idx, level)

	deck := make([dynamic]Move_Id, 0)
	for m in sp.starter {
		append(&deck, m)
	}

	return Creature{
		species      = species_idx,
		name         = name,
		level        = level,
		hp           = max_hp,
		max_hp       = max_hp,
		power        = power,
		defense      = defense,
		speed        = speed,
		energy       = 0,
		energy_regen = energy_regen,
		energy_max   = energy_max,
		deck         = deck,
		draw_pile    = make([dynamic]Move_Id, 0),
		hand         = make([dynamic]Move_Id, 0),
		discard      = make([dynamic]Move_Id, 0),
	}
}

creature_free_piles :: proc(c: ^Creature) {
	delete(c.draw_pile)
	delete(c.hand)
	delete(c.discard)
	c.draw_pile = make([dynamic]Move_Id, 0)
	c.hand = make([dynamic]Move_Id, 0)
	c.discard = make([dynamic]Move_Id, 0)
}

creature_free_all :: proc(c: ^Creature) {
	delete(c.deck)
	c.deck = make([dynamic]Move_Id, 0)
	creature_free_piles(c)
}

// Deep-copies the creature (deck included) so the copy owns its own cards.
creature_copy :: proc(src: ^Creature) -> Creature {
	cap := src^
	cap.deck = make([dynamic]Move_Id, 0)
	for m in src.deck {
		append(&cap.deck, m)
	}
	cap.draw_pile = make([dynamic]Move_Id, 0)
	cap.hand = make([dynamic]Move_Id, 0)
	cap.discard = make([dynamic]Move_Id, 0)
	cap.shake = 0
	cap.flash = 0
	return cap
}

// Level up: recompute scaled stats and automatically learn any learnset moves
// whose level is now reached. Reward picks happen separately (from move_pool).
creature_level_up :: proc(c: ^Creature) {
	old_max := c.max_hp
	c.level += 1
	new_max, new_power, new_def, new_spd, new_regen, new_energy_max := creature_stats_for_level(c.species, c.level)
	c.max_hp = new_max
	c.power = new_power
	c.defense = new_def
	c.speed = new_spd
	c.energy_regen = new_regen
	c.energy_max = new_energy_max
	c.hp = min(c.hp + (new_max - old_max) + new_max / 8, new_max)

	for entry in SPECIES[c.species].learnset {
		if entry.level == c.level && !creature_knows(c, entry.move) {
			append(&c.deck, entry.move)
		}
	}
}

// Clear per-battle state so temporary buffs/debuffs don't carry over.
creature_reset_battle_state :: proc(c: ^Creature) {
	c.block = 0
	c.strength = 0
	c.vulnerable = 0
	c.defense_buff = 0
	c.energy = 0
	c.shake = 0
	c.flash = 0
}

party_free :: proc(p: ^[dynamic]Creature) {
	arr := p^
	for i in 0..<len(arr) {
		creature_free_all(&arr[i])
	}
	delete(arr)
	p^ = make([dynamic]Creature, 0)
}

party_heal :: proc(p: ^[dynamic]Creature, fraction: f32) {
	arr := p^
	for i in 0..<len(arr) {
		amount := int(f32(arr[i].max_hp) * fraction)
		arr[i].hp = min(arr[i].hp + amount, arr[i].max_hp)
	}
}
