# The battle engine (`src/battle.odin`)

A **symmetric** deck-builder: your side and the wilds obey the same rules. Each
`Creature` has its own deck; every turn it resets Block, gains energy, and draws
a fresh hand. **Every monster on the field is in play at once** — all of your
party and all wilds share one initiative queue. The only asymmetry is that you
command your monsters by hand (each on its own turn) while the wilds are
AI-driven, and capture is player-only.

## State

```
Battle_Phase :: enum { PLAYER_ACTION, ENEMY_ACTION, WON, LOST, CAPTURED }

Battle.party, .enemies   [dynamic]^Creature   // borrowed from Colony.roster
       .party_done       per party member: ended its turn this turn
       .enemy_ids        parallel colony ids (for capture/loot)
       .target           current enemy index
       .active           the party member whose turn it is (UI)
       .enemy_acting     current wild index (the one taking its slot)
       .captured_ids     ids captured this fight
       .capture_cards    spent on capture
       .phase, .round, .timer
       .order: [dynamic]Actor, .order_pos   // the initiative queue
       .rng, .log, .popups, .shake
```

`Actor` is `{ side: Battle_Side, index: int }` — every living party member and
every wild is one actor in the shared queue.

Anything that changes HP/energy/statuses changes it on the real colony
`Creature` — the battle is a *view + driver* over them.

## Lifecycle

`battle_start(defenders, enemies, enemy_ids, seed_rng)`:
1. copy the pointer lists, seed the RNG,
2. `creature_reset_battle_state` on both sides (clears block/strength/vuln/buffs
   — **but not energy**, which is shared with the map),
3. `prepare_piles` (deck → draw pile, shuffled) for everyone,
4. `begin_round`.

`battle_free` releases the log/popups and the per-creature *piles*
(`creature_free_piles`) — never the creatures themselves.

## Piles & drawing

- `prepare_piles` moves the whole `deck` into `draw_pile` and shuffles.
- `creature_draw(c, n, rng)` draws `n`, reshuffling `discard` back in when the
  draw pile runs dry.
- `creature_begin_round` sets `block = 0`, `played = 0`,
  `energy = min(energy + energy_regen, energy_max)`, and draws 5.
- `creature_end_round` discards the hand and ticks `vulnerable` down by 1.

## Turn order — the initiative queue

There is **no side alternation**. Each *turn* (a hand/energy refresh) cycles a
Speed-sorted queue of every living monster.

1. **`begin_round`** runs when nobody can act: the stalemate check
   (`STALL_ROUNDS` rounds with no HP lost anywhere, plus the `SAFETY_ROUNDS`
   net), end-of-round cleanup, `round += 1`, `creature_begin_round` for all, then
   `build_order` and `advance`.
2. **`build_order`** builds `order`: one `Actor` per **living party member** and
   per living wild. It **shuffles**, then stable-sorts by `speed` descending —
   so equal speeds are a coin flip, faster monsters act first.
3. **`advance`** walks `order` from `order_pos` (wrapping) and hands control to
   the first actor that **`actor_can_act`** (player: not `party_done`, alive, has
   an affordable card; wild: alive, has an affordable card). If a whole pass
   finds nobody, `begin_round` starts a new turn.
4. **`set_actor`** sets the phase: `PLAYER_ACTION` (and `active` = that party
   member, waits for input) or `ENEMY_ACTION` (a short `timer` then `enemy_step`).

So each actor can act **once per pass**, and passes repeat until everyone is out
of cards/energy. **Energy and hands refresh once per turn, not per pass.**

`actor_speed` adds each creature's per-battle `speed_buff`, so the `Swift`
ability changes initiative without touching the map-movement Speed stat.

## Species abilities (`src/abilities.odin`)

Each species has a 3-ability pool (`ABILITY_POOLS`); `creature_make(..., rng)`
rolls one at spawn into `Creature.ability`. Hooks:

| Ability | Hook |
|---|---|
| Berserk / Guardian / Thick Hide / Swift / Intimidate | `ability_battle_start` (called from `battle_start` after the reset) |
| Lucky | `creature_begin_round` (draws 5 + `ABILITY_LUCKY_DRAW`) |
| Regenerator | `creature_end_round` |
| Vampiric | `play_creature_card` (heals on a landed hit) |

Items hook the same points: `item_battle_start` (buffs), the draw in
`creature_begin_round`, the on-hit heal in `play_creature_card`, and
`capture_chance`. Stat items are folded into `creature_recompute_stats`.

`creature_end_round` (not `creature_begin_round`) clears **Block**, so a
battle-start Block like Guardian or War Banner survives turn one.

## Damage — `apply_damage(attacker, target, base, elem)`

