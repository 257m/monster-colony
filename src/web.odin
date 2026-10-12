package main

import rl "vendor:raylib"
import "core:c"
import "core:time"
import "core:mem"
import "base:runtime"

// ============================================================================
// WEB (js_wasm32) ENTRY
//
// The browser drives the frame loop through these exports (see
// web/index_template.html). Desktop uses `main` in main.odin instead. Build
// with `make web`, then serve build/web/ over http.
// ============================================================================

when ODIN_ARCH == .wasm32 || ODIN_ARCH == .wasm64p32 {

	@(private = "file")
	web_game: Game
	@(private = "file")
	web_context: runtime.Context
	@(private = "file")
	web_ready: bool

	// Called once after the WASM module is ready (from index.html).
	@(export)
	main_start :: proc "c" () {
		context = runtime.default_context()
		// The default Odin WASM allocator grows linear memory directly, which
		// detaches emscripten's cached JS views. Route all allocation (including
		// the temporary allocator) through emscripten's malloc instead.
		context.allocator = emscripten_allocator()
		runtime.init_global_temporary_allocator(2 * mem.Megabyte)
		web_context = context

		rl.InitWindow(1280, 720, "Monster Colony")
		rl.SetExitKey(.KEY_NULL)
		rl.SetTargetFPS(60)

		web_game.seed_rng = rng_make(u64(time.now()._nsec))
		web_game.selected = -1
		web_game.attack_ids = make([dynamic]int, 0)
		web_game.attack_chosen = make([dynamic]bool, 0)
		hex_renderer_init(&web_game.renderer, 46.0, int(rl.GetScreenWidth()), int(rl.GetScreenHeight()))
		reset_to_starter(&web_game)
		web_ready = true
	}

	// Called once per animation frame; return false to stop the loop.
	@(export)
	main_update :: proc "c" () -> bool {
		context = web_context
		if !web_ready {
			return false
		}
		dt := rl.GetFrameTime()
		web_game.renderer.origin_x = f32(rl.GetScreenWidth()) / 2
		web_game.renderer.origin_y = f32(rl.GetScreenHeight()) / 2

		game_update(&web_game, dt)

		rl.BeginDrawing()
		game_draw(&web_game)
		rl.EndDrawing()
		return true
	}

	@(export)
	main_end :: proc "c" () {
		context = web_context
		if web_ready {
			end_run(&web_game)
			web_ready = false
		}
		rl.CloseWindow()
	}

	@(export)
	web_window_size_changed :: proc "c" (w, h: c.int) {
		context = web_context
		// The renderer reads rl.GetScreenWidth/Height every frame, so nothing
		// to do here yet.
	}
}
