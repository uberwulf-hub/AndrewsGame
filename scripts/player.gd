class_name Player
extends CharacterBody3D
## Third-person over-the-shoulder hero: movement, gunplay, abilities, loot and leveling.

signal hit_confirmed(crit: bool, killed: bool)
signal damaged(amount: float)
signal leveled_up(new_level: int)
signal died
signal respawned
signal woke_up

## Mouse-wheel camera distance: 0 is first person, up to MAX_ZOOM behind.
const MAX_ZOOM := 6.0
const FIRST_PERSON := 0.35
const EYE_HEIGHT := 1.78

const WALK_SPEED := 6.5
const SPRINT_SPEED := 10.0
## On foot in the story: a walk by default, a run while Shift is held.
const STORY_WALK_SPEED := 2.2
const STORY_RUN_SPEED := 6.0
const AIM_SPEED := 4.0
const JUMP_VELOCITY := 7.5
const GRAVITY := 22.0
const MOUSE_SENSITIVITY := 0.0022
const NOVA_COOLDOWN := 8.0
const NOVA_RADIUS := 7.5
const DASH_COOLDOWN := 2.2
const DASH_SPEED := 26.0
const DASH_TIME := 0.18
const SPAWN_POINT := Vector3(0, 2, 6)
const NOVA_COLOR := Color(1.0, 0.78, 0.72)  # blossom pink-cream (Bloom, dash, the puff when knocked out)
const SWIM_DEPTH := 1.3  # water at chest height
const FLOAT_DEPTH := 1.45  # how deep the feet hang while treading water
const SWIM_SPEED := 4.0
const SWIM_SPRINT_SPEED := 6.5

var alive := true
var max_health := 100.0
var health := 100.0
var level := 1
var xp := 0
var weapon: WeaponData  # null while unarmed (the story start)
var ammo := 0
var spawn_point := SPAWN_POINT
var zoom := 3.4
## True during scripted moments (waking up): no control, the rig plays on its own.
var frozen := false
var nova_cooldown := 0.0
var dash_cooldown := 0.0
var focused_loot: LootDrop
var aiming := false
var swimming := false
var camera: Camera3D

var _yaw := 0.0
var _pitch := -0.12
var _recoil := 0.0
var _fire_timer := 0.0
var _reload_timer := 0.0
var _dash_timer := 0.0
var _dash_dir := Vector3.ZERO
var _momentum_timer := 0.0
var _since_damage := 10.0
var _shot_pose := 0.0
var _walk_phase := 0.0
var _respawn_timer := 0.0
var _sprinting := false
var _nearby_loot: Array = []

var _camera_rig: Node3D
## Height the third-person camera orbits around: shoulder height, or just
## over the hood for the shorter, big-headed ranger.
var _shoulder := 1.55
var _pitch_pivot: Node3D
var _spring: SpringArm3D
var _model: Node3D
var _rig: CharacterRig  # rigged hero model, when one is in models/hero
var _twist: TorsoTwist
var _legs: Node3D
var _torso: Node3D
var _backpedal := false
var _was_on_floor := true
var _fall_speed := 0.0
var _last_step_sign := 1.0
var _step_count := 0
var _hurt_sound_cooldown := 0.0
var _feet_wet := false
var _swim_facing := 0.0
var _swim_tilt := 0.0
var _stroke_timer := 0.0
var _bubble_timer := 2.0
var _leg_l: Node3D
var _leg_r: Node3D
var _gun_socket: Node3D
var _gun_model: Node3D
var _muzzle_light: OmniLight3D

## Unarmed: left click throws a punch, alternating fists.
const PUNCH_TIME := 0.42
const PUNCH_COOLDOWN := 0.5
const PUNCH_REACH := 1.3
const PUNCH_DAMAGE := 12.0
var _punch_time := 0.0  # counts down while a punch is out
var _punch_count := 0
var _punch_animated := false  # this punch is the rig's own animation, not PunchArm
## A one-off rig animation (punch, dodge, shot, hit...) playing over movement.
var _action_time := 0.0
var _action_soft := true  # moving off cancels it, so feet never slide
var _punch_cooldown := 0.0
var _punch_landed := false
var _punch_arm: PunchArm
var _sling_draw: SlingDraw
var _cross_legs: CrossLegs
var _sitting := false  # cross-legged on the ground (blended in by _cross_legs)
var _sit_forward := Vector3.FORWARD

## Building: the preview being placed, and a pause between "can't build here" thoughts.
signal says(lines: Array)
## A small menu of choices to show (heading, [label, Callable] pairs), e.g. a chest.
signal menu_requested(heading: String, options: Array)
var _placer: Placer
var _cant_build_cooldown := 0.0

## Stepping into a fire: a short hop back out during which the controls let go.
var _stagger := 0.0
var _soot_bones := {}  # bone name -> BoneAttachment3D carrying soot marks

## Sitting by a campfire (from its menu): E still opens the fire menu, and any
## move key makes him get up (the getting-up motion plays out first).
signal stood_up
var seated := false
var _seat_fire: Node3D
var _getting_up := false

## Holding his breath: air runs out after AIR_TIME under the surface and he
## passes out (the pets tow him ashore). As it runs low a heartbeat grows
## louder and faster and the view closes in (the HUD listens to `heartbeat`).
signal passed_out
signal heartbeat(panic: float)
const AIR_TIME := 30.0
var air := 1.0
var knocked_out := false
var tow := Vector3.ZERO  # the pets pulling him along while he's out
var _was_under := false
var _air_warned := false
var _heart_timer := 0.0

## Soaked after a swim: clothes darker and shiny, dripping, drying off over a
## minute or so (much faster by a fire). Wet clothes make the cold bite harder.
var wet := 0.0
var _wet_mat: StandardMaterial3D
var _wet_shown := 0.0
var _was_soaked := false


func _ready() -> void:
	Game.player = self
	collision_layer = 2
	collision_mask = 1 | 4
	floor_max_angle = deg_to_rad(50.0)
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 1.8
	shape.shape = capsule
	shape.position.y = 0.9
	add_child(shape)
	_build_model()
	_build_camera()
	if not Game.story_start:
		equip(WeaponData.generate(1, Game.rng, 0.0, "Rifle", 0))
	if Game.screenshot_mode:
		_yaw = Game.shot_yaw
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# --- Stats -------------------------------------------------------------------

func damage_multiplier() -> float:
	return 1.0 + 0.06 * (level - 1)


func xp_to_next() -> int:
	return int(40.0 * pow(level, 1.5))


func is_reloading() -> bool:
	return _reload_timer > 0.0


func momentum_active() -> bool:
	return _momentum_timer > 0.0


# --- Input & per-frame -------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	var motion := event as InputEventMouseMotion
	if motion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sens := MOUSE_SENSITIVITY * (0.5 if aiming else 1.0)
		_yaw -= motion.relative.x * sens
		_pitch = clampf(_pitch - motion.relative.y * sens, -1.25, 1.0)
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED \
			and (event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN):
		var step := -0.5 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 0.5
		zoom = clampf(zoom + step, 0.0, MAX_ZOOM)
		if zoom < FIRST_PERSON and step < 0.0:
			zoom = 0.0  # snap the last bit into first person
	elif event is InputEventMouseButton and event.is_pressed() and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not Game.screenshot_mode:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if _cross_legs:
		_cross_legs.amount = move_toward(_cross_legs.amount, 1.0 if _sitting else 0.0, delta / (0.5 if _sitting else 0.8))
		_cross_legs.ground = global_position.y
		_cross_legs.forward = _sit_forward
	_camera_rig.rotation.y = _yaw
	_pitch_pivot.rotation.x = _pitch + _recoil
	var smooth := 1.0 - exp(-12.0 * delta)
	# First person: camera at the eyes, shoulder offset gone, own body hidden.
	var first_person := zoom < FIRST_PERSON and not frozen
	var arm := 0.0 if first_person else (minf(zoom, 1.9) if aiming else zoom)
	_spring.spring_length = lerpf(_spring.spring_length, arm, smooth)
	_spring.position.x = lerpf(_spring.position.x, 0.0 if first_person else 0.65, smooth)
	_camera_rig.position.y = lerpf(_camera_rig.position.y, EYE_HEIGHT if first_person else _shoulder, smooth)
	if _rig:
		_rig.visible = not (first_person and _spring.spring_length < 0.3)
	var target_fov := 55.0 if aiming else (78.0 if _sprinting else 72.0)
	camera.fov = lerpf(camera.fov, target_fov, smooth)
	_recoil = lerpf(_recoil, 0.0, 1.0 - exp(-9.0 * delta))
	_muzzle_light.light_energy = lerpf(_muzzle_light.light_energy, 0.0, 1.0 - exp(-30.0 * delta))
	var gun_pitch := _pitch if (aiming or _shot_pose > 0.0) else 0.0
	_gun_socket.rotation.x = lerpf(_gun_socket.rotation.x, gun_pitch, smooth)
	_follow_hand(delta)
	Game.underwater = camera.global_position.y < Game.WATER_LEVEL - 0.05


# --- Water -------------------------------------------------------------------

## How deep the player's feet are below the water surface (negative when dry).
func water_depth() -> float:
	return Game.WATER_LEVEL - global_position.y


## Swimming starts once the water reaches the chest and ends when the feet find
## ground shallow enough to wade. Also plays splashes when entering or leaving.
func _update_water_state() -> void:
	var depth := water_depth()
	var feet_wet := depth > 0.15
	if feet_wet != _feet_wet:
		var speed := velocity.length()
		if feet_wet and speed > 2.0:
			Audio.play("splash_in", global_position, clampf(speed - 8.0, -6.0, 5.0))
			FX.burst(Vector3(global_position.x, Game.WATER_LEVEL, global_position.z), Color(0.8, 0.95, 1.0), 18, 4.0, 0.07)
		if feet_wet and Burns.wash_off(_model):
			Game.notify("The water rinses off the soot.", Color(0.6, 0.85, 1.0))
		elif not feet_wet:
			Audio.play("splash_out", global_position)
		_feet_wet = feet_wet
	if not swimming and depth > SWIM_DEPTH:
		swimming = true
		_swim_facing = _legs.rotation.y
		_legs.rotation.y = 0.0
		_torso.rotation.y = 0.0
		velocity.y *= 0.3
	elif swimming and depth < SWIM_DEPTH - 0.25:
		swimming = false
		_legs.rotation.y = _swim_facing
		_torso.rotation.y = _swim_facing
		_model.transform = Transform3D.IDENTITY


