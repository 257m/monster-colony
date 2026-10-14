package main

import rl "vendor:raylib"
import "core:fmt"
tile_prevents_spawn :: proc(t: ^Tile) -> bool {
	return t.improvement == .FARM || t.improvement == .MINE
}

terrain_spawn_chance :: proc(t: Terrain) -> f32 {
	switch t {
	case .CAVE:         return 0.03
	case .WATER:        return 0.015
	case .GROVE:        return 0.03
	case .DUNGEON:      return 0.08
	case .TRADING_POST: return 0.0
	case .BOSS_ROOM:    return 0.0
	case .MUSHROOM:     return 0.02
	case .RUINS:        return 0.05
	case .TUNDRA:       return 0.05
	case .JUNGLE:       return 0.06
	case .LAVA:         return 0.05
	case .DESERT:       return 0.05
	case .QUICKSAND:    return 0.03
	case .ARENA:        return 0.0
	case .CRYSTAL_COVE: return 0.03
	}
	return 0.0
}

// New colonies get a grace period: wild spawns ramp from 10% up to full over the
// first SPAWN_GRACE_TURNS turns, so the opening isn't overwhelming.
SPAWN_GRACE_TURNS :: 30
spawn_ramp :: proc(turn: int) -> f32 {
	if turn >= SPAWN_GRACE_TURNS {
		return 1.0
	}
	return 0.1 + 0.9 * f32(turn) / f32(SPAWN_GRACE_TURNS)
}

// Weighted spawn pick: one rng roll, linear scan over a tiny cutoffs table.
// Entries must be sorted by ascending cutoff; the last cutoff must be 1.0.
Spawn_Entry :: struct {
	cutoff:  f32,
	species: Species_Id,
}

spawn_pick :: proc(r: f32, entries: []Spawn_Entry) -> Species_Id {
	for e in entries {
		if r < e.cutoff {
			return e.species
		}
	}
	return entries[len(entries) - 1].species
}

SPAWN_CAVE := [?]Spawn_Entry {
	{0.30, .Gloomling},
	{0.50, .Wispling},
	{1.0, .Cave_Bat},
}
SPAWN_GROVE := [?]Spawn_Entry {
	{0.30, .Swampbeast},
	{0.50, .Mosshide},
	{1.0, .Thornkit},
}
SPAWN_WATER := [?]Spawn_Entry {
	{0.22, .Krakling},
	{0.40, .Rimescale},
	{0.58, .Bogfang},
	{0.72, .Frostmoss},
	{1.0, .Bubblet},
}
SPAWN_DUNGEON := [?]Spawn_Entry {
	{0.12, .Elite_Sentinel},
	{0.34, .Pyrelord},
	{0.54, .Cindermaw},
	{0.72, .Emberbloom},
	{1.0, .Magmite},
}
SPAWN_MUSHROOM := [?]Spawn_Entry {
	{0.28, .Mosshide},
	{0.52, .Swampbeast},
	{0.72, .Frostmoss},
	{1.0, .Thornkit},
}
SPAWN_RUINS := [?]Spawn_Entry {
	{0.28, .Wispling},
	{0.52, .Gloomling},
	{0.72, .Cinderwing},
	{1.0, .Magmite},
}
SPAWN_TUNDRA := [?]Spawn_Entry {
	{0.35, .Frostfang},
	{0.60, .Blizzard},
	{0.80, .Galebeast},
	{1.0, .Frostfang},
}
SPAWN_JUNGLE := [?]Spawn_Entry {
	{0.35, .Venomtail},
	{0.65, .Swampbeast},
	{1.0, .Mosshide},
}
SPAWN_LAVA := [?]Spawn_Entry {
	{0.30, .Pyrelord},
	{0.60, .Cindermaw},
	{1.0, .Magmite},
}
SPAWN_DESERT := [?]Spawn_Entry {
	{0.35, .Stonepaw},
	{0.65, .Sparkit},
	{1.0, .Magmite},
}
SPAWN_CRYSTAL_COVE := [?]Spawn_Entry {
	{0.30, .Stonepaw},
	{0.55, .Frostfang},
	{0.78, .Rimescale},
	{1.0, .Sparkit},
}

