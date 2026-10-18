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
	if len(entries) == 0 {
		return .Emberling
	}
	return entries[len(entries) - 1].species
}

// ----------------------------------------------------------------------------
// WILD SPAWNS
//
// One table per terrain. Entries are ordered by ascending cutoff and the last
// cutoff must be 1.0, so `spawn_pick` can be a single roll and a linear scan.
// Common species sit low, rare species sit at the top of the range.
// ----------------------------------------------------------------------------

SPAWN_CAVE := [?]Spawn_Entry {
	{0.35, .Grubling},
	{0.60, .Vesperling},
	{0.85, .Rockmite},
	{1.0, .Dustwing},
}
SPAWN_GROVE := [?]Spawn_Entry {
	{0.30, .Thornkit},
	{0.55, .Mossling},
	{0.85, .Bloomcap},
	{1.0, .Barkhound},
}
SPAWN_WATER := [?]Spawn_Entry {
	{0.30, .Bubblet},
	{0.65, .Ripjaw},
	{0.90, .Tidecaller},
	{1.0, .Abyssal_Fry},
}
SPAWN_DUNGEON := [?]Spawn_Entry {
	{0.40, .Gloomling},
	{0.75, .Crypt_Rat},
	{1.0, .Wispling},
}
SPAWN_MUSHROOM := [?]Spawn_Entry {
	{0.55, .Sporeling},
	{1.0, .Capmaw},
}
SPAWN_RUINS := [?]Spawn_Entry {
	{0.40, .Sentinel},
	{0.75, .Relic_Hound},
	{1.0, .Hexling},
}
SPAWN_TUNDRA := [?]Spawn_Entry {
	{0.35, .Snowpup},
	{0.70, .Glacierling},
	{1.0, .Frostmaw},
}
SPAWN_JUNGLE := [?]Spawn_Entry {
	{0.35, .Vinecat},
	{0.70, .Pouncer},
	{1.0, .Venomtail},
}
SPAWN_LAVA := [?]Spawn_Entry {
	{0.40, .Magmite},
	{0.75, .Cinderwing},
	{1.0, .Slagbeast},
}
SPAWN_DESERT := [?]Spawn_Entry {
	{0.45, .Sandfang},
	{1.0, .Sparkit},
}
SPAWN_QUICKSAND := [?]Spawn_Entry {
	{0.35, .Sandfang},
	{0.70, .Rockmite},
	{1.0, .Relic_Hound},
}
SPAWN_CRYSTAL_COVE := [?]Spawn_Entry {
	{0.50, .Hexling},
	{1.0, .Crystalfin},
}

spawn_species_for :: proc(t: Terrain, rng: ^Rng) -> Species_Id {
	r := rng_f32(rng)
	switch t {
	case .CAVE:         return spawn_pick(r, SPAWN_CAVE[:])
	case .GROVE:        return spawn_pick(r, SPAWN_GROVE[:])
	case .WATER:        return spawn_pick(r, SPAWN_WATER[:])
	case .DUNGEON:      return spawn_pick(r, SPAWN_DUNGEON[:])
	case .MUSHROOM:     return spawn_pick(r, SPAWN_MUSHROOM[:])
	case .RUINS:        return spawn_pick(r, SPAWN_RUINS[:])
	case .TUNDRA:       return spawn_pick(r, SPAWN_TUNDRA[:])
	case .JUNGLE:       return spawn_pick(r, SPAWN_JUNGLE[:])
	case .LAVA:         return spawn_pick(r, SPAWN_LAVA[:])
	case .DESERT:       return spawn_pick(r, SPAWN_DESERT[:])
	case .QUICKSAND:    return spawn_pick(r, SPAWN_QUICKSAND[:])
	case .CRYSTAL_COVE: return spawn_pick(r, SPAWN_CRYSTAL_COVE[:])
	case .TRADING_POST, .BOSS_ROOM, .ARENA:
		return .Grubling // no ambient spawns here; callers spawn their own
	}
	return .Grubling
}