## Swim toward where the camera looks; Space rises, C/Ctrl dives. Idle swimmers
## bob at the surface with their head out of the water.
func _swim(delta: float, input: Vector2) -> Vector3:
	var wish := camera.global_basis * Vector3(input.x, 0.0, input.y)
	var rise := 0.0
	if Input.is_action_pressed("jump"):
		rise += 1.0
	if Input.is_action_pressed("swim_down"):
		rise -= 1.0
	wish.y += rise
	wish = wish.limit_length(1.0)
	var speed := SWIM_SPRINT_SPEED if Input.is_action_pressed("sprint") else SWIM_SPEED
	if rise < 0.0 and Game.skills.has("Diving"):
		speed *= 1.3  # remembered how to dive: down quick and smooth
	var target := wish * speed
	var float_y := Game.WATER_LEVEL - FLOAT_DEPTH
	var below := float_y - global_position.y
	if rise == 0.0 and wish.y > -0.35 and below < 1.2:
		target.y = below * 2.5 + sin(Time.get_ticks_msec() * 0.003) * 0.15
	elif rise == 0.0 and absf(wish.y) < 0.35:
		target.y = 0.4
	if below < 0.0:
		target.y = minf(target.y, below * 4.0)
	if _dash_timer > 0.0:
		_dash_timer -= delta
		target = _dash_dir * DASH_SPEED * 0.6
	velocity = velocity.lerp(target, 1.0 - exp(-3.5 * delta))
	move_and_slide()

	var moving := Vector3(velocity.x, 0.0, velocity.z).length() > 0.8 or absf(velocity.y) > 1.0
	_stroke_timer -= delta
	if moving and _stroke_timer <= 0.0:
		_stroke_timer = 0.95 if speed == SWIM_SPEED else 0.7
		if Game.underwater:
			Audio.play("bubbles")
		else:
			Audio.play("swim_stroke", global_position)
	_bubble_timer -= delta
	if Game.underwater and _bubble_timer <= 0.0:
		_bubble_timer = randf_range(1.5, 3.5)
		FX.burst(global_position + Vector3.UP * 1.6, Color(0.85, 0.95, 1.0), 6, 1.5, 0.05)
		Audio.play("bubbles", null, -3.0)
	return Vector3(wish.x, 0.0, wish.z)


## Head under: sunk clearly below where he floats with his head out.
func head_under() -> bool:
	return swimming and global_position.y < Game.WATER_LEVEL - FLOAT_DEPTH - 0.3


## How long a breath lasts: 30 s, or with Diving remembered at the lake, 45 s
## at first and up to 75 s at the cap.
func air_time() -> float:
	if not Game.skills.has("Diving"):
		return AIR_TIME
	return AIR_TIME * (1.5 + float(Game.skill_level("Diving") - 1) / float(Game.SKILL_MAX - 1))


## How close he is to running out of air: 0 while there's plenty, rising to 1
## as the last of it goes.
func low_air() -> float:
	return clampf((0.55 - air) / 0.55, 0.0, 1.0)


func _update_air(delta: float) -> void:
	var under := head_under()
	if under:
		air = maxf(0.0, air - delta / air_time())
		if air < 0.35 and not _air_warned:
			_air_warned = true
			Game.notify("Running out of air! Swim up (Space)!", Color(0.6, 0.85, 1.0))
		if air <= 0.0:
			_pass_out()
			return
	else:
		if _was_under and air < 0.75:
			# Breaking the surface after a long one: a big gulp of air.
			Audio.play("gasp", null, lerpf(-6.0, 2.0, low_air()))
			FX.burst(global_position + Vector3.UP * 1.6, Color(0.85, 0.95, 1.0), 10, 2.0, 0.05)
		air = minf(1.0, air + delta / 3.0)
		if air > 0.6:
			_air_warned = false
	_was_under = under
	# The heartbeat speeds up and gets louder the lower the air.
	var panic := low_air()
	_heart_timer -= delta
	if panic > 0.0 and _heart_timer <= 0.0:
		_heart_timer = lerpf(1.0, 0.36, panic)
		Audio.play("heartbeat", null, lerpf(-14.0, 4.0, panic), lerpf(0.95, 1.1, panic), 0.0)
		heartbeat.emit(panic)


func _update_wet(delta: float) -> void:
	var depth := water_depth()
	if depth > 0.15:
		# Wet up to wherever the water reaches; a swim soaks him through.
		wet = maxf(wet, clampf(depth / SWIM_DEPTH, 0.0, 1.0))
	else:
		var by_fire := Campfire.warms(get_tree(), global_position)
		wet = maxf(0.0, wet - delta / (12.0 if by_fire else 70.0))
		if wet > 0.4 and randf() < delta * 5.0:
			var drip := global_position + Vector3(randf_range(-0.25, 0.25), randf_range(0.4, 1.3), randf_range(-0.25, 0.25))
			FX.burst(drip, Color(0.7, 0.85, 1.0), 1, 0.3, 0.02)
		if _was_soaked and wet > 0.9 and randf() < 0.35:
			says.emit([["Brrr. Soggy socks.", "Squish. Squish. Squish.", "Note to self: dry clothes are nice."].pick_random()])
		_was_soaked = false
	if depth > SWIM_DEPTH:
		_was_soaked = true  # a real swim, not a paddle
	if absf(wet - _wet_shown) < 0.03 and (wet > 0.0 or _wet_shown == 0.0):
		return
	if _wet_mat == null:
		_wet_mat = StandardMaterial3D.new()
		_wet_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_wet_mat.albedo_color = Color(0.03, 0.04, 0.06, 0.0)
		_wet_mat.roughness = 0.1
		_wet_mat.metallic_specular = 1.0
	var was_dry := _wet_shown == 0.0
	_wet_shown = wet
	_wet_mat.albedo_color.a = 0.4 * wet
	if was_dry != (wet == 0.0):
		for m in _model.find_children("*", "MeshInstance3D", true, false):
			if not m.is_in_group("soot"):
				(m as MeshInstance3D).material_overlay = _wet_mat if wet > 0.0 else null


## Out of air: he goes limp and drifts up to lie on the surface. The world
## takes it from there (the pets come for him); `wake_on_shore` ends it.
func _pass_out() -> void:
	knocked_out = true
	frozen = true
	aiming = false
	cancel_placing()
	velocity = Vector3.ZERO
	tow = Vector3.ZERO
	_model.transform = Transform3D.IDENTITY
	_legs.rotation.y = _swim_facing
	_torso.rotation.y = _swim_facing
	_pitch = -0.6
	if _rig:
		_rig.rotation.y = _swim_facing
		_rig.play("getting_up", 0.0, 0.8)  # held on its first frame: lying flat
	else:
		_model.rotation.x = -PI / 2
	FX.burst(global_position + Vector3.UP * 1.2, Color(0.85, 0.95, 1.0), 16, 1.5, 0.05)
	Audio.play("bubbles", null, 2.0, 0.8)
	passed_out.emit()


## Lying limp: drifts up to the surface and bobs there, or gets towed along.
func _update_knocked_out(delta: float) -> void:
	var float_y := Game.WATER_LEVEL - 0.22
	var y := global_position.y
	if y < float_y - 0.05:
		y = move_toward(y, float_y, 0.9 * delta)
	else:
		y = float_y + sin(Time.get_ticks_msec() * 0.002) * 0.04
	if Game.ground_at(global_position.x, global_position.z) > Game.WATER_LEVEL - 0.6:
		tow = Vector3.ZERO  # into the shallows: they can stop pulling
	global_position = Vector3(global_position.x, y, global_position.z) + tow * delta
	velocity = Vector3.ZERO
	if tow.length() > 0.1:
		var facing := atan2(tow.x, tow.z)  # turned to lie along the way he is pulled
		_legs.rotation.y = lerp_angle(_legs.rotation.y, facing, 1.0 - exp(-2.0 * delta))
		if _rig:
			_rig.rotation.y = _legs.rotation.y


## Comes to on dry ground at `spot`, lying there, then gets up (the screen is
## black when this is called).
func wake_on_shore(spot: Vector3, facing: float) -> void:
	knocked_out = false
	wet = 1.0
	_was_soaked = false
	tow = Vector3.ZERO
	air = 1.0
	_was_under = false
	swimming = false
	global_position = spot
	velocity = Vector3.ZERO
	_model.transform = Transform3D.IDENTITY
	_feet_wet = false
	_legs.rotation.y = facing
	_torso.rotation.y = facing
	_yaw = facing + PI
	_pitch = -0.28
	if _rig:
		_rig.rotation.y = facing
		_rig.current = ""
		_rig.play("getting_up", 0.0, 0.0)


func _physics_process(delta: float) -> void:
	if not alive:
		_respawn_timer -= delta
		if _respawn_timer <= 0.0:
			_respawn()
		return
	_tick_timers(delta)
	_update_cooking(delta)
	if knocked_out:
		_update_knocked_out(delta)
		return
	if raft:
		_ride(delta)
		return
	if frozen:
		if seated:
			_update_seated()
		velocity.x = 0.0
		velocity.z = 0.0
		velocity.y -= GRAVITY * delta
		move_and_slide()
		return
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	aiming = captured and weapon != null and Input.is_action_pressed("aim")
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var wish := Basis(Vector3.UP, _yaw) * Vector3(input.x, 0.0, input.y)
	_sprinting = Input.is_action_pressed("sprint") and input.y < 0.0 and not aiming
	var speed := AIM_SPEED if aiming else (SPRINT_SPEED if _sprinting else WALK_SPEED)
	if Game.story_start and not aiming:
		speed = STORY_RUN_SPEED if _sprinting else STORY_WALK_SPEED
	if _sprinting and Game.skills.has("Running"):
		# Remembered on the hill: up to a third faster with practice.
		speed *= 1.0 + 0.33 * (Game.skill_level("Running") - 1) / (Game.SKILL_MAX - 1.0) + 0.06
		if is_on_floor() and velocity.length() > 2.0:
			Game.practice("Running", delta * 0.12)
	_update_water_state()
	_update_air(delta)
	_update_wet(delta)
	if knocked_out:
		return

	if swimming:
		wish = _swim(delta, input)
	else:
		if _dash_timer > 0.0:
			_dash_timer -= delta
			velocity.x = _dash_dir.x * DASH_SPEED
			velocity.z = _dash_dir.z * DASH_SPEED
		elif _stagger > 0.0:
			_stagger -= delta
		else:
			var accel := 1.0 - exp(-(14.0 if is_on_floor() else 4.0) * delta)
			var wade := 1.0 - clampf(water_depth() / SWIM_DEPTH, 0.0, 1.0) * 0.45
			velocity.x = lerpf(velocity.x, wish.x * speed * wade, accel)
			velocity.z = lerpf(velocity.z, wish.z * speed * wade, accel)

		if is_on_floor():
			if Input.is_action_just_pressed("jump"):
				velocity.y = JUMP_VELOCITY
				Audio.play("jump")
		else:
			velocity.y -= GRAVITY * delta
			_fall_speed = minf(_fall_speed, velocity.y)
		var was_grounded := is_on_floor()
		move_and_slide()
		if was_grounded and is_on_wall():
			_step_up(wish, delta)
	_clamp_to_world()
	if is_on_floor() and not _was_on_floor:
		if _fall_speed < -6.0:
			Audio.play("land", null, clampf(-_fall_speed - 6.0, 0.0, 8.0))
			_play_footstep(4.0)
		_fall_speed = 0.0
	_was_on_floor = is_on_floor()

	if Input.is_action_just_pressed("ability_dash") and not Game.story_start:
		_dash(wish)
	if Input.is_action_just_pressed("ability_nova"):
		_nova()
	if Input.is_action_just_pressed("reload"):
		_start_reload()
	if Input.is_action_just_pressed("interact") and cooking == "":
		_interact()
	if _placer:
		_update_placing(captured)
	elif weapon and _uses_sling():
		_update_pull(delta, captured)
	elif weapon:
		var wants_fire := Input.is_action_pressed("fire") if weapon.automatic else Input.is_action_just_pressed("fire")
		if wants_fire and captured:
			_try_fire()
	elif Input.is_action_just_pressed("fire") and captured and not swimming:
		_punch()

	_update_model(delta, wish)
	_update_loot_focus()
	_update_needs(delta)
	if global_position.y < -30.0:
		take_damage(99999.0)


