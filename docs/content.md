# Content: elements, species, moves (`src/moves.odin`, `src/creature.odin`)

This is the data layer. Almost everything here is tables; changing a number here
changes gameplay immediately, no other code required.

## Elements (`moves.odin`)

`Element :: enum { NEUTRAL, EMBER, AQUA, FLORA, ICE, GROUND, ELECTRIC, AIR, POISON }`

- `element_multiplier(atk, def)` → `2.0` (super), `0.5` (weak), else `1.0`.
- `element_super(atk, def)` / `element_weak(atk, def)` are the two hand-written
  tables — **edit these to rebalance type matchups.**
- A defender with **two** types multiplies against **both** (e.g. 2× · 0.5× = 1×),
  applied in `apply_damage`.
- **STAB**: a move whose element matches one of the attacker's elements deals
  ×1.5.
- `element_name` / `element_color` drive labels and UI colours.

## Moves (`moves.odin`)

`Move_Id` is a flat enum; `MOVE_DATA: [Move_Id]Move` holds the data. A `Move`:

```
name, desc, cost: f32, element: Element, rarity: Rarity
damage, block, hits, vulnerable, strength, defense: f32, draw
heal_pct, leech_pct: f32                   // % of max HP / % of damage dealt
strength_down: int, defense_down: f32      // debuffs applied to the TARGET
poison, burn, stun, regen, thorns: int     // status effects (Phase 21)
vuln_bonus, block_bonus, combo_bonus: int  // conditional damage synergies
```

- `cost` is in energy half-steps (0.5 granularity) because energy is a float.
- `hits` defaults to 1; multi-hit cards call `apply_damage` per hit (so Strength
  and Block apply per hit).
- `heal_pct` heals a fraction of the **caster's max HP** (Mend, Heal Spring, …);
  `leech_pct` heals a fraction of the **damage dealt** (Leech, Gnaw, Phoenix).
  Percentages keep heals relevant at every level. **Block stays flat** — a block
  card gives block.
- Synergies add to the **first hit only** when the condition holds:
  `vuln_bonus` (target is Vulnerable), `block_bonus` (you have Block),
  `combo_bonus` (you already played a card this turn).
- `rarity` (`COMMON`/`UNCOMMON`/`RARE`) drives reward weighting
  (`card_rarity_weight`) and the rarity tag on the picker.
- Status fields apply **Poison/Burn/Stun** to the target and **Regen/Thorns** to
  the caster; see `STATUS_MOVES` and the battle docs.
- `move_value(id)` is the **AI heuristic** — raise a term here if you want the AI
  to value a card more (status effects have terms).
- `fmt_num` (top of the file) formats floats compactly (`3`, `2.5`, `1.25`).

There are 81 moves (13 of them status cards). The `desc` string is what the card
shows; keep it accurate.

## Species (`creature.odin`)

`SPECIES: [Species_Id]Species` — each entry:

```
name, elements: []Element      // 1 or 2 types, primary first
base_hp: int
base_energy, base_energy_max: int
base_power, base_defense, base_speed: f32   // power is a MULTIPLIER (~1.0)
base_satiety, base_upkeep: int              // food capacity / per-turn cost
color, role: Species_Role
rarity: Rarity                             // COMMON..LEGENDARY (capture/shop/loot)
starter:  []Move_Id              // the deck the monster is born with
learnset: []Learn_Entry          // moves auto-learned at a level
move_pool: []Move_Id             // candidates for reward-card picks
```

`Species_Role :: enum { STARTER, WILD, ELITE, BOSS }`. **ELITE** is the tier
between the evolved lines and the bosses — regular monsters built to stand beside
one (Ashfang, Stormwing, Bogmaw, Dreadhorn, Rimewarden, Gravemaw). It exists so
the deep Arena floors stay varied instead of fielding the same five bosses.

