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

Stats that take points: **HP, Power, Defense, Speed** — unless OPEN 1 below
says otherwise.

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

### OPEN 1 — Does Energy take points?
- **(a)** No; energy stays a species constant, points cover HP/Power/Defense/Speed.
- **(b)** Yes, as a fifth stat.
- **(b)** makes energy a breeding target and lets you build a tempo line, but it
  also means a bad spread can starve a monster of the thing that lets it play
  cards — punishing in a way the other four aren't.
- **Default: (a).** **Blocks: stage 1.**
Answer: energy and energy regen can take points *but* they scale logarithmically. there wont be a insane difference in energy stats even with a bunch of points but a creature with few points in energy is intended to be unable to play high power cards. thats the trade off. they can still play lower energy cards if they wish. the base energy alone allows for that after all.

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

### OPEN 2 — How does the level-up screen ask for stat points?
- **(a)** One point, one click, every level.
- **(b)** Points bank, and you spend them in a batch whenever you like (a "stats"
  tab beside the deck viewer).
- **(c)** They auto-spend along a plan you set, re-specable from town.
- (a) means 100 modal clicks per monster. (b) keeps the decision but at your
  pace. (c) is the least tedious and the most "set and forget" — but it removes
  the moment-to-moment choice.
- **Default: (b).** **Blocks: stage 1.**
Answer: (b) but its still one click per level. you go into the creature's stats tab and apply the level. this can be done mid battle as well.

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
- **Females have a 20-turn breeding cooldown after a birth.** Males have none, so
  one good male can serve several females — which makes a second good female
  valuable. The Nursery keeps its shape (2 parents, 4 babies, 2 food/turn,
  `NURSERY_PERIOD` 8 fed turns); the cooldown sits on the female, so a Nursery
  can stall waiting on her.
- Same species only, as today.

The consequence worth stating plainly: **a line's ceiling is set by its best
captures plus mutations, never by grinding.** One level-60 wild with 38 Power is
worth more than ten level-40s, and the right move is to keep looking rather than
breed the first pair you catch.

### OPEN 3 — How do mutation counters inherit?
- **(a)** Sum of both parents (+1 if this birth mutated) — hits the 32 cap after
  ~5 generations.
- **(b)** The higher of the two — lines last longer, the cap arrives slowly.
- **(c)** Random.
- **Default: Each child has a matrilineal and a patrilineal mutation counter. the mutation counter is passed based on who passes a given stat to the child. like if it gets the mutated attack stat from its mother that adds to its mutations on its matrilineal mutation counter. each side gets 16 mutations each.

### OPEN 4 — Hybrids or same-species only?
- **(a)** Same species only, as today.
- **(b)** A short list of hand-authored hybrid pairs.
- (b) is pure content and can be layered on later without changing the model.
- **Default: (a).** **Blocks: stage 3.**

## 4. Spawns and heat: rings, caps, and the size of your footprint

Today `spawn_level_for` includes `player_top_level × 2/3`, so wilds track *your*
level and there is never a better monster out there than the one you own. That
goes, or the hunt has no point.

- **The ceiling** comes from boss progress (below). **Heat** lifts the roll
  within the ring without moving the ceiling — it is what makes a hot colony
  worth having, and it is also what makes it a target. See the heat section
  under the cap table.
- **The roll** is heavily low-biased: `level = low + (span) × r²`, `r` uniform,
  `low = 25% of cap`, `span = cap − low − heat bonus`. Squaring makes the top of
  a ring rare:

| cap | lowest | median | top 10% | top 1% |
|---|---|---|---|---|
| 30 | 7 | 13 | ≥28 | 30 |
| 75 | 18 | 32 | ≥69 | ≥74 |
| 150 | 37 | 65 | ≥139 | ≥149 |

At a cap of 60 you see mostly 20s and 30s, occasionally a 55 — "a good one is out
there somewhere".

### What "depth" means here

