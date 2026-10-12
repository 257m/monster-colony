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

Terrain :: enum { CAVE, WATER, DUNGEON, GROVE, TRADING_POST, BOSS_ROOM, MUSHROOM, RUINS, TUNDRA, JUNGLE, LAVA, DESERT, QUICKSAND }
Improvement :: enum { NONE, FARM, MINE, BRIDGE, GRANARY, TREASURY, WATCHTOWER, WALL, WELL, GATE, SPIKE_TRAP, SCARECROW, ROAD, SILO, CRYSTAL_REFINERY, FOUNTAIN, TURRET, DRAWBRIDGE, QUARRY, LUMBER_MILL, MARKETPLACE, KITCHEN, BARRACKS, BEACON }

MAX_MONSTERS_PER_TILE :: 6
REFILL_FRAC           :: f32(0.5) // of max satiation gained per fed turn
STARVE_FRAC           :: f32(0.3) // of max satiation lost per starving turn
STORAGE_CAP           :: 100
BASE_GOLD_CAP         :: 100 // the stockpile's own cap; treasuries add storage beyond it
STARTING_CAPTURE_CARDS :: 3   // capture cards you begin the run with
FEED_RADIUS           :: 4
DELIVER_RADIUS        :: 4
MAX_WILDS              :: 30
SIM_DISTANCE           :: 6    // spawn/despawn radius around your nearest monster
DESPAWN_DISTANCE       :: 8    // beyond this, wilds may wander off
DESPAWN_CHANCE         :: f32(0.25)
CROWD_LIMIT            :: 3    // per tile; more than this and they may fight
CROWD_FIGHT_CHANCE     :: f32(0.30)
FARM_FOOD_YIELD        :: 6    // per staffed Farm per turn
WELL_FOOD_YIELD        :: 2    // per Well per turn
MINE_GOLD_YIELD        :: 4    // per staffed Mine per turn
WATCHTOWER_REVEAL      :: 6    // tiles revealed around a Watchtower
WATCHTOWER_DETER       :: 4    // radius in which a Watchtower stops spawns
WATCHTOWER_GUARD       :: 4    // radius in which defenders get starting Block
WATCHTOWER_GUARD_BLOCK :: 6    // Block granted to those defenders at battle start
SPIKE_TRAP_DAMAGE      :: 8    // HP a wild loses per turn standing on a Spike Trap
SCARECROW_DETER        :: 2    // radius a Scarecrow keeps spawns out of
SCARECROW_PANIC        :: 3    // radius a Scarecrow makes wilds likelier to flee
SCARECROW_PANIC_CHANCE :: f32(0.5)
CRYSTAL_REFINERY_COST  :: 15   // gold converted into 1 crystal per turn
ROAD_MOVE_FACTOR       :: f32(0.5)
// Phase B — energy network + builders
FOUNTAIN_RANGE         :: 4    // a Fountain supplies the closest recipient in range
FOUNTAIN_OUTPUT        :: 3    // energy handed out per turn
TURRET_RANGE           :: 4    // a Turret shoots the nearest wild in range
TURRET_DAMAGE          :: 10
TURRET_COST            :: 2    // charge spent per shot
TURRET_CAP             :: 6    // max charge a Turret can hold
MARKET_RADIUS          :: 3    // a Marketplace boosts Mines within this radius
MARKET_BONUS           :: f32(0.5)
QUARRY_GOLD_YIELD      :: 5
LUMBER_FOOD_YIELD      :: 5
KITCHEN_RADIUS         :: 4    // a Kitchen buffs defenders near the fight
KITCHEN_FOOD_COST      :: 6
KITCHEN_STRENGTH       :: 2
BARRACKS_RANGE         :: 4
BARRACKS_UPKEEP        :: 2    // food consumed per turn
BARRACKS_HEAL          :: 3
BARRACKS_XP            :: 1
BEACON_REVEAL          :: 8
BEACON_DETER           :: 5
BEACON_GUARD           :: 5
BEACON_VULN            :: 2    // Vulnerable applied to wilds attacking near a Beacon

terrain_name :: proc(t: Terrain) -> cstring {
	switch t {
	case .CAVE:         return "Cave"
	case .WATER:        return "Water"
	case .DUNGEON:      return "Dungeon"
	case .GROVE:        return "Grove"
	case .TRADING_POST: return "Trading Post"
	case .BOSS_ROOM:    return "Boss Room"
	case .MUSHROOM:     return "Mushroom Grove"
	case .RUINS:        return "Ruins"
	case .TUNDRA:       return "Tundra"
	case .JUNGLE:       return "Jungle"
	case .LAVA:         return "Lava"
	case .DESERT:       return "Desert"
	case .QUICKSAND:    return "Quicksand"
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
	case .MUSHROOM:     return rl.Color{96, 84, 112, 255}
	case .RUINS:        return rl.Color{96, 90, 78, 255}
	case .TUNDRA:       return rl.Color{196, 210, 224, 255}
	case .JUNGLE:       return rl.Color{40, 92, 52, 255}
	case .LAVA:         return rl.Color{168, 60, 30, 255}
	case .DESERT:       return rl.Color{186, 166, 108, 255}
	case .QUICKSAND:    return rl.Color{150, 132, 88, 255}
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
	case .WATCHTOWER: return "Watchtower"
	case .WALL:      return "Wall"
	case .WELL:      return "Well"
	case .GATE:      return "Gate"
	case .SPIKE_TRAP: return "Spike Trap"
	case .SCARECROW: return "Scarecrow"
	case .ROAD:      return "Road"
	case .SILO:      return "Silo"
	case .CRYSTAL_REFINERY: return "Crystal Refinery"
	case .FOUNTAIN:  return "Fountain"
	case .TURRET:    return "Turret"
	case .DRAWBRIDGE: return "Drawbridge"
	case .QUARRY:    return "Quarry"
	case .LUMBER_MILL: return "Lumber Mill"
	case .MARKETPLACE: return "Marketplace"
	case .KITCHEN:   return "Kitchen"
	case .BARRACKS:  return "Barracks"
	case .BEACON:    return "Beacon"
	}
	return ""
}

IMPROVEMENT_HP :: 50

// Health per improvement. Gates are deliberately frailer than Walls.
improvement_max_hp :: proc(im: Improvement) -> int {
	#partial switch im {
	case .NONE:             return 0
	case .GATE:             return 30
	case .SPIKE_TRAP:       return 25
	case .SCARECROW:        return 20
	case .ROAD:             return 40
	case .SILO:             return 50
	case .CRYSTAL_REFINERY: return 45
	case .TURRET:           return 35
	case .DRAWBRIDGE:       return 40
	case .FOUNTAIN:         return 45
	case .BEACON:           return 55
	}
	return IMPROVEMENT_HP
}

improvement_cost :: proc(im: Improvement) -> int {
	switch im {
	case .NONE:     return 0
	case .FARM:     return 20
	case .MINE:     return 20
	case .BRIDGE:   return 18
	case .GRANARY:  return 18
	case .TREASURY: return 18
	case .WATCHTOWER: return 25
	case .WALL:     return 15
	case .WELL:     return 20
	case .GATE:     return 12
	case .SPIKE_TRAP: return 18
	case .SCARECROW: return 8
	case .ROAD:     return 10
	case .SILO:     return 18
	case .CRYSTAL_REFINERY: return 30
	case .FOUNTAIN: return 24
	case .TURRET:   return 28
	case .DRAWBRIDGE: return 16
	case .QUARRY:   return 22
	case .LUMBER_MILL: return 22
	case .MARKETPLACE: return 26
	case .KITCHEN:  return 24
	case .BARRACKS: return 26
	case .BEACON:   return 40
	}
	return 0
}

