package main

// ============================================================================
// PROCEDURAL HEX DUNGEON MAP
//
// The map is an organic cavern grown on the hex grid. Growth is biased
// downward so the dungeon descends into the underground. Difficulty tiers are
// derived from BFS distance from the entrance, and the boss is placed at the
// deepest reachable hex.
// ============================================================================

Node_Type :: enum {
	START,
	COMBAT,
	ELITE,
	REST,
	SHOP,
	EVENT,
	BOSS,
}

Map_Node :: struct {
	hex:         Hex,
	kind:        Node_Type,
	depth:       int,                 // BFS distance from the entrance
	connections: [dynamic]Hex,        // adjacent hexes that are part of the map
	revealed:    bool,
	visited:     bool,
	cleared:     bool,                // its encounter (if any) has been resolved
}

Map_Graph :: struct {
	nodes:       [dynamic]Map_Node,
	start_hex:   Hex,
	boss_hex:    Hex,
	current_hex: Hex,
	max_depth:   int,
	seed:        u64,
}

Map_Config :: struct {
	target_size: int,   // how many hexes to grow
	half_width:  int,   // max |q|
	min_y:       f32,   // vertical bounds in "row" units (wy = r + q/2)
	max_y:       f32,
}

default_map_config :: proc() -> Map_Config {
	return Map_Config{
		target_size = 44,
		half_width  = 5,
		min_y       = -1.0,
		max_y       = 9.0,
	}
}

// ----------------------------------------------------------------------------
// Construction helpers
// ----------------------------------------------------------------------------

make_node :: proc(hex: Hex, kind: Node_Type, depth: int) -> Map_Node {
	return Map_Node{
		hex  = hex,
		kind = kind,
		depth = depth,
		connections = make([dynamic]Hex, 0),
	}
}

map_free :: proc(g: ^Map_Graph) {
	for i in 0..<len(g.nodes) {
		delete(g.nodes[i].connections)
	}
	delete(g.nodes)
}

map_find :: proc(g: ^Map_Graph, hex: Hex) -> int {
	for n, i in g.nodes {
		if hex_equal(n.hex, hex) {
			return i
		}
	}
	return -1
}

region_contains :: proc(region: []Hex, hex: Hex) -> bool {
	for h in region {
		if hex_equal(h, hex) {
			return true
		}
	}
	return false
}

approx_y :: proc(hex: Hex) -> f32 {
	return f32(hex.r) + 0.5 * f32(hex.q)
}

// ----------------------------------------------------------------------------
// Generation
// ----------------------------------------------------------------------------

generate_map :: proc(seed: u64, cfg: Map_Config) -> Map_Graph {
	rng := rng_make(seed)

	g := Map_Graph{seed = seed}
	g.nodes = make([dynamic]Map_Node, 0)

	// 1. Grow the cavern.
	region := grow_region(&rng, cfg)
	defer delete(region)

	for hex in region {
		append(&g.nodes, make_node(hex, .COMBAT, 0))
	}

	g.start_hex = Hex{0, 0}

	// 2. Connect adjacent hexes.
	build_connections(&g)

	// 3. Depth (difficulty tier) via BFS from the entrance.
	compute_depths(&g)

	// 4. Choose the boss at the deepest point.
	boss_i := 0
	for n, i in g.nodes {
		if n.depth > g.nodes[boss_i].depth {
			boss_i = i
		}
	}
	g.boss_hex = g.nodes[boss_i].hex
	g.max_depth = g.nodes[boss_i].depth
	g.nodes[boss_i].kind = .BOSS
	g.nodes[map_find(&g, g.start_hex)].kind = .START

	// 5. Assign node types everywhere else.
	for i in 0..<len(g.nodes) {
		node := &g.nodes[i]
		if node.kind == .BOSS || node.kind == .START {
			continue
		}
		if node.depth < 0 {
			node.kind = .EVENT
			continue
		}
		if is_neighbor_of(&g, i, g.boss_hex) {
			node.kind = .REST // campfire guarding the boss
			continue
		}
		progress := f32(node.depth) / f32(max(g.max_depth, 1))
		node.kind = pick_node_kind(&rng, progress)
	}

	// 6. Reveal the entrance area.
	g.current_hex = g.start_hex
	start_i := map_find(&g, g.start_hex)
	g.nodes[start_i].revealed = true
	g.nodes[start_i].visited = true
	reveal_around(&g, g.start_hex)

	return g
}

grow_region :: proc(rng: ^Rng, cfg: Map_Config) -> [dynamic]Hex {
	region := make([dynamic]Hex, 0)
	append(&region, Hex{0, 0})

	for len(region) < cfg.target_size {
		cands := make([dynamic]Hex, 0)
		weights := make([dynamic]f32, 0)

		for h in region {
			for n in hex_neighbors(h) {
				if region_contains(region[:], n) || region_contains(cands[:], n) {
					continue
				}
				if abs(n.q) > cfg.half_width {
					continue
				}
				wy := approx_y(n)
				if wy < cfg.min_y || wy > cfg.max_y {
					continue
				}
				// Bias growth downward, with a little randomness.
				w := 1.0 + 0.6 * max(f32(0.0), wy) + 0.25 * rng_f32(rng)
				append(&cands, n)
				append(&weights, w)
			}
		}

		if len(cands) == 0 {
			break
		}

		total := f32(0.0)
		for w in weights {
			total += w
		}
		roll := rng_f32(rng) * total
		chosen := 0
		acc := f32(0.0)
		for w, i in weights {
			acc += w
			if roll < acc {
				chosen = i
				break
			}
		}
		append(&region, cands[chosen])

		delete(cands)
		delete(weights)
	}

	return region
}

