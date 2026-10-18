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
//     food store (Granary/Silo) within 4 tiles, spilling over to the next store
//     in range when one fills (only food past every store is wasted).
//   - Granaries/Silos store food and feed your monsters within 4 tiles.
//   - Mines deliver gold to a Treasury within 4 tiles (overflow is wasted).
//   - Treasury gold counts toward your spendable gold. A destroyed granary or
//     treasury loses its contents (handled in Phase 3).
// ============================================================================

Terrain :: enum { CAVE, WATER, DUNGEON, GROVE, TRADING_POST, BOSS_ROOM, MUSHROOM, RUINS, TUNDRA, JUNGLE, LAVA, DESERT, QUICKSAND, ARENA, CRYSTAL_COVE }
Improvement :: enum { NONE, FARM, MINE, BRIDGE, GRANARY, TREASURY, WATCHTOWER, WALL, WELL, GATE, SPIKE_TRAP, SCARECROW, ROAD, SILO, CRYSTAL_REFINERY, FOUNTAIN, TURRET, DRAWBRIDGE, QUARRY, LUMBER_MILL, MARKETPLACE, KITCHEN, BARRACKS, BEACON, DEN, VAULT, NURSERY, MENDER, RELIC_TOWER, WARD_STONE, TRAINING_YARD, CALTROPS, BATTERY }

MAX_MONSTERS_PER_TILE :: 6
REFILL_FRAC           :: f32(0.5) // of max satiation gained per fed turn
STARVE_FRAC           :: f32(0.3) // of max satiation lost per starving turn
STORAGE_CAP           :: 100
BASE_GOLD_CAP         :: 100 // the stockpile's own cap; treasuries add storage beyond it
STARTING_CAPTURE_CARDS :: 3   // capture cards you begin the run with
FEED_RADIUS           :: 4
DELIVER_RADIUS        :: 4
MAX_WILDS              :: 42
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
SPIKE_TRAP_DAMAGE_PCT  :: f32(0.15) // HP a wild loses per turn on a Spike Trap (of its max HP)
CALTROPS_DAMAGE_PCT    :: f32(0.24) // Caltrops bite harder than a Spike Trap
WARD_STONE_RANGE       :: 4         // tiles a Ward Stone widens towers within
WARD_STONE_BONUS       :: 2         // extra relic radius per Ward Stone
TRAINING_YARD_XP       :: 8         // XP a monster standing on a Training Yard gains per turn
BATTERY_CAP            :: 40        // charge a Battery can hold
BATTERY_RANGE          :: 4         // tiles a Battery links to Fountains and Turrets
SCARECROW_DETER        :: 2    // radius a Scarecrow keeps spawns out of
SCARECROW_PANIC        :: 3    // radius a Scarecrow makes wilds likelier to flee
SCARECROW_PANIC_CHANCE :: f32(0.5)
CRYSTAL_REFINERY_COST  :: 20   // gold spent per crystal refined
CRYSTAL_REFINERY_PERIOD :: 6   // turns a Refinery takes to make one crystal (slow!)
ROAD_MOVE_FACTOR       :: f32(0.5)
MOVE_STEP_FACTOR       :: f32(0.8) // global multiplier on every step's cost
// Phase B — energy network + builders
FOUNTAIN_RANGE         :: 4    // a Fountain supplies the closest recipient in range
FOUNTAIN_OUTPUT        :: 3    // energy handed out per turn
TURRET_RANGE           :: 4    // a Turret shoots the nearest wild in range
TURRET_DAMAGE          :: 10
TURRET_COST            :: 2    // charge spent per shot
TURRET_CAP             :: 6    // max charge a Turret can hold
TURRET_SPLASH_DAMAGE   :: 5    // splash per Shrapnel Rounds level
// Phase 15 — energy-powered repairs.
MENDER_REPAIR_RANGE    :: 4    // radius the Mender mends improvements within
MENDER_COST            :: 1    // charge spent per turn of mending
MENDER_CAP             :: 6    // max charge a Mender can hold
MENDER_HEAL            :: 1    // HP restored per improvement per turn
MARKET_RADIUS          :: 3    // a Marketplace boosts Mines within this radius
MARKET_BONUS           :: f32(0.5)
QUARRY_GOLD_YIELD      :: 5
LUMBER_FOOD_YIELD      :: 5
KITCHEN_RADIUS         :: 4    // a Kitchen buffs defenders near the fight
KITCHEN_FOOD_COST      :: 6
KITCHEN_STRENGTH       :: 2
BARRACKS_RANGE         :: 4
BARRACKS_UPKEEP        :: 2    // food consumed per turn
BARRACKS_HEAL_PCT      :: f32(0.08) // Barracks heals this fraction of max HP per turn
BARRACKS_XP            :: 1
BEACON_REVEAL          :: 8
BEACON_DETER           :: 5
BEACON_GUARD           :: 5
BEACON_VULN            :: 2    // Vulnerable applied to wilds attacking near a Beacon

// Arena (Phase C): pay gold to fight a strong team of 6 for crystals.
ARENA_ENTRY_COST       :: 40
ARENA_TEAM_SIZE        :: 6
ARENA_LEVEL_BONUS      :: 2
ARENA_CRYSTAL_REWARD   :: 12
// The Arena is a *run*: one flat entry fee buys a chain of floors, starting at
// floor 1 every time. Each cleared floor banks its purse; the run ends when you
// cash out (keeping the winnings) or when your party wipes (losing them).
ARENA_BASE_LEVEL      :: 4   // floor 1 challengers start around here
ARENA_LEVEL_PER_FLOOR :: 1   // each floor adds a level
ARENA_TEAM_BASE       :: 2   // challengers on floor 1
ARENA_TEAM_PER_FLOOR  :: 8   // +1 challenger per this many floors (up to ARENA_TEAM_SIZE)
ARENA_PURSE_PER_FLOOR :: 2   // crystals a floor banks per floor number
ARENA_GOLD_PER_FLOOR  :: 25  // gold a cleared floor pays, on top of kill loot
ARENA_HEAL_PCT        :: f32(0.25) // of max HP, when a heal floor comes round
BOSS_CRYSTAL_REWARD    :: 6

// Phase 10 — storage & breeding buildings.
DEN_CAPACITY           :: 32   // monsters a Den holds in stasis (no upkeep)
DEN_CAPACITY_PER_LEVEL :: 8    // extra Den capacity per Deep Dens level
STORE_RANGE            :: 1    // within this range of a Den/Nursery to store/assign
BASE_ITEM_CAP          :: 8    // item slots without a Vault
VAULT_ITEM_CAP         :: 12   // extra item slots per Vault
VAULT_CAP_PER_LEVEL    :: 4    // extra item slots per Strongboxes level
NURSERY_PARENTS        :: 2    // monsters a Nursery breeds (the pair)
NURSERY_BABIES         :: 4    // babies a Nursery stores
NURSERY_FOOD_PER_TURN  :: 2    // food a breeding Nursery eats each turn
NURSERY_PERIOD         :: 8    // fed turns to hatch one baby

// Phase D — raids, heat & alphas.
HEAT_MAX               :: 60   // clamp on the heat meter
RAID_GRACE             :: 35   // no raids before this turn
RAID_MIN_HEAT          :: 4    // below this, no raids are organised
RAID_BASE_INTERVAL     :: 26   // turns between raids at low heat
RAID_MIN_INTERVAL      :: 9    // fastest raid cadence at high heat
RAID_MAX_SIZE          :: 14   // biggest raid at max heat
RAID_LEVEL_PER_HEAT    :: 4    // raid monsters gain +1 level per this much heat
HEAT_LEVEL_PER         :: 3    // wilds/bosses gain +1 level per this much heat