improvement_valid_on :: proc(im: Improvement, t: Terrain) -> bool {
	#partial switch im {
	case .FARM:       return t == .GROVE || t == .MUSHROOM || t == .JUNGLE
	case .MINE:       return t == .CAVE || t == .DESERT || t == .TUNDRA
	case .BRIDGE:     return t == .WATER
	case .GRANARY:    return t == .CAVE || t == .GROVE || t == .MUSHROOM || t == .JUNGLE || t == .DESERT
	case .TREASURY:   return t == .CAVE || t == .DESERT || t == .TUNDRA
	case .WATCHTOWER: return t == .CAVE || t == .GROVE || t == .MUSHROOM || t == .RUINS || t == .TUNDRA || t == .DESERT || t == .JUNGLE
	case .WALL:       return t == .CAVE || t == .RUINS || t == .GROVE || t == .MUSHROOM || t == .TUNDRA || t == .DESERT
	case .WELL:       return t == .CAVE || t == .GROVE || t == .MUSHROOM || t == .JUNGLE || t == .DESERT
	case .GATE:       return t == .CAVE || t == .RUINS || t == .GROVE || t == .MUSHROOM
	case .SPIKE_TRAP: return t == .CAVE || t == .RUINS || t == .GROVE
	case .SCARECROW:  return t == .GROVE || t == .MUSHROOM || t == .JUNGLE
	case .ROAD:       return t == .CAVE || t == .GROVE || t == .DUNGEON || t == .RUINS || t == .DESERT || t == .TUNDRA || t == .MUSHROOM || t == .JUNGLE
	case .SILO:       return t == .CAVE || t == .GROVE
	case .CRYSTAL_REFINERY: return t == .RUINS || t == .CAVE || t == .DUNGEON
	case .FOUNTAIN:   return t == .CAVE || t == .GROVE || t == .MUSHROOM || t == .RUINS || t == .DESERT || t == .TUNDRA
	case .TURRET:     return t == .CAVE || t == .RUINS || t == .DESERT || t == .GROVE || t == .TUNDRA
	case .DRAWBRIDGE: return t == .WATER
	case .QUARRY:     return t == .RUINS || t == .DESERT || t == .TUNDRA
	case .LUMBER_MILL: return t == .GROVE || t == .MUSHROOM || t == .JUNGLE
	case .MARKETPLACE: return t == .CAVE || t == .GROVE || t == .MUSHROOM || t == .RUINS || t == .DESERT
	case .KITCHEN:    return t == .CAVE || t == .GROVE || t == .MUSHROOM
	case .BARRACKS:   return t == .CAVE || t == .RUINS || t == .GROVE || t == .DESERT
	case .BEACON:     return t == .RUINS || t == .CAVE
	case:             return false
	}
}

improvement_effect :: proc(im: Improvement) -> cstring {
	switch im {
	case .NONE:     return ""
	case .FARM:     return "staffed: feeds within 4, surplus to granary"
	case .MINE:     return "staffed: gold to treasury within 4"
	case .BRIDGE:   return "land monsters can cross water"
	case .GRANARY:  return "stores food, feeds within 4"
	case .TREASURY: return "stores gold"
	case .WATCHTOWER: return "reveals 6, deters spawns 4, guards within 4 (+6 block)"
	case .WALL:     return "wilds won't roam across it"
	case .WELL:     return "feeds within 4, +2 (needs water nearby)"
	case .GATE:     return "wilds can't cross; your monsters can"
	case .SPIKE_TRAP: return "wilds standing here take 8 dmg/turn"
	case .SCARECROW: return "cheap; keeps spawns out (r2), spooks wilds (r3)"
	case .ROAD:     return "monsters cross for half the energy"
	case .SILO:     return "extra food storage"
	case .CRYSTAL_REFINERY: return "spends 15 gold/turn to make 1 crystal"
	case .FOUNTAIN: return "gives energy to the closest unit or Turret nearby"
	case .TURRET:   return "needs Fountain energy; shoots a wild within 4"
	case .DRAWBRIDGE: return "a Bridge you can raise (blocks wilds) or lower"
	case .QUARRY:   return "staffed: gold to treasury within 4"
	case .LUMBER_MILL: return "staffed: food (needs water nearby)"
	case .MARKETPLACE: return "+50% gold from Mines within 3"
	case .KITCHEN:  return "spends food so defenders start with +2 Str"
	case .BARRACKS: return "heals & grants a little XP (eats 2 food/turn)"
	case .BEACON:   return "reveals 8, deters 5, attacking wilds start Vulnerable"
	}
	return ""
}

// Stackable improvements sit in a tile's `overlay` slot instead of replacing the
// building, so e.g. a Road can be laid under a Farm.
improvement_stacks :: proc(im: Improvement) -> bool {
	return im == .ROAD
}

// Every buildable improvement, in build-panel order (used by the improvements dex).
ALL_IMPROVEMENTS := [?]Improvement{
	.FARM, .MINE, .WELL, .BRIDGE, .GRANARY, .TREASURY, .WATCHTOWER, .WALL,
	.GATE, .SPIKE_TRAP, .SCARECROW, .ROAD, .SILO, .CRYSTAL_REFINERY, .FOUNTAIN,
	.TURRET, .DRAWBRIDGE, .QUARRY, .LUMBER_MILL, .MARKETPLACE, .KITCHEN,
	.BARRACKS, .BEACON,
}

// Grouping shown in the improvements dex header.
improvement_category :: proc(im: Improvement) -> cstring {
	switch im {
	case .FARM, .WELL, .LUMBER_MILL:                                     return "Food"
	case .MINE, .QUARRY, .CRYSTAL_REFINERY, .MARKETPLACE:                return "Gold"
	case .GRANARY, .SILO, .TREASURY:                                     return "Storage"
	case .WALL, .GATE, .DRAWBRIDGE, .SPIKE_TRAP, .SCARECROW, .WATCHTOWER: return "Defense"
	case .BEACON:                                                        return "Defense"
	case .FOUNTAIN, .TURRET:                                             return "Energy"
	case .KITCHEN, .BARRACKS:                                            return "Support"
	case .BRIDGE, .ROAD:                                                 return "Traversal"
	case .NONE:                                                          return "-"
	}
	return "-"
}

