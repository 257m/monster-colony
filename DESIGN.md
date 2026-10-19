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
  cards, and it regenerates per turn in both. Energy grows **logarithmically**
  with level while everything else grows linearly, so it stays a real constraint
  at every level. Wilds on your tile can be attacked
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
  by **Hone** (+5 str) and **Warcry** (+2 str, draw 1); lowered by **Depower**
  (−2 str, −2 dex).
- **Defense** — a temporary modifier on the defender. Raised by **Iron Skin**
  (+3 def); shredded by **Sunder** (4 dmg, −3 def) and **Expose** (2 vuln,
  −2 def).
- **Dexterity** — a duration; each point adds **+1 Block** to every Block card.
  Raised by **Footwork** (+2); lowered by **Disarm** (−3 dex) and **Depower**.
- **Block** — a per-turn pool that absorbs damage, reset each round.
- **Vulnerable** — a **duration in turns** at a fixed **×1.5** damage taken (it
  does not stack multiplicatively), ticking down one per turn (**Mark**, 3).
- **Poison / Burn** — damage-over-time that decays each round. **Poison** phases
  through Block (2%/stack of max HP); **Burn** is absorbed by Block (3%/stack)
  *and* weakens the burned creature's damage (5%/stack, cap 50%).
- **Stun (daze)** — loses card plays: it fumbles N cards at turn start, costs no
  energy, and the turn continues (**Concuss**).
- **Thorns** — reflects a **% of the attacker's max HP** on a diminishing curve,
  spending a stack per hit.
- **Haze** clears **stat boosts only**; **cleanse** (Antidote, Purify) clears
  Poison / Burn / Stun.

These cards reach you as **reward drops** (drawn from each species' own
`move_pool`) and also sit in learnsets and starter decks, so wild monsters use
them too.

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
Emberlings can play differently. A boss always rolls its **signature** (the
first entry in its pool). There are **21** abilities:

| Ability | Effect |
|---|---|
| **Berserk** | +3 Strength at battle start |
| **Guardian** | +8 Block at battle start |
| **Thick Hide** | +3 Defense at battle start |
| **Swift** | +4 Speed for initiative |
| **Lucky** | draws 1 extra card each turn |
| **Vampiric** | heals 25% of the damage it deals |
| **Regenerator** | heals 6% of max HP at the end of each turn |
| **Intimidate** | enemies start the fight with −3 Strength |
| **Momentum** | +1 Strength at the start of each turn |
| **Ironclad** | +1 Dexterity at the start of each turn |
| **Aftershock** | its first Attack each turn hits twice |
| **Envenom** | its Attacks apply 1 Poison |
| **Predator** | ×1.25 damage against foes below half HP |
| **Vengeance** | +1 Strength whenever it takes a hit |
| **Resilient** | once a battle, survives a lethal blow at 25% HP |
| **Abyssal** *(boss)* | takes ×0.70 damage while above half HP |
| **Inferno** *(boss)* | burns every foe for 2 at the end of each turn |
| **Colossus** *(boss)* | its Block is not cleared between rounds |
| **Dominion** *(boss)* | strips 1 Strength from every foe each turn |

Battle-start abilities are applied in `battle_start` (after the per-battle
reset). The rest hook in through `ability_begin_round` (Lucky, Momentum,
Ironclad), `ability_defense_mult` / `ability_attack_mult` (Predator, Abyssal),
`ability_on_hit_taken` (Vengeance), `ability_on_hit_poison` (Envenom),
`ability_first_attack_doubles` (Aftershock), `ability_try_survive` (Resilient),
`ability_keeps_block` (Colossus) and the end-of-turn pass (Regenerator,
Inferno, Dominion). The player panel and enemy rows show each fighter's ability,
and the encyclopedia (`M`) lists every species' pool.

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
| **Mender** | Cave/Grove/Ruins/Desert/Mushroom | needs Fountain; +1 hp/turn |

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

- **Heat** is the colony's raid pressure: it rises with your **footprint** —
  every standing improvement adds its own weight (`improvement_heat`:
  roads/walls/gates/bridges/traps **1**, ordinary production/support buildings
  **2**, watchtowers/turrets **3**, beacons and crystal refineries **4**) plus
  monster levels (`/6`), all over 3. **Nothing lowers it** — defences don't cool
  the colony, they just make it harder to raid. Clamped to `HEAT_MAX` (60);
  `colony_heat` recomputes it each turn and the HUD shows it.
