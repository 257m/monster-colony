# UI, screens & input (`src/main.odin`, `src/hex_render.odin`)

## Modes

`Game_Mode :: enum { STARTER, MAP, BATTLE, GAME_OVER }`.

`main()` sets up the window and the `Game`, then loops `game_update` +
`game_draw` until the window closes. Esc is **not** the quit key
(`rl.SetExitKey(.KEY_NULL)`); Esc closes the current panel instead.

### Update dispatch (`game_update`)
Handled in this priority order, each returning early:
```
tick status_timer
show_deck         -> update_deck_viewer
show_encyclopedia -> update_encyclopedia
MAP|STARTER + M   -> open encyclopedia
attack_select_open-> update_attack_select
battle_choice_open-> update_battle_choice
results_open      -> update_results
MAP + V           -> open deck viewer
otherwise switch mode:
  STARTER -> update_starter
  MAP     -> update_colony
  BATTLE  -> update_battle
  GAME_OVER: N -> reset_to_starter
```

### Draw dispatch (`game_draw`)
```
switch mode: STARTER|MAP(+build/trade panels)|BATTLE|GAME_OVER
then overlays on top: attack_select, battle_choice, results, deck viewer, encyclopedia
```

**Checklist for a new overlay:** add a field to `Game`; an early-return branch
in `game_update`; an `update_*`/`draw_*` proc; a `draw_*` call after the mode
switch in `game_draw`; and clear it in `reset_to_starter`.

## Colony screen (`draw_colony`)

Draws the world, then `draw_colony_hud`, `draw_roster_panel`,
`draw_end_turn_button`, `draw_terrain_legend`.

- `draw_colony_hud` shows gold/food/crystals, **Food +N/turn / Gold +N/turn**
  production and upkeep, and, for the hovered tile, its name, improvement +
  **HP**, production status, and occupants.
- `draw_roster_panel` lists your monsters (compact — wilds aren't drawn) with HP,
  food, **energy** and an XP bar.
- `draw_move_highlights` shows, for the selected monster, each neighbour as an
  **outline only**: green = can move, red = blocked/full, amber = not enough
  energy (plus the move cost when valid).
- `draw_map_monsters` draws creatures as coloured dots (red ring = wild); a
  small red dot marks a hungry monster.

## Panels / overlays

| Panel | Opened by | Update | Draw |
|---|---|---|---|
| Build / repair / replace | `B`, then click a tile | `update_build` | `draw_build_panel` |
| Trading Post | `T` when your monster stands on one | `update_trade` | `draw_trade_panel` |
| Choose attackers | attacking a tile | `update_attack_select` | `draw_attack_select` |
| Ambush choice (Auto/Manual) | a wild ambush | `update_battle_choice` | `draw_battle_choice` |
| Results | after a battle | `update_results` | `draw_results` |
| Deck viewer | `V` | `update_deck_viewer` | `draw_deck_viewer` |
| Encyclopedia | `M` | `update_encyclopedia` | `draw_encyclopedia` |
| Starter picker | mode STARTER | `update_starter` | `draw_starter` |

Each panel has small `*_rect()` helpers returning `rl.Rectangle`s, used by both
the hit-test (update) and the draw. Keep them in sync when you move things.

## Input map

### Colony (`update_colony` and helpers)
| Input | Action |
|---|---|
| Right-drag / `WASD` (held) | pan |
| Wheel | zoom (around the cursor) |
| `R` | recenter on the entrance |
| Left click an adjacent tile | move the selected monster (starts a fight / attacker picker if wilds are there) |
| Left click your tile (no wild) | cycle through your monsters standing there |
| Left click your tile (with a wild) | open the attacker picker |
| `Tab` | cycle through **your** monsters |
| `Space` / `E` | end turn |
| `B` | toggle build mode (`Esc` to exit) |
| `T` | Trading Post (only if the selected monster is on one) |
| `V` | deck viewer |
| `M` | encyclopedia |
| `N` | new run (**game-over screen only**) |

### Battle (`battle_input`)
| Input | Action |
|---|---|
| `1`–`9` / click a card | play that card |
| click an enemy | target it |
| `Space` / `E` / button | end your turn |
| `C` / button | use a capture card |

Every one of your monsters takes its own turn in the Speed queue — the player
panel and hand follow whichever monster is currently acting, and **End Turn**
ends just that monster's turn. The party list (right) highlights the current
actor and is otherwise informational (there is no switching).

The attack overlays are modal and consume input before the mode runs.

## Rendering (`hex_render.odin`)

Flat-top hexes. `Hex` is axial `(q, r)` — see `src/hex_math.odin` for the
coordinate helpers.

- `hex_world(r, hex)` → `x = 1.5·size·q`, `y = √3·size·(r + 0.5·q)`.
- `hex_to_screen` applies camera + zoom + screen origin; `screen_to_hex` inverts
  it via `hex_round_axial`.
- `draw_hex_filled` uses `rl.DrawPoly` (DrawTriangleFan gave artefacts), and
  `draw_hex_outline`/`draw_hex_inset` draw the edges.
- `hex_renderer_update_camera` does WASD panning and wheel zoom (anchored on the
  mouse); `center_camera_on` recenters.
- `hex_renderer_hovered(r)` converts the mouse to a hex.

`draw_colony` **culls** tiles outside the viewport, because the map is infinite
and `c.tiles` grows as you explore — keep the cull if you add per-tile drawing.
Unrevealed (fog) tiles draw as a dim slate hex so the grid reads.