// Long-form description for the improvements dex.
improvement_detail :: proc(im: Improvement) -> cstring {
	switch im {
	case .NONE:
		return ""
	case .FARM:
		return "Staffed by one of your monsters standing on the tile. Makes food each turn into a local pool that is delivered to the nearest Granary within 4 tiles; food past the Granary's storage is lost, so pair it with a Granary (or Silo) in range. Wilds will not spawn on a staffed Farm, making it a safe tile to hold."
	case .MINE:
		return "Staffed by a monster on the tile. Produces gold into the nearest Treasury within 4 tiles. A Marketplace within 3 tiles boosts its output by 50%. No wilds spawn while it is staffed. Cheaper and safer than a Quarry, but yields less."
	case .BRIDGE:
		return "Built on Water. Lets your ground monsters cross the water tile, and turns it into a normal traversable hex. Permanent and cheap, but unlike a Drawbridge it can never be raised to block wilds."
	case .GRANARY:
		return "The food hub. Stores food up to the storage cap and feeds every monster within 4 tiles each turn. Farms, Wells and Lumber Mills within 4 deliver their output here. Any food produced without a Granary in range is wasted, so a Granary should anchor every food district."
	case .TREASURY:
		return "Stores gold safely and raises your effective gold cap. Mines and Quarries within 4 tiles deliver their gold here. Placing a Treasury among your mines turns a cluster into real income."
	case .WATCHTOWER:
		return "Reveals tiles within 6, deters wild spawns within 4, and gives defenders within 4 tiles +6 Block at the start of a battle. A solid anchor for a front-line tile you expect to be attacked."
	case .WALL:
		return "Ground wilds cannot move through a Wall (Air types fly over). A wild whose step is blocked by a Wall batters it instead, so even a wall line needs occasional repair — but it reliably channels wilds away from what it protects."
	case .WELL:
		return "Must be built adjacent to Water. Produces a small amount of food each turn into the local pool (delivered to a Granary within 4) and needs no staffing to do it. A cheap top-up for a food district near water."
	case .GATE:
		return "Wilds cannot pass, but your own monsters move through freely. Frailer than a Wall (30 HP) and wilds batter it down faster, so treat a Gate as a door you control rather than a wall."
	case .SPIKE_TRAP:
		return "Any wild standing on the tile loses 8 HP per turn. Cheap, passive attrition for a chokepoint or a tile wilds keep walking over. Your own monsters are unaffected."
	case .SCARECROW:
		return "The cheapest deterrent. Keeps wild spawns out of a 2-tile radius, and spooks wilds within 3 so that, instead of crossing, they step away toward open ground. Best used to keep a quiet pocket around farms and workers."
	case .ROAD:
		return "Stackable — it lives in the tile's overlay slot, so a Road can be laid underneath any building rather than replacing it. Your monsters cross the tile for half the usual energy, which speeds up long hauls and lets a monster cover more ground per turn."
	case .SILO:
		return "Adds extra food storage on top of your Granary capacity. Only useful once your food production outpaces a Granary; place it in your main food district."
	case .CRYSTAL_REFINERY:
		return "Spends 15 gold per turn to produce 1 crystal. Crystals are the end-game progression currency, so a Refinery is how a strong gold economy converts into lasting power. Expect to run a few once your mines are built up."
	case .FOUNTAIN:
		return "Each turn hands 3 energy to the closest monster, or charges the closest Turret within 4 tiles. The heart of an energy network — a Fountain next to a Turret keeps it firing, and one near your workers keeps them moving."
	case .TURRET:
		return "Needs energy from a nearby Fountain. Spends 2 charge to shoot the nearest wild within 4 tiles for 10 damage. Useless on its own — always pair it with a Fountain, and cluster a couple of Turrets around a single one to cover a flank."
	case .DRAWBRIDGE:
		return "Built on Water. Toggle it raised to block wilds or lowered to let your monsters cross. More expensive than a Bridge but reconfigurable, so you can seal a water lane when a raid approaches and reopen it afterward."
	case .QUARRY:
		return "Staffed by a monster on the tile. Produces noticeably more gold than a Mine into the nearest Treasury within 4 tiles. Needs Ruins, Desert or Tundra, so it is the reward for pushing into harsher biomes."
	case .LUMBER_MILL:
		return "Staffed by a monster on the tile and must be built next to Water. Produces food into the local pool (delivered to a Granary within 4). A second food chain alongside Farms for a colony spread across wet terrain."
	case .MARKETPLACE:
		return "Boosts the gold output of every Mine within 3 tiles by 50%. It produces nothing itself, so place it in the middle of a mining cluster to multiply several mines at once."
	case .KITCHEN:
		return "At the start of a battle, spends 6 food from a Granary within 4 tiles to give your defenders +2 Strength for the whole fight. A pre-battle buff you pay for with food, so keep a stocked Granary near the front line."
	case .BARRACKS:
		return "Eats 2 food per turn from a nearby Granary and, if fed, heals your monsters and grants a little XP each turn. A training and recovery hub — park wounded monsters beside it between fights."
	case .BEACON:
		return "The strongest lookout. Reveals tiles within 8, deters wild spawns within 5, and makes wilds attacking within 5 tiles start the battle Vulnerable (taking +50% damage). A great forward base for pushing into dangerous ground."
	}
	return ""
}

Tile :: struct {
	hex:            Hex,
	terrain:        Terrain,
	revealed:       bool,
	improvement:    Improvement,
	overlay:        Improvement, // a stackable improvement (e.g. Road) on top of the building
	improvement_hp: int,
	stored:         int,   // food (Granary) / gold (Treasury) / charge (Turret)
	scuffle:        int,   // turns a "fight happened here" marker lingers
	hit_t0:         f32,   // rl.GetTime of the last damage (for hit shake/flash)
	drawbridge_down: bool, // false = raised (blocks wilds), true = lowered (bridge)
}

// Does this tile contain the given improvement (as building or overlay)?
tile_has :: proc(t: ^Tile, im: Improvement) -> bool {
	return t.improvement == im || t.overlay == im
}

Monster :: struct {
	id:          int,
	creature:    Creature,
	pos:         Hex,
	wild:     bool,
	food:     f32, // satiation bar 0..100
	genetics: [5]int,
}

// A short-lived floating "+N gold/food" marker at a tile, spawned by the turn
// loop when a producer works. Drawn by draw_tile_floats; ages via rl.GetTime().
Float_Kind :: enum { GOLD, FOOD, FOOD_IN, FOOD_OUT, DAMAGE, CRYSTAL, FLEE, ENERGY }
FLOAT_LIFE :: f32(1.6)
HIT_LIFE   :: f32(0.4) // improvement damage shake/flash duration

Tile_Float :: struct {
	hex:    Hex,
	kind:   Float_Kind,
	amount: int,
	t0:     f32,
}

// A monster offered for sale at a Trading Post.
Shop_Offer :: struct {
	species: int,
	level:   int,
	price:   int,
}

Colony :: struct {
	tiles:      [dynamic]^Tile, // materialized tiles (the map extends on demand)
	tile_index: map[u64]int,    // hex key -> index into tiles
	roster:     [dynamic]Monster,
	graveyard:  [dynamic]Monster,
	width:      int,
	height:     int,
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
	floats:    [dynamic]Tile_Float, // transient production popups
	shop:      [dynamic]Shop_Offer, // Trading Post stock, rerolled each turn
	shop_turn: int,                 // turn the current stock belongs to
	items:     [dynamic]Item,       // unequipped item inventory
}

// ----------------------------------------------------------------------------
// Grid helpers
// ----------------------------------------------------------------------------

hex_key :: proc(h: Hex) -> u64 {
	return u64(u32(h.q)) << 32 | u64(u32(h.r))
}

// The underground is infinite; tiles are generated on demand. tile_at only
// looks up already-materialized tiles (returns nil for the unknown).
tile_at :: proc(c: ^Colony, hex: Hex) -> ^Tile {
	if idx, ok := c.tile_index[hex_key(hex)]; ok {
		return c.tiles[idx]
	}
	return nil
}

// Materializes a tile (deterministic terrain from the colony seed) if needed.
ensure_tile :: proc(c: ^Colony, hex: Hex) -> ^Tile {
	if t := tile_at(c, hex); t != nil {
		return t
	}
	t := new(Tile)
	t^ = Tile{hex = hex, terrain = pick_terrain_at(c.seed, c.start_hex, hex)}
	c.tile_index[hex_key(hex)] = len(c.tiles)
	append(&c.tiles, t)
	return t
}

// Generate every tile within `radius` of `center` (hex range).
materialize_around :: proc(c: ^Colony, center: Hex, radius: int) {
	for dq in -radius..=radius {
		lo := max(-radius, -dq - radius)
		hi := min(radius, -dq + radius)
		for dr in lo..=hi {
			_ = ensure_tile(c, Hex{q = center.q + dq, r = center.r + dr})
		}
	}
}

colony_reveal_around :: proc(c: ^Colony, hex: Hex) {
	if t := ensure_tile(c, hex); t != nil {
		t.revealed = true
	}
	for n in hex_neighbors(hex) {
		if t := ensure_tile(c, n); t != nil {
			t.revealed = true
		}
	}
	// Ensure one ring further out so unexplored tiles render as fog.
	for n in hex_neighbors(hex) {
		for nn in hex_neighbors(n) {
			_ = ensure_tile(c, nn)
		}
	}
}