- **Raids**: once past `RAID_GRACE` (turn 35) and at `heat >= RAID_MIN_HEAT`
  (4), a timer (`colony_raids`) counts down and then gathers a band of
  **raiders** in a ring a few tiles off your colony (spread across tiles so they
  don't crowd-fight). Raids **ignore spawn deterrence** — watchtowers, beacons,
  scarecrows and the Farm/Mine no-spawn rule don't keep them out — because they
  exist to hit your colony. **Size grows with heat** (`2 + heat/4`, up to
  `RAID_MAX_SIZE` 14), the cadence tightens (`RAID_BASE_INTERVAL - heat`, floor
  9), and **raiders get tougher** — `raid_level_bonus` adds
  `heat / RAID_LEVEL_PER_HEAT` levels (heat 4 → +1, heat 60 → +15). Raiders
  **march on whichever is closer, a monster or an improvement**. The timer ticks
  from turn 0 (so the grace doesn't double-delay the first raid). The player is
  kept informed: the HUD reads `Raids from turn 35` before the grace, `Raid in
  N` once one is pending, or `Raid calm (low heat)` when the colony is too cold
  — and a notification fires when the grace ends.
- **Alphas**: a hot colony (`heat >= 8`) sends one **alpha** with each raid —
  **double the level** of the rank-and-file raiders — which **hunts your
  monsters**, battering any fortification in its way.
- Raiders and alphas are committed: they don't wander off, spook from
  Scarecrows, or get culled by the wild cap. On the map a **raider** gets a warm
  ring while an **alpha** is unmistakable — a **gold halo, a thick ring, a crown
  and an `ALPHA` label** (`draw_alpha_marker`); both are tagged `[ALPHA]`/
  `[raider]` in the attacker picker (the alpha row bordered gold).

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

## Saving

- **3 save slots** (`O` panel, or `F5`/`F9` for slot 1), written as
  `save_1.mcs`…`save_3.mcs` beside the executable. A small hand-rolled binary
  format (`src/save.odin`) round-trips the **whole colony**: tiles, roster,
  Dens/Nursery storage, graveyard, items, shop stock, the upgrade tree, the RNG
  state and the turn clock. **Battle state is not saved** — save on the map.
- The same panel has a **New Run** button (or the **`N`** key) that returns to
  the **starter picker** (`reset_to_starter`) so you can pick again and roll a
  fresh seed (seed hunting). A second click/press confirms while a run is in
  progress.
- Each slot's header carries **turn / gold / monsters / crystals / time** so the
  panel can list saves without a full parse.
- Not available in the **browser build** (no persistent filesystem).

## Audio

- **No audio files ship** — every sound effect and the looping music track are
  **synthesised at startup** into 16-bit PCM (`src/audio.odin`) and handed to
  raylib. A tiny oscillator (sine/square/saw/triangle/noise) with an
  attack + decay envelope builds one-shot cues; the music is a slow A-minor
  loop (bass, pad, pentatonic lead, kick/tick) encoded to an in-memory WAV and
  streamed with `LoadMusicStreamFromMemory` so it loops seamlessly.
- `audio` is a package-level singleton: any file fires a cue with
  `audio_play(.BUILD)`. Cues are hooked on build/repair, card play and battle
  hits — plus **BUFF / BLOCK / DOT** cues for the battle effects — as well as
  victory/defeat, level-up, crystals, raids, end-turn, save/load and starter
  choice. In battle `battle_sfx` keeps headless skirmishes silent.
- If the device can't open, everything no-ops. **`F2`** toggles mute.

## Rewards & deck-building choices

- Reward cards are **no longer given after every battle** — they become **rare
  drops**.
- Drop tables are **per species and per level**.
- Reward drops draw **only** from a species' own `move_pool` (rarity-weighted),
  so what you are offered always fits the monster. There is no shared pool of
  generic cards: a move lives in the `move_pool` of every species that should
  be able to learn it, and a card can appear both in a learnset and as a drop.
- **You choose your cards — or decline.** Every level that unlocks a move raises
  a **`LEVEL UP!` prompt** (one card if the level unlocks one, up to 3 if
  several), and a **reward drop** offers **3 cards**. In both cases you can
  **Skip** to take nothing. The modal picker (`update_move_choice` /
  `draw_move_choice`) queues on `Colony.choices`; click a card or press
  **1–3**, or Skip.
- **Kills grant XP** (scaled by the defeated monster's level); surviving
  defenders level up as thresholds are crossed. A **post-fight results screen**
  shows gold, XP, any food delivered, a pending reward, and whether a monster
  levelled up.

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
7. **Raids, heat & alphas (Phase D)** — a **heat** level that rises with every
   improvement and level (nothing lowers it); **raids** that ignore spawn
   deterrence, grow with heat and march on your monsters and improvements;
   **alphas** (double level) that hunt your monsters.
8. **Breeding & genetics** — ✅ 0–5 genetics, breeding rolls, babies at level 1.
9. **Storage & the Nursery** — ✅ a **Den** (monster stasis, 32/Den), a **Vault**
   (item storage, +12 slots) and a **Nursery** (the breeding building: a Lvl 5+
   pair, fed per turn, holds 4 babies).
10. **Save files** — ✅ 3 slots (map state round-trips; `O` / `F5` / `F9`).
11. **Title screen** — ✅ a main menu (New Game / Load Game / Quit) before the
    starter picker; loading a save is offered from here.

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
  all 27 improvements (`draw_improvements`). Left = scrolling list; right =
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
  (`colony_heat`) shown in the HUD; **raids** that gather raiders in a ring
  around your colony and march on your nearest monster (ramped behind
  `RAID_GRACE`, sized, cadenced **and levelled** by heat via
  `raid_level_bonus`); and **alphas** that lead hot raids and hunt your
  improvements. Raiders/alphas are exempt from wandering off, Scarecrow
  spooking and the wild cap, and are marked on the map and in the attacker
  picker.
- Phase 14 ✅ **raid & heat fixes**: heat now weights each improvement
  (`improvement_heat`: 1 roads/walls/traps, 2 ordinary, 3 watchtower/turret,
  4 beacon/refinery) and is **never lowered** (defences no longer cool the
  colony); raids **ignore spawn deterrence** (watchtower/beacon/scarecrow +
  Farm/Mine), **alphas hunt monsters** and **raiders hit the nearer of a monster
  or an improvement**; and **overlay** improvements (Road / Scarecrow / Spike
  Trap) are now **attacked** — `colony_resolve_wild_actions` wrecks a tile with
  a building *or* an overlay.
- Phase 15 ✅ **Mender**: an energy-powered repair building. A **Fountain**
  charges it exactly like a Turret (`colony_fountains` now feeds Turrets *and*
  Menders); while charged, `colony_menders` spends `MENDER_COST` to repair
  **every** damaged improvement within `MENDER_REPAIR_RANGE` by `MENDER_HEAL`
  HP/turn (buildings *and* overlays, with a green `+1hp` float). Useless without
  a Fountain — a passive alternative to paying gold to repair.
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
- Phase 11 ✅ **save files**: a hand-rolled binary format (`src/save.odin`) that
  round-trips the whole colony — tiles, roster, Dens/Nursery storage, graveyard,
  items, shop, upgrades, RNG and turn clock — into **3 slots** (`save_N.mcs`).
  `O` opens the panel (`F5`/`F9` quick save/load slot 1); each header carries
  turn/gold/monsters/crystals/age for the slot list. I/O is platform-gated
  (`save_io_desktop.odin` / `save_io_js.odin`); disabled in the browser.
- Phase 12 ✅ **title screen**: the game opens on a **main menu** (`draw_title`,
  `Game_Mode.TITLE`) with **New Game**, **Load Game** and **Quit** (desktop
  only). Load Game opens the save/load panel (which also has **New Run**, going
  back to the starter picker for seed hunting); game over returns here with
  **Esc**. The starter picker also accepts number keys **1**–**3**. Lifecycle
  helpers `goto_title` / `reset_to_starter` share `close_all_panels`.
- Phase 13 ✅ **world-gen tuning**: `biome_at`'s elevation bands widened so
  **Water** rose from ~7% to ~23% of the map (Water < 0.40, Cave < 0.48), giving
  proper lakes and coastlines while keeping Cave ~21%; the moisture band for
  **Mushroom Grove** was narrowed (10.4% → ~5%).
- Phase 16 ✅ **audio**: procedurally **synthesised** sound effects (16 cues) and
  a looping A-minor music track, generated into 16-bit PCM at startup
  (`src/audio.odin`) — no asset files. Cues are hooked across build/repair,
  battle (card play, hits, victory/defeat), level-up, crystals, raids, end-turn,
  save/load and the starter pick. `F2` mutes; no-ops if the device can't open.
- Phase 17 ✅ **clearer alphas**: a raid alpha on the map gets a gold halo, a
  thick pulsing ring, a **crown** and an `ALPHA` label (`draw_alpha_marker`),
  while raiders get a warm ring; the attacker picker tags `[ALPHA]`/`[raider]`
  and borders the alpha row gold.
- Phase 18 ✅ **raid scaling**: the **heat cap** rose to `HEAT_MAX` **60** and
  raids now grow to `RAID_MAX_SIZE` **14** (`2 + heat/4`), so hotter colonies
  face bigger bands; the **alpha** is now **double the level** of the
  rank-and-file raiders (replacing the flat `ALPHA_LEVEL_BONUS`).
- Phase 19 ✅ **deck-building choices**: every level that unlocks a move now
  raises a **`LEVEL UP!` picker** (one card, or up to 3), and battle **reward
  drops offer 3 cards** — and in both cases you can **Skip** to decline. Choices
  queue on `Colony.choices` and show a modal `draw_move_choice` overlay (cards
  reuse `draw_card`; click or `1`–`3`, or Skip). `creature_level_up` now returns
  its candidates instead of learning them.
- Phase 20 ✅ **energy economy + premium cards**: energy no longer scales with
  `level_scale` (linear); it follows a **logarithmic** `energy_scale`
  (`1 + 0.12·ln(level)`) with **no hard cap**, so a high-level monster regens
  ~4–4.5/turn against a 5-card hand instead of out-regenerating it (was 6/16
  from ~L8). Added **6 premium reward-only cards** (`PREMIUM_MOVES`:
  Meteor, Tsunami, Maelstrom, Cataclysm, Aegis, Phoenix) at **3.0–3.5 energy** —
  the energy sinks you save up for.
- Phase 21 ✅ **status effects, card rarity, deck thinning, escalation**: five
  battle statuses — **Poison/Burn** (damage-over-time that decays each round),
  **Stun** (skips actions), **Regen** (heal-over-time) and **Thorns**
  (retaliation) — on `Creature`, applied by **13 new reward-only cards**
  (`STATUS_MOVES`) and shown as chips/tooltips in battle. Cards now carry a
  **`rarity`** (`COMMON`/`UNCOMMON`/`RARE`) and reward picks are rarity-weighted
  (commons ×8, uncommons ×4, rares ×1). The deck viewer (`V`) supports **deck
  thinning**: right-click a card to forget it for gold (`forget_card_cost`).
  Difficulty now **escalates**: `spawn_level_for` adds `colony_escalation`
  (`turn/20`) and never falls below **2/3 of your best monster's level**, so
  over-levelling can't trivialise the wilds. **Threat variety**: raids now throw
  in **siege** beasts (target buildings, double improvement damage) and **fast
  stalkers** (two steps, slip past walls), with distinct map markers.
- Phase 22 ✅ **goal, milestones, graveyard, tooltips**: a **10-entry quest
  board** (`Q`) tracks milestones (build a Farm/Beacon/Den, survive 60 turns,
  grow to 8/16 monsters, win 6 fights, slay an alpha, weather 3 raids, earn 40
  crystals), each paying a **small** crystal bounty (1–5; ~27 total); finishing
  all completes the run. The **Hall of the Fallen** (`Y`) lists every fallen
  monster and lets you **revive** them or **salvage** the item they carried. A
  frame-last **hover tooltip** system (`tooltip_set`/`tooltip_draw`,
  word-wrapped) covers cards, status chips, roster entries, build options,
  upgrade cells and map tiles.
- Phase 23 ✅ **deeper tree + more turret upgrades**: the crystal tree grew from
  26 to **35 nodes**. Turret damage grows only through upgrades: `Focused
  Barrels` now runs to **5** levels at **+6 damage each** (base 10 → 40). New
  turret nodes: **Quick Loaders** (extra shot per turn) and **Shrapnel Rounds**
  (shots splash beside the target). New support nodes: **Long Wrenches** (Mender
  range), **Wide Channels** (Fountain range), **Hearty Rations** (Kitchen
  Strength), **Bright Beacon** (Beacon Vulnerable), **Deep Dens** (Den stasis),
  **Strongboxes** (Vault item slots) and **Warm Broods** (Nursery hatch speed).
  The upgrade panel (`U`) is now a **scrolling** 3-column grid to fit them.
- Phase 24 ✅ **QoL & polish**: a **minimap** (top-left, `Z`, click to jump) of
  every explored tile with POIs, wilds/raids and the viewport; **off-screen POI
  arrows**; **edge tooltips** on the HUD resources, trade buttons, cards, chips,
  roster, build options, upgrade cells and map tiles; a **settings panel**
  (`F10`) holding the **last-turn summary**, a **volume slider**, and
  **minimap / tooltips / FPS / autosave** toggles; a **controls overlay**
  (`F1`); **unit picker** — clicking a tile with several of your monsters asks
  which to control (instead of Tab-cycling); a **special autosave slot** written
  every `AUTOSAVE_EVERY` turns; **confirm dialogs** for destructive actions
  (forget card, overwrite building); **camera tweens**; **pointing-hand cursor**
  feedback; **thousands separators**; a **net-food / starvation warning** in the
  HUD; and a **battle initiative bar**.
- Phase 25 ✅ **relics, boss packs, demolition**: **10 stackable relics**
  (`Relic` / `Colony.relics`) — colony-wide passives (power, HP, speed, energy,
  gold, food, Block, turret damage, crystals, XP) dropped by bosses and meant to
  be farmed to keep pace with the escalating late game. **Four unique boss
  species** (`Boss_Leviathan` / `Boss_Infernal` / `Boss_Titan` /
  `Boss_Sovereign`) with synergy movesets spawn in **Boss Rooms** as a **pack of
  six** (boss + 5 themed cronies) that **moves as a unit** and can be
  re-challenged (relic farming). Improvements can be **demolished** for a
  **50% refund** of their base cost. **Function keys are gone** (they collide
  with the OS): help is `K`, settings `P`, mute `X`, quick-save `F`.
- Phase 26 ✅ **movement economy & attack flow**: movement costs more
  (`MOVE_STEP_FACTOR` **0.8**, up from 0.5) and varies by terrain
  (`terrain_move_cost`: 0.9 Grove/Mushroom … 1.8 Quicksand), so a monster covers
  far less ground per turn. **Attacking ends a monster's turn**
  (`Monster.acted`, set in `begin_battle`), so chained fights can't keep it
  moving on battle-refilled energy. Clicking a wild tile now opens the attacker
  picker **without moving**; the step (`attack_move_attackers`) happens only
  when you commit, so backing out no longer strands you on the tile. Acted
  monsters show `(done)` in the roster and red move hints.
- Phase 27 ✅ **fainted-monster & battle-HUD fixes**: fainted monsters no longer
  "revive" at the end of the turn — the feeding step skips 0-HP monsters
  (`colony_end_turn`) and leveling never heals a fainted one
  (`creature_level_up`), so a lost party really is lost. The enemy battle panel
  now shows its **element types as coloured chips** (`draw_enemies`) and its
  buff chips no longer overlap the energy readout (the enemy block sits higher,
  `ey` 212, effects row at `ey + 120`).
- Phase 28 ✅ **percentage-based mechanics**: the flat battle mechanics that went
  stale at high levels are now **fractions** — lifesteal (`Move.leech_pct`:
  Leech/Gnaw/Phoenix drain a % of damage dealt; Vampiric ability 25%; Vampire
  Fang 30%), heals (`Move.heal_pct`: Mend/Heal Spring/Bloom/Regrowth/Second
  Wind/Tidecall heal a % of **max HP**), **Poison/Burn** (`POISON_PCT` 2% /
  `BURN_PCT` 3% of max HP per stack), **Regen** (`REGEN_PCT` 3% of max HP),
  **Thorns** (`THORNS_REFLECT_PCT` 10% of the hit per stack), and the
  Regenerator ability (6% max HP). **Block stays flat** — a block card still
  gives block — as do raw damage (already scaled by Power) and
  Vulnerable/Strength (already %).
- Phase 29 ✅ **energy regen halved & demolish guard**:
  `creature_stats_for_level` now applies `ENERGY_REGEN_FACTOR` (0.5) to
  `energy_regen`, so regen is ~1.5 (L1) → ~2.3 (L100) instead of ~3 → ~4.7 — the
  shared movement/battle pool is a tighter resource. Fixed a bug where the build
  panel's **Demolish** hit-test ran on an empty tile (its rect overlapped the
  build-option grid), so clicking a build option could raise a spurious demolish
  prompt; it's now gated on the tile actually holding a building/overlay.
- Phase 30 ✅ **wilds never idle**: plain wilds always roam (the old 40% "stay
  put" was removed) and hunters/boss packs always step (the 15% hold was
  removed), so the map keeps moving every turn.
- Phase 31 ✅ **pile viewer**: in battle, `D` (or clicking the `Draw N` /
  `Discard N` readout, `draw_pile_readout`) opens `draw_piles` — a modal listing
  the active monster's **draw pile** and **discard pile** (name, cost, element).
  The stale "V deck" hint became "D piles".
- Phase 32 ✅ **card systems & powers**: the `Move` struct grew a whole
  vocabulary — **X-cost** cards (`x_cost`), **Retain**, **Ethereal**,
  discard-hand / exhaust-hand, energy sabotage and self-energy, block/strength/
  poison/burn **doublers**, `scale_per_exhausted`, **Dexterity** and **Speed**
  modifiers, `offense_stat` (Body Press: damage from Defense), `unplayable` +
  `hand_damage` (Wound), junk-card generation and `cleanse_status`. Cards carry
  a `Card_Kind` (ATTACK / SKILL / POWER). **Powers** (`src/powers.odin`) are
  per-battle permanent effects granted by POWER cards — Barricade, Juggernaut,
  Demon Form, Metronome, Sanguine, Scavenger, Rage, Combustion, Toxic, Bastion
  and Flow — shown as purple chips. Targeting collapsed into one `Move.targets`
  bit set (empty = enemy-only).
- Phase 33 ✅ **status & combat rework**: **Stun** became **daze** — it loses
  card plays (fumbles N cards at turn start; no energy cost, turn continues).
  **Vulnerable** is now a **duration in turns** at a fixed **×1.5**, not a
  stacking multiplier. **Thorns** reflects a **% of the attacker's max HP** on a
  diminishing curve (never reaching 100%), spending a stack per hit. **Burn**
  and **Poison** split: Poison phases through Block (2%/stack), while Burn is
  absorbed by Block (3%/stack) *and* weakens the burned creature's damage
  (5%/stack, cap 50%). **Haze** clears stat boosts only; the new **cleanse**
  clears Poison/Burn/Stun (Antidote, Purify). Lifesteal and thorns fire **per
  hit**, so multi-hit cards interact correctly. Skirmishes and predation run
  the **real battle engine headlessly** (`src/skirmish.odin`,
  `run_headless_battle`, budgeted at 8 battles a turn then a stat fallback),
  crowd fights split a tile into two sides and run one battle, and the world
  events are now **Tremor / Stampede / Distant Roar / Migration** (never
  rewriting terrain). A camera-based **UI scale factor** (`src/screen.odin`)
  renders a 1280×720 design space scaled to the window, so text stays crisp at
  any size.
- Phase 34 ✅ **content revamp — roster, builds & evolutions**: the roster was
  rebuilt from scratch around **3 starter lines + 5 bosses + 40 wild species**.
  Each starter line runs three stages and **stages 2 and 3 are dual-typed**
  (Emberling → Cinderscale → Magmalisk, Ember/Ground; Tidepup → Ripfin →
  Tidewyrm, Aqua/Ice; Sproutle → Thornbud → Blightbloom, Flora/Poison). Every
  species' learnset is a **build menu**: each level offers **three moves, one
  per build column**, so a level-up commits a direction (the fire line's Fury /
  Pyre / Ruin, and so on), and evolved stages add further tiers per column.
  **Evolutions** are data (`Species.evolves_to` / `evolve_level`) and the
  encyclopedia draws the **whole chain** with the levels between stages. **32
  wilds** spawn from per-terrain tables and **8 of them evolve** (Grubling →
  Rotshell, Vesperling → Nightwing, Thornkit → Thornmaw, Bubblet → Bubblord,
  Snowpup → Frostfang, Magmite → Magmaw, Sporeling → Sporelord, Sparkit →
  Voltail); a wild spawned at or past its evolve level may arrive **already
  evolved** (`wild_mature_species`), and boss packs field a themed retinue of
  real wilds. The ability roster grew to **21** (adding Momentum, Ironclad,
  Aftershock, Envenom, Predator, Vengeance and Resilient, plus the boss-only
  Abyssal, Inferno, Colossus and Dominion). Reward drops come **only** from a
  species' own `move_pool` — there is no shared generic card pool.
  **`SAVE_VERSION` is 5** — the rework reordered species and move ordinals, so
  older saves are rejected rather than loaded corrupt.
- Phase 35 ✅ **effect feedback everywhere**: every battle effect now announces
  itself with a popup + burst + cue, including the ones that used to fire
  silently. The per-turn triggers — **Momentum**, **Ironclad**, **Demon Form**,
  **Bastion**, **Flow** and **Metronome** — pop their gain each round;
  **Vengeance** pops when it gains Strength from a hit; and **Resilient** now
  visibly saves you (popup, gold burst, cue and a log) instead of surviving
  quietly, since `apply_damage` had no battle handle to report through. The
  battle-start buffs (**Berserk**, **Guardian**, **Thick Hide**, **Swift**,
  **Intimidate** and item buffs) pop as the fight opens. Card flow got popups
  too: **draws** (Lucky, Warcry, Gambit, Scavenger), **junk cards** handed to a
  hand, **discard / exhaust hand**, and **Haze / cleanse** now report how much
  they wiped. Three new popup kinds (DRAW, JUNK, CLEAR) and three new cues
  (BUFF, BLOCK, DOT) back it, and `battle_sfx` keeps headless skirmishes quiet.
- Phase 36 ✅ **battle UI for big fights**: the HUD keeps a panel in each top
  corner — yours left, the **selected target right** — and the enemy row now
  lives in the band **between** them, so no enemy card can run under a panel or
  off the screen. The row shows as many foes as fit (`enemy_visible_count`) and
  scrolls the rest into view with the wheel, `[` / `]`, or a click, with a
  `first-last of N` hint and edge arrows; it auto-scrolls to keep the target on
  screen, and only on-screen foes are clickable. Enemy cards are compact —
  avatar, name, level, type chips, ability, HP and energy — with their boosts
  reduced to small colour-coded dots, since a full chip row ran hundreds of
  pixels wide. The target panel mirrors the player panel exactly (avatar, name,
  ability, level/type/stats, HP, energy, rarity, **active boosts**), and the
  panel's stat line is split across two rows because `Lvl / type / PWR / DEF /
  SPD` on one line overflowed the box. The initiative bar is capped to the gap
  between the two panels.
- Phase 37 ✅ **move dex, readable key hints & a tutorial**: **`L`** opens a
  **move dex** — every card in the game in a scrolling list (cost on the right),
  with a detail panel showing element / rarity / kind chips, the flavour line,
  and an **effect breakdown generated from the card's own data**
  (`move_lines`) rather than hand-written prose, plus a **LEARNED BY** line
  listing the species whose `move_pool` carries it. The map's key hints were two
  full-width lines that overflowed the screen; they are now **one centred line
  of the most useful keys**, with the full list left to `K`. And the opening
  turns now show a **tutorial tip** — one short contextual hint per turn for the
  first eight turns (`TUTORIAL_HINTS`, **build first**), in a box the player can
  click to open the **TIPS window**: all eight hints again in order, reachable
  any time from the `K` help panel (and carrying a **show-at-start** toggle).
- Phase 38 ✅ **temp-allocator leak fixed**: `fmt.ctprintf` (used ~260 times in
  the draw code) allocates from `context.temp_allocator`, and the frame loop
  never reset it, so the process climbed by ~12MB per 600k calls — a steady leak
  while playing. Both loops (desktop and web) now `free_all` the temp allocator
  at the end of every frame, and `set_status` **copies** its text into an owned
  buffer (`Game.status_buf`) rather than keeping the pointer, so the two
  `set_status(g, fmt.ctprintf(...))` callers can no longer dangle.
- Phase 39 ✅ **revamp batch 1 — dead content wired up**: three finished things
  had no delivery. **Dazzle** (1 Stun + 2 `Dazed` into the foe's hand) finally
  creates the `Dazed` junk card, which nothing could produce before.
  **Metronome** and **Scavenger** are now POWER cards (combo Strength /
  draw-on-exhaust), so every power has a granting card, and **Slime Spit**
  (Poison: 5 damage + 2 `Dazed`) spreads the daze as an attack. **Intimidate**
  finally sits in a species pool (Sentinel, Slagbeast). New cards append to the
  end of `Move_Id` so existing save ordinals don't shift.
- Phase 40 ✅ **revamp batch 2 — elemental top-ups**: Electric, Flora, Ice and
  Air were thin (2–3 cards each), so **twelve new cards** fill them out at
  roughly the existing rate (~5 damage / 8–10 Block per energy). **Electric**
  gets a real identity — chip damage (**Jolt**), stun (**Static Shock**), energy
  denial (**Short Circuit**), chain (**Chain Lightning**), a battery
  (**Capacitor**) and an X-cost finisher (**Overcharge**) — going from 2 cards
  to 8. **Flora** gains **Thorn Volley** and **Photosynthesis**, **Ice** gains
  **Frost Nova** and **Ice Wall**, **Air** gains **Updraft** and **Tailwind**,
  so every element now has 5 or more. **Every element also gets a premium
  attack** at the 6-damage-per-energy rate with a twist of its own —
  **Firestorm** (15 + 3 Burn), **Tidal Crash** (18), **Bramble Crush** (16 + 2
  Thorns), **Avalanche** (15 + 3 Vulnerable), **Fault Line** (16 + −3 Def),
  **Supercell** (15 + Stun), **Gale Force** (6×3), **Venom Fang** (12 + 4
  Poison) — plus **Riptide** (4×2, drain) rounding Aqua up to 6. The baseline
  card is 5 damage per energy; these are the 15–18 damage finishers.
- Phase 41 ✅ **AoE cards**: `Move.aoe` makes a card hit **every living foe at
  once** — damage and hostile statuses loop over all of them, while the
  caster-side effects (Block, buffs, powers) still land once. **Earthquake**
  (Ground, 3.0, RARE) is the first: 12 damage to every foe. Single-target
  resolution is unchanged, and the AI values an AoE well above its per-target
  number (`move_value` +28) so wilds will actually use one.
- Phase 42 ✅ **staggered hit feedback**: damage still resolves instantly, so
  the game logic never waits, but the *feedback* now goes through a queue
  (`Battle.hit_fx`) that plays out in `battle_update`. Events are grouped into
  **waves by hit index**, so a multi-hit card reads as several impacts — one
  popup, spark, flinch and cue per hit, 60ms apart — while a **spread (AoE)**
  card is a single wave, hitting every victim at the same instant. The old
  aggregated per-victim damage number is gone in favour of per-hit numbers, and
  `drain_hit_fx` runs in every phase (including headless skirmishes).
- Phase 43 ✅ **revamp batch 3 — held items**: the 12 items were flat stat
  sticks; they are now **held items**, each a rule that hooks a specific
  synergy. Offense: **Bloodstone** (+30% damage, 3% max-HP recoil per Attack),
  **Weakpoint Lens** (+25% on super-effective hits), **Ricochet Charm**
  (multi-hit Attacks land one extra hit). Synergy: **Siphon Gland** (+50% drain
  / lifesteal), **Venom Sac** (+1 Poison/Burn stack), **Spiked Carapace** (start
  with 2 Thorns). Sustain and defense: **Ration Pouch** (4%/turn), **Amber
  Fruit** (once, heal 25% below half HP), **Cleansing Bloom** (cleanse each
  turn), **Grit Charm** (survive one lethal blow at 1 HP) and **Grudge Idol**
  (+2 Strength when hit super-effectively). **Snare Kit** stays colony-facing.
  The enum keeps its 12 slots in order, so old saves still load.
- Phase 44 ✅ **revamp batch 4 — Relic Towers**: relics are no longer
  colony-wide. Each one must be slotted into a **Relic Tower** (a new
  improvement, 60g, 3 slots, 60 HP) and then projects over a **5-tile radius**
  around it, so relics became a base-building decision rather than a passive
  pile. The 10 relics were reworked around what "in range" means: **battle**
  relics (**War Banner** +2 Str, **Iron Idol** +10 Block, **Swift Totem** +4
  Speed, **Mana Shard** +1 energy regen, **Warden's Seal** +2 Thorns) buff your
  party for a fight inside the radius, **economy** relics (**Coin of Plenty**,
  **Harvest Charm**, **Siege Core**) boost the Mines, Farms and Turrets inside
  it, and **post-battle** relics (**Crystal Prism**, **Beast Fang**) pay out for
  wins there. Copies stack. The `J` panel gained **Place** / **Take** buttons
  (Place arms a click-on-the-tower mode with an on-map banner), the build panel
  and tile readout list a tower's contents, and `SAVE_VERSION` is **6** because
  tiles now carry their slots.
- Phase 45 ✅ **revamp batch 4b — one inventory**: relics became **bag entries**
  instead of a separate count array (`Colony.relic_bag` replaces
  `Colony.relics`), so items and relics live in one place and the `J` relic
  panel is gone (`J` is now an alias for the inventory). The bag panel was
  rewritten as a proper **inventory screen**: a **slot grid** (items first, then
  relics) with a per-slot procedural icon, a detail pane showing the name, kind,
  description and full effect breakdown, and action buttons — **Equip** /
  **Unequip** for items (onto the map-selected monster) and **Place** /
  **Take back** for relics. `SAVE_VERSION` is **7** for the new bag layout.
- Phase 46 ✅ **revamp batch 5 — the quest board**: the 10 easy milestones
  became a **20-entry ladder** running from "build your first Farm" out to
  **slaying each of the five bosses**, surviving **150 turns**, winning **50
  battles**, weathering **10 raids** and commanding **20 monsters**. Rewards
  scale with the target (96 crystals total, up from 27), and the board pays into
  `crystals_earned` too. Per-boss quests needed boss tracking, so the colony
  gained `bosses_slain[Species_Id]` (set on a `.BOSS` kill, saved —
  `SAVE_VERSION` is **8**), and the panel is now a **two-column** board. The
  Deep One was also missing from the boss spawn table, so it could never be
  fought — that is fixed (5 bosses, 5 spawns).
- Phase 47 ✅ **energy, and rewards scoped to the fight**: creatures were created
  with `energy = 0` against a bank of 10–17 and ~2 regen a turn, so a wild
  spawned that turn fought on fumes (and so did a fresh starter). Every creature
  now spawns **charged** (`energy = energy_max`). Separately, `resolve_won` paid
  the **Arena** bounty from the *tile* — any wandering wild standing on an Arena
  paid 5 crystals — and the **Boss** bounty likewise. Both are now scoped to the
  fight: the Arena reward needs a **paid challenge** (`Game.battle_arena`, since
  `finish_battle` clears it mid-resolve it is captured up front) and the Boss
  reward needs an actual **`.BOSS` kill**. The hovered-tile readout now explains
  Arena / Trading Post / Boss Room tiles, which is how you start an Arena fight:
  stand a monster there and press **T**.
- Phase 48 ✅ **wild fight-readiness**: a plain wild that wanders onto one of
  your monsters starts the fight, so wilds now **hold off unless they are
  charged** — below **40%** of their energy bank they will not step onto your
  monsters (or start a crowded-tile brawl), and above that the odds scale with
  energy, so a full wild almost always commits. Verified: 0–39% energy = never,
  50% = ~48%, 80% = ~79%, 100% = always. Raiders, alphas and sieges still hunt
  deliberately. (A procedural creature-sprite pass was tried here and reverted —
  the circles keep their letter until per-species art exists.)
- Phase 49 ✅ **revamp batch 6 — base building**: a proper perimeter is
  affordable now — **Wall 15→6**, **Gate 12→5**, **Drawbridge 16→8**, Spike Trap
  18→9, Scarecrow 8→5, Road 10→6 — and the repeat-build divisor for Walls and
  Gates went **6 → 16**, so the eleventh wall still costs 6. Three new
  improvements round out a base: **Ward Stone** (every Relic Tower within 4
  projects 2 tiles further, so a ring of stones turns one tower into a
  district-wide aura), **Training Yard** (a monster standing on it gains 8 XP a
  turn, for bringing a recruit up without feeding it to fights) and **Caltrops**
  (a nastier Spike Trap at 24% max HP/turn). Finally, the crystal tree gained
  **uncapped nodes**: `Upgrade_Info.cost_growth` compounds the price per level,
  and Focused Barrels, Reinforced Mounts, Reservoir, Green Thumb and Rich Seams
  are now unlimited (Focused Barrels: 8 → 116 → 1000 → 7896 crystals at levels
  0/5/12/20) so Turrets can keep pace with the escalating threats. The panel
  caps its pips at 8 and shows a `Lv N` readout for those nodes.
- Phase 50 ✅ **percentage lines, a Battery, and a reason to fight the Arena**:
  **Green Thumb** and **Rich Seams** are now **percentage** lines (**+25%** food
  / gold per level) instead of flat +2s, so they scale with the base yield as
  the colony grows — verified a staffed Farm goes 6 → 12 food at 4 levels. New
  improvement **Battery**: when every Turret and Mender in a Fountain's reach is
  already full, the surplus pours into a Battery within 4 tiles instead of being
  wasted, and Turrets within 4 draw from it whenever their own cells run dry.
  Verified: a full Turret banked 3 charge, and a dry Turret drew 2 back to fire.
  Energy transfers are now **visible**: charging a Turret / Mender / Battery
  floats a `+N en`, a Turret drawing from a Battery floats what it took, and
  Menders and Batteries carry a small **charge bar** under their icon (plus a
  Battery link ring) so you can see a tank filling or running dry.
  Finally, the **Arena** is now worth entering: it is the hardest fight in the
  game, so it pays **12 crystals** (double a boss) and **always drops an item**,
  making it the crystal farm while Boss Rooms stay the relic source. Bosses
  re-lair every **30** turns.
- Phase 51 ✅ **battle HUD, ring clarity & a fair Arena**: the initiative bar's
  `NEXT` label moved back under the chips (it was touching the turn counter),
  and the party field now gives the **acting** monster the big outer ring while
  the selected teammate only gets a thin inner border — the yellow halo used to
  be the most prominent thing on the field, so it read as "this one is moving".
  An
  **Arena** fight now also strips every colony-side battle effect: no relics, no
  Watchtower guard Block, no Drills, no Beacon mark, no Kitchen rations and
  no Scout capture edge. Only monsters, decks, abilities and items decide it.
  Verified: the same fight gives 22 Block outside the Arena and **0** inside.
- Phase 52 ✅ **damage estimates always show**: the hover readout on an attack
  card was gated on `Battle.sel_kind == .ENEMY`, and that flag is **sticky** —
  once you targeted one of your own monsters to play a support card, every
  attack card silently stopped showing its damage. The readout now follows
  `pick_card_target`, i.e. whoever the card would *actually* land on, so an
  enemy-only attack always shows its estimate while a self/ally card correctly
  shows none.

- Phase 53 ✅ **heat drives difficulty, and the Arena becomes a tower**: wild and
  boss level no longer uses turn escalation at all — `wild_threat_level` reads
  **heat** (your footprint: improvements and monster levels), so a quiet colony
  faces quiet wilds and a loud one draws monsters grown to match. Verified:
  heat 0 at turn 5 and at turn 300 both give level 1, while heat 60 gives 21 —
  camping no longer hardens the underground. The **Arena** is now a **ladder of
  curated teams**: each win takes you a floor higher, teams grow (2 → 6) and
  step through four species tiers (basics → mid forms → finals → the bosses),
  and the level is `max(base + floor, the average level of the party you brought
  +
  floor/2)` — so the tower is built to beat *you*, which is what finally gives
  breeding and late game deck-building something to aim at. The entry fee and
  purse both climb with the floor (floor 100: 440g in, 212 crystals out). Losing
  drops you to floor 1 but **keeps your best floor** as the high score, and four
  new milestones reward reaching floors 10 / 25 / 50 / **100**. `SAVE_VERSION`
  is **9**.

- Phase 54 ✅ **the Arena is a run**: one **flat** entry fee (40g) buys a chain
  of floors that always starts at **floor 1**. Each cleared floor **banks** its
  purse instead of paying it; the run ends when you **cash out** (banking the
  winnings) or when your party **wipes** (losing them, and dropping you to
  floor 1 — your best floor stays as the record). The payout is therefore a
  function of how deep you got. Arenas **drop gold** too (25 + 2·floor per
  cleared floor, on top of kill loot). And the tower gets **stingier as you
  climb**: a between-floor party heal comes every **1 / 2 / 5 / 10 / 20** floors
  (below 10, 30, 60, 120, then every 20), which is how difficulty scales without
  a brutal level curve. New capstone milestone: **reach Arena floor 1000**
  (+100 crystals), and the quest board is now three columns to hold it.
  `SAVE_VERSION` is **10**.
- Phase 55 ✅ **full restores, two cadences**: the tower's between-floor rest is
  now a **complete** heal (HP to max, and every ailment cleansed) rather than a
  percentage, and the **energy refill is a separate, later cadence** — not a
  change to in-battle regen. HP comes back every **1 / 2 / 5 / 10 / 20** floors
  (below 10, 30, 60, 120, then every 20); energy refills after *every* floor at
  first, and only thins below floors **20 / 50 / 100 / 200** (then every 20).
  The gap between the two is the tower's curve: level numbers stay sane while
  your team stops being topped up.

- Phase 56 ✅ **Arena sets and a weighted roster** (`src/sets.odin`): the tower
  no longer fields curated tier teams. Every species owns **three sets**, each a
  loadout of **ability + item + deck** (generated from that species' own move
  pool as a starting point, and meant to be hand-edited). The builder rolls a
  set per challenger, so one species can turn up as a **Striker**, a
  **Controller** or a **Bulwark**. Species are picked by a **soft band over
  roster rank**: the power the tower wants lerps from the weakest species to the
  strongest across `ARENA_RAMP_FLOORS` (250) floors, and a species' weight falls
  off with its distance *in rank* from that target — rank, not raw power,
  because two thirds of the roster is near-identical weak wilds that would
  otherwise swamp any power-based band. So floor 1 is weak wilds, the middle is
  the evolved lines, and the deep floors are the bosses. **Rarity plays no
  part** (it governs findability, not strength), a species already on the team
  is down-weighted rather than banned (`ARENA_REPEAT`), and challengers skip
  wild maturation since the builder already picks by strength.
- Phase 57 ✅ **the tower's level curve is logarithmic**: the challengers are
  levelled from the party's average level **at the moment the run started**
  (`arena_base_level`, so the tower doesn't drift up under you mid-run), scaled
  by `1 + 0.3·ln(floor)` — the same slow shape as `energy_scale`. A party of
  level 30 meets level 30 on floor 1, 71 on floor 100 and 92 on floor 1000. A
  flat "+1 per floor" put floor 1000 thousands of levels away; this keeps the
  whole tower reachable and lets the attrition carry the difficulty.

- Phase 58 ✅ **deep floors stay varied**: the tower no longer collapses to
  nothing but bosses. Two changes. First, the pick band **widens as you climb**
  (`arena_spread`, 4.5 ranks up to 11), so the strong regulars stay in the
  lineup. Second, a non-boss challenger is levelled by a **multiplier** that
  ramps in with the floor (`1 + floor/800`, so 1.0× on floor 1 and 2.25× at
  floor 1000) to stand beside the bosses' unique abilities and much larger base
  stats. Floor 1 is still an even fight; floor 1000 is roughly half bosses and
  half levelled regulars.

- Phase 59 ✅ **synergy sets**: `src/sets.odin` is regenerated so every set is
  built around a real **synergy** from that species' own move pool — a poison
  engine ending in Catalyst, a block wall that swings with Body Press, a thorn
  shell, a strength ramp, a multi-hit swarm, a vulnerable ambush, a tempo loop,
  an exhaust payoff (Finale), a stun lock, a sustain grind, a reckless low-HP
  gamble, a defence-shred sweep, a speed package. The held item and the ability
  are chosen to reinforce the plan. A species' three sets are its three best
  fits; if a pool cannot support three real synergies it gets honest generic
  ones (**Bruiser** / **Warden** / **Skirmisher**) instead of a synergy it
  cannot run. So a challenger is never just a wild with a bigger number.

- Phase 60 ✅ **the battle row fits a whole Arena team**: the enemy row is now a
  **full-width band below the two corner panels** instead of the gap between
  them, so **nine** challengers are on screen at once and a six-monster team
  never needs scrolling. The cards are slightly more compact (smaller avatars,
  tighter text) to fit, a pack smaller than the row is **centred** rather than
  bunched left, and the scroll arrows either side are now **clickable**
  (alongside the wheel and `[` / `]`).
- Phase 61 ✅ **the tower levels on *your* curve**: the challengers no longer use
  a bespoke log scale. A run **banks its own XP total** (`arena_run_xp`), seeded
  with `xp_total_for_level(party average)` when you enter and topped up by the
  **same XP the fight hands your team** on every cleared floor, and the level is
  read off it with `level_for_xp` — the exact inverse of `xp_to_next`. So the
  tower grows precisely as your monsters do, without ever reading their levels.
  The old log curve happened to match this closely enough to keep, but the real
  curve is better: it stays honest even when a floor's XP take is unusual.

- Phase 62 ✅ **the party field sits lower**: the enemy row's bars and boost dots
  were crowding the ring around the acting monster. The field is 10px shorter
  and 16px lower, the hovered-card tooltip tucks in closer to the hand, and the
  enemy row drops with it — 8px of clear air between the row and the ring now,
  and nothing overlaps the tooltip.

- Phase 63 ✅ **six strong wilds** (the elite tier, `Species_Role.ELITE` — the
  role that had never been used). `Ashfang` (Ember/Air, fast striker),
  `Stormwing` (Electric/Air, storm flier), `Bogmaw` (Poison/Aqua, poison
  engine), `Dreadhorn` (Ground/Ember, charger), `Rimewarden` (Ice/Ground,
  glacier tank) and `Gravemaw` (Neutral/Ground, the heaviest). They are regular
  monsters, not bosses, but built to stand beside one — their power scores
  (4.99, 5.32, 5.61, 6.09, 6.65, 7.50) fill the stretch between the evolved
  lines (4.28) and the bosses (6.2–10.2) that was previously empty, which is
  what makes the deep floors varied instead of a parade of five bosses. Each
  spawns rarely in one fitting terrain (lava, crystal cove, jungle, desert,
  tundra, dungeon) and each gets three synergy sets of its own. `SAVE_VERSION`
  is **12**.