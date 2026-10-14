package main
monster_can_breed :: proc(c: ^Colony, idx: int) -> bool {
	if idx < 0 || idx >= len(c.roster) {
		return false
	}
	return !c.roster[idx].wild && c.roster[idx].creature.level >= BREED_MIN_LEVEL
}

// How many stored monsters of `kind` live in the building at `hex`.
stored_count :: proc(c: ^Colony, hex: Hex, kind: Stored_In) -> int {
	n := 0
	for m in c.storage {
		if m.stored == kind && hex_equal(m.stored_hex, hex) {
			n += 1
		}
	}
	return n
}

den_occupancy :: proc(c: ^Colony, hex: Hex) -> int {
	return stored_count(c, hex, .DEN)
}

nursery_parent_count :: proc(c: ^Colony, hex: Hex) -> int {
	return stored_count(c, hex, .NURSERY_PARENT)
}

nursery_baby_count :: proc(c: ^Colony, hex: Hex) -> int {
	return stored_count(c, hex, .NURSERY_BABY)
}

// A map tile a stored monster can be dropped onto.
stored_deploy_ok :: proc(c: ^Colony, m: ^Monster, hex: Hex) -> bool {
	t := tile_at(c, hex)
	if t == nil || !t.revealed {
		return false
	}
	if monsters_on_tile(c, hex, false) >= MAX_MONSTERS_PER_TILE {
		return false
	}
	return tile_passable(c, m, hex)
}

// A free tile at the building or beside it.
deploy_position :: proc(c: ^Colony, m: ^Monster, center: Hex) -> (Hex, bool) {
	if stored_deploy_ok(c, m, center) {
		return center, true
	}
	for n in hex_neighbors(center) {
		if stored_deploy_ok(c, m, n) {
			return n, true
		}
	}
	return center, false
}

// --- Den: stasis in / out ---

// 0 ok, 1 not storable, 2 full, 3 too far from the Den.
colony_store_monster :: proc(c: ^Colony, roster_idx: int, den_hex: Hex) -> int {
	if roster_idx < 0 || roster_idx >= len(c.roster) {
		return 1
	}
	m := &c.roster[roster_idx]
	if m.wild {
		return 1
	}
	t := tile_at(c, den_hex)
	if t == nil || t.improvement != .DEN {
		return 1
	}
	if hex_distance(m.pos, den_hex) > STORE_RANGE {
		return 3
	}
	if den_occupancy(c, den_hex) >= den_capacity(c) {
		return 2
	}
	stored := c.roster[roster_idx]
	unordered_remove(&c.roster, roster_idx)
	stored.stored = .DEN
	stored.stored_hex = den_hex
	stored.pos = den_hex
	append(&c.storage, stored)
	return 0
}

// 0 ok, 1 bad index, 2 no room beside the building.
colony_deploy_stored :: proc(c: ^Colony, storage_idx: int) -> int {
	if storage_idx < 0 || storage_idx >= len(c.storage) {
		return 1
	}
	moved := c.storage[storage_idx]
	pos, ok := deploy_position(c, &moved, moved.stored_hex)
	if !ok {
		return 2
	}
	unordered_remove(&c.storage, storage_idx)
	moved.stored = .MAP
	moved.stored_hex = {}
	moved.pos = pos
	moved.food = monster_satiety_max(&moved)
	moved.creature.energy = moved.creature.energy_max
	append(&c.roster, moved)
	return 0
}

// When a Den/Nursery is destroyed or replaced, push its occupants back onto the
// map around `hex`; anything with nowhere to stand is lost.
colony_evacuate_storage :: proc(c: ^Colony, hex: Hex) {
	i := 0
	for i < len(c.storage) {
		m := &c.storage[i]
		if !hex_equal(m.stored_hex, hex) {
			i += 1
			continue
		}
		pos, ok := deploy_position(c, m, hex)
		if !ok {
			creature_free_all(&m.creature)
			unordered_remove(&c.storage, i)
			continue
		}
		moved := c.storage[i]
		unordered_remove(&c.storage, i)
		moved.stored = .MAP
		moved.stored_hex = {}
		moved.pos = pos
		moved.food = monster_satiety_max(&moved)
		moved.creature.energy = moved.creature.energy_max
		append(&c.roster, moved)
	}
}

// --- Nursery: pair in / babies out ---

// The species of the nursery's pair, if any parent is present.
nursery_pair_species :: proc(c: ^Colony, hex: Hex) -> (Species_Id, bool) {
	for m in c.storage {
		if m.stored == .NURSERY_PARENT && hex_equal(m.stored_hex, hex) {
			return m.creature.species, true
		}
	}
	return .Emberling, false
}

// Can this map monster join the nursery's pair? It must be beside the Nursery,
// Lvl 5+, and the same species as the other parent (if one is already in).
nursery_accepts :: proc(c: ^Colony, roster_idx: int, hex: Hex) -> bool {
	if !monster_can_breed(c, roster_idx) {
		return false
	}
	if hex_distance(c.roster[roster_idx].pos, hex) > STORE_RANGE {
		return false
	}
	if nursery_parent_count(c, hex) >= NURSERY_PARENTS {
		return false
	}
	if sp, ok := nursery_pair_species(c, hex); ok {
		return c.roster[roster_idx].creature.species == sp
	}
	return true
}

