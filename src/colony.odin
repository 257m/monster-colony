package main

import rl "vendor:raylib"
import "core:fmt"
import "core:math"

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
BASE_GOLD_CAP         :: 100 // the stockpile's own cap; treasuries add storage beyond it
FEED_RADIUS           :: 4
DELIVER_RADIUS        :: 4
MAX_WILDS              :: 30
SIM_DISTANCE           :: 6    // spawn/despawn radius around your nearest monster
DESPAWN_DISTANCE       :: 8    // beyond this, wilds may wander off
DESPAWN_CHANCE         :: f32(0.25)
CROWD_LIMIT            :: 3    // per tile; more than this and they may fight
CROWD_FIGHT_CHANCE     :: f32(0.30)

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
	scuffle:        int, // turns a "fight happened here" marker lingers
}

Monster :: struct {
	id:       int,
	creature: Creature,
	pos:      Hex,
	wild:     bool,
	energy:   f32, // movement energy for the current turn
	food:     f32, // satiation bar 0..100
	xp:       int, // experience toward the next level
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
	capture_cards: int, // consumable capture cards (buy at a Trading Post)
	gold_cap:  int,
	food_cap:  int,
	turn:      int,
	floor:     int,
	seed:      u64,
	rng:       Rng,
	start_hex: Hex,
	next_id:   int,
	pending_tiles: [dynamic]Hex, // tiles where wilds and your monsters share a tile
	messages:  [dynamic]string, // recent world notifications
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
	c.pending_tiles = make([dynamic]Hex, 0)
	c.next_id = 1
	c.messages = make([dynamic]string, 0)

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
	delete(c.pending_tiles)
	for s in c.messages {
		delete(s)
	}
	delete(c.messages)
	c.roster = make([dynamic]Monster, 0)
	c.graveyard = make([dynamic]Monster, 0)
	c.tiles = make([dynamic]Tile, 0)
	c.pending_tiles = make([dynamic]Hex, 0)
	c.messages = make([dynamic]string, 0)
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

xp_to_next :: proc(level: int) -> int {
	return 40 + level * 30
}

// Grants XP and levels the monster up as thresholds are crossed.
monster_add_xp :: proc(m: ^Monster, amount: int) -> bool {
	m.xp += amount
	leveled := false
	for m.xp >= xp_to_next(m.creature.level) {
		m.xp -= xp_to_next(m.creature.level)
		creature_level_up(&m.creature)
		leveled = true
	}
	return leveled
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
	gold_cap := BASE_GOLD_CAP
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

// Deposits gold into a Treasury within range first, then the stockpile (which
// is capped at the *base* cap, not the total). Returns the amount actually kept.
colony_deposit_gold :: proc(c: ^Colony, from: Hex, amount: int) -> int {
	kept := 0
	remaining := amount
	if gi := nearest_improvement_within(c, from, DELIVER_RADIUS, .TREASURY); gi >= 0 {
		t := &c.tiles[gi]
		m := min(remaining, STORAGE_CAP - t.stored)
		if m > 0 {
			t.stored += m
			remaining -= m
			kept += m
		}
	}
	if remaining > 0 {
		room := BASE_GOLD_CAP - c.gold
		m := min(remaining, max(room, 0))
		if m > 0 {
			c.gold += m
			kept += m
		}
	}
	return kept
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

capture_card_cost :: proc() -> int {
	return 40
}

// 0 ok, 2 not enough gold.
colony_buy_capture_card :: proc(c: ^Colony) -> int {
	if !colony_spend_gold(c, capture_card_cost()) {
		return 2
	}
	c.capture_cards += 1
	return 0
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

	// 1. Mines: a staffed mine deposits gold (to a treasury in range, else to
	// the stockpile, which caps at the base cap).
	for t in c.tiles {
		if t.improvement != .MINE {
			continue
		}
		if monsters_on_tile(c, t.hex, false) == 0 {
			continue
		}
		colony_deposit_gold(c, t.hex, 4)
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

	// 6. Wild monsters: spawn near you, roam, wander off, squabble, then act.
	for s in c.messages {
		delete(s)
	}
	clear(&c.messages)
	for i in 0..<len(c.tiles) {
		if c.tiles[i].scuffle > 0 {
			c.tiles[i].scuffle -= 1
		}
	}

	colony_spawn_wilds(c)
	colony_roam_wilds(c)
	colony_despawn_wilds(c)
	colony_crowd_fights(c)
	colony_resolve_wild_actions(c)

	c.turn += 1
}

// ----------------------------------------------------------------------------
// Wild monsters: spawning, roaming and attacks (Phase 3)
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

player_monsters :: proc(c: ^Colony) -> int {
	n := 0
	for m in c.roster {
		if !m.wild {
			n += 1
		}
	}
	return n
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

tile_prevents_spawn :: proc(t: ^Tile) -> bool {
	return t.improvement == .FARM || t.improvement == .MINE
}

terrain_spawn_chance :: proc(t: Terrain) -> f32 {
	switch t {
	case .CAVE:         return 0.06
	case .WATER:        return 0.03
	case .GROVE:        return 0.06
	case .DUNGEON:      return 0.18
	case .TRADING_POST: return 0.0
	case .BOSS_ROOM:    return 0.0
	}
	return 0.0
}

spawn_species_for :: proc(t: Terrain, rng: ^Rng) -> int {
	#partial switch t {
	case .CAVE:         return 3
	case .GROVE:        return 6
	case .WATER:        return 5
	case .DUNGEON:      return rng_f32(rng) < 0.35 ? 7 : 4
	case .BOSS_ROOM:    return 8
	case:               return 3
	}
}

spawn_level_for :: proc(c: ^Colony) -> int {
	return 1 + c.floor / 2 + rng_below(&c.rng, 2)
}

spawn_wild_at :: proc(c: ^Colony, hex: Hex, species: int, level: int) {
	m := Monster{
		id       = c.next_id,
		creature = creature_make(species, level, SPECIES[species].name),
		pos      = hex,
		wild     = true,
	}
	c.next_id += 1
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

colony_notify :: proc(c: ^Colony, format: string, args: ..any) {
	append(&c.messages, fmt.aprintf(format, ..args))
	for len(c.messages) > 5 {
		delete(c.messages[0])
		ordered_remove(&c.messages, 0)
	}
}

// Rough compass direction ("north", "southeast", ...) from one hex to another.
compass_dir :: proc(from, to: Hex) -> cstring {
	if hex_equal(from, to) {
		return "here"
	}
	x := f32(to.q - from.q)
	y := f32(to.r-from.r) + 0.5 * f32(to.q-from.q)
	ang := math.atan2(y, x) * 180.0 / math.PI
	switch {
	case ang >= -22.5 && ang < 22.5:    return "east"
	case ang >= 22.5 && ang < 67.5:     return "southeast"
	case ang >= 67.5 && ang < 112.5:    return "south"
	case ang >= 112.5 && ang < 157.5:   return "southwest"
	case ang >= 157.5 || ang < -157.5:  return "west"
	case ang >= -157.5 && ang < -112.5: return "northwest"
	case ang >= -112.5 && ang < -67.5:  return "north"
	case:                               return "northeast"
	}
}

colony_spawn_wilds :: proc(c: ^Colony) {
	for i in 0..<len(c.tiles) {
		if wild_monsters(c) >= MAX_WILDS {
			return
		}
		t := &c.tiles[i]
		if tile_prevents_spawn(t) {
			continue
		}
		if monsters_on_tile(c, t.hex, false) > 0 {
			continue // guarded
		}
		// Simulated on all tiles near your monsters, explored or not.
		if nearest_player_distance(c, t.hex) > SIM_DISTANCE {
			continue
		}
		if rng_f32(&c.rng) >= terrain_spawn_chance(t.terrain) {
			continue
		}
		sp := spawn_species_for(t.terrain, &c.rng)
		spawn_wild_at(c, t.hex, sp, spawn_level_for(c))
	}
}

// Wilds far from your presence may wander off, and excess is culled from the
// farthest tiles, so the world doesn't fill up.
colony_despawn_wilds :: proc(c: ^Colony) {
	i := 0
	for i < len(c.roster) {
		m := &c.roster[i]
		if !m.wild {
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
		i += 1
	}
	// Hard cap: cull the wild farthest from you.
	for wild_monsters(c) > MAX_WILDS - 6 {
		far_i := -1
		far_d := -1
		for m, k in c.roster {
			if !m.wild {
				continue
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
		if rng_f32(&c.rng) >= 0.6 {
			continue // sometimes stay put
		}
		ns := hex_neighbors(m.pos)
		start := rng_below(&c.rng, 6)
		for k in 0..<6 {
			n := ns[(start + k) % 6]
			if tile_at(c, n) != nil {
				m.pos = n
				break
			}
		}
	}
}

damage_improvement :: proc(c: ^Colony, t: ^Tile, dmg: int) {
	t.improvement_hp -= dmg
	if t.improvement_hp <= 0 {
		// Destroyed: contents are lost.
		t.stored = 0
		t.improvement = .NONE
		t.improvement_hp = 0
		colony_recompute_caps(c)
	}
}

// Wilds that ended their move on a defended tile queue that tile for battle;
// wilds on an unguarded improved tile damage it.
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
		if t := tile_at(c, m.pos); t != nil && t.improvement != .NONE {
			damage_improvement(c, t, 6 + m.creature.level * 3)
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
	creature_free_piles(&m.creature)
	m.food = monster_satiety_max(m)
	m.energy = monster_energy_max(m)
	return true
}

// ----------------------------------------------------------------------------
// Spawning the player's first monster
// ----------------------------------------------------------------------------

colony_add_starter :: proc(c: ^Colony, species_idx: int) -> int {
	m := Monster{
		id       = c.next_id,
		creature = creature_make(species_idx, 1, SPECIES[species_idx].name),
		pos      = c.start_hex,
	}
	c.next_id += 1
	m.energy = monster_energy_max(&m)
	m.food = monster_satiety_max(&m)
	append(&c.roster, m)
	return len(c.roster) - 1
}
