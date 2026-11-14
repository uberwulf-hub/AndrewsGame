class_name Babble
extends Node
## Cute made-up "voices": each line someone says is read out as a burst of tiny
## sung syllables, one per syllable of the real text, so it bobs along with the
## words without ever saying them. Every voice is synthesized here (no files):
## a buzzy little pulse shaped by vowel formants, with a soft consonant puff in
## front. The hero hums low and gentle, the Fox is bright and quick, the Otter
## is high, squeaky and quickest of all.

const RATE := 22050
const VOWELS := {  # formants (Hz) of a, e, i, o, u
	"a": [800.0, 1250.0], "e": [450.0, 2100.0], "i": [320.0, 2600.0],
	"o": [480.0, 850.0], "u": [350.0, 720.0],
}
const ONSETS := ["", "p", "s", "m"]  # none, a pop, a hiss, a hum
const VOICES := {
	# f0: speaking pitch, formant: how small the "throat" is, step: seconds per
	# syllable, wobble: random pitch spread, db: loudness, buzz: brightness
	"hero": {"f0": 230.0, "formant": 1.05, "step": 0.105, "wobble": 0.07, "db": -19.0, "buzz": 0.55},
	"fox": {"f0": 390.0, "formant": 1.25, "step": 0.09, "wobble": 0.10, "db": -17.0, "buzz": 0.75},
	"otter": {"f0": 560.0, "formant": 1.45, "step": 0.075, "wobble": 0.14, "db": -17.0, "buzz": 0.9},
}
const MAX_SYLLABLES := 18

static var _banks := {}  # voice -> {"a": [AudioStreamWAV per onset], ...}

var _player: AudioStreamPlayer
var _queue: Array = []  # [time, stream, pitch, volume_db]
var _clock := 0.0


## Says `line` in `voice` ("hero", "fox" or "otter"). The babble lives on `owner`
## (usually the thought bubble) and stops if that goes away.
static func speak(owner: Node, voice: String, line: String) -> void:
	if not VOICES.has(voice) or owner == null:
		return
	for child in owner.get_children():
		if child is Babble:
			child.queue_free()  # a new line cuts off the last one
	var b := Babble.new()
	owner.add_child(b)
	b._start(voice, line)


func _start(voice: String, line: String) -> void:
	var v: Dictionary = VOICES[voice]
	var bank := _bank(voice)
	_player = AudioStreamPlayer.new()
	var poly := AudioStreamPolyphonic.new()
	poly.polyphony = 4
	_player.stream = poly
	_player.bus = "SFX"
	_player.volume_db = v.db
	add_child(_player)
	_player.play()
	var syllables := syllables_of(line)
	var question := line.strip_edges().ends_with("?")
	var excited := line.contains("!")
	var t := 0.0
	var n := syllables.size()
	for k in n:
		var s: Array = syllables[k]
		var vowel: String = s[0]
		var onset: String = s[1]
		var progress := float(k) / maxf(n - 1, 1)
		# A gentle sing-song: a slow arc, a little random step, and the ending tells
		# you if it was a question (up) or a statement (settles down).
		var pitch := 1.0 + sin(progress * PI) * 0.06 + randf_range(-v.wobble, v.wobble)
		if excited:
			pitch += 0.08
		if k == n - 1:
			pitch += 0.22 if question else -0.08
		var vol := randf_range(-2.0, 0.0) + (1.5 if excited else 0.0)
		_queue.append([t, bank[vowel][ONSETS.find(onset)], pitch, vol])
		t += v.step * randf_range(0.85, 1.15) + float(s[2])


func _process(delta: float) -> void:
	_clock += delta
	var playback := _player.get_stream_playback() as AudioStreamPlaybackPolyphonic
	while not _queue.is_empty() and _queue[0][0] <= _clock:
		var q: Array = _queue.pop_front()
		var shown := not (get_parent() is CanvasItem) or (get_parent() as CanvasItem).visible
		if playback and shown:  # quiet when the bubble is off-screen or far away
			playback.play_stream(q[1], 0.0, q[3], q[2])
	if _queue.is_empty() and _clock > 0.0:
		set_process(false)
		get_tree().create_timer(0.4).timeout.connect(queue_free)


## The line as [vowel, onset, pause-after] syllables: one per vowel group of each
## word, a pause after each word and a longer one at punctuation.
static func syllables_of(line: String) -> Array:
	var out := []
	var text := line.to_lower()
	var onset := ""
	var in_vowel := false
	for i in text.length():
		var c := text[i]
		if c in "aeiouy":
			if not in_vowel:
				out.append([("i" if c == "y" else c), onset, 0.0])
				onset = ""
			in_vowel = true
			continue
		in_vowel = false
		if c in "bpdtkgcq":
			onset = "p"
		elif c in "szfvhxj":
			onset = "s"
		elif c in "mnlrw":
			onset = "m"
		elif not out.is_empty():
			var pause: float = out[-1][2]
			if c == " ":
				pause = maxf(pause, 0.035)
			elif c in ",;:-":
				pause = maxf(pause, 0.16)
			elif c in ".!?":
				pause = maxf(pause, 0.26)
			out[-1][2] = pause
			onset = ""
	if out.is_empty():
		out.append(["a", "", 0.0])  # "...", "Hm": still make a little sound
	if out.size() > MAX_SYLLABLES:
		out.resize(MAX_SYLLABLES)
	return out


