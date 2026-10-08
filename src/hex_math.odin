package main

import "core:math"

// ============================================================================
// AXIAL HEX COORDINATES (q, r) - Flat-top orientation
//
// Screen layout for flat-top hexes:
//   world_x = 1.5 * size * q
//   world_y = sqrt(3) * size * (r + q/2)
//
// Neighbor directions (flat-top), clockwise starting East:
//   E (+1, 0)   NE (+1,-1)   NW (0,-1)
//   W (-1, 0)   SW (-1,+1)   SE (0,+1)
// ============================================================================

Hex :: struct {
	q: int,
	r: int,
}

HEX_DIRECTIONS: [6]Hex = {
	{+1,  0}, // 0 E
	{+1, -1}, // 1 NE
	{ 0, -1}, // 2 NW
	{-1,  0}, // 3 W
	{-1, +1}, // 4 SW
	{ 0, +1}, // 5 SE
}

hex_add :: proc(a, b: Hex) -> Hex {
	return Hex{q = a.q + b.q, r = a.r + b.r}
}

hex_sub :: proc(a, b: Hex) -> Hex {
	return Hex{q = a.q - b.q, r = a.r - b.r}
}

hex_scale :: proc(h: Hex, k: int) -> Hex {
	return Hex{q = h.q * k, r = h.r * k}
}

hex_neg :: proc(h: Hex) -> Hex {
	return Hex{q = -h.q, r = -h.r}
}

hex_equal :: proc(a, b: Hex) -> bool {
	return a.q == b.q && a.r == b.r
}

hex_neighbor :: proc(hex: Hex, direction: int) -> Hex {
	return hex_add(hex, HEX_DIRECTIONS[direction])
}

hex_neighbors :: proc(hex: Hex) -> [6]Hex {
	result: [6]Hex
	for i in 0..<6 {
		result[i] = hex_neighbor(hex, i)
	}
	return result
}

// Cube coordinates: x = q, z = r, y = -x - z
hex_to_cube :: proc(h: Hex) -> (x, y, z: int) {
	x = h.q
	z = h.r
	y = -x - z
	return
}

hex_distance :: proc(a, b: Hex) -> int {
	ax, ay, az := hex_to_cube(a)
	bx, by, bz := hex_to_cube(b)
	return max(abs(ax - bx), max(abs(ay - by), abs(az - bz)))
}

// Round fractional axial coordinates to the nearest hex.
hex_round_axial :: proc(q_f, r_f: f32) -> Hex {
	x := q_f
	z := r_f
	y := -x - z

	rx := int(math.round(x))
	ry := int(math.round(y))
	rz := int(math.round(z))

	dx := abs(f32(rx) - x)
	dy := abs(f32(ry) - y)
	dz := abs(f32(rz) - z)

	if dx > dy && dx > dz {
		rx = -ry - rz
	} else if dy > dz {
		ry = -rx - rz
	} else {
		rz = -rx - ry
	}
	return Hex{q = rx, r = rz}
}
