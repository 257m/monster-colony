package main

// ============================================================================
// SPECIES SETS
//
// Every species can be fought as one of a few **sets**: a loadout of ability,
// item and deck. The Arena's team builder picks a species (weighted by floor, so
// tougher monsters ramp in as you climb) and then rolls one of its sets, so the
// same species turns up as a different opponent each time.
//
// Each set is built around a **synergy** taken from that species' own move pool,
// and the held item and ability are chosen to reinforce it. What each set name
// means:
//
//   Blight       POISON ENGINE. Envenom / Venom / Slime Spit stack Poison, then
//                Catalyst doubles whatever is already there. Venom Sac (+1
//                stack per application). Slow, but Poison phases through Block.
//   Pyre         BURN ENGINE. Flame Burst / Ember Coil / Firestorm stack Burn;
//                Hellfire doubles it and Blackout burns the foe's energy too.
//                Burn is soaked by Block but weakens the burned creature.
//   Bulwark      BLOCK WALL. Guard / Fortify / Rampart / Barrier build Block,
//                then Body Press, Shield Bash and Cataclysm spend it as damage.
//                Barricade keeps Block between turns, Entrench doubles it.
//   Bramble      THORNS SHELL. Bramble Armor / Spike Shell / Ice Wall / Thorn
//                Volley / Bramble Crush. Wins by being hit: Thorns reflect a
//                slice of the attacker's max HP, one stack per hit.
//   Fury         STRENGTH RAMP. Hone / Dragon Dance / Warcry / Rally / Blood
//                Pact stack Strength (each point is +10% damage on *everything*)
//                and Amplify doubles the pile. Bloodstone adds 30% more.
//   Swarm        MULTI-HIT + LEECH. Fang Flurry / Cyclone / Chain Lightning /
//                Riptide / Maelstrom / Gale Force. Every hit rolls lifesteal and
//                on-hit powers separately; Ricochet Charm adds a hit.
//   Ambush       VULNERABLE PAYOFF. Mark / Expose / Frost Bite / Bash apply
//                Vulnerable, then Overwhelm, Avalanche and Frost Nova cash it in
//                (+50% damage taken while it lasts). Weakpoint Lens helps.
//   Tempo        ENERGY AND DRAW. Channel / Capacitor / Adrenaline / Insight /
//                Study / Meditate / Aqua Cutter. Plays many cheap cards a turn,
//                which is also what Metronome and combo bonuses want.
//   Void         EXHAUST PAYOFF. Purge / Gambit / All-In / Overcharge / Study
//                burn through the deck, and Finale deals +4 damage per card
//                exhausted this battle. Scavenger draws on every exhaust.
//   Daze         STUN LOCK. Concuss / Static Shock / Supercell / Dazzle / Slime
//                Spit / Sabotage. Stun fumbles cards out of the foe's hand at
//                the start of its turn; Wounds and Dazed clog it further.
//   Bloom        SUSTAIN GRIND. Photosynthesis / Purify / Antidote / Leech /
//                Devour / Maelstrom / Riptide. Regen each round plus lifesteal,
//                so it outlasts rather than out-damages. Amber Fruit helps.
//   Ruin         LOW-HP GAMBLE. Reckoning scales with the HP you have *lost*,
//                Blood Pact and Overclock pay HP for damage, Cull finishes
//                anything under 40%, All-In spends the whole bank. Grudge Idol.
//   Rubble       DEFENCE SHRED. Sunder / Rock Throw / Fault Line / Expose /
//                Disarm / Depower strip the target's stats and defence, with
//                Earthquake hitting everything at once. Weakpoint Lens helps.
//   Zephyr       SPEED PACKAGE. Agility / Dragon Dance / Updraft / Tailwind /
//                Footwork / Gust. Wins the initiative order and cycles cards
//                fast rather than hitting hard.
//
// Three more are fallbacks, with no synergy core of their own, for a move pool
// too thin to support three real plans. Their names describe the deck:
//
//   Bruiser      the hardest-hitting cards in the pool, Bloodstone on top.
//   Warden       the best Block and defence cards, Grit Charm to survive.
//   Skirmisher   draw, energy and combo cards, Ration Pouch to keep going.
//
// Generated from the move pools as a starting point — edit freely.
// ============================================================================

MAX_SETS :: 3

Species_Set :: struct {
	name:    string,
	ability: Ability,
	item:    Item,
	deck:    []Move_Id,
}

// Hey this is for whenever you look at this again. Can you give me a
// description of what each set name is supposed to do? Like the 
// different types you have.

