package main

import rl "vendor:raylib"
import "core:math"

// ============================================================================
// IMPROVEMENT ICONS
//
// Animated icons drawn on the colony map, one per improvement, at the centre of
// its hex (cx, cy) scaled by the camera zoom. Everything is a pure function of
// rl.GetTime(), so there is no per-frame state to manage.
// ============================================================================

draw_improvement_icon :: proc(im: Improvement, cx, cy, zoom: f32) {
	if im == .NONE {
		return
	}
	t := f32(rl.GetTime())
	z := zoom * 1.3

	// Soft shadow so icons read on pale terrain (Tundra/Desert).
	rl.DrawCircleV(rl.Vector2{cx, cy + 5 * z}, 13 * z, rl.Color{0, 0, 0, 50})

	switch im {
	case .FARM:       draw_icon_farm(cx, cy, z, t)
	case .MINE:       draw_icon_mine(cx, cy, z, t)
	case .WELL:       draw_icon_well(cx, cy, z, t)
	case .BRIDGE:     draw_icon_bridge(cx, cy, z, t)
	case .GRANARY:    draw_icon_granary(cx, cy, z, t)
	case .TREASURY:   draw_icon_treasury(cx, cy, z, t)
	case .WATCHTOWER: draw_icon_watchtower(cx, cy, z, t)
	case .WALL:       draw_icon_wall(cx, cy, z, t)
	case .GATE:       draw_icon_gate(cx, cy, z, t)
	case .SPIKE_TRAP: draw_icon_spike_trap(cx, cy, z, t)
	case .SCARECROW:  draw_icon_scarecrow(cx, cy, z, t)
	case .ROAD:       draw_icon_road(cx, cy, z, t)
	case .SILO:       draw_icon_silo(cx, cy, z, t)
	case .CRYSTAL_REFINERY: draw_icon_refinery(cx, cy, z, t)
	case .FOUNTAIN:   draw_icon_fountain(cx, cy, z, t)
	case .TURRET:     draw_icon_turret(cx, cy, z, t)
	case .DRAWBRIDGE: draw_icon_drawbridge(cx, cy, z, t)
	case .QUARRY:     draw_icon_quarry(cx, cy, z, t)
	case .LUMBER_MILL: draw_icon_lumber(cx, cy, z, t)
	case .MARKETPLACE: draw_icon_marketplace(cx, cy, z, t)
	case .KITCHEN:    draw_icon_kitchen(cx, cy, z, t)
	case .BARRACKS:   draw_icon_barracks(cx, cy, z, t)
	case .BEACON:     draw_icon_beacon(cx, cy, z, t)
	case .DEN:        draw_icon_den(cx, cy, z, t)
	case .VAULT:      draw_icon_vault(cx, cy, z, t)
	case .NURSERY:    draw_icon_nursery(cx, cy, z, t)
	case .MENDER:     draw_icon_mender(cx, cy, z, t)
	case .RELIC_TOWER: draw_icon_relic_tower(cx, cy, z, t)
	case .WARD_STONE: draw_icon_ward_stone(cx, cy, z, t)
	case .TRAINING_YARD: draw_icon_training_yard(cx, cy, z, t)
	case .CALTROPS: draw_icon_caltrops(cx, cy, z, t)
	case .BATTERY: draw_icon_battery(cx, cy, z, t)
	case .NONE:
	}
}

// Farm: soil bed with grain stalks that sway in the wind.
draw_icon_farm :: proc(cx, cy, z, t: f32) {
	rl.DrawRectangleRounded(rl.Rectangle{cx - 15 * z, cy + 5 * z, 30 * z, 8 * z}, 0.5, 6, rl.Color{74, 54, 38, 255})
	for k in 0..<5 {
		bx := cx + (f32(k) - 2) * 6 * z
		sway := math.sin(t * 2.0 + f32(k) * 1.3) * 2.5 * z
		top_x := bx + sway
		top_y := cy - 8 * z + math.sin(t * 2.0 + f32(k)) * 1.0 * z
		rl.DrawLineEx(rl.Vector2{bx, cy + 6 * z}, rl.Vector2{top_x, top_y}, 1.8 * z, rl.Color{96, 170, 92, 255})
		rl.DrawCircleV(rl.Vector2{top_x, top_y}, 2.4 * z, rl.Color{216, 198, 96, 255})
	}
}

