# UI, screens & input (`src/main.odin`, `src/hex_render.odin`)

## Modes

`Game_Mode :: enum { TITLE, STARTER, MAP, ARENA, BATTLE, GAME_OVER }`.

**ARENA** is a real mode, not a modal: a live Arena run owns the screen (the
colony is frozen until you cash out or abandon), and a won floor returns you
there rather than to the map. A save with `arena_run` set reloads straight into
it.

The game opens on the **title screen** (`draw_title`): **New Game** → the starter
picker (`reset_to_starter`), **Load Game** → the save/load panel, **Quit** → exit
(desktop only; the web build hides it). `main()` loops `game_update` + `game_draw`
until the window closes or `g.quit` is set. Esc is **not** the quit key
(`rl.SetExitKey(.KEY_NULL)`); Esc closes the current panel instead.

### Update dispatch (`game_update`)
Handled in this priority order, each returning early. Note that the **move
choice is first** and blocks everything — except the deck viewer and the
inventory, which it deliberately lets through so you can see what a monster
already runs while picking its next card.
```
tick status_timer
pending move choice -> update_move_choice   (but: show_deck / show_bag pass through)
confirm_kind != NONE-> update_confirm
attack_select_open  -> update_attack_select
battle_choice_open  -> update_battle_choice
results_open        -> update_results
show_deck           -> update_deck_viewer
show_dex            -> update_dex
show_bag            -> update_inventory
show_upgrades / show_quests / show_improvements / show_graveyard
show_nursery / show_storage / show_save / unit_picker
MAP|STARTER|ARENA|BATTLE + M -> open the dex on the MONSTERS tab
MAP|ARENA|BATTLE + L         -> open the dex where it was
MAP|ARENA + I / G / J / U    -> improvements dex / inventory / inventory / upgrades
MAP + C / H / O              -> nursery / storage / save panel
MAP + V (and ARENA/BATTLE)   -> open the deck viewer
otherwise switch mode:
  TITLE   -> update_title
  STARTER -> update_starter
  MAP     -> update_colony
  ARENA   -> update_arena
  BATTLE  -> update_battle
  GAME_OVER: N -> reset_to_starter, Esc -> goto_title
```

### Draw dispatch (`game_draw`)
```
switch mode: TITLE | STARTER | MAP(+build/trade panels) | ARENA | BATTLE | GAME_OVER
then overlays on top, in this order (later = on top):
  arena event, attack_select, battle_choice, results, move choice,
  deck viewer, inventory, dex, upgrades, quests, graveyard, nursery,
  storage, save, unit picker, confirm, tips, tooltip
```
The move choice draws *before* the deck viewer and inventory on purpose — those
two are the ones you open from it, so they have to sit above it.

**Checklist for a new overlay:** add a field to `Game`; an early-return branch
in `game_update`; an `update_*`/`draw_*` proc; a `draw_*` call after the mode
switch in `game_draw`; and clear it in `close_all_panels` (used by both
`goto_title` and `reset_to_starter`).

### Title screen (`draw_title`)
A centered wordmark over a soft pulsing glow, a tagline, and three buttons —
**New Game** (`reset_to_starter`), **Load Game** (opens the save/load panel), and
**Quit** (desktop only, sets `g.quit`). Enter/Space starts a new game, `L` opens
the load panel.

### Starter picker (`draw_starter`)
Three species cards with a **numbered badge** (1/2/3) and a "Click or press N"
label. Click a card, or press the matching number key (`DIGIT_KEYS`), to begin —
`choose_starter` rolls the seed and generates the colony.

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
  ring; a small red dot marks a hungry monster. A raid **raider** gets a warm
  ring, and a raid **alpha** is unmistakable — gold halo, thick ring, a **crown**
  and an `ALPHA` label (`draw_alpha_marker`).
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
- **Build-mode selection** (`draw_build_selection`): the tile you've picked in
  build mode gets a bold pulsing green fill + thick outline and a `BUILD HERE`
  label, so it's obvious which hex the panel is acting on.
- **Overlay health**: stackable improvements (Road / Scarecrow / Spike Trap)
  carry their own `Tile.overlay_hp`. The build panel lists the building and
  overlay HP separately and repairs whichever is damaged (`tile_repair_target`).

## Panels / overlays

