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
	// Starter lines: stage 1 -> 2 -> 3 (stage 3 gains a secondary type).
	Emberling,
	Cinderscale,
	Magmalisk,
	Tidepup,
	Ripfin,
	Tidewyrm,
	Sproutle,
	Thornbud,
	Blightbloom,
	Grubling,
	Vesperling,
	Rockmite,
	Dustwing,
	Thornkit,
	Mossling,
	Bloomcap,
	Barkhound,
	Bubblet,
	Ripjaw,
	Tidecaller,
	Abyssal_Fry,
	Gloomling,
	Crypt_Rat,
	Wispling,
	Sporeling,
	Capmaw,
	Sentinel,
	Relic_Hound,
	Hexling,
	Snowpup,
	Frostmaw,
	Glacierling,
	Vinecat,
	Venomtail,
	Pouncer,
	Magmite,
	Cinderwing,
	Slagbeast,
	Sandfang,
	Sparkit,
	Crystalfin,
	Rotshell,
	Nightwing,
	Thornmaw,
	Bubblord,
	Frostfang,
	Magmaw,
	Sporelord,
	Voltail,
	// Bosses.
	Deep_One,
	Boss_Leviathan,
	Boss_Infernal,
	Boss_Titan,
	Boss_Sovereign,
	// Strong wilds (Phase 61): the elite tier between the evolved lines and the
	// bosses, so the deep Arena floors have more than five faces to field.
	Ashfang,
	Stormwing,
	Bogmaw,
	Dreadhorn,
	Rimewarden,
	Gravemaw,
}

Species :: struct {
	name:         string,
	desc:         string, // one-line encyclopedia blurb
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
	// Evolution: at `evolve_level`, the creature becomes `evolves_to` (0 = none).
	evolves_to:   Species_Id,
	evolve_level: int,
	starter:      []Move_Id,
	learnset:     []Learn_Entry,
	move_pool:    []Move_Id,
}

