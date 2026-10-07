package main

import rl "vendor:raylib"

// ============================================================================
// COLONY LAYER
//
// A regular hex grid with terrain, a persistent roster of monsters standing on
// tiles, resources, and a turn loop with movement energy and range-gated food
// logistics. See DESIGN.md for the full target.
//
// Economy notes:
//   - Farms and Mines only produce if one of your monsters is stationed there.
//   - Farms feed your monsters within 4 tiles; their surplus is delivered to a
//     Granary within 4 tiles (overflow is wasted).
//   - Granaries store food and feed your monsters within 4 tiles.
//   - Mines deliver gold to a Treasury within 4 tiles (overflow is wasted).
//   - Treasury gold counts toward your spendable gold. A destroyed granary or
//     treasury loses its contents (handled in Phase 3).
// ============================================================================

Terrain :: enum { CAVE, WATER, DUNGEON, GROVE, TRADING_POST, BOSS_ROOM }
Improvement :: enum { NONE, FARM, MINE, BRIDGE, GRANARY, TREASURY }

MAX_MONSTERS_PER_TILE :: 6
REFILL_FRAC           :: f32(0.5) // of max satiation gained per fed turn
STARVE_FRAC           :: f32(0.3) // of max satiation lost per starving turn
STORAGE_CAP           :: 100
FEED_RADIUS           :: 4
DELIVER_RADIUS        :: 4

terrain_name :: proc(t: Terrain) -> cstring {
	switch t {
	case .CAVE:         return "Cave"
	case .WATER:        return "Water"
	case .DUNGEON:      return "Dungeon"
	case .GROVE:        return "Grove"
	case .TRADING_POST: return "Trading Post"
	case .BOSS_ROOM:    return "Boss Room"
	}
	return "?"
}

terrain_color :: proc(t: Terrain) -> rl.Color {
	switch t {
	case .CAVE:         return rl.Color{66, 60, 52, 255}
	case .WATER:        return rl.Color{40, 88, 148, 255}
	case .DUNGEON:      return rl.Color{74, 56, 88, 255}
	case .GROVE:        return rl.Color{58, 108, 60, 255}
	case .TRADING_POST: return rl.Color{150, 120, 54, 255}
	case .BOSS_ROOM:    return rl.Color{132, 42, 52, 255}
	}
	return rl.Color{80, 80, 80, 255}
}

improvement_name :: proc(im: Improvement) -> cstring {
	switch im {
	case .NONE:      return ""
	case .FARM:      return "Farm"
	case .MINE:      return "Mine"
	case .BRIDGE:    return "Bridge"
	case .GRANARY:   return "Granary"
	case .TREASURY:  return "Treasury"
	}
	return ""
}

improvement_label :: proc(im: Improvement) -> cstring {
	switch im {
	case .NONE:      return ""
	case .FARM:      return "F"
	case .MINE:      return "M"
	case .BRIDGE:    return "="
	case .GRANARY:   return "G"
	case .TREASURY:  return "T"
	}
	return ""
}

IMPROVEMENT_HP :: 50

improvement_cost :: proc(im: Improvement) -> int {
	switch im {
	case .NONE:     return 0
	case .FARM:     return 30
	case .MINE:     return 30
	case .BRIDGE:   return 25
	case .GRANARY:  return 25
	case .TREASURY: return 25
	}
	return 0
}

improvement_valid_on :: proc(im: Improvement, t: Terrain) -> bool {
	switch im {
	case .NONE:     return false
	case .FARM:     return t == .GROVE
	case .MINE:     return t == .CAVE
	case .BRIDGE:   return t == .WATER
	case .GRANARY:  return t == .CAVE || t == .GROVE
	case .TREASURY: return t == .CAVE
	}
	return false
}

improvement_effect :: proc(im: Improvement) -> cstring {
	switch im {
	case .NONE:     return ""
	case .FARM:     return "staffed: feeds within 4, surplus to granary"
	case .MINE:     return "staffed: gold to treasury within 4"
	case .BRIDGE:   return "land monsters can cross water"
	case .GRANARY:  return "stores food, feeds within 4"
	case .TREASURY: return "stores gold"
	}
	return ""
}