// Mine: a mound with a dark shaft and a blinking gold nugget.
draw_icon_mine :: proc(cx, cy, z, t: f32) {
	rl.DrawCircleV(rl.Vector2{cx, cy + 6 * z}, 13 * z, rl.Color{96, 82, 66, 255})
	rl.DrawCircleV(rl.Vector2{cx, cy + 7 * z}, 6.5 * z, rl.Color{24, 20, 24, 255})
	rl.DrawRectangleRec(rl.Rectangle{cx - 6.5 * z, cy + 7 * z, 13 * z, 6 * z}, rl.Color{24, 20, 24, 255})
	pulse := 0.5 + 0.5 * math.sin(t * 4.0)
	r := (2.4 + 1.2 * pulse) * z
	rl.DrawCircleV(rl.Vector2{cx, cy - 1 * z}, r, rl.Color{240, 200, 80, u8(150 + 100 * pulse)})
	rl.DrawCircleLinesV(rl.Vector2{cx, cy - 1 * z}, r + 2 * z, rl.Color{255, 230, 140, u8(120 * pulse)})
}

// Well: a stone rim, water, ripples, and a little roof frame.
draw_icon_well :: proc(cx, cy, z, t: f32) {
	rl.DrawCircleV(rl.Vector2{cx, cy}, 10 * z, rl.Color{122, 122, 132, 255})
	rl.DrawCircleV(rl.Vector2{cx, cy}, 8 * z, rl.Color{40, 92, 152, 255})
	for k in 0..<2 {
		p := math.mod(t * 0.9 + f32(k) * 0.5, 1.0)
		rl.DrawCircleLinesV(rl.Vector2{cx, cy}, (2 + p * 6) * z, rl.Color{150, 205, 245, u8((1.0 - p) * 190)})
	}
	wood := rl.Color{96, 72, 48, 255}
	rl.DrawLineEx(rl.Vector2{cx - 8 * z, cy - 4 * z}, rl.Vector2{cx - 8 * z, cy - 12 * z}, 1.5 * z, wood)
	rl.DrawLineEx(rl.Vector2{cx + 8 * z, cy - 4 * z}, rl.Vector2{cx + 8 * z, cy - 12 * z}, 1.5 * z, wood)
	rl.DrawLineEx(rl.Vector2{cx - 9 * z, cy - 12 * z}, rl.Vector2{cx + 9 * z, cy - 12 * z}, 2 * z, rl.Color{124, 94, 62, 255})
}

// Bridge: a few planks spanning the tile.
draw_icon_bridge :: proc(cx, cy, z, t: f32) {
	for k in 0..<3 {
		y := cy + (f32(k) - 1) * 6 * z
		col := k == 1 ? rl.Color{146, 106, 66, 255} : rl.Color{104, 74, 46, 255}
		rl.DrawRectangleRounded(rl.Rectangle{cx - 15 * z, y - 2.5 * z, 30 * z, 5 * z}, 0.4, 4, col)
	}
}

// Granary: a silo that gently bobs.
draw_icon_granary :: proc(cx, cy, z, t: f32) {
	bob := math.sin(t * 1.5) * 1.2 * z
	rl.DrawRectangleRounded(rl.Rectangle{cx - 9 * z, cy - 6 * z + bob, 18 * z, 15 * z}, 0.35, 6, rl.Color{196, 168, 110, 255})
	rl.DrawCircleV(rl.Vector2{cx, cy - 6 * z + bob}, 9 * z, rl.Color{216, 190, 134, 255})
	band := rl.Color{150, 120, 76, 255}
	rl.DrawLineEx(rl.Vector2{cx - 8 * z, cy + 1 * z + bob}, rl.Vector2{cx + 8 * z, cy + 1 * z + bob}, 1.5 * z, band)
	rl.DrawLineEx(rl.Vector2{cx - 8 * z, cy + 6 * z + bob}, rl.Vector2{cx + 8 * z, cy + 6 * z + bob}, 1.5 * z, band)
}

// Treasury: a chest with a coin that floats up and fades on a loop.
draw_icon_treasury :: proc(cx, cy, z, t: f32) {
	rl.DrawRectangleRounded(rl.Rectangle{cx - 12 * z, cy - 3 * z, 24 * z, 12 * z}, 0.2, 5, rl.Color{132, 96, 56, 255})
	rl.DrawRectangleRounded(rl.Rectangle{cx - 12 * z, cy - 8 * z, 24 * z, 7 * z}, 0.5, 5, rl.Color{158, 118, 70, 255})
	rl.DrawRectangleRec(rl.Rectangle{cx - 2 * z, cy - 4 * z, 4 * z, 5 * z}, rl.Color{230, 200, 120, 255})
	p := math.mod(t * 0.8, 1.0)
	a := u8((1.0 - p) * 255)
	y := cy - 10 * z - p * 12 * z
	rl.DrawCircleV(rl.Vector2{cx, y}, 3.5 * z, rl.Color{245, 205, 80, a})
	rl.DrawCircleLinesV(rl.Vector2{cx, y}, 3.5 * z, rl.Color{255, 240, 180, a})
}

