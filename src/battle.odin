package main

import rl "vendor:raylib"
import "core:fmt"
import "core:math"

// ============================================================================
// SYMMETRIC CREATURE BATTLE
//
// Both the player's active creature and the wild monster use the same rules:
// each has its own deck, and each turn it resets block, refills energy and
// draws a fresh hand. The player picks cards by hand; the AI picks the most
// valuable affordable card. Switching and capturing are player-only actions.
// ============================================================================

PARTY_MAX    :: 6

SHAKE_DUR         :: f32(0.22) // screen shake duration
CREATURE_SHAKE_DUR :: f32(0.30) // per-creature hit wobble duration
MAX_ROUNDS        :: 30        // stalemate cap

// Percentage-based battle tuning (Phase 28). DoT/heal/reflect are fractions so
// they scale with HP instead of going stale at high levels.
POISON_PCT         :: f32(0.02) // poison damage per stack, of the victim's max HP
BURN_PCT           :: f32(0.03) // burn damage per stack, of the victim's max HP
REGEN_PCT          :: f32(0.03) // regen heal per stack, of the owner's max HP
// Burn isn't just damage: a burning creature also *hits softer*. Poison is pure
// attrition (highest raw DoT, no rider); Burn is attrition + a weaken.
BURN_WEAKEN_PER_STACK :: f32(0.05)
BURN_WEAKEN_CAP       :: f32(0.50)
// Thorns: each stack reflects a slice of the *attacker's* max HP, not of the
// hit. Stacks compound with diminishing returns (`thorns_fraction`), so the
// total can never reach 100%. A stack is spent on each hit.
THORNS_HP_PCT :: f32(0.0625)
// Vulnerable: a *duration* (in turns), not a stack. While it's up, attacks deal
// this much to the target. Each turn it ticks down by one.
VULN_MULT :: f32(1.5)

hp_fraction :: proc(list: []^Creature) -> f32 {
	hp := 0
	mx := 0
	for c in list {
		if c.hp > 0 {
			hp += c.hp
		}
		mx += c.max_hp
	}
	if mx <= 0 {
		return 0
	}
	return f32(hp) / f32(mx)
}

// Both sides alternate playing one card at a time within a round. Initiative
// is rolled at the start of each round (weighted by Speed); once both sides
// have ended their turn or run out of playable cards, the next round begins.
Battle_Phase :: enum { PLAYER_ACTION, ENEMY_ACTION, WON, LOST, CAPTURED }
Battle_Side  :: enum { PLAYER, WILD }

Popup_Kind :: enum { DAMAGE, BLOCK, HEAL, BUFF, DEBUFF, DEFEND, WEAKEN, SHATTER, CAPTURE, POISON, BURN, STUN, REGEN, THORNS, ENERGY, DRAW, JUNK, CLEAR }

Popup :: struct {
	value:    int,
	kind:     Popup_Kind,
	side:     Battle_Side,
	life:     f32,
	max_life: f32,
}

// One queued piece of per-hit feedback. Damage resolves instantly (so the game
// logic never waits), but the feedback plays out in `wave`s: every event from
// the same hit index fires together, and waves are spaced by HIT_FX_STAGGER. A
// multi-hit card therefore reads as several impacts, while a spread (AoE) card
// is a single wave — every victim hit at the same instant.
Hit_Fx :: struct {
	wave:   int,
	kind:   Popup_Kind,
	value:  int,
	side:   Battle_Side,
	target: ^Creature, // who flinches and sparks
}

HIT_FX_STAGGER :: f32(0.06)

Actor :: struct {
	side:  Battle_Side,
	index: int, // party index (PLAYER) or enemy index (WILD)
}

Battle :: struct {
	party:         [dynamic]^Creature, // defenders (external creatures), array owned here
	active:        int,                // party member currently taking its turn (for the UI)
	party_done:    [dynamic]bool,      // per party member: ended its turn this turn
	enemies:       [dynamic]^Creature, // the attacking wilds (external)
	enemy_ids:     [dynamic]int,       // colony ids, parallel to enemies
	target:        int,                // currently targeted enemy
	enemy_first:   int,                // scroll: leftmost visible enemy in the row
	ally_target:   int,                // currently targeted teammate (for support cards)
	sel_kind:      Move_Target,        // which side the player last picked (.ENEMY or .ALLY)
	enemy_acting:  int,                // enemy taking the current action
	captured_ids:  [dynamic]int,       // enemies captured this battle
	capture_cards: int,                // capture cards available (spent on capture)
	capture_bonus: f32,                // colony Scout upgrade, added to capture odds
	auto_play:     bool,               // AI plays the player's side
	show_piles:    bool,               // the draw/discard pile viewer is open
	phase:         Battle_Phase,
	round:         int,
	order:         [dynamic]Actor, // initiative queue: every living monster
	order_pos:     int,            // next slot to consider (wraps each pass)
	timer:         f32,
	rng:           Rng,
	log:           [dynamic]string,
	popups:        [dynamic]Popup,
	hit_fx:        [dynamic]Hit_Fx, // queued per-hit feedback (see Hit_Fx)
	hit_fx_wave:   int,
	hit_fx_t:      f32,
	shake:         f32,
	shake_mag:     f32,
}

DIGIT_KEYS := [?]rl.KeyboardKey{.ONE, .TWO, .THREE, .FOUR, .FIVE, .SIX, .SEVEN, .EIGHT, .NINE}

// Set while a battle is resolved headlessly (map skirmishes) so it doesn't fire
// UI sounds for a fight the player never sees.
battle_silent: bool

// ----------------------------------------------------------------------------
// Lifecycle
// ----------------------------------------------------------------------------

battle_log :: proc(b: ^Battle, format: string, args: ..any) {
	append(&b.log, fmt.aprintf(format, ..args))
	if len(b.log) > 7 {
		delete(b.log[0])
		ordered_remove(&b.log, 0)
	}
}

battle_free :: proc(b: ^Battle) {
	for i in 0..<len(b.party) {
		creature_free_piles(b.party[i])
	}
	for i in 0..<len(b.enemies) {
		creature_free_piles(b.enemies[i])
	}
	delete(b.hit_fx)
	b.hit_fx = make([dynamic]Hit_Fx, 0)
	delete(b.party)
	b.party = make([dynamic]^Creature, 0)
	delete(b.party_done)
	b.party_done = make([dynamic]bool, 0)
	delete(b.enemies)
	b.enemies = make([dynamic]^Creature, 0)
	delete(b.enemy_ids)
	b.enemy_ids = make([dynamic]int, 0)
	delete(b.captured_ids)
	b.captured_ids = make([dynamic]int, 0)
	delete(b.order)
	b.order = make([dynamic]Actor, 0)
	for s in b.log {
		delete(s)
	}
	delete(b.log)
	b.log = make([dynamic]string, 0)
	delete(b.popups)
	b.popups = make([dynamic]Popup, 0)
	b.hit_fx = make([dynamic]Hit_Fx, 0)
}

shuffle_cards :: proc(cards: ^[dynamic]Move_Id, rng: ^Rng) {
	n := len(cards)
	for i := n - 1; i > 0; i -= 1 {
		j := rng_below(rng, i + 1)
		tmp := cards[i]
		cards[i] = cards[j]
		cards[j] = tmp
	}
}

prepare_piles :: proc(c: ^Creature, rng: ^Rng) {
	creature_free_piles(c)
	for card in c.deck {
		append(&c.draw_pile, card)
	}
	shuffle_cards(&c.draw_pile, rng)
}

battle_start :: proc(defenders: []^Creature, enemies: []^Creature, enemy_ids: []int, seed_rng: ^Rng) -> Battle {
	b := Battle{}
	b.rng = rng_make(rng_next_u64(seed_rng))
	b.log = make([dynamic]string, 0)
	b.popups = make([dynamic]Popup, 0)
	b.hit_fx = make([dynamic]Hit_Fx, 0)
	b.party = make([dynamic]^Creature, 0)
	b.party_done = make([dynamic]bool, 0)
	b.enemies = make([dynamic]^Creature, 0)
	b.enemy_ids = make([dynamic]int, 0)
	b.captured_ids = make([dynamic]int, 0)
	b.order = make([dynamic]Actor, 0)

	for c in defenders {
		append(&b.party, c)
		append(&b.party_done, false)
	}
	for e, i in enemies {
		append(&b.enemies, e)
		if i < len(enemy_ids) {
			append(&b.enemy_ids, enemy_ids[i])
		} else {
			append(&b.enemy_ids, -1)
		}
	}
	b.active = 0
	b.target = 0
	b.ally_target = 0
	b.enemy_acting = 0

	for e in b.enemies {
		creature_reset_battle_state(e)
		prepare_piles(e, &b.rng)
	}
	for i in 0..<len(b.party) {
		creature_reset_battle_state(b.party[i])
		prepare_piles(b.party[i], &b.rng)
	}

	// Species abilities that fire once at the start of the fight (Intimidate
	// needs the opposing side, so both sides are applied here), then item buffs.
	for e in b.enemies {
		ability_battle_start(&b, e, b.party[:])
		item_battle_start(&b, e)
	}
	for i in 0..<len(b.party) {
		ability_battle_start(&b, b.party[i], b.enemies[:])
		item_battle_start(&b, b.party[i])
	}

	n := len(b.enemies)
	battle_log(&b, "%d wild%s attack%s!", n, n == 1 ? "" : "s", n == 1 ? "s" : "")

	begin_round(&b)
	return b
}

// ----------------------------------------------------------------------------
// Enemy-party helpers
// ----------------------------------------------------------------------------

first_alive_enemy :: proc(b: ^Battle) -> int {
	for e, i in b.enemies {
		if e.hp > 0 {
			return i
		}
	}
	return -1
}

enemies_alive :: proc(b: ^Battle) -> int {
	n := 0
	for e in b.enemies {
		if e.hp > 0 {
			n += 1
		}
	}
	return n
}

target_enemy :: proc(b: ^Battle) -> ^Creature {
	if len(b.enemies) == 0 {
		return nil
	}
	t := clamp(b.target, 0, len(b.enemies) - 1)
	return b.enemies[t]
}

fix_target :: proc(b: ^Battle) {
	if len(b.enemies) == 0 {
		return
	}
	if b.target < 0 || b.target >= len(b.enemies) || b.enemies[b.target].hp <= 0 {
		if i := first_alive_enemy(b); i >= 0 {
			b.target = i
		}
	}
	// Keep the target on screen in the scrolled row.
	enemy_scroll_to(b, b.target)
}

enemy_has_card :: proc(e: ^Creature) -> bool {
	for m in e.hand {
		if move_playable(e, move_data(m)) {
			return true
		}
	}
	return false
}

remove_enemy_index :: proc(b: ^Battle, i: int) {
	if i < 0 || i >= len(b.enemies) {
		return
	}
	unordered_remove(&b.enemies, i)
	if i < len(b.enemy_ids) {
		unordered_remove(&b.enemy_ids, i)
	}
	// Keep the initiative queue consistent: drop the removed enemy and shift
	// any later enemy indices down (player indices are untouched).
	k := 0
	for k < len(b.order) {
		a := b.order[k]
		if a.side == .WILD && a.index == i {
			ordered_remove(&b.order, k)
			if b.order_pos > k {
				b.order_pos -= 1
			}
			continue
		}
		if a.side == .WILD && a.index > i {
			b.order[k].index = a.index - 1
		}
		k += 1
	}
}

// ----------------------------------------------------------------------------
// Turn structure (shared by both sides)
// ----------------------------------------------------------------------------

creature_draw :: proc(c: ^Creature, n: int, rng: ^Rng) {
	for _ in 0..<n {
		if len(c.draw_pile) == 0 {
			if len(c.discard) == 0 {
				return
			}
			for card in c.discard {
				append(&c.draw_pile, card)
			}
			clear(&c.discard)
			shuffle_cards(&c.draw_pile, rng)
		}
		append(&c.hand, pop(&c.draw_pile))
	}
}

creature_begin_round :: proc(b: ^Battle, c: ^Creature, rng: ^Rng) {
	c.played = 0
	c.attacked_this_turn = false
	// Energy is generated each round and carries over up to the bank cap. Relic
	// towers in range (Mana Shard) add a battle-only regen bonus.
	c.energy = min(c.energy + c.energy_regen + c.energy_regen_buff, c.energy_max)
	draw := 5
	if c.ability == .Lucky {
		draw += ABILITY_LUCKY_DRAW
	}
	creature_draw(c, draw, rng)
	if extra := draw - 5; extra > 0 {
		spawn_popup(b, side_of(b, c), .DRAW, extra)
	}
	power_begin_round(b, c)
	ability_begin_round(b, c)
}

creature_end_round :: proc(b: ^Battle, c: ^Creature) {
	power_combustion(b, c)
	// Junk cards (Wound) punish you for ending the turn with them in hand.
	dmg := 0
	for card in c.hand {
		dmg += MOVE_DATA[card].hand_damage
	}
	if dmg > 0 {
		c.hp -= dmg
		spawn_popup(b, side_of(b, c), .DAMAGE, dmg)
		creature_burst(c, popup_color(.DAMAGE), 0.4)
		battle_log(b, "%s's wounds ache for %d.", c.name, dmg)
	}
	// Clear the hand. Retain cards stay; Ethereal cards exhaust instead of
	// being discarded.
	i := 0
	for i < len(c.hand) {
		md := MOVE_DATA[c.hand[i]]
		if md.retain {
			i += 1
			continue
		}
		card := c.hand[i]
		if md.ethereal {
			append(&c.exhausted, card)
		} else {
			append(&c.discard, card)
		}
		ordered_remove(&c.hand, i)
	}
	power_end_round(b, c)
	// Inferno (boss ability): burn every foe at the end of the turn.
	if c.ability == .Inferno {
		foes := side_of(b, c) == .PLAYER ? b.enemies[:] : b.party[:]
		for f in foes {
			if f.hp <= 0 {
				continue
			}
			f.burn += ABILITY_INFERNO_BURN
			spawn_popup(b, side_of(b, f), .BURN, ABILITY_INFERNO_BURN)
			creature_burst(f, popup_color(.BURN), 0.5)
		}
		battle_log(b, "%s's Inferno scorches every foe.", c.name)
	}
	// Block is cleared between rounds (here rather than in begin_round so a
	// battle-start ability like Guardian keeps its Block through turn one).
	// Barricade (power) and Colossus (ability) keep it.
	if !power_keeps_block(c) && !ability_keeps_block(c) {
		c.block = 0
	}
	if c.vulnerable > 0 {
		c.vulnerable -= 1
	}
	// Ration Pouch: a trickle of healing each turn (the caller's heal popup covers
	// it, since it diffs HP around this call).
	if it := ITEM_DATA[c.item]; it.turn_heal_pct > 0 && c.hp > 0 {
		c.hp = min(c.hp + max(int(f32(c.max_hp) * it.turn_heal_pct), 1), c.max_hp)
	}
	// Cleansing Bloom: shrug off Poison / Burn / Stun every turn.
	if ITEM_DATA[c.item].cleanse_turn {
		if n := creature_cleanse_status(c); n > 0 {
			spawn_popup(b, side_of(b, c), .CLEAR, n)
			creature_burst(c, popup_color(.HEAL), 0.6)
			battle_log(b, "%s's Cleansing Bloom clears its status.", c.name)
		}
	}
	if c.ability == .Regenerator && c.hp > 0 {
		c.hp = min(c.hp + max(int(f32(c.max_hp)*ABILITY_REGENERATOR_PCT), 1), c.max_hp)
	}
}