Tile :: struct {
	hex:            Hex,
	terrain:        Terrain,
	revealed:       bool,
	improvement:    Improvement,
	improvement_hp: int,
	stored:         int, // food (Granary) or gold (Treasury)
}

Monster :: struct {
	creature: Creature,
	pos:      Hex,
	wild:     bool,
	energy:   f32, // movement energy for the current turn
	food:     f32, // satiation bar 0..100
	genetics: [5]int,
}

Colony :: struct {
	tiles:     [dynamic]Tile,
	roster:    [dynamic]Monster,
	graveyard: [dynamic]Monster,
	width:     int,
	height:    int,
	gold:      int, // the player's base (spendable) gold
	crystals:  int,
	gold_cap:  int,
	food_cap:  int,
	turn:      int,
	floor:     int,
	seed:      u64,
	rng:       Rng,
	start_hex: Hex,
}

// ----------------------------------------------------------------------------
// Grid helpers
// ----------------------------------------------------------------------------

hex_from_offset :: proc(col, row: int) -> Hex {
	q := col
	r := row - (col - (col & 1)) / 2
	return Hex{q = q, r = r}
}

tile_at :: proc(c: ^Colony, hex: Hex) -> ^Tile {
	for i in 0..<len(c.tiles) {
		if hex_equal(c.tiles[i].hex, hex) {
			return &c.tiles[i]
		}
	}
	return nil
}

tile_terrain :: proc(c: ^Colony, hex: Hex) -> Terrain {
	if t := tile_at(c, hex); t != nil {
		return t.terrain
	}
	return .CAVE
}

colony_reveal_around :: proc(c: ^Colony, hex: Hex) {
	if t := tile_at(c, hex); t != nil {
		t.revealed = true
	}
	for n in hex_neighbors(hex) {
		if t := tile_at(c, n); t != nil {
			t.revealed = true
		}
	}
}

nearest_improvement_within :: proc(c: ^Colony, from: Hex, radius: int, im: Improvement) -> int {
	best := -1
	best_d := 1 << 30
	for i in 0..<len(c.tiles) {
		if c.tiles[i].improvement != im {
			continue
		}
		d := hex_distance(from, c.tiles[i].hex)
		if d <= radius && d < best_d {
			best_d = d
			best = i
		}
	}
	return best
}

// ----------------------------------------------------------------------------
// Generation
// ----------------------------------------------------------------------------

colony_generate :: proc(seed: u64, width, height: int) -> Colony {
	c := Colony{
		width    = width,
		height   = height,
		seed     = seed,
		floor    = 1,
		gold     = 40,
		crystals = 0,
	}
	c.rng = rng_make(seed)
	c.tiles = make([dynamic]Tile, 0, width * height)
	c.roster = make([dynamic]Monster, 0)
	c.graveyard = make([dynamic]Monster, 0)

	for col in 0..<width {
		for row in 0..<height {
			hex := hex_from_offset(col, row)
			append(&c.tiles, Tile{hex = hex, terrain = pick_terrain(&c.rng)})
		}
	}

	c.start_hex = hex_from_offset(width / 2, 0)
	if t := tile_at(&c, c.start_hex); t != nil {
		t.terrain = .CAVE
	}

	boss_hex := hex_from_offset(width / 2, height - 1)
	if t := tile_at(&c, boss_hex); t != nil {
		t.terrain = .BOSS_ROOM
	}

	for _ in 0..<2 {
		t := &c.tiles[rng_below(&c.rng, len(c.tiles))]
		if t.terrain != .BOSS_ROOM && !hex_equal(t.hex, c.start_hex) {
			t.terrain = .TRADING_POST
		}
	}

	has_exit := false
	for n in hex_neighbors(c.start_hex) {
		if t := tile_at(&c, n); t != nil && t.terrain != .WATER {
			has_exit = true
			break
		}
	}
	if !has_exit {
		if t := tile_at(&c, hex_add(c.start_hex, HEX_DIRECTIONS[5])); t != nil {
			t.terrain = .CAVE
		}
	}

	colony_recompute_caps(&c)
	colony_reveal_around(&c, c.start_hex)
	return c
}