// Watchtower: a tower with a pulsing beacon.
draw_icon_watchtower :: proc(cx, cy, z, t: f32) {
	rl.DrawRectangleRounded(rl.Rectangle{cx - 5 * z, cy - 2 * z, 10 * z, 13 * z}, 0.15, 4, rl.Color{150, 150, 160, 255})
	for k in 0..<3 {
		rl.DrawRectangleRec(rl.Rectangle{cx - 6 * z + f32(k) * 5 * z, cy - 5 * z, 3 * z, 3 * z}, rl.Color{172, 172, 182, 255})
	}
	pulse := 0.5 + 0.5 * math.sin(t * 3.0)
	rl.DrawCircleV(rl.Vector2{cx, cy - 9 * z}, (2.4 + 1.0 * pulse) * z, rl.Color{245, 220, 120, 255})
	rl.DrawCircleLinesV(rl.Vector2{cx, cy - 9 * z}, (5 + 5 * pulse) * z, rl.Color{255, 235, 160, u8(170 * (1 - pulse))})
}

// Wall: a brick pattern.
draw_icon_wall :: proc(cx, cy, z, t: f32) {
	rl.DrawRectangleRounded(rl.Rectangle{cx - 14 * z, cy - 8 * z, 28 * z, 16 * z}, 0.12, 4, rl.Color{92, 90, 86, 255})
	for row in 0..<2 {
		off := row == 1 ? 3.5 * z : 0
		for k in 0..<4 {
			x := cx - 13 * z + f32(k) * 7 * z + off
			rl.DrawRectangleRec(rl.Rectangle{x, cy - 7 * z + f32(row) * 7.5 * z, 6 * z, 6.5 * z}, rl.Color{152, 148, 140, 255})
		}
	}
}

// Gate: a post-and-lintel arch with a barred door — your monsters pass, wilds don't.
draw_icon_gate :: proc(cx, cy, z, t: f32) {
	wood := rl.Color{120, 88, 54, 255}
	rl.DrawRectangleRec(rl.Rectangle{cx - 11 * z, cy - 8 * z, 4 * z, 16 * z}, wood)
	rl.DrawRectangleRec(rl.Rectangle{cx + 7 * z, cy - 8 * z, 4 * z, 16 * z}, wood)
	rl.DrawRectangleRec(rl.Rectangle{cx - 12 * z, cy - 11 * z, 24 * z, 4 * z}, rl.Color{142, 106, 66, 255})
	rl.DrawLineEx(rl.Vector2{cx - 7 * z, cy - 6 * z}, rl.Vector2{cx - 3 * z, cy + 7 * z}, 2 * z, rl.Color{92, 66, 40, 255})
	rl.DrawLineEx(rl.Vector2{cx - 7 * z, cy + 2 * z}, rl.Vector2{cx - 1 * z, cy + 2 * z}, 1.4 * z, rl.Color{92, 66, 40, 255})
}

// Spike Trap: a pit of spikes.
draw_icon_spike_trap :: proc(cx, cy, z, t: f32) {
	rl.DrawRectangleRounded(rl.Rectangle{cx - 13 * z, cy - 3 * z, 26 * z, 12 * z}, 0.3, 4, rl.Color{30, 26, 28, 255})
	for k in 0..<4 {
		x := cx - 9 * z + f32(k) * 6 * z
		rl.DrawTriangle(rl.Vector2{x - 2.5 * z, cy + 6 * z}, rl.Vector2{x + 2.5 * z, cy + 6 * z}, rl.Vector2{x, cy - 7 * z}, rl.Color{192, 198, 208, 255})
	}
}

// Scarecrow: a straw man on a post, gently swaying.
draw_icon_scarecrow :: proc(cx, cy, z, t: f32) {
	sway := math.sin(t * 1.2) * 1.2 * z
	wood := rl.Color{120, 92, 56, 255}
	rl.DrawLineEx(rl.Vector2{cx, cy + 9 * z}, rl.Vector2{cx, cy - 10 * z}, 2.4 * z, wood)
	rl.DrawLineEx(rl.Vector2{cx - 9 * z, cy - 3 * z}, rl.Vector2{cx + 9 * z, cy - 3 * z}, 2.2 * z, wood)
	rl.DrawCircleV(rl.Vector2{cx + sway, cy - 8 * z}, 4 * z, rl.Color{214, 190, 120, 255})
	rl.DrawLineEx(rl.Vector2{cx + sway - 4 * z, cy - 8 * z}, rl.Vector2{cx + sway + 4 * z, cy - 8 * z}, 1.2 * z, rl.Color{158, 118, 58, 255})
}

