# Proposal: stat points, breeding, and boss tiers

**Status: DRAFT — edit freely.** Nothing here is built. The numbers are
proposals to react to, not settled balance. Anything marked **OPEN** is a
decision I don't want to make for you.

The loop we're aiming for:

> explore → find a high-level monster with its points in the stats you want →
> capture it → breed a line that keeps the best of each parent → beat a boss
> tier → higher-level spawns unlock → repeat → the endgame bosses need a bred
> team, and the Ascendant tier needs a *built* one.

That is ARK's loop, and your colony layer already has the right shape for it:
monsters stand on the map, breeding happens in a building, and the world
escalates. What's missing is a reason to *care* which monster you catch.

---

## 1. Stat points replace levels-as-multipliers

Today every stat is `base × level_scale(level)` with
`level_scale(L) = 1 + 0.15×(L−1)`, and genes nudge each stat ±5% per point.

New model: a monster owns **points per stat**, and **its level is the sum of
those points**.

```
stat = base_stat × (1 + POINT_SCALE × points_in_that_stat)

POINT_SCALE = 0.14
```

Why 0.14 specifically: 100 points in one stat gives ×15, which is about what a
level-100 monster has today (`level_scale(100)` = ×15.85). So **the game's whole
numeric range is essentially unchanged** — no card, damage formula, enemy or
arena number needs rebalancing.
What changes is *distribution*: a wild spreads its points wherever the dice say,
a bred line concentrates them.

Stats that take points: **HP, Power, Defense, Speed**. (Energy is a separate
question — **OPEN 1**.)

What the spread means in practice:

| monster | HP / PWR / DEF / SPD | level | HP × | PWR × |
|---|---|---|---|---|
| fresh wild, level 20 | 7 / 5 / 4 / 4 | 20 | 1.98 | 1.70 |
| wild level 60, unlucky spread | 15 / 15 / 15 / 15 | 60 | 3.10 | 3.10 |
| wild level 60, **lucky** spread | 10 / **38** / 6 / 6 | 60 | 2.40 | **6.32** |
| bred, all-in on damage | 0 / **100** / 0 / 0 | 100 | 1.00 | **15.0** |
| bred, balanced | 25 / 25 / 25 / 25 | 100 | 4.50 | 4.50 |
| bred, all-in on bulk | **100** / 0 / 0 / 0 | 100 | **15.0** | 1.00 |

A level-100 all-in damage dealer hits 3.3× harder than a balanced level-100 but
has a quarter of its HP; an all-in tank is 15× the brute's HP and hits for 1.0×.
That's the whole point: **level stops being a proxy for power**, so a bred
monster is genuinely different from a merely high-level one. Specialisation also
has a real cost, which is what makes the choice interesting rather than a free
win.

## 2. Capture, growth, and the +100 cap

- A monster's **base level** is fixed at capture or birth — the sum of the
  points it arrived with.
- It can then grow **+100 more levels** (100 points, **you** choose where). A
  capture at 60 can reach 160; a birth at 90 can reach 190.
- **At spawn, points are dealt at random** — so two level-60 wilds of the same
  species are genuinely different, and checking the spread is the hunt.
- **On level-up, you allocate the point.** That's the trade: the wild is a
  lottery, the bred line is a plan.
- XP still drives levels (`xp_to_next` stays), just capped at base+100.
- **Genes are removed entirely**: `Gene`, `GENE_BONUS`, `genes_roll_random`,
  `genes_breed`, the gene row in the roster/dex, and the save fields.

**OPEN 2 — the level-up screen.** Today a level-up offers 3 learnset cards. If
every level also asks for a stat point that is 100 extra clicks over a monster's
life. Suggest: the stat point is *always* a choice (it's the interesting
decision) but moves stay on learnset levels only; or batch stat points and ask
once every N levels. Your call.

## 3. Breeding

- **Inheritance: per stat, a straight 50/50 pick** — mother's value or father's
  value, independently for each stat. Not an average. (Today `genes_breed` takes
  the midpoint, which is what makes breeding feel like a rounding exercise.)
- **The child's level is the sum of its points.** Because it takes the best of
  each parent *per stat*, it can beat both parents — but it can never exceed the
  **higher** parent's level, since every stat is at most `max(mother, father)`.
  Growth past that comes from mutations and from better captures, exactly like
  ARK.
