extends Node
## Plays every sound in the game (autoload "Audio").
##
## Sounds are looked up by name. Files named <name>.ogg/.wav/.mp3 or <name>_<n>.*
## in res://audio/sfx/ (e.g. hand-picked files from free packs) replace the generated
## fallbacks in res://audio/generated/. Multiple numbered files become random variants.
##
## Music: all themes are 48s loops on the same grid. They start together and stay in
## sync; biome changes crossfade between them and combat fades in a drum layer.

const CUSTOM_DIR := "res://audio/sfx/"
const GENERATED_DIR := "res://audio/generated/"
const MUSIC_DIR := "res://audio/music/"
const AUDIO_EXTENSIONS := ["wav", "ogg", "mp3"]
const BIOME_MUSIC := {"sanctum": "sanctum", "meadow": "wilds", "shore": "wilds", "highlands": "highlands"}
const BIOME_AMBIENCE := {
	"sanctum": {"loop_wind_soft": 0.25, "loop_crystal": 0.55},
	"meadow": {"loop_wind_soft": 0.6},
	"shore": {"loop_wind_soft": 0.4, "loop_water": 0.7},
	"highlands": {"loop_wind_strong": 0.75},
}
const MUSIC_DB := -15.0
const AMBIENCE_DB := -16.0
const SFX_DB := 0.0

## The mix: base level (dB) of every sound. Call sites only add situational offsets
## (stride, fall speed, rarity), so all balancing happens here. Tiers, quiet to loud:
## background texture < footsteps/UI < player actions < gunfire < big events.
const MIX := {
	# Gunfire: rapid weapons sit lower so sustained fire doesn't fatigue.
	"shot_smg": -12.0, "shot_rifle": -10.0, "shot_scatter": -7.5, "shot_cannon": -7.0, "shot_lance": -6.0,
	"elem_fire": -19.0, "elem_shock": -19.0, "elem_frost": -18.0,
	"dry_fire": -15.0, "reload_out": -14.0, "reload_in": -13.0,
	"hit_marker": -21.0, "hit_crit": -16.0, "impact_stone": -15.0, "impact_metal": -15.0,
	# Movement
	"footstep_grass": -21.0, "footstep_stone": -21.0, "footstep_sand": -20.0, "footstep_snow": -20.0,
	"footstep_water": -18.0, "gear_rustle": -29.0, "jump": -17.0, "land": -15.0, "dash": -12.0,
	"splash_in": -11.0, "splash_out": -16.0, "swim_stroke": -15.0, "bubbles": -20.0,
	"heartbeat": -7.0, "gasp": -11.0, "shake_off": -15.0,
	# Abilities & player events
	"nova": -8.0, "player_hurt": -11.0, "player_death": -7.0, "respawn": -10.0, "level_up": -8.0,
	"equip": -11.0, "camp_cleared": -10.0, "ui_notify": -15.0,
	"loot_drop_0": -13.0, "loot_drop_1": -12.0, "loot_drop_2": -10.5, "loot_drop_3": -9.0, "loot_drop_4": -7.5,
	# Enemies (positional, so distance lowers them further)
	"husk_aggro": -10.0, "husk_attack": -11.0, "husk_step": -18.0,
	"sentinel_alert": -12.0, "sentinel_shoot": -11.0, "orb_impact": -12.0,
	"brute_roar": -6.0, "brute_windup": -7.0, "brute_slam": -4.0, "brute_step": -10.0,
	"death_stone": -9.0, "death_sentinel": -9.0,
	# World
	"bird_chirp": -17.0, "crow_caw": -15.0, "gull_call": -16.0, "owl_hoot": -14.0, "wing_flap": -18.0, "loop_crystal": -10.0, "loop_fire": -11.0, "loop_sentinel": -15.0,
	# Story
	"thunder": -6.0, "door_slam": -8.0, "loop_rain": -14.0,
}
const SETTINGS_PATH := "user://settings.cfg"

## Player-facing master volume (0-1), changed with the - and = keys and saved.
var master_volume := 0.6
const COMBAT_GAIN := 0.8

var _library := {}
var _music := {}
var _ambience := {}
var _biome := ""
var _pending_biome := ""
var _pending_time := 0.0
var _combat := 0.0
var _bird_timer := 4.0
var _master_fade := 0.0
var _underwater := 0.0
var _muffle_filters: Array[AudioEffectLowPassFilter] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_buses()
	_load_settings()
	_library = _scan(GENERATED_DIR)
	var custom := _scan(CUSTOM_DIR)
	for sound in custom:
		_library[sound] = custom[sound]
	for sound in _library:
		if sound.begins_with("loop_"):
			for stream in _library[sound]:
				_make_looping(stream)
	_start_music()
	_start_ambience()


# --- Public API --------------------------------------------------------------

func has_sound(sound: String) -> bool:
	return _library.has(sound)