pick_terrain :: proc(rng: ^Rng) -> Terrain {
	r := rng_f32(rng)
	if r < 0.46 { return .CAVE }
	if r < 0.64 { return .WATER }
	if r < 0.79 { return .DUNGEON }
	return .GROVE
}

colony_free :: proc(c: ^Colony) {
	for i in 0..<len(c.roster) {
		creature_free_all(&c.roster[i].creature)
	}
	for i in 0..<len(c.graveyard) {
		creature_free_all(&c.graveyard[i].creature)
	}
	delete(c.roster)
	delete(c.graveyard)
	delete(c.tiles)
	c.roster = make([dynamic]Monster, 0)
	c.graveyard = make([dynamic]Monster, 0)
	c.tiles = make([dynamic]Tile, 0)
}

// ----------------------------------------------------------------------------
// Roster helpers
// ----------------------------------------------------------------------------

monsters_on_tile :: proc(c: ^Colony, hex: Hex, wild: bool) -> int {
	n := 0
	for m in c.roster {
		if m.wild == wild && hex_equal(m.pos, hex) {
			n += 1
		}
	}
	return n
}

first_player_monster_on :: proc(c: ^Colony, hex: Hex) -> int {
	for m, i in c.roster {
		if !m.wild && hex_equal(m.pos, hex) {
			return i
		}
	}
	return -1
}

monster_energy_max :: proc(m: ^Monster) -> f32 {
	return 4.0 + f32(m.creature.speed) * 0.35
}

// Per-turn consumption: the species' base_upkeep scaled by level.
monster_upkeep :: proc(m: ^Monster) -> int {
	base := f32(SPECIES[m.creature.species].base_upkeep)
	return max(1, int(base * level_scale(m.creature.level)))
}

// Satiation capacity is per-species base scaled by level.
monster_satiety_max :: proc(m: ^Monster) -> f32 {
	base := f32(SPECIES[m.creature.species].base_satiety)
	return base * level_scale(m.creature.level)
}

terrain_move_cost :: proc(t: Terrain) -> f32 {
	#partial switch t {
	case .DUNGEON, .BOSS_ROOM, .WATER: return 1.5
	case: return 1.0
	}
}

monster_move_cost :: proc(m: ^Monster, t: Terrain) -> f32 {
	speed := max(f32(m.creature.speed), 1.0)
	factor := clamp(10.0 / speed, 0.6, 1.6)
	return terrain_move_cost(t) * factor
}

tile_passable :: proc(c: ^Colony, m: ^Monster, hex: Hex) -> bool {
	t := tile_at(c, hex)
	if t == nil {
		return false
	}
	if t.terrain == .WATER {
		if t.improvement == .BRIDGE {
			return true
		}
		return creature_element(&m.creature) == .AQUA
	}
	return true
}

// 0 ok, 1 not adjacent, 2 blocked, 3 full, 4 not enough energy.
colony_move :: proc(c: ^Colony, monster_index: int, target: Hex) -> int {
	if monster_index < 0 || monster_index >= len(c.roster) {
		return 1
	}
	m := &c.roster[monster_index]
	if m.wild || hex_distance(m.pos, target) != 1 {
		return 1
	}
	if !tile_passable(c, m, target) {
		return 2
	}
	if monsters_on_tile(c, target, false) >= MAX_MONSTERS_PER_TILE {
		return 3
	}
	t := tile_at(c, target)
	cost := monster_move_cost(m, t.terrain)
	if m.energy < cost {
		return 4
	}
	m.energy -= cost
	m.pos = target
	colony_reveal_around(c, target)
	return 0
}

// ----------------------------------------------------------------------------
// Improvements
// ----------------------------------------------------------------------------

// 0 ok, 1 invalid terrain, 2 already improved, 3 not enough gold.
colony_build :: proc(c: ^Colony, hex: Hex, im: Improvement) -> int {
	t := tile_at(c, hex)
	if t == nil || !improvement_valid_on(im, t.terrain) {
		return 1
	}
	if t.improvement != .NONE {
		return 2
	}
	cost := improvement_cost(im)
	if !colony_spend_gold(c, cost) {
		return 3
	}
	t.improvement = im
	t.improvement_hp = IMPROVEMENT_HP
	t.stored = 0
	colony_recompute_caps(c)
	return 0
}

