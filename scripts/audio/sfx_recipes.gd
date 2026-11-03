class_name SfxRecipes
extends RefCounted
## Recipes for every generated sound effect. Each method builds one variant; the
## render tool saves them as res://audio/generated/<name>_<variant>.wav.
## Names starting with "loop_" are rendered as seamless loops.

## name: [variant count, seconds]
const SOUNDS := {
	# Player weapons
	"shot_rifle": [3, 0.5], "shot_cannon": [3, 0.9], "shot_scatter": [3, 0.8], "shot_smg": [3, 0.25], "shot_lance": [2, 1.3],
	"elem_fire": [3, 0.5], "elem_shock": [3, 0.35], "elem_frost": [3, 0.5],
	"dry_fire": [2, 0.15], "reload_out": [2, 0.4], "reload_in": [2, 0.6],
	"hit_marker": [3, 0.12], "hit_crit": [2, 0.35], "impact_stone": [4, 0.3], "impact_metal": [4, 0.35],
	# Player movement & abilities
	"footstep_grass": [5, 0.25], "footstep_stone": [5, 0.2], "footstep_sand": [5, 0.3], "footstep_snow": [5, 0.3],
	"gear_rustle": [4, 0.3], "jump": [3, 0.35], "land": [3, 0.35], "dash": [3, 0.5], "nova": [2, 1.8],
	"player_hurt": [4, 0.4], "player_death": [1, 2.0], "respawn": [1, 2.2], "level_up": [1, 2.6],
	"equip": [2, 0.7], "loot_drop_0": [1, 1.2], "loot_drop_1": [1, 1.4], "loot_drop_2": [1, 1.8],
	"loot_drop_3": [1, 2.2], "loot_drop_4": [1, 3.2], "ui_notify": [1, 0.8], "camp_cleared": [1, 2.4],
	# Enemies
	"husk_aggro": [3, 1.0], "husk_attack": [3, 0.5], "husk_step": [4, 0.3],
	"sentinel_alert": [2, 0.7], "sentinel_shoot": [3, 0.5], "orb_impact": [3, 0.5],
	"brute_roar": [2, 1.8], "brute_windup": [1, 1.0], "brute_slam": [2, 2.0], "brute_step": [4, 0.5],
	"death_stone": [3, 1.2], "death_sentinel": [2, 1.2],
	# Water
	"splash_in": [3, 1.0], "splash_out": [3, 0.6], "swim_stroke": [4, 0.7], "footstep_water": [5, 0.35],
	"bubbles": [4, 1.0], "loop_underwater": [1, 11.0],
	# Story
	"thunder": [3, 4.0], "door_slam": [1, 1.2], "loop_rain": [1, 9.0],
	# World
	"bird_chirp": [6, 1.4],
	"loop_wind_soft": [1, 13.0], "loop_wind_strong": [1, 13.0], "loop_water": [1, 13.0],
	"loop_crystal": [1, 9.0], "loop_fire": [1, 7.0], "loop_sentinel": [1, 4.5],
}

const S := SfxSynth.SINE
const T := SfxSynth.TRIANGLE
const Q := SfxSynth.SQUARE
const W := SfxSynth.SAW


func build(sound: String, variant: int) -> SfxSynth:
	var spec: Array = SOUNDS[sound]
	var s := SfxSynth.new(spec[1], variant + sound.hash())
	if sound.begins_with("loot_drop_"):
		loot_drop(s, sound.right(1).to_int())
	else:
		call(sound, s, variant)
	return s


func _p(s: SfxSynth, spread := 0.05) -> float:
	return s.rng.randf_range(1.0 - spread, 1.0 + spread)


# --- Weapons -----------------------------------------------------------------

func shot_rifle(s: SfxSynth, _v: int) -> void:
	var p := _p(s)
	s.noise(0.0, 0.3, 0.9, 24.0, 7000.0, 1200.0, 150.0)
	s.tone(0.0, 0.2, 190.0 * p, 55.0, 0.8, 26.0, Q)
	s.tone(0.0, 0.03, 2400.0 * p, 900.0, 0.25, 90.0, W)
	s.noise(0.03, 0.45, 0.16, 6.0, 900.0, 300.0)


