# Proposal: stat points, breeding, and boss tiers

**Status: DRAFT v2 — edit freely.** Nothing here is built. Numbers are proposals
to react to. Anything marked **OPEN** is a decision I don't want to make for you.

The loop we're aiming for:

> explore → find a high-level monster whose points sit in the stats you want →
> capture it → breed a line that keeps the best of each parent → beat a boss
> tier → raise the spawn ceiling → hunt deeper → repeat → the endgame bosses
> need a bred team, and Ascendant needs one built to answer *that* boss.

That is ARK's loop. Your colony layer already has the shape for it: monsters
stand on the map, breeding happens in a building, and the world escalates. What's
missing is a reason to care which monster you catch.

---

## 1. Stat points replace levels-as-multipliers

Today every stat is `base × level_scale(level)` with
`level_scale(L) = 1 + 0.15×(L−1)`, and genes nudge each stat ±5% per point.

New model: a monster owns **points per stat**, and **its level is the sum of
those points**.

```
stat = base_stat × (1 + POINT_SCALE × points_in_that_stat)

POINT_SCALE = 0.15
```

**Why 0.15** — it is exactly the slope `level_scale` already uses, so the game's
numeric range does not move at all and no card, damage formula, enemy or arena
number needs rebalancing. Only *distribution* becomes the variable. (You said
0.14 felt odd; 0.14 was me chasing ×15 at 100 points. 0.15 is the rounder number
*and* the one the code already agrees with.)

If you'd rather the whole game got tighter or looser, this one constant is the
lever:

| POINT_SCALE | × at 100 points | vs today |
|---|---|---|
| 0.125 | ×13.5 | 15% weaker |
| **0.15** | **×16.0** | **today (±1%)** |
| 0.20 | ×21.0 | 33% stronger |

Stats that take points: **HP, Power, Defense, Speed**. (Energy is **OPEN 1**.)

| monster | HP / PWR / DEF / SPD | level | HP × | PWR × |
|---|---|---|---|---|
| fresh wild, level 20 | 7 / 5 / 4 / 4 | 20 | 2.05 | 1.75 |
| wild level 60, unlucky spread | 15 / 15 / 15 / 15 | 60 | 3.25 | 3.25 |
| wild level 60, **lucky** spread | 10 / **38** / 6 / 6 | 60 | 2.50 | **6.70** |
| bred, all-in on damage | 0 / **100** / 0 / 0 | 100 | 1.00 | **16.0** |
| bred, balanced | 25 / 25 / 25 / 25 | 100 | 4.75 | 4.75 |
| bred, all-in on bulk | **100** / 0 / 0 / 0 | 100 | **16.0** | 1.00 |

A level-100 all-in damage dealer hits ~3.4× harder than a balanced one and has a
quarter of its HP. **Level stops being a proxy for power**, and specialisation
has a real cost — which is what makes the breeding choice interesting rather
than a free win.

## 2. Two kinds of points: birth and levelling

This is the rule that keeps the ladder honest. A monster has **two separate
pools**:

- **Birth points** — what it spawned or hatched with. Random for a wild, chosen
  by inheritance for a child.
- **Level points** — up to **+100**, allocated by you as it levels.

```
level = birth_points + level_points           (so a wild caught at 60 can reach 160)
stat  = base × (1 + 0.15 × (birth + level))   (both count for fighting)

Breeding reads BIRTH POINTS ONLY. Level points are never inherited.
```

So a monster you poured 100 levels into contributes **exactly what it was caught
as** to its offspring. You get what it *was*, not what you made it. That alone
removes the compounding problem — no cap needed, and there is no reason to hold
a monster back.

Worked example of why it matters:

```
mother  birth 20/10/10/20  (level 60)   grown 60/30/30/40  (level 160)
father  birth 10/40/10/10  (level 70)   grown 30/90/25/25  (level 170)

child base = best of each BIRTH stat = 20/40/10/20  ->  level 90
(if growth were inherited it would be 60/90/30/40 = level 220)
```