// Road: a cobbled path.
draw_icon_road :: proc(cx, cy, z, t: f32) {
	rl.DrawRectangleRounded(rl.Rectangle{cx - 15 * z, cy - 8 * z, 30 * z, 16 * z}, 0.25, 4, rl.Color{96, 90, 80, 255})
	for row in 0..<2 {
		for k in 0..<4 {
			x := cx - 12 * z + f32(k) * 8 * z + (row == 1 ? 4 * z : 0)
			rl.DrawRectangleRec(rl.Rectangle{x, cy - 6 * z + f32(row) * 8 * z, 6 * z, 6 * z}, rl.Color{132, 126, 114, 255})
		}
	}
}

// Silo: a tall storage tower (extra food storage).
draw_icon_silo :: proc(cx, cy, z, t: f32) {
	bob := math.sin(t * 1.5 + 1.0) * 1.0 * z
	rl.DrawRectangleRounded(rl.Rectangle{cx - 8 * z, cy - 6 * z + bob, 16 * z, 16 * z}, 0.25, 6, rl.Color{178, 172, 160, 255})
	rl.DrawCircleV(rl.Vector2{cx, cy - 6 * z + bob}, 8 * z, rl.Color{200, 194, 182, 255})
	band := rl.Color{140, 134, 122, 255}
	rl.DrawLineEx(rl.Vector2{cx - 8 * z, cy + 1 * z + bob}, rl.Vector2{cx + 8 * z, cy + 1 * z + bob}, 1.4 * z, band)
	rl.DrawLineEx(rl.Vector2{cx - 8 * z, cy + 6 * z + bob}, rl.Vector2{cx + 8 * z, cy + 6 * z + bob}, 1.4 * z, band)
	rl.DrawCircleV(rl.Vector2{cx, cy - 9 * z + bob}, 2.2 * z, rl.Color{120, 116, 108, 255})
}

// Crystal Refinery: a furnace with a glowing crystal.
draw_icon_refinery :: proc(cx, cy, z, t: f32) {
	pulse := 0.5 + 0.5 * math.sin(t * 2.5)
	rl.DrawRectangleRounded(rl.Rectangle{cx - 11 * z, cy - 2 * z, 22 * z, 12 * z}, 0.25, 5, rl.Color{92, 84, 96, 255})
	rl.DrawRectangleRec(rl.Rectangle{cx - 8 * z, cy - 6 * z, 16 * z, 5 * z}, rl.Color{72, 66, 78, 255})
	rl.DrawTriangle(rl.Vector2{cx - 4 * z, cy - 7 * z}, rl.Vector2{cx + 4 * z, cy - 7 * z}, rl.Vector2{cx, cy - 16 * z}, rl.Color{120, 220, 245, u8(150 + 95 * pulse)})
	rl.DrawTriangle(rl.Vector2{cx - 3 * z, cy - 7 * z}, rl.Vector2{cx, cy - 16 * z}, rl.Vector2{cx, cy - 7 * z}, rl.Color{205, 245, 255, u8(110 + 95 * pulse)})
}

// Fountain: a basin with a little water jet and droplets.
draw_icon_fountain :: proc(cx, cy, z, t: f32) {
	rl.DrawRectangleRounded(rl.Rectangle{cx - 12 * z, cy + 4 * z, 24 * z, 7 * z}, 0.4, 5, rl.Color{120, 124, 134, 255})
	rl.DrawCircleV(rl.Vector2{cx, cy + 2 * z}, 9 * z, rl.Color{66, 148, 210, 255})
	rl.DrawLineEx(rl.Vector2{cx, cy - 1 * z}, rl.Vector2{cx, cy - 9 * z}, 2 * z, rl.Color{155, 212, 245, 220})
	p := math.mod(t * 1.5, 1.0)
	rl.DrawCircleV(rl.Vector2{cx - 4 * z, cy - 4 * z - p * 6 * z}, 1.6 * z, rl.Color{185, 228, 250, u8((1 - p) * 220)})
	q := math.mod(t * 1.5 + 0.5, 1.0)
	rl.DrawCircleV(rl.Vector2{cx + 4 * z, cy - 4 * z - q * 6 * z}, 1.6 * z, rl.Color{185, 228, 250, u8((1 - q) * 200)})
}

// Turret: a base, a barrel, and a pulsing muzzle flash.
draw_icon_turret :: proc(cx, cy, z, t: f32) {
	pulse := 0.5 + 0.5 * math.sin(t * 5.0)
	rl.DrawRectangleRounded(rl.Rectangle{cx - 9 * z, cy + 3 * z, 18 * z, 8 * z}, 0.3, 4, rl.Color{96, 84, 92, 255})
	rl.DrawCircleV(rl.Vector2{cx, cy - 1 * z}, 7 * z, rl.Color{120, 108, 118, 255})
	rl.DrawLineEx(rl.Vector2{cx, cy - 2 * z}, rl.Vector2{cx + 10 * z, cy - 8 * z}, 4 * z, rl.Color{70, 64, 72, 255})
	rl.DrawCircleV(rl.Vector2{cx + 12 * z, cy - 9 * z}, (2 + 2 * pulse) * z, rl.Color{255, 200, 90, u8(110 + 130 * pulse)})
}

