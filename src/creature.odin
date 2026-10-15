package main

import rl "vendor:raylib"
import "core:fmt"
import "core:math"

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

// How hard a species is to find, catch and buy. Drives capture odds, shop
// appearance rates/prices, and kill loot.
Rarity :: enum { COMMON, UNCOMMON, RARE, EPIC, LEGENDARY }

Learn_Entry :: struct {
	move:  Move_Id,
	level: int,
}

Species_Id :: enum {
	Emberling,     // 0
	Tidepup,       // 1
	Sproutle,      // 2
	Cave_Bat,      // 3
	Magmite,       // 4
	Bubblet,       // 5
	Thornkit,      // 6
	Elite_Sentinel, // 7
	Deep_One,      // 8
	Gloomling,     // 9
	Pyrelord,      // 10
	Krakling,      // 11
	Swampbeast,    // 12
	Wispling,      // 13
	Cindermaw,     // 14
	Rimescale,     // 15
	Mosshide,      // 16
	Emberbloom,    // 17
	Bogfang,       // 18
	Cinderwing,    // 19
	Frostmoss,     // 20
	Frostfang,     // 21
	Stonepaw,      // 22
	Sparkit,       // 23
	Galebeast,     // 24
	Venomtail,     // 25
	Blizzard,      // 26
	// Bosses (Phase 25): unique, very powerful, with synergy movesets.
	Boss_Leviathan, // 27
	Boss_Infernal,  // 28
	Boss_Titan,     // 29
	Boss_Sovereign, // 30
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
	rarity:       Rarity,
	starter:      []Move_Id,
	learnset:     []Learn_Entry,
	move_pool:    []Move_Id,
}

// Neutral moves any creature can pick up as a reward but that no learnset
// grants — i.e. reward-only options.
COMMON_MOVES := []Move_Id{.Jab, .Brace, .Body_Slam, .Fortify, .Flurry, .Mend, .Insight, .Crush, .Iron_Skin, .Fang, .Exploit, .Payback, .Followup, .Second_Wind, .Gnaw, .Warcry, .Twin_Fangs, .Feint, .Weaken, .Disarm, .Sunder, .Corrode, .Channel, .Shared_Ward, .Field_Mend, .Siphon, .Cull, .Coordinated_Strike, .Overexert, .Kindle, .Conduit, .Ward}

// Premium reward-only cards: expensive, high-impact energy sinks. Choosing one
// commits a large chunk of a monster's energy, so it is a real trade-off.
PREMIUM_MOVES := []Move_Id{.Meteor, .Tsunami, .Maelstrom, .Cataclysm, .Aegis, .Phoenix}

// Status-effect reward-only cards (Phase 21): poison/burn DoT, stun, regen and
// thorns. Like COMMON_MOVES these are never in a learnset.
STATUS_MOVES := []Move_Id{.Toxic_Cloud, .Envenom, .Plague, .Ember_Coil, .Immolate, .Wildfire, .Concuss, .Static_Shock, .Paralyze, .Photosynth, .Rejuvenate, .Bramble_Armor, .Spike_Shell}