buildable_improvements :: proc(t: Terrain, out: []Improvement) -> int {
	n := 0
	for im in Improvement {
		if im != .NONE && improvement_valid_on(im, t) {
			if n < len(out) {
				out[n] = im
			}
			n += 1
		}
	}
	return n
}

// ----------------------------------------------------------------------------
// Gold (global; treasuries hold part of it and lose it if destroyed)
// ----------------------------------------------------------------------------

colony_total_gold :: proc(c: ^Colony) -> int {
	sum := c.gold
	for t in c.tiles {
		if t.improvement == .TREASURY {
			sum += t.stored
		}
	}
	return sum
}

colony_total_food :: proc(c: ^Colony) -> int {
	sum := 0
	for t in c.tiles {
		if t.improvement == .GRANARY {
			sum += t.stored
		}
	}
	return sum
}

colony_spend_gold :: proc(c: ^Colony, amount: int) -> bool {
	if amount <= 0 {
		return true
	}
	if colony_total_gold(c) < amount {
		return false
	}
	remaining := amount
	take := min(c.gold, remaining)
	c.gold -= take
	remaining -= take
	for i in 0..<len(c.tiles) {
		if remaining <= 0 {
			break
		}
		t := &c.tiles[i]
		if t.improvement != .TREASURY {
			continue
		}
		g := min(t.stored, remaining)
		t.stored -= g
		remaining -= g
	}
	return true
}

colony_recompute_caps :: proc(c: ^Colony) {
	gold_cap := 100
	food_cap := 0
	for t in c.tiles {
		#partial switch t.improvement {
		case .TREASURY: gold_cap += STORAGE_CAP
		case .GRANARY:  food_cap += STORAGE_CAP
		case:
		}
	}
	c.gold_cap = gold_cap
	c.food_cap = food_cap
}

granary_count :: proc(c: ^Colony) -> int {
	n := 0
	for t in c.tiles {
		if t.improvement == .GRANARY {
			n += 1
		}
	}
	return n
}

// ----------------------------------------------------------------------------
// Trading Post services
// ----------------------------------------------------------------------------

heal_cost :: proc(m: ^Monster) -> int {
	missing := m.creature.max_hp - m.creature.hp
	if missing <= 0 {
		return 0
	}
	return max(missing * 2, 5)
}

energy_cost :: proc(m: ^Monster) -> int {
	return 5
}

revive_cost :: proc(m: ^Monster) -> int {
	return 30 + m.creature.level * 5
}

// 0 ok, 1 no monster, 2 not enough gold.
colony_heal :: proc(c: ^Colony, index: int) -> int {
	if index < 0 || index >= len(c.roster) {
		return 1
	}
	m := &c.roster[index]
	cost := heal_cost(m)
	if cost <= 0 {
		return 1
	}
	if !colony_spend_gold(c, cost) {
		return 2
	}
	m.creature.hp = m.creature.max_hp
	return 0
}

colony_refill_energy :: proc(c: ^Colony, index: int) -> int {
	if index < 0 || index >= len(c.roster) {
		return 1
	}
	if !colony_spend_gold(c, energy_cost(&c.roster[index])) {
		return 2
	}
	c.roster[index].energy = monster_energy_max(&c.roster[index])
	return 0
}

// 0 ok, 1 bad index, 2 not enough gold, 3 start tile full.
colony_revive :: proc(c: ^Colony, grave_index: int) -> int {
	if grave_index < 0 || grave_index >= len(c.graveyard) {
		return 1
	}
	m := c.graveyard[grave_index]
	if !colony_spend_gold(c, revive_cost(&m)) {
		return 2
	}
	if monsters_on_tile(c, c.start_hex, false) >= MAX_MONSTERS_PER_TILE {
		return 3
	}

	m.creature.hp = m.creature.max_hp
	m.creature.block = 0
	m.creature.strength = 0
	m.creature.vulnerable = 0
	m.creature.defense_buff = 0
	creature_free_piles(&m.creature)
	m.food = monster_satiety_max(&m)
	m.pos = c.start_hex
	m.energy = monster_energy_max(&m)

	append(&c.roster, m)
	unordered_remove(&c.graveyard, grave_index)
	return 0
}