- **At spawn, points are dealt at random** — two level-60 wilds of a species are
  genuinely different, and checking the spread *is* the hunt.
- **On level-up, you allocate.** The wild is a lottery; the bred line is a plan.
- XP still drives levels (`xp_to_next` stays), capped at birth + 100.
- **Genes are removed entirely**: `Gene`, `GENE_BONUS`, `genes_roll_random`,
  `genes_breed`, the gene row in the roster/dex, and the save fields.

**OPEN 2 — the level-up screen.** Today a level-up offers 3 learnset cards. With
100 levels, one stat click per level is 100 clicks across a monster's life.
Suggest: stat points are always a choice but can be **banked and spent in
batches**, and moves stay on learnset levels only.

## 3. Breeding

- **Inheritance: per stat, a 50/50 pick between the parents' birth values** — not
  an average. (Today `genes_breed` takes the midpoint, which is what makes
  breeding feel like rounding.)
- **Child level = the sum of the points it inherited.** It takes the best of each
  parent per stat, so it can beat both — but never exceed the **higher parent's
  birth level**, because each stat is at most `max(mother, father)`.
- **Bred base levels are not capped.** Growth past the parents comes from
  mutations and from better captures, exactly like ARK — and it is bounded
  naturally by the rule above.
- **Mutations: 1/16 per birth**, +1 point to a random stat.
  **Max 32 mutations per monster.**
- **Mutation counters are inherited.** Proposal: child = mother + father
  (+1 if it mutated), so 32 arrives after ~5 generations of pushing a line.
  **OPEN 3.**
- **Females have a 20-turn breeding cooldown after a birth.** Males have none, so
  one good male can serve several females — which makes a second good female
  valuable. The Nursery keeps its shape (2 parents, 4 babies, 2 food/turn,
  `NURSERY_PERIOD` 8 fed turns); the cooldown sits on the female, so a Nursery
  can stall waiting on her.
- Same species only, as today. **OPEN 4** — hybrids for a handful of pairs?

The consequence worth stating plainly: **a line's ceiling is set by its best
captures plus mutations, never by grinding.** One level-60 wild with 38 Power is
worth more than ten level-40s, and the right move is to keep looking rather than
breed the first pair you catch.

## 4. Spawns: wide bands, rare high rolls, gated by eras

Today `spawn_level_for` includes `player_top_level × 2/3`, so wilds track *your*
level and there is never a better monster out there than the one you own. That
goes, or the hunt has no point.

- **The ceiling** comes from boss progress (below). **Heat** pushes the roll up
  within the band without moving the ceiling, which keeps "build big and the
  underground answers" true.
- **The roll** is heavily low-biased: `level = floor + (cap − floor) × r²`,
  `r` uniform, `floor = 25% of cap`. Squaring makes the top of a band rare:

| cap | floor | median | top 10% | top 1% |
|---|---|---|---|---|
| 30 | 7 | 13 | ≥28 | 30 |
| 75 | 18 | 32 | ≥69 | ≥74 |
| 150 | 37 | 65 | ≥139 | ≥149 |

At a cap of 60 you see mostly 20s and 30s, occasionally a 55 — "a good one is out
there somewhere".

**OPEN 5 — the spread bias.** A purely random spread makes most wilds mediocre at
everything. Proposal: each wild also rolls a bias toward one or two stats (say
60% of its points land there), so "a level-60 with 38 Power" is something that
happens — checkable at capture, and worth hunting.

**OPEN 6 — the cap table.** Sketch, tied to the era structure in §5:

