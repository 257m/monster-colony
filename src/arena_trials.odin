package main

import "core:fmt"
import "core:strings"

// ============================================================================
// ARENA TRIALS (Phase 64)
//
// Every tenth floor of the tower is a set-piece. Most are **gyms**: a fixed,
// hand-built team, a little tougher than the floors around it, drawn from a
// short list that cycles as you climb. Every third trial is instead an
// **event** — a decision floor, where the tower offers a few concrete ways to
// adapt your team (a card, an item, an ability) and you may always walk on
// unchanged. Both are pure functions of the floor, so they never re-roll.
// ============================================================================

ARENA_TRIAL_EVERY       :: 10 // a set-piece floor every this many floors
ARENA_TRIAL_EVENT_EVERY :: 3  // every Nth trial is an event rather than a gym
ARENA_GYM_LEVEL_MULT    :: 1.25
// How many run boons a run can hold. A boon is a relic you picked up on the way
// up: it works for the rest of the run and then it is gone.
ARENA_BOON_CAP          :: 6

// A cheap, stable hash of (run seed, n). A run's gym order and its event offers
// are both derived from it, so they are fixed for the whole run — you can be
// told what is coming and plan around it — while a fresh run gets its own.
arena_run_hash :: proc(seed: u64, n: u64) -> u64 {
	z := seed + n*0x9E3779B97F4A7C15 + 0x2545F4914F6CDD1D
	z = (z ~ (z >> 30)) * 0xBF58476D1CE4E5B9
	z = (z ~ (z >> 27)) * 0x94D049BB133111EB
	return z ~ (z >> 31)
}

arena_is_trial_floor :: proc(floor: int) -> bool {
	return floor > 0 && floor % ARENA_TRIAL_EVERY == 0
}

// Trials are numbered 1, 2, 3 ... from floor 10 upward.
arena_trial_index :: proc(floor: int) -> int {
	return floor / ARENA_TRIAL_EVERY
}

arena_is_event_floor :: proc(floor: int) -> bool {
	return arena_is_trial_floor(floor) && arena_trial_index(floor) % ARENA_TRIAL_EVENT_EVERY == 0
}

// ----------------------------------------------------------------------------
// Gyms
//
// A named team with a theme and one boss leading it. Members name the *set*
// they fight as rather than an index, so the list survives the generator
// reshuffling a species' sets.
// ----------------------------------------------------------------------------

Gym_Member :: struct {
	species: Species_Id,
	set:     string,
}

Gym :: struct {
	name: string,
	desc: string,
	team: []Gym_Member,
}

