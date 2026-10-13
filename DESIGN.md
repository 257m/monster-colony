# Monster Colony — Colony Hexcrawl Design

Pivot: the hex map becomes a **colony / management layer**. The deck-based
creature battle from the current build stays and is what resolves combat.

## Currencies

| Currency | Source | Sink |
|---|---|---|
| **Gold** | mob drops (scale by level) | Trading Posts; improvements |
| **Food** | Grove/Farm tiles; some mob drops | monster upkeep; breeding |
| **Crystals** | bosses only | travel between floors; fed to monsters for XP |

- **Food upkeep:** every monster consumes food per turn based on its **species
  and level**. Too little → **starvation**. Surplus → stockpile (up to a cap) or
  spend on **breeding**. A monster with a **full food bar heals over time**.
- **Win condition:** reach **floor 10** and kill the final boss.

## Monsters on tiles

- A tile can hold **up to 6 monsters**.
- Wild monsters **roam** and attack improvements / your monsters.
- Attacking a tile defended by your monster(s) triggers a **battle**: the
  attackers are **all wilds on the attacking tile**, the defenders are **all
  your monsters on the defended tile** (not your whole roster). Moving one of
  your monsters **into a tile with wilds** also starts a battle. Choose
  **auto-fight** (your side AI-controlled) or **manual**.
- A tile with one of your monsters is **guarded** → no mob spawns there.
- You **send monsters each turn**; moving costs **energy** based on the
  monster's **Speed** and the destination tile. **Energy is one pool shared
  between the map and battle** — moving spends the same energy you use to play
  cards, and it regenerates per turn in both. Wilds on your tile can be attacked
  by **clicking your own tile** (and they ambush you at end of turn).
- **Capturing** a wild in battle uses a **capture card** (bought at a Trading
  Post), not a free action. Success chance scales with how wounded the target
  is.
- Each species has **separate base stats** for food: **`base_satiety`** (bar
  capacity) and **`base_upkeep`** (food consumed per turn), both scaled by
  level. Feeding refills 50% of the bar, starvation drains 30%; a full bar heals
  over time.
- Species have an **`elements` array** (1–2 types, primary first). Incoming
  damage is multiplied against **every** type the defender has — **weakness 2×,
  resistance 0.5×** — and a move whose element matches one of the attacker's
  types gets a **1.5× STAB** bonus (e.g. Flora vs Aqua/Ember = 2× × 0.5× = 1×).

## Elements

Nine types: **Neutral, Ember, Aqua, Flora, Ice, Ground, Electric, Air, Poison**.

- Weakness = **2×**, resistance = **0.5×**; dual types multiply together.
- **STAB**: a move whose element matches one of the attacker's types deals
  **1.5×**.
- Super-effective (attacker → 2× vs): Ember→Flora/Ice · Aqua→Ember/Ground ·
  Flora→Aqua/Ground · Ice→Flora/Ground/Air · Ground→Ember/Electric/Poison ·
  Electric→Aqua/Air · Air→Flora/Ground · Poison→Flora/Aqua.
- **Air types ignore Walls** (flying over them).

## Damage formula

Attacks are **multiplicative**: base card damage × Power × Strength bonus, then
type / STAB / Vulnerability, then Defense.

```
dmg = card_damage
    × power                  -- Power stat (~1.0 at level 1, grows)
    × (1 + 0.1 × strength)   -- each point of Strength = +10% damage
    × type multipliers       -- 2× / 0.5× against each of the defender's types
    × 1.5 (STAB)             -- if the move matches one of the attacker's types
    × 1.5 (Vulnerable)       -- if the target has any Vulnerable
    × 10 / (10 + defense)    -- defense scales hit down (10 = half)
```

Species **base Power was rebalanced to 0.75–1.6** (it is a multiplier now) so a
level-1 hit lands close to the card's printed damage; **Defense** stays a stat
but now reduces damage proportionally, so it stays relevant at every level.

### Rarity

Every species has a **`Rarity`** (`Common / Uncommon / Rare / Epic /
Legendary`), set in the species table. It scales three things, so rarer monsters
are more valuable *and* harder to get:

| | Common | Uncommon | Rare | Epic | Legendary |
|---|---|---|---|---|---|
| **Capture odds** (×) | 1.0 | 0.85 | 0.65 | 0.45 | 0.20 |
| **Shop rate** (weight) | 100 | 55 | 26 | 10 | 3 |
| **Shop price** (base g) | 25 | 45 | 80 | 140 | 240 |
| **Kill loot** (×) | 1.0 | 1.35 | 1.8 | 2.5 | 4.0 |