// Tick one creature's status effects at the start of a round. Poison and Burn
// deal damage and decay by 1; Regen heals and decays by 1; Thorns persists;
// Stun is consumed in `advance`. Returns true if the creature died.
tick_status :: proc(b: ^Battle, c: ^Creature, side: Battle_Side) -> bool {
	if c.hp <= 0 {
		return false
	}
	if c.poison > 0 {
		// Poison phases straight through Block — it's the answer to turtling.
		dmg := max(int(f32(c.max_hp) * POISON_PCT * f32(c.poison)), 1)
		c.hp -= dmg
		spawn_popup(b, side, .DAMAGE, dmg)
		creature_burst(c, popup_color(.POISON), 0.4)
		battle_sfx(.DOT, 0.5)
		battle_log(b, "%s suffers %d poison.", c.name, dmg)
		c.poison -= 1
	}
	if c.burn > 0 {
		// Burn is stopped by Block (Block soaks it), but weakens the burned.
		dmg := max(int(f32(c.max_hp) * BURN_PCT * f32(c.burn)), 1)
		absorbed := min(c.block, dmg)
		c.block -= absorbed
		dmg -= absorbed
		if dmg > 0 {
			c.hp -= dmg
			spawn_popup(b, side, .DAMAGE, dmg)
			battle_log(b, "%s burns for %d.", c.name, dmg)
		} else {
			spawn_popup(b, side, .BLOCK, absorbed)
			battle_log(b, "%s's Block smothers the flames.", c.name)
		}
		creature_burst(c, popup_color(.BURN), 0.4)
		battle_sfx(.DOT, 0.5)
		c.burn -= 1
	}
	if c.regen > 0 && c.hp > 0 {
		heal := max(int(f32(c.max_hp) * REGEN_PCT * f32(c.regen)), 1)
		before := c.hp
		c.hp = min(c.hp + heal, c.max_hp)
		if c.hp > before {
			spawn_popup(b, side, .HEAL, c.hp - before)
			creature_burst(c, popup_color(.HEAL), 0.5)
			battle_sfx(.HEAL, 0.45)
		}
		c.regen -= 1
	}
	if c.hp <= 0 {
		ability_try_survive(b, c) // Resilient: bursts + logs if it saves them
	}
	if c.hp <= 0 {
		c.hp = 0
		battle_log(b, "%s succumbs!", c.name)
		return true
	}
	return false
}

// ----------------------------------------------------------------------------
// Initiative queue: every living monster acts in Speed order. Each pass through
// the queue, a monster plays one card; the queue cycles until nobody can act,
// then a new turn begins (fresh hands + energy).
// ----------------------------------------------------------------------------

actor_speed :: proc(b: ^Battle, a: Actor) -> f32 {
	if a.side == .PLAYER {
		c := b.party[a.index]
		return c.speed + c.speed_buff
	}
	e := b.enemies[a.index]
	return e.speed + e.speed_buff
}

build_order :: proc(b: ^Battle) {
	clear(&b.order)
	// Every living monster on the field: all of your party + all wilds.
	for i in 0..<len(b.party) {
		if b.party[i].hp > 0 {
			append(&b.order, Actor{.PLAYER, i})
		}
	}
	for i in 0..<len(b.enemies) {
		if b.enemies[i].hp > 0 {
			append(&b.order, Actor{.WILD, i})
		}
	}
	// Shuffle so equal speeds are a coin flip, then stable-sort fastest first.
	n := len(b.order)
	for i := n - 1; i > 0; i -= 1 {
		j := rng_below(&b.rng, i + 1)
		b.order[i], b.order[j] = b.order[j], b.order[i]
	}
	for i in 1..<n {
		key := b.order[i]
		ks := actor_speed(b, key)
		j := i - 1
		for j >= 0 && actor_speed(b, b.order[j]) < ks {
			b.order[j + 1] = b.order[j]
			j -= 1
		}
		b.order[j + 1] = key
	}
}

actor_can_act :: proc(b: ^Battle, a: Actor) -> bool {
	if a.side == .PLAYER {
		if a.index < 0 || a.index >= len(b.party) {
			return false
		}
		c := b.party[a.index]
		if b.party_done[a.index] || c.hp <= 0 {
			return false
		}
		for m in c.hand {
			if move_playable(c, move_data(m)) {
				return true
			}
		}
		return false
	}
	if a.index < 0 || a.index >= len(b.enemies) {
		return false
	}
	e := b.enemies[a.index]
	return e.hp > 0 && enemy_has_card(e)
}

set_actor :: proc(b: ^Battle, a: Actor) {
	if a.side == .PLAYER {
		b.active = a.index
		b.phase = .PLAYER_ACTION
		b.timer = b.auto_play ? 0.55 : 0
		if a.index >= 0 && a.index < len(b.party) {
			daze(b, b.party[a.index])
		}
	} else {
		b.enemy_acting = a.index
		b.phase = .ENEMY_ACTION
		b.timer = 0.6
		if a.index >= 0 && a.index < len(b.enemies) {
			daze(b, b.enemies[a.index])
		}
	}
}

// The creature behind an initiative-queue entry, or nil if it is gone.
actor_creature :: proc(b: ^Battle, a: Actor) -> ^Creature {
	if a.side == .PLAYER {
		if a.index >= 0 && a.index < len(b.party) {
			return b.party[a.index]
		}
		return nil
	}
	if a.index >= 0 && a.index < len(b.enemies) {
		return b.enemies[a.index]
	}
	return nil
}

// A stunned creature loses card plays, not its whole turn: when its turn starts
// it fumbles `stun` cards from its hand (discarded, no energy spent) and the
// stun is consumed. So Stun 2 costs it two cards, not the entire round.
daze :: proc(b: ^Battle, c: ^Creature) {
	if c == nil || c.stun <= 0 {
		return
	}
	n := min(c.stun, len(c.hand))
	for _ in 0..<n {
		i := rng_below(&b.rng, len(c.hand))
		append(&c.discard, c.hand[i])
		ordered_remove(&c.hand, i)
	}
	c.stun = 0
	if n > 0 {
		battle_log(b, "%s is dazed — fumbles %d card%s.", c.name, n, n == 1 ? "" : "s")
		creature_burst(c, popup_color(.STUN), 0.5)
		spawn_popup(b, side_of(b, c), .STUN, n)
	}
}

// Hand control to the next monster in the queue that can act, cycling. If a
// full pass finds nobody able to act, the turn ends.
advance :: proc(b: ^Battle) {
	if b.phase == .WON || b.phase == .LOST || b.phase == .CAPTURED {
		return
	}
	n := len(b.order)
	for _ in 0..<n {
		if b.order_pos >= n {
			b.order_pos = 0
		}
		a := b.order[b.order_pos]
		b.order_pos = (b.order_pos + 1) % n
		if actor_can_act(b, a) {
			set_actor(b, a)
			return
		}
	}
	begin_round(b)
}

begin_round :: proc(b: ^Battle) {
	// Safety valve: healing on both sides can stalemate. After MAX_ROUNDS the
	// side with the greater remaining HP fraction wins.
	if b.round >= MAX_ROUNDS {
		pf := hp_fraction(b.party[:])
		ef := hp_fraction(b.enemies[:])
		b.phase = pf >= ef ? .WON : .LOST
		b.timer = 0
		battle_log(b, "The fight drags on - it ends in your %s.", pf >= ef ? "favour" : "disfavour")
		return
	}
	if b.round > 0 {
		for p in b.party {
			before := p.hp
			creature_end_round(b, p)
			if p.hp > before {
				creature_burst(p, popup_color(.HEAL), 0.6)
				spawn_popup(b, .PLAYER, .HEAL, p.hp - before)
			}
		}
		for e in b.enemies {
			before := e.hp
			creature_end_round(b, e)
			if e.hp > before {
				creature_burst(e, popup_color(.HEAL), 0.6)
				spawn_popup(b, .WILD, .HEAL, e.hp - before)
			}
		}
	}
	b.round += 1

	// Boss aura: Dominion strips Strength from every foe each round.
	for p in b.party {
		ability_dominion(b, p)
	}
	for e in b.enemies {
		ability_dominion(b, e)
	}

	// Status effects tick at the start of each round; a DoT can end the fight.
	died := false
	for p in b.party {
		if tick_status(b, p, .PLAYER) {
			died = true
		}
	}
	for e in b.enemies {
		if tick_status(b, e, .WILD) {
			died = true
		}
	}
	if died {
		if enemies_alive(b) == 0 {
			b.phase = .WON
			b.timer = 0
			battle_log(b, "All wilds defeated!")
			return
		}
		if !party_has_alive(b) {
			b.phase = .LOST
			b.timer = 0
			battle_log(b, "Your party has fallen...")
			return
		}
	}

	for i in 0..<len(b.party) {
		b.party_done[i] = false
		creature_begin_round(b, b.party[i], &b.rng)
	}
	for e in b.enemies {
		creature_begin_round(b, e, &b.rng)
	}

	build_order(b)
	b.order_pos = 0
	if len(b.order) > 0 {
		first := b.order[0]
		lead := string("You")
		if first.side == .WILD {
			lead = b.enemies[first.index].name
		}
		battle_log(b, "Turn %d - %s fastest.", b.round, lead)
	}
	advance(b)
}

// ----------------------------------------------------------------------------
// Card resolution
// ----------------------------------------------------------------------------

// ----------------------------------------------------------------------------
// Damage
//
//   damage = move.damage x offense x type_mult x stab_mult x vuln_mult
//                              x defense_mult
//
//   move.damage   - the card's own damage (Move data)
//   offense       - the attacker's attacking stat and its multiplier (see Offense)
//   type_mult     - element effectiveness against the target's types
//   stab_mult     - same-type attack bonus (1.5 when the element matches)
//   vuln_mult     - the target's Vulnerable stacks
//   defense_mult  - the target's defense reduction, 10 / (10 + defense)
// ----------------------------------------------------------------------------

// An attack's offense: the creature stat it attacks with, and the multiplier
// applied to that stat. Normal attacks use power + the strength bonus; a Body
// Press uses defense for both.
Offense :: struct {
	stat: f32,
	mult: f32,
}

move_offense :: proc(m: Move, c: ^Creature) -> Offense {
	if m.offense_stat == .DEFENSE {
		d := creature_defense(c)
		return {stat = d, mult = max(1.0 + 0.1 * d, 0.1)}
	}
	return {stat = c.power, mult = max(1.0 + 0.1 * f32(c.strength), 0.1)}
}

// How much a creature's attacks are weakened by its own Burn stacks.
burn_weaken :: proc(c: ^Creature) -> f32 {
	if c.burn <= 0 {
		return 0
	}
	return min(f32(c.burn) * BURN_WEAKEN_PER_STACK, BURN_WEAKEN_CAP)
}

// Can this creature play this card right now? (X-cost cards need at least 1
// energy; unplayable junk never can.)
move_playable :: proc(c: ^Creature, m: Move) -> bool {
	if m.unplayable {
		return false
	}
	if m.x_cost {
		return c.energy >= 1
	}
	return c.energy >= m.cost
}

apply_damage :: proc(b: ^Battle, attacker: ^Creature, target: ^Creature, base: int, elem: Element, offense: Offense) -> int {
	type_mult := f32(1)
	for de in creature_elements(target) {
		type_mult *= element_multiplier(elem, de)
	}
	stab_mult := f32(1)
	for ae in creature_elements(attacker) {
		if ae == elem {
			stab_mult = 1.5
			break
		}
	}
	vuln_mult := f32(1)
	if target.vulnerable > 0 {
		vuln_mult = VULN_MULT
	}
	defense_mult := 10.0 / (10.0 + creature_defense(target))

	// Ability multipliers: Predator (attacker) and Abyssal (target). Held items
	// add raw damage (Bloodstone) and type-advantage damage (Weakpoint Lens).
	item_mult := item_damage_mult(attacker.item, type_mult > 1.0)
	d := int(f32(base) * offense.stat * offense.mult * type_mult * stab_mult * vuln_mult * defense_mult *
		(1.0 - burn_weaken(attacker)) * ability_attack_mult(attacker, target) * ability_defense_mult(target) * item_mult)
	absorbed := min(target.block, d)
	target.block -= absorbed
	d -= absorbed
	if d > 0 {
		target.hp -= d
		target.shake = CREATURE_SHAKE_DUR
		target.flash = 0.22
		ability_on_hit_taken(b, target) // Vengeance
		// Grudge Idol: a super-effective hit hardens the victim.
		if type_mult > 1.0 {
			if w := ITEM_DATA[target.item].weakness_str; w > 0 {
				target.strength += w
				spawn_popup(b, side_of(b, target), .BUFF, w)
				creature_burst(target, popup_color(.BUFF), 0.5)
			}
		}
		ability_try_survive(b, target) // Resilient
		item_try_save(b, target)       // Grit Charm / Amber Fruit
		battle_sfx(.HIT, 0.8)
	}
	return d
}

// Fraction of the attacker's max HP that `stacks` thorns reflect. Each stack
// multiplies the remaining fraction, so it rises fast at first and then flattens
// — 6.25% at one stack, ~40% at eight, and never 100%.
thorns_fraction :: proc(stacks: int) -> f32 {
	remain := f32(1)
	for _ in 0..<clamp(stacks, 0, 64) {
		remain *= 1.0 - THORNS_HP_PCT
	}
	return 1.0 - remain
}

// Remove the harmful status effects (Poison / Burn / Stun) — a cleanse.
// Returns the number of stacks removed, for the popup.
creature_cleanse_status :: proc(c: ^Creature) -> int {
	n := c.poison + c.burn + c.stun
	c.poison = 0
	c.burn = 0
	c.stun = 0
	return n
}

// Clear every battle modifier (boosts and debuffs) on a creature — Haze.
// Returns the total magnitude removed, for the popup.
creature_clear_boosts :: proc(c: ^Creature) -> int {
	n := abs(c.strength) + abs(c.dexterity) + int(c.defense_buff) + int(c.defense_debuff) + c.vulnerable + c.regen + c.thorns
	c.strength = 0
	c.dexterity = 0
	c.defense_buff = 0
	c.defense_debuff = 0
	c.vulnerable = 0
	c.regen = 0
	c.thorns = 0
	return n
}

// Extra base damage a card gains from the caster's creature stats (block,
// defense, max HP, or the HP it has lost). Additive scaling. Shared by the live
// hit and the tooltip.
move_scaled_damage :: proc(m: Move, c: ^Creature) -> int {
	return int(f32(c.block) * m.scale_block) +
		int(creature_defense(c) * m.scale_defense) +
		int(f32(c.max_hp) * m.scale_max_hp) +
		int(f32(max(c.max_hp - c.hp, 0)) * m.scale_missing_hp) +
		len(c.exhausted) * m.scale_per_exhausted
}

// Damage multiplier from the caster's health: 1.0 at full HP, rising toward
// 1 + mult_missing_hp as it nears death. Shared by the live hit and the tooltip.
move_damage_mult :: proc(m: Move, c: ^Creature) -> f32 {
	if m.mult_missing_hp == 0 {
		return 1
	}
	missing := 1.0 - f32(c.hp) / f32(max(c.max_hp, 1))
	return 1.0 + m.mult_missing_hp * clamp(missing, 0, 1)
}