ARENA_GYMS := [?]Gym {
	{
		name = "Emberworks",
		desc = "A forge that never cooled. Everything here is already burning.",
		team = []Gym_Member {
			{.Magmalisk, "Pyre"},
			{.Ashfang, "Pyre"},
			{.Cinderwing, "Pyre"},
			{.Magmaw, "Pyre"},
			{.Dreadhorn, "Fury"},
			{.Boss_Infernal, "Pyre"},
		},
	},
	{
		name = "Tidehollow",
		desc = "A drowned hall. Something in the water is still hungry.",
		team = []Gym_Member {
			{.Tidewyrm, "Bloom"},
			{.Bubblord, "Bulwark"},
			{.Ripfin, "Swarm"},
			{.Bogmaw, "Blight"},
			{.Tidecaller, "Daze"},
			{.Boss_Leviathan, "Swarm"},
		},
	},
	{
		name = "Bramble Court",
		desc = "The garden won. It has opinions about trespassers.",
		team = []Gym_Member {
			{.Blightbloom, "Bramble"},
			{.Thornmaw, "Bramble"},
			{.Sporelord, "Bramble"},
			{.Bloomcap, "Bramble"},
			{.Rimewarden, "Bramble"},
			{.Bogmaw, "Bloom"},
		},
	},
	{
		name = "The Static Choir",
		desc = "They hum in unison. It is not a pleasant sound.",
		team = []Gym_Member {
			{.Stormwing, "Daze"},
			{.Voltail, "Daze"},
			{.Sparkit, "Tempo"},
			{.Nightwing, "Zephyr"},
			{.Cinderwing, "Zephyr"},
			{.Boss_Sovereign, "Zephyr"},
		},
	},
	{
		name = "Permafrost Vault",
		desc = "A vault of blue ice. Nothing inside it has ever thawed.",
		team = []Gym_Member {
			{.Rimewarden, "Bulwark"},
			{.Frostfang, "Rubble"},
			{.Glacierling, "Bulwark"},
			{.Frostmaw, "Bulwark"},
			{.Gravemaw, "Bulwark"},
			{.Boss_Titan, "Bulwark"},
		},
	},
	{
		name = "The Bone Yard",
		desc = "Whatever the dungeon buried, this is where it ended up.",
		team = []Gym_Member {
			{.Gravemaw, "Rubble"},
			{.Rotshell, "Ruin"},
			{.Grubling, "Ruin"},
			{.Crypt_Rat, "Swarm"},
			{.Relic_Hound, "Rubble"},
			{.Deep_One, "Rubble"},
		},
	},
	{
		name = "Mirrorhall",
		desc = "Your own lines, wearing someone else's colours.",
		team = []Gym_Member {
			{.Magmalisk, "Fury"},
			{.Tidewyrm, "Bulwark"},
			{.Blightbloom, "Blight"},
			{.Cinderscale, "Fury"},
			{.Ripfin, "Swarm"},
			{.Thornbud, "Bramble"},
		},
	},
	{
		name = "The Deep Choir",
		desc = "The floor stops pretending. Something down here is awake.",
		team = []Gym_Member {
			{.Deep_One, "Ambush"},
			{.Boss_Infernal, "Ambush"},
			{.Gravemaw, "Ambush"},
			{.Dreadhorn, "Ambush"},
			{.Rimewarden, "Rubble"},
			{.Boss_Sovereign, "Fury"},
		},
	},
}

// Which gym of the run a trial floor is (1-based, counting only gym trials).
arena_gym_number :: proc(floor: int) -> int {
	t := arena_trial_index(floor)
	return t - t / ARENA_TRIAL_EVENT_EVERY
}

// The gym a trial floor fields. Each run gets its own ordering of the list: the
// cycle is rotated by a run-derived offset and walked by a run-derived stride
// (always odd, so it never falls into a short loop over the list), which means
// no gym repeats until the whole list has been seen.
arena_gym_for :: proc(c: ^Colony, floor: int) -> ^Gym {
	n := len(ARENA_GYMS)
	g := max(arena_gym_number(floor) - 1, 0)
	cycle := g / n
	slot := g % n
	offset := int(arena_run_hash(c.arena_run_seed, u64(cycle)*2 + 1) % u64(n))
	stride := 1 + 2*int(arena_run_hash(c.arena_run_seed, u64(cycle)*2 + 2)%u64(max(n/2, 1)))
	return &ARENA_GYMS[(offset + slot*stride) % n]
}

// The next few trial floors, so the run can be planned around them.
arena_trials_ahead :: proc(c: ^Colony, floor: int) -> cstring {
	sb := strings.builder_make(context.temp_allocator)
	shown := 0
	for f := floor + 1; f <= floor + ARENA_TRIAL_EVERY*3 && shown < 2; f += 1 {
		if !arena_is_trial_floor(f) {
			continue
		}
		if shown > 0 {
			strings.write_string(&sb, "   ")
		}
		if arena_is_event_floor(f) {
			fmt.sbprintf(&sb, "%d a decision", f)
		} else {
			fmt.sbprintf(&sb, "%d %s", f, arena_gym_for(c, f).name)
		}
		shown += 1
	}
	if shown == 0 {
		return cstring("Ahead:  none")
	}
	return fmt.ctprintf("Ahead:  %s", strings.to_string(sb))
}

// The index of a named set within a species' sets (0 when it isn't there).
arena_set_index :: proc(sp: Species_Id, name: string) -> int {
	for k in 0..<MAX_SETS {
		if SPECIES_SETS[sp][k].name == name {
			return k
		}
	}
	return 0
}

// ----------------------------------------------------------------------------
// Events
//
// A decision floor. The tower offers three concrete changes to the team you
// brought — a card, an item, an ability (or a relic, or a rest) — and you may
// always decline all three and walk on unchanged.
// ----------------------------------------------------------------------------