SPECIES := [Species_Id]Species{
	.Emberling = {
		name = "Emberling", desc = "A coal-skinned lizard hatchling. Its tail-flame dims when it is scared.", elements = []Element{.EMBER}, base_hp = 60, base_energy = 3, base_energy_max = 8, base_power = 1.0, base_defense = 1.0, base_speed = 9.0, base_satiety = 100, base_upkeep = 3,
		color = rl.Color{226, 96, 62, 255}, role = .STARTER, rarity = .COMMON,
		evolves_to = .Cinderscale, evolve_level = 12,
		starter = []Move_Id{.Ember_Strike, .Ember_Strike, .Ember_Strike, .Ember_Strike, .Guard, .Guard, .Guard, .Hone, .Mark, .Flame_Burst},
		learnset = []Learn_Entry{
			{.Warcry, 2}, {.Ember_Coil, 2}, {.Blood_Pact, 2},
			{.Followup, 4}, {.Mark, 4}, {.Reckoning, 4},
			{.Bash, 6}, {.Expose, 6}, {.Cull, 6},
			{.Cleave, 8}, {.Sunder, 8}, {.Fuse, 8},
			{.Hone, 10}, {.Haze, 10}, {.Overclock, 10},
		},
		move_pool = []Move_Id{.Ember_Strike, .Flame_Burst, .Ember_Coil, .Warcry, .Followup, .Cleave, .Bash, .Sunder, .Mark, .Expose, .Blood_Pact, .Reckoning, .Cull, .Fuse, .Guard, .Hone, .Mark, .Iron_Skin, .Slash, .Metronome, .Firestorm},
	},
	.Cinderscale = {
		name = "Cinderscale", desc = "A scaled lizard that basks in lava. Its hide cracks into cooling plates.", elements = []Element{.EMBER, .GROUND}, base_hp = 88, base_energy = 3, base_energy_max = 9, base_power = 1.2, base_defense = 1.2, base_speed = 11.0, base_satiety = 135, base_upkeep = 4,
		color = rl.Color{238, 120, 60, 255}, role = .STARTER, rarity = .COMMON,
		evolves_to = .Magmalisk, evolve_level = 28,
		starter = []Move_Id{.Ember_Strike, .Ember_Strike, .Ember_Strike, .Flame_Burst, .Flame_Burst, .Guard, .Guard, .Hone, .Cleave, .Warcry},
		learnset = []Learn_Entry{
			{.Dragon_Dance, 13}, {.Concuss, 13}, {.Combustion, 13},
			{.Rage, 15}, {.Depower, 15}, {.All_In, 15},
			{.Amplify, 17}, {.Haze, 17}, {.Finale, 17},
			{.Meteor, 19}, {.Overwhelm, 19}, {.Cull, 19},
		},
		move_pool = []Move_Id{.Ember_Strike, .Flame_Burst, .Ember_Coil, .Cleave, .Sunder, .Bash, .Overwhelm, .Warcry, .Followup, .Dragon_Dance, .Amplify, .All_In, .Meteor, .Concuss, .Blood_Pact, .Reckoning, .Cull, .Finale, .Overclock, .Fuse, .Guard, .Hone, .Metronome, .Firestorm},
	},
	.Magmalisk = {
		name = "Magmalisk", desc = "A magma-lizard the size of a cart. It swims through molten rock.", elements = []Element{.EMBER, .GROUND}, base_hp = 120, base_energy = 3, base_energy_max = 10, base_power = 1.45, base_defense = 1.5, base_speed = 12.0, base_satiety = 175, base_upkeep = 6,
		color = rl.Color{252, 140, 64, 255}, role = .STARTER, rarity = .COMMON,
		starter = []Move_Id{.Ember_Strike, .Ember_Strike, .Ember_Strike, .Flame_Burst, .Flame_Burst, .Cleave, .Cleave, .Guard, .Guard, .Hone},
		learnset = []Learn_Entry{
			{.Demon_Form, 28}, {.Combustion, 28}, {.All_In, 28},
			{.Meteor, 32}, {.Rage, 32}, {.Amplify, 32},
			{.Dragon_Dance, 36}, {.Overwhelm, 36}, {.Finale, 36},
		},
		move_pool = []Move_Id{.Ember_Strike, .Flame_Burst, .Ember_Coil, .Cleave, .Sunder, .Overwhelm, .Bash, .All_In, .Meteor, .Concuss, .Amplify, .Dragon_Dance, .Rage, .Combustion, .Demon_Form, .Finale, .Cull, .Guard, .Hone, .Metronome, .Firestorm},
	},
	.Tidepup = {
		name = "Tidepup", desc = "A playful water-pup. It naps in shallow tidepools and wakes to the tide.", elements = []Element{.AQUA}, base_hp = 62, base_energy = 3, base_energy_max = 8, base_power = 1.0, base_defense = 1.0, base_speed = 8.0, base_satiety = 105, base_upkeep = 3,
		color = rl.Color{74, 146, 226, 255}, role = .STARTER, rarity = .COMMON,
		evolves_to = .Ripfin, evolve_level = 12,
		starter = []Move_Id{.Aqua_Jet, .Aqua_Jet, .Aqua_Jet, .Aqua_Jet, .Guard, .Guard, .Guard, .Fortify, .Insight, .Leech},
		learnset = []Learn_Entry{
			{.Footwork, 2}, {.Fang_Flurry, 2}, {.Adrenaline, 2},
			{.Iron_Skin, 4}, {.Overwhelm, 4}, {.Study, 4},
			{.Shield_Bash, 6}, {.Cyclone, 6}, {.Meditate, 6},
			{.Rampart, 8}, {.Body_Press, 8}, {.Gambit, 8},
			{.Fortify, 10}, {.Leech, 10}, {.Siphon, 10},
		},
		move_pool = []Move_Id{.Aqua_Jet, .Aqua_Cutter, .Leech, .Fang_Flurry, .Cyclone, .Overwhelm, .Footwork, .Iron_Skin, .Shield_Bash, .Body_Press, .Rampart, .Guard, .Fortify, .Insight, .Study, .Meditate, .Adrenaline, .Gambit, .Hold_the_Line, .Tidal_Crash},
	},
	.Ripfin = {
		name = "Ripfin", desc = "A sleek riptide-hunter. It rides its own current and never stops moving.", elements = []Element{.AQUA, .ICE}, base_hp = 92, base_energy = 3, base_energy_max = 9, base_power = 1.15, base_defense = 1.45, base_speed = 8.0, base_satiety = 145, base_upkeep = 4,
		color = rl.Color{86, 160, 232, 255}, role = .STARTER, rarity = .COMMON,
		evolves_to = .Tidewyrm, evolve_level = 28,
		starter = []Move_Id{.Aqua_Jet, .Aqua_Jet, .Aqua_Jet, .Aqua_Cutter, .Aqua_Cutter, .Guard, .Guard, .Fortify, .Shield_Bash, .Adrenaline},
		learnset = []Learn_Entry{
			{.Hold_the_Line, 13}, {.Siphon, 13}, {.Overclock, 13},
			{.Entrench, 15}, {.Fang_Flurry, 15}, {.Blackout, 15},
			{.Barrier, 17}, {.Cyclone, 17}, {.Channel, 17},
			{.Bulwark, 19}, {.Leech, 19}, {.Flow, 19},
		},
		move_pool = []Move_Id{.Aqua_Jet, .Aqua_Cutter, .Leech, .Fang_Flurry, .Cyclone, .Body_Press, .Shield_Bash, .Entrench, .Barrier, .Bulwark, .Rampart, .Hold_the_Line, .Fortify, .Iron_Skin, .Footwork, .Insight, .Study, .Meditate, .Siphon, .Blackout, .Overclock, .Maelstrom, .Channel, .Guard, .Riptide, .Tidal_Crash},
	},
	.Tidewyrm = {
		name = "Tidewyrm", desc = "A serpent of the deep current. Its coils freeze the water around it.", elements = []Element{.AQUA, .ICE}, base_hp = 145, base_energy = 3, base_energy_max = 10, base_power = 1.25, base_defense = 1.9, base_speed = 7.0, base_satiety = 195, base_upkeep = 6,
		color = rl.Color{120, 190, 240, 255}, role = .STARTER, rarity = .COMMON,
		starter = []Move_Id{.Aqua_Jet, .Aqua_Jet, .Aqua_Jet, .Aqua_Cutter, .Aqua_Cutter, .Barrier, .Barrier, .Guard, .Guard, .Fortify},
		learnset = []Learn_Entry{
			{.Bastion, 28}, {.Flow, 28}, {.Barricade, 28},
			{.Maelstrom, 32}, {.Bulwark, 32}, {.Channel, 32},
			{.Barrier, 36}, {.Entrench, 36}, {.Bastion, 36},
		},
		move_pool = []Move_Id{.Aqua_Jet, .Aqua_Cutter, .Maelstrom, .Body_Press, .Shield_Bash, .Entrench, .Barrier, .Bulwark, .Rampart, .Hold_the_Line, .Bastion, .Flow, .Barricade, .Fortify, .Iron_Skin, .Footwork, .Insight, .Study, .Siphon, .Blackout, .Channel, .Guard, .Riptide, .Tidal_Crash},
	},
	.Sproutle = {
		name = "Sproutle", desc = "A seedling with legs. It photosynthesises while it sleeps.", elements = []Element{.FLORA}, base_hp = 58, base_energy = 3, base_energy_max = 8, base_power = 1.0, base_defense = 1.0, base_speed = 7.0, base_satiety = 95, base_upkeep = 3,
		color = rl.Color{102, 188, 112, 255}, role = .STARTER, rarity = .COMMON,
		evolves_to = .Thornbud, evolve_level = 12,
		starter = []Move_Id{.Vine_Whip, .Vine_Whip, .Vine_Whip, .Vine_Whip, .Guard, .Guard, .Guard, .Bramble_Armor, .Venom, .Overwhelm},
		learnset = []Learn_Entry{
			{.Envenom, 2}, {.Spike_Shell, 2}, {.Footwork, 2},
			{.Mark, 4}, {.Iron_Skin, 4}, {.Body_Press, 4},
			{.Catalyst, 6}, {.Rampart, 6}, {.Haze, 6},
			{.Expose, 8}, {.Hold_the_Line, 8}, {.Purify, 8},
			{.Venom, 10}, {.Bramble_Armor, 10}, {.Entrench, 10},
		},
		move_pool = []Move_Id{.Vine_Whip, .Venom, .Envenom, .Catalyst, .Bramble_Armor, .Spike_Shell, .Overwhelm, .Body_Press, .Footwork, .Iron_Skin, .Rampart, .Mark, .Expose, .Haze, .Purify, .Guard, .Fortify, .Hold_the_Line, .Thorn_Volley, .Photosynthesis, .Bramble_Crush},
	},
	.Thornbud = {
		name = "Thornbud", desc = "A thorny thicket that walks. Its barbs catch anything that comes close.", elements = []Element{.FLORA, .POISON}, base_hp = 86, base_energy = 3, base_energy_max = 9, base_power = 1.2, base_defense = 1.25, base_speed = 8.0, base_satiety = 130, base_upkeep = 4,
		color = rl.Color{96, 190, 110, 255}, role = .STARTER, rarity = .COMMON,
		evolves_to = .Blightbloom, evolve_level = 28,
		starter = []Move_Id{.Vine_Whip, .Vine_Whip, .Vine_Whip, .Venom, .Venom, .Guard, .Guard, .Bramble_Armor, .Footwork, .Body_Press},
		learnset = []Learn_Entry{
			{.Sunder, 13}, {.Entrench, 13}, {.Reckoning, 13},
			{.Depower, 15}, {.Barrier, 15}, {.All_In, 15},
			{.Toxic, 17}, {.Barricade, 17}, {.Combustion, 17},
			{.Catalyst, 19}, {.Bramble_Armor, 19}, {.Cull, 19},
		},
		move_pool = []Move_Id{.Vine_Whip, .Venom, .Envenom, .Catalyst, .Toxic, .Bramble_Armor, .Spike_Shell, .Body_Press, .Shield_Bash, .Entrench, .Barrier, .Barricade, .Footwork, .Iron_Skin, .Rampart, .Sunder, .Depower, .Mark, .Expose, .Haze, .Purify, .Reckoning, .Cull, .All_In, .Guard, .Thorn_Volley, .Photosynthesis, .Bramble_Crush},
	},
	.Blightbloom = {
		name = "Blightbloom", desc = "A flower that burns instead of wilting. Its pollen is a slow poison.", elements = []Element{.FLORA, .POISON}, base_hp = 122, base_energy = 3, base_energy_max = 10, base_power = 1.4, base_defense = 1.55, base_speed = 8.0, base_satiety = 170, base_upkeep = 6,
		color = rl.Color{110, 200, 120, 255}, role = .STARTER, rarity = .COMMON,
		starter = []Move_Id{.Vine_Whip, .Vine_Whip, .Vine_Whip, .Venom, .Venom, .Catalyst, .Spike_Shell, .Spike_Shell, .Guard, .Guard},
		learnset = []Learn_Entry{
			{.Combustion, 28}, {.Bastion, 28}, {.Amplify, 28},
			{.Toxic, 32}, {.Barricade, 32}, {.All_In, 32},
			{.Catalyst, 36}, {.Barrier, 36}, {.Sunder, 36},
		},
		move_pool = []Move_Id{.Vine_Whip, .Venom, .Envenom, .Catalyst, .Toxic, .Bramble_Armor, .Spike_Shell, .Body_Press, .Shield_Bash, .Entrench, .Barrier, .Barricade, .Combustion, .Bastion, .Amplify, .Sunder, .Depower, .Haze, .Purify, .Mark, .Expose, .Guard, .Thorn_Volley, .Photosynthesis, .Bramble_Crush},
	},
	.Grubling = {
		name = "Grubling", desc = "A pale grub that burrows through the dark. It panics when cornered.", elements = []Element{.NEUTRAL}, base_hp = 34, base_energy = 3, base_energy_max = 8, base_power = 0.8, base_defense = 0.4, base_speed = 7.0, base_satiety = 60, base_upkeep = 2,
		color = rl.Color{150, 140, 120, 255}, role = .WILD, rarity = .COMMON,
		evolves_to = .Rotshell, evolve_level = 16,
		starter = []Move_Id{.Tackle, .Tackle, .Tackle, .Guard, .Guard, .Blood_Pact, .Reckoning, .Cull, .Overclock, .Shiv},
		learnset = []Learn_Entry{
			{.Blood_Pact, 2}, {.Reckoning, 2}, {.Cull, 2},
			{.Overclock, 6}, {.Shiv, 6}, {.Finale, 6},
			{.All_In, 10}, {.Purge, 10}, {.Blade_Dance, 10},
		},
		move_pool = []Move_Id{.Tackle, .Slash, .Guard, .Blood_Pact, .Reckoning, .Cull, .Overclock, .Shiv, .Finale, .All_In, .Purge, .Blade_Dance, .Scavenger, .Slime_Spit, .Earthquake},
	},
	.Vesperling = {
		name = "Vesperling", desc = "A cave bat that hunts by sound. Paper wings, needle teeth.", elements = []Element{.AIR, .NEUTRAL}, base_hp = 40, base_energy = 3, base_energy_max = 9, base_power = 0.95, base_defense = 0.6, base_speed = 14.0, base_satiety = 75, base_upkeep = 2,
		color = rl.Color{112, 106, 132, 255}, role = .WILD, rarity = .COMMON,
		evolves_to = .Nightwing, evolve_level = 16,
		starter = []Move_Id{.Gust, .Gust, .Gust, .Guard, .Guard, .Fang_Flurry, .Leech, .Agility, .Cyclone, .Siphon},
		learnset = []Learn_Entry{
			{.Fang_Flurry, 2}, {.Leech, 2}, {.Gust, 2},
			{.Cyclone, 6}, {.Sanguine, 6}, {.Agility, 6},
			{.Blade_Dance, 10}, {.Overwhelm, 10}, {.Adrenaline, 10},
		},
		move_pool = []Move_Id{.Gust, .Fang_Flurry, .Leech, .Cyclone, .Sanguine, .Agility, .Blade_Dance, .Overwhelm, .Adrenaline, .Siphon, .Guard, .Slash, .Scavenger, .Updraft, .Tailwind, .Gale_Force},
	},
	.Rockmite = {
		name = "Rockmite", desc = "A scuttling boulder. Its shell is thicker than its temper.", elements = []Element{.GROUND}, base_hp = 50, base_energy = 3, base_energy_max = 8, base_power = 0.85, base_defense = 1.4, base_speed = 5.0, base_satiety = 85, base_upkeep = 3,
		color = rl.Color{140, 124, 100, 255}, role = .WILD, rarity = .COMMON,
		starter = []Move_Id{.Rock_Throw, .Rock_Throw, .Rock_Throw, .Guard, .Guard, .Shield_Bash, .Footwork, .Body_Press, .Iron_Skin, .Fortify},
		learnset = []Learn_Entry{
			{.Shield_Bash, 2}, {.Footwork, 2}, {.Rock_Throw, 2},
			{.Entrench, 6}, {.Body_Press, 6}, {.Iron_Skin, 6},
			{.Rampart, 10}, {.Barrier, 10}, {.Bulwark, 10},
		},
		move_pool = []Move_Id{.Rock_Throw, .Guard, .Shield_Bash, .Footwork, .Body_Press, .Iron_Skin, .Fortify, .Entrench, .Rampart, .Barrier, .Bulwark, .Slash, .Juggernaut, .Fault_Line, .Earthquake},
	},
	.Dustwing = {
		name = "Dustwing", desc = "A moth of grey dust. It moves in fits and starts.", elements = []Element{.AIR}, base_hp = 36, base_energy = 3, base_energy_max = 9, base_power = 0.8, base_defense = 0.3, base_speed = 13.0, base_satiety = 65, base_upkeep = 2,
		color = rl.Color{180, 176, 190, 255}, role = .WILD, rarity = .COMMON,
		starter = []Move_Id{.Gust, .Gust, .Gust, .Guard, .Guard, .Insight, .Study, .Cyclone, .Meditate, .Adrenaline},
		learnset = []Learn_Entry{
			{.Insight, 2}, {.Study, 2}, {.Gust, 2},
			{.Meditate, 6}, {.Adrenaline, 6}, {.Cyclone, 6},
			{.Overclock, 10}, {.Siphon, 10}, {.Blackout, 10},
		},
		move_pool = []Move_Id{.Gust, .Insight, .Study, .Cyclone, .Meditate, .Adrenaline, .Overclock, .Siphon, .Blackout, .Guard, .Slash, .Agility, .Rally, .Metronome, .Scavenger, .Updraft, .Tailwind, .Gale_Force},
	},
	.Thornkit = {
		name = "Thornkit", desc = "A prickly sprout. Its barbs catch anything that comes close.", elements = []Element{.FLORA}, base_hp = 44, base_energy = 3, base_energy_max = 8, base_power = 0.85, base_defense = 1.1, base_speed = 9.0, base_satiety = 85, base_upkeep = 2,
		color = rl.Color{96, 180, 104, 255}, role = .WILD, rarity = .COMMON,
		evolves_to = .Thornmaw, evolve_level = 16,
		starter = []Move_Id{.Vine_Whip, .Vine_Whip, .Vine_Whip, .Guard, .Guard, .Bramble_Armor, .Spike_Shell, .Iron_Skin, .Entrench, .Body_Press},
		learnset = []Learn_Entry{
			{.Bramble_Armor, 2}, {.Spike_Shell, 2}, {.Iron_Skin, 2},
			{.Entrench, 6}, {.Body_Press, 6}, {.Shield_Bash, 6},
			{.Barricade, 10}, {.Rampart, 10}, {.Bulwark, 10},
		},
		move_pool = []Move_Id{.Vine_Whip, .Bramble_Armor, .Spike_Shell, .Iron_Skin, .Entrench, .Body_Press, .Shield_Bash, .Barricade, .Rampart, .Bulwark, .Guard, .Fortify, .Thorn_Volley, .Bramble_Crush},
	},
	.Mossling = {
		name = "Mossling", desc = "A soft mound of moss. It sleeps through most fights.", elements = []Element{.FLORA}, base_hp = 52, base_energy = 3, base_energy_max = 8, base_power = 0.8, base_defense = 1.2, base_speed = 6.0, base_satiety = 95, base_upkeep = 3,
		color = rl.Color{110, 170, 110, 255}, role = .WILD, rarity = .COMMON,
		starter = []Move_Id{.Vine_Whip, .Vine_Whip, .Vine_Whip, .Guard, .Guard, .Meditate, .Purify, .Antidote, .Footwork, .Rampart},
		learnset = []Learn_Entry{
			{.Meditate, 2}, {.Purify, 2}, {.Antidote, 2},
			{.Footwork, 6}, {.Rampart, 6}, {.Barrier, 6},
			{.Bastion, 10}, {.Flow, 10}, {.Bulwark, 10},
		},
		move_pool = []Move_Id{.Vine_Whip, .Guard, .Fortify, .Meditate, .Purify, .Antidote, .Footwork, .Rampart, .Barrier, .Bastion, .Flow, .Bulwark, .Rally, .Thorn_Volley, .Photosynthesis, .Bramble_Crush},
	},
	.Bloomcap = {
		name = "Bloomcap", desc = "A cap of bright spores. Breathe deep and you will not wake.", elements = []Element{.FLORA, .POISON}, base_hp = 46, base_energy = 3, base_energy_max = 8, base_power = 0.9, base_defense = 1.0, base_speed = 8.0, base_satiety = 90, base_upkeep = 3,
		color = rl.Color{120, 190, 110, 255}, role = .WILD, rarity = .UNCOMMON,
		starter = []Move_Id{.Vine_Whip, .Vine_Whip, .Vine_Whip, .Venom, .Venom, .Guard, .Guard, .Envenom, .Catalyst, .Bramble_Armor},
		learnset = []Learn_Entry{
			{.Venom, 2}, {.Envenom, 2}, {.Catalyst, 2},
			{.Toxic, 6}, {.Haze, 6}, {.Bramble_Armor, 6},
			{.Combustion, 10}, {.Spike_Shell, 10}, {.Purify, 10},
		},
		move_pool = []Move_Id{.Vine_Whip, .Venom, .Envenom, .Catalyst, .Toxic, .Haze, .Bramble_Armor, .Combustion, .Spike_Shell, .Purify, .Guard, .Spike_Shell, .Slime_Spit, .Venom_Fang},
	},
	.Barkhound = {
		name = "Barkhound", desc = "A hound of living bark. It headbutts with a trunk.", elements = []Element{.FLORA, .GROUND}, base_hp = 56, base_energy = 3, base_energy_max = 8, base_power = 1.0, base_defense = 1.4, base_speed = 8.0, base_satiety = 100, base_upkeep = 3,
		color = rl.Color{126, 150, 90, 255}, role = .WILD, rarity = .UNCOMMON,
		starter = []Move_Id{.Vine_Whip, .Vine_Whip, .Vine_Whip, .Guard, .Guard, .Body_Press, .Iron_Skin, .Rock_Throw, .Shield_Bash, .Fortify},
		learnset = []Learn_Entry{
			{.Body_Press, 2}, {.Iron_Skin, 2}, {.Rock_Throw, 2},
			{.Shield_Bash, 6}, {.Fortify, 6}, {.Entrench, 6},
			{.Rampart, 10}, {.Bulwark, 10}, {.All_In, 10},
		},
		move_pool = []Move_Id{.Vine_Whip, .Rock_Throw, .Body_Press, .Iron_Skin, .Shield_Bash, .Fortify, .Entrench, .Rampart, .Bulwark, .All_In, .Guard, .Bash, .Juggernaut, .Thorn_Volley, .Bramble_Crush, .Fault_Line, .Earthquake},
	},
	.Bubblet = {
		name = "Bubblet", desc = "A round drifter that floats on its own bubbles.", elements = []Element{.AQUA}, base_hp = 48, base_energy = 3, base_energy_max = 8, base_power = 0.85, base_defense = 1.2, base_speed = 8.0, base_satiety = 95, base_upkeep = 2,
		color = rl.Color{72, 140, 214, 255}, role = .WILD, rarity = .COMMON,
		evolves_to = .Bubblord, evolve_level = 16,
		starter = []Move_Id{.Aqua_Jet, .Aqua_Jet, .Aqua_Jet, .Guard, .Guard, .Shield_Bash, .Footwork, .Fortify, .Body_Press, .Rampart},
		learnset = []Learn_Entry{
			{.Guard, 2}, {.Shield_Bash, 2}, {.Footwork, 2},
			{.Fortify, 6}, {.Body_Press, 6}, {.Rampart, 6},
			{.Barrier, 10}, {.Bulwark, 10}, {.Bastion, 10},
		},
		move_pool = []Move_Id{.Aqua_Jet, .Aqua_Cutter, .Guard, .Shield_Bash, .Footwork, .Fortify, .Body_Press, .Rampart, .Barrier, .Bulwark, .Bastion, .Meditate, .Riptide, .Tidal_Crash},
	},
	.Ripjaw = {
		name = "Ripjaw", desc = "A lean hunter with too many teeth. It never stops biting.", elements = []Element{.AQUA}, base_hp = 50, base_energy = 3, base_energy_max = 8, base_power = 0.95, base_defense = 0.9, base_speed = 10.0, base_satiety = 95, base_upkeep = 3,
		color = rl.Color{60, 128, 200, 255}, role = .WILD, rarity = .UNCOMMON,
		starter = []Move_Id{.Aqua_Jet, .Aqua_Jet, .Aqua_Jet, .Guard, .Guard, .Fang_Flurry, .Leech, .Cyclone, .Sanguine, .Overwhelm},
		learnset = []Learn_Entry{
			{.Fang_Flurry, 2}, {.Leech, 2}, {.Aqua_Jet, 2},
			{.Cyclone, 6}, {.Sanguine, 6}, {.Overwhelm, 6},
			{.Blade_Dance, 10}, {.Shiv, 10}, {.Adrenaline, 10},
		},
		move_pool = []Move_Id{.Aqua_Jet, .Aqua_Cutter, .Fang_Flurry, .Leech, .Cyclone, .Sanguine, .Overwhelm, .Blade_Dance, .Shiv, .Adrenaline, .Guard, .Slash, .Metronome, .Scavenger, .Riptide, .Tidal_Crash},
	},
	.Tidecaller = {
		name = "Tidecaller", desc = "It hums the tide into a lullaby. Prey stands still to listen.", elements = []Element{.AQUA, .ICE}, base_hp = 54, base_energy = 3, base_energy_max = 9, base_power = 0.9, base_defense = 1.3, base_speed = 8.0, base_satiety = 110, base_upkeep = 3,
		color = rl.Color{96, 168, 220, 255}, role = .WILD, rarity = .UNCOMMON,
		starter = []Move_Id{.Aqua_Jet, .Aqua_Jet, .Aqua_Jet, .Guard, .Guard, .Frost_Bite, .Concuss, .Snowball, .Meditate, .Mark},
		learnset = []Learn_Entry{
			{.Frost_Bite, 2}, {.Concuss, 2}, {.Snowball, 2},
			{.Mark, 6}, {.Depower, 6}, {.Meditate, 6},
			{.Barrier, 10}, {.Haze, 10}, {.Hold_the_Line, 10},
		},
		move_pool = []Move_Id{.Aqua_Jet, .Aqua_Cutter, .Frost_Bite, .Concuss, .Snowball, .Mark, .Depower, .Meditate, .Barrier, .Haze, .Hold_the_Line, .Guard, .Dazzle, .Frost_Nova, .Ice_Wall, .Riptide, .Tidal_Crash, .Avalanche},
	},
	.Abyssal_Fry = {
		name = "Abyssal Fry", desc = "A deep-sea hatchling with venom in its fins.", elements = []Element{.AQUA, .POISON}, base_hp = 44, base_energy = 3, base_energy_max = 8, base_power = 0.9, base_defense = 0.8, base_speed = 9.0, base_satiety = 85, base_upkeep = 3,
		color = rl.Color{70, 110, 170, 255}, role = .WILD, rarity = .UNCOMMON,
		starter = []Move_Id{.Aqua_Jet, .Aqua_Jet, .Aqua_Jet, .Venom, .Venom, .Guard, .Guard, .Envenom, .Leech, .Catalyst},
		learnset = []Learn_Entry{
			{.Venom, 2}, {.Envenom, 2}, {.Leech, 2},
			{.Catalyst, 6}, {.Toxic, 6}, {.Fang_Flurry, 6},
			{.Combustion, 10}, {.Siphon, 10}, {.Overwhelm, 10},
		},
		move_pool = []Move_Id{.Aqua_Jet, .Venom, .Envenom, .Leech, .Catalyst, .Toxic, .Fang_Flurry, .Combustion, .Siphon, .Overwhelm, .Guard, .Haze, .Slime_Spit, .Riptide, .Tidal_Crash, .Venom_Fang},
	},
	.Gloomling = {
		name = "Gloomling", desc = "A shadow that clings to cave ceilings and watches.", elements = []Element{.NEUTRAL}, base_hp = 42, base_energy = 3, base_energy_max = 8, base_power = 1.0, base_defense = 0.5, base_speed = 10.0, base_satiety = 80, base_upkeep = 2,
		color = rl.Color{96, 88, 120, 255}, role = .WILD, rarity = .COMMON,
		starter = []Move_Id{.Tackle, .Tackle, .Tackle, .Guard, .Guard, .Blood_Pact, .Reckoning, .Mark, .Cull, .Expose},
		learnset = []Learn_Entry{
			{.Blood_Pact, 2}, {.Reckoning, 2}, {.Mark, 2},
			{.Cull, 6}, {.Expose, 6}, {.Overclock, 6},
			{.All_In, 10}, {.Finale, 10}, {.Sunder, 10},
		},
		move_pool = []Move_Id{.Tackle, .Slash, .Blood_Pact, .Reckoning, .Mark, .Cull, .Expose, .Overclock, .All_In, .Finale, .Sunder, .Guard, .Disarm, .Dazzle},
	},
	.Crypt_Rat = {
		name = "Crypt Rat", desc = "A rat that nests in old bones. Its bite festers.", elements = []Element{.NEUTRAL, .POISON}, base_hp = 44, base_energy = 3, base_energy_max = 8, base_power = 0.95, base_defense = 0.7, base_speed = 11.0, base_satiety = 80, base_upkeep = 2,
		color = rl.Color{120, 110, 100, 255}, role = .WILD, rarity = .COMMON,
		starter = []Move_Id{.Tackle, .Tackle, .Tackle, .Venom, .Venom, .Guard, .Guard, .Fang_Flurry, .Envenom, .Catalyst},
		learnset = []Learn_Entry{
			{.Venom, 2}, {.Fang_Flurry, 2}, {.Envenom, 2},
			{.Catalyst, 6}, {.Cyclone, 6}, {.Leech, 6},
			{.Sabotage, 10}, {.Toxic, 10}, {.Overwhelm, 10},
		},
		move_pool = []Move_Id{.Tackle, .Venom, .Fang_Flurry, .Envenom, .Catalyst, .Cyclone, .Leech, .Sabotage, .Toxic, .Overwhelm, .Guard, .Haze, .Venom_Fang},
	},
	.Wispling = {
		name = "Wispling", desc = "A flickering spirit that leads travellers astray.", elements = []Element{.AIR, .ELECTRIC}, base_hp = 40, base_energy = 3, base_energy_max = 9, base_power = 0.9, base_defense = 0.5, base_speed = 14.0, base_satiety = 75, base_upkeep = 2,
		color = rl.Color{160, 180, 220, 255}, role = .WILD, rarity = .UNCOMMON,
		starter = []Move_Id{.Gust, .Gust, .Gust, .Zap, .Zap, .Guard, .Guard, .Agility, .Insight, .Study},
		learnset = []Learn_Entry{
			{.Zap, 2}, {.Gust, 2}, {.Insight, 2},
			{.Agility, 6}, {.Study, 6}, {.Concuss, 6},
			{.Thunderbolt, 10}, {.Overclock, 10}, {.Adrenaline, 10},
		},
		move_pool = []Move_Id{.Gust, .Zap, .Agility, .Insight, .Study, .Concuss, .Thunderbolt, .Overclock, .Adrenaline, .Guard, .Slash, .Cyclone, .Disarm, .Dazzle, .Jolt, .Static_Shock, .Short_Circuit, .Capacitor, .Updraft, .Tailwind, .Supercell, .Gale_Force},
	},
	.Sporeling = {
		name = "Sporeling", desc = "A drifting spore-cloud with a grudge.", elements = []Element{.POISON}, base_hp = 40, base_energy = 3, base_energy_max = 8, base_power = 0.85, base_defense = 0.7, base_speed = 9.0, base_satiety = 80, base_upkeep = 2,
		color = rl.Color{150, 110, 170, 255}, role = .WILD, rarity = .COMMON,
		evolves_to = .Sporelord, evolve_level = 16,
		starter = []Move_Id{.Sting, .Sting, .Sting, .Guard, .Guard, .Venom, .Envenom, .Haze, .Catalyst, .Purify},
		learnset = []Learn_Entry{
			{.Venom, 2}, {.Envenom, 2}, {.Haze, 2},
			{.Catalyst, 6}, {.Toxic, 6}, {.Purify, 6},
			{.Combustion, 10}, {.Spike_Shell, 10}, {.Bramble_Armor, 10},
		},
		move_pool = []Move_Id{.Sting, .Venom, .Envenom, .Haze, .Catalyst, .Toxic, .Purify, .Combustion, .Spike_Shell, .Bramble_Armor, .Guard, .Slash, .Slime_Spit, .Photosynthesis, .Bramble_Crush, .Venom_Fang},
	},
	.Capmaw = {
		name = "Capmaw", desc = "A mushroom with a mouth. It feeds on what the spores drop.", elements = []Element{.FLORA, .POISON}, base_hp = 58, base_energy = 3, base_energy_max = 8, base_power = 1.0, base_defense = 1.2, base_speed = 7.0, base_satiety = 105, base_upkeep = 3,
		color = rl.Color{140, 180, 120, 255}, role = .WILD, rarity = .UNCOMMON,
		starter = []Move_Id{.Vine_Whip, .Vine_Whip, .Vine_Whip, .Venom, .Venom, .Guard, .Guard, .Envenom, .Leech, .Catalyst},
		learnset = []Learn_Entry{
			{.Venom, 2}, {.Leech, 2}, {.Envenom, 2},
			{.Catalyst, 6}, {.Fang_Flurry, 6}, {.Toxic, 6},
			{.Combustion, 10}, {.Sanguine, 10}, {.Overwhelm, 10},
		},
		move_pool = []Move_Id{.Vine_Whip, .Venom, .Leech, .Envenom, .Catalyst, .Fang_Flurry, .Toxic, .Combustion, .Sanguine, .Overwhelm, .Guard, .Haze, .Slime_Spit, .Photosynthesis, .Bramble_Crush, .Venom_Fang},
	},
	.Sentinel = {
		name = "Sentinel", desc = "An ancient guardian that never abandons its post.", elements = []Element{.NEUTRAL}, base_hp = 66, base_energy = 3, base_energy_max = 9, base_power = 0.9, base_defense = 1.8, base_speed = 6.0, base_satiety = 120, base_upkeep = 4,
		color = rl.Color{150, 150, 164, 255}, role = .WILD, rarity = .UNCOMMON,
		starter = []Move_Id{.Slash, .Slash, .Slash, .Guard, .Guard, .Shield_Bash, .Fortify, .Barrier, .Entrench, .Footwork},
		learnset = []Learn_Entry{
			{.Guard, 2}, {.Shield_Bash, 2}, {.Fortify, 2},
			{.Barrier, 6}, {.Entrench, 6}, {.Footwork, 6},
			{.Rampart, 10}, {.Bulwark, 10}, {.Barricade, 10},
		},
		move_pool = []Move_Id{.Slash, .Guard, .Shield_Bash, .Fortify, .Barrier, .Entrench, .Footwork, .Rampart, .Bulwark, .Barricade, .Body_Press, .Iron_Skin, .Disarm, .Juggernaut, .Rally, .Dazzle},
	},
	.Relic_Hound = {
		name = "Relic Hound", desc = "A stone hound that guards buried vaults.", elements = []Element{.GROUND}, base_hp = 58, base_energy = 3, base_energy_max = 8, base_power = 1.0, base_defense = 1.5, base_speed = 8.0, base_satiety = 105, base_upkeep = 3,
		color = rl.Color{150, 130, 100, 255}, role = .WILD, rarity = .UNCOMMON,
		starter = []Move_Id{.Rock_Throw, .Rock_Throw, .Rock_Throw, .Guard, .Guard, .Body_Press, .Iron_Skin, .Shield_Bash, .Entrench, .Bash},
		learnset = []Learn_Entry{
			{.Body_Press, 2}, {.Iron_Skin, 2}, {.Rock_Throw, 2},
			{.Shield_Bash, 6}, {.Entrench, 6}, {.Bash, 6},
			{.Rampart, 10}, {.All_In, 10}, {.Overwhelm, 10},
		},
		move_pool = []Move_Id{.Rock_Throw, .Body_Press, .Iron_Skin, .Shield_Bash, .Entrench, .Bash, .Rampart, .All_In, .Overwhelm, .Fortify, .Guard, .Cleave, .Juggernaut, .Fault_Line, .Earthquake},
	},
	.Hexling = {
		name = "Hexling", desc = "A knot of static that curses what it touches.", elements = []Element{.ELECTRIC}, base_hp = 46, base_energy = 3, base_energy_max = 9, base_power = 0.95, base_defense = 0.8, base_speed = 12.0, base_satiety = 85, base_upkeep = 2,
		color = rl.Color{196, 190, 110, 255}, role = .WILD, rarity = .UNCOMMON,
		starter = []Move_Id{.Zap, .Zap, .Zap, .Guard, .Guard, .Concuss, .Agility, .Depower, .Thunderbolt, .Blackout},
		learnset = []Learn_Entry{
			{.Zap, 2}, {.Concuss, 2}, {.Agility, 2},
			{.Depower, 6}, {.Thunderbolt, 6}, {.Blackout, 6},
			{.All_In, 10}, {.Overclock, 10}, {.Sabotage, 10},
		},
		move_pool = []Move_Id{.Zap, .Thunderbolt, .Concuss, .Agility, .Depower, .Blackout, .All_In, .Overclock, .Sabotage, .Guard, .Slash, .Insight, .Disarm, .Dazzle, .Jolt, .Static_Shock, .Short_Circuit, .Capacitor, .Chain_Lightning, .Overcharge, .Supercell},
	},
	.Snowpup = {
		name = "Snowpup", desc = "A pup of packed snow. Its bark frosts the air.", elements = []Element{.ICE}, base_hp = 46, base_energy = 3, base_energy_max = 8, base_power = 0.9, base_defense = 0.9, base_speed = 10.0, base_satiety = 90, base_upkeep = 2,
		color = rl.Color{190, 220, 240, 255}, role = .WILD, rarity = .COMMON,
		evolves_to = .Frostfang, evolve_level = 16,
		starter = []Move_Id{.Snowball, .Snowball, .Snowball, .Guard, .Guard, .Frost_Bite, .Mark, .Bash, .Expose, .Cleave},
		learnset = []Learn_Entry{
			{.Frost_Bite, 2}, {.Mark, 2}, {.Snowball, 2},
			{.Bash, 6}, {.Expose, 6}, {.Cleave, 6},
			{.Overwhelm, 10}, {.All_In, 10}, {.Sunder, 10},
		},
		move_pool = []Move_Id{.Snowball, .Frost_Bite, .Mark, .Bash, .Expose, .Cleave, .Overwhelm, .All_In, .Sunder, .Guard, .Hone, .Slash, .Frost_Nova, .Avalanche},
	},
	.Frostmaw = {
		name = "Frostmaw", desc = "A maw of black ice. It bites and does not let go.", elements = []Element{.ICE, .GROUND}, base_hp = 62, base_energy = 3, base_energy_max = 9, base_power = 1.1, base_defense = 1.3, base_speed = 8.0, base_satiety = 115, base_upkeep = 4,
		color = rl.Color{150, 190, 220, 255}, role = .WILD, rarity = .UNCOMMON,
		starter = []Move_Id{.Snowball, .Snowball, .Snowball, .Guard, .Guard, .Frost_Bite, .Body_Press, .Rock_Throw, .Shield_Bash, .Bash},
		learnset = []Learn_Entry{
			{.Frost_Bite, 2}, {.Body_Press, 2}, {.Rock_Throw, 2},
			{.Shield_Bash, 6}, {.Bash, 6}, {.Entrench, 6},
			{.All_In, 10}, {.Overwhelm, 10}, {.Rampart, 10},
		},
		move_pool = []Move_Id{.Snowball, .Rock_Throw, .Frost_Bite, .Body_Press, .Shield_Bash, .Bash, .Entrench, .All_In, .Overwhelm, .Rampart, .Guard, .Iron_Skin, .Juggernaut, .Frost_Nova, .Ice_Wall, .Avalanche, .Fault_Line, .Earthquake},
	},
	.Glacierling = {
		name = "Glacierling", desc = "A slow wall of ice. It does not need to chase you.", elements = []Element{.ICE, .AQUA}, base_hp = 70, base_energy = 3, base_energy_max = 9, base_power = 0.9, base_defense = 1.9, base_speed = 5.0, base_satiety = 130, base_upkeep = 4,
		color = rl.Color{140, 200, 230, 255}, role = .WILD, rarity = .UNCOMMON,
		starter = []Move_Id{.Snowball, .Snowball, .Snowball, .Aqua_Jet, .Aqua_Jet, .Guard, .Guard, .Fortify, .Barrier, .Footwork},
		learnset = []Learn_Entry{
			{.Snowball, 2}, {.Guard, 2}, {.Fortify, 2},
			{.Barrier, 6}, {.Footwork, 6}, {.Entrench, 6},
			{.Rampart, 10}, {.Bastion, 10}, {.Bulwark, 10},
		},
		move_pool = []Move_Id{.Snowball, .Aqua_Jet, .Guard, .Fortify, .Barrier, .Footwork, .Entrench, .Rampart, .Bastion, .Bulwark, .Body_Press, .Iron_Skin, .Juggernaut, .Frost_Nova, .Ice_Wall, .Tidal_Crash, .Avalanche},
	},
	.Vinecat = {
		name = "Vinecat", desc = "A cat made of vines. It pounces three times before you blink.", elements = []Element{.FLORA}, base_hp = 48, base_energy = 3, base_energy_max = 8, base_power = 0.95, base_defense = 0.8, base_speed = 12.0, base_satiety = 90, base_upkeep = 3,
		color = rl.Color{100, 180, 110, 255}, role = .WILD, rarity = .UNCOMMON,
		starter = []Move_Id{.Vine_Whip, .Vine_Whip, .Vine_Whip, .Guard, .Guard, .Fang_Flurry, .Cyclone, .Agility, .Leech, .Blade_Dance},
		learnset = []Learn_Entry{
			{.Fang_Flurry, 2}, {.Vine_Whip, 2}, {.Cyclone, 2},
			{.Agility, 6}, {.Leech, 6}, {.Blade_Dance, 6},
			{.Overwhelm, 10}, {.Sanguine, 10}, {.Shiv, 10},
		},
		move_pool = []Move_Id{.Vine_Whip, .Fang_Flurry, .Cyclone, .Agility, .Leech, .Blade_Dance, .Overwhelm, .Sanguine, .Shiv, .Guard, .Slash, .Insight, .Metronome, .Thorn_Volley, .Bramble_Crush},
	},
	.Venomtail = {
		name = "Venomtail", desc = "A dripping stinger. Everything it touches goes numb.", elements = []Element{.POISON}, base_hp = 50, base_energy = 3, base_energy_max = 8, base_power = 0.95, base_defense = 1.0, base_speed = 10.0, base_satiety = 95, base_upkeep = 3,
		color = rl.Color{150, 90, 170, 255}, role = .WILD, rarity = .UNCOMMON,
		starter = []Move_Id{.Sting, .Sting, .Sting, .Venom, .Venom, .Guard, .Guard, .Fang_Flurry, .Envenom, .Cyclone},
		learnset = []Learn_Entry{
			{.Venom, 2}, {.Fang_Flurry, 2}, {.Envenom, 2},
			{.Cyclone, 6}, {.Catalyst, 6}, {.Toxic, 6},
			{.Combustion, 10}, {.Sabotage, 10}, {.Overwhelm, 10},
		},
		move_pool = []Move_Id{.Sting, .Venom, .Fang_Flurry, .Envenom, .Cyclone, .Catalyst, .Toxic, .Combustion, .Sabotage, .Overwhelm, .Guard, .Haze, .Dazzle, .Slime_Spit, .Venom_Fang},
	},
	.Pouncer = {
		name = "Pouncer", desc = "A jungle stalker. It leaps before it lands.", elements = []Element{.FLORA, .AIR}, base_hp = 52, base_energy = 3, base_energy_max = 8, base_power = 1.0, base_defense = 0.9, base_speed = 13.0, base_satiety = 95, base_upkeep = 3,
		color = rl.Color{130, 200, 130, 255}, role = .WILD, rarity = .UNCOMMON,
		starter = []Move_Id{.Vine_Whip, .Vine_Whip, .Vine_Whip, .Gust, .Gust, .Guard, .Guard, .Frost_Bite, .Mark, .Cyclone},
		learnset = []Learn_Entry{
			{.Frost_Bite, 2}, {.Mark, 2}, {.Vine_Whip, 2},
			{.Cyclone, 6}, {.Fang_Flurry, 6}, {.Expose, 6},
			{.All_In, 10}, {.Overwhelm, 10}, {.Sunder, 10},
		},
		move_pool = []Move_Id{.Vine_Whip, .Gust, .Frost_Bite, .Mark, .Cyclone, .Fang_Flurry, .Expose, .All_In, .Overwhelm, .Sunder, .Guard, .Agility, .Thorn_Volley, .Updraft, .Tailwind, .Bramble_Crush, .Gale_Force},
	},
	.Magmite = {
		name = "Magmite", desc = "A pebble of living magma. Warm to the touch, warmer when angry.", elements = []Element{.EMBER}, base_hp = 48, base_energy = 3, base_energy_max = 8, base_power = 0.95, base_defense = 1.0, base_speed = 7.0, base_satiety = 90, base_upkeep = 3,
		color = rl.Color{214, 92, 62, 255}, role = .WILD, rarity = .COMMON,
		evolves_to = .Magmaw, evolve_level = 16,
		starter = []Move_Id{.Ember_Strike, .Ember_Strike, .Ember_Strike, .Guard, .Guard, .Ember_Coil, .Flame_Burst, .Mark, .Combustion, .Hone},
		learnset = []Learn_Entry{
			{.Ember_Coil, 2}, {.Flame_Burst, 2}, {.Ember_Strike, 2},
			{.Mark, 6}, {.Combustion, 6}, {.Hone, 6},
			{.Overwhelm, 10}, {.Fuse, 10}, {.All_In, 10},
		},
		move_pool = []Move_Id{.Ember_Strike, .Flame_Burst, .Ember_Coil, .Mark, .Combustion, .Hone, .Overwhelm, .Fuse, .All_In, .Guard, .Cleave, .Warcry, .Firestorm},
	},
	.Cinderwing = {
		name = "Cinderwing", desc = "A cinder-drake that rides the hot updrafts.", elements = []Element{.EMBER, .AIR}, base_hp = 50, base_energy = 3, base_energy_max = 9, base_power = 1.0, base_defense = 0.8, base_speed = 13.0, base_satiety = 95, base_upkeep = 3,
		color = rl.Color{232, 120, 70, 255}, role = .WILD, rarity = .UNCOMMON,
		starter = []Move_Id{.Ember_Strike, .Ember_Strike, .Ember_Strike, .Gust, .Gust, .Guard, .Guard, .Ember_Coil, .Flame_Burst, .Agility},
		learnset = []Learn_Entry{
			{.Ember_Coil, 2}, {.Gust, 2}, {.Flame_Burst, 2},
			{.Cyclone, 6}, {.Combustion, 6}, {.Agility, 6},
			{.Dragon_Dance, 10}, {.Overwhelm, 10}, {.All_In, 10},
		},
		move_pool = []Move_Id{.Ember_Strike, .Gust, .Flame_Burst, .Ember_Coil, .Cyclone, .Combustion, .Agility, .Dragon_Dance, .Overwhelm, .All_In, .Guard, .Fuse, .Metronome, .Updraft, .Firestorm, .Gale_Force},
	},
	.Slagbeast = {
		name = "Slagbeast", desc = "A heap of cooling slag that walks like a bear.", elements = []Element{.EMBER, .GROUND}, base_hp = 66, base_energy = 3, base_energy_max = 9, base_power = 1.15, base_defense = 1.5, base_speed = 6.0, base_satiety = 120, base_upkeep = 4,
		color = rl.Color{190, 100, 70, 255}, role = .WILD, rarity = .UNCOMMON,
		starter = []Move_Id{.Ember_Strike, .Ember_Strike, .Ember_Strike, .Rock_Throw, .Rock_Throw, .Guard, .Guard, .Hone, .Warcry, .Cleave},
		learnset = []Learn_Entry{
			{.Hone, 2}, {.Warcry, 2}, {.Cleave, 2},
			{.Body_Press, 6}, {.Bash, 6}, {.Amplify, 6},
			{.All_In, 10}, {.Rampart, 10}, {.Overwhelm, 10},
		},
		move_pool = []Move_Id{.Ember_Strike, .Rock_Throw, .Cleave, .Body_Press, .Hone, .Warcry, .Bash, .Amplify, .All_In, .Rampart, .Overwhelm, .Guard, .Juggernaut, .Firestorm, .Fault_Line, .Earthquake},
	},
	.Sandfang = {
		name = "Sandfang", desc = "A desert lurker that swims through dunes.", elements = []Element{.GROUND}, base_hp = 56, base_energy = 3, base_energy_max = 8, base_power = 1.05, base_defense = 1.1, base_speed = 10.0, base_satiety = 105, base_upkeep = 3,
		color = rl.Color{196, 170, 110, 255}, role = .WILD, rarity = .UNCOMMON,
		starter = []Move_Id{.Sand_Attack, .Sand_Attack, .Sand_Attack, .Guard, .Guard, .Hone, .Bash, .Sunder, .Warcry, .Followup},
		learnset = []Learn_Entry{
			{.Hone, 2}, {.Bash, 2}, {.Sand_Attack, 2},
			{.Warcry, 6}, {.Sunder, 6}, {.Followup, 6},
			{.Amplify, 10}, {.All_In, 10}, {.Overwhelm, 10},
		},
		move_pool = []Move_Id{.Sand_Attack, .Hone, .Bash, .Sunder, .Warcry, .Followup, .Amplify, .All_In, .Overwhelm, .Cleave, .Guard, .Rock_Throw, .Fault_Line, .Earthquake},
	},
	.Sparkit = {
		name = "Sparkit", desc = "A crackling spark that cannot sit still.", elements = []Element{.ELECTRIC}, base_hp = 42, base_energy = 3, base_energy_max = 9, base_power = 0.9, base_defense = 0.6, base_speed = 15.0, base_satiety = 80, base_upkeep = 2,
		color = rl.Color{242, 214, 70, 255}, role = .WILD, rarity = .UNCOMMON,
		evolves_to = .Voltail, evolve_level = 16,
		starter = []Move_Id{.Zap, .Zap, .Zap, .Guard, .Guard, .Insight, .Agility, .Thunderbolt, .Study, .Concuss},
		learnset = []Learn_Entry{
			{.Zap, 2}, {.Insight, 2}, {.Agility, 2},
			{.Thunderbolt, 6}, {.Study, 6}, {.Concuss, 6},
			{.All_In, 10}, {.Overclock, 10}, {.Adrenaline, 10},
		},
		move_pool = []Move_Id{.Zap, .Thunderbolt, .Insight, .Agility, .Study, .Concuss, .All_In, .Overclock, .Adrenaline, .Guard, .Slash, .Siphon, .Jolt, .Static_Shock, .Short_Circuit, .Capacitor, .Chain_Lightning, .Overcharge, .Supercell},
	},
	.Crystalfin = {
		name = "Crystalfin", desc = "A fish of living crystal. Its scales hum with charge.", elements = []Element{.ICE, .ELECTRIC}, base_hp = 54, base_energy = 3, base_energy_max = 10, base_power = 1.0, base_defense = 1.1, base_speed = 11.0, base_satiety = 105, base_upkeep = 3,
		color = rl.Color{150, 220, 235, 255}, role = .WILD, rarity = .RARE,
		starter = []Move_Id{.Snowball, .Snowball, .Snowball, .Zap, .Zap, .Guard, .Guard, .Barrier, .Thunderbolt, .Footwork},
		learnset = []Learn_Entry{
			{.Snowball, 2}, {.Zap, 2}, {.Guard, 2},
			{.Barrier, 6}, {.Thunderbolt, 6}, {.Footwork, 6},
			{.Flow, 10}, {.All_In, 10}, {.Bulwark, 10},
		},
		move_pool = []Move_Id{.Snowball, .Zap, .Thunderbolt, .Barrier, .Footwork, .Flow, .All_In, .Bulwark, .Frost_Bite, .Concuss, .Guard, .Slash, .Rally, .Jolt, .Static_Shock, .Short_Circuit, .Capacitor, .Chain_Lightning, .Frost_Nova, .Ice_Wall, .Tidal_Crash, .Avalanche, .Supercell},
	},
	.Rotshell = {
		name = "Rotshell", desc = "A hulking rot-beetle. It eats what it kills, and it kills slowly.", elements = []Element{.NEUTRAL, .POISON}, base_hp = 74, base_energy = 3, base_energy_max = 9, base_power = 1.15, base_defense = 1.4, base_speed = 7.0, base_satiety = 130, base_upkeep = 4,
		color = rl.Color{140, 130, 110, 255}, role = .WILD, rarity = .UNCOMMON,
		starter = []Move_Id{.Slash, .Slash, .Guard, .Guard, .Guard, .Venom, .Envenom, .Blood_Pact, .Reckoning, .Catalyst},
		learnset = []Learn_Entry{
			{.Blood_Pact, 16}, {.Reckoning, 16}, {.Venom, 16},
			{.All_In, 20}, {.Finale, 20}, {.Envenom, 20},
			{.Overwhelm, 24}, {.Combustion, 24}, {.Cull, 24},
		},
		move_pool = []Move_Id{.Slash, .Venom, .Envenom, .Catalyst, .Blood_Pact, .Reckoning, .Cull, .All_In, .Finale, .Overwhelm, .Combustion, .Guard, .Scavenger, .Slime_Spit, .Venom_Fang, .Earthquake},
	},
	.Nightwing = {
		name = "Nightwing", desc = "A bat grown huge on blood. It hunts by the sound of your heartbeat.", elements = []Element{.AIR, .NEUTRAL}, base_hp = 68, base_energy = 3, base_energy_max = 10, base_power = 1.15, base_defense = 0.9, base_speed = 16.0, base_satiety = 120, base_upkeep = 4,
		color = rl.Color{90, 84, 116, 255}, role = .WILD, rarity = .UNCOMMON,
		starter = []Move_Id{.Gust, .Gust, .Guard, .Guard, .Guard, .Fang_Flurry, .Leech, .Cyclone, .Sanguine, .Agility},
		learnset = []Learn_Entry{
			{.Fang_Flurry, 16}, {.Leech, 16}, {.Cyclone, 16},
			{.Sanguine, 20}, {.Blade_Dance, 20}, {.Overwhelm, 20},
			{.All_In, 24}, {.Shiv, 24}, {.Adrenaline, 24},
		},
		move_pool = []Move_Id{.Gust, .Fang_Flurry, .Leech, .Cyclone, .Sanguine, .Blade_Dance, .Overwhelm, .All_In, .Shiv, .Adrenaline, .Guard, .Slash, .Disarm, .Dazzle, .Scavenger, .Updraft, .Tailwind, .Gale_Force},
	},
	.Thornmaw = {
		name = "Thornmaw", desc = "A wall of briars with a mouth somewhere in the middle.", elements = []Element{.FLORA, .GROUND}, base_hp = 78, base_energy = 3, base_energy_max = 9, base_power = 1.15, base_defense = 1.8, base_speed = 7.0, base_satiety = 135, base_upkeep = 4,
		color = rl.Color{88, 180, 98, 255}, role = .WILD, rarity = .UNCOMMON,
		starter = []Move_Id{.Vine_Whip, .Vine_Whip, .Guard, .Guard, .Guard, .Bramble_Armor, .Spike_Shell, .Body_Press, .Shield_Bash, .Entrench},
		learnset = []Learn_Entry{
			{.Bramble_Armor, 16}, {.Body_Press, 16}, {.Shield_Bash, 16},
			{.Entrench, 20}, {.Rampart, 20}, {.Bulwark, 20},
			{.All_In, 24}, {.Barricade, 24}, {.Overwhelm, 24},
		},
		move_pool = []Move_Id{.Vine_Whip, .Bramble_Armor, .Spike_Shell, .Body_Press, .Shield_Bash, .Entrench, .Rampart, .Bulwark, .All_In, .Barricade, .Overwhelm, .Guard, .Thorn_Volley, .Bramble_Crush},
	},
	.Bubblord = {
		name = "Bubblord", desc = "A bloated orb of water. Everything it swallows comes back out blue.", elements = []Element{.AQUA}, base_hp = 84, base_energy = 3, base_energy_max = 10, base_power = 1.05, base_defense = 2.1, base_speed = 6.0, base_satiety = 145, base_upkeep = 4,
		color = rl.Color{64, 132, 214, 255}, role = .WILD, rarity = .UNCOMMON,
		starter = []Move_Id{.Aqua_Jet, .Aqua_Jet, .Guard, .Guard, .Guard, .Barrier, .Body_Press, .Shield_Bash, .Footwork, .Rampart},
		learnset = []Learn_Entry{
			{.Barrier, 16}, {.Body_Press, 16}, {.Shield_Bash, 16},
			{.Rampart, 20}, {.Bulwark, 20}, {.Flow, 20},
			{.Bastion, 24}, {.Barricade, 24}, {.All_In, 24},
		},
		move_pool = []Move_Id{.Aqua_Jet, .Aqua_Cutter, .Barrier, .Body_Press, .Shield_Bash, .Footwork, .Rampart, .Bulwark, .Flow, .Bastion, .Barricade, .All_In, .Rally, .Tidal_Crash},
	},
	.Frostfang = {
		name = "Frostfang", desc = "A wolf of black ice. It freezes you, then takes its time.", elements = []Element{.ICE, .GROUND}, base_hp = 72, base_energy = 3, base_energy_max = 9, base_power = 1.25, base_defense = 1.4, base_speed = 10.0, base_satiety = 125, base_upkeep = 4,
		color = rl.Color{160, 196, 222, 255}, role = .WILD, rarity = .UNCOMMON,
		starter = []Move_Id{.Snowball, .Snowball, .Guard, .Guard, .Guard, .Frost_Bite, .Mark, .Bash, .Sunder, .Expose},
		learnset = []Learn_Entry{
			{.Frost_Bite, 16}, {.Mark, 16}, {.Bash, 16},
			{.Sunder, 20}, {.Expose, 20}, {.Cleave, 20},
			{.All_In, 24}, {.Overwhelm, 24}, {.Meteor, 24},
		},
		move_pool = []Move_Id{.Snowball, .Frost_Bite, .Mark, .Bash, .Sunder, .Expose, .Cleave, .All_In, .Overwhelm, .Meteor, .Guard, .Iron_Skin, .Frost_Nova, .Ice_Wall, .Avalanche},
	},
	.Magmaw = {
		name = "Magmaw", desc = "A furnace with legs. Its throat glows through the cracks in its hide.", elements = []Element{.EMBER, .GROUND}, base_hp = 76, base_energy = 3, base_energy_max = 10, base_power = 1.3, base_defense = 1.5, base_speed = 8.0, base_satiety = 130, base_upkeep = 4,
		color = rl.Color{224, 88, 52, 255}, role = .WILD, rarity = .UNCOMMON,
		starter = []Move_Id{.Ember_Strike, .Ember_Strike, .Guard, .Guard, .Guard, .Ember_Coil, .Combustion, .Hone, .Mark, .Overwhelm},
		learnset = []Learn_Entry{
			{.Ember_Coil, 16}, {.Combustion, 16}, {.Hone, 16},
			{.Mark, 20}, {.Overwhelm, 20}, {.Amplify, 20},
			{.All_In, 24}, {.Fuse, 24}, {.Meteor, 24},
		},
		move_pool = []Move_Id{.Ember_Strike, .Flame_Burst, .Ember_Coil, .Combustion, .Hone, .Mark, .Overwhelm, .Amplify, .All_In, .Fuse, .Meteor, .Guard, .Juggernaut, .Firestorm},
	},
	.Sporelord = {
		name = "Sporelord", desc = "A crowned mushroom that farms the dead. Its spores sing.", elements = []Element{.POISON, .FLORA}, base_hp = 74, base_energy = 3, base_energy_max = 9, base_power = 1.15, base_defense = 1.5, base_speed = 7.0, base_satiety = 130, base_upkeep = 4,
		color = rl.Color{160, 110, 180, 255}, role = .WILD, rarity = .UNCOMMON,
		starter = []Move_Id{.Sting, .Sting, .Guard, .Guard, .Guard, .Venom, .Envenom, .Catalyst, .Toxic, .Leech},
		learnset = []Learn_Entry{
			{.Venom, 16}, {.Catalyst, 16}, {.Envenom, 16},
			{.Toxic, 20}, {.Combustion, 20}, {.Leech, 20},
			{.Overwhelm, 24}, {.Sanguine, 24}, {.Bramble_Armor, 24},
		},
		move_pool = []Move_Id{.Sting, .Venom, .Envenom, .Catalyst, .Toxic, .Combustion, .Leech, .Overwhelm, .Sanguine, .Bramble_Armor, .Guard, .Purify, .Slime_Spit, .Photosynthesis, .Bramble_Crush, .Venom_Fang},
	},
	.Voltail = {
		name = "Voltail", desc = "A storm given a spine. It discharges when it is bored.", elements = []Element{.ELECTRIC}, base_hp = 70, base_energy = 3, base_energy_max = 11, base_power = 1.2, base_defense = 1.0, base_speed = 17.0, base_satiety = 125, base_upkeep = 4,
		color = rl.Color{248, 214, 66, 255}, role = .WILD, rarity = .RARE,
		starter = []Move_Id{.Zap, .Zap, .Guard, .Guard, .Guard, .Concuss, .Agility, .Thunderbolt, .Overclock, .All_In},
		learnset = []Learn_Entry{
			{.Zap, 16}, {.Concuss, 16}, {.Agility, 16},
			{.Thunderbolt, 20}, {.Overclock, 20}, {.All_In, 20},
			{.Meteor, 24}, {.Dragon_Dance, 24}, {.Adrenaline, 24},
		},
		move_pool = []Move_Id{.Zap, .Thunderbolt, .Concuss, .Agility, .Overclock, .All_In, .Meteor, .Dragon_Dance, .Adrenaline, .Guard, .Slash, .Blackout, .Jolt, .Static_Shock, .Short_Circuit, .Capacitor, .Chain_Lightning, .Overcharge, .Supercell},
	},
	.Deep_One = {
		name = "Deep One", desc = "A pale thing from the flooded depths. It hums to itself.", elements = []Element{.NEUTRAL}, base_hp = 120, base_energy = 3, base_energy_max = 10, base_power = 1.6, base_defense = 3.0, base_speed = 5.0, base_satiety = 220, base_upkeep = 8,
		color = rl.Color{150, 42, 62, 255}, role = .BOSS, rarity = .LEGENDARY,
		starter = []Move_Id{.Cleave, .Cleave, .Cleave, .Cleave, .Fortify, .Fortify, .Fortify, .Devour, .Iron_Skin, .Hone},
		learnset = []Learn_Entry{
			{.Bash, 2}, {.Haze, 2}, {.Mark, 2},
			{.Depower, 4}, {.Body_Press, 4}, {.Sunder, 4},
			{.Barrier, 6}, {.Entrench, 6}, {.Rampart, 6},
			{.Overwhelm, 8}, {.All_In, 8}, {.Cleave, 8},
		},
		move_pool = []Move_Id{.Cleave, .Bash, .Bash, .Overwhelm, .Slash, .Fortify, .Barrier, .Rampart, .Iron_Skin, .Hone, .Haze, .Depower, .Devour},
	},
	.Boss_Leviathan = {
		name = "Boss Leviathan", desc = "The abyss given form. It has drowned fleets of monsters.", elements = []Element{.AQUA}, base_hp = 210, base_energy = 3, base_energy_max = 12, base_power = 1.8, base_defense = 3.6, base_speed = 6.0, base_satiety = 280, base_upkeep = 12,
		color = rl.Color{38, 96, 168, 255}, role = .BOSS, rarity = .LEGENDARY,
		starter = []Move_Id{.Maelstrom, .Aqua_Jet, .Aqua_Jet, .Fortify, .Fortify, .Leech, .Leech, .Body_Press, .Fang_Flurry, .Sanguine},
		learnset = []Learn_Entry{
			{.Cyclone, 2}, {.Body_Press, 2}, {.Fang_Flurry, 2},
			{.Barrier, 4}, {.Entrench, 4}, {.Leech, 4},
			{.Sanguine, 6}, {.All_In, 6}, {.Maelstrom, 6},
		},
		move_pool = []Move_Id{.Maelstrom, .Aqua_Jet, .Aqua_Cutter, .Leech, .Fang_Flurry, .Cyclone, .Body_Press, .Barrier, .Entrench, .Fortify, .Sanguine, .Guard, .Rally, .Tidal_Crash},
	},
	.Boss_Infernal = {
		name = "Boss Infernal", desc = "A lord of the deep fires. Its court is ash.", elements = []Element{.EMBER}, base_hp = 170, base_energy = 3, base_energy_max = 12, base_power = 2.2, base_defense = 2.6, base_speed = 9.0, base_satiety = 240, base_upkeep = 11,
		color = rl.Color{208, 72, 44, 255}, role = .BOSS, rarity = .LEGENDARY,
		starter = []Move_Id{.Hellfire, .Ember_Strike, .Ember_Strike, .Flame_Burst, .Flame_Burst, .Guard, .Guard, .Ember_Coil, .Combustion, .Warcry},
		learnset = []Learn_Entry{
			{.Mark, 2}, {.Expose, 2}, {.Warcry, 2},
			{.Overwhelm, 4}, {.Combustion, 4}, {.Hone, 4},
			{.All_In, 6}, {.Meteor, 6}, {.Rage, 6},
		},
		move_pool = []Move_Id{.Hellfire, .Ember_Strike, .Flame_Burst, .Ember_Coil, .Combustion, .Overwhelm, .Mark, .Expose, .Warcry, .Guard, .Cleave, .Firestorm},
	},
	.Boss_Titan = {
		name = "Boss Titan", desc = "The first mountain, and it remembers being awake.", elements = []Element{.GROUND}, base_hp = 280, base_energy = 3, base_energy_max = 12, base_power = 1.7, base_defense = 5.2, base_speed = 4.0, base_satiety = 320, base_upkeep = 14,
		color = rl.Color{168, 138, 92, 255}, role = .BOSS, rarity = .LEGENDARY,
		starter = []Move_Id{.Cataclysm, .Cleave, .Cleave, .Fortify, .Fortify, .Shield_Bash, .Entrench, .Barricade, .Rampart, .Iron_Skin},
		learnset = []Learn_Entry{
			{.Bash, 2}, {.Body_Press, 2}, {.Shield_Bash, 2},
			{.Depower, 4}, {.Entrench, 4}, {.Rampart, 4},
			{.Overwhelm, 6}, {.All_In, 6}, {.Cataclysm, 6},
		},
		move_pool = []Move_Id{.Cataclysm, .Cleave, .Bash, .Overwhelm, .Shield_Bash, .Body_Press, .Entrench, .Barricade, .Rampart, .Barrier, .Fortify, .Iron_Skin, .Depower, .Guard, .Juggernaut, .Rally, .Fault_Line, .Earthquake},
	},
	.Boss_Sovereign = {
		name = "Boss Sovereign", desc = "The throne at the bottom of the world. It does not negotiate.", elements = []Element{.ELECTRIC, .AIR}, base_hp = 180, base_energy = 3, base_energy_max = 12, base_power = 1.9, base_defense = 3.0, base_speed = 13.0, base_satiety = 250, base_upkeep = 11,
		color = rl.Color{196, 178, 96, 255}, role = .BOSS, rarity = .LEGENDARY,
		starter = []Move_Id{.Decree, .Zap, .Zap, .Gust, .Gust, .Thunderbolt, .Cyclone, .Concuss, .Agility, .Dragon_Dance},
		learnset = []Learn_Entry{
			{.Depower, 2}, {.Haze, 2}, {.Concuss, 2},
			{.Overwhelm, 4}, {.Thunderbolt, 4}, {.Agility, 4},
			{.All_In, 6}, {.Dragon_Dance, 6}, {.Decree, 6},
		},
		move_pool = []Move_Id{.Decree, .Zap, .Gust, .Thunderbolt, .Cyclone, .Concuss, .Agility, .Dragon_Dance, .Overwhelm, .Depower, .Haze, .Guard, .Rally, .Jolt, .Static_Shock, .Short_Circuit, .Capacitor, .Updraft, .Supercell, .Gale_Force},
	},

	// ------------------------------------------------------------------------
	// Strong wilds. These are the elite tier: regular monsters, not bosses, but
	// built to hold their own against one — which is what keeps the deep Arena
	// floors varied instead of a parade of the same five bosses.
	// ------------------------------------------------------------------------
	.Ashfang = {
		name = "Ashfang", desc = "A cinder-furred hunter that rides its own updraft. Nothing outruns it twice.", elements = []Element{.EMBER, .AIR}, base_hp = 132, base_energy = 3, base_energy_max = 9, base_power = 1.5, base_defense = 0.9, base_speed = 9.5, base_satiety = 200, base_upkeep = 6,
		color = rl.Color{240, 130, 70, 255}, role = .ELITE, rarity = .RARE,
		starter = []Move_Id{.Ember_Strike, .Ember_Strike, .Gust, .Gust, .Guard, .Agility, .Flame_Burst, .Cleave, .Followup, .Dragon_Dance},
		learnset = []Learn_Entry{
			{.Flame_Burst, 2}, {.Agility, 2}, {.Followup, 2},
			{.Cleave, 6}, {.Cyclone, 6}, {.Dragon_Dance, 6},
			{.Firestorm, 10}, {.Gale_Force, 10}, {.Overwhelm, 10},
			{.Hellfire, 16}, {.Combustion, 16}, {.Amplify, 16},
		},
		move_pool = []Move_Id{.Ember_Strike, .Gust, .Flame_Burst, .Agility, .Followup, .Cleave, .Cyclone, .Dragon_Dance, .Firestorm, .Gale_Force, .Overwhelm, .Hellfire, .Combustion, .Amplify, .Hone, .Fuse, .Updraft, .Mark, .Expose, .Slash},
	},
	.Stormwing = {
		name = "Stormwing", desc = "It flies in the eye of its own squall. Every feather carries a charge.", elements = []Element{.ELECTRIC, .AIR}, base_hp = 146, base_energy = 4, base_energy_max = 10, base_power = 1.4, base_defense = 1.0, base_speed = 9.0, base_satiety = 210, base_upkeep = 6,
		color = rl.Color{250, 225, 110, 255}, role = .ELITE, rarity = .RARE,
		starter = []Move_Id{.Zap, .Zap, .Gust, .Gust, .Guard, .Jolt, .Chain_Lightning, .Capacitor, .Tailwind, .Adrenaline},
		learnset = []Learn_Entry{
			{.Jolt, 2}, {.Tailwind, 2}, {.Capacitor, 2},
			{.Chain_Lightning, 6}, {.Cyclone, 6}, {.Static_Shock, 6},
			{.Supercell, 10}, {.Thunderbolt, 10}, {.Gale_Force, 10},
			{.Concuss, 16}, {.Overcharge, 16}, {.Short_Circuit, 16},
		},
		move_pool = []Move_Id{.Zap, .Gust, .Jolt, .Tailwind, .Capacitor, .Chain_Lightning, .Cyclone, .Static_Shock, .Supercell, .Thunderbolt, .Gale_Force, .Concuss, .Overcharge, .Short_Circuit, .Agility, .Adrenaline, .Followup, .Updraft, .Dazzle, .Study},
	},
	.Bogmaw = {
		name = "Bogmaw", desc = "A bloated swamp lurker. It digests for years and never stops being hungry.", elements = []Element{.POISON, .AQUA}, base_hp = 158, base_energy = 3, base_energy_max = 10, base_power = 1.3, base_defense = 1.6, base_speed = 6.0, base_satiety = 230, base_upkeep = 7,
		color = rl.Color{110, 150, 80, 255}, role = .ELITE, rarity = .EPIC,
		starter = []Move_Id{.Sting, .Sting, .Aqua_Jet, .Aqua_Jet, .Guard, .Envenom, .Venom, .Leech, .Barrier, .Purify},
		learnset = []Learn_Entry{
			{.Envenom, 2}, {.Venom, 2}, {.Leech, 2},
			{.Riptide, 6}, {.Slime_Spit, 6}, {.Barrier, 6},
			{.Catalyst, 10}, {.Venom_Fang, 10}, {.Maelstrom, 10},
			{.Toxic, 16}, {.Devour, 16}, {.Photosynthesis, 16},
		},
		move_pool = []Move_Id{.Sting, .Aqua_Jet, .Envenom, .Venom, .Leech, .Riptide, .Slime_Spit, .Barrier, .Catalyst, .Venom_Fang, .Maelstrom, .Toxic, .Devour, .Photosynthesis, .Purify, .Sabotage, .Aqua_Cutter, .Tidal_Crash, .Fortify, .Antidote},
	},
	.Dreadhorn = {
		name = "Dreadhorn", desc = "A horned brute that charges through stone and keeps going.", elements = []Element{.GROUND, .EMBER}, base_hp = 176, base_energy = 3, base_energy_max = 10, base_power = 1.5, base_defense = 1.7, base_speed = 7.5, base_satiety = 250, base_upkeep = 8,
		color = rl.Color{190, 120, 90, 255}, role = .ELITE, rarity = .EPIC,
		starter = []Move_Id{.Sand_Attack, .Sand_Attack, .Ember_Strike, .Ember_Strike, .Guard, .Mark, .Bash, .Rock_Throw, .Hone, .Body_Press},
		learnset = []Learn_Entry{
			{.Mark, 2}, {.Bash, 2}, {.Hone, 2},
			{.Rock_Throw, 6}, {.Expose, 6}, {.Overwhelm, 6},
			{.Fault_Line, 10}, {.Rally, 10}, {.Warcry, 10},
			{.Meteor, 16}, {.Earthquake, 16}, {.Rage, 16},
		},
		move_pool = []Move_Id{.Sand_Attack, .Ember_Strike, .Mark, .Bash, .Rock_Throw, .Hone, .Expose, .Overwhelm, .Fault_Line, .Rally, .Warcry, .Meteor, .Earthquake, .Rage, .Blood_Pact, .Cleave, .Sunder, .Body_Press, .Cataclysm, .Flame_Burst},
	},
	.Rimewarden = {
		name = "Rimewarden", desc = "A walking glacier with a grudge. Its shell has never been cracked.", elements = []Element{.ICE, .GROUND}, base_hp = 200, base_energy = 3, base_energy_max = 11, base_power = 1.2, base_defense = 2.2, base_speed = 5.5, base_satiety = 270, base_upkeep = 9,
		color = rl.Color{150, 200, 225, 255}, role = .ELITE, rarity = .EPIC,
		starter = []Move_Id{.Snowball, .Snowball, .Guard, .Guard, .Sand_Attack, .Barrier, .Fortify, .Ice_Wall, .Body_Press, .Footwork},
		learnset = []Learn_Entry{
			{.Barrier, 2}, {.Fortify, 2}, {.Ice_Wall, 2},
			{.Body_Press, 6}, {.Shield_Bash, 6}, {.Footwork, 6},
			{.Avalanche, 10}, {.Rampart, 10}, {.Spike_Shell, 10},
			{.Bastion, 16}, {.Cataclysm, 16}, {.Entrench, 16},
		},
		move_pool = []Move_Id{.Snowball, .Guard, .Sand_Attack, .Barrier, .Fortify, .Ice_Wall, .Body_Press, .Shield_Bash, .Footwork, .Avalanche, .Rampart, .Spike_Shell, .Bastion, .Cataclysm, .Entrench, .Bramble_Armor, .Earthquake, .Fault_Line, .Hold_the_Line, .Frost_Nova},
	},
	.Gravemaw = {
		name = "Gravemaw", desc = "It eats what the dungeon buries. The rest of the pack follows it.", elements = []Element{.NEUTRAL, .GROUND}, base_hp = 232, base_energy = 3, base_energy_max = 12, base_power = 1.6, base_defense = 2.4, base_speed = 6.5, base_satiety = 300, base_upkeep = 10,
		color = rl.Color{140, 130, 150, 255}, role = .ELITE, rarity = .LEGENDARY,
		starter = []Move_Id{.Tackle, .Tackle, .Sand_Attack, .Sand_Attack, .Guard, .Barrier, .Bash, .Rock_Throw, .Body_Press, .Reckoning},
		learnset = []Learn_Entry{
			{.Bash, 2}, {.Barrier, 2}, {.Rock_Throw, 2},
			{.Earthquake, 6}, {.Body_Press, 6}, {.Reckoning, 6},
			{.Fault_Line, 10}, {.Rampart, 10}, {.Overwhelm, 10},
			{.Cataclysm, 16}, {.Decree, 16}, {.Bastion, 16},
		},
		move_pool = []Move_Id{.Tackle, .Sand_Attack, .Guard, .Barrier, .Bash, .Rock_Throw, .Body_Press, .Reckoning, .Earthquake, .Fault_Line, .Rampart, .Overwhelm, .Cataclysm, .Decree, .Bastion, .Entrench, .Shield_Bash, .Sunder, .Cleave, .Cull},
	},
}