SPECIES := [Species_Id]Species{
	// Emberling
	.Emberling = {
		name = "Emberling", elements = []Element{.EMBER}, base_hp = 60, base_energy = 3, base_energy_max = 8, base_power = 1.0, base_defense = 1.0, base_speed = 9.0, base_satiety = 100, base_upkeep = 3,
		color = rl.Color{226, 110, 72, 255}, role = .STARTER, rarity = .COMMON,
		starter = []Move_Id{.Ember_Strike, .Ember_Strike, .Ember_Strike, .Ember_Strike, .Guard, .Guard, .Guard, .Flame_Burst, .Hone, .Screech},
		learnset = []Learn_Entry{
			{.Ember_Strike, 1}, {.Guard, 1}, {.Hone, 1}, {.Screech, 1},
			{.Flame_Burst, 2}, {.Cinder, 3}, {.Iron_Skin, 4}, {.Inferno, 5},
			{.Flurry, 6}, {.Insight, 6}, {.Mend, 7}, {.Fortify, 8}, {.Blaze, 9},
		},
		move_pool = []Move_Id{.Ember_Strike, .Flame_Burst, .Cinder, .Inferno, .Blaze, .Ash_Screen, .Guard, .Hone, .Screech, .Jab, .Brace, .Body_Slam, .Fortify, .Flurry, .Mend, .Insight, .Crush, .Iron_Skin},
	},
	// Tidepup
	.Tidepup = {
		name = "Tidepup", elements = []Element{.AQUA}, base_hp = 62, base_energy = 3, base_energy_max = 8, base_power = 1.0, base_defense = 1.0, base_speed = 8.0, base_satiety = 105, base_upkeep = 3,
		color = rl.Color{86, 150, 226, 255}, role = .STARTER, rarity = .COMMON,
		starter = []Move_Id{.Aqua_Jet, .Aqua_Jet, .Aqua_Jet, .Aqua_Jet, .Guard, .Guard, .Guard, .Tidal_Slam, .Hone, .Undertow},
		learnset = []Learn_Entry{
			{.Aqua_Jet, 1}, {.Guard, 1}, {.Hone, 1}, {.Undertow, 1},
			{.Tidal_Slam, 2}, {.Bubble_Shield, 3}, {.Heal_Spring, 4}, {.Iron_Skin, 5},
			{.Torrent, 5}, {.Insight, 6}, {.Mend, 7}, {.Fortify, 8},
		},
		move_pool = []Move_Id{.Aqua_Jet, .Tidal_Slam, .Undertow, .Bubble_Shield, .Torrent, .Heal_Spring, .Guard, .Hone, .Jab, .Brace, .Body_Slam, .Fortify, .Flurry, .Mend, .Insight, .Crush, .Iron_Skin},
	},
	// Sproutle
	.Sproutle = {
		name = "Sproutle", elements = []Element{.FLORA}, base_hp = 58, base_energy = 3, base_energy_max = 8, base_power = 1.0, base_defense = 1.0, base_speed = 7.0, base_satiety = 95, base_upkeep = 3,
		color = rl.Color{102, 188, 112, 255}, role = .STARTER, rarity = .COMMON,
		starter = []Move_Id{.Vine_Whip, .Vine_Whip, .Vine_Whip, .Vine_Whip, .Guard, .Guard, .Guard, .Thorn_Crash, .Hone, .Screech},
		learnset = []Learn_Entry{
			{.Vine_Whip, 1}, {.Guard, 1}, {.Hone, 1}, {.Screech, 1},
			{.Thorn_Crash, 2}, {.Leech, 3}, {.Bark_Skin, 4}, {.Bloom, 5},
			{.Iron_Skin, 5}, {.Flurry, 6}, {.Overgrowth, 6}, {.Mend, 7}, {.Fortify, 8},
		},
		move_pool = []Move_Id{.Vine_Whip, .Thorn_Crash, .Leech, .Bloom, .Overgrowth, .Bark_Skin, .Guard, .Hone, .Screech, .Jab, .Brace, .Body_Slam, .Fortify, .Flurry, .Mend, .Insight, .Crush, .Iron_Skin},
	},
	// Cave Bat
	.Cave_Bat = {
		name = "Cave Bat", elements = []Element{.NEUTRAL}, base_hp = 36, base_energy = 3, base_energy_max = 8, base_power = 0.75, base_defense = 0.0, base_speed = 13.0, base_satiety = 70, base_upkeep = 2,
		color = rl.Color{158, 146, 178, 255}, role = .WILD, rarity = .COMMON,
		starter = []Move_Id{.Tackle, .Tackle, .Tackle, .Tackle, .Guard, .Guard, .Guard, .Flurry, .Screech, .Hone},
		learnset = []Learn_Entry{
			{.Tackle, 1}, {.Guard, 1}, {.Hone, 1}, {.Screech, 1},
			{.Flurry, 2}, {.Crush, 3}, {.Insight, 4}, {.Mend, 4},
			{.Iron_Skin, 5}, {.Body_Slam, 5}, {.Fortify, 6},
		},
		move_pool = []Move_Id{.Tackle, .Flurry, .Crush, .Body_Slam, .Guard, .Fortify, .Hone, .Screech, .Iron_Skin, .Mend, .Insight, .Jab, .Brace},
	},
	// Magmite
	.Magmite = {
		name = "Magmite", elements = []Element{.EMBER}, base_hp = 42, base_energy = 3, base_energy_max = 8, base_power = 0.85, base_defense = 1.0, base_speed = 6.0, base_satiety = 90, base_upkeep = 3,
		color = rl.Color{214, 92, 62, 255}, role = .WILD, rarity = .COMMON,
		starter = []Move_Id{.Ember_Strike, .Ember_Strike, .Ember_Strike, .Ember_Strike, .Guard, .Guard, .Guard, .Cinder, .Flame_Burst, .Screech},
		learnset = []Learn_Entry{
			{.Ember_Strike, 1}, {.Guard, 1}, {.Screech, 1}, {.Cinder, 1},
			{.Flame_Burst, 2}, {.Ash_Screen, 2}, {.Inferno, 4}, {.Iron_Skin, 5},
			{.Mend, 5}, {.Fortify, 6}, {.Blaze, 7},
		},
		move_pool = []Move_Id{.Ember_Strike, .Cinder, .Flame_Burst, .Inferno, .Ash_Screen, .Blaze, .Tackle, .Body_Slam, .Guard, .Fortify, .Flurry, .Iron_Skin, .Mend, .Crush, .Jab, .Brace},
	},
	// Bubblet
	.Bubblet = {
		name = "Bubblet", elements = []Element{.AQUA}, base_hp = 44, base_energy = 3, base_energy_max = 8, base_power = 0.85, base_defense = 1.0, base_speed = 8.0, base_satiety = 95, base_upkeep = 2,
		color = rl.Color{72, 134, 214, 255}, role = .WILD, rarity = .COMMON,
		starter = []Move_Id{.Aqua_Jet, .Aqua_Jet, .Aqua_Jet, .Aqua_Jet, .Guard, .Guard, .Guard, .Bubble_Shield, .Tidal_Slam, .Undertow},
		learnset = []Learn_Entry{
			{.Aqua_Jet, 1}, {.Guard, 1}, {.Undertow, 1}, {.Bubble_Shield, 1},
			{.Tidal_Slam, 2}, {.Heal_Spring, 3}, {.Iron_Skin, 4}, {.Insight, 5},
			{.Torrent, 5}, {.Mend, 6}, {.Fortify, 7},
		},
		move_pool = []Move_Id{.Aqua_Jet, .Undertow, .Tidal_Slam, .Bubble_Shield, .Heal_Spring, .Torrent, .Tackle, .Guard, .Fortify, .Flurry, .Iron_Skin, .Insight, .Mend, .Jab, .Brace},
	},
	// Thornkit
	.Thornkit = {
		name = "Thornkit", elements = []Element{.FLORA}, base_hp = 40, base_energy = 3, base_energy_max = 8, base_power = 0.85, base_defense = 1.0, base_speed = 9.0, base_satiety = 85, base_upkeep = 2,
		color = rl.Color{88, 172, 98, 255}, role = .WILD, rarity = .COMMON,
		starter = []Move_Id{.Vine_Whip, .Vine_Whip, .Vine_Whip, .Vine_Whip, .Guard, .Guard, .Guard, .Leech, .Thorn_Crash, .Screech},
		learnset = []Learn_Entry{
			{.Vine_Whip, 1}, {.Guard, 1}, {.Screech, 1}, {.Leech, 1},
			{.Thorn_Crash, 2}, {.Bark_Skin, 2}, {.Bloom, 4}, {.Iron_Skin, 5},
			{.Overgrowth, 5}, {.Mend, 6}, {.Fortify, 7},
		},
		move_pool = []Move_Id{.Vine_Whip, .Leech, .Thorn_Crash, .Bark_Skin, .Bloom, .Overgrowth, .Tackle, .Guard, .Fortify, .Screech, .Iron_Skin, .Mend, .Crush, .Jab, .Brace},
	},
	// Elite Sentinel
	.Elite_Sentinel = {
		name = "Elite Sentinel", elements = []Element{.NEUTRAL}, base_hp = 66, base_energy = 4, base_energy_max = 10, base_power = 1.3, base_defense = 2.0, base_speed = 6.0, base_satiety = 140, base_upkeep = 5,
		color = rl.Color{206, 122, 62, 255}, role = .ELITE, rarity = .RARE,
		starter = []Move_Id{.Tackle, .Tackle, .Tackle, .Tackle, .Body_Slam, .Body_Slam, .Guard, .Guard, .Fortify, .Crush},
		learnset = []Learn_Entry{
			{.Tackle, 1}, {.Guard, 1}, {.Crush, 1}, {.Body_Slam, 1},
			{.Fortify, 2}, {.Iron_Skin, 3}, {.Screech, 3}, {.Flurry, 4},
			{.Hone, 4}, {.Mend, 5}, {.Insight, 5}, {.Blaze, 8},
		},
		move_pool = []Move_Id{.Tackle, .Body_Slam, .Crush, .Guard, .Fortify, .Iron_Skin, .Screech, .Flurry, .Hone, .Mend, .Insight, .Blaze, .Jab, .Brace},
	},
	// The Deep One
	.Deep_One = {
		name = "The Deep One", elements = []Element{.NEUTRAL}, base_hp = 120, base_energy = 4, base_energy_max = 10, base_power = 1.6, base_defense = 3.0, base_speed = 5.0, base_satiety = 220, base_upkeep = 8,
		color = rl.Color{150, 42, 62, 255}, role = .BOSS, rarity = .LEGENDARY,
		starter = []Move_Id{.Body_Slam, .Body_Slam, .Body_Slam, .Body_Slam, .Fortify, .Fortify, .Fortify, .Crush, .Iron_Skin, .Hone},
		learnset = []Learn_Entry{
			{.Body_Slam, 1}, {.Fortify, 1}, {.Crush, 1}, {.Iron_Skin, 1}, {.Hone, 1},
			{.Blaze, 2}, {.Screech, 2}, {.Torrent, 4}, {.Inferno, 4},
			{.Overgrowth, 5}, {.Insight, 6}, {.Mend, 7},
		},
		move_pool = []Move_Id{.Body_Slam, .Fortify, .Crush, .Iron_Skin, .Hone, .Blaze, .Screech, .Torrent, .Inferno, .Overgrowth, .Insight, .Mend, .Guard, .Jab, .Brace},
	},
	// Gloomling (content)
	.Gloomling = {
		name = "Gloomling", elements = []Element{.NEUTRAL, .FLORA}, base_hp = 50, base_energy = 3, base_energy_max = 8, base_power = 0.85, base_defense = 2.0, base_speed = 5.0, base_satiety = 110, base_upkeep = 3,
		color = rl.Color{120, 118, 140, 255}, role = .WILD, rarity = .UNCOMMON,
		starter = []Move_Id{.Tackle, .Tackle, .Tackle, .Tackle, .Guard, .Guard, .Weaken, .Body_Slam, .Fortify, .Exploit},
		learnset = []Learn_Entry{
			{.Tackle, 1}, {.Guard, 1}, {.Fortify, 1}, {.Exploit, 1},
			{.Crush, 2}, {.Body_Slam, 3}, {.Iron_Skin, 3}, {.Payback, 4}, {.Screech, 4},
			{.Mend, 5}, {.Followup, 6},
		},
		move_pool = []Move_Id{.Tackle, .Body_Slam, .Crush, .Guard, .Fortify, .Iron_Skin, .Screech, .Payback, .Exploit, .Followup, .Mend, .Insight, .Fang, .Brace, .Jab},
	},
	// Pyrelord (content)
	.Pyrelord = {
		name = "Pyrelord", elements = []Element{.EMBER}, base_hp = 54, base_energy = 3, base_energy_max = 8, base_power = 1.1, base_defense = 1.0, base_speed = 7.0, base_satiety = 110, base_upkeep = 4,
		color = rl.Color{232, 84, 48, 255}, role = .WILD, rarity = .UNCOMMON,
		starter = []Move_Id{.Ember_Strike, .Ember_Strike, .Ember_Strike, .Ember_Strike, .Guard, .Guard, .Guard, .Flame_Burst, .Combust, .Rampage},
		learnset = []Learn_Entry{
			{.Ember_Strike, 1}, {.Guard, 1}, {.Combust, 1},
			{.Flame_Burst, 2}, {.Cinder, 2}, {.Rampage, 3}, {.Inferno, 4}, {.Iron_Skin, 4},
			{.Screech, 5}, {.Followup, 5}, {.Blaze, 6}, {.Mend, 6},
		},
		move_pool = []Move_Id{.Ember_Strike, .Cinder, .Combust, .Flame_Burst, .Rampage, .Inferno, .Blaze, .Ash_Screen, .Guard, .Fortify, .Followup, .Exploit, .Iron_Skin, .Mend},
	},
	// Krakling (content)
	.Krakling = {
		name = "Krakling", elements = []Element{.AQUA, .EMBER}, base_hp = 56, base_energy = 3, base_energy_max = 8, base_power = 1.05, base_defense = 1.0, base_speed = 8.0, base_satiety = 110, base_upkeep = 3,
		color = rl.Color{60, 120, 210, 255}, role = .WILD, rarity = .RARE,
		starter = []Move_Id{.Aqua_Jet, .Aqua_Jet, .Aqua_Jet, .Aqua_Jet, .Guard, .Guard, .Guard, .Tidal_Slam, .Frost_Bite, .Bubble_Shield},
		learnset = []Learn_Entry{
			{.Aqua_Jet, 1}, {.Guard, 1}, {.Frost_Bite, 1},
			{.Bubble_Shield, 2}, {.Tidal_Slam, 2}, {.Undertow, 3}, {.Iron_Skin, 4}, {.Heal_Spring, 4},
			{.Torrent, 5}, {.Followup, 5}, {.Mend, 6}, {.Fortify, 6},
		},
		move_pool = []Move_Id{.Aqua_Jet, .Undertow, .Frost_Bite, .Bubble_Shield, .Tidal_Slam, .Heal_Spring, .Torrent, .Guard, .Fortify, .Followup, .Insight, .Iron_Skin, .Mend},
	},
	// Swampbeast (content)
	.Swampbeast = {
		name = "Swampbeast", elements = []Element{.FLORA, .AQUA}, base_hp = 60, base_energy = 3, base_energy_max = 8, base_power = 1.05, base_defense = 2.0, base_speed = 5.0, base_satiety = 120, base_upkeep = 4,
		color = rl.Color{74, 158, 84, 255}, role = .WILD, rarity = .UNCOMMON,
		starter = []Move_Id{.Vine_Whip, .Vine_Whip, .Vine_Whip, .Vine_Whip, .Guard, .Guard, .Guard, .Thorn_Crash, .Lash, .Bloom},
		learnset = []Learn_Entry{
			{.Vine_Whip, 1}, {.Guard, 1}, {.Lash, 1},
			{.Bloom, 2}, {.Thorn_Crash, 2}, {.Leech, 3}, {.Bark_Skin, 3}, {.Iron_Skin, 4},
			{.Overgrowth, 5}, {.Followup, 5}, {.Mend, 6}, {.Fortify, 6},
		},
		move_pool = []Move_Id{.Vine_Whip, .Lash, .Leech, .Thorn_Crash, .Bloom, .Overgrowth, .Bark_Skin, .Guard, .Fortify, .Followup, .Screech, .Iron_Skin, .Mend, .Crush},
	},
	// Wispling (content): fast support, fragile
	.Wispling = {
		name = "Wispling", elements = []Element{.NEUTRAL}, base_hp = 44, base_energy = 3, base_energy_max = 8, base_power = 0.95, base_defense = 0.5, base_speed = 11.5, base_satiety = 90, base_upkeep = 2,
		color = rl.Color{150, 170, 200, 255}, role = .WILD, rarity = .UNCOMMON,
		starter = []Move_Id{.Jab, .Jab, .Jab, .Jab, .Guard, .Guard, .Disarm, .Flurry, .Feint, .Warcry},
		learnset = []Learn_Entry{
			{.Jab, 1}, {.Guard, 1}, {.Feint, 1}, {.Warcry, 1},
			{.Flurry, 2}, {.Followup, 2}, {.Insight, 3}, {.Gnaw, 4},
			{.Twin_Fangs, 5}, {.Exploit, 5}, {.Mend, 6}, {.Second_Wind, 6},
		},
		move_pool = []Move_Id{.Jab, .Feint, .Warcry, .Flurry, .Followup, .Gnaw, .Twin_Fangs, .Exploit, .Payback, .Second_Wind, .Insight, .Mend, .Brace, .Guard, .Fang},
	},
	// Cindermaw (content): glass cannon
	.Cindermaw = {
		name = "Cindermaw", elements = []Element{.EMBER}, base_hp = 48, base_energy = 3, base_energy_max = 8, base_power = 1.25, base_defense = 0.5, base_speed = 6.5, base_satiety = 100, base_upkeep = 4,
		color = rl.Color{240, 70, 40, 255}, role = .WILD, rarity = .RARE,
		starter = []Move_Id{.Ember_Strike, .Ember_Strike, .Ember_Strike, .Ember_Strike, .Guard, .Guard, .Guard, .Flare, .Combust, .Rampage},
		learnset = []Learn_Entry{
			{.Ember_Strike, 1}, {.Guard, 1}, {.Flare, 1},
			{.Combust, 2}, {.Cinder, 2}, {.Rampage, 3}, {.Inferno, 4}, {.Twin_Fangs, 5},
			{.Exploit, 5}, {.Blaze, 6}, {.Mend, 6},
		},
		move_pool = []Move_Id{.Ember_Strike, .Flare, .Cinder, .Combust, .Rampage, .Inferno, .Blaze, .Ash_Screen, .Twin_Fangs, .Exploit, .Followup, .Guard, .Mend},
	},
	// Rimescale (content): tanky water
	.Rimescale = {
		name = "Rimescale", elements = []Element{.AQUA}, base_hp = 64, base_energy = 3, base_energy_max = 8, base_power = 0.95, base_defense = 2.5, base_speed = 5.5, base_satiety = 130, base_upkeep = 4,
		color = rl.Color{70, 150, 220, 255}, role = .WILD, rarity = .UNCOMMON,
		starter = []Move_Id{.Aqua_Jet, .Aqua_Jet, .Aqua_Jet, .Aqua_Jet, .Guard, .Guard, .Guard, .Frost_Bite, .Bubble_Shield, .Tidecall},
		learnset = []Learn_Entry{
			{.Aqua_Jet, 1}, {.Guard, 1}, {.Frost_Bite, 1}, {.Bubble_Shield, 1},
			{.Tidecall, 2}, {.Tidal_Slam, 2}, {.Undertow, 3}, {.Iron_Skin, 4},
			{.Heal_Spring, 4}, {.Torrent, 5}, {.Regrowth, 6}, {.Mend, 6},
		},
		move_pool = []Move_Id{.Aqua_Jet, .Frost_Bite, .Bubble_Shield, .Tidecall, .Undertow, .Tidal_Slam, .Heal_Spring, .Torrent, .Guard, .Fortify, .Iron_Skin, .Regrowth, .Mend, .Second_Wind},
	},
	// Mosshide (content): balanced flora
	.Mosshide = {
		name = "Mosshide", elements = []Element{.FLORA}, base_hp = 62, base_energy = 3, base_energy_max = 8, base_power = 1.05, base_defense = 1.5, base_speed = 7.5, base_satiety = 125, base_upkeep = 4,
		color = rl.Color{96, 170, 88, 255}, role = .WILD, rarity = .UNCOMMON,
		starter = []Move_Id{.Vine_Whip, .Vine_Whip, .Vine_Whip, .Vine_Whip, .Guard, .Guard, .Guard, .Bramble, .Lash, .Bloom},
		learnset = []Learn_Entry{
			{.Vine_Whip, 1}, {.Guard, 1}, {.Bramble, 1}, {.Lash, 1},
			{.Bloom, 2}, {.Leech, 2}, {.Thorn_Crash, 3}, {.Bark_Skin, 4},
			{.Iron_Skin, 4}, {.Overgrowth, 5}, {.Regrowth, 5}, {.Mend, 6},
		},
		move_pool = []Move_Id{.Vine_Whip, .Bramble, .Lash, .Leech, .Bloom, .Thorn_Crash, .Overgrowth, .Bark_Skin, .Guard, .Fortify, .Regrowth, .Iron_Skin, .Mend, .Screech},
	},
	// Emberbloom (dual Ember/Flora)
	.Emberbloom = {
		name = "Emberbloom", elements = []Element{.EMBER, .FLORA}, base_hp = 56, base_energy = 3, base_energy_max = 8, base_power = 1.15, base_defense = 1.0, base_speed = 6.0, base_satiety = 115, base_upkeep = 4,
		color = rl.Color{206, 120, 92, 255}, role = .WILD, rarity = .RARE,
		starter = []Move_Id{.Ember_Strike, .Ember_Strike, .Ember_Strike, .Ember_Strike, .Guard, .Guard, .Guard, .Flame_Burst, .Vine_Whip, .Bramble},
		learnset = []Learn_Entry{
			{.Ember_Strike, 1}, {.Guard, 1}, {.Bramble, 1},
			{.Flame_Burst, 2}, {.Cinder, 2}, {.Vine_Whip, 3}, {.Combust, 4},
			{.Inferno, 5}, {.Overgrowth, 5}, {.Rampage, 6}, {.Mend, 6},
		},
		move_pool = []Move_Id{.Ember_Strike, .Cinder, .Combust, .Flame_Burst, .Rampage, .Inferno, .Vine_Whip, .Bramble, .Leech, .Overgrowth, .Guard, .Fortify, .Exploit, .Mend},
	},
	// Bogfang (dual Aqua/Neutral)
	.Bogfang = {
		name = "Bogfang", elements = []Element{.AQUA, .NEUTRAL}, base_hp = 60, base_energy = 3, base_energy_max = 8, base_power = 0.95, base_defense = 2.0, base_speed = 6.0, base_satiety = 120, base_upkeep = 4,
		color = rl.Color{78, 124, 124, 255}, role = .WILD, rarity = .UNCOMMON,
		starter = []Move_Id{.Aqua_Jet, .Aqua_Jet, .Aqua_Jet, .Aqua_Jet, .Guard, .Guard, .Weaken, .Undertow, .Fang, .Fortify},
		learnset = []Learn_Entry{
			{.Aqua_Jet, 1}, {.Guard, 1}, {.Undertow, 1}, {.Fang, 1},
			{.Tidal_Slam, 2}, {.Fortify, 2}, {.Iron_Skin, 3}, {.Frost_Bite, 4},
			{.Crush, 4}, {.Torrent, 5}, {.Mend, 5}, {.Payback, 6},
		},
		move_pool = []Move_Id{.Aqua_Jet, .Undertow, .Frost_Bite, .Tidal_Slam, .Torrent, .Fang, .Crush, .Body_Slam, .Guard, .Fortify, .Iron_Skin, .Payback, .Mend, .Brace},
	},
	// Cinderwing (dual Ember/Neutral)
	.Cinderwing = {
		name = "Cinderwing", elements = []Element{.EMBER, .NEUTRAL}, base_hp = 46, base_energy = 3, base_energy_max = 8, base_power = 1.15, base_defense = 0.5, base_speed = 10.5, base_satiety = 95, base_upkeep = 3,
		color = rl.Color{232, 116, 66, 255}, role = .WILD, rarity = .RARE,
		starter = []Move_Id{.Ember_Strike, .Ember_Strike, .Ember_Strike, .Ember_Strike, .Guard, .Guard, .Guard, .Flare, .Followup, .Feint},
		learnset = []Learn_Entry{
			{.Ember_Strike, 1}, {.Guard, 1}, {.Flare, 1}, {.Feint, 1},
			{.Followup, 2}, {.Flurry, 2}, {.Cinder, 3}, {.Twin_Fangs, 4},
			{.Rampage, 5}, {.Exploit, 5}, {.Blaze, 6}, {.Mend, 6},
		},
		move_pool = []Move_Id{.Ember_Strike, .Flare, .Cinder, .Combust, .Rampage, .Blaze, .Followup, .Feint, .Flurry, .Twin_Fangs, .Exploit, .Guard, .Mend, .Insight},
	},
	// Frostmoss (dual Aqua/Flora)
	.Frostmoss = {
		name = "Frostmoss", elements = []Element{.AQUA, .FLORA}, base_hp = 66, base_energy = 3, base_energy_max = 8, base_power = 0.95, base_defense = 2.5, base_speed = 5.0, base_satiety = 130, base_upkeep = 4,
		color = rl.Color{96, 168, 168, 255}, role = .WILD, rarity = .RARE,
		starter = []Move_Id{.Aqua_Jet, .Aqua_Jet, .Aqua_Jet, .Aqua_Jet, .Guard, .Guard, .Guard, .Frost_Bite, .Bramble, .Bloom},
		learnset = []Learn_Entry{
			{.Aqua_Jet, 1}, {.Guard, 1}, {.Frost_Bite, 1}, {.Bramble, 1},
			{.Bloom, 2}, {.Bubble_Shield, 2}, {.Leech, 3}, {.Undertow, 3},
			{.Iron_Skin, 4}, {.Regrowth, 5}, {.Tidal_Slam, 5}, {.Mend, 6},
		},
		move_pool = []Move_Id{.Aqua_Jet, .Frost_Bite, .Undertow, .Bubble_Shield, .Tidecall, .Bloom, .Bramble, .Leech, .Regrowth, .Heal_Spring, .Guard, .Fortify, .Iron_Skin, .Mend},
	},
	// Frostfang (Ice)
	.Frostfang = {
		name = "Frostfang", elements = []Element{.ICE}, base_hp = 52, base_energy = 3, base_energy_max = 8, base_power = 1.05, base_defense = 1.5, base_speed = 7.0, base_satiety = 110, base_upkeep = 3,
		color = rl.Color{150, 216, 236, 255}, role = .WILD, rarity = .UNCOMMON,
		starter = []Move_Id{.Frost_Shard, .Frost_Shard, .Frost_Shard, .Frost_Shard, .Guard, .Guard, .Guard, .Glacier_Slam, .Iron_Skin, .Mend},
		learnset = []Learn_Entry{
			{.Frost_Shard, 1}, {.Guard, 1}, {.Iron_Skin, 1}, {.Glacier_Slam, 2},
			{.Fortify, 3}, {.Frost_Bite, 4}, {.Followup, 4}, {.Mend, 4},
			{.Second_Wind, 5}, {.Insight, 5}, {.Regrowth, 6},
		},
		move_pool = []Move_Id{.Frost_Shard, .Glacier_Slam, .Frost_Bite, .Guard, .Fortify, .Iron_Skin, .Followup, .Second_Wind, .Mend, .Insight, .Regrowth, .Brace, .Exploit},
	},
	// Stonepaw (Ground)
	.Stonepaw = {
		name = "Stonepaw", elements = []Element{.GROUND}, base_hp = 62, base_energy = 3, base_energy_max = 8, base_power = 1.05, base_defense = 2.5, base_speed = 4.5, base_satiety = 125, base_upkeep = 4,
		color = rl.Color{160, 128, 84, 255}, role = .WILD, rarity = .UNCOMMON,
		starter = []Move_Id{.Rock_Toss, .Rock_Toss, .Rock_Toss, .Rock_Toss, .Guard, .Guard, .Sunder, .Quake, .Fortify, .Iron_Skin},
		learnset = []Learn_Entry{
			{.Rock_Toss, 1}, {.Guard, 1}, {.Fortify, 1}, {.Quake, 2}, {.Iron_Skin, 2},
			{.Crush, 3}, {.Body_Slam, 4}, {.Payback, 4}, {.Mend, 5}, {.Bramble, 5}, {.Second_Wind, 6},
		},
		move_pool = []Move_Id{.Rock_Toss, .Quake, .Crush, .Body_Slam, .Guard, .Fortify, .Iron_Skin, .Payback, .Bramble, .Mend, .Second_Wind, .Brace, .Fang},
	},
	// Sparkit (Electric)
	.Sparkit = {
		name = "Sparkit", elements = []Element{.ELECTRIC}, base_hp = 46, base_energy = 3, base_energy_max = 8, base_power = 1.1, base_defense = 0.5, base_speed = 11.0, base_satiety = 95, base_upkeep = 3,
		color = rl.Color{242, 214, 70, 255}, role = .WILD, rarity = .UNCOMMON,
		starter = []Move_Id{.Spark, .Spark, .Spark, .Spark, .Guard, .Guard, .Guard, .Thunderbolt, .Feint, .Followup},
		learnset = []Learn_Entry{
			{.Spark, 1}, {.Guard, 1}, {.Feint, 1}, {.Followup, 2}, {.Flurry, 2},
			{.Hone, 3}, {.Thunderbolt, 4}, {.Twin_Fangs, 4}, {.Exploit, 5}, {.Insight, 5}, {.Mend, 6},
		},
		move_pool = []Move_Id{.Spark, .Thunderbolt, .Followup, .Flurry, .Twin_Fangs, .Exploit, .Feint, .Insight, .Hone, .Guard, .Mend, .Brace, .Fang},
	},
	// Galebeast (Air)
	.Galebeast = {
		name = "Galebeast", elements = []Element{.AIR}, base_hp = 50, base_energy = 3, base_energy_max = 8, base_power = 0.95, base_defense = 1.0, base_speed = 12.0, base_satiety = 100, base_upkeep = 3,
		color = rl.Color{206, 214, 230, 255}, role = .WILD, rarity = .UNCOMMON,
		starter = []Move_Id{.Gust, .Gust, .Gust, .Gust, .Guard, .Guard, .Guard, .Cyclone, .Feint, .Warcry},
		learnset = []Learn_Entry{
			{.Gust, 1}, {.Guard, 1}, {.Feint, 1}, {.Warcry, 1}, {.Followup, 2},
			{.Cyclone, 4}, {.Twin_Fangs, 4}, {.Exploit, 5}, {.Insight, 5}, {.Second_Wind, 5}, {.Mend, 6},
		},
		move_pool = []Move_Id{.Gust, .Cyclone, .Followup, .Flurry, .Twin_Fangs, .Feint, .Warcry, .Second_Wind, .Insight, .Exploit, .Guard, .Mend, .Brace},
	},
	// Venomtail (Poison)
	.Venomtail = {
		name = "Venomtail", elements = []Element{.POISON}, base_hp = 54, base_energy = 3, base_energy_max = 8, base_power = 1.05, base_defense = 1.0, base_speed = 8.0, base_satiety = 105, base_upkeep = 3,
		color = rl.Color{170, 84, 186, 255}, role = .WILD, rarity = .RARE,
		starter = []Move_Id{.Toxic_Bite, .Toxic_Bite, .Toxic_Bite, .Toxic_Bite, .Guard, .Guard, .Corrode, .Venom, .Screech, .Hone},
		learnset = []Learn_Entry{
			{.Toxic_Bite, 1}, {.Guard, 1}, {.Screech, 1}, {.Hone, 1}, {.Venom, 2},
			{.Crush, 3}, {.Leech, 3}, {.Followup, 4}, {.Exploit, 5}, {.Mend, 5}, {.Second_Wind, 6},
		},
		move_pool = []Move_Id{.Toxic_Bite, .Venom, .Crush, .Leech, .Screech, .Hone, .Followup, .Exploit, .Payback, .Guard, .Fortify, .Mend, .Second_Wind},
	},
	// Blizzard (dual Ice/Air)
	.Blizzard = {
		name = "Blizzard", elements = []Element{.ICE, .AIR}, base_hp = 58, base_energy = 3, base_energy_max = 8, base_power = 1.1, base_defense = 1.5, base_speed = 9.0, base_satiety = 115, base_upkeep = 4,
		color = rl.Color{176, 210, 240, 255}, role = .WILD, rarity = .EPIC,
		starter = []Move_Id{.Frost_Shard, .Frost_Shard, .Frost_Shard, .Frost_Shard, .Guard, .Guard, .Guard, .Glacier_Slam, .Gust, .Cyclone},
		learnset = []Learn_Entry{
			{.Frost_Shard, 1}, {.Guard, 1}, {.Gust, 1}, {.Glacier_Slam, 2},
			{.Cyclone, 3}, {.Followup, 3}, {.Iron_Skin, 4}, {.Second_Wind, 5},
			{.Twin_Fangs, 5}, {.Mend, 6},
		},
		move_pool = []Move_Id{.Frost_Shard, .Glacier_Slam, .Gust, .Cyclone, .Frost_Bite, .Followup, .Twin_Fangs, .Iron_Skin, .Second_Wind, .Guard, .Fortify, .Mend, .Insight},
	},

	// --- Bosses (Phase 25) ---------------------------------------------------
	// Unique, very powerful, and built around a synergy combo. They spawn with
	// a pack of cronies and roam as a unit of six.
	.Boss_Leviathan = {
		name = "The Leviathan", elements = []Element{.AQUA}, base_hp = 210, base_energy = 4, base_energy_max = 12, base_power = 1.8, base_defense = 3.6, base_speed = 6.0, base_satiety = 280, base_upkeep = 12,
		color = rl.Color{38, 96, 168, 255}, role = .BOSS, rarity = .LEGENDARY,
		// Combo: Undertow marks Vulnerable, then Torrent / Tsunami cash it in.
		starter = []Move_Id{.Undertow, .Undertow, .Torrent, .Torrent, .Tidal_Slam, .Heal_Spring, .Bubble_Shield, .Rejuvenate, .Tsunami, .Torrent},
		learnset = []Learn_Entry{
			{.Undertow, 1}, {.Torrent, 1}, {.Tidal_Slam, 1}, {.Heal_Spring, 1}, {.Bubble_Shield, 1},
			{.Rejuvenate, 1}, {.Tsunami, 2}, {.Aqua_Jet, 2}, {.Sunder, 3}, {.Regrowth, 4}, {.Insight, 5},
		},
		move_pool = []Move_Id{.Undertow, .Torrent, .Tidal_Slam, .Heal_Spring, .Bubble_Shield, .Rejuvenate, .Tsunami, .Aqua_Jet, .Sunder, .Regrowth, .Insight, .Fortify, .Mend},
	},
	.Boss_Infernal = {
		name = "The Infernal", elements = []Element{.EMBER}, base_hp = 170, base_energy = 4, base_energy_max = 12, base_power = 2.2, base_defense = 2.6, base_speed = 9.0, base_satiety = 240, base_upkeep = 11,
		color = rl.Color{214, 74, 44, 255}, role = .BOSS, rarity = .LEGENDARY,
		// Combo: Cinder marks Vulnerable, Hone buffs Strength, Rampage/Combust finish.
		starter = []Move_Id{.Cinder, .Cinder, .Blaze, .Blaze, .Combust, .Combust, .Hone, .Immolate, .Wildfire, .Rampage},
		learnset = []Learn_Entry{
			{.Cinder, 1}, {.Blaze, 1}, {.Combust, 1}, {.Hone, 1}, {.Immolate, 1}, {.Wildfire, 1},
			{.Rampage, 2}, {.Inferno, 2}, {.Sunder, 3}, {.Warcry, 4}, {.Mend, 5},
		},
		move_pool = []Move_Id{.Cinder, .Blaze, .Combust, .Hone, .Immolate, .Wildfire, .Rampage, .Inferno, .Sunder, .Warcry, .Mend, .Fortify, .Ash_Screen},
	},
	.Boss_Titan = {
		name = "The Titan", elements = []Element{.GROUND}, base_hp = 280, base_energy = 4, base_energy_max = 12, base_power = 1.7, base_defense = 5.2, base_speed = 4.0, base_satiety = 320, base_upkeep = 14,
		color = rl.Color{146, 112, 66, 255}, role = .BOSS, rarity = .LEGENDARY,
		// Combo: Crush marks Vulnerable, then Cataclysm / Quake land; thorns punish.
		starter = []Move_Id{.Crush, .Crush, .Quake, .Quake, .Rock_Toss, .Fortify, .Iron_Skin, .Bramble_Armor, .Cataclysm, .Quake},
		learnset = []Learn_Entry{
			{.Crush, 1}, {.Quake, 1}, {.Rock_Toss, 1}, {.Fortify, 1}, {.Iron_Skin, 1}, {.Bramble_Armor, 1},
			{.Cataclysm, 2}, {.Body_Slam, 2}, {.Sunder, 3}, {.Regrowth, 4}, {.Screech, 5},
		},
		move_pool = []Move_Id{.Crush, .Quake, .Rock_Toss, .Fortify, .Iron_Skin, .Bramble_Armor, .Cataclysm, .Body_Slam, .Sunder, .Regrowth, .Screech, .Mend, .Warcry},
	},
	.Boss_Sovereign = {
		name = "The Sovereign", elements = []Element{.ELECTRIC, .AIR}, base_hp = 180, base_energy = 4, base_energy_max = 12, base_power = 1.9, base_defense = 3.0, base_speed = 13.0, base_satiety = 250, base_upkeep = 11,
		color = rl.Color{226, 196, 70, 255}, role = .BOSS, rarity = .LEGENDARY,
		// Combo: Static Shock / Paralyze lock you down, then Maelstrom / Thunderbolt.
		starter = []Move_Id{.Static_Shock, .Static_Shock, .Thunderbolt, .Thunderbolt, .Paralyze, .Cyclone, .Maelstrom, .Hone, .Gust, .Thunderbolt},
		learnset = []Learn_Entry{
			{.Static_Shock, 1}, {.Thunderbolt, 1}, {.Cyclone, 1}, {.Hone, 1}, {.Gust, 1}, {.Paralyze, 1},
			{.Maelstrom, 2}, {.Spark, 2}, {.Sunder, 3}, {.Followup, 4}, {.Insight, 5},
		},
		move_pool = []Move_Id{.Static_Shock, .Thunderbolt, .Cyclone, .Hone, .Gust, .Paralyze, .Maelstrom, .Spark, .Sunder, .Followup, .Insight, .Second_Wind, .Warcry},
	},
}