```
str   = max(1 + 0.1*attacker.strength, 0.1)     // +10% per Strength, floored
dmg   = base * attacker.power * str             // power is a multiplier stat
dmg  *= element_multiplier(elem, def) for EACH defender element   // 2x / 0.5x
dmg  *= 1.5 if the move matches one of the attacker's elements      // STAB
dmg  *= 1 + 0.5*target.vulnerable   if target.vulnerable > 0
dmg  *= 10 / (10 + creature_defense(target))    // defence scales it down
d      = int(dmg)
absorb = min(target.block, d); target.block -= absorb
target.hp -= (d - absorb)
```

Key ideas:
- Only **type, STAB, Vulnerable and Defense** are multiplicative; `power` and
  `Strength` become multipliers via the species stats / `1 + 0.1·str`.
- `creature_defense = max(defense + defense_buff − defense_debuff, 0)`.
- `estimate_damage` mirrors this exactly (including synergy bonuses) for the
  hover preview; keep the two in sync if you change the formula.

## Playing a card — `play_creature_card`

1. Checks energy and spends `m.cost`.
2. If it deals damage, computes the synergy `bonus` for the first hit
   (`vuln_bonus` / `block_bonus` / `combo_bonus`) and loops `m.hits` calling
   `apply_damage`.
3. Applies the rest: `block`, `vulnerable` (to target), `strength`,
   `defense` buff, `strength_down` (Weaken), `defense_down` (Sunder/Corrode),
   `heal`, `draw`.
4. Moves the card hand → discard and does `played += 1`.

Popup feedback is via `spawn_popup` + `Popup_Kind` (`DAMAGE, BLOCK, HEAL, BUFF,
DEBUFF, DEFEND, WEAKEN, SHATTER, CAPTURE`).

## Statuses

| Status | Where | Effect |
|---|---|---|
| `block` | reset each turn | absorbs damage before HP |
| `vulnerable` | ticks down each turn | target takes ×(1 + 0.5·stacks) |
| `strength` | persists (can go negative) | ±10% outgoing damage |
| `defense_buff` / `defense_debuff` | persists | raise/lower the defense divisor |
| `played` | reset each turn | enables combo synergies |
| `poison` | ticks down each round | lose `poison × POISON_PCT` of **max HP** at round start, then −1 |
| `burn` | ticks down each round | lose `burn × BURN_PCT` of **max HP** at round start, then −1 |
| `regen` | ticks down each round | heal `regen × REGEN_PCT` of **max HP** at round start, then −1 |
| `thorns` | persists (one stack per hit) | reflect a slice of the **attacker's max HP**, `THORNS_HP_PCT` per stack on a diminishing curve |
| `stun` | consumed per round | **Daze**: fumbles that many cards out of the creature's hand at the start of its turn. Costs no energy and the turn continues — it is a disruption, not a skip. |

Damage/heal-over-time statuses tick in `tick_status` (called from
`begin_round`); **Stun** is consumed in `advance` (`actor_is_stunned`, guarded
by `stun_round` so it only decays once per round) and DoT deaths are checked at
the round boundary. Thorns fire from `play_creature_card` after a hit lands.
**These are all percentages** (`POISON_PCT` 2%, `BURN_PCT` 3%, `REGEN_PCT` 3%,
`THORNS_HP_PCT` 6.25% of the attacker's max HP per stack, on a diminishing curve
that never reaches 100%) so they scale with HP instead of going stale. Lifesteal
(Leech, Devour, Riptide/Maelstrom, the Vampiric ability, the Siphon Gland item)
is a fraction of the damage dealt. Cards apply them via the
`poison`/`burn`/`stun`/`regen`/`thorns` fields on `Move`.

**Poison vs Burn** are deliberately different: Poison phases straight through
Block (it is the answer to turtling), while Burn is absorbed by Block *and*
weakens the burned creature's damage (`BURN_WEAKEN_PER_STACK`, capped).

`creature_reset_battle_state` clears all per-battle statuses at battle start
(**not** energy). `build_effects` renders them as chips with their multipliers,
each with a hover tooltip. The chip rows are deliberately tiny and a buffed
monster overflows them fast, so **`S` opens the scrollable ACTIVE EFFECTS panel**
(`draw_battle_effects`) — every living creature on both sides, every effect in
full, two columns, modal.

**Powers** (`powers.odin`) are the per-battle effects granted by POWER cards —
Toxic, Rage, Combustion, Barricade, Demon Form, Sanguine, Metronome, Scavenger,
Juggernaut, Bastion, Flow. They live in `Creature.powers: [Power]int` and are
ticked by `power_*` helpers; `POWER_TOXIC_POISON` etc. are the rates.

## Actions

- **Play a card**: `player_play(b, hand_index)` plays from the current actor's
  hand → `play_creature_card`, then `advance`.
