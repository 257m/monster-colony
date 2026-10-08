# The colony layer (`src/colony.odin`)

Everything on the board: the infinite map, tiles, improvements, the economy,
movement, and the wild monsters.

## 1. The map is infinite

Tiles are generated **on demand** and stored as pointers:

```
tiles: [dynamic]^Tile      // every materialized tile
tile_index: map[u64]int     // hex_key(hex) -> index into tiles
```

- `hex_key` packs a `Hex` into a `u64` for the map key.
- `tile_at(c, hex)` is a **pure lookup** — it returns `nil` for unmaterialized
  hexes and never generates anything.
- `ensure_tile(c, hex)` allocates a tile if missing, computing its terrain with
  `pick_terrain_at`. Returns the `^Tile`.
- `materialize_around(c, center, radius)` loads a hex range of tiles.

**Why pointers?** Pointers into `tiles` stay valid when the array grows, so code
that holds a `^Tile` across an `ensure_tile` call is safe. `tile_at` stays
O(1); the `for t in c.tiles` loops only see materialized tiles (bounded by how
far you've explored).

### When tiles get materialized
- At world-gen: `materialize_around(start, SIM_DISTANCE)`.
- Every turn (step 6 of `colony_end_turn`): `materialize_around(m.pos, SIM_DISTANCE + 3)`
  for each of your monsters — enough room to spawn and roam, plus a fog ring.
- `colony_reveal_around` (moving) reveals the tile + 6 neighbours and loads one
  ring further (the fog border).
- `colony_reveal_radius` (Watchtowers) loads + reveals within a radius.

### Terrain from coherent noise
`biome_at(seed, hex)` samples flat-top world coordinates and blends two
value-noise fBm fields, **elevation × moisture**, into the 11 natural terrains,
plus a high-frequency field for small **Lava / Quicksand** pockets. Everything
is a pure function of `(seed, hex)`, so the world never shifts as you explore.
Key knobs: `TERRAIN_SCALE` (region size), the band thresholds in `biome_at`.

`pick_terrain_at(seed, origin, hex)` layers **Trading Posts (~1.5%, ≥2 from the
entrance)** and **Boss Rooms (~0.8%, ≥6 away)** on top of the biome.

### A safe entrance
- `choose_start_hex(seed)` scans ~13×13 hexes around the origin and picks the
  one with the most neutral (walkable-by-anyone) tiles in a 3-ring, so no
  starter spawns boxed in by type-locked terrain.
- `seed_starting_area(c)` clears a radius-2 chamber of impassable terrain and
  seeds one tile each of Tundra/Jungle/Lava/Quicksand/Grove/Water just outside,
  so the type-locked biomes are reachable early.

`colony_generate(seed, w, h)` ties it together. `w`/`h` are ignored now (kept
for call-site compatibility).

## 2. Terrain & traversal

`Terrain` has 13 values. Traversal is enforced by `tile_passable(c, m, hex)`:

| Terrain | Rule |
|---|---|
| `WATER` | needs a `BRIDGE` or the monster to have `.AQUA` |
| `TUNDRA` | needs `.ICE` |
| `JUNGLE` | needs `.FLORA` |
| `LAVA` | needs `.EMBER` |
| `QUICKSAND` | needs `.GROUND` |
| any + `WALL` improvement | blocked unless `.AIR` |
| everything else | open |

`move_block_reason` turns a blocked move into a readable status line.

`terrain_spawn_chance(t)` is the per-tile wild spawn probability;
`terrain_move_cost(t)` is the movement cost multiplier.

## 3. Improvements

`Improvement` enum: `NONE, FARM, MINE, BRIDGE, GRANARY, TREASURY, WATCHTOWER, WALL, WELL`.

| Proc | Purpose |
|---|---|
| `improvement_valid_on(im, terrain)` | which terrains allow it |
| `improvement_cost(im)` | base price |
| `improvement_cost_scaled(c, im)` | `base + base·count / divisor` |
| `improvement_cost_divisor(im)` | 6 for Walls (they scale at half rate), else 3 |
| `improvement_effect(im)` | the build-panel blurb |
| `can_build` / `buildable_improvements` | placement rules |
| `colony_build(c, hex, im)` | spends gold and **replaces** anything already there |
| `improvement_repair_cost` / `colony_repair` | repair for half base cost, prorated by missing HP |

`improvement_count` counts only **standing** improvements (destroyed ones are
reset to `NONE`), so rebuilding after a raid is no pricier.

- `IMPROVEMENT_HP` (50) is the starting/max health.
- Staffing matters: a Farm/Mine only produces if one of your monsters is on the
  tile (`monsters_on_tile`).
- Watchtower constants: `WATCHTOWER_REVEAL` (6), `WATCHTOWER_DETER` (4),
  `WATCHTOWER_GUARD` (4), `WATCHTOWER_GUARD_BLOCK` (6).

## 4. Economy

**Gold is global.** `colony_total_gold` = stockpile (`c.gold`) + every
Treasury's `stored`. `colony_spend_gold` drains the stockpile first, then
Treasuries. `colony_deposit_gold(c, from, amount)` puts gold into a Treasury
within `DELIVER_RADIUS`, else the stockpile (capped at `BASE_GOLD_CAP`).

**Food is local.** It lives in farms/wells/granaries; there is no global pool.
A monster eats from a Granary or a staffed Farm within `FEED_RADIUS`.

Caps are recomputed by `colony_recompute_caps`: `gold_cap = BASE_GOLD_CAP +
100·(treasuries)`, `food_cap = 100·(granaries)`.

## 5. Movement & energy

**Energy is a single pool shared with battle** — it lives on
`Monster.creature.energy` (there is no `Monster.energy`).

- `colony_move(c, index, target)` returns `0 ok, 1 not adjacent, 2 blocked,
  3 tile full, 4 not enough energy`, and spends `monster_move_cost`.
- `monster_move_cost(m, terrain) = terrain_move_cost · clamp(10/speed, 0.6, 1.6) · 0.5`
  (the `·0.5` keeps the map feeling like it used to when the pool was larger).
- `creature.energy_max` / `energy_regen` scale with level
  (`creature_stats_for_level`), so higher-level monsters move and cast more.

## 6. The turn loop — `colony_end_turn(c)`

Runs in a fixed order. **Read this top-to-bottom before changing any economy.**

1. **Mines** — every staffed Mine deposits `MINE_GOLD_YIELD` (4).
2. **Food production** — build `farm_pool[]` (parallel to `tiles`): a staffed
   Farm = `FARM_FOOD_YIELD` (6), any Well = `WELL_FOOD_YIELD` (2). The array
   length is pinned (`n_tiles`) because step 2b can materialize new tiles.
   2b. **Watchtowers** re-reveal `/` load` their surroundings.
3. **Farms deliver** surplus to a Granary within `DELIVER_RADIUS` (else wasted).
4. **Feed monsters** (range-gated): eat from a Granary, else a Farm/Well pool.
   Fed → `+REFILL_FRAC` satiety (full bar heals); unfed → `−STARVE_FRAC`, and at
   zero satiety the monster takes damage.
5. **Deaths & regen** — 0-HP monsters go to the graveyard; survivors gain
   `energy_regen` (capped at `energy_max`).
6. **Wilds** — load the neighbourhood, tick down `scuffle` markers, then:
   `colony_spawn_wilds → colony_roam_wilds → colony_despawn_wilds →
   colony_crowd_fights → colony_resolve_wild_actions`.

Then `c.turn += 1`.

> **Hazard:** anything in steps 1–4 that calls `ensure_tile` would grow `tiles`
> and desync `farm_pool`. That's why `farm_pool` is sized against `n_tiles` and
> Watchtower reveals only touch already-materialized tiles.

## 7. Wild monsters

- **Spawn** (`colony_spawn_wilds`): iterate materialized tiles; skip if
  `tile_prevents_spawn` (Farm/Mine), if guarded, if within a Watchtower's
  `WATCHTOWER_DETER`, or if farther than `SIM_DISTANCE` from your nearest
  monster. Otherwise roll `< terrain_spawn_chance(t) · spawn_ramp(turn)`.
  `spawn_ramp` gives a **grace period** (`SPAWN_GRACE_TURNS = 30`): from 10% to
  full rate over the first 30 turns.
- **Level** (`spawn_level_for`) scales with distance from the entrance
  (`start_hex`) and `floor`.
- **Roam** (`colony_roam_wilds`): each wild sometimes steps to a passable
  neighbour (may not move). Type gates apply, so an Ice wild can leave Tundra but
  a neutral monster can't enter it.
- **Despawn** (`colony_despawn_wilds`): far wilds may wander off; a hard cap
  (`MAX_WILDS`) culls the farthest.
- **Crowd fights** (`colony_crowd_fights`): too many wilds on one tile may
  brawl, killing one and leaving a `scuffle` marker.
- **Act** (`colony_resolve_wild_actions`): a wild on an **unguarded** improved
  tile damages it (`damage_improvement`); a wild sharing a tile with your
  monster pushes that tile onto `pending_tiles`, which `start_next_attack`
  turns into an **ambush** battle.

`damage_improvement` reduces HP, and on destruction notifies, drops `stored`,
resets to `NONE`, and recomputes caps.

## 8. Notifications

`colony_notify(c, fmt, ...)` keeps the last 5 strings in `c.messages`; the HUD
draws them centered near the bottom (see [ui-and-input.md](ui-and-input.md)).

## Tuning knobs (colony.odin, top of file)

`MAX_MONSTERS_PER_TILE`, `REFILL_FRAC`, `STARVE_FRAC`, `STORAGE_CAP`,
`BASE_GOLD_CAP`, `FEED_RADIUS`, `DELIVER_RADIUS`, `MAX_WILDS`, `SIM_DISTANCE`,
`DESPAWN_DISTANCE`, `DESPAWN_CHANCE`, `CROWD_LIMIT`, `CROWD_FIGHT_CHANCE`,
`FARM_FOOD_YIELD`, `WELL_FOOD_YIELD`, `MINE_GOLD_YIELD`, the four `WATCHTOWER_*`,
`IMPROVEMENT_HP`, `TERRAIN_SCALE`, `SPAWN_GRACE_TURNS`.