// ----------------------------------------------------------------------------
// Turn loop
// ----------------------------------------------------------------------------

nearest_farm_pool :: proc(c: ^Colony, from: Hex, radius: int, pools: []int) -> int {
	best := -1
	best_d := 1 << 30
	for i in 0..<len(c.tiles) {
		if c.tiles[i].improvement != .FARM || pools[i] <= 0 {
			continue
		}
		d := hex_distance(from, c.tiles[i].hex)
		if d <= radius && d < best_d {
			best_d = d
			best = i
		}
	}
	return best
}

colony_end_turn :: proc(c: ^Colony) {
	farm_pool := make([]int, len(c.tiles))
	defer delete(farm_pool)
	for i in 0..<len(c.tiles) {
		farm_pool[i] = 0
	}

	// 1. Mines: staffed mines deliver gold to a treasury within range.
	for t in c.tiles {
		if t.improvement != .MINE {
			continue
		}
		if monsters_on_tile(c, t.hex, false) == 0 {
			continue
		}
		gi := nearest_improvement_within(c, t.hex, DELIVER_RADIUS, .TREASURY)
		if gi >= 0 {
			g := &c.tiles[gi]
			g.stored = min(g.stored + 4, STORAGE_CAP)
		}
		// else wasted
	}

	// 2. Farms: staffed farms produce a local pool.
	for i in 0..<len(c.tiles) {
		t := &c.tiles[i]
		if t.improvement != .FARM {
			continue
		}
		if monsters_on_tile(c, t.hex, false) == 0 {
			continue
		}
		farm_pool[i] = 6
	}

	// 3. Farms deliver surplus to a granary within range (else wasted).
	for i in 0..<len(c.tiles) {
		if farm_pool[i] <= 0 {
			continue
		}
		gi := nearest_improvement_within(c, c.tiles[i].hex, DELIVER_RADIUS, .GRANARY)
		if gi >= 0 {
			g := &c.tiles[gi]
			move := min(farm_pool[i], STORAGE_CAP - g.stored)
			if move > 0 {
				g.stored += move
				farm_pool[i] -= move
			}
		}
	}

	// 4. Feed monsters (range-gated): eat from a granary or farm pool within range.
	for &m in c.roster {
		if m.wild {
			continue
		}
		need := monster_upkeep(&m)
		fed := false

		gi := nearest_improvement_within(c, m.pos, FEED_RADIUS, .GRANARY)
		if gi >= 0 && c.tiles[gi].stored >= need {
			c.tiles[gi].stored -= need
			fed = true
		}
		if !fed {
			fi := nearest_farm_pool(c, m.pos, FEED_RADIUS, farm_pool)
			if fi >= 0 && farm_pool[fi] >= need {
				farm_pool[fi] -= need
				fed = true
			}
		}

		smax := monster_satiety_max(&m)
		if fed {
			m.food = min(smax, m.food + smax * REFILL_FRAC)
			if m.food >= smax {
				m.creature.hp = min(m.creature.hp + max(m.creature.max_hp / 10, 1), m.creature.max_hp)
			}
		} else {
			m.food = max(0, m.food - smax * STARVE_FRAC)
			if m.food <= 0 {
				m.creature.hp -= max(m.creature.max_hp / 10, 1)
			}
		}
	}

	// 5. Deaths + energy refill.
	i := 0
	for i < len(c.roster) {
		m := &c.roster[i]
		if m.wild {
			i += 1
			continue
		}
		if m.creature.hp <= 0 {
			append(&c.graveyard, m^)
			unordered_remove(&c.roster, i)
			continue
		}
		m.energy = monster_energy_max(m)
		i += 1
	}

	c.turn += 1
}

// ----------------------------------------------------------------------------
// Spawning the player's first monster
// ----------------------------------------------------------------------------

colony_add_starter :: proc(c: ^Colony, species_idx: int) -> int {
	m := Monster{
		creature = creature_make(species_idx, 1, SPECIES[species_idx].name),
		pos      = c.start_hex,
	}
	m.energy = monster_energy_max(&m)
	m.food = monster_satiety_max(&m)
	append(&c.roster, m)
	return len(c.roster) - 1
}
