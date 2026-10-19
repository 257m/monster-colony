package main

import rl "vendor:raylib"
import "core:fmt"

// ============================================================================
// ITEMS (Phase C)
//
// Every monster has one item slot, found as battle loot and equipped from the
// deck viewer. Items are deliberately *held-item* flavoured (Pokemon-style):
// each one is a rule that changes how the monster fights and interacts with a
// specific synergy — multi-hit, drain, poison/burn, thorns, type advantage —
// rather than a flat stat bump. A few stay colony-facing (gold, capture).
//
// The enum keeps its original 12 slots in the same order, so existing saves
// still load; only what each slot *means* has changed.
// ============================================================================

Item :: enum {
	NONE,
	Bloodstone,      // +30% damage dealt, but recoil per Attack you play
	Weakpoint_Lens,   // +25% damage on super-effective hits
	Ricochet_Charm,   // multi-hit Attacks hit 1 extra time
	Siphon_Gland,      // drain / lifesteal heals +50%
	Venom_Sac,  // Poison / Burn apply +1 stack
	Spiked_Carapace,  // start each battle with 2 Thorns
	Ration_Pouch,     // heal 4% max HP at the end of each turn
	Amber_Fruit,  // once per battle, heal 25% when dropping below half HP
	Cleansing_Bloom,      // cleanse Poison / Burn / Stun each turn
	Grit_Charm,     // survive one lethal blow at 1 HP
	Grudge_Idol, // +Strength when hit super-effectively
	Snare_Kit,      // +15% capture chance
}

Item_Info :: struct {
	name: string,
	desc: string,

	// Stat bonuses (applied in `creature_recompute_stats`).
	energy_regen: f32,

	// Battle start.
	thorns: int,

	// Offense.
	damage_mult:     f32, // all damage dealt
	super_mult:      f32, // extra damage on super-effective hits
	extra_hits:      int, // extra hits on multi-hit Attacks
	drain_mult:      f32, // lifesteal / drain healing
	status_bonus:    int, // extra Poison / Burn stacks applied
	self_damage_pct: f32, // recoil, as a fraction of max HP, per Attack

	// Per-turn / reactive.
	turn_heal_pct:   f32,
	cleanse_turn:    bool,
	low_hp_heal_pct: f32, // heal once per battle when dropping below half HP
	sash:            bool, // survive one lethal blow at 1 HP, once per battle
	weakness_str:    int, // +Strength when hit super-effectively

	// Colony-facing.
	gold_per_turn: int,
	capture_pct:   f32,
}

ITEM_DATA := [Item]Item_Info{
	.NONE            = {name = "None", desc = "No item equipped."},
	.Bloodstone      = {name = "Bloodstone",      desc = "+30% damage dealt, but you lose 3% max HP each Attack.", damage_mult = 0.30, self_damage_pct = 0.03},
	.Weakpoint_Lens  = {name = "Weakpoint Lens",  desc = "+25% damage on super-effective hits.", super_mult = 0.25},
	.Ricochet_Charm  = {name = "Ricochet Charm",  desc = "Your multi-hit Attacks hit 1 extra time.", extra_hits = 1},
	.Siphon_Gland    = {name = "Siphon Gland",    desc = "Drain and lifesteal heal +50%.", drain_mult = 0.50},
	.Venom_Sac       = {name = "Venom Sac",       desc = "Your Poison and Burn apply +1 extra stack.", status_bonus = 1},
	.Spiked_Carapace = {name = "Spiked Carapace", desc = "Start each battle with 2 Thorns.", thorns = 2},
	.Ration_Pouch    = {name = "Ration Pouch",    desc = "Heal 4% max HP at the end of each turn.", turn_heal_pct = 0.04},
	.Amber_Fruit     = {name = "Amber Fruit",     desc = "Once per battle, heal 25% when you drop below half HP.", low_hp_heal_pct = 0.25},
	.Cleansing_Bloom = {name = "Cleansing Bloom", desc = "Cleanse Poison, Burn and Stun at the end of each turn.", cleanse_turn = true},
	.Grit_Charm      = {name = "Grit Charm",      desc = "Survive one lethal blow at 1 HP, once per battle.", sash = true},
	.Grudge_Idol     = {name = "Grudge Idol",     desc = "Gain +2 Strength when hit super-effectively.", weakness_str = 2},
	.Snare_Kit       = {name = "Snare Kit",       desc = "+15% capture chance.", capture_pct = 0.15},
}