## A stream for callers that manage their own player (e.g. cutscene rain).
func get_stream(sound: String) -> AudioStream:
	return _pick(sound)


## Plays a one-shot at its MIX level plus `offset_db`. `at` may be null
## (non-positional), a Vector3 or a Node3D.
func play(sound: String, at: Variant = null, offset_db := 0.0, pitch := 1.0, jitter := 0.06, max_distance := 60.0) -> void:
	var stream := _pick(sound)
	if stream == null:
		return
	var volume_db: float = MIX.get(sound, -12.0) + offset_db
	var pitch_scale := pitch * randf_range(1.0 - jitter, 1.0 + jitter)
	if at == null:
		var p := AudioStreamPlayer.new()
		p.stream = stream
		p.volume_db = volume_db
		p.pitch_scale = pitch_scale
		p.bus = "SFX"
		add_child(p)
		p.finished.connect(p.queue_free)
		p.play()
		return
	var scene := get_tree().current_scene
	if scene == null:
		return
	var p3 := AudioStreamPlayer3D.new()
	p3.stream = stream
	p3.volume_db = volume_db
	p3.pitch_scale = pitch_scale
	p3.bus = "SFX"
	p3.unit_size = 8.0
	p3.max_distance = max_distance
	scene.add_child(p3)
	p3.global_position = at.global_position if at is Node3D else at
	p3.finished.connect(p3.queue_free)
	p3.play()


## Attaches a looping positional sound to a node; it follows the node and dies with it.
func attach_loop(node: Node3D, sound: String, offset_db := 0.0, max_distance := 30.0, unit_size := 5.0) -> AudioStreamPlayer3D:
	var stream := _pick(sound)
	if stream == null:
		return null
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.volume_db = MIX.get(sound, -12.0) + offset_db
	p.bus = "Ambience"
	p.max_distance = max_distance
	p.unit_size = unit_size
	p.autoplay = true
	node.add_child(p)
	return p


# --- Library -----------------------------------------------------------------

func _scan(dir_path: String) -> Dictionary:
	var found := {}
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return found
	var seen := {}
	for file in dir.get_files():
		file = file.trim_suffix(".import").trim_suffix(".remap")
		if seen.has(file) or not AUDIO_EXTENSIONS.has(file.get_extension().to_lower()):
			continue
		seen[file] = true
		var stream := load(dir_path + file) as AudioStream
		if stream == null:
			continue
		var sound := _sound_name(file.get_basename())
		if not found.has(sound):
			found[sound] = []
		found[sound].append(stream)
	return found


## "footstep_grass_3" -> "footstep_grass"; "loot_drop_4_1" -> "loot_drop_4".
func _sound_name(base: String) -> String:
	var parts := base.rsplit("_", true, 1)
	if parts.size() == 2 and parts[1].is_valid_int() and _library_name_ok(parts[0], base):
		return parts[0]
	return base


func _library_name_ok(stem: String, base: String) -> bool:
	# Rarity-indexed sounds like "loot_drop_4" keep their number unless a variant follows.
	return not (stem == "loot_drop" and base.count("_") == 2)


func _pick(sound: String) -> AudioStream:
	var options: Array = _library.get(sound, [])
	if options.is_empty():
		push_warning("Missing sound: " + sound)
		return null
	return options[randi() % options.size()]


func _make_looping(stream: AudioStream) -> void:
	if stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = int(wav.get_length() * wav.mix_rate)
	elif stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	elif stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true


# --- Buses -------------------------------------------------------------------

func _setup_buses() -> void:
	for bus_name in ["Music", "Ambience", "SFX"]:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, bus_name)
			AudioServer.set_bus_send(i, "Master")
	var hall := AudioEffectReverb.new()
	hall.room_size = 0.85
	hall.damping = 0.35
	hall.spread = 1.0
	hall.wet = 0.32
	hall.dry = 0.85
	AudioServer.add_bus_effect(AudioServer.get_bus_index("Music"), hall)
	var room := AudioEffectReverb.new()
	room.room_size = 0.45
	room.damping = 0.6
	room.wet = 0.1
	room.dry = 1.0
	AudioServer.add_bus_effect(AudioServer.get_bus_index("SFX"), room)
	AudioServer.add_bus_effect(0, AudioEffectHardLimiter.new())
	# Underwater muffling: a lowpass on every bus, wide open until submerged.
	for bus_name in ["Music", "Ambience", "SFX"]:
		var muffle := AudioEffectLowPassFilter.new()
		muffle.cutoff_hz = 20000.0
		AudioServer.add_bus_effect(AudioServer.get_bus_index(bus_name), muffle, 0)
		_muffle_filters.append(muffle)


# --- Music & ambience --------------------------------------------------------