| progress | depth band | spawn cap |
|---|---|---|
| start (the Shallows) | 1–9 | 30 |
| +1 Shallows Beta kill | 1–9 | 35 |
| … all 5 Shallows Beta | 1–9 | 55 |
| all 5 Shallows Beta (era gate) | 10–19 | 60 |
| +1 Deepdark Beta kill | 10–19 | 68 |
| … all 5 Deepdark Beta | 10–19 | 100 |
| all 5 Deepdark Beta (era gate) | 20+ | 105 |
| +1 Abyss Beta kill | 20+ | 117 |
| … all 5 Abyss Beta | 20+ | 165 |

## 5. Bosses: per-era rosters, three tiers, hunted by room

Bosses **stop roaming**. A Boss Room is an entry point that opens its own screen
— same shape as the Arena's — with the boss, the preview and the tier choice.

- **Three eras**: Early, Mid, End. **Each has its own roster of up to 5 bosses.**
- **Era = depth band.** A Boss Room rolls **a random boss from its band's
  roster**, decided when the room is generated. So you hunt for the *room*
  holding the boss you want, not just a room.
- **Tiers**: at the room you pick **Beta / Alpha / Ascendant**. Proposal:
  **Beta is open**; **Alpha unlocks on that boss's Beta kill**; **Ascendant on its
  Alpha**. A per-boss ladder, so you can push one boss deep before moving on.
  **OPEN 7.**
- **Era gate**: the next era's band (and its higher spawn cap) opens when **all
  of the current era's bosses are beaten at Beta**. So progressing means hunting
  every room in a band, not farming the one you like. **OPEN 8** — should
  Ascendant be required instead, or count toward it?
- **Each tier**: a bigger team, higher stats, and **one extra ability** — Beta 1,
  Alpha 2, Ascendant 3. Nothing else in the game has more than one, so the tiers
  change *what the fight is*, not just its size.
- **Preview before you commit**: the boss, its whole team, every member's
  set/deck, their abilities, the tier's modifiers and the loot table. Nothing
  hidden.

### Bosses should ask a question and accept one answer

Each boss gets a **gimmick** and a **specific answer** — something a *bred*
monster can be built to be, so the breeding system is what lets you take the
fight. Sketches, in the shape I'd like the table to take:

| era | boss | gimmick | the answer |
|---|---|---|---|
| Shallows | a brood boss | adds a minion every round; loses only when the board is clear | **AoE** damage, or enough burst to ignore the adds |
| Shallows | a burrower | goes untargetable every other round | **multi-hit / chip** and **regen** so dead turns cost you nothing |
| Deepdark | a wall | enormous Block, thorns while Blocked | **Poison** (phases through Block) and a **thorn tank** of your own |
| Deepdark | a seer | strips your Strength at the start of each round | **raw base damage** from a high-Power breeder, not buff stacking |
| Abyss | a sovereign | heals itself unless it is Burning; immune to Poison | a **Burn** line + enough burst to out-pace the heal |
| Abyss | a colossus | hits one monster for lethal, telegraphed | a **bulk breeder** built to eat it, plus **cleanse** |

**OPEN 9 — the full 15-boss roster**: names, gimmicks, teams and which species
they are. I'd rather design these with you than guess.

## 6. Loot — and things that aren't equipment

Tier should pay in kind: Beta gives gear, Ascendant gives *identity*. New
**materials** (not equippable — a count in the bag, like relics):

| loot | what it is | sink |
|---|---|---|
| Bones / Ichor / Scales / Cores | tiered boss materials | craft held items; upgrade improvements past their normal cap |
| **Trophies** | one per boss · tier | permanent colony buffs (+XP, +spawn cap, +crystal yield) |
| **Blueprints** | named | unlock boss-gated improvements |
| Relics, held items, crystals | existing | as now, better odds by tier |

Suggested rates: **Beta** → materials + a relic. **Alpha** → materials + a held
item + crystals. **Ascendant** → a trophy, a blueprint and a guaranteed strong
item.

This is also where your `IDEAS.md` note applies directly: **a strong relic should
be narrow**. Beta loot can be boring and always-useful; Ascendant loot should be
strong and conditional, so it's a real decision rather than a strict upgrade.