ITEM_IDS := [?]Item{.Bloodstone, .Weakpoint_Lens, .Ricochet_Charm, .Siphon_Gland, .Venom_Sac, .Spiked_Carapace, .Ration_Pouch, .Amber_Fruit, .Cleansing_Bloom, .Grit_Charm, .Grudge_Idol, .Snare_Kit}

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
	case info.damage_mult != 0 || info.super_mult != 0 || info.extra_hits != 0 || info.self_damage_pct != 0:
		return rl.Color{240, 150, 110, 255} // offense
	case info.drain_mult != 0 || info.status_bonus != 0 || info.thorns != 0:
		return rl.Color{190, 140, 230, 255} // synergy
	case info.turn_heal_pct != 0 || info.cleanse_turn || info.low_hp_heal_pct != 0 || info.sash || info.weakness_str != 0:
		return rl.Color{110, 210, 180, 255} // defense / sustain
	case info.energy_regen != 0:
		return rl.Color{120, 180, 245, 255} // tempo
	case info.capture_pct != 0:
		return rl.Color{240, 205, 90, 255} // utility
	case:
		return rl.Color{200, 200, 210, 255}
	}
}

// Battle-start buffs an item grants. Called from `battle_start`.
item_battle_start :: proc(b: ^Battle, self: ^Creature) {
	it := ITEM_DATA[self.item]
	side := side_of(b, self)
	if it.thorns != 0 {
		self.thorns += it.thorns
		spawn_popup(b, side, .THORNS, it.thorns)
		creature_burst(self, popup_color(.THORNS), 0.6)
		battle_sfx(.BUFF, 0.5)
	}
}

// The item's damage multiplier (Bloodstone), plus the super-effective bonus
// (Weakpoint Lens). `super_effective` is the type multiplier from `apply_damage`.
item_damage_mult :: proc(it: Item, super_effective: bool) -> f32 {
	info := ITEM_DATA[it]
	m := 1.0 + info.damage_mult
	if super_effective {
		m += info.super_mult
	}
	return m
}

// Defensive once-per-battle items, checked whenever the holder is damaged:
// the Grit Charm keeps it alive at 1 HP, and the Amber Fruit heals it the
// first time it drops below half HP.
item_try_save :: proc(b: ^Battle, self: ^Creature) {
	if self.item_once_used {
		return
	}
	info := ITEM_DATA[self.item]
	if info.sash && self.hp <= 0 {
		self.hp = 1
		self.item_once_used = true
		spawn_popup(b, side_of(b, self), .HEAL, 1)
		creature_burst(self, rl.Color{255, 245, 180, 255}, 0.75)
		battle_sfx(.NOTIFY, 0.8)
		battle_log(b, "%s's Grit Charm holds it at 1 HP!", self.name)
		return
	}
	if info.low_hp_heal_pct > 0 && self.hp > 0 && self.hp * 2 < self.max_hp {
		heal := max(int(f32(self.max_hp) * info.low_hp_heal_pct), 1)
		self.hp = min(self.hp + heal, self.max_hp)
		self.item_once_used = true
		spawn_popup(b, side_of(b, self), .HEAL, heal)
		creature_burst(self, popup_color(.HEAL), 0.7)
		battle_sfx(.HEAL, 0.7)
		battle_log(b, "%s's Amber Fruit restores %d HP.", self.name, heal)
	}
}
