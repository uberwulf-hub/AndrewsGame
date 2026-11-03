class_name MusicThemes
extends RefCounted
## Composes the looping music. Every theme shares one grid (8 chords x 6s = 48s), so
## the game can start them together and crossfade between biomes, or fade in the
## combat drum layer, without ever falling out of time.
##
## The style aims for an old-school fantasy MMO (modal strings, harp, wooden flute,
## hand drums) blended with a calm spa layer (singing bowls, soft crystal bells).

const CHORD_SECONDS := 6.0
const LOOP_SECONDS := 48.0
const THEMES := ["sanctum", "wilds", "highlands", "combat"]

# [root MIDI note, intervals above the root]
const WILDS_CHORDS := [
	[38, [0, 3, 7, 10, 14]], [36, [0, 4, 7, 14]], [41, [0, 4, 7, 11]], [43, [0, 4, 7, 9]],
	[38, [0, 3, 7, 10, 14]], [34, [0, 4, 7, 11, 14]], [36, [0, 4, 7, 14]], [45, [0, 5, 7, 10]],
]
const SANCTUM_CHORDS := [
	[38, [0, 4, 7, 11, 14]], [43, [0, 4, 7, 11, 18]], [35, [0, 3, 7, 10, 14]], [45, [0, 4, 7, 14]],
	[38, [0, 4, 7, 11, 14]], [40, [0, 3, 7, 10, 14]], [43, [0, 4, 7, 11, 14]], [45, [0, 2, 7, 12]],
]
const HIGHLANDS_CHORDS := [
	[38, [0, 7, 12, 15]], [34, [0, 7, 12, 16]], [36, [0, 7, 12, 16]], [33, [0, 7, 12, 15]],
	[38, [0, 7, 12, 15, 19]], [31, [0, 7, 12, 15]], [34, [0, 7, 12, 16, 19]], [33, [0, 7, 12, 16]],
]
const D_DORIAN := [2, 4, 5, 7, 9, 11, 0]
const D_AEOLIAN := [2, 4, 5, 7, 9, 10, 0]
const D_MAJOR_PENTATONIC := [2, 4, 6, 9, 11]


static func compose(theme: String) -> MusicSynth:
	match theme:
		"dream":
			return _dream()
		"sanctum":
			return _sanctum()
		"wilds":
			return _wilds()
		"highlands":
			return _highlands()
		_:
			return _combat()


## Meadows, forests and shores: wistful D dorian with harp, flute and hand drums.
static func _wilds() -> MusicSynth:
	var m := MusicSynth.new(LOOP_SECONDS, 101)
	var pattern := [0, 1, 2, 3, 4, 3, 2, 1, 2, 3, 4, 2]
	for c in 8:
		var chord: Array = WILDS_CHORDS[c]
		var t0 := c * CHORD_SECONDS
		m.pad(_voicing(chord, 50, 67), t0, CHORD_SECONDS, 0.2, 1300.0)
		m.pad([chord[0]], t0, CHORD_SECONDS, 0.14, 380.0, 1.5, 2.5)
		var arp := _voicing(chord, 62, 82)
		for step in 12:
			if m.rng.randf() < 0.18:
				continue
			m.pluck(arp[pattern[step] % arp.size()], t0 + step * 0.5, 0.2, sin(step * 0.9) * 0.5, 3.0, 0.998, 0.45)
		m.drum(t0, 0.3, 105.0, 55.0, 7.0, 0.25, -0.2)
		m.drum(t0 + 3.0, 0.24, 105.0, 55.0, 7.0, 0.25, -0.2)
		m.drum(t0 + 1.5, 0.1, 190.0, 120.0, 14.0, 0.5, 0.3)
		m.drum(t0 + 4.5, 0.1, 190.0, 120.0, 14.0, 0.5, 0.3)
	for phrase_start in [6.0, 18.0, 30.0, 42.0]:
		_melody(m, WILDS_CHORDS, _scale(D_DORIAN, 67, 86), phrase_start, 10.0, 0.16)
	_sparkle(m, _scale(D_MAJOR_PENTATONIC, 81, 93), 10, 0.035)
	m.normalize()
	return m