## 7. Scaling after the cap — improvements and upgrades need a pass

This is the consequence of a hard ceiling that's easy to miss. Today a monster's
power grows ~15% per level forever, so **everything else can stay flat and still
be a small slice of a growing pie**. Once the pie stops growing (birth + 100,
and births capped by the top spawn band), the colony layer stops being a slice
and becomes **the whole endgame progression** — so it has to be designed for
that, not inherited from when levels did the work.

The rule to sort the existing content by:

> **Anything meant to matter forever must be *relative*. Anything flat is an
> early-game crutch that quietly deflates.**

Status/effect maths already behaves: Strength is +10% damage per point, Thorns is
a % of the attacker's max HP, Caltrops/Barracks are %s, energy regen is +1
against a regen of ~2 (so it stays ~+50%). The problems are the flat numbers:

| bonus | today | as stats plateau | proposal |
|---|---|---|---|
| Watchtower starting Block | `+6` flat | deflates hard | **% of max HP** |
| Iron Idol (relic) | `+10` flat Block | deflates hard | **% of max HP** |
| War Banner (relic) | `+2` Strength | stays relative (+20% dmg) | keep |
| Kitchen Strength | `+2` | stays relative | keep |
| Swift Totem (relic) | `+4` Speed | relative (initiative order) | keep |
| Mana Shard (relic) | `+1` regen | ~+50% forever | keep |
| Warden's Seal (relic) | `+2` Thorns | relative (% of attacker HP) | keep |
| Training Yard XP | `+8`/turn | **meaningless at the cap** | re-purpose: XP → something else, or let it *raise* the birth cap |
| Barracks XP | `+1`/kill | same | same |

Three more things this touches:

- **The XP producers lose their job.** Training Yards, Barracks and the Academy
  upgrade all exist to accelerate levelling. Once every monster hits birth + 100
  they're dead weight. Either they feed something else (materials, breeding
  speed), or levelling takes long enough that they still matter — worth deciding
  deliberately rather than discovering.
- **The economy's sinks change.** Gold's biggest sink late is now **capture cards
  and breeding fodder** rather than levelling. Food's is upkeep on a larger
  roster. That's a good fit — it pushes the late game toward the breeding loop —
  but the numbers should be checked against it.
- **Heat plateaus.** Heat is improvements + monster levels, both of which cap, so
  raids stop escalating. That's fine (the bosses are the escalation now) but it
  means the raid system should be tuned to stay interesting *at* the plateau
  rather than to keep climbing.

**OPEN 12 — how far to rework.** Minimum: convert the two flat Block bonuses to
percentages and re-purpose the XP producers. Fuller pass: re-derive every
improvement and upgrade against a "what does this do at the cap?" question, and
give the economy its breeding-era sinks.

## 8. Arena

Today the tower levels challengers from the party's *entry average level* through
the XP curve. With birth/level points and breeding, level stops describing
strength — two level-100 teams can be 3.4× apart. Two problems:

1. **What should the tower scale on?** Options: the party's total points (same
   as level), the sum of its *stat multipliers* (so a min-maxed team faces a
   stronger tower), or a fixed ramp with the party's own power as the variable.
   **OPEN 11.**
2. **The deep floors.** Monsters cap at birth+100, and bred births reach ~200, so
   the tower's 1000 floors can't be level-driven forever. Past roughly floor 200
   difficulty should come from team size, items, boons and attrition — which is
   already the design.

Also from `IDEAS.md`: **the arena should offer a choice of 3 relics** rather than
handing you one. That drops straight into the event floors.

## 9. Queued from `IDEAS.md`

You said yes to implementing these; they're independent of breeding, so they can
be a batch of their own at any point.

