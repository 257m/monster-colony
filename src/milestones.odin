package main

// ============================================================================
// MILESTONES (Phase 22)
//
// A light quest board that gives the sandbox a goal without turning it into a
// checklist. Each milestone tracks progress against a target and pays a small
// crystal bounty; finishing them all completes the run. Rewards are modest on
// purpose — the Arena and Boss Rooms stay the real crystal source.
// ============================================================================

Milestone_Kind :: enum {
	FIRST_FARM,
	TURNS_60,
	MONSTERS_8,
	WIN_FIGHTS_6,
	BUILD_BEACON,
	HUNT_ALPHA,
	CRYSTALS_40,
	BUILD_DEN,
	SURVIVE_RAIDS_3,
	MONSTERS_16,
}

Milestone :: struct {
	desc:   cstring,
	target: int,
	reward: int, // crystals
}

@(rodata)
MILESTONES := [Milestone_Kind]Milestone{
	.FIRST_FARM       = {"Build your first Farm", 1, 1},
	.TURNS_60         = {"Survive 60 turns", 60, 2},
	.MONSTERS_8       = {"Grow the colony to 8 monsters", 8, 2},
	.WIN_FIGHTS_6     = {"Win 6 battles", 6, 2},
	.BUILD_BEACON     = {"Raise a Beacon", 1, 3},
	.HUNT_ALPHA       = {"Slay an alpha raider", 1, 3},
	.CRYSTALS_40      = {"Earn 40 crystals in total", 40, 3},
	.BUILD_DEN        = {"Build a Den", 1, 3},
	.SURVIVE_RAIDS_3  = {"Weather 3 raids", 3, 3},
	.MONSTERS_16      = {"Command 16 monsters", 16, 5},
}

// Current progress toward a milestone (capped by the caller for display).
milestone_progress :: proc(c: ^Colony, k: Milestone_Kind) -> int {
	switch k {
	case .FIRST_FARM:      return improvement_count(c, .FARM)
	case .TURNS_60:        return c.turn
	case .MONSTERS_8:      return player_monster_count(c)
	case .WIN_FIGHTS_6:    return c.fights_won
	case .BUILD_BEACON:    return improvement_count(c, .BEACON)
	case .HUNT_ALPHA:      return c.alphas_slain
	case .CRYSTALS_40:     return c.crystals_earned
	case .BUILD_DEN:       return improvement_count(c, .DEN)
	case .SURVIVE_RAIDS_3: return c.raids
	case .MONSTERS_16:     return player_monster_count(c)
	}
	return 0
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
			colony_notify(c, "Milestone: %s (+%d crystals)", MILESTONES[k].desc, r)
			audio_play(.CONFIRM)
		}
		if !c.milestones[k] {
			all = false
		}
	}
	if all && !c.goal_done {
		c.goal_done = true
		colony_notify(c, "Every milestone complete - the colony is ascendant!")
	}
}
