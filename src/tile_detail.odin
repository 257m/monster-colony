package main

import rl "vendor:raylib"
import "core:math"

// ============================================================================
// TILE DETAIL
//
// Procedural "texture" drawn on each revealed tile — rocks in caves, grass and
// a tree in groves, mushrooms, pillars, snow, lava cracks, etc. — so a tile is
// more than a flat colour. Positions are derived from the hex (stable, no
// state); a few details animate off rl.GetTime().
//
// This is vector drawing, not textures. If you later add a sprite atlas, swap
// the body of draw_tile_detail for rl.DrawTexturePro.
// ============================================================================

// Stable per-hex random in [0,1). `k` selects a channel.
tile_rand :: proc(hex: Hex, k: int) -> f32 {
	h := hex_key(hex) ~ (u64(k) * 0x9E3779B97F4A7C15)
	h = (h ~ (h >> 30)) * 0xBF58476D1CE4E5B9
	h = (h ~ (h >> 27)) * 0x94D049BB133111EB
	h = h ~ (h >> 31)
	return f32(h >> 40) * (1.0 / 16777216.0)
}

// Offset from the tile centre, scattered within `radius`.
jit :: proc(hex: Hex, k: int, radius: f32) -> (f32, f32) {
	return (tile_rand(hex, k) - 0.5) * 2 * radius, (tile_rand(hex, k + 101) - 0.5) * 2 * radius
}

fract :: proc(x: f32) -> f32 {
	return x - math.floor(x)
}

// Faint blotches under everything so even plain tiles have a little texture.
draw_tile_mottle :: proc(hex: Hex, cx, cy, z: f32) {
	for k in 0..<4 {
		ox, oy := jit(hex, 40 + k, 22 * z)
		r := (6.0 + tile_rand(hex, 60 + k) * 8.0) * z
		col := rl.Color{0, 0, 0, 28}
		if tile_rand(hex, 80 + k) < 0.45 {
			col = rl.Color{255, 255, 255, 20}
		}
		rl.DrawCircleV(rl.Vector2{cx + ox, cy + oy}, r, col)
	}
}