// Damage a card would deal right now, without mutating anything. Mirrors
// apply_damage (including the synergy bonuses) and also returns the type
// multiplier so the UI can flag super-effective / resisted hits.
estimate_damage :: proc(attacker, target: ^Creature, id: Move_Id, allies := 0) -> (total: int, type_mult: f32) {
	m := MOVE_DATA[id]
	type_mult = 1
	if !move_has_damage(m) || target == nil {
		return 0, type_mult
	}
	// Flat damage bonuses from the move's synergies.
	bonus := 0
	if m.vuln_bonus > 0 && target.vulnerable > 0 {
		bonus += m.vuln_bonus
	}
	if m.block_bonus > 0 && attacker.block > 0 {
		bonus += m.block_bonus
	}
	if m.combo_bonus > 0 && attacker.played > 0 {
		bonus += m.combo_bonus
	}
	if m.execute_bonus > 0 && m.execute_pct > 0 && f32(target.hp) < m.execute_pct * f32(target.max_hp) {
		bonus += m.execute_bonus
	}
	if m.ally_bonus > 0 {
		bonus += m.ally_bonus * allies
	}
	// Multipliers, matching apply_damage.
	for de in creature_elements(target) {
		type_mult *= element_multiplier(m.element, de)
	}
	stab_mult := f32(1)
	for ae in creature_elements(attacker) {
		if ae == m.element {
			stab_mult = 1.5
			break
		}
	}
	vuln_mult := f32(1)
	if target.vulnerable > 0 {
		vuln_mult = VULN_MULT
	}
	defense_mult := 10.0 / (10.0 + creature_defense(target))
	offense := move_offense(m, attacker)
	scaled := move_scaled_damage(m, attacker)
	mult := move_damage_mult(m, attacker)
	// X-cost cards scale with whatever energy the caster has right now.
	dmg_base := m.damage
	if m.x_cost {
		dmg_base *= max(int(attacker.energy), 1)
	}
	total = 0
	for h in 0..<max(m.hits, 1) {
		base := int(f32(dmg_base + scaled) * mult) + (h == 0 ? bonus : 0)
		total += int(f32(base) * offense.stat * offense.mult * type_mult * stab_mult * vuln_mult * defense_mult *
			(1.0 - burn_weaken(attacker)) * ability_attack_mult(attacker, target) * ability_defense_mult(target))
	}
	return total, type_mult
}

side_of :: proc(b: ^Battle, c: ^Creature) -> Battle_Side {
	for e in b.enemies {
		if c == e {
			return .WILD
		}
	}
	return .PLAYER
}

// Combustion: damage every foe at the end of the turn.
power_combustion :: proc(b: ^Battle, c: ^Creature) {
	n := c.powers[.Combustion]
	if n <= 0 {
		return
	}
	d := POWER_COMBUSTION_DMG * n
	hit := false
	foes := side_of(b, c) == .PLAYER ? b.enemies[:] : b.party[:]
	for f in foes {
		if f.hp <= 0 {
			continue
		}
		f.hp -= d
		spawn_popup(b, side_of(b, f), .DAMAGE, d)
		creature_burst(f, popup_color(.DAMAGE), 0.4)
		hit = true
	}
	if hit {
		battle_log(b, "%s's Combustion sears every foe for %d.", c.name, d)
	}
}

// Dominion (boss ability): strip Strength from every foe at the start of a round.
ability_dominion :: proc(b: ^Battle, c: ^Creature) {
	if c.ability != .Dominion {
		return
	}
	foes := side_of(b, c) == .PLAYER ? b.enemies[:] : b.party[:]
	for f in foes {
		if f.hp <= 0 {
			continue
		}
		f.strength -= ABILITY_DOMINION_STR
		spawn_popup(b, side_of(b, f), .WEAKEN, ABILITY_DOMINION_STR)
		creature_burst(f, popup_color(.WEAKEN), 0.4)
	}
}

// Juggernaut: gaining Block deals that much damage to a random living foe.
power_juggernaut :: proc(b: ^Battle, c: ^Creature, gained: int) {
	n := c.powers[.Juggernaut]
	if n <= 0 || gained <= 0 {
		return
	}
	foes := side_of(b, c) == .PLAYER ? b.enemies[:] : b.party[:]
	alive := 0
	for f in foes {
		if f.hp > 0 {
			alive += 1
		}
	}
	if alive == 0 {
		return
	}
	k := rng_below(&b.rng, alive)
	for f in foes {
		if f.hp <= 0 {
			continue
		}
		if k == 0 {
			d := gained * n
			f.hp -= d
			spawn_popup(b, side_of(b, f), .DAMAGE, d)
			creature_burst(f, popup_color(.DAMAGE), 0.4)
			battle_log(b, "%s's Juggernaut slams %s for %d.", c.name, f.name, d)
			return
		}
		k -= 1
	}
}

// How many of the caster's teammates (excluding itself) are still standing.
other_allies_alive :: proc(b: ^Battle, c: ^Creature) -> int {
	n := 0
	if side_of(b, c) == .PLAYER {
		for p in b.party {
			if p != c && p.hp > 0 {
				n += 1
			}
		}
	} else {
		for e in b.enemies {
			if e != c && e.hp > 0 {
				n += 1
			}
		}
	}
	return n
}

// The currently selected teammate, falling back to the acting monster.
ally_target_creature :: proc(b: ^Battle) -> ^Creature {
	i := b.ally_target
	if i >= 0 && i < len(b.party) && b.party[i].hp > 0 {
		return b.party[i]
	}
	if b.active >= 0 && b.active < len(b.party) {
		return b.party[b.active]
	}
	return nil
}

// Who a card lands on, given the kinds it allows and the player's last pick.
// Single-kind cards ignore the selection; flexible ones follow it.
pick_card_target :: proc(b: ^Battle, m: Move) -> ^Creature {
	allowed := move_targets(m)
	c := b.party[b.active]
	if allowed == {.SELF} {
		return c
	}
	if b.sel_kind == .ALLY && .ALLY in allowed {
		return ally_target_creature(b)
	}
	if b.sel_kind == .ENEMY && .ENEMY in allowed {
		return target_enemy(b)
	}
	if .ENEMY in allowed {
		return target_enemy(b)
	}
	if .ALLY in allowed {
		return ally_target_creature(b)
	}
	return c
}

spawn_popup :: proc(b: ^Battle, side: Battle_Side, kind: Popup_Kind, value: int) {
	append(&b.popups, Popup{value = value, kind = kind, side = side, life = 0.95, max_life = 0.95})
}

// Queue per-hit feedback. Events are grouped by `wave` (the hit index), so a
// multi-hit card plays out one hit at a time while a spread (AoE) card — one
// hit, many victims — fires every victim in the same wave.
queue_hit_fx :: proc(b: ^Battle, wave: int, kind: Popup_Kind, value: int, side: Battle_Side, target: ^Creature) {
	if value == 0 {
		return
	}
	append(&b.hit_fx, Hit_Fx{wave = wave, kind = kind, value = value, side = side, target = target})
}

// Play one queued piece of feedback: popup, spark, flinch and cue.
emit_hit_fx :: proc(b: ^Battle, fx: Hit_Fx) {
	spawn_popup(b, fx.side, fx.kind, fx.value)
	if fx.target != nil {
		creature_burst(fx.target, popup_color(fx.kind), 0.45)
		fx.target.shake = CREATURE_SHAKE_DUR * 0.6
		fx.target.flash = 0.18
	}
	#partial switch fx.kind {
	case .DAMAGE:
		b.shake = SHAKE_DUR
		b.shake_mag = clamp(3.0 + f32(fx.value) * 0.4, 3.0, 10.0)
		battle_sfx(.HIT, 0.8)
	case .HEAL:
		battle_sfx(.HEAL, 0.6)
	case .POISON, .BURN:
		battle_sfx(.DOT, 0.5)
	case .BLOCK, .DEFEND:
		battle_sfx(.BLOCK, 0.5)
	case .BUFF, .REGEN, .THORNS:
		battle_sfx(.BUFF, 0.5)
	case:
	}
}

// Drain the feedback queue: every event in the current wave fires at once, then
// the next wave waits HIT_FX_STAGGER.
drain_hit_fx :: proc(b: ^Battle, dt: f32) {
	if len(b.hit_fx) == 0 {
		return
	}
	b.hit_fx_t -= dt
	if b.hit_fx_t > 0 {
		return
	}
	for len(b.hit_fx) > 0 && b.hit_fx[0].wave == b.hit_fx_wave {
		fx := b.hit_fx[0]
		ordered_remove(&b.hit_fx, 0)
		emit_hit_fx(b, fx)
	}
	b.hit_fx_wave += 1
	if len(b.hit_fx) > 0 {
		b.hit_fx_t = HIT_FX_STAGGER
	} else {
		b.hit_fx_wave = 0
		b.hit_fx_t = 0
	}
}

// Fire a battle cue, unless the engine is running silently (headless skirmish).
battle_sfx :: proc(cue: Sfx, volume := f32(0.7)) {
	if !battle_silent {
		audio_play(cue, volume)
	}
}