func shot_cannon(s: SfxSynth, _v: int) -> void:
	var p := _p(s)
	s.noise(0.0, 0.5, 1.0, 12.0, 5000.0, 700.0, 60.0)
	s.tone(0.0, 0.45, 120.0 * p, 38.0, 1.0, 9.0, Q)
	s.tone(0.0, 0.04, 1600.0 * p, 600.0, 0.3, 70.0, W)
	s.noise(0.05, 0.85, 0.3, 3.5, 700.0, 200.0)


func shot_scatter(s: SfxSynth, _v: int) -> void:
	var p := _p(s)
	s.noise(0.0, 0.5, 1.0, 10.0, 9000.0, 900.0, 80.0)
	s.tone(0.0, 0.4, 95.0 * p, 34.0, 0.9, 9.0, Q)
	s.grains(0.02, 0.2, 18, 0.25, 6000.0, 0.006, 0.8)
	s.noise(0.06, 0.7, 0.22, 4.0, 800.0, 250.0)
	s.noise(0.32, 0.12, 0.2, 30.0, 3000.0, 1500.0, 500.0)
	s.tone(0.32, 0.08, 900.0, 500.0, 0.12, 40.0, Q)


func shot_smg(s: SfxSynth, _v: int) -> void:
	var p := _p(s, 0.08)
	s.noise(0.0, 0.16, 0.8, 40.0, 8000.0, 2500.0, 300.0)
	s.tone(0.0, 0.1, 280.0 * p, 90.0, 0.6, 45.0, Q)
	s.tone(0.0, 0.02, 3200.0 * p, 1400.0, 0.2, 140.0, W)


func shot_lance(s: SfxSynth, _v: int) -> void:
	var p := _p(s)
	s.tone(0.0, 0.25, 600.0 * p, 2600.0, 0.25, 6.0, W, 0.02)
	s.tone(0.18, 0.9, 1800.0 * p, 160.0, 0.45, 5.0, Q)
	s.noise(0.18, 0.8, 0.9, 7.0, 6000.0, 600.0, 100.0)
	s.tone(0.18, 0.9, 75.0, 28.0, 0.9, 4.0, S)
	s.bell(0.18, 1320.0 * p, 0.12, 4.0, 1.0)


func elem_fire(s: SfxSynth, _v: int) -> void:
	s.noise(0.0, 0.4, 0.4, 7.0, 2500.0, 900.0, 200.0, 0.02)
	s.grains(0.0, 0.4, 22, 0.5, 5000.0, 0.004, 0.7)


func elem_shock(s: SfxSynth, _v: int) -> void:
	var p := _p(s, 0.1)
	for k in 5:
		var at := k * 0.045 + s.rng.randf() * 0.02
		s.tone(at, 0.05, 1400.0 * p * s.rng.randf_range(0.7, 1.4), 500.0, 0.35, 25.0, Q)
	s.noise(0.0, 0.3, 0.3, 12.0, 9000.0, 4000.0, 2000.0)


func elem_frost(s: SfxSynth, _v: int) -> void:
	var p := _p(s, 0.08)
	s.bell(0.0, 2100.0 * p, 0.35, 9.0, 0.5, [1.0, 2.32, 3.9, 5.7])
	s.noise(0.0, 0.3, 0.2, 14.0, 12000.0, 8000.0, 4000.0)


func dry_fire(s: SfxSynth, _v: int) -> void:
	s.noise(0.0, 0.03, 0.8, 120.0, 6000.0, 3000.0, 1500.0)
	s.tone(0.0, 0.05, 1800.0 * _p(s), 1200.0, 0.3, 80.0, Q)


func reload_out(s: SfxSynth, _v: int) -> void:
	s.noise(0.0, 0.05, 0.7, 70.0, 7000.0, 3000.0, 1000.0)
	s.tone(0.0, 0.06, 1100.0 * _p(s), 900.0, 0.35, 60.0, T)
	s.noise(0.08, 0.25, 0.3, 10.0, 1800.0, 3500.0, 600.0, 0.05)