terrain_name :: proc(t: Terrain) -> cstring {
	switch t {
	case .CAVE:         return "Cave"
	case .WATER:        return "Water"
	case .DUNGEON:      return "Dungeon"
	case .GROVE:        return "Grove"
	case .TRADING_POST: return "Trading Post"
	case .BOSS_ROOM:    return "Boss Room"
	case .ARENA:        return "Arena"
	case .CRYSTAL_COVE: return "Crystal Cove"
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
	case .ARENA:        return rl.Color{150, 118, 60, 255}
	case .CRYSTAL_COVE: return rl.Color{78, 96, 158, 255}
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

IMPROVEMENT_HP :: 50 // the default health for most buildings

// Everything static about an improvement lives here, so adding one means adding
// a single row instead of touching eight parallel switches.
Improvement_Info :: struct {
	name:         cstring,
	cost:         int,
	hp:           int,
	category:     cstring,
	effect:       cstring, // one-line summary (build panel / dex header)
	detail:       cstring, // long-form dex description
	heat:         int,     // raid pressure this draws while standing
	terrains:     bit_set[Terrain],
	stacks:       bool, // lives in the tile's overlay slot
	blocks:       bool, // stops a wild's step (so it may batter it)
	cost_divisor: int,  // repeat-build price scaling (higher = slower)
}

IMPROVEMENT_INFO := [Improvement]Improvement_Info {
	.NONE = Improvement_Info{
		name = "", cost = 0, hp = 0, category = "-", effect = "", detail = "",
		heat = 0, terrains = {}, cost_divisor = 3,
	},
	.FARM = Improvement_Info{
		name = "Farm", cost = 20, hp = IMPROVEMENT_HP, category = "Food",
		effect = "staffed: feeds within 4, surplus to nearest store",
		heat = 2, terrains = {.GROVE, .MUSHROOM, .JUNGLE}, cost_divisor = 3,
		detail = "Staffed by one of your monsters standing on the tile. Makes food each turn into a local pool that is delivered to the nearest food store (Granary or Silo) within 4 tiles, spilling over to the next store when one fills; only food past every store in range is lost. Roaming wilds will not spawn on a staffed Farm (raids still will), making it a safe tile to hold.",
	},
	.MINE = Improvement_Info{
		name = "Mine", cost = 20, hp = IMPROVEMENT_HP, category = "Gold",
		effect = "staffed: gold to treasury within 4",
		heat = 2, terrains = {.CAVE, .DESERT, .TUNDRA}, cost_divisor = 3,
		detail = "Staffed by a monster on the tile. Produces gold into the nearest Treasury within 4 tiles. A Marketplace within 3 tiles boosts its output by 50%. Roaming wilds don't spawn while it is staffed (raids still will). Cheaper and safer than a Quarry, but yields less.",
	},
	.BRIDGE = Improvement_Info{
		name = "Bridge", cost = 18, hp = IMPROVEMENT_HP, category = "Traversal",
		effect = "land monsters can cross water",
		heat = 1, terrains = {.WATER}, cost_divisor = 3,
		detail = "Built on Water. Lets your ground monsters cross the water tile, and turns it into a normal traversable hex. Permanent and cheap, but unlike a Drawbridge it can never be raised to block wilds.",
	},
	.GRANARY = Improvement_Info{
		name = "Granary", cost = 18, hp = IMPROVEMENT_HP, category = "Storage",
		effect = "stores food, feeds within 4",
		heat = 2, terrains = {.CAVE, .GROVE, .MUSHROOM, .JUNGLE, .DESERT}, cost_divisor = 3,
		detail = "The food hub. Stores food up to the storage cap and feeds every monster within 4 tiles each turn. Farms, Wells and Lumber Mills within 4 deliver their output here, spilling over to the next store in range when it fills. A Granary should anchor every food district.",
	},
	.TREASURY = Improvement_Info{
		name = "Treasury", cost = 18, hp = IMPROVEMENT_HP, category = "Storage",
		effect = "stores gold",
		heat = 2, terrains = {.CAVE, .DESERT, .TUNDRA}, cost_divisor = 3,
		detail = "Stores gold safely and raises your effective gold cap. Mines and Quarries within 4 tiles deliver their gold here. Placing a Treasury among your mines turns a cluster into real income.",
	},
	.WATCHTOWER = Improvement_Info{
		name = "Watchtower", cost = 25, hp = IMPROVEMENT_HP, category = "Defense",
		effect = "reveals 6, deters spawns 4, guards within 4 (+6 block)",
		heat = 3, terrains = {.CAVE, .GROVE, .MUSHROOM, .RUINS, .TUNDRA, .DESERT, .JUNGLE}, cost_divisor = 3,
		detail = "Reveals tiles within 6, deters wild spawns within 4, and gives defenders within 4 tiles +6 Block at the start of a battle. A solid anchor for a front-line tile you expect to be attacked.",
	},
	.WALL = Improvement_Info{
		name = "Wall", cost = 6, hp = IMPROVEMENT_HP, category = "Defense",
		effect = "wilds won't roam across it",
		heat = 1, terrains = {.CAVE, .RUINS, .GROVE, .MUSHROOM, .TUNDRA, .DESERT},
		blocks = true, cost_divisor = 16,
		detail = "Ground wilds cannot move through a Wall (Air types fly over). A wild whose step is blocked by a Wall batters it instead, so even a wall line needs occasional repair — but it reliably channels wilds away from what it protects.",
	},
	.WELL = Improvement_Info{
		name = "Well", cost = 20, hp = IMPROVEMENT_HP, category = "Food",
		effect = "feeds within 4, +2 (needs water nearby)",
		heat = 2, terrains = {.CAVE, .GROVE, .MUSHROOM, .JUNGLE, .DESERT}, cost_divisor = 3,
		detail = "Must be built adjacent to Water. Produces a small amount of food each turn into the local pool (delivered to a food store within 4) and needs no staffing to do it. A cheap top-up for a food district near water.",
	},
	.GATE = Improvement_Info{
		name = "Gate", cost = 5, hp = 30, category = "Defense",
		effect = "wilds can't cross; your monsters can",
		heat = 1, terrains = {.CAVE, .RUINS, .GROVE, .MUSHROOM},
		blocks = true, cost_divisor = 16,
		detail = "Wilds cannot pass, but your own monsters move through freely. Frailer than a Wall (30 HP) and wilds batter it down faster, so treat a Gate as a door you control rather than a wall.",
	},
	.SPIKE_TRAP = Improvement_Info{
		name = "Spike Trap", cost = 9, hp = 25, category = "Defense",
		effect = "wilds standing here take 8 dmg/turn",
		heat = 1, terrains = {.CAVE, .RUINS, .GROVE}, stacks = true, cost_divisor = 6,
		detail = "Any wild standing on the tile loses 8 HP per turn. Cheap, passive attrition for a chokepoint or a tile wilds keep walking over. Your own monsters are unaffected.",
	},
	.SCARECROW = Improvement_Info{
		name = "Scarecrow", cost = 5, hp = 20, category = "Defense",
		effect = "cheap; keeps spawns out (r2), spooks wilds (r3)",
		heat = 1, terrains = {.GROVE, .MUSHROOM, .JUNGLE}, stacks = true, cost_divisor = 6,
		detail = "The cheapest deterrent. Keeps wild spawns out of a 2-tile radius, and spooks wilds within 3 so that, instead of crossing, they step away toward open ground. Best used to keep a quiet pocket around farms and workers.",
	},
	.ROAD = Improvement_Info{
		name = "Road", cost = 6, hp = 40, category = "Traversal",
		effect = "monsters cross for half the energy",
		heat = 1, terrains = {.CAVE, .GROVE, .DUNGEON, .RUINS, .DESERT, .TUNDRA, .MUSHROOM, .JUNGLE},
		stacks = true, cost_divisor = 6,
		detail = "Stackable — it lives in the tile's overlay slot, so a Road can be laid underneath any building rather than replacing it. Your monsters cross the tile for half the usual energy, which speeds up long hauls and lets a monster cover more ground per turn.",
	},
	.SILO = Improvement_Info{
		name = "Silo", cost = 18, hp = IMPROVEMENT_HP, category = "Storage",
		effect = "second food store; feeds within 4",
		heat = 2, terrains = {.CAVE, .GROVE}, cost_divisor = 3,
		detail = "A second food store, working exactly like a Granary: farms and wells in range deliver to it, and monsters can eat from it. Build one where production outpaces a single Granary so the surplus has somewhere to go.",
	},
	.CRYSTAL_REFINERY = Improvement_Info{
		name = "Crystal Refinery", cost = 30, hp = 45, category = "Gold",
		effect = "staffed on Crystal Cove; slow: ~1 crystal / 6 turns",
		heat = 4, terrains = {.CRYSTAL_COVE}, cost_divisor = 3,
		detail = "Built only on a **Crystal Cove**, and staffed by one of your monsters standing on it. Turns gold into crystals very slowly: one crystal every 6 turns, spending 20 gold. A steady trickle between fights, but the Arena and Boss Rooms are far quicker for real progression — think of a Refinery as a backstop, not a source. Crystals buy permanent upgrades in the tree (U).",
	},
	.FOUNTAIN = Improvement_Info{
		name = "Fountain", cost = 24, hp = 45, category = "Energy",
		effect = "gives energy to the closest unit or Turret nearby",
		heat = 2, terrains = {.CAVE, .GROVE, .MUSHROOM, .RUINS, .DESERT, .TUNDRA}, cost_divisor = 3,
		detail = "Each turn hands 3 energy to the closest monster, or charges the closest Turret within 4 tiles. The heart of an energy network — a Fountain next to a Turret keeps it firing, and one near your workers keeps them moving.",
	},
	.TURRET = Improvement_Info{
		name = "Turret", cost = 28, hp = 35, category = "Energy",
		effect = "needs Fountain energy; shoots a wild within 4",
		heat = 3, terrains = {.CAVE, .RUINS, .DESERT, .GROVE, .TUNDRA}, cost_divisor = 3,
		detail = "Needs energy from a nearby Fountain. Spends 2 charge to shoot the nearest wild within 4 tiles for 10 damage. Useless on its own — always pair it with a Fountain, and cluster a couple of Turrets around a single one to cover a flank.",
	},
	.DRAWBRIDGE = Improvement_Info{
		name = "Drawbridge", cost = 8, hp = 40, category = "Defense",
		effect = "a Bridge you can raise (blocks wilds) or lower",
		heat = 1, terrains = {.WATER}, cost_divisor = 3,
		detail = "Built on Water. Toggle it raised to block wilds or lowered to let your monsters cross. More expensive than a Bridge but reconfigurable, so you can seal a water lane when a raid approaches and reopen it afterward.",
	},
	.QUARRY = Improvement_Info{
		name = "Quarry", cost = 22, hp = IMPROVEMENT_HP, category = "Gold",
		effect = "staffed: gold to treasury within 4",
		heat = 2, terrains = {.RUINS, .DESERT, .TUNDRA}, cost_divisor = 3,
		detail = "Staffed by a monster on the tile. Produces noticeably more gold than a Mine into the nearest Treasury within 4 tiles. Needs Ruins, Desert or Tundra, so it is the reward for pushing into harsher biomes.",
	},
	.LUMBER_MILL = Improvement_Info{
		name = "Lumber Mill", cost = 22, hp = IMPROVEMENT_HP, category = "Food",
		effect = "staffed: food (needs water nearby)",
		heat = 2, terrains = {.GROVE, .MUSHROOM, .JUNGLE}, cost_divisor = 3,
		detail = "Staffed by a monster on the tile and must be built next to Water. Produces food into the local pool (delivered to a food store within 4). A second food chain alongside Farms for a colony spread across wet terrain.",
	},
	.MARKETPLACE = Improvement_Info{
		name = "Marketplace", cost = 26, hp = IMPROVEMENT_HP, category = "Gold",
		effect = "+50% gold from Mines within 3",
		heat = 2, terrains = {.CAVE, .GROVE, .MUSHROOM, .RUINS, .DESERT}, cost_divisor = 3,
		detail = "Boosts the gold output of every Mine within 3 tiles by 50%. It produces nothing itself, so place it in the middle of a mining cluster to multiply several mines at once.",
	},
	.KITCHEN = Improvement_Info{
		name = "Kitchen", cost = 24, hp = IMPROVEMENT_HP, category = "Support",
		effect = "spends food so defenders start with +2 Str",
		heat = 2, terrains = {.CAVE, .GROVE, .MUSHROOM}, cost_divisor = 3,
		detail = "At the start of a battle, spends 6 food from a food store within 4 tiles to give your defenders +2 Strength for the whole fight. A pre-battle buff you pay for with food, so keep a stocked store near the front line.",
	},
	.BARRACKS = Improvement_Info{
		name = "Barracks", cost = 26, hp = IMPROVEMENT_HP, category = "Support",
		effect = "heals & grants a little XP (eats 2 food/turn)",
		heat = 2, terrains = {.CAVE, .RUINS, .GROVE, .DESERT}, cost_divisor = 3,
		detail = "Eats 2 food per turn from a nearby food store and, if fed, heals your monsters and grants a little XP each turn. A training and recovery hub — park wounded monsters beside it between fights.",
	},
	.BEACON = Improvement_Info{
		name = "Beacon", cost = 40, hp = 55, category = "Defense",
		effect = "reveals 8, deters 5, attacking wilds start Vulnerable",
		heat = 4, terrains = {.RUINS, .CAVE}, cost_divisor = 3,
		detail = "The strongest lookout. Reveals tiles within 8, deters wild spawns within 5, and makes wilds attacking within 5 tiles start the battle Vulnerable (taking +50% damage). A great forward base for pushing into dangerous ground.",
	},
	.DEN = Improvement_Info{
		name = "Den", cost = 34, hp = 70, category = "Storage",
		effect = "stasis: holds 32 monsters, no upkeep",
		heat = 2, terrains = {.CAVE, .GROVE, .RUINS, .MUSHROOM, .DESERT}, cost_divisor = 3,
		detail = "Monster storage. Walk one of your monsters next to a Den and press H to put it into stasis: it stops eating (no upkeep) and stops counting toward heat, and it will not act or be attacked. A Den holds up to 32 monsters; take one out any time from the same panel to put it back on the map beside the Den.",
	},
	.VAULT = Improvement_Info{
		name = "Vault", cost = 26, hp = 55, category = "Storage",
		effect = "+12 item slots",
		heat = 2, terrains = {.CAVE, .RUINS, .DESERT, .TUNDRA}, cost_divisor = 3,
		detail = "Item storage. Raises your item inventory cap by 12. Fight-loot items only fit while there is room, so a Vault lets you hoard more gear before equipping it. Press G to browse the bag.",
	},
	.NURSERY = Improvement_Info{
		name = "Nursery", cost = 44, hp = 60, category = "Support",
		effect = "breeds a Lvl 5+ pair; eats food; holds 4 babies",
		heat = 2, terrains = {.CAVE, .GROVE, .MUSHROOM, .JUNGLE}, cost_divisor = 3,
		detail = "Where breeding happens. Move two nearby monsters (same species, Lvl 5+) into a Nursery as its breeding pair. While it has a valid pair it eats 2 food per turn from a nearby food store; every 8 fed turns it hatches a level 1 baby with genes averaged from the pair. A Nursery stores up to 4 babies until you take them out (press C).",
	},
	.MENDER = Improvement_Info{
		name = "Mender", cost = 30, hp = 45, category = "Energy",
		effect = "needs Fountain energy; repairs nearby +1 hp/turn",
		heat = 3, terrains = {.CAVE, .GROVE, .RUINS, .DESERT, .MUSHROOM}, cost_divisor = 3,
		detail = "A repair drone. It draws energy from a Fountain within 4 tiles into its own charge, then spends that charge to mend every damaged improvement within 4 tiles by 1 HP per turn — buildings and overlays alike. Useless without a Fountain, so build one alongside it. Slow, but it quietly keeps a wall line or a front-line cluster patched between raids without spending gold.",
	},
	.WARD_STONE = Improvement_Info{
		name = "Ward Stone", cost = 35, hp = 40, category = "Support",
		effect = "Relic Towers within 4 project 2 tiles further",
		heat = 2, terrains = {.CAVE, .GROVE, .MUSHROOM, .RUINS, .TUNDRA, .CRYSTAL_COVE}, cost_divisor = 3,
		detail = "A standing stone that focuses relic energy. Every Relic Tower within 4 tiles projects its relics 2 tiles further per Ward Stone, so a ring of stones turns one tower into a district-wide aura. Costs nothing to run; it is pure reach.",
	},
	.TRAINING_YARD = Improvement_Info{
		name = "Training Yard", cost = 30, hp = 45, category = "Support",
		effect = "a monster standing here gains +8 XP/turn",
		heat = 2, terrains = {.CAVE, .RUINS, .GROVE, .MUSHROOM, .DESERT, .JUNGLE}, cost_divisor = 3,
		detail = "A sparring ground. Any of your monsters standing on the tile gains 8 XP every turn, so a fresh recruit can be brought up to speed without feeding it into fights it cannot win. Leave a monster here between expeditions.",
	},
	.BATTERY = Improvement_Info{
		name = "Battery", cost = 25, hp = 40, category = "Energy",
		effect = "banks Fountain overflow for Turrets within 4",
		heat = 2, terrains = {.CAVE, .RUINS, .DESERT, .CRYSTAL_COVE, .TUNDRA}, cost_divisor = 3,
		detail = "A bank of cells. When a Fountain within 4 tiles has nothing that needs its charge — every Turret and Mender in reach is already full — the surplus pours into the Battery instead of being wasted. Turrets within 4 draw from it whenever their own cells run dry, so a Fountain can keep a whole cluster firing through a long raid instead of trickling into one barrel at a time.",
	},
	.CALTROPS = Improvement_Info{
		name = "Caltrops", cost = 14, hp = 25, category = "Defense",
		effect = "wilds here take 24% max HP/turn",
		heat = 1, terrains = {.CAVE, .RUINS, .GROVE, .DESERT}, stacks = true, cost_divisor = 6,
		detail = "A nastier Spike Trap. Wilds standing on the tile lose 24% of their max HP per turn instead of 15%, so a couple of Caltrops tiles will grind down even a boss pack that parks on them. Shares the overlay slot with Roads and Scarecrows.",
	},
	.RELIC_TOWER = Improvement_Info{
		name = "Relic Tower", cost = 60, hp = 60, category = "Support",
		effect = "holds 3 relics; projects them 5 tiles",
		heat = 4, terrains = {.CAVE, .GROVE, .MUSHROOM, .RUINS, .TUNDRA, .DESERT, .JUNGLE, .CRYSTAL_COVE}, cost_divisor = 2,
		detail = "A spire built to hold relics. It has 3 slots; each relic slotted here projects its effect over a 5-tile radius — battle relics buff your monsters fighting inside that radius, economy relics boost the Mines, Farms and Turrets inside it, and win-bonus relics pay out for fights won there. Relics outside a tower do nothing, so where you raise your towers decides what your relics actually do. Copies stack.",
	},
}

// Every buildable improvement, in build-panel order (used by the improvements dex).
ALL_IMPROVEMENTS := [?]Improvement{
	.FARM, .MINE, .WELL, .BRIDGE, .GRANARY, .TREASURY, .WATCHTOWER, .WALL,
	.GATE, .SPIKE_TRAP, .SCARECROW, .ROAD, .SILO, .CRYSTAL_REFINERY, .FOUNTAIN,
	.TURRET, .DRAWBRIDGE, .QUARRY, .LUMBER_MILL, .MARKETPLACE, .KITCHEN,
	.BARRACKS, .BEACON, .DEN, .VAULT, .NURSERY, .MENDER, .RELIC_TOWER,
	.WARD_STONE, .TRAINING_YARD, .CALTROPS, .BATTERY,
}

tile_has :: proc(t: ^Tile, im: Improvement) -> bool {
	return t.improvement == im || t.overlay == im
}

Monster :: struct {
	id:       int,
	creature: Creature,
	pos:      Hex,
	wild:     bool,
	food:     f32, // satiation bar 0..100
	role:     Wild_Role, // wilds only: raider/alpha hunt the colony (Phase D)
	pack:     int, // boss-pack id (0 = not in a pack); pack members move together
	acted:    bool, // player monsters: already moved/fought this turn
	// Map move animation: the drawn world-space position eases toward `pos`.
	anim_x, anim_y: f32,
	anim_fx:        f32,
	anim_fy:        f32,
	anim_target:    Hex,
	anim_t:         f32,
	anim_ok:        bool,
	home:           Hex, // wilds: the lair they wander around
	home_set:       bool,
	spawn_t0:       f32, // when the monster first appeared (arrival burst)
	stored:     Stored_In, // Phase 10: where it lives (MAP, a Den, or a Nursery)
	stored_hex: Hex,       // the building holding it when stored
}

// Where a monster lives. Only `.MAP` monsters are in `Colony.roster`; the rest
// sit in `Colony.storage` inside a Den or Nursery (no upkeep, off the map).
Stored_In :: enum { MAP, DEN, NURSERY_PARENT, NURSERY_BABY }

// What a wild is up to. Raiders hit the nearer of your monsters or improvements;
// alphas hunt your monsters.
Wild_Role :: enum { WILD, RAIDER, ALPHA, SIEGE, STALKER, BOSS, CRONY }

// Short tag shown next to a wild's name in battle/rosters.
wild_role_tag :: proc(r: Wild_Role) -> cstring {
	switch r {
	case .ALPHA:   return "  [ALPHA]"
	case .RAIDER:  return "  [raider]"
	case .SIEGE:   return "  [siege]"
	case .STALKER: return "  [stalker]"
	case .BOSS:    return "  [BOSS]"
	case .CRONY:   return "  [crony]"
	case .WILD:    return ""
	}
	return ""
}

// Seconds for a monster to slide from its old tile to its new one.
MOVE_ANIM_DUR :: f32(0.22)
// Duration of the arrival burst when a monster first appears.
SPAWN_BURST :: f32(0.6)

// Ease the drawn position of every map monster toward its logical hex. Detects
// the change itself (comparing against `anim_target`) so any code that assigns
// `m.pos` gets the tween for free.
colony_update_move_anims :: proc(g: ^Game, dt: f32) {
	for i in 0..<len(g.colony.roster) {
		m := &g.colony.roster[i]
		tx, ty := hex_world(&g.renderer, m.pos)
		if !m.anim_ok {
			m.anim_x, m.anim_y = tx, ty
			m.anim_fx, m.anim_fy = tx, ty
			m.anim_target = m.pos
			m.anim_ok = true
			m.spawn_t0 = f32(rl.GetTime())
			continue
		}
		if !hex_equal(m.anim_target, m.pos) {
			m.anim_fx, m.anim_fy = m.anim_x, m.anim_y
			m.anim_target = m.pos
			m.anim_t = 0
		}
		if m.anim_t < MOVE_ANIM_DUR {
			m.anim_t += dt
			p := clamp(m.anim_t / MOVE_ANIM_DUR, 0, 1)
			e := 1.0 - (1.0 - p) * (1.0 - p) // ease-out quad
			m.anim_x = m.anim_fx + (tx - m.anim_fx) * e
			m.anim_y = m.anim_fy + (ty - m.anim_fy) * e
		} else {
			m.anim_x, m.anim_y = tx, ty
		}
	}
}

// A pending "pick one of these moves" prompt — raised when a monster levels into
// several learnset moves at once, or when a battle reward offers a choice.
MAX_CHOICE_OPTIONS :: 3

Choice_Kind :: enum { LEVEL, REWARD }

Move_Choice :: struct {
	monster_id: int,
	kind:       Choice_Kind,
	options:    [MAX_CHOICE_OPTIONS]Move_Id,
	count:      int,
}

// A short-lived floating "+N gold/food" marker at a tile, spawned by the turn
// loop when a producer works. Drawn by draw_tile_floats; ages via rl.GetTime().
Float_Kind :: enum { GOLD, FOOD, FOOD_IN, FOOD_OUT, DAMAGE, CRYSTAL, FLEE, ENERGY, HEAL, GROW }
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
	species: Species_Id,
	level:   int,
	price:   int,
}

Colony :: struct {
	tiles:      [dynamic]^Tile, // materialized tiles (the map extends on demand)
	tile_index: map[u64]int,    // hex key -> index into tiles
	roster:     [dynamic]Monster,
	graveyard:  [dynamic]Monster,
	storage:    [dynamic]Monster, // monsters in Dens / Nurseries (Phase 10)
	choices:    [dynamic]Move_Choice, // pending level-up / reward card picks
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
	next_pack_id: int, // ids for boss packs (Phase 25)
	pending_tiles: [dynamic]Hex, // tiles where wilds and your monsters share a tile
	messages:  [dynamic]string, // recent world notifications
	floats:    [dynamic]Tile_Float, // transient production popups
	shop:      [dynamic]Shop_Offer, // Trading Post stock, rerolled each turn
	shop_turn: int,                 // turn the current stock belongs to
	items:     [dynamic]Item,       // unequipped item inventory
	upgrades:  [Upgrade]int,        // crystal progression levels (Phase C)
	heat:      int,                 // raid pressure: grows with every improvement & level
	raid_timer: int,                // turns until the next raid
	raids:     int,                 // raids weathered so far

	// Lifetime stats + milestone board (Phase 22).
	fights_won:         int,
	alphas_slain:       int,
	bosses_slain:       [Species_Id]bool, // one flag per boss, for the quest board
	crystals_earned:    int,
	improvements_built: int,
	milestones:         [Milestone_Kind]bool,
	goal_done:          bool,

	// Arena tower (Phase 53/54): the run, the floor you're on, your best ever,
	// and the winnings banked so far this run.
	arena_run:          bool,
	arena_floor:        int,
	arena_best_floor:   int,
	arena_run_crystals: int,

	// Boss relics you own but haven't slotted into a tower yet (Phase 25/44).
	// Placed relics live on the tower tile itself; see `src/relics.odin`.
	relic_bag: [dynamic]Relic,

	// World event state (Phase: ecology/events).
	tremor: f32, // seconds of screen shake remaining
	// Headless skirmish budget for the current turn.
	battles_this_turn: int,
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
	fresh := false
	if t := ensure_tile(c, hex); t != nil {
		if !t.revealed {
			fresh = true
		}
		t.revealed = true
	}
	for n in hex_neighbors(hex) {
		if t := ensure_tile(c, n); t != nil {
			if !t.revealed {
				fresh = true
			}
			t.revealed = true
		}
	}
	// Ensure one ring further out so unexplored tiles render as fog.
	for n in hex_neighbors(hex) {
		for nn in hex_neighbors(n) {
			_ = ensure_tile(c, nn)
		}
	}
	if fresh {
		audio_play(.DISCOVER, 0.55)
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

// Collects the hexes of every tile holding improvement `im` (building or overlay)
// into `out`. Do this once when a check is repeated over many tiles, so the work
// is O(tiles) once instead of O(tiles) per tile.
collect_improvement_hexes :: proc(c: ^Colony, im: Improvement, out: ^[dynamic]Hex) {
	clear(out)
	for t in c.tiles {
		if tile_has(t, im) {
			append(out, t.hex)
		}
	}
}

// Is any hex in `hexes` within `radius` of `from`?
near_any :: proc(from: Hex, radius: int, hexes: []Hex) -> bool {
	for h in hexes {
		if hex_distance(from, h) <= radius {
			return true
		}
	}
	return false
}

// Nearest hex in `hexes` within `radius` of `from` (returns `from` if none).
nearest_hex_in :: proc(from: Hex, radius: int, hexes: []Hex) -> Hex {
	best := from
	best_d := radius + 1
	for h in hexes {
		d := hex_distance(from, h)
		if d <= radius && d < best_d {
			best_d = d
			best = h
		}
	}
	return best
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

// A building that stores food (Granary or Silo).
tile_is_food_store :: proc(t: ^Tile) -> bool {
	return t.improvement == .GRANARY || t.improvement == .SILO
}

// Nearest food store within range that holds at least `need` food. Used for
// eating, so a monster ignores a nearer store that can't feed it and eats from
// one that can instead of starving beside an empty Granary.
//
// The list-based forms take a precomputed `stores` list (see
// `collect_food_stores`) so the turn loop can scan only food stores instead of
// every tile, many times per turn.
nearest_food_store_in :: proc(c: ^Colony, stores: []int, from: Hex, radius, need: int) -> int {
	best := -1
	best_d := 1 << 30
	for i in stores {
		t := c.tiles[i]
		if t.stored < need {
			continue
		}
		d := hex_distance(from, t.hex)
		if d <= radius && d < best_d {
			best_d = d
			best = i
		}
	}
	return best
}

nearest_food_store_with :: proc(c: ^Colony, from: Hex, radius, need: int) -> int {
	stores := make([dynamic]int, 0)
	defer delete(stores)
	collect_food_stores(c, &stores)
	return nearest_food_store_in(c, stores[:], from, radius, need)
}

// Fills `out` with the tile index of every food store (Granary / Silo).
collect_food_stores :: proc(c: ^Colony, out: ^[dynamic]int) {
	clear(out)
	for i in 0..<len(c.tiles) {
		if tile_is_food_store(c.tiles[i]) {
			append(out, i)
		}
	}
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
	c.storage = make([dynamic]Monster, 0)
	c.choices = make([dynamic]Move_Choice, 0)
	c.pending_tiles = make([dynamic]Hex, 0)
	c.next_id = 1
	c.next_pack_id = 1
	c.messages = make([dynamic]string, 0)
	c.floats = make([dynamic]Tile_Float, 0)
	c.shop = make([dynamic]Shop_Offer, 0)
	c.items = make([dynamic]Item, 0)
	c.raid_timer = RAID_GRACE

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

	// Water is deliberately generous — it carves lakes and coastlines that shape
	// the whole map (and give Wells/Bridges/Lumber Mills somewhere to go).
	if e < 0.40 { return .WATER }
	if e < 0.48 { return .CAVE }
	if e < 0.72 {
		switch {
		case m < 0.28: return .DUNGEON
		case m < 0.50: return .GROVE
		case m < 0.54: return .MUSHROOM
		case m < 0.84: return .JUNGLE
		case:          return .GROVE
		}
	}
	if e < 0.88 {
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
	if dist >= 4 && rng_f32(&special) < 0.006 {
		return .ARENA
	}
	if dist >= 3 && rng_f32(&special) < 0.012 {
		return .CRYSTAL_COVE
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
	for i in 0..<len(c.storage) {
		creature_free_all(&c.storage[i].creature)
	}
	for t in c.tiles {
		free(t)
	}
	delete(c.roster)
	delete(c.graveyard)
	delete(c.storage)
	delete(c.choices)
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
	c.storage = make([dynamic]Monster, 0)
	c.choices = make([dynamic]Move_Choice, 0)
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
// Grants XP and levels the monster up as thresholds are crossed. Any move a
// level unlocks becomes a choice (even a single one), so the player can decline.
monster_add_xp :: proc(c: ^Colony, m: ^Monster, amount: int) -> bool {
	m.creature.xp += amount
	leveled := false
	for m.creature.xp >= xp_to_next(m.creature.level) {
		m.creature.xp -= xp_to_next(m.creature.level)
		old_name := m.creature.name
		opts, n, evolved := creature_level_up(&m.creature)
		leveled = true
		if evolved {
			colony_notify(c, "%s evolved into %s!", old_name, m.creature.name)
			colony_add_float(c, m.pos, .GROW, 1)
		}
		if n > 0 {
			enqueue_choice(c, m.id, opts, n, .LEVEL)
		}
	}
	if leveled {
		audio_play(.LEVELUP)
	}
	return leveled
}

// Queues a pending "pick a move" prompt for a monster.
enqueue_choice :: proc(c: ^Colony, monster_id: int, opts: [MAX_CHOICE_OPTIONS]Move_Id, n: int, kind: Choice_Kind) {
	ch := Move_Choice{monster_id = monster_id, kind = kind, count = n}
	for i in 0..<n {
		ch.options[i] = opts[i]
	}
	append(&c.choices, ch)
}

// How much a step into each terrain costs, before the mover's Speed and the
// global step factor. Rough ground is pricier, so routes and Roads matter.
terrain_move_cost :: proc(t: Terrain) -> f32 {
	switch t {
	case .GROVE, .MUSHROOM:            return 0.9  // soft, easy going
	case .CAVE, .TRADING_POST, .ARENA: return 1.0
	case .CRYSTAL_COVE, .RUINS:        return 1.15
	case .DESERT:                      return 1.25
	case .TUNDRA, .JUNGLE:             return 1.35
	case .DUNGEON:                     return 1.4
	case .BOSS_ROOM, .WATER:           return 1.5
	case .LAVA:                        return 1.6
	case .QUICKSAND:                   return 1.8  // the worst footing
	}
	return 1.0
}

monster_move_cost :: proc(m: ^Monster, t: Terrain) -> f32 {
	speed := max(f32(m.creature.speed), 1.0)
	factor := clamp(10.0 / speed, 0.7, 1.6)
	// Movement and card-play share one energy pool. A step is deliberately not
	// free: long treks cost real energy, so you can't cross the map in a turn.
	return terrain_move_cost(t) * factor * MOVE_STEP_FACTOR
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
	cost *= upgrade_move_cost_mult(c)
	return cost
}

// Terrain-only movement check (no fortifications): water/tundra/jungle/lava/
// quicksand gate on the mover's elements.
terrain_passable :: proc(c: ^Colony, m: ^Monster, hex: Hex) -> bool {
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
	return true
}

tile_passable :: proc(c: ^Colony, m: ^Monster, hex: Hex) -> bool {
	if !terrain_passable(c, m, hex) {
		return false
	}
	t := tile_at(c, hex)
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
	if m.acted {
		return 5 // its turn is over (it moved or fought already)
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
		if tile_is_food_store(t) {
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
		case .TREASURY: gold_cap += storage_cap(c)
		case .GRANARY, .SILO: food_cap += storage_cap(c)
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
		m := min(remaining, storage_cap(c) - t.stored)
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

// Deposits food into food stores within range, nearest first, spilling over to
// the next store whenever one fills up. Returns the amount actually kept, so
// only food past *every* store in range is wasted.
colony_store_food_in :: proc(c: ^Colony, stores: []int, from: Hex, amount: int) -> int {
	remaining := amount
	for remaining > 0 {
		best := -1
		best_d := 1 << 30
		for i in stores {
			t := c.tiles[i]
			if t.stored >= storage_cap(c) {
				continue
			}
			d := hex_distance(from, t.hex)
			if d <= DELIVER_RADIUS && d < best_d {
				best_d = d
				best = i
			}
		}
		if best < 0 {
			break
		}
		t := c.tiles[best]
		move := min(remaining, storage_cap(c) - t.stored)
		t.stored += move
		remaining -= move
		colony_add_float(c, t.hex, .FOOD_IN, move)
	}
	return amount - remaining
}

colony_store_food :: proc(c: ^Colony, from: Hex, amount: int) -> int {
	stores := make([dynamic]int, 0)
	defer delete(stores)
	collect_food_stores(c, &stores)
	return colony_store_food_in(c, stores[:], from, amount)
}

// Gross per-turn output for the colony HUD (before range/storage limits, so a
// farm with no receiver in range still shows its potential).
colony_food_production :: proc(c: ^Colony) -> int {
	sum := 0
	farm_bonus := upgrade_farm_food_bonus(c)
	for t in c.tiles {
		#partial switch t.improvement {
		case .FARM:
			if monsters_on_tile(c, t.hex, false) > 0 {
				sum += int(f32(FARM_FOOD_YIELD + farm_bonus) * upgrade_food_mult(c))
			}
		case .WELL:
			sum += int(f32(WELL_FOOD_YIELD) * upgrade_food_mult(c))
		case:
		}
	}
	return sum
}

colony_gold_production :: proc(c: ^Colony) -> int {
	sum := 0
	bonus := upgrade_deep_core_bonus(c)
	for t in c.tiles {
		if t.improvement == .MINE && monsters_on_tile(c, t.hex, false) > 0 {
			sum += int(f32(MINE_GOLD_YIELD + bonus) * upgrade_gold_mult(c))
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

shop_pick_species :: proc(c: ^Colony) -> Species_Id {
	total := 0
	for sp in SPECIES {
		if sp.role == .BOSS {
			continue // bosses aren't for sale
		}
		total += rarity_weight(sp.rarity)
	}
	if total <= 0 {
		return .Emberling
	}
	roll := rng_below(&c.rng, total)
	acc := 0
	for id in Species_Id {
		if SPECIES[id].role == .BOSS {
			continue
		}
		acc += rarity_weight(SPECIES[id].rarity)
		if roll < acc {
			return id
		}
	}
	return .Emberling
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
	m.creature.player = true
	creature_recompute_stats(&m.creature)
	m.creature.hp = m.creature.max_hp
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

// Deck thinning: permanently remove one card from a monster's deck for gold.
// 0 ok, 1 bad index, 2 not enough gold, 3 cannot thin the last card.
colony_forget_card :: proc(c: ^Colony, index, deck_index: int) -> int {
	if index < 0 || index >= len(c.roster) {
		return 1
	}
	deck := &c.roster[index].creature.deck
	if deck_index < 0 || deck_index >= len(deck) || len(deck) <= 1 {
		return 3
	}
	if !colony_spend_gold(c, forget_card_cost(deck[deck_index])) {
		return 2
	}
	ordered_remove(deck, deck_index)
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
	creature_reset_battle_state(&m.creature)
	creature_free_piles(&m.creature)
	m.food = monster_satiety_max(&m)
	m.pos = c.start_hex
	m.creature.energy = m.creature.energy_max

	append(&c.roster, m)
	unordered_remove(&c.graveyard, grave_index)
	return 0
}

// Hall of the Fallen: recover the item a fallen monster carried, freeing the
// corpse's slot. 0 ok, 1 bad index, 2 no item, 3 the bag is full.
colony_salvage_grave :: proc(c: ^Colony, grave_index: int) -> int {
	if grave_index < 0 || grave_index >= len(c.graveyard) {
		return 1
	}
	m := &c.graveyard[grave_index]
	if m.creature.item == .NONE {
		return 2
	}
	if len(c.items) >= colony_item_cap(c) {
		return 3
	}
	append(&c.items, m.creature.item)
	creature_equip_item(&m.creature, .NONE)
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
	// Reset the headless-battle budget for this turn.
	c.battles_this_turn = 0

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
		yield += upgrade_deep_core_bonus(c)
		yield = int(f32(yield) * upgrade_gold_mult(c))
		if t.improvement == .MINE && near_improvement(c, t.hex, MARKET_RADIUS, .MARKETPLACE) {
			yield += int(f32(yield) * (MARKET_BONUS + upgrade_market_bonus(c)))
		}
		// Coin of Plenty relics project onto the Mine/Quarry they cover.
		yield = int(f32(yield) * relic_gold_mult_at(c, t.hex))
		kept := colony_deposit_gold(c, t.hex, yield)
		if kept > 0 {
			colony_add_float(c, t.hex, .GOLD, kept)
		}
	}

	// 1b. Crystal refineries: staffed, and deliberately the slowest crystal
	// source. Each counts turns up; every few turns it spends gold and yields a
	// single crystal. Needs a monster standing on the Crystal Cove.
	for t in c.tiles {
		if t.improvement != .CRYSTAL_REFINERY {
			continue
		}
		if monsters_on_tile(c, t.hex, false) == 0 {
			continue // unstaffed
		}
		t.stored += 1
		period := max(CRYSTAL_REFINERY_PERIOD - upgrade_refinery_boost(c), 2)
		if t.stored >= period {
			if colony_total_gold(c) >= CRYSTAL_REFINERY_COST && colony_spend_gold(c, CRYSTAL_REFINERY_COST) {
				c.crystals += 1
				c.crystals_earned += 1
				colony_add_float(c, t.hex, .CRYSTAL, 1)
				t.stored = 0
			}
		}
	}

	// 2. Farms / Lumber Mills (staffed) and Wells produce a local food pool.
	for i in 0..<n_tiles {
		t := c.tiles[i]
		food := 0
		if t.improvement == .FARM && monsters_on_tile(c, t.hex, false) > 0 {
			food = FARM_FOOD_YIELD
		} else if t.improvement == .LUMBER_MILL && monsters_on_tile(c, t.hex, false) > 0 {
			food = LUMBER_FOOD_YIELD
		} else if t.improvement == .WELL {
			food = WELL_FOOD_YIELD
		}
		if food > 0 {
			if t.improvement == .FARM {
				food += upgrade_farm_food_bonus(c)
			}
			food = int(f32(food) * upgrade_food_mult(c))
			food = int(f32(food) * relic_food_mult_at(c, t.hex))
			farm_pool[i] = food
			colony_add_float(c, t.hex, .FOOD, food)
		}
	}

	// Watchtowers & Beacons keep their surroundings revealed.
	for i in 0..<n_tiles {
		t := c.tiles[i]
		if t.improvement == .WATCHTOWER {
			colony_reveal_radius(c, t.hex, WATCHTOWER_REVEAL + upgrade_vigilance(c))
		} else if t.improvement == .BEACON {
			colony_reveal_radius(c, t.hex, BEACON_REVEAL + upgrade_vigilance(c))
		}
	}

	// Gather food stores once for the delivery / feeding / barracks / nursery
	// passes below, so they scan only stores rather than every tile.
	food_stores := make([dynamic]int, 0)
	defer delete(food_stores)
	collect_food_stores(c, &food_stores)

	// 3. Farms deliver their pool to the nearest food store with room, spilling
	// over to the next store in range; only food past *every* store is wasted.
	for i in 0..<n_tiles {
		if farm_pool[i] <= 0 {
			continue
		}
		kept := colony_store_food_in(c, food_stores[:], c.tiles[i].hex, farm_pool[i])
		farm_pool[i] -= kept
	}

	// 4. Feed monsters (range-gated): eat from a granary or farm pool within range.
	for &m in c.roster {
		if m.wild {
			continue
		}
		// A fainted monster doesn't eat — otherwise a full meal would heal it
		// back above 0 before the death sweep below and it would "revive".
		if m.creature.hp <= 0 {
			continue
		}
		need := monster_upkeep(&m)
		fed := false

		gi := nearest_food_store_in(c, food_stores[:], m.pos, FEED_RADIUS, need)
		if gi >= 0 {
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
			if m.food >= smax && m.creature.hp > 0 {
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
	colony_barracks(c, n_tiles, food_stores[:])
	colony_training_yards(c)

	// 4c. Nurseries eat food and hatch babies from their breeding pair.
	colony_nurseries(c, n_tiles, food_stores[:])

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
		m.acted = false // a new turn: it can move and fight again
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

	// Phase D: heat rises with the colony; when it's hot enough a raid forms.
	c.heat = colony_heat(c)
	colony_raids(c)

	colony_spawn_wilds(c)
	colony_grow_wilds(c)
	colony_spawn_boss_packs(c)
	colony_roam_wilds(c)
	colony_roam_boss_packs(c)
	colony_despawn_wilds(c)
	colony_crowd_fights(c)
	colony_predation(c)
	colony_carrion(c)
	colony_fountains(c)
	colony_menders(c)
	colony_turrets(c)
	colony_apply_traps(c)
	colony_resolve_wild_actions(c)
	colony_world_events(c)

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
	// Check the quest board once per turn (turn-based milestones included).
	milestones_check(c)
}

// Barracks: each one eats food from a nearby Granary and, if fed, heals and
// grants a little XP to your monsters nearby.
// Training Yard: any of your monsters standing on the tile gains XP each turn,
// so a recruit can be brought up to speed without feeding it to fights.
colony_training_yards :: proc(c: ^Colony) {
	for &m in c.roster {
		if m.wild || m.creature.hp <= 0 {
			continue
		}
		t := tile_at(c, m.pos)
		if t == nil || t.improvement != .TRAINING_YARD {
			continue
		}
		monster_add_xp(c, &m, TRAINING_YARD_XP)
		colony_add_float(c, m.pos, .GROW, TRAINING_YARD_XP)
	}
}

colony_barracks :: proc(c: ^Colony, n_tiles: int, food_stores: []int) {
	for i in 0..<n_tiles {
		t := c.tiles[i]
		if t.improvement != .BARRACKS {
			continue
		}
		gi := nearest_food_store_in(c, food_stores, t.hex, DELIVER_RADIUS, BARRACKS_UPKEEP)
		if gi < 0 {
			continue // no rations, no training
		}
		c.tiles[gi].stored -= BARRACKS_UPKEEP
		for &m in c.roster {
			if m.wild || m.creature.hp <= 0 {
				continue
			}
			if hex_distance(m.pos, t.hex) <= BARRACKS_RANGE {
				m.creature.hp = min(m.creature.hp + max(int(f32(m.creature.max_hp)*BARRACKS_HEAL_PCT), 1), m.creature.max_hp)
				_ = monster_add_xp(c, &m, BARRACKS_XP + upgrade_veterans(c))
			}
		}
	}
}

// Fountains hand FOUNTAIN_OUTPUT energy to the closest recipient within range:
// a Turret or Mender that needs charge, or one of your monsters that needs
// energy. Fountains and chargeable structures are gathered once, so this is
// O(fountains x (structures + roster)) rather than O(tiles^2).
colony_fountains :: proc(c: ^Colony) {
	output := FOUNTAIN_OUTPUT + upgrade_fountain_output(c)
	turret_cap := TURRET_CAP + upgrade_turret_cap(c)
	range_ := FOUNTAIN_RANGE + upgrade_fountain_range(c)

	fountains := make([dynamic]int, 0); defer delete(fountains)
	structs := make([dynamic]int, 0); defer delete(structs)
	batteries := make([dynamic]int, 0); defer delete(batteries)
	for i in 0..<len(c.tiles) {
		#partial switch c.tiles[i].improvement {
		case .FOUNTAIN:
			append(&fountains, i)
		case .TURRET, .MENDER:
			append(&structs, i)
		case .BATTERY:
			append(&batteries, i)
		}
	}

	for fi in fountains {
		f := c.tiles[fi]
		best_d := 1 << 30
		best_struct := -1
		best_monster := -1
		for j in structs {
			t := c.tiles[j]
			cap := t.improvement == .TURRET ? turret_cap : MENDER_CAP
			if t.stored >= cap {
				continue
			}
			d := hex_distance(f.hex, t.hex)
			if d <= range_ && d < best_d {
				best_d = d
				best_struct = j
			}
		}
		for k in 0..<len(c.roster) {
			m := &c.roster[k]
			if m.wild || m.creature.hp <= 0 || m.creature.energy >= m.creature.energy_max {
				continue
			}
			d := hex_distance(f.hex, m.pos)
			if d <= range_ && d < best_d {
				best_d = d
				best_struct = -1
				best_monster = k
			}
		}
		if best_struct >= 0 {
			t := c.tiles[best_struct]
			cap := t.improvement == .TURRET ? turret_cap : MENDER_CAP
			before := t.stored
			t.stored = min(cap, t.stored + output)
			if t.stored > before {
				// Show the charge actually landing (monsters and Batteries
				// already float it).
				colony_add_float(c, t.hex, .ENERGY, t.stored - before)
			}
		} else if best_monster >= 0 {
			m := &c.roster[best_monster]
			m.creature.energy = min(m.creature.energy_max, m.creature.energy + f32(output))
			colony_add_float(c, m.pos, .ENERGY, output)
		} else {
			// Nobody needs the charge right now — every Turret and Mender in
			// reach is full. Bank it in a Battery instead of wasting it.
			best_b := -1
			best_bd := 1 << 30
			for j in batteries {
				b := c.tiles[j]
				if b.stored >= BATTERY_CAP {
					continue
				}
				d := hex_distance(f.hex, b.hex)
				if d <= BATTERY_RANGE && d < best_bd {
					best_bd = d
					best_b = j
				}
			}
			if best_b >= 0 {
				b := c.tiles[best_b]
				b.stored = min(BATTERY_CAP, b.stored + output)
				colony_add_float(c, b.hex, .ENERGY, output)
			}
		}
	}
}

// Menders spend stored charge to repair every damaged improvement within
// MENDER_REPAIR_RANGE, MENDER_HEAL HP each, once per turn. (Energy reaches them
// via a Fountain's FOUNTAIN_RANGE, same as Turrets — this is only the repair
// radius.) Only the hexes in range are visited, not the whole tile list.
colony_menders :: proc(c: ^Colony) {
	disk := make([dynamic]Hex, 0); defer delete(disk)
	for i in 0..<len(c.tiles) {
		m := c.tiles[i]
		if m.improvement != .MENDER || m.stored < MENDER_COST {
			continue
		}
		hex_range(m.hex, MENDER_REPAIR_RANGE + upgrade_mender_range(c), &disk)
		healed := false
		for h in disk {
			t := tile_at(c, h)
			if t == nil {
				continue
			}
			if t.improvement != .NONE && t.improvement_hp < improvement_hp_cap(c, t.improvement) {
				t.improvement_hp = min(t.improvement_hp + MENDER_HEAL, improvement_hp_cap(c, t.improvement))
				colony_add_float(c, t.hex, .HEAL, MENDER_HEAL)
				healed = true
			}
			if t.overlay != .NONE && t.overlay_hp < improvement_max_hp(t.overlay) {
				t.overlay_hp = min(t.overlay_hp + MENDER_HEAL, improvement_max_hp(t.overlay))
				healed = true
			}
		}
		if healed {
			m.stored -= MENDER_COST
		}
	}
}


// Turrets spend stored charge to shoot the nearest wild in range. Damage scales
// with the target's level so turrets keep pace as the run escalates; Quick
// Loaders fire extra shots and Shrapnel Rounds splash nearby wilds.
colony_turrets :: proc(c: ^Colony) {
	shots := 1 + upgrade_turret_rate(c)
	splash := upgrade_turret_splash(c)
	range_ := TURRET_RANGE + upgrade_turret_range(c)
	// Batteries let a dry Turret draw stored surplus before it gives up a shot.
	batteries := make([dynamic]int, 0); defer delete(batteries)
	for i in 0..<len(c.tiles) {
		if c.tiles[i].improvement == .BATTERY {
			append(&batteries, i)
		}
	}
	for i in 0..<len(c.tiles) {
		t := c.tiles[i]
		if t.improvement != .TURRET {
			continue
		}
		for _ in 0..<shots {
			if t.stored < TURRET_COST {
				for j in batteries {
					b := c.tiles[j]
					if b.stored <= 0 || hex_distance(b.hex, t.hex) > BATTERY_RANGE {
						continue
					}
					need := TURRET_COST - t.stored
					drawn := min(need, b.stored)
					b.stored -= drawn
					t.stored += drawn
					colony_add_float(c, t.hex, .ENERGY, drawn)
					if t.stored >= TURRET_COST {
						break
					}
				}
			}
			if t.stored < TURRET_COST {
				break
			}
			best_d := 1 << 30
			best_w := -1
			for k in 0..<len(c.roster) {
				m := c.roster[k]
				if !m.wild || m.creature.hp <= 0 {
					continue
				}
				d := hex_distance(t.hex, m.pos)
				if d <= range_ && d < best_d {
					best_d = d
					best_w = k
				}
			}
			if best_w < 0 {
				break
			}
			t.stored -= TURRET_COST
			target_hex := c.roster[best_w].pos
			dmg := int(f32(TURRET_DAMAGE+upgrade_turret_damage(c)) * relic_turret_mult_at(c, t.hex))
			c.roster[best_w].creature.hp -= dmg
			colony_add_float(c, target_hex, .DAMAGE, dmg)
			if c.roster[best_w].creature.hp <= 0 {
				remove_monster_at(c, best_w, false)
			}
			// Shrapnel: wound other wilds standing beside the target.
			if splash > 0 {
				k := 0
				for k < len(c.roster) {
					m := &c.roster[k]
					if m.wild && m.creature.hp > 0 && hex_distance(m.pos, target_hex) <= 1 {
						m.creature.hp -= splash
						colony_add_float(c, m.pos, .DAMAGE, splash)
						if m.creature.hp <= 0 {
							remove_monster_at(c, k, false)
							continue
						}
					}
					k += 1
				}
			}
		}
	}
}

// Spike traps wound any wild standing on them (they can die to the spikes).
colony_apply_traps :: proc(c: ^Colony) {
	i := 0
	for i < len(c.roster) {
		m := &c.roster[i]
		if m.wild {
			t := tile_at(c, m.pos)
			pct := f32(0)
			if t != nil {
				if tile_has(t, .SPIKE_TRAP) { pct = SPIKE_TRAP_DAMAGE_PCT }
				if tile_has(t, .CALTROPS) { pct = CALTROPS_DAMAGE_PCT }
			}
			if pct > 0 {
				dmg := max(int(f32(m.creature.max_hp)*(pct+upgrade_spike_pct(c))), 1)
				m.creature.hp -= dmg
				colony_add_float(c, m.pos, .DAMAGE, dmg)
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

colony_add_starter :: proc(c: ^Colony, species_idx: Species_Id) -> int {
	m := Monster{
		id       = c.next_id,
		creature = creature_make(species_idx, 1, SPECIES[species_idx].name, &c.rng),
		pos      = c.start_hex,
	}
	c.next_id += 1
	m.creature.player = true
	creature_recompute_stats(&m.creature)
	m.creature.hp = m.creature.max_hp
	m.creature.energy = m.creature.energy_max
	m.food = monster_satiety_max(&m)
	append(&c.roster, m)
	return len(c.roster) - 1
}

// ----------------------------------------------------------------------------
// Storage & breeding buildings (Phase 10)
//
// A Den keeps monsters in stasis (no upkeep, off the map, up to DEN_CAPACITY).
// A Nursery breeds a same-species Lvl 5+ pair, eating food each turn, and stores
// up to NURSERY_BABIES babies. Stored monsters live in `Colony.storage`.
// ----------------------------------------------------------------------------

BREED_MIN_LEVEL :: 5

// A pairing is legal when it is yours and old enough to breed.
