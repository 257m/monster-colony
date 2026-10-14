package main

import rl "vendor:raylib"
import "core:fmt"
import "core:c"

// ============================================================================
// SHADERS
//
// A single fragment shader draws the whole "card face": a rounded panel with a
// rarity frame, an element gradient, a holographic sheen, sparkles and a
// mouse-following highlight. Desktop builds compile GLSL 330; the browser build
// is OpenGL ES 2.0, so it gets GLSL 100. If the shader fails to load the callers
// fall back to plain primitives.
// ============================================================================

when ODIN_ARCH == .wasm32 || ODIN_ARCH == .wasm64p32 {
	GLSL_VS_HEADER :: "#version 100\n#define VATTR attribute\n#define VOUT varying\n"
	GLSL_FS_HEADER :: "#version 100\nprecision mediump float;\n#define VIN varying\n#define FRAG_OUT gl_FragColor\n"
} else {
	GLSL_VS_HEADER :: "#version 330\n#define VATTR in\n#define VOUT out\n"
	GLSL_FS_HEADER :: "#version 330\n#define VIN in\nout vec4 fragOut;\n#define FRAG_OUT fragOut\n"
}

CARD_VS_SRC :: `
VATTR vec3 vertexPosition;
VATTR vec2 vertexTexCoord;
VATTR vec4 vertexColor;
uniform mat4 mvp;
VOUT vec2 fragTexCoord;
VOUT vec4 fragColor;
void main() {
	fragTexCoord = vertexTexCoord;
	fragColor = vertexColor;
	gl_Position = mvp * vec4(vertexPosition, 1.0);
}
`

CARD_FS_SRC :: `
VIN vec2 fragTexCoord;
VIN vec4 fragColor;
uniform vec3  uElement;
uniform vec3  uFrame;
uniform float uRarity;   // 0 = common .. 1 = legendary
uniform float uTime;
uniform float uHover;    // 0 or 1
uniform vec2  uSize;     // panel size in pixels
uniform vec2  uMouse;    // cursor in local 0..1 coords

float sdf(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void main() {
	vec2 uv = fragTexCoord;
	vec2 hs = uSize * 0.5;
	vec2 p = (uv - 0.5) * uSize;
	float rr = min(uSize.x, uSize.y) * 0.15;
	float outer = sdf(p, hs - vec2(rr), rr);
	float face  = sdf(p, hs - vec2(rr * 0.55 + 3.0), rr * 0.72);

	// Element gradient + inner glow.
	vec3 top = uElement * 0.95 + 0.06;
	vec3 bot = uElement * 0.30 + vec3(0.02, 0.02, 0.05);
	vec3 col = mix(top, bot, uv.y);
	col += uElement * (1.0 - smoothstep(0.0, 0.55, length(uv - vec2(0.5, 0.34)))) * 0.22;

	// Holographic sweep (rarity gated) + rainbow + sparkles.
	float band = sin((uv.x * 7.0 + uv.y * 5.0) - uTime * 2.2);
	float holo = smoothstep(0.55, 1.0, band) * uRarity;
	vec3 rainbow = 0.5 + 0.5 * cos(uTime * 1.3 + uv.x * 7.0 + vec3(0.0, 2.1, 4.2));
	col += rainbow * holo * 0.5;
	float h = fract(sin(dot(floor(uv * 34.0), vec2(12.9898, 78.233))) * 43758.5453 + floor(uTime * 6.0));
	col += step(0.986, h) * uRarity * 0.8;

	// Cursor highlight.
	col += (1.0 - smoothstep(0.0, 0.55, distance(uv, uMouse))) * uHover * 0.30;

	// Frame vs face, with a bright inner edge.
	float in_face = 1.0 - smoothstep(-1.5, 0.5, face);
	vec3 outc = mix(uFrame, col, in_face);
	outc += (1.0 - smoothstep(0.0, 2.0, abs(face))) * 0.10;

	float a = 1.0 - smoothstep(-1.5, 1.0, outer);
	FRAG_OUT = vec4(outc, a) * fragColor;
}
`

