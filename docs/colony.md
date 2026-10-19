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
Elevation bands are **Water < 0.40** and **Cave < 0.48** (water is deliberately
generous, ~20% of the map, so lakes and coastlines shape the colony), then
moisture picks the mid/high biomes.

`pick_terrain_at(seed, origin, hex)` layers **Trading Posts (~1.5%, ≥2 from the
entrance)** and **Boss Rooms (~0.8%, ≥6 away)** on top of the biome.

### Trading Post & rarity
Every species has a `Rarity` (`COMMON..LEGENDARY`) that scales capture odds,
kill loot and the shop. The Post's **stock of monsters for sale is rerolled each
turn**: `colony_roll_shop` (called from `colony_end_turn`) makes two
rarity-weighted picks via `shop_pick_species`, prices them with `recruit_price`,
and `colony_buy_recruit` places a bought monster at `find_placement_tile`
(entrance or beside it). The heal / energy / revive / capture-card services
remain. Kill loot uses `species_loot_gold`.

### Overlays, upgrades & the Arena
`improvement_stacks` marks `ROAD`, `SCARECROW` and `SPIKE_TRAP` as **overlays** —
they live in `Tile.overlay` so they share a tile with a building (only one
overlay per tile). `tile_has` and the trap pass (`colony_apply_traps`) consider
overlays, so a Spike-Trap overlay still hurts wilds; `colony_build` routes them
to the overlay slot and stamps `Tile.overlay_hp`. `damage_improvement` hits the
building first and the overlay after, and `colony_repair` / `tile_repair_target`
repair whichever is damaged.

**Crystals** buy permanent upgrades in a **tree** of 26 nodes
(`src/upgrades.odin`): `colony_buy_upgrade` spends them (children need their
parent at `req_level`), and the `upgrade_*` helpers feed per-turn yields,
build/repair cost (`upgrade_masonry_mult`), improvement HP (`improvement_hp_cap`
for Fortify / Reinforced Mounts), storage (`storage_cap`), movement cost,
turret damage/range/cost/cap, spike damage, barracks XP, loot/food/XP, capture
odds and per-battle Block. The panel is on **`U`**. Crystals come mainly from
**fights** (Arena / Boss Rooms, boosted by Spoils); the Crystal Refinery is a
slow trickle (1 per 6 turns).

**Crystal Cove** terrain (`~1.2%`, ≥3 from the entrance) is the **only** tile a
`CRYSTAL_REFINERY` can be built on (`improvement_valid_on`), and a refinery only
refines while **staffed** (a monster standing on it) — see the refinery pass in
`colony_end_turn`. It has glowing-shard tile art and its own spawn table.

**Arena** terrain (~0.6%, ≥4 from the entrance) has no spawns. Standing on it and
pressing `T` opens the **Arena screen** (its own `Game_Mode.ARENA`, not a modal —
see [ui-and-input.md](ui-and-input.md)). The colony is frozen while a run is live:
the party you brought is the party you climb with, and the only exits are cashing
out or abandoning.

The Arena is a **run**, not a ladder of one-off fights:

- One **flat** entry fee (`ARENA_ENTRY_COST`) buys a chain of floors that always
  starts at **floor 1**. Each cleared floor **banks** its purse; the run ends when
  you **cash out** (banking the winnings) or your party **wipes** (losing them).
- `arena_floor_purse` is back-loaded: nothing at all for the first
  `ARENA_PURSE_DELAY` (10) floors, then a crystal a floor bending up slowly
  (floor 50 → 1, 100 → 3, 250 → 7, 1000 → 49). A run to floor 100 banks ~150.
- **The challengers level on your curve, and never read your team.** A run banks
  its own entry level (`arena_base_level`, the party average when the run
  started) and walks the floors letting the tower earn what a monster would earn
  from the same fights — one kill's XP per challenger at the level being fielded
  — then reads a level off that total with `xp_to_next` (`arena_challenger_level`).
  Nothing in it reads your monsters as they stand, so holding them back gains
  nothing.
- Species are picked by a **soft band over roster rank** (`arena_species_weight`),
  so floor 1 is weak wilds, the middle is the evolved lines and the deep floors
  are the bosses — plus the **elite** species that fill the gap between them. A
  non-boss gets a level multiplier (`arena_regular_level_mult`) so deep floors
  stay mixed rather than all bosses.
