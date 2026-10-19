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
3. To make it obtainable, put it in a species' `learnset` (wilds grow into it),
   `starter` (its opening deck) or `move_pool` (reward cards and Arena sets).
   There is no shared generic pool — a species can only offer cards it could
   plausibly run.
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
1. Append a `Species{...}` literal to `SPECIES` — and append, don't insert:
   `Species_Id` ordinals are written into saves.
2. Add a matching `ABILITY_POOLS[Species_Id]` entry and a `SPECIES_SETS` entry
   (or re-run the sets generator). Both tables are indexed by `Species_Id` and
   the compiler will tell you if you forget one.
3. To make it appear as a wild, add it to a `spawn_*` table; to make it
   selectable, add it to `STARTER_SPECIES`. The Arena picks it up automatically
   (the builder reads `SPECIES` and `SPECIES_SETS`).

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
- `energy_regen` (per turn) is the income; `energy_max` is the **bank**, and the
  bank is what decides how hard a fight opens. Species banks are deliberately
  small (4–6, from `base_energy_max`) because a large bank lets turn one dump a
  whole hand — that is why fights used to end in three rounds. Halving the banks
  (Phase 88) took the average auto-fight from 2.7 to 4.1 rounds. X-cost cards
  (`All_In`, `Bulwark`, `Overcharge`) spend the *whole* bank, so they scale with
  it: if you retune the banks, retune those too.
- XP is on `Creature.xp` (moved off `Monster`) so the battle UI can read it.

### Allocations
- **`fmt.ctprintf` allocates on the frame's temp allocator**, which is reset once
  per frame — perfect for anything drawn immediately, and it is why the codebase
  formats inline instead of caching strings. **`fmt.aprintf` allocates on the
  heap and you must `delete` it.** If you find yourself calling `aprintf` inside
  a `draw_*` or `update_*` proc, you almost certainly want `ctprintf`; a heap
  string built every frame and never freed is a silent leak.
- When a proc needs both (e.g. `effect_tooltip` for a tooltip that *keeps* the
  string, and the same text for immediate drawing), define the text once with
  `ctprintf` and make the owned version a thin `aprintf("%s", ...)` wrapper. See
  `effect_tooltip_text` / `effect_tooltip` in `battle.odin`.
- Per-frame `make([dynamic]…)` is a smell: use a fixed array or
  `make(…, context.temp_allocator)`. Anything allocated with the temp allocator
  needs no `delete` — it dies at the end of the frame.
- Quick leak check: wrap the frame in `mem.Tracking_Allocator` and confirm the
  live-block count does not grow across many frames.

### The UI layer
- **Everything is laid out in a 1280×720 design space.** Never call
  `rl.GetMousePosition` or use `rl.GetScreenWidth` for layout — use `mouse_pos()`
  and `screen_w()`/`screen_h()`. Draw through the camera the frame already
  entered (`ui_camera`); `scissor_*` takes design-space rects and maps them.
- **Use the shared widgets**: `draw_panel` (fill + outline), `draw_button` with a
  `Button_Style` (there are four presets), `draw_row` for selectable rows,
  `List_View` + `list_navigate` + `draw_list_chrome` for anything scrollable, and
  `draw_scrollbar` directly if you need the bar on its own. Hand-rolling a
  rounded rect + outline pair, or a `hover ? a : b` colour pick, is how the look
  drifts apart — that is exactly how the dex's scrollbar ended up under a
  selected row.
- **Anything drawn next to a number gets `fit_text`d** to the room it has.
  Long species names, XP totals and deck counts have all collided with their
  neighbours at some point.
- Hoverable widgets call `ui_want_hand()` so the cursor changes.
- Tooltips are **queued** (`tooltip_set` / `tooltip_set_owned`) and drawn last,
  because an immediate-mode tooltip would be painted over by later draws.

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
- A battle only ends early on a genuine stalemate — `STALL_ROUNDS` (12) rounds
  with **no HP lost anywhere** — with `SAFETY_ROUNDS` (200) as a last-ditch net
  so a bug can never freeze the game. There is no flat round cap any more.
- Reward cards are a flat ~18% drop (`resolve_won`) picking an unknown move from
  the species' `move_pool`.
- `arena_challenger_level` integrates the XP curve floor-by-floor, so it is O(floor)
  per call. Fine at 1000 floors (microseconds, once a frame), but a closed form
  would be tidier.
- Roughly 34 places still hand-roll a rounded-rect + outline pair instead of
  calling `draw_panel`, and `ui_want_hand()` is used far less often than
  `draw_button` — see "The UI layer" above.