WHITE_TEX:   rl.Texture2D
CARD_SHADER: rl.Shader
SHADER_OK:   bool

U_ELEMENT, U_FRAME, U_RARITY, U_TIME, U_HOVER, U_SIZE, U_MOUSE: c.int

shader_init :: proc() {
	img := rl.GenImageColor(1, 1, rl.WHITE)
	WHITE_TEX = rl.LoadTextureFromImage(img)
	rl.UnloadImage(img)

	vs_buf: [4096]u8
	fs_buf: [4096]u8
	vs := fmt.bprintf(vs_buf[:], "%s%s", GLSL_VS_HEADER, CARD_VS_SRC)
	vs_buf[len(vs)] = 0
	fs := fmt.bprintf(fs_buf[:], "%s%s", GLSL_FS_HEADER, CARD_FS_SRC)
	fs_buf[len(fs)] = 0
	CARD_SHADER = rl.LoadShaderFromMemory(cstring(&vs_buf[0]), cstring(&fs_buf[0]))
	SHADER_OK = CARD_SHADER.id != 0
	if !SHADER_OK {
		return
	}
	U_ELEMENT = rl.GetShaderLocation(CARD_SHADER, "uElement")
	U_FRAME = rl.GetShaderLocation(CARD_SHADER, "uFrame")
	U_RARITY = rl.GetShaderLocation(CARD_SHADER, "uRarity")
	U_TIME = rl.GetShaderLocation(CARD_SHADER, "uTime")
	U_HOVER = rl.GetShaderLocation(CARD_SHADER, "uHover")
	U_SIZE = rl.GetShaderLocation(CARD_SHADER, "uSize")
	U_MOUSE = rl.GetShaderLocation(CARD_SHADER, "uMouse")
}

shader_shutdown :: proc() {
	if SHADER_OK {
		rl.UnloadShader(CARD_SHADER)
	}
	rl.UnloadTexture(WHITE_TEX)
}

// Draw a shader-rendered panel into `rec`. `element` and `frame` are colours;
// `rarity` 0..1; `hover` 0 or 1. Returns false when the shader is unavailable so
// callers can fall back to primitives.
shader_panel :: proc(rec: rl.Rectangle, element, frame: rl.Color, rarity: f32, hover: f32) -> bool {
	if !SHADER_OK {
		return false
	}
	el := [3]f32{f32(element[0]) / 255, f32(element[1]) / 255, f32(element[2]) / 255}
	fr := [3]f32{f32(frame[0]) / 255, f32(frame[1]) / 255, f32(frame[2]) / 255}
	sz := [2]f32{rec.width, rec.height}
	mp := rl.GetMousePosition()
	mv := [2]f32{clamp((mp.x - rec.x) / rec.width, 0, 1), clamp((mp.y - rec.y) / rec.height, 0, 1)}
	tt := f32(rl.GetTime())
	rar := rarity
	hov := hover
	rl.SetShaderValue(CARD_SHADER, U_ELEMENT, rawptr(&el), .VEC3)
	rl.SetShaderValue(CARD_SHADER, U_FRAME, rawptr(&fr), .VEC3)
	rl.SetShaderValue(CARD_SHADER, U_RARITY, rawptr(&rar), .FLOAT)
	rl.SetShaderValue(CARD_SHADER, U_TIME, rawptr(&tt), .FLOAT)
	rl.SetShaderValue(CARD_SHADER, U_HOVER, rawptr(&hov), .FLOAT)
	rl.SetShaderValue(CARD_SHADER, U_SIZE, rawptr(&sz), .VEC2)
	rl.SetShaderValue(CARD_SHADER, U_MOUSE, rawptr(&mv), .VEC2)
	rl.BeginShaderMode(CARD_SHADER)
	rl.DrawTexturePro(WHITE_TEX, rl.Rectangle{0, 0, 1, 1}, rec, rl.Vector2{0, 0}, 0, rl.WHITE)
	rl.EndShaderMode()
	return true
}
