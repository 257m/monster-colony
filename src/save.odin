package main

import "core:fmt"
import "core:time"

// ============================================================================
// SAVE FILES
//
// A small hand-rolled little-endian binary format (no reflection) so the whole
// colony round-trips: every map tile, your roster, Dens/Nursery storage, the
// graveyard, items, shop stock, the upgrade tree and the turn clock. Battle
// state is deliberately NOT saved — saving/loading is only offered on the map.
//
// Layout: "MCV1" + version + a small metadata block (readable without a full
// parse, for the slot list) + the colony. Slots live beside the executable as
// `save_1.mcs`, `save_2.mcs`, `save_3.mcs`.
// ============================================================================

SAVE_MAGIC   :: "MCV1"
SAVE_VERSION :: 15
SAVE_SLOTS   :: 3
// The autosave is a 4th, special slot: the game writes it every so often and the
// save panel only lets you load from it.
AUTOSAVE_SLOT     :: SAVE_SLOTS
AUTOSAVE_EVERY    :: 10 // turns between autosaves

Save_Writer :: struct {
	buf: [dynamic]u8,
}

Save_Reader :: struct {
	buf:    []u8,
	pos:    int,
	failed: bool,
}

// A slot's header, shown in the save/load panel.
Save_Meta :: struct {
	exists:   bool,
	turn:     int,
	gold:     int,
	monsters: int,
	crystals: int,
	saved_at: i64, // unix seconds
}

// ----------------------------------------------------------------------------
// Primitives
// ----------------------------------------------------------------------------

sw_u8 :: proc(w: ^Save_Writer, v: u8) {
	append(&w.buf, v)
}

sw_i32 :: proc(w: ^Save_Writer, v: i32) {
	u := u32(v)
	append(&w.buf, u8(u), u8(u >> 8), u8(u >> 16), u8(u >> 24))
}

sw_i64 :: proc(w: ^Save_Writer, v: i64) {
	u := u64(v)
	for i in 0 ..< 8 {
		append(&w.buf, u8(u >> (u64(i) * 8)))
	}
}

sw_u64 :: proc(w: ^Save_Writer, v: u64) {
	sw_i64(w, transmute(i64)v)
}

sw_f32 :: proc(w: ^Save_Writer, v: f32) {
	sw_i32(w, transmute(i32)v)
}

sw_bool :: proc(w: ^Save_Writer, v: bool) {
	sw_u8(w, v ? 1 : 0)
}

sw_int :: proc(w: ^Save_Writer, v: int) {
	sw_i32(w, i32(v))
}

sw_hex :: proc(w: ^Save_Writer, h: Hex) {
	sw_i32(w, i32(h.q))
	sw_i32(w, i32(h.r))
}

sw_enum :: proc(w: ^Save_Writer, v: $E) {
	sw_i32(w, i32(v))
}

sr_u8 :: proc(r: ^Save_Reader) -> u8 {
	if r.pos >= len(r.buf) {
		r.failed = true
		return 0
	}
	v := r.buf[r.pos]
	r.pos += 1
	return v
}

sr_i32 :: proc(r: ^Save_Reader) -> i32 {
	b0 := u32(sr_u8(r))
	b1 := u32(sr_u8(r))
	b2 := u32(sr_u8(r))
	b3 := u32(sr_u8(r))
	return i32(b0 | b1 << 8 | b2 << 16 | b3 << 24)
}

sr_i64 :: proc(r: ^Save_Reader) -> i64 {
	u: u64
	for i in 0 ..< 8 {
		u |= u64(sr_u8(r)) << (u64(i) * 8)
	}
	return i64(u)
}

sr_u64 :: proc(r: ^Save_Reader) -> u64 {
	return transmute(u64)sr_i64(r)
}

sr_f32 :: proc(r: ^Save_Reader) -> f32 {
	return transmute(f32)sr_i32(r)
}

sr_bool :: proc(r: ^Save_Reader) -> bool {
	return sr_u8(r) != 0
}

