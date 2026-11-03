class_name MusicSynth
extends RefCounted
## Offline stereo music renderer. Instruments: warm string pad, Karplus-Strong harp,
## breathy flute, inharmonic bells / singing bowls, and hand drums. Notes that ring
## past the end wrap to the start, so every theme loops seamlessly.

const RATE := 32000

var length: int
var left := PackedFloat32Array()
var right := PackedFloat32Array()
var rng := RandomNumberGenerator.new()


func _init(seconds: float, seed_value: int) -> void:
	length = int(seconds * RATE)
	left.resize(length)
	right.resize(length)
	rng.seed = seed_value


static func hz(midi: float) -> float:
	return 440.0 * pow(2.0, (midi - 69.0) / 12.0)


func _gains(pan: float, gain: float) -> Vector2:
	var angle := (clampf(pan, -1.0, 1.0) + 1.0) * PI * 0.25
	return Vector2(cos(angle), sin(angle)) * gain


## Warm pad: each note is two detuned saws (one per side) through a two-pole lowpass.
func pad(notes: Array, start: float, dur: float, gain: float, cutoff := 1100.0, attack := 2.5, release := 3.0) -> void:
	var count := notes.size()
	var phases := PackedFloat32Array()
	var incs := PackedFloat32Array()
	var side := PackedFloat32Array()
	for k in count:
		var f := hz(notes[k])
		for det in [0.9965, 1.0035]:
			phases.append(rng.randf())
			incs.append(f * det / RATE)
			side.append(1.0 if det > 1.0 else 0.0)
	var voices := phases.size()
	var n := int((dur + release) * RATE)
	var s0 := int(start * RATE)
	var a := 1.0 - exp(-TAU * cutoff / RATE)
	var l1 := 0.0
	var l2 := 0.0
	var r1 := 0.0
	var r2 := 0.0
	var norm := gain / sqrt(float(count))
	for i in n:
		var t := float(i) / RATE
		var env := minf(t / attack, 1.0)
		if t > dur:
			env *= maxf(0.0, 1.0 - (t - dur) / release)
		var sl := 0.0
		var sr := 0.0
		for v in voices:
			var p := phases[v] + incs[v]
			if p >= 1.0:
				p -= 1.0
			phases[v] = p
			if side[v] > 0.5:
				sr += p - 0.5
			else:
				sl += p - 0.5
		l1 += a * (sl - l1)
		l2 += a * (l1 - l2)
		r1 += a * (sr - r1)
		r2 += a * (r1 - r2)
		var idx := (s0 + i) % length
		var e := env * norm
		left[idx] += l2 * e
		right[idx] += r2 * e


## Plucked string (Karplus-Strong with an allpass for exact tuning).
func pluck(note: float, start: float, gain: float, pan: float, dur := 3.5, decay := 0.998, brightness := 0.5) -> void:
	var delay := RATE / hz(note) - 0.5
	var size := maxi(2, int(floor(delay)))
	var frac := delay - size
	var c := (1.0 - frac) / (1.0 + frac)
	var ring := PackedFloat32Array()
	ring.resize(size)
	var prev := 0.0
	for k in size:
		var x := rng.randf_range(-1.0, 1.0)
		prev += brightness * (x - prev)
		ring[k] = prev
	var g := _gains(pan, gain)
	var n := int(dur * RATE)
	var s0 := int(start * RATE)
	var pos := 0
	var last := 0.0
	var ap_x := 0.0
	var ap_y := 0.0
	var fade := int(0.3 * RATE)
	for i in n:
		var out := ring[pos]
		var filtered := decay * 0.5 * (out + last)
		last = out
		var y := c * filtered + ap_x - c * ap_y
		ap_x = filtered
		ap_y = y
		ring[pos] = y
		pos += 1
		if pos >= size:
			pos = 0
		var env := minf(float(n - i) / fade, 1.0)
		var idx := (s0 + i) % length
		left[idx] += out * g.x * env
		right[idx] += out * g.y * env