func reload_in(s: SfxSynth, _v: int) -> void:
	s.noise(0.0, 0.06, 0.9, 60.0, 5000.0, 2000.0, 400.0)
	s.tone(0.0, 0.08, 700.0 * _p(s), 500.0, 0.4, 50.0, T)
	s.noise(0.18, 0.05, 0.8, 80.0, 8000.0, 4000.0, 1500.0)
	s.tone(0.18, 0.05, 2200.0, 1800.0, 0.25, 90.0, Q)
	s.tone(0.22, 0.35, 500.0, 1500.0, 0.12, 6.0, S, 0.05)


func hit_marker(s: SfxSynth, _v: int) -> void:
	s.tone(0.0, 0.08, 1500.0 * _p(s), 1100.0, 0.5, 45.0, T)
	s.noise(0.0, 0.03, 0.3, 100.0, 9000.0, 6000.0, 3000.0)


func hit_crit(s: SfxSynth, _v: int) -> void:
	s.bell(0.0, 1760.0 * _p(s, 0.02), 0.5, 10.0, 0.35)
	s.tone(0.0, 0.08, 2600.0, 1800.0, 0.3, 40.0, T)


func impact_stone(s: SfxSynth, _v: int) -> void:
	var p := _p(s, 0.12)
	s.tone(0.0, 0.2, 260.0 * p, 110.0, 0.7, 22.0, T)
	s.noise(0.0, 0.2, 0.6, 30.0, 3500.0, 800.0, 150.0)
	s.grains(0.01, 0.15, 6, 0.25, 4000.0, 0.005, 0.5)


func impact_metal(s: SfxSynth, _v: int) -> void:
	var p := _p(s, 0.1)
	s.bell(0.0, 520.0 * p, 0.4, 14.0, 0.3, [1.0, 2.41, 3.73, 5.2])
	s.noise(0.0, 0.1, 0.5, 45.0, 7000.0, 2000.0, 500.0)


# --- Movement ----------------------------------------------------------------

func footstep_grass(s: SfxSynth, _v: int) -> void:
	s.noise(0.0, 0.08, 0.5, 35.0, 2600.0, 1500.0, 250.0, 0.005)
	s.grains(0.0, 0.12, 9, 0.35, 5000.0, 0.006, 0.5)
	s.noise(0.05, 0.12, 0.4, 25.0, 3000.0, 1500.0, 300.0, 0.01)
	s.tone(0.0, 0.06, 110.0 * _p(s), 60.0, 0.25, 50.0, S)


func footstep_stone(s: SfxSynth, _v: int) -> void:
	s.noise(0.0, 0.05, 0.8, 70.0, 6000.0, 2500.0, 900.0)
	s.tone(0.0, 0.05, 420.0 * _p(s, 0.15), 260.0, 0.35, 70.0, T)
	s.noise(0.04, 0.06, 0.4, 60.0, 5000.0, 2500.0, 1200.0)
	s.tone(0.0, 0.08, 120.0, 70.0, 0.3, 40.0, S)


func footstep_sand(s: SfxSynth, _v: int) -> void:
	s.noise(0.0, 0.22, 0.6, 16.0, 1800.0, 900.0, 200.0, 0.02)
	s.grains(0.0, 0.18, 12, 0.18, 3000.0, 0.01, 0.6)


func footstep_snow(s: SfxSynth, _v: int) -> void:
	s.grains(0.0, 0.2, 30, 0.35, 3500.0, 0.007, 0.4)
	s.noise(0.0, 0.2, 0.35, 14.0, 1500.0, 900.0, 150.0, 0.03)


func gear_rustle(s: SfxSynth, _v: int) -> void:
	s.noise(0.0, 0.25, 0.4, 10.0, 3500.0, 2500.0, 800.0, 0.04)
	if s.rng.randf() < 0.6:
		s.bell(0.05, 2600.0 * _p(s, 0.1), 0.06, 20.0, 0.2, [1.0, 2.7, 4.1])


