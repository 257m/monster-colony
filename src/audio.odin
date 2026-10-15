package main

import rl "vendor:raylib"
import "core:c"
import "core:math"

// ============================================================================
// AUDIO
//
// No audio files ship with the game, so every sound effect and the looping
// music track are **synthesised at startup** into 16-bit PCM and handed to
// raylib. `audio` is a package-level singleton, so any file can fire a cue with
// `audio_play(.CLICK)`. If the audio device can't open (some browser setups),
// everything silently no-ops.
// ============================================================================

AUDIO_SR :: 44100

Synth_Kind :: enum { SINE, SQUARE, SAW, TRIANGLE, NOISE }

Sfx :: enum {
	CLICK, CONFIRM, CANCEL, BUILD, ERROR, COIN, FOOD, CRYSTAL,
	HIT, HEAL, LEVELUP, VICTORY, DEFEAT, NOTIFY, TURN, RAID,
	DISCOVER, ROAR, DRIP, WIND, CHIRP, HEARTBEAT,
}

Audio :: struct {
	ready:     bool,
	muted:     bool,
	volume:    f32, // master volume when unmuted (0..1)
	sfx:       [Sfx]rl.Sound,
	music:     rl.Music,
	has_music: bool,
	pcm:       [dynamic][]i16, // keeps the sample buffers alive while raylib owns copies
	wav:       [dynamic]u8,    // the music track encoded as a WAV, kept alive for the stream
	rng:       Rng,
	amb_t:     f32, // countdown to the next random ambient cue
	beat_t:    f32, // countdown to the next threat heartbeat
	threat:    f32, // 0..1, how close the nearest wild is (drives the heartbeat)
}

audio: Audio

// ----------------------------------------------------------------------------
// Synthesis
// ----------------------------------------------------------------------------

osc :: proc(kind: Synth_Kind, phase: f32, r: ^Rng) -> f32 {
	switch kind {
	case .SINE:
		return math.sin(phase * 2.0 * math.PI)
	case .SQUARE:
		return (phase - f32(int(phase))) < 0.5 ? 1.0 : -1.0
	case .SAW:
		return 2.0 * (phase - f32(int(phase))) - 1.0
	case .TRIANGLE:
		f := phase - f32(int(phase))
		return 4.0 * abs(f - 0.5) - 1.0
	case .NOISE:
		return rng_f32(r) * 2.0 - 1.0
	}
	return 0
}

audio_buf :: proc(dur: f32) -> []i16 {
	n := max(int(dur * AUDIO_SR), 1)
	return make([]i16, n)
}

// Mixes one note (a pitch sweep with an attack + exponential-decay envelope)
// into `buf` starting at `start` seconds.
audio_note :: proc(
	buf: []i16,
	start, f0, f1, dur, vol: f32,
	kind: Synth_Kind,
	decay := f32(6.0),
	attack := f32(0.004),
	r: ^Rng = nil,
) {
	n := int(dur * AUDIO_SR)
	i0 := int(start * AUDIO_SR)
	phase: f32
	for k in 0..<n {
		i := i0 + k
		if i < 0 {
			continue
		}
		if i >= len(buf) {
			break
		}
		t := f32(k) / AUDIO_SR
		u := f32(k) / f32(max(n, 1))
		freq := f0 + (f1 - f0) * u
		phase += freq / AUDIO_SR
		s := osc(kind, phase, r)
		a := (attack > 0 && t < attack) ? t / attack : 1.0
		env := a * math.exp(-decay * t)
		v := clamp(s * env * vol, -1, 1)
		buf[i] = i16(clamp(f32(buf[i]) + v * 32000, -32767, 32767))
	}
}

// Short fade in/out so looped and one-shot buffers never click.
audio_fade_edges :: proc(buf: []i16, fade_in, fade_out: f32) {
	fi := int(fade_in * AUDIO_SR)
	fo := int(fade_out * AUDIO_SR)
	for i in 0..<fi {
		if i >= len(buf) {
			break
		}
		buf[i] = i16(f32(buf[i]) * (f32(i) / f32(max(fi, 1))))
	}
	for k in 0..<fo {
		i := len(buf) - 1 - k
		if i < 0 {
			break
		}
		buf[i] = i16(f32(buf[i]) * (f32(k) / f32(max(fo, 1))))
	}
}

note_freq :: proc(semitones_from_a4: int) -> f32 {
	return 440.0 * math.pow(2.0, f32(semitones_from_a4) / 12.0)
}

// ----------------------------------------------------------------------------
// Sound effects
// ----------------------------------------------------------------------------