play_creature_card :: proc(b: ^Battle, c: ^Creature, target: ^Creature, index: int, rng: ^Rng) -> bool {
	if index < 0 || index >= len(c.hand) {
		return false
	}
	id := c.hand[index]
	m := move_data(id)
	if m.unplayable {
		return false // Wound: it only clogs a hand
	}
	// X-cost cards spend the caster's whole bank and scale per energy spent.
	cost := m.cost
	if m.x_cost {
		if c.energy < 1 {
			return false
		}
		cost = c.energy
	}
	if c.energy < cost {
		return false
	}
	c.energy -= cost
	spent := max(int(cost), 1)

	// Damage / block scale with energy for X-cost cards.
	dmg_base := m.damage
	block_gain := m.block
	if m.x_cost {
		dmg_base *= spent
		block_gain *= spent
	}

	self_side := side_of(b, c)

	// Resolve who gets hurt and who gets helped: a target on the caster's own
	// side is a beneficiary (support), an opposing one is a victim (hostile).
	if target == nil {
		c.energy += m.cost // no valid target: refund
		return false
	}
	victim: ^Creature
	benef := c
	if side_of(b, target) == self_side {
		benef = target
	} else {
		victim = target
		if victim.hp <= 0 {
			c.energy += m.cost
			return false
		}
	}
	victim_side := self_side
	if victim != nil {
		victim_side = side_of(b, victim)
	}
	benef_side := side_of(b, benef)

	// Who gets hurt: the chosen victim, or every living foe for an AoE card.
	victims: [24]^Creature
	nvictims := 0
	if m.aoe {
		foes := self_side == .PLAYER ? b.enemies[:] : b.party[:]
		for f in foes {
			if f.hp > 0 && nvictims < len(victims) {
				victims[nvictims] = f
				nvictims += 1
			}
		}
	} else if victim != nil {
		victims[0] = victim
		nvictims = 1
	}

	// --- Damage. One victim, or every foe at once for an AoE card. ---
	if move_has_damage(m) && nvictims > 0 {
		// On-hit effects resolve per hit, which is what gives multi-hit moves an
		// identity: lifesteal drains in several bites, and thorns bite back once
		// per hit, so many small hits heal more but hurt more too.
		leech := m.leech_pct
		if c.ability == .Vampiric {
			leech += ABILITY_VAMPIRIC_PCT
		}
		// Siphon Gland: drain and lifesteal heal more.
		if dm := ITEM_DATA[c.item].drain_mult; dm > 0 {
			leech *= 1.0 + dm
		}

		scaled := move_scaled_damage(m, c)
		mult := move_damage_mult(m, c)
		offense := move_offense(m, c)
		hits := max(m.hits, 1)
		// Ricochet Charm: multi-hit Attacks land one extra hit.
		if m.hits > 1 {
			hits += ITEM_DATA[c.item].extra_hits
		}
		// Aftershock: the first Attack each turn hits twice. (Once per card, not
		// once per victim.)
		if m.kind == .ATTACK && ability_first_attack_doubles(c) && !c.attacked_this_turn {
			hits *= 2
		}
		if m.kind == .ATTACK {
			c.attacked_this_turn = true
		}

		for vi in 0..<nvictims {
			victim := victims[vi]
			victim_side := side_of(b, victim)
			// Flat damage bonuses from this card's synergies, per victim.
			bonus := 0
			if m.vuln_bonus > 0 && victim.vulnerable > 0 {
				bonus += m.vuln_bonus
			}
			if m.block_bonus > 0 && c.block > 0 {
				bonus += m.block_bonus
			}
			if m.combo_bonus > 0 && c.played > 0 {
				bonus += m.combo_bonus
			}
			// Execute: extra damage against a badly hurt foe.
			if m.execute_bonus > 0 && m.execute_pct > 0 && f32(victim.hp) < m.execute_pct * f32(victim.max_hp) {
				bonus += m.execute_bonus
			}
			// Teamwork: extra damage for every other ally still standing.
			if m.ally_bonus > 0 {
				bonus += m.ally_bonus * other_allies_alive(b, c)
			}

			total := 0
			for hit in 0..<hits {
				base := int(f32(dmg_base + scaled) * mult) + (hit == 0 ? bonus : 0)
				hit_dmg := apply_damage(b, c, victim, base, m.element, offense)
				total += hit_dmg
				if hit_dmg <= 0 {
					continue
				}
				// The damage has landed; the feedback is queued per hit so a
				// multi-hit card reads as several impacts (see `queue_hit_fx`).
				queue_hit_fx(b, hit, .DAMAGE, hit_dmg, victim_side, victim)
				if leech > 0 {
					heal := max(int(f32(hit_dmg) * leech), 1)
					before := c.hp
					c.hp = min(c.hp + heal, c.max_hp)
					queue_hit_fx(b, hit, .HEAL, c.hp - before, self_side, c)
				}
				if victim.thorns > 0 {
					back := max(int(f32(c.max_hp) * thorns_fraction(victim.thorns)), 1)
					c.hp -= back
					victim.thorns -= 1 // a stack is spent on each hit
					queue_hit_fx(b, hit, .DAMAGE, back, self_side, c)
					battle_log(b, "%s's thorns bite %s for %d.", victim.name, c.name, back)
				}
				// Sanguine: a flat heal per hit landed (multi-hit friendly).
				if h := power_on_hit_heal(c); h > 0 {
					before := c.hp
					c.hp = min(c.hp + h, c.max_hp)
					queue_hit_fx(b, hit, .HEAL, c.hp - before, self_side, c)
				}
				// Toxic (power) + Envenom (ability): every hit applies Poison.
				if tp := power_toxic_poison(c) + ability_on_hit_poison(c); tp > 0 {
					victim.poison += tp
					queue_hit_fx(b, hit, .POISON, tp, victim_side, victim)
				}
			}
			if total > 0 {
				c.shake = CREATURE_SHAKE_DUR * 0.4
			}
		}
		c.shake = CREATURE_SHAKE_DUR * 0.4
	}
	// Beneficial effects land on the beneficiary (the ally, or the caster).
	if m.block > 0 {
		gained := block_gain + benef.dexterity // Dexterity adds to every Block gain
		benef.block += gained
		spawn_popup(b, benef_side, .BLOCK, gained)
		creature_burst(benef, popup_color(.BLOCK), 0.5)
		power_juggernaut(b, benef, gained)
	}
	if m.dexterity != 0 {
		benef.dexterity += m.dexterity
		spawn_popup(b, benef_side, .DEFEND, m.dexterity)
		creature_burst(benef, popup_color(.DEFEND), 0.55)
	}
	if m.double_block && benef.block > 0 {
		gained := benef.block
		benef.block += gained
		spawn_popup(b, benef_side, .BLOCK, gained)
		creature_burst(benef, popup_color(.BLOCK), 0.6)
		power_juggernaut(b, benef, gained)
	}
	if m.strength > 0 {
		benef.strength += m.strength
		spawn_popup(b, benef_side, .BUFF, m.strength)
		creature_burst(benef, popup_color(.BUFF), 0.55)
	}
	if m.double_strength && benef.strength > 0 {
		gained := benef.strength
		benef.strength += gained
		spawn_popup(b, benef_side, .BUFF, gained)
		creature_burst(benef, popup_color(.BUFF), 0.65)
	}
	if m.defense > 0 {
		benef.defense_buff += m.defense
		spawn_popup(b, benef_side, .DEFEND, int(m.defense))
		creature_burst(benef, popup_color(.DEFEND), 0.55)
	}
	if m.speed > 0 {
		benef.speed_buff += m.speed
		spawn_popup(b, benef_side, .BUFF, int(m.speed))
		creature_burst(benef, popup_color(.BUFF), 0.55)
	}
	if m.regen > 0 {
		benef.regen += m.regen
		spawn_popup(b, benef_side, .REGEN, m.regen)
		creature_burst(benef, popup_color(.REGEN), 0.5)
	}
	if m.thorns > 0 {
		benef.thorns += m.thorns
		spawn_popup(b, benef_side, .THORNS, m.thorns)
		creature_burst(benef, popup_color(.THORNS), 0.5)
	}
	if m.heal_pct > 0 {
		heal := max(int(f32(benef.max_hp) * m.heal_pct), 1)
		before := benef.hp
		benef.hp = min(benef.hp + heal, benef.max_hp)
		if benef.hp > before {
			spawn_popup(b, benef_side, .HEAL, benef.hp - before)
			creature_burst(benef, popup_color(.HEAL), 0.6)
		}
	}
	if m.energy_give > 0 {
		benef.energy = min(benef.energy + f32(m.energy_give), benef.energy_max)
		spawn_popup(b, benef_side, .ENERGY, m.energy_give)
		creature_burst(benef, popup_color(.ENERGY), 0.5)
	}
	// Hostile effects land on every victim (one, or all foes for an AoE card).
	for vi in 0..<nvictims {
		victim := victims[vi]
		victim_side := side_of(b, victim)
		if m.vulnerable > 0 {
			victim.vulnerable += m.vulnerable
			spawn_popup(b, victim_side, .DEBUFF, m.vulnerable)
			creature_burst(victim, popup_color(.DEBUFF), 0.5)
		}
		if m.strength_down > 0 {
			victim.strength -= m.strength_down
			spawn_popup(b, victim_side, .WEAKEN, m.strength_down)
			creature_burst(victim, popup_color(.WEAKEN), 0.5)
		}
		if m.dexterity_down > 0 {
			victim.dexterity -= m.dexterity_down
			spawn_popup(b, victim_side, .WEAKEN, m.dexterity_down)
			creature_burst(victim, popup_color(.WEAKEN), 0.5)
		}
		if m.defense_down > 0 {
			victim.defense_debuff += m.defense_down
			spawn_popup(b, victim_side, .SHATTER, int(m.defense_down))
			creature_burst(victim, popup_color(.SHATTER), 0.5)
		}
		// Venom Sac: this creature's Poison and Burn bite deeper.
		status_bonus := ITEM_DATA[c.item].status_bonus
		if m.poison > 0 {
			applied := m.poison + status_bonus
			victim.poison += applied
			spawn_popup(b, victim_side, .POISON, applied)
			creature_burst(victim, popup_color(.POISON), 0.5)
		}
		if m.burn > 0 {
			applied := m.burn + status_bonus
			victim.burn += applied
			spawn_popup(b, victim_side, .BURN, applied)
			creature_burst(victim, popup_color(.BURN), 0.5)
		}
		if m.double_poison && victim.poison > 0 {
			victim.poison *= 2
			spawn_popup(b, victim_side, .POISON, victim.poison)
			creature_burst(victim, popup_color(.POISON), 0.65)
		}
		if m.double_burn && victim.burn > 0 {
			victim.burn *= 2
			spawn_popup(b, victim_side, .BURN, victim.burn)
			creature_burst(victim, popup_color(.BURN), 0.65)
		}
		if m.stun > 0 {
			victim.stun += m.stun
			spawn_popup(b, victim_side, .STUN, m.stun)
			creature_burst(victim, popup_color(.STUN), 0.5)
		}
		if m.energy_drain > 0 {
			before := victim.energy
			victim.energy = max(victim.energy - f32(m.energy_drain), 0)
			gained := int(before - victim.energy)
			if gained > 0 {
				c.energy = min(c.energy + f32(gained), c.energy_max)
				spawn_popup(b, self_side, .ENERGY, gained)
				spawn_popup(b, victim_side, .ENERGY, -gained)
				creature_burst(victim, popup_color(.ENERGY), 0.5)
			}
		}
		// Energy sabotage: burn the target's energy away (the caster gains none).
		if m.energy_burn > 0 {
			before := victim.energy
			victim.energy = max(victim.energy - f32(m.energy_burn), 0)
			lost := int(before - victim.energy)
			if lost > 0 {
				spawn_popup(b, victim_side, .ENERGY, -lost)
				creature_burst(victim, popup_color(.ENERGY), 0.5)
				battle_log(b, "%s burns away %d of %s's energy.", c.name, lost, victim.name)
			}
		}
	}
	// Bloodstone recoil: every Attack costs the holder a slice of its max HP.
	if pct := ITEM_DATA[c.item].self_damage_pct; pct > 0 && m.kind == .ATTACK {
		recoil := max(int(f32(c.max_hp) * pct), 1)
		c.hp -= recoil
		queue_hit_fx(b, 0, .DAMAGE, recoil, self_side, c)
		battle_log(b, "%s's Bloodstone burns it for %d.", c.name, recoil)
	}
	// Self-costs: paid by the caster no matter the target.
	if m.self_strength_down > 0 {
		c.strength -= m.self_strength_down
		spawn_popup(b, self_side, .WEAKEN, m.self_strength_down)
		creature_burst(c, popup_color(.WEAKEN), 0.5)
	}
	if m.self_defense_down > 0 {
		c.defense_debuff += m.self_defense_down
		spawn_popup(b, self_side, .SHATTER, int(m.self_defense_down))
		creature_burst(c, popup_color(.SHATTER), 0.5)
	}
	if m.self_damage > 0 {
		c.hp -= m.self_damage
		spawn_popup(b, self_side, .DAMAGE, m.self_damage)
		creature_burst(c, popup_color(.DAMAGE), 0.4)
	}
	if m.draw > 0 && !m.discard_hand {
		creature_draw(c, m.draw, rng)
		spawn_popup(b, self_side, .DRAW, m.draw)
		battle_sfx(.CLICK, 0.4)
	}
	// Haze: wipe the target's modifiers, whichever side it's on.
	if m.clear_boosts {
		wiped := creature_clear_boosts(target)
		creature_burst(target, popup_color(.DEBUFF), 0.6)
		if wiped > 0 {
			spawn_popup(b, side_of(b, target), .CLEAR, wiped)
		}
		battle_sfx(.CANCEL, 0.5)
		battle_log(b, "%s's boosts are wiped away.", target.name)
	}
	// Cleanse: strip Poison / Burn / Stun from the beneficiary.
	if m.cleanse_status {
		wiped := creature_cleanse_status(benef)
		creature_burst(benef, popup_color(.HEAL), 0.6)
		if wiped > 0 {
			spawn_popup(b, benef_side, .CLEAR, wiped)
		}
		battle_sfx(.HEAL, 0.5)
		battle_log(b, "%s is cleansed.", benef.name)
	}
	// Powers: grant a persistent per-battle effect to the caster.
	if m.grant_power != .NONE {
		n := max(m.power_stacks, 1)
		c.powers[m.grant_power] += n
		spawn_popup(b, self_side, .BUFF, n)
		creature_burst(c, popup_color(.BUFF), 0.65)
		battle_log(b, "%s gains %s.", c.name, power_name(m.grant_power))
	}
	// Rage: gain Block whenever you play an Attack.
	if m.kind == .ATTACK {
		if blk := power_rage_block(c); blk > 0 {
			c.block += blk
			spawn_popup(b, self_side, .BLOCK, blk)
			creature_burst(c, popup_color(.BLOCK), 0.5)
			power_juggernaut(b, c, blk)
		}
	}
	// Cards this card creates: into a battle pile, or permanently into the deck.
	// `add_to_target` sends them to the target's piles instead (junk cards).
	if m.add_count > 0 {
		dst := c
		if m.add_to_target && target != nil {
			dst = target
		}
		for _ in 0..<m.add_count {
			switch m.add_where {
			case .HAND:    append(&dst.hand, m.add_move)
			case .DRAW:    append(&dst.draw_pile, m.add_move)
			case .DISCARD: append(&dst.discard, m.add_move)
			case .DECK:    append(&dst.deck, m.add_move)
			}
		}
		spawn_popup(b, side_of(b, dst), .JUNK, m.add_count)
		creature_burst(dst, popup_color(.JUNK), 0.5)
		battle_sfx(.ERROR, 0.5)
		battle_log(b, "%s adds %d %s to %s.", c.name, m.add_count, MOVE_DATA[m.add_move].name, dst.name)
	}

	ordered_remove(&c.hand, index)
	if m.exhaust {
		append(&c.exhausted, id) // spent for the rest of the battle
		// Scavenger: draw for each card that exhausts.
		if n := power_on_exhaust_draw(c); n > 0 {
			creature_draw(c, n, rng)
			spawn_popup(b, self_side, .DRAW, n)
			battle_sfx(.CLICK, 0.4)
		}
	} else {
		append(&c.discard, id)
	}
	// Hand manipulation: dump or burn the rest of your hand.
	if m.discard_hand || m.exhaust_hand {
		n := len(c.hand)
		for card in c.hand {
			if m.exhaust_hand {
				append(&c.exhausted, card)
			} else {
				append(&c.discard, card)
			}
		}
		clear(&c.hand)
		if n > 0 {
			spawn_popup(b, self_side, .CLEAR, n)
			creature_burst(c, popup_color(.CLEAR), 0.5)
			battle_sfx(.CANCEL, 0.5)
		}
		if m.discard_hand {
			creature_draw(c, n + m.draw, rng) // Gambit: draw back more than you threw away
			spawn_popup(b, self_side, .DRAW, n + m.draw)
		} else if sc := power_on_exhaust_draw(c); sc > 0 {
			creature_draw(c, sc * n, rng)
			spawn_popup(b, self_side, .DRAW, sc * n)
		}
	}
	c.played += 1
	return true
}

player_play :: proc(b: ^Battle, index: int) {
	if b.phase != .PLAYER_ACTION {
		return
	}
	c := b.party[b.active]
	// The card's allowed targets (and the player's last pick) decide who it hits.
	tgt: ^Creature
	if index >= 0 && index < len(c.hand) {
		tgt = pick_card_target(b, move_data(c.hand[index]))
	}
	if play_creature_card(b, c, tgt, index, &b.rng) {
		if !battle_silent {
			audio_play(.CLICK, 0.7)
		}
		fix_target(b)
		if enemies_alive(b) == 0 {
			b.phase = .WON
			b.timer = 0
			battle_log(b, "All wilds defeated!")
			return
		}
		if !party_has_alive(b) {
			b.phase = .LOST
			b.timer = 0
			battle_log(b, "Your party has fallen...")
			return
		}
		advance(b)
	}
}

player_end_round :: proc(b: ^Battle) {
	if b.phase != .PLAYER_ACTION {
		return
	}
	if b.active >= 0 && b.active < len(b.party_done) {
		b.party_done[b.active] = true
	}
	battle_log(b, "%s ends its turn.", b.party[b.active].name)
	advance(b)
}

// ----------------------------------------------------------------------------
// Enemy AI
// ----------------------------------------------------------------------------

choose_enemy_card :: proc(c: ^Creature) -> int {
	best := -1
	best_val := -1
	for card, i in c.hand {
		md := move_data(card)
		if !move_playable(c, md) {
			continue
		}
		v := move_value(card)
		if v > best_val {
			best_val = v
			best = i
		}
	}
	return best
}

enemy_step :: proc(b: ^Battle) {
	if b.phase != .ENEMY_ACTION {
		return
	}
	if len(b.enemies) == 0 || b.enemy_acting < 0 || b.enemy_acting >= len(b.enemies) {
		advance(b)
		return
	}
	wild := b.enemies[b.enemy_acting]

	if wild.hp <= 0 {
		advance(b)
		return
	}

	idx := choose_enemy_card(wild)
	if idx < 0 {
		advance(b)
		return
	}

	target := pick_party_target(b)
	if target == nil {
		advance(b)
		return
	}

	m := move_data(wild.hand[idx])
	play_creature_card(b, wild, target, idx, &b.rng)
	battle_log(b, "%s uses %s on %s.", wild.name, m.name, target.name)

	if target.hp <= 0 {
		target.hp = 0
		battle_log(b, "%s fainted!", target.name)
		if !party_has_alive(b) {
			b.phase = .LOST
			b.timer = 0
			battle_log(b, "Your party has fallen...")
			return
		}
	}
	advance(b)
}

// A wild picks a random living party member to attack (no taunt/front line).
pick_party_target :: proc(b: ^Battle) -> ^Creature {
	alive := 0
	for p in b.party {
		if p.hp > 0 {
			alive += 1
		}
	}
	if alive == 0 {
		return nil
	}
	k := rng_below(&b.rng, alive)
	for p in b.party {
		if p.hp > 0 {
			if k == 0 {
				return p
			}
			k -= 1
		}
	}
	return nil
}

party_has_alive :: proc(b: ^Battle) -> bool {
	for c in b.party {
		if c.hp > 0 {
			return true
		}
	}
	return false
}

// ----------------------------------------------------------------------------
// Player-only actions: capture
// ----------------------------------------------------------------------------

capture_chance :: proc(b: ^Battle) -> f32 {
	t := target_enemy(b)
	if t == nil || t.max_hp <= 0 {
		return 0
	}
	frac := f32(t.max_hp-t.hp) / f32(t.max_hp)
	base := clamp(frac, 0, 1) * 0.9
	// Higher level and rarer species are harder to catch.
	lvl_mult := 1.0 / (1.0 + 0.08 * f32(max(t.level - 1, 0)))
	// A Snare Kit on any of your monsters, plus the colony's Scout upgrade.
	bonus := b.capture_bonus
	for p in b.party {
		bonus = max(bonus, ITEM_DATA[p.item].capture_pct)
	}
	return clamp(base * lvl_mult * rarity_catch_mult(species_rarity(t.species)) + bonus, 0, 1)
}

attempt_capture :: proc(b: ^Battle) {
	if b.phase != .PLAYER_ACTION {
		return
	}
	if len(b.enemies) == 0 {
		return
	}
	if b.capture_cards <= 0 {
		battle_log(b, "No capture card! Buy one at a Trading Post.")
		return
	}
	b.capture_cards -= 1

	chance := capture_chance(b)
	if rng_f32(&b.rng) < chance {
		// Capture the targeted enemy: record its colony id, drop it from the fight.
		if b.target >= 0 && b.target < len(b.enemy_ids) {
			append(&b.captured_ids, b.enemy_ids[b.target])
		}
		spawn_popup(b, .WILD, .CAPTURE, 0)
		battle_log(b, "You captured %s!", target_enemy(b).name)
		remove_enemy_index(b, b.target)
		fix_target(b)
		if len(b.enemies) == 0 || enemies_alive(b) == 0 {
			b.phase = .WON
			b.timer = 0
			return
		}
		advance(b)
	} else {
		spawn_popup(b, .PLAYER, .CAPTURE, 0)
		battle_log(b, "Capture failed! (%d%% chance)", int(chance * 100))
		advance(b)
	}
}

// ----------------------------------------------------------------------------
// Update
// ----------------------------------------------------------------------------

battle_update :: proc(b: ^Battle, dt: f32) {
	// Visual timers always tick.
	if b.shake > 0 {
		b.shake = max(b.shake - dt, 0)
	}
	for i in 0..<len(b.party) {
		c := b.party[i]
		if c.shake > 0 { c.shake = max(c.shake - dt, 0) }
		if c.flash > 0 { c.flash = max(c.flash - dt, 0) }
		if c.fx_t > 0 { c.fx_t = max(c.fx_t - dt, 0) }
	}
	for e in b.enemies {
		if e.shake > 0 { e.shake = max(e.shake - dt, 0) }
		if e.flash > 0 { e.flash = max(e.flash - dt, 0) }
		if e.fx_t > 0 { e.fx_t = max(e.fx_t - dt, 0) }
	}

	i := 0
	for i < len(b.popups) {
		b.popups[i].life -= dt
		if b.popups[i].life <= 0 {
			unordered_remove(&b.popups, i)
		} else {
			i += 1
		}
	}

	// Play out queued per-hit feedback (waves of one hit index at a time).
	drain_hit_fx(b, dt)

	if b.phase == .WON || b.phase == .LOST || b.phase == .CAPTURED {
		b.timer += dt
		return
	}
	if b.phase == .ENEMY_ACTION {
		b.timer -= dt
		if b.timer <= 0 {
			enemy_step(b)
		}
	}
	if b.phase == .PLAYER_ACTION && b.auto_play {
		b.timer -= dt
		if b.timer <= 0 {
			player_ai_step(b)
		}
	}
}

