# Monster Colony — Colony Hexcrawl Design

Pivot: the hex map becomes a **colony / management layer**. The deck-based
creature battle from the current build stays and is what resolves combat.

## Currencies

| Currency | Source | Sink |
|---|---|---|
| **Gold** | dropped by mobs (scaled by level) | Trading Posts; building improvements |
| **Food** | Grove/Farm tiles; some mobs drop it | consumed by monsters each turn; breeding |
| **Crystals** | bosses only | travel between floors; fed to monsters for XP |

- **Food upkeep:** every monster consumes food per turn based on its **species and level**. Too little → **starvation**. Surplus → stockpile (up to a cap) or spend on **breeding**. A monster with a **full food bar heals over time**.
- **Win condition:** reach **floor 10** and kill the final boss.

## Monsters on tiles

- A tile can hold **up to 6 monsters**.
- Wild monsters **roam** and attack improvements / your monsters.
- Attacking a tile defended by your monster(s) triggers a **battle**: the attackers are **all wilds on the attacking tile**, the defenders are **all your monsters on the defended tile** (not your whole roster). Moving one of your monsters **into a tile with wilds** also starts a battle. Choose **auto-fight** (your side AI-controlled) or **manual**.
- A tile with one of your monsters is **guarded** → no mob spawns there.
- You **send monsters each turn**; moving costs **energy** based on the monster's **Speed** and the destination tile. **Energy is one pool shared between the map and battle** — moving spends the same energy you use to play cards, and it regenerates per turn in both. Wilds on your tile can be attacked by **clicking your own tile** (and they ambush you at end of turn).
- **Capturing** a wild in battle uses a **capture card** (bought at a Trading Post), not a free action. Success chance scales with how wounded the target is.
- Each species has **separate base stats** for food: **`base_satiety`** (bar capacity) and **`base_upkeep`** (food consumed per turn), both scaled by level. Feeding refills 50% of the bar, starvation drains 30%; a full bar heals over time.
- Species have an **`elements` array** (1–2 types, primary first). Incoming damage is multiplied against **every** type the defender has — **weakness 2×, resistance 0.5×** — and a move whose element matches one of the attacker's types gets a **1.5× STAB** bonus (e.g. Flora vs Aqua/Ember = 2× × 0.5× = 1×).

## Elements

Nine types: **Neutral, Ember, Aqua, Flora, Ice, Ground, Electric, Air, Poison**.

- Weakness = **2×**, resistance = **0.5×**; dual types multiply together.
- **STAB**: a move whose element matches one of the attacker's types deals **1.5×**.
- Super-effective (attacker → 2× vs): Ember→Flora/Ice · Aqua→Ember/Ground · Flora→Aqua/Ground · Ice→Flora/Ground/Air · Ground→Ember/Electric/Poison · Electric→Aqua/Air · Air→Flora/Ground · Poison→Flora/Aqua.
- **Air types ignore Walls** (flying over them).

## Damage formula

Attacks are **multiplicative**: base card damage × Power × Strength bonus, then type / STAB / Vulnerability, then Defense.

```
dmg = card_damage
    × power                  -- the creature's Power stat (~1.0 at level 1; grows with level)
    × (1 + 0.1 × strength)   -- each point of Strength = +10% damage
    × type multipliers       -- 2× / 0.5× against each of the defender's types
    × 1.5 (STAB)             -- if the move matches one of the attacker's types
    × 1.5 (Vulnerable)       -- if the target has any Vulnerable
    × 10 / (10 + defense)    -- defense scales the hit down proportionally (10 = half damage)
```

Species **base Power was rebalanced to 0.75–1.6** (it is a multiplier now) so a level-1 hit lands close to the card's printed damage; **Defense** stays a stat but now reduces damage proportionally, so it stays relevant at every level.

### Status cards

Self-buffs and enemy debuffs share the same stat model, so a card can push a stat either way:

- **Strength** — each point is **+10%** damage dealt (can go negative). Raised by **Hone / Warcry**; lowered by **Weaken** (−2 str) and **Disarm** (4 dmg, −2 str).
- **Defense** — a temporary modifier on the defender. Raised by **Iron Skin / Bark Skin / Warcry**; shredded by **Sunder** (6 dmg, −2 def) and **Corrode** (−3 def).
- **Block** — a per-turn pool that absorbs damage, reset each round.
- **Vulnerable** — the target takes **×1.5** damage while it lasts (Screech, Cinder…).

Weaken / Disarm / Sunder / Corrode are available to every species as **reward cards** (in `COMMON_MOVES`) and also sit in the starter decks of **Gloomling** (Weaken), **Wispling** (Disarm), **Bogfang** (Weaken), **Stonepaw** (Sunder) and **Venomtail** (Corrode), so wild monsters use them too.

### Turn order

Combat uses a **per-monster initiative queue**. Each turn, every living monster on the field — **all of your party and every wild** — is sorted by **Speed** (highest first; exact ties are a coin flip). The queue is then cycled: each monster plays **one card** when its slot comes up, and the queue wraps around until nobody can act. Only then does a new **turn** begin — fresh hands, energy and Block. So hands/energy refresh once per *turn*, while each pass through the queue is just an exchange. Extra monsters each get their own slot, so numbers and Speed both matter.