// Threats keep pace with the run: wilds and raiders gain levels over time, so
// an over-levelled colony never trivialises the wilds near the entrance. This
// is the single knob that makes the world get meaner the longer you survive.
// How much tougher the world has become. **Heat is the driver**: it is your
// footprint (improvements and monster levels), so a loud colony draws monsters
// that have grown to match, while a quiet one stays easy. Turn count does not
// feed it — camping does not make the underground harder.
wild_threat_level :: proc(c: ^Colony) -> int {
	return c.heat / HEAT_LEVEL_PER
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
	// Weaker near the entrance and tougher the further out you are, but the real
	// driver is **heat**: the attention your colony has drawn. Build big and the
	// underground grows to match; stay small and it stays quiet. Wilds never
	// fall far behind your best monster, so there is always a fight worth having.
	dist := hex_distance(c.start_hex, hex)
	by_place := 1 + c.floor / 2 + dist / 4 + wild_threat_level(c)
	by_player := player_top_level(c) * 2 / 3
	return max(by_place, by_player) + rng_below(&c.rng, 2)
}

// The Arena sends a fresh, strong team onto its tile when challenged.
// --- Arena tower (Phase 53) ---
//
// The Arena is a ladder of curated teams. Each win takes you a floor higher;
// the teams get bigger, better and higher-levelled, and the purse grows. Losing
// drops you back to floor 1, but your best floor is recorded for good — the
// high score a bred and hand-built team is trying to beat.

// Species each band of floors fields: starter basics, then their mid forms, then
// their finals and the strong wilds, and finally the bosses themselves.
ARENA_TIER_1 := [?]Species_Id{.Grubling, .Vesperling, .Rockmite, .Dustwing, .Thornkit, .Mossling, .Bubblet, .Ripjaw, .Snowpup, .Vinecat, .Magmite, .Sparkit}
ARENA_TIER_2 := [?]Species_Id{.Cinderscale, .Ripfin, .Thornbud, .Bloomcap, .Barkhound, .Tidecaller, .Abyssal_Fry, .Hexling, .Frostmaw, .Glacierling, .Pouncer, .Venomtail, .Cinderwing, .Slagbeast, .Sandfang, .Crystalfin, .Capmaw, .Sentinel, .Relic_Hound, .Wispling, .Crypt_Rat, .Gloomling}
ARENA_TIER_3 := [?]Species_Id{.Magmalisk, .Tidewyrm, .Blightbloom, .Rotshell, .Nightwing, .Thornmaw, .Bubblord, .Frostfang, .Magmaw, .Sporelord, .Voltail}
ARENA_TIER_4 := [?]Species_Id{.Deep_One, .Boss_Leviathan, .Boss_Infernal, .Boss_Titan, .Boss_Sovereign}

// The average level of the monsters you brought to this Arena tile. The tower is
// built to beat *you*, so this is what sets the floor's difficulty — breed and
// deck-build a strong team and the tower answers it.
arena_party_level :: proc(c: ^Colony, hex: Hex) -> int {
	sum := 0
	n := 0
	for m in c.roster {
		if m.wild || m.creature.hp <= 0 || !hex_equal(m.pos, hex) {
			continue
		}
		sum += m.creature.level
		n += 1
	}
	if n == 0 {
		return player_top_level(c)
	}
	return sum / n
}

arena_species_for :: proc(floor: int, rng: ^Rng) -> Species_Id {
	pool := ARENA_TIER_1[:]
	if floor >= 50 {
		pool = ARENA_TIER_4[:]
	} else if floor >= 25 {
		pool = ARENA_TIER_3[:]
	} else if floor >= 10 {
		pool = ARENA_TIER_2[:]
	}
	return pool[rng_below(rng, len(pool))]
}

arena_entry_cost :: proc(c: ^Colony) -> int {
	return ARENA_ENTRY_COST + max(c.arena_floor, 1) * ARENA_ENTRY_PER_FLOOR
}