## The Sanctum hub: bright, warm D lydian with singing bowls and slow harp (the spa).
static func _sanctum() -> MusicSynth:
	var m := MusicSynth.new(LOOP_SECONDS, 202)
	for c in 8:
		var chord: Array = SANCTUM_CHORDS[c]
		var t0 := c * CHORD_SECONDS
		m.pad(_voicing(chord, 52, 71), t0, CHORD_SECONDS, 0.22, 900.0, 3.5, 3.5)
		m.pad([chord[0]], t0, CHORD_SECONDS, 0.1, 300.0, 2.5, 3.0)
		var arp := _voicing(chord, 62, 86)
		for step in 6:
			if m.rng.randf() < 0.3:
				continue
			var note: int = arp[(step + c) % arp.size()]
			m.pluck(note, t0 + step * 1.0 + 0.5, 0.17, m.rng.randf_range(-0.6, 0.6), 3.5, 0.9985, 0.35)
		if c % 2 == 0:
			m.bell(_voicing(chord, 50, 62)[0], t0, 0.16, 0.0, 9.0, [1.0, 2.71, 5.1])
	_melody(m, SANCTUM_CHORDS, _scale(D_MAJOR_PENTATONIC, 69, 86), 24.0, 9.0, 0.08)
	_sparkle(m, _scale(D_MAJOR_PENTATONIC, 79, 93), 22, 0.05)
	m.normalize()
	return m


## Mountains: darker open fifths, low ocarina, slow war drum.
static func _highlands() -> MusicSynth:
	var m := MusicSynth.new(LOOP_SECONDS, 303)
	for c in 8:
		var chord: Array = HIGHLANDS_CHORDS[c]
		var t0 := c * CHORD_SECONDS
		m.pad(_voicing(chord, 45, 64), t0, CHORD_SECONDS, 0.24, 700.0, 3.0, 3.0)
		m.pad([chord[0] - 12 if chord[0] > 35 else chord[0]], t0, CHORD_SECONDS, 0.16, 250.0, 2.0, 3.0)
		var arp := _voicing(chord, 55, 74)
		for step in 6:
			if m.rng.randf() < 0.55:
				continue
			m.pluck(arp[m.rng.randi() % arp.size()], t0 + step * 1.0, 0.18, m.rng.randf_range(-0.5, 0.5), 3.5, 0.998, 0.3)
		m.drum(t0, 0.35, 75.0, 40.0, 3.5, 0.15, 0.0)
		if c % 2 == 1:
			m.drum(t0 + 4.5, 0.2, 75.0, 40.0, 3.5, 0.15, 0.3)
		if c % 4 == 0:
			m.bell(_voicing(chord, 45, 57)[0], t0 + 1.0, 0.12, -0.3, 8.0, [1.0, 2.71, 5.1])
	for phrase_start in [6.0, 30.0]:
		_melody(m, HIGHLANDS_CHORDS, _scale(D_AEOLIAN, 57, 74), phrase_start, 11.0, 0.18)
	m.normalize()
	return m


## Combat layer: taiko groove and a driving low pluck ostinato over the wilds roots.
static func _combat() -> MusicSynth:
	var m := MusicSynth.new(LOOP_SECONDS, 404)
	var ostinato := [0, 0, 7, 0, 12, 0, 7, 0]
	for c in 8:
		var chord: Array = WILDS_CHORDS[c]
		var t0 := c * CHORD_SECONDS
		var root: int = chord[0]
		while root < 38:
			root += 12
		m.pad([root, root + 7], t0, CHORD_SECONDS, 0.12, 500.0, 0.8, 1.5)
		for step in 24:
			var t := t0 + step * 0.25
			m.pluck(root + ostinato[step % 8], t, 0.2, -0.25, 0.7, 0.994, 0.6)
		for bar in 3:
			var b0 := t0 + bar * 2.0
			m.drum(b0, 0.55, 80.0, 42.0, 5.0, 0.3, 0.0)
			m.drum(b0 + 1.0, 0.45, 80.0, 42.0, 5.0, 0.3, 0.0)
			m.drum(b0 + 0.75, 0.22, 150.0, 90.0, 10.0, 0.4, 0.4)
			m.drum(b0 + 1.5, 0.22, 150.0, 90.0, 10.0, 0.4, -0.4)
			if m.rng.randf() < 0.5:
				m.drum(b0 + 0.5, 0.12, 220.0, 140.0, 16.0, 0.6, 0.5)
			if (c * 3 + bar) % 4 == 3:
				for k in 4:
					m.drum(b0 + 1.0 + k * 0.25, 0.18 + k * 0.05, 160.0, 95.0, 11.0, 0.45, -0.3 + k * 0.2)
	m.normalize()
	return m


