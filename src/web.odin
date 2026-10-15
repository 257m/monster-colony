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

		audio_init()

		web_game.seed_rng = rng_make(u64(time.now()._nsec))
		web_game.selected = -1
		web_game.attack_ids = make([dynamic]int, 0)
		web_game.attack_chosen = make([dynamic]bool, 0)
		web_game.unit_picker_ids = make([dynamic]int, 0)
		web_game.summary = make([dynamic]string, 0)
		web_game.show_minimap = true
		web_game.tooltips_on = true
		web_game.autosave_on = true
		web_game.show_terrain_legend = true
		web_game.show_key_hints = true
		web_game.ring_total = make(map[u64]int)
		web_game.ring_seen = make(map[u64]int)
		hex_renderer_init(&web_game.renderer, 46.0, int(screen_w()), int(screen_h()))
		goto_title(&web_game)
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
		web_game.renderer.origin_x = f32(screen_w()) / 2
		web_game.renderer.origin_y = f32(screen_h()) / 2

		audio_update()
		game_update(&web_game, dt)

		screen_begin()
		game_draw(&web_game)
		screen_end()
		return true
	}

	@(export)
	main_end :: proc "c" () {
		context = web_context
		if web_ready {
			end_run(&web_game)
			delete(web_game.attack_ids)
			delete(web_game.attack_chosen)
			delete(web_game.unit_picker_ids)
			for s in web_game.summary { delete(s) }
			delete(web_game.summary)
			delete(web_game.ring_total)
			delete(web_game.ring_seen)
			audio_shutdown()
			web_ready = false
		}
		rl.CloseWindow()
	}

	@(export)
	web_window_size_changed :: proc "c" (w, h: c.int) {
		context = web_context
		// Match the render target to the browser viewport so the game fills the
		// screen (and reflows on resize / fullscreen). rl.GetScreenWidth/Height
		// then report the new size to the game's layout.
		if web_ready && w > 0 && h > 0 {
			rl.SetWindowSize(w, h)
		}
	}
}