**Wild decks** are built by `enrich_wild_deck` from the species' own data: the
`learnset` moves up to the wild's level, a thematic status card for its element
once it is tough enough, then `starter` basics to fill up to `WILD_DECK_MAX`.
So a wild *does* grow into its learnset — put a move there if you want wilds to
use it. `move_pool` is what **reward cards** and **Arena sets** draw from; there
is no shared generic card pool, so a species can only ever offer cards it could
plausibly run.

`base_energy_max` (the bank) is deliberately small — 4–6 against a regen of
~1.5–2 — because a large bank lets a fight's first turn dump a whole hand. See
[colony.md](colony.md#5-movement--energy).

## Sets (`sets.odin`)

`SPECIES_SETS: [Species_Id][MAX_SETS]Species_Set` — every species' **three**
Arena loadouts, each a `{name, ability, item, deck}` built around a synergy from
that species' own `move_pool`. The Arena's team builder rolls one per challenger,
so a species turns up as a Striker, a Controller or a Bulwark rather than a stock
wild. The header comment in `sets.odin` lists what every set name means. They are
generated from the move pools as a starting point — edit freely.

## Abilities (`abilities.odin`)

`Ability` is a 20-value enum: eight generic ones (`Berserk`, `Guardian`,
`Thick_Hide`, `Swift`, `Lucky`, `Vampiric`, `Regenerator`, `Intimidate`), seven
regular ones (`Momentum`, `Ironclad`, `Aftershock`, `Envenom`, `Predator`,
`Vengeance`, `Resilient`) and four boss-only (`Abyssal`, `Inferno`, `Colossus`,
`Dominion`). `ability_name` / `ability_desc` are the text; the effects live in
the hook points described in
[battle.md](battle.md#species-abilities-abilitiesodin).

`ABILITY_POOLS: [Species_Id][3]Ability` gives each species **three** options;
`creature_make(species, level, name, rng)` rolls one with `creature_roll_ability`
and stores it in `Creature.ability`. Effects and hook points are in
[battle.md](battle.md#species-abilities-abilitiesodin). To add an ability:
extend the enum, add its case to `ability_name` / `ability_desc`, add its effect
to the right hook, then list it in one or more species' pools.

## Items (`items.odin`)

`ITEM_DATA: [Item]Item_Info` (name, desc + effect fields). Every `Creature` has
one `item` slot, and items are **effect-based**, not stat sticks — the only field
that touches stats is `energy_regen` (`creature_recompute_stats`); everything else
hooks into `item_battle_start`, `creature_begin_round`, `play_creature_card`,
`colony_end_turn` and `capture_chance`.

Where items come from matters. A **slain boss always drops one** and ordinary
fights drop one sometimes; **Arena floors deliberately drop none** (a tower climb
would be a faucet). The **trial floors** are where a run hands out gear, and they
put it in the run's own unbounded pack (`Colony.arena_items`) rather than straight
onto a monster. The two-pane **inventory** (`G` / `J`) is where you pick which
monster wears what — click a monster, click an item, click Equip; a swap sends
the old item back to the bag. Opened from the Arena screen it shows only the
monsters on the tower tile and only the run's pack. To add an item: extend the
enum, add an `ITEM_DATA` entry, and add it to `ITEM_IDS`.

## Relics (`relics.odin`)

`Relic :: enum { War_Banner, … Beast_Fang }` with `RELIC_INFO` and `RELIC_ORDER`.
Counts live on `Colony.relics` and **stack**: `relic_*_mult` readers scale with
the count (e.g. `relic_power_mult = 1 + 0.08·count`). Bosses drop a random relic
(`random_relic` → `grant_relic`). Stat relics are mirrored into a package global
(`colony_sync_relic_state`) that `creature_recompute_stats` reads **for player
creatures only** (`Creature.player`), so wilds are unaffected; `colony_apply_relics`
recomputes everything you own. Non-stat relics hook into kill loot/XP
(`resolve_won`), food production (`colony_end_turn`), battle-start Block
(`begin_battle`) and turret damage (`colony_turrets`).

## Upgrades (`upgrades.odin`)

`Upgrade :: enum { NONE, Green_Thumb, … Scouts, Drills }` with
`UPGRADES: [Upgrade]Upgrade_Info` (name, desc, max_level, per-level cost,
`prereq` + `req_level`). Levels live on `Colony.upgrades`. Nodes form a **tree**
(35 nodes): `upgrade_unlocked` gates a child until its parent reaches
`req_level`, and `colony_buy_upgrade` spends crystals. `UPGRADE_ORDER` fixes the
panel order; the panel is a 3-column grid of `UPGRADE_ROWS` (12) rows, scrolled
with the wheel (`upgrade_cell_rect(i, scroll)` / `upgrade_max_scroll`). To add
one: extend the enum, add an `UPGRADES` entry (set `prereq`/`req_level` for a
child), read its level via an `upgrade_*` helper at the relevant hook (yields,
`improvement_cost_scaled`, `improvement_hp_cap`, `storage_cap`,
`monster_step_cost`, `colony_turrets`, `colony_menders`, `colony_fountains`,
`colony_nurseries`, `colony_item_cap`, `den_capacity`, `colony_barracks`, kill
loot/food/XP, spawn deter, capture odds, per-battle Block/Strength/Vulnerable),
and add it to `UPGRADE_ORDER`.

**Turret damage grows through upgrades** (`Focused Barrels` adds a flat amount
per level) — it does not depend on the target.

## Creatures & stats (`creature.odin`)

`Creature` is documented in [architecture.md](architecture.md#creature-creatureodin).
Stat scaling:

```
level_scale(level)              = 1 + 0.15*(level-1)
energy_scale(level)             = 1 + 0.12*ln(level)     // logarithmic!
creature_stats_for_level(...)   = base * level_scale, with
    energy_regen = base_energy * energy_scale * ENERGY_REGEN_FACTOR (0.5)
    energy_max   = base_energy_max * energy_scale
```

So `power`, `defense`, `speed` and HP grow ~15% per level, but **energy grows on
a logarithmic curve** (no hard cap) — otherwise a high-level monster would
out-regenerate its 5-card hand and energy would stop mattering. Species
`base_energy_max` is **8** (10 for elites/bosses) versus `base_energy` 3–4, so
the bank stays well above the regen and saving for a premium card is worth it.
Regen is additionally **halved** (`ENERGY_REGEN_FACTOR`), so a monster regens
~1.5–2.3/turn — the shared movement/battle pool is a tight resource.

- `creature_make(species, level, name)` builds a fresh creature + starter deck.
- `creature_level_up` recomputes stats and learns any `learnset` moves whose
  level was just reached.
- `xp_to_next(level)` and `monster_add_xp` (in `colony.odin`) handle XP; **xp now
  lives on `Creature.xp`** so the battle UI can read it.
- `creature_defense(c)` = `max(defense + defense_buff − defense_debuff, 0)`.
- `creature_has_element`, `creature_element`, `element_label`,
  `elements_label` are the type helpers used everywhere.

## Adding content

Short version; full recipes are in [hacking.md](hacking.md):

- **New move:** add to `Move_Id`, add a `MOVE_DATA` entry, then put it in a
  species' `learnset` (wilds grow into it), `starter` (its opening deck) or
  `move_pool` (reward cards and Arena sets). There is no shared generic pool. If
  it has a new *kind* of effect, teach `play_creature_card` and `move_value`.
- **New species:** append a `Species` literal to `SPECIES`, then add a matching
  `ABILITY_POOLS` entry and a `SPECIES_SETS` entry (or re-run the sets
  generator) — those two tables are indexed by `Species_Id` and the compiler will
  tell you if you forget. To make it appear in the world, add it to a `spawn_*`
  table; to put it in the Arena, nothing more is needed (the builder reads
  `SPECIES`).
- **New element:** extend `Element`, then the `element_super`/`element_weak`
  switches (they must stay exhaustive or become `#partial`), plus
  `element_name`/`element_color`.