Event_Kind :: enum {
	LEARN,   // trade one card in a deck for another from that move pool
	ABILITY, // swap a monster's ability for another of its species'
	ITEM,    // a monster takes a held item
	RELIC,   // the colony gains a relic
	REST,    // the whole party is restored
}

Event_Option :: struct {
	kind:    Event_Kind,
	mon:     int,     // index into the party on the tile
	move:    Move_Id, // LEARN: the card gained
	drop:    Move_Id, // LEARN: the card given up
	ability: Ability, // ABILITY
	item:    Item,    // ITEM
	relic:   Relic,   // RELIC
}

MAX_EVENT_OPTIONS :: 3

Arena_Event :: struct {
	floor:   int,
	title:   string,
	text:    string,
	options: [MAX_EVENT_OPTIONS]Event_Option,
	count:   int,
}

Arena_Event_Flavor :: struct {
	title: string,
	text:  string,
}

ARENA_EVENT_FLAVORS := [?]Arena_Event_Flavor {
	{
		"A Quiet Landing",
		"The stair opens onto a landing nobody has disturbed in a long while. " +
		"Someone left supplies here, and there is time to sort through them.",
	},
	{
		"A Merchant at the Turn",
		"\"Going up?\" The figure does not look up from its ledger. " +
		"\"Then you'll want to travel lighter than that.\"",
	},
	{
		"A Shrine of Small Debts",
		"The shrine takes nothing, but it asks. You can feel it reading the team " +
		"you brought, looking for something worth trading.",
	},
	{
		"A Broken Warmachine",
		"Its core is still warm. Whatever it was built to do, it can still be " +
		"talked into doing it for you once.",
	},
	{
		"The Long Landing",
		"Someone scratched a tally into the wall here, then a second one. " +
		"There is chalk left over, and a moment to use it.",
	},
}

// The party you brought into the tower — the monsters on the tile.
arena_party_members :: proc(c: ^Colony, hex: Hex) -> ([PARTY_MAX]int, int) {
	out: [PARTY_MAX]int
	n := 0
	for m, i in c.roster {
		if m.wild || m.creature.hp <= 0 || !hex_equal(m.pos, hex) {
			continue
		}
		if n >= PARTY_MAX {
			break
		}
		out[n] = i
		n += 1
	}
	return out, n
}

// One offer: trade the weakest card in a deck for the best card of its move
// pool that it does not already run.
event_offer_learn :: proc(c: ^Colony, rng: ^Rng, mon: int) -> (Event_Option, bool) {
	cr := &c.roster[mon].creature
	best, found := Move_Id.Tackle, false
	for id in SPECIES[cr.species].move_pool {
		if move_in_deck(cr, id) {
			continue
		}
		if !found || move_value(id) > move_value(best) {
			best, found = id, true
		}
	}
	if !found || len(cr.deck) == 0 {
		return {}, false
	}
	worst := cr.deck[0]
	for id in cr.deck {
		if move_value(id) < move_value(worst) {
			worst = id
		}
	}
	if move_value(best) <= move_value(worst) {
		return {}, false
	}
	return Event_Option{kind = .LEARN, mon = mon, move = best, drop = worst}, true
}

// One offer: swap an ability for another its species can have.
event_offer_ability :: proc(c: ^Colony, rng: ^Rng, mon: int) -> (Event_Option, bool) {
	cr := &c.roster[mon].creature
	pool := species_abilities(cr.species)
	choices := make([dynamic]Ability, 0, context.temp_allocator)
	for a in pool {
		if a != cr.ability {
			append(&choices, a)
		}
	}
	if len(choices) == 0 {
		return {}, false
	}
	return Event_Option{kind = .ABILITY, mon = mon, ability = choices[rng_below(rng, len(choices))]}, true
}

// One offer: take a held item.
event_offer_item :: proc(c: ^Colony, rng: ^Rng, mon: int) -> (Event_Option, bool) {
	cr := &c.roster[mon].creature
	pool := make([dynamic]Item, 0, context.temp_allocator)
	for it in ITEM_IDS {
		if it != cr.item {
			append(&pool, it)
		}
	}
	if len(pool) == 0 {
		return {}, false
	}
	return Event_Option{kind = .ITEM, mon = mon, item = pool[rng_below(rng, len(pool))]}, true
}