spawn_species_for :: proc(t: Terrain, rng: ^Rng) -> Species_Id {
	switch t {
	case .CAVE:         return spawn_pick(rng_f32(rng), SPAWN_CAVE[:])
	case .GROVE:        return spawn_pick(rng_f32(rng), SPAWN_GROVE[:])
	case .WATER:        return spawn_pick(rng_f32(rng), SPAWN_WATER[:])
	case .DUNGEON:      return spawn_pick(rng_f32(rng), SPAWN_DUNGEON[:])
	case .MUSHROOM:     return spawn_pick(rng_f32(rng), SPAWN_MUSHROOM[:])
	case .RUINS:        return spawn_pick(rng_f32(rng), SPAWN_RUINS[:])
	case .TUNDRA:       return spawn_pick(rng_f32(rng), SPAWN_TUNDRA[:])
	case .JUNGLE:       return spawn_pick(rng_f32(rng), SPAWN_JUNGLE[:])
	case .LAVA:         return spawn_pick(rng_f32(rng), SPAWN_LAVA[:])
	case .DESERT:       return spawn_pick(rng_f32(rng), SPAWN_DESERT[:])
	case .CRYSTAL_COVE: return spawn_pick(rng_f32(rng), SPAWN_CRYSTAL_COVE[:])
	case .QUICKSAND:    return .Stonepaw
	case .BOSS_ROOM:    return .Deep_One
	case .TRADING_POST: return .Cave_Bat
	case .ARENA:        return .Cave_Bat
	}
	return .Cave_Bat
}

// Threats keep pace with the run: wilds and raiders gain levels over time, so
// an over-levelled colony never trivialises the wilds near the entrance. This
// is the single knob that makes the world get meaner the longer you survive.
colony_escalation :: proc(c: ^Colony) -> int {
	return c.turn / 20
}

// Highest level among your monsters — used to keep wilds relevant even in the
// "safe" zone near the entrance, so a strong colony can't farm trivial fights.
player_top_level :: proc(c: ^Colony) -> int {
	top := 1
	for m in c.roster {
		if !m.wild && m.creature.hp > 0 && m.creature.level > top {
			top = m.creature.level
		}
	}
	return top
}

spawn_level_for :: proc(c: ^Colony, hex: Hex) -> int {
	// Weaker near the entrance, tougher the further out you are — and tougher
	// the longer the run has gone on. Wilds never fall far behind your best
	// monster, so there is always something worth fighting.
	dist := hex_distance(c.start_hex, hex)
	by_place := 1 + c.floor / 2 + dist / 4 + colony_escalation(c)
	by_player := player_top_level(c) * 2 / 3
	return max(by_place, by_player) + rng_below(&c.rng, 2)
}

// The Arena sends a fresh, strong team onto its tile when challenged.
colony_spawn_arena_team :: proc(c: ^Colony, hex: Hex) {
	lvl := spawn_level_for(c, hex) + ARENA_LEVEL_BONUS
	for _ in 0..<ARENA_TEAM_SIZE {
		sp := Species_Id(rng_below(&c.rng, len(Species_Id)))
		spawn_wild_at(c, hex, sp, lvl)
	}
}

spawn_wild_at :: proc(c: ^Colony, hex: Hex, species: Species_Id, level: int, role: Wild_Role = .WILD, pack: int = 0) {
	m := Monster{
		id       = c.next_id,
		creature = creature_make(species, level, SPECIES[species].name, &c.rng),
		pos      = hex,
		wild     = true,
		role     = role,
		pack     = pack,
	}
	c.next_id += 1
	// Wilds use a level-appropriate deck (see `enrich_wild_deck`).
	enrich_wild_deck(&m.creature)
	append(&c.roster, m)
}