// Drawbridge: a deck with a raised leaf (or lowered when open).
draw_icon_drawbridge :: proc(cx, cy, z, t: f32) {
	wood := rl.Color{146, 106, 66, 255}
	rl.DrawRectangleRounded(rl.Rectangle{cx - 15 * z, cy + 2 * z, 30 * z, 6 * z}, 0.3, 4, wood)
	rl.DrawLineEx(rl.Vector2{cx - 4 * z, cy + 2 * z}, rl.Vector2{cx, cy - 9 * z}, 5 * z, wood)
	rl.DrawLineEx(rl.Vector2{cx + 4 * z, cy + 2 * z}, rl.Vector2{cx, cy - 9 * z}, 5 * z, wood)
	rl.DrawCircleV(rl.Vector2{cx - 14 * z, cy}, 2 * z, rl.Color{92, 92, 102, 255})
	rl.DrawCircleV(rl.Vector2{cx + 14 * z, cy}, 2 * z, rl.Color{92, 92, 102, 255})
}

// Quarry: a stepped rock pit.
draw_icon_quarry :: proc(cx, cy, z, t: f32) {
	rl.DrawRectangleRounded(rl.Rectangle{cx - 13 * z, cy + 5 * z, 26 * z, 6 * z}, 0.4, 4, rl.Color{118, 110, 98, 255})
	rl.DrawRectangleRec(rl.Rectangle{cx - 9 * z, cy + 1 * z, 18 * z, 5 * z}, rl.Color{140, 130, 116, 255})
	rl.DrawRectangleRec(rl.Rectangle{cx - 5 * z, cy - 3 * z, 10 * z, 5 * z}, rl.Color{162, 150, 134, 255})
	rl.DrawCircleV(rl.Vector2{cx + 8 * z, cy - 4 * z}, 3 * z, rl.Color{100, 94, 84, 255})
}

// Lumber Mill: a log pile and a spinning saw blade.
draw_icon_lumber :: proc(cx, cy, z, t: f32) {
	rl.DrawCircleV(rl.Vector2{cx - 6 * z, cy + 5 * z}, 4 * z, rl.Color{150, 112, 72, 255})
	rl.DrawCircleV(rl.Vector2{cx + 1 * z, cy + 5 * z}, 4 * z, rl.Color{150, 112, 72, 255})
	rl.DrawCircleV(rl.Vector2{cx - 3 * z, cy - 1 * z}, 4 * z, rl.Color{168, 128, 84, 255})
	rl.DrawCircleV(rl.Vector2{cx - 3 * z, cy - 1 * z}, 1.6 * z, rl.Color{110, 80, 50, 255})
	a := t * 2.0
	rl.DrawCircleV(rl.Vector2{cx + 10 * z, cy - 5 * z}, 5 * z, rl.Color{190, 195, 205, 255})
	for k in 0..<6 {
		ang := a + f32(k) * math.PI / 3
		rl.DrawLineEx(rl.Vector2{cx + 10 * z, cy - 5 * z}, rl.Vector2{cx + 10 * z + math.cos(ang) * 5 * z, cy - 5 * z + math.sin(ang) * 5 * z}, 1.2 * z, rl.Color{150, 155, 165, 255})
	}
}

// Marketplace: a tilting balance scale.
draw_icon_marketplace :: proc(cx, cy, z, t: f32) {
	rl.DrawLineEx(rl.Vector2{cx, cy + 8 * z}, rl.Vector2{cx, cy - 9 * z}, 2.4 * z, rl.Color{120, 92, 56, 255})
	tilt := math.sin(t * 1.5) * 0.08
	rl.DrawLineEx(rl.Vector2{cx - 10 * z, cy - 8 * z + tilt * 40 * z}, rl.Vector2{cx + 10 * z, cy - 8 * z - tilt * 40 * z}, 1.8 * z, rl.Color{150, 120, 70, 255})
	rl.DrawCircleV(rl.Vector2{cx - 10 * z, cy - 6 * z + tilt * 40 * z}, 3.5 * z, rl.Color{205, 182, 120, 255})
	rl.DrawCircleV(rl.Vector2{cx + 10 * z, cy - 6 * z - tilt * 40 * z}, 3.5 * z, rl.Color{205, 182, 120, 255})
}

