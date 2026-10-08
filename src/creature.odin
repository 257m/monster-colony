package main

import rl "vendor:raylib"
import "core:fmt"

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
	elements:     []Element, // 1 or 2 types, primary first
	base_hp:      int,
	base_energy:  int, // energy generated per turn
	base_energy_max: int, // energy bank cap
	base_power:   f32,
	base_defense: f32,
	base_speed:   f32,
	base_satiety: int, // satiation capacity (food bar)
	base_upkeep:  int, // food consumed per turn
	color:        rl.Color,
	role:         Species_Role,
	starter:      []Move_Id,
	learnset:     []Learn_Entry,
	move_pool:    []Move_Id,
}

// Neutral moves any creature can pick up as a reward but that no learnset
// grants — i.e. reward-only options.
COMMON_MOVES := []Move_Id{.Jab, .Brace, .Body_Slam, .Fortify, .Flurry, .Mend, .Insight, .Crush, .Iron_Skin, .Fang, .Exploit, .Payback, .Followup, .Second_Wind, .Gnaw, .Warcry, .Twin_Fangs, .Feint, .Weaken, .Disarm, .Sunder, .Corrode}

SPECIES := [?]Species{
	// 0 - Emberling
	{
		name = "Emberling", elements = []Element{.EMBER}, base_hp = 60, base_energy = 3, base_energy_max = 4, base_power = 1.0, base_defense = 1.0, base_speed = 9.0, base_satiety = 100, base_upkeep = 3,
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
		name = "Tidepup", elements = []Element{.AQUA}, base_hp = 62, base_energy = 3, base_energy_max = 4, base_power = 1.0, base_defense = 1.0, base_speed = 8.0, base_satiety = 105, base_upkeep = 3,
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
		name = "Sproutle", elements = []Element{.FLORA}, base_hp = 58, base_energy = 3, base_energy_max = 4, base_power = 1.0, base_defense = 1.0, base_speed = 7.0, base_satiety = 95, base_upkeep = 3,
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
		name = "Cave Bat", elements = []Element{.NEUTRAL}, base_hp = 36, base_energy = 3, base_energy_max = 4, base_power = 0.75, base_defense = 0.0, base_speed = 13.0, base_satiety = 70, base_upkeep = 2,
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
		name = "Magmite", elements = []Element{.EMBER}, base_hp = 42, base_energy = 3, base_energy_max = 4, base_power = 0.85, base_defense = 1.0, base_speed = 6.0, base_satiety = 90, base_upkeep = 3,
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
		name = "Bubblet", elements = []Element{.AQUA}, base_hp = 44, base_energy = 3, base_energy_max = 4, base_power = 0.85, base_defense = 1.0, base_speed = 8.0, base_satiety = 95, base_upkeep = 2,
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
		name = "Thornkit", elements = []Element{.FLORA}, base_hp = 40, base_energy = 3, base_energy_max = 4, base_power = 0.85, base_defense = 1.0, base_speed = 9.0, base_satiety = 85, base_upkeep = 2,
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
		name = "Elite Sentinel", elements = []Element{.NEUTRAL}, base_hp = 66, base_energy = 4, base_energy_max = 5, base_power = 1.3, base_defense = 2.0, base_speed = 6.0, base_satiety = 140, base_upkeep = 5,
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
		name = "The Deep One", elements = []Element{.NEUTRAL}, base_hp = 120, base_energy = 4, base_energy_max = 5, base_power = 1.6, base_defense = 3.0, base_speed = 5.0, base_satiety = 220, base_upkeep = 8,
		color = rl.Color{150, 42, 62, 255}, role = .BOSS,
		starter = []Move_Id{.Body_Slam, .Body_Slam, .Body_Slam, .Body_Slam, .Fortify, .Fortify, .Fortify, .Crush, .Iron_Skin, .Hone},
		learnset = []Learn_Entry{
			{.Body_Slam, 1}, {.Fortify, 1}, {.Crush, 1}, {.Iron_Skin, 1}, {.Hone, 1},
			{.Blaze, 2}, {.Screech, 2}, {.Torrent, 4}, {.Inferno, 4},
			{.Overgrowth, 5}, {.Insight, 6}, {.Mend, 7},
		},
		move_pool = []Move_Id{.Body_Slam, .Fortify, .Crush, .Iron_Skin, .Hone, .Blaze, .Screech, .Torrent, .Inferno, .Overgrowth, .Insight, .Mend, .Guard, .Jab, .Brace},
	},
	// 9 - Gloomling (content)
	{
		name = "Gloomling", elements = []Element{.NEUTRAL, .FLORA}, base_hp = 50, base_energy = 3, base_energy_max = 4, base_power = 0.85, base_defense = 2.0, base_speed = 5.0, base_satiety = 110, base_upkeep = 3,
		color = rl.Color{120, 118, 140, 255}, role = .WILD,
		starter = []Move_Id{.Tackle, .Tackle, .Tackle, .Tackle, .Guard, .Guard, .Weaken, .Body_Slam, .Fortify, .Exploit},
		learnset = []Learn_Entry{
			{.Tackle, 1}, {.Guard, 1}, {.Fortify, 1}, {.Exploit, 1},
			{.Crush, 2}, {.Body_Slam, 3}, {.Iron_Skin, 3}, {.Payback, 4}, {.Screech, 4},
			{.Mend, 5}, {.Followup, 6},
		},
		move_pool = []Move_Id{.Tackle, .Body_Slam, .Crush, .Guard, .Fortify, .Iron_Skin, .Screech, .Payback, .Exploit, .Followup, .Mend, .Insight, .Fang, .Brace, .Jab},
	},
	// 10 - Pyrelord (content)
	{
		name = "Pyrelord", elements = []Element{.EMBER}, base_hp = 54, base_energy = 3, base_energy_max = 4, base_power = 1.1, base_defense = 1.0, base_speed = 7.0, base_satiety = 110, base_upkeep = 4,
		color = rl.Color{232, 84, 48, 255}, role = .WILD,
		starter = []Move_Id{.Ember_Strike, .Ember_Strike, .Ember_Strike, .Ember_Strike, .Guard, .Guard, .Guard, .Flame_Burst, .Combust, .Rampage},
		learnset = []Learn_Entry{
			{.Ember_Strike, 1}, {.Guard, 1}, {.Combust, 1},
			{.Flame_Burst, 2}, {.Cinder, 2}, {.Rampage, 3}, {.Inferno, 4}, {.Iron_Skin, 4},
			{.Screech, 5}, {.Followup, 5}, {.Blaze, 6}, {.Mend, 6},
		},
		move_pool = []Move_Id{.Ember_Strike, .Cinder, .Combust, .Flame_Burst, .Rampage, .Inferno, .Blaze, .Ash_Screen, .Guard, .Fortify, .Followup, .Exploit, .Iron_Skin, .Mend},
	},
	// 11 - Krakling (content)
	{
		name = "Krakling", elements = []Element{.AQUA, .EMBER}, base_hp = 56, base_energy = 3, base_energy_max = 4, base_power = 1.05, base_defense = 1.0, base_speed = 8.0, base_satiety = 110, base_upkeep = 3,
		color = rl.Color{60, 120, 210, 255}, role = .WILD,
		starter = []Move_Id{.Aqua_Jet, .Aqua_Jet, .Aqua_Jet, .Aqua_Jet, .Guard, .Guard, .Guard, .Tidal_Slam, .Frost_Bite, .Bubble_Shield},
		learnset = []Learn_Entry{
			{.Aqua_Jet, 1}, {.Guard, 1}, {.Frost_Bite, 1},
			{.Bubble_Shield, 2}, {.Tidal_Slam, 2}, {.Undertow, 3}, {.Iron_Skin, 4}, {.Heal_Spring, 4},
			{.Torrent, 5}, {.Followup, 5}, {.Mend, 6}, {.Fortify, 6},
		},
		move_pool = []Move_Id{.Aqua_Jet, .Undertow, .Frost_Bite, .Bubble_Shield, .Tidal_Slam, .Heal_Spring, .Torrent, .Guard, .Fortify, .Followup, .Insight, .Iron_Skin, .Mend},
	},
	// 12 - Swampbeast (content)
	{
		name = "Swampbeast", elements = []Element{.FLORA, .AQUA}, base_hp = 60, base_energy = 3, base_energy_max = 4, base_power = 1.05, base_defense = 2.0, base_speed = 5.0, base_satiety = 120, base_upkeep = 4,
		color = rl.Color{74, 158, 84, 255}, role = .WILD,
		starter = []Move_Id{.Vine_Whip, .Vine_Whip, .Vine_Whip, .Vine_Whip, .Guard, .Guard, .Guard, .Thorn_Crash, .Lash, .Bloom},
		learnset = []Learn_Entry{
			{.Vine_Whip, 1}, {.Guard, 1}, {.Lash, 1},
			{.Bloom, 2}, {.Thorn_Crash, 2}, {.Leech, 3}, {.Bark_Skin, 3}, {.Iron_Skin, 4},
			{.Overgrowth, 5}, {.Followup, 5}, {.Mend, 6}, {.Fortify, 6},
		},
		move_pool = []Move_Id{.Vine_Whip, .Lash, .Leech, .Thorn_Crash, .Bloom, .Overgrowth, .Bark_Skin, .Guard, .Fortify, .Followup, .Screech, .Iron_Skin, .Mend, .Crush},
	},
	// 13 - Wispling (content): fast support, fragile
	{
		name = "Wispling", elements = []Element{.NEUTRAL}, base_hp = 44, base_energy = 3, base_energy_max = 4, base_power = 0.95, base_defense = 0.5, base_speed = 11.5, base_satiety = 90, base_upkeep = 2,
		color = rl.Color{150, 170, 200, 255}, role = .WILD,
		starter = []Move_Id{.Jab, .Jab, .Jab, .Jab, .Guard, .Guard, .Disarm, .Flurry, .Feint, .Warcry},
		learnset = []Learn_Entry{
			{.Jab, 1}, {.Guard, 1}, {.Feint, 1}, {.Warcry, 1},
			{.Flurry, 2}, {.Followup, 2}, {.Insight, 3}, {.Gnaw, 4},
			{.Twin_Fangs, 5}, {.Exploit, 5}, {.Mend, 6}, {.Second_Wind, 6},
		},
		move_pool = []Move_Id{.Jab, .Feint, .Warcry, .Flurry, .Followup, .Gnaw, .Twin_Fangs, .Exploit, .Payback, .Second_Wind, .Insight, .Mend, .Brace, .Guard, .Fang},
	},
	// 14 - Cindermaw (content): glass cannon
	{
		name = "Cindermaw", elements = []Element{.EMBER}, base_hp = 48, base_energy = 3, base_energy_max = 4, base_power = 1.25, base_defense = 0.5, base_speed = 6.5, base_satiety = 100, base_upkeep = 4,
		color = rl.Color{240, 70, 40, 255}, role = .WILD,
		starter = []Move_Id{.Ember_Strike, .Ember_Strike, .Ember_Strike, .Ember_Strike, .Guard, .Guard, .Guard, .Flare, .Combust, .Rampage},
		learnset = []Learn_Entry{
			{.Ember_Strike, 1}, {.Guard, 1}, {.Flare, 1},
			{.Combust, 2}, {.Cinder, 2}, {.Rampage, 3}, {.Inferno, 4}, {.Twin_Fangs, 5},
			{.Exploit, 5}, {.Blaze, 6}, {.Mend, 6},
		},
		move_pool = []Move_Id{.Ember_Strike, .Flare, .Cinder, .Combust, .Rampage, .Inferno, .Blaze, .Ash_Screen, .Twin_Fangs, .Exploit, .Followup, .Guard, .Mend},
	},
	// 15 - Rimescale (content): tanky water
	{
		name = "Rimescale", elements = []Element{.AQUA}, base_hp = 64, base_energy = 3, base_energy_max = 4, base_power = 0.95, base_defense = 2.5, base_speed = 5.5, base_satiety = 130, base_upkeep = 4,
		color = rl.Color{70, 150, 220, 255}, role = .WILD,
		starter = []Move_Id{.Aqua_Jet, .Aqua_Jet, .Aqua_Jet, .Aqua_Jet, .Guard, .Guard, .Guard, .Frost_Bite, .Bubble_Shield, .Tidecall},
		learnset = []Learn_Entry{
			{.Aqua_Jet, 1}, {.Guard, 1}, {.Frost_Bite, 1}, {.Bubble_Shield, 1},
			{.Tidecall, 2}, {.Tidal_Slam, 2}, {.Undertow, 3}, {.Iron_Skin, 4},
			{.Heal_Spring, 4}, {.Torrent, 5}, {.Regrowth, 6}, {.Mend, 6},
		},
		move_pool = []Move_Id{.Aqua_Jet, .Frost_Bite, .Bubble_Shield, .Tidecall, .Undertow, .Tidal_Slam, .Heal_Spring, .Torrent, .Guard, .Fortify, .Iron_Skin, .Regrowth, .Mend, .Second_Wind},
	},
	// 16 - Mosshide (content): balanced flora
	{
		name = "Mosshide", elements = []Element{.FLORA}, base_hp = 62, base_energy = 3, base_energy_max = 4, base_power = 1.05, base_defense = 1.5, base_speed = 7.5, base_satiety = 125, base_upkeep = 4,
		color = rl.Color{96, 170, 88, 255}, role = .WILD,
		starter = []Move_Id{.Vine_Whip, .Vine_Whip, .Vine_Whip, .Vine_Whip, .Guard, .Guard, .Guard, .Bramble, .Lash, .Bloom},
		learnset = []Learn_Entry{
			{.Vine_Whip, 1}, {.Guard, 1}, {.Bramble, 1}, {.Lash, 1},
			{.Bloom, 2}, {.Leech, 2}, {.Thorn_Crash, 3}, {.Bark_Skin, 4},
			{.Iron_Skin, 4}, {.Overgrowth, 5}, {.Regrowth, 5}, {.Mend, 6},
		},
		move_pool = []Move_Id{.Vine_Whip, .Bramble, .Lash, .Leech, .Bloom, .Thorn_Crash, .Overgrowth, .Bark_Skin, .Guard, .Fortify, .Regrowth, .Iron_Skin, .Mend, .Screech},
	},
	// 17 - Emberbloom (dual Ember/Flora)
	{
		name = "Emberbloom", elements = []Element{.EMBER, .FLORA}, base_hp = 56, base_energy = 3, base_energy_max = 4, base_power = 1.15, base_defense = 1.0, base_speed = 6.0, base_satiety = 115, base_upkeep = 4,
		color = rl.Color{206, 120, 92, 255}, role = .WILD,
		starter = []Move_Id{.Ember_Strike, .Ember_Strike, .Ember_Strike, .Ember_Strike, .Guard, .Guard, .Guard, .Flame_Burst, .Vine_Whip, .Bramble},
		learnset = []Learn_Entry{
			{.Ember_Strike, 1}, {.Guard, 1}, {.Bramble, 1},
			{.Flame_Burst, 2}, {.Cinder, 2}, {.Vine_Whip, 3}, {.Combust, 4},
			{.Inferno, 5}, {.Overgrowth, 5}, {.Rampage, 6}, {.Mend, 6},
		},
		move_pool = []Move_Id{.Ember_Strike, .Cinder, .Combust, .Flame_Burst, .Rampage, .Inferno, .Vine_Whip, .Bramble, .Leech, .Overgrowth, .Guard, .Fortify, .Exploit, .Mend},
	},
	// 18 - Bogfang (dual Aqua/Neutral)
	{
		name = "Bogfang", elements = []Element{.AQUA, .NEUTRAL}, base_hp = 60, base_energy = 3, base_energy_max = 4, base_power = 0.95, base_defense = 2.0, base_speed = 6.0, base_satiety = 120, base_upkeep = 4,
		color = rl.Color{78, 124, 124, 255}, role = .WILD,
		starter = []Move_Id{.Aqua_Jet, .Aqua_Jet, .Aqua_Jet, .Aqua_Jet, .Guard, .Guard, .Weaken, .Undertow, .Fang, .Fortify},
		learnset = []Learn_Entry{
			{.Aqua_Jet, 1}, {.Guard, 1}, {.Undertow, 1}, {.Fang, 1},
			{.Tidal_Slam, 2}, {.Fortify, 2}, {.Iron_Skin, 3}, {.Frost_Bite, 4},
			{.Crush, 4}, {.Torrent, 5}, {.Mend, 5}, {.Payback, 6},
		},
		move_pool = []Move_Id{.Aqua_Jet, .Undertow, .Frost_Bite, .Tidal_Slam, .Torrent, .Fang, .Crush, .Body_Slam, .Guard, .Fortify, .Iron_Skin, .Payback, .Mend, .Brace},
	},
	// 19 - Cinderwing (dual Ember/Neutral)
	{
		name = "Cinderwing", elements = []Element{.EMBER, .NEUTRAL}, base_hp = 46, base_energy = 3, base_energy_max = 4, base_power = 1.15, base_defense = 0.5, base_speed = 10.5, base_satiety = 95, base_upkeep = 3,
		color = rl.Color{232, 116, 66, 255}, role = .WILD,
		starter = []Move_Id{.Ember_Strike, .Ember_Strike, .Ember_Strike, .Ember_Strike, .Guard, .Guard, .Guard, .Flare, .Followup, .Feint},
		learnset = []Learn_Entry{
			{.Ember_Strike, 1}, {.Guard, 1}, {.Flare, 1}, {.Feint, 1},
			{.Followup, 2}, {.Flurry, 2}, {.Cinder, 3}, {.Twin_Fangs, 4},
			{.Rampage, 5}, {.Exploit, 5}, {.Blaze, 6}, {.Mend, 6},
		},
		move_pool = []Move_Id{.Ember_Strike, .Flare, .Cinder, .Combust, .Rampage, .Blaze, .Followup, .Feint, .Flurry, .Twin_Fangs, .Exploit, .Guard, .Mend, .Insight},
	},
	// 20 - Frostmoss (dual Aqua/Flora)
	{
		name = "Frostmoss", elements = []Element{.AQUA, .FLORA}, base_hp = 66, base_energy = 3, base_energy_max = 4, base_power = 0.95, base_defense = 2.5, base_speed = 5.0, base_satiety = 130, base_upkeep = 4,
		color = rl.Color{96, 168, 168, 255}, role = .WILD,
		starter = []Move_Id{.Aqua_Jet, .Aqua_Jet, .Aqua_Jet, .Aqua_Jet, .Guard, .Guard, .Guard, .Frost_Bite, .Bramble, .Bloom},
		learnset = []Learn_Entry{
			{.Aqua_Jet, 1}, {.Guard, 1}, {.Frost_Bite, 1}, {.Bramble, 1},
			{.Bloom, 2}, {.Bubble_Shield, 2}, {.Leech, 3}, {.Undertow, 3},
			{.Iron_Skin, 4}, {.Regrowth, 5}, {.Tidal_Slam, 5}, {.Mend, 6},
		},
		move_pool = []Move_Id{.Aqua_Jet, .Frost_Bite, .Undertow, .Bubble_Shield, .Tidecall, .Bloom, .Bramble, .Leech, .Regrowth, .Heal_Spring, .Guard, .Fortify, .Iron_Skin, .Mend},
	},
	// 21 - Frostfang (Ice)
	{
		name = "Frostfang", elements = []Element{.ICE}, base_hp = 52, base_energy = 3, base_energy_max = 4, base_power = 1.05, base_defense = 1.5, base_speed = 7.0, base_satiety = 110, base_upkeep = 3,
		color = rl.Color{150, 216, 236, 255}, role = .WILD,
		starter = []Move_Id{.Frost_Shard, .Frost_Shard, .Frost_Shard, .Frost_Shard, .Guard, .Guard, .Guard, .Glacier_Slam, .Iron_Skin, .Mend},
		learnset = []Learn_Entry{
			{.Frost_Shard, 1}, {.Guard, 1}, {.Iron_Skin, 1}, {.Glacier_Slam, 2},
			{.Fortify, 3}, {.Frost_Bite, 4}, {.Followup, 4}, {.Mend, 4},
			{.Second_Wind, 5}, {.Insight, 5}, {.Regrowth, 6},
		},
		move_pool = []Move_Id{.Frost_Shard, .Glacier_Slam, .Frost_Bite, .Guard, .Fortify, .Iron_Skin, .Followup, .Second_Wind, .Mend, .Insight, .Regrowth, .Brace, .Exploit},
	},
	// 22 - Stonepaw (Ground)
	{
		name = "Stonepaw", elements = []Element{.GROUND}, base_hp = 62, base_energy = 3, base_energy_max = 4, base_power = 1.05, base_defense = 2.5, base_speed = 4.5, base_satiety = 125, base_upkeep = 4,
		color = rl.Color{160, 128, 84, 255}, role = .WILD,
		starter = []Move_Id{.Rock_Toss, .Rock_Toss, .Rock_Toss, .Rock_Toss, .Guard, .Guard, .Sunder, .Quake, .Fortify, .Iron_Skin},
		learnset = []Learn_Entry{
			{.Rock_Toss, 1}, {.Guard, 1}, {.Fortify, 1}, {.Quake, 2}, {.Iron_Skin, 2},
			{.Crush, 3}, {.Body_Slam, 4}, {.Payback, 4}, {.Mend, 5}, {.Bramble, 5}, {.Second_Wind, 6},
		},
		move_pool = []Move_Id{.Rock_Toss, .Quake, .Crush, .Body_Slam, .Guard, .Fortify, .Iron_Skin, .Payback, .Bramble, .Mend, .Second_Wind, .Brace, .Fang},
	},
	// 23 - Sparkit (Electric)
	{
		name = "Sparkit", elements = []Element{.ELECTRIC}, base_hp = 46, base_energy = 3, base_energy_max = 4, base_power = 1.1, base_defense = 0.5, base_speed = 11.0, base_satiety = 95, base_upkeep = 3,
		color = rl.Color{242, 214, 70, 255}, role = .WILD,
		starter = []Move_Id{.Spark, .Spark, .Spark, .Spark, .Guard, .Guard, .Guard, .Thunderbolt, .Feint, .Followup},
		learnset = []Learn_Entry{
			{.Spark, 1}, {.Guard, 1}, {.Feint, 1}, {.Followup, 2}, {.Flurry, 2},
			{.Hone, 3}, {.Thunderbolt, 4}, {.Twin_Fangs, 4}, {.Exploit, 5}, {.Insight, 5}, {.Mend, 6},
		},
		move_pool = []Move_Id{.Spark, .Thunderbolt, .Followup, .Flurry, .Twin_Fangs, .Exploit, .Feint, .Insight, .Hone, .Guard, .Mend, .Brace, .Fang},
	},
	// 24 - Galebeast (Air)
	{
		name = "Galebeast", elements = []Element{.AIR}, base_hp = 50, base_energy = 3, base_energy_max = 4, base_power = 0.95, base_defense = 1.0, base_speed = 12.0, base_satiety = 100, base_upkeep = 3,
		color = rl.Color{206, 214, 230, 255}, role = .WILD,
		starter = []Move_Id{.Gust, .Gust, .Gust, .Gust, .Guard, .Guard, .Guard, .Cyclone, .Feint, .Warcry},
		learnset = []Learn_Entry{
			{.Gust, 1}, {.Guard, 1}, {.Feint, 1}, {.Warcry, 1}, {.Followup, 2},
			{.Cyclone, 4}, {.Twin_Fangs, 4}, {.Exploit, 5}, {.Insight, 5}, {.Second_Wind, 5}, {.Mend, 6},
		},
		move_pool = []Move_Id{.Gust, .Cyclone, .Followup, .Flurry, .Twin_Fangs, .Feint, .Warcry, .Second_Wind, .Insight, .Exploit, .Guard, .Mend, .Brace},
	},
	// 25 - Venomtail (Poison)
	{
		name = "Venomtail", elements = []Element{.POISON}, base_hp = 54, base_energy = 3, base_energy_max = 4, base_power = 1.05, base_defense = 1.0, base_speed = 8.0, base_satiety = 105, base_upkeep = 3,
		color = rl.Color{170, 84, 186, 255}, role = .WILD,
		starter = []Move_Id{.Toxic_Bite, .Toxic_Bite, .Toxic_Bite, .Toxic_Bite, .Guard, .Guard, .Corrode, .Venom, .Screech, .Hone},
		learnset = []Learn_Entry{
			{.Toxic_Bite, 1}, {.Guard, 1}, {.Screech, 1}, {.Hone, 1}, {.Venom, 2},
			{.Crush, 3}, {.Leech, 3}, {.Followup, 4}, {.Exploit, 5}, {.Mend, 5}, {.Second_Wind, 6},
		},
		move_pool = []Move_Id{.Toxic_Bite, .Venom, .Crush, .Leech, .Screech, .Hone, .Followup, .Exploit, .Payback, .Guard, .Fortify, .Mend, .Second_Wind},
	},
	// 26 - Blizzard (dual Ice/Air)
	{
		name = "Blizzard", elements = []Element{.ICE, .AIR}, base_hp = 58, base_energy = 3, base_energy_max = 4, base_power = 1.1, base_defense = 1.5, base_speed = 9.0, base_satiety = 115, base_upkeep = 4,
		color = rl.Color{176, 210, 240, 255}, role = .WILD,
		starter = []Move_Id{.Frost_Shard, .Frost_Shard, .Frost_Shard, .Frost_Shard, .Guard, .Guard, .Guard, .Glacier_Slam, .Gust, .Cyclone},
		learnset = []Learn_Entry{
			{.Frost_Shard, 1}, {.Guard, 1}, {.Gust, 1}, {.Glacier_Slam, 2},
			{.Cyclone, 3}, {.Followup, 3}, {.Iron_Skin, 4}, {.Second_Wind, 5},
			{.Twin_Fangs, 5}, {.Mend, 6},
		},
		move_pool = []Move_Id{.Frost_Shard, .Glacier_Slam, .Gust, .Cyclone, .Frost_Bite, .Followup, .Twin_Fangs, .Iron_Skin, .Second_Wind, .Guard, .Fortify, .Mend, .Insight},
	},
}