// Some wilds keep a lair; the rest are wanderers with no fixed home. Territorial
// species drift back toward their lair instead of diffusing across the map.
// Walk a species' family tree: back to its first stage, then forward along the
// line. `levels[i]` is the level at which `chain[i]` is reached (0 = the root),
// so the dex can show the whole chain and highlight where the player is.
evolution_line :: proc(id: Species_Id) -> (chain: [4]Species_Id, levels: [4]int, count: int) {
	root := id
	for {
		found := false
		for p in Species_Id {
			if SPECIES[p].evolve_level > 0 && SPECIES[p].evolves_to == root {
				root = p
				found = true
				break
			}
		}
		if !found {
			break
		}
	}
	cur := root
	chain[0] = cur
	count = 1
	for count < len(chain) {
		sp := SPECIES[cur]
		if sp.evolve_level <= 0 {
			break
		}
		levels[count] = sp.evolve_level
		chain[count] = sp.evolves_to
		cur = sp.evolves_to
		count += 1
	}
	return
}

species_territorial :: proc(id: Species_Id) -> bool {
	#partial switch id {
	case .Deep_One, .Boss_Leviathan, .Boss_Infernal, .Boss_Titan, .Boss_Sovereign:
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
	dexterity:    int, // per-battle: adds to every Block gain (see Dexterity)

	// Status effects (Phase 21). Damage/heal-over-time statuses tick once per
	// round and decay by 1; Thorns persists; Stun skips the creature's actions.
	poison:     int,
	burn:       int,
	regen:      int,
	thorns:     int,
	stun:       int,
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

	powers: [Power]int, // per-battle effects granted by POWER cards (see powers.odin)

	genes: [Gene]int, // per-stat genetic bonus 0-5 (Phase 8; see below)

	deck:       [dynamic]Move_Id, // persistent, owned by this creature
	draw_pile:  [dynamic]Move_Id, // per-battle
	hand:       [dynamic]Move_Id, // per-battle
	discard:    [dynamic]Move_Id, // per-battle
	exhausted:  [dynamic]Move_Id, // per-battle: cards spent with `exhaust`
	played:     int,              // cards played this turn (combo synergy)
	attacked_this_turn: bool,     // Aftershock: has an Attack been played yet this turn
	resilient_used:     bool,     // Resilient: the once-per-battle save is spent
	item_once_used:     bool,     // Amber Fruit / Grit Charm: the once-per-battle trigger is spent
	energy_regen_buff:  f32,      // per-battle energy regen from relics (Mana Shard)

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
		exhausted = make([dynamic]Move_Id, 0),
	}
	creature_recompute_stats(&c)
	c.hp = c.max_hp
	// Start charged: a creature that spawns with an empty bank can barely act,
	// which made freshly-spawned wilds (and a fresh starter) fight on fumes.
	c.energy = c.energy_max
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
	case .POISON:   return .Venom, true
	case .FLORA:    return .Bramble_Armor, true
	case .ELECTRIC: return .Agility, true
	case .AQUA:     return .Meditate, true
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

	// Items are effect-based now, not stat sticks (see `src/items.odin`); the
	// only one that touches stats is the energy berry.
	energy_regen += ITEM_DATA[c.item].energy_regen

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
	delete(c.exhausted)
	c.draw_pile = make([dynamic]Move_Id, 0)
	c.hand = make([dynamic]Move_Id, 0)
	c.discard = make([dynamic]Move_Id, 0)
	c.exhausted = make([dynamic]Move_Id, 0)
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
creature_level_up :: proc(c: ^Creature) -> (opts: [MAX_CHOICE_OPTIONS]Move_Id, n: int, evolved: bool) {
	old_max := c.max_hp
	c.level += 1

	// Evolution: at the species' evolve level, become the next form. Stats are
	// recomputed from the new species at the current level; the deck is kept.
	if sp := SPECIES[c.species]; sp.evolve_level > 0 && c.level >= sp.evolve_level && sp.evolves_to != c.species {
		c.species = sp.evolves_to
		c.name = SPECIES[c.species].name
		evolved = true
	}

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
	c.dexterity = 0
	c.vulnerable = 0
	c.defense_buff = 0
	c.defense_debuff = 0
	c.speed_buff = 0
	c.poison = 0
	c.burn = 0
	c.regen = 0
	c.thorns = 0
	c.stun = 0
	c.powers = {}
	c.attacked_this_turn = false
	c.resilient_used = false
	c.item_once_used = false
	c.energy_regen_buff = 0
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