build_connections :: proc(g: ^Map_Graph) {
	for i in 0..<len(g.nodes) {
		for n in hex_neighbors(g.nodes[i].hex) {
			if map_find(g, n) >= 0 {
				append(&g.nodes[i].connections, n)
			}
		}
	}
}

compute_depths :: proc(g: ^Map_Graph) {
	n := len(g.nodes)
	visited := make([]bool, n)
	defer delete(visited)
	dist := make([]int, n)
	defer delete(dist)
	for i in 0..<n {
		dist[i] = -1
	}

	start := map_find(g, Hex{0, 0})
	if start < 0 {
		return
	}

	queue := make([dynamic]int, 0)
	defer delete(queue)
	append(&queue, start)
	dist[start] = 0

	head := 0
	for head < len(queue) {
		cur := queue[head]
		head += 1
		for c in g.nodes[cur].connections {
			j := map_find(g, c)
			if j >= 0 && dist[j] < 0 {
				dist[j] = dist[cur] + 1
				append(&queue, j)
			}
		}
	}

	for i in 0..<n {
		g.nodes[i].depth = dist[i]
	}
}

is_neighbor_of :: proc(g: ^Map_Graph, node_index: int, hex: Hex) -> bool {
	for c in g.nodes[node_index].connections {
		if hex_equal(c, hex) {
			return true
		}
	}
	return false
}

pick_node_kind :: proc(rng: ^Rng, progress: f32) -> Node_Type {
	combat: f32 = 42.0
	elite: f32 = 6.0 + 16.0 * progress
	rest: f32 = 11.0
	shop: f32 = 9.0
	event: f32 = 18.0

	if progress < 0.15 {
		elite = 0.0
		rest *= 0.2
		shop *= 0.2
	}

	total := combat + elite + rest + shop + event
	roll := rng_f32(rng) * total

	if roll < combat { return .COMBAT }
	roll -= combat
	if roll < elite { return .ELITE }
	roll -= elite
	if roll < rest { return .REST }
	roll -= rest
	if roll < shop { return .SHOP }
	return .EVENT
}

// ----------------------------------------------------------------------------
// Navigation / fog of war
// ----------------------------------------------------------------------------

reveal_around :: proc(g: ^Map_Graph, hex: Hex) {
	idx := map_find(g, hex)
	if idx < 0 {
		return
	}
	for c in g.nodes[idx].connections {
		j := map_find(g, c)
		if j >= 0 {
			g.nodes[j].revealed = true
		}
	}
}

map_get :: proc(g: ^Map_Graph, hex: Hex) -> ^Map_Node {
	idx := map_find(g, hex)
	if idx < 0 {
		return nil
	}
	return &g.nodes[idx]
}

map_node_at :: proc(g: ^Map_Graph, hex: Hex) -> (Map_Node, bool) {
	idx := map_find(g, hex)
	if idx < 0 {
		return {}, false
	}
	return g.nodes[idx], true
}

is_current :: proc(g: ^Map_Graph, hex: Hex) -> bool {
	return hex_equal(g.current_hex, hex)
}

is_visited :: proc(g: ^Map_Graph, hex: Hex) -> bool {
	n := map_get(g, hex)
	return n != nil && n.visited
}

is_revealed :: proc(g: ^Map_Graph, hex: Hex) -> bool {
	n := map_get(g, hex)
	return n != nil && n.revealed
}

map_node_kind :: proc(g: ^Map_Graph, hex: Hex) -> Node_Type {
	n := map_get(g, hex)
	if n == nil {
		return .COMBAT
	}
	return n.kind
}

// Civ-style movement: any adjacent tile in the map can be entered, whether or
// not it has been visited before (backtracking allowed).
can_travel_to :: proc(g: ^Map_Graph, target: Hex) -> bool {
	cur := map_get(g, g.current_hex)
	if cur == nil {
		return false
	}
	if hex_equal(target, g.current_hex) {
		return false
	}
	for c in cur.connections {
		if hex_equal(c, target) {
			return true
		}
	}
	return false
}

is_cleared :: proc(g: ^Map_Graph, hex: Hex) -> bool {
	n := map_get(g, hex)
	return n != nil && n.cleared
}

clear_node :: proc(g: ^Map_Graph, hex: Hex) {
	if n := map_get(g, hex); n != nil {
		n.cleared = true
	}
}

travel_to :: proc(g: ^Map_Graph, target: Hex) -> bool {
	if !can_travel_to(g, target) {
		return false
	}

	if cur := map_get(g, g.current_hex); cur != nil {
		cur.visited = true
	}

	g.current_hex = target
	if dst := map_get(g, target); dst != nil {
		dst.visited = true
		dst.revealed = true
	}

	reveal_around(g, target)
	return true
}

map_available_moves :: proc(g: ^Map_Graph) -> [dynamic]Hex {
	moves := make([dynamic]Hex, 0)
	if cur := map_get(g, g.current_hex); cur != nil {
		for c in cur.connections {
			if can_travel_to(g, c) {
				append(&moves, c)
			}
		}
	}
	return moves
}