draw_tile_detail :: proc(ter: Terrain, hex: Hex, cx, cy, z: f32) {
	now := f32(rl.GetTime())
	draw_tile_mottle(hex, cx, cy, z)

	switch ter {
	case .CAVE:
		for k in 0..<5 {
			ox, oy := jit(hex, k, 20 * z)
			r := (2.8 + tile_rand(hex, k + 7) * 3.4) * z
			rl.DrawCircleV(rl.Vector2{cx + ox, cy + oy}, r, rl.Color{46, 42, 36, 210})
			rl.DrawCircleV(rl.Vector2{cx + ox - r * 0.35, cy + oy - r * 0.35}, r * 0.5, rl.Color{92, 86, 74, 190})
		}
	case .WATER:
		for k in 0..<2 {
			wob := math.sin(now * 1.6 + f32(hex.q) * 0.9 + f32(hex.r) * 0.5 + f32(k) * 2.0) * 3.5 * z
			y := cy - 6 * z + f32(k) * 11 * z + wob
			rl.DrawLineEx(rl.Vector2{cx - 14 * z, y}, rl.Vector2{cx + 14 * z, y}, 2.0 * z, rl.Color{150, 205, 245, 80})
		}
	case .GROVE:
		for k in 0..<9 {
			ox, oy := jit(hex, k, 21 * z)
			sway := math.sin(now * 1.8 + f32(hex.q) * 0.4 + f32(k) * 0.9) * 1.4 * z
			tip := (tile_rand(hex, k + 3) - 0.5) * 5 * z + sway
			rl.DrawLineEx(rl.Vector2{cx + ox, cy + oy + 4 * z}, rl.Vector2{cx + ox + tip, cy + oy - 6 * z}, 1.8 * z, rl.Color{70, 140, 74, 215})
		}
		ox, oy := jit(hex, 11, 13 * z)
		rl.DrawLineEx(rl.Vector2{cx + ox, cy + oy + 9 * z}, rl.Vector2{cx + ox, cy + oy - 2 * z}, 2.8 * z, rl.Color{92, 66, 40, 255})
		rl.DrawCircleV(rl.Vector2{cx + ox, cy + oy - 8 * z}, 9 * z, rl.Color{56, 122, 60, 255})
		rl.DrawCircleV(rl.Vector2{cx + ox - 5 * z, cy + oy - 4 * z}, 6 * z, rl.Color{76, 150, 80, 255})
	case .DUNGEON:
		for k in 0..<5 {
			ox, oy := jit(hex, k, 19 * z)
			rl.DrawLineEx(rl.Vector2{cx + ox - 6 * z, cy + oy}, rl.Vector2{cx + ox, cy + oy - 3 * z}, 1.7 * z, rl.Color{40, 30, 46, 205})
			rl.DrawLineEx(rl.Vector2{cx + ox, cy + oy - 3 * z}, rl.Vector2{cx + ox + 6 * z, cy + oy + 2 * z}, 1.7 * z, rl.Color{40, 30, 46, 205})
		}
	case .MUSHROOM:
		for k in 0..<4 {
			ox, oy := jit(hex, k, 20 * z)
			bob := math.sin(now * 2.0 + f32(k) * 1.7) * 1.3 * z
			rl.DrawLineEx(rl.Vector2{cx + ox, cy + oy + 4 * z}, rl.Vector2{cx + ox, cy + oy - 3 * z + bob}, 2.2 * z, rl.Color{206, 198, 180, 255})
			rl.DrawCircleV(rl.Vector2{cx + ox, cy + oy - 4 * z + bob}, 4.2 * z, rl.Color{168, 96, 150, 255})
			rl.DrawCircleV(rl.Vector2{cx + ox - 1.5 * z, cy + oy - 5.5 * z + bob}, 1.4 * z, rl.Color{224, 176, 208, 255})
		}
	case .RUINS:
		for k in 0..<3 {
			ox, oy := jit(hex, k, 18 * z)
			h := (8 + tile_rand(hex, k + 6) * 9) * z
			rl.DrawRectangleRec(rl.Rectangle{cx + ox - 4 * z, cy + oy - h, 8 * z, h}, rl.Color{112, 106, 94, 255})
			rl.DrawRectangleRec(rl.Rectangle{cx + ox - 5.5 * z, cy + oy - h - 3 * z, 11 * z, 3 * z}, rl.Color{134, 128, 114, 255})
			rl.DrawLineEx(rl.Vector2{cx + ox, cy + oy - h + 2 * z}, rl.Vector2{cx + ox + 2 * z, cy + oy - h + 6 * z}, 1.2 * z, rl.Color{88, 82, 72, 200})
		}
	case .TUNDRA:
		for k in 0..<7 {
			ox, oy := jit(hex, k, 22 * z)
			rl.DrawCircleV(rl.Vector2{cx + ox, cy + oy}, 1.4 * z, rl.Color{255, 255, 255, 215})
		}
		rl.DrawTriangle(rl.Vector2{cx - 3.5 * z, cy + 7 * z}, rl.Vector2{cx + 3.5 * z, cy + 7 * z}, rl.Vector2{cx, cy - 8 * z}, rl.Color{196, 228, 246, 215})
	case .JUNGLE:
		for k in 0..<13 {
			ox, oy := jit(hex, k, 22 * z)
			sway := math.sin(now * 1.6 + f32(hex.r) * 0.4 + f32(k) * 0.8) * 1.3 * z
			tip := (tile_rand(hex, k + 3) - 0.5) * 5 * z + sway
			rl.DrawLineEx(rl.Vector2{cx + ox, cy + oy + 5 * z}, rl.Vector2{cx + ox + tip, cy + oy - 6 * z}, 1.8 * z, rl.Color{34, 94, 46, 235})
		}
	case .LAVA:
		pulse := 0.5 + 0.5 * math.sin(now * 2.2)
		for k in 0..<4 {
			ox, oy := jit(hex, k, 18 * z)
			rl.DrawLineEx(rl.Vector2{cx + ox - 7 * z, cy + oy}, rl.Vector2{cx + ox, cy + oy - 4 * z}, 2.2 * z, rl.Color{255, 150, 50, u8(120 + 120 * pulse)})
			rl.DrawLineEx(rl.Vector2{cx + ox, cy + oy - 4 * z}, rl.Vector2{cx + ox + 7 * z, cy + oy + 2 * z}, 2.2 * z, rl.Color{255, 110, 40, u8(100 + 120 * pulse)})
		}
	case .DESERT:
		for k in 0..<5 {
			ox, oy := jit(hex, k, 20 * z)
			rl.DrawLineEx(rl.Vector2{cx + ox - 8 * z, cy + oy}, rl.Vector2{cx + ox, cy + oy - 3 * z}, 1.6 * z, rl.Color{150, 128, 80, 170})
			rl.DrawLineEx(rl.Vector2{cx + ox, cy + oy - 3 * z}, rl.Vector2{cx + ox + 8 * z, cy + oy}, 1.6 * z, rl.Color{150, 128, 80, 170})
		}
	case .QUICKSAND:
		for k in 0..<4 {
			rl.DrawCircleLinesV(rl.Vector2{cx, cy}, (4 + f32(k) * 5.5) * z, rl.Color{118, 102, 66, 160})
		}
		a := now * 0.8
		rl.DrawLineEx(rl.Vector2{cx, cy}, rl.Vector2{cx + math.cos(a) * 17 * z, cy + math.sin(a) * 17 * z}, 1.8 * z, rl.Color{118, 102, 66, 170})
	case .TRADING_POST:
		rl.DrawRectangleRec(rl.Rectangle{cx - 12 * z, cy + 2 * z, 24 * z, 9 * z}, rl.Color{120, 92, 52, 255})
		for k in 0..<5 {
			col := k % 2 == 0 ? rl.Color{210, 90, 80, 255} : rl.Color{230, 220, 200, 255}
			rl.DrawRectangleRec(rl.Rectangle{cx - 13 * z + f32(k) * 5.2 * z, cy - 9 * z, 5.2 * z, 8 * z}, col)
		}
		rl.DrawLineEx(rl.Vector2{cx - 12 * z, cy - 9 * z}, rl.Vector2{cx + 12 * z, cy - 9 * z}, 1.5 * z, rl.Color{150, 120, 70, 255})
	case .BOSS_ROOM:
		rl.DrawCircleV(rl.Vector2{cx, cy - 1 * z}, 9 * z, rl.Color{120, 40, 44, 255})
		rl.DrawCircleV(rl.Vector2{cx - 3.4 * z, cy - 2.5 * z}, 2.4 * z, rl.Color{20, 8, 10, 255})
		rl.DrawCircleV(rl.Vector2{cx + 3.4 * z, cy - 2.5 * z}, 2.4 * z, rl.Color{20, 8, 10, 255})
		rl.DrawLineEx(rl.Vector2{cx - 4 * z, cy + 4 * z}, rl.Vector2{cx + 4 * z, cy + 4 * z}, 1.6 * z, rl.Color{20, 8, 10, 255})
	case .ARENA:
		// A ringed fighting pit with crossed blades.
		rl.DrawCircleLinesV(rl.Vector2{cx, cy}, 15 * z, rl.Color{198, 162, 86, 230})
		rl.DrawCircleLinesV(rl.Vector2{cx, cy}, 11 * z, rl.Color{150, 116, 60, 200})
		rl.DrawLineEx(rl.Vector2{cx - 6 * z, cy + 6.5 * z}, rl.Vector2{cx + 6 * z, cy - 5.5 * z}, 2.0 * z, rl.Color{214, 218, 228, 235})
		rl.DrawLineEx(rl.Vector2{cx + 6 * z, cy + 6.5 * z}, rl.Vector2{cx - 6 * z, cy - 5.5 * z}, 2.0 * z, rl.Color{214, 218, 228, 235})
	case .CRYSTAL_COVE:
		// A cluster of glowing crystal shards.
		pulse := 0.5 + 0.5 * math.sin(now * 1.8 + f32(hex.q) * 0.6)
		rl.DrawCircleV(rl.Vector2{cx, cy}, 15 * z, rl.Color{140, 170, 255, u8(26 + 18 * pulse)})
		for k in 0..<5 {
			ox, oy := jit(hex, k, 16 * z)
			h := (10 + tile_rand(hex, k + 4) * 11) * z
			w := (3.6 + tile_rand(hex, k + 9) * 1.8) * z
			base := rl.Color{150, 182, 250, 255}
			top := rl.Color{212, 230, 255, u8(210 + 45 * pulse)}
			rl.DrawTriangle(rl.Vector2{cx + ox - w, cy + oy + 5 * z}, rl.Vector2{cx + ox + w, cy + oy + 5 * z}, rl.Vector2{cx + ox, cy + oy + 5 * z - h}, base)
			rl.DrawLineEx(rl.Vector2{cx + ox, cy + oy + 5 * z - h}, rl.Vector2{cx + ox, cy + oy - 1 * z}, 1.4 * z, top)
		}
	}
}