STARTER_SPECIES := [?]int{0, 1, 2}

Creature :: struct {
	species:      int,
	name:         string,
	level:        int,
	xp:           int, // experience toward the next level (shared with the map)
	hp:           int,
	max_hp:       int,
	block:        int,
	vulnerable:   int,
	strength:     int,
	power:        f32, // permanent bonus damage from leveling
	defense:      f32, // permanent damage reduction from leveling
	defense_buff: f32, // temporary, from moves (resets each battle)
	defense_debuff: f32, // temporary defense shred from enemy moves (resets each battle)
	speed:        f32, // initiative
	energy:       f32, // current bank (carries over between turns)
	energy_regen: f32, // gained at the start of each turn
	energy_max:   f32, // cap on the bank

	deck:       [dynamic]Move_Id, // persistent, owned by this creature
	draw_pile:  [dynamic]Move_Id, // per-battle
	hand:       [dynamic]Move_Id, // per-battle
	discard:    [dynamic]Move_Id, // per-battle
	played:     int,              // cards played this turn (combo synergy)

	// transient hit feedback (decays each frame, not saved)
	shake: f32,
	flash: f32,
}

creature_elements :: proc(c: ^Creature) -> []Element {
	return SPECIES[c.species].elements
}

// Primary element (used for colour / defaults).
creature_element :: proc(c: ^Creature) -> Element {
	els := SPECIES[c.species].elements
	return len(els) > 0 ? els[0] : .NEUTRAL
}