func _tick_timers(delta: float) -> void:
	_fire_timer = maxf(0.0, _fire_timer - delta)
	nova_cooldown = maxf(0.0, nova_cooldown - delta)
	dash_cooldown = maxf(0.0, dash_cooldown - delta)
	_momentum_timer = maxf(0.0, _momentum_timer - delta)
	_shot_pose = maxf(0.0, _shot_pose - delta)
	_punch_cooldown = maxf(0.0, _punch_cooldown - delta)
	_action_time = maxf(0.0, _action_time - delta)
	_cant_build_cooldown = maxf(0.0, _cant_build_cooldown - delta)
	if _punch_time > 0.0:
		_punch_time = maxf(0.0, _punch_time - delta)
		var t := 1.0 - _punch_time / PUNCH_TIME
		if t > 0.3 and not _punch_landed:
			_punch_landed = true
			_punch_land()
		if _punch_arm and not _punch_animated:
			# Snap out fast, hold a beat, ease back.
			_punch_arm.amount = smoothstep(0.0, 0.28, t) * (1.0 - smoothstep(0.45, 1.0, t))
			_punch_arm.target = _chest() + _aim_flat() * PUNCH_REACH
	_hurt_sound_cooldown = maxf(0.0, _hurt_sound_cooldown - delta)
	if _reload_timer > 0.0:
		_reload_timer -= delta
		if _reload_timer <= 0.0 and weapon:
			_reload_timer = 0.0
			ammo = weapon.mag_size
			Audio.play("reload_in")
	_since_damage += delta
	if _since_damage > 5.0 and health < max_health and Game.lowest_need() > 10.0:
		heal(max_health * 0.08 * delta)


func _clamp_to_world() -> void:
	var flat := Vector2(global_position.x, global_position.z)
	if flat.length() > Game.WORLD_RADIUS:
		flat = flat.limit_length(Game.WORLD_RADIUS)
		global_position.x = flat.x
		global_position.z = flat.y


# --- Combat ------------------------------------------------------------------

func _try_fire() -> void:
	if _fire_timer > 0.0 or is_reloading():
		return
	if ammo <= 0:
		Audio.play("dry_fire")
		_start_reload()
		return
	ammo -= 1
	_play_shot_sound()
	var rate := weapon.fire_rate * (1.3 if momentum_active() else 1.0)
	_fire_timer = 1.0 / rate
	_shot_pose = 0.6
	if _fire_timer >= 0.3:  # a kick of recoil for slower tools; quick ones just hold the aim
		_act(_shoot_state(), minf(_fire_timer, 0.45))
	var muzzle := _gun_model.to_global(_gun_model.get_meta("muzzle"))
	for i in weapon.pellets:
		_fire_ray(muzzle)
	_recoil += minf(0.01 + 0.02 / weapon.fire_rate, 0.05) * (0.6 if aiming else 1.0)
	_muzzle_light.light_energy = 5.0
	if Game.skills.has("Aim"):
		Game.practice("Aim", 0.25 / weapon.fire_rate)  # by time spent, so quick tools don't level faster
	if ammo == 0:
		_start_reload()


## Aim (remembered at the heartstone) narrows the spread: up to 60% at the cap.
func aim_steadiness() -> float:
	if not Game.skills.has("Aim"):
		return 1.0
	return 1.0 - 0.6 * float(Game.skill_level("Aim") - 1) / float(Game.SKILL_MAX - 1)


const SHOT_SOUNDS := {
	"Rifle": "shot_rifle", "Hand Cannon": "shot_cannon", "Scattergun": "shot_scatter",
	"Rune SMG": "shot_smg", "Sky Lance": "shot_lance",
}
const ELEMENT_SOUNDS := ["", "elem_fire", "elem_shock", "elem_frost"]


func _play_shot_sound() -> void:
	Audio.play(SHOT_SOUNDS.get(weapon.archetype, "shot_rifle"), null, 0.0, 1.0, 0.05)
	if weapon.element != WeaponData.Element.KINETIC:
		Audio.play(ELEMENT_SOUNDS[weapon.element], null, 0.0, 1.0, 0.1)


# --- The sling's draw ------------------------------------------------------------
# Hold fire to pull the band back (it takes PULL_TIME). Let go too early and
# the stone flies weak and wobbly; let go just after it's fully drawn (the
# sweet spot, a little longer with Aim) for a perfect shot; hold on past that
# and his arm starts to shake, until he gets tired and lets go by himself.

signal sling_released(quality: String)

const PULL_TIME := 0.7
const SWEET_TIME := 0.4
const TIRE_TIME := 2.0

## How far the band is drawn (0..1), and how long it's been held at full.
var pull := 0.0
var pull_hold := 0.0
var pulling := false
var _shot_power := 1.0
var _shot_wobble := 1.0


## How long the sweet spot lasts after a full draw: Aim stretches it a little.
func sweet_window() -> float:
	return SWEET_TIME + 0.006 * (Game.skill_level("Aim") - 1)


## 0 in the sweet spot, rising to 1 as his arm gives out.
func tremble() -> float:
	return clampf((pull_hold - sweet_window()) / (TIRE_TIME - sweet_window()), 0.0, 1.0)


func _update_pull(delta: float, captured: bool) -> void:
	if not pulling:
		if Input.is_action_just_pressed("fire") and captured and not swimming:
			if ammo <= 0 or is_reloading():
				_try_fire()  # the dry click, and a reload
			elif _fire_timer <= 0.0:
				pulling = true
				pull = 0.0
				pull_hold = 0.0
				Audio.play("reload_out", null, -10.0, 0.7)
		return
	if not Input.is_action_pressed("fire") or not captured or swimming:
		_release_pull(false)
		return
	pull = minf(1.0, pull + delta / (PULL_TIME * (0.85 if aiming else 1.0)))
	if pull >= 1.0:
		pull_hold += delta
		if pull_hold >= TIRE_TIME:
			_release_pull(true)


func _release_pull(tired: bool) -> void:
	pulling = false
	if pull < 0.15 and not tired:
		pull = 0.0
		return  # barely pulled: no shot
	var quality := "shaky"
	if tired:
		quality = "tired"
		_shot_power = 0.5
		_shot_wobble = 9.0
	elif pull < 1.0:
		quality = "weak"
		_shot_power = pull * pull
		_shot_wobble = 1.0 + (1.0 - pull) * 6.0
	elif pull_hold <= sweet_window():
		quality = "perfect"
		_shot_power = 1.2
		_shot_wobble = 0.0
	else:
		_shot_power = 1.0
		_shot_wobble = 1.5 + tremble() * 6.0
	_try_fire()
	if quality == "perfect":
		Audio.play("ui_notify", null, -6.0, 1.6)
		Game.practice("Aim", 0.5)
	sling_released.emit(quality)
	_shot_power = 1.0
	_shot_wobble = 1.0
	pull = 0.0
	pull_hold = 0.0