nearest_player_distance :: proc(c: ^Colony, hex: Hex) -> int {
	best := 1 << 30
	for m in c.roster {
		if !m.wild {
			d := hex_distance(m.pos, hex)
			if d < best {
				best = d
			}
		}
	}
	return best
}

nearest_player_hex :: proc(c: ^Colony, hex: Hex) -> Hex {
	best := 1 << 30
	res := hex
	for m in c.roster {
		if !m.wild {
			d := hex_distance(m.pos, hex)
			if d < best {
				best = d
				res = m.pos
			}
		}
	}
	return res
}

colony_spawn_wilds :: proc(c: ^Colony) {
	// Deterrence is a radial check; gather the watchtowers/beacons/scarecrows
	// once so the tile sweep below is O(tiles x deterrents), not O(tiles^2).
	towers := make([dynamic]Hex, 0); defer delete(towers)
	beacons := make([dynamic]Hex, 0); defer delete(beacons)
	scarecrows := make([dynamic]Hex, 0); defer delete(scarecrows)
	collect_improvement_hexes(c, .WATCHTOWER, &towers)
	collect_improvement_hexes(c, .BEACON, &beacons)
	collect_improvement_hexes(c, .SCARECROW, &scarecrows)
	tower_r := WATCHTOWER_DETER + upgrade_vigilance(c)
	beacon_r := BEACON_DETER + upgrade_vigilance(c)
	scare_r := SCARECROW_DETER + upgrade_warding(c)

	for i in 0..<len(c.tiles) {
		if wild_monsters(c) >= MAX_WILDS {
			return
		}
		t := c.tiles[i]
		if tile_prevents_spawn(t) {
			continue
		}
		if monsters_on_tile(c, t.hex, false) > 0 {
			continue // guarded
		}
		if near_any(t.hex, tower_r, towers[:]) {
			continue // watchtowers deter spawns
		}
		if near_any(t.hex, beacon_r, beacons[:]) {
			continue // beacons deter over a wider area
		}
		if near_any(t.hex, scare_r, scarecrows[:]) {
			continue // scarecrows keep spawns out
		}
		// Simulated on all tiles near your monsters, explored or not.
		if nearest_player_distance(c, t.hex) > SIM_DISTANCE {
			continue
		}
		if rng_f32(&c.rng) >= terrain_spawn_chance(t.terrain) * spawn_ramp(c.turn) {
			continue
		}
		sp := spawn_species_for(t.terrain, &c.rng)
		spawn_wild_at(c, t.hex, sp, spawn_level_for(c, t.hex))
	}
}

// ----------------------------------------------------------------------------
// Phase D — heat, raids & alphas
// ----------------------------------------------------------------------------

// How much attention an improvement draws — heat it adds while it stands.
// Loud things (lookouts, beacons, a glowing refinery, a firing turret) pull
// raids; quiet ones (roads, walls, traps) barely register.
// How much attention an improvement draws — heat it adds while it stands.
// Loud things (lookouts, beacons, a glowing refinery, a firing turret) pull
// raids; quiet ones (roads, walls, traps) barely register.
total_monster_levels :: proc(c: ^Colony) -> int {
	n := 0
	for m in c.roster {
		if !m.wild && m.creature.hp > 0 { n += m.creature.level }
	}
	return n
}

// Heat is your footprint: every improvement adds its own weight (see
// `improvement_heat`) and every monster level pushes it higher. Nothing lowers
// it — defences don't cool the colony, they just make it harder to raid.
raid_interval :: proc(heat: int) -> int {
	return clamp(RAID_BASE_INTERVAL - heat, RAID_MIN_INTERVAL, RAID_BASE_INTERVAL)
}

raid_size :: proc(heat: int) -> int {
	return clamp(2 + heat / 4, 2, RAID_MAX_SIZE)
}

