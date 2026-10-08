# Hacking guide: recipes, knobs, gotchas

## Workflow

```sh
make run      # compile + play
make build    # bin/monster-colony
make check    # odin check src   (fast, no window)
make clean
```

There are no external dependencies beyond Odin's bundled `vendor:raylib`.

A quick way to test *logic* without a window: copy `src` somewhere, rename
`main` (Odin needs one `main`), and write a small `test.odin` with its own
`main` that calls the procs you care about (this is how most of the systems here
were verified). Windowed code just needs a display.

---

## Recipes

### A. Tweak a move
Edit its entry in `MOVE_DATA` (`moves.odin`) and its `desc`. Nothing else.

### B. Add a move
1. Add an id to `Move_Id`.
2. Add a `MOVE_DATA[.YourMove] = { ... }` entry (give it a `desc`).
3. To make it obtainable, put it in a species' `starter`/`learnset`/`move_pool`
   or in `COMMON_MOVES`. (Remember: wilds only use `starter`.)
4. If it introduces a **new effect field**, also teach `play_creature_card`
   (apply it), `move_value` (value it for the AI), and any UI that shows it.

### C. Add a status / card effect
1. Add a field to `Move` (e.g. `evasion: int`) and to `Creature` if it's a state.
2. Apply it in `play_creature_card`; reset it in `creature_reset_battle_state`
   if it's per-battle, or in `creature_begin_round` if per-turn.
3. If it affects damage/defense, update **both** `apply_damage` and
   `estimate_damage` (they must match).
4. Give it a `Popup_Kind` + `popup_text`/`popup_color`, and a chip in
   `build_effects` (+ `Effect_Kind`/`effect_chip_text`/`effect_chip_color`).
5. Add a term to `move_value` so the AI values it.

### D. Add a species
Append a `Species{...}` literal to `SPECIES`. That's enough to exist. To make it
appear as a wild, add its index to the relevant `spawn_species_for` case; to make
it selectable, add it to `STARTER_SPECIES`.

### E. Add a terrain
1. Add to `Terrain`.
2. Fill in `terrain_name`, `terrain_color`.
3. `terrain_spawn_chance`, `terrain_move_cost`, `spawn_species_for`, and the
   traversal rules in `tile_passable` (if it should gate movement).
4. If it's a biome, add a band/branch in `biome_at`.
5. Add it to the legend (`draw_terrain_legend`) and anywhere terrain is listed.

### F. Add an improvement
1. Add to `Improvement`.
2. Fill in `improvement_name/label/cost/valid_on/effect`, and `IMPROVEMENT_HP`
   behaviour if needed.
3. Wire its effect into `colony_end_turn` (production) or a reveal/deter radius
   constant, and into `colony_recompute_caps` if it changes storage.
4. `improvement_cost_divisor` if it should scale differently.

### G. Tune difficulty / economy
Everything is a named constant — see [colony.md](colony.md#tuning-knobs-colonyodin-top-of-file).
Spawn pressure: `terrain_spawn_chance`, `SPAWN_GRACE_TURNS`, `MAX_WILDS`.
Combat pace: the species `base_*` stats, `move` damage/cost, and the damage
formula in `apply_damage`.

### H. Change the damage formula
Edit `apply_damage`, then make `estimate_damage` identical (it powers the card
hover preview). Keep both in sync or the preview lies.

### I. Change battle turn order
`build_order` (who's in the queue and how it's sorted), `advance`/`actor_can_act`
(when someone acts), `begin_round` (what "a turn" resets).

---

## Gotchas

### Odin language
- **Enum switches must be exhaustive**, or use `#partial switch` / a `case:`
  default. Several switches here are `#partial` for exactly this reason.
- **`case:` is the default**; a `switch` with a `case:` that *returns* still
  needs every enum member or `#partial` — if the compiler complains about
  "Unhandled switch cases", switch to `#partial switch` + a trailing `return`.
- **No `const` inside a proc** — put constants at file scope.
- **Reserved words bite**: e.g. `where` and `any` are keywords; don't name a
  variable `where` or `any` (this caused a real syntax error).
- **No `++`/C-style `for`** — use `i += 1` and `for i in 0..<n`.
- **Struct literals use `=`** (`Move{name = "X"}`), and `for x in [?]T{...}` is
  invalid — bind the array to a variable first.
- **`fmt.ctprintf`** returns a `cstring`; nested calls inside one expression are
  fine and the codebase convention is *format then `DrawText` immediately*.
  Don't hold a formatted string across a lot of other work.

### Pointers & the roster
- **`&c.roster[i]` can be invalidated by `append(&c.roster, ...)`** (the array
  may reallocate). Re-index *after* any append, or copy what you need first.
  This is why `resolve_won` re-scans by index rather than holding pointers.
- `Colony.tiles` is `[dynamic]^Tile` (a pointer array) specifically so tile
  pointers stay valid when the array grows. Don't change it to `[dynamic]Tile`
  without auditing every `ensure_tile` caller.

### The infinite map
- `tile_at` is a **pure lookup** and returns `nil` for unknown hexes; call
  `ensure_tile` explicitly where you intend to create. Most read paths already
  nil-check, but a new one might not.
- Tiles are materialized near your monsters and revealed areas. If you write a
  loop that "should see everything", remember it only sees materialized tiles.
- `colony_end_turn` pins `n_tiles` for `farm_pool` because Watchtower reveals can
  materialize tiles mid-turn. If you add a step that calls `ensure_tile` before
  the farm loops, extend that pinning.

### Shared energy & xp
- Energy is **one pool** on `Creature.energy` (there is no `Monster.energy`).
  Both `colony_move` and card play read/write it. Battles must **not** zero it
  (`creature_reset_battle_state` intentionally doesn't).
- XP is on `Creature.xp` (moved off `Monster`) so the battle UI can read it.

---

## Dead code

The legacy node-graph map (`hex_map_gen.odin`), its render helpers (`node_type_*`,
`draw_map_node`, `draw_minimap`, `draw_hex_inset`, `draw_hex_connection`), and
the old battle/colony leftovers (`pick_wild`, `draw_game_over`, `draw_badge`,
`hex_bounds`, `hex_from_offset`, `tile_terrain`, `first_player_monster_on`,
`monster_energy_max`) have been **removed**. Keep it that way: if you delete a
feature, delete its helpers too.

## Known rough edges

- The colony controls hint says "N new run", but `N` is only handled on the
  **game-over** screen. (Easy fix: handle `N` on the map too, or drop it from the
  hint.)
- Battle stalemates are capped by `MAX_ROUNDS` (30): the higher remaining-HP
  fraction wins.
- Reward cards are a flat ~18% drop (`resolve_won`) picking an unknown move from
  `move_pool` + `COMMON_MOVES`.
- The repo currently has many uncommitted changes; commit deliberately.
