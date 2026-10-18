package main

import "core:math"

// ============================================================================
// CRYSTAL PROGRESSION TREE (Phase C)
//
// Permanent, colony-wide upgrades bought with crystals. Nodes form a tree:
// a child unlocks once its parent reaches `req_level`. Costs differ per node and
// rise with each level. Crystals come mostly from fights (Arena / Boss Rooms);
// the Crystal Refinery is deliberately a very slow trickle.
// ============================================================================

Upgrade :: enum {
	NONE,
	// --- roots (available from the start) ---
	Green_Thumb, // Farm / Well / Lumber food
	Rich_Seams,  // Mine / Quarry gold
	Masonry,     // cheaper builds & repairs
	Bounty,      // more loot gold
	Vigilance,   // Watchtower / Beacon reveal & deter
	Armory,      // cheaper Turrets
	Hydraulics,  // Fountain energy output
	Logistics,   // cheaper monster movement
	Scouts,      // better capture odds
	Academy,     // more XP from kills
	Warding,     // stronger Scarecrows
	Trade,       // stronger Marketplaces
	Drills,      // defenders start with Block
	Refining,    // faster Crystal Refineries
	// --- children ---
	Bumper_Crop,   // needs Green Thumb
	Deep_Core,     // needs Rich Seams
	Fortify,       // needs Masonry: tougher Walls / Gates
	Foundations,   // needs Masonry: bigger storage caps
	Spikecraft,    // needs Fortify: deadlier Spike Traps
	Turret_Damage, // needs Armory
	Turret_Health, // needs Armory
	Turret_Range,  // needs Armory (higher level)
	Reservoir,     // needs Hydraulics: more Turret charge
	Forage,        // needs Logistics: food from kills
	Spoils,        // needs Bounty: more crystals from fights
	Veterans,      // needs Academy: Barracks train more
	// --- second wave (Phase 23) ---
	Turret_Rate,     // needs Armory: an extra Turret shot per turn
	Turret_Splash,   // needs Turret Range: shots also hit wilds beside the target
	Mender_Range,    // needs Hydraulics: Menders reach further
	Fountain_Range,  // needs Hydraulics: Fountains reach further
	Kitchen_Rations, // needs Green Thumb: Kitchen feeds a bigger Strength bonus
	Beacon_Power,    // needs Vigilance: Beacon marks wilds harder
	Den_Capacity,    // needs Foundations: Dens hold more monsters
	Vault_Capacity,  // needs Foundations: Vaults hold more items
	Nursery_Speed,   // needs Green Thumb: Nurseries hatch sooner
}

Upgrade_Info :: struct {
	name:      cstring,
	desc:      cstring,
	max_level: int,
	cost:      int, // crystals for the first level
	cost_step: int, // added per level already owned
	// Extra multiplier applied per level already owned. 0 or 1 = the flat
	// linear curve; uncapped nodes use >1 so a long run has a real sink and
	// keeps answering the escalating threats.
	cost_growth: f32,
	prereq:    Upgrade,
	req_level: int, // level of `prereq` needed to unlock
}