// Auto-fight: the AI plays the player's side with the same greedy heuristic.
player_ai_step :: proc(b: ^Battle) {
	c := b.party[b.active]
	best := -1
	best_val := -1
	for card, i in c.hand {
		md := move_data(card)
		if !move_playable(c, md) {
			continue
		}
		v := move_value(card)
		if v > best_val {
			best_val = v
			best = i
		}
	}
	if best >= 0 {
		// Support-only cards need a teammate: aim at whoever has the least energy.
		if .ENEMY not_in move_targets(move_data(c.hand[best])) {
			low := -1
			low_e := f32(1 << 30)
			for p, i in b.party {
				if p.hp <= 0 {
					continue
				}
				if p.energy < low_e {
					low_e = p.energy
					low = i
				}
			}
			if low >= 0 {
				b.ally_target = low
			}
			b.sel_kind = .ALLY
		} else {
			b.sel_kind = .ENEMY
		}
		player_play(b, best)
	} else {
		player_end_round(b)
	}
}

// ----------------------------------------------------------------------------
// Input
// ----------------------------------------------------------------------------

end_turn_rect :: proc() -> rl.Rectangle {
	sw := f32(screen_w())
	sh := f32(screen_h())
	return rl.Rectangle{sw - 236, sh - 122, 216, 46}
}

capture_rect :: proc() -> rl.Rectangle {
	sw := f32(screen_w())
	sh := f32(screen_h())
	return rl.Rectangle{sw - 236, sh - 176, 216, 46}
}

battle_input :: proc(b: ^Battle) {
	// Pile viewer toggle works even in auto-fights, and while open it's modal.
	if rl.IsKeyPressed(.D) {
		b.show_piles = !b.show_piles
		return
	}
	if b.show_piles {
		if rl.IsKeyPressed(.ESCAPE) {
			b.show_piles = false
		}
		return
	}
	if b.auto_play {
		return // auto-fight: no player input
	}
	mp := mouse_pos()

	// Pile readout is clickable in any phase.
	if rl.IsMouseButtonPressed(.LEFT) {
		if rl.CheckCollisionPointRec(mp, pile_draw_rect()) || rl.CheckCollisionPointRec(mp, pile_discard_rect()) {
			b.show_piles = true
			return
		}
	}

	// Scroll the enemy row (the wheel, or the [ and ] keys) whenever a pack is
	// wider than the field. Works in any phase — it only moves the view.
	if len(b.enemies) > enemy_visible_count() {
		if w := rl.GetMouseWheelMove(); w != 0 {
			enemy_scroll(b, w > 0 ? -1 : 1)
		}
		if rl.IsKeyPressed(.LEFT_BRACKET) {
			enemy_scroll(b, -1)
		}
		if rl.IsKeyPressed(.RIGHT_BRACKET) {
			enemy_scroll(b, 1)
		}
		// The arrows either side of the row are clickable, too.
		if rl.IsMouseButtonPressed(.LEFT) {
			if rl.CheckCollisionPointRec(mp, enemy_arrow_rect(true)) {
				enemy_scroll(b, -1)
				return
			}
			if rl.CheckCollisionPointRec(mp, enemy_arrow_rect(false)) {
				enemy_scroll(b, 1)
				return
			}
		}
	}

	if b.phase != .PLAYER_ACTION {
		return
	}

	if rl.IsKeyPressed(.E) || rl.IsKeyPressed(.SPACE) {
		player_end_round(b)
		return
	}
	if rl.IsKeyPressed(.C) {
		attempt_capture(b)
		return
	}
	for key, i in DIGIT_KEYS {
		if rl.IsKeyPressed(key) {
			player_play(b, i)
			return
		}
	}

	if rl.IsMouseButtonPressed(.LEFT) {
		if rl.CheckCollisionPointRec(mp, end_turn_rect()) {
			player_end_round(b)
			return
		}
		if rl.CheckCollisionPointRec(mp, capture_rect()) {
			attempt_capture(b)
			return
		}
		// Click an enemy to target it (only the ones currently on screen).
		visible := enemy_visible_count()
		first := enemy_first_index(b)
		for slot in 0..<visible {
			i := first + slot
			if i >= len(b.enemies) {
				break
			}
			if b.enemies[i].hp > 0 && rl.CheckCollisionPointRec(mp, enemy_rect(b, i)) {
				b.target = i
				b.sel_kind = .ENEMY
				enemy_scroll_to(b, i)
				return
			}
		}
		// Click a teammate to target them, the same way as an enemy.
		for i in 0..<len(b.party) {
			if b.party[i].hp > 0 && rl.CheckCollisionPointRec(mp, party_field_rect(i, len(b.party))) {
				b.ally_target = i
				b.sel_kind = .ALLY
				return
			}
		}
		hand := b.party[b.active].hand
		for i in 0..<len(hand) {
			if rl.CheckCollisionPointRec(mp, hand_card_rect(i, len(hand))) {
				player_play(b, i)
				return
			}
		}
	}
}

// ----------------------------------------------------------------------------
// Rendering
// ----------------------------------------------------------------------------

COL_BG     :: rl.Color{10, 10, 16, 255}
COL_FLOOR  :: rl.Color{17, 17, 26, 255}
COL_PANEL  :: rl.Color{24, 24, 34, 255}
COL_HP     :: rl.Color{200, 62, 62, 255}
COL_HP_BG  :: rl.Color{52, 26, 30, 255}
COL_BLOCK  :: rl.Color{88, 150, 230, 255}
COL_VULN   :: rl.Color{190, 90, 200, 255}
COL_ENERGY :: rl.Color{242, 200, 70, 255}
COL_TEXT   :: rl.Color{228, 228, 238, 255}
COL_MUTED  :: rl.Color{140, 140, 158, 255}

CARD_W :: f32(124)
CARD_H :: f32(168)
CARD_HOVER_LIFT :: f32(14) // how far a hovered hand card rises

hand_card_rect :: proc(index, count: int) -> rl.Rectangle {
	sw := f32(screen_w())
	sh := f32(screen_h())
	spacing := CARD_W + 12
	total := f32(count) * spacing - 12
	if total < 0 { total = 0 }
	start := sw / 2 - total / 2
	return rl.Rectangle{start + f32(index) * spacing, sh - CARD_H - 22, CARD_W, CARD_H}
}

draw_bar :: proc(rec: rl.Rectangle, value, max_value: int, fill: rl.Color) {
	rl.DrawRectangleRounded(rec, 0.5, 8, COL_HP_BG)
	frac := f32(0)
	if max_value > 0 {
		frac = clamp(f32(value) / f32(max_value), 0, 1)
	}
	if frac > 0 {
		rl.DrawRectangleRounded(rl.Rectangle{rec.x, rec.y, rec.width * frac, rec.height}, 0.5, 8, fill)
	}
	rl.DrawRectangleRoundedLinesEx(rec, 0.5, 8, 2, rl.Color{12, 12, 16, 255})
}

shake_offset :: proc(mag: f32) -> (f32, f32) {
	t := f32(rl.GetTime())
	return math.sin(t * 71.0) * mag, math.cos(t * 57.0) * mag
}

creature_offset :: proc(c: ^Creature) -> (f32, f32) {
	if c.shake <= 0 {
		return 0, 0
	}
	mag := (c.shake / CREATURE_SHAKE_DUR) * 9.0
	t := f32(rl.GetTime())
	return math.sin(t * 90.0) * mag, math.cos(t * 80.0) * mag
}

popup_anchor :: proc(b: ^Battle, side: Battle_Side) -> rl.Vector2 {
	sw := f32(screen_w())
	if side == .WILD {
		return rl.Vector2{sw / 2, 232}
	}
	return rl.Vector2{64, 78}
}

popup_text :: proc(p: Popup) -> cstring {
	switch p.kind {
	case .DAMAGE:  return fmt.ctprintf("-%d", p.value)
	case .BLOCK:   return fmt.ctprintf("+%d blk", p.value)
	case .HEAL:    return fmt.ctprintf("+%d", p.value)
	case .BUFF:    return fmt.ctprintf("+%d str", p.value)
	case .DEFEND:  return fmt.ctprintf("+%d def", p.value)
	case .DEBUFF:  return fmt.ctprintf("+%d vuln", p.value)
	case .WEAKEN:  return fmt.ctprintf("-%d str", p.value)
	case .SHATTER: return fmt.ctprintf("-%d def", p.value)
	case .CAPTURE: return "!"
	case .POISON:  return fmt.ctprintf("+%d psn", p.value)
	case .BURN:    return fmt.ctprintf("+%d brn", p.value)
	case .STUN:    return fmt.ctprintf("stun %d", p.value)
	case .REGEN:   return fmt.ctprintf("+%d reg", p.value)
	case .THORNS:  return fmt.ctprintf("+%d thr", p.value)
	case .ENERGY:  return fmt.ctprintf("+%d en", p.value)
	case .DRAW:    return fmt.ctprintf("+%d card", p.value)
	case .JUNK:    return fmt.ctprintf("+%d junk", p.value)
	case .CLEAR:   return fmt.ctprintf("%d wiped", p.value)
	}
	return ""
}

popup_color :: proc(k: Popup_Kind) -> rl.Color {
	switch k {
	case .DAMAGE:  return rl.Color{255, 120, 110, 255}
	case .BLOCK:   return rl.Color{120, 180, 245, 255}
	case .HEAL:    return rl.Color{130, 235, 140, 255}
	case .BUFF:    return rl.Color{245, 210, 110, 255}
	case .DEFEND:  return rl.Color{120, 235, 210, 255}
	case .DEBUFF:  return rl.Color{210, 120, 230, 255}
	case .WEAKEN:  return rl.Color{240, 130, 120, 255}
	case .SHATTER: return rl.Color{240, 150, 100, 255}
	case .CAPTURE: return rl.Color{140, 210, 255, 255}
	case .POISON:  return rl.Color{170, 90, 200, 255}
	case .BURN:    return rl.Color{255, 150, 70, 255}
	case .STUN:    return rl.Color{250, 240, 130, 255}
	case .REGEN:   return rl.Color{130, 235, 140, 255}
	case .THORNS:  return rl.Color{150, 220, 150, 255}
	case .ENERGY:  return rl.Color{245, 205, 90, 255}
	case .DRAW:    return rl.Color{180, 200, 245, 255}
	case .JUNK:    return rl.Color{170, 140, 120, 255}
	case .CLEAR:   return rl.Color{205, 205, 220, 255}
	}
	return COL_TEXT
}

draw_popups :: proc(b: ^Battle) {
	for p in b.popups {
		t := 1.0 - p.life / p.max_life
		anchor := popup_anchor(b, p.side)
		x := anchor.x + f32((p.value * 37) % 41 - 20) * 0.8
		y := anchor.y - 30 - t * 55
		alpha := u8(clamp(p.life / p.max_life * 1.8, 0, 1) * 255)
		col := popup_color(p.kind)
		txt := popup_text(p)
		tw := rl.MeasureText(txt, 26)
		rl.DrawText(txt, i32(x) - tw / 2 + 2, i32(y) + 2, 26, rl.Color{0, 0, 0, alpha})
		rl.DrawText(txt, i32(x) - tw / 2, i32(y), 26, rl.Color{col[0], col[1], col[2], alpha})
	}
}

draw_energy :: proc(x, y, width, current, maximum: f32, preview: f32 = 0) {
	h := f32(16)
	rec := rl.Rectangle{x, y - h / 2, width, h}
	rl.DrawRectangleRounded(rec, 0.5, 8, rl.Color{42, 38, 26, 255})
	total := max(maximum, 0.0001)
	frac := clamp(current / total, 0, 1)
	if frac > 0 {
		rl.DrawRectangleRounded(rl.Rectangle{x, y - h / 2, width * frac, h}, 0.5, 8, COL_ENERGY)
	}
	// Dim segment showing how much energy you'll generate next turn.
	if preview > 0 {
		pv := clamp((current + preview) / total, 0, 1)
		if pv > frac {
			rl.DrawRectangleRec(rl.Rectangle{x + width * frac, y - h / 2, width * (pv - frac), h}, rl.Color{COL_ENERGY[0], COL_ENERGY[1], COL_ENERGY[2], 120})
		}
	}
	rl.DrawRectangleRoundedLinesEx(rec, 0.5, 8, 2, rl.Color{12, 12, 16, 255})
	txt := preview > 0 ? fmt.ctprintf("%s / %s   +%s per turn", fmt_num(current), fmt_num(maximum), fmt_num(preview)) : fmt.ctprintf("%s / %s", fmt_num(current), fmt_num(maximum))
	rl.DrawText(txt, i32(x), i32(y) + 12, 13, COL_MUTED)
}

draw_creature_avatar :: proc(center: rl.Vector2, radius: f32, c: ^Creature, dead: bool) {
	base := creature_color(c)
	if dead {
		base = rl.Color{60, 60, 70, 255}
	}
	rl.DrawCircleV(center, radius, base)
	rl.DrawCircleLinesV(center, radius, rl.Color{235, 235, 245, 255})
	// element ring
	rl.DrawCircleLinesV(center, radius - 4, element_color(creature_element(c)))
	initial := fmt.ctprintf("%c", c.name[0])
	w := rl.MeasureText(initial, i32(radius))
	rl.DrawText(initial, i32(center.x) - w / 2, i32(center.y) - i32(radius) / 2, i32(radius), rl.Color{255, 255, 255, 255})

	if c.flash > 0 {
		a := u8(clamp(c.flash / 0.22, 0, 1) * 180)
		rl.DrawCircleV(center, radius, rl.Color{255, 255, 255, a})
	}

	// Effect burst: an expanding coloured ring (heal / block / buff / debuff).
	if c.fx_t > 0 && c.fx_dur > 0 {
		t := 1.0 - c.fx_t / c.fx_dur
		a := u8(clamp((1.0 - t) * 230, 0, 230))
		col := rl.Color{c.fx_col[0], c.fx_col[1], c.fx_col[2], a}
		ring := radius + 4 + t * 26
		rl.DrawRing(center, ring, ring + 4, 0, 360, 48, col)
		rl.DrawCircleV(center, radius + 2, rl.Color{c.fx_col[0], c.fx_col[1], c.fx_col[2], u8(f32(a) * 0.20)})
	}
}