- **Mutations: 1/16 per birth**, adding +1 point to a random stat.
  **Max 32 mutations per monster** (a monster's counter, not a colony total).
- **Mutation counters are inherited.** Proposal: child = mother + father
  (+1 if it mutated this time), so the 32 cap arrives after ~5 generations of
  pushing the line. **OPEN 3.**
- **Females have a 20-turn breeding cooldown after a birth.** Males have none, so
  one good male can serve several females — which is the pressure that makes a
  second good female valuable.
- The Nursery keeps its shape: 2 parents, 4 stored babies, 2 food per turn,
  `NURSERY_PERIOD` 8 fed turns to a birth. The cooldown sits on the *female*, so
  a Nursery can stall waiting on her.
- Same species only, as today. **OPEN 4** — hybrids for a handful of pairs?

A worked generation:

| | HP | PWR | DEF | SPD | level |
|---|---|---|---|---|---|
| mother | 20 | 10 | 10 | 20 | 60 |
| father | 10 | **40** | 10 | 10 | 70 |
| child (rolls) | 20 | **40** | 10 | 20 | **90** |
| child (+ mutation) | 20 | **40** | 10 | 21 | **91** |

So the line's ceiling is set by its best finds: one level-60 with 38 Power is
worth more than ten level-40s, and the correct move is to *keep looking* rather
than breed the first pair you catch.

## 4. Spawns: wide bands, rare high rolls, gated by bosses

Today `spawn_level_for` includes `player_top_level × 2/3` — wilds track *your*
level, so there is never a better monster out there than the one you have. That
has to go, or the hunt has no point.

Proposal: the **ceiling** comes from boss kills, the **roll** below it is heavily
low-biased, and **heat** pushes the roll up without moving the ceiling.

Within a band: `level = floor + (cap − floor) × r²`, `r` uniform, `floor = 25% of
cap`. Squaring makes low rolls common and the top of the band rare:

| cap | floor | median | top 10% | top 1% |
|---|---|---|---|---|
| 30 | 7 | 13 | ≥28 | 30 |
| 75 | 18 | 32 | ≥69 | ≥74 |
| 150 | 37 | 65 | ≥139 | ≥149 |

At a cap of 60 you would see mostly 20s and 30s, occasionally a 55 — which is the
"a good one is out there somewhere" feeling.

**OPEN 5 — the gate table.** Sketch, to edit:

| gate (boss · tier) | spawn cap |
|---|---|
| start | 30 |
| Early · Beta | 45 |
| Early · Alpha | 60 |
| Early · Ascendant | 75 |
| Mid · Beta | 90 |
| Mid · Alpha | 105 |
| Mid · Ascendant | 120 |
| Late · Beta | 135 |
| Late · Alpha | 150 |
| Late · Ascendant | 165 |

**OPEN 6 — the spread bias.** A purely random spread means most wilds are
mediocre at everything. Proposal: each wild also rolls a *bias* toward one or two
stats (say 60% of its points land there), so "a level-60 with 38 Power" is a
thing that happens — checkable at capture, and worth hunting.

## 5. Bosses: three eras × three tiers, in a window

**Bosses stop roaming.** Right now they spawn in Boss Rooms and wander, which
means you meet them by accident. Instead, a Boss Room becomes an **entry point**
that opens a **Boss screen** — its own screen, exactly like the Arena's — with
the tiers, the preview, and the loot.

- **Three eras** — early / mid / end — × **three tiers** — **Beta**, **Alpha**,
  **Ascendant** — for nine fights.
- Each tier: a bigger team, higher stats, and **one extra ability**. Beta 1,
  Alpha 2, Ascendant 3. Nothing else in the game has more than one ability, so
  the extra layers are what make the tiers feel *different* rather than bigger.
- **Preview before you commit**: the boss, its team, every member's set/deck,
  their abilities, the tier's modifiers, and the loot table. Nothing hidden.
- **Ascendant is the endgame**: it should assume a bred, specialised team, and
  each fight should have a *specific counter* worth building toward. Ideas:
  - **Early — a brood boss** that adds a minion each round: bring AoE or lose to
    the clock.
  - **Mid — a wall** with enormous Block and thorns: Poison/Burn phases through,
    raw damage doesn't.
  - **End — a sovereign** that strips Strength and punishes buffs: bring base
    damage and a cleanse, not a buff stack.
- **OPEN 7 — which species.** You have five bosses now (`Deep_One`,
  `Boss_Leviathan`, `Boss_Infernal`, `Boss_Titan`, `Boss_Sovereign`). Options:
  three of them become the three eras (each with three tiers), or the five stay
  as flavour and the nine fights are new species.

## 6. Loot — and things that aren't equipment

Tier should pay in kind: Beta gives gear, Ascendant gives *identity*. New
**materials** (not equippable — a count in the bag, like relics):

| loot | what it is | sink |
|---|---|---|
| Bones / Ichor / Scales / Cores | tiered boss materials | craft held items; upgrade improvements past their normal cap |
| **Trophies** | one per boss · tier | permanent colony buffs (+XP, +spawn cap, +crystal yield) |
| **Blueprints** | named | unlock boss-gated improvements |
| Relics, held items, crystals | existing | as now, with better odds by tier |

Suggested rates per tier: Beta → materials + a relic; Alpha → materials + a held
item + crystals; Ascendant → a trophy, a blueprint, and a guaranteed strong item.
**OPEN 8 — the actual item list.** I'd rather you name these than me.

## 7. Arena

Today the tower levels challengers from the party's *entry average level* through
the XP curve. With +100 growth and breeding, level stops describing strength —
two level-100 teams can be 3× apart. Two problems follow:

1. **What should the tower scale on?** Options: the party's total points (same
   thing as level), the sum of its *stat multipliers* (so a min-maxed team faces
   a stronger tower), or a fixed ramp with the party's own power simply being the
   variable. **OPEN 9.**
