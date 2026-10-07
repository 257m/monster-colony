package main

// A tiny self-contained deterministic PRNG (SplitMix64) so the project does not
// depend on any specific version of core:math/rand.

Rng :: struct {
	state: u64,
}

rng_make :: proc(seed: u64) -> Rng {
	s := seed
	if s == 0 {
		s = 0x9E3779B97F4A7C15
	}
	return Rng{state = s}
}

rng_next_u64 :: proc(r: ^Rng) -> u64 {
	r.state += 0x9E3779B97F4A7C15
	z := r.state
	z = (z ~ (z >> 30)) * 0xBF58476D1CE4E5B9
	z = (z ~ (z >> 27)) * 0x94D049BB133111EB
	return z ~ (z >> 31)
}

// Uniform float in [0, 1).
rng_f32 :: proc(r: ^Rng) -> f32 {
	return f32(rng_next_u64(r) >> 40) * (1.0 / 16777216.0)
}

// Uniform int in [lo, hi).
rng_range :: proc(r: ^Rng, lo, hi: int) -> int {
	if hi <= lo {
		return lo
	}
	return lo + int(rng_next_u64(r) % u64(hi - lo))
}

// Uniform int in [0, n).
rng_below :: proc(r: ^Rng, n: int) -> int {
	if n <= 0 {
		return 0
	}
	return int(rng_next_u64(r) % u64(n))
}

rng_chance :: proc(r: ^Rng, p: f32) -> bool {
	return rng_f32(r) < p
}