draw_card :: proc(id: Move_Id, rec: rl.Rectangle, playable_in, hovered: bool) {
	m := move_data(id)
	playable := playable_in && !m.unplayable // Wound can't be played
	r := rec
	if hovered && playable {
		r.y -= CARD_HOVER_LIFT
	}

	base := element_color(m.element)
	fill := rl.Color{u8(f32(base[0]) * 0.30), u8(f32(base[1]) * 0.30), u8(f32(base[2]) * 0.30), 255}
	if !playable {
		fill = rl.Color{28, 28, 36, 255}
	}

	rl.DrawRectangleRounded(r, 0.14, 8, fill)

	outline := base
	if !playable {
		outline = rl.Color{90, 90, 104, 255}
	}
	rl.DrawRectangleRoundedLinesEx(r, 0.14, 8, 2, outline)

	// Card-kind band across the top (Attack / Skill / Power).
	rl.DrawRectangleRounded(rl.Rectangle{r.x + 7, r.y + 4, r.width - 14, 5}, 0.5, 4, card_kind_color(m.kind))

	// Top-right marker for hand-behaviour cards: R = Retain, E = Ethereal.
	if m.retain || m.ethereal {
		lbl := m.retain ? cstring("R") : cstring("E")
		col := m.retain ? rl.Color{150, 210, 255, 255} : rl.Color{200, 160, 230, 255}
		lw := rl.MeasureText(lbl, 12)
		rl.DrawText(lbl, i32(r.x + r.width) - lw - 7, i32(r.y) + 7, 12, col)
	}

	cc := rl.Vector2{r.x + 19, r.y + 19}
	rl.DrawCircleV(cc, 14, rl.Color{30, 34, 52, 255})
	rl.DrawCircleLinesV(cc, 14, base)
	cost := m.x_cost ? cstring("X") : fmt_num(m.cost)
	cw := rl.MeasureText(cost, 18)
	rl.DrawText(cost, i32(cc.x) - cw / 2, i32(cc.y) - 9, 18, COL_TEXT)

	name := fmt.ctprintf("%s", m.name)
	nw := rl.MeasureText(name, 16)
	rl.DrawText(name, i32(r.x + r.width / 2) - nw / 2, i32(r.y + 40), 16, COL_TEXT)

	desc := fmt.ctprintf("%s", m.desc)
	dw := rl.MeasureText(desc, 13)
	rl.DrawText(desc, i32(r.x + r.width / 2) - dw / 2, i32(r.y + r.height - 30), 13, rl.Color{215, 215, 228, 255})

	elem := element_name(m.element)
	ew := rl.MeasureText(elem, 11)
	rl.DrawText(elem, i32(r.x + r.width / 2) - ew / 2, i32(r.y + r.height - 14), 11, base)

	if hovered {
		tag: cstring = ""
		switch {
		case m.x_cost:       tag = "X-cost, "
		case m.retain:       tag = "Retain, "
		case m.ethereal:     tag = "Ethereal, "
		case m.discard_hand: tag = "Discards hand, "
		case m.exhaust_hand: tag = "Exhausts hand, "
		case m.cleanse_status: tag = "Cleanse, "
		}
		tooltip_set("%s [%s %s]  -  %s  (%s, %s%s)", m.name, card_kind_name(m.kind), card_rarity_name(m.rarity), m.desc, elem, tag, move_target_label(m))
	}
}

draw_battle :: proc(b: ^Battle) {
	sw := f32(screen_w())
	sh := f32(screen_h())

	rl.ClearBackground(COL_BG)

	// Screen shake: shift the whole world layer.
	sx, sy := f32(0), f32(0)
	if b.shake > 0 {
		mag := b.shake_mag * (b.shake / SHAKE_DUR)
		sx, sy = shake_offset(mag)
	}

	rl.BeginMode2D(ui_camera(sx, sy))
	rl.DrawRectangle(0, i32(sh * 0.58), i32(sw), i32(sh * 0.42), COL_FLOOR)
	draw_enemies(b)
	draw_player_panel(b)
	draw_target_panel(b)
	draw_party_field(b, sw, sh)
	draw_hand(b)
	draw_popups(b)
	// Re-enter the scaled space for the HUD layer. (EndMode2D would reset the
	// transform to identity, dropping the UI scale.)
	rl.BeginMode2D(ui_camera())

	// Round + action indicator.
	if b.phase == .PLAYER_ACTION || b.phase == .ENEMY_ACTION {
		label := b.phase == .PLAYER_ACTION ? cstring("YOUR MOVE") : cstring("ENEMY MOVE")
		col := b.phase == .PLAYER_ACTION ? rl.Color{140, 240, 190, 255} : rl.Color{240, 140, 120, 255}
		ind := fmt.ctprintf("Turn %d   -   %s", b.round, label)
		iw := rl.MeasureText(ind, 22)
		rl.DrawText(ind, i32(sw) / 2 - iw / 2, 14, 22, col)
	}
	draw_initiative(b)

	draw_buttons(b)
	draw_battle_log(b)
	draw_pile_readout(b)

	if b.phase == .WON {
		draw_center_overlay("VICTORY", "Click to claim your reward", rl.Color{120, 230, 150, 255}, b.timer)
	} else if b.phase == .LOST {
		draw_center_overlay("DEFEAT", "Click to continue", rl.Color{235, 90, 90, 255}, b.timer)
	} else if b.phase == .CAPTURED {
		draw_center_overlay("CAPTURED!", "Click to return to the map", rl.Color{120, 200, 255, 255}, b.timer)
	}

	if b.show_piles {
		draw_piles(b)
	}
}

// The upcoming initiative order: a row of chips showing who acts next.
draw_initiative :: proc(b: ^Battle) {
	sw := f32(screen_w())
	n := len(b.order)
	if n == 0 {
		return
	}
	count := min(n, 9)
	chip_w := f32(70)
	gap := f32(6)
	// Keep the bar inside the gap between the two corner panels.
	gap_w := max(sw - 2 * (PANEL_MARGIN + PANEL_W) - 20, 200)
	count = min(count, max(int((gap_w + gap) / (chip_w + gap)), 1))
	total := f32(count) * chip_w + f32(count - 1) * gap
	x := sw / 2 - total / 2
	y := f32(44)
	start := (b.order_pos - 1 + n) % n
	rl.DrawText("NEXT", i32(x), i32(y) + 34, 12, rl.Color{150, 150, 170, 255})
	for k in 0..<count {
		a := b.order[(start + k) % n]
		c := actor_creature(b, a)
		if c == nil {
			continue
		}
		rec := rl.Rectangle{x + f32(k) * (chip_w + gap), y, chip_w, 30}
		is_now := k == 0
		col := element_color(creature_element(c))
		bg := is_now ? rl.Color{u8(f32(col[0]) * 0.45), u8(f32(col[1]) * 0.45), u8(f32(col[2]) * 0.45), 255} : rl.Color{24, 26, 34, 235}
		rl.DrawRectangleRounded(rec, 0.25, 5, bg)
		rl.DrawRectangleRoundedLinesEx(rec, 0.25, 5, 2, is_now ? col : rl.Color{70, 74, 90, 255})
		dot := a.side == .PLAYER ? rl.Color{140, 230, 160, 255} : rl.Color{235, 90, 90, 255}
		rl.DrawCircleV(rl.Vector2{rec.x + 8, rec.y + 15}, 4, dot)
		name := fmt.ctprintf("%s", c.name)
		nw := rl.MeasureText(name, 11)
		rl.DrawText(name, i32(rec.x + chip_w / 2) - nw / 2 + 4, i32(rec.y) + 9, 11, rl.Color{230, 235, 245, 255})
	}
}

// ----------------------------------------------------------------------------
// Enemy row layout
//
// The row is a full-width band *below* the two corner panels, so a whole Arena
// team (six challengers) fits on screen at once with no scrolling. Only a wider
// pack than that scrolls (wheel, `[` / `]`, or the arrows either side).
// ----------------------------------------------------------------------------
PANEL_W      :: f32(340)
PANEL_H      :: f32(180)
PANEL_MARGIN :: f32(16)
ENEMY_CARD_W :: f32(132)
ENEMY_EY     :: f32(272)
// How far the card reaches above / below its centre line.
ENEMY_ROW_TOP :: f32(72)
ENEMY_ROW_BOT :: f32(78)
ENEMY_ROW_PAD :: f32(34)

// The full-width band the enemy row lives in.
enemy_row_band :: proc() -> (left, right: f32) {
	sw := f32(screen_w())
	return ENEMY_ROW_PAD, sw - ENEMY_ROW_PAD
}

// How many enemy cards fit in the row.
enemy_visible_count :: proc() -> int {
	l, r := enemy_row_band()
	return max(1, int((r - l) / ENEMY_CARD_W))
}

// The leftmost enemy currently on screen.
enemy_first_index :: proc(b: ^Battle) -> int {
	n := len(b.enemies)
	visible := enemy_visible_count()
	return clamp(b.enemy_first, 0, max(n - visible, 0))
}

// Centre x of visible slot `slot` (0-based) out of `spread` slots, spread evenly
// across the row. A pack smaller than the row is centred rather than bunched to
// the left.
enemy_slot_x :: proc(slot, spread: int) -> f32 {
	l, r := enemy_row_band()
	step := (r - l) / f32(max(spread, 1))
	return l + (f32(slot) + 0.5) * step
}

// The clickable rect for enemy `i` in the scrolled row.
enemy_rect :: proc(b: ^Battle, i: int) -> rl.Rectangle {
	spread := min(enemy_visible_count(), len(b.enemies))
	first := enemy_first_index(b)
	ex := enemy_slot_x(i - first, spread)
	return rl.Rectangle{ex - ENEMY_CARD_W / 2, ENEMY_EY - ENEMY_ROW_TOP, ENEMY_CARD_W, ENEMY_ROW_TOP + ENEMY_ROW_BOT}
}

// The clickable scroll arrows either side of the row.
enemy_arrow_rect :: proc(left: bool) -> rl.Rectangle {
	l, r := enemy_row_band()
	x := left ? l - 24 : r - 4
	return rl.Rectangle{x, ENEMY_EY - 24, 28, 48}
}

// Scroll the row the least amount needed to bring enemy `i` on screen.
enemy_scroll_to :: proc(b: ^Battle, i: int) {
	visible := enemy_visible_count()
	if i < b.enemy_first {
		b.enemy_first = i
	} else if i >= b.enemy_first + visible {
		b.enemy_first = i - visible + 1
	}
	b.enemy_first = clamp(b.enemy_first, 0, max(len(b.enemies) - visible, 0))
}

// Scroll by `step` slots, clamped to the row.
enemy_scroll :: proc(b: ^Battle, step: int) {
	visible := enemy_visible_count()
	b.enemy_first = clamp(b.enemy_first + step, 0, max(len(b.enemies) - visible, 0))
}
// ----------------------------------------------------------------------------
// Active combat boosts (Strength / Defense / Block / Vulnerable) and the
// damage multiplier each one contributes, so the player can read them at a
// glance. Strength and Defense are flat bonuses, so their multiplier is shown
// relative to the creature's average attack (STR) / a typical incoming hit
// (DEF).
// ----------------------------------------------------------------------------

Effect_Kind :: enum { STR, DEF, DEX, BLOCK, VULN, PSN, BRN, STUN, REGEN, THORNS, PWR }
Effect :: struct {
	kind:  Effect_Kind,
	value: int,
	mult:  f32, // damage multiplier this boost contributes (0 = not applicable)
}

build_effects :: proc(c: ^Creature) -> ([16]Effect, int) {
	out: [16]Effect
	n := 0
	if c.strength != 0 {
		// Each Strength point is a flat +10% damage multiplier (debuffs can push
		// it below 1.0).
		out[n] = {.STR, c.strength, max(1.0 + 0.1 * f32(c.strength), 0.1)}
		n += 1
	}
	if c.defense_buff != 0 || c.defense_debuff != 0 {
		net := creature_defense(c) - c.defense
		if net != 0 {
			// Incoming-damage multiplier: defense before/after the temporary change.
			out[n] = {.DEF, int(math.round(net)), (10.0 + c.defense) / (10.0 + creature_defense(c))}
			n += 1
		}
	}
	if c.block > 0 {
		out[n] = {.BLOCK, c.block, 0}
		n += 1
	}
	if c.dexterity != 0 {
		out[n] = {.DEX, c.dexterity, 0}
		n += 1
	}
	if c.vulnerable > 0 {
		out[n] = {.VULN, c.vulnerable, VULN_MULT}
		n += 1
	}
	if c.poison > 0 {
		out[n] = {.PSN, c.poison, 0}
		n += 1
	}
	if c.burn > 0 {
		out[n] = {.BRN, c.burn, 0}
		n += 1
	}
	if c.stun > 0 {
		out[n] = {.STUN, c.stun, 0}
		n += 1
	}
	if c.regen > 0 {
		out[n] = {.REGEN, c.regen, 0}
		n += 1
	}
	if c.thorns > 0 {
		out[n] = {.THORNS, c.thorns, 0}
		n += 1
	}
	// Active powers (Barricade, Demon Form, ...). value = the power, mult = stacks.
	for p in Power {
		if p == .NONE || c.powers[p] <= 0 {
			continue
		}
		if n >= len(out) {
			break
		}
		out[n] = {.PWR, int(p), f32(c.powers[p])}
		n += 1
	}
	return out, n
}

effect_chip_text :: proc(e: Effect) -> cstring {
	switch e.kind {
	case .STR:
		if e.mult > 1.001 || e.mult < 0.999 {
			return fmt.ctprintf("STR%+d x%.2f", e.value, e.mult)
		}
		return fmt.ctprintf("STR%+d", e.value)
	case .DEF:
		if e.mult > 1.001 || e.mult < 0.999 {
			return fmt.ctprintf("DEF%+d x%.2f", e.value, e.mult)
		}
		return fmt.ctprintf("DEF%+d", e.value)
	case .BLOCK:
		return fmt.ctprintf("BLK %d", e.value)
	case .DEX:
		return fmt.ctprintf("DEX %+d", e.value)
	case .VULN:
		return fmt.ctprintf("VULN %d", e.value)
	case .PSN:
		return fmt.ctprintf("PSN %d", e.value)
	case .BRN:
		return fmt.ctprintf("BRN %d", e.value)
	case .STUN:
		return fmt.ctprintf("STUN %d", e.value)
	case .REGEN:
		return fmt.ctprintf("REG %d", e.value)
	case .THORNS:
		return fmt.ctprintf("THR %d", e.value)
	case .PWR:
		return fmt.ctprintf("%s %d", power_name(Power(e.value)), int(e.mult))
	}
	return ""
}

effect_chip_color :: proc(e: Effect) -> rl.Color {
	switch e.kind {
	case .STR:
		return e.value < 0 ? rl.Color{235, 120, 115, 255} : rl.Color{245, 175, 95, 255}
	case .DEF:
		return e.value < 0 ? rl.Color{235, 120, 115, 255} : rl.Color{115, 225, 200, 255}
	case .BLOCK:
		return COL_BLOCK
	case .DEX:
		return e.value < 0 ? rl.Color{235, 120, 115, 255} : rl.Color{150, 220, 250, 255}
	case .VULN:
		return COL_VULN
	case .PSN:
		return rl.Color{170, 90, 200, 255}
	case .BRN:
		return rl.Color{255, 150, 70, 255}
	case .STUN:
		return rl.Color{250, 240, 130, 255}
	case .REGEN:
		return rl.Color{130, 235, 140, 255}
	case .THORNS:
		return rl.Color{150, 220, 150, 255}
	case .PWR:
		return rl.Color{200, 150, 240, 255}
	}
	return COL_TEXT
}

effect_tooltip :: proc(e: Effect) -> string {
	switch e.kind {
	case .STR:    return fmt.aprintf("Strength: +10%% damage per point (now %+d).", e.value)
	case .DEF:    return fmt.aprintf("Defence: scales incoming damage down (net %+d).", e.value)
	case .BLOCK:  return fmt.aprintf("Block: soaks the next %d damage this round.", e.value)
	case .DEX:    return fmt.aprintf("Dexterity: every Block gain is %+d.", e.value)
	case .VULN:   return fmt.aprintf("Vulnerable: takes +50%% damage for %d more turn(s).", e.value)
	case .PSN:    return fmt.aprintf("Poison: %d stack(s) — loses HP each round, phasing through Block, then decays.", e.value)
	case .BRN:    return fmt.aprintf("Burn: %d stack(s) — loses HP each round (Block soaks it) and deals %d%% less damage, then decays.", e.value, int(min(f32(e.value)*BURN_WEAKEN_PER_STACK, BURN_WEAKEN_CAP)*100))
	case .STUN:   return fmt.aprintf("Stunned: skips its next %d action(s).", e.value)
	case .REGEN:  return fmt.aprintf("Regen: heals %d HP at the start of each round, then decays.", e.value)
	case .THORNS: return fmt.aprintf("Thorns: %d stack(s) — reflects a slice of the attacker's max HP on each hit, and a stack is spent.", e.value)
	case .PWR:    return fmt.aprintf("%s", power_desc(Power(e.value)))
	}
	return ""
}