arena_purse :: proc(c: ^Colony) -> int {
	return ARENA_CRYSTAL_REWARD + max(c.arena_floor, 1) * ARENA_PURSE_PER_FLOOR
}

colony_spawn_arena_team :: proc(c: ^Colony, hex: Hex) {
	floor := max(c.arena_floor, 1)
	// At least the average level you brought, and it climbs with the floor.
	lvl := max(ARENA_BASE_LEVEL + floor * ARENA_LEVEL_PER_FLOOR, arena_party_level(c, hex) + floor / 2)
	n := min(ARENA_TEAM_BASE + floor / ARENA_TEAM_PER_FLOOR, ARENA_TEAM_SIZE)
	for _ in 0..<n {
		sp := arena_species_for(floor, &c.rng)
		spawn_wild_at(c, hex, sp, lvl)
	}
}

// Wilds grow up in the world, too: one spawned at or past its evolve level may
// show up as its evolved form instead (and keeps climbing while the level
// allows), so the late-game roster includes the evolved wilds. The odds rise
// the further past the evolve level the spawn is.
WILD_EVOLVE_CHANCE :: f32(0.5)

wild_mature_species :: proc(id: Species_Id, level: int, rng: ^Rng) -> Species_Id {
	cur := id
	for _ in 0..<2 {
		sp := SPECIES[cur]
		if sp.evolve_level <= 0 || level < sp.evolve_level {
			break
		}
		chance := clamp(WILD_EVOLVE_CHANCE + 0.1 * f32(level - sp.evolve_level), 0.0, 1.0)
		if rng_f32(rng) >= chance {
			break
		}
		cur = sp.evolves_to
	}
	return cur
}

