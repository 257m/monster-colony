# Architecture

## Files

| File | Lines* | Responsibility |
|---|---|---|
| `src/main.odin` | ~1075 | `Game` state, `main()`, lifecycle, update/draw dispatch, colony update, build/trade update |
| `src/ui_colony.odin` | ~1170 | Colony-screen rendering: map monsters, floats, HUD, roster, legend |
| `src/ui_panels.odin` | ~3600 | Every overlay panel: the dex, inventory, upgrades, quests, nursery, storage, save, arena, event |
| `src/ui_screens.odin` | ~230 | Title, starter picker and game-over screens |
| `src/ui_draw.odin` | ~395 | Shared UI drawing: `draw_panel`, `draw_button` (+ styles), `draw_row`, `draw_scrollbar`, `List_View`, tooltips, `fit_text` |
| `src/screen.odin` | ~90 | The design-space layer: `screen_w`/`screen_h`, `mouse_pos`, `ui_camera`, `scissor_*` |
| `src/battle_glue.odin` | ~865 | Map ⇄ battle glue: attacker picker, begin/update/resolve, results |
| `src/colony.odin` | ~2240 | Constants, types, improvement table, terrain, hex/grid, generation, economy, turn loop, movement |
| `src/colony_improvements.odin` | ~295 | Improvement metadata accessors, build/cost/repair, heat |
| `src/colony_wilds.odin` | ~1545 | Wild spawning/roaming/AI, raids, heat, alphas, **and the Arena's team builder** |
| `src/arena_trials.odin` | ~605 | Arena gyms, event floors, run boons, the sample team |
| `src/colony_storage.odin` | ~315 | Dens/Nurseries: stasis, breeding, item cap |
| `src/battle.odin` | ~3445 | The battle engine + battle rendering |
| `src/creature.odin` | ~1430 | `Species` table, `Creature` struct, stat/level helpers, genetics, sets lookup |
| `src/sets.odin` | ~570 | `SPECIES_SETS`: every species' three Arena loadouts (ability + item + deck) |
| `src/abilities.odin` | ~305 | Species ability pools, names/descriptions, battle hooks |
| `src/powers.odin` | ~140 | Per-battle POWER effects (Toxic, Rage, Combustion, …) |
| `src/items.odin` | ~165 | Item table, effects, battle-start hook |
| `src/relics.odin` | ~275 | Relic table, Relic Towers, range, battle application |
| `src/upgrades.odin` | ~225 | Crystal progression tree: upgrades, costs, effect readers |
| `src/milestones.odin` | ~165 | The quest board's milestones (incl. per-boss and Arena floors) |
| `src/world_events.odin` | ~125 | Random world events (spawns, alphas, tremors) |
| `src/skirmish.odin` | ~105 | Headless auto-battles, for testing balance |
| `src/web.odin` | ~110 | Browser (wasm) entry: exported `main_start` / `main_update` / … |
| `src/web_allocator.odin` | ~110 | Emscripten-backed allocator used by the web build |
| `src/moves.odin` | ~785 | `Element` chart, `Move` struct, `MOVE_DATA`, `Move_Id` enum |
| `src/hex_math.odin` | ~105 | Axial hex coordinate math (incl. `hex_range`) |
| `src/hex_render.odin` | ~145 | Hex <-> screen transforms, camera, hex drawing, `visible_hex_bounds` |
| `src/improvement_icons.odin` | ~415 | Animated improvement icons drawn on the map |
| `src/tile_detail.odin` | ~220 | Procedural per-terrain tile detail (rocks, grass, mushrooms…) |
| `src/rng.odin` | ~45 | SplitMix64 PRNG |
| `src/audio.odin` | ~470 | Synthesised sound effects + looping music (no asset files) |
| `src/save.odin` | ~595 | Save format: serialization + slots + panel data |
| `src/save_io_desktop.odin` | ~25 | Save file I/O (`#+build !js`) |
| `src/save_io_js.odin` | ~20 | Save stubs for the browser build (`#+build js`) |

\* Approximate; use `wc -l` for exact counts.

## The core types

### `Creature` (`creature.odin`)
A single fighter. This is the unit both the colony and battle care about.