audio_make_sfx :: proc(kind: Sfx) -> []i16 {
	switch kind {
	case .CLICK:
		b := audio_buf(0.07)
		audio_note(b, 0, 900, 680, 0.06, 0.28, .SQUARE, 36.0, 0.002, &audio.rng)
		return b
	case .CONFIRM:
		b := audio_buf(0.22)
		audio_note(b, 0.00, 660, 660, 0.09, 0.30, .SINE, 14.0, 0.004, &audio.rng)
		audio_note(b, 0.07, 990, 990, 0.14, 0.30, .SINE, 10.0, 0.004, &audio.rng)
		return b
	case .CANCEL:
		b := audio_buf(0.20)
		audio_note(b, 0.00, 440, 440, 0.08, 0.28, .SQUARE, 16.0, 0.003, &audio.rng)
		audio_note(b, 0.06, 300, 300, 0.13, 0.28, .SQUARE, 12.0, 0.003, &audio.rng)
		return b
	case .BUILD:
		b := audio_buf(0.22)
		audio_note(b, 0.00, 190, 120, 0.18, 0.45, .SINE, 9.0, 0.002, &audio.rng)
		audio_note(b, 0.00, 0, 0, 0.05, 0.30, .NOISE, 40.0, 0.001, &audio.rng)
		return b
	case .ERROR:
		b := audio_buf(0.22)
		audio_note(b, 0.00, 150, 130, 0.18, 0.32, .SQUARE, 7.0, 0.004, &audio.rng)
		return b
	case .COIN:
		b := audio_buf(0.20)
		audio_note(b, 0.00, 1180, 1780, 0.08, 0.26, .SQUARE, 22.0, 0.002, &audio.rng)
		audio_note(b, 0.06, 1780, 1780, 0.09, 0.22, .SQUARE, 16.0, 0.002, &audio.rng)
		return b
	case .FOOD:
		b := audio_buf(0.16)
		audio_note(b, 0.00, 520, 620, 0.12, 0.28, .SINE, 12.0, 0.004, &audio.rng)
		return b
	case .CRYSTAL:
		b := audio_buf(0.34)
		audio_note(b, 0.00, 1500, 2400, 0.16, 0.24, .SINE, 8.0, 0.003, &audio.rng)
		audio_note(b, 0.10, 2100, 3000, 0.20, 0.20, .SINE, 7.0, 0.003, &audio.rng)
		return b
	case .HIT:
		b := audio_buf(0.20)
		audio_note(b, 0.00, 0, 0, 0.10, 0.38, .NOISE, 26.0, 0.001, &audio.rng)
		audio_note(b, 0.00, 220, 70, 0.14, 0.40, .SINE, 12.0, 0.001, &audio.rng)
		return b
	case .HEAL:
		b := audio_buf(0.28)
		audio_note(b, 0.00, 520, 980, 0.24, 0.26, .SINE, 6.0, 0.006, &audio.rng)
		return b
	case .LEVELUP:
		b := audio_buf(0.42)
		freqs := [?]f32{660, 880, 1100, 1320}
		for f, i in freqs {
			audio_note(b, f32(i) * 0.075, f, f, 0.12, 0.30, .SINE, 9.0, 0.004, &audio.rng)
		}
		return b
	case .VICTORY:
		b := audio_buf(0.95)
		freqs := [?]f32{523, 659, 784, 1046}
		for f, i in freqs {
			d := i == len(freqs) - 1 ? f32(0.5) : f32(0.16)
			audio_note(b, f32(i) * 0.15, f, f, d, 0.30, .SQUARE, 5.0, 0.005, &audio.rng)
		}
		return b
	case .DEFEAT:
		b := audio_buf(1.0)
		freqs := [?]f32{440, 349, 261}
		for f, i in freqs {
			audio_note(b, f32(i) * 0.22, f, f * 0.98, 0.34, 0.30, .SINE, 3.0, 0.01, &audio.rng)
		}
		return b
	case .NOTIFY:
		b := audio_buf(0.20)
		audio_note(b, 0.00, 880, 880, 0.07, 0.22, .SINE, 14.0, 0.004, &audio.rng)
		audio_note(b, 0.06, 1174, 1174, 0.11, 0.20, .SINE, 10.0, 0.004, &audio.rng)
		return b
	case .TURN:
		b := audio_buf(0.20)
		audio_note(b, 0.00, 330, 520, 0.16, 0.24, .SINE, 8.0, 0.006, &audio.rng)
		return b
	case .RAID:
		b := audio_buf(0.6)
		audio_note(b, 0.00, 220, 210, 0.22, 0.40, .SQUARE, 5.0, 0.004, &audio.rng)
		audio_note(b, 0.24, 165, 158, 0.30, 0.40, .SQUARE, 4.0, 0.004, &audio.rng)
		return b
	case .DISCOVER:
		b := audio_buf(0.5)
		freqs := [?]f32{784, 1046, 1318}
		for f, i in freqs {
			audio_note(b, f32(i) * 0.07, f, f * 1.02, 0.16, 0.24, .SINE, 9.0, 0.004, &audio.rng)
		}
		return b
	case .ROAR:
		b := audio_buf(0.75)
		audio_note(b, 0.00, 150, 88, 0.55, 0.32, .SAW, 4.0, 0.02, &audio.rng)
		audio_note(b, 0.00, 0, 0, 0.30, 0.10, .NOISE, 6.0, 0.02, &audio.rng)
		return b
	case .DRIP:
		b := audio_buf(0.25)
		audio_note(b, 0.00, 1600, 640, 0.10, 0.20, .SINE, 20.0, 0.002, &audio.rng)
		return b
	case .WIND:
		b := audio_buf(1.1)
		audio_note(b, 0.00, 0, 0, 1.0, 0.14, .NOISE, 2.0, 0.35, &audio.rng)
		return b
	case .CHIRP:
		b := audio_buf(0.32)
		audio_note(b, 0.00, 2200, 2600, 0.08, 0.14, .SINE, 24.0, 0.003, &audio.rng)
		audio_note(b, 0.09, 2600, 2200, 0.10, 0.12, .SINE, 20.0, 0.003, &audio.rng)
		return b
	case .HEARTBEAT:
		b := audio_buf(0.5)
		audio_note(b, 0.00, 72, 54, 0.12, 0.50, .SINE, 5.0, 0.004, &audio.rng)
		audio_note(b, 0.17, 62, 46, 0.15, 0.38, .SINE, 5.0, 0.004, &audio.rng)
		return b
	}
	return audio_buf(0.01)
}

