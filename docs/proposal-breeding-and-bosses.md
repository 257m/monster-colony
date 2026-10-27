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

## 7. Scaling after the cap — the ceilings have to line up

Today a monster's power grows ~15% per level forever, so every other bonus can
stay flat and still be a sensible slice of a growing pie. With a hard ceiling the
pie stops growing, and the question changes. Not "should this be relative?" —
**"is the top of this upgrade line on par with the strongest monster?"**

So flat is fine. Watchtower Block can stay flat; it just needs to *grow with
upgrades* until its maximum is comparable to what a maxed monster brings. That
gives each line a concrete design target, and a way to check it:

> **At maximum, every colony bonus should be roughly as large as the strongest
> thing a single maxed monster can do.**

The top of the monster progression is a birth around 195 (top spawn band plus
the mutation cap) grown to ~295. Against that:

| bonus | today's maximum | on par with a maxed monster? |
|---|---|---|
| Watchtower starting Block | `+6` flat, **no upgrade line** | **no** — give it an upgrade line that grows toward a maxed monster's Block |
| Iron Idol (relic) | `+10` flat per copy | **no** — needs a per-copy percentage or a much stronger stack |
| Kitchen Strength | `+2` | yes — Strength is relative (+20% damage) |
| War Banner (relic) | `+2` Strength | yes (relative) |
| Mana Shard (relic) | `+1` energy regen | yes (~+50% of a 2/turn regen) |
| Warden's Seal (relic) | `+2` Thorns | yes (% of the attacker's max HP) |
| Caltrops / Barracks heal | 24% / 8% | yes (percentages) |
| Spike Trap / Turret damage | flat, via upgrades | see below |

### The uncapped lines are the real hazard

Three upgrades are `max_level = 99` **and flat** — unbounded in a game that has
just been bounded:

| upgrade | per level | at level 99 |
|---|---|---|
| Focused Barrels | +6 Turret damage | **+594 damage** |
| Reinforced Mounts | +12 Turret HP | **+1188 HP** |
| Reservoir | +2 Turret charge | **+198 charge** |

Either **cap them at a level whose top is on par** with a maxed monster, or
**re-base them on the target** — e.g. a Turret shot deals a % of the *target's*
max HP (like Poison and Thorns already do), which scales with the world and
never needs re-tuning. The second is tidier and keeps turrets relevant at any
depth.

The two uncapped *economy* nodes (Green Thumb, Rich Seams, +25%/level) are a
different question: they're self-limiting through `cost_growth` and they feed
gold/food rather than damage, so they can stay uncapped — but check that the
economy they produce still has a sink once levelling stops being one.

### Two casualties worth naming

- **The XP producers lose their job.** Training Yard (+8 XP/turn), Barracks
  (+1/kill) and the Academy upgrade exist to accelerate levelling. At birth+100
  they have nothing to accelerate. Either they feed something else (breeding
  speed, materials) or levelling needs to be slow enough that they still matter.
- **Heat plateaus.** Heat is improvements + monster levels, both of which now
  cap, so raids stop escalating. Fine — the bosses are the escalation — but tune
  the raid system to stay interesting *at* the plateau rather than to keep
  climbing.

**OPEN 12 — how far to rework.** Minimum: give Watchtower Block an upgrade line,
fix Iron Idol, and either cap or re-base the three uncapped turret nodes.
Fuller pass: re-derive all 33 improvements and the whole tree against "what is
this worth at the cap?", and give the economy its breeding-era sinks.

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

## 12. Open questions — how to answer these

You don't have to answer them all, and you don't have to answer them now. Each
one has a **default** — say nothing and I'll take it and note it in the doc. If
you disagree later, it's a line to change, not a rebuild.

Two ways to answer:

- **In chat**, briefly: `"1a, 2b, 3 default, rest default"` is plenty.
- **In this file**: change **OPEN n** to **DECIDED — n: (your answer)**, or just
  write under the question. It's your document.

Only the ones under **blocks** for the next stage actually hold anything up:

| to start | answer |
|---|---|
| stage 1 — stat points | **1, 2** |
| stage 2 — spawns | **5, 6** |
| stage 3 — breeding | **3, 4** |
| stage 4 — bosses | **7, 8, 9, 10** |
| stage 5 — loot | **14** |
| stage 6 — colony scaling | **12** |
| stage 7 — learnsets | **13** |
| stage 8 — arena | **11** |

So to unblock the *first* batch I need **1 and 2**, and I'd like **5 and 6** at
the same time so spawns can follow straight on.

---

### OPEN 1 — Does Energy take points?
- **(a)** No; energy stays a species constant, points cover HP/Power/Defense/Speed.
- **(b)** Yes, as a fifth stat.
- **(b)** makes energy a breeding target and lets you build a tempo line, but it
  also means a bad spread can starve a monster of the thing that lets it play
  cards — punishing in a way the other four aren't.