// Hotter colonies raise not just more raiders, but tougher ones.
raid_level_bonus :: proc(heat: int) -> int {
	return heat / RAID_LEVEL_PER_HEAT
}

// Centre of your colony for raid staging: the first living monster you own.
player_center :: proc(c: ^Colony) -> Hex {
	for m in c.roster {
		if !m.wild && m.creature.hp > 0 {
			return m.pos
		}
	}
	return c.start_hex
}

// Nearest tile that carries an improvement (building or overlay).
nearest_improvement_hex :: proc(c: ^Colony, from: Hex) -> Hex {
	best := 1 << 30
	res := from
	for t in c.tiles {
		if t.improvement == .NONE && t.overlay == .NONE {
			continue
		}
		d := hex_distance(from, t.hex)
		if d < best {
			best = d
			res = t.hex
		}
	}
	return res
}

// The closer of the nearest player monster and the nearest improvement — what a
// raider marches on (so raids hit both your monsters and your buildings).
nearest_player_or_improvement_hex :: proc(c: ^Colony, from: Hex) -> Hex {
	p := nearest_player_hex(c, from)
	i := nearest_improvement_hex(c, from)
	if hex_equal(i, from) {
		return p
	}
	if hex_equal(p, from) {
		return i
	}
	if hex_distance(from, i) < hex_distance(from, p) {
		return i
	}
	return p
}

// Organise a raid when the timer elapses and the colony is hot enough. Raiders
// spawn in a ring a few tiles off your colony and march in; a really hot colony
// gets an alpha leading them.
colony_raids :: proc(c: ^Colony) {
	if c.turn == RAID_GRACE {
		colony_notify(c, "The wilds have scented the colony - raids can begin.")
	}
	// The timer ticks every turn so the first raid isn't double-delayed by the
	// grace period; the spawn itself still waits for the grace AND enough heat.
	if c.raid_timer > 0 {
		c.raid_timer -= 1
	}
	if c.turn < RAID_GRACE || c.heat < RAID_MIN_HEAT || c.raid_timer > 0 {
		return
	}

	origin := player_center(c)
	cands := make([dynamic]Hex, 0)
	defer delete(cands)
	for i in 0..<len(c.tiles) {
		t := c.tiles[i]
		// Raids ignore spawn deterrence (watchtowers/beacons/scarecrows) and the
		// Farm/Mine no-spawn rule — they exist to hit your improvements. They
		// just don't materialise on top of one of your monsters.
		if monsters_on_tile(c, t.hex, false) > 0 {
			continue
		}
		d := hex_distance(origin, t.hex)
		if d < SIM_DISTANCE - 1 || d > DESPAWN_DISTANCE {
			continue
		}
		append(&cands, t.hex)
	}
	if len(cands) == 0 {
		c.raid_timer = 4
		return
	}

	size := raid_size(c.heat)
	alpha := c.heat >= RAID_MIN_HEAT * 2
	heat_lvl := raid_level_bonus(c.heat)
	for k in 0..<size {
		h := cands[rng_below(&c.rng, len(cands))]
		t := tile_at(c, h)
		sp := spawn_species_for(t.terrain, &c.rng)
		lvl := spawn_level_for(c, h) + 1 + heat_lvl
		role := Wild_Role.RAIDER
		if alpha && k == 0 {
			// The alpha is twice the level of a rank-and-file raider.
			role = .ALPHA
			lvl *= 2
		} else {
			// A growing share of the rank and file specialise as the run drags
			// on: sieges tear down buildings, stalkers run down monsters.
			spec := clamp(0.15 + f32(colony_escalation(c)) * 0.03, 0, 0.5)
			roll := rng_f32(&c.rng)
			if roll < spec {
				role = .SIEGE
			} else if roll < spec * 2 {
				role = .STALKER
			}
		}
		spawn_wild_at(c, h, sp, lvl, role)
	}
	c.raids += 1
	c.raid_timer = raid_interval(c.heat)
	audio_play(.RAID)
	dir := compass_dir(origin, cands[0])
	colony_notify(c, "A raid of %d gathers %s%s!", size, dir == "here" ? "right here" : fmt.ctprintf("to the %s", dir), alpha ? " (led by an alpha)" : "")
}