SPECIES_SETS := [Species_Id][MAX_SETS]Species_Set{
	.Emberling = {
		{name = "Ruin", ability = .Vengeance, item = .Grudge_Idol, deck = []Move_Id{.Reckoning, .Blood_Pact,
			.Cull, .Followup, .Firestorm, .Fuse, .Bash, .Cleave, .Slash, .Flame_Burst}},
		{name = "Fury", ability = .Berserk, item = .Bloodstone, deck = []Move_Id{.Hone, .Warcry, .Blood_Pact,
			.Firestorm, .Fuse, .Followup, .Bash, .Cleave, .Slash, .Flame_Burst}},
		{name = "Ambush", ability = .Momentum, item = .Weakpoint_Lens, deck = []Move_Id{.Mark, .Expose, .Bash,
			.Cull, .Firestorm, .Fuse, .Sunder, .Cleave, .Slash, .Flame_Burst}},
	},
	.Cinderscale = {
		{name = "Ruin", ability = .Berserk, item = .Grudge_Idol, deck = []Move_Id{.Reckoning, .Blood_Pact,
			.Overclock, .Cull, .All_In, .Followup, .Meteor, .Firestorm, .Fuse, .Bash}},
		{name = "Fury", ability = .Berserk, item = .Bloodstone, deck = []Move_Id{.Hone, .Dragon_Dance, .Warcry,
			.Blood_Pact, .Amplify, .Meteor, .Firestorm, .Fuse, .Followup, .Bash}},
		{name = "Void", ability = .Momentum, item = .Grudge_Idol, deck = []Move_Id{.Finale, .All_In, .Metronome,
			.Meteor, .Firestorm, .Fuse, .Bash, .Cleave, .Overwhelm, .Flame_Burst}},
	},
	.Magmalisk = {
		{name = "Fury", ability = .Berserk, item = .Bloodstone, deck = []Move_Id{.Hone, .Dragon_Dance, .Amplify,
			.Demon_Form, .Rage, .Meteor, .Firestorm, .Bash, .Cleave, .Overwhelm}},
		{name = "Pyre", ability = .Momentum, item = .Venom_Sac, deck = []Move_Id{.Flame_Burst, .Ember_Coil,
			.Combustion, .Firestorm, .Meteor, .Bash, .Cleave, .Overwhelm, .Cull, .Ember_Strike}},
		{name = "Void", ability = .Momentum, item = .Grudge_Idol, deck = []Move_Id{.Finale, .All_In, .Metronome,
			.Meteor, .Firestorm, .Bash, .Cleave, .Overwhelm, .Flame_Burst, .Ember_Coil}},
	},
	.Tidepup = {
		{name = "Tempo", ability = .Regenerator, item = .Ration_Pouch, deck = []Move_Id{.Adrenaline, .Meditate,
			.Insight, .Study, .Aqua_Cutter, .Gambit, .Tidal_Crash, .Overwhelm, .Aqua_Jet, .Leech}},
		{name = "Bulwark", ability = .Guardian, item = .Grit_Charm, deck = []Move_Id{.Fortify, .Rampart,
			.Body_Press, .Shield_Bash, .Hold_the_Line, .Guard, .Tidal_Crash, .Iron_Skin, .Footwork, .Overwhelm}},
		{name = "Swarm", ability = .Regenerator, item = .Ricochet_Charm, deck = []Move_Id{.Fang_Flurry, .Cyclone,
			.Tidal_Crash, .Leech, .Overwhelm, .Gambit, .Aqua_Cutter, .Body_Press, .Study, .Aqua_Jet}},
	},
	.Ripfin = {
		{name = "Bulwark", ability = .Guardian, item = .Grit_Charm, deck = []Move_Id{.Fortify, .Rampart, .Barrier,
			.Body_Press, .Shield_Bash, .Entrench, .Hold_the_Line, .Guard, .Tidal_Crash, .Bulwark}},
		{name = "Tempo", ability = .Ironclad, item = .Ration_Pouch, deck = []Move_Id{.Channel, .Overclock,
			.Meditate, .Insight, .Study, .Aqua_Cutter, .Tidal_Crash, .Aqua_Jet, .Leech, .Body_Press}},
		{name = "Swarm", ability = .Ironclad, item = .Ricochet_Charm, deck = []Move_Id{.Fang_Flurry, .Cyclone,
			.Riptide, .Maelstrom, .Tidal_Crash, .Leech, .Overclock, .Aqua_Cutter, .Body_Press, .Study}},
	},
	.Tidewyrm = {
		{name = "Bulwark", ability = .Guardian, item = .Grit_Charm, deck = []Move_Id{.Fortify, .Rampart, .Barrier,
			.Body_Press, .Shield_Bash, .Entrench, .Hold_the_Line, .Guard, .Tidal_Crash, .Bulwark}},
		{name = "Tempo", ability = .Ironclad, item = .Ration_Pouch, deck = []Move_Id{.Channel, .Insight, .Study,
			.Aqua_Cutter, .Tidal_Crash, .Aqua_Jet, .Maelstrom, .Body_Press, .Siphon, .Riptide}},
		{name = "Bloom", ability = .Ironclad, item = .Amber_Fruit, deck = []Move_Id{.Riptide, .Maelstrom,
			.Barrier, .Fortify, .Rampart, .Tidal_Crash, .Hold_the_Line, .Guard, .Bulwark, .Body_Press}},
	},
	.Sproutle = {
		{name = "Bramble", ability = .Regenerator, item = .Spiked_Carapace, deck = []Move_Id{.Bramble_Armor,
			.Spike_Shell, .Thorn_Volley, .Bramble_Crush, .Fortify, .Rampart, .Hold_the_Line, .Guard, .Overwhelm,
			.Body_Press}},
		{name = "Bulwark", ability = .Ironclad, item = .Grit_Charm, deck = []Move_Id{.Fortify, .Rampart,
			.Body_Press, .Hold_the_Line, .Spike_Shell, .Guard, .Bramble_Crush, .Iron_Skin, .Footwork, .Overwhelm}},
		{name = "Blight", ability = .Envenom, item = .Venom_Sac, deck = []Move_Id{.Envenom, .Venom, .Catalyst,
			.Bramble_Crush, .Fortify, .Rampart, .Hold_the_Line, .Overwhelm, .Spike_Shell, .Guard}},
	},
	.Thornbud = {
		{name = "Bulwark", ability = .Ironclad, item = .Grit_Charm, deck = []Move_Id{.Rampart, .Barrier,
			.Body_Press, .Shield_Bash, .Entrench, .Barricade, .Spike_Shell, .Guard, .Bramble_Crush, .Iron_Skin}},
		{name = "Bramble", ability = .Regenerator, item = .Spiked_Carapace, deck = []Move_Id{.Bramble_Armor,
			.Spike_Shell, .Thorn_Volley, .Bramble_Crush, .Barrier, .Rampart, .Guard, .Body_Press, .Reckoning,
			.Cull}},
		{name = "Blight", ability = .Envenom, item = .Venom_Sac, deck = []Move_Id{.Envenom, .Venom, .Toxic,
			.Catalyst, .Barrier, .Bramble_Crush, .Rampart, .Spike_Shell, .Guard, .Body_Press}},
	},
	.Blightbloom = {
		{name = "Bulwark", ability = .Envenom, item = .Grit_Charm, deck = []Move_Id{.Barrier, .Body_Press,
			.Shield_Bash, .Entrench, .Barricade, .Spike_Shell, .Guard, .Bramble_Crush, .Vine_Whip, .Envenom}},
		{name = "Bramble", ability = .Vengeance, item = .Spiked_Carapace, deck = []Move_Id{.Bramble_Armor,
			.Spike_Shell, .Thorn_Volley, .Bramble_Crush, .Barrier, .Guard, .Body_Press, .Vine_Whip, .Envenom,
			.Sunder}},
		{name = "Blight", ability = .Envenom, item = .Venom_Sac, deck = []Move_Id{.Envenom, .Venom, .Toxic,
			.Catalyst, .Barrier, .Bramble_Crush, .Spike_Shell, .Guard, .Body_Press, .Vine_Whip}},
	},
	.Grubling = {
		{name = "Ruin", ability = .Vengeance, item = .Grudge_Idol, deck = []Move_Id{.Reckoning, .Blood_Pact,
			.Overclock, .Cull, .All_In, .Earthquake, .Slash, .Tackle, .Slime_Spit, .Shiv}},
		{name = "Void", ability = .Momentum, item = .Grudge_Idol, deck = []Move_Id{.Finale, .Purge, .All_In,
			.Scavenger, .Earthquake, .Slash, .Shiv, .Blood_Pact, .Reckoning, .Cull}},
		{name = "Bruiser", ability = .Momentum, item = .Bloodstone, deck = []Move_Id{.Earthquake, .Blood_Pact,
			.Slash, .Reckoning, .Cull, .Tackle, .Overclock, .All_In, .Slime_Spit, .Shiv}},
	},
	.Vesperling = {
		{name = "Zephyr", ability = .Swift, item = .Ration_Pouch, deck = []Move_Id{.Agility, .Updraft, .Tailwind,
			.Gust, .Slash, .Overwhelm, .Leech, .Gale_Force, .Siphon, .Fang_Flurry}},
		{name = "Swarm", ability = .Aftershock, item = .Ricochet_Charm, deck = []Move_Id{.Fang_Flurry, .Cyclone,
			.Gale_Force, .Sanguine, .Leech, .Overwhelm, .Slash, .Gust, .Adrenaline, .Tailwind}},
		{name = "Tempo", ability = .Swift, item = .Ration_Pouch, deck = []Move_Id{.Adrenaline, .Tailwind, .Slash,
			.Overwhelm, .Gust, .Leech, .Gale_Force, .Siphon, .Fang_Flurry, .Cyclone}},
	},
	.Rockmite = {
		{name = "Bulwark", ability = .Guardian, item = .Grit_Charm, deck = []Move_Id{.Fortify, .Rampart, .Barrier,
			.Body_Press, .Shield_Bash, .Entrench, .Guard, .Bulwark, .Fault_Line, .Iron_Skin}},
		{name = "Rubble", ability = .Thick_Hide, item = .Weakpoint_Lens, deck = []Move_Id{.Rock_Throw,
			.Fault_Line, .Earthquake, .Barrier, .Fortify, .Slash, .Rampart, .Body_Press, .Guard, .Bulwark}},
		{name = "Bruiser", ability = .Guardian, item = .Bloodstone, deck = []Move_Id{.Fault_Line, .Earthquake,
			.Slash, .Rock_Throw, .Body_Press, .Guard, .Shield_Bash, .Footwork, .Iron_Skin, .Fortify}},
	},
	.Dustwing = {
		{name = "Tempo", ability = .Lucky, item = .Ration_Pouch, deck = []Move_Id{.Adrenaline, .Overclock,
			.Meditate, .Insight, .Study, .Tailwind, .Slash, .Gust, .Gale_Force, .Siphon}},
		{name = "Zephyr", ability = .Swift, item = .Ration_Pouch, deck = []Move_Id{.Agility, .Updraft, .Tailwind,
			.Gust, .Study, .Slash, .Insight, .Overclock, .Gale_Force, .Meditate}},
		{name = "Void", ability = .Aftershock, item = .Grudge_Idol, deck = []Move_Id{.Metronome, .Scavenger,
			.Adrenaline, .Study, .Slash, .Gale_Force, .Gust, .Overclock, .Insight, .Tailwind}},
	},
	.Thornkit = {
		{name = "Bulwark", ability = .Ironclad, item = .Grit_Charm, deck = []Move_Id{.Fortify, .Rampart,
			.Body_Press, .Shield_Bash, .Entrench, .Barricade, .Spike_Shell, .Guard, .Bulwark, .Bramble_Crush}},
		{name = "Bramble", ability = .Vengeance, item = .Spiked_Carapace, deck = []Move_Id{.Bramble_Armor,
			.Spike_Shell, .Thorn_Volley, .Bramble_Crush, .Fortify, .Rampart, .Guard, .Bulwark, .Body_Press,
			.Vine_Whip}},
		{name = "Bruiser", ability = .Vengeance, item = .Bloodstone, deck = []Move_Id{.Bramble_Crush, .Body_Press,
			.Thorn_Volley, .Vine_Whip, .Bramble_Armor, .Spike_Shell, .Iron_Skin, .Entrench, .Shield_Bash,
			.Barricade}},
	},
	.Mossling = {
		{name = "Bloom", ability = .Regenerator, item = .Amber_Fruit, deck = []Move_Id{.Photosynthesis, .Purify,
			.Antidote, .Barrier, .Fortify, .Rampart, .Bramble_Crush, .Guard, .Bulwark, .Vine_Whip}},
		{name = "Bulwark", ability = .Guardian, item = .Grit_Charm, deck = []Move_Id{.Fortify, .Rampart, .Barrier,
			.Guard, .Bulwark, .Bramble_Crush, .Footwork, .Vine_Whip, .Thorn_Volley, .Meditate}},
		{name = "Bramble", ability = .Guardian, item = .Spiked_Carapace, deck = []Move_Id{.Thorn_Volley,
			.Bramble_Crush, .Barrier, .Fortify, .Rampart, .Guard, .Bulwark, .Vine_Whip, .Meditate, .Purify}},
	},
	.Bloomcap = {
		{name = "Blight", ability = .Envenom, item = .Venom_Sac, deck = []Move_Id{.Envenom, .Venom, .Toxic,
			.Catalyst, .Venom_Fang, .Slime_Spit, .Spike_Shell, .Spike_Shell, .Guard, .Vine_Whip}},
		{name = "Bramble", ability = .Vengeance, item = .Spiked_Carapace, deck = []Move_Id{.Bramble_Armor,
			.Spike_Shell, .Guard, .Venom_Fang, .Vine_Whip, .Slime_Spit, .Envenom, .Venom, .Catalyst, .Toxic}},
		{name = "Bruiser", ability = .Envenom, item = .Bloodstone, deck = []Move_Id{.Venom_Fang, .Vine_Whip,
			.Slime_Spit, .Envenom, .Venom, .Catalyst, .Toxic, .Haze, .Bramble_Armor, .Combustion}},
	},
	.Barkhound = {
		{name = "Bulwark", ability = .Ironclad, item = .Grit_Charm, deck = []Move_Id{.Fortify, .Rampart,
			.Body_Press, .Shield_Bash, .Entrench, .Juggernaut, .Guard, .Bulwark, .Bramble_Crush, .Fault_Line}},
		{name = "Rubble", ability = .Thick_Hide, item = .Weakpoint_Lens, deck = []Move_Id{.Rock_Throw,
			.Fault_Line, .Earthquake, .Bramble_Crush, .Bash, .Fortify, .Rampart, .Body_Press, .Vine_Whip, .All_In}},
		{name = "Bramble", ability = .Thick_Hide, item = .Spiked_Carapace, deck = []Move_Id{.Thorn_Volley,
			.Bramble_Crush, .Fortify, .Rampart, .Fault_Line, .Guard, .Earthquake, .Bulwark, .Bash, .Rock_Throw}},
	},
	.Bubblet = {
		{name = "Bulwark", ability = .Guardian, item = .Grit_Charm, deck = []Move_Id{.Fortify, .Rampart, .Barrier,
			.Body_Press, .Shield_Bash, .Guard, .Tidal_Crash, .Bulwark, .Footwork, .Aqua_Jet}},
		{name = "Tempo", ability = .Guardian, item = .Ration_Pouch, deck = []Move_Id{.Meditate, .Aqua_Cutter,
			.Tidal_Crash, .Aqua_Jet, .Body_Press, .Riptide, .Guard, .Shield_Bash, .Footwork, .Rampart}},
		{name = "Bruiser", ability = .Guardian, item = .Bloodstone, deck = []Move_Id{.Tidal_Crash, .Body_Press,
			.Riptide, .Aqua_Jet, .Aqua_Cutter, .Guard, .Shield_Bash, .Footwork, .Fortify, .Rampart}},
	},
	.Ripjaw = {
		{name = "Swarm", ability = .Aftershock, item = .Ricochet_Charm, deck = []Move_Id{.Fang_Flurry, .Cyclone,
			.Riptide, .Sanguine, .Tidal_Crash, .Leech, .Overwhelm, .Slash, .Aqua_Cutter, .Aqua_Jet}},
		{name = "Void", ability = .Aftershock, item = .Grudge_Idol, deck = []Move_Id{.Metronome, .Scavenger,
			.Adrenaline, .Tidal_Crash, .Overwhelm, .Aqua_Cutter, .Shiv, .Slash, .Aqua_Jet, .Leech}},
		{name = "Tempo", ability = .Vampiric, item = .Ration_Pouch, deck = []Move_Id{.Adrenaline, .Aqua_Cutter,
			.Tidal_Crash, .Slash, .Overwhelm, .Aqua_Jet, .Leech, .Shiv, .Riptide, .Fang_Flurry}},
	},
	.Tidecaller = {
		{name = "Ambush", ability = .Ironclad, item = .Weakpoint_Lens, deck = []Move_Id{.Mark, .Frost_Bite,
			.Avalanche, .Frost_Nova, .Tidal_Crash, .Aqua_Jet, .Aqua_Cutter, .Snowball, .Concuss, .Riptide}},
		{name = "Daze", ability = .Resilient, item = .Cleansing_Bloom, deck = []Move_Id{.Concuss, .Dazzle,
			.Depower, .Tidal_Crash, .Avalanche, .Frost_Nova, .Haze, .Aqua_Jet, .Aqua_Cutter, .Frost_Bite}},
		{name = "Tempo", ability = .Ironclad, item = .Ration_Pouch, deck = []Move_Id{.Meditate, .Aqua_Cutter,
			.Tidal_Crash, .Avalanche, .Frost_Nova, .Aqua_Jet, .Frost_Bite, .Snowball, .Concuss, .Riptide}},
	},
	.Abyssal_Fry = {
		{name = "Blight", ability = .Envenom, item = .Venom_Sac, deck = []Move_Id{.Envenom, .Venom, .Toxic,
			.Catalyst, .Venom_Fang, .Slime_Spit, .Tidal_Crash, .Overwhelm, .Guard, .Aqua_Jet}},
		{name = "Bloom", ability = .Vampiric, item = .Amber_Fruit, deck = []Move_Id{.Leech, .Riptide,
			.Tidal_Crash, .Venom_Fang, .Guard, .Overwhelm, .Aqua_Jet, .Slime_Spit, .Envenom, .Venom}},
		{name = "Swarm", ability = .Vampiric, item = .Ricochet_Charm, deck = []Move_Id{.Fang_Flurry, .Riptide,
			.Tidal_Crash, .Leech, .Venom_Fang, .Overwhelm, .Aqua_Jet, .Slime_Spit, .Envenom, .Venom}},
	},
	.Gloomling = {
		{name = "Ruin", ability = .Vengeance, item = .Grudge_Idol, deck = []Move_Id{.Reckoning, .Blood_Pact,
			.Overclock, .Cull, .All_In, .Slash, .Tackle, .Sunder, .Finale, .Mark}},
		{name = "Rubble", ability = .Predator, item = .Weakpoint_Lens, deck = []Move_Id{.Sunder, .Expose, .Disarm,
			.Slash, .Blood_Pact, .Reckoning, .Cull, .Tackle, .Overclock, .All_In}},
		{name = "Ambush", ability = .Predator, item = .Weakpoint_Lens, deck = []Move_Id{.Mark, .Expose, .Cull,
			.Sunder, .Slash, .Blood_Pact, .Reckoning, .Tackle, .Overclock, .All_In}},
	},
	.Crypt_Rat = {
		{name = "Blight", ability = .Envenom, item = .Venom_Sac, deck = []Move_Id{.Envenom, .Venom, .Toxic,
			.Catalyst, .Venom_Fang, .Overwhelm, .Guard, .Tackle, .Leech, .Fang_Flurry}},
		{name = "Swarm", ability = .Vampiric, item = .Ricochet_Charm, deck = []Move_Id{.Fang_Flurry, .Cyclone,
			.Leech, .Venom_Fang, .Overwhelm, .Tackle, .Envenom, .Venom, .Catalyst, .Sabotage}},
		{name = "Bruiser", ability = .Vampiric, item = .Bloodstone, deck = []Move_Id{.Venom_Fang, .Overwhelm,
			.Fang_Flurry, .Cyclone, .Tackle, .Envenom, .Leech, .Venom, .Catalyst, .Sabotage}},
	},
	.Wispling = {
		{name = "Tempo", ability = .Lucky, item = .Ration_Pouch, deck = []Move_Id{.Capacitor, .Adrenaline,
			.Overclock, .Insight, .Study, .Tailwind, .Supercell, .Thunderbolt, .Slash, .Gust}},
		{name = "Daze", ability = .Swift, item = .Cleansing_Bloom, deck = []Move_Id{.Concuss, .Static_Shock,
			.Supercell, .Dazzle, .Disarm, .Thunderbolt, .Slash, .Gale_Force, .Gust, .Zap}},
		{name = "Zephyr", ability = .Swift, item = .Ration_Pouch, deck = []Move_Id{.Agility, .Updraft, .Tailwind,
			.Gust, .Supercell, .Thunderbolt, .Study, .Slash, .Insight, .Zap}},
	},
	.Sporeling = {
		{name = "Blight", ability = .Envenom, item = .Venom_Sac, deck = []Move_Id{.Envenom, .Venom, .Toxic,
			.Catalyst, .Venom_Fang, .Slime_Spit, .Bramble_Crush, .Spike_Shell, .Slash, .Guard}},
		{name = "Bramble", ability = .Envenom, item = .Spiked_Carapace, deck = []Move_Id{.Bramble_Armor,
			.Spike_Shell, .Bramble_Crush, .Guard, .Venom_Fang, .Slash, .Sting, .Slime_Spit, .Envenom, .Venom}},
		{name = "Bloom", ability = .Regenerator, item = .Amber_Fruit, deck = []Move_Id{.Photosynthesis, .Purify,
			.Bramble_Crush, .Spike_Shell, .Venom_Fang, .Guard, .Slash, .Sting, .Slime_Spit, .Envenom}},
	},
	.Capmaw = {
		{name = "Blight", ability = .Envenom, item = .Venom_Sac, deck = []Move_Id{.Envenom, .Venom, .Toxic,
			.Catalyst, .Venom_Fang, .Slime_Spit, .Bramble_Crush, .Overwhelm, .Guard, .Vine_Whip}},
		{name = "Bloom", ability = .Regenerator, item = .Amber_Fruit, deck = []Move_Id{.Photosynthesis, .Leech,
			.Bramble_Crush, .Venom_Fang, .Guard, .Overwhelm, .Vine_Whip, .Slime_Spit, .Envenom, .Venom}},
		{name = "Swarm", ability = .Vampiric, item = .Ricochet_Charm, deck = []Move_Id{.Fang_Flurry, .Sanguine,
			.Bramble_Crush, .Leech, .Venom_Fang, .Overwhelm, .Vine_Whip, .Slime_Spit, .Envenom, .Venom}},
	},
	.Sentinel = {
		{name = "Bulwark", ability = .Guardian, item = .Grit_Charm, deck = []Move_Id{.Fortify, .Rampart, .Barrier,
			.Body_Press, .Shield_Bash, .Entrench, .Guard, .Bulwark, .Iron_Skin, .Footwork}},
		{name = "Daze", ability = .Intimidate, item = .Cleansing_Bloom, deck = []Move_Id{.Dazzle, .Disarm, .Slash,
			.Body_Press, .Guard, .Shield_Bash, .Fortify, .Barrier, .Entrench, .Footwork}},
		{name = "Bruiser", ability = .Guardian, item = .Bloodstone, deck = []Move_Id{.Slash, .Body_Press, .Rally,
			.Guard, .Shield_Bash, .Fortify, .Barrier, .Entrench, .Footwork, .Rampart}},
	},
	.Relic_Hound = {
		{name = "Bulwark", ability = .Ironclad, item = .Grit_Charm, deck = []Move_Id{.Fortify, .Rampart,
			.Body_Press, .Shield_Bash, .Entrench, .Juggernaut, .Guard, .Fault_Line, .Iron_Skin, .Earthquake}},
		{name = "Rubble", ability = .Thick_Hide, item = .Weakpoint_Lens, deck = []Move_Id{.Rock_Throw,
			.Fault_Line, .Earthquake, .Cleave, .Bash, .Overwhelm, .Fortify, .Rampart, .Body_Press, .All_In}},
		{name = "Ambush", ability = .Predator, item = .Weakpoint_Lens, deck = []Move_Id{.Bash, .Overwhelm,
			.Fault_Line, .Earthquake, .Cleave, .Rock_Throw, .Body_Press, .All_In, .Iron_Skin, .Shield_Bash}},
	},
	.Hexling = {
		{name = "Daze", ability = .Swift, item = .Cleansing_Bloom, deck = []Move_Id{.Concuss, .Static_Shock,
			.Supercell, .Dazzle, .Sabotage, .Disarm, .Thunderbolt, .Depower, .Slash, .Zap}},
		{name = "Tempo", ability = .Lucky, item = .Ration_Pouch, deck = []Move_Id{.Capacitor, .Overclock,
			.Insight, .Supercell, .Thunderbolt, .Slash, .Zap, .All_In, .Overcharge, .Short_Circuit}},
		{name = "Rubble", ability = .Swift, item = .Weakpoint_Lens, deck = []Move_Id{.Disarm, .Depower,
			.Supercell, .Thunderbolt, .Slash, .Zap, .All_In, .Overclock, .Static_Shock, .Overcharge}},
	},
	.Snowpup = {
		{name = "Ambush", ability = .Predator, item = .Weakpoint_Lens, deck = []Move_Id{.Mark, .Expose,
			.Frost_Bite, .Bash, .Overwhelm, .Avalanche, .Frost_Nova, .Sunder, .Cleave, .Slash}},
		{name = "Rubble", ability = .Swift, item = .Weakpoint_Lens, deck = []Move_Id{.Sunder, .Expose, .Cleave,
			.Avalanche, .Bash, .Overwhelm, .Frost_Nova, .Slash, .Snowball, .Frost_Bite}},
		{name = "Bruiser", ability = .Momentum, item = .Bloodstone, deck = []Move_Id{.Avalanche, .Bash, .Cleave,
			.Overwhelm, .Frost_Nova, .Slash, .Hone, .Snowball, .Frost_Bite, .All_In}},
	},
	.Frostmaw = {
		{name = "Bulwark", ability = .Ironclad, item = .Grit_Charm, deck = []Move_Id{.Rampart, .Body_Press,
			.Shield_Bash, .Entrench, .Juggernaut, .Ice_Wall, .Guard, .Fault_Line, .Iron_Skin, .Avalanche}},
		{name = "Ambush", ability = .Predator, item = .Weakpoint_Lens, deck = []Move_Id{.Frost_Bite, .Bash,
			.Overwhelm, .Avalanche, .Frost_Nova, .Fault_Line, .Earthquake, .Rock_Throw, .Body_Press, .Snowball}},
		{name = "Rubble", ability = .Thick_Hide, item = .Weakpoint_Lens, deck = []Move_Id{.Rock_Throw,
			.Fault_Line, .Earthquake, .Avalanche, .Bash, .Overwhelm, .Frost_Nova, .Rampart, .Body_Press, .Snowball}},
	},
	.Glacierling = {
		{name = "Bulwark", ability = .Guardian, item = .Grit_Charm, deck = []Move_Id{.Fortify, .Rampart, .Barrier,
			.Body_Press, .Entrench, .Juggernaut, .Ice_Wall, .Guard, .Tidal_Crash, .Bulwark}},
		{name = "Ambush", ability = .Ironclad, item = .Weakpoint_Lens, deck = []Move_Id{.Avalanche, .Frost_Nova,
			.Tidal_Crash, .Body_Press, .Snowball, .Aqua_Jet, .Guard, .Fortify, .Barrier, .Footwork}},
		{name = "Bruiser", ability = .Ironclad, item = .Bloodstone, deck = []Move_Id{.Tidal_Crash, .Avalanche,
			.Frost_Nova, .Body_Press, .Snowball, .Aqua_Jet, .Guard, .Fortify, .Barrier, .Footwork}},
	},
	.Vinecat = {
		{name = "Swarm", ability = .Aftershock, item = .Ricochet_Charm, deck = []Move_Id{.Fang_Flurry, .Cyclone,
			.Sanguine, .Bramble_Crush, .Leech, .Thorn_Volley, .Overwhelm, .Slash, .Vine_Whip, .Shiv}},
		{name = "Bramble", ability = .Aftershock, item = .Spiked_Carapace, deck = []Move_Id{.Thorn_Volley,
			.Bramble_Crush, .Guard, .Overwhelm, .Fang_Flurry, .Cyclone, .Slash, .Vine_Whip, .Leech, .Shiv}},
		{name = "Bruiser", ability = .Predator, item = .Bloodstone, deck = []Move_Id{.Bramble_Crush, .Overwhelm,
			.Slash, .Fang_Flurry, .Cyclone, .Thorn_Volley, .Vine_Whip, .Leech, .Shiv, .Agility}},
	},
	.Venomtail = {
		{name = "Blight", ability = .Envenom, item = .Venom_Sac, deck = []Move_Id{.Envenom, .Venom, .Toxic,
			.Catalyst, .Venom_Fang, .Slime_Spit, .Overwhelm, .Guard, .Sting, .Fang_Flurry}},
		{name = "Daze", ability = .Envenom, item = .Cleansing_Bloom, deck = []Move_Id{.Dazzle, .Slime_Spit,
			.Sabotage, .Venom_Fang, .Overwhelm, .Haze, .Sting, .Envenom, .Venom, .Fang_Flurry}},
		{name = "Swarm", ability = .Aftershock, item = .Ricochet_Charm, deck = []Move_Id{.Fang_Flurry, .Cyclone,
			.Venom_Fang, .Overwhelm, .Sting, .Slime_Spit, .Envenom, .Venom, .Catalyst, .Toxic}},
	},
	.Pouncer = {
		{name = "Zephyr", ability = .Swift, item = .Ration_Pouch, deck = []Move_Id{.Agility, .Updraft, .Tailwind,
			.Gust, .Bramble_Crush, .Overwhelm, .Vine_Whip, .Frost_Bite, .All_In, .Sunder}},
		{name = "Ambush", ability = .Predator, item = .Weakpoint_Lens, deck = []Move_Id{.Mark, .Expose,
			.Frost_Bite, .Overwhelm, .Bramble_Crush, .Sunder, .Gale_Force, .Vine_Whip, .Gust, .All_In}},
		{name = "Swarm", ability = .Aftershock, item = .Ricochet_Charm, deck = []Move_Id{.Fang_Flurry, .Cyclone,
			.Gale_Force, .Bramble_Crush, .Thorn_Volley, .Overwhelm, .Vine_Whip, .Gust, .Frost_Bite, .All_In}},
	},
	.Magmite = {
		{name = "Pyre", ability = .Momentum, item = .Venom_Sac, deck = []Move_Id{.Flame_Burst, .Ember_Coil,
			.Combustion, .Firestorm, .Fuse, .Cleave, .Overwhelm, .Ember_Strike, .All_In, .Mark}},
		{name = "Fury", ability = .Berserk, item = .Bloodstone, deck = []Move_Id{.Hone, .Warcry, .Firestorm,
			.Fuse, .Cleave, .Overwhelm, .Flame_Burst, .Ember_Coil, .Ember_Strike, .All_In}},
		{name = "Ambush", ability = .Momentum, item = .Weakpoint_Lens, deck = []Move_Id{.Mark, .Overwhelm,
			.Firestorm, .Fuse, .Cleave, .Flame_Burst, .Ember_Coil, .Ember_Strike, .All_In, .Combustion}},
	},
	.Cinderwing = {
		{name = "Zephyr", ability = .Swift, item = .Ration_Pouch, deck = []Move_Id{.Agility, .Dragon_Dance,
			.Updraft, .Gust, .Fuse, .Firestorm, .Ember_Coil, .Overwhelm, .Ember_Strike, .All_In}},
		{name = "Pyre", ability = .Berserk, item = .Venom_Sac, deck = []Move_Id{.Flame_Burst, .Ember_Coil,
			.Combustion, .Firestorm, .Fuse, .Overwhelm, .Gale_Force, .Ember_Strike, .Gust, .All_In}},
		{name = "Void", ability = .Aftershock, item = .Grudge_Idol, deck = []Move_Id{.All_In, .Metronome,
			.Firestorm, .Fuse, .Overwhelm, .Flame_Burst, .Ember_Coil, .Gale_Force, .Ember_Strike, .Gust}},
	},
	.Slagbeast = {
		{name = "Rubble", ability = .Intimidate, item = .Weakpoint_Lens, deck = []Move_Id{.Rock_Throw,
			.Fault_Line, .Earthquake, .Cleave, .Firestorm, .Bash, .Overwhelm, .Rampart, .Body_Press, .Ember_Strike}},
		{name = "Fury", ability = .Berserk, item = .Bloodstone, deck = []Move_Id{.Hone, .Warcry, .Amplify,
			.Fault_Line, .Firestorm, .Earthquake, .Bash, .Cleave, .Overwhelm, .Rock_Throw}},
		{name = "Bulwark", ability = .Thick_Hide, item = .Grit_Charm, deck = []Move_Id{.Rampart, .Body_Press,
			.Juggernaut, .Guard, .Fault_Line, .Firestorm, .Earthquake, .Bash, .Cleave, .Overwhelm}},
	},
	.Sandfang = {
		{name = "Rubble", ability = .Thick_Hide, item = .Weakpoint_Lens, deck = []Move_Id{.Sunder, .Rock_Throw,
			.Fault_Line, .Earthquake, .Cleave, .Bash, .Overwhelm, .Sand_Attack, .Followup, .All_In}},
		{name = "Fury", ability = .Momentum, item = .Bloodstone, deck = []Move_Id{.Hone, .Warcry, .Amplify,
			.Fault_Line, .Followup, .Earthquake, .Bash, .Cleave, .Overwhelm, .Rock_Throw}},
		{name = "Ambush", ability = .Predator, item = .Weakpoint_Lens, deck = []Move_Id{.Bash, .Overwhelm,
			.Fault_Line, .Earthquake, .Sunder, .Cleave, .Rock_Throw, .Sand_Attack, .Followup, .All_In}},
	},
	.Sparkit = {
		{name = "Tempo", ability = .Lucky, item = .Ration_Pouch, deck = []Move_Id{.Capacitor, .Adrenaline,
			.Overclock, .Insight, .Study, .Supercell, .Thunderbolt, .Slash, .Zap, .All_In}},
		{name = "Void", ability = .Aftershock, item = .Grudge_Idol, deck = []Move_Id{.All_In, .Overcharge,
			.Adrenaline, .Supercell, .Thunderbolt, .Study, .Slash, .Zap, .Overclock, .Static_Shock}},
		{name = "Daze", ability = .Swift, item = .Cleansing_Bloom, deck = []Move_Id{.Concuss, .Static_Shock,
			.Supercell, .Thunderbolt, .Slash, .Zap, .All_In, .Overclock, .Overcharge, .Short_Circuit}},
	},
	.Crystalfin = {
		{name = "Ambush", ability = .Swift, item = .Weakpoint_Lens, deck = []Move_Id{.Frost_Bite, .Avalanche,
			.Frost_Nova, .Tidal_Crash, .Supercell, .Thunderbolt, .Slash, .Snowball, .Zap, .All_In}},
		{name = "Daze", ability = .Swift, item = .Cleansing_Bloom, deck = []Move_Id{.Concuss, .Static_Shock,
			.Supercell, .Tidal_Crash, .Avalanche, .Thunderbolt, .Frost_Nova, .Slash, .Snowball, .Zap}},
		{name = "Bruiser", ability = .Ironclad, item = .Bloodstone, deck = []Move_Id{.Tidal_Crash, .Avalanche,
			.Supercell, .Thunderbolt, .Frost_Nova, .Slash, .Chain_Lightning, .Snowball, .Zap, .All_In}},
	},
	.Rotshell = {
		{name = "Blight", ability = .Envenom, item = .Venom_Sac, deck = []Move_Id{.Envenom, .Venom, .Catalyst,
			.Venom_Fang, .Slime_Spit, .Earthquake, .Overwhelm, .Slash, .Guard, .Blood_Pact}},
		{name = "Ruin", ability = .Vengeance, item = .Grudge_Idol, deck = []Move_Id{.Reckoning, .Blood_Pact,
			.Cull, .All_In, .Venom_Fang, .Earthquake, .Overwhelm, .Slash, .Slime_Spit, .Envenom}},
		{name = "Void", ability = .Resilient, item = .Grudge_Idol, deck = []Move_Id{.Finale, .All_In, .Scavenger,
			.Venom_Fang, .Earthquake, .Overwhelm, .Slash, .Blood_Pact, .Reckoning, .Cull}},
	},
	.Nightwing = {
		{name = "Swarm", ability = .Aftershock, item = .Ricochet_Charm, deck = []Move_Id{.Fang_Flurry, .Cyclone,
			.Gale_Force, .Sanguine, .Leech, .Overwhelm, .Slash, .Gust, .All_In, .Shiv}},
		{name = "Zephyr", ability = .Swift, item = .Ration_Pouch, deck = []Move_Id{.Updraft, .Tailwind, .Gust,
			.Slash, .Overwhelm, .All_In, .Leech, .Shiv, .Gale_Force, .Fang_Flurry}},
		{name = "Void", ability = .Aftershock, item = .Grudge_Idol, deck = []Move_Id{.All_In, .Scavenger,
			.Adrenaline, .Overwhelm, .Shiv, .Slash, .Gale_Force, .Gust, .Leech, .Tailwind}},
	},
	.Thornmaw = {
		{name = "Bulwark", ability = .Ironclad, item = .Grit_Charm, deck = []Move_Id{.Rampart, .Body_Press,
			.Shield_Bash, .Entrench, .Barricade, .Spike_Shell, .Guard, .Bulwark, .Bramble_Crush, .Overwhelm}},
		{name = "Bramble", ability = .Vengeance, item = .Spiked_Carapace, deck = []Move_Id{.Bramble_Armor,
			.Spike_Shell, .Thorn_Volley, .Bramble_Crush, .Rampart, .Guard, .Bulwark, .Overwhelm, .Body_Press,
			.Vine_Whip}},
		{name = "Bruiser", ability = .Vengeance, item = .Bloodstone, deck = []Move_Id{.Bramble_Crush, .Overwhelm,
			.Body_Press, .Thorn_Volley, .Vine_Whip, .All_In, .Bramble_Armor, .Spike_Shell, .Shield_Bash, .Entrench}},
	},
	.Bubblord = {
		{name = "Bulwark", ability = .Guardian, item = .Grit_Charm, deck = []Move_Id{.Rampart, .Barrier,
			.Body_Press, .Shield_Bash, .Barricade, .Tidal_Crash, .Bulwark, .Footwork, .Aqua_Jet, .Aqua_Cutter}},
		{name = "Bruiser", ability = .Guardian, item = .Bloodstone, deck = []Move_Id{.Tidal_Crash, .Body_Press,
			.Aqua_Jet, .Aqua_Cutter, .All_In, .Rally, .Barrier, .Shield_Bash, .Footwork, .Rampart}},
		{name = "Warden", ability = .Guardian, item = .Grit_Charm, deck = []Move_Id{.Barrier, .Rampart, .Bulwark,
			.Tidal_Crash, .Footwork, .Body_Press, .Aqua_Jet, .Aqua_Cutter, .Shield_Bash, .All_In}},
	},
	.Frostfang = {
		{name = "Ambush", ability = .Predator, item = .Weakpoint_Lens, deck = []Move_Id{.Mark, .Expose,
			.Frost_Bite, .Bash, .Overwhelm, .Avalanche, .Meteor, .Frost_Nova, .Sunder, .Cleave}},
		{name = "Rubble", ability = .Thick_Hide, item = .Weakpoint_Lens, deck = []Move_Id{.Sunder, .Expose,
			.Cleave, .Meteor, .Avalanche, .Bash, .Overwhelm, .Frost_Nova, .Snowball, .Frost_Bite}},
		{name = "Bruiser", ability = .Predator, item = .Bloodstone, deck = []Move_Id{.Meteor, .Avalanche, .Bash,
			.Cleave, .Overwhelm, .Frost_Nova, .Snowball, .Frost_Bite, .All_In, .Sunder}},
	},
	.Magmaw = {
		{name = "Pyre", ability = .Momentum, item = .Venom_Sac, deck = []Move_Id{.Flame_Burst, .Ember_Coil,
			.Combustion, .Firestorm, .Meteor, .Fuse, .Overwhelm, .Ember_Strike, .All_In, .Hone}},
		{name = "Fury", ability = .Berserk, item = .Bloodstone, deck = []Move_Id{.Hone, .Amplify, .Meteor,
			.Firestorm, .Fuse, .Overwhelm, .Flame_Burst, .Ember_Coil, .Ember_Strike, .All_In}},
		{name = "Ambush", ability = .Momentum, item = .Weakpoint_Lens, deck = []Move_Id{.Mark, .Overwhelm,
			.Meteor, .Firestorm, .Fuse, .Flame_Burst, .Ember_Coil, .Ember_Strike, .All_In, .Combustion}},
	},
	.Sporelord = {
		{name = "Blight", ability = .Envenom, item = .Venom_Sac, deck = []Move_Id{.Envenom, .Venom, .Toxic,
			.Catalyst, .Venom_Fang, .Slime_Spit, .Bramble_Crush, .Overwhelm, .Guard, .Sting}},
		{name = "Bloom", ability = .Regenerator, item = .Amber_Fruit, deck = []Move_Id{.Photosynthesis, .Purify,
			.Leech, .Bramble_Crush, .Venom_Fang, .Guard, .Overwhelm, .Sting, .Slime_Spit, .Envenom}},
		{name = "Bramble", ability = .Envenom, item = .Spiked_Carapace, deck = []Move_Id{.Bramble_Armor,
			.Bramble_Crush, .Guard, .Venom_Fang, .Overwhelm, .Sting, .Slime_Spit, .Envenom, .Leech, .Venom}},
	},
	.Voltail = {
		{name = "Tempo", ability = .Lucky, item = .Ration_Pouch, deck = []Move_Id{.Capacitor, .Adrenaline,
			.Overclock, .Meteor, .Supercell, .Thunderbolt, .Slash, .Zap, .All_In, .Overcharge}},
		{name = "Void", ability = .Aftershock, item = .Grudge_Idol, deck = []Move_Id{.All_In, .Overcharge,
			.Adrenaline, .Meteor, .Supercell, .Thunderbolt, .Slash, .Zap, .Overclock, .Static_Shock}},
		{name = "Daze", ability = .Swift, item = .Cleansing_Bloom, deck = []Move_Id{.Concuss, .Static_Shock,
			.Supercell, .Meteor, .Thunderbolt, .Slash, .Zap, .Overclock, .All_In, .Overcharge}},
	},
	.Deep_One = {
		{name = "Bulwark", ability = .Guardian, item = .Grit_Charm, deck = []Move_Id{.Fortify, .Rampart, .Barrier,
			.Iron_Skin, .Devour, .Bash, .Bash, .Cleave, .Overwhelm, .Slash}},
		{name = "Rubble", ability = .Guardian, item = .Weakpoint_Lens, deck = []Move_Id{.Depower, .Cleave,
			.Devour, .Barrier, .Bash, .Bash, .Overwhelm, .Fortify, .Slash, .Rampart}},
		{name = "Ambush", ability = .Vengeance, item = .Weakpoint_Lens, deck = []Move_Id{.Bash, .Overwhelm,
			.Devour, .Cleave, .Slash, .Fortify, .Barrier, .Rampart, .Iron_Skin, .Hone}},
	},
	.Boss_Leviathan = {
		{name = "Bulwark", ability = .Guardian, item = .Grit_Charm, deck = []Move_Id{.Fortify, .Barrier,
			.Body_Press, .Entrench, .Guard, .Tidal_Crash, .Maelstrom, .Aqua_Jet, .Aqua_Cutter, .Leech}},
		{name = "Swarm", ability = .Abyssal, item = .Ricochet_Charm, deck = []Move_Id{.Fang_Flurry, .Cyclone,
			.Maelstrom, .Sanguine, .Tidal_Crash, .Leech, .Aqua_Cutter, .Body_Press, .Aqua_Jet, .Barrier}},
		{name = "Bloom", ability = .Regenerator, item = .Amber_Fruit, deck = []Move_Id{.Leech, .Maelstrom,
			.Barrier, .Fortify, .Tidal_Crash, .Guard, .Body_Press, .Aqua_Jet, .Aqua_Cutter, .Fang_Flurry}},
	},
	.Boss_Infernal = {
		{name = "Pyre", ability = .Inferno, item = .Venom_Sac, deck = []Move_Id{.Flame_Burst, .Ember_Coil,
			.Combustion, .Hellfire, .Firestorm, .Cleave, .Overwhelm, .Ember_Strike, .Mark, .Expose}},
		{name = "Ambush", ability = .Inferno, item = .Weakpoint_Lens, deck = []Move_Id{.Mark, .Expose, .Overwhelm,
			.Firestorm, .Cleave, .Hellfire, .Flame_Burst, .Ember_Coil, .Ember_Strike, .Combustion}},
		{name = "Rubble", ability = .Inferno, item = .Weakpoint_Lens, deck = []Move_Id{.Expose, .Cleave,
			.Firestorm, .Hellfire, .Overwhelm, .Flame_Burst, .Ember_Coil, .Ember_Strike, .Guard, .Combustion}},
	},
	.Boss_Titan = {
		{name = "Bulwark", ability = .Guardian, item = .Grit_Charm, deck = []Move_Id{.Fortify, .Rampart, .Barrier,
			.Body_Press, .Shield_Bash, .Entrench, .Guard, .Fault_Line, .Iron_Skin, .Cataclysm}},
		{name = "Rubble", ability = .Thick_Hide, item = .Weakpoint_Lens, deck = []Move_Id{.Fault_Line, .Depower,
			.Earthquake, .Cleave, .Barrier, .Bash, .Overwhelm, .Fortify, .Rampart, .Body_Press}},
		{name = "Ambush", ability = .Colossus, item = .Weakpoint_Lens, deck = []Move_Id{.Bash, .Overwhelm,
			.Fault_Line, .Earthquake, .Cleave, .Body_Press, .Cataclysm, .Shield_Bash, .Entrench, .Barricade}},
	},
	.Boss_Sovereign = {
		{name = "Zephyr", ability = .Swift, item = .Ration_Pouch, deck = []Move_Id{.Agility, .Dragon_Dance,
			.Updraft, .Gust, .Supercell, .Decree, .Thunderbolt, .Overwhelm, .Zap, .Short_Circuit}},
		{name = "Daze", ability = .Swift, item = .Cleansing_Bloom, deck = []Move_Id{.Concuss, .Static_Shock,
			.Supercell, .Depower, .Decree, .Thunderbolt, .Overwhelm, .Gale_Force, .Haze, .Zap}},
		{name = "Fury", ability = .Berserk, item = .Bloodstone, deck = []Move_Id{.Dragon_Dance, .Rally,
			.Supercell, .Decree, .Thunderbolt, .Gale_Force, .Overwhelm, .Cyclone, .Zap, .Gust}},
	},
	.Ashfang = {
		{name = "Zephyr", ability = .Swift, item = .Ration_Pouch, deck = []Move_Id{.Agility, .Dragon_Dance,
			.Updraft, .Gust, .Fuse, .Firestorm, .Cleave, .Slash, .Overwhelm, .Hellfire}},
		{name = "Pyre", ability = .Momentum, item = .Venom_Sac, deck = []Move_Id{.Flame_Burst, .Combustion,
			.Hellfire, .Firestorm, .Fuse, .Cleave, .Overwhelm, .Slash, .Gale_Force, .Ember_Strike}},
		{name = "Fury", ability = .Momentum, item = .Bloodstone, deck = []Move_Id{.Hone, .Dragon_Dance, .Amplify,
			.Firestorm, .Fuse, .Followup, .Cleave, .Gale_Force, .Overwhelm, .Hellfire}},
	},
	.Stormwing = {
		{name = "Tempo", ability = .Lucky, item = .Ration_Pouch, deck = []Move_Id{.Capacitor, .Adrenaline, .Study,
			.Tailwind, .Followup, .Supercell, .Thunderbolt, .Zap, .Gust, .Overcharge}},
		{name = "Zephyr", ability = .Swift, item = .Ration_Pouch, deck = []Move_Id{.Agility, .Updraft, .Tailwind,
			.Gust, .Supercell, .Thunderbolt, .Study, .Zap, .Overcharge, .Followup}},
		{name = "Daze", ability = .Swift, item = .Cleansing_Bloom, deck = []Move_Id{.Concuss, .Static_Shock,
			.Supercell, .Dazzle, .Thunderbolt, .Gale_Force, .Zap, .Gust, .Overcharge, .Followup}},
	},
	.Bogmaw = {
		{name = "Bloom", ability = .Regenerator, item = .Amber_Fruit, deck = []Move_Id{.Photosynthesis, .Purify,
			.Antidote, .Leech, .Devour, .Riptide, .Barrier, .Fortify, .Maelstrom, .Tidal_Crash}},
		{name = "Blight", ability = .Envenom, item = .Venom_Sac, deck = []Move_Id{.Envenom, .Venom, .Toxic,
			.Catalyst, .Venom_Fang, .Slime_Spit, .Barrier, .Tidal_Crash, .Fortify, .Devour}},
		{name = "Bulwark", ability = .Envenom, item = .Grit_Charm, deck = []Move_Id{.Fortify, .Barrier,
			.Tidal_Crash, .Venom_Fang, .Devour, .Maelstrom, .Sting, .Aqua_Jet, .Slime_Spit, .Aqua_Cutter}},
	},
	.Dreadhorn = {
		{name = "Rubble", ability = .Berserk, item = .Weakpoint_Lens, deck = []Move_Id{.Sunder, .Rock_Throw,
			.Fault_Line, .Expose, .Earthquake, .Cleave, .Meteor, .Bash, .Overwhelm, .Blood_Pact}},
		{name = "Fury", ability = .Berserk, item = .Bloodstone, deck = []Move_Id{.Hone, .Rally, .Warcry,
			.Blood_Pact, .Rage, .Meteor, .Fault_Line, .Earthquake, .Bash, .Cleave}},
		{name = "Ambush", ability = .Predator, item = .Weakpoint_Lens, deck = []Move_Id{.Mark, .Expose, .Bash,
			.Overwhelm, .Fault_Line, .Meteor, .Earthquake, .Sunder, .Cleave, .Rock_Throw}},
	},
	.Rimewarden = {
		{name = "Bulwark", ability = .Guardian, item = .Grit_Charm, deck = []Move_Id{.Fortify, .Rampart, .Barrier,
			.Body_Press, .Shield_Bash, .Entrench, .Ice_Wall, .Hold_the_Line, .Spike_Shell, .Guard}},
		{name = "Bramble", ability = .Thick_Hide, item = .Spiked_Carapace, deck = []Move_Id{.Bramble_Armor,
			.Spike_Shell, .Ice_Wall, .Barrier, .Fortify, .Rampart, .Hold_the_Line, .Fault_Line, .Avalanche, .Guard}},
		{name = "Rubble", ability = .Thick_Hide, item = .Weakpoint_Lens, deck = []Move_Id{.Fault_Line,
			.Earthquake, .Avalanche, .Barrier, .Frost_Nova, .Fortify, .Rampart, .Body_Press, .Snowball,
			.Sand_Attack}},
	},
	.Gravemaw = {
		{name = "Bulwark", ability = .Thick_Hide, item = .Grit_Charm, deck = []Move_Id{.Rampart, .Barrier,
			.Body_Press, .Shield_Bash, .Entrench, .Guard, .Fault_Line, .Cataclysm, .Earthquake, .Decree}},
		{name = "Rubble", ability = .Thick_Hide, item = .Weakpoint_Lens, deck = []Move_Id{.Sunder, .Rock_Throw,
			.Fault_Line, .Earthquake, .Cleave, .Decree, .Barrier, .Bash, .Overwhelm, .Rampart}},
		{name = "Ambush", ability = .Vengeance, item = .Weakpoint_Lens, deck = []Move_Id{.Bash, .Overwhelm,
			.Fault_Line, .Cull, .Earthquake, .Decree, .Sunder, .Cleave, .Rock_Throw, .Body_Press}},
	},
}