- **Default: (a).** **Blocks: stage 1.**

### OPEN 2 — How does the level-up screen ask for stat points?
- **(a)** One point, one click, every level.
- **(b)** Points bank, and you spend them in a batch whenever you like (a "stats"
  tab beside the deck viewer).
- **(c)** They auto-spend along a plan you set, re-specable from town.
- (a) means 100 modal clicks per monster. (b) keeps the decision but at your
  pace. (c) is the least tedious and the most "set and forget" — but it removes
  the moment-to-moment choice.
- **Default: (b).** **Blocks: stage 1.**

### OPEN 3 — How do mutation counters inherit?
- **(a)** Sum of both parents (+1 if this birth mutated) — hits the 32 cap after
  ~5 generations.
- **(b)** The higher of the two — lines last longer, the cap arrives slowly.
- **(c)** Random.
- **Default: (a)** (closest to ARK). **Blocks: stage 3.**

### OPEN 4 — Hybrids or same-species only?
- **(a)** Same species only, as today.
- **(b)** A short list of hand-authored hybrid pairs.
- (b) is pure content and can be layered on later without changing the model.
- **Default: (a).** **Blocks: stage 3.**

### OPEN 5 — How strongly is a wild's spread biased?
- **(a)** None — fully random.
- **(b)** ~60% of its points land in one or two favoured stats.
- **(c)** Stricter (75%+), so wilds are more lopsided and easier to judge.
- This is the knob that decides whether "a level-60 with 38 Power" is a
  one-in-fifty find or something you see every few captures.
- **Default: (b).** **Blocks: stage 2.**

### OPEN 6 — The spawn-cap table
Needs the era/boss roster (OPEN 9) to settle, but the sketch in §4 works as-is.
- **Default: the sketch as written** (30 → 165 across three eras, rising per Beta
  kill). **Blocks: stage 2.**

### OPEN 7 — How do tiers unlock?
- **(a)** Per boss: Beta → Alpha → Ascendant on that boss alone.
- **(b)** Era-wide: all bosses at Beta unlocks Alpha for all of them.
- (a) lets you push one favourite boss deep early; (b) makes each era a single
  ladder. (a) plus the era gate in OPEN 8 keeps both pressures.
- **Default: (a).** **Blocks: stage 4.**

### OPEN 8 — What opens the next era?
- **(a)** Every boss in the era beaten at **Beta**.
- **(b)** …at **Alpha**. **(c)** …at **Ascendant** (a much longer wall).
- **Default: (a).** **Blocks: stage 4.**

### OPEN 9 — The 15-boss roster, gimmicks and teams
Hand-authored content. The shape is in §5 (gimmick → the specific answer).
- **Default: I'll draft all fifteen for you to edit**, the way the species sets
  were drafted — names, gimmicks, teams and which species each one is.
  **Blocks: stage 4.**

### OPEN 10 — Era names
**A:** Shallows / Deepdark / Abyss  ·  **B:** Warrens / Chasm / Maw  ·
**C:** Roothold / Underworks / Underthrone.
- **Default: A.** Doesn't block anything — cosmetic, change whenever.

### OPEN 11 — What does the Arena scale on now?
- **(a)** The party's total points (i.e. its level).
- **(b)** The sum of its stat *multipliers* — so a min-maxed team faces a
  correspondingly stronger tower.
- **(c)** A fixed ramp, with the party's power simply being the variable.
- (b) is the only one that keeps the tower an even fight once breeding makes
  level a poor description of strength — but it also means the tower deliberately
  neutralises your specialisation, which may not be what you want the "prove
  your team" mode to do.
- **Default: (b).** **Blocks: stage 8.**

### OPEN 12 — How far to rework improvements and upgrades?
- **(a)** Minimum: an upgrade line for Watchtower Block, fix Iron Idol, and cap
  or re-base the three uncapped turret nodes.
- **(b)** Full pass over all 33 improvements and the tree, answering "what is
  this worth at the cap?"
- **Default: (a) during the systems work, (b) as its own batch after.**
  **Blocks: stage 6 (for (a)).**

### OPEN 13 — Does the deck grow with level?
- **(a)** Fixed ~10 cards; every new card is a replacement decision.
- **(b)** Grows as the monster levels.
- (a) keeps each learnset choice sharp and makes deck thinning meaningful;
  (b) dilutes both but lets a high-level monster express more.
- **Default: (a).** **Blocks: stage 7.**

### OPEN 14 — The loot list (materials, trophies, blueprints)
Names and numbers for the non-equippable drops in §6.
- **Default: I'll draft them for you to edit.** **Blocks: stage 5.**

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