// A hunting wild steps toward its target; if a fortification is in the way it
// batters it instead of wandering off. `ignore_walls` lets a stalker slip past
// fortifications rather than stopping to break them.
step_hunt :: proc(c: ^Colony, m: ^Monster, target: Hex, ignore_walls := false) {
	if hex_equal(m.pos, target) {
		return
	}
	best := m.pos
	best_d := hex_distance(m.pos, target)
	block: ^Tile = nil
	block_d := 1 << 30
	for n in hex_neighbors(m.pos) {
		t := tile_at(c, n)
		if t == nil {
			continue
		}
		d := hex_distance(n, target)
		passable := tile_passable(c, m, n)
		if ignore_walls && !passable {
			// A stalker slips past fortifications but still obeys terrain.
			passable = terrain_passable(c, m, n)
		}
		if passable {
			if d < best_d {
				best_d = d
				best = n
			}
		} else if improvement_blocks_wilds(t) && d < block_d {
			block_d = d
			block = t
		}
	}
	if !hex_equal(best, m.pos) {
		m.pos = best
	} else if block != nil {
		damage_improvement(c, block, wild_improvement_damage(m))
	}
}

// Wilds far from your presence may wander off, and excess is culled from the
// farthest tiles, so the world doesn't fill up.
colony_despawn_wilds :: proc(c: ^Colony) {
	// Gather scarecrows once so the per-wild spook check doesn't rescan tiles.
	scarecrows := make([dynamic]Hex, 0)
	defer delete(scarecrows)
	collect_improvement_hexes(c, .SCARECROW, &scarecrows)
	panic_r := SCARECROW_PANIC + upgrade_warding(c)

	i := 0
	for i < len(c.roster) {
		m := &c.roster[i]
		if !m.wild {
			i += 1
			continue
		}
		// Raiders and alphas are committed: they don't wander off or spook.
		if m.role != .WILD {
			i += 1
			continue
		}
		if nearest_player_distance(c, m.pos) > DESPAWN_DISTANCE && rng_f32(&c.rng) < DESPAWN_CHANCE {
			if rng_f32(&c.rng) < 0.25 {
				dir := compass_dir(nearest_player_hex(c, m.pos), m.pos)
				colony_notify(c, "Something skitters away into the dark %s.", fmt.ctprintf("to the %s", dir))
			}
			remove_monster_at(c, i, false)
			continue
		}
		// Scarecrows spook nearby wilds — they bolt away from it rather than
		// vanishing outright. Tougher monsters are more likely to shrug it off.
		if near_any(m.pos, panic_r, scarecrows[:]) {
			panic := clamp(SCARECROW_PANIC_CHANCE - f32(m.creature.level) * 0.06, 0.05, SCARECROW_PANIC_CHANCE)
			if rng_f32(&c.rng) < panic {
				sc := nearest_hex_in(m.pos, panic_r, scarecrows[:])
				start := m.pos
				// Step up to two tiles, each time choosing the neighbour that
				// is farthest from the Scarecrow.
				for _ in 0 ..< 2 {
					best := m.pos
					best_d := hex_distance(m.pos, sc)
					for n in hex_neighbors(m.pos) {
						if !tile_passable(c, m, n) {
							continue
						}
						if monsters_on_tile(c, n, false) > 0 {
							continue // don't flee onto the player
						}
						if d := hex_distance(n, sc); d > best_d {
							best_d = d
							best = n
						}
					}
					if hex_equal(best, m.pos) {
						break
					}
					m.pos = best
				}
				if !hex_equal(m.pos, start) {
					colony_notify(c, "%s bolts from a Scarecrow!", m.creature.name)
					colony_add_float(c, start, .FLEE, 1)
				}
			}
		}
		i += 1
	}
	// Hard cap: cull the wild farthest from you.
	for wild_monsters(c) > MAX_WILDS - 6 {
		far_i := -1
		far_d := -1
		for m, k in c.roster {
			if !m.wild || m.role != .WILD {
				continue // keep committed raiders/alphas
			}
			d := nearest_player_distance(c, m.pos)
			if d > far_d {
				far_d = d
				far_i = k
			}
		}
		if far_i < 0 {
			break
		}
		remove_monster_at(c, far_i, false)
	}
}