- **End turn**: `player_end_round` sets `party_done[b.active] = true` (ending
  *that* monster's turn) and `advance`s — the rest of the queue keeps going.
- **Target**: click an enemy → `b.target`.
- **Death**: a fainted party member is simply skipped by `actor_can_act`; there
  is **no** switching. The fight continues with the survivors, and goes to
  `LOST` only when all of them are down.
- **Capture**: `attempt_capture` spends a capture card; `capture_chance` scales
  with how wounded the target is, and falls with the target's **level** and
  **species rarity** (`rarity_catch_mult`). Captured ids land in `captured_ids`.

## Enemy AI

- `choose_enemy_card` picks the affordable card with the highest `move_value`
  (the heuristic in `moves.odin`).
- `enemy_step` plays it, logs it, and handles a kill. It attacks a **random
  living party member** (`pick_party_target`) — there is no front line / taunt.
- `player_ai_step` runs the *same* greedy heuristic for your side during
  auto-fight (for whichever party member's turn it is).

Three things here are load-bearing, because getting them wrong spins the fight
forever:

- **`card_worth_playing` is the single gate.** The turn gate (`actor_can_act` /
  `enemy_has_card`) and *both* AIs must answer "is this card usable right now?"
  the same way. A `move_value` of −4 (a Dazed, which exhausts) used to be skipped
  by the chooser while the gate counted it playable — the monster got a turn it
  could never take, and the fight hung.
- **`MAX_PLAYS_PER_ROUND`** (12) retires any monster that has spent its round.
  It exists to catch genuine loops, like a retained card that pays for itself
  (Meditate costs 0.5 and hands back 1).
- **A failed play retires the actor** (`enemy_step`) rather than re-picking the
  same card, and **`advance` settles a wiped side itself** — a side killed by
  item recoil, a poison tick or reflected thorns was never marked `.LOST`, and
  the other side took turns at nobody forever.

Auto-fights settle themselves: `update_battle` skips the "click to continue"
gate when `battle.auto_play` is set.

## End of fight

- `phase = .WON` / `.LOST` / `.CAPTURED` freezes the engine (only timers tick).
- `main.odin` picks them up: `resolve_won` / `resolve_lost` (see
  [architecture.md](architecture.md)).
- There is **no flat round cap**. A fight ends early only on a genuine standstill
  (`STALL_ROUNDS`, 12 rounds with no HP lost on either side — the higher
  remaining-HP fraction wins), with `SAFETY_ROUNDS` (200) as a last-ditch net so
  a bug can never freeze the game. A 480-fight sample averages 4.1 rounds.

## The Arena (`battle_arena`)

An Arena fight is an ordinary battle with three differences:

- **It is fought by the monsters standing on the tile** (`build_attack(g, hex, 0)`
  from the Arena screen), not everyone within a hex of it — and a tile holds six,
  so a party can never exceed `PARTY_MAX`.
- **Colony relics are stripped** (no Relic Tower projection). The one relic
  effect that *does* apply is the run's own **boons**
  (`arena_boon_counts`), which die with the run.
- On a win, `resolve_won` banks the floor's purse instead of paying it
  (`arena_clear_floor`), and returns you to the **Arena screen** rather than the
  map while the run is live.

The reference panels stay available mid-battle: `V` (deck viewer), `L` (dex),
`M` (dex on the monster tab), `S` (active effects), `D` (piles). See
[ui-and-input.md](ui-and-input.md).

## Battle rendering

`draw_battle` (in `battle.odin`) draws everything: `draw_enemies` (name, level +
**element-type chips**, ability, HP bar, energy bar with `En cur/max +regen`,
modifier chip row), `draw_player_panel` (name, ability, stats, HP, **XP bar**, an
energy bar that shows a dim **regen preview** and `cur / max +regen per turn`,
deck size, modifier row), `draw_party_field` (your whole party as info cards on
the field — avatar, name, level/element, HP numbers, energy bar, active buff
chips, and ability/item; the acting monster is ringed, ended-turn ones are dimmed
with an `ENDED` tag, the dead are greyed), `draw_hand`,
`draw_card_estimate` (hover damage preview), `draw_buttons` (capture / end-turn),
`draw_pile_readout` (clickable `Draw N` / `Discard N`), `draw_piles` (the
`D` pile viewer, listing the draw and discard piles), `draw_battle_log`,
`draw_popups`, and the win/lose overlays. Geometry helpers (`*_rect`) live next to
their use. `PARTY_MAX` is 6.

**Effect feedback.** Playing a card spawns a `Popup` (`draw_popups`, floating
`-12` / `+8 blk` / `+4 str` … text, coloured by `popup_color`) *and* a
`creature_burst` on the affected creature — an expanding coloured ring drawn by
`draw_creature_avatar` and aged down in `battle_update` (`fx_t`/`fx_dur`/`fx_col`).
Heals from the **Regenerator** ability (at the round transition in `begin_round`)
and **Vampiric** (in `play_creature_card`) get the same green burst + popup, so
healing is visible even when it isn't from a card.

If you add a battle status, update **both** `build_effects` (the chip) and
`draw_*` uses, and the damage/defense formula where relevant.