func _fire_ray(muzzle: Vector3) -> void:
	var cam_basis := camera.global_basis
	var forward := -cam_basis.z
	var spread := weapon.spread * (0.35 if aiming else 1.0) * aim_steadiness() * _shot_wobble + maxf(_shot_wobble - 1.0, 0.0) * 0.012
	var dir := (forward
		+ cam_basis.x * Game.rng.randf_range(-spread, spread)
		+ cam_basis.y * Game.rng.randf_range(-spread, spread)).normalized()
	# Start at the shoulder (spring arm origin) so walls behind the player never block shots.
	var origin := camera.global_position + forward * _spring.get_hit_length()
	# A weak sling shot doesn't carry far.
	var reach := lerpf(8.0, 300.0, clampf(_shot_power, 0.0, 1.0) ** 2)
	var target := origin + dir * reach
	var query := PhysicsRayQueryParameters3D.create(origin, target, 1 | 4, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var end := target
	if not hit.is_empty():
		end = hit["position"]
	# Birds are too small for colliders: a stone passing close enough hits one.
	var bird := _bird_on_line(origin, end)
	if bird:
		end = bird.global_position
		if _shot_power >= 0.35:
			bird.shot_down(global_position)
			Game.practice("Aim", 1.0)
			hit_confirmed.emit(false, true)
		else:
			bird.take_off(origin)  # too weak: it just startles
		FX.tracer(muzzle, end, WeaponData.ELEMENT_COLORS[weapon.element])
		return
	if not hit.is_empty():
		end = hit["position"]
		var collider = hit["collider"]
		if collider is Enemy:
			_hit_enemy(collider, end)
		elif collider.has_method("on_sling_hit"):
			collider.on_sling_hit(_shot_power)  # e.g. the crows' nest: needs a strong shot
		elif collider.has_method("on_shot"):
			collider.on_shot()
		else:
			FX.burst(end, Color(1.0, 0.85, 0.6), 5, 3.0, 0.05)
	FX.tracer(muzzle, end, WeaponData.ELEMENT_COLORS[weapon.element])


## Walking into a low ledge (a step, the Sanctum's rim, a flat rock) steps up
## onto it instead of getting stuck, if it's no taller than STEP_HEIGHT and
## there's flat room on top.
const STEP_HEIGHT := 0.55


func _step_up(wish: Vector3, delta: float) -> void:
	var flat := Vector3(wish.x, 0, wish.z)
	if flat.length() < 0.1:
		return
	var ahead := flat.normalized() * maxf(Vector2(velocity.x, velocity.z).length() * delta, 0.08) + flat.normalized() * 0.12
	var up := Vector3.UP * STEP_HEIGHT
	var start := global_transform
	if test_move(start, up):
		return  # no headroom
	var raised := start.translated(up)
	if test_move(raised, ahead):
		return  # still a wall up there: too tall to step
	var over := raised.translated(ahead)
	var hit := KinematicCollision3D.new()
	if not test_move(over, -up * 1.05, hit) or hit.get_normal().y < 0.7:
		return  # nothing flat to stand on
	global_position = over.origin + hit.get_travel()
	velocity.y = 0.0
	apply_floor_snap()


## The nearest bird the shot passes within reach of, between `from` and `to`.
func _bird_on_line(from: Vector3, to: Vector3) -> Bird:
	var best: Bird = null
	var best_t := INF
	var seg := to - from
	var length := seg.length()
	if length < 0.01:
		return null
	var dir := seg / length
	for node in get_tree().get_nodes_in_group("birds"):
		var b := node as Bird
		var c := b.global_position + Vector3.UP * 0.08
		var t := (c - from).dot(dir)
		if t < 0.0 or t > length or t > best_t:
			continue
		var size: float = Bird.KINDS[b.kind][4]
		if (from + dir * t).distance_to(c) < 0.16 + 0.06 * size:
			best = b
			best_t = t
	return best


func _hit_enemy(enemy: Enemy, pos: Vector3) -> void:
	var dmg := weapon.damage * damage_multiplier() * _shot_power
	var crit := Game.rng.randf() < weapon.crit_chance
	if crit:
		dmg *= 2.0
	if weapon.has_perk("executioner") and enemy.health < enemy.max_health * 0.3:
		dmg *= 1.6
	var killed := enemy.take_damage(dmg, crit, weapon.element)
	hit_confirmed.emit(crit, killed)
	Audio.play("hit_crit" if crit else "hit_marker")
	if weapon.has_perk("vampiric"):
		heal(dmg * 0.03)
	if weapon.has_perk("explosive"):
		_explode(pos, 2.5, dmg * 0.4, enemy)
	if weapon.element == WeaponData.Element.SHOCK:
		_chain_shock(enemy, dmg * 0.5)


func _explode(pos: Vector3, radius: float, dmg: float, exclude: Enemy) -> void:
	FX.ring(pos, radius, Color(1.0, 0.6, 0.2), 0.25)
	FX.flash(pos, Color(1.0, 0.6, 0.2), 3.0, 6.0, 0.15)
	for node in get_tree().get_nodes_in_group("enemies"):
		var e := node as Enemy
		if e == null or e == exclude or e.dead:
			continue
		if e.center().distance_to(pos) <= radius + 0.5:
			e.take_damage(dmg, false, weapon.element)


func _chain_shock(source: Enemy, dmg: float) -> void:
	var best: Enemy = null
	var best_dist := 9.0
	for node in get_tree().get_nodes_in_group("enemies"):
		var e := node as Enemy
		if e == null or e == source or e.dead:
			continue
		var d := e.center().distance_to(source.center())
		if d < best_dist:
			best_dist = d
			best = e
	if best:
		FX.tracer(source.center(), best.center(), WeaponData.ELEMENT_COLORS[WeaponData.Element.SHOCK], 0.07)
		best.take_damage(dmg, false, WeaponData.Element.KINETIC)


func _start_reload() -> void:
	if weapon == null or is_reloading() or ammo >= weapon.mag_size:
		return
	_reload_timer = weapon.reload_time
	Audio.play("reload_out")


func _nova() -> void:
	if weapon == null:
		Game.notify("The rune marble hums, but nothing answers... yet.", Color(0.6, 0.9, 1.0))
		return
	if nova_cooldown > 0.0:
		return
	nova_cooldown = NOVA_COOLDOWN
	_act("cast", 0.7)
	var color: Color = NOVA_COLOR if weapon.element == WeaponData.Element.KINETIC else WeaponData.ELEMENT_COLORS[weapon.element]
	var center := global_position + Vector3.UP * 0.6
	FX.bloom(center, NOVA_RADIUS, color)
	FX.flash(center, color.lerp(Color(1.0, 0.9, 0.75), 0.4), 4.0, 12.0, 0.9)
	Audio.play("nova", null, 0.0, 1.0, 0.03)
	if weapon.element != WeaponData.Element.KINETIC:
		Audio.play(ELEMENT_SOUNDS[weapon.element], null, 6.0, 0.8)
	var dmg := 45.0 * damage_multiplier() * pow(1.13, level - 1)
	for node in get_tree().get_nodes_in_group("enemies"):
		var e := node as Enemy
		if e == null or e.dead:
			continue
		var offset := e.global_position - global_position
		if offset.length() <= NOVA_RADIUS:
			var killed := e.take_damage(dmg, false, weapon.element)
			hit_confirmed.emit(false, killed)
			offset.y = 0.0
			e.knockback(offset.normalized() * 14.0)


## Plays one of the rig's one-off animations over whatever the body is doing.
## Light ones (`soft`) only start while standing more or less still, and stop
## if you move off; hard ones (dodges, falling over) play through.
func _act(state: String, duration: float, soft := true) -> bool:
	if _rig == null or swimming or raft or not is_on_floor():
		return false
	if soft and Vector2(velocity.x, velocity.z).length() > 1.2:
		return false
	if not _rig.act(state, duration):
		return false
	_action_time = duration
	_action_soft = soft
	return true


## Which way a dodge roll goes, from the dash direction and the way the body faces.
func _dodge_state(dir: Vector3) -> String:
	var local := Basis(Vector3.UP, -_legs.rotation.y) * dir
	if absf(local.x) > absf(local.z):
		return "dodge_right" if local.x > 0.0 else "dodge_left"
	return "dodge_forward" if local.z < 0.0 else "dodge_backward"


func _dash(wish: Vector3) -> void:
	if dash_cooldown > 0.0:
		return
	dash_cooldown = DASH_COOLDOWN
	_dash_timer = DASH_TIME
	_dash_dir = wish.normalized() if wish.length() > 0.1 else Basis(Vector3.UP, _yaw) * Vector3.FORWARD
	FX.burst(global_position + Vector3.UP * 0.9, NOVA_COLOR, 14, 4.0)
	Audio.play("dash")
	_act(_dodge_state(_dash_dir), 0.5, false)


func take_damage(amount: float) -> void:
	if not alive or _dash_timer > 0.0:
		return
	health -= amount
	_since_damage = 0.0
	damaged.emit(amount)
	if _hurt_sound_cooldown <= 0.0:
		_hurt_sound_cooldown = 0.25
		Audio.play("player_hurt")
		if health > 0.0 and _action_time <= 0.0:
			_act("hit" if randf() < 0.5 else "hit_b", 0.4)
	if health <= 0.0:
		_die()


## Stepped into a fire: ouch! A little damage, a hop back out, and a sooty
## smudge on the leg that was nearest the flames.
func burn(from: Vector3) -> void:
	var away := Burns._away(from, global_position)
	take_damage(5.0)
	if not alive:
		return
	if not frozen:
		velocity = away * 5.5 + Vector3.UP * 4.2
		_stagger = 0.4
	Audio.play("elem_fire", global_position, -3.0)
	FX.burst(global_position + Vector3.UP * 0.3, Color(1.0, 0.55, 0.15), 10, 2.5, 0.04)
	says.emit([Burns.HERO_LINES.pick_random()])
	_soot_mark(from)


func _soot_mark(from: Vector3) -> void:
	if _rig == null or _rig.skeleton == null:
		var shin := global_position + Vector3.UP * 0.35
		var toward := Vector3(from.x - shin.x, 0.0, from.z - shin.z).normalized()
		Burns.mark(_model, shin + toward * 0.1, toward)
		return
	var sk := _rig.skeleton
	# Whichever shin is nearer the fire takes the smudge.
	var best := -1
	var best_dist := INF
	for b in sk.get_bone_count():
		var n := sk.get_bone_name(b)
		if n.ends_with("LeftLeg") or n.ends_with("RightLeg"):
			var d := (sk.global_transform * sk.get_bone_global_pose(b).origin).distance_to(from)
			if d < best_dist:
				best = b
				best_dist = d
	if best < 0:
		return
	var knee := sk.global_transform * sk.get_bone_global_pose(best).origin
	var children := sk.get_bone_children(best)
	var ankle := sk.global_transform * sk.get_bone_global_pose(children[0]).origin if children.size() > 0 else knee - Vector3.UP * 0.45
	var spot := knee.lerp(ankle, randf_range(0.35, 0.6))
	var out := Vector3(from.x - spot.x, 0.0, from.z - spot.z).normalized()
	var bone_name := sk.get_bone_name(best)
	var holder: BoneAttachment3D = _soot_bones.get(bone_name)
	if not is_instance_valid(holder):
		holder = BoneAttachment3D.new()
		holder.bone_name = bone_name
		sk.add_child(holder)
		_soot_bones[bone_name] = holder
	holder.global_transform = sk.global_transform * sk.get_bone_global_pose(best)
	Burns.mark(holder, spot + out * 0.055, out, 0.055)


func heal(amount: float) -> void:
	health = minf(max_health, health + amount)


func on_enemy_killed(enemy: Enemy) -> void:
	gain_xp(enemy.xp_reward())
	if weapon == null:
		return
	if weapon.has_perk("overcharge"):
		nova_cooldown = maxf(0.0, nova_cooldown - 2.0)
	if weapon.has_perk("momentum"):
		_momentum_timer = 4.0


func gain_xp(amount: int) -> void:
	xp += amount
	while xp >= xp_to_next():
		xp -= xp_to_next()
		level += 1
		max_health = 100.0 + 15.0 * (level - 1)
		health = max_health
		FX.ring(global_position + Vector3.UP * 0.2, 4.0, Color(1.0, 0.8, 0.3), 0.6)
		FX.burst(global_position + Vector3.UP, Color(1.0, 0.8, 0.3), 30, 6.0)
		Audio.play("level_up", null, 0.0, 1.0, 0.0)
		leveled_up.emit(level)


func _die() -> void:
	alive = false
	health = 0.0
	velocity = Vector3.ZERO
	_respawn_timer = 4.0
	if _rig and not swimming and _rig.act("death", 1.1):
		# Topple over first, then fade out in the burst of light.
		get_tree().create_timer(1.4).timeout.connect(func() -> void:
			if not alive:
				_model.visible = false
				FX.burst(global_position + Vector3.UP * 0.4, NOVA_COLOR, 40, 7.0))
	else:
		_model.visible = false
		FX.burst(global_position + Vector3.UP, NOVA_COLOR, 40, 7.0)
	Audio.play("player_death", null, 0.0, 1.0, 0.0)
	died.emit()


func _respawn() -> void:
	global_position = spawn_point
	velocity = Vector3.ZERO
	health = max_health
	ammo = weapon.mag_size if weapon else 0
	_reload_timer = 0.0
	alive = true
	swimming = false
	air = 1.0
	knocked_out = false
	tow = Vector3.ZERO
	_model.transform = Transform3D.IDENTITY
	_action_time = 0.0
	if _rig:
		_rig.current = ""
		_rig.play("idle", 1.0, 0.0)
	_model.visible = true
	Audio.play("respawn", null, 0.0, 1.0, 0.0)
	respawned.emit()


# --- Loot --------------------------------------------------------------------

func equip(w: WeaponData) -> void:
	weapon = w
	ammo = w.mag_size
	_reload_timer = 0.0
	if _gun_model:
		_gun_model.queue_free()
	_gun_model = WeaponModel.build(w)
	_gun_socket.add_child(_gun_model)
	_muzzle_light.position = _gun_model.get_meta("muzzle")
	_build_band()


# --- Tools in hand -------------------------------------------------------------
# With a rig that has hand slots, the tool rides in a hand: the sling's fork in
# the left, the rest in the right. It still points where you aim. The sling's
# band is drawn live: tied to the fork tips, pulled back by the right hand
# while aiming, and snapping forward when the stone flies.

var _grip_l: BoneAttachment3D
var _grip_r: BoneAttachment3D
var _band: Array[MeshInstance3D] = []  # two cords and the pouch


func _uses_sling() -> bool:
	return _gun_model != null and _gun_model.has_meta("band_tips")


## The hand that holds the tool: the sling's fork goes in the left.
func _grip() -> BoneAttachment3D:
	return _grip_l if _uses_sling() else _grip_r


## Aiming and shooting poses: both hands for the sling, one for the rest.
func _aim_state() -> String:
	return "2h_ranged_aiming" if _uses_sling() and _rig and _rig.has_state("2h_ranged_aiming") else "aim_idle"


func _shoot_state() -> String:
	return "2h_ranged_shoot" if _uses_sling() and _rig and _rig.has_state("2h_ranged_shoot") else "shoot"


func _build_band() -> void:
	for b in _band:
		b.queue_free()
	_band.clear()
	if not _uses_sling() or _grip_r == null:
		return
	for n in _gun_model.find_children("Band", "", true, false):
		(n as Node3D).visible = false
	var mats: Array = _gun_model.get_meta("band_mats")
	for k in 3:
		var mi := MeshInstance3D.new()
		mi.mesh = MeshKit.cyl(0.006, 0.006, 1.0, 4) if k < 2 else MeshKit.sphere(0.035)
		mi.material_override = mats[0] if k < 2 else mats[1]
		mi.top_level = true
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_gun_model.add_child(mi)
		_band.append(mi)


## Puts the tool in its hand (keeping its aim) and draws the sling's band.
func _follow_hand(delta: float) -> void:
	var grip := _grip()
	# The band follows the right hand while he pulls it back (it shakes once
	# his arm tires), then snaps forward to rest between the fork tips.
	var sling := _uses_sling() and grip != null and swimming == false and _action_time <= 0.0
	var holding := sling and (aiming or pulling or _shot_pose > 0.0)
	if _sling_draw:
		_sling_draw.aim_dir = -camera.global_basis.z
		_sling_draw.hold = move_toward(_sling_draw.hold, 1.0 if holding else 0.0, delta * 5.0)
		if pulling and sling:
			_sling_draw.draw = pull
		else:
			_sling_draw.draw = move_toward(_sling_draw.draw, 0.0, delta * 14.0)  # the release is a snap
		_sling_draw.shake = tremble() if pulling else 0.0
	if grip == null or _gun_model == null:
		return
	_gun_socket.global_position = grip.global_position
	if _band.is_empty():
		return
	var tips: Array = _gun_model.get_meta("band_tips")
	var a: Vector3 = _gun_model.to_global(tips[0])
	var b: Vector3 = _gun_model.to_global(tips[1])
	var rest := _gun_model.to_global(Vector3(0, 0.2, 0.05))
	var amount := _sling_draw.draw if _sling_draw else 0.0
	var pouch := rest.lerp(_grip_r.global_position, amount)
	_cord(_band[0], a, pouch)
	_cord(_band[1], b, pouch)
	_band[2].global_position = pouch


## Stretches a unit-tall cylinder between two points.
func _cord(mi: MeshInstance3D, from: Vector3, to: Vector3) -> void:
	var d := to - from
	var length := maxf(d.length(), 0.001)
	var y := d / length
	var x := y.cross(Vector3.UP)
	if x.length() < 0.01:
		x = y.cross(Vector3.RIGHT)
	x = x.normalized()
	var z := x.cross(y)
	mi.global_transform = Transform3D(Basis(x, y * length, z), (from + to) * 0.5)


# --- Survival ----------------------------------------------------------------

## Forgiving rates: thirst empties in ~30 min, hunger ~45 min, warmth ~6 min of
## night away from a fire. An empty need stops health from recovering and wears
## it down slowly, but never below a quarter.
const THIRST_RATE := 100.0 / 1800.0
const HUNGER_RATE := 100.0 / 2700.0
const COLD_RATE := 100.0 / 360.0
const FIRE_WARM_RATE := 10.0
const NEED_FLOOR := 0.25

var focused_gatherable: Gatherable
## A pet close enough to talk to (when nothing to pick up is closer).
var focused_companion: Companion
signal talk_requested(companion: Companion)
## Something built that E works on (a campfire, a rain catcher), when no pet
## or pickup is closer. It's in the "usables" group with use_radius(),
## use_prompt() and use(player).
var focused_usable: Node3D
signal fire_requested(fire: Campfire)
var _warned := {}
var _swim_practice := 0.0
var _dive_practice := 0.0


func _update_needs(delta: float) -> void:
	if not Game.story_start:
		return
	Game.thirst = maxf(0.0, Game.thirst - THIRST_RATE * delta)
	Game.hunger = maxf(0.0, Game.hunger - HUNGER_RATE * delta)
	if Campfire.warms(get_tree(), global_position) or TorchPost.warms(get_tree(), global_position):
		Game.warmth = minf(100.0, Game.warmth + FIRE_WARM_RATE * delta)
	else:
		var sheltered := 0.4 if Shelter.covers(get_tree(), global_position) else 1.0  # out of the wind
		var daytime := 1.0 if Game.is_night else 0.3  # the sun takes the edge off
		Game.warmth = maxf(0.0, Game.warmth - COLD_RATE * delta * daytime * (2.0 if swimming else sheltered * (1.0 + wet * 0.6)))  # wet clothes chill
	if Game.lowest_need() <= 0.0 and health > max_health * NEED_FLOOR:
		health -= 0.4 * delta
	for need in [["warmth", "You're getting cold. A fire would help."], ["hunger", "Your stomach growls."], ["thirst", "Your mouth is dry. Find water."]]:
		var value: float = Game.get(need[0])
		if value < 25.0 and not _warned.get(need[0], false):
			_warned[need[0]] = true
			Game.notify(need[1], Color(1.0, 0.8, 0.5))
		elif value > 50.0:
			_warned[need[0]] = false
	if swimming:
		_swim_practice += delta
		if _swim_practice > 10.0:
			_swim_practice = 0.0
			Game.practice("Swimming", 1.0)
		if head_under() and Game.skills.has("Diving"):
			_dive_practice += delta
			if _dive_practice > 6.0:
				_dive_practice = 0.0
				Game.practice("Diving", 1.0)
	if raft:
		# On the raft E only hops off: nothing else to pick or talk to.
		if is_instance_valid(focused_gatherable):
			focused_gatherable.set_focused(false)
		focused = null
		focused_gatherable = null
		focused_companion = null
		focused_usable = null
		return
	_update_gather_focus()


## What E acts on: the one thing within reach that the cursor (the middle of
## the screen) is pointing at, or failing that, something right at your feet.
## Pets only count when you point at them, so they don't keep popping up
## while they mill about. Nothing gets picked from a list.
var focused: Node = null
## Pointing at it: within this share of the screen's height of the middle.
const AIM_SLACK := 0.11
## Right at your feet: picked even without pointing.
const UNDERFOOT := 1.1


func _update_gather_focus() -> void:
	var pick := [null, INF]  # [node, score]; an array so the lambda below can update it
	var view := get_viewport().get_visible_rect().size
	var middle := view * 0.5
	var slack := view.y * AIM_SLACK
	var consider := func(node: Node, at: Vector3, reach: float, lift: float, must_point: bool):
		var to := at - global_position
		to.y = 0.0
		var d := to.length()
		if d > reach:
			return
		var score := INF
		var tip := at + Vector3.UP * lift
		if camera and not camera.is_position_behind(tip):
			var off := camera.unproject_position(tip).distance_to(middle)
			if off < slack:
				score = off / slack + d * 0.1
		if score == INF and not must_point and d < UNDERFOOT:
			score = 1.5 + d
		if score < pick[1]:
			pick[0] = node
			pick[1] = score
	for node in get_tree().get_nodes_in_group("gatherables"):
		if (node as Gatherable).available:
			consider.call(node, node.global_position, 2.8, 0.15, false)
	for node in get_tree().get_nodes_in_group("companions"):
		var c := node as Companion
		if c.state == Companion.State.FOLLOWING:
			consider.call(c, c.body.global_position, 4.0, c.head_height * 0.5, true)
	for node in get_tree().get_nodes_in_group("usables"):
		consider.call(node, node.global_position, node.use_radius(), 0.4, false)
	var best: Node = pick[0]
	focused = best
	var gather := best as Gatherable
	if gather != focused_gatherable:
		if is_instance_valid(focused_gatherable):
			focused_gatherable.set_focused(false)
		if gather:
			gather.set_focused(true)
	focused_gatherable = gather
	focused_companion = best as Companion
	focused_usable = best if best != null and best.is_in_group("usables") else null


## E: gather what's in front of you, else talk to a pet beside you or use
## what's built there, else swap in a weapon, else drink if you're standing
## in water.
func _interact() -> void:
	if focused_gatherable == null and is_instance_valid(focused_companion):
		talk_requested.emit(focused_companion)
		return
	if focused_gatherable == null and is_instance_valid(focused_usable):
		focused_usable.use(self)
		return
	if is_instance_valid(focused_gatherable):
		var got := focused_gatherable.gather(Game.rng)
		if got != "":
			_act("pick_up", 0.8)
			Game.notify(got, Color(0.9, 0.95, 0.8))
		return
	if is_instance_valid(focused_loot):
		_pick_up_focused()
		return
	if water_depth() > 0.15:
		Game.thirst = 100.0
		Game.canteen_sips = 3
		Game.practice("Survival", 1.0)
		Audio.play("swim_stroke", null, 0.0, 0.8)
		Game.notify("You drink deep and fill your canteen.", Color(0.6, 0.85, 1.0))


func eat(item: String) -> void:
	if Game.FOODS.has(item) and Game.take_items(item, 1):
		Game.hunger = minf(100.0, Game.hunger + Game.FOODS[item])
		if item == "Berries":
			Game.thirst = minf(100.0, Game.thirst + 3.0)  # juicy
		if Game.COOKS.values().has(item):
			Game.warmth = minf(100.0, Game.warmth + Game.COOKED_WARMTH)
		Game.practice("Survival", 0.5)
		Audio.play("gear_rustle", null, 0.0, 1.5)


## At a campfire: cooks every piece of one raw food you're carrying.
## Cooking: one piece at a time on a stick held out over the fire. Halfway it
## needs flipping (E), then it finishes and the next piece goes on, until the
## raw food runs out. Moving away puts the stick down.
const COOK_TIME := 4.0
const FOOD_COLORS := {"Bird meat": Color(0.9, 0.62, 0.55), "Grubs": Color(0.92, 0.85, 0.62), "Mushrooms": Color(0.75, 0.6, 0.45), "Eggs": Color(0.96, 0.94, 0.88),
	"Fish": Color(0.62, 0.68, 0.72), "Crayfish": Color(0.75, 0.3, 0.2), "Clams": Color(0.7, 0.66, 0.58)}
var cooking := ""  # the raw food on the stick right now
var cook_progress := 0.0
var cook_needs_flip := false
var _cook_flipped := false
var _cook_fire: Node3D
var _cook_stick: Node3D
var _cook_food: MeshInstance3D


func cook(raw: String, fire: Node3D) -> void:
	if not Game.has_items(raw) or not Game.COOKS.has(raw) or not Game.known.has("cooking"):
		return
	cooking = raw
	_cook_fire = fire
	cook_progress = 0.0
	cook_needs_flip = false
	_cook_flipped = false
	if _cook_stick == null:
		_cook_stick = Node3D.new()
		_cook_stick.top_level = true
		add_child(_cook_stick)
		var wood := MeshKit.part(_cook_stick, MeshKit.cyl(0.012, 0.016, 1.0, 5), MeshKit.mat(Color(0.45, 0.33, 0.2)), Vector3(0, 0, -0.5), Vector3(PI / 2, 0, 0))
		wood.name = "Wood"
		_cook_food = MeshKit.part(_cook_stick, MeshKit.sphere(0.06, 0.1, 7, 4), MeshKit.mat(Color.WHITE, 0.6), Vector3(0, 0, -0.95))
	(_cook_food.material_override as StandardMaterial3D).albedo_color = FOOD_COLORS.get(raw, Color(0.8, 0.7, 0.5))
	_cook_food.rotation = Vector3.ZERO
	_cook_stick.visible = true
	Audio.play("gear_rustle", null, -6.0)


func stop_cooking(line := "") -> void:
	cooking = ""
	cook_needs_flip = false
	if _cook_stick:
		_cook_stick.visible = false
	if _punch_arm:
		_punch_arm.amount = 0.0
	if line != "":
		says.emit([line])


func _update_cooking(delta: float) -> void:
	if cooking == "":
		return
	var moving := Input.get_vector("move_left", "move_right", "move_forward", "move_back").length() > 0.3
	if not is_instance_valid(_cook_fire) or _cook_fire.global_position.distance_to(global_position) > 3.2 or moving or not alive:
		stop_cooking()
		return
	# Arm out, stick pointing down into the flames.
	var tip := _cook_fire.global_position + Vector3.UP * 0.45
	var hand := _chest() + (tip - _chest()).normalized() * 0.45 + Vector3.DOWN * 0.1
	if _punch_arm:
		_punch_arm.left = false
		_punch_arm.amount = 0.85
		_punch_arm.target = hand + (tip - hand).normalized() * 0.3
	_cook_stick.global_position = hand
	_cook_stick.look_at(tip, Vector3.UP)
	_cook_stick.scale = Vector3(1, 1, clampf(hand.distance_to(tip), 0.6, 1.6))
	_cook_food.scale = Vector3(1, 1, 1.0 / _cook_stick.scale.z)  # stays round on the stretched stick
	if cook_needs_flip:
		if Input.is_action_just_pressed("interact"):
			cook_needs_flip = false
			_cook_flipped = true
			_cook_food.rotation.x += PI
			Audio.play("elem_fire", null, -16.0, 0.8)
		return
	cook_progress += delta / COOK_TIME
	# Browns as it cooks.
	var base: Color = FOOD_COLORS.get(cooking, Color(0.8, 0.7, 0.5))
	(_cook_food.material_override as StandardMaterial3D).albedo_color = base.lerp(Color(0.5, 0.3, 0.14), cook_progress * 0.7)
	if cook_progress >= 0.5 and not _cook_flipped:
		cook_needs_flip = true
		return
	if cook_progress >= 1.0:
		var raw := cooking
		var cooked: String = Game.COOKS[raw]
		Game.take_items(raw, 1)
		Game.add_item(cooked, 1)
		Game.practice("Firecraft", 1.5)
		Audio.play("elem_fire", null, -14.0, 0.7)
		Game.notify("Sizzle... +1 %s" % cooked, Color(1.0, 0.75, 0.45))
		if Game.has_items(raw):
			cook(raw, _cook_fire)
		else:
			stop_cooking()


## Sitting down facing `toward` (by the fire) and getting back up.
func sit_facing(toward: Vector3) -> void:
	frozen = true
	var to := toward - global_position
	_sit_forward = Vector3(to.x, 0.0, to.z).normalized()
	_sitting = true
	var facing := atan2(-to.x, -to.z)
	_legs.rotation.y = facing
	_torso.rotation.y = facing
	_yaw = facing  # camera over his shoulder, into the fire
	_pitch = -0.22
	if _rig:
		_rig.rotation.y = facing
		_rig.play("sit", 1.0, 0.5)


func stand_up() -> void:
	frozen = false
	_sitting = false
	if _rig:
		_rig.play("idle", 1.0, 0.5)


func drink_canteen() -> void:
	if Game.canteen_sips > 0:
		Game.canteen_sips -= 1
		Game.thirst = minf(100.0, Game.thirst + 35.0)
		Audio.play("swim_stroke", null, -4.0, 1.2)


## Starts choosing where to build something you know how to make. Returns
## false if you don't have what it needs.
func begin_placing(id: String) -> bool:
	if not Game.known.has(id) or not _can_afford(id):
		return false
	cancel_placing()
	_placer = Placer.create(id)
	get_parent().add_child(_placer)
	_placer.follow(global_position, _aim_flat())
	return true


func cancel_placing() -> void:
	if _placer:
		_placer.queue_free()
		_placer = null


func is_placing() -> bool:
	return _placer != null


## Left click builds it where the preview is (if it's blue); right click or
## Esc puts the idea away.
func _update_placing(captured: bool) -> void:
	_placer.follow(global_position, _aim_flat())
	_legs.rotation.y = lerp_angle(_legs.rotation.y, _yaw, 0.2)
	if Input.is_action_just_pressed("aim"):
		cancel_placing()
	elif Input.is_action_just_pressed("fire") and captured:
		if not _placer.valid:
			if _cant_build_cooldown <= 0.0:
				_cant_build_cooldown = 3.0
				says.emit(["I don't think I can build that there.", "Should find a different spot."])
			Audio.play("dry_fire", null, -10.0, 1.4)
		elif _can_afford(_placer.id):
			_build(_placer.id, _placer.global_position, _placer.rotation.y)
			cancel_placing()


func _can_afford(id: String) -> bool:
	var needs: Dictionary = Game.KNOW_HOW[id].needs
	for item in needs:
		if not Game.has_items(item, needs[item]):
			return false
	return true


## Makes something you carry (the map) from what's in your pockets.
func make(id: String) -> void:
	var entry: Dictionary = Game.KNOW_HOW[id]
	for item in entry.needs:
		if not Game.has_items(item, entry.needs[item]):
			return
	for item in entry.needs:
		Game.take_items(item, entry.needs[item])
	Game.backpack.append(entry.name)
	Game.practice("Survival", 3.0)
	Audio.play("gear_rustle", null, -4.0, 0.7)
	if id == "map":
		says.emit(["Charcoal on bark... there. Everywhere we've been so far.", "(Press M to look at the map.)"])


func _build(id: String, spot: Vector3, yaw: float) -> void:
	var needs: Dictionary = Game.KNOW_HOW[id].needs
	for item in needs:
		Game.take_items(item, needs[item])
	match id:
		"campfire":
			Campfire.build(get_parent(), spot)
			Game.practice("Firecraft", 6.0)
		"lean_to":
			Shelter.build(get_parent(), spot, yaw)
			Game.practice("Woodcraft", 6.0)
		"torch_post":
			TorchPost.build(get_parent(), spot)
			Game.practice("Firecraft", 3.0)
		"rain_catcher":
			RainCatcher.build(get_parent(), spot).rotation.y = yaw
			Game.practice("Survival", 3.0)
		"hearth":
			Hearth.build_hearth(get_parent(), spot, yaw)
			Game.practice("Firecraft", 8.0)
		"bedroll":
			Bedroll.build(get_parent(), spot, yaw)
			Game.practice("Woodcraft", 4.0)
		"chest":
			StorageChest.build(get_parent(), spot, yaw)
			Game.practice("Woodcraft", 6.0)
		"rain_cover":
			RainCover.build(get_parent(), spot, yaw)
			Game.practice("Woodcraft", 8.0)
		"raft":
			Raft.build(get_parent(), spot, yaw)
			Game.practice("Woodcraft", 8.0)
			Audio.play("splash_in", spot, -4.0, 0.7)
	Audio.play("nova", spot, -8.0, 0.6)
	Game.built.emit(id, spot)


# --- The raft ------------------------------------------------------------------
# Sitting on the raft, cross-legged, paddling toward where you look. The pets
# close by hop on with you. E hops off onto a dock or shore in reach, or else
# into the water.

var raft: Raft
const PET_RIDE_REACH := 12.0


func board(r: Raft) -> void:
	cancel_placing()
	if swimming:
		swimming = false
		_legs.rotation.y = _swim_facing
		_torso.rotation.y = _swim_facing
		_model.transform = Transform3D.IDENTITY
	raft = r
	r.boarded(self)
	velocity = Vector3.ZERO
	_feet_wet = false
	_sitting = true
	if _rig:
		_rig.play("sit", 1.0, 0.4)
	for comp in get_tree().get_nodes_in_group("companions"):
		var pet := comp as Companion
		if pet.state == Companion.State.FOLLOWING and pet.body.global_position.distance_to(r.global_position) < PET_RIDE_REACH:
			pet.ride(r, Raft.FOX_SEAT if pet.who == "fox" else Raft.OTTER_SEAT)


## Off the raft: onto a dock or the shore if there's one in reach (the pets
## hop off after), or else into the water (they stay aboard, dry).
func leave_raft() -> void:
	if raft == null:
		return
	var r := raft
	var land := r.landing()
	raft = null
	r.left()
	_sitting = false
	if _rig:
		_rig.play("idle", 1.0, 0.4)
	if land == Vector3.INF:
		var side := r.global_basis.x * (Raft.WIDTH * 0.5 + 0.7)
		global_position = r.global_position + side + Vector3.DOWN * 1.2
		Audio.play("splash_in", global_position, -2.0)
		FX.burst(Vector3(global_position.x, Game.WATER_LEVEL, global_position.z), Color(0.8, 0.95, 1.0), 18, 4.0, 0.07)
		return
	global_position = land
	velocity = Vector3.ZERO
	Audio.play("land", null, -2.0)
	var k := 0
	for comp in get_tree().get_nodes_in_group("companions"):
		var pet := comp as Companion
		if pet.state == Companion.State.RIDING:
			k += 1
			pet.hop_off(land + r.global_basis.x * (0.9 if k == 1 else -0.9))


func _ride(delta: float) -> void:
	var r := raft
	if not is_instance_valid(r):
		raft = null
		_sitting = false
		return
	var input := Vector2.ZERO
	if not frozen:
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var wish := Basis(Vector3.UP, _yaw) * Vector3(input.x, 0.0, input.y)
	r.paddle(wish, Input.is_action_pressed("sprint") and not frozen, delta)
	global_position = r.seat(Raft.SEAT)
	velocity = Vector3.ZERO
	var facing := r.rotation.y
	_sit_forward = -r.global_basis.z
	_legs.rotation.y = facing
	_torso.rotation.y = facing
	if _rig:
		_rig.rotation.y = facing
	_clamp_to_world()
	if frozen:
		return
	if Input.is_action_just_pressed("interact"):
		leave_raft()
		return
	_update_needs(delta)


func _punch() -> void:
	if _punch_cooldown > 0.0 or frozen:
		return
	_punch_time = PUNCH_TIME
	_punch_cooldown = PUNCH_COOLDOWN
	_punch_landed = false
	# Standing still, the rig throws its own jab, cross and kick in turn;
	# on the move, PunchArm swings an arm over the run.
	_punch_count += 1
	_punch_animated = _act(["punch", "punch_b", "kick"][_punch_count % 3], PUNCH_TIME + 0.2)
	if _punch_arm:
		_punch_arm.left = not _punch_arm.left
		if _punch_animated:
			_punch_arm.amount = 0.0
	Audio.play("dash", null, -14.0, 1.6)


## The moment the fist arrives: hurt an enemy in front, or thump whatever's
## there. Punching a tree now and then knocks a branch loose.
func _punch_land() -> void:
	var forward := _aim_flat()
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as Node3D
		var to := enemy.global_position - global_position
		to.y = 0.0
		if to.length() < PUNCH_REACH + 0.6 and to.normalized().dot(forward) > 0.5:
			enemy.take_damage(PUNCH_DAMAGE)
			Audio.play("hit_marker")
			return
	var from := _chest()
	var query := PhysicsRayQueryParameters3D.create(from, from + forward * (PUNCH_REACH + 0.2), 1)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return
	var body := hit.collider as CollisionObject3D
	var owner_node := body.shape_owner_get_owner(body.shape_find_owner(hit.shape)) if body else null
	var is_tree := owner_node is CollisionShape3D and (owner_node as CollisionShape3D).shape is CylinderShape3D
	Audio.play("impact_stone", hit.position, -6.0, 0.6 if is_tree else 1.0)
	_recoil = 0.04
	if not is_tree:
		return
	Game.practice("Woodcraft", 0.5)
	if Game.rng.randf() < 0.3 + Game.skill_level("Woodcraft") * 0.02:
		var drop: Vector3 = hit.position - forward * 0.5
		drop.y = Game.ground_at(drop.x, drop.z)
		Gatherable.spawn(get_parent(), drop, "sticks", Game.rng)
		Game.notify("A branch falls loose.", Color(0.9, 0.95, 0.8))


func _chest() -> Vector3:
	return global_position + Vector3(0, 1.4, 0)


## Where the camera looks, flattened onto the ground.
func _aim_flat() -> Vector3:
	return Basis(Vector3.UP, _yaw) * Vector3.FORWARD


## Story start: the hero lies under the great tree and gets up while the camera
## looks back at him from the front; control returns once he's on his feet.
func begin_wake(facing: float) -> void:
	frozen = true
	_waking = true
	_legs.rotation.y = facing
	_torso.rotation.y = facing
	_yaw = facing + PI
	_pitch = -0.28
	if _rig:
		_rig.rotation.y = facing
		_rig.current = ""  # restart it even if it was held on a frame
		_rig.play("getting_up", 0.8, 0.0)
		if not _rig.finished.is_connected(_on_rig_finished):
			_rig.finished.connect(_on_rig_finished)
	get_tree().create_timer(12.0).timeout.connect(_end_wake)  # safety net


var _waking := false


func _on_rig_finished(state: String) -> void:
	if state == "getting_up":
		_end_wake()


func _end_wake() -> void:
	if not _waking:
		return
	_waking = false
	frozen = false
	if _rig:
		_rig.play("idle", 1.0, 0.4)
	woke_up.emit()


func register_loot(drop: LootDrop, in_range: bool) -> void:
	if in_range:
		if not _nearby_loot.has(drop):
			_nearby_loot.append(drop)
	else:
		_nearby_loot.erase(drop)


func _update_loot_focus() -> void:
	_nearby_loot = _nearby_loot.filter(func(d): return is_instance_valid(d))
	var best: LootDrop = null
	var best_dist := INF
	for d in _nearby_loot:
		var dist := global_position.distance_to(d.global_position)
		if dist < best_dist:
			best_dist = dist
			best = d
	focused_loot = best


## Swap places with the focused drop: pick it up and leave the current weapon there.
func _pick_up_focused() -> void:
	if not is_instance_valid(focused_loot):
		return
	var drop := focused_loot
	var new_weapon := drop.weapon
	var spot := drop.global_position
	_nearby_loot.erase(drop)
	drop.queue_free()
	focused_loot = null
	if weapon:
		LootDrop.spawn(get_parent(), weapon, spot, false)
	equip(new_weapon)
	Audio.play("equip")
	_act("pick_up", 0.8)
	Game.notify("In hand: %s" % new_weapon.display_name, new_weapon.color)


# --- Visuals -----------------------------------------------------------------

## Upper and lower body turn independently: the legs follow the movement direction
## while the torso and gun follow the aim. If the aim points more than ~100 degrees
## away from where you're running, the legs flip around and backpedal instead.
func _update_model(delta: float, wish: Vector3) -> void:
	if swimming:
		_update_swim_pose(delta, wish)
		return
	var smooth := 1.0 - exp(-14.0 * delta)
	var moving := wish.length() > 0.1
	var move_yaw := atan2(-wish.x, -wish.z) if moving else _legs.rotation.y
	var combat_pose := aiming or pulling or _shot_pose > 0.0
	var facing_aim := combat_pose or _punch_time > 0.0
	var aim_yaw := _yaw if facing_aim else (move_yaw if moving else _torso.rotation.y)

	var leg_yaw := move_yaw
	if not moving and _punch_time > 0.0:
		leg_yaw = _yaw  # standing still: turn the whole body into the punch
	if moving and facing_aim:
		_backpedal = absf(angle_difference(move_yaw, aim_yaw)) > deg_to_rad(100.0)
		if _backpedal:
			leg_yaw = move_yaw + PI
	else:
		_backpedal = false
	_legs.rotation.y = lerp_angle(_legs.rotation.y, leg_yaw, smooth)
	_torso.rotation.y = lerp_angle(_torso.rotation.y, aim_yaw, smooth)

	var horizontal := Vector2(velocity.x, velocity.z).length()
	_walk_phase += delta * horizontal * 1.6 * (-1.0 if _backpedal else 1.0)
	var stride := clampf(horizontal / SPRINT_SPEED, 0.0, 1.0)
	var swing := sin(_walk_phase) * stride * 0.8
	_leg_l.rotation.x = swing
	_leg_r.rotation.x = -swing
	_torso.position.y = TORSO_HEIGHT + absf(sin(_walk_phase)) * stride * 0.05
	_torso.rotation.x = lerpf(_torso.rotation.x, -0.15 if _sprinting else 0.0, 1.0 - exp(-8.0 * delta))
	if _rig:
		_update_rig(combat_pose)

	# A footstep lands each time the stride swings through center.
	var step_sign := signf(sin(_walk_phase))
	if is_on_floor() and horizontal > 1.5 and step_sign != _last_step_sign and _dash_timer <= 0.0:
		_play_footstep(stride * 4.0)
	_last_step_sign = step_sign


## While swimming the whole body turns as one and tilts flat, pivoting at the chest,
## with a flutter kick. Aiming brings the body upright to tread water and shoot.
func _update_swim_pose(delta: float, wish: Vector3) -> void:
	var smooth := 1.0 - exp(-8.0 * delta)
	var moving := wish.length() > 0.1
	var combat_pose := aiming or pulling or _shot_pose > 0.0
	var target_facing := _swim_facing
	if combat_pose:
		target_facing = _yaw
	elif moving:
		target_facing = atan2(-wish.x, -wish.z)
	_swim_facing = lerp_angle(_swim_facing, target_facing, smooth)
	var dive := clampf(-velocity.y / SWIM_SPRINT_SPEED, -1.0, 1.0)
	var target_tilt := -1.25 - dive * 0.3 if moving and not combat_pose else -0.15
	if _rig and _rig.has_state("swim"):
		target_tilt = -dive * 0.4  # the swim animation already lies the body flat
	if _rig:
		_legs.rotation.y = 0.0
		_torso.rotation.y = 0.0
		_update_rig(combat_pose)
	_swim_tilt = lerpf(_swim_tilt, target_tilt, smooth)
	var basis := Basis(Vector3.UP, _swim_facing) * Basis(Vector3.RIGHT, _swim_tilt)
	var pivot := Vector3(0, 1.1, 0)
	_model.transform = Transform3D(basis, pivot - basis * pivot)
	var kick := sin(Time.get_ticks_msec() * 0.009) * (0.45 if moving else 0.2)
	_leg_l.rotation.x = kick
	_leg_r.rotation.x = -kick
	_torso.position.y = TORSO_HEIGHT
	_torso.rotation.x = lerpf(_torso.rotation.x, 0.0, smooth)


func _play_footstep(offset_db: float) -> void:
	Audio.play("footstep_" + _surface(), null, offset_db, 1.0, 0.1)
	_step_count += 1
	if _step_count % 2 == 0:
		Audio.play("gear_rustle", null, offset_db, 1.0, 0.1)


## Ground material under the player: terrain picks grass/sand/snow by height;
## anything built (Sanctum, ruins, rocks) counts as stone.
func _surface() -> String:
	if water_depth() > 0.15:
		return "water"
	for i in get_slide_collision_count():
		var hit := get_slide_collision(i)
		if hit.get_normal().y < 0.6:
			continue
		var collider := hit.get_collider() as Node
		if collider and collider.name != "Terrain":
			return "stone"
	var h := Game.height_at(global_position.x, global_position.z)
	if h > 26.0:
		return "snow"
	if h < -0.4:
		return "sand"
	return "grass"


func _build_camera() -> void:
	_camera_rig = Node3D.new()
	_camera_rig.position = Vector3(0, _shoulder, 0)
	add_child(_camera_rig)
	_pitch_pivot = Node3D.new()
	_camera_rig.add_child(_pitch_pivot)
	_spring = SpringArm3D.new()
	_spring.spring_length = 3.4
	_spring.position = Vector3(0.65, 0.15, 0)
	var probe := SphereShape3D.new()
	probe.radius = 0.25
	_spring.shape = probe
	_spring.collision_mask = 1
	_spring.add_excluded_object(get_rid())
	_pitch_pivot.add_child(_spring)
	camera = Camera3D.new()
	camera.fov = 72.0
	camera.far = 600.0
	_spring.add_child(camera)
	camera.current = true


const TORSO_HEIGHT := 0.82


## Two independently rotating halves: legs + pelvis, and a torso pivoting at the hips.
## Torso part positions below are given in model space and shifted to the hip pivot.
func _build_model() -> void:
	_model = Node3D.new()
	add_child(_model)
	_legs = Node3D.new()
	_model.add_child(_legs)
	_torso = Node3D.new()
	_torso.position.y = TORSO_HEIGHT
	_model.add_child(_torso)
	var hip := Vector3(0, TORSO_HEIGHT, 0)
	var cloth := MeshKit.mat(Color(0.1, 0.2, 0.24))
	var armor := MeshKit.mat(Color(0.72, 0.52, 0.26), 0.35, 0.8)
	var dark := MeshKit.mat(Color(0.12, 0.12, 0.14), 0.6, 0.3)
	var visor := MeshKit.glow(Color(0.35, 0.95, 1.0), 4.0)
	_leg_l = _limb(Vector3(-0.13, 0.82, 0), Vector3(0.17, 0.8, 0.2), dark)
	_leg_r = _limb(Vector3(0.13, 0.82, 0), Vector3(0.17, 0.8, 0.2), dark)
	MeshKit.part(_legs, MeshKit.box(Vector3(0.44, 0.18, 0.26)), dark, Vector3(0, 0.86, 0))
	MeshKit.part(_torso, MeshKit.box(Vector3(0.5, 0.6, 0.3)), cloth, Vector3(0, 1.15, 0) - hip)
	MeshKit.part(_torso, MeshKit.box(Vector3(0.52, 0.32, 0.32)), armor, Vector3(0, 1.3, -0.01) - hip)
	MeshKit.part(_torso, MeshKit.box(Vector3(0.56, 1.05, 0.05)), cloth, Vector3(0, 1.0, 0.19) - hip, Vector3(0.1, 0, 0))
	for side in [-1.0, 1.0]:
		MeshKit.part(_torso, MeshKit.sphere(0.15, 0.2, 8, 4), armor, Vector3(0.32 * side, 1.47, 0) - hip)
		MeshKit.part(_torso, MeshKit.box(Vector3(0.13, 0.55, 0.14)), cloth, Vector3(0.34 * side, 1.15, -0.08) - hip, Vector3(0.5, 0, 0))
	MeshKit.part(_torso, MeshKit.sphere(0.19, 0.4, 10, 6), armor, Vector3(0, 1.72, 0) - hip)
	MeshKit.part(_torso, MeshKit.box(Vector3(0.28, 0.06, 0.06)), visor, Vector3(0, 1.73, -0.17) - hip)
	MeshKit.part(_torso, MeshKit.cyl(0.0, 0.05, 0.25, 4), armor, Vector3(0, 1.98, 0.02) - hip)
	_gun_socket = Node3D.new()
	_gun_socket.position = Vector3(0.24, 1.22, -0.32) - hip
	_torso.add_child(_gun_socket)
	_attach_rig()
	_muzzle_light = OmniLight3D.new()
	_muzzle_light.light_color = Color(1.0, 0.8, 0.5)
	_muzzle_light.omni_range = 5.0
	_muzzle_light.light_energy = 0.0
	_gun_socket.add_child(_muzzle_light)


## When a rigged hero model has been dropped into models/hero, it replaces the
## primitive body: the primitive parts are hidden but their pivots keep driving
## the facing (legs) and aim (torso), which the rig follows via a spine twist.
const RANGER_HEIGHT := 1.8
## Where the ranger's right hand is when it aims (its 1H_Ranged_Aiming pose).
const RANGER_HAND := Vector3(0.33, 0.64, -0.36)
## Camera height for the ranger: a little above the top of the hood.
const RANGER_SHOULDER := 2.05


func _attach_rig() -> void:
	# The KayKit ranger when it's there, else the photo-made hero.
	_rig = CharacterRig.create("ranger", RANGER_HEIGHT) if CharacterRig.exists("ranger") else CharacterRig.create("hero", 1.93)
	if _rig == null:
		return
	for part in _legs.get_children() + _torso.get_children():
		if part != _gun_socket:
			part.visible = false
	_model.add_child(_rig)
	_twist = TorsoTwist.new()
	_rig.skeleton.add_child(_twist)
	_punch_arm = PunchArm.new()
	_rig.skeleton.add_child(_punch_arm)
	if _rig.name == "Rig_hero":  # the ranger's own sit is already cross-legged
		_cross_legs = CrossLegs.new()
		_rig.skeleton.add_child(_cross_legs)
	# Hold the gun in front of the chest, where the aiming pose puts the hands.
	if _rig.name == "Rig_ranger":
		_shoulder = RANGER_SHOULDER  # the camera is built after this
		_gun_socket.position = RANGER_HAND - Vector3(0, TORSO_HEIGHT, 0)
		# Its hands have prop slots: tools ride in them and move with every
		# animation (see _follow_hand).
		for side in ["l", "r"]:
			if _rig.skeleton.find_bone("handslot." + side) >= 0:
				var grip := BoneAttachment3D.new()
				grip.bone_name = "handslot." + side
				_rig.skeleton.add_child(grip)
				if side == "l":
					_grip_l = grip
				else:
					_grip_r = grip
		_sling_draw = SlingDraw.new()
		_rig.skeleton.add_child(_sling_draw)
	else:
		_gun_socket.position = Vector3(0.12, 1.38, -0.42) - Vector3(0, TORSO_HEIGHT, 0)
	_rig.play("idle")


## Picks the rig's animation from what the body is doing and keeps the rig
## facing with the legs while the spine twists toward the aim.
func _update_rig(combat_pose: bool) -> void:
	_rig.rotation.y = _legs.rotation.y
	_twist.yaw = angle_difference(_legs.rotation.y, _torso.rotation.y)
	var horizontal := Vector2(velocity.x, velocity.z).length()
	if _action_time > 0.0:
		if swimming or not is_on_floor() or (_action_soft and horizontal > 1.6):
			_action_time = 0.0  # moved off, jumped or fell in: back to moving
		else:
			return
	if swimming:
		_twist.yaw = 0.0
		if horizontal > 0.5 and not combat_pose:
			if not _rig.play("swim", clampf(horizontal / SWIM_SPEED, 0.6, 1.6)):
				_rig.play("sprint", 0.6)  # no swim of its own: lying flat, arms and legs going
		elif not _rig.play("tread"):
			_rig.play("fall", 0.6)
	elif not is_on_floor():
		_rig.play("jump" if velocity.y > 1.0 else "fall", 1.0, 0.15)
	elif horizontal > 0.4:
		if _backpedal:
			_rig.play("walk_back", clampf(horizontal / 1.5, 0.8, 2.4))
		elif horizontal < 2.5:
			_rig.play("walk", clampf(horizontal / 1.4, 0.6, 1.8))
		else:
			_rig.play("run", clampf(horizontal / 5.0, 0.8, 1.7))
	else:
		_rig.play(_aim_state() if combat_pose else "idle")


func _limb(hip: Vector3, size: Vector3, material: Material) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = hip
	_legs.add_child(pivot)
	MeshKit.part(pivot, MeshKit.box(size), material, Vector3(0, -size.y * 0.5, 0))
	return pivot


# --- Sitting by the fire -------------------------------------------------------

## Sits down on the ground beside `fire`, facing it; the pets come and join.
func sit_by_fire(fire: Node3D) -> void:
	var c := fire.global_position
	var from := global_position - c
	from.y = 0.0
	from = from.normalized() if from.length() > 0.1 else Vector3.BACK
	var spot := c + from * 1.8
	spot.y = Game.ground_at(spot.x, spot.z)
	create_tween().tween_property(self, "global_position", spot, 0.35)
	sit_facing(c)
	seated = true
	_getting_up = false
	_seat_fire = fire
	var angle := atan2(from.z, from.x)
	var offset := 1.25
	for comp in get_tree().get_nodes_in_group("companions"):
		var pet := comp as Companion
		if pet.state == Companion.State.FOLLOWING and pet.body.global_position.distance_to(c) < 20.0:
			pet.sit_by_fire(fire, angle + offset)
			offset = -offset


func _update_seated() -> void:
	if _getting_up:
		return
	if Input.is_action_just_pressed("interact") and is_instance_valid(_seat_fire) and cooking == "":
		fire_requested.emit(_seat_fire)
		return
	var moving := Input.get_vector("move_left", "move_right", "move_forward", "move_back").length() > 0.3
	if moving or Input.is_action_just_pressed("jump"):
		get_up()


## Gets up off the ground (plays the getting-up motion), then can move again.
func get_up() -> void:
	if not seated or _getting_up:
		return
	_getting_up = true
	var done := func():
		if not seated:
			return
		seated = false
		_getting_up = false
		stand_up()
		stood_up.emit()
		for comp in get_tree().get_nodes_in_group("companions"):
			if (comp as Companion)._sitting_fire:
				comp.follow()
	# Uncross, push up, and stand: the cross-legged pose eases out as the idle
	# stance blends in.
	_sitting = false
	if _rig:
		_rig.play("idle", 1.0, 0.8)
	get_tree().create_timer(0.8).timeout.connect(done)