There are no floors in this game. The map is infinite and you start at
`start_hex`, so depth is **distance from your entrance**:
`hex_distance(start_hex, hex)`. That is already how the world thickens today
(`dist / 4` in `spawn_level_for`), and it is the only axis that stays meaningful
as the map grows in every direction.

(`Colony.floor` exists in the save and the HUD prints "Floor 1", but nothing ever
increments it — it is vestigial. This work should drop it, or repurpose it as the
name of the ring you are standing in.)

So **an era is a ring**, and "depth band" just means the ring:

| era | ring (distance from the entrance) | notes |
|---|---|---|
| Shallows | 6–15 | boss rooms already start at `dist >= 6`, so this is the first ring one can appear in |
| Deepdark | 16–30 | |
| Abyss | 31+ | |

The boundary between rings is **sealed** until the era gate opens — otherwise
nothing stops you walking to the Abyss on turn 1 and the gate would be
decoration. The seal cuts both ways; see *"The rings are sealed in both
directions"* below. OPEN 6 owns the boundaries and the caps.

Each ring carries its own cap, and boss progress raises it (OPEN 6 below tunes
the numbers):

| progress | Shallows (6–15) | Deepdark (16–30) | Abyss (31+) |
|---|---|---|---|
| start | 30 | sealed | sealed |
| +1 Shallows Beta | 35 | sealed | sealed |
| … all 5 Shallows Beta (era gate) | 55 | 60 | sealed |
| +1 Deepdark Beta | 55 | 68 | sealed |
| … all 5 Deepdark Beta (era gate) | 55 | 100 | 105 |
| +1 Abyss Beta | 55 | 100 | 117 |
| … all 5 Abyss Beta | 55 | 100 | 165 |

Caps only rise. Nothing in this table ever makes an already-open ring easier.

### Heat — the size of your footprint

Heat is **derived from your improvements**, not from your monsters. Buildings are
your *presence*; monsters are your *defence*. Every standing improvement adds its
own weight (`improvement_heat`: roads, walls and traps 1, production and support
2, watchtowers and turrets 3, beacons and refineries 4, counting overlays too),
and nothing else feeds it.

Monster levels should come **out** of the formula. Today
`colony_heat = improvement_heat/3 + total_monster_levels/6`, which means a maxed
roster pins the meter at `HEAT_MAX` forever no matter what you actually built —
and a colony with no defences is exactly as hot as a fortress of the same size.
Heat should measure what you *put on the map*, so building is the lever and
defending is the answer.

Heat does two things, and both are wanted:

- **The underground answers.** Raid size, raid cadence and raid monster level all
  rise with heat. Building without walls, turrets or monsters that can hold a
  line gets you steamrolled — that is the limiter.
- **Breeding gets possible.** Heat lifts the spawn-level roll *inside the ring
  you are standing in*, never past the ring's cap. Since breeding reads birth
  points, the top of a band is exactly what you hunt, and heat is what turns the
  mid-game from a slow grind of mediocre wilds into a run of real candidates.

So heat is a resource you want and a bill you pay, at the same time.

#### Heat saturates per ring

Heat is global, but its **spawn** effect is capped per ring, and the caps differ:

| ring | heat that saturates it | most levels it adds |
|---|---|---|
| Shallows (6–15) | 16 | +5 |
| Deepdark (16–30) | 32 | +10 |
| Abyss (31+) | 48 | +16 |

Past 16 heat, extra heat does nothing for Shallows wilds. To spend it you have to
go deeper — which is where the bosses, the materials and the danger are. So the
reward side of heat pushes you outward and the raid side never stops, which means
a hot colony always wants more walls than it has.

The spawn roll with heat folded in:

```
low  = 25% of cap
low += min(heat, saturation(ring)) / saturation(ring) × band_bonus(ring)
level = low + (cap − low) × r²          // r uniform
```

Because the top of the roll is still `cap`, a hot ring is "mostly decent,
occasionally great" rather than "everything is capped". Heat lifts the floor of
what you meet; the `r²` still decides whether you get lucky.

#### The rings are sealed in both directions