// Kitchen: a pot on a fire with rising steam.
draw_icon_kitchen :: proc(cx, cy, z, t: f32) {
	rl.DrawRectangleRounded(rl.Rectangle{cx - 9 * z, cy - 2 * z, 18 * z, 11 * z}, 0.3, 5, rl.Color{92, 94, 102, 255})
	rl.DrawLineEx(rl.Vector2{cx - 11 * z, cy - 2 * z}, rl.Vector2{cx + 11 * z, cy - 2 * z}, 2 * z, rl.Color{122, 124, 132, 255})
	for k in 0..<2 {
		p := math.mod(t * 1.2 + f32(k) * 0.5, 1.0)
		rl.DrawCircleV(rl.Vector2{cx - 3 * z + f32(k) * 6 * z, cy - 6 * z - p * 8 * z}, 1.8 * z, rl.Color{232, 232, 238, u8((1 - p) * 180)})
	}
	pulse := 0.5 + 0.5 * math.sin(t * 6.0)
	rl.DrawCircleV(rl.Vector2{cx, cy + 10 * z}, (3 + pulse) * z, rl.Color{240, 140, 60, 220})
}

// Barracks: a tent with a waving flag.
draw_icon_barracks :: proc(cx, cy, z, t: f32) {
	rl.DrawTriangle(rl.Vector2{cx - 12 * z, cy + 8 * z}, rl.Vector2{cx + 12 * z, cy + 8 * z}, rl.Vector2{cx, cy - 8 * z}, rl.Color{108, 120, 92, 255})
	rl.DrawRectangleRec(rl.Rectangle{cx - 3 * z, cy + 1 * z, 6 * z, 7 * z}, rl.Color{58, 64, 50, 255})
	rl.DrawLineEx(rl.Vector2{cx, cy - 8 * z}, rl.Vector2{cx, cy - 14 * z}, 1.5 * z, rl.Color{120, 92, 56, 255})
	wave := math.sin(t * 2.0) * 1.5 * z
	rl.DrawTriangle(rl.Vector2{cx, cy - 14 * z}, rl.Vector2{cx + 7 * z + wave, cy - 12 * z}, rl.Vector2{cx, cy - 10 * z}, rl.Color{210, 90, 80, 255})
}

// Beacon: a tall tower with a sweeping light.
draw_icon_beacon :: proc(cx, cy, z, t: f32) {
	rl.DrawRectangleRounded(rl.Rectangle{cx - 4 * z, cy - 2 * z, 8 * z, 13 * z}, 0.1, 4, rl.Color{152, 152, 162, 255})
	rl.DrawCircleV(rl.Vector2{cx, cy - 5 * z}, 5 * z, rl.Color{110, 110, 120, 255})
	pulse := 0.5 + 0.5 * math.sin(t * 4.0)
	rl.DrawCircleV(rl.Vector2{cx, cy - 5 * z}, (3 + 2 * pulse) * z, rl.Color{255, 235, 150, 255})
	a := t * 2.0
	rl.DrawLineEx(rl.Vector2{cx, cy - 5 * z}, rl.Vector2{cx + math.cos(a) * 16 * z, cy - 5 * z + math.sin(a) * 16 * z}, 2.5 * z, rl.Color{255, 240, 170, u8(90 + 60 * pulse)})
}

// Den: a rocky burrow with a soft glow from the entrance (monsters in stasis).
draw_icon_den :: proc(cx, cy, z, t: f32) {
	rl.DrawCircleV(rl.Vector2{cx, cy + 2 * z}, 13 * z, rl.Color{86, 78, 70, 255})
	rl.DrawCircleV(rl.Vector2{cx, cy - 2 * z}, 10 * z, rl.Color{104, 96, 86, 255})
	// Burrow mouth.
	rl.DrawCircleV(rl.Vector2{cx, cy + 1 * z}, 5.5 * z, rl.Color{30, 26, 24, 255})
	pulse := 0.5 + 0.5 * math.sin(t * 1.6)
	rl.DrawCircleV(rl.Vector2{cx, cy + 1 * z}, (3.0 + 1.5 * pulse) * z, rl.Color{140, 200, 255, u8(70 + 60 * pulse)})
}

// Vault: an iron-banded strongbox with a slow shine.
draw_icon_vault :: proc(cx, cy, z, t: f32) {
	rl.DrawRectangleRounded(rl.Rectangle{cx - 13 * z, cy - 9 * z, 26 * z, 18 * z}, 0.18, 5, rl.Color{96, 104, 116, 255})
	rl.DrawRectangleRoundedLinesEx(rl.Rectangle{cx - 13 * z, cy - 9 * z, 26 * z, 18 * z}, 0.18, 5, 1.5 * z, rl.Color{60, 66, 76, 255})
	band := rl.Color{140, 150, 165, 255}
	rl.DrawLineEx(rl.Vector2{cx - 9 * z, cy - 9 * z}, rl.Vector2{cx - 9 * z, cy + 9 * z}, 2 * z, band)
	rl.DrawLineEx(rl.Vector2{cx + 9 * z, cy - 9 * z}, rl.Vector2{cx + 9 * z, cy + 9 * z}, 2 * z, band)
	rl.DrawCircleV(rl.Vector2{cx, cy}, 3.5 * z, rl.Color{200, 210, 225, 255})
	p := 0.5 + 0.5 * math.sin(t * 2.0)
	rl.DrawCircleV(rl.Vector2{cx, cy}, (1.5 + 1.0 * p) * z, rl.Color{255, 255, 255, u8(120 + 80 * p)})
}