// 0 ok, 1 not eligible, 2 pair already full.
colony_assign_parent :: proc(c: ^Colony, roster_idx: int, nursery_hex: Hex) -> int {
	t := tile_at(c, nursery_hex)
	if t == nil || t.improvement != .NURSERY {
		return 1
	}
	if nursery_parent_count(c, nursery_hex) >= NURSERY_PARENTS {
		return 2
	}
	if !nursery_accepts(c, roster_idx, nursery_hex) {
		return 1
	}
	moved := c.roster[roster_idx]
	unordered_remove(&c.roster, roster_idx)
	moved.stored = .NURSERY_PARENT
	moved.stored_hex = nursery_hex
	moved.pos = nursery_hex
	append(&c.storage, moved)
	return 0
}

// Hatches one baby from the nursery's pair into storage.
colony_nursery_birth :: proc(c: ^Colony, hex: Hex) {
	a: ^Monster
	b: ^Monster
	for i in 0..<len(c.storage) {
		m := &c.storage[i]
		if m.stored != .NURSERY_PARENT || !hex_equal(m.stored_hex, hex) {
			continue
		}
		if a == nil {
			a = m
		} else if b == nil {
			b = m
		}
	}
	if a == nil || b == nil {
		return
	}
	species := a.creature.species
	genes := genes_breed(a.creature.genes, b.creature.genes, &c.rng)
	baby := Monster{
		id         = c.next_id,
		creature   = creature_make_genes(species, 1, SPECIES[species].name, genes, &c.rng),
		pos        = hex,
		stored     = .NURSERY_BABY,
		stored_hex = hex,
	}
	c.next_id += 1
	baby.creature.player = true
	baby.creature.energy = baby.creature.energy_max
	baby.food = monster_satiety_max(&baby)
	creature_recompute_stats(&baby.creature)
	append(&c.storage, baby)
	colony_notify(c, "A %s hatches in a Nursery!", SPECIES[species].name)
}

// Each occupied Nursery eats food and advances toward a baby.
colony_nurseries :: proc(c: ^Colony, n_tiles: int, food_stores: []int) {
	for i in 0..<n_tiles {
		t := c.tiles[i]
		if t.improvement != .NURSERY {
			continue
		}
		if nursery_parent_count(c, t.hex) < NURSERY_PARENTS {
			t.stored = 0
			continue
		}
		if nursery_baby_count(c, t.hex) >= NURSERY_BABIES {
			continue // full: stop eating until a baby is taken out
		}
		gi := nearest_food_store_in(c, food_stores, t.hex, DELIVER_RADIUS, NURSERY_FOOD_PER_TURN)
		if gi < 0 {
			continue // starved: no progress this turn
		}
		c.tiles[gi].stored -= NURSERY_FOOD_PER_TURN
		colony_add_float(c, c.tiles[gi].hex, .FOOD_OUT, NURSERY_FOOD_PER_TURN)
		t.stored += 1
		period := max(NURSERY_PERIOD - upgrade_nursery_speed(c), 3)
		if t.stored >= period {
			t.stored = 0
			colony_nursery_birth(c, t.hex)
		}
	}
}

// Item slots your bag holds: a base plus every Vault.
building_count :: proc(c: ^Colony, im: Improvement) -> int {
	n := 0
	for t in c.tiles {
		if t.improvement == im {
			n += 1
		}
	}
	return n
}

building_hex_at :: proc(c: ^Colony, im: Improvement, k: int) -> Hex {
	n := 0
	for t in c.tiles {
		if t.improvement == im {
			if n == k {
				return t.hex
			}
			n += 1
		}
	}
	return {}
}

den_count :: proc(c: ^Colony) -> int {
	return building_count(c, .DEN)
}
den_hex_at :: proc(c: ^Colony, k: int) -> Hex {
	return building_hex_at(c, .DEN, k)
}
nursery_count :: proc(c: ^Colony) -> int {
	return building_count(c, .NURSERY)
}
nursery_hex_at :: proc(c: ^Colony, k: int) -> Hex {
	return building_hex_at(c, .NURSERY, k)
}

// Index into `Colony.storage` of the k-th stored monster of `kind` at `hex`.
stored_slot_index :: proc(c: ^Colony, hex: Hex, kind: Stored_In, k: int) -> int {
	n := 0
	for i in 0..<len(c.storage) {
		m := c.storage[i]
		if m.stored == kind && hex_equal(m.stored_hex, hex) {
			if n == k {
				return i
			}
			n += 1
		}
	}
	return -1
}

// The k-th map monster within STORE_RANGE of `hex` (roster index), or -1.
nearby_map_monster_at :: proc(c: ^Colony, hex: Hex, k: int) -> int {
	n := 0
	for i in 0..<len(c.roster) {
		m := c.roster[i]
		if m.wild || hex_distance(m.pos, hex) > STORE_RANGE {
			continue
		}
		if n == k {
			return i
		}
		n += 1
	}
	return -1
}