## Breathy flute / ocarina with delayed vibrato.
func flute(note: float, start: float, dur: float, gain: float, pan: float, breath := 0.05) -> void:
	var f := hz(note)
	var g := _gains(pan, gain)
	var n := int((dur + 0.35) * RATE)
	var s0 := int(start * RATE)
	var phase := 0.0
	var lp := 0.0
	var a := 1.0 - exp(-TAU * 2500.0 / RATE)
	for i in n:
		var t := float(i) / RATE
		var vib := 1.0 + 0.004 * sin(TAU * 5.2 * t) * clampf((t - 0.25) * 2.0, 0.0, 1.0)
		phase += f * vib / RATE
		phase -= floorf(phase)
		var x := sin(TAU * phase) + 0.18 * sin(2.0 * TAU * phase) + 0.06 * sin(3.0 * TAU * phase)
		lp += a * (rng.randf_range(-1.0, 1.0) - lp)
		x += lp * breath * 6.0
		var env := minf(t / 0.12, 1.0)
		if t > dur:
			env *= maxf(0.0, 1.0 - (t - dur) / 0.35)
		var idx := (s0 + i) % length
		left[idx] += x * g.x * env
		right[idx] += x * g.y * env


## Bell / singing bowl. Partials decay faster the higher they are; slight beating.
func bell(note: float, start: float, gain: float, pan: float, dur := 4.0, partials := [1.0, 2.0, 2.76, 4.07, 5.4]) -> void:
	var weights := [1.0, 0.5, 0.35, 0.18, 0.1]
	var f := hz(note)
	var g := _gains(pan, gain)
	var n := int(dur * RATE)
	var s0 := int(start * RATE)
	for k in partials.size():
		var pf: float = f * partials[k]
		if pf > RATE * 0.45:
			continue
		var w: float = weights[k]
		var rate_k := (1.5 + k * 1.6) / dur
		var phase := rng.randf()
		var phase2 := phase
		for i in n:
			var t := float(i) / RATE
			phase += pf / RATE
			phase2 += pf * 1.0015 / RATE
			var env := minf(t / 0.004, 1.0) * exp(-t * rate_k)
			var x := (sin(TAU * phase) + sin(TAU * phase2)) * 0.5 * w * env
			var idx := (s0 + i) % length
			left[idx] += x * g.x
			right[idx] += x * g.y


## Hand drum / taiko: pitch-dropping sine body plus a noisy skin slap.
func drum(start: float, gain: float, f0 := 120.0, f1 := 60.0, decay := 9.0, slap := 0.3, pan := 0.0) -> void:
	var g := _gains(pan, gain)
	var n := int(minf(6.0 / decay, 2.0) * RATE)
	var s0 := int(start * RATE)
	var phase := 0.0
	var lp := 0.0
	var a := 1.0 - exp(-TAU * 1800.0 / RATE)
	for i in n:
		var t := float(i) / RATE
		phase += lerpf(f1, f0, exp(-t * 30.0)) / RATE
		var body := sin(TAU * phase) * exp(-t * decay)
		lp += a * (rng.randf_range(-1.0, 1.0) - lp)
		var x := body + lp * slap * exp(-t * 60.0) * 3.0
		var idx := (s0 + i) % length
		left[idx] += x * g.x
		right[idx] += x * g.y


func normalize(peak := 0.8) -> void:
	var m := 0.0001
	for i in length:
		m = maxf(m, maxf(absf(left[i]), absf(right[i])))
	var gain := peak / m
	for i in length:
		left[i] *= gain
		right[i] *= gain


func save(path: String) -> void:
	var bytes := PackedByteArray()
	bytes.resize(length * 4)
	for i in length:
		bytes.encode_s16(i * 4, int(clampf(left[i], -1.0, 1.0) * 32767.0))
		bytes.encode_s16(i * 4 + 2, int(clampf(right[i], -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = true
	stream.data = bytes
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_end = length
	stream.save_to_wav(path)