// Ambient motes drifting over a tile — embers, bubbles, spores, snow, pollen.
// Stateless: every mote is a pure function of the hex and the clock, so there is
// no particle bookkeeping and nothing to allocate or clean up.
draw_tile_ambient :: proc(ter: Terrain, hex: Hex, cx, cy, z: f32, now: f32) {
	#partial switch ter {
	case .LAVA:
		for k in 0..<3 {
			spd := 0.18 + tile_rand(hex, 210 + k) * 0.30
			p := fract(now * spd + tile_rand(hex, 200 + k))
			ox := (tile_rand(hex, 220 + k) - 0.5) * 26 * z + math.sin((p + f32(k)) * 6.283) * 3.5 * z
			oy := 14 * z - p * 30 * z
			a := u8((1.0 - p) * 220)
			rl.DrawCircleV(rl.Vector2{cx + ox, cy + oy}, (1.0 + tile_rand(hex, 230 + k) * 1.4) * z, rl.Color{255, 170, 70, a})
		}
	case .WATER:
		for k in 0..<2 {
			spd := 0.12 + tile_rand(hex, 210 + k) * 0.18
			p := fract(now * spd + tile_rand(hex, 200 + k))
			ox := (tile_rand(hex, 220 + k) - 0.5) * 22 * z
			oy := 10 * z - p * 22 * z
			a := u8(math.sin(p * 3.14159) * 150)
			rl.DrawCircleLinesV(rl.Vector2{cx + ox, cy + oy}, (1.6 + tile_rand(hex, 230 + k)) * z, rl.Color{190, 225, 250, a})
		}
	case .MUSHROOM:
		for k in 0..<3 {
			spd := 0.10 + tile_rand(hex, 210 + k) * 0.16
			p := fract(now * spd + tile_rand(hex, 200 + k))
			ox := (tile_rand(hex, 220 + k) - 0.5) * 28 * z + math.sin((p + f32(k) * 1.7) * 6.283) * 4 * z
			oy := -4 * z - p * 20 * z
			a := u8((1.0 - p) * 170)
			rl.DrawCircleV(rl.Vector2{cx + ox, cy + oy}, 1.4 * z, rl.Color{222, 176, 224, a})
		}
	case .TUNDRA:
		for k in 0..<3 {
			spd := 0.06 + tile_rand(hex, 210 + k) * 0.10
			p := fract(now * spd + tile_rand(hex, 200 + k))
			ox := (tile_rand(hex, 220 + k) - 0.5) * 30 * z + p * 8 * z
			oy := 14 * z - p * 30 * z
			a := u8((1.0 - p) * 200)
			rl.DrawCircleV(rl.Vector2{cx + ox, cy + oy}, 1.3 * z, rl.Color{235, 245, 255, a})
		}
	case .GROVE, .JUNGLE:
		for k in 0..<3 {
			spd := 0.08 + tile_rand(hex, 210 + k) * 0.14
			p := fract(now * spd + tile_rand(hex, 200 + k))
			ox := (tile_rand(hex, 220 + k) - 0.5) * 30 * z + math.sin((p + f32(k)) * 6.283) * 5 * z
			oy := -2 * z - p * 22 * z
			a := u8((1.0 - p) * 150)
			rl.DrawCircleV(rl.Vector2{cx + ox, cy + oy}, 1.2 * z, rl.Color{180, 230, 150, a})
		}
	case:
	}
}