## The opening dream (not a loop). Sections follow the cutscene timeline in dream.gd:
## love 0-12, adventure 12-24, family 24-40, hard times 40-52, the villain 52-66,
## cast out 66-80, waking 80-90.
const DREAM_SECONDS := 90.0


static func _dream() -> MusicSynth:
	var m := MusicSynth.new(DREAM_SECONDS, 505)
	# Love and adventure: warm D lydian, harp and flute.
	var warm := [[38, [0, 4, 7, 11, 14]], [43, [0, 4, 7, 11, 18]], [35, [0, 3, 7, 10, 14]], [45, [0, 4, 7, 14]]]
	for c in 4:
		var t0 := c * 6.0
		m.pad(_voicing(warm[c], 52, 71), t0, 6.0, 0.22, 1100.0, 2.0 if c == 0 else 1.5, 2.5)
		m.pad([warm[c][0]], t0, 6.0, 0.1, 300.0, 2.0, 2.5)
		var arp := _voicing(warm[c], 62, 84)
		for step in 12:
			if c == 0 and step < 4 or m.rng.randf() < 0.2:
				continue
			m.pluck(arp[(step + c) % arp.size()], t0 + step * 0.5, 0.17, sin(step) * 0.5, 3.0, 0.998, 0.4)
	_melody(m, warm, _scale(D_MAJOR_PENTATONIC, 69, 88), 3.0, 20.0, 0.13, 6.0, 0.0)
	# Family: brighter, quicker chords and a playful hand drum.
	var family := [[43, [0, 4, 7, 14]], [42, [0, 3, 8, 15]], [40, [0, 3, 7, 10, 14]], [45, [0, 4, 7, 10]]]
	for c in 4:
		var t0 := 24.0 + c * 4.0
		m.pad(_voicing(family[c], 52, 72), t0, 4.0, 0.2, 1400.0, 0.8, 1.5)
		m.pad([family[c][0] - 12 if family[c][0] > 40 else family[c][0]], t0, 4.0, 0.1, 300.0, 0.5, 1.5)
		var arp := _voicing(family[c], 64, 86)
		for step in 8:
			m.pluck(arp[step % arp.size()], t0 + step * 0.5, 0.15, -0.3 + step * 0.08, 2.0, 0.997, 0.5)
		for beat in 4:
			m.drum(t0 + beat, 0.16 if beat % 2 == 0 else 0.09, 150.0, 90.0, 12.0, 0.4, 0.2)
	_melody(m, family, _scale(D_MAJOR_PENTATONIC, 71, 88), 25.0, 14.0, 0.12, 4.0, 24.0)
	for k in 6:
		m.bell([86, 88, 90, 93][k % 4], 26.0 + k * 2.3, 0.04, m.rng.randf_range(-0.7, 0.7), 2.5, [1.0, 2.0, 4.07])
	# Hard times: B minor, darker and sparser.
	var gloom := [[35, [0, 3, 7, 10]], [43, [0, 4, 7, 11]], [40, [0, 3, 7, 10]]]
	for c in 3:
		var t0 := 40.0 + c * 4.0
		m.pad(_voicing(gloom[c], 47, 66), t0, 4.0, 0.22, 650.0, 1.2, 2.0)
		m.pad([gloom[c][0]], t0, 4.0, 0.12, 250.0, 1.0, 2.0)
		var arp := _voicing(gloom[c], 54, 70)
		for step in 4:
			if m.rng.randf() < 0.35:
				continue
			m.pluck(arp[(arp.size() - 1 - step) % arp.size()], t0 + step * 1.0, 0.14, m.rng.randf_range(-0.4, 0.4), 3.0, 0.998, 0.3)
	m.flute(66, 43.0, 2.5, 0.1, 0.1)
	m.flute(64, 46.0, 1.5, 0.09, 0.1)
	m.flute(62, 47.6, 3.0, 0.1, 0.1)
	# The dream fades: one long, soft D major chord thinning into haze while a
	# music box drifts slowly downward. No drums, nothing sour.
	m.pad([38, 50, 54, 57, 64], 52.0, 14.0, 0.2, 900.0, 3.0, 5.0)
	m.pad([62, 66, 69], 55.0, 10.0, 0.08, 1600.0, 3.0, 4.0)
	var box := [86, 81, 83, 78, 81, 76, 78, 74]
	for k in box.size():
		m.bell(box[k], 52.5 + k * 1.55, 0.05 - k * 0.004, sin(k * 1.3) * 0.5, 3.0, [1.0, 2.0, 4.07])
	# Cast out: D minor, a lone flute over a falling harp.
	var lost := [[38, [0, 3, 7, 10]], [34, [0, 4, 7, 11]], [43, [0, 3, 7, 10]], [45, [0, 4, 7, 10]]]
	for c in 4:
		var t0 := 66.0 + c * 3.5
		m.pad(_voicing(lost[c], 50, 67), t0, 3.5, 0.2, 800.0, 1.0, 2.0)
		m.pad([lost[c][0]], t0, 3.5, 0.1, 280.0, 1.0, 2.0)
		var arp := _voicing(lost[c], 57, 76)
		for step in 4:
			m.pluck(arp[arp.size() - 1 - step % arp.size()], t0 + step * 0.85, 0.13, 0.3, 2.5, 0.998, 0.35)
	_melody(m, lost, _scale(D_AEOLIAN, 62, 79), 67.0, 12.0, 0.13, 3.5, 66.0)
	# Waking: a bright swell and rising bells, gone by the end.
	m.pad(_voicing([38, [0, 4, 7, 11, 14]], 52, 76), 80.0, 5.5, 0.22, 1600.0, 2.5, 3.0)
	for k in 6:
		m.bell([74, 78, 81, 85, 86, 90][k], 81.0 + k * 0.45, 0.06, -0.5 + k * 0.2, 4.0, [1.0, 2.0, 4.07])
	m.normalize()
	return m