sr_int :: proc(r: ^Save_Reader) -> int {
	return int(sr_i32(r))
}

sr_hex :: proc(r: ^Save_Reader) -> Hex {
	q := sr_i32(r)
	rr := sr_i32(r)
	return Hex{q = int(q), r = int(rr)}
}

sr_enum :: proc(r: ^Save_Reader, $E: typeid) -> E {
	return E(sr_i32(r))
}

// ----------------------------------------------------------------------------
// Object serialization
// ----------------------------------------------------------------------------

save_creature :: proc(w: ^Save_Writer, cr: ^Creature) {
	sw_enum(w, cr.species)
	sw_int(w, cr.level)
	sw_int(w, cr.xp)
	sw_int(w, cr.hp)
	sw_int(w, cr.max_hp)
	sw_int(w, cr.block)
	sw_int(w, cr.vulnerable)
	sw_int(w, cr.strength)
	sw_f32(w, cr.power)
	sw_f32(w, cr.defense)
	sw_f32(w, cr.defense_buff)
	sw_f32(w, cr.defense_debuff)
	sw_f32(w, cr.speed)
	sw_f32(w, cr.speed_buff)
	sw_f32(w, cr.energy)
	sw_f32(w, cr.energy_regen)
	sw_f32(w, cr.energy_max)
	sw_enum(w, cr.ability)
	sw_enum(w, cr.item)
	for gene in Gene {
		sw_int(w, cr.genes[gene])
	}
	sw_int(w, len(cr.deck))
	for m in cr.deck {
		sw_enum(w, m)
	}
	sw_int(w, cr.played)
}

load_creature :: proc(r: ^Save_Reader) -> Creature {
	cr: Creature
	cr.species = sr_enum(r, Species_Id)
	// Guard against a corrupt/old file picking an out-of-range species.
	if int(cr.species) < 0 || int(cr.species) >= len(SPECIES) {
		cr.species = .Emberling
	}
	cr.name = SPECIES[cr.species].name
	cr.level = max(sr_int(r), 1)
	cr.xp = sr_int(r)
	cr.hp = sr_int(r)
	cr.max_hp = sr_int(r)
	cr.block = sr_int(r)
	cr.vulnerable = sr_int(r)
	cr.strength = sr_int(r)
	cr.power = sr_f32(r)
	cr.defense = sr_f32(r)
	cr.defense_buff = sr_f32(r)
	cr.defense_debuff = sr_f32(r)
	cr.speed = sr_f32(r)
	cr.speed_buff = sr_f32(r)
	cr.energy = sr_f32(r)
	cr.energy_regen = sr_f32(r)
	cr.energy_max = sr_f32(r)
	cr.ability = sr_enum(r, Ability)
	cr.item = sr_enum(r, Item)
	for gene in Gene {
		cr.genes[gene] = sr_int(r)
	}
	n := sr_int(r)
	cr.deck = make([dynamic]Move_Id, 0)
	for _ in 0 ..< n {
		append(&cr.deck, sr_enum(r, Move_Id))
	}
	cr.played = sr_int(r)
	// Per-battle piles are rebuilt when a fight starts.
	cr.draw_pile = make([dynamic]Move_Id, 0)
	cr.hand = make([dynamic]Move_Id, 0)
	cr.discard = make([dynamic]Move_Id, 0)
	return cr
}

save_monster :: proc(w: ^Save_Writer, m: ^Monster) {
	sw_int(w, m.id)
	save_creature(w, &m.creature)
	sw_hex(w, m.pos)
	sw_bool(w, m.wild)
	sw_f32(w, m.food)
	sw_enum(w, m.role)
	sw_int(w, m.pack)
	sw_enum(w, m.stored)
	sw_hex(w, m.stored_hex)
}