// Too many wilds on one tile: they turn on each other and one dies.
colony_crowd_fights :: proc(c: ^Colony) {
	i := 0
	for i < len(c.roster) {
		if !c.roster[i].wild {
			i += 1
			continue
		}
		hex := c.roster[i].pos
		if monsters_on_tile(c, hex, true) <= CROWD_LIMIT {
			i += 1
			continue
		}
		if rng_f32(&c.rng) < CROWD_FIGHT_CHANCE {
			t := tile_at(c, hex)
			revealed := t != nil && t.revealed
			if t != nil {
				t.scuffle = 3
			}
			dir := compass_dir(nearest_player_hex(c, hex), hex)
			if revealed {
				colony_notify(c, "A scuffle breaks out %s.", dir == "here" ? "right here" : fmt.ctprintf("to the %s", dir))
			} else {
				colony_notify(c, "Snarling in the fog %s.", fmt.ctprintf("to the %s", dir))
			}
			// One wild on this tile loses the scrap.
			remove_monster_at(c, i, false)
			continue
		}
		i += 1
	}
}

colony_roam_wilds :: proc(c: ^Colony) {
	for i in 0..<len(c.roster) {
		m := &c.roster[i]
		if !m.wild {
			continue
		}
		// Raiders hit the nearer of your monsters/improvements; alphas hunt your
		// monsters; sieges beeline for your buildings; stalkers are fast and
		// ghost through walls. Every wild moves every turn.
		if m.role != .WILD {
			switch m.role {
			case .ALPHA:
				step_hunt(c, m, nearest_player_hex(c, m.pos))
			case .SIEGE:
				step_hunt(c, m, nearest_improvement_hex(c, m.pos))
			case .STALKER:
				step_hunt(c, m, nearest_player_hex(c, m.pos), true)
				step_hunt(c, m, nearest_player_hex(c, m.pos), true)
			case .BOSS, .CRONY:
				// Boss packs move together in `colony_roam_boss_packs`.
			case .RAIDER, .WILD:
				step_hunt(c, m, nearest_player_or_improvement_hex(c, m.pos))
			}
			continue
		}
		// Plain wilds always wander (no staying put).
		ns := hex_neighbors(m.pos)
		start := rng_below(&c.rng, 6)
		for k in 0..<6 {
			n := ns[(start + k) % 6]
			t := tile_at(c, n)
			if t == nil {
				continue
			}
			if tile_passable(c, m, n) {
				m.pos = n
				break
			}
			// It tried to step into a fortification and couldn't, so it throws
			// itself at it. Only the first heading it picks counts as the
			// attempt; blocked terrain just makes it try another direction.
			if k == 0 && improvement_blocks_wilds(t) {
				damage_improvement(c, t, wild_improvement_damage(m))
				break
			}
		}
	}
}

// Damage a wild deals to an improvement — whether it battered a blocker on its
// way past or is wrecking one it's standing on. Sieges hit buildings twice as
// hard.
wild_improvement_damage :: proc(m: ^Monster) -> int {
	d := 6 + m.creature.level * 3
	if m.role == .SIEGE {
		d *= 2
	}
	return d
}