Capture chance also falls with the target's **level** (`1 / (1 +
0.08·(lvl−1))`). Kill gold is `(5 + 3·level) × loot` (raised from the old
`3·level`). The Trading Post's **stock is rerolled each turn**
(`colony_roll_shop`) — a rarity-weighted pick of two species, each priced by
`recruit_price`.

### Status cards

Self-buffs and enemy debuffs share the same stat model, so a card can push a
stat either way:

- **Strength** — each point is **+10%** damage dealt (can go negative). Raised
  by **Hone** (+5 str) and **Warcry** (+4 str, +1 def); lowered by **Weaken**
  (−2 str) and **Disarm** (3 dmg, −2 str).
- **Defense** — a temporary modifier on the defender. Raised by **Iron Skin /
  Bark Skin / Warcry**; shredded by **Sunder** (5 dmg, −2 def) and **Corrode**
  (−3 def).
- **Block** — a per-turn pool that absorbs damage, reset each round.
- **Vulnerable** — each stack adds **+50%** damage taken (**×2.0** at 2 stacks,
  etc.), ticking down one per turn (Screech, Cinder…).

Weaken / Disarm / Sunder / Corrode are available to every species as **reward
cards** (in `COMMON_MOVES`) and also sit in the starter decks of **Gloomling**
(Weaken), **Wispling** (Disarm), **Bogfang** (Weaken), **Stonepaw** (Sunder) and
**Venomtail** (Corrode), so wild monsters use them too.

### Turn order

Combat uses a **per-monster initiative queue**. Each turn, every living monster
on the field — **all of your party and every wild** — is sorted by **Speed**
(highest first; exact ties are a coin flip). The queue is then cycled: each
monster plays **one card** when its slot comes up, and the queue wraps around
until nobody can act. Only then does a new **turn** begin — fresh hands, energy
and Block. So hands/energy refresh once per *turn*, while each pass through the
queue is just an exchange. Extra monsters each get their own slot, so numbers
and Speed both matter.

### Species abilities

Every species has a pool of **three passive abilities** (`ABILITY_POOLS` in
`src/abilities.odin`); when a creature spawns it **rolls one at random**, so two
Emberlings can play differently. Abilities fire at battle start, each turn, or
on dealing damage:

| Ability | Effect |
|---|---|
| **Berserk** | +2 Strength at battle start |
| **Guardian** | +8 Block at battle start |
| **Thick Hide** | +2 Defense at battle start |
| **Swift** | +2 Speed for initiative |
| **Lucky** | draws 1 extra card each turn |
| **Vampiric** | heals 2 whenever it deals card damage |
| **Regenerator** | heals 4 at the end of each turn |
| **Intimidate** | enemies start the fight with −2 Strength |

Battle-start abilities are applied in `battle_start` (after the per-battle
reset); the rest hook into `creature_begin_round` (Lucky), `creature_end_round`
(Regenerator; Block is cleared here so **Guardian** keeps its Block through turn
one), and `apply_damage` (Vampiric). The player panel and enemy rows show each
fighter's ability, and the encyclopedia (`M`) lists every species' pool.

### Items

Every monster has **one item slot** (`Creature.item`). Items are found as
**battle loot** (Boss Rooms always drop one, normal fights ~22%) into the shared
colony bag (`Colony.items`), and equipped from the **deck viewer** (`V`, "Equip
item" / "Unequip"). Twelve items (`ITEM_DATA` in `src/items.odin`) split into:

- **Battle-start buffs** — Ember Charm (+2 Str), Iron Band (+2 Def), Swift Boots
  (+2 Speed), War Banner (+6 Block); applied by `item_battle_start`.
- **Per-turn / on-hit** — Lucky Coin (+1 draw), Vampire Fang (heal 3 on a landed
  card).
- **Stat bonuses** (recomputed in `creature_recompute_stats`) — Focus Sash (+1
  energy regen), Deep Pocket (+3 energy bank), Life Gem (+12% max HP), Power
  Core (+0.2 Power).
- **Map / capture** — Gold Finder (+2 gold/turn, in `colony_end_turn`), Snare
  Kit (+15% capture, in `capture_chance`).

`creature_recompute_stats` rebuilds stats from `(species, level)` plus the
equipped item, so items don't stack or get lost on level-up.

### Crystal progression

**Crystals** buy permanent, colony-wide upgrades from a **tree**
(`src/upgrades.odin`, panel on **`U`**). Roots are always available; each
**child unlocks once its parent reaches a required level**. Costs differ per
node and rise with every level (`cost + cost_step·level`).

**Crystals are won by fighting** — the **Arena** (~5) and **Boss Rooms** (~6) —
with the **Spoils** node adding +1 each. The **Crystal Refinery** is only a slow
backstop: it must be built on a **Crystal Cove** and **staffed** (a monster on
the tile), and yields one crystal per **6 turns** for 20 gold (Refining shaves
that down) — fights, not refining, drive progression.

```
Economy                    Industry / military            Support
Green Thumb                Masonry                        Bounty
 └ Bumper Crop (GT 2)       ├ Fortify (Mas 1)               └ Spoils (Bounty 2)