load_monster :: proc(r: ^Save_Reader) -> Monster {
	m: Monster
	m.id = sr_int(r)
	m.creature = load_creature(r)
	m.pos = sr_hex(r)
	m.wild = sr_bool(r)
	m.food = sr_f32(r)
	m.role = sr_enum(r, Wild_Role)
	m.pack = sr_int(r)
	m.stored = sr_enum(r, Stored_In)
	m.stored_hex = sr_hex(r)
	// Player-ness is derived: anything not wild is yours (relics apply to it).
	m.creature.player = !m.wild
	return m
}

save_tile :: proc(w: ^Save_Writer, t: ^Tile) {
	sw_hex(w, t.hex)
	sw_enum(w, t.terrain)
	sw_bool(w, t.revealed)
	sw_enum(w, t.improvement)
	sw_enum(w, t.overlay)
	sw_int(w, t.improvement_hp)
	sw_int(w, t.overlay_hp)
	sw_int(w, t.stored)
	sw_int(w, t.scuffle)
	sw_bool(w, t.drawbridge_down)
	// Relic Tower contents.
	sw_int(w, int(t.relic_count))
	for i in 0..<int(t.relic_count) {
		sw_enum(w, t.relics[i])
	}
}

load_tile :: proc(r: ^Save_Reader) -> Tile {
	t: Tile
	t.hex = sr_hex(r)
	t.terrain = sr_enum(r, Terrain)
	t.revealed = sr_bool(r)
	t.improvement = sr_enum(r, Improvement)
	t.overlay = sr_enum(r, Improvement)
	t.improvement_hp = sr_int(r)
	t.overlay_hp = sr_int(r)
	t.stored = sr_int(r)
	t.scuffle = sr_int(r)
	t.drawbridge_down = sr_bool(r)
	// Relic Tower contents.
	t.relic_count = u8(clamp(sr_int(r), 0, RELIC_SLOTS))
	for i in 0..<int(t.relic_count) {
		t.relics[i] = sr_enum(r, Relic)
	}
	t.hit_t0 = 0 // don't replay a stale damage shake
	return t
}

save_colony :: proc(w: ^Save_Writer, c: ^Colony) {
	sw_i64(w, i64(c.seed))
	sw_i64(w, i64(c.rng.state))
	sw_int(w, c.turn)
	sw_int(w, c.floor)
	sw_int(w, c.next_id)
	sw_int(w, c.next_pack_id)
	sw_hex(w, c.start_hex)
	sw_int(w, c.gold)
	sw_int(w, c.crystals)
	sw_int(w, c.capture_cards)
	sw_int(w, c.gold_cap)
	sw_int(w, c.food_cap)
	sw_int(w, c.heat)
	sw_int(w, c.raid_timer)
	sw_int(w, c.raids)
	sw_int(w, c.shop_turn)
	for u in Upgrade {
		sw_int(w, c.upgrades[u])
	}
	sw_int(w, len(c.tiles))
	for t in c.tiles {
		save_tile(w, t)
	}
	sw_int(w, len(c.roster))
	for i in 0 ..< len(c.roster) {
		save_monster(w, &c.roster[i])
	}
	sw_int(w, len(c.storage))
	for i in 0 ..< len(c.storage) {
		save_monster(w, &c.storage[i])
	}
	sw_int(w, len(c.graveyard))
	for i in 0 ..< len(c.graveyard) {
		save_monster(w, &c.graveyard[i])
	}
	sw_int(w, len(c.items))
	for it in c.items {
		sw_enum(w, it)
	}
	sw_int(w, len(c.shop))
	for o in c.shop {
		sw_enum(w, o.species)
		sw_int(w, o.level)
		sw_int(w, o.price)
	}
	// Lifetime stats + quest board (Phase 22).
	sw_int(w, c.fights_won)
	sw_int(w, c.alphas_slain)
	sw_int(w, c.arena_run ? 1 : 0)
	sw_int(w, c.arena_floor)
	sw_int(w, c.arena_best_floor)
	sw_int(w, c.arena_run_crystals)
	sw_int(w, c.arena_base_level)
	sw_u64(w, c.arena_run_seed)
	sw_int(w, len(c.arena_boons))
	for r in c.arena_boons {
		sw_enum(w, r)
	}
	for sp in Species_Id {
		sw_int(w, c.bosses_slain[sp] ? 1 : 0)
	}
	sw_int(w, c.crystals_earned)
	sw_int(w, c.improvements_built)
	for k in Milestone_Kind {
		sw_int(w, c.milestones[k] ? 1 : 0)
	}
	sw_int(w, c.goal_done ? 1 : 0)
	// Relic bag (Phase 25/44): the relics you haven't slotted yet. Placed ones
	// live on their tower tiles (see `save_tile`).
	sw_int(w, len(c.relic_bag))
	for r in c.relic_bag {
		sw_enum(w, r)
	}
}