spawn_wild_at :: proc(c: ^Colony, hex: Hex, species_in: Species_Id, level: int, role: Wild_Role = .WILD, pack: int = 0) {
	// Spawns past an evolve level have a chance to arrive already evolved.
	species := wild_mature_species(species_in, level, &c.rng)
	m := Monster{
		id       = c.next_id,
		creature = creature_make(species, level, SPECIES[species].name, &c.rng),
		pos      = hex,
		wild     = true,
		role     = role,
		pack     = pack,
		home     = hex,
		home_set = species_territorial(species),
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
			spec := clamp(0.15 + f32(wild_threat_level(c)) * 0.03, 0, 0.5)
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

// ----------------------------------------------------------------------------
// ECOLOGY
//
// Wilds aren't static scenery: they toughen over time, hunt each other, leave
// carrion, and scavengers drift toward the remains. All chance-driven per turn.
// ----------------------------------------------------------------------------

WILD_GROW_CHANCE :: f32(0.045)
PREDATION_CHANCE :: f32(0.05)
PREDATION_LEVEL_GAP :: 2
CARRION_LIFE     :: 6
CARRION_ATTRACT  :: 7
TERRITORY_RADIUS :: 4

// Wilds slowly gain levels so an ignored corner of the map isn't free forever.
// Capped a little above your best monster so it never runs away from you.
colony_grow_wilds :: proc(c: ^Colony) {
	cap := player_top_level(c) + 4
	bump := WILD_GROW_CHANCE + f32(wild_threat_level(c)) * 0.012
	for i in 0..<len(c.roster) {
		m := &c.roster[i]
		if !m.wild || m.role == .BOSS || m.role == .CRONY {
			continue
		}
		if m.creature.level >= cap || rng_f32(&c.rng) >= bump {
			continue
		}
		m.creature.level += 1
		creature_recompute_stats(&m.creature)
		m.creature.hp = m.creature.max_hp
		if t := tile_at(c, m.pos); t != nil && t.revealed {
			colony_notify(c, "%s grows tougher.", m.creature.name)
			colony_add_float(c, m.pos, .GROW, 1)
		}
	}
}

// A wild that spots a weak neighbour — lower level, or badly hurt — moves in for
// the kill. The fight is a *real* headless battle; the loser is dragged down.
colony_predation :: proc(c: ^Colony) {
	// Plan the duels first (removals reshuffle the roster), then resolve them.
	pred_ids := make([dynamic]int, 0)
	prey_ids := make([dynamic]int, 0)
	claimed := make(map[int]bool)
	defer {
		delete(pred_ids)
		delete(prey_ids)
		delete(claimed)
	}

	for i in 0..<len(c.roster) {
		m := &c.roster[i]
		if !m.wild || m.role == .BOSS || m.role == .CRONY {
			continue
		}
		if rng_f32(&c.rng) >= PREDATION_CHANCE {
			continue
		}
		// Pick the weakest adjacent wild that looks like easy prey.
		best := -1
		best_hp := f32(2)
		for j in 0..<len(c.roster) {
			if j == i {
				continue
			}
			o := &c.roster[j]
			if !o.wild || claimed[o.id] {
				continue
			}
			if hex_distance(o.pos, m.pos) > 1 {
				continue
			}
			weak := o.creature.level + PREDATION_LEVEL_GAP <= m.creature.level ||
				f32(o.creature.hp) < 0.5 * f32(o.creature.max_hp)
			if !weak {
				continue
			}
			frac := f32(o.creature.hp) / f32(max(o.creature.max_hp, 1))
			if best < 0 || frac < best_hp {
				best, best_hp = j, frac
			}
		}
		if best < 0 {
			continue
		}
		append(&pred_ids, m.id)
		append(&prey_ids, c.roster[best].id)
		claimed[c.roster[best].id] = true
	}

	for k in 0..<len(pred_ids) {
		pi := monster_by_id(c, pred_ids[k])
		qi := monster_by_id(c, prey_ids[k])
		if pi < 0 || qi < 0 {
			continue // one of them already died in an earlier duel
		}
		pred := &c.roster[pi]
		prey := &c.roster[qi]
		hex := prey.pos
		pred_name := pred.creature.name
		prey_name := prey.creature.name

		won, rounds := resolve_duel(c, pred, prey)

		loser_id := won ? prey.id : pred.id
		winner := won ? pred : prey
		// The winner recovers a little from the kill.
		winner.creature.hp = min(winner.creature.max_hp, winner.creature.hp + winner.creature.max_hp / 4)

		if t := tile_at(c, hex); t != nil {
			t.scuffle = 3
			t.carrion = CARRION_LIFE
			if t.revealed {
				if won {
					colony_notify(c, "%s drags down %s (%d rounds).", pred_name, prey_name, rounds)
				} else {
					colony_notify(c, "%s fights off %s (%d rounds).", prey_name, pred_name, rounds)
				}
				colony_add_float(c, hex, .DAMAGE, 1)
			} else {
				dir := compass_dir(nearest_player_hex(c, hex), hex)
				colony_notify(c, "Snarling in the dark %s.", dir == "here" ? "close by" : fmt.ctprintf("to the %s", dir))
			}
		}
		if idx := monster_by_id(c, loser_id); idx >= 0 {
			c.roster[idx].creature.hp = 0
			remove_monster_at(c, idx, false)
		}
	}
}

// Scavengers: wilds within reach step toward carrion, and one standing on it
// eats and heals. Carrion also ages out.
colony_carrion :: proc(c: ^Colony) {
	carrion := make([dynamic]Hex, 0)
	defer delete(carrion)
	for i in 0..<len(c.tiles) {
		if c.tiles[i].carrion > 0 {
			append(&carrion, c.tiles[i].hex)
		}
	}
	if len(carrion) == 0 {
		return
	}
	for i in 0..<len(c.roster) {
		m := &c.roster[i]
		if !m.wild || m.role != .WILD {
			continue
		}
		if t := tile_at(c, m.pos); t != nil && t.carrion > 0 {
			t.carrion = 0
			m.creature.hp = min(m.creature.max_hp, m.creature.hp + m.creature.max_hp / 4)
			if t.revealed {
				colony_notify(c, "%s scavenges the remains.", m.creature.name)
				colony_add_float(c, m.pos, .HEAL, 1)
			}
			continue
		}
		best := CARRION_ATTRACT + 1
		target := m.pos
		for ch in carrion {
			if d := hex_distance(ch, m.pos); d < best {
				best = d
				target = ch
			}
		}
		if best <= CARRION_ATTRACT {
			step_hunt(c, m, target)
		}
	}
	// Age the remains.
	for i in 0..<len(c.tiles) {
		if c.tiles[i].carrion > 0 {
			c.tiles[i].carrion -= 1
		}
	}
}

// Too many wilds on one tile: they split into two sides and brawl. The whole
// tile is one real battle (not a dozen duels), so a pile-up stays cheap.
colony_crowd_fights :: proc(c: ^Colony) {
	// One fight per overcrowded tile per turn.
	tiles := make([dynamic]Hex, 0)
	seen := make(map[u64]bool)
	defer {
		delete(tiles)
		delete(seen)
	}
	for m in c.roster {
		if !m.wild {
			continue
		}
		if monsters_on_tile(c, m.pos, true) <= CROWD_LIMIT {
			continue
		}
		k := hex_key(m.pos)
		if seen[k] {
			continue
		}
		seen[k] = true
		append(&tiles, m.pos)
	}

	for hex in tiles {
		if rng_f32(&c.rng) >= CROWD_FIGHT_CHANCE {
			continue
		}
		// Same readiness rule as picking a fight with you.
		ready := false
		for &m in c.roster {
			if m.wild && hex_equal(m.pos, hex) && wild_ready_to_fight(c, &m) {
				ready = true
				break
			}
		}
		if !ready {
			continue
		}
		ids := make([dynamic]int, 0)
		for m in c.roster {
			if m.wild && hex_equal(m.pos, hex) {
				append(&ids, m.id)
			}
		}
		if len(ids) < 2 {
			delete(ids)
			continue
		}

		// Split the brawlers into two sides.
		a_side := make([dynamic]^Creature, 0)
		b_side := make([dynamic]^Creature, 0)
		for id, k in ids {
			idx := monster_by_id(c, id)
			if idx < 0 {
				continue
			}
			if k % 2 == 0 {
				append(&a_side, &c.roster[idx].creature)
			} else {
				append(&b_side, &c.roster[idx].creature)
			}
		}

		_, rounds := resolve_team(c, a_side[:], b_side[:])

		// Anyone left at 0 HP fell in the brawl.
		fell := 0
		for id in ids {
			idx := monster_by_id(c, id)
			if idx >= 0 && c.roster[idx].creature.hp <= 0 {
				remove_monster_at(c, idx, false)
				fell += 1
			}
		}

		t := tile_at(c, hex)
		revealed := t != nil && t.revealed
		if t != nil {
			t.scuffle = 3
			if fell > 0 {
				t.carrion = CARRION_LIFE
			}
		}
		dir := compass_dir(nearest_player_hex(c, hex), hex)
		loc := dir == "here" ? cstring("right here") : fmt.ctprintf("to the %s", dir)
		if revealed {
			if fell > 0 {
				colony_notify(c, "A brawl %s: %d wild%s fell (%d rounds).", loc, fell, fell == 1 ? "" : "s", rounds)
			} else {
				colony_notify(c, "A brawl breaks out %s — nobody falls.", loc)
			}
		} else {
			colony_notify(c, "Snarling in the fog %s.", loc)
		}

		delete(ids)
		delete(a_side)
		delete(b_side)
	}
}

// A wild won't pick a fight it can't afford. Stepping onto one of your monsters
// (or brawling over a crowded tile) starts a battle, so a drained wild holds off
// and a charged one gets bolder — fights are worth having on both sides.
WILD_FIGHT_ENERGY_MIN :: f32(0.40) // fraction of its bank it wants before engaging

wild_ready_to_fight :: proc(c: ^Colony, m: ^Monster) -> bool {
	frac := m.creature.energy / max(m.creature.energy_max, 0.001)
	if frac < WILD_FIGHT_ENERGY_MIN {
		return false
	}
	return rng_f32(&c.rng) < frac
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
		// Plain wilds always wander (no staying put), but a wild that has strayed
		// far from its lair heads back rather than diffusing across the map.
		if m.home_set && hex_distance(m.pos, m.home) > TERRITORY_RADIUS && rng_f32(&c.rng) < 0.6 {
			step_hunt(c, m, m.home)
			continue
		}
		ns := hex_neighbors(m.pos)
		start := rng_below(&c.rng, 6)
		for k in 0..<6 {
			n := ns[(start + k) % 6]
			t := tile_at(c, n)
			if t == nil {
				continue
			}
			if tile_passable(c, m, n) {
				// Walking onto your monster starts a fight; only a charged wild
				// will commit to that.
				if monsters_on_tile(c, n, false) > 0 && !wild_ready_to_fight(c, m) {
					continue
				}
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

// 0..1 proximity of the nearest wild to any of your monsters (drives the
// heartbeat). 0 = nothing within range.
nearest_threat :: proc(c: ^Colony) -> f32 {
	best := 1 << 30
	for m in c.roster {
		if m.wild {
			continue
		}
		for o in c.roster {
			if !o.wild {
				continue
			}
			d := hex_distance(m.pos, o.pos)
			if d < best {
				best = d
			}
		}
	}
	if best == 1 << 30 {
		return 0
	}
	return clamp(1.0 - f32(best) / 10.0, 0, 1)
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

damage_improvement :: proc(c: ^Colony, t: ^Tile, dmg: int, cause: cstring = "Wilds") {
	// The building takes the hit first; once it's rubble the overlay is next.
	if t.improvement != .NONE {
		t.improvement_hp -= dmg
		t.hit_t0 = f32(rl.GetTime())
		colony_add_float(c, t.hex, .DAMAGE, dmg)
		if t.improvement_hp <= 0 {
			// Destroyed: contents are lost. Den/Nursery occupants are pushed
			// back onto the map (or lost if there is nowhere to stand).
			colony_notify(c, "%s destroyed your %s!", cause, improvement_name(t.improvement))
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
			colony_notify(c, "%s wrecked your %s!", cause, improvement_name(t.overlay))
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

BOSS_SPECIES := [?]Species_Id{.Boss_Leviathan, .Boss_Infernal, .Boss_Titan, .Boss_Sovereign, .Deep_One}
BOSS_PACK_SIZE     :: 6
BOSS_LEVEL_BONUS   :: 5
BOSS_RESPAWN_TURNS :: 30
BOSS_SPAWN_RANGE   :: 14

boss_cronies :: proc(boss: Species_Id) -> [BOSS_PACK_SIZE - 1]Species_Id {
	// Each boss keeps a retinue themed to its lair, drawn from the wild roster.
	#partial switch boss {
	case .Boss_Leviathan: return {.Abyssal_Fry, .Ripjaw, .Bubblet, .Tidecaller, .Glacierling}
	case .Boss_Infernal:  return {.Magmite, .Cinderwing, .Slagbeast, .Magmaw, .Cinderwing}
	case .Boss_Titan:     return {.Rockmite, .Relic_Hound, .Sandfang, .Sentinel, .Slagbeast}
	case .Boss_Sovereign: return {.Sparkit, .Hexling, .Wispling, .Voltail, .Vesperling}
	case:                 return {.Grubling, .Vesperling, .Rockmite, .Dustwing, .Gloomling}
	}
	return {.Grubling, .Vesperling, .Rockmite, .Dustwing, .Gloomling}
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
