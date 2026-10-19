# Monster Colony — Code Guide

This folder explains how the game is put together so you can modify it with
confidence. It is written against the code as it stands; line numbers move, so
each doc refers to **names** (procs, structs, constants) rather than lines.

Start here, then jump to the topic you need.

| Doc | What it covers |
|---|---|
| [architecture.md](architecture.md) | The big picture: modules, data flow, the `Game`/`Colony`/`Battle`/`Creature` types, a full turn from keypress to results |
| [colony.md](colony.md) | The map (infinite, biomes, specials), tiles, improvements & economy, the turn loop, movement/energy, wild monster AI, **and the Arena run** |
| [battle.md](battle.md) | The symmetric deck-builder engine: initiative queue, damage formula, cards/statuses/powers, capture, enemy AI, and the Arena's rules |
| [content.md](content.md) | Elements, species (incl. the elite tier), **sets**, creatures & levelling, the move table, synergies, items/relics/upgrades |
| [ui-and-input.md](ui-and-input.md) | Game modes, every screen/panel (incl. the Arena screen, the dex and the inventory), the input map, and the hex renderer/camera |
| [hacking.md](hacking.md) | Step-by-step recipes (add a move/species/terrain/improvement/card effect), all tuning knobs, **conventions** (allocations, the design space, the shared widgets), Gotchas, and dead code |

## The 30-second version

- **Language / libs:** Odin + raylib (`vendor:raylib`). One package, `main`,
  spread over `src/*.odin`. Build with `make` (see the top-level `README.md`).
- **There are three layers:**
  1. **Colony** (`colony.odin`) — the board: tiles with terrain, monsters
     standing on tiles, improvements, gold/food, and a turn loop.
  2. **Creature/content** (`creature.odin`, `moves.odin`) — the *data*: species,
     stats, elements, moves. Pure data + small helpers, no rendering.
  3. **Battle** (`battle.odin`) — a self-contained symmetric fight engine that
     reads `Creature`s and mutates them directly.
- **`main.odin`** glues them together: it owns a `Game` (mode, colony, current
  battle) and routes input/update/draw per mode, plus every panel/HUD.
- **The Arena** (`colony_wilds.odin` + `arena_trials.odin` + `sets.odin`) is a
  fourth thing: a *run* of floors with its own `Game_Mode`, its own unbounded
  pack and its own seed. The colony is frozen while one is live.
- **`hex_math.odin` / `hex_render.odin` / `rng.odin` / `screen.odin`** are
  low-level utilities. `screen.odin` owns the 1280×720 design space — see
  [hacking.md](hacking.md#the-ui-layer) before placing anything on screen.

The single most useful mental model: **the colony stores `Monster`s; each
`Monster` *owns* a `Creature`; a battle borrows pointers to those `Creature`s
and edits them in place**, then `main.odin` writes the results back into the
colony (loot, xp, deaths, captures). `DESIGN.md` at the repo root is the design
spec; this folder is the *implementation* guide.
