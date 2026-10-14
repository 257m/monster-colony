# Architecture

## Files

| File | Lines* | Responsibility |
|---|---|---|
| `src/main.odin` | ~775 | `Game` state, `main()`, lifecycle, update/draw dispatch, colony update, build/trade update |
| `src/ui_colony.odin` | ~660 | Colony-screen rendering: map monsters, floats, HUD, roster, legend |
| `src/ui_panels.odin` | ~1585 | Every overlay panel: deck, dexes, bag, upgrades, nursery, storage, save, arena, build/trade |
| `src/ui_screens.odin` | ~240 | Title, starter picker and game-over screens |
| `src/ui_draw.odin` | ~180 | Shared UI drawing: `draw_panel`, `draw_button` (+ styles), `draw_row`, `List_View` (list nav + chrome) |
| `src/battle_glue.odin` | ~700 | Map ⇄ battle glue: attacker picker, begin/update/resolve, results |
| `src/colony.odin` | ~1860 | Constants, types, improvement table, terrain, hex/grid, generation, economy, turn loop, movement |
| `src/colony_improvements.odin` | ~250 | Improvement metadata accessors, build/cost/repair, heat |
| `src/colony_wilds.odin` | ~685 | Wild spawning/roaming/AI, raids, heat, alphas |
| `src/colony_storage.odin` | ~315 | Dens/Nurseries: stasis, breeding, item cap |
| `src/battle.odin` | ~1665 | The battle engine + battle rendering |
| `src/creature.odin` | ~830 | `Species` table, `Creature` struct, stat/level helpers, genetics |
| `src/abilities.odin` | ~120 | Species ability pools, names/descriptions, battle-start hook |
| `src/items.odin` | ~110 | Item table, effects, battle-start hook |
| `src/upgrades.odin` | ~176 | Crystal progression tree: upgrades, costs, effect readers |
| `src/web.odin` | ~93 | Browser (wasm) entry: exported `main_start` / `main_update` / … |
| `src/web_allocator.odin` | ~110 | Emscripten-backed allocator used by the web build |
| `src/moves.odin` | ~292 | `Element` chart, `Move` struct, `MOVE_DATA`, `Move_Id` enum |
| `src/hex_math.odin` | ~100 | Axial hex coordinate math (incl. `hex_range`) |
| `src/hex_render.odin` | ~140 | Hex <-> screen transforms, camera, hex drawing, `visible_hex_bounds` |
| `src/improvement_icons.odin` | ~355 | Animated improvement icons drawn on the map |
| `src/tile_detail.odin` | ~158 | Procedural per-terrain tile detail (rocks, grass, mushrooms…) |
| `src/rng.odin` | ~49 | SplitMix64 PRNG |
| `src/audio.odin` | ~384 | Synthesised sound effects + looping music (no asset files) |
| `src/shaders.odin` | ~170 | Card/relic panel fragment shader (GLSL 330 desktop / 100 web) + `shader_panel` |
| `src/font.odin` | ~60 | `draw_text` / `measure_text` over a loaded TTF (falls back to the default font) |
| `src/relics.odin` | ~120 | Stackable boss relics: table, effect readers, grant/apply |
| `src/milestones.odin` | ~90 | Quest board: milestone table, progress, completion |
| `src/save.odin` | ~495 | Save format: serialization + slots + panel data |
| `src/save_io_desktop.odin` | ~25 | Save file I/O (`#+build !js`) |
| `src/save_io_js.odin` | ~20 | Save stubs for the browser build (`#+build js`) |

\* Approximate; use `wc -l` for exact counts.

## The core types

### `Creature` (`creature.odin`)
A single fighter. This is the unit both the colony and battle care about.

```
species, name, level, xp
hp, max_hp
block, vulnerable, strength, defense_buff, defense_debuff   // per-battle state
power, defense, speed     // floats, scaled from the species by level
energy, energy_regen, energy_max   // ONE pool shared map <-> battle
genes: [Gene]int          // 0-5 per-stat genetic bonus (Phase 8)
deck, draw_pile, hand, discard     // Move_Id arrays
played                    // cards played this turn (combo synergy)
shake, flash              // transient draw-only feedback
```

`Creature` **owns** its `deck`/piles (heap arrays) — see `creature_copy`,
`creature_free_piles`, `creature_free_all`.

### `Monster` (`colony.odin`)
A `Creature` **standing on the map**. Owns colony-only state:

```
id, creature, pos: Hex, wild: bool, food, role: Wild_Role, stored: Stored_In
```

Your party and enemy wilds are *both* `Monster`s in `Colony.roster`; `wild`
distinguishes them. `role` (Phase D) marks wilds as `WILD` (roams randomly),
`RAIDER` (marches on your nearest monster) or `ALPHA` (hunts improvements).
`stored` (Phase 10) is `.MAP` for monsters on the map; monsters inside a Den or
Nursery live in `Colony.storage` instead (see below). (Note: `xp` lives on
`Creature` now, not `Monster`.)

### `Tile` (`colony.odin`)
```
hex, terrain: Terrain, revealed: bool,
improvement: Improvement, overlay: Improvement, improvement_hp, overlay_hp,
stored, scuffle
```
`stored` = food (Granary/Silo) or gold (Treasury). `overlay` is the stackable
improvement slot (Road/Scarecrow/Spike Trap), with its own `overlay_hp`.

