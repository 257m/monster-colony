# Architecture

## Files

| File | Lines* | Responsibility |
|---|---|---|
| `src/main.odin` | ~2090 | `Game` state, `main()`, per-mode update/draw, every panel & HUD, battle glue, results |
| `src/colony.odin` | ~1600 | Map generation, tiles, improvements, economy, turn loop, wild-monster AI |
| `src/battle.odin` | ~1600 | The battle engine + battle rendering |
| `src/creature.odin` | ~590 | `Species` table, `Creature` struct, stat/level helpers |
| `src/moves.odin` | ~292 | `Element` chart, `Move` struct, `MOVE_DATA`, `Move_Id` enum |
| `src/hex_math.odin` | ~100 | Axial hex coordinate math |
| `src/hex_render.odin` | ~127 | Hex <-> screen transforms, camera, hex drawing |
| `src/rng.odin` | ~49 | SplitMix64 PRNG |

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
deck, draw_pile, hand, discard     // Move_Id arrays
played                    // cards played this turn (combo synergy)
shake, flash              // transient draw-only feedback
```

`Creature` **owns** its `deck`/piles (heap arrays) — see `creature_copy`,
`creature_free_piles`, `creature_free_all`.

### `Monster` (`colony.odin`)
A `Creature` **standing on the map**. Owns colony-only state:

```
id, creature, pos: Hex, wild: bool, food, genetics[5]
```

Your party and enemy wilds are *both* `Monster`s in `Colony.roster`; `wild`
distinguishes them. (Note: `xp` lives on `Creature` now, not `Monster`.)

### `Tile` (`colony.odin`)
```
hex, terrain: Terrain, revealed: bool,
improvement: Improvement, improvement_hp, stored, scuffle
```
`stored` = food (Granary) or gold (Treasury).

### `Colony` (`colony.odin`)
```
tiles: [dynamic]^Tile, tile_index: map[u64]int   // the infinite map
roster, graveyard: [dynamic]Monster
gold, crystals, capture_cards, gold_cap, food_cap
turn, floor, seed, rng, start_hex, next_id
pending_tiles: [dynamic]Hex   // tiles where a wild and your monster share
messages: [dynamic]string     // world notifications
```

### `Game` (`main.odin`)
Owns the whole session:
```
mode: Game_Mode, renderer, colony, has_colony, selected
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
enemy_ids: [dynamic]int
target, enemy_acting, captured_ids, capture_cards
phase: Battle_Phase, round, acting, player_done, timer
order, order_pos                     // the initiative queue
rng, log, popups, shake
```

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
| Terrain effects / spawn rates | `terrain_*` procs in `colony.odin` |
| What an improvement does / costs | `improvement_*` procs in `colony.odin` |
| The economy / turn loop | `colony_end_turn` in `colony.odin` |
| Wild AI (spawn/roam/attack) | `colony_spawn_wilds` … `colony_resolve_wild_actions` |
| A panel or HUD line | the `draw_*` procs in `main.odin` |
| Input | `game_update` + the per-mode `update_*` procs |