UPGRADES := [Upgrade]Upgrade_Info{
	.NONE = {name = "-", desc = "", max_level = 0},

	// --- roots ---
	.Green_Thumb = {name = "Green Thumb", desc = "Farm/Well/Mill food: +25% per level. Uncapped.", max_level = 99, cost = 5, cost_step = 5, cost_growth = 1.20},
	.Rich_Seams  = {name = "Rich Seams",  desc = "Mine/Quarry gold: +25% per level. Uncapped.", max_level = 99, cost = 5, cost_step = 5, cost_growth = 1.20},
	.Masonry     = {name = "Masonry",     desc = "Builds and repairs cost 5% less per level.", max_level = 3, cost = 4, cost_step = 4},
	.Bounty      = {name = "Bounty",      desc = "Defeated wilds drop +12% gold per level.", max_level = 3, cost = 4, cost_step = 4},
	.Vigilance   = {name = "Vigilance",   desc = "Watchtowers/Beacons: +1 reveal and deter.", max_level = 3, cost = 4, cost_step = 4},
	.Armory      = {name = "Armory",      desc = "Turrets cost 8% less gold per level.", max_level = 3, cost = 5, cost_step = 5},
	.Hydraulics  = {name = "Hydraulics",  desc = "Fountains hand out +1 energy per level.", max_level = 3, cost = 5, cost_step = 4},
	.Logistics   = {name = "Logistics",   desc = "Monsters move for 8% less energy per level.", max_level = 3, cost = 5, cost_step = 4},
	.Scouts      = {name = "Scouts",      desc = "Capture cards succeed +6% more per level.", max_level = 3, cost = 6, cost_step = 5},
	.Academy     = {name = "Academy",     desc = "Monsters gain +15% XP from kills per level.", max_level = 3, cost = 5, cost_step = 4},
	.Warding     = {name = "Warding",     desc = "Scarecrows deter & spook 1 tile further.", max_level = 3, cost = 4, cost_step = 3},
	.Trade       = {name = "Trade",       desc = "Marketplaces boost Mines +10% more.", max_level = 3, cost = 5, cost_step = 4},
	.Drills      = {name = "Drills",      desc = "Defenders start fights with +4 Block.", max_level = 3, cost = 6, cost_step = 5},
	.Refining    = {name = "Refining",    desc = "Refineries need 1 fewer turn per crystal.", max_level = 2, cost = 6, cost_step = 5},

	// --- children ---
	.Bumper_Crop   = {name = "Bumper Crop",   desc = "Farms: +3 more food per level.", max_level = 2, cost = 9, cost_step = 7, prereq = .Green_Thumb, req_level = 2},
	.Deep_Core     = {name = "Deep Core",     desc = "Mines/Quarries: +3 more gold per level.", max_level = 2, cost = 9, cost_step = 7, prereq = .Rich_Seams, req_level = 2},
	.Fortify       = {name = "Fortify",       desc = "Walls and Gates gain +15 HP per level.", max_level = 3, cost = 7, cost_step = 6, prereq = .Masonry, req_level = 1},
	.Foundations   = {name = "Foundations",   desc = "Granary/Treasury/Silo store +25 per level.", max_level = 3, cost = 6, cost_step = 5, prereq = .Masonry, req_level = 2},
	.Spikecraft    = {name = "Spikecraft",    desc = "Spike Traps deal +5% max HP per level.", max_level = 2, cost = 6, cost_step = 6, prereq = .Fortify, req_level = 1},
	.Turret_Damage = {name = "Focused Barrels", desc = "Turrets deal +6 damage per level. Uncapped.", max_level = 99, cost = 8, cost_step = 7, cost_growth = 1.22, prereq = .Armory, req_level = 1},
	.Turret_Health = {name = "Reinforced Mounts", desc = "Turrets gain +12 HP per level. Uncapped.", max_level = 99, cost = 6, cost_step = 6, cost_growth = 1.20, prereq = .Armory, req_level = 1},
	.Turret_Range  = {name = "Long Barrels",  desc = "Turrets shoot +1 tile further per level.", max_level = 2, cost = 10, cost_step = 8, prereq = .Armory, req_level = 2},
	.Reservoir     = {name = "Reservoir",     desc = "Turrets store +2 more charge per level. Uncapped.", max_level = 99, cost = 7, cost_step = 6, cost_growth = 1.18, prereq = .Hydraulics, req_level = 1},
	.Forage        = {name = "Forage",        desc = "Defeated wilds drop +1 food per level.", max_level = 3, cost = 7, cost_step = 6, prereq = .Logistics, req_level = 2},
	.Spoils        = {name = "Spoils",        desc = "Arena/Boss wins: +1 crystal per level.", max_level = 3, cost = 10, cost_step = 9, prereq = .Bounty, req_level = 2},
	.Veterans      = {name = "Veterans",      desc = "Barracks grant +1 more XP per level.", max_level = 2, cost = 7, cost_step = 6, prereq = .Academy, req_level = 2},

	// --- second wave (Phase 23) ---
	.Turret_Rate     = {name = "Quick Loaders", desc = "Turrets fire +1 shot per turn per level.", max_level = 2, cost = 12, cost_step = 10, prereq = .Armory, req_level = 2},
	.Turret_Splash   = {name = "Shrapnel Rounds", desc = "Shrapnel: +5 splash dmg per level.", max_level = 2, cost = 11, cost_step = 9, prereq = .Turret_Range, req_level = 1},
	.Mender_Range    = {name = "Long Wrenches", desc = "Menders repair 1 tile further per level.", max_level = 2, cost = 7, cost_step = 6, prereq = .Hydraulics, req_level = 1},
	.Fountain_Range  = {name = "Wide Channels", desc = "Fountains reach 1 tile further per level.", max_level = 2, cost = 8, cost_step = 6, prereq = .Hydraulics, req_level = 2},
	.Kitchen_Rations = {name = "Hearty Rations", desc = "Kitchen feeds +2 Strength per level.", max_level = 2, cost = 7, cost_step = 6, prereq = .Green_Thumb, req_level = 2},
	.Beacon_Power    = {name = "Bright Beacon", desc = "Beacon: +1 Vulnerable per level.", max_level = 2, cost = 8, cost_step = 6, prereq = .Vigilance, req_level = 2},
	.Den_Capacity    = {name = "Deep Dens",   desc = "Dens hold +8 more monsters per level.", max_level = 2, cost = 8, cost_step = 7, prereq = .Foundations, req_level = 1},
	.Vault_Capacity  = {name = "Strongboxes", desc = "Vaults hold +4 more items per level.", max_level = 2, cost = 8, cost_step = 7, prereq = .Foundations, req_level = 2},
	.Nursery_Speed   = {name = "Warm Broods", desc = "Nurseries hatch 1 turn sooner per level.", max_level = 2, cost = 8, cost_step = 6, prereq = .Green_Thumb, req_level = 2},
}