func jump(s: SfxSynth, _v: int) -> void:
	s.noise(0.0, 0.3, 0.6, 9.0, 1200.0, 3500.0, 300.0, 0.03)
	s.tone(0.0, 0.12, 140.0 * _p(s), 90.0, 0.25, 25.0, S)


func land(s: SfxSynth, _v: int) -> void:
	s.tone(0.0, 0.25, 130.0 * _p(s), 55.0, 0.8, 18.0, S)
	s.noise(0.0, 0.25, 0.6, 22.0, 1500.0, 500.0, 60.0)
	s.grains(0.0, 0.15, 10, 0.25, 4000.0, 0.006, 0.6)


func dash(s: SfxSynth, _v: int) -> void:
	s.noise(0.0, 0.45, 0.8, 6.0, 600.0, 5000.0, 300.0, 0.06)
	s.tone(0.0, 0.35, 300.0 * _p(s), 900.0, 0.12, 7.0, S, 0.03)
	s.bell(0.05, 1400.0, 0.06, 8.0, 0.4)


func nova(s: SfxSynth, _v: int) -> void:
	s.tone(0.0, 1.0, 95.0, 36.0, 1.0, 4.0, S, 0.01)
	s.noise(0.0, 1.2, 0.8, 3.5, 2500.0, 300.0, 40.0, 0.01)
	s.tone(0.0, 0.8, 400.0, 1600.0, 0.15, 4.0, W, 0.02)
	for k in 4:
		s.bell(0.05 + k * 0.07, [587.0, 880.0, 1174.0, 1760.0][k], 0.14, 3.0, 1.5)


func player_hurt(s: SfxSynth, _v: int) -> void:
	s.tone(0.0, 0.25, 160.0 * _p(s, 0.1), 80.0, 0.8, 14.0, S)
	s.noise(0.0, 0.25, 0.6, 20.0, 2000.0, 600.0, 100.0)
	s.tone(0.02, 0.2, 240.0, 150.0, 0.2, 12.0, W)


func player_death(s: SfxSynth, _v: int) -> void:
	s.tone(0.0, 1.6, 440.0, 55.0, 0.5, 1.8, T, 0.01)
	s.noise(0.0, 1.8, 0.5, 2.0, 1500.0, 200.0, 40.0)
	s.bell(0.1, 293.0, 0.3, 1.5, 1.8)
	s.bell(0.5, 220.0, 0.3, 1.5, 1.5)


func respawn(s: SfxSynth, _v: int) -> void:
	var notes := [587.3, 740.0, 880.0, 1174.7]
	for k in notes.size():
		s.bell(k * 0.14, notes[k], 0.3, 2.0, 2.0 - k * 0.14)
	s.noise(0.0, 1.5, 0.15, 1.5, 6000.0, 9000.0, 3000.0, 0.5)


func level_up(s: SfxSynth, _v: int) -> void:
	var notes := [587.3, 740.0, 880.0, 1174.7, 1480.0, 1760.0]
	for k in notes.size():
		s.bell(k * 0.09, notes[k], 0.28, 1.6, 2.5 - k * 0.09)
	s.tone(0.0, 2.2, 146.8, 146.8, 0.25, 1.2, T, 0.05)
	s.tone(0.0, 2.2, 220.0, 220.0, 0.18, 1.2, T, 0.05)
	s.noise(0.3, 2.0, 0.12, 1.2, 8000.0, 10000.0, 4000.0, 0.3)


func equip(s: SfxSynth, _v: int) -> void:
	s.noise(0.0, 0.06, 0.8, 60.0, 6000.0, 2500.0, 600.0)
	s.tone(0.0, 0.1, 900.0 * _p(s), 650.0, 0.4, 35.0, T)
	s.noise(0.1, 0.25, 0.3, 10.0, 2500.0, 2000.0, 500.0, 0.04)
	s.tone(0.15, 0.5, 300.0, 600.0, 0.15, 5.0, S, 0.06)
	s.bell(0.2, 1318.5, 0.12, 5.0, 0.5)