## Terrain

| Terrain | Rarity | Behaviour | Traversal |
|---|---|---|---|
| **Cave** | common | low-level mobs occasionally if unguarded; **Mine** → small gold, no spawns | normal |
| **Water** | common | low-level mobs rarely if unguarded | **water monsters only** unless **Bridge** |
| **Dungeon** | uncommon | high spawn chance, tougher mobs, more loot/xp, rarity scaling | normal |
| **Grove** | uncommon | small food; low mob spawns if unguarded; **Farm** → decent food, no spawns | normal |
| **Trading Post** | rare | spend gold on heals, energy, revives, capture cards | normal |
| **Boss Room** | rare | near dungeons; very strong, **uncatchable**, great loot/xp, drops **crystals** | normal |
| **Mushroom Grove** | uncommon | food-rich; flora mobs; **Farm**/**Well** valid | normal |
| **Ruins** | uncommon | neutral mobs, tougher; **Wall**/**Watchtower** valid | normal |
| **Tundra** | uncommon | ice/air mobs | **Ice** only |
| **Jungle** | uncommon | **only Flora types** may enter | **Flora** |
| **Lava** | rare | **only Ember types** may enter | **Ember** |
| **Desert** | uncommon | ground/electric mobs | normal |
| **Quicksand** | rare | **only Ground types** may enter | **Ground** |

Spawn tables differ per terrain, with some mobs **unique to a tile type**. Enemy **level scales with distance from the entrance**, so the starting area is gentler and the frontier is dangerous.

## Improvements (built with gold)

| Improvement | On | Effect |
|---|---|---|
| **Farm** | Grove | **staffed** by one of your monsters: feeds your monsters within 4 tiles; surplus is delivered to a **Granary within 4** (else wasted) |
| **Mine** | Cave | **staffed**: delivers gold to a **Treasury within 4**; with none in range it goes to your **stockpile** (up to the gold cap) |
| **Bridge** | Water | lets non-water monsters cross |
| **Granary** | Cave, Grove | stores food; feeds your monsters within 4 |
| **Treasury** | Cave | stores gold (counts as spendable) |
| **Watchtower** | Cave, Grove, Mushroom, Ruins | reveals within 6; deters spawns within 4; **defenders within 4 start battle with +6 Block** |
| **Wall** | Cave, Grove, Mushroom, Ruins | wilds won't roam across it |
| **Well** | Cave, Grove, Mushroom — **must be adjacent to Water** | feeds your monsters within 4, small (+2, no staffing) |

Building an improvement again gets progressively **more expensive** (cost = base + base·count/3), so the early colony is cheap to expand — except **Walls**, which scale at half that rate (`base·count/6`) so you can wall off an area affordably. The scaling counts only improvements **currently standing** — destroyed ones don't raise the price, so rebuilding after a raid is no worse than the first time. Damaged improvements can be **repaired** from the build panel for half their base cost (prorated by the missing HP), and you can **replace** a built improvement by building over it (the old one, and anything it stored, is lost).

**Logistics rules**
- **Farms and Mines only produce while one of your monsters is stationed on the tile.**
- **Food has no global pool:** it lives in farms/granaries. A monster is fed only if a Farm or Granary with food is **within 4 tiles**; otherwise it starves.
- **Gold is global/accessible.** Treasury contents count toward your spendable gold and are **lost if the treasury is destroyed** (Phase 3). Likewise a destroyed granary loses its food.
- Any production with **no valid receiver in range is wasted** that turn.

## Breeding & genetics

- Every monster has a **genetic bonus per stat, 0–5**, with higher values increasingly rare (0 common … 5 very rare).
- **Breeding**: average the parents' genetics, then apply random rolls.
- Babies spawn at **level 1**.

## Rewards