| Panel | Opened by | Update | Draw |
|---|---|---|---|
| Build / repair / replace | `B`, then click a tile | `update_build` | `draw_build_panel` |
| Trading Post | `T` when your monster stands on one | `update_trade` | `draw_trade_panel` |
| **Arena screen** | `T` when your monster stands on one | `update_arena` | `draw_arena` |
| Arena event floor | a trial floor that is an event | `update_arena_event` | `draw_arena_event` |
| Choose attackers | attacking a tile | `update_attack_select` | `draw_attack_select` |
| Ambush choice (Auto/Manual) | a wild ambush | `update_battle_choice` | `draw_battle_choice` |
| Results | after a battle | `update_results` | `draw_results` |
| Deck viewer | `V` (also mid-battle, and during a move choice) | `update_deck_viewer` | `draw_deck_viewer` |
| **Dex** (monsters/cards/abilities/items) | `L`, or `M` for the monster tab | `update_dex` | `draw_dex` |
| Improvements dex | `I` | `update_improvements` | `draw_improvements` |
| **Inventory** (monsters ⇄ bag, two panes) | `G` or `J` | `update_inventory` | `draw_inventory` |
| Active effects (in battle) | `S` | `battle_input` + scroll in `update_battle` | `draw_battle_effects` |
| Upgrades | `U` | `update_upgrades` | `draw_upgrades` |
| Nursery | `C` | `update_nursery` | `draw_nursery` |
| Monster storage | `H` | `update_storage` | `draw_storage` |
| Save / load | `O` | `update_save_panel` | `draw_save_panel` |
| Quest journal | `Q` | `update_quests` | `draw_quests` |
| Hall of the Fallen | `Y` | `update_graveyard` | `draw_graveyard` |
| Controls help | `K` | `update_help` | `draw_help` |
| Settings | `P` | `update_settings` | `draw_settings` |
| Unit picker | clicking a shared tile | `update_unit_picker` | `draw_unit_picker` |
| Confirm dialog | destructive action | `update_confirm` | `draw_confirm` |
| Move choice | level-up / reward | `update_move_choice` | `draw_move_choice` |
| Starter picker | mode STARTER | `update_starter` | `draw_starter` |

The **deck viewer** (`draw_deck_viewer`) lists the selected monster's stats, its
**genes** (`genes_label` + total), its **ability** and **item** (name +
description), and its full deck as a scrollable card grid. The top-right
**Equip item** button moves the next bagged item into this monster's slot (old
item returns to the bag); **Unequip** drops it back.

The **nursery panel** (`draw_nursery`, `C`) lists your Nurseries and, for the
selected one, its breeding **pair** (2 slots, click to remove) and **babies** (4
slots, click to take). The right side lists the monsters **beside the Nursery**
(Lvl 5+, same species) — click one to move it in as a parent
(`colony_assign_parent`).

The **monster storage panel** (`draw_storage`, `H`) lists your Dens and, for the
selected one, the monsters **nearby** (click to store with `colony_store_monster`)
and those **in stasis** (click to deploy with `colony_deploy_stored`). Stored
monsters cost no upkeep and don't count toward heat.