## Rarer drops ring more notes of a rising D major arpeggio.
func loot_drop(s: SfxSynth, rarity: int) -> void:
	var spec_len := s.buf.size() / float(SfxSynth.RATE)
	var scale := [587.3, 740.0, 880.0, 1174.7, 1480.0]
	for k in rarity + 1:
		s.bell(k * 0.11, scale[k], 0.3, 2.2, spec_len - k * 0.11)
	s.tone(0.0, 0.08, 400.0, 250.0, 0.3, 40.0, T)
	if rarity >= 3:
		s.tone(0.0, spec_len, 293.7, 293.7, 0.2, 1.0, T, 0.2)
		s.tone(0.0, spec_len, 440.0, 440.0, 0.15, 1.0, T, 0.2)
		s.noise(0.1, spec_len - 0.1, 0.12, 1.0, 9000.0, 12000.0, 4000.0, 0.3)


func ui_notify(s: SfxSynth, _v: int) -> void:
	s.bell(0.0, 880.0, 0.3, 4.0, 0.8)
	s.bell(0.08, 1318.5, 0.2, 4.0, 0.7)


func camp_cleared(s: SfxSynth, _v: int) -> void:
	var notes := [293.7, 440.0, 587.3]
	for k in notes.size():
		s.tone(k * 0.22, 1.6, notes[k], notes[k], 0.35, 1.6, W, 0.05)
		s.tone(k * 0.22, 1.6, notes[k] * 1.004, notes[k] * 1.004, 0.25, 1.6, T, 0.05)
	s.bell(0.66, 1174.7, 0.25, 1.8, 1.6)
	s.tone(0.0, 0.5, 70.0, 45.0, 0.6, 5.0, S)


# --- Enemies -----------------------------------------------------------------

func husk_aggro(s: SfxSynth, _v: int) -> void:
	var p := _p(s, 0.12)
	s.tone(0.0, 0.9, 85.0 * p, 60.0, 0.5, 2.5, W, 0.08)
	s.tone(0.0, 0.9, 128.0 * p, 92.0, 0.3, 2.5, Q, 0.08)
	s.grains(0.0, 0.8, 40, 0.3, 1500.0, 0.012, 0.5)
	s.noise(0.0, 0.9, 0.3, 3.0, 700.0, 400.0, 80.0, 0.1)


func husk_attack(s: SfxSynth, _v: int) -> void:
	s.noise(0.0, 0.35, 0.8, 8.0, 500.0, 3000.0, 200.0, 0.08)
	s.tone(0.0, 0.3, 100.0 * _p(s), 70.0, 0.35, 8.0, W, 0.05)


func husk_step(s: SfxSynth, _v: int) -> void:
	s.tone(0.0, 0.15, 150.0 * _p(s, 0.15), 70.0, 0.6, 25.0, S)
	s.grains(0.0, 0.1, 8, 0.4, 2500.0, 0.006, 0.6)


func sentinel_alert(s: SfxSynth, _v: int) -> void:
	for k in 3:
		s.tone(k * 0.13, 0.12, 900.0 + k * 300.0, 1300.0 + k * 300.0, 0.35, 15.0, T, 0.005)
	s.tone(0.0, 0.6, 220.0, 330.0, 0.15, 3.0, Q, 0.05)


func sentinel_shoot(s: SfxSynth, _v: int) -> void:
	var p := _p(s, 0.08)
	s.tone(0.0, 0.35, 1500.0 * p, 250.0, 0.5, 9.0, Q)
	s.tone(0.0, 0.3, 300.0 * p, 120.0, 0.4, 10.0, S)
	s.noise(0.0, 0.2, 0.25, 15.0, 6000.0, 2000.0, 1000.0)


