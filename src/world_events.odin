package main

import rl "vendor:raylib"

// ============================================================================
// WORLD EVENTS
//
// Each turn there's a small chance something happens out in the world. Events
// only ever affect monsters or resources — they never rewrite terrain — so the
// map's terrain distribution can't drift over a long run.
// ============================================================================

World_Event :: enum { TREMOR, STAMPEDE, DISTANT_ROAR, MIGRATION }

WORLD_EVENT_CHANCE  :: f32(0.12)
// An alpha is the one world event that hunts your buildings, so it stays out of
// the pool until the colony has had time to put up walls. (Raid alphas are
// already gated behind RAID_GRACE and a doubled heat threshold.)
ALPHA_EVENT_GRACE   :: 40
TREMOR_DUR          :: f32(0.6)
TREMOR_RADIUS       :: 4
TREMOR_BUILDING_DMG :: 14
TREMOR_MONSTER_PCT  :: f32(0.10)

colony_world_events :: proc(c: ^Colony) {
	if rng_f32(&c.rng) >= WORLD_EVENT_CHANCE {
		return
	}
	// Pick from the events that are allowed yet. The roar joins the pool at
	// ALPHA_EVENT_GRACE and takes an even share from then on.
	pool := [?]World_Event{.TREMOR, .STAMPEDE, .MIGRATION}
	ev := pool[rng_below(&c.rng, len(pool))]
	if c.turn >= ALPHA_EVENT_GRACE && rng_below(&c.rng, 4) == 3 {
		ev = .DISTANT_ROAR
	}
	switch ev {
	case .TREMOR:
		tremor_strike(c)
	case .STAMPEDE:
		center := player_center(c)
		n := 2 + rng_below(&c.rng, 2)
		dir := rng_below(&c.rng, 6)
		for _ in 0..<n {
			h := center
			for _ in 0..<7 {
				ns := hex_neighbors(h)
				h = ns[dir]
			}
			t := ensure_tile(c, h)
			if t == nil {
				continue
			}
			spawn_wild_at(c, h, spawn_species_for(t.terrain, &c.rng), spawn_level_for(c, h))
		}
		colony_notify(c, "A stampede thunders past — the wilds are on the move.")
	case .DISTANT_ROAR:
		center := player_center(c)
		dir := rng_below(&c.rng, 6)
		h := center
		for _ in 0..<6 {
			ns := hex_neighbors(h)
			h = ns[dir]
		}
		t := ensure_tile(c, h)
		if t != nil {
			species := spawn_species_for(t.terrain, &c.rng)
			spawn_wild_at(c, h, species, spawn_level_for(c, h) + 2, .ALPHA)
			colony_notify(c, "A distant roar — something big has picked up your scent.")
		}
	case .MIGRATION:
		dir := rng_below(&c.rng, 6)
		moved := 0
		for i in 0..<len(c.roster) {
			m := &c.roster[i]
			if !m.wild || m.role != .WILD {
				continue
			}
			ns := hex_neighbors(m.pos)
			n := ns[dir]
			if tile_passable(c, m, n) {
				m.pos = n
				moved += 1
			}
		}
		if moved > 0 {
			colony_notify(c, "A migration sweeps through — wilds stream past.")
		}
	}
}

// A tremor: shake the screen, crack nearby buildings, and bruise nearby
// monsters. Improvements can be destroyed; monsters are chipped, never killed.
tremor_strike :: proc(c: ^Colony) {
	c.tremor = TREMOR_DUR
	center := player_center(c)
	buildings_hit := 0
	monsters_hit := 0
	now := f32(rl.GetTime())

	for i in 0..<len(c.tiles) {
		t := c.tiles[i]
		if hex_distance(t.hex, center) > TREMOR_RADIUS {
			continue
		}
		if t.improvement == .NONE && t.overlay == .NONE {
			continue
		}
		t.hit_t0 = now
		damage_improvement(c, t, TREMOR_BUILDING_DMG, "A tremor")
		buildings_hit += 1
	}

	for i in 0..<len(c.roster) {
		m := &c.roster[i]
		if hex_distance(m.pos, center) > TREMOR_RADIUS || m.creature.hp <= 0 {
			continue
		}
		dmg := max(1, int(f32(m.creature.max_hp) * TREMOR_MONSTER_PCT))
		m.creature.hp = max(1, m.creature.hp - dmg)
		colony_add_float(c, m.pos, .DAMAGE, dmg)
		monsters_hit += 1
	}

	switch {
	case buildings_hit > 0 && monsters_hit > 0:
		colony_notify(c, "A tremor! Buildings crack and monsters stagger.")
	case buildings_hit > 0:
		colony_notify(c, "A tremor cracks the nearby buildings.")
	case monsters_hit > 0:
		colony_notify(c, "A tremor sends monsters reeling.")
	case:
		colony_notify(c, "The ground shudders. Dust rains from the ceiling.")
	}
}
