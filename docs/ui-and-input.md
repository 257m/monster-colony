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
then overlays on top: attack_select, battle_choice, results, deck viewer, encyclopedia, improvements dex, item bag
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
  their **ability** (right-aligned on the HP row), food, **energy** and an XP bar.
- `draw_move_highlights` shows, for the selected monster, each neighbour as an
  **outline only**: green = can move, red = blocked/full, amber = not enough
  energy (plus the move cost when valid).
- `draw_map_monsters` draws creatures as coloured dots with a ground shadow and a
  gentle idle bob; wilds get a pulsing red ring and the selected monster a pulsing
  ring; a small red dot marks a hungry monster.
- **Improvements are animated icons** (`src/improvement_icons.odin`): farms sway,
  mines sparkle, wells ripple, watchtowers pulse, treasuries spawn floating
  coins, granaries bob, and Walls/Bridges are drawn as bricks/planks. Water tiles
  shimmer. All animation is driven by `rl.GetTime()`, so there is no per-frame
  state.
- **Tiles have procedural detail** (`src/tile_detail.odin`): caves scatter rocks,
  groves grow grass and a tree, mushroom groves sprout mushrooms, ruins have
  broken pillars, tundra has snow and ice, jungle is dense grass, lava has
  pulsing cracks, desert has dunes, quicksand swirls, trading posts show a stall,
  and boss rooms a skull. Positions come from a per-hex hash (stable); water,
  mushrooms, lava and quicksand animate off `rl.GetTime()`.
- **Production popups**: when the turn loop produces or moves food/gold,
  `colony_end_turn` records a short-lived `Tile_Float` on the tile, and
  `draw_tile_floats` draws it rising + fading with a burst ring — `+4g` on a
  working Mine, `+6f` on a Farm/Well, `+Nf` into a Granary, and `-Nf` when a
  Granary feeds a monster.
- **Damage feedback**: when a wild hits an improvement (`damage_improvement`),
  the tile records `hit_t0`, so for `HIT_LIFE` seconds the icon **shakes**, a
  red flash + ring pulses, and a red `-N` float pops.
- **Coverage radii** (`draw_inspect_radii` + `improvement_rings`): a tinted hex
  area with a bright boundary ring shows an improvement's coverage. It appears
  when you hover a build option (preview), when a tile is selected in build mode,
  and when you hover a built tile to inspect it. The build panel tags stackable
  improvements with **`+stack`**.

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
| Improvements dex | `I` | `update_improvements` | `draw_improvements` |
| Item bag | `G` | `update_bag` | `draw_bag` |
| Starter picker | mode STARTER | `update_starter` | `draw_starter` |

The **deck viewer** (`draw_deck_viewer`) lists the selected monster's stats, its
**ability** and **item** (name + description), and its full deck as a scrollable
card grid. The top-right **Equip item** button moves the next bagged item into
this monster's slot (old item returns to the bag); **Unequip** drops it back.

The **improvements dex** (`draw_improvements`, `I`) is a browsable reference for
all 23 improvements: a scrolling list on the left and, on the right, the animated
icon, base cost, HP, category, the terrains it can be built on (chips coloured by
terrain), the short effect line, and a long-form `improvement_detail` paragraph
(word-wrapped by `draw_text_wrapped`).

The **item bag** (`draw_bag`, `G`) lists the items in `Colony.items` with a
colour-coded dot; the right side shows the selected item's icon, description and
an **effect breakdown** (`draw_item_effects`), plus **Equip to selected monster**
(`equip_bag_item` — swaps the item onto the map-selected monster, returning its
old item to the bag). Items can also be cycled on in the deck viewer.

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
ends just that monster's turn. Your whole party is drawn **on the field** as info
cards (`draw_party_field`): avatar, name, level/element, HP numbers, an energy
bar, active buff chips, and its ability/item. The acting monster is ringed,
monsters that have ended their turn are dimmed with an `ENDED` tag, and the dead
are greyed out (there is no switching).

The attacker picker (`draw_attack_select`) is a two-column panel: **your
monsters** (checkboxed) on the left and **the enemies on the tile** on the right
(name, level, element, HP, ability and rarity), so you can see what you're
picking a fight with. The attack overlays are modal and consume input before the
mode runs.

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