Until the era gate opens, wilds cannot cross a ring boundary **either way**: the
deep ones cannot come in to find you, and you cannot walk out. The boundary is a
wall you cannot cross or work across.

Opening a gate opens both directions at once, and that is the point of the whole
thing: once the Deepdark gate is open, Deepdark monsters can come inward. The
walls and turrets you built when they were pointless start earning their keep,
and the rings you cleared stop being free real estate. This also means the
deepest open ring sets the level of everything that can reach you, so the gates
are a difficulty step as well as an unlock.

### OPEN 5 — How strongly is a wild's spread biased?
- **(a)** None — fully random.
- **(b)** ~60% of its points land in one or two favoured stats.
- **(c)** Stricter (75%+), so wilds are more lopsided and easier to judge.
- This is the knob that decides whether "a level-60 with 38 Power" is a
  one-in-fifty find or something you see every few captures.
- **Default: (a).** **Blocks: stage 2.**

### OPEN 6 — The depth rings and the spawn-cap table
- **(a)** Rings of 6–15 / 16–30 / 31+, sealed **both ways** until the gate
  opens, as sketched.
- **(b)** Narrower Shallows (6–12) and a longer tail, so the first ring is a
  tutorial and the Deepdark starts sooner.
- **(c)** No seal — rings only decide which bosses live where and which cap
  applies. Walking deep early is then suicide rather than impossible, and the era
  gate only decides which boss rooms are *worth* doing.
- (a) makes progress legible and stops accidental suicide runs; (c) trusts the
  player and removes a wall to cross, but it also means deep monsters wander
  inward from turn one and there is no step change at the gate. The cap numbers
  work either way.
- **Default: (a)** (rings 6–15 / 16–30 / 31+, sealed). **Blocks: stage 2.**

### OPEN 15 — Do monster levels still add heat?
- **(a)** No — heat is improvements only, so building is the lever and monsters
  are purely the answer. A big roster costs food, not attention.
- **(b)** A small, **capped** share, e.g. `min(monster_levels/6, 12)`, so a huge
  roster still draws some attention without pegging the meter.
- As written today, monster levels alone reach the clamp and swamp the building
  contribution entirely.
- **Default: (a).** **Blocks: stage 2.**

### OPEN 16 — What stops raids escalating forever?
Heat keeps rising with the colony (more buildings, and the uncapped upgrades let
you build a lot). Raids cannot keep growing past the point where they out-level
everything the game can produce.
- **(a)** Raid level is capped by the deepest **open** ring's cap (so raids are
  always "the world you have unlocked" plus an alpha), and the escalation after
  that comes from **size and composition** — more raiders, more specialists,
  more alphas — rather than from level.
- **(b)** Raid level is uncapped and expressed in points, so a very hot colony
  eventually faces monsters no monster can beat — a soft doomsday clock.
- **(c)** Raid level saturates like spawns do, and heat past that point only
  shortens the interval and grows the band.
- (a) keeps the gates as the real escalation, which is where the bosses are.
- **Default: (a).** **Blocks: stage 2.**

## 5. Bosses: per-era rosters, three tiers, hunted by room

Bosses **stop roaming**. A Boss Room is an entry point that opens its own screen
— same shape as the Arena's — with the boss, the preview and the tier choice.

- **Three eras**: Early, Mid, End. **Each has its own roster of up to 5 bosses.**
- **Era = a ring** (§4). A Boss Room rolls **a random boss from the roster of
  the ring it sits in**, decided when the room is generated. So you hunt for the
  *room* holding the boss you want, not just a room.
- **Tiers**: at the room you pick **Beta / Alpha / Ascendant**. Proposal:
  **Beta is open**; **Alpha unlocks on that boss's Beta kill**; **Ascendant on its
  Alpha**. A per-boss ladder, so you can push one boss deep before moving on.
