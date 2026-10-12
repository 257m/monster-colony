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
name, desc, cost: f32, element: Element
damage, block, hits, vulnerable, strength, defense: f32, heal, draw
strength_down: int, defense_down: f32      // debuffs applied to the TARGET
vuln_bonus, block_bonus, combo_bonus: int  // conditional damage synergies
```

- `cost` is in energy half-steps (0.5 granularity) because energy is a float.
- `hits` defaults to 1; multi-hit cards call `apply_damage` per hit (so Strength
  and Block apply per hit).
- Synergies add to the **first hit only** when the condition holds:
  `vuln_bonus` (target is Vulnerable), `block_bonus` (you have Block),
  `combo_bonus` (you already played a card this turn).
- `move_value(id)` is the **AI heuristic** — raise a term here if you want the AI
  to value a card more (e.g. new status effects need a term).
- `fmt_num` (top of the file) formats floats compactly (`3`, `2.5`, `1.25`).

There are 62 moves. The `desc` string is what the card shows; keep it accurate.

## Species (`creature.odin`)

`SPECIES: [27]Species` — each entry:

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

`Species_Role :: enum { STARTER, WILD, ELITE, BOSS }`.

> **Important:** wild monsters are created with `creature_make`, which copies
> **only `starter`**. Wilds do **not** learn `learnset` moves. So if you want
> wilds to *use* a move, put it in their `starter`; put reward-only moves in
> `move_pool` / `COMMON_MOVES` instead.

`COMMON_MOVES` are reward-only options available to every species.

## Abilities (`abilities.odin`)

`Ability :: enum { NONE, Berserk, Guardian, Thick_Hide, Swift, Lucky, Vampiric, Regenerator, Intimidate }`.

`ABILITY_POOLS: [27][3]Ability` gives each species **three** options;
`creature_make(species, level, name, rng)` rolls one with `creature_roll_ability`
and stores it in `Creature.ability`. Effects and hook points are in
[battle.md](battle.md#species-abilities-abilitiesodin). To add an ability:
extend the enum, add its case to `ability_name` / `ability_desc`, add its effect
to the right hook, then list it in one or more species' pools.

## Items (`items.odin`)

`Item :: enum { NONE, Ember_Charm, … Snare_Kit }` with `ITEM_DATA: [Item]Item_Info`
(name, desc + effect fields). Every `Creature` has one `item` slot. Items are
found as battle loot into `Colony.items` and equipped from the deck viewer. To
add an item: extend the enum, add an `ITEM_DATA` entry (set the fields it uses),
and add it to `ITEM_IDS` (for random drops). Stat fields feed
`creature_recompute_stats`; the rest hook into `item_battle_start`,
`creature_begin_round`, `play_creature_card`, `colony_end_turn`, and
`capture_chance`.

## Creatures & stats (`creature.odin`)

`Creature` is documented in [architecture.md](architecture.md#creature-creatureodin).
Stat scaling:

```
level_scale(level)              = 1 + 0.15*(level-1)
creature_stats_for_level(...)   = base * level_scale, with
    energy_regen = clamp(base_energy * scale, base_energy, 6)
    energy_max   = clamp(base_energy_max * scale, energy_regen, 16)
```

So `power`, `defense`, `speed`, `energy_*` all grow ~15% per level; HP too.
Species `base_energy_max` is **8** (10 for elites/bosses) versus `base_energy` 3–4,
so the bank is ~2.7× the regen and saving for expensive cards is worth it.

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

- **New move:** add to `Move_Id`, add a `MOVE_DATA` entry, (optionally) put it in
  a species' `learnset`/`starter`/`move_pool` or in `COMMON_MOVES`. If it has a
  new *kind* of effect, teach `play_creature_card` and `move_value`.
- **New species:** append a `Species` literal to `SPECIES`. Nothing else is
  required — spawn tables, encyclopedia and battle all index by species number.
  If you want it to appear in the world, add its index to a `spawn_species_for`
  case and/or `STARTER_SPECIES`.
- **New element:** extend `Element`, then the `element_super`/`element_weak`
  switches (they must stay exhaustive or become `#partial`), plus
  `element_name`/`element_color`.
