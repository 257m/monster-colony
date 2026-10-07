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

Popup_Kind :: enum { DAMAGE, BLOCK, HEAL, BUFF, DEBUFF, DEFEND, CAPTURE }

Popup :: struct {
	value:    int,
	kind:     Popup_Kind,
	side:     Battle_Side,
	life:     f32,
	max_life: f32,
}

Battle :: struct {
	party:         [dynamic]^Creature, // defenders (external creatures), array owned here
	active:        int,
	enemies:       [dynamic]^Creature, // the attacking wilds (external)
	enemy_ids:     [dynamic]int,       // colony ids, parallel to enemies
	target:        int,                // currently targeted enemy
	enemy_acting:  int,                // enemy taking the current action
	captured_ids:  [dynamic]int,       // enemies captured this battle
	capture_cards: int,                // capture cards available (spent on capture)
	auto_play:     bool,               // AI plays the player's side
	phase:         Battle_Phase,
	round:         int,
	acting:        Battle_Side,
	player_first:  bool,
	player_done:   bool,
	enemy_done:    bool,
	timer:         f32,
	switch_menu:   bool,
	forced_switch: bool,
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
	delete(b.enemies)
	b.enemies = make([dynamic]^Creature, 0)
	delete(b.enemy_ids)
	b.enemy_ids = make([dynamic]int, 0)
	delete(b.captured_ids)
	b.captured_ids = make([dynamic]int, 0)
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

pick_wild :: proc(kind: Node_Type, depth: int, rng: ^Rng) -> (int, int) {
	level := 1 + depth / 2
	#partial switch kind {
	case .BOSS:
		return 8, max(level, 4)
	case .ELITE:
		return 7, max(level, 3)
	case:
		wilds := [?]int{3, 4, 5, 6}
		idx := wilds[rng_below(rng, len(wilds))]
		return idx, max(level, 1)
	}
}