func _start_music() -> void:
	for theme in MusicThemes.THEMES:
		var path: String = MUSIC_DIR + theme + ".wav"
		if not ResourceLoader.exists(path):
			continue
		var stream := load(path) as AudioStream
		_make_looping(stream)
		var p := AudioStreamPlayer.new()
		p.stream = stream
		p.bus = "Music"
		p.volume_db = -80.0
		add_child(p)
		_music[theme] = p
	# Start every theme on the same frame so they stay in lockstep.
	for theme in _music:
		_music[theme].play()


func _start_ambience() -> void:
	for amb in ["loop_wind_soft", "loop_wind_strong", "loop_water", "loop_crystal", "loop_underwater"]:
		var stream := _pick(amb)
		if stream == null:
			continue
		var p := AudioStreamPlayer.new()
		p.stream = stream
		p.bus = "Ambience"
		p.volume_db = -80.0
		add_child(p)
		p.play()
		_ambience[amb] = p


func _process(delta: float) -> void:
	var player := Game.player
	if player == null or not is_instance_valid(player):
		return
	_master_fade = minf(1.0, _master_fade + delta / 4.0)
	_update_biome(player, delta)
	_update_combat(player, delta)

	var active_theme: String = BIOME_MUSIC.get(_biome, "wilds")
	var duck := 1.0 if player.alive else 0.35
	for theme in _music:
		var target := 0.0
		if theme == "combat":
			target = _combat * COMBAT_GAIN
		elif theme == active_theme:
			target = 1.0 - _combat * 0.35
		target *= duck * _master_fade
		var p: AudioStreamPlayer = _music[theme]
		var gain := lerpf(db_to_linear(p.volume_db), target, 1.0 - exp(-delta / 1.6))
		p.volume_db = linear_to_db(maxf(gain, 0.0001))
	_apply_bus_levels()

	_underwater = move_toward(_underwater, 1.0 if Game.underwater else 0.0, delta * 4.0)
	var cutoff := lerpf(20000.0, 550.0, sqrt(_underwater))
	for muffle in _muffle_filters:
		muffle.cutoff_hz = cutoff

	var amb_targets: Dictionary = BIOME_AMBIENCE.get(_biome, {})
	for amb in _ambience:
		var p: AudioStreamPlayer = _ambience[amb]
		var target: float = amb_targets.get(amb, 0.0) * _master_fade
		if amb == "loop_underwater":
			target = _underwater * 0.9
		else:
			target *= 1.0 - _underwater * 0.7
		var gain := lerpf(db_to_linear(p.volume_db), target, 1.0 - exp(-delta / 2.0))
		p.volume_db = linear_to_db(maxf(gain, 0.0001))

	_bird_timer -= delta
	if _bird_timer <= 0.0:
		_bird_timer = randf_range(2.5, 7.0)
		if (_biome == "meadow" or _biome == "shore") and _combat < 0.3 and not Game.underwater:
			var a := randf() * TAU
			var pos := player.global_position + Vector3(cos(a), 0.0, sin(a)) * randf_range(12.0, 30.0) + Vector3.UP * randf_range(4.0, 9.0)
			play("bird_chirp", pos, randf_range(-5.0, 2.0), randf_range(0.9, 1.15), 0.0, 80.0)


func _apply_bus_levels() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(master_volume, 0.0001)))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), MUSIC_DB)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Ambience"), AMBIENCE_DB)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), SFX_DB)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("volume_down"):
		set_master_volume(master_volume - 0.1)
	elif event.is_action_pressed("volume_up"):
		set_master_volume(master_volume + 0.1)


func set_master_volume(value: float) -> void:
	master_volume = clampf(snappedf(value, 0.1), 0.0, 1.0)
	_apply_bus_levels()
	Game.notify("Volume %d%%" % roundi(master_volume * 100.0))
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("audio", "master_volume", master_volume)
	cfg.save(SETTINGS_PATH)


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		master_volume = cfg.get_value("audio", "master_volume", master_volume)
	_apply_bus_levels()


## Biome changes only stick after a couple of seconds so walking along a border
## doesn't flip the music back and forth.
func _update_biome(player: Player, delta: float) -> void:
	var biome := Game.biome_at(player.global_position)
	if _biome == "":
		_biome = biome
	if biome == _biome:
		_pending_time = 0.0
		return
	if biome != _pending_biome:
		_pending_biome = biome
		_pending_time = 0.0
	_pending_time += delta
	if _pending_time > 2.5:
		_biome = biome


func _update_combat(player: Player, delta: float) -> void:
	var engaged := false
	if player.alive:
		for node in get_tree().get_nodes_in_group("enemies"):
			var e := node as Enemy
			if e and not e.dead and e.is_engaged() and e.global_position.distance_to(player.global_position) < 40.0:
				engaged = true
				break
	var rate := 1.0 / 1.2 if engaged else 1.0 / 5.0
	_combat = move_toward(_combat, 1.0 if engaged else 0.0, delta * rate)