- **Era gate**: the next era's ring (and its higher spawn cap) opens when **all
  of the current era's bosses are beaten at Beta**. So progressing means hunting
  every room in a ring, not farming the one you like.
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
Hand-authored content. The shape is the table above (gimmick → the specific
answer).
- **Default: I'll draft all fifteen for you to edit**, the way the species sets
  were drafted — names, gimmicks, teams and which species each one is.
  **Blocks: stage 4.**

### OPEN 10 — Era names
**A:** Shallows / Deepdark / Abyss  ·  **B:** Warrens / Chasm / Maw  ·
**C:** Roothold / Underworks / Underthrone.
- **Default: A.** Doesn't block anything — cosmetic, change whenever.

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

### OPEN 14 — The loot list (materials, trophies, blueprints)
Names and numbers for the non-equippable drops above.
- **Default: I'll draft them for you to edit.** **Blocks: stage 5.**

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

The top of the monster progression is a birth around 195 (top spawn ring plus
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
point in the game.

The two uncapped *economy* nodes (Green Thumb, Rich Seams, +25%/level) are a
different question: they're self-limiting through `cost_growth` and they feed
gold/food rather than damage, so they can stay uncapped — but check that the
economy they produce still has a sink once levelling stops being one.

### Two casualties worth naming

- **The XP producers lose their job.** Training Yard (+8 XP/turn), Barracks
  (+1/kill) and the Academy upgrade exist to accelerate levelling. At birth+100
  they have nothing to accelerate. Either they feed something else (breeding
  speed, materials) or levelling needs to be slow enough that they still matter.
- **Heat stops being a progress tax.** Once heat is improvements-only (§4),
  it no longer pegs at the clamp just because your roster is big — it tracks what
  you built, so a small careful colony stays quiet and a sprawl does not. The
  cap-busting escalation moves to the gates: opening a ring lets deeper monsters
  reach you, which is a step change no amount of heat produces.

### OPEN 12 — How far to rework improvements and upgrades?
- **(a)** Minimum: an upgrade line for Watchtower Block, fix Iron Idol, and cap
  or re-base the three uncapped turret nodes.
- **(b)** Full pass over all 33 improvements and the tree, answering "what is
  this worth at the cap?"
- **Default: (a) during the systems work, (b) as its own batch after.**
  **Blocks: stage 6 (for (a)).**

## 8. Arena

Today the tower levels challengers from the party's *entry average level* through
the XP curve. With birth/level points and breeding, level stops describing
strength — two level-100 teams can be 3.4× apart. Two problems:

1. **What should the tower scale on?** Options: the party's total points (same
   as level), the sum of its *stat multipliers* (so a min-maxed team faces a
   stronger tower), or a fixed ramp with the party's own power as the variable.
   See OPEN 11 below.
2. **The deep floors.** Monsters cap at birth+100, and bred births reach ~200, so
   the tower's 1000 floors can't be level-driven forever. Past roughly floor 200
   difficulty should come from team size, items, boons and attrition — which is
   already the design.

Also from `IDEAS.md`: **the arena should offer a choice of 3 relics** rather than
handing you one. That drops straight into the event floors.

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
- **Deck size**: does a deck stay ~10 cards, or grow as a monster levels? A
  fixed deck makes each new card a *replacement* decision, which suits the
  "build" fantasy; a growing deck dilutes it. See OPEN 13 below.

This is the biggest content job in the plan and it touches every species, so it
should probably be its own pass after the systems are in.

### OPEN 13 — Does the deck grow with level?
- **(a)** Fixed ~10 cards; every new card is a replacement decision.
- **(b)** Grows as the monster levels.
- (a) keeps each learnset choice sharp and makes deck thinning meaningful;
  (b) dilutes both but lets a high-level monster express more.
- **Default: (a).** **Blocks: stage 7.**

## 11. What this touches

- `creature.odin`: points replace genes; `level_scale` → per-stat point scaling;
  `creature_stats_for_level` rewritten; `genes_*` deleted.
- `colony_storage.odin`: birth path — per-stat 50/50 on **birth** points,
  mutations, counters, female cooldowns.