draw_effect_chip :: proc(x, y: f32, text: cstring, col: rl.Color) -> f32 {
	w := f32(rl.MeasureText(text, 13)) + 12
	rec := rl.Rectangle{x, y, w, 19}
	rl.DrawRectangleRounded(rec, 0.45, 4, rl.Color{col[0] / 5, col[1] / 5, col[2] / 5, 235})
	rl.DrawRectangleRoundedLinesEx(rec, 0.45, 4, 1, col)
	rl.DrawText(text, i32(x) + 6, i32(y) + 3, 13, col)
	return w
}

// Centered chip row clamped to `max_w`: chips that don't fit collapse into a
// `+N` tail, so a panel can never be overrun by a long boost list.
draw_effects_row_clamped :: proc(effects: []Effect, center_x, y: f32, max_w: f32) {
	n := len(effects)
	if n == 0 {
		return
	}
	fit := n
	for fit > 0 {
		w := f32(0)
		for i in 0..<fit {
			w += f32(rl.MeasureText(effect_chip_text(effects[i]), 13)) + 16
		}
		if fit < n {
			w += f32(rl.MeasureText(fmt.ctprintf("+%d", n - fit), 13)) + 8
		}
		if w - 4 <= max_w {
			break
		}
		fit -= 1
	}
	w := f32(0)
	for i in 0..<fit {
		w += f32(rl.MeasureText(effect_chip_text(effects[i]), 13)) + 16
	}
	tw := f32(0)
	if fit < n {
		tw = f32(rl.MeasureText(fmt.ctprintf("+%d", n - fit), 13)) + 8
	}
	total := max(w - 4, 0) + tw
	x := center_x - total / 2
	if fit < n {
		rl.DrawText(fmt.ctprintf("+%d", n - fit), i32(x), i32(y) + 3, 13, COL_MUTED)
		x += tw
	}
	for i in 0..<fit {
		w2 := draw_effect_chip(x, y, effect_chip_text(effects[i]), effect_chip_color(effects[i]))
		if rl.CheckCollisionPointRec(mouse_pos(), rl.Rectangle{x, y, w2, 19}) {
			tooltip_set_owned(effect_tooltip(effects[i]))
		}
		x += w2 + 4
	}
}

draw_enemies :: proc(b: ^Battle) {
	sw := f32(screen_w())
	n := len(b.enemies)
	visible := enemy_visible_count()
	first := enemy_first_index(b)
	spread := min(visible, n)
	ey := ENEMY_EY
	cw := ENEMY_CARD_W

	for slot in 0..<visible {
		i := first + slot
		if i >= n {
			break
		}
		e := b.enemies[i]
		ex := enemy_slot_x(slot, spread)
		radius := f32(32)
		ox, oy := creature_offset(e)
		draw_creature_avatar(rl.Vector2{ex + ox, ey + oy}, radius, e, e.hp <= 0)

		name := fmt.ctprintf("%s", e.name)
		nw := rl.MeasureText(name, 14)
		rl.DrawText(name, i32(ex) - nw / 2, i32(ey) - 70, 14, COL_TEXT)

		// Level, then the enemy's element types as coloured chips.
		lvl := fmt.ctprintf("Lv%d", e.level)
		lw := rl.MeasureText(lvl, 11)
		els := creature_elements(e)
		chip_gap := f32(4)
		total_w := f32(lw)
		for el in els {
			total_w += f32(rl.MeasureText(element_name(el), 10)) + 7 + chip_gap
		}
		x0 := ex - total_w / 2
		rl.DrawText(lvl, i32(x0), i32(ey) - 56, 11, rl.Color{175, 175, 195, 255})
		ccx := x0 + f32(lw) + chip_gap
		for el in els {
			txt := element_name(el)
			w := f32(rl.MeasureText(txt, 10)) + 7
			crec := rl.Rectangle{ccx, ey - 58, w, 14}
			col := element_color(el)
			rl.DrawRectangleRounded(crec, 0.4, 4, rl.Color{col[0] / 5, col[1] / 5, col[2] / 5, 235})
			rl.DrawRectangleRoundedLinesEx(crec, 0.4, 4, 1, col)
			rl.DrawText(txt, i32(ccx) + 4, i32(ey) - 56, 10, col)
			ccx += w + chip_gap
		}

		if e.ability != .NONE {
			ab := ability_name(e.ability)
			aw := rl.MeasureText(ab, 11)
			rl.DrawText(ab, i32(ex) - aw / 2, i32(ey) - 41, 11, rl.Color{200, 180, 240, 255})
		}

		hp_rec := rl.Rectangle{ex - cw / 2 + 4, ey + 38, cw - 8, 14}
		draw_bar(hp_rec, e.hp, e.max_hp, COL_HP)
		hp_txt := fmt.ctprintf("%d/%d", e.hp, e.max_hp)
		hw := rl.MeasureText(hp_txt, 10)
		rl.DrawText(hp_txt, i32(ex) - hw / 2, i32(hp_rec.y) + 1, 10, COL_TEXT)

		// Energy (the same pool the wild uses on the colony map).
		en_rec := rl.Rectangle{ex - cw / 2 + 4, ey + 56, cw - 8, 5}
		draw_bar(en_rec, int(e.energy * 100), int(max(e.energy_max, 0.01) * 100), COL_ENERGY)
		en_txt := fmt.ctprintf("En %s/%s", fmt_num(e.energy), fmt_num(e.energy_max))
		ew := rl.MeasureText(en_txt, 10)
		rl.DrawText(en_txt, i32(ex) - ew / 2, i32(en_rec.y) + 6, 10, COL_TEXT)

		// Active boosts as compact colour-coded dots — the full chips for the
		// selected target live in the target panel, so a card stays narrow.
		effs, ne := build_effects(e)
		draw_effect_dots(effs[:ne], ex, ey + 74, 6)

		if i == b.target && e.hp > 0 {
			rl.DrawCircleLinesV(rl.Vector2{ex, ey}, radius + 5, rl.Color{255, 235, 140, 255})
		} else if i == b.enemy_acting && e.hp > 0 && b.phase == .ENEMY_ACTION {
			rl.DrawCircleLinesV(rl.Vector2{ex, ey}, radius + 10, rl.Color{240, 140, 120, 200})
		}
	}

	// Scroll affordances when the pack is wider than the row.
	if n > visible {
		hint := fmt.ctprintf("%d-%d of %d   (wheel, [ ] or the arrows)", first + 1, min(first + visible, n), n)
		hw := rl.MeasureText(hint, 13)
		// Above the row: the space below it belongs to your party.
		rl.DrawText(hint, i32(sw) / 2 - hw / 2, i32(ey) - 88, 13, COL_MUTED)
		l, r := enemy_row_band()
		mp := mouse_pos()
		draw_scroll_arrow(l - 20, ey, true, first > 0, rl.CheckCollisionPointRec(mp, enemy_arrow_rect(true)))
		draw_scroll_arrow(r - 16, ey, false, first + visible < n, rl.CheckCollisionPointRec(mp, enemy_arrow_rect(false)))
	}
}

// A scroll arrow either side of the enemy row. Dimmed when there is nothing
// left to scroll to, and highlighted on hover so it reads as clickable.
draw_scroll_arrow :: proc(x, ey: f32, left, active, hovered: bool) {
	col := rl.Color{110, 112, 128, 255}
	if active {
		col = hovered ? rl.Color{255, 240, 200, 255} : rl.Color{205, 205, 220, 255}
	}
	txt := left ? cstring("<") : cstring(">")
	w := rl.MeasureText(txt, 26)
	rl.DrawText(txt, i32(x) + (28 - w) / 2, i32(ey) - 14, 26, col)
}

// A compact stand-in for the full chip row: one small colour-coded dot per
// active boost, capped, with a `+N` tail.
draw_effect_dots :: proc(effects: []Effect, center_x, y: f32, max_dots: int) {
	n := min(len(effects), max_dots)
	if n <= 0 {
		return
	}
	dot := f32(9)
	gap := f32(4)
	total := f32(n) * dot + f32(n - 1) * gap
	x := center_x - total / 2
	for i in 0..<n {
		col := effect_chip_color(effects[i])
		rl.DrawCircleV(rl.Vector2{x + dot / 2, y + dot / 2}, dot / 2, col)
		rl.DrawCircleLinesV(rl.Vector2{x + dot / 2, y + dot / 2}, dot / 2, rl.Color{16, 16, 22, 255})
		x += dot + gap
	}
	if len(effects) > n {
		rl.DrawText(fmt.ctprintf("+%d", len(effects) - n), i32(x) + 2, i32(y), 12, COL_MUTED)
	}
}

vfmt :: proc(b: ^Battle, format: string, args: ..any) -> cstring {
	return fmt.ctprintf(format, ..args)
}

draw_player_panel :: proc(b: ^Battle) {
	c := b.party[b.active]
	panel := rl.Rectangle{PANEL_MARGIN, PANEL_MARGIN, PANEL_W, PANEL_H}
	rl.DrawRectangleRounded(panel, 0.10, 8, COL_PANEL)
	rl.DrawRectangleRoundedLinesEx(panel, 0.10, 8, 2, rl.Color{60, 60, 78, 255})

	ox, oy := creature_offset(c)
	draw_creature_avatar(rl.Vector2{panel.x + 46 + ox, panel.y + 60 + oy}, 32, c, false)

	tx := panel.x + 88 // text column
	name := fmt.ctprintf("%s", c.name)
	rl.DrawText(name, i32(tx), i32(panel.y) + 12, 22, COL_TEXT)
	if c.ability != .NONE {
		ab := ability_name(c.ability)
		aw := rl.MeasureText(ab, 14)
		rl.DrawText(ab, i32(panel.x + panel.width) - aw - 12, i32(panel.y) + 20, 14, rl.Color{200, 180, 240, 255})
	}
	// Stats on two lines: the whole row never fits the panel on one.
	line1 := fmt.ctprintf("Lvl %d  %s", c.level, element_label(c))
	rl.DrawText(line1, i32(tx), i32(panel.y) + 40, 14, element_color(creature_element(c)))
	line2 := fmt.ctprintf("PWR x%s  DEF %s  SPD %s", fmt_num(c.power), fmt_num(creature_defense(c)), fmt_num(c.speed))
	rl.DrawText(line2, i32(tx), i32(panel.y) + 56, 14, rl.Color{190, 190, 210, 255})

	hp_rec := rl.Rectangle{tx, panel.y + 76, panel.width - 88 - 12, 20}
	draw_bar(hp_rec, c.hp, c.max_hp, COL_HP)
	hp_txt := fmt.ctprintf("%d / %d", c.hp, c.max_hp)
	rl.DrawText(hp_txt, i32(hp_rec.x) + 8, i32(hp_rec.y) + 2, 15, COL_TEXT)

	// XP toward the next level.
	need := xp_to_next(c.level)
	xp_rec := rl.Rectangle{tx, panel.y + 100, 190, 6}
	rl.DrawRectangleRounded(xp_rec, 0.5, 4, rl.Color{32, 36, 50, 255})
	xf := clamp(f32(c.xp) / f32(max(need, 1)), 0, 1)
	if xf > 0 {
		rl.DrawRectangleRounded(rl.Rectangle{xp_rec.x, xp_rec.y, xp_rec.width * xf, xp_rec.height}, 0.5, 4, rl.Color{150, 210, 255, 255})
	}
	rl.DrawText(fmt.ctprintf("XP %d/%d", c.xp, need), i32(tx) + 196, i32(panel.y) + 96, 11, rl.Color{150, 210, 255, 255})
	piles := vfmt(b, "deck %d", len(c.deck))
	rl.DrawText(piles, i32(panel.x + panel.width) - rl.MeasureText(piles, 11) - 12, i32(panel.y) + 96, 11, COL_MUTED)

	draw_energy(tx, panel.y + 124, panel.width - 88 - 12, c.energy, c.energy_max, c.energy_regen)

	// Active boosts, each with the damage multiplier it contributes.
	effs, ne := build_effects(c)
	draw_effects_row_clamped(effs[:ne], panel.x + panel.width / 2, panel.y + 158, panel.width - 24)
}

// The selected target, mirrored into the top-right corner: the same shape as the
// player panel, so both sides of the fight read the same way — avatar, name,
// ability, level/type/stats, HP, energy, rarity and the target's active boosts.
draw_target_panel :: proc(b: ^Battle) {
	if b.target < 0 || b.target >= len(b.enemies) {
		return
	}
	e := b.enemies[b.target]
	sw := f32(screen_w())
	panel := rl.Rectangle{sw - PANEL_MARGIN - PANEL_W, PANEL_MARGIN, PANEL_W, PANEL_H}
	rl.DrawRectangleRounded(panel, 0.10, 8, COL_PANEL)
	rl.DrawRectangleRoundedLinesEx(panel, 0.10, 8, 2, rl.Color{60, 60, 78, 255})

	// Avatar hugs the outer edge and the text runs inward, mirroring the player
	// panel on the other side.
	ox, oy := creature_offset(e)
	draw_creature_avatar(rl.Vector2{panel.x + panel.width - 46 + ox, panel.y + 60 + oy}, 32, e, e.hp <= 0)

	right := i32(panel.x + panel.width) - 88 // mirrored text column
	name := fmt.ctprintf("%s", e.name)
	nw := rl.MeasureText(name, 22)
	rl.DrawText(name, right - nw, i32(panel.y) + 12, 22, COL_TEXT)
	if e.ability != .NONE {
		rl.DrawText(ability_name(e.ability), i32(panel.x) + 12, i32(panel.y) + 20, 14, rl.Color{200, 180, 240, 255})
	}
	// Rarity is worth knowing before you spend a capture card on it.
	rl.DrawText(rarity_name(SPECIES[e.species].rarity), i32(panel.x) + 12, i32(panel.y) + 41, 12, rarity_color(SPECIES[e.species].rarity))

	line1 := fmt.ctprintf("Lvl %d  %s", e.level, element_label(e))
	l1w := rl.MeasureText(line1, 14)
	rl.DrawText(line1, right - l1w, i32(panel.y) + 40, 14, element_color(creature_element(e)))
	line2 := fmt.ctprintf("PWR x%s  DEF %s  SPD %s", fmt_num(e.power), fmt_num(creature_defense(e)), fmt_num(e.speed))
	l2w := rl.MeasureText(line2, 14)
	rl.DrawText(line2, right - l2w, i32(panel.y) + 56, 14, rl.Color{190, 190, 210, 255})

	hp_rec := rl.Rectangle{panel.x + 12, panel.y + 76, panel.width - 88 - 12, 20}
	draw_bar(hp_rec, e.hp, e.max_hp, COL_HP)
	hp_txt := fmt.ctprintf("%d / %d", e.hp, e.max_hp)
	rl.DrawText(hp_txt, i32(hp_rec.x) + 8, i32(hp_rec.y) + 2, 15, COL_TEXT)

	draw_energy(panel.x + 12, panel.y + 124, panel.width - 88 - 12, e.energy, e.energy_max, e.energy_regen)

	// Active boosts, each with the damage multiplier it contributes.
	effs, ne := build_effects(e)
	draw_effects_row_clamped(effs[:ne], panel.x + panel.width / 2, panel.y + 158, panel.width - 24)
}

// Your party, drawn as info cards on the field (bottom strip): avatar, name,
// level/element, HP numbers, energy, active buff chips, and ability/item. The
// acting monster is ringed, monsters that have ended their turn are dimmed, and
// the dead are greyed out.
// The on-field party card rect (used for drawing and for ally targeting).
party_field_rect :: proc(i, n: int) -> rl.Rectangle {
	sw := f32(screen_w())
	gap := f32(10)
	cw := min(f32(178), (sw - 60 - gap * f32(n - 1)) / f32(n))
	ch := f32(100)
	total := f32(n) * cw + gap * f32(n - 1)
	start := sw / 2 - total / 2
	// Sit above the hand *and* above the hovered card's damage tooltip.
	top := hand_card_rect(0, 1).y - CARD_HOVER_LIFT - 60 - ch
	return rl.Rectangle{start + f32(i) * (cw + gap), top, cw, ch}
}