// Panel order: grouped by branch, each child right after its parent where it
// fits. Drawn in three columns (see draw_upgrades).
UPGRADE_ORDER := [?]Upgrade{
	// column 1 — economy
	.Green_Thumb, .Bumper_Crop, .Kitchen_Rations, .Nursery_Speed,
	.Rich_Seams, .Deep_Core, .Trade, .Refining,
	.Logistics, .Forage, .Hydraulics, .Reservoir,
	// column 2 — industry & military
	.Masonry, .Fortify, .Spikecraft, .Foundations, .Den_Capacity, .Vault_Capacity,
	.Armory, .Turret_Damage, .Turret_Health, .Turret_Range, .Turret_Rate, .Turret_Splash,
	// column 3 — support
	.Bounty, .Spoils, .Vigilance, .Warding, .Beacon_Power,
	.Academy, .Veterans, .Scouts, .Drills, .Mender_Range, .Fountain_Range,
}

upgrade_name :: proc(u: Upgrade) -> cstring { return UPGRADES[u].name }
upgrade_desc :: proc(u: Upgrade) -> cstring { return UPGRADES[u].desc }

// Crystals to buy the next level, given how many are already owned. Capped
// nodes climb linearly; uncapped ones compound by `cost_growth`.
upgrade_cost :: proc(u: Upgrade, level: int) -> int {
	info := UPGRADES[u]
	base := f32(info.cost + info.cost_step * level)
	if info.cost_growth > 1.0 {
		base *= math.pow(info.cost_growth, f32(level))
	}
	return max(int(base), 1)
}

// A node is available once its parent reaches the required level. Roots are
// always available.
upgrade_unlocked :: proc(c: ^Colony, u: Upgrade) -> bool {
	p := UPGRADES[u].prereq
	return p == .NONE || c.upgrades[p] >= UPGRADES[u].req_level
}

// 0 ok, 1 maxed, 2 not enough crystals, 3 locked.
colony_buy_upgrade :: proc(c: ^Colony, u: Upgrade) -> int {
	lvl := c.upgrades[u]
	if lvl >= UPGRADES[u].max_level {
		return 1
	}
	if !upgrade_unlocked(c, u) {
		return 3
	}
	cost := upgrade_cost(u, lvl)
	if c.crystals < cost {
		return 2
	}
	c.crystals -= cost
	c.upgrades[u] += 1
	return 0
}

// --- effect readers --------------------------------------------------------

// Green Thumb and Rich Seams are *percentage* lines: they scale with the base
// yield, so they stay meaningful as the colony grows (and they are uncapped).
upgrade_food_mult :: proc(c: ^Colony) -> f32 { return 1.0 + 0.25 * f32(c.upgrades[.Green_Thumb]) }
upgrade_farm_food_bonus :: proc(c: ^Colony) -> int { return c.upgrades[.Bumper_Crop] * 3 }
upgrade_gold_mult :: proc(c: ^Colony) -> f32 { return 1.0 + 0.25 * f32(c.upgrades[.Rich_Seams]) }
upgrade_deep_core_bonus :: proc(c: ^Colony) -> int { return c.upgrades[.Deep_Core] * 3 }
upgrade_masonry_mult :: proc(c: ^Colony) -> f32 { return max(1.0 - 0.05 * f32(c.upgrades[.Masonry]), 0.5) }
upgrade_bounty_mult :: proc(c: ^Colony) -> f32 { return 1.0 + 0.12 * f32(c.upgrades[.Bounty]) }
upgrade_vigilance :: proc(c: ^Colony) -> int { return c.upgrades[.Vigilance] }
upgrade_turret_cost_mult :: proc(c: ^Colony) -> f32 { return max(1.0 - 0.08 * f32(c.upgrades[.Armory]), 0.4) }
upgrade_turret_damage :: proc(c: ^Colony) -> int { return c.upgrades[.Turret_Damage] * 6 }
upgrade_turret_hp :: proc(c: ^Colony) -> int { return c.upgrades[.Turret_Health] * 12 }
upgrade_turret_range :: proc(c: ^Colony) -> int { return c.upgrades[.Turret_Range] }
upgrade_fortify_hp :: proc(c: ^Colony) -> int { return c.upgrades[.Fortify] * 15 }
upgrade_spike_pct :: proc(c: ^Colony) -> f32 { return f32(c.upgrades[.Spikecraft]) * 0.05 }
upgrade_crystal_bonus :: proc(c: ^Colony) -> int { return c.upgrades[.Spoils] }