// ----------------------------------------------------------------------------
// Music — a slow, calm A-minor loop
// ----------------------------------------------------------------------------

audio_make_music :: proc() -> []i16 {
	bpm := f32(84.0)
	beat := 60.0 / bpm
	bars := 8
	beats_per_bar := 4
	total_beats := bars * beats_per_bar
	b := audio_buf(f32(total_beats) * beat + 0.6)

	// i - VI - III - VII in A minor, twice.
	roots := [8]int{-12, -16, -9, -14, -12, -16, -9, -14}
	for bar in 0..<bars {
		f := note_freq(roots[bar])
		start := f32(bar * beats_per_bar) * beat
		audio_note(b, start, f, f, f32(beats_per_bar) * beat * 0.96, 0.26, .TRIANGLE, 2.0, 0.02, &audio.rng)
		// A soft fifth as a pad.
		audio_note(b, start, note_freq(roots[bar] + 7), note_freq(roots[bar] + 7), f32(beats_per_bar) * beat * 0.9, 0.06, .SINE, 1.6, 0.15, &audio.rng)
	}

	// Lead: a pentatonic line, one note per beat (-99 = rest).
	lead := [32]int{
		12, 10, 7, -99, 8, 7, 5, -99, 7, 5, 3, -99, 10, 7, 10, 12,
		12, 15, 12, -99, 8, 10, 8, 7, 7, 5, 3, -99, 3, 5, 7, 5,
	}
	for i in 0..<len(lead) {
		if lead[i] == -99 {
			continue
		}
		f := note_freq(lead[i])
		audio_note(b, f32(i) * beat, f, f, beat * 0.82, 0.20, .SQUARE, 3.0, 0.01, &audio.rng)
	}

	// Percussion: a soft kick on each beat, a tick on the off-beat.
	for beat_i in 0..<total_beats {
		start := f32(beat_i) * beat
		audio_note(b, start, 130, 46, 0.10, 0.30, .SINE, 24.0, 0.001, &audio.rng)
		audio_note(b, start + beat * 0.5, 6000, 6000, 0.02, 0.05, .NOISE, 60.0, 0.001, &audio.rng)
	}

	audio_fade_edges(b, 0.02, 0.15)
	return b
}

// ----------------------------------------------------------------------------
// WAV encoding (so the music can be streamed + looped via LoadMusicStreamFromMemory)
// ----------------------------------------------------------------------------

wav_put_u16 :: proc(out: ^[dynamic]u8, v: u16) {
	append(out, u8(v), u8(v >> 8))
}

wav_put_u32 :: proc(out: ^[dynamic]u8, v: u32) {
	append(out, u8(v), u8(v >> 8), u8(v >> 16), u8(v >> 24))
}

wav_put_str :: proc(out: ^[dynamic]u8, s: string) {
	for ch in s {
		append(out, u8(ch))
	}
}