func orb_impact(s: SfxSynth, _v: int) -> void:
	s.tone(0.0, 0.2, 500.0 * _p(s, 0.1), 120.0, 0.6, 18.0, S)
	s.noise(0.0, 0.4, 0.5, 9.0, 5000.0, 800.0, 300.0)
	s.grains(0.05, 0.3, 14, 0.2, 7000.0, 0.004, 0.8)


func brute_roar(s: SfxSynth, _v: int) -> void:
	var p := _p(s, 0.08)
	s.tone(0.0, 1.6, 55.0 * p, 42.0, 0.7, 1.4, W, 0.15)
	s.tone(0.0, 1.6, 82.0 * p, 62.0, 0.5, 1.4, Q, 0.15)
	s.noise(0.0, 1.6, 0.6, 1.6, 400.0, 900.0, 60.0, 0.15)
	s.grains(0.1, 1.3, 60, 0.25, 1200.0, 0.015, 0.6)


func brute_windup(s: SfxSynth, _v: int) -> void:
	s.tone(0.0, 0.95, 40.0, 95.0, 0.7, 0.3, W, 0.3)
	s.noise(0.0, 0.95, 0.5, 0.5, 300.0, 1500.0, 40.0, 0.4)


func brute_slam(s: SfxSynth, _v: int) -> void:
	s.tone(0.0, 1.2, 65.0 * _p(s), 24.0, 1.0, 3.0, S)
	s.noise(0.0, 1.6, 1.0, 3.0, 2500.0, 180.0, 30.0)
	s.grains(0.05, 1.2, 70, 0.35, 3000.0, 0.012, 0.9)
	s.tone(0.0, 0.08, 900.0, 300.0, 0.3, 40.0, Q)


func brute_step(s: SfxSynth, _v: int) -> void:
	s.tone(0.0, 0.35, 75.0 * _p(s, 0.1), 38.0, 0.9, 10.0, S)
	s.noise(0.0, 0.3, 0.5, 14.0, 900.0, 300.0, 40.0)
	s.grains(0.02, 0.25, 10, 0.2, 2500.0, 0.008, 0.6)


func death_stone(s: SfxSynth, _v: int) -> void:
	s.tone(0.0, 0.5, 140.0 * _p(s, 0.1), 50.0, 0.7, 6.0, S)
	s.noise(0.0, 0.9, 0.6, 4.0, 3000.0, 400.0, 80.0)
	s.grains(0.0, 1.0, 55, 0.4, 3500.0, 0.01, 0.9)


func death_sentinel(s: SfxSynth, _v: int) -> void:
	s.tone(0.0, 0.9, 1200.0 * _p(s, 0.08), 90.0, 0.4, 3.0, Q)
	s.noise(0.0, 0.8, 0.6, 5.0, 9000.0, 1500.0, 600.0)
	s.grains(0.0, 0.7, 40, 0.3, 9000.0, 0.004, 0.8)
	s.bell(0.0, 1046.5, 0.25, 4.0, 1.0, [1.0, 2.32, 3.9, 5.7])


# --- Water -------------------------------------------------------------------

func _droplets(s: SfxSynth, start: float, span: float, count: int, amp: float) -> void:
	for k in count:
		var f := s.rng.randf_range(500.0, 1300.0)
		s.tone(start + s.rng.randf() * span, 0.06, f, f * 1.8, amp * s.rng.randf_range(0.4, 1.0), 35.0, S, 0.002)


func splash_in(s: SfxSynth, _v: int) -> void:
	s.noise(0.0, 0.7, 1.0, 5.0, 4500.0, 900.0, 150.0, 0.01)
	s.grains(0.02, 0.6, 45, 0.35, 6000.0, 0.01, 0.8)
	s.tone(0.0, 0.25, 170.0 * _p(s), 65.0, 0.45, 10.0, S)
	_droplets(s, 0.1, 0.7, 10, 0.18)


func splash_out(s: SfxSynth, _v: int) -> void:
	s.noise(0.0, 0.4, 0.6, 8.0, 3000.0, 1200.0, 300.0, 0.03)
	_droplets(s, 0.05, 0.45, 8, 0.15)