The **save / load panel** (`draw_save_panel`, `O`) lists **3 slots** with their
metadata (turn, gold, monsters, crystals, age) and **Save**/**Load** buttons.
`F` quick-saves slot 1 from the map. **No function keys are used anywhere** (they
collide with the OS). Saving is disabled mid-battle and in the browser build (no
filesystem) — but an Arena run autosaves after every cleared floor, and the Arena
screen has a Save button. A **New Run** button below the
slots (or the **`N`** key) returns to the **starter picker** (`reset_to_starter`)
so you can choose a starter again and roll a fresh seed — handy for hunting a
good start; while a run is in progress it needs a second click/press to confirm.

The **move-choice overlay** (`draw_move_choice`) is modal and takes priority over
every other screen. It appears when a level unlocks a move (`LEVEL UP!` — one
card, or up to 3) or when a battle reward drops (up to **3 move cards**, via
`draw_card`); click one or press **`1`–`3`** to learn it, or **Skip** to decline.
Pending choices queue on `Colony.choices` and are shown one at a time. Each card
shows its **rarity** tag above it, and reward offers are rarity-weighted.

The **quest journal** (`draw_quests`, `Q`) lists the 10 milestones with a
progress bar, reward and a done marker, and shows `OBJECTIVE COMPLETE` once the
run's goal is met. The **Hall of the Fallen** (`draw_graveyard`, `Y`) lists the
whole graveyard (name, level, elements, carried item) with **Revive** (gold) and
**Salvage** (move the corpse's item into your bag) buttons, scrolled with
Up/Down. The deck viewer also supports **deck thinning**: right-click a card to
forget it for gold (`colony_forget_card` / `forget_card_cost`).

**Hover tooltips** are a frame-last overlay: a hovered widget calls
`tooltip_set`/`tooltip_set_owned`, the frame draws it via `tooltip_draw`
(word-wrapped, kept on screen), and `tooltip_clear` frees it at the top of the
next frame. They cover battle cards, status-effect chips, roster entries, build
options, upgrade cells and map tiles.

The **crystal progression panel** (`draw_upgrades`, `U`) is a 3-column grid of
upgrade nodes (`UPGRADE_ROWS` = 12 rows), **scrolled with the wheel**
(`upgrade_cell_rect(i, scroll)` / `upgrade_max_scroll`); each cell shows level
pips, its description and a buy button, and children are indented under their
parent.

**QoL (Phase 24).** The **minimap** (`draw_minimap`, `Z`, top-left) plots every
explored tile, POIs, wilds/raids and the viewport; clicking it **tweens the
camera** (`minimap_hex_at` → `tween_camera`). Off-screen POIs get **edge arrows**
(`draw_poi_markers`). Clicking a tile with several of your monsters opens the
**unit picker** (`select_or_pick_on_tile`) instead of Tab-cycling. The
**autosave** is a special slot (`AUTOSAVE_SLOT`, load-only in the panel, written
every `AUTOSAVE_EVERY` turns in `do_end_turn` when enabled). Destructive actions
raise a **confirm dialog** (`ask_confirm` / `Confirm_Kind`). The **settings
panel** (`F10`, `draw_settings`) holds the **last-turn summary**
(`build_turn_summary`), a **volume slider** (`audio_set_volume`), and toggles for
minimap / tooltips / FPS / autosave. The HUD shows **net food** (red when
starving). `fmt_thousands` adds separators; `ui_want_hand`/`ui_cursor_apply`
give a pointing-hand cursor. In battle, `draw_initiative` shows the upcoming
turn order. **Relics live in the inventory** (`G`/`J`) alongside items now — they
are placed from there into a Relic Tower. **No function keys are used** (they
collide with the OS): help is `K`, settings `P`, mute `X`, quick-save `F`.

The **improvements dex** (`draw_improvements`, `I`) is a browsable reference for
all 27 improvements: a scrolling list on the left and, on the right, the animated
icon, base cost, HP, category, the terrains it can be built on (chips coloured by
terrain), the short effect line, and a long-form `improvement_detail` paragraph
(word-wrapped by `draw_text_wrapped`).

The **inventory** (`draw_inventory`, `G` / `J`) is two panes: **your monsters**
on the left (a `List_View`: name, level, and what each is wearing, scrollable)
and **your bag** on the right (items + relics). Click a monster, click an item,
click **Equip** — a swap returns the old item to the bag, and **Unequip** strips
it. The selected slot's effects (`draw_item_effects`) or relic description sit
underneath. Both action buttons are drawn even with an empty bag, because that is
exactly when Unequip is the one you want.

Opened from the **Arena screen** it shows something else entirely: only the
monsters **standing on the tower tile**, and only the run's own pack
(`Colony.arena_items`, unbounded, separate from `Colony.items`). `open_inventory(g,
arena = true)` is what switches it.

The **dex** (`draw_dex`, `L`, or `M` for the monster tab) is one reference with
four tabs — MONSTERS / CARDS / ABILITIES / ITEMS — sharing one `List_View` and
one `draw_scrollbar`. The monster tab carries the whole species detail (portrait,
typing, evolution line, stats, starter deck, learnset grid, ability pool, blurb)
that used to be the separate encyclopedia panel.

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
| `V` | deck viewer (also works in the Arena and mid-battle) |
| `M` | dex, on the MONSTERS tab |
| `L` | dex, on whatever tab it was last on |
| `I` | improvements dex |
| `G` / `J` | inventory (monsters ⇄ bag; in the Arena, the run's pack) |
| `U` | crystal progression upgrades |
| `C` | nursery (breeding) panel |
| `H` | monster storage (Dens) |
| `O` | save / load panel |
| `Q` | quest journal (milestones) |
| `Y` | Hall of the Fallen (graveyard) |
| `Z` | toggle the minimap |
| `K` | controls / help overlay |
| `P` | settings (sound, display, last turn) |
| `X` | mute / unmute sound |
| `F` | quick-save to slot 1 |
| `N` | new run — back to the starter picker (**game-over screen or save panel**) |

### Arena screen (`update_arena`)
The colony is frozen while a run is live, so this screen has its own row of
buttons rather than reusing the map's keys.
| Input | Action |
|---|---|
| **Enter the tower** / **Fight floor N** | start a run (flat `ARENA_ENTRY_COST`) or fight the next floor; a trial floor shows its gym name or "a decision" |
| **Cash out** | bank the winnings and end the run |
| **Save the run** | write the autosave slot (every cleared floor also autosaves) |
| **Items** | `open_inventory(g, arena = true)` |
| **Decks** | the deck viewer |
| **Abandon** / **Walk away** | end the run and lose the pack, or (with no run) go back to the map |
| `Esc` | only backs out when there is nothing at stake |

### Starter picker
| Input | Action |
|---|---|
| `1`–`3` / click a card | choose that starter (rolls a new seed) |

### Battle (`battle_input`)
| Input | Action |
|---|---|
| `1`–`9` / click a card | play that card |
| click an enemy | target it |
| `Space` / `E` / button | end your turn |
| `C` / button | use a capture card |
| `D` / click the pile readout | view the draw & discard piles |
| `S` | the scrollable ACTIVE EFFECTS panel (Esc or `S` closes) |
| `V` | deck viewer — including **during a level-up / reward card choice** |
| `L` / `M` | the dex (cards / monsters) |
| `[` `]` / wheel | scroll the enemy row when a pack is wider than the field |
| PgUp / PgDn, or the wheel over it | scroll the battle log |

The reward-card overlay has a **View deck** button for the same reason `V` works
there: deciding which card to learn without seeing what the monster already runs
is guesswork. Both it and the inventory draw above the choice.

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