1. **Power ↔ niche-ness for relics (and items, abilities, cards).** Strong relics
   should be strong *and* conditional; weak ones unconditional but dull. Cards
   are the flexible case — you can tune power, cost *or* trigger. Concretely:
   audit the 10 relics against that rule, and re-cost/re-condition them so no
   relic is a strict upgrade.
2. **Arena relic offers: choose 1 of 3.** Event floors present three run boons.
3. **Run-scoped cards and abilities for *any* team member.** An event can offer a
   temporary card or ability that you attach to whichever monster you like; it
   expires with the run. This is close to what event floors already do, except
   the target is chosen by you and the offer isn't fixed to one monster.

## 10. Learnsets have to span the new curve

Today learnsets end around level 16–24, which was fine when level ~25 was late
game. With a birth of 60 and +100 growth, a monster lives to level ~160, so:

- learnset entries spread across the whole climb — roughly **every 8–12 levels**
  out to ~100, with **2–3 options at each level** so builds diverge.
- **more learnable moves** overall: the per-species `move_pool` needs to be deep
  enough that 10–12 learnset levels each offer real choices rather than filler.
- **OPEN 13 — deck size**: does a deck stay ~10 cards, or grow as a monster
  levels? A fixed deck makes each new card a *replacement* decision, which suits
  the "build" fantasy; a growing deck dilutes it.

This is the biggest content job in the plan and it touches every species, so it
should probably be its own pass after the systems are in.

## 11. What this touches

- `creature.odin`: points replace genes; `level_scale` → per-stat point scaling;
  `creature_stats_for_level` rewritten; `genes_*` deleted.
- `colony_storage.odin`: birth path — per-stat 50/50 on **birth** points,
  mutations, counters, female cooldowns.
- `colony_wilds.odin`: `spawn_level_for` — drop player-tracking; add bands, caps,
  spread bias, era gates; boss rooms roll a boss instead of spawning one.
- `colony.odin`: XP cap; birth/level point split; boss-progress state; Nursery
  cooldown state.
- Bosses: `BOSS_SPECIES`, `boss_cronies`, `bosses_slain` and the roaming spawn are
  replaced by an era/roster table, a boss screen, per-boss tier progress, and a
  tier-aware quest board.
- UI: stat allocation; stat display everywhere (birth + level = live); boss screen
  and preview; materials in the bag; era progress.
- `save.odin`: version bump; genes out; points, mutations, cooldowns, boss tiers
  and era gates in.

## 12. Open questions, collected

1. Does Energy take points, or stay fixed?
2. Level-up flow: stat point per level, banked, or batched?
3. Mutation counter inheritance: sum, max, or rolled?
4. Hybrids, or same-species only?
5. How strongly a wild's spread is biased.
6. The spawn-cap table (per-era, per-Beta-kill).
7. Tier unlocks: per-boss Beta→Alpha→Ascendant?
8. Era gate: all Beta kills, or a stricter bar?
9. The 15-boss roster and their gimmicks.
10. Era names: A, B or C (or your own).
11. What the Arena scales on now.
12. How far to rework improvements/upgrades for the cap (see §7).
13. Deck size: fixed 10, or grows with level?

## 13. Suggested build order

1. **Stat points + birth/level split + genes out** (creature, UI, saves). The
   foundation; the game should feel the same, just reshaped.
2. **Spawns**: bands, caps, spread bias. Capture becomes interesting on its own.
3. **Breeding**: birth-point 50/50, mutations, cooldowns. Now a line can be built.
4. **Boss screen + eras + tiers + preview**, reusing the Arena screen's shape.
5. **Loot and materials**, plus the sinks and the relic rule from §9.
6. **The scaling pass** (§7): flat bonuses to percentages, XP producers
   re-purposed, economy sinks checked at the cap. This is what keeps the colony
   layer meaningful once monsters stop growing.
7. **Learnsets/move pools** across the new curve — the content pass.
8. **Arena rescale**, last, because it depends on all of the above.
