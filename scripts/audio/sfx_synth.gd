class_name SfxSynth
extends RefCounted
## Offline mono synthesizer for sound effects. Recipes layer tones, filtered noise,
## grains and bells into one buffer, then save it as a 16-bit WAV.

const RATE := 44100
const SINE := 0
const TRIANGLE := 1
const SQUARE := 2
const SAW := 3

var buf := PackedFloat32Array()
var rng := RandomNumberGenerator.new()


func _init(seconds: float, seed_value := 0) -> void:
	buf.resize(int(seconds * RATE))
	rng.seed = seed_value * 7919 + 17


## Oscillator with an exponential pitch sweep from f0 to f1 and exponential decay.
func tone(start: float, dur: float, f0: float, f1: float, amp: float, decay: float, wave := SINE, attack := 0.002) -> SfxSynth:
	var s0 := int(start * RATE)
	var n := mini(int(dur * RATE), buf.size() - s0)
	var phase := rng.randf()
	var ratio := f1 / f0
	for i in n:
		var t := float(i) / RATE
		phase += f0 * pow(ratio, t / dur) / RATE
		phase -= floorf(phase)
		var x: float
		if wave == SINE:
			x = sin(TAU * phase)
		elif wave == TRIANGLE:
			x = 4.0 * absf(phase - 0.5) - 1.0
		elif wave == SQUARE:
			x = tanh(sin(TAU * phase) * 4.0)
		else:
			x = 2.0 * phase - 1.0
		var env := minf(t / attack, 1.0) * exp(-t * decay) * minf((n - i) / 220.0, 1.0)
		buf[s0 + i] += x * amp * env
	return self


## White noise through a sweeping one-pole lowpass (lp0 -> lp1 Hz) and optional highpass.
func noise(start: float, dur: float, amp: float, decay: float, lp0 := 18000.0, lp1 := 18000.0, hp := 0.0, attack := 0.001) -> SfxSynth:
	var s0 := int(start * RATE)
	var n := mini(int(dur * RATE), buf.size() - s0)
	var lp := 0.0
	var lp2 := 0.0
	var hp_state := 0.0
	var hp_a := 1.0 - exp(-TAU * hp / RATE) if hp > 0.0 else 0.0
	var ratio := lp1 / lp0
	for i in n:
		var t := float(i) / RATE
		var cutoff := lp0 * pow(ratio, t / dur)
		var a := 1.0 - exp(-TAU * cutoff / RATE)
		lp += a * (rng.randf_range(-1.0, 1.0) - lp)
		lp2 += a * (lp - lp2)
		var x := lp2
		if hp > 0.0:
			hp_state += hp_a * (x - hp_state)
			x -= hp_state
		var env := minf(t / attack, 1.0) * exp(-t * decay) * minf((n - i) / 220.0, 1.0)
		buf[s0 + i] += x * amp * env * 1.6
	return self


## Many tiny noise clicks spread over time: crackle, gravel, debris, crunch.
func grains(start: float, dur: float, count: int, amp: float, lp := 4000.0, grain := 0.008, fade := 0.0) -> SfxSynth:
	for g in count:
		var at := start + rng.randf() * dur
		var weight := 1.0 - fade * (at - start) / dur
		noise(at, grain * rng.randf_range(0.6, 1.6), amp * rng.randf_range(0.4, 1.0) * weight, 1.0 / grain, lp, lp * 0.6)
	return self


## Inharmonic bell: a fundamental plus partials that decay faster the higher they are.
func bell(start: float, freq: float, amp: float, decay: float, dur := 2.0, partials := [1.0, 2.0, 2.76, 4.07, 5.4]) -> SfxSynth:
	var weights := [1.0, 0.45, 0.35, 0.2, 0.12, 0.08]
	for k in partials.size():
		tone(start, dur, freq * partials[k], freq * partials[k], amp * weights[k], decay * (1.0 + k * 0.8), SINE, 0.001)
	return self


## Turns the buffer into a seamless loop by crossfading the tail over the head.
func make_loop(fade_seconds: float) -> SfxSynth:
	var fade := int(fade_seconds * RATE)
	var keep := buf.size() - fade
	for i in fade:
		var w := float(i) / fade
		buf[i] = buf[i] * sqrt(w) + buf[keep + i] * sqrt(1.0 - w)
	buf.resize(keep)
	return self


func normalize(peak := 0.9) -> SfxSynth:
	var m := 0.0001
	for x in buf:
		m = maxf(m, absf(x))
	var g := peak / m
	for i in buf.size():
		buf[i] *= g
	return self


func save(path: String, loop := false) -> void:
	var bytes := PackedByteArray()
	bytes.resize(buf.size() * 2)
	for i in buf.size():
		bytes.encode_s16(i * 2, int(clampf(buf[i], -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.data = bytes
	if loop:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_end = buf.size()
	stream.save_to_wav(path)