Rich Seams                  │  └ Spikecraft (Fort 1)       Vigilance
 └ Deep Core (RS 2)         └ Foundations (Mas 2)          Warding
Trade                      Armory                         Academy
Refining                    ├ Focused Barrels (Arm 1)      └ Veterans (Acad 2)
Logistics                   ├ Reinforced Mounts (Arm 1)   Scouts
 └ Forage (Log 2)           └ Long Barrels (Arm 2)         Drills
Hydraulics
 └ Reservoir (Hyd 1)
```

| Node | Needs | Effect per level |
|---|---|---|
| **Green Thumb** | — | Farm/Well/Lumber: +2 food |
| **Bumper Crop** | Green Thumb 2 | Farms: +3 more food |
| **Rich Seams** | — | Mines/Quarries: +2 gold |
| **Deep Core** | Rich Seams 2 | Mines/Quarries: +3 more gold |
| **Trade** | — | Marketplace Mine bonus +10% |
| **Refining** | — | Refinery −1 turn per crystal |
| **Logistics** | — | Monster movement −8% energy |
| **Forage** | Logistics 2 | Kills drop +1 food |
| **Hydraulics** | — | Fountain output +1 energy |
| **Reservoir** | Hydraulics 1 | Turret charge cap +2 |
| **Masonry** | — | Build & repair −5% |
| **Fortify** | Masonry 1 | Wall/Gate +15 HP |
| **Spikecraft** | Fortify 1 | Spike Trap +4 damage |
| **Foundations** | Masonry 2 | Granary/Treasury/Silo +25 storage |
| **Armory** | — | Turrets cost −8% gold |
| **Focused Barrels** | Armory 1 | Turret +4 damage |
| **Reinforced Mounts** | Armory 1 | Turret +12 HP |
| **Long Barrels** | Armory 2 | Turret +1 range |
| **Bounty** | — | Kill loot +12% gold |
| **Spoils** | Bounty 2 | Arena/Boss wins +1 crystal |
| **Vigilance** | — | Watchtower/Beacon +1 reveal & deter |
| **Warding** | — | Scarecrow deter & spook +1 tile |
| **Academy** | — | Monsters +15% XP from kills |
| **Veterans** | Academy 2 | Barracks train +1 XP |
| **Scouts** | — | Capture cards +6% success |
| **Drills** | — | Defenders start fights +4 Block |

Effects are read through `upgrade_*` helpers in the economy (per-turn yields,
`improvement_cost_scaled` / `improvement_repair_cost`, `improvement_hp_cap`,
`storage_cap`, `monster_step_cost`, `colony_fountains` / `colony_turrets`,
`colony_barracks`, spawn deter & scarecrow panic, kill loot/food/XP, capture
odds, and the per-battle Drills block).

## Terrain

| Terrain | Rarity | Behaviour | Traversal |
|---|---|---|---|
| **Cave** | common | weak mobs if unguarded; **Mine** → gold | normal |
| **Water** | common | rare weak mobs | needs **Bridge** (or Aqua) |
| **Dungeon** | uncommon | tough mobs, more loot/xp | normal |
| **Grove** | uncommon | small food; **Farm** → food, no spawns | normal |
| **Trading Post** | rare | heals, revives, cards, **monsters** | normal |
| **Boss Room** | rare | very strong, **uncatchable**, **crystals** | normal |
| **Arena** | rare | pay gold (`T`) to fight 6; win → **crystals** | normal |
| **Crystal Cove** | rare | the **only** tile a **Refinery** fits | normal |
| **Mushroom Grove** | uncommon | food-rich; **Farm**/**Well** valid | normal |
| **Ruins** | uncommon | tough mobs; **Wall**/**Watchtower** valid | normal |
| **Tundra** | uncommon | ice/air mobs | **Ice** only |
| **Jungle** | uncommon | **only Flora types** may enter | **Flora** |
| **Lava** | rare | **only Ember types** may enter | **Ember** |
| **Desert** | uncommon | ground/electric mobs | normal |
| **Quicksand** | rare | **only Ground types** may enter | **Ground** |

Spawn tables differ per terrain, with some mobs **unique to a tile type**. Enemy
**level scales with distance from the entrance**, so the starting area is
gentler and the frontier is dangerous.

## Improvements (built with gold)

| Improvement | On | Effect |
|---|---|---|
| **Farm** | Grove | **staffed**: feeds within 4, surplus to granary |
| **Mine** | Cave | **staffed**: gold to treasury within 4 |
| **Bridge** | Water | lets non-water monsters cross |
| **Granary** | Cave, Grove | stores food; feeds within 4; farms spill to it |
| **Treasury** | Cave | stores gold (counts as spendable) |
| **Watchtower** | Cave, Grove, Mushroom, Ruins | reveal 6, deter 4, +6 Block |
| **Wall** | Cave, Grove, Mushroom, Ruins | blocks wilds; they **batter** it |
| **Well** | Cave, Grove, Mushroom | needs Water nearby; feeds within 4 (+2) |
| **Gate** | Cave, Grove, Mushroom, Ruins | wilds can't cross; frail (30 HP) |
| **Spike Trap** | Cave, Ruins, Grove | wilds here take **8 dmg/turn** |
| **Scarecrow** | Grove, Mushroom, Jungle | no spawns (r2); **spooks** (r3) |
| **Road** | most land | **half energy**; **stackable** (`+stack`) |
| **Silo** | Cave, Grove | second **food store**: receives + feeds within 4 |
| **Crystal Refinery** | **Crystal Cove** | staffed; **1 crystal / 6 turns** |
| **Fountain** | Cave, Grove, Mushroom, Ruins, Desert, Tundra | energy (4) |
| **Turret** | Cave, Grove, Ruins, Desert, Tundra | **needs Fountain** (4) |
| **Drawbridge** | Water | **raise** to block wilds; click to toggle |
| **Quarry** | Ruins, Desert, Tundra | staffed gold (5) to treasury |
| **Lumber Mill** | Grove, Mushroom, Jungle | needs Water; staffed food (5) |
| **Marketplace** | Cave, Grove, Mushroom, Ruins, Desert | **+50%** Mine gold |
| **Kitchen** | Cave, Grove, Mushroom | spends food: defenders **+2 Str** |
| **Barracks** | Cave, Grove, Ruins, Desert | eats food; heals + trains nearby |
| **Beacon** | Cave, Ruins | reveal 8, deter 5; attackers start Vulnerable |
| **Den** | Cave, Grove, Ruins, Mushroom, Desert | stasis: 32/Den, no upkeep |
| **Vault** | Cave, Ruins, Desert, Tundra | **+12 item slots** |
| **Nursery** | Cave, Grove, Mushroom, Jungle | breeds a Lvl 5+ pair; 4 babies |

Improvements have **per-type HP** (`improvement_max_hp`): a Gate is 30, a Spike
Trap 25, a Scarecrow 20, a Turret 35, a Road/Drawbridge 40, a Fountain/Crystal
Refinery 45, a Beacon 55; most others 50. The build panel lists options in a
**two-column grid**, with the hovered one's effect shown along the bottom and a
**`+stack`** tag on stackable ones (`ROAD`, `SCARECROW`, `SPIKE_TRAP` — these
occupy a tile's **overlay slot** and can share a tile with a building; a
Spike-Trap overlay still zaps wilds). Overlays **carry their own health**
(`Tile.overlay_hp`) — wilds wreck the building first, then the overlay, and the
build panel repairs whichever is damaged. In **build mode the chosen tile is
marked** with a bold pulsing outline + `BUILD HERE`. **Coverage radii are shown
on the map** —
when you hover a build option (preview), select a tile in build mode, or hover a
built tile to inspect it — as a tinted hex area with a bright boundary ring
(e.g. a Watchtower shows its reveal-6 and deter-4 zones).

Building an improvement again gets progressively **more expensive** (cost = base
+ base·count/3), so the early colony is cheap to expand — except **Walls**,
which scale at half that rate (`base·count/6`) so you can wall off an area
affordably. The scaling counts only improvements **currently standing** —
destroyed ones don't raise the price, so rebuilding after a raid is no worse
than the first time. Damaged improvements can be **repaired** from the build
panel for half their base cost (prorated by the missing HP), and you can
**replace** a built improvement by building over it (the old one, and anything
it stored, is lost).

**Logistics rules**
- **Farms and Mines only produce while one of your monsters is stationed on the
  tile.**
- **Food has no global pool:** it lives in farms/granaries/silos. A monster is
  fed only if a Farm, Granary or Silo with food is **within 4 tiles**; otherwise
  it starves.
- **Food distribution spreads out:** a Farm/Well's output goes to the nearest
  food store (Granary/Silo) in range and **spills over to the next store** when
  one fills, so several stores share the load instead of one hogging it.
- **Gold is global/accessible.** Treasury contents count toward your spendable
  gold and are **lost if the treasury is destroyed** (Phase 3). Likewise a
  destroyed granary loses its food.
- Any production with **no valid receiver in range is wasted** that turn.

## Raids, heat & alphas (Phase D)

- **Heat** is the colony's raid pressure: it rises with your **footprint**
  (`improvement_total/3 + total monster levels/6`) and is pushed back down by
  **defences** (Watchtower +2, Beacon +3, Wall/Gate +1, Turret +2), clamped to
  `HEAT_MAX` (40). `colony_heat` recomputes it each turn and the HUD shows it.
- **Raids**: once past `RAID_GRACE` (turn 35) and at `heat >= RAID_MIN_HEAT`
  (4), a timer (`colony_raids`) counts down and then gathers a band of
  **raiders** in a ring a few tiles off your colony (spread across tiles so
  they don't crowd-fight). Size scales with heat (`2 + heat/4`, max 8), the
  cadence tightens (`RAID_BASE_INTERVAL - heat`, floor 9), and **raiders get
  tougher** — `raid_level_bonus` adds `heat / RAID_LEVEL_PER_HEAT` levels (so
  heat 4 → +1, heat 40 → +10). Raiders **march on your nearest monster**.
  The timer ticks from turn 0 (so the grace doesn't double-delay the first
  raid). The player is kept informed: the HUD reads `Raids from turn 35` before
  the grace, `Raid in N` once one is pending, or `Raid calm (low heat)` when the
  colony is too cold — and a notification fires when the grace ends.
- **Alphas**: a hot colony (`heat >= 8`) sends one **alpha** with each raid —
  `ALPHA_LEVEL_BONUS` (4) levels higher — which **hunts your improvements**
  instead, battering any fortification in its way.
- Raiders and alphas are committed: they don't wander off, spook from
  Scarecrows, or get culled by the wild cap. Both are marked on the map (warm
  ring) and tagged `ALPHA`/`raider` in the attacker picker.

## Breeding & genetics

- Every monster has a **genetic bonus per stat, 0–5** (`Creature.genes`), one
  gene for each of **HP / Power / Defense / Speed / Energy**, with higher values
  increasingly rare (0 common … 5 very rare). Each point is **+5%** on the
  species base, applied before items.
- Wilds, shop recruits and starters **roll** their genes on the rarity curve.
- **Breeding happens in a Nursery** (`C` panel): move two **nearby** monsters of
  the **same species**, both at least **Lvl 5**, in as the breeding pair. A pair
  eats **2 food/turn** from a nearby store; every **8 fed turns** it hatches a
  **level 1** baby (genes average the parents, rounded up, then roll **−1..+1**
  with a rare **+1 mutation**). A Nursery stores up to **4 babies** until you
  take them out.

## Storage

- **Den** — put monsters into **stasis**: no food upkeep, no heat, off the map.
  Up to **32** per Den; store/deploy from the `H` panel when a monster is beside
  the Den. A destroyed Den pushes its occupants back onto the map.
- **Vault** — raises the item bag cap (**+12** each). Fight-loot items only fit
  while there is room.

## Rewards

- Reward cards are **no longer given after every battle** — they become **rare
  drops**.
- Drop tables are **per species and per level**.
- Many **special moves** only come from reward cards.
- **Kills grant XP** (scaled by the defeated monster's level); surviving
  defenders level up as thresholds are crossed. A **post-fight results screen**
  shows gold, XP, any food delivered and any card gained.

## Floors

- **10 floors**, each harder, with higher-level monsters and **new mobs** to
  encounter.
- **Crystals** charge the move of monsters between floors, or can be fed for XP.

---

# Roadmap (phased)

1. **Colony foundation** — regular hex grid with terrain; currencies + HUD;
   persistent monster roster placed on tiles; turn loop; energy-based movement;
   food consumption / starvation / healing.
2. **Improvements & economy** — build/upgrade improvements; storage caps;
   Trading Post UI.
3. **Threats & combat hooks** — spawn tables, roaming wilds, guarding,
   improvement damage/destruction, auto vs manual fight, loot
   (gold/food/xp/cards).
4. **Content** — more monsters, moves, and card synergies.
5. More improvements and economy fleshed out - Difficulty curve on the game
   adjusted, more types of improvements and tiles
6. **Abilities, items & progression (Phase C)** — ✅ species ability
   pools (a spawn rolls one at random); ✅ one **item slot** per monster
   (12 items, battle loot, deck-viewer equip); ✅ **stackable overlays** beyond
   Road (Scarecrow and Spike Trap share a tile with a building); ✅ a
   **crystal-costed progression tree** (`U`: 26 nodes across economy, industry/
   military and support branches — improvement-specific Farm/Mine nodes, a
   Fortify→Spikecraft line, and an Armory turret branch with cost/damage/HP/
   range); ✅ **Arena** tiles (pay gold to fight a strong team of 6 for crystals,
   the main crystal source alongside Boss Rooms — refining is deliberately
   slow). *Multiple floors are dropped.*
7. **Raids, heat & alphas (Phase D)** — a **heat** level that rises as you build
   and level up and is cut by watchtowers/gates/turrets; **raids** that march on
   the colony, ramped so they're gentle early; **alphas** that hunt your
   improvements.
8. **Breeding & genetics** — ✅ 0–5 genetics, breeding rolls, babies at level 1.
9. **Storage & the Nursery** — ✅ a **Den** (monster stasis, 32/Den), a **Vault**
   (item storage, +12 slots) and a **Nursery** (the breeding building: a Lvl 5+
   pair, fed per turn, holds 4 babies).

## Lose conditions

- **All monsters dead** — whether from **starvation** or **killed in battle** —
  the run ends.

## Progress

- Phase 1 ✅ colony foundation (regular hex grid + terrain, currencies, roster on
  tiles, turn loop, movement energy, food upkeep). The grid is now **infinite**
  (tiles generated on demand).
- Phase 2 ✅ improvements & economy (build with gold, staffed production,
  range-gated food logistics, Trading Post: heal / energy / revive) + graveyard.
- Phase 3 ✅ threats & combat: per-terrain spawn tables, roaming wilds, guarding
  (no spawns on defended/Farm/Mine tiles), improvement damage & destruction — a
  wild on an **unguarded** improved tile damages it each turn (defended tiles
  instead trigger a battle; contents are lost on destruction, with a destruction
  notice; damaged improvements can be **repaired** from the build panel for half
  their base cost, prorated by missing HP), auto/manual deck battles, loot (gold
  + rare reward cards), and the all-monsters-dead lose condition.
- Phase 4 ✅ content: **12 new species** (Gloomling, Pyrelord, Krakling,
  Swampbeast, Wispling, Cindermaw, Rimescale, Mosshide, Emberbloom, Bogfang,
  Cinderwing, Frostmoss) with own decks/learnsets/pools, **17 new moves**
  including **synergies** (bonus vs Vulnerable, bonus while Blocked, bonus on
  combo), and a common move pool available as drops to every species. **Power /
  Defense / Speed are now floats**, scaled from fractional species base stats
  for finer variety.
- Phase 5 ✅ improvements & difficulty: **build costs scale up** the more of an
  improvement you have — counting only improvements **currently standing**, so
  destroyed ones don't raise the price (cheap early); enemies **scale with
  distance from the entrance** so the start is gentler; new improvements
  **Watchtower** (reveals within 6, deters spawns within 4, and gives defenders
  within 4 **+6 Block** at battle start), **Wall** (wilds won't roam across it),
  **Well** (must be adjacent to Water; feeds within 4, +2, no staffing); new
  tiles **Mushroom Grove** and **Ruins**; **prices lowered** across buildings
  and Trading Post (they scale up as you grow anyway). The map is **infinite**:
  tiles are generated on demand (deterministically from the seed) around your
  monsters and the entrance, and rendered as fog until explored. **Trading Posts
  (~1.5% of tiles) and Boss Rooms (~0.8%, at least 6 tiles from the entrance)
  are scattered randomly** rather than fixed, so they must be found by
  exploring. Terrain comes from **coherent value-noise biomes** (elevation ×
  moisture, a few octaves of fBm) so regions are contiguous — cave systems,
  groves, lakes, tundra fields, jungle belts — instead of a per-tile mosaic; a
  few of the type-locked terrains are seeded just outside the entrance so
  Ice/Flora/Ember/Ground content is reachable early. The **entrance is placed in
  the most open, neutral spot near the origin** and its chamber is cleared of
  impassable terrain, so no starter can spawn boxed in by Tundra/Lava/Water/etc.
  **Wild spawns ramp up over the first 30 turns** (from 10% to full rate) so the
  opening is calm. **Energy is a single pool** shared by colony movement and
  battle card play (spent in one, missing from the other; regenerated per turn).
  Each monster gains `energy_regen` per turn up to `energy_max` (base
  `base_energy_max` is **8**, or 10 for elites/bosses, versus regen 3–4), so the
  bank is ~2.7× the income and banking for expensive cards is worthwhile. The
  battle UI shows the bar, the per-turn regen, and a dim preview of next turn's
  energy. **Walls can be built on Grove / Mushroom Grove.** You can **attack a
  wild sharing your tile** by clicking your own tile. The battle UI shows an
  **XP bar**, and each enemy now shows an **energy bar** alongside its HP and
  modifier chips. Improvements are drawn as **animated icons** on the map (farms
  sway, mines sparkle, wells ripple, watchtowers pulse) and monsters have a
  subtle idle bob; tiles now carry **procedural detail** (rocks, grass,
  mushrooms, dunes, lava cracks, a boss skull…) instead of a flat colour, water
  shimmers, and a **damaged improvement shakes and flashes red** with a `-N`
  popup. Working producers pop `+N`/`-N` gold/food floats when a turn resolves.
  **Attacks open a "choose attackers" screen** — your monsters on the target
  tile and adjacent tiles, each toggleable — instead of only the monster that
  started the fight; **TAB cycles only through monsters you own**, and clicking
  a tile with several of your monsters cycles through them.
- Phase 5b ✅ more content: **5 new elements** (Ice, Ground, Electric, Air,
  Poison) with a 9-type chart (2×/0.5×) and STAB; **5 new terrain types** —
  Tundra, Desert, and type-locked **Jungle (Flora only)**, **Lava (Ember
  only)**, **Quicksand (Ground only)**; Air types ignore Walls; **6 new
  species** covering the new types (Frostfang, Stonepaw, Sparkit, Galebeast,
  Venomtail, Blizzard); **10 new moves**; and an in-game **monster
  encyclopedia** (`M`) showing every species' types, base stats, starter deck
  and learnset; the colony HUD shows global **Food +N/turn** and **Gold
  +N/turn** production, and hovering an improved tile shows its remaining HP.
  The battle UI lists each fighter's active boosts (Strength / Defense / Block /
  Vulnerable) with the damage multiplier each one contributes; **enemy debuff
  cards** (Weaken, Disarm, Sunder, Corrode) lower a target's Strength or Defense
  (several species carry them, so wilds use them too), Strength/Defense can now
  go negative, **combat uses a per-monster Speed initiative queue** (every
  living monster acts in Speed order, cycling each turn; ties are a coin flip),
  and hovering a hand card shows its **estimated damage** against the current
  target (with a super-effective / resisted / multi-hit note).
- Phase 6 (started) ✅ **species abilities**: every species has a 3-ability pool
  and each spawn rolls one (`src/abilities.odin`). 8 abilities (Berserk,
  Guardian, Thick Hide, Swift, Lucky, Vampiric, Regenerator, Intimidate) hook
  into battle start / per-turn / on-damage. Shown on the starter cards, the
  battle panels, the roster, and in the encyclopedia. **Effect feedback**:
  playing a card now spawns a coloured expanding-ring burst on the affected
  creature (`creature_burst` → drawn in `draw_creature_avatar`, aged in
  `battle_update`) alongside the floating popup — heals (cards, Regenerator,
  Vampiric), block, buffs and debuffs all pulse; Strength buffs were raised for
  punch (**Hone +5**, **Warcry +4**). Balance passes: attack damage lowered
  (~20% on the card data), base `energy_max` raised to 8/10, Mushroom Groves
  made rarer (noise band halved), and wilds now **batter** a Wall/Gate that
  blocks their step instead of walking around it.
- Phase 6b ✅ **rarity & the Trading Post**: every species has a `Rarity` that
  scales **capture odds** (rarer and higher-level monsters are harder to catch),
  **kill loot gold** (base raised to `5 + 3·level`, then rarity-scaled), and the
  **shop**. You start with **3 capture cards**. The Trading Post now sells a
  **rotating stock of monsters** (two rarity-weighted offers, rerolled each turn
  in `colony_roll_shop`; price from `recruit_price`, bought with
  `colony_buy_recruit`), keeps the heal/energy/revive/capture-card services, and
  shows each offer's rarity colour. Rarity also appears in the encyclopedia.
- Phase 6c ✅ **items**: every monster has a **one-item slot** (`src/items.odin`,
  12 items). Items drop as battle loot into a colony bag and are equipped from
  the deck viewer ("Equip item" / "Unequip"); effects cover battle-start buffs,
  per-turn draw, on-hit lifesteal, stat bonuses (max HP / Power / energy — via
  `creature_recompute_stats`), gold per turn, and capture odds. Results screen
  reports drops.
- Phase 6d ✅ **improvements dex**: press **`I`** for a browsable reference of
  all 26 improvements (`draw_improvements`). Left = scrolling list; right =
  animated icon, category, base cost, HP, stackable flag, **built-on** terrain
  chips, the short effect line, and a long-form description
  (`improvement_detail`). Text wraps via `draw_text_wrapped`.
- Phase 6e ✅ **fight clarity**: the attacker picker now shows **both sides** —
  your monsters on the left and the **enemies on the tile** on the right (name,
  level, element, HP, ability, rarity) — and in battle your **whole party is
  drawn on the field** as rich info cards (`draw_party_field`: avatar, HP
  numbers, energy bar, buff chips, ability/item; acting ringed, ended dimmed,
  dead greyed) instead of a side list.
- Phase 6f ✅ **status fix**: **Vulnerable** used to be a binary ×1.5 no matter
  how much you stacked (a hidden cap). It now scales — each stack adds **+50%**
  damage taken — and its chip shows the real `VULN+N x%.2f`. (Strength was
  already uncapped: 0→50 Strength measured 16→96 damage.)
- Phase 6g ✅ **item bag viewer**: press **`G`** for a browsable list of the
  items in `Colony.items` — colour-coded dots, the selected item's
  icon/description, a full **effect breakdown**, and **Equip to selected
  monster** (swaps with the map-selected monster, old item returns to the bag).
- Phase 7 ✅ **web build**: the game compiles to **WebAssembly** and runs in a
  browser. `src/web.odin` exports
  `main_start`/`main_update`/`main_end`/`web_window_size_changed` (the browser
  drives the loop), `src/web_allocator.odin` routes allocation through
  emscripten's `malloc` (the default Odin wasm allocator detaches emscripten's
  views), and `web/index_template.html` + `web/build_web.sh` assemble the page
  with `emcc` (raylib's OpenGL→WebGL). `make web` builds `build/web/`, `make
  serve` hosts it. Desktop entry (`main`) is compiled out on wasm.
- Phase 7b ✅ **rest of Phase C**: **stackable overlays** generalised beyond
  Road (`SCARECROW` and `SPIKE_TRAP` join `ROAD`; a tile carries a building plus
  one overlay, and a non-Road overlay is drawn smaller/offset so both read) — a
  Spike Trap overlay still zaps wilds because the trap pass now uses
  `tile_has`. **Arena** terrain (~0.6% of tiles, ≥4 from the entrance): stand on
  it and press **`T`** to pay 40 gold for a forced fight against a fresh team of
  6 above your level; a loss resets the Arena.
- Phase 7c ✅ **progression tree + crystal economy rework**: the upgrades became
  a real **tree** (`src/upgrades.odin`) — roots plus children that unlock at a
  parent level, with per-node and per-level costs, including
  **improvement-specific** branches (Farm/Mine, Fortify→Spikecraft, and an
  Armory turret branch: cost/damage/HP/range). Crystals now come from
  **fights**: **Arena** wins pay **5**, **Boss Rooms** pay **6**, and **Spoils**
  adds +1 each; the **Crystal Refinery** was slowed to **1 crystal / 6 turns**
  (20 gold) so refining is a backstop, not a source. New hooks:
  `improvement_hp_cap` (Fortify/Reinforced Mounts), turret damage/range, spike
  damage, and the Farm-only Bumper Crop / Deep Core yields.
- Phase 7d ✅ **more progression nodes**: the tree grew to **26 nodes** across
  three branches. New roots: **Hydraulics** (Fountain energy), **Logistics**
  (cheaper movement), **Scouts** (capture odds, via a new
  `Battle.capture_bonus`), **Academy** (kill XP), **Warding** (Scarecrows),
  **Trade** (Marketplaces), **Drills** (defenders start with Block) and
  **Refining** (faster refineries). New children: **Reservoir**, **Forage**,
  **Foundations** (storage, via `storage_cap`) and **Veterans**. The `U` panel
  is now three columns.
- Phase 7e ✅ **Crystal Coves**: a new rare **`CRYSTAL_COVE`** terrain (~1.2%,
  ≥3 from the entrance) with glowing-shard tile art and its own spawn table.
  **Crystal Refineries can now only be built on a Cove** (was Cave/Ruins/
  Dungeon) and must be **staffed** — a monster standing on the tile — to refine,
  so the slow crystal trickle also costs you a body.
- Phase 8 (Phase D) ✅ **raids, heat & alphas**: a **heat** meter
  (`colony_heat` = footprint minus defences) shown in the HUD; **raids** that
  gather raiders in a ring around your colony and march on your nearest monster
  (ramped behind `RAID_GRACE`, sized, cadenced **and levelled** by heat via
  `raid_level_bonus`); and **alphas** that lead hot raids and hunt your
  improvements. Raiders/alphas are exempt from wandering off, Scarecrow spooking
  and the wild cap, and are marked on the map and in the attacker picker.
- Phase 9 ✅ **breeding & genetics**: every creature carries a **0–5 gene per
  stat** (`Gene` on `Creature.genes`), rolled on the rarity curve for wilds,
  recruits and starters, and applied as **+5%/point** on the species base in
  `creature_recompute_stats`. Genes show in the deck viewer.
- Phase 10 ✅ **storage & the Nursery**: a **Den** holds **32** monsters in
  stasis (`Colony.storage`, no upkeep/heat, off the map) — store/deploy from the
  `H` panel; a **Vault** adds **+12** item slots (`colony_item_cap`); and a
  **Nursery** is the breeding building (`C` panel): move a **Lvl 5+** pair
  in, it eats **2 food/turn** and hatches a level 1 baby every **8 fed turns**
  (`colony_nurseries`/`colony_nursery_birth`, genes averaged via `genes_breed`),
  storing up to **4**. Destroying a Den/Nursery evacuates its occupants.