// Build the event for a floor. Seeded off the run and the floor together, so the
// offers are the same every time you look at them within a run — there is
// nothing to gain by backing out — while a fresh run offers something else.
arena_make_event :: proc(c: ^Colony, hex: Hex, floor: int) {
	ev := &c.arena_event
	ev.floor = floor
	ev.count = 0
	flavor := ARENA_EVENT_FLAVORS[(arena_trial_index(floor) / ARENA_TRIAL_EVENT_EVERY - 1) % len(ARENA_EVENT_FLAVORS)]
	ev.title = flavor.title
	ev.text = flavor.text

	rng := rng_make(arena_run_hash(c.arena_run_seed, u64(floor)))
	party, n := arena_party_members(c, hex)
	if n == 0 {
		return
	}

	// A card offer and an ability offer, each on a different monster where we
	// can manage it, then one of item / relic / rest.
	mon_a := party[rng_below(&rng, n)]
	mon_b := party[rng_below(&rng, n)]
	if n > 1 && mon_b == mon_a {
		mon_b = party[(rng_below(&rng, n - 1) + 1) % n]
	}
	if o, ok := event_offer_learn(c, &rng, mon_a); ok {
		ev.options[ev.count] = o
		ev.count += 1
	}
	if o, ok := event_offer_ability(c, &rng, mon_b); ok {
		ev.options[ev.count] = o
		ev.count += 1
	}
	switch rng_below(&rng, 3) {
	case 0:
		if o, ok := event_offer_item(c, &rng, party[rng_below(&rng, n)]); ok {
			ev.options[ev.count] = o
			ev.count += 1
		}
	case 1:
		if ev.count < MAX_EVENT_OPTIONS {
			if len(c.arena_boons) < ARENA_BOON_CAP {
				ev.options[ev.count] = Event_Option{kind = .RELIC, relic = random_relic(&rng)}
				ev.count += 1
			} else {
				ev.options[ev.count] = Event_Option{kind = .REST}
				ev.count += 1
			}
		}
	case 2:
		if ev.count < MAX_EVENT_OPTIONS {
			ev.options[ev.count] = Event_Option{kind = .REST}
			ev.count += 1
		}
	}
}

// The run's boons, as the count-per-relic array the battle code wants.
arena_boon_counts :: proc(c: ^Colony) -> [Relic]int {
	out: [Relic]int
	for b in c.arena_boons {
		out[b] += 1
	}
	return out
}

// The run's boons, spelled out for the panel.
arena_boons_label :: proc(c: ^Colony) -> cstring {
	if len(c.arena_boons) == 0 {
		return cstring("")
	}
	counts := arena_boon_counts(c)
	sb := strings.builder_make(context.temp_allocator)
	shown := 0
	for r in Relic {
		if counts[r] == 0 {
			continue
		}
		if shown > 0 {
			strings.write_string(&sb, ", ")
		}
		if counts[r] > 1 {
			fmt.sbprintf(&sb, "%s x%d", relic_name(r), counts[r])
		} else {
			fmt.sbprintf(&sb, "%s", relic_name(r))
		}
		shown += 1
	}
	return fmt.ctprintf("Boons:  %s", strings.to_string(sb))
}

// Apply a chosen offer.
arena_apply_event_option :: proc(c: ^Colony, hex: Hex, o: Event_Option) {
	switch o.kind {
	case .LEARN:
		cr := &c.roster[o.mon].creature
		for id, i in cr.deck {
			if id == o.drop {
				cr.deck[i] = o.move
				break
			}
		}
		colony_notify(c, "%s trades %s for %s.", cr.name, MOVE_DATA[o.drop].name, MOVE_DATA[o.move].name)
	case .ABILITY:
		cr := &c.roster[o.mon].creature
		old := cr.ability
		cr.ability = o.ability
		colony_notify(c, "%s sets aside %s and takes up %s.", cr.name, ability_name(old), ability_name(o.ability))
	case .ITEM:
		cr := &c.roster[o.mon].creature
		creature_equip_item(cr, o.item)
		colony_notify(c, "%s takes the %s.", cr.name, ITEM_DATA[o.item].name)
	case .RELIC:
		// A boon, not a colony relic: it lasts the run and is dropped when the
		// run ends, so an event floor can't be farmed for permanent relics.
		if len(c.arena_boons) < ARENA_BOON_CAP {
			append(&c.arena_boons, o.relic)
			colony_notify(c, "The %s serves you for this run.", relic_name(o.relic))
			return
		}
	case .REST:
		party, n := arena_party_members(c, hex)
		for i in 0..<n {
			cr := &c.roster[party[i]].creature
			cr.hp = cr.max_hp
			cr.energy = cr.energy_max
			creature_cleanse_status(cr)
		}
		colony_notify(c, "The whole party is mended.")
	}
	audio_play(.NOTIFY, 0.8)
}