// Nursery: a rounded shell-egg on a nest, rocking gently.
draw_icon_nursery :: proc(cx, cy, z, t: f32) {
	rock := math.sin(t * 1.8) * 0.12
	rl.DrawEllipse(i32(cx), i32(cy + 8 * z), 14 * z, 4 * z, rl.Color{96, 82, 58, 255})
	// Nest twigs.
	for k in 0..<4 {
		x := cx + (f32(k) - 1.5) * 6 * z
		rl.DrawLineEx(rl.Vector2{x, cy + 9 * z}, rl.Vector2{x + 3 * z, cy + 5 * z}, 1.5 * z, rl.Color{140, 116, 78, 255})
	}
	ex := cx + math.sin(rock) * 3 * z
	rl.DrawEllipse(i32(ex), i32(cy - 1 * z), 8 * z, 11 * z, rl.Color{236, 232, 216, 255})
	rl.DrawCircleV(rl.Vector2{ex - 2.5 * z, cy - 5 * z}, 2.0 * z, rl.Color{255, 255, 255, 160})
	rl.DrawEllipseLines(i32(ex), i32(cy - 1 * z), 8 * z, 11 * z, rl.Color{196, 190, 170, 255})
}

// Mender: a little repair drone with a pulsing green cross.
draw_icon_mender :: proc(cx, cy, z, t: f32) {
	bob := math.sin(t * 2.2) * 1.2 * z
	body := rl.Color{104, 118, 134, 255}
	rl.DrawRectangleRounded(rl.Rectangle{cx - 11 * z, cy - 8 * z + bob, 22 * z, 17 * z}, 0.3, 6, body)
	rl.DrawRectangleRoundedLinesEx(rl.Rectangle{cx - 11 * z, cy - 8 * z + bob, 22 * z, 17 * z}, 0.3, 6, 1.5 * z, rl.Color{64, 74, 86, 255})
	// Two stubby arms.
	rl.DrawRectangleRounded(rl.Rectangle{cx - 15 * z, cy - 4 * z + bob, 4 * z, 9 * z}, 0.4, 3, rl.Color{88, 100, 114, 255})
	rl.DrawRectangleRounded(rl.Rectangle{cx + 11 * z, cy - 4 * z + bob, 4 * z, 9 * z}, 0.4, 3, rl.Color{88, 100, 114, 255})
	// Antenna with a blinking tip.
	rl.DrawLineEx(rl.Vector2{cx, cy - 8 * z + bob}, rl.Vector2{cx, cy - 14 * z + bob}, 1.5 * z, rl.Color{120, 130, 144, 255})
	pulse := 0.5 + 0.5 * math.sin(t * 3.0)
	rl.DrawCircleV(rl.Vector2{cx, cy - 14 * z + bob}, (1.6 + 0.8 * pulse) * z, rl.Color{150, 245, 170, 255})
	// Glowing green cross on the body.
	green := rl.Color{150, 240, 165, 255}
	rl.DrawRectangleRec(rl.Rectangle{cx - 5 * z, cy - 2 * z + bob, 10 * z, 3 * z}, green)
	rl.DrawRectangleRec(rl.Rectangle{cx - 1.5 * z, cy - 5.5 * z + bob, 3 * z, 10 * z}, green)
	rl.DrawCircleLinesV(rl.Vector2{cx, cy + bob}, (10 + 4 * pulse) * z, rl.Color{140, 235, 160, u8(90 * (1 - pulse))})
}

// Relic Tower: a tapered spire with a floating relic core bobbing above it.
draw_icon_relic_tower :: proc(cx, cy, z, t: f32) {
	rl.DrawTriangle(rl.Vector2{cx - 7 * z, cy + 8 * z}, rl.Vector2{cx + 7 * z, cy + 8 * z}, rl.Vector2{cx, cy - 9 * z}, rl.Color{96, 104, 140, 255})
	rl.DrawTriangleLines(rl.Vector2{cx - 7 * z, cy + 8 * z}, rl.Vector2{cx + 7 * z, cy + 8 * z}, rl.Vector2{cx, cy - 9 * z}, rl.Color{150, 165, 220, 255})
	bob := math.sin(t * 2.0) * 1.6 * z
	rl.DrawCircleV(rl.Vector2{cx, cy - 14 * z + bob}, 3.2 * z, rl.Color{245, 215, 140, 255})
	rl.DrawCircleLinesV(rl.Vector2{cx, cy - 14 * z + bob}, (4.5 + 1.5 * math.sin(t * 3.0)) * z, rl.Color{255, 235, 170, 190})
}

