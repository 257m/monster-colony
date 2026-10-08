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

1. **`begin_round`** runs when nobody can act: stalemate check against
   `MAX_ROUNDS`, end-of-round cleanup, `round += 1`, `creature_begin_round` for
   all, then `build_order` and `advance`.
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

## Damage — `apply_damage(attacker, target, base, elem)`

```
str   = max(1 + 0.1*attacker.strength, 0.1)     // +10% per Strength, floored
dmg   = base * attacker.power * str             // power is a multiplier stat
dmg  *= element_multiplier(elem, def) for EACH defender element   // 2x / 0.5x
dmg  *= 1.5 if the move matches one of the attacker's elements      // STAB
dmg  *= 1.5 if target.vulnerable > 0
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
| `vulnerable` | ticks down each turn | target takes ×1.5 |
| `strength` | persists (can go negative) | ±10% outgoing damage |
| `defense_buff` / `defense_debuff` | persists | raise/lower the defense divisor |
| `played` | reset each turn | enables combo synergies |

`creature_reset_battle_state` clears all per-battle statuses at battle start
(**not** energy). `build_effects` + `draw_effects_row/column` render them as
chips with their multipliers.

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
  with how wounded the target is. Captured ids land in `captured_ids`.

## Enemy AI

- `choose_enemy_card` picks the affordable card with the highest `move_value`
  (the heuristic in `moves.odin`).
- `enemy_step` plays it, logs it, and handles a kill. It attacks a **random
  living party member** (`pick_party_target`) — there is no front line / taunt.
- `player_ai_step` runs the *same* greedy heuristic for your side during
  auto-fight (for whichever party member's turn it is).

## End of fight

- `phase = .WON` / `.LOST` / `.CAPTURED` freezes the engine (only timers tick).
- `main.odin` picks them up: `resolve_won` / `resolve_lost` (see
  [architecture.md](architecture.md)).

## Battle rendering

`draw_battle` (in `battle.odin`) draws everything: `draw_enemies` (name, HP bar,
energy bar, modifier chip column), `draw_player_panel` (name, stats, HP, **XP
bar**, energy, deck size, modifier row), `draw_party` (the right-hand roster),
`draw_hand`, `draw_card_estimate` (hover damage preview), `draw_buttons`
(capture / end-turn), `draw_battle_log`, `draw_popups`, and the win/lose
overlays. Geometry helpers (`*_rect`) live next to their use. `PARTY_MAX` is 6.

If you add a battle status, update **both** `build_effects` (the chip) and
`draw_*` uses, and the damage/defense formula where relevant.
