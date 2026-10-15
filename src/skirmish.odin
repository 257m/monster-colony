package main

// ============================================================================
// SKIRMISHES
//
// Wild-vs-wild fights (crowd brawls and predation) resolve through the *real*
// battle engine, run headlessly: both sides are set up with `battle_start`, the
// AI plays each side, and the outcome is written back onto the map creatures.
//
// Because a turn could otherwise trigger a dozen fights, each turn has a budget
// of real battles (`MAX_HEADLESS_BATTLES`); once it's spent the remaining fights
// fall back to a cheap stat comparison so a pile-up can't stall the turn.
// ============================================================================

MAX_HEADLESS_BATTLES :: 8

// Run one battle to completion with no UI. Returns true if `party` won, plus the
// number of rounds it took.
run_headless_battle :: proc(party, enemies: []^Creature, rng: ^Rng) -> (party_won: bool, rounds: int) {
	b := battle_start(party, enemies, nil, rng)
	b.auto_play = true
	prev := battle_silent
	battle_silent = true
	defer battle_silent = prev
	// Every step with a generous dt fires exactly one AI action.
	for _ in 0..<5000 {
		if b.phase == .WON || b.phase == .LOST || b.phase == .CAPTURED {
			break
		}
		battle_update(&b, 0.7)
	}
	party_won = b.phase == .WON
	rounds = b.round
	battle_free(&b)
	return
}

// A rough strength estimate for the cheap fallback path.
skirmish_score :: proc(c: ^Creature) -> f32 {
	hp_f := f32(max(c.hp, 0)) / f32(max(c.max_hp, 1))
	return c.power * (1.0 + 0.12 * f32(c.level)) * (0.35 + 0.65 * hp_f)
}

// Resolve a one-on-one fight. Returns whether `a` won.
resolve_duel :: proc(c: ^Colony, a, b: ^Monster) -> (a_won: bool, rounds: int) {
	if c.battles_this_turn < MAX_HEADLESS_BATTLES {
		c.battles_this_turn += 1
		pa := [1]^Creature{&a.creature}
		pb := [1]^Creature{&b.creature}
		return run_headless_battle(pa[:], pb[:], &c.rng)
	}
	return skirmish_score(&a.creature) >= skirmish_score(&b.creature), 1
}

// Resolve a whole-tile brawl. Returns whether side A won.
resolve_team :: proc(c: ^Colony, a_side, b_side: []^Creature) -> (a_won: bool, rounds: int) {
	if c.battles_this_turn < MAX_HEADLESS_BATTLES {
		c.battles_this_turn += 1
		return run_headless_battle(a_side, b_side, &c.rng)
	}
	sa, sb := f32(0), f32(0)
	for x in a_side {
		sa += skirmish_score(x)
	}
	for x in b_side {
		sb += skirmish_score(x)
	}
	quick_team(a_side, b_side)
	return sa >= sb, 1
}

// Fallback brawl: the weaker half of the losing side is dragged down (hp set to
// 0; the caller removes the fallen).
quick_team :: proc(a_side, b_side: []^Creature) {
	sa, sb := f32(0), f32(0)
	for x in a_side {
		sa += skirmish_score(x)
	}
	for x in b_side {
		sb += skirmish_score(x)
	}
	losing := sa >= sb ? b_side : a_side
	if len(losing) == 0 {
		return
	}
	dead := make([]bool, len(losing))
	defer delete(dead)
	n := len(losing) / 2 + 1
	for _ in 0..<n {
		bi := -1
		bs := f32(0)
		for x, i in losing {
			if dead[i] {
				continue
			}
			s := skirmish_score(x)
			if bi < 0 || s < bs {
				bi, bs = i, s
			}
		}
		if bi < 0 {
			break
		}
		dead[bi] = true
		losing[bi].hp = 0
	}
}