// Ward Stone: a standing stone with a slow halo.
draw_icon_ward_stone :: proc(cx, cy, z, t: f32) {
	rl.DrawRectangleRounded(rl.Rectangle{cx - 6 * z, cy - 11 * z, 12 * z, 22 * z}, 0.3, 5, rl.Color{120, 126, 160, 255})
	rl.DrawRectangleRoundedLinesEx(rl.Rectangle{cx - 6 * z, cy - 11 * z, 12 * z, 22 * z}, 0.3, 5, 1.5 * z, rl.Color{170, 178, 215, 255})
	pulse := 0.5 + 0.5 * math.sin(t * 2.0)
	rl.DrawCircleLinesV(rl.Vector2{cx, cy - 3 * z}, (7 + 4 * pulse) * z, rl.Color{180, 200, 255, u8(150 * (1 - pulse))})
	rl.DrawCircleV(rl.Vector2{cx, cy - 3 * z}, 2.6 * z, rl.Color{210, 225, 255, 255})
}

// Training Yard: a practice dummy on a mat.
draw_icon_training_yard :: proc(cx, cy, z, t: f32) {
	rl.DrawRectangleRounded(rl.Rectangle{cx - 14 * z, cy + 6 * z, 28 * z, 7 * z}, 0.4, 4, rl.Color{84, 68, 52, 255})
	rl.DrawRectangleRounded(rl.Rectangle{cx - 4 * z, cy - 12 * z, 8 * z, 18 * z}, 0.3, 4, rl.Color{140, 112, 78, 255})
	rl.DrawCircleV(rl.Vector2{cx, cy - 12 * z}, 5 * z, rl.Color{158, 128, 90, 255})
	rl.DrawLineEx(rl.Vector2{cx - 9 * z, cy - 2 * z}, rl.Vector2{cx + 9 * z, cy - 2 * z}, 2.2 * z, rl.Color{196, 170, 130, 255})
	sway := math.sin(t * 2.4) * 1.4 * z
	rl.DrawLineEx(rl.Vector2{cx + 12 * z, cy + 4 * z}, rl.Vector2{cx + 12 * z + sway, cy - 10 * z}, 2.2 * z, rl.Color{200, 200, 210, 255})
}

// Caltrops: a scatter of spikes on the ground.
draw_icon_caltrops :: proc(cx, cy, z, t: f32) {
	_ = t
	rl.DrawRectangleRounded(rl.Rectangle{cx - 14 * z, cy + 6 * z, 28 * z, 6 * z}, 0.4, 4, rl.Color{70, 62, 54, 255})
	for k in 0..<4 {
		x := cx + (f32(k) - 1.5) * 7 * z
		h := (5 + f32(k % 2) * 3) * z
		rl.DrawTriangle(rl.Vector2{x - 3 * z, cy + 6 * z}, rl.Vector2{x + 3 * z, cy + 6 * z}, rl.Vector2{x, cy + 6 * z - h}, rl.Color{190, 195, 205, 255})
	}
}

// Battery: a stack of cells with a charge level.
draw_icon_battery :: proc(cx, cy, z, t: f32) {
	rl.DrawRectangleRounded(rl.Rectangle{cx - 11 * z, cy - 10 * z, 22 * z, 20 * z}, 0.2, 4, rl.Color{38, 42, 54, 255})
	rl.DrawRectangleRoundedLinesEx(rl.Rectangle{cx - 11 * z, cy - 10 * z, 22 * z, 20 * z}, 0.2, 4, 1.6 * z, rl.Color{120, 130, 160, 255})
	// three cells, the lit portion pulsing
	lit := 0.55 + 0.45 * math.sin(t * 2.2)
	for k in 0..<3 {
		x := cx - 8 * z + f32(k) * 6 * z
		rl.DrawRectangleRounded(rl.Rectangle{x, cy - 7 * z, 4 * z, 14 * z}, 0.3, 3, rl.Color{30, 34, 44, 255})
		h := 14 * z * f32(k + 1) / 3 * lit
		rl.DrawRectangleRounded(rl.Rectangle{x, cy + 7 * z - h, 4 * z, h}, 0.3, 3, rl.Color{242, 200, 70, 255})
	}
	rl.DrawRectangleRounded(rl.Rectangle{cx + 11 * z, cy - 3 * z, 3 * z, 6 * z}, 0.4, 2, rl.Color{150, 160, 190, 255})
}
