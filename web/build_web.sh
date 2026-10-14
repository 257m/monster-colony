#!/usr/bin/env bash
# Build the browser (WebAssembly) version of Monster Colony.
#
# Needs Emscripten. The script looks for `emcc` on PATH, then in EMSDK_DIR, then
# in a few common emsdk locations. If it still can't find it you can either set
# EMSDK_DIR=/path/to/emsdk, or run `EMSDK_AUTO_INSTALL=1 make web` to have it
# download emsdk into ./.emsdk automatically.
#
# Output goes to build/web/ ; serve that folder over http (see below) because
# browsers block WASM loaded from file:// .
set -euo pipefail

cd "$(dirname "$0")/.."

OUT="build/web"
ODIN_PATH="$(odin root)"

# --- locate Emscripten -----------------------------------------------------
locate_emcc() {
	if command -v emcc >/dev/null 2>&1; then
		return 0
	fi
	local candidates=(
		"${EMSDK_DIR:-}"
		"$HOME/emsdk"
		"$HOME/.emsdk"
		"/opt/emsdk"
		"/usr/local/emsdk"
		"$PWD/.emsdk"
	)
	local d
	for d in "${candidates[@]}"; do
		if [ -n "$d" ] && [ -f "$d/emsdk_env.sh" ]; then
			# shellcheck disable=SC1090
			source "$d/emsdk_env.sh" >/dev/null 2>&1 || true
			if command -v emcc >/dev/null 2>&1; then
				return 0
			fi
		fi
	done
	return 1
}

if ! locate_emcc; then
	if [ "${EMSDK_AUTO_INSTALL:-0}" = "1" ]; then
		echo "Emscripten not found - installing emsdk into ./.emsdk (a few hundred MB)..."
		git clone --depth 1 https://github.com/emscripten-core/emsdk.git .emsdk
		(
			cd .emsdk
			./emsdk install latest
			./emsdk activate latest
		)
		# shellcheck disable=SC1090
		source "$PWD/.emsdk/emsdk_env.sh" >/dev/null 2>&1
	fi
fi

if ! command -v emcc >/dev/null 2>&1; then
	cat >&2 <<'EOF'
error: emcc not found - Emscripten is required for the web build.

Install it one of these ways:

  1) Automatic (downloads emsdk into ./.emsdk):
         EMSDK_AUTO_INSTALL=1 make web

  2) Manual install, then point the build at it:
         git clone https://github.com/emscripten-core/emsdk.git ~/emsdk
         cd ~/emsdk && ./emsdk install latest && ./emsdk activate latest
         EMSDK_DIR=~/emsdk make web

  3) Install emscripten with your package manager / system image so that
     `emcc` is on PATH, then run `make web`.

More: https://emscripten.org/docs/getting_started/downloads.html
EOF
	exit 1
fi

mkdir -p "$OUT"

# Odin ships its raylib web lib via git-LFS, which is often just a pointer.
# Fetch the real one into web/lib/ if we don't already have it.
RL_LIB="web/lib/libraylib.web.a"
if [ ! -s "$RL_LIB" ] || head -c 8 "$RL_LIB" | grep -q "version "; then
	echo "Fetching raylib web library..."
	mkdir -p web/lib
	curl -fsSL -o "$RL_LIB" \
		"https://media.githubusercontent.com/media/odin-lang/Odin/master/vendor/raylib/wasm/libraylib.web.a"
fi

echo "Compiling Odin -> wasm object..."
# -define:RAYLIB_WASM_LIB=env.o tells Odin not to link raylib itself; emcc links
# the real library below.
odin build src \
	-target:js_wasm32 \
	-build-mode:obj \
	-define:RAYLIB_WASM_LIB=env.o \
	-out:"$OUT/game.wasm.o"

echo "Copying Odin web runtime..."
cp "$ODIN_PATH/core/sys/wasm/js/odin.js" "$OUT/odin.js"

echo "Linking with emscripten (emcc)..."
emcc -o "$OUT/index.html" \
	"$OUT/game.wasm.o" \
	"$RL_LIB" \
	--preload-file assets/font.ttf \
	-sUSE_GLFW=3 \
	-sWARN_ON_UNDEFINED_SYMBOLS=0 \
	-sASSERTIONS \
	--shell-file web/index_template.html

rm -f "$OUT/game.wasm.o"

echo
echo "Web build created in $OUT/"
echo "Serve it (WASM needs http, not file://):"
echo "    cd $OUT && python3 -m http.server 8000"
echo "then open http://localhost:8000/"