draw_party_field :: proc(b: ^Battle, sw, sh: f32) {
	n := len(b.party)
	if n == 0 {
		return
	}
	for c, i in b.party {
		rec := party_field_rect(i, n)
		x := rec.x
		top := rec.y
		cw := rec.width
		dead := c.hp <= 0
		done := b.party_done[i]
		active := i == b.active && b.phase == .PLAYER_ACTION && !dead

		bg := rl.Color{24, 26, 34, 240}
		if dead {
			bg = rl.Color{20, 18, 22, 240}
		} else if done {
			bg = rl.Color{18, 20, 26, 240}
		}
		rl.DrawRectangleRounded(rec, 0.09, 6, bg)
		border := rl.Color{56, 58, 72, 255}
		if active {
			border = rl.Color{120, 230, 180, 255}
		} else if dead {
			border = rl.Color{74, 52, 58, 255}
		}
		rl.DrawRectangleRoundedLinesEx(rec, 0.09, 6, 2, border)
		// The monster whose turn it is wears the big outer ring — it is the one
		// that matters right now. (The selected teammate only gets a thin inner
		// border, so it can't be mistaken for the acting monster.)
		if active && !dead {
			rl.DrawRectangleRoundedLinesEx(rl.Rectangle{rec.x - 4, rec.y - 4, rec.width + 8, rec.height + 8}, 0.09, 6, 3, rl.Color{120, 230, 180, 255})
		}
		if i == b.ally_target && b.phase == .PLAYER_ACTION && !dead {
			rl.DrawRectangleRoundedLinesEx(rl.Rectangle{rec.x + 2, rec.y + 2, rec.width - 4, rec.height - 4}, 0.09, 6, 2, rl.Color{255, 225, 130, 255})
		}

		ox, oy := creature_offset(c)
		draw_creature_avatar(rl.Vector2{x + 30 + ox, top + 38 + oy}, 23, c, dead)

		name_col := COL_TEXT
		if dead {
			name_col = rl.Color{120, 120, 130, 255}
		} else if done {
			name_col = rl.Color{165, 165, 180, 255}
		}
		rl.DrawText(fmt.ctprintf("%s", c.name), i32(x) + 60, i32(top) + 6, 15, name_col)
		rl.DrawText(fmt.ctprintf("Lvl %d  %s", c.level, element_label(c)), i32(x) + 60, i32(top) + 23, 13, element_color(creature_element(c)))

		hp := rl.Rectangle{x + 60, top + 42, cw - 72, 14}
		draw_bar(hp, c.hp, c.max_hp, COL_HP)
		ht := fmt.ctprintf("%d/%d", c.hp, c.max_hp)
		hw := rl.MeasureText(ht, 12)
		rl.DrawText(ht, i32(x + 60 + (cw - 72) / 2) - hw / 2, i32(top) + 43, 12, COL_TEXT)

		en := rl.Rectangle{x + 60, top + 58, cw - 72, 6}
		draw_bar(en, int(c.energy * 100), int(max(c.energy_max, 0.01) * 100), COL_ENERGY)

		// Active buffs as chips along the bottom-left.
		effs, ne := build_effects(c)
		cx := x + 9
		for e in effs[:ne] {
			w := draw_effect_chip(cx, top + 66, effect_chip_text(e), effect_chip_color(e))
			cx += w + 4
			if cx > x + cw - 12 {
				break
			}
		}

		// Ability + item line.
		ab := c.ability != .NONE ? ability_name(c.ability) : cstring("-")
		it := c.item != .NONE ? item_name(c.item) : cstring("-")
		rl.DrawText(fmt.ctprintf("%s  |  %s", ab, it), i32(x) + 9, i32(top) + 85, 11, rl.Color{180, 178, 200, 255})

		if done && !dead {
			ed := cstring("ENDED")
			ew := rl.MeasureText(ed, 11)
			rl.DrawText(ed, i32(x + cw) - 8 - ew, i32(top) + 4, 11, rl.Color{150, 150, 168, 255})
		}
	}
}

draw_card_estimate :: proc(attacker, target: ^Creature, id: Move_Id, rec: rl.Rectangle, allies := 0) {
	m := MOVE_DATA[id]
	if !move_has_damage(m) {
		return
	}
	total, type_mult := estimate_damage(attacker, target, id, allies)
	label := fmt.ctprintf("~%d dmg", total)

	note: cstring
	has_note := false
	note_col := COL_MUTED
	switch {
	case type_mult > 1.001:
		note = "super effective"
		note_col = rl.Color{140, 235, 150, 255}
		has_note = true
	case type_mult < 0.999:
		note = "resisted"
		note_col = rl.Color{235, 150, 120, 255}
		has_note = true
	case m.hits > 1:
		note = fmt.ctprintf("x%d hits", m.hits)
		has_note = true
	}

	num_col := rl.Color{255, 222, 130, 255}
	if type_mult > 1.001 {
		num_col = rl.Color{160, 245, 170, 255}
	} else if type_mult < 0.999 {
		num_col = rl.Color{245, 160, 130, 255}
	}

	lw := f32(rl.MeasureText(label, 18))
	nw := f32(0)
	if has_note {
		nw = f32(rl.MeasureText(note, 13))
	}
	box_w := max(lw, nw) + 24
	box_h := has_note ? f32(48) : f32(30)
	bx := rec.x + rec.width / 2 - box_w / 2
	sw := f32(screen_w())
	bx = clamp(bx, 6, sw - box_w - 6)
	by := rec.y - box_h - 8
	box := rl.Rectangle{bx, by, box_w, box_h}
	rl.DrawRectangleRounded(box, 0.28, 6, rl.Color{16, 16, 24, 242})
	rl.DrawRectangleRoundedLinesEx(box, 0.28, 6, 2, rl.Color{130, 130, 150, 255})
	rl.DrawText(label, i32(bx) + 12, i32(by) + 6, 18, num_col)
	if has_note {
		rl.DrawText(note, i32(bx) + 12, i32(by) + 29, 13, note_col)
	}
}

draw_hand :: proc(b: ^Battle) {
	mp := mouse_pos()
	hand := b.party[b.active].hand
	for id, i in hand {
		rec := hand_card_rect(i, len(hand))
		playable := b.phase == .PLAYER_ACTION && move_playable(b.party[b.active], move_data(id))
		hovered := rl.CheckCollisionPointRec(mp, rec)
		draw_card(id, rec, playable, hovered)
		if hovered {
			dr := rec
			if playable {
				dr.y -= CARD_HOVER_LIFT // draw_card lifts hovered playable cards
			}
			// Offensive cards get a damage readout against whoever this card
			// would actually land on. (Gating on `sel_kind` was wrong: that flag
			// sticks after you target an ally, which silently hid the estimate on
			// every attack card.)
			card_target := pick_card_target(b, move_data(id))
			if card_target != nil && side_of(b, card_target) == .WILD {
				draw_card_estimate(b.party[b.active], card_target, id, dr, other_allies_alive(b, b.party[b.active]))
			}
		}
	}
}

draw_buttons :: proc(b: ^Battle) {
	mp := mouse_pos()

	// capture
	cap := capture_rect()
	cap_hover := rl.CheckCollisionPointRec(mp, cap)
	chance := int(capture_chance(b) * 100)
	can_cap := b.phase == .PLAYER_ACTION && b.capture_cards > 0 && len(b.enemies) > 0
	cap_col := rl.Color{70, 100, 150, 255}
	if !can_cap {
		cap_col = rl.Color{45, 52, 66, 255}
	} else if cap_hover {
		cap_col = rl.Color{95, 135, 195, 255}
	}
	rl.DrawRectangleRounded(cap, 0.25, 8, cap_col)
	rl.DrawRectangleRoundedLinesEx(cap, 0.25, 8, 2, rl.Color{200, 220, 240, 255})
	cap_txt := fmt.ctprintf("Capture Card x%d  %d%%", b.capture_cards, chance)
	cpw := rl.MeasureText(cap_txt, 18)
	rl.DrawText(cap_txt, i32(cap.x + cap.width / 2) - cpw / 2, i32(cap.y + cap.height / 2) - 9, 18, rl.Color{235, 245, 255, 255})

	// end turn
	btn := end_turn_rect()
	btn_hover := rl.CheckCollisionPointRec(mp, btn)
	btn_col := rl.Color{70, 130, 100, 255}
	if b.phase != .PLAYER_ACTION {
		btn_col = rl.Color{45, 60, 55, 255}
	} else if btn_hover {
		btn_col = rl.Color{95, 175, 130, 255}
	}
	rl.DrawRectangleRounded(btn, 0.25, 8, btn_col)
	rl.DrawRectangleRoundedLinesEx(btn, 0.25, 8, 2, rl.Color{210, 230, 220, 255})
	et := cstring("End Turn (E)")
	ew := rl.MeasureText(et, 18)
	rl.DrawText(et, i32(btn.x + btn.width / 2) - ew / 2, i32(btn.y + btn.height / 2) - 9, 18, rl.Color{240, 255, 245, 255})

	hint := cstring("D piles  |  C capture")
	rl.DrawText(hint, i32(btn.x), i32(cap.y) - 26, 15, COL_MUTED)
}

// --- draw / discard pile viewer ---------------------------------------------

pile_draw_rect :: proc() -> rl.Rectangle {
	sh := f32(screen_h())
	return rl.Rectangle{20, sh - 96, 172, 30}
}

pile_discard_rect :: proc() -> rl.Rectangle {
	r := pile_draw_rect()
	return rl.Rectangle{r.x, r.y + 34, r.width, 30}
}

pile_exhaust_rect :: proc() -> rl.Rectangle {
	r := pile_draw_rect()
	return rl.Rectangle{r.x, r.y + 68, r.width, 30}
}

// Clickable readouts of the active monster's piles, bottom-left.
draw_pile_readout :: proc(b: ^Battle) {
	c := b.party[b.active]
	mp := mouse_pos()
	dr := pile_draw_rect()
	dc := pile_discard_rect()
	de := pile_exhaust_rect()
	hd := rl.CheckCollisionPointRec(mp, dr)
	hc := rl.CheckCollisionPointRec(mp, dc)
	he := rl.CheckCollisionPointRec(mp, de)
	if hd || hc || he {
		ui_want_hand()
	}
	rl.DrawRectangleRounded(dr, 0.25, 6, hd ? rl.Color{40, 52, 70, 240} : rl.Color{24, 30, 42, 230})
	rl.DrawRectangleRoundedLinesEx(dr, 0.25, 6, 1, rl.Color{90, 140, 200, 255})
	rl.DrawText(fmt.ctprintf("Draw %d", len(c.draw_pile)), i32(dr.x) + 10, i32(dr.y) + 6, 16, rl.Color{150, 210, 255, 255})
	rl.DrawRectangleRounded(dc, 0.25, 6, hc ? rl.Color{52, 44, 34, 240} : rl.Color{30, 26, 20, 230})
	rl.DrawRectangleRoundedLinesEx(dc, 0.25, 6, 1, rl.Color{200, 150, 90, 255})
	rl.DrawText(fmt.ctprintf("Discard %d", len(c.discard)), i32(dc.x) + 10, i32(dc.y) + 6, 16, rl.Color{230, 180, 120, 255})
	rl.DrawRectangleRounded(de, 0.25, 6, he ? rl.Color{58, 40, 54, 240} : rl.Color{32, 24, 30, 230})
	rl.DrawRectangleRoundedLinesEx(de, 0.25, 6, 1, rl.Color{180, 120, 175, 255})
	rl.DrawText(fmt.ctprintf("Exhaust %d", len(c.exhausted)), i32(de.x) + 10, i32(de.y) + 6, 16, rl.Color{215, 165, 210, 255})
	if hd || hc || he {
		tooltip_set("Click (or press D) to view your draw, discard and exhaust piles.")
	}
}

// The pile viewer overlay: the draw and discard piles for the active monster.
draw_piles :: proc(b: ^Battle) {
	c := b.party[b.active]
	sw := f32(screen_w())
	sh := f32(screen_h())
	rl.DrawRectangle(0, 0, i32(sw), i32(sh), rl.Color{0, 0, 0, 215})

	p := rl.Rectangle{sw / 2 - 500, 40, 1000, sh - 80}
	draw_panel(p, rl.Color{18, 20, 28, 248}, rl.Color{150, 170, 220, 255})
	rl.DrawText(fmt.ctprintf("%s  -  piles", c.name), i32(p.x) + 24, i32(p.y) + 14, 26, rl.Color{230, 235, 245, 255})

	col_w := (p.width - 88) / 3
	rl.DrawText(fmt.ctprintf("DRAW PILE  (%d)", len(c.draw_pile)), i32(p.x) + 24, i32(p.y) + 56, 18, rl.Color{150, 210, 255, 255})
	draw_pile_list(c.draw_pile[:], p.x + 24, p.y + 84, col_w)
	rl.DrawText(fmt.ctprintf("DISCARD PILE  (%d)", len(c.discard)), i32(p.x) + 24 + i32(col_w) + 20, i32(p.y) + 56, 18, rl.Color{230, 180, 120, 255})
	draw_pile_list(c.discard[:], p.x + 24 + col_w + 20, p.y + 84, col_w)
	rl.DrawText(fmt.ctprintf("EXHAUSTED  (%d)", len(c.exhausted)), i32(p.x) + 24 + i32((col_w + 20) * 2), i32(p.y) + 56, 18, rl.Color{215, 165, 210, 255})
	draw_pile_list(c.exhausted[:], p.x + 24 + (col_w + 20) * 2, p.y + 84, col_w)

	hint := cstring("D / Esc to close")
	hw := rl.MeasureText(hint, 16)
	rl.DrawText(hint, i32(p.x + p.width / 2) - hw / 2, i32(p.y + p.height) - 28, 16, rl.Color{150, 150, 170, 255})
}

draw_pile_list :: proc(cards: []Move_Id, x, y, w: f32) {
	row_h := f32(22)
	max_rows := int((f32(screen_h()) - y - 50) / row_h)
	for id, i in cards {
		if i >= max_rows {
			rl.DrawText(fmt.ctprintf("+%d more", len(cards) - i), i32(x), i32(y + f32(i) * row_h), 14, rl.Color{140, 140, 160, 255})
			break
		}
		m := MOVE_DATA[id]
		col := element_color(m.element)
		rl.DrawText(fmt.ctprintf("%s", m.name), i32(x), i32(y + f32(i) * row_h), 15, rl.Color{220, 222, 235, 255})
		right := fmt.ctprintf("%s  %s", fmt_num(m.cost), element_name(m.element))
		rw := rl.MeasureText(right, 14)
		rl.DrawText(right, i32(x + w) - rw, i32(y + f32(i) * row_h), 14, col)
	}
}

draw_battle_log :: proc(b: ^Battle) {
	for msg, i in b.log {
		rl.DrawText(fmt.ctprintf("%s", msg), 16, 196 + i32(i) * 21, 15, COL_MUTED)
	}
}

draw_center_overlay :: proc(title, sub: cstring, color: rl.Color, timer: f32) {
	sw := f32(screen_w())
	sh := f32(screen_h())
	rl.DrawRectangle(0, 0, i32(sw), i32(sh), rl.Color{0, 0, 0, 150})

	tw := rl.MeasureText(title, 62)
	rl.DrawText(title, i32(sw) / 2 - tw / 2, i32(sh) / 2 - 60, 62, color)

	if timer > 0.4 {
		sw2 := rl.MeasureText(sub, 23)
		rl.DrawText(sub, i32(sw) / 2 - sw2 / 2, i32(sh) / 2 + 18, 23, COL_TEXT)
	}
}