wav_encode :: proc(samples: []i16, sample_rate: u32) -> [dynamic]u8 {
	out := make([dynamic]u8, 0)
	data_bytes := u32(len(samples) * 2)
	wav_put_str(&out, "RIFF")
	wav_put_u32(&out, 36 + data_bytes)
	wav_put_str(&out, "WAVE")
	wav_put_str(&out, "fmt ")
	wav_put_u32(&out, 16) // PCM chunk size
	wav_put_u16(&out, 1)  // format = PCM
	wav_put_u16(&out, 1)  // channels = mono
	wav_put_u32(&out, sample_rate)
	wav_put_u32(&out, sample_rate * 2) // byte rate
	wav_put_u16(&out, 2)               // block align
	wav_put_u16(&out, 16)              // bits per sample
	wav_put_str(&out, "data")
	wav_put_u32(&out, data_bytes)
	for s in samples {
		wav_put_u16(&out, u16(s))
	}
	return out
}

// ----------------------------------------------------------------------------
// Lifecycle
// ----------------------------------------------------------------------------

audio_load_sound :: proc(buf: []i16) -> rl.Sound {
	w := rl.Wave{
		frameCount = c.uint(len(buf)),
		sampleRate = c.uint(AUDIO_SR),
		sampleSize = 16,
		channels   = 1,
		data       = raw_data(buf),
	}
	return rl.LoadSoundFromWave(w)
}

audio_init :: proc() {
	rl.InitAudioDevice()
	if !rl.IsAudioDeviceReady() {
		return
	}
	audio.ready = true
	audio.rng = rng_make(0xA0D10)
	audio.volume = 0.85
	rl.SetMasterVolume(audio.volume)

	for kind in Sfx {
		buf := audio_make_sfx(kind)
		append(&audio.pcm, buf)
		audio.sfx[kind] = audio_load_sound(buf)
	}

	mbuf := audio_make_music()
	append(&audio.pcm, mbuf)
	audio.wav = wav_encode(mbuf, AUDIO_SR)
	audio.music = rl.LoadMusicStreamFromMemory(cstring(".wav"), raw_data(audio.wav), c.int(len(audio.wav)))
	if audio.music.frameCount > 0 {
		audio.music.looping = true
		audio.has_music = true
		rl.SetMusicVolume(audio.music, 0.32)
		rl.PlayMusicStream(audio.music)
	}
}

audio_update :: proc() {
	if audio.ready && audio.has_music {
		rl.UpdateMusicStream(audio.music)
	}
	if !audio.ready || audio.muted {
		return
	}
	dt := rl.GetFrameTime()

	// Occasional ambient cue so the cavern isn't silent between actions.
	audio.amb_t -= dt
	if audio.amb_t <= 0 {
		audio.amb_t = 6.0 + rng_f32(&audio.rng) * 9.0
		cues := [?]Sfx{.DRIP, .WIND, .CHIRP, .ROAR}
		cue := cues[rng_below(&audio.rng, len(cues))]
		audio_play(cue, cue == .ROAR ? 0.26 : 0.14)
	}

	// A heartbeat that quickens as a wild closes in.
	if audio.threat > 0.05 {
		audio.beat_t -= dt
		if audio.beat_t <= 0 {
			audio.beat_t = 1.1 - audio.threat * 0.55
			audio_play(.HEARTBEAT, 0.12 + audio.threat * 0.33)
		}
	} else {
		audio.beat_t = 0
	}
}

// 0 = nothing near, 1 = something is right on top of you.
audio_set_threat :: proc(v: f32) {
	audio.threat = clamp(v, 0, 1)
}

audio_shutdown :: proc() {
	if !audio.ready {
		return
	}
	if audio.has_music {
		rl.StopMusicStream(audio.music)
		rl.UnloadMusicStream(audio.music)
		audio.has_music = false
	}
	for kind in Sfx {
		rl.UnloadSound(audio.sfx[kind])
	}
	for b in audio.pcm {
		delete(b)
	}
	delete(audio.pcm)
	delete(audio.wav)
	rl.CloseAudioDevice()
	audio.ready = false
}

// Fire a cue. Safe to call anywhere (no-ops until the device is ready / unmuted).
audio_play :: proc(kind: Sfx, volume := f32(1.0)) {
	if !audio.ready || audio.muted {
		return
	}
	rl.SetSoundVolume(audio.sfx[kind], volume)
	rl.PlaySound(audio.sfx[kind])
}

// Returns the new muted state.
audio_toggle_mute :: proc() -> bool {
	audio.muted = !audio.muted
	if audio.ready {
		rl.SetMasterVolume(audio.muted ? 0.0 : audio.volume)
	}
	return audio.muted
}

// Set the master volume (0..1); applies immediately unless muted.
audio_set_volume :: proc(v: f32) {
	audio.volume = clamp(v, 0, 1)
	if audio.ready && !audio.muted {
		rl.SetMasterVolume(audio.volume)
	}
}
