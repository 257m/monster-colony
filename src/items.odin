package main

import rl "vendor:raylib"
import "core:fmt"

// ============================================================================
// ITEMS (Phase C)
//
// Every monster has one item slot. Items are found as battle loot and equipped
// from the deck viewer. They give permanent stat bonuses (recomputed in
// `creature_recompute_stats`), battle-start buffs, or per-turn/per-hit effects.
// ============================================================================

Item :: enum {
	NONE,
	Ember_Charm,  // +2 Strength at battle start
	Iron_Band,    // +2 Defense at battle start
	Swift_Boots,  // +2 Speed
	War_Banner,   // +6 Block at battle start
	Lucky_Coin,   // draw 1 extra card each turn
	Vampire_Fang, // heal 3 on dealing damage
	Focus_Sash,   // +1 energy regen
	Deep_Pocket,  // +3 energy bank
	Life_Gem,     // +12% max HP
	Power_Core,   // +0.2 Power
	Gold_Finder,  // +2 gold per turn
	Snare_Kit,    // +15% capture chance
}

Item_Info :: struct {
	name:  string,
	desc:  string,
	// battle-start buffs
	strength: int,
	defense:  f32,
	speed:    f32,
	block:    int,
	// per-turn / on-hit
	draw:        int,
	on_hit_leech_pct: f32,
	gold_per_turn: int,
	capture_pct:   f32,
	// stat bonuses (applied in creature_recompute_stats)
	hp_pct:       f32,
	power:        f32,
	energy_regen: f32,
	energy_max:   f32,
}

ITEM_DATA := [Item]Item_Info{
	.NONE        = {name = "None", desc = "No item equipped."},
	.Ember_Charm  = {name = "Ember Charm",  desc = "+2 Strength at battle start.", strength = 2},
	.Iron_Band    = {name = "Iron Band",    desc = "+2 Defense at battle start.", defense = 2.0},
	.Swift_Boots  = {name = "Swift Boots",  desc = "+2 Speed for initiative.", speed = 2.0},
	.War_Banner   = {name = "War Banner",   desc = "+6 Block at battle start.", block = 6},
	.Lucky_Coin   = {name = "Lucky Coin",   desc = "Draws 1 extra card each turn.", draw = 1},
	.Vampire_Fang = {name = "Vampire Fang", desc = "Drains 30% of the damage it deals.", on_hit_leech_pct = 0.30},
	.Focus_Sash   = {name = "Focus Sash",   desc = "+1 energy generated per turn.", energy_regen = 1.0},
	.Deep_Pocket  = {name = "Deep Pocket",  desc = "+3 energy bank.", energy_max = 3.0},
	.Life_Gem     = {name = "Life Gem",     desc = "+12% max HP.", hp_pct = 0.12},
	.Power_Core   = {name = "Power Core",   desc = "+0.2 Power.", power = 0.2},
	.Gold_Finder  = {name = "Gold Finder",  desc = "+2 gold per turn.", gold_per_turn = 2},
	.Snare_Kit    = {name = "Snare Kit",    desc = "+15% capture chance.", capture_pct = 0.15},
}

ITEM_IDS := [?]Item{.Ember_Charm, .Iron_Band, .Swift_Boots, .War_Banner, .Lucky_Coin, .Vampire_Fang, .Focus_Sash, .Deep_Pocket, .Life_Gem, .Power_Core, .Gold_Finder, .Snare_Kit}

item_info :: proc(it: Item) -> Item_Info {
	return ITEM_DATA[it]
}

item_name :: proc(it: Item) -> cstring {
	if it == .NONE {
		return "-"
	}
	return fmt.ctprintf("%s", ITEM_DATA[it].name)
}

item_desc :: proc(it: Item) -> cstring {
	return fmt.ctprintf("%s", ITEM_DATA[it].desc)
}

random_item :: proc(rng: ^Rng) -> Item {
	return ITEM_IDS[rng_below(rng, len(ITEM_IDS))]
}

// Accent colour by primary effect, so the bag UI can colour-code items.
item_color :: proc(it: Item) -> rl.Color {
	info := ITEM_DATA[it]
	switch {
	case info.strength != 0 || info.power != 0 || info.on_hit_leech_pct != 0:
		return rl.Color{240, 150, 110, 255} // offense
	case info.defense != 0 || info.block != 0 || info.hp_pct != 0:
		return rl.Color{110, 210, 180, 255} // defense
	case info.speed != 0 || info.draw != 0 || info.energy_regen != 0 || info.energy_max != 0:
		return rl.Color{120, 180, 245, 255} // tempo
	case info.gold_per_turn != 0 || info.capture_pct != 0:
		return rl.Color{240, 205, 90, 255} // utility
	case:
		return rl.Color{200, 200, 210, 255}
	}
}

// Battle-start buffs an item grants. Called from `battle_start`.
item_battle_start :: proc(b: ^Battle, self: ^Creature) {
	it := ITEM_DATA[self.item]
	side := side_of(b, self)
	if it.strength != 0 {
		self.strength += it.strength
		spawn_popup(b, side, .BUFF, it.strength)
		creature_burst(self, popup_color(.BUFF), 0.6)
	}
	if it.defense > 0 {
		self.defense_buff += it.defense
		spawn_popup(b, side, .DEFEND, int(it.defense))
		creature_burst(self, popup_color(.DEFEND), 0.6)
	}
	if it.speed > 0 {
		self.speed_buff += it.speed
		spawn_popup(b, side, .BUFF, int(it.speed))
		creature_burst(self, popup_color(.BUFF), 0.6)
	}
	if it.block > 0 {
		self.block += it.block
		spawn_popup(b, side, .BLOCK, it.block)
		creature_burst(self, popup_color(.BLOCK), 0.6)
	}
	if it.strength != 0 || it.defense > 0 || it.speed > 0 || it.block > 0 {
		battle_sfx(.BUFF, 0.5)
	}
}
