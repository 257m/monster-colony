# Vibegambling — Colony Hexcrawl Design

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
- Attacking a tile defended by your monster(s) triggers a **battle**: choose **auto-fight** (your side AI-controlled) or **manual**.
- A tile with one of your monsters is **guarded** → no mob spawns there.
- You **send monsters each turn**; moving costs **energy** based on the monster's **Speed** and the destination tile.

## Terrain

| Terrain | Rarity | Behaviour | Traversal |
|---|---|---|---|
| **Cave** | common | low-level mobs occasionally if unguarded; **Mine** → small gold, no spawns | normal |
| **Water** | common | low-level mobs rarely if unguarded | **water monsters only** unless **Bridge** |
| **Dungeon** | uncommon | high spawn chance, tougher mobs, more loot/xp, rarity scaling | normal |
| **Grove** | uncommon | small food; low mob spawns if unguarded; **Farm** → decent food, no spawns | normal |
| **Trading Post** | rare | spend gold on heals, energy, revives, capture cards | normal |
| **Boss Room** | rare | near dungeons; very strong, **uncatchable**, great loot/xp, drops **crystals** | normal |

Spawn tables differ per terrain, with some mobs **unique to a tile type**.

## Improvements (built with gold)

| Improvement | On | Effect |
|---|---|---|
| **Farm** | Grove | decent food/turn; prevents spawns |
| **Mine** | Cave | small gold/turn; prevents spawns |
| **Bridge** | Water | lets non-water monsters cross |
| **Granary** | Cave, Grove | + food storage |
| **Treasury** | Cave | + gold storage |

## Breeding & genetics

- Every monster has a **genetic bonus per stat, 0–5**, with higher values increasingly rare (0 common … 5 very rare).
- **Breeding**: average the parents' genetics, then apply random rolls.
- Babies spawn at **level 1**.

## Rewards

- Reward cards are **no longer given after every battle** — they become **rare drops**.
- Drop tables are **per species and per level**.
- Many **special moves** only come from reward cards.

## Floors

- **10 floors**, each harder, with higher-level monsters and **new mobs** to encounter.
- **Crystals** charge the move of monsters between floors, or can be fed for XP.

---

# Roadmap (phased)

1. **Colony foundation** — regular hex grid with terrain; currencies + HUD; persistent monster roster placed on tiles; turn loop; energy-based movement; food consumption / starvation / healing.
2. **Improvements & economy** — build/upgrade improvements; storage caps; Trading Post UI.
3. **Threats & combat hooks** — spawn tables, roaming wilds, guarding, improvement damage/destruction, auto vs manual fight, loot (gold/food/xp/cards).
4. **Floors & progression** — floor 1–10 scaling, crystal travel cost, crystal→XP feeding, final boss.
5. **Breeding & genetics** — 0–5 genetics, breeding rolls, babies at level 1.
6. **Content** — more monsters, moves, and card synergies.