### `Colony` (`colony.odin`)
```
tiles: [dynamic]^Tile, tile_index: map[u64]int   // the infinite map
roster, graveyard: [dynamic]Monster
storage: [dynamic]Monster   // monsters in Dens/Nurseries (Phase 10)
choices: [dynamic]Move_Choice // pending level-up / reward card picks
gold, crystals, capture_cards, gold_cap, food_cap
turn, floor, seed, rng, start_hex, next_id
pending_tiles: [dynamic]Hex   // tiles where a wild and your monster share
messages: [dynamic]string     // world notifications
floats:   [dynamic]Tile_Float // transient per-tile production popups
shop:     [dynamic]Shop_Offer // Trading Post stock, rerolled each turn
items:    [dynamic]Item       // unequipped item bag
upgrades: [Upgrade]int        // crystal progression levels
heat, raid_timer, raids       // Phase D: raid pressure + scheduling
```

### `Game` (`main.odin`)
Owns the whole session:
```
mode: Game_Mode (TITLE|STARTER|MAP|BATTLE|GAME_OVER), renderer, colony, has_colony,
selected, quit
show_deck/view_index/view_scroll, show_encyclopedia/...
status, status_timer
build_mode/build_hex/has_build, trade_open
battle: Battle, has_battle, battle_choice_open, battle_hex, battle_forced, ...
attack_select_open, attack_ids, attack_chosen
results_open, results: Battle_Results
seed_rng
```

### `Battle` (`battle.odin`)
```
party, enemies: [dynamic]^Creature   // pointers INTO colony Monsters
party_done:   [dynamic]bool          // per party member: ended its turn this turn
enemy_ids, captured_ids: [dynamic]int
target, active, enemy_acting, capture_cards
phase: Battle_Phase, round, timer
order: [dynamic]Actor, order_pos     // the initiative queue (every living monster)
rng, log, popups, shake
```

`Actor` is `{ side: Battle_Side, index: int }` — all of your party and every
wild share one Speed-sorted queue. `active` is just "the party member whose turn
it currently is" (for the UI); there is no benched party.

**Ownership rule:** `Battle.party`/`enemies` are *borrowed pointers* to
`Creature`s owned by `Colony.roster`. The battle never clones them; it mutates
HP/energy/statuses directly, and frees only the transient piles via
`battle_free`.

## Data flow

### Session lifecycle
```
main() -> reset_to_starter(g)                  # clears any run, mode = STARTER
       -> choose_starter(g, species)           # colony_generate + add_starter, mode = MAP
       -> loop { game_update(g, dt); game_draw(g) }
       -> end_run(g)                           # colony_free
```

### One colony turn
```
Space/E or the End Turn button -> do_end_turn(g)
  colony_end_turn(&g.colony)        # economy, feeding, wilds (see colony.md)
  if no player monsters -> mode = GAME_OVER
  start_next_attack(g)              # pop pending_tiles -> open an ambush battle
```

### One battle
```
update_colony: player attacks a tile
  build_attack(g, hex, 1); attack_select_open = true   # choose attackers
  -> begin_battle(g, auto)
       defs  = chosen defenders (or tile monsters for an ambush)
       enemies = wilds on the tile
       g.battle = battle_start(defs, enemies, ids, &g.seed_rng)
       apply Watchtower starting Block
       mode = BATTLE

update_battle -> battle_update + battle_input  (engine drives itself, see battle.md)
  phase WON  -> resolve_won(g)   # loot, xp, level-ups, card drop, reaps wilds
  phase LOST -> resolve_lost(g)  # graves your dead monsters; game over if none left
```

`finish_battle` copies `capture_cards` back to the colony and frees the battle.
`resolve_won`/`resolve_lost` are the only places that write battle outcomes back
into the colony.

## Rendering / update routing

`game_update` and `game_draw` (`main.odin`) are the dispatch tables. Overlays
are handled **before** the mode switch and return early, in priority order:

```
deck viewer > encyclopedia > attack-select > battle-choice > results
> V (deck) > { STARTER | MAP | BATTLE | GAME_OVER }
```

If you add a new modal overlay, you must add it to **both** `game_update`
(early-return branch) and `game_draw` (draw after the mode switch), and clear it
in `reset_to_starter`. See [ui-and-input.md](ui-and-input.md).

## Where to look for what

| I want to change… | Go to |
|---|---|
| A monster's stats / learnset / deck | `SPECIES` in `creature.odin` (see [content.md](content.md)) |
| A card's numbers or add a card | `Move_Id` + `MOVE_DATA` in `moves.odin` |
| How much damage a hit does | `apply_damage` / `estimate_damage` in `battle.odin` |
| Turn order in battle | `build_order` / `advance` / `begin_round` in `battle.odin` |
| A species' abilities | `ABILITY_POOLS` / `ability_*` in `abilities.odin` |
| A crystal upgrade | `UPGRADES` / `upgrade_*` in `upgrades.odin` |
| Terrain effects / spawn rates | `terrain_*` procs in `colony.odin` |
| Raid pressure / raid timing | `colony_heat` / `colony_raids` in `colony.odin` |
| What an improvement does / costs | `improvement_*` procs in `colony.odin` |
| The economy / turn loop | `colony_end_turn` in `colony.odin` |
| Wild AI (spawn/roam/attack) | `colony_spawn_wilds` … `colony_resolve_wild_actions` |
| A panel or HUD line | the `draw_*` procs in `main.odin` |
| Input | `game_update` + the per-mode `update_*` procs |
