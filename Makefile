ODIN ?= odin
SRC  := src
BIN  := bin

.PHONY: run build check clean web serve

# Run the game directly (compiles + executes).
run:
	$(ODIN) run $(SRC)

# Build a standalone executable into bin/.
build:
	@mkdir -p $(BIN)
	$(ODIN) build $(SRC) -out:$(BIN)/monster-colony -o:speed

# Type/compile check without running.
check:
	$(ODIN) check $(SRC)

# Build the browser (WebAssembly) version into build/web/ (needs emscripten).
web:
	./web/build_web.sh

# Serve the web build at http://localhost:8000/ (WASM can't load from file://).
serve: web
	cd build/web && python3 -m http.server 8000

clean:
	rm -rf $(BIN) build