colony_reveal_radius :: proc(c: ^Colony, center: Hex, radius: int) {
	for dq in -radius..=radius {
		lo := max(-radius, -dq - radius)
		hi := min(radius, -dq + radius)
		for dr in lo..=hi {
			if t := ensure_tile(c, Hex{q = center.q + dq, r = center.r + dr}); t != nil {
				t.revealed = true
			}
		}
	}
}

near_improvement :: proc(c: ^Colony, hex: Hex, radius: int, im: Improvement) -> bool {
	for t in c.tiles {
		if tile_has(t, im) && hex_distance(t.hex, hex) <= radius {
			return true
		}
	}
	return false
}

nearest_improvement_within :: proc(c: ^Colony, from: Hex, radius: int, im: Improvement) -> int {
	best := -1
	best_d := 1 << 30
	for i in 0..<len(c.tiles) {
		if !tile_has(c.tiles[i], im) {
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

// A tile any starter can stand on (no type-locked traversal needed).
neutral_terrain :: proc(t: Terrain) -> bool {
	#partial switch t {
	case .WATER, .TUNDRA, .JUNGLE, .LAVA, .QUICKSAND, .BOSS_ROOM:
		return false
	}
	return true
}

// Pick the entrance in the most open, neutral spot near the origin, so no
// starter can be boxed in by terrain it can't cross.
choose_start_hex :: proc(seed: u64) -> Hex {
	best := Hex{0, 0}
	best_open := -1
	best_dist := 1 << 30
	for dq in -6..=6 {
		for dr in max(-6, -dq - 6)..=min(6, -dq + 6) {
			h := Hex{dq, dr}
			if !neutral_terrain(biome_at(seed, h)) {
				continue
			}
			open := 0
			for eq in -3..=3 {
				for er in max(-3, -eq - 3)..=min(3, -eq + 3) {
					if neutral_terrain(biome_at(seed, Hex{h.q + eq, h.r + er})) {
						open += 1
					}
				}
			}
			d := hex_distance(Hex{0, 0}, h)
			if open > best_open || (open == best_open && d < best_dist) {
				best_open = open
				best_dist = d
				best = h
			}
		}
	}
	return best
}

// Guarantees the entrance is workable and that the type-locked biomes are
// reachable early (so Ice/Flora/Ember/Ground content isn't walled off).
Start_Seed :: struct {
	dir:     int,
	dist:    int,
	terrain: Terrain,
}

seed_starting_area :: proc(c: ^Colony) {
	// Clear the entrance chamber of anything a starter can't cross.
	for dq in -2..=2 {
		for dr in max(-2, -dq - 2)..=min(2, -dq + 2) {
			if t := ensure_tile(c, Hex{c.start_hex.q + dq, c.start_hex.r + dr}); t != nil {
				if !neutral_terrain(t.terrain) {
					t.terrain = .CAVE
				}
			}
		}
	}
	// A single taste of each gated terrain just outside the clearing.
	seeds := [?]Start_Seed{
		{1, 4, .TUNDRA},
		{5, 4, .JUNGLE},
		{2, 4, .LAVA},
		{4, 4, .QUICKSAND},
		{0, 5, .GROVE},
		{3, 5, .WATER},
	}
	for s in seeds {
		h := hex_add(c.start_hex, hex_scale(HEX_DIRECTIONS[s.dir], s.dist))
		if t := ensure_tile(c, h); t != nil {
			t.terrain = s.terrain
		}
	}
}

colony_generate :: proc(seed: u64, width, height: int) -> Colony {
	c := Colony{
		width          = width,
		height         = height,
		seed           = seed,
		floor          = 1,
		gold           = 40,
		crystals       = 0,
		capture_cards  = STARTING_CAPTURE_CARDS,
	}
	c.rng = rng_make(seed)
	c.tiles = make([dynamic]^Tile, 0)
	c.tile_index = make(map[u64]int)
	c.roster = make([dynamic]Monster, 0)
	c.graveyard = make([dynamic]Monster, 0)
	c.pending_tiles = make([dynamic]Hex, 0)
	c.next_id = 1
	c.messages = make([dynamic]string, 0)
	c.floats = make([dynamic]Tile_Float, 0)
	c.shop = make([dynamic]Shop_Offer, 0)
	c.items = make([dynamic]Item, 0)

	// Choose an open, neutral entrance; the underground extends without bound.
	c.start_hex = choose_start_hex(seed)
	if start := ensure_tile(&c, c.start_hex); start != nil {
		start.terrain = .CAVE
	}

	// Make sure the entrance isn't boxed in by water.
	has_exit := false
	for n in hex_neighbors(c.start_hex) {
		if t := ensure_tile(&c, n); t != nil && t.terrain != .WATER {
			has_exit = true
			break
		}
	}
	if !has_exit {
		if t := ensure_tile(&c, hex_add(c.start_hex, HEX_DIRECTIONS[5])); t != nil {
			t.terrain = .CAVE
		}
	}

	colony_recompute_caps(&c)
	materialize_around(&c, c.start_hex, SIM_DISTANCE)
	seed_starting_area(&c)
	colony_reveal_around(&c, c.start_hex)
	colony_roll_shop(&c)
	return c
}

pick_terrain :: proc(rng: ^Rng) -> Terrain {
	r := rng_f32(rng)
	if r < 0.30 { return .CAVE }
	if r < 0.42 { return .WATER }
	if r < 0.52 { return .DUNGEON }
	if r < 0.64 { return .GROVE }
	if r < 0.72 { return .MUSHROOM }
	if r < 0.80 { return .RUINS }
	if r < 0.87 { return .TUNDRA }
	if r < 0.93 { return .DESERT }
	if r < 0.96 { return .JUNGLE }
	if r < 0.985 { return .LAVA }
	return .QUICKSAND
}

// ----------------------------------------------------------------------------
// Coherent terrain: value-noise fBm so biomes form contiguous regions instead
// of per-tile static. Fully deterministic in (seed, hex).
// ----------------------------------------------------------------------------

TERRAIN_SCALE :: f32(0.09)

lattice_hash :: proc(seed: u64, ix, iy: i64) -> f32 {
	r := rng_make(seed ~ (u64(ix) * 0x9E3779B97F4A7C15) ~ (u64(iy) * 0xD1B54A32D192ED03))
	return rng_f32(&r)
}

smoothstep :: proc(t: f32) -> f32 {
	return t * t * (3.0 - 2.0 * t)
}

lerp32 :: proc(a, b, t: f32) -> f32 {
	return a + (b - a) * t
}

value_noise :: proc(seed: u64, x, y: f32) -> f32 {
	x0 := i64(math.floor(x))
	y0 := i64(math.floor(y))
	tx := smoothstep(x - f32(x0))
	ty := smoothstep(y - f32(y0))
	v00 := lattice_hash(seed, x0, y0)
	v10 := lattice_hash(seed, x0 + 1, y0)
	v01 := lattice_hash(seed, x0, y0 + 1)
	v11 := lattice_hash(seed, x0 + 1, y0 + 1)
	return lerp32(lerp32(v00, v10, tx), lerp32(v01, v11, tx), ty)
}

fbm :: proc(seed: u64, x, y: f32, octaves: int) -> f32 {
	amp := f32(0.5)
	freq := f32(1.0)
	sum := f32(0)
	norm := f32(0)
	for i in 0..<octaves {
		sum += amp * value_noise(seed + u64(i) * 0x9E3779B97F4A7C15, x * freq, y * freq)
		norm += amp
		amp *= 0.5
		freq *= 2.0
	}
	return sum / norm
}

// Biome from elevation + moisture noise. Rare lava/quicksand pockets sit on top.
biome_at :: proc(seed: u64, hex: Hex) -> Terrain {
	// Flat-top hex -> world space so the noise is isotropic.
	x := 1.5 * f32(hex.q)
	y := 1.7320508 * (f32(hex.r) + 0.5 * f32(hex.q))

	an := fbm(seed ~ 0xC0FFEE, x * 0.42, y * 0.42, 3)
	if an > 0.87 { return .LAVA }
	if an < 0.09 { return .QUICKSAND }

	e := fbm(seed ~ 0xA5A5A5A5A5A5A5A5, x * TERRAIN_SCALE, y * TERRAIN_SCALE, 4)
	m := fbm(seed ~ 0x123456789ABCDEF0, x * TERRAIN_SCALE + 37.0, y * TERRAIN_SCALE + 91.0, 3)

	if e < 0.30 { return .WATER }
	if e < 0.42 { return .CAVE }
	if e < 0.70 {
		switch {
		case m < 0.28: return .DUNGEON
		case m < 0.50: return .GROVE
		case m < 0.58: return .MUSHROOM
		case m < 0.84: return .JUNGLE
		case:          return .GROVE
		}
	}
	if e < 0.86 {
		switch {
		case m < 0.30: return .RUINS
		case m < 0.50: return .DESERT
		case m < 0.72: return .TUNDRA
		case:          return .RUINS
		}
	}
	if m < 0.5 { return .TUNDRA }
	return .RUINS
}

// Deterministic per-hex terrain. Trading posts and boss rooms are scattered on
// top of the biomes, relative to the entrance, so they must be found by exploring.
pick_terrain_at :: proc(seed: u64, origin: Hex, hex: Hex) -> Terrain {
	h := hex_key(hex)
	dist := hex_distance(origin, hex)
	special := rng_make(seed ~ (h * 0xD1B54A32D192ED03))
	if dist >= 2 && rng_f32(&special) < 0.015 {
		return .TRADING_POST
	}
	if dist >= 6 && rng_f32(&special) < 0.008 {
		return .BOSS_ROOM
	}
	return biome_at(seed, hex)
}

colony_free :: proc(c: ^Colony) {
	for i in 0..<len(c.roster) {
		creature_free_all(&c.roster[i].creature)
	}
	for i in 0..<len(c.graveyard) {
		creature_free_all(&c.graveyard[i].creature)
	}
	for t in c.tiles {
		free(t)
	}
	delete(c.roster)
	delete(c.graveyard)
	delete(c.tiles)
	delete(c.tile_index)
	delete(c.pending_tiles)
	delete(c.floats)
	delete(c.shop)
	delete(c.items)
	for s in c.messages {
		delete(s)
	}
	delete(c.messages)
	c.roster = make([dynamic]Monster, 0)
	c.graveyard = make([dynamic]Monster, 0)
	c.tiles = make([dynamic]^Tile, 0)
	c.tile_index = make(map[u64]int)
	c.pending_tiles = make([dynamic]Hex, 0)
	c.messages = make([dynamic]string, 0)
	c.floats = make([dynamic]Tile_Float, 0)
	c.shop = make([dynamic]Shop_Offer, 0)
	c.items = make([dynamic]Item, 0)
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
	m.creature.xp += amount
	leveled := false
	for m.creature.xp >= xp_to_next(m.creature.level) {
		m.creature.xp -= xp_to_next(m.creature.level)
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
	// Movement and card-play share one energy pool, so a step is cheap.
	return terrain_move_cost(t) * factor * 0.5
}

// Step cost to a specific tile, including a Road's discount.
monster_step_cost :: proc(c: ^Colony, m: ^Monster, hex: Hex) -> f32 {
	t := tile_at(c, hex)
	if t == nil {
		return 99
	}
	cost := monster_move_cost(m, t.terrain)
	if tile_has(t, .ROAD) {
		cost *= ROAD_MOVE_FACTOR
	}
	return cost
}

tile_passable :: proc(c: ^Colony, m: ^Monster, hex: Hex) -> bool {
	t := tile_at(c, hex)
	if t == nil {
		return false
	}
	#partial switch t.terrain {
	case .WATER:
		if t.improvement == .DRAWBRIDGE {
			if m.wild && !t.drawbridge_down {
				return false // raised drawbridge keeps wilds out
			}
		} else if t.improvement != .BRIDGE && !creature_has_element(&m.creature, .AQUA) {
			return false
		}
	case .TUNDRA:
		if !creature_has_element(&m.creature, .ICE) {
			return false
		}
	case .JUNGLE:
		if !creature_has_element(&m.creature, .FLORA) {
			return false
		}
	case .LAVA:
		if !creature_has_element(&m.creature, .EMBER) {
			return false
		}
	case .QUICKSAND:
		if !creature_has_element(&m.creature, .GROUND) {
			return false
		}
	case:
	}
	// Walls block movement, but Air types fly over them.
	if t.improvement == .WALL && !creature_has_element(&m.creature, .AIR) {
		return false
	}
	// Gates block wilds entirely, but your own monsters pass freely.
	if t.improvement == .GATE && m.wild {
		return false
	}
	return true
}

// Improvements that stop a wild's step (so it may batter them instead of
// walking around). Air monsters fly over Walls, so callers check passability
// first.
improvement_blocks_wilds :: proc(t: ^Tile) -> bool {
	#partial switch t.improvement {
	case .WALL, .GATE:
		return true
	case .DRAWBRIDGE:
		return !t.drawbridge_down
	}
	return false
}

// Human-readable reason a move is blocked, for the status line. tile_passable
// returns a single "blocked" result, so explain it from the tile itself.
move_block_reason :: proc(c: ^Colony, m: ^Monster, hex: Hex) -> cstring {
	t := tile_at(c, hex)
	if t == nil {
		return "Can't move there."
	}
	#partial switch t.terrain {
	case .WATER:
		if t.improvement != .BRIDGE {
			return "Blocked: water needs an Aqua monster or a Bridge."
		}
	case .TUNDRA:
		return "Blocked: Tundra is Ice-only."
	case .JUNGLE:
		return "Blocked: Jungle is Flora-only."
	case .LAVA:
		return "Blocked: Lava is Ember-only."
	case .QUICKSAND:
		return "Blocked: Quicksand is Ground-only."
	}
	if t.improvement == .GATE && m.wild {
		return "Blocked: a Gate keeps wilds out."
	}
	if t.improvement == .WALL {
		return "Blocked: a Wall stops ground monsters (Air can fly over)."
	}
	return "Blocked."
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
	cost := monster_step_cost(c, m, target)
	if m.creature.energy < cost {
		return 4
	}
	m.creature.energy -= cost
	m.pos = target
	colony_reveal_around(c, target)
	return 0
}