# --- Helpers -----------------------------------------------------------------

## Chord tones folded into [lo, hi), sorted, without duplicates.
static func _voicing(chord: Array, lo: int, hi: int) -> Array:
	var root: int = chord[0]
	var out := []
	for interval in chord[1]:
		var n: int = root + interval
		while n < lo:
			n += 12
		while n >= hi:
			n -= 12
		if not out.has(n):
			out.append(n)
	out.sort()
	return out


static func _scale(pitch_classes: Array, lo: int, hi: int) -> Array:
	var out := []
	for n in range(lo, hi):
		if pitch_classes.has(n % 12):
			out.append(n)
	return out


## A wandering flute phrase. Long notes snap to a tone of the chord underneath
## (chords change every `chord_seconds`, counted from `chords_start`).
static func _melody(m: MusicSynth, chords: Array, scale: Array, start: float, span: float, gain: float, chord_seconds := CHORD_SECONDS, chords_start := 0.0) -> void:
	var rhythm := [1.0, 0.5, 0.5, 1.5, 1.0, 2.0, 0.5, 1.0]
	var moves := [-2, -1, -1, 1, 1, 2, 0, -1, 1]
	var idx := m.rng.randi_range(scale.size() / 3, scale.size() * 2 / 3)
	var t := start
	var stop := start + span
	while t < stop - 0.5:
		var d: float = minf(rhythm[m.rng.randi() % rhythm.size()], stop - t)
		var note: int = scale[idx]
		if d >= 1.5 or t + d >= stop - 0.5:
			var chord: Array = chords[clampi(int((t - chords_start) / chord_seconds), 0, chords.size() - 1)]
			note = _nearest_chord_tone(note, chord)
			d = maxf(d, 1.5)
		m.flute(note, t, d * 0.95, gain, m.rng.randf_range(-0.25, 0.25))
		t += d
		idx = clampi(idx + moves[m.rng.randi() % moves.size()], 0, scale.size() - 1)


static func _nearest_chord_tone(note: int, chord: Array) -> int:
	var best := note
	var best_dist := 99
	for interval in chord[1]:
		var pc: int = (chord[0] + interval) % 12
		for candidate in [note - 2, note - 1, note, note + 1, note + 2]:
			if candidate % 12 == pc and absi(candidate - note) < best_dist:
				best_dist = absi(candidate - note)
				best = candidate
	return best


## Sparse crystal bell plinks scattered across the loop (the spa shimmer).
static func _sparkle(m: MusicSynth, scale: Array, count: int, gain: float) -> void:
	for k in count:
		var note: int = scale[m.rng.randi() % scale.size()]
		m.bell(note, m.rng.randf() * LOOP_SECONDS, gain, m.rng.randf_range(-0.8, 0.8), 2.5, [1.0, 2.0, 4.07])