load_colony :: proc(r: ^Save_Reader, c: ^Colony) {
	c.seed = u64(sr_i64(r))
	c.rng = Rng{state = u64(sr_i64(r))}
	c.turn = sr_int(r)
	c.floor = sr_int(r)
	c.next_id = sr_int(r)
	c.next_pack_id = sr_int(r)
	c.start_hex = sr_hex(r)
	c.gold = sr_int(r)
	c.crystals = sr_int(r)
	c.capture_cards = sr_int(r)
	c.gold_cap = sr_int(r)
	c.food_cap = sr_int(r)
	c.heat = sr_int(r)
	c.raid_timer = sr_int(r)
	c.raids = sr_int(r)
	c.shop_turn = sr_int(r)
	for u in Upgrade {
		c.upgrades[u] = sr_int(r)
	}
	nt := sr_int(r)
	for _ in 0 ..< nt {
		t := new(Tile)
		t^ = load_tile(r)
		c.tile_index[hex_key(t.hex)] = len(c.tiles)
		append(&c.tiles, t)
	}
	n_roster := sr_int(r)
	for _ in 0 ..< n_roster {
		append(&c.roster, load_monster(r))
	}
	n_storage := sr_int(r)
	for _ in 0 ..< n_storage {
		append(&c.storage, load_monster(r))
	}
	n_grave := sr_int(r)
	for _ in 0 ..< n_grave {
		append(&c.graveyard, load_monster(r))
	}	ni := sr_int(r)
	for _ in 0 ..< ni {
		append(&c.items, sr_enum(r, Item))
	}
	ns := sr_int(r)
	for _ in 0 ..< ns {
		append(&c.shop, Shop_Offer{species = sr_enum(r, Species_Id), level = sr_int(r), price = sr_int(r)})
	}
	// Lifetime stats + quest board (Phase 22).
	c.fights_won = sr_int(r)
	c.alphas_slain = sr_int(r)
	c.arena_run = sr_int(r) != 0
	c.arena_floor = sr_int(r)
	c.arena_best_floor = sr_int(r)
	c.arena_run_crystals = sr_int(r)
	c.arena_base_level = sr_int(r)
	c.arena_run_seed = sr_u64(r)
	{
		bn := sr_int(r)
		for _ in 0..<bn {
			append(&c.arena_boons, sr_enum(r, Relic))
		}
	}
	for sp in Species_Id {
		c.bosses_slain[sp] = sr_int(r) != 0
	}
	c.crystals_earned = sr_int(r)
	c.improvements_built = sr_int(r)
	for k in Milestone_Kind {
		c.milestones[k] = sr_int(r) != 0
	}
	c.goal_done = sr_int(r) != 0
	// Relic bag (Phase 25/44).
	n_relics := sr_int(r)
	for _ in 0..<n_relics {
		append(&c.relic_bag, sr_enum(r, Relic))
	}
}

// ----------------------------------------------------------------------------
// Header + metadata
// ----------------------------------------------------------------------------

save_write_header :: proc(w: ^Save_Writer, g: ^Game) {
	for ch in SAVE_MAGIC {
		append(&w.buf, u8(ch))
	}
	sw_i32(w, SAVE_VERSION)
	sw_int(w, g.colony.turn)
	sw_int(w, g.colony.gold)
	sw_int(w, player_monster_count(&g.colony))
	sw_int(w, g.colony.crystals)
	sw_i64(w, time.time_to_unix(time.now()))
}