battle_start :: proc(defenders: []^Creature, enemies: []^Creature, enemy_ids: []int, seed_rng: ^Rng) -> Battle {
	b := Battle{}
	b.rng = rng_make(rng_next_u64(seed_rng))
	b.log = make([dynamic]string, 0)
	b.popups = make([dynamic]Popup, 0)
	b.party = make([dynamic]^Creature, 0)
	b.enemies = make([dynamic]^Creature, 0)
	b.enemy_ids = make([dynamic]int, 0)
	b.captured_ids = make([dynamic]int, 0)

	for c in defenders {
		append(&b.party, c)
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

// A side can act if it has not ended its turn and has an affordable card.
can_act :: proc(b: ^Battle, side: Battle_Side) -> bool {
	if side == .PLAYER {
		c := b.party[b.active]
		if b.player_done || c.hp <= 0 {
			return false
		}
		for m in c.hand {
			if c.energy >= move_data(m).cost {
				return true
			}
		}
		return false
	}
	if b.enemy_done {
		return false
	}
	for e in b.enemies {
		if e.hp > 0 && enemy_has_card(e) {
			return true
		}
	}
	return false
}

set_action :: proc(b: ^Battle, side: Battle_Side) {
	b.acting = side
	if side == .PLAYER {
		b.phase = .PLAYER_ACTION
		b.timer = b.auto_play ? 0.55 : 0
	} else {
		// Pick the next alive enemy that can act.
		n := len(b.enemies)
		if n > 0 {
			for k in 0..<n {
				j := (b.enemy_acting + k) % n
				if b.enemies[j].hp > 0 && enemy_has_card(b.enemies[j]) {
					b.enemy_acting = j
					break
				}
			}
		}
		b.phase = .ENEMY_ACTION
		b.timer = 0.6
	}
}

// Initiative is rolled each round; faster creatures are more likely to lead.
roll_initiative :: proc(b: ^Battle) -> bool {
	ps := f32(b.party[b.active].speed)
	es := f32(1)
	for e in b.enemies {
		if e.hp > 0 && f32(e.speed) > es {
			es = f32(e.speed)
		}
	}
	total := ps + es
	if total <= 0 {
		return true
	}
	return rng_f32(&b.rng) < ps / total
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
		creature_end_round(b.party[b.active])
		for e in b.enemies {
			creature_end_round(e)
		}
	}
	b.round += 1
	b.player_done = false
	b.enemy_done = false

	creature_begin_round(b.party[b.active], &b.rng)
	for e in b.enemies {
		creature_begin_round(e, &b.rng)
	}

	b.player_first = roll_initiative(b)
	lead := b.player_first ? "You" : target_enemy(b).name
	battle_log(b, "Round %d - %s has initiative.", b.round, lead)
	set_action(b, b.player_first ? Battle_Side.PLAYER : Battle_Side.WILD)

	// If whoever won initiative cannot act, hand over right away.
	if !can_act(b, b.acting) {
		proceed(b, b.acting)
	}
}

// After a side completes one action, decide who acts next. Sides alternate
// while both can still play; a side that is done (or stuck) yields to the
// other until neither can act, then a new round begins.
proceed :: proc(b: ^Battle, last: Battle_Side) {
	if b.phase == .WON || b.phase == .LOST || b.phase == .CAPTURED {
		return
	}
	other := last == .PLAYER ? Battle_Side.WILD : Battle_Side.PLAYER

	if can_act(b, other) {
		set_action(b, other)
		return
	}
	if can_act(b, last) {
		set_action(b, last)
		return
	}
	begin_round(b)
}

// ----------------------------------------------------------------------------
// Card resolution
// ----------------------------------------------------------------------------

apply_damage :: proc(attacker: ^Creature, target: ^Creature, base: int, elem: Element) -> int {
	dmg := f32(base + attacker.strength + attacker.power)
	dmg *= element_multiplier(elem, creature_element(target))
	if target.vulnerable > 0 {
		dmg *= 1.5
	}
	d := int(dmg)
	if d < 0 {
		d = 0
	}
	// Defense reduces the hit, but never below 0 (block handles the rest).
	d = max(d - creature_defense(target), 0)
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
		total := 0
		for _ in 0..<max(m.hits, 1) {
			total += apply_damage(c, target, m.damage, m.element)
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
		spawn_popup(b, self_side, .DEFEND, m.defense)
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
		proceed(b, .PLAYER)
	}
}

player_end_round :: proc(b: ^Battle) {
	if b.phase != .PLAYER_ACTION {
		return
	}
	b.player_done = true
	battle_log(b, "You end your turn.")
	proceed(b, .PLAYER)
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
	if len(b.enemies) == 0 {
		b.enemy_done = true
		proceed(b, .WILD)
		return
	}
	if b.enemy_acting < 0 || b.enemy_acting >= len(b.enemies) {
		b.enemy_acting = 0
	}
	wild := b.enemies[b.enemy_acting]
	target := b.party[b.active]

	if wild.hp <= 0 {
		b.enemy_acting = (b.enemy_acting + 1) % len(b.enemies)
		proceed(b, .WILD)
		return
	}

	idx := choose_enemy_card(wild)
	if idx < 0 {
		b.enemy_acting = (b.enemy_acting + 1) % len(b.enemies)
		if !can_act(b, .WILD) {
			b.enemy_done = true
		}
		proceed(b, .WILD)
		return
	}

	m := move_data(wild.hand[idx])
	play_creature_card(b, wild, target, idx, &b.rng)
	battle_log(b, "%s uses %s.", wild.name, m.name)
	b.enemy_acting = (b.enemy_acting + 1) % len(b.enemies)

	if target.hp <= 0 {
		target.hp = 0
		handle_player_faint(b)
		return
	}
	proceed(b, .WILD)
}

handle_player_faint :: proc(b: ^Battle) {
	fainted := b.party[b.active]
	battle_log(b, "%s fainted!", fainted.name)
	for m in fainted.hand {
		append(&fainted.discard, m)
	}
	clear(&fainted.hand)

	if party_has_alive(b) {
		b.forced_switch = true
		b.switch_menu = true
		b.phase = .PLAYER_ACTION
		b.timer = 0
	} else {
		b.phase = .LOST
		b.timer = 0
		battle_log(b, "Your party has fallen...")
	}
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
// Player-only actions: capture + switching
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
	if b.phase != .PLAYER_ACTION || b.forced_switch {
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
		proceed(b, .PLAYER)
	} else {
		spawn_popup(b, .PLAYER, .CAPTURE, 0)
		battle_log(b, "Capture failed! (%d%% chance)", int(chance * 100))
		proceed(b, .PLAYER)
	}
}

switch_to :: proc(b: ^Battle, index: int) {
	if b.phase != .PLAYER_ACTION || b.forced_switch {
		return
	}
	if index == b.active || index < 0 || index >= len(b.party) || b.party[index].hp <= 0 {
		return
	}
	// Switching uses your action for the round.
	creature_end_round(b.party[b.active])
	b.active = index
	b.player_done = true
	b.switch_menu = false
	battle_log(b, "You send out %s.", b.party[index].name)
	proceed(b, .PLAYER)
}

forced_switch_to :: proc(b: ^Battle, index: int) {
	if index < 0 || index >= len(b.party) || b.party[index].hp <= 0 {
		return
	}
	b.active = index
	b.forced_switch = false
	b.switch_menu = false
	battle_log(b, "You send out %s.", b.party[index].name)
	begin_round(b)
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

	if b.switch_menu {
		if rl.IsMouseButtonPressed(.LEFT) {
			for i in 0..<len(b.party) {
				if i == b.active || b.party[i].hp <= 0 {
					continue
				}
				if rl.CheckCollisionPointRec(mp, party_entry_rect(i)) {
					if b.forced_switch {
						forced_switch_to(b, i)
					} else {
						switch_to(b, i)
					}
					return
				}
			}
		}
		if !b.forced_switch && (rl.IsKeyPressed(.ESCAPE) || rl.IsKeyPressed(.T)) {
			b.switch_menu = false
		}
		return
	}

	if b.phase != .PLAYER_ACTION {
		return
	}

	if rl.IsKeyPressed(.E) || rl.IsKeyPressed(.SPACE) {
		player_end_round(b)
		return
	}
	if rl.IsKeyPressed(.T) {
		b.switch_menu = true
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
		for i in 0..<len(b.party) {
			if i == b.active || b.party[i].hp <= 0 {
				continue
			}
			if rl.CheckCollisionPointRec(mp, party_entry_rect(i)) {
				b.switch_menu = true
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

draw_badge :: proc(center: rl.Vector2, value: int, color: rl.Color) {
	rl.DrawCircleV(center, 16, color)
	rl.DrawCircleLinesV(center, 16, rl.Color{240, 240, 250, 255})
	txt := fmt.ctprintf("%d", value)
	w := rl.MeasureText(txt, 18)
	rl.DrawText(txt, i32(center.x) - w / 2, i32(center.y) - 9, 18, rl.Color{255, 255, 255, 255})
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
		ind := fmt.ctprintf("Round %d   -   %s", b.round, label)
		iw := rl.MeasureText(ind, 22)
		rl.DrawText(ind, i32(sw) / 2 - iw / 2, 14, 22, col)
	}

	draw_buttons(b)
	draw_battle_log(b)

	if b.switch_menu {
		draw_switch_overlay(b)
	}

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

		lvl := fmt.ctprintf("Lv %d  %s", e.level, element_name(creature_element(e)))
		lw := rl.MeasureText(lvl, 15)
		rl.DrawText(lvl, i32(ex) - lw / 2, i32(ey) - 86, 15, element_color(creature_element(e)))

		hp_rec := rl.Rectangle{ex - 70, ey + 70, 140, 18}
		draw_bar(hp_rec, e.hp, e.max_hp, COL_HP)
		hp_txt := fmt.ctprintf("%d/%d", e.hp, e.max_hp)
		hw := rl.MeasureText(hp_txt, 13)
		rl.DrawText(hp_txt, i32(ex) - hw / 2, i32(hp_rec.y) + 2, 13, COL_TEXT)

		if e.block > 0 {
			draw_badge(rl.Vector2{ex + 84, ey + 78}, e.block, COL_BLOCK)
		}
		if e.vulnerable > 0 {
			draw_badge(rl.Vector2{ex + 84, ey + 40}, e.vulnerable, COL_VULN)
		}

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
	panel := rl.Rectangle{16, 16, 344, 138}
	rl.DrawRectangleRounded(panel, 0.10, 8, COL_PANEL)
	rl.DrawRectangleRoundedLinesEx(panel, 0.10, 8, 2, rl.Color{60, 60, 78, 255})

	ox, oy := creature_offset(c)
	draw_creature_avatar(rl.Vector2{panel.x + 48 + ox, panel.y + 62 + oy}, 34, c, false)

	name := fmt.ctprintf("%s", c.name)
	rl.DrawText(name, i32(panel.x) + 94, i32(panel.y) + 14, 22, COL_TEXT)
	sub := fmt.ctprintf("Lv %d  %s  PWR +%d  DEF %d  SPD %d", c.level, element_name(creature_element(c)), c.power, creature_defense(c), c.speed)
	rl.DrawText(sub, i32(panel.x) + 94, i32(panel.y) + 40, 16, element_color(creature_element(c)))

	hp_rec := rl.Rectangle{panel.x + 94, panel.y + 64, 210, 20}
	draw_bar(hp_rec, c.hp, c.max_hp, COL_HP)
	hp_txt := fmt.ctprintf("%d / %d", c.hp, c.max_hp)
	rl.DrawText(hp_txt, i32(hp_rec.x) + 8, i32(hp_rec.y) + 2, 15, COL_TEXT)

	if c.block > 0 {
		draw_badge(rl.Vector2{panel.x + 322, panel.y + 74}, c.block, COL_BLOCK)
	}
	if c.vulnerable > 0 {
		draw_badge(rl.Vector2{panel.x + 322, panel.y + 34}, c.vulnerable, COL_VULN)
	}

	rl.DrawText(fmt.ctprintf("Energy +%s", fmt_num(c.energy_regen)), i32(panel.x) + 94, i32(panel.y) + 96, 15, COL_MUTED)
	draw_energy(panel.x + 156, panel.y + 104, 160, c.energy, c.energy_max)

	piles := vfmt(b, "deck %d", len(c.deck))
	rl.DrawText(piles, i32(panel.x) + 94, i32(panel.y) + 116, 14, COL_MUTED)
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
		lv := fmt.ctprintf("Lv%d", c.level)
		rl.DrawText(lv, i32(rec.x) + 54, i32(rec.y) + 44, 12, COL_MUTED)

		if active {
			rl.DrawText("ACTIVE", i32(rec.x) + 150, i32(rec.y) + 44, 12, rl.Color{120, 230, 180, 255})
		}
	}
}

draw_hand :: proc(b: ^Battle) {
	mp := rl.GetMousePosition()
	hand := b.party[b.active].hand
	for id, i in hand {
		rec := hand_card_rect(i, len(hand))
		playable := b.phase == .PLAYER_ACTION && !b.switch_menu && b.party[b.active].energy >= move_data(id).cost
		hovered := rl.CheckCollisionPointRec(mp, rec)
		draw_card(id, rec, playable, hovered)
	}
}

draw_buttons :: proc(b: ^Battle) {
	mp := rl.GetMousePosition()

	// capture
	cap := capture_rect()
	cap_hover := rl.CheckCollisionPointRec(mp, cap)
	chance := int(capture_chance(b) * 100)
	can_cap := b.phase == .PLAYER_ACTION && !b.switch_menu && b.capture_cards > 0 && len(b.enemies) > 0
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
	if b.phase != .PLAYER_ACTION || b.switch_menu {
		btn_col = rl.Color{45, 60, 55, 255}
	} else if btn_hover {
		btn_col = rl.Color{95, 175, 130, 255}
	}
	rl.DrawRectangleRounded(btn, 0.25, 8, btn_col)
	rl.DrawRectangleRoundedLinesEx(btn, 0.25, 8, 2, rl.Color{210, 230, 220, 255})
	et := cstring("End My Turn (E)")
	ew := rl.MeasureText(et, 18)
	rl.DrawText(et, i32(btn.x + btn.width / 2) - ew / 2, i32(btn.y + btn.height / 2) - 9, 18, rl.Color{240, 255, 245, 255})

	hint := cstring("V deck  |  T switch  |  C capture")
	rl.DrawText(hint, i32(btn.x), i32(cap.y) - 26, 15, COL_MUTED)
}

draw_battle_log :: proc(b: ^Battle) {
	for msg, i in b.log {
		rl.DrawText(fmt.ctprintf("%s", msg), 16, 172 + i32(i) * 21, 15, COL_MUTED)
	}
}

draw_switch_overlay :: proc(b: ^Battle) {
	sw := f32(rl.GetScreenWidth())
	sh := f32(rl.GetScreenHeight())
	rl.DrawRectangle(0, 0, i32(sw), i32(sh), rl.Color{0, 0, 0, 150})

	title := cstring("Choose a creature to send out")
	if b.forced_switch {
		title = "Your creature fainted - choose a replacement"
	}
	tw := rl.MeasureText(title, 26)
	rl.DrawText(title, i32(sw) / 2 - tw / 2, 70, 26, COL_TEXT)

	for i in 0..<len(b.party) {
		if i == b.active {
			continue
		}
		rec := party_entry_rect(i)
		dead := b.party[i].hp <= 0
		if dead {
			rl.DrawRectangleRounded(rec, 0.18, 6, rl.Color{30, 26, 30, 255})
		} else if rl.CheckCollisionPointRec(rl.GetMousePosition(), rec) {
			rl.DrawRectangleRounded(rec, 0.18, 6, rl.Color{50, 60, 52, 255})
		}
	}

	if !b.forced_switch {
		hint := cstring("Esc / T to cancel")
		hw := rl.MeasureText(hint, 18)
		rl.DrawText(hint, i32(sw) / 2 - hw / 2, i32(sh) - 60, 18, COL_MUTED)
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

draw_game_over :: proc(moves: int) {
	sw := f32(rl.GetScreenWidth())
	sh := f32(rl.GetScreenHeight())

	rl.ClearBackground(rl.Color{28, 8, 12, 255})

	title := cstring("YOUR PARTY HAS FALLEN")
	tw := rl.MeasureText(title, 58)
	rl.DrawText(title, i32(sw) / 2 - tw / 2, i32(sh) / 2 - 100, 58, rl.Color{220, 60, 60, 255})

	sub := fmt.ctprintf("You travelled %d rooms into the underground.", moves)
	sw2 := rl.MeasureText(sub, 22)
	rl.DrawText(sub, i32(sw) / 2 - sw2 / 2, i32(sh) / 2 - 10, 22, COL_TEXT)

	hint := cstring("Press N to choose a new starter")
	hw := rl.MeasureText(hint, 26)
	rl.DrawText(hint, i32(sw) / 2 - hw / 2, i32(sh) / 2 + 56, 26, rl.Color{220, 180, 120, 255})
}