damage_improvement :: proc(c: ^Colony, t: ^Tile, dmg: int) {
	// The building takes the hit first; once it's rubble the overlay is next.
	if t.improvement != .NONE {
		t.improvement_hp -= dmg
		t.hit_t0 = f32(rl.GetTime())
		colony_add_float(c, t.hex, .DAMAGE, dmg)
		if t.improvement_hp <= 0 {
			// Destroyed: contents are lost. Den/Nursery occupants are pushed
			// back onto the map (or lost if there is nowhere to stand).
			colony_notify(c, "Wilds destroyed your %s!", improvement_name(t.improvement))
			if t.improvement == .DEN || t.improvement == .NURSERY {
				colony_evacuate_storage(c, t.hex)
			}
			t.stored = 0
			t.improvement = .NONE
			t.improvement_hp = 0
			colony_recompute_caps(c)
		}
		return
	}
	if t.overlay != .NONE {
		t.overlay_hp -= dmg
		t.hit_t0 = f32(rl.GetTime())
		colony_add_float(c, t.hex, .DAMAGE, dmg)
		if t.overlay_hp <= 0 {
			colony_notify(c, "Wilds tore up your %s!", improvement_name(t.overlay))
			t.overlay = .NONE
			t.overlay_hp = 0
		}
	}
}

// Wilds that ended their move on a defended tile queue that tile for battle;
// only wilds on an *unguarded* improved tile damage it.
colony_resolve_wild_actions :: proc(c: ^Colony) {
	clear(&c.pending_tiles)
	for i in 0..<len(c.roster) {
		m := &c.roster[i]
		if !m.wild {
			continue
		}
		if monsters_on_tile(c, m.pos, false) > 0 {
			already := false
			for h in c.pending_tiles {
				if hex_equal(h, m.pos) {
					already = true
					break
				}
			}
			if !already {
				append(&c.pending_tiles, m.pos)
			}
			continue
		}
		if t := tile_at(c, m.pos); t != nil && (t.improvement != .NONE || t.overlay != .NONE) {
			damage_improvement(c, t, wild_improvement_damage(m))
		}
	}
}

// Turns a defeated-in-spirit wild into one of yours (used on capture).
colony_capture :: proc(c: ^Colony, wild_id: int) -> bool {
	i := monster_by_id(c, wild_id)
	if i < 0 || !c.roster[i].wild {
		return false
	}
	m := &c.roster[i]
	m.wild = false
	m.creature.player = true
	creature_free_piles(&m.creature)
	m.food = monster_satiety_max(m)
	m.creature.energy = m.creature.energy_max
	creature_recompute_stats(&m.creature)
	return true
}

// ----------------------------------------------------------------------------
// Spawning the player's first monster
// ----------------------------------------------------------------------------

monster_by_id :: proc(c: ^Colony, id: int) -> int {
	for m, i in c.roster {
		if m.id == id {
			return i
		}
	}
	return -1
}

remove_monster_at :: proc(c: ^Colony, i: int, to_graveyard: bool) {
	if to_graveyard {
		append(&c.graveyard, c.roster[i])
	} else {
		creature_free_all(&c.roster[i].creature)
	}
	unordered_remove(&c.roster, i)
}

wild_monsters :: proc(c: ^Colony) -> int {
	n := 0
	for m in c.roster {
		if m.wild {
			n += 1
		}
	}
	return n
}

// ----------------------------------------------------------------------------
// Phase 25 — boss packs
//
// A Boss Room grows a unique boss plus a retinue of cronies. They move as a
// unit of six and are re-challengeable, so relics can be farmed.
// ----------------------------------------------------------------------------

BOSS_SPECIES := [?]Species_Id{.Boss_Leviathan, .Boss_Infernal, .Boss_Titan, .Boss_Sovereign}
BOSS_PACK_SIZE     :: 6
BOSS_LEVEL_BONUS   :: 5
BOSS_RESPAWN_TURNS :: 12
BOSS_SPAWN_RANGE   :: 14