```
species, name, level, xp
hp, max_hp
block, vulnerable, strength, dexterity
power, defense, speed, defense_buff, defense_debuff   // per-battle state
poison, burn, regen, thorns, stun                     // statuses (tick per round)
energy, energy_regen, energy_max   // ONE pool shared map <-> battle
ability: Ability, item: Item       // one of each per creature
powers: [Power]int                 // per-battle POWER effects (Toxic, Rage, …)
genes: [Gene]int          // 0-5 per-stat genetic bonus (Phase 8)
deck, draw_pile, hand, discard, exhausted   // Move_Id arrays
played                    // cards played this turn (combo synergy)
shake, flash, fx_t        // transient draw-only feedback
player: bool              // owned by you (relic stat bonuses apply to these)
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
gold, crystals, crystals_earned, capture_cards, gold_cap, food_cap
turn, floor, seed, rng, start_hex, next_id
pending_tiles: [dynamic]Hex   // tiles where a wild and your monster share
messages: [dynamic]string     // world notifications
floats:   [dynamic]Tile_Float // transient per-tile production popups
shop:     [dynamic]Shop_Offer // Trading Post stock, rerolled each turn
items:    [dynamic]Item       // the colony's item bag
relic_bag: [dynamic]Relic     // relics not yet slotted into a Relic Tower
upgrades: [Upgrade]int        // crystal progression levels
heat, raid_timer, raids       // Phase D: raid pressure + scheduling
bosses_slain: [Species_Id]bool // per-boss flags for the quest board

// The Arena *run* (Phase 54+). A run is one chain of floors:
arena_run: bool, arena_floor: int, arena_best_floor: int
arena_run_crystals: int       // banked so far; paid on cash-out, lost on a wipe
arena_base_level: int         // the party's average level when the run started
arena_run_seed: u64           // fixes this run's gym order and event offers
arena_boons: [dynamic]Relic   // run-scoped relics (die with the run)
arena_items: [dynamic]Item    // the run's own unbounded pack
arena_event: Arena_Event      // the pending trial-floor offer
```

### `Game` (`main.odin`)
Owns the whole session:
```
mode: Game_Mode (TITLE|STARTER|MAP|ARENA|BATTLE|GAME_OVER), renderer, colony, has_colony,
selected, quit
show_deck/view_index/view_scroll                 // the deck viewer (V)
show_dex/dex_tab/dex_index/dex_first             // the dex (L, M)
show_bag/bag_index/bag_first/bag_arena/bag_mon   // the inventory (G, J)
show_upgrades/upgrade_scroll, show_quests, show_improvements/...,
show_graveyard, show_nursery, show_storage, show_save, show_help,
show_settings, show_tips, show_fps, show_minimap
status, status_timer
build_mode/build_hex/has_build, trade_open
battle: Battle, has_battle, battle_choice_open, battle_hex, battle_forced,
        battle_arena, battle_choice_open
attack_select_open, attack_ids, attack_chosen
results_open, results: Battle_Results
relic_place/relic_place_active, unit_picker_open, confirm_kind
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
auto_play: bool                      // the AI is playing your side (auto-fight)
stall, stall_hp: int                 // rounds with no HP lost anywhere (stalemate valve)
rng, log, log_scroll, popups, hit_fx, shake
show_piles, show_effects             // D = piles, S = the active-effects panel
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
move choice > confirm > attack-select > battle-choice > results
> deck viewer > dex > inventory > upgrades > quests > graveyard > nursery
> storage > save > unit picker > { TITLE | STARTER | MAP | ARENA | BATTLE | GAME_OVER }
```

A pending move choice (level-up / reward card) blocks everything **except** the
deck viewer and the inventory, which is deliberate: you want to see what a
monster already runs while picking its next card. Those two therefore also
**draw after** `draw_move_choice`, so they sit on top of it.

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
| The Arena: floors, teams, level curve | `colony_wilds.odin` (the `arena_*` block) |
| Arena gyms / event floors | `arena_trials.odin` |
| A species' Arena loadouts | `SPECIES_SETS` in `sets.odin` |
| Per-battle POWER effects | `powers.odin` |
| The quest board | `milestones.odin` |
| The design space / UI scale | `screen.odin` |
