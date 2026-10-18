package main

// ============================================================================
// MILESTONES (Phase 22, reworked in Phase 46)
//
// The colony's quest board. It is deliberately a *long* ladder now rather than
// a short checklist: the opening objectives are quick, but the board runs all
// the way out to slaying each of the five bosses, surviving 150 turns and
// commanding twenty monsters. Each one pays a crystal bounty, and crystals are
// a real progression currency (see the crystal sink), so the board is one of
// the main ways you fund a long run.
// ============================================================================

Milestone_Kind :: enum {
	// Opening moves.
	FIRST_FARM,
	FIRST_BLOOD, // win a battle
	FIVE_MONSTERS,
	FIRST_RAID,
	// Growing pains.
	BUILD_BEACON,
	BUILD_DEN,
	BUILD_RELIC_TOWER,
	FIRST_ALPHA, // slay an alpha raider
	FIFTY_CRYSTALS,
	TEN_MONSTERS,
	// The five thrones: one quest per boss.
	SLAY_LEVIATHAN,
	SLAY_INFERNAL,
	SLAY_TITAN,
	SLAY_SOVEREIGN,
	SLAY_DEEP_ONE,
	// The Arena tower.
	ARENA_FLOOR_10,
	ARENA_FLOOR_25,
	ARENA_FLOOR_50,
	ARENA_FLOOR_100,
	ARENA_FLOOR_1000,
	// The long haul.
	FIFTY_FIGHTS,
	SURVIVE_150,
	TEN_RAIDS,
	TWENTY_MONSTERS,
	ALL_BOSSES,
}

Milestone :: struct {
	desc:   cstring,
	target: int,
	reward: int, // crystals
}

@(rodata)
MILESTONES := [Milestone_Kind]Milestone{
	.FIRST_FARM         = {"Build your first Farm", 1, 1},
	.FIRST_BLOOD        = {"Win your first battle", 1, 1},
	.FIVE_MONSTERS      = {"Command 5 monsters", 5, 2},
	.FIRST_RAID         = {"Weather your first raid", 1, 2},
	.BUILD_BEACON       = {"Raise a Beacon", 1, 3},
	.BUILD_DEN          = {"Build a Den", 1, 3},
	.BUILD_RELIC_TOWER  = {"Raise a Relic Tower", 1, 3},
	.FIRST_ALPHA        = {"Slay an alpha raider", 1, 4},
	.FIFTY_CRYSTALS     = {"Earn 50 crystals in total", 50, 4},
	.TEN_MONSTERS       = {"Command 10 monsters", 10, 5},
	.SLAY_LEVIATHAN     = {"Slay the Boss Leviathan", 1, 6},
	.SLAY_INFERNAL      = {"Slay the Boss Infernal", 1, 6},
	.SLAY_TITAN         = {"Slay the Boss Titan", 1, 6},
	.SLAY_SOVEREIGN     = {"Slay the Boss Sovereign", 1, 6},
	.SLAY_DEEP_ONE      = {"Slay the Deep One", 1, 6},
	.ARENA_FLOOR_10     = {"Reach Arena floor 10", 10, 6},
	.ARENA_FLOOR_25     = {"Reach Arena floor 25", 25, 8},
	.ARENA_FLOOR_50     = {"Reach Arena floor 50", 50, 12},
	.ARENA_FLOOR_100    = {"Reach Arena floor 100", 100, 25},
	.ARENA_FLOOR_1000   = {"Reach Arena floor 1000", 1000, 100},
	.FIFTY_FIGHTS       = {"Win 50 battles", 50, 6},
	.SURVIVE_150        = {"Survive 150 turns", 150, 6},
	.TEN_RAIDS          = {"Weather 10 raids", 10, 6},
	.TWENTY_MONSTERS    = {"Command 20 monsters", 20, 8},
	.ALL_BOSSES         = {"Slay all five bosses", 5, 12},
}

// Which boss a per-boss quest is about, or .Emberling for the others.
milestone_boss :: proc(k: Milestone_Kind) -> Species_Id {
	#partial switch k {
	case .SLAY_LEVIATHAN: return .Boss_Leviathan
	case .SLAY_INFERNAL:  return .Boss_Infernal
	case .SLAY_TITAN:     return .Boss_Titan
	case .SLAY_SOVEREIGN: return .Boss_Sovereign
	case .SLAY_DEEP_ONE:  return .Deep_One
	case:                 return .Emberling
	}
}

// Current progress toward a milestone (capped by the caller for display).
milestone_progress :: proc(c: ^Colony, k: Milestone_Kind) -> int {
	switch k {
	case .FIRST_FARM:        return improvement_count(c, .FARM)
	case .FIRST_BLOOD:       return c.fights_won
	case .FIVE_MONSTERS:     return player_monster_count(c)
	case .FIRST_RAID:        return c.raids
	case .BUILD_BEACON:      return improvement_count(c, .BEACON)
	case .BUILD_DEN:         return improvement_count(c, .DEN)
	case .BUILD_RELIC_TOWER: return improvement_count(c, .RELIC_TOWER)
	case .FIRST_ALPHA:       return c.alphas_slain
	case .FIFTY_CRYSTALS:    return c.crystals_earned
	case .TEN_MONSTERS:      return player_monster_count(c)
	case .SLAY_LEVIATHAN, .SLAY_INFERNAL, .SLAY_TITAN, .SLAY_SOVEREIGN, .SLAY_DEEP_ONE:
		return c.bosses_slain[milestone_boss(k)] ? 1 : 0
	case .ARENA_FLOOR_10, .ARENA_FLOOR_25, .ARENA_FLOOR_50, .ARENA_FLOOR_100, .ARENA_FLOOR_1000:
		return c.arena_best_floor
	case .FIFTY_FIGHTS:      return c.fights_won
	case .SURVIVE_150:       return c.turn
	case .TEN_RAIDS:         return c.raids
	case .TWENTY_MONSTERS:   return player_monster_count(c)
	case .ALL_BOSSES:        return bosses_slain_count(c)
	}
	return 0
}

// How many distinct bosses have been slain (per-boss quests + the capstone).
// Counts every boss *species*, not the spawn table, so the Deep One counts too.
bosses_slain_count :: proc(c: ^Colony) -> int {
	n := 0
	for sp in Species_Id {
		if SPECIES[sp].role == .BOSS && c.bosses_slain[sp] {
			n += 1
		}
	}
	return n
}

milestones_done_count :: proc(c: ^Colony) -> int {
	n := 0
	for k in Milestone_Kind {
		if c.milestones[k] {
			n += 1
		}
	}
	return n
}

// Grant any milestones whose target has just been reached, then flag the run
// complete when every one is done. Called once per turn and after battles.
milestones_check :: proc(c: ^Colony) {
	all := true
	for k in Milestone_Kind {
		if !c.milestones[k] && milestone_progress(c, k) >= MILESTONES[k].target {
			c.milestones[k] = true
			r := MILESTONES[k].reward
			c.crystals += r
			c.crystals_earned += r
			colony_notify(c, "Milestone: %s  (+%d crystals)", MILESTONES[k].desc, r)
			audio_play(.CONFIRM)
		}
		if !c.milestones[k] {
			all = false
		}
	}
	if all && !c.goal_done {
		c.goal_done = true
		colony_notify(c, "Every milestone complete - the colony has mastered the underground!")
		audio_play(.VICTORY)
	}
}