- Every **tenth** floor is a **trial** (`arena_trials.odin`): a **gym** (a fixed,
  themed team from a cycling list, at `ARENA_GYM_LEVEL_MULT`) or, every third
  trial, an **event** — a decision floor with no fight that offers a card, an
  item, an ability, a run boon or a rest, and always the option to walk on.
- The run has its own seed (`arena_run_seed`), which fixes the gym order and the
  event offers for that run — and its own **pack** (`arena_items`, unbounded) and
  **boons** (`arena_boons`). Cashing out keeps the pack; a wipe or an abandon
  loses it along with the winnings.
- `colony_spawn_arena_team` builds each floor's team; `arena_clear_floor` banks a
  cleared floor, climbs, and hands out the tower's rest; `arena_reset` clears the
  tile after a loss.

### Raids, heat & alphas (Phase D)
`colony_heat` = `colony_improvement_heat/3 + total_monster_levels/6`, clamped to
`HEAT_MAX`; **nothing lowers it** (defences don't cool the colony) and it counts
every standing building *and* overlay, each by its own weight (`improvement_heat`:
**1** roads/walls/gates/bridges/traps, **2** ordinary production/support,
**3** watchtower/turret, **4** beacon/refinery). It's recomputed each turn and
shown in the HUD. Once past `RAID_GRACE`, `colony_raids` counts `raid_timer` down
(from turn 0, so the grace doesn't double-delay it) and then spawns a band of
**raiders** (role `RAIDER`) in a ring around `player_center`, sized, cadenced
**and levelled** by heat (`raid_size` = `2 + heat/4`, up to `RAID_MAX_SIZE` 14;
`raid_interval`; `raid_level_bonus`), with an **alpha** (`ALPHA`, **double the
raiders' level**) leading hot raids. Raid spawns **ignore spawn deterrence**
(they don't check `tile_prevents_spawn` or watchtower/beacon/scarecrow radii).
The HUD shows `Raids from turn 35` / `Raid in N` / `Raid calm (low heat)` and a
notification fires when the grace ends. In `colony_roam_wilds`, non-`WILD` roles
use `step_hunt`: raiders head to `nearest_player_or_improvement_hex` (the closer
of your monsters and your buildings), alphas to `nearest_player_hex` (your
monsters), battering fortifications in the way. They're skipped by
despawn/scarecrow/the wild cap.

**Threat variety (Phase 21).** Two specialist roles now mix into raids:
**sieges** (`SIEGE`) march on `nearest_improvement_hex` and deal **double**
improvement damage (`wild_improvement_damage`), and **stalkers** (`STALKER`)
take **two** `step_hunt` steps a turn and slip past fortifications
(`step_hunt(..., ignore_walls = true)` → `terrain_passable`). The share of
specialists grows with `colony_escalation`. On the map, sieges draw a heavy
double red ring and stalkers a pale flickering ring.

**Escalation (Phase 21).** `spawn_level_for` adds `colony_escalation` (`turn/20`)
and clamps up to **2/3 of `player_top_level`**, so wilds and raids stay relevant
as the run drags on — progression can't trivialise the map. `tile_passable` now
delegates its terrain gate to `terrain_passable`, reused by stalkers.

**Boss packs (Phase 25).** A revealed **Boss Room** within `BOSS_SPAWN_RANGE` of
your nearest monster grows a **pack of six** (`colony_spawn_boss_packs` →
`colony_spawn_boss_pack`): one of four unique `BOSS_SPECIES` plus five themed
cronies (`boss_cronies`), sharing a `Monster.pack` id. The timer lives in
`Tile.stored` (Boss Rooms hold no production), so packs **respawn** every
`BOSS_RESPAWN_TURNS` for relic farming. `colony_roam_boss_packs` moves a pack as
a **unit**: the boss picks the step toward `nearest_player_hex` and the retinue
follows. Packs are skipped by despawn/scarecrow/the wild cap, and a Boss Room win
drops a **relic** (see [content.md](content.md#relics-relicsodin)).

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
| any + `GATE` improvement | blocked for **wilds only**; your monsters pass |
| everything else | open |

`move_block_reason` turns a blocked move into a readable status line.

`colony_demolish(c, hex)` tears down the **overlay** first (so a Road can be
peeled off a building) or the building, refunding `improvement_refund` = **50% of
the base cost** (`IMPROVEMENT_REFUND_PCT`) into the stockpile. The build panel's
**Demolish** button (`build_demolish_rect`) asks for a confirm
(`Confirm_Kind.DEMOLISH`) first.

`terrain_spawn_chance(t)` is the per-tile wild spawn probability;
`terrain_move_cost(t)` is the movement cost multiplier. Step cost goes through
`monster_step_cost(c, m, hex)` (which applies a `ROAD` discount).

## 3. Improvements

`Improvement` enum: `NONE, FARM, MINE, BRIDGE, GRANARY, TREASURY, WATCHTOWER, WALL, WELL, GATE, SPIKE_TRAP, SCARECROW, ROAD, SILO, CRYSTAL_REFINERY, FOUNTAIN, TURRET, DRAWBRIDGE, QUARRY, LUMBER_MILL, MARKETPLACE, KITCHEN, BARRACKS, BEACON, DEN, VAULT, NURSERY, MENDER`.

Beyond production, several are **defensive** and there's now an **energy network**:
`GATE`/`DRAWBRIDGE` block wilds (the drawbridge toggles raised/lowered);
a wild whose step is blocked by a `WALL`/`GATE` (or a raised `DRAWBRIDGE`) **batters
the blocker** instead of walking around — see `colony_roam_wilds` and
`improvement_blocks_wilds`, using `wild_improvement_damage`;
`SPIKE_TRAP`/`TURRET` deal damage (`colony_apply_traps` / `colony_turrets`) —
spike traps take a **percentage** of the wild's max HP
(`SPIKE_TRAP_DAMAGE_PCT` 15% + `upgrade_spike_pct`), so they keep pace;
`SCARECROW` deters spawns and spooks nearby wilds into **moving a couple of tiles
away** (they don't despawn), `WATCHTOWER` reveals and gives defenders starting
Block, and `BEACON` reveals over a wider radius and makes attacking wilds start
**Vulnerable** (`BEACON_VULN`, applied in `begin_battle`).
`FOUNTAIN` hands energy to the closest unit, Turret or Mender
(`colony_fountains`); `TURRET` needs that charge to fire, and `MENDER` spends
charge to repair every damaged improvement within `MENDER_REPAIR_RANGE` by
`MENDER_HEAL` HP per turn (`colony_menders`) — energy reaches it via the
Fountain's `FOUNTAIN_RANGE`, exactly like a Turret. `MARKETPLACE` boosts nearby
Mines, `KITCHEN` spends food for battle-start Strength, and `BARRACKS` eats food
to heal (a **percentage** of max HP, `BARRACKS_HEAL_PCT` 8%) + train nearby
monsters. `QUARRY`/`LUMBER_MILL` are the second producer
chain (Lumber needs water adjacent). `ROAD` halves step cost, `SILO` adds food
storage, and `CRYSTAL_REFINERY` converts gold into crystals each turn.

**Stacking:** `improvement_stacks(im)` is true for `ROAD`. Such an improvement is
stored in a tile's `overlay` slot instead of replacing the building, so a Road
can sit under a Farm. `tile_has(t, im)` checks building *or* overlay, and
`improvement_count`/`near_improvement`/`nearest_improvement_within` use it. When
the building is later replaced the overlay survives; wilds only ever damage the
building.

| Proc | Purpose |
|---|---|
| `improvement_valid_on(im, terrain)` | which terrains allow it |
| `improvement_cost(im)` | base price |
| `improvement_cost_scaled(c, im)` | `base + base·count / divisor` |
| `improvement_cost_divisor(im)` | 6 for Walls/Gates/Roads/Scarecrows/Spike Traps (bulk), else 3 |
| `improvement_max_hp(im)` | per-type health (Gate 30 < Wall 50, etc.) |
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
  3 tile full, 4 not enough energy, 5 already acted`, and spends
  `monster_move_cost`.
- `monster_move_cost(m, terrain) = terrain_move_cost · clamp(10/speed, 0.7, 1.6)`.
  `terrain_move_cost` is the **real** cost per tile you're **entering** — 0.7
  Grove/Mushroom up to 1.45 Quicksand, with no global multiplier on top — so
  tuning the map's pace means editing that one table. Routes and Roads matter
  (a Road halves the step).
- **Attacking ends the turn** (`Monster.acted`, set in `begin_battle`, cleared in
  `colony_end_turn`): a monster that fought can't move again until next turn, so
  you can't chain fights to keep moving on battle-refilled energy. Acted monsters
  show `(done)` in the roster and red move hints.
- Clicking a wild tile opens the attacker picker **without moving**;
  `attack_move_attackers` (called on commit in `update_attack_select`) steps the
  chosen attackers onto the tile, so cancelling costs nothing.
- `creature.energy_max` / `energy_regen` grow **logarithmically** with level
  (`creature_stats_for_level` → `energy_scale`, no hard cap), so higher-level
  monsters get a little more but energy stays a real constraint. Both are **raw
  species values** — `base_energy` (regen, 1.5) and `base_energy_max` (bank,
  4–6) — with no multiplier applied on top.
- **The bank (`base_energy_max`) is deliberately small** — 4–6, against a regen
  of ~1.5–2 per turn. It is the bank that decides how hard a fight opens, because
  energy carries over and creatures enter a battle holding a full one. With the
  old 8–12 banks, turn one could dump a whole hand and fights averaged 2.7
  rounds; halving them took that to 4.1. X-cost cards (`All_In`, `Bulwark`,
  `Overcharge`) spend the whole bank, so they scale with it — they were doubled
  when the banks were halved.

## 6. The turn loop — `colony_end_turn(c)`

Runs in a fixed order. **Read this top-to-bottom before changing any economy.**

1. **Mines** — every staffed Mine deposits `MINE_GOLD_YIELD` (4).
2. **Food production** — build `farm_pool[]` (parallel to `tiles`): a staffed
   Farm = `FARM_FOOD_YIELD` (6), any Well = `WELL_FOOD_YIELD` (2). The array
   length is pinned (`n_tiles`) because step 2b can materialize new tiles.
   2b. **Watchtowers** re-reveal `/` load` their surroundings.
3. **Farms deliver** their pool to the nearest food store (Granary/Silo) within
   `DELIVER_RADIUS` via `colony_store_food`, **spilling over to the next store in
   range whenever one fills**; only food past *every* store in range is wasted.
4. **Feed monsters** (range-gated): eat from the nearest food store that holds
   enough (`nearest_food_store_with`), else a Farm/Well pool.
   Fed → `+REFILL_FRAC` satiety (full bar heals); unfed → `−STARVE_FRAC`, and at
   zero satiety the monster takes damage. **Fainted monsters (0 HP) are skipped**
   — otherwise a full meal would heal them above 0 before step 5 and they'd
   "revive" instead of dying. Leveling up likewise never heals a fainted monster.

Steps 1–4 also call `colony_add_float` so the map shows a brief `+4g`/`+6f`
production popup on the tile (see [ui-and-input.md](ui-and-input.md)).
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
  (`start_hex`), `floor`, `colony_escalation` (`turn/20`) and never falls below
  **2/3 of `player_top_level`** — so wilds stay relevant as the run goes on.
- **Deck** (`enrich_wild_deck`, called from `spawn_wild_at`): wilds don't keep
  the plain starter deck. They get their **learnset moves up to their level**, a
  **thematic status card** at level 8+ (`thematic_status_move`), then starter
  basics to fill, capped at `WILD_DECK_MAX` (12). So a level-20 wild fights with
  real cards, and high-level fights are genuinely harder.
- **Roam** (`colony_roam_wilds`): every wild steps each turn (no staying put).
  Plain wilds pick a **random** passable neighbour (a random start heading, then
  the first passable one clockwise); role wilds `step_hunt` **greedily** toward
  their target. Type gates apply, so an Ice wild can leave Tundra but a neutral
  monster can't enter it.
- **Despawn** (`colony_despawn_wilds`): far wilds may wander off; a hard cap
  (`MAX_WILDS`) culls the farthest.
- **Crowd fights** (`colony_crowd_fights`): too many wilds on one tile may
  brawl, killing one and leaving a `scuffle` marker.
- **Act** (`colony_resolve_wild_actions`): a wild on an **unguarded** improved
  tile damages it (`damage_improvement`); a wild sharing a tile with your
  monster pushes that tile onto `pending_tiles`, which `start_next_attack`
  turns into an **ambush** battle.

`damage_improvement` reduces HP, records `hit_t0` (for the map's damage shake +
red flash) and a `.DAMAGE` float, and on destruction notifies, drops `stored`,
resets to `NONE`, and recomputes caps.

## 8. Breeding & genetics (Phase 8)

- Every `Creature` carries `genes: [Gene]int`, a **0–5 bonus per stat** (HP,
  Power, Defense, Speed, Energy). `creature_recompute_stats` applies each point as
  **+5%** on the species base, before item bonuses, so genes survive level-ups
  and gear changes.
- Wilds, shop recruits and starters **roll** their genes on the rarity curve
  (`genes_roll_random` → `gene_roll_random`, weights `GENE_WEIGHTS`).
- Breeding happens in a **Nursery** (see section 10): `genes_breed` averages the
  pair (`gene_breed_mid`, rounded up) then rolls **−1..+1**, with a rare
  `GENE_MUTATE_CHANCE` (5%) extra +1.

## 9. Storage & the Nursery (Phase 10)

Stored monsters live in `Colony.storage` (a `Monster` list), not `roster`, so
they are naturally skipped by the turn loop, heat, spawning, drawing and
selection. `Monster.stored` (`Stored_In`: `MAP`/`DEN`/`NURSERY_PARENT`/
`NURSERY_BABY`) and `Monster.stored_hex` say where.

- **Den** (`DEN_CAPACITY` 32): `colony_store_monster` moves a map monster within
  `STORE_RANGE` (1) of a Den into stasis; `colony_deploy_stored` puts it back at
  the Den (or beside it). No upkeep, no heat.
- **Vault**: `colony_item_cap` = `BASE_ITEM_CAP` (8) + `VAULT_ITEM_CAP` (12) per
  Vault; fight-loot only fits while there is room.
- **Nursery** (`NURSERY_PARENTS` 2, `NURSERY_BABIES` 4): `colony_assign_parent`
  moves a same-species `BREED_MIN_LEVEL` (5) monster **within `STORE_RANGE` (1)**
  of the Nursery into the pair; `colony_nurseries` runs each turn — a full pair
  eats `NURSERY_FOOD_PER_TURN` (2) from a nearby store and, every
  `NURSERY_PERIOD` (8) fed turns, calls `colony_nursery_birth` to hatch a level 1
  baby into storage.
- `colony_evacuate_storage` is called when a Den/Nursery is destroyed or replaced:
  occupants are pushed back onto the map, or lost if there is no room.

## 10. Notifications

`colony_notify(c, fmt, ...)` keeps the last 5 strings in `c.messages`; the HUD
draws them centered near the bottom (see [ui-and-input.md](ui-and-input.md)).

## Tuning knobs (colony.odin, top of file)

`MAX_MONSTERS_PER_TILE`, `REFILL_FRAC`, `STARVE_FRAC`, `STORAGE_CAP`,
`BASE_GOLD_CAP`, `FEED_RADIUS`, `DELIVER_RADIUS`, `MAX_WILDS`, `SIM_DISTANCE`,
`DESPAWN_DISTANCE`, `DESPAWN_CHANCE`, `CROWD_LIMIT`, `CROWD_FIGHT_CHANCE`,
`FARM_FOOD_YIELD`, `WELL_FOOD_YIELD`, `MINE_GOLD_YIELD`, the four `WATCHTOWER_*`,
`DEN_CAPACITY`, `STORE_RANGE`, `BASE_ITEM_CAP`, `VAULT_ITEM_CAP`,
`NURSERY_PARENTS`, `NURSERY_BABIES`, `NURSERY_FOOD_PER_TURN`, `NURSERY_PERIOD`,
`IMPROVEMENT_HP`, `TERRAIN_SCALE`, `SPAWN_GRACE_TURNS`.