func swim_stroke(s: SfxSynth, _v: int) -> void:
	s.noise(0.0, 0.55, 0.7, 5.0, 1200.0, 2800.0, 200.0, 0.12)
	s.grains(0.1, 0.4, 14, 0.2, 5000.0, 0.008, 0.6)
	_droplets(s, 0.2, 0.4, 4, 0.1)


func footstep_water(s: SfxSynth, _v: int) -> void:
	s.noise(0.0, 0.25, 0.8, 14.0, 3000.0, 1200.0, 250.0, 0.01)
	_droplets(s, 0.03, 0.25, 4, 0.15)


func bubbles(s: SfxSynth, _v: int) -> void:
	var count := s.rng.randi_range(6, 12)
	for k in count:
		var f := s.rng.randf_range(250.0, 700.0)
		s.tone(s.rng.randf() * 0.8, 0.09, f, f * 2.2, 0.35 * s.rng.randf_range(0.5, 1.0), 30.0, S, 0.003)


func loop_underwater(s: SfxSynth, _v: int) -> void:
	var lp := 0.0
	var lp2 := 0.0
	var n := s.buf.size()
	for i in n:
		var t := float(i) / SfxSynth.RATE
		var swell := 0.6 + 0.4 * sin(t * 0.8) * sin(t * 0.33 + 1.0)
		var a := 1.0 - exp(-TAU * 220.0 / SfxSynth.RATE)
		lp += a * (s.rng.randf_range(-1.0, 1.0) - lp)
		lp2 += a * (lp - lp2)
		s.buf[i] = lp2 * 2.5 * swell
	for k in 18:
		var f := s.rng.randf_range(200.0, 500.0)
		s.tone(s.rng.randf() * 10.0, 0.1, f, f * 2.0, 0.08, 25.0, S, 0.003)
	s.make_loop(1.5)


# --- Story -------------------------------------------------------------------

func thunder(s: SfxSynth, _v: int) -> void:
	s.noise(0.0, 0.25, 1.0, 10.0, 9000.0, 3000.0, 400.0)
	s.noise(0.05, 3.8, 0.9, 0.9, 900.0, 120.0, 25.0, 0.15)
	s.grains(0.1, 2.5, 50, 0.3, 700.0, 0.05, 0.8)
	s.tone(0.05, 3.0, 55.0, 30.0, 0.5, 1.0, S, 0.2)


func door_slam(s: SfxSynth, _v: int) -> void:
	s.tone(0.0, 0.5, 110.0, 55.0, 1.0, 8.0, S)
	s.noise(0.0, 0.5, 0.8, 9.0, 2500.0, 400.0, 60.0)
	s.tone(0.0, 0.9, 260.0, 240.0, 0.25, 4.0, T)
	s.grains(0.02, 0.3, 10, 0.2, 3000.0, 0.008, 0.7)


func loop_rain(s: SfxSynth, _v: int) -> void:
	var dur := s.buf.size() / float(SfxSynth.RATE)
	s.noise(0.0, dur, 0.5, 0.0, 6000.0, 6000.0, 800.0)
	s.grains(0.0, dur, 900, 0.25, 7000.0, 0.003)
	s.noise(0.0, dur, 0.3, 0.0, 400.0, 400.0, 40.0)
	s.make_loop(1.0)


# --- World -------------------------------------------------------------------

func bird_chirp(s: SfxSynth, v: int) -> void:
	var p := _p(s, 0.1)
	match v % 3:
		0: # quick rising chirps
			var count := s.rng.randi_range(3, 6)
			for k in count:
				s.tone(k * 0.11, 0.07, 3000.0 * p, 4600.0 * p, 0.35, 25.0, S, 0.005)
		1: # two-note whistle
			s.tone(0.0, 0.35, 2300.0 * p, 2200.0 * p, 0.35, 5.0, S, 0.03)
			s.tone(0.42, 0.45, 1850.0 * p, 1700.0 * p, 0.35, 4.0, S, 0.03)
		_: # warbling trill
			for k in 12:
				var f := 3600.0 * p * (1.0 + 0.12 * sin(k * 1.7))
				s.tone(k * 0.045, 0.04, f, f * 0.9, 0.3, 30.0, S, 0.003)