// ----------------------------------------------------------------------------
// Improvements
// ----------------------------------------------------------------------------

// 0 ok, 1 invalid terrain / placement, 3 not enough gold.
// Building the same improvement repeatedly gets pricier, so the early colony is
// cheap to start. Building on an already-improved tile replaces what's there
// (its stored contents are lost).
adjacent_to_water :: proc(c: ^Colony, hex: Hex) -> bool {
	for n in hex_neighbors(hex) {
		if t := tile_at(c, n); t != nil && t.terrain == .WATER {
			return true
		}
	}
	return false
}

// Whether an improvement can be placed here (terrain + extra placement rules).
can_build :: proc(c: ^Colony, hex: Hex, im: Improvement) -> bool {
	t := tile_at(c, hex)
	if t == nil || !improvement_valid_on(im, t.terrain) {
		return false
	}
	if (im == .WELL || im == .LUMBER_MILL) && !adjacent_to_water(c, hex) {
		return false
	}
	if improvement_stacks(im) && t.overlay == im {
		return false // already stacked here
	}
	return true
}

// Counts only improvements that currently stand (building or overlay). Destroyed
// ones are reset to `.NONE`, so a replacement after a raid costs the same as
// building a fresh one would have.
improvement_count :: proc(c: ^Colony, im: Improvement) -> int {
	n := 0
	for t in c.tiles {
		if tile_has(t, im) {
			n += 1
		}
	}
	return n
}