- `colony_wilds.odin`: `spawn_level_for` — drop player-tracking; add rings, caps,
  spread bias, era gates; boss rooms roll a boss instead of spawning one.
- Heat: `colony_heat` becomes improvements-only; `spawn_level_for` takes the
  per-ring heat bonus; `raid_*` is capped by the deepest open ring; wild AI and
  `step_hunt` respect sealed ring boundaries; the HUD shows heat *and* which ring
  it is saturating.
- Every "level" escalation has to become a **points** escalation, because level is
  now the sum of points rather than a multiplier: the alpha's double-level, the
  boss `BOSS_LEVEL_BONUS`, and the tier stats. Doubling points is the exact
  equivalent of doubling level today, so the numbers carry over.
- The Den's description promises that stored monsters "stop counting toward
  heat". They already don't (denned monsters are counted anyway today — the text
  was ahead of the code), and with heat improvements-only the claim just becomes
  true. Reword it.
- `colony.odin`: XP cap; birth/level point split; boss-progress state; Nursery
  cooldown state.
- Bosses: `BOSS_SPECIES`, `boss_cronies`, `bosses_slain` and the roaming spawn are
  replaced by an era/roster table, a boss screen, per-boss tier progress, and a
  tier-aware quest board.
- UI: stat allocation; stat display everywhere (birth + level = live); boss screen
  and preview; materials in the bag; era progress.
- `save.odin`: version bump; genes out; points, mutations, cooldowns, boss tiers
  and era gates in.

## 12. Open questions — index

Every question now sits in the section it belongs to, so you can answer it where
you're reading. Nothing here is repeated; this is just the map.

**Answering:** reply in chat (`"1a, 2b, rest default"`), or edit the question in
place — change **OPEN n** to **DECIDED — n: (your answer)**. Each has a default
you can leave alone; anything unanswered takes the default and gets noted, so
nothing stalls.

| # | question | lives in | blocks |
|---|---|---|---|
| 1 | does Energy take points? | §1 | stage 1 |
| 2 | how the level-up screen asks | §2 | stage 1 |
| 3 | mutation counter inheritance | §3 | stage 3 |
| 4 | hybrids, or same species only | §3 | stage 3 |
| 5 | wild spread bias strength | §4 | stage 2 |
| 6 | the depth rings and spawn-cap table | §4 | stage 2 |
| 15 | do monster levels still add heat | §4 | stage 2 |
| 16 | what stops raids escalating forever | §4 | stage 2 |
| 7 | how tiers unlock | §5 | stage 4 |
| 8 | what opens the next era | §5 | stage 4 |
| 9 | the 15-boss roster | §5 | stage 4 |
| 10 | era names | §5 | nothing |
| 11 | what the Arena scales on | §8 | stage 8 |
| 12 | how far to rework improvements | §7 | stage 6 |
| 13 | deck size | §10 | stage 7 |
| 14 | the loot list | §6 | stage 5 |

**To start the first batch I only need 1 and 2**; 5, 6, 15 and 16 would let
spawns and heat follow straight on.

## 13. Suggested build order

1. **Stat points + birth/level split + genes out** (creature, UI, saves). The
   foundation; the game should feel the same, just reshaped.
2. **Spawns and heat**: depth rings (sealed both ways), caps, spread bias, heat
   saturation per ring, raids capped by the deepest open ring. Capture becomes
   interesting on its own and the colony layer gets its risk/reward lever.
3. **Breeding**: birth-point 50/50, mutations, cooldowns. Now a line can be built.
4. **Boss screen + eras + tiers + preview**, reusing the Arena screen's shape.
5. **Loot and materials**, plus the sinks and the relic rule from §9.
6. **The scaling pass** (§7): flat bonuses to percentages, XP producers
   re-purposed, economy sinks checked at the cap. This is what keeps the colony
   layer meaningful once monsters stop growing.
7. **Learnsets/move pools** across the new curve — the content pass.
8. **Arena rescale**, last, because it depends on all of the above.