save_check_header :: proc(r: ^Save_Reader) -> bool {
	if len(r.buf) < 4 || string(r.buf[0:4]) != SAVE_MAGIC {
		return false
	}
	r.pos = 4
	return sr_i32(r) == SAVE_VERSION
}

save_skip_meta :: proc(r: ^Save_Reader) {
	_ = sr_int(r) // turn
	_ = sr_int(r) // gold
	_ = sr_int(r) // monsters
	_ = sr_int(r) // crystals
	_ = sr_i64(r) // saved_at
}

save_path :: proc(slot: int, buf: []u8) -> string {
	if slot == AUTOSAVE_SLOT {
		return fmt.bprintf(buf, "autosave.mcs")
	}
	return fmt.bprintf(buf, "save_%d.mcs", slot + 1)
}

// ----------------------------------------------------------------------------
// File I/O lives in save_io_desktop.odin / save_io_js.odin (platform-gated,
// because `core:os` does not exist on the web target). The procs below are
// provided by those files: `save_supported`, `save_write_file`, `save_read_file`.
// ----------------------------------------------------------------------------

// ----------------------------------------------------------------------------
// Public API
// ----------------------------------------------------------------------------

save_game :: proc(g: ^Game, slot: int) -> bool {
	if !g.has_colony || !save_supported() {
		return false
	}
	w: Save_Writer
	defer delete(w.buf)
	save_write_header(&w, g)
	save_colony(&w, &g.colony)
	buf: [64]u8
	ok := save_write_file(save_path(slot, buf[:]), w.buf[:])
	audio_play(ok ? .CONFIRM : .ERROR)
	return ok
}

load_game :: proc(g: ^Game, slot: int) -> bool {
	if !save_supported() {
		return false
	}
	buf: [64]u8
	data, ok := save_read_file(save_path(slot, buf[:]))
	if !ok {
		return false
	}
	defer delete(data)

	r := Save_Reader{buf = data}
	if !save_check_header(&r) {
		return false
	}
	save_skip_meta(&r)

	// Tear down whatever is running, then rebuild the colony from the file.
	end_run(g)
	load_colony(&r, &g.colony)
	if r.failed {
		end_run(g)
		return false
	}
	g.has_colony = true
	// A run in progress resumes on the Arena screen, where it left off.
	g.mode = g.colony.arena_run ? .ARENA : .MAP
	g.has_battle = false
	g.battle_choice_open = false
	g.attack_select_open = false
	g.results_open = false
	g.build_mode = false
	g.has_build = false
	g.selected = -1
	colony_recompute_caps(&g.colony)
	center_camera_on(&g.renderer, g.colony.start_hex)
	audio_play(.CONFIRM)
	return true
}

save_read_meta :: proc(slot: int) -> Save_Meta {
	if !save_supported() {
		return {}
	}
	buf: [64]u8
	data, ok := save_read_file(save_path(slot, buf[:]))
	if !ok {
		return {}
	}
	defer delete(data)
	r := Save_Reader{buf = data}
	if !save_check_header(&r) {
		return {}
	}
	m: Save_Meta
	m.exists = true
	m.turn = sr_int(&r)
	m.gold = sr_int(&r)
	m.monsters = sr_int(&r)
	m.crystals = sr_int(&r)
	m.saved_at = sr_i64(&r)
	return m
}

// A short "3h ago" style label for a slot's saved-at timestamp.
save_age_label :: proc(saved_at: i64, buf: []u8) -> string {
	now := time.time_to_unix(time.now())
	age := now - saved_at
	if age < 0 {
		age = 0
	}
	switch {
	case age < 60:
		return "just now"
	case age < 3600:
		return fmt.bprintf(buf, "%dm ago", age / 60)
	case age < 86400:
		return fmt.bprintf(buf, "%dh ago", age / 3600)
	case:
		return fmt.bprintf(buf, "%dd ago", age / 86400)
	}
}
