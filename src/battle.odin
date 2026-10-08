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

Popup_Kind :: enum { DAMAGE, BLOCK, HEAL, BUFF, DEBUFF, DEFEND, WEAKEN, SHATTER, CAPTURE }

Popup :: struct {
	value:    int,
	kind:     Popup_Kind,
	side:     Battle_Side,
	life:     f32,
	max_life: f32,
}

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
	enemy_acting:  int,                // enemy taking the current action
	captured_ids:  [dynamic]int,       // enemies captured this battle
	capture_cards: int,                // capture cards available (spent on capture)
	auto_play:     bool,               // AI plays the player's side
	phase:         Battle_Phase,
	round:         int,
	order:         [dynamic]Actor, // initiative queue: every living monster
	order_pos:     int,            // next slot to consider (wraps each pass)
	timer:         f32,
	rng:           Rng,
	log:           [dynamic]string,
	popups:        [dynamic]Popup,
	shake:         f32,
	shake_mag:     f32,
}

DIGIT_KEYS := [?]rl.KeyboardKey{.ONE, .TWO, .THREE, .FOUR, .FIVE, .SIX, .SEVEN, .EIGHT, .NINE}

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
	b.enemy_acting = 0

	for e in b.enemies {
		creature_reset_battle_state(e)
		prepare_piles(e, &b.rng)
	}
	for i in 0..<len(b.party) {
		creature_reset_battle_state(b.party[i])
		prepare_piles(b.party[i], &b.rng)
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
}