// The label on an option button.
event_option_label :: proc(c: ^Colony, o: Event_Option) -> cstring {
	switch o.kind {
	case .LEARN:
		name := "?"
		if o.mon >= 0 && o.mon < len(c.roster) {
			name = c.roster[o.mon].creature.name
		}
		return fmt.ctprintf("%s: %s  ->  %s", name, MOVE_DATA[o.drop].name, MOVE_DATA[o.move].name)
	case .ABILITY:
		name := "?"
		if o.mon >= 0 && o.mon < len(c.roster) {
			name = c.roster[o.mon].creature.name
		}
		return fmt.ctprintf("%s takes %s", name, ability_name(o.ability))
	case .ITEM:
		name := "?"
		if o.mon >= 0 && o.mon < len(c.roster) {
			name = c.roster[o.mon].creature.name
		}
		return fmt.ctprintf("%s takes the %s", name, ITEM_DATA[o.item].name)
	case .RELIC:
		return fmt.ctprintf("Take the %s for this run", relic_name(o.relic))
	case .REST:
		return cstring("Mend the whole party")
	}
	return cstring("?")
}

// ----------------------------------------------------------------------------
// Sample team (testing aid)
//
// A ready-made six for trying the tower out: two walls, a poison engine, a
// control unit and two damage dealers, each already equipped and running one of
// its named sets. Press `grave` in the colony view to drop them at your
// entrance, levelled to match your best monster so the tower is an even fight.
// ----------------------------------------------------------------------------

Sample_Member :: struct {
	species: Species_Id,
	set:     string,
	item:    Item,
}

SAMPLE_TEAM := [?]Sample_Member {
	{.Gravemaw, "Bulwark", .Grit_Charm},
	{.Rimewarden, "Bramble", .Spiked_Carapace},
	{.Bogmaw, "Blight", .Venom_Sac},
	{.Stormwing, "Daze", .Cleansing_Bloom},
	{.Ashfang, "Fury", .Bloodstone},
	{.Dreadhorn, "Ambush", .Weakpoint_Lens},
}

// A free tile at, or beside, the entrance.
sample_placement :: proc(c: ^Colony) -> (Hex, bool) {
	if monsters_on_tile(c, c.start_hex, false) < MAX_MONSTERS_PER_TILE {
		return c.start_hex, true
	}
	for n in hex_neighbors(c.start_hex) {
		if monsters_on_tile(c, n, false) < MAX_MONSTERS_PER_TILE {
			return n, true
		}
	}
	return c.start_hex, false
}

colony_grant_sample_team :: proc(c: ^Colony) {
	lvl := max(player_top_level(c), 5)
	placed := 0
	for member in SAMPLE_TEAM {
		hex, ok := sample_placement(c)
		if !ok {
			break
		}
		m := Monster{
			id       = c.next_id,
			creature = creature_make(member.species, lvl, SPECIES[member.species].name, &c.rng),
			pos      = hex,
		}
		c.next_id += 1
		m.creature.player = true
		append(&c.roster, m)
		target := &c.roster[len(c.roster) - 1]
		sets := SPECIES_SETS[member.species]
		arena_apply_set(&target.creature, sets[arena_set_index(member.species, member.set)])
		creature_equip_item(&target.creature, member.item)
		target.creature.hp = target.creature.max_hp
		target.creature.energy = target.creature.energy_max
		target.food = monster_satiety_max(target)
		placed += 1
	}
	colony_notify(c, "%d sample monsters arrive at the entrance.", placed)
	audio_play(.NOTIFY, 1.0)
}