upgrade_fountain_output :: proc(c: ^Colony) -> int { return c.upgrades[.Hydraulics] }
upgrade_turret_cap :: proc(c: ^Colony) -> int { return c.upgrades[.Reservoir] * 2 }
upgrade_move_cost_mult :: proc(c: ^Colony) -> f32 { return max(1.0 - 0.08 * f32(c.upgrades[.Logistics]), 0.4) }
upgrade_forage_food :: proc(c: ^Colony) -> int { return c.upgrades[.Forage] }
upgrade_capture_bonus :: proc(c: ^Colony) -> f32 { return f32(c.upgrades[.Scouts]) * 0.06 }
upgrade_xp_mult :: proc(c: ^Colony) -> f32 { return 1.0 + 0.15 * f32(c.upgrades[.Academy]) }
upgrade_warding :: proc(c: ^Colony) -> int { return c.upgrades[.Warding] }
upgrade_market_bonus :: proc(c: ^Colony) -> f32 { return f32(c.upgrades[.Trade]) * 0.10 }
upgrade_drills_block :: proc(c: ^Colony) -> int { return c.upgrades[.Drills] * 4 }
upgrade_storage :: proc(c: ^Colony) -> int { return c.upgrades[.Foundations] * 25 }
// Per-Granary/Treasury/Silo storage capacity, including Foundations.
storage_cap :: proc(c: ^Colony) -> int { return STORAGE_CAP + upgrade_storage(c) }
upgrade_veterans :: proc(c: ^Colony) -> int { return c.upgrades[.Veterans] }
upgrade_refinery_boost :: proc(c: ^Colony) -> int { return c.upgrades[.Refining] }

// --- second wave (Phase 23) ---
upgrade_turret_rate :: proc(c: ^Colony) -> int { return c.upgrades[.Turret_Rate] }
upgrade_turret_splash :: proc(c: ^Colony) -> int { return c.upgrades[.Turret_Splash] * TURRET_SPLASH_DAMAGE }
upgrade_mender_range :: proc(c: ^Colony) -> int { return c.upgrades[.Mender_Range] }
upgrade_fountain_range :: proc(c: ^Colony) -> int { return c.upgrades[.Fountain_Range] }
upgrade_kitchen_strength :: proc(c: ^Colony) -> int { return c.upgrades[.Kitchen_Rations] * 2 }
upgrade_beacon_vuln :: proc(c: ^Colony) -> int { return c.upgrades[.Beacon_Power] }
upgrade_den_capacity :: proc(c: ^Colony) -> int { return c.upgrades[.Den_Capacity] * DEN_CAPACITY_PER_LEVEL }
upgrade_vault_cap :: proc(c: ^Colony) -> int { return c.upgrades[.Vault_Capacity] * VAULT_CAP_PER_LEVEL }
upgrade_nursery_speed :: proc(c: ^Colony) -> int { return c.upgrades[.Nursery_Speed] }

// A Den's stasis capacity, including Deep Dens.
den_capacity :: proc(c: ^Colony) -> int { return DEN_CAPACITY + upgrade_den_capacity(c) }

// HP cap for a built improvement, including Fortify / Reinforced Mounts.
improvement_hp_cap :: proc(c: ^Colony, im: Improvement) -> int {
	base := improvement_max_hp(im)
	#partial switch im {
	case .WALL, .GATE: base += upgrade_fortify_hp(c)
	case .TURRET:      base += upgrade_turret_hp(c)
	}
	return base
}