static func _bank(voice: String) -> Dictionary:
	if _banks.has(voice):
		return _banks[voice]
	var v: Dictionary = VOICES[voice]
	var bank := {}
	for vowel in VOWELS:
		var list := []
		for onset in ONSETS:
			list.append(_syllable(v, VOWELS[vowel], onset))
		bank[vowel] = list
	_banks[voice] = bank
	return bank


## One syllable: an optional consonant puff, then a vowel sung on a pulse wave
## through two resonant filters (the formants), with a soft little scoop in pitch.
static func _syllable(v: Dictionary, formants: Array, onset: String) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([v.f0, formants, onset])
	var lead := {"": 0.0, "p": 0.012, "s": 0.04, "m": 0.03}[onset] as float
	var body := 0.1
	var n := int((lead + body) * RATE)
	var samples := PackedFloat32Array()
	samples.resize(n)
	var f0: float = v.f0
	var scale: float = v.formant
	var f1: float = formants[0] * scale
	var f2: float = formants[1] * scale
	var r1 := _reso(f1, 90.0 * scale)
	var r2 := _reso(f2, 140.0 * scale)
	var s1 := [0.0, 0.0]
	var s2 := [0.0, 0.0]
	var phase := 0.0
	var lead_n := int(lead * RATE)
	var hum := 0.0
	for i in n:
		var x := 0.0
		if i < lead_n:
			var lt := float(i) / maxf(lead_n, 1)
			if onset == "p":
				x = rng.randf_range(-1.0, 1.0) * (1.0 - lt) * 0.9
			elif onset == "s":
				x = (rng.randf_range(-1.0, 1.0) - hum) * 0.35 * sin(lt * PI)
				hum = rng.randf_range(-1.0, 1.0) * 0.6
			elif onset == "m":
				phase = fmod(phase + f0 * 0.92 / RATE, 1.0)
				x = sin(TAU * phase) * 0.5 * minf(lt * 4.0, 1.0)
			samples[i] = x
			continue
		var t := float(i - lead_n) / RATE
		var u := t / body
		var f := f0 * (0.94 + 0.06 * minf(u * 5.0, 1.0)) * (1.0 + 0.012 * sin(TAU * 7.0 * t))
		phase = fmod(phase + f / RATE, 1.0)
		# A pulse that's rounder or buzzier per voice, sent through both formants.
		var buzz: float = v.buzz
		var src := (1.0 - 2.0 * phase) * buzz + sin(TAU * phase) * (1.0 - buzz)
		var a := _step(r1, s1, src)
		var b := _step(r2, s2, src)
		var env := minf(u / 0.08, 1.0) * pow(1.0 - u, 1.6)
		x = (a * 0.8 + b * 0.45 + sin(TAU * phase) * 0.35) * env
		samples[i] = x
	# Normalize and pack as 16-bit.
	var peak := 0.001
	for s in samples:
		peak = maxf(peak, absf(s))
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		data.encode_s16(i * 2, int(clampf(samples[i] / peak * 0.85, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.data = data
	return wav


## Two-pole resonator coefficients for a peak at `freq` with bandwidth `bw`.
static func _reso(freq: float, bw: float) -> Array:
	var r := exp(-PI * bw / RATE)
	return [2.0 * r * cos(TAU * freq / RATE), -r * r, 1.0 - r]


static func _step(c: Array, s: Array, x: float) -> float:
	var y: float = c[2] * x + c[0] * s[0] + c[1] * s[1]
	s[1] = s[0]
	s[0] = y
	return y


# --- The bone whistle ----------------------------------------------------------
# A breathy two-note "fwee-oo": up, then a little drop, with air in it.

static var _whistle_wav: AudioStreamWAV


## Plays the bone whistle from `owner` (the hero).
static func whistle(owner: Node) -> void:
	if _whistle_wav == null:
		_whistle_wav = _make_whistle()
	var p := AudioStreamPlayer.new()
	p.stream = _whistle_wav
	p.bus = "SFX"
	p.volume_db = -14.0
	p.pitch_scale = randf_range(0.97, 1.03)
	owner.add_child(p)
	p.play()
	p.finished.connect(p.queue_free)


static func _make_whistle() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	# [start Hz, end Hz, seconds]: a rising first note, a short gap, a falling second.
	var notes := [[1900.0, 2500.0, 0.2], [0.0, 0.0, 0.05], [2450.0, 2050.0, 0.26]]
	var samples := PackedFloat32Array()
	var phase := 0.0
	for note in notes:
		var n := int(note[2] * RATE)
		for i in n:
			var u := float(i) / n
			if note[0] == 0.0:
				samples.append(0.0)
				continue
			var f: float = lerpf(note[0], note[1], u * u * (3.0 - 2.0 * u)) * (1.0 + 0.006 * sin(TAU * 6.0 * i / RATE))
			phase = fmod(phase + f / RATE, 1.0)
			var env := minf(u / 0.12, 1.0) * minf((1.0 - u) / 0.2, 1.0)
			var air := rng.randf_range(-1.0, 1.0) * 0.12
			samples.append((sin(TAU * phase) + sin(TAU * phase * 2.0) * 0.08 + air) * env)
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i] * 0.8, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.data = data
	return wav