2. **The deep floors.** With monsters capped at base+100, and bred bases reaching
   ~190, the tower's 1000 floors can't be level-driven forever. Beyond ~floor 200
   the difficulty should come from team size, items, boons and attrition (which
   is already the design) rather than from levels the player can't reach.

## 8. What this touches

- `creature.odin`: `Species`/`Creature` — points replace `genes`; `level_scale`
  becomes per-stat point scaling; `creature_stats_for_level` rewritten;
  `genes_*` deleted.
- `colony_storage.odin`: the Nursery's birth path — `genes_breed` → per-stat
  50/50, mutations, counters, cooldowns.
- `colony_wilds.odin`: `spawn_level_for` — remove player-tracking, add bands,
  caps and boss gates; alphas/elites read the cap.
- `colony.odin`: `xp_to_next` stays; a growth cap; the boss gate state; the
  Nursery cooldown state.
- `moves.odin` / `sets.odin`: unaffected (sets are deck+ability+item, not stats).
- `arena_*`: the level curve re-derived (OPEN 9).
- Bosses: `BOSS_SPECIES`, `boss_cronies`, `bosses_slain`, and the roaming spawn —
  replaced by a boss table, a boss screen and a tier-aware quest board.
- UI: stat-point allocation, stat display everywhere (base + points = live),
  boss screen + preview, materials in the bag.
- `save.odin`: a version bump; genes out, points/mutations/cooldowns/boss tiers
  in.

## 9. Open questions, collected

1. Does Energy take points, or stay fixed?
2. Level-up flow: stat point every level, or batched?
3. Mutation counter inheritance: sum, max, or rolled?
4. Hybrids, or same-species only?
5. The spawn-cap gate table.
6. How strongly a wild's spread is biased.
7. Which species become the nine boss fights.
8. The actual material/trophy/blueprint list.
9. What the Arena scales on now.
10. Does a bred monster's *base* level also cap somewhere (otherwise a line can
    compound +100 per generation forever)?

## 10. Suggested build order

1. **Stat points + genes out** (creature, UI, saves). The foundation; the game
   should feel the same, just reshaped.
2. **Spawns**: bands, caps, and the hunt. Capture becomes interesting even
   without bosses.
3. **Breeding**: 50/50 + mutations + cooldowns. Now a line can be built.
4. **Boss screen + tiers + preview**, reusing the Arena screen's shape.
5. **Loot and materials**, plus the sinks.
6. **Arena rescale**, last, because it depends on all of the above.