improvement_cost_scaled :: proc(c: ^Colony, im: Improvement) -> int {
	base := improvement_cost(im)
	return base + (base * improvement_count(c, im)) / improvement_cost_divisor(im)
}

// Repeated builds get pricier; how fast depends on the improvement. Walls are
// meant to be built in bulk, so their price climbs slowly.
improvement_cost_divisor :: proc(im: Improvement) -> int {
	#partial switch im {
	case .WALL, .GATE, .ROAD, .SCARECROW, .SPIKE_TRAP:
		return 6 // built in bulk; price climbs slowly
	}
	return 3
}

colony_build :: proc(c: ^Colony, hex: Hex, im: Improvement) -> int {
	t := tile_at(c, hex)
	if !can_build(c, hex, im) {
		return 1
	}
	cost := improvement_cost_scaled(c, im)
	if !colony_spend_gold(c, cost) {
		return 3
	}
	if improvement_stacks(im) {
		// Stackable (Road): lay it in the overlay slot, keep the building.
		t.overlay = im
		return 0
	}
	// Replaces the building (stored contents are lost); a Road overlay survives.
	t.improvement = im
	t.improvement_hp = improvement_max_hp(im)
	t.stored = 0
	colony_recompute_caps(c)
	return 0
}

buildable_improvements :: proc(c: ^Colony, hex: Hex, out: []Improvement) -> int {
	n := 0
	for im in Improvement {
		if im != .NONE && can_build(c, hex, im) {
			if n < len(out) {
				out[n] = im
			}
			n += 1
		}
	}
	return n
}

// Repairs cost half the improvement's base cost when fully damaged, prorated by
// the missing HP. Repairs never scale with how many you own.
improvement_repair_cost :: proc(im: Improvement, hp: int) -> int {
	max_hp := improvement_max_hp(im)
	if im == .NONE || max_hp <= 0 || hp >= max_hp {
		return 0
	}
	missing := max_hp - hp
	return max(1, (improvement_cost(im) * missing) / (2 * max_hp))
}

// 0 ok, 1 nothing to repair, 2 not enough gold.
colony_repair :: proc(c: ^Colony, hex: Hex) -> int {
	t := tile_at(c, hex)
	if t == nil || t.improvement == .NONE || t.improvement_hp >= improvement_max_hp(t.improvement) {
		return 1
	}
	cost := improvement_repair_cost(t.improvement, t.improvement_hp)
	if !colony_spend_gold(c, cost) {
		return 2
	}
	t.improvement_hp = improvement_max_hp(t.improvement)
	return 0
}

// Toggle a Drawbridge: raised blocks wilds, lowered acts as a bridge.
colony_toggle_drawbridge :: proc(c: ^Colony, hex: Hex) -> bool {
	t := tile_at(c, hex)
	if t == nil || t.improvement != .DRAWBRIDGE {
		return false
	}
	t.drawbridge_down = !t.drawbridge_down
	return true
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
		t := c.tiles[i]
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
		case .GRANARY, .SILO: food_cap += STORAGE_CAP
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
		t := c.tiles[gi]
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

// Gross per-turn output for the colony HUD (before range/storage limits, so a
// farm with no receiver in range still shows its potential).
colony_food_production :: proc(c: ^Colony) -> int {
	sum := 0
	for t in c.tiles {
		#partial switch t.improvement {
		case .FARM:
			if monsters_on_tile(c, t.hex, false) > 0 {
				sum += FARM_FOOD_YIELD
			}
		case .WELL:
			sum += WELL_FOOD_YIELD
		case:
		}
	}
	return sum
}

colony_gold_production :: proc(c: ^Colony) -> int {
	sum := 0
	for t in c.tiles {
		if t.improvement == .MINE && monsters_on_tile(c, t.hex, false) > 0 {
			sum += MINE_GOLD_YIELD
		}
	}
	return sum
}

// ----------------------------------------------------------------------------
// Trading Post services
// ----------------------------------------------------------------------------

heal_cost :: proc(m: ^Monster) -> int {
	missing := m.creature.max_hp - m.creature.hp
	if missing <= 0 {
		return 0
	}
	return max(missing, 5)
}

energy_cost :: proc(m: ^Monster) -> int {
	return 4
}

revive_cost :: proc(m: ^Monster) -> int {
	return 20 + m.creature.level * 3
}

capture_card_cost :: proc() -> int {
	return 30
}

// 0 ok, 2 not enough gold.
colony_buy_capture_card :: proc(c: ^Colony) -> int {
	if !colony_spend_gold(c, capture_card_cost()) {
		return 2
	}
	c.capture_cards += 1
	return 0
}

// ----------------------------------------------------------------------------
// Trading Post stock: a couple of monsters for sale, rerolled each turn. Which
// species appear (rate) and what they cost (price) both come from their rarity.
// ----------------------------------------------------------------------------

SHOP_SLOTS :: 2

shop_pick_species :: proc(c: ^Colony) -> int {
	total := 0
	for sp in SPECIES {
		total += rarity_weight(sp.rarity)
	}
	if total <= 0 {
		return 0
	}
	roll := rng_below(&c.rng, total)
	acc := 0
	for i in 0..<len(SPECIES) {
		acc += rarity_weight(SPECIES[i].rarity)
		if roll < acc {
			return i
		}
	}
	return 0
}

colony_roll_shop :: proc(c: ^Colony) {
	clear(&c.shop)
	for _ in 0..<SHOP_SLOTS {
		sp := shop_pick_species(c)
		lvl := max(1, 1 + c.turn / 15 + rng_below(&c.rng, 2))
		append(&c.shop, Shop_Offer{species = sp, level = lvl, price = recruit_price(sp, lvl)})
	}
	c.shop_turn = c.turn
}

// First free, passable land tile at the entrance or beside it.
find_placement_tile :: proc(c: ^Colony, m: ^Monster) -> (Hex, bool) {
	if t := tile_at(c, c.start_hex); t != nil && monsters_on_tile(c, c.start_hex, false) < MAX_MONSTERS_PER_TILE && tile_passable(c, m, c.start_hex) {
		return c.start_hex, true
	}
	for n in hex_neighbors(c.start_hex) {
		if t := tile_at(c, n); t != nil && monsters_on_tile(c, n, false) < MAX_MONSTERS_PER_TILE && tile_passable(c, m, n) {
			return n, true
		}
	}
	return c.start_hex, false
}

// 0 ok, 1 bad offer, 2 not enough gold, 3 no room at the entrance.
colony_buy_recruit :: proc(c: ^Colony, offer_index: int) -> int {
	if offer_index < 0 || offer_index >= len(c.shop) {
		return 1
	}
	offer := c.shop[offer_index]
	m := Monster{
		id       = c.next_id,
		creature = creature_make(offer.species, offer.level, SPECIES[offer.species].name, &c.rng),
		pos      = c.start_hex,
	}
	h, room := find_placement_tile(c, &m)
	if !room {
		creature_free_all(&m.creature)
		return 3
	}
	if !colony_spend_gold(c, offer.price) {
		creature_free_all(&m.creature)
		return 2
	}
	m.pos = h
	c.next_id += 1
	m.creature.energy = m.creature.energy_max
	m.food = monster_satiety_max(&m)
	append(&c.roster, m)
	ordered_remove(&c.shop, offer_index)
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
	c.roster[index].creature.energy = c.roster[index].creature.energy_max
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
	m.creature.defense_debuff = 0
	creature_free_piles(&m.creature)
	m.food = monster_satiety_max(&m)
	m.pos = c.start_hex
	m.creature.energy = m.creature.energy_max

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
		im := c.tiles[i].improvement
		if (im == .FARM || im == .WELL) && pools[i] > 0 {
			d := hex_distance(from, c.tiles[i].hex)
			if d <= radius && d < best_d {
				best_d = d
				best = i
			}
		}
	}
	return best
}