boss_cronies :: proc(boss: Species_Id) -> [BOSS_PACK_SIZE - 1]Species_Id {
	#partial switch boss {
	case .Boss_Leviathan: return {.Krakling, .Bubblet, .Bogfang, .Frostmoss, .Rimescale}
	case .Boss_Infernal:  return {.Magmite, .Cindermaw, .Emberbloom, .Pyrelord, .Cinderwing}
	case .Boss_Titan:     return {.Stonepaw, .Mosshide, .Swampbeast, .Gloomling, .Venomtail}
	case .Boss_Sovereign: return {.Sparkit, .Galebeast, .Wispling, .Blizzard, .Cave_Bat}
	case:                 return {.Cave_Bat, .Cave_Bat, .Cave_Bat, .Cave_Bat, .Cave_Bat}
	}
	return {.Cave_Bat, .Cave_Bat, .Cave_Bat, .Cave_Bat, .Cave_Bat}
}

colony_spawn_boss_pack :: proc(c: ^Colony, hex: Hex) {
	boss := BOSS_SPECIES[rng_below(&c.rng, len(BOSS_SPECIES))]
	lvl := spawn_level_for(c, hex) + BOSS_LEVEL_BONUS
	pack := c.next_pack_id
	c.next_pack_id += 1
	spawn_wild_at(c, hex, boss, lvl, .BOSS, pack)
	cronies := boss_cronies(boss)
	for i in 0..<BOSS_PACK_SIZE - 1 {
		spawn_wild_at(c, hex, cronies[i], max(lvl - 3, 1), .CRONY, pack)
	}
	colony_notify(c, "A %s and its retinue stir in a Boss Room %s.", SPECIES[boss].name, compass_dir(nearest_player_hex(c, hex), hex))
}

// Boss Rooms grow a fresh pack once the player is near, after a cooldown. The
// timer lives in Tile.stored (Boss Rooms never hold production).
colony_spawn_boss_packs :: proc(c: ^Colony) {
	for i in 0..<len(c.tiles) {
		t := c.tiles[i]
		if t.terrain != .BOSS_ROOM || !t.revealed {
			continue
		}
		occupied := false
		for m in c.roster {
			if m.wild && hex_equal(m.pos, t.hex) {
				occupied = true
				break
			}
		}
		if occupied {
			continue
		}
		if t.stored > 0 {
			t.stored -= 1
			continue
		}
		if nearest_player_distance(c, t.hex) > BOSS_SPAWN_RANGE {
			continue
		}
		if wild_monsters(c) >= MAX_WILDS + BOSS_PACK_SIZE {
			continue
		}
		colony_spawn_boss_pack(c, t.hex)
		t.stored = BOSS_RESPAWN_TURNS
	}
}

// A boss pack moves as one: the boss picks the step toward your nearest monster
// and the whole retinue follows, so they stay a unit of six.
colony_roam_boss_packs :: proc(c: ^Colony) {
	processed := make(map[int]bool, 0)
	defer delete(processed)
	for i in 0..<len(c.roster) {
		m := &c.roster[i]
		if !m.wild || m.role != .BOSS || m.pack == 0 || processed[m.pack] {
			continue
		}
		processed[m.pack] = true
		target := nearest_player_hex(c, m.pos)
		if hex_equal(m.pos, target) {
			continue
		}
		best := m.pos
		best_d := hex_distance(m.pos, target)
		for n in hex_neighbors(m.pos) {
			if !tile_passable(c, m, n) {
				continue
			}
			if d := hex_distance(n, target); d < best_d {
				best_d = d
				best = n
			}
		}
		if hex_equal(best, m.pos) {
			// Blocked: the pack batters a fortification in the way.
			for n in hex_neighbors(m.pos) {
				t := tile_at(c, n)
				if t != nil && improvement_blocks_wilds(t) {
					damage_improvement(c, t, wild_improvement_damage(m))
					break
				}
			}
			continue
		}
		for j in 0..<len(c.roster) {
			mj := &c.roster[j]
			if mj.wild && mj.pack == m.pack && mj.creature.hp > 0 && tile_passable(c, mj, best) {
				mj.pos = best
			}
		}
	}
}
