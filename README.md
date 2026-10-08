# Monster Colony

A hex-crawl **colony builder** set in an infinite underground. Build a colony on
procedurally generated terrain, feed and defend your monsters from roaming
wilds, and settle fights in a symmetric **deck-builder** battle engine.

Built with [Odin](https://odin-lang.org/) and [raylib](https://www.raylib.com/).

## 🎬 Demo

▶️ **[Watch the gameplay demo — `out.mp4`](out.mp4)**

<video src="out.mp4" controls width="720"></video>

## Build & run

You need **Odin** with its bundled raylib bindings (and the usual raylib system
deps). Then:

```sh
make run     # compile & play
make build   # build bin/monster-colony
make check   # type-check only
make clean   # remove bin/
```

### Controls (colony)

| Key | Action |
|---|---|
| Left click | move to an adjacent tile / select a monster (click again to cycle stacked monsters) |
| `Tab` | cycle through your monsters |
| `Space` / `E` | end turn |
| `B` | build / repair / replace improvements |
| `T` | Trading Post (when standing on one) |
| `V` | view a monster's deck |
| `M` | monster encyclopedia |
| RMB / `WASD` | pan, wheel to zoom |

Battles are played with `1`–`5` / clicks to play cards, `E` to end your turn,
`C` to use a capture card, `T` to switch.

## Design

See [DESIGN.md](DESIGN.md) for the full spec, systems and phased roadmap.

---

## Original design notes

There will be 2 currencies in the game:
Gold - dropped by mobs, more gold for higher level mobs, can be spent in Trading
Posts, can also be spent building an improvement on a tile
Food - Every monster you have consumes this based on its species and level, too
little food and your monsters will starve, excess and you can either stockpile
it or spend it on breeding. A monster with a full food bar will heal over time.
Some monsters drop food when killed.
Crystals - Dropped by bosses. There is crystal charge when sending monsters
between floors. Each floor is harder than the last, contains higher level
monsters and new mobs to encounter. You win the game by reaching floor 10 and
killing the final boss. Crystals can also be fed to monsters to provide them xp.

Monsters can sit on tiles. Up to 6 monsters can be on a tile. Wild monsters will
roam around and attack improvements and your monsters. If they attack a tile
with a monster you own it initiates the battle. You can either choose to have it
auto fight with the monsters you have on that tile or control them yourself.
Attacking an improvement damages its health or destroys it. Improvements can be
built on tiles with gold. If a tile has your monster on it, it is guarded and
mobs will not spawn on it. You can choose where to send your monsters each turn
but it costs them energy based on their speed stat and tile being moved into.
Killing a monster can drop gold, xp, food or even reward cards. Reward cards
will no longer be given freely at the end of every battle but instead be rare. A
lot of special moves will be dropped from reward cards. The reward cards have
their own drop tables based on the monster species and its level.

There will be different terrain tiles:
Cave (Common) - Will spawn low level mobs on occasion if unguarded. Mine can be
built which generates a small amount of gold and prevents mob spawns.
Water (Common) - Will spawn low level mobs on rare occasion if unguarded. Only
traversable by water monsters unless a Bridge has been built.
Dungeon (Uncommon) - Has a large chance to spawn mobs if left unguarded, mobs
are generally tougher but drop more loot and xp. Encounters have rarity scaling.
Grove (Uncommon) - Can provide a small amount of food. Will spawn low level mobs
if left unguarded. Farm can be built which generates a decent amount of food and
prevents mob spawns.
Trading post (Rare) - Allows you to spend gold on heals, energy bars, revives,
and capture cards.
Boss room (Rare) - Found near dungeons, contain very strong mobs but spawn rate
is low. Cannot be caught. Very good loot. High xp drop. Drops crystals.

Note: Types of mobs spawning in caves, groves and dungeons are pulled from
different spawn tables. They have certain mobs unique to the tile.

Improvements:
Farms (Grove) - Generate a decent amount of food every turn and prevent mob spawns
Mine (Cave) - Generate a small amount of gold every turn and prevent mob spawns
Bridge (Water) - Enables non-water monsters to travel over Water tiles
Granary (Cave, Grove) - Adds additional food storage
Treasury (Cave) - Adds additional gold storage

Breeding system:
Every monster has a genetic bonus attached to every stat, scaling from 0 to 5.
The chance of a higher genetic bonus gets rarer and rarer. 0 being most common
and 5 very rare. Breeding monsters averages and then does some random rolls on
the genetics. Baby monsters spawn at level 1.

This is just a general overview of what I want. Of course in addition add more
monster and move variety. In addition to synergies between cards.