// Record a transient production popup at a tile (drawn for FLOAT_LIFE seconds).
colony_add_float :: proc(c: ^Colony, hex: Hex, kind: Float_Kind, amount: int) {
	if amount <= 0 {
		return
	}
	append(&c.floats, Tile_Float{hex = hex, kind = kind, amount = amount, t0 = f32(rl.GetTime())})
	if len(c.floats) > 200 {
		ordered_remove(&c.floats, 0)
	}
}

colony_end_turn :: proc(c: ^Colony) {
	// Drop production popups left over from previous turns.
	{
		now := f32(rl.GetTime())
		i := 0
		for i < len(c.floats) {
			if now - c.floats[i].t0 > FLOAT_LIFE {
				ordered_remove(&c.floats, i)
			} else {
				i += 1
			}
		}
	}

	// farm_pool is parallel to the tile list; watchtower reveals can materialize
	// new tiles, so pin the count we sized against.
	n_tiles := len(c.tiles)
	farm_pool := make([]int, n_tiles)
	defer delete(farm_pool)
	for i in 0..<n_tiles {
		farm_pool[i] = 0
	}

	// 1. Mines & Quarries deliver gold (Marketplace boosts nearby Mines).
	for t in c.tiles {
		if t.improvement != .MINE && t.improvement != .QUARRY {
			continue
		}
		if monsters_on_tile(c, t.hex, false) == 0 {
			continue
		}
		yield := t.improvement == .QUARRY ? QUARRY_GOLD_YIELD : MINE_GOLD_YIELD
		if t.improvement == .MINE && near_improvement(c, t.hex, MARKET_RADIUS, .MARKETPLACE) {
			yield += int(f32(yield) * MARKET_BONUS)
		}
		kept := colony_deposit_gold(c, t.hex, yield)
		if kept > 0 {
			colony_add_float(c, t.hex, .GOLD, kept)
		}
	}

	// 1b. Crystal refineries turn gold into crystals.
	for t in c.tiles {
		if t.improvement != .CRYSTAL_REFINERY {
			continue
		}
		if colony_total_gold(c) >= CRYSTAL_REFINERY_COST && colony_spend_gold(c, CRYSTAL_REFINERY_COST) {
			c.crystals += 1
			colony_add_float(c, t.hex, .CRYSTAL, 1)
		}
	}

	// 2. Farms / Lumber Mills (staffed) and Wells produce a local food pool.
	for i in 0..<n_tiles {
		t := c.tiles[i]
		if t.improvement == .FARM && monsters_on_tile(c, t.hex, false) > 0 {
			farm_pool[i] = FARM_FOOD_YIELD
			colony_add_float(c, t.hex, .FOOD, FARM_FOOD_YIELD)
		} else if t.improvement == .LUMBER_MILL && monsters_on_tile(c, t.hex, false) > 0 {
			farm_pool[i] = LUMBER_FOOD_YIELD
			colony_add_float(c, t.hex, .FOOD, LUMBER_FOOD_YIELD)
		} else if t.improvement == .WELL {
			farm_pool[i] = WELL_FOOD_YIELD
			colony_add_float(c, t.hex, .FOOD, WELL_FOOD_YIELD)
		}
	}

	// Watchtowers & Beacons keep their surroundings revealed.
	for i in 0..<n_tiles {
		t := c.tiles[i]
		if t.improvement == .WATCHTOWER {
			colony_reveal_radius(c, t.hex, WATCHTOWER_REVEAL)
		} else if t.improvement == .BEACON {
			colony_reveal_radius(c, t.hex, BEACON_REVEAL)
		}
	}

	// 3. Farms deliver surplus to a granary within range (else wasted).
	for i in 0..<n_tiles {
		if farm_pool[i] <= 0 {
			continue
		}
		gi := nearest_improvement_within(c, c.tiles[i].hex, DELIVER_RADIUS, .GRANARY)
		if gi >= 0 {
			g := c.tiles[gi]
			move := min(farm_pool[i], STORAGE_CAP - g.stored)
			if move > 0 {
				g.stored += move
				farm_pool[i] -= move
				colony_add_float(c, g.hex, .FOOD_IN, move)
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
			colony_add_float(c, c.tiles[gi].hex, .FOOD_OUT, need)
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

	// 4b. Barracks heal and train nearby monsters (each eats food to run).
	colony_barracks(c, n_tiles)

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
		m.creature.energy = min(m.creature.energy + m.creature.energy_regen, m.creature.energy_max)
		i += 1
	}

	// 6. Wild monsters: spawn near you, roam, wander off, squabble, then act.
	for s in c.messages {
		delete(s)
	}
	clear(&c.messages)

	// Keep the neighbourhood around your monsters loaded (infinite map): enough
	// room to spawn and roam, plus a ring of unexplored fog.
	for m in c.roster {
		if !m.wild {
			materialize_around(c, m.pos, SIM_DISTANCE + 3)
		}
	}

	for i in 0..<len(c.tiles) {
		if c.tiles[i].scuffle > 0 {
			c.tiles[i].scuffle -= 1
		}
	}

	colony_spawn_wilds(c)
	colony_roam_wilds(c)
	colony_despawn_wilds(c)
	colony_crowd_fights(c)
	colony_fountains(c)
	colony_turrets(c)
	colony_apply_traps(c)
	colony_resolve_wild_actions(c)

	// Gold Finder items trickle a little gold each turn.
	for m in c.roster {
		if m.wild || m.creature.hp <= 0 {
			continue
		}
		if amt := ITEM_DATA[m.creature.item].gold_per_turn; amt > 0 {
			c.gold += amt
			colony_add_float(c, m.pos, .GOLD, amt)
		}
	}

	c.turn += 1
	// The Trading Post restocks each turn.
	colony_roll_shop(c)
}

// Barracks: each one eats food from a nearby Granary and, if fed, heals and
// grants a little XP to your monsters nearby.
colony_barracks :: proc(c: ^Colony, n_tiles: int) {
	for i in 0..<n_tiles {
		t := c.tiles[i]
		if t.improvement != .BARRACKS {
			continue
		}
		gi := nearest_improvement_within(c, t.hex, DELIVER_RADIUS, .GRANARY)
		if gi < 0 || c.tiles[gi].stored < BARRACKS_UPKEEP {
			continue // no rations, no training
		}
		c.tiles[gi].stored -= BARRACKS_UPKEEP
		for &m in c.roster {
			if m.wild || m.creature.hp <= 0 {
				continue
			}
			if hex_distance(m.pos, t.hex) <= BARRACKS_RANGE {
				m.creature.hp = min(m.creature.hp + BARRACKS_HEAL, m.creature.max_hp)
				_ = monster_add_xp(&m, BARRACKS_XP)
			}
		}
	}
}

// Fountains hand FOUNTAIN_OUTPUT energy to the closest recipient within range:
// a Turret that needs charge, or one of your monsters that needs energy.
colony_fountains :: proc(c: ^Colony) {
	for i in 0..<len(c.tiles) {
		f := c.tiles[i]
		if f.improvement != .FOUNTAIN {
			continue
		}
		best_d := 1 << 30
		best_turret := -1
		best_monster := -1
		for j in 0..<len(c.tiles) {
			t := c.tiles[j]
			if t.improvement != .TURRET || t.stored >= TURRET_CAP {
				continue
			}
			d := hex_distance(f.hex, t.hex)
			if d <= FOUNTAIN_RANGE && d < best_d {
				best_d = d
				best_turret = j
			}
		}
		for k in 0..<len(c.roster) {
			m := &c.roster[k]
			if m.wild || m.creature.hp <= 0 || m.creature.energy >= m.creature.energy_max {
				continue
			}
			d := hex_distance(f.hex, m.pos)
			if d <= FOUNTAIN_RANGE && d < best_d {
				best_d = d
				best_turret = -1
				best_monster = k
			}
		}
		if best_turret >= 0 {
			c.tiles[best_turret].stored = min(TURRET_CAP, c.tiles[best_turret].stored + FOUNTAIN_OUTPUT)
		} else if best_monster >= 0 {
			m := &c.roster[best_monster]
			m.creature.energy = min(m.creature.energy_max, m.creature.energy + f32(FOUNTAIN_OUTPUT))
			colony_add_float(c, m.pos, .ENERGY, FOUNTAIN_OUTPUT)
		}
	}
}

// Turrets spend stored charge to shoot the nearest wild in range.
colony_turrets :: proc(c: ^Colony) {
	for i in 0..<len(c.tiles) {
		t := c.tiles[i]
		if t.improvement != .TURRET || t.stored < TURRET_COST {
			continue
		}
		best_d := 1 << 30
		best_w := -1
		for k in 0..<len(c.roster) {
			m := c.roster[k]
			if !m.wild || m.creature.hp <= 0 {
				continue
			}
			d := hex_distance(t.hex, m.pos)
			if d <= TURRET_RANGE && d < best_d {
				best_d = d
				best_w = k
			}
		}
		if best_w < 0 {
			continue
		}
		t.stored -= TURRET_COST
		w := &c.roster[best_w]
		w.creature.hp -= TURRET_DAMAGE
		colony_add_float(c, w.pos, .DAMAGE, TURRET_DAMAGE)
		if w.creature.hp <= 0 {
			remove_monster_at(c, best_w, false)
		}
	}
}

// Spike traps wound any wild standing on them (they can die to the spikes).
colony_apply_traps :: proc(c: ^Colony) {
	i := 0
	for i < len(c.roster) {
		m := &c.roster[i]
		if m.wild {
			if t := tile_at(c, m.pos); t != nil && t.improvement == .SPIKE_TRAP {
				m.creature.hp -= SPIKE_TRAP_DAMAGE
				colony_add_float(c, m.pos, .DAMAGE, SPIKE_TRAP_DAMAGE)
				if m.creature.hp <= 0 {
					remove_monster_at(c, i, false)
					continue
				}
			}
		}
		i += 1
	}
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

spawn_species_for :: proc(t: Terrain, rng: ^Rng) -> int {
	#partial switch t {
	case .CAVE:
		r := rng_f32(rng)
		if r < 0.30 { return 9 }  // Gloomling
		if r < 0.50 { return 13 } // Wispling
		return 3
	case .GROVE:
		r := rng_f32(rng)
		if r < 0.30 { return 12 } // Swampbeast
		if r < 0.50 { return 16 } // Mosshide
		return 6
	case .WATER:
		r := rng_f32(rng)
		if r < 0.22 { return 11 } // Krakling
		if r < 0.40 { return 15 } // Rimescale
		if r < 0.58 { return 18 } // Bogfang
		if r < 0.72 { return 20 } // Frostmoss
		return 5
	case .DUNGEON:
		r := rng_f32(rng)
		if r < 0.12 { return 7 }  // elite
		if r < 0.34 { return 10 } // Pyrelord
		if r < 0.54 { return 14 } // Cindermaw
		if r < 0.72 { return 17 } // Emberbloom
		return 4
	case .MUSHROOM:
		r := rng_f32(rng)
		if r < 0.28 { return 16 } // Mosshide
		if r < 0.52 { return 12 } // Swampbeast
		if r < 0.72 { return 20 } // Frostmoss
		return 6
	case .RUINS:
		r := rng_f32(rng)
		if r < 0.28 { return 13 } // Wispling
		if r < 0.52 { return 9 }  // Gloomling
		if r < 0.72 { return 19 } // Cinderwing
		return 4
	case .TUNDRA:
		r := rng_f32(rng)
		if r < 0.35 { return 21 } // Frostfang
		if r < 0.60 { return 26 } // Blizzard
		if r < 0.80 { return 24 } // Galebeast
		return 21
	case .JUNGLE:
		r := rng_f32(rng)
		if r < 0.35 { return 25 } // Venomtail
		if r < 0.65 { return 12 } // Swampbeast
		return 16 // Mosshide
	case .LAVA:
		r := rng_f32(rng)
		if r < 0.30 { return 10 } // Pyrelord
		if r < 0.60 { return 14 } // Cindermaw
		return 4 // Magmite
	case .DESERT:
		r := rng_f32(rng)
		if r < 0.35 { return 22 } // Stonepaw
		if r < 0.65 { return 23 } // Sparkit
		return 4 // Magmite
	case .QUICKSAND:
		return 22 // Stonepaw
	case .BOSS_ROOM: return 8
	case:           return 3
	}
}

spawn_level_for :: proc(c: ^Colony, hex: Hex) -> int {
	// Weaker near the entrance, tougher the further out you are.
	dist := hex_distance(c.start_hex, hex)
	return 1 + c.floor / 2 + dist / 4 + rng_below(&c.rng, 2)
}

spawn_wild_at :: proc(c: ^Colony, hex: Hex, species: int, level: int) {
	m := Monster{
		id       = c.next_id,
		creature = creature_make(species, level, SPECIES[species].name, &c.rng),
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
		t := c.tiles[i]
		if tile_prevents_spawn(t) {
			continue
		}
		if monsters_on_tile(c, t.hex, false) > 0 {
			continue // guarded
		}
		if near_improvement(c, t.hex, WATCHTOWER_DETER, .WATCHTOWER) {
			continue // watchtowers deter spawns
		}
		if near_improvement(c, t.hex, BEACON_DETER, .BEACON) {
			continue // beacons deter over a wider area
		}
		if near_improvement(c, t.hex, SCARECROW_DETER, .SCARECROW) {
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
		// Scarecrows spook nearby wilds — they bolt away from it rather than
		// vanishing outright. Tougher monsters are more likely to shrug it off.
		if near_improvement(c, m.pos, SCARECROW_PANIC, .SCARECROW) {
			panic := clamp(SCARECROW_PANIC_CHANCE - f32(m.creature.level) * 0.06, 0.05, SCARECROW_PANIC_CHANCE)
			if rng_f32(&c.rng) < panic {
				if sc_i := nearest_improvement_within(c, m.pos, SCARECROW_PANIC, .SCARECROW); sc_i >= 0 {
					sc := c.tiles[sc_i].hex
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
// way past or is wrecking one it's standing on.
wild_improvement_damage :: proc(m: ^Monster) -> int {
	return 6 + m.creature.level * 3
}

damage_improvement :: proc(c: ^Colony, t: ^Tile, dmg: int) {
	if t.improvement == .NONE {
		return
	}
	t.improvement_hp -= dmg
	t.hit_t0 = f32(rl.GetTime())
	colony_add_float(c, t.hex, .DAMAGE, dmg)
	if t.improvement_hp <= 0 {
		// Destroyed: contents are lost.
		colony_notify(c, "Wilds destroyed your %s!", improvement_name(t.improvement))
		t.stored = 0
		t.improvement = .NONE
		t.improvement_hp = 0
		colony_recompute_caps(c)
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
		if t := tile_at(c, m.pos); t != nil && t.improvement != .NONE {
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
	creature_free_piles(&m.creature)
	m.food = monster_satiety_max(m)
	m.creature.energy = m.creature.energy_max
	return true
}

// ----------------------------------------------------------------------------
// Spawning the player's first monster
// ----------------------------------------------------------------------------

colony_add_starter :: proc(c: ^Colony, species_idx: int) -> int {
	m := Monster{
		id       = c.next_id,
		creature = creature_make(species_idx, 1, SPECIES[species_idx].name, &c.rng),
		pos      = c.start_hex,
	}
	c.next_id += 1
	m.creature.energy = m.creature.energy_max
	m.food = monster_satiety_max(&m)
	append(&c.roster, m)
	return len(c.roster) - 1
}