// Some wilds keep a lair; the rest are wanderers with no fixed home. Territorial
// species drift back toward their lair instead of diffusing across the map.
species_territorial :: proc(id: Species_Id) -> bool {
	#partial switch id {
	case .Cave_Bat, .Rimescale, .Pyrelord, .Stonepaw, .Deep_One, .Mosshide, .Bogfang, .Gloomling, .Cinderwing:
		return true
	case:
		return false
	}
	return false
}

STARTER_SPECIES := [?]Species_Id{.Emberling, .Tidepup, .Sproutle}

Creature :: struct {
	species:      Species_Id,
	name:         string,
	level:        int,
	xp:           int, // experience toward the next level (shared with the map)
	hp:           int,
	max_hp:       int,
	block:        int,
	vulnerable:   int,
	strength:     int,

	// Status effects (Phase 21). Damage/heal-over-time statuses tick once per
	// round and decay by 1; Thorns persists; Stun skips the creature's actions.
	poison:     int,
	burn:       int,
	regen:      int,
	thorns:     int,
	stun:       int,
	stun_round: int, // transient: round in which Stun was last consumed
	power:        f32, // permanent bonus damage from leveling
	defense:      f32, // permanent damage reduction from leveling
	defense_buff: f32, // temporary, from moves (resets each battle)
	defense_debuff: f32, // temporary defense shred from enemy moves (resets each battle)
	speed:        f32, // initiative
	speed_buff:   f32, // per-battle initiative bonus (resets each battle)
	energy:       f32, // current bank (carries over between turns)
	energy_regen: f32, // gained at the start of each turn
	energy_max:   f32, // cap on the bank

	ability: Ability, // species ability, rolled at spawn (Phase C)
	item:    Item,    // one item slot (Phase C)

	genes: [Gene]int, // per-stat genetic bonus 0-5 (Phase 8; see below)

	deck:       [dynamic]Move_Id, // persistent, owned by this creature
	draw_pile:  [dynamic]Move_Id, // per-battle
	hand:       [dynamic]Move_Id, // per-battle
	discard:    [dynamic]Move_Id, // per-battle
	played:     int,              // cards played this turn (combo synergy)

	// transient hit feedback (decays each frame, not saved)
	shake: f32,
	flash: f32,

	// true for monsters you own (relic stat bonuses apply to these only)
	player: bool,

	// short effect burst (heal/buff/debuff...): an expanding coloured ring
	fx_t:   f32,       // remaining time, counts down
	fx_dur: f32,       // total time (for interpolation)
	fx_col: rl.Color,  // burst colour
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

species_rarity :: proc(species: Species_Id) -> Rarity {
	return SPECIES[species].rarity
}

rarity_name :: proc(r: Rarity) -> cstring {
	switch r {
	case .COMMON:    return "Common"
	case .UNCOMMON:  return "Uncommon"
	case .RARE:      return "Rare"
	case .EPIC:      return "Epic"
	case .LEGENDARY: return "Legendary"
	}
	return "?"
}

rarity_color :: proc(r: Rarity) -> rl.Color {
	switch r {
	case .COMMON:    return rl.Color{185, 192, 205, 255}
	case .UNCOMMON:  return rl.Color{120, 220, 130, 255}
	case .RARE:      return rl.Color{110, 170, 250, 255}
	case .EPIC:      return rl.Color{200, 140, 250, 255}
	case .LEGENDARY: return rl.Color{250, 200, 90, 255}
	}
	return rl.Color{200, 200, 200, 255}
}

// Capture odds multiplier — rarer creatures are harder to catch.
rarity_catch_mult :: proc(r: Rarity) -> f32 {
	switch r {
	case .COMMON:    return 1.0
	case .UNCOMMON:  return 0.85
	case .RARE:      return 0.65
	case .EPIC:      return 0.45
	case .LEGENDARY: return 0.20
	}
	return 1.0
}

// Shop appearance weight — rarer creatures are offered less often.
rarity_weight :: proc(r: Rarity) -> int {
	switch r {
	case .COMMON:    return 100
	case .UNCOMMON:  return 55
	case .RARE:      return 26
	case .EPIC:      return 10
	case .LEGENDARY: return 3
	}
	return 100
}

// Recruit price before level scaling.
rarity_price :: proc(r: Rarity) -> int {
	switch r {
	case .COMMON:    return 25
	case .UNCOMMON:  return 45
	case .RARE:      return 80
	case .EPIC:      return 140
	case .LEGENDARY: return 240
	}
	return 25
}

// Kill loot multiplier.
rarity_loot_mult :: proc(r: Rarity) -> f32 {
	switch r {
	case .COMMON:    return 1.0
	case .UNCOMMON:  return 1.35
	case .RARE:      return 1.8
	case .EPIC:      return 2.5
	case .LEGENDARY: return 4.0
	}
	return 1.0
}

// Cost to recruit a monster of this species/level at a Trading Post.
recruit_price :: proc(species: Species_Id, level: int) -> int {
	base := rarity_price(species_rarity(species))
	return int(f32(base) * (1.0 + 0.25 * f32(level - 1)))
}

// Gold a defeated wild of this species/level is worth.
species_loot_gold :: proc(species: Species_Id, level: int) -> int {
	base := 5 + 3 * level
	return int(f32(base) * rarity_loot_mult(species_rarity(species)))
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

// ----------------------------------------------------------------------------
// Genetics (Phase 8)
//
// Every creature carries a 0-5 gene per stat. A gene is a percentage bonus on
// top of the species base, so 5 is a real prize and 0 is the plain baseline.
// Wilds, shop recruits and starters roll theirs; breeding averages two parents
// and nudges the result with a random roll (plus a rare mutation).
// ----------------------------------------------------------------------------

Gene :: enum { HP, POWER, DEFENSE, SPEED, ENERGY }

GENE_MAX           :: 5
GENE_BONUS         :: f32(0.05) // +5% to a stat's base per gene point
// Weights for a random roll: 0 common ... 5 very rare (out of 100).
@(rodata)
GENE_WEIGHTS := [GENE_MAX + 1]int{40, 28, 18, 9, 4, 1}

// A random gene value on the rarity curve.
gene_roll_random :: proc(rng: ^Rng) -> int {
	total := 0
	for w in GENE_WEIGHTS {
		total += w
	}
	roll := rng_below(rng, total)
	acc := 0
	for i in 0..<len(GENE_WEIGHTS) {
		acc += GENE_WEIGHTS[i]
		if roll < acc {
			return i
		}
	}
	return 0
}

genes_roll_random :: proc(rng: ^Rng) -> [Gene]int {
	g: [Gene]int
	for gene in Gene {
		g[gene] = gene_roll_random(rng)
	}
	return g
}

// The expected midpoint of two parents' gene (rounded up), ignoring the roll.
gene_breed_mid :: proc(a, b: int) -> int {
	return clamp((a + b + 1) / 2, 0, GENE_MAX)
}

// Breed one gene: average the parents, nudge by -1..+1.
gene_breed :: proc(a, b: int, rng: ^Rng) -> int {
	v := clamp(gene_breed_mid(a, b) + rng_range(rng, -1, 2), 0, GENE_MAX)
	return v
}

genes_breed :: proc(a, b: [Gene]int, rng: ^Rng) -> [Gene]int {
	g: [Gene]int
	for gene in Gene {
		g[gene] = gene_breed(a[gene], b[gene], rng)
	}
	return g
}

// A compact "HP 3  Pow 2  Def 1  Spd 4  En 0" label.
genes_label :: proc(g: [Gene]int) -> cstring {
	return fmt.ctprintf("HP %d  Pow %d  Def %d  Spd %d  En %d",
		g[.HP], g[.POWER], g[.DEFENSE], g[.SPEED], g[.ENERGY])
}

// Total gene points, for a quick "quality" read on a monster.
genes_total :: proc(g: [Gene]int) -> int {
	sum := 0
	for gene in Gene {
		sum += g[gene]
	}
	return sum
}

// Energy is the one pool shared by map movement and card play, so it must stay a
// real constraint at every level. Unlike HP/power/defence/speed (linear in
// level), energy grows on a **logarithmic** curve — slow enough that a
// high-level monster doesn't out-regenerate its hand, with no hard cap. This is
// only computed when stats are recomputed (level-up / gear), never per frame.
energy_scale :: proc(level: int) -> f32 {
	return 1.0 + 0.12 * math.ln(f32(max(level, 1)))
}

// Energy regen is deliberately halved: it is the one pool shared by map movement
// and card play, and it was too generous — a monster could cross the map in a
// turn and still play a full hand.
ENERGY_REGEN_FACTOR :: f32(0.5)

creature_stats_for_level :: proc(species_idx: Species_Id, level: int) -> (max_hp: int, power, defense, speed, energy_regen, energy_max: f32) {
	sp := SPECIES[species_idx]
	scale := level_scale(level)
	max_hp = int(f32(sp.base_hp) * scale)
	power = sp.base_power * scale
	defense = sp.base_defense * scale
	speed = sp.base_speed * scale
	// Energy is continuous (no rounding), so costs can be any value the
	// designer wants. Regen is the per-turn income; max is the bank cap. Both
	// grow on the same slow curve, so the bank stays well above the regen and
	// saving for a premium card pays off.
	es := energy_scale(level)
	energy_regen = f32(sp.base_energy) * es * ENERGY_REGEN_FACTOR
	energy_max = f32(sp.base_energy_max) * es
	return
}

// Builds a creature with explicit genes. `rng` only rolls the ability (pass nil
// for none). Stats are computed from species + level + genes.
creature_make_genes :: proc(species_idx: Species_Id, level: int, name: string, genes: [Gene]int, rng: ^Rng = nil) -> Creature {
	sp := SPECIES[species_idx]

	deck := make([dynamic]Move_Id, 0)
	for m in sp.starter {
		append(&deck, m)
	}

	ability := Ability.NONE
	if rng != nil {
		ability = creature_roll_ability(species_idx, rng)
	}

	c := Creature{
		species   = species_idx,
		name      = name,
		level     = level,
		energy    = 0,
		ability   = ability,
		item      = .NONE,
		genes     = genes,
		deck      = deck,
		draw_pile = make([dynamic]Move_Id, 0),
		hand      = make([dynamic]Move_Id, 0),
		discard   = make([dynamic]Move_Id, 0),
	}
	creature_recompute_stats(&c)
	c.hp = c.max_hp
	return c
}

creature_make :: proc(species_idx: Species_Id, level: int, name: string, rng: ^Rng = nil) -> Creature {
	genes: [Gene]int
	if rng != nil {
		genes = genes_roll_random(rng)
	}
	return creature_make_genes(species_idx, level, name, genes, rng)
}

// A status card that fits an element, for wild decks (and only wilds — the
// player curates their own deck through rewards). DoT/regen are preferred over
// Stun so a wild can't lock the player down.
thematic_status_move :: proc(el: Element) -> (Move_Id, bool) {
	switch el {
	case .EMBER:    return .Ember_Coil, true
	case .POISON:   return .Toxic_Cloud, true
	case .FLORA:    return .Bramble_Armor, true
	case .ELECTRIC: return .Static_Shock, true
	case .AQUA:     return .Rejuvenate, true
	case .NEUTRAL, .ICE, .GROUND, .AIR: return .Tackle, false
	}
	return .Tackle, false
}

// Wilds fight with a real deck: their learnset moves up to their level, a
// thematic status card once they're tough enough, then starter basics to fill.
// Player creatures keep their curated starter deck — this is wilds only (called
// from `spawn_wild_at`).
WILD_DECK_MAX :: 12
enrich_wild_deck :: proc(c: ^Creature) {
	sp := SPECIES[c.species]
	clear(&c.deck)
	// A thematic status card first (higher-level wilds), so it's never crowded
	// out by the learnset.
	if c.level >= 8 {
		if id, ok := thematic_status_move(creature_element(c)); ok {
			append(&c.deck, id)
		}
	}
	// Learnset moves up to the wild's level — the cards that scale with it.
	for entry in sp.learnset {
		if entry.level > c.level || len(c.deck) >= WILD_DECK_MAX {
			continue
		}
		dup := false
		for m in c.deck {
			if m == entry.move {
				dup = true
				break
			}
		}
		if !dup {
			append(&c.deck, entry.move)
		}
	}
	// Fill the rest with starter basics so the deck is never too thin.
	for m in sp.starter {
		if len(c.deck) >= WILD_DECK_MAX {
			break
		}
		append(&c.deck, m)
	}
}

// Recompute stored stats from (species, level), genetic bonuses, and the
// equipped item's stat bonuses. Call after leveling up or changing the item.
creature_recompute_stats :: proc(c: ^Creature) {
	max_hp, power, defense, speed, energy_regen, energy_max := creature_stats_for_level(c.species, c.level)
	// Genetics scale the species base before items are added.
	max_hp = int(f32(max_hp) * (1.0 + GENE_BONUS * f32(c.genes[.HP])))
	power *= 1.0 + GENE_BONUS * f32(c.genes[.POWER])
	defense *= 1.0 + GENE_BONUS * f32(c.genes[.DEFENSE])
	speed *= 1.0 + GENE_BONUS * f32(c.genes[.SPEED])
	ge := 1.0 + GENE_BONUS * f32(c.genes[.ENERGY])
	energy_regen *= ge
	energy_max *= ge

	it := ITEM_DATA[c.item]
	max_hp += int(f32(max_hp) * it.hp_pct)
	power += it.power
	defense += it.defense
	speed += it.speed
	energy_regen += it.energy_regen
	energy_max += it.energy_max

	// Colony relics (Phase 25): stackable passives for player monsters only.
	// The state global is synced from the colony whenever relics change.
	if c.player {
		max_hp = int(f32(max_hp) * relic_state.hp)
		power *= relic_state.power
		speed *= relic_state.speed
		energy_regen += relic_state.energy_regen
	}

	c.max_hp = max_hp
	c.power = power
	c.defense = defense
	c.speed = speed
	c.energy_regen = energy_regen
	c.energy_max = energy_max
	if c.hp > c.max_hp {
		c.hp = c.max_hp
	}
}

// Equip an item, recomputing stats and granting any gained max HP.
creature_equip_item :: proc(c: ^Creature, item: Item) {
	old_max := c.max_hp
	c.item = item
	creature_recompute_stats(c)
	if c.max_hp > old_max {
		c.hp = min(c.hp + (c.max_hp - old_max), c.max_hp)
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

// Level up: recompute scaled stats and automatically learn any learnset moves
// whose level is now reached. Reward picks happen separately (from move_pool).
// Levels the creature up and returns the learnset moves newly available at this
// level that it doesn't already know (up to MAX_CHOICE_OPTIONS). Learning is the
// caller's job, so several options can become a player choice.
creature_level_up :: proc(c: ^Creature) -> (opts: [MAX_CHOICE_OPTIONS]Move_Id, n: int) {
	old_max := c.max_hp
	c.level += 1
	creature_recompute_stats(c)
	if c.hp > 0 {
		// Leveling heals — but never revives a fainted monster.
		c.hp = min(c.hp + (c.max_hp - old_max) + c.max_hp / 8, c.max_hp)
	}

	for entry in SPECIES[c.species].learnset {
		if entry.level != c.level || creature_knows(c, entry.move) {
			continue
		}
		dup := false
		for k in 0..<n {
			if opts[k] == entry.move {
				dup = true
				break
			}
		}
		if !dup && n < MAX_CHOICE_OPTIONS {
			opts[n] = entry.move
			n += 1
		}
	}
	return
}

// Clear per-battle state so temporary buffs/debuffs don't carry over. Energy is
// shared with the colony map, so it is NOT reset here.
creature_reset_battle_state :: proc(c: ^Creature) {
	c.block = 0
	c.strength = 0
	c.vulnerable = 0
	c.defense_buff = 0
	c.defense_debuff = 0
	c.speed_buff = 0
	c.poison = 0
	c.burn = 0
	c.regen = 0
	c.thorns = 0
	c.stun = 0
	c.stun_round = 0
	c.shake = 0
	c.flash = 0
	c.fx_t = 0
}

// Start a short visual burst (an expanding coloured ring) on a creature. Used
// for heals, blocks, buffs and debuffs so their effects are visible on the art.
creature_burst :: proc(c: ^Creature, col: rl.Color, dur: f32 = 0.55) {
	c.fx_col = col
	c.fx_dur = dur
	c.fx_t = dur
}