func loop_wind_soft(s: SfxSynth, _v: int) -> void:
	_wind(s, 0.5, 350.0, 900.0)


func loop_wind_strong(s: SfxSynth, _v: int) -> void:
	_wind(s, 0.9, 500.0, 2200.0)


func _wind(s: SfxSynth, amp: float, low: float, high: float) -> void:
	var lp := 0.0
	var lp2 := 0.0
	var n := s.buf.size()
	for i in n:
		var t := float(i) / SfxSynth.RATE
		var gust := 0.5 + 0.3 * sin(t * 0.55) + 0.2 * sin(t * 1.37 + 1.0)
		var cutoff := lerpf(low, high, gust * gust)
		var a := 1.0 - exp(-TAU * cutoff / SfxSynth.RATE)
		lp += a * (s.rng.randf_range(-1.0, 1.0) - lp)
		lp2 += a * (lp - lp2)
		s.buf[i] = lp2 * amp * (0.4 + gust)
	s.make_loop(1.5)


func loop_water(s: SfxSynth, _v: int) -> void:
	var lp := 0.0
	var n := s.buf.size()
	for i in n:
		var t := float(i) / SfxSynth.RATE
		var wave := pow(0.5 + 0.5 * sin(t * 1.9 + sin(t * 0.7) * 2.0), 3.0)
		var a := 1.0 - exp(-TAU * (300.0 + wave * 900.0) / SfxSynth.RATE)
		lp += a * (s.rng.randf_range(-1.0, 1.0) - lp)
		s.buf[i] = lp * (0.15 + wave * 0.8)
	for k in 30:
		s.tone(s.rng.randf() * 11.0, 0.08, 900.0 * _p(s, 0.4), 1500.0, 0.08, 40.0, S, 0.005)
	s.make_loop(1.5)


func loop_crystal(s: SfxSynth, _v: int) -> void:
	var dur := s.buf.size() / float(SfxSynth.RATE)
	for f in [146.83, 220.0, 293.66, 440.0]:
		var n := s.buf.size()
		var phase := 0.0
		for i in n:
			var t := float(i) / SfxSynth.RATE
			phase += f * (1.0 + 0.002 * sin(t * 0.9)) / SfxSynth.RATE
			s.buf[i] += sin(TAU * phase) * 0.12 * (0.7 + 0.3 * sin(t * 0.6 + f))
	for k in 6:
		s.bell(s.rng.randf() * (dur - 2.0), [1174.7, 1318.5, 1760.0][k % 3], 0.05, 2.0, 2.0)
	s.make_loop(1.5)


func loop_fire(s: SfxSynth, _v: int) -> void:
	var dur := s.buf.size() / float(SfxSynth.RATE)
	s.noise(0.0, dur, 0.35, 0.0, 700.0, 700.0, 80.0)
	s.grains(0.0, dur, 260, 0.45, 5000.0, 0.004)
	for k in 10:
		s.noise(s.rng.randf() * (dur - 0.5), 0.15, 0.4, 20.0, 2500.0, 1200.0, 300.0)
	s.make_loop(1.0)


func loop_sentinel(s: SfxSynth, _v: int) -> void:
	var n := s.buf.size()
	var p1 := 0.0
	var p2 := 0.0
	for i in n:
		var t := float(i) / SfxSynth.RATE
		p1 += 110.0 / SfxSynth.RATE
		p2 += 166.0 / SfxSynth.RATE
		var wob := 0.6 + 0.4 * sin(t * TAU * 1.5)
		s.buf[i] = (sin(TAU * p1) * 0.5 + tanh(sin(TAU * p2) * 2.0) * 0.2) * wob
	s.noise(0.0, n / float(SfxSynth.RATE), 0.08, 0.0, 4000.0, 4000.0, 1500.0)
	s.make_loop(0.5)