// "Ember" for a single type, "Aqua/Ember" for a dual type.
elements_label :: proc(els: []Element) -> cstring {
	if len(els) == 0 {
		return "Neutral"
	}
	if len(els) == 1 {
		return element_name(els[0])
	}
	return fmt.ctprintf("%s/%s", element_name(els[0]), element_name(els[1]))
}

element_label :: proc(c: ^Creature) -> cstring {
	return elements_label(SPECIES[c.species].elements)
}

role_name :: proc(r: Species_Role) -> cstring {
	switch r {
	case .STARTER: return "Starter"
	case .WILD:    return "Wild"
	case .ELITE:   return "Elite"
	case .BOSS:    return "Boss"
	}
	return "?"
}

creature_has_element :: proc(c: ^Creature, e: Element) -> bool {
	for el in SPECIES[c.species].elements {
		if el == e {
			return true
		}
	}
	return false
}

creature_color :: proc(c: ^Creature) -> rl.Color {
	return SPECIES[c.species].color
}

creature_defense :: proc(c: ^Creature) -> f32 {
	return max(c.defense + c.defense_buff - c.defense_debuff, 0)
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

creature_stats_for_level :: proc(species_idx, level: int) -> (max_hp: int, power, defense, speed, energy_regen, energy_max: f32) {
	sp := SPECIES[species_idx]
	scale := level_scale(level)
	max_hp = int(f32(sp.base_hp) * scale)
	power = sp.base_power * scale
	defense = sp.base_defense * scale
	speed = sp.base_speed * scale
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

// Clear per-battle state so temporary buffs/debuffs don't carry over. Energy is
// shared with the colony map, so it is NOT reset here.
creature_reset_battle_state :: proc(c: ^Creature) {
	c.block = 0
	c.strength = 0
	c.vulnerable = 0
	c.defense_buff = 0
	c.defense_debuff = 0
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