- Reward cards are **no longer given after every battle** — they become **rare drops**.
- Drop tables are **per species and per level**.
- Many **special moves** only come from reward cards.
- **Kills grant XP** (scaled by the defeated monster's level); surviving defenders level up as thresholds are crossed. A **post-fight results screen** shows gold, XP, any food delivered and any card gained.

## Floors

- **10 floors**, each harder, with higher-level monsters and **new mobs** to encounter.
- **Crystals** charge the move of monsters between floors, or can be fed for XP.

---

# Roadmap (phased)

1. **Colony foundation** — regular hex grid with terrain; currencies + HUD; persistent monster roster placed on tiles; turn loop; energy-based movement; food consumption / starvation / healing.
2. **Improvements & economy** — build/upgrade improvements; storage caps; Trading Post UI.
3. **Threats & combat hooks** — spawn tables, roaming wilds, guarding, improvement damage/destruction, auto vs manual fight, loot (gold/food/xp/cards).
4. **Content** — more monsters, moves, and card synergies.
5. More improvements and economy fleshed out - Difficulty curve on the game adjusted, more types of improvements and tiles
6. **Floors & progression** — floor 1–10 scaling, crystal travel cost, crystal→XP feeding, final boss.
7. **Breeding & genetics** — 0–5 genetics, breeding rolls, babies at level 1.

## Lose conditions

- **All monsters dead** — whether from **starvation** or **killed in battle** — the run ends.

## Progress

- Phase 1 ✅ colony foundation (regular hex grid + terrain, currencies, roster on tiles, turn loop, movement energy, food upkeep). The grid is now **infinite** (tiles generated on demand).
- Phase 2 ✅ improvements & economy (build with gold, staffed production, range-gated food logistics, Trading Post: heal / energy / revive) + graveyard.
- Phase 3 ✅ threats & combat: per-terrain spawn tables, roaming wilds, guarding (no spawns on defended/Farm/Mine tiles), improvement damage & destruction — a wild on an **unguarded** improved tile damages it each turn (defended tiles instead trigger a battle; contents are lost on destruction, with a destruction notice; damaged improvements can be **repaired** from the build panel for half their base cost, prorated by missing HP), auto/manual deck battles, loot (gold + rare reward cards), and the all-monsters-dead lose condition.
- Phase 4 ✅ content: **12 new species** (Gloomling, Pyrelord, Krakling, Swampbeast, Wispling, Cindermaw, Rimescale, Mosshide, Emberbloom, Bogfang, Cinderwing, Frostmoss) with own decks/learnsets/pools, **17 new moves** including **synergies** (bonus vs Vulnerable, bonus while Blocked, bonus on combo), and a common move pool available as drops to every species. **Power / Defense / Speed are now floats**, scaled from fractional species base stats for finer variety.
- Phase 5 ✅ improvements & difficulty: **build costs scale up** the more of an improvement you have — counting only improvements **currently standing**, so destroyed ones don't raise the price (cheap early); enemies **scale with distance from the entrance** so the start is gentler; new improvements **Watchtower** (reveals within 6, deters spawns within 4, and gives defenders within 4 **+6 Block** at battle start), **Wall** (wilds won't roam across it), **Well** (must be adjacent to Water; feeds within 4, +2, no staffing); new tiles **Mushroom Grove** and **Ruins**; **prices lowered** across buildings and Trading Post (they scale up as you grow anyway). The map is **infinite**: tiles are generated on demand (deterministically from the seed) around your monsters and the entrance, and rendered as fog until explored. **Trading Posts (~1.5% of tiles) and Boss Rooms (~0.8%, at least 6 tiles from the entrance) are scattered randomly** rather than fixed, so they must be found by exploring. Terrain comes from **coherent value-noise biomes** (elevation × moisture, a few octaves of fBm) so regions are contiguous — cave systems, groves, lakes, tundra fields, jungle belts — instead of a per-tile mosaic; a few of the type-locked terrains are seeded just outside the entrance so Ice/Flora/Ember/Ground content is reachable early. The **entrance is placed in the most open, neutral spot near the origin** and its chamber is cleared of impassable terrain, so no starter can spawn boxed in by Tundra/Lava/Water/etc. **Wild spawns ramp up over the first 30 turns** (from 10% to full rate) so the opening is calm. **Energy is a single pool** shared by colony movement and battle card play (spent in one, missing from the other; regenerated per turn). **Walls can be built on Grove / Mushroom Grove.** You can **attack a wild sharing your tile** by clicking your own tile. The battle UI shows an **XP bar**, and each enemy now shows an **energy bar** alongside its HP and modifier chips. **Attacks open a "choose attackers" screen** — your monsters on the target tile and adjacent tiles, each toggleable — instead of only the monster that started the fight; **TAB cycles only through monsters you own**, and clicking a tile with several of your monsters cycles through them.
- Phase 5b ✅ more content: **5 new elements** (Ice, Ground, Electric, Air, Poison) with a 9-type chart (2×/0.5×) and STAB; **5 new terrain types** — Tundra, Desert, and type-locked **Jungle (Flora only)**, **Lava (Ember only)**, **Quicksand (Ground only)**; Air types ignore Walls; **6 new species** covering the new types (Frostfang, Stonepaw, Sparkit, Galebeast, Venomtail, Blizzard); **10 new moves**; and an in-game **monster encyclopedia** (`M`) showing every species' types, base stats, starter deck and learnset; the colony HUD shows global **Food +N/turn** and **Gold +N/turn** production, and hovering an improved tile shows its remaining HP. The battle UI lists each fighter's active boosts (Strength / Defense / Block / Vulnerable) with the damage multiplier each one contributes; **enemy debuff cards** (Weaken, Disarm, Sunder, Corrode) lower a target's Strength or Defense (several species carry them, so wilds use them too), Strength/Defense can now go negative, **combat uses a per-monster Speed initiative queue** (every living monster acts in Speed order, cycling each turn; ties are a coin flip), and hovering a hand card shows its **estimated damage** against the current target (with a super-effective / resisted / multi-hit note).