enemy_has_card :: proc(e: ^Creature) -> bool {
	for m in e.hand {
		if e.energy >= move_data(m).cost {
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

creature_begin_round :: proc(c: ^Creature, rng: ^Rng) {
	c.block = 0
	c.played = 0
	// Energy is generated each round and carries over up to the bank cap.
	c.energy = min(c.energy + c.energy_regen, c.energy_max)
	creature_draw(c, 5, rng)
}

creature_end_round :: proc(c: ^Creature) {
	for card in c.hand {
		append(&c.discard, card)
	}
	clear(&c.hand)
	if c.vulnerable > 0 {
		c.vulnerable -= 1
	}
}

// ----------------------------------------------------------------------------
// Initiative queue: every living monster acts in Speed order. Each pass through
// the queue, a monster plays one card; the queue cycles until nobody can act,
// then a new turn begins (fresh hands + energy).
// ----------------------------------------------------------------------------

actor_speed :: proc(b: ^Battle, a: Actor) -> f32 {
	return a.side == .PLAYER ? b.party[a.index].speed : b.enemies[a.index].speed
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
			if c.energy >= move_data(m).cost {
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
	} else {
		b.enemy_acting = a.index
		b.phase = .ENEMY_ACTION
		b.timer = 0.6
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
			creature_end_round(p)
		}
		for e in b.enemies {
			creature_end_round(e)
		}
	}
	b.round += 1

	for i in 0..<len(b.party) {
		b.party_done[i] = false
		creature_begin_round(b.party[i], &b.rng)
	}
	for e in b.enemies {
		creature_begin_round(e, &b.rng)
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

// Damage = base card damage x power x strength bonus, then type effectiveness,
// STAB and vulnerability, then a multiplicative defense reduction.
//   - power is the creature's power stat (a multiplier, ~1.0 at level 1).
//   - each point of Strength adds +10% damage.
//   - defense scales the hit down proportionally (defense 10 = half damage),
//     so it stays relevant as attacks grow.
apply_damage :: proc(attacker: ^Creature, target: ^Creature, base: int, elem: Element) -> int {
	str_mult := max(1.0 + 0.1 * f32(attacker.strength), 0.1)
	dmg := f32(base) * attacker.power * str_mult
	// Type effectiveness against every type the defender has.
	for de in creature_elements(target) {
		dmg *= element_multiplier(elem, de)
	}
	// Same-type attack bonus: a move matching one of the attacker's types.
	for ae in creature_elements(attacker) {
		if ae == elem {
			dmg *= 1.5
			break
		}
	}
	if target.vulnerable > 0 {
		dmg *= 1.5
	}
	dmg *= 10.0 / (10.0 + creature_defense(target))
	d := int(dmg)
	absorbed := min(target.block, d)
	target.block -= absorbed
	d -= absorbed
	if d > 0 {
		target.hp -= d
		target.shake = CREATURE_SHAKE_DUR
		target.flash = 0.22
	}
	return d
}

// Damage a card would deal to a target right now, without mutating anything.
// Mirrors apply_damage (including synergy bonuses) and also returns the type
// multiplier so the UI can flag super-effective / resisted hits.
estimate_damage :: proc(attacker, target: ^Creature, id: Move_Id) -> (total: int, type_mult: f32) {
	m := MOVE_DATA[id]
	type_mult = 1
	if m.damage <= 0 || target == nil {
		return 0, type_mult
	}
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
	for de in creature_elements(target) {
		type_mult *= element_multiplier(m.element, de)
	}
	f := type_mult
	for ae in creature_elements(attacker) {
		if ae == m.element {
			f *= 1.5
			break
		}
	}
	if target.vulnerable > 0 {
		f *= 1.5
	}
	str_mult := max(1.0 + 0.1 * f32(attacker.strength), 0.1)
	def_mult := 10.0 / (10.0 + creature_defense(target))
	total = 0
	for h in 0..<max(m.hits, 1) {
		d := m.damage + (h == 0 ? bonus : 0)
		total += int(f32(d) * attacker.power * str_mult * f * def_mult)
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

spawn_popup :: proc(b: ^Battle, side: Battle_Side, kind: Popup_Kind, value: int) {
	append(&b.popups, Popup{value = value, kind = kind, side = side, life = 0.95, max_life = 0.95})
}

play_creature_card :: proc(b: ^Battle, c: ^Creature, target: ^Creature, index: int, rng: ^Rng) -> bool {
	if index < 0 || index >= len(c.hand) {
		return false
	}
	id := c.hand[index]
	m := move_data(id)
	if c.energy < m.cost {
		return false
	}
	c.energy -= m.cost

	self_side := side_of(b, c)
	target_side := side_of(b, target)

	if m.damage > 0 {
		bonus := 0
		if m.vuln_bonus > 0 && target.vulnerable > 0 {
			bonus += m.vuln_bonus
		}
		if m.block_bonus > 0 && c.block > 0 {
			bonus += m.block_bonus
		}
		if m.combo_bonus > 0 && c.played > 0 {
			bonus += m.combo_bonus
		}
		total := 0
		for hit in 0..<max(m.hits, 1) {
			d := m.damage + (hit == 0 ? bonus : 0)
			total += apply_damage(c, target, d, m.element)
		}
		if total > 0 {
			spawn_popup(b, target_side, .DAMAGE, total)
			b.shake = SHAKE_DUR
			b.shake_mag = clamp(3.0 + f32(total) * 0.4, 3.0, 10.0)
		}
		c.shake = CREATURE_SHAKE_DUR * 0.4
	}
	if m.block > 0 {
		c.block += m.block
		spawn_popup(b, self_side, .BLOCK, m.block)
	}
	if m.vulnerable > 0 {
		target.vulnerable += m.vulnerable
		spawn_popup(b, target_side, .DEBUFF, m.vulnerable)
	}
	if m.strength > 0 {
		c.strength += m.strength
		spawn_popup(b, self_side, .BUFF, m.strength)
	}
	if m.defense > 0 {
		c.defense_buff += m.defense
		spawn_popup(b, self_side, .DEFEND, int(m.defense))
	}
	if m.strength_down > 0 {
		target.strength -= m.strength_down
		spawn_popup(b, target_side, .WEAKEN, m.strength_down)
	}
	if m.defense_down > 0 {
		target.defense_debuff += m.defense_down
		spawn_popup(b, target_side, .SHATTER, int(m.defense_down))
	}
	if m.heal > 0 {
		before := c.hp
		c.hp = min(c.hp + m.heal, c.max_hp)
		if c.hp > before {
			spawn_popup(b, self_side, .HEAL, c.hp - before)
		}
	}
	if m.draw > 0 {
		creature_draw(c, m.draw, rng)
	}

	ordered_remove(&c.hand, index)
	append(&c.discard, id)
	c.played += 1
	return true
}

player_play :: proc(b: ^Battle, index: int) {
	if b.phase != .PLAYER_ACTION {
		return
	}
	if play_creature_card(b, b.party[b.active], target_enemy(b), index, &b.rng) {
		fix_target(b)
		if enemies_alive(b) == 0 {
			b.phase = .WON
			b.timer = 0
			battle_log(b, "All wilds defeated!")
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
		if c.energy < move_data(card).cost {
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
	return clamp(frac, 0, 1) * 0.9
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
	}
	for e in b.enemies {
		if e.shake > 0 { e.shake = max(e.shake - dt, 0) }
		if e.flash > 0 { e.flash = max(e.flash - dt, 0) }
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
		if c.energy < move_data(card).cost {
			continue
		}
		v := move_value(card)
		if v > best_val {
			best_val = v
			best = i
		}
	}
	if best >= 0 {
		player_play(b, best)
	} else {
		player_end_round(b)
	}
}

// ----------------------------------------------------------------------------
// Input
// ----------------------------------------------------------------------------

party_entry_rect :: proc(i: int) -> rl.Rectangle {
	sw := f32(rl.GetScreenWidth())
	return rl.Rectangle{sw - 236, 120 + f32(i) * 62, 216, 56}
}

end_turn_rect :: proc() -> rl.Rectangle {
	sw := f32(rl.GetScreenWidth())
	sh := f32(rl.GetScreenHeight())
	return rl.Rectangle{sw - 236, sh - 122, 216, 46}
}

capture_rect :: proc() -> rl.Rectangle {
	sw := f32(rl.GetScreenWidth())
	sh := f32(rl.GetScreenHeight())
	return rl.Rectangle{sw - 236, sh - 176, 216, 46}
}

battle_input :: proc(b: ^Battle) {
	if b.auto_play {
		return // auto-fight: no player input
	}
	mp := rl.GetMousePosition()

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
		// Click an enemy to target it.
		for i in 0..<len(b.enemies) {
			if b.enemies[i].hp > 0 && rl.CheckCollisionPointRec(mp, enemy_rect(i, len(b.enemies))) {
				b.target = i
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

hand_card_rect :: proc(index, count: int) -> rl.Rectangle {
	sw := f32(rl.GetScreenWidth())
	sh := f32(rl.GetScreenHeight())
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
	sw := f32(rl.GetScreenWidth())
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

draw_energy :: proc(x, y, width: f32, current, maximum: f32) {
	h := f32(16)
	rec := rl.Rectangle{x, y - h / 2, width, h}
	rl.DrawRectangleRounded(rec, 0.5, 8, rl.Color{42, 38, 26, 255})
	frac := clamp(current / max(maximum, 0.0001), 0, 1)
	if frac > 0 {
		rl.DrawRectangleRounded(rl.Rectangle{x, y - h / 2, width * frac, h}, 0.5, 8, COL_ENERGY)
	}
	rl.DrawRectangleRoundedLinesEx(rec, 0.5, 8, 2, rl.Color{12, 12, 16, 255})
	txt := fmt.ctprintf("%s / %s", fmt_num(current), fmt_num(maximum))
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
}

draw_card :: proc(id: Move_Id, rec: rl.Rectangle, playable, hovered: bool) {
	m := move_data(id)
	r := rec
	if hovered && playable {
		r.y -= 22
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

	cc := rl.Vector2{r.x + 19, r.y + 19}
	rl.DrawCircleV(cc, 14, rl.Color{30, 34, 52, 255})
	rl.DrawCircleLinesV(cc, 14, base)
	cost := fmt_num(m.cost)
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
}

draw_battle :: proc(b: ^Battle) {
	sw := f32(rl.GetScreenWidth())
	sh := f32(rl.GetScreenHeight())

	rl.ClearBackground(COL_BG)

	// Screen shake: shift the whole world layer.
	sx, sy := f32(0), f32(0)
	if b.shake > 0 {
		mag := b.shake_mag * (b.shake / SHAKE_DUR)
		sx, sy = shake_offset(mag)
	}

	cam := rl.Camera2D{
		offset = rl.Vector2{sw / 2 + sx, sh / 2 + sy},
		target = rl.Vector2{sw / 2, sh / 2},
		zoom   = 1,
	}
	rl.BeginMode2D(cam)
	rl.DrawRectangle(0, i32(sh * 0.58), i32(sw), i32(sh * 0.42), COL_FLOOR)
	draw_enemies(b)
	draw_player_panel(b)
	draw_party(b, sw)
	draw_hand(b)
	draw_popups(b)
	rl.EndMode2D()

	// Round + action indicator.
	if b.phase == .PLAYER_ACTION || b.phase == .ENEMY_ACTION {
		label := b.phase == .PLAYER_ACTION ? cstring("YOUR MOVE") : cstring("ENEMY MOVE")
		col := b.phase == .PLAYER_ACTION ? rl.Color{140, 240, 190, 255} : rl.Color{240, 140, 120, 255}
		ind := fmt.ctprintf("Turn %d   -   %s", b.round, label)
		iw := rl.MeasureText(ind, 22)
		rl.DrawText(ind, i32(sw) / 2 - iw / 2, 14, 22, col)
	}

	draw_buttons(b)
	draw_battle_log(b)

	if b.phase == .WON {
		draw_center_overlay("VICTORY", "Click to claim your reward", rl.Color{120, 230, 150, 255}, b.timer)
	} else if b.phase == .LOST {
		draw_center_overlay("DEFEAT", "Click to continue", rl.Color{235, 90, 90, 255}, b.timer)
	} else if b.phase == .CAPTURED {
		draw_center_overlay("CAPTURED!", "Click to return to the map", rl.Color{120, 200, 255, 255}, b.timer)
	}
}

enemy_rect :: proc(i, n: int) -> rl.Rectangle {
	sw := f32(rl.GetScreenWidth())
	spacing := f32(170)
	total := f32(n) * spacing
	start := sw / 2 - total / 2 + spacing / 2
	ex := start + f32(i) * spacing
	ey := f32(232)
	return rl.Rectangle{ex - 60, ey - 60, 120, 120}
}

// ----------------------------------------------------------------------------
// Active combat boosts (Strength / Defense / Block / Vulnerable) and the
// damage multiplier each one contributes, so the player can read them at a
// glance. Strength and Defense are flat bonuses, so their multiplier is shown
// relative to the creature's average attack (STR) / a typical incoming hit
// (DEF).
// ----------------------------------------------------------------------------

Effect_Kind :: enum { STR, DEF, BLOCK, VULN }
Effect :: struct {
	kind:  Effect_Kind,
	value: int,
	mult:  f32, // damage multiplier this boost contributes (0 = not applicable)
}

build_effects :: proc(c: ^Creature) -> ([4]Effect, int) {
	out: [4]Effect
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
	if c.vulnerable > 0 {
		out[n] = {.VULN, c.vulnerable, 1.5}
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
	case .VULN:
		return fmt.ctprintf("VULN x1.50")
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
	case .VULN:
		return COL_VULN
	}
	return COL_TEXT
}

draw_effect_chip :: proc(x, y: f32, text: cstring, col: rl.Color) -> f32 {
	w := f32(rl.MeasureText(text, 13)) + 12
	rec := rl.Rectangle{x, y, w, 19}
	rl.DrawRectangleRounded(rec, 0.45, 4, rl.Color{col[0] / 5, col[1] / 5, col[2] / 5, 235})
	rl.DrawRectangleRoundedLinesEx(rec, 0.45, 4, 1, col)
	rl.DrawText(text, i32(x) + 6, i32(y) + 3, 13, col)
	return w
}

// Centered row of chips.
draw_effects_row :: proc(effects: []Effect, center_x, y: f32) {
	total := f32(0)
	for e in effects {
		total += f32(rl.MeasureText(effect_chip_text(e), 13)) + 12 + 4
	}
	if len(effects) > 0 {
		total -= 4
	}
	x := center_x - total / 2
	for e in effects {
		w := draw_effect_chip(x, y, effect_chip_text(e), effect_chip_color(e))
		x += w + 4
	}
}

// Left-aligned vertical list of chips.
draw_effects_column :: proc(effects: []Effect, x, y: f32) {
	yy := y
	for e in effects {
		draw_effect_chip(x, yy, effect_chip_text(e), effect_chip_color(e))
		yy += 22
	}
}

draw_enemies :: proc(b: ^Battle) {
	sw := f32(rl.GetScreenWidth())
	n := len(b.enemies)
	ey := f32(232)
	spacing := f32(170)
	total := f32(n) * spacing
	start := sw / 2 - total / 2 + spacing / 2

	for e, i in b.enemies {
		ex := start + f32(i) * spacing
		radius := f32(56)
		ox, oy := creature_offset(e)
		draw_creature_avatar(rl.Vector2{ex + ox, ey + oy}, radius, e, e.hp <= 0)

		name := fmt.ctprintf("%s", e.name)
		nw := rl.MeasureText(name, 20)
		rl.DrawText(name, i32(ex) - nw / 2, i32(ey) - 108, 20, COL_TEXT)

		lvl := fmt.ctprintf("Lvl %d  %s", e.level, element_label(e))
		lw := rl.MeasureText(lvl, 15)
		rl.DrawText(lvl, i32(ex) - lw / 2, i32(ey) - 86, 15, element_color(creature_element(e)))

		hp_rec := rl.Rectangle{ex - 70, ey + 70, 140, 18}
		draw_bar(hp_rec, e.hp, e.max_hp, COL_HP)
		hp_txt := fmt.ctprintf("%d/%d", e.hp, e.max_hp)
		hw := rl.MeasureText(hp_txt, 13)
		rl.DrawText(hp_txt, i32(ex) - hw / 2, i32(hp_rec.y) + 2, 13, COL_TEXT)

		// Energy (the same pool the wild uses on the colony map).
		en_rec := rl.Rectangle{ex - 70, ey + 91, 140, 7}
		draw_bar(en_rec, int(e.energy * 100), int(max(e.energy_max, 0.01) * 100), COL_ENERGY)
		en_txt := fmt.ctprintf("En %s/%s", fmt_num(e.energy), fmt_num(e.energy_max))
		ew := rl.MeasureText(en_txt, 11)
		rl.DrawText(en_txt, i32(ex) - ew / 2, i32(en_rec.y) + 7, 11, COL_TEXT)

		// Active boosts, each with the damage multiplier it contributes.
		effs, ne := build_effects(e)
		draw_effects_column(effs[:ne], ex - 62, ey + 112)

		if i == b.target && e.hp > 0 {
			rl.DrawCircleLinesV(rl.Vector2{ex, ey}, radius + 5, rl.Color{255, 235, 140, 255})
			rl.DrawText("TARGET", i32(ex) - 27, i32(ey) - 134, 14, rl.Color{255, 235, 140, 255})
		} else if i == b.enemy_acting && e.hp > 0 && b.phase == .ENEMY_ACTION {
			rl.DrawCircleLinesV(rl.Vector2{ex, ey}, radius + 10, rl.Color{240, 140, 120, 200})
		}
	}
}

vfmt :: proc(b: ^Battle, format: string, args: ..any) -> cstring {
	return fmt.ctprintf(format, ..args)
}

draw_player_panel :: proc(b: ^Battle) {
	c := b.party[b.active]
	panel := rl.Rectangle{16, 16, 344, 170}
	rl.DrawRectangleRounded(panel, 0.10, 8, COL_PANEL)
	rl.DrawRectangleRoundedLinesEx(panel, 0.10, 8, 2, rl.Color{60, 60, 78, 255})

	ox, oy := creature_offset(c)
	draw_creature_avatar(rl.Vector2{panel.x + 48 + ox, panel.y + 62 + oy}, 34, c, false)

	name := fmt.ctprintf("%s", c.name)
	rl.DrawText(name, i32(panel.x) + 94, i32(panel.y) + 14, 22, COL_TEXT)
	sub := fmt.ctprintf("Lvl %d  %s  PWR x%s  DEF %s  SPD %s", c.level, element_label(c), fmt_num(c.power), fmt_num(creature_defense(c)), fmt_num(c.speed))
	rl.DrawText(sub, i32(panel.x) + 94, i32(panel.y) + 40, 16, element_color(creature_element(c)))

	hp_rec := rl.Rectangle{panel.x + 94, panel.y + 64, 210, 20}
	draw_bar(hp_rec, c.hp, c.max_hp, COL_HP)
	hp_txt := fmt.ctprintf("%d / %d", c.hp, c.max_hp)
	rl.DrawText(hp_txt, i32(hp_rec.x) + 8, i32(hp_rec.y) + 2, 15, COL_TEXT)

	// XP toward the next level.
	need := xp_to_next(c.level)
	xp_rec := rl.Rectangle{panel.x + 94, panel.y + 87, 176, 6}
	rl.DrawRectangleRounded(xp_rec, 0.5, 4, rl.Color{32, 36, 50, 255})
	xf := clamp(f32(c.xp) / f32(max(need, 1)), 0, 1)
	if xf > 0 {
		rl.DrawRectangleRounded(rl.Rectangle{xp_rec.x, xp_rec.y, xp_rec.width * xf, xp_rec.height}, 0.5, 4, rl.Color{150, 210, 255, 255})
	}
	rl.DrawText(fmt.ctprintf("XP %d/%d", c.xp, need), i32(panel.x) + 276, i32(panel.y) + 82, 11, rl.Color{150, 210, 255, 255})

	rl.DrawText(fmt.ctprintf("Energy +%s", fmt_num(c.energy_regen)), i32(panel.x) + 94, i32(panel.y) + 96, 15, COL_MUTED)
	draw_energy(panel.x + 156, panel.y + 104, 160, c.energy, c.energy_max)

	piles := vfmt(b, "deck %d", len(c.deck))
	rl.DrawText(piles, i32(panel.x) + 94, i32(panel.y) + 116, 14, COL_MUTED)

	// Active boosts, each with the damage multiplier it contributes.
	effs, ne := build_effects(c)
	draw_effects_row(effs[:ne], panel.x + panel.width / 2, panel.y + 142)
}

draw_party :: proc(b: ^Battle, sw: f32) {
	for c, i in b.party {
		rec := party_entry_rect(i)
		active := i == b.active
		dead := c.hp <= 0

		bg := COL_PANEL
		if active {
			bg = rl.Color{34, 46, 42, 255}
		}
		rl.DrawRectangleRounded(rec, 0.18, 6, bg)
		border := rl.Color{60, 60, 78, 255}
		if active {
			border = rl.Color{120, 230, 180, 255}
		}
		rl.DrawRectangleRoundedLinesEx(rec, 0.18, 6, 2, border)

		ox, oy := creature_offset(b.party[i])
		draw_creature_avatar(rl.Vector2{rec.x + 28 + ox, rec.y + 28 + oy}, 20, b.party[i], dead)

		name_col := COL_TEXT
		if dead {
			name_col = rl.Color{120, 120, 130, 255}
		}
		name := fmt.ctprintf("%s", c.name)
		rl.DrawText(name, i32(rec.x) + 54, i32(rec.y) + 8, 15, name_col)

		bar := rl.Rectangle{rec.x + 54, rec.y + 30, 150, 14}
		draw_bar(bar, c.hp, c.max_hp, COL_HP)
		lv := fmt.ctprintf("Lvl %d", c.level)
		rl.DrawText(lv, i32(rec.x) + 54, i32(rec.y) + 44, 12, COL_MUTED)

		if active {
			rl.DrawText("ACTIVE", i32(rec.x) + 150, i32(rec.y) + 44, 12, rl.Color{120, 230, 180, 255})
		}
	}
}

draw_card_estimate :: proc(attacker, target: ^Creature, id: Move_Id, rec: rl.Rectangle) {
	m := MOVE_DATA[id]
	if m.damage <= 0 {
		return
	}
	total, type_mult := estimate_damage(attacker, target, id)
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
	box_h := has_note ? f32(50) : f32(32)
	bx := rec.x + rec.width / 2 - box_w / 2
	sw := f32(rl.GetScreenWidth())
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
	mp := rl.GetMousePosition()
	hand := b.party[b.active].hand
	tgt := target_enemy(b)
	for id, i in hand {
		rec := hand_card_rect(i, len(hand))
		playable := b.phase == .PLAYER_ACTION && b.party[b.active].energy >= move_data(id).cost
		hovered := rl.CheckCollisionPointRec(mp, rec)
		draw_card(id, rec, playable, hovered)
		if hovered {
			dr := rec
			if playable {
				dr.y -= 22 // draw_card lifts hovered playable cards
			}
			draw_card_estimate(b.party[b.active], tgt, id, dr)
		}
	}
}

draw_buttons :: proc(b: ^Battle) {
	mp := rl.GetMousePosition()

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

	hint := cstring("V deck  |  C capture")
	rl.DrawText(hint, i32(btn.x), i32(cap.y) - 26, 15, COL_MUTED)
}

draw_battle_log :: proc(b: ^Battle) {
	for msg, i in b.log {
		rl.DrawText(fmt.ctprintf("%s", msg), 16, 196 + i32(i) * 21, 15, COL_MUTED)
	}
}

draw_center_overlay :: proc(title, sub: cstring, color: rl.Color, timer: f32) {
	sw := f32(rl.GetScreenWidth())
	sh := f32(rl.GetScreenHeight())
	rl.DrawRectangle(0, 0, i32(sw), i32(sh), rl.Color{0, 0, 0, 150})

	tw := rl.MeasureText(title, 62)
	rl.DrawText(title, i32(sw) / 2 - tw / 2, i32(sh) / 2 - 60, 62, color)

	if timer > 0.4 {
		sw2 := rl.MeasureText(sub, 23)
		rl.DrawText(sub, i32(sw) / 2 - sw2 / 2, i32(sh) / 2 + 18, 23, COL_TEXT)
	}
}
