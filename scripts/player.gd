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
const NOVA_COLOR := Color(0.4, 0.9, 1.0)
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
var _punch_cooldown := 0.0
var _punch_landed := false
var _punch_arm: PunchArm

## Building: the preview being placed, and a pause between "can't build here" thoughts.
signal says(lines: Array)
var _placer: Placer
var _cant_build_cooldown := 0.0


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
	_camera_rig.rotation.y = _yaw
	_pitch_pivot.rotation.x = _pitch + _recoil
	var smooth := 1.0 - exp(-12.0 * delta)
	# First person: camera at the eyes, shoulder offset gone, own body hidden.
	var first_person := zoom < FIRST_PERSON and not frozen
	var arm := 0.0 if first_person else (minf(zoom, 1.9) if aiming else zoom)
	_spring.spring_length = lerpf(_spring.spring_length, arm, smooth)
	_spring.position.x = lerpf(_spring.position.x, 0.0 if first_person else 0.65, smooth)
	_camera_rig.position.y = lerpf(_camera_rig.position.y, EYE_HEIGHT if first_person else 1.55, smooth)
	if _rig:
		_rig.visible = not (first_person and _spring.spring_length < 0.3)
	var target_fov := 55.0 if aiming else (78.0 if _sprinting else 72.0)
	camera.fov = lerpf(camera.fov, target_fov, smooth)
	_recoil = lerpf(_recoil, 0.0, 1.0 - exp(-9.0 * delta))
	_muzzle_light.light_energy = lerpf(_muzzle_light.light_energy, 0.0, 1.0 - exp(-30.0 * delta))
	var gun_pitch := _pitch if (aiming or _shot_pose > 0.0) else 0.0
	_gun_socket.rotation.x = lerpf(_gun_socket.rotation.x, gun_pitch, smooth)
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


func _physics_process(delta: float) -> void:
	if not alive:
		_respawn_timer -= delta
		if _respawn_timer <= 0.0:
			_respawn()
		return
	_tick_timers(delta)
	if frozen:
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
	_update_water_state()

	if swimming:
		wish = _swim(delta, input)
	else:
		if _dash_timer > 0.0:
			_dash_timer -= delta
			velocity.x = _dash_dir.x * DASH_SPEED
			velocity.z = _dash_dir.z * DASH_SPEED
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
		move_and_slide()
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
	if Input.is_action_just_pressed("interact"):
		_interact()
	if _placer:
		_update_placing(captured)
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
	_cant_build_cooldown = maxf(0.0, _cant_build_cooldown - delta)
	if _punch_time > 0.0:
		_punch_time = maxf(0.0, _punch_time - delta)
		var t := 1.0 - _punch_time / PUNCH_TIME
		if t > 0.3 and not _punch_landed:
			_punch_landed = true
			_punch_land()
		if _punch_arm:
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
	var muzzle := _gun_model.to_global(_gun_model.get_meta("muzzle"))
	for i in weapon.pellets:
		_fire_ray(muzzle)
	_recoil += minf(0.01 + 0.02 / weapon.fire_rate, 0.05) * (0.6 if aiming else 1.0)
	_muzzle_light.light_energy = 5.0
	if ammo == 0:
		_start_reload()


const SHOT_SOUNDS := {
	"Rifle": "shot_rifle", "Hand Cannon": "shot_cannon", "Scattergun": "shot_scatter",
	"Rune SMG": "shot_smg", "Sky Lance": "shot_lance",
}
const ELEMENT_SOUNDS := ["", "elem_fire", "elem_shock", "elem_frost"]


func _play_shot_sound() -> void:
	Audio.play(SHOT_SOUNDS.get(weapon.archetype, "shot_rifle"), null, 0.0, 1.0, 0.05)
	if weapon.element != WeaponData.Element.KINETIC:
		Audio.play(ELEMENT_SOUNDS[weapon.element], null, 0.0, 1.0, 0.1)


func _fire_ray(muzzle: Vector3) -> void:
	var cam_basis := camera.global_basis
	var forward := -cam_basis.z
	var spread := weapon.spread * (0.35 if aiming else 1.0)
	var dir := (forward
		+ cam_basis.x * Game.rng.randf_range(-spread, spread)
		+ cam_basis.y * Game.rng.randf_range(-spread, spread)).normalized()
	# Start at the shoulder (spring arm origin) so walls behind the player never block shots.
	var origin := camera.global_position + forward * _spring.get_hit_length()
	var target := origin + dir * 300.0
	var query := PhysicsRayQueryParameters3D.create(origin, target, 1 | 4, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var end := target
	if not hit.is_empty():
		end = hit["position"]
		var collider = hit["collider"]
		if collider is Enemy:
			_hit_enemy(collider, end)
		else:
			FX.burst(end, Color(1.0, 0.85, 0.6), 5, 3.0, 0.05)
	FX.tracer(muzzle, end, WeaponData.ELEMENT_COLORS[weapon.element])


func _hit_enemy(enemy: Enemy, pos: Vector3) -> void:
	var dmg := weapon.damage * damage_multiplier()
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
	var color: Color = NOVA_COLOR if weapon.element == WeaponData.Element.KINETIC else WeaponData.ELEMENT_COLORS[weapon.element]
	var center := global_position + Vector3.UP * 0.6
	FX.ring(center, NOVA_RADIUS, color, 0.4)
	FX.flash(center, color, 8.0, 14.0, 0.4)
	FX.burst(center, color, 36, 10.0)
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


func _dash(wish: Vector3) -> void:
	if dash_cooldown > 0.0:
		return
	dash_cooldown = DASH_COOLDOWN
	_dash_timer = DASH_TIME
	_dash_dir = wish.normalized() if wish.length() > 0.1 else Basis(Vector3.UP, _yaw) * Vector3.FORWARD
	FX.burst(global_position + Vector3.UP * 0.9, NOVA_COLOR, 14, 4.0)
	Audio.play("dash")


func take_damage(amount: float) -> void:
	if not alive or _dash_timer > 0.0:
		return
	health -= amount
	_since_damage = 0.0
	damaged.emit(amount)
	if _hurt_sound_cooldown <= 0.0:
		_hurt_sound_cooldown = 0.25
		Audio.play("player_hurt")
	if health <= 0.0:
		_die()


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
	_model.visible = false
	FX.burst(global_position + Vector3.UP, NOVA_COLOR, 40, 7.0)
	_respawn_timer = 4.0
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
	_model.transform = Transform3D.IDENTITY
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
var _warned := {}
var _swim_practice := 0.0


func _update_needs(delta: float) -> void:
	if not Game.story_start:
		return
	Game.thirst = maxf(0.0, Game.thirst - THIRST_RATE * delta)
	Game.hunger = maxf(0.0, Game.hunger - HUNGER_RATE * delta)
	if Campfire.warms(get_tree(), global_position):
		Game.warmth = minf(100.0, Game.warmth + FIRE_WARM_RATE * delta)
	else:
		var sheltered := 0.4 if Shelter.covers(get_tree(), global_position) else 1.0  # out of the wind
		Game.warmth = maxf(0.0, Game.warmth - COLD_RATE * delta * (2.0 if swimming else sheltered))
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
	_update_gather_focus()


func _update_gather_focus() -> void:
	var best: Gatherable = null
	var best_dist := 2.8
	for node in get_tree().get_nodes_in_group("gatherables"):
		var g := node as Gatherable
		if not g.available:
			continue
		var d := g.global_position.distance_to(global_position)
		if d < best_dist:
			best_dist = d
			best = g
	if best != focused_gatherable:
		if is_instance_valid(focused_gatherable):
			focused_gatherable.set_focused(false)
		if best:
			best.set_focused(true)
	focused_gatherable = best
	focused_companion = null
	if best == null:
		var closest := 2.4
		for node in get_tree().get_nodes_in_group("companions"):
			var c := node as Companion
			if c.state == Companion.State.FOLLOWING and c.body.global_position.distance_to(global_position) < closest:
				closest = c.body.global_position.distance_to(global_position)
				focused_companion = c


## E: gather what's in front of you, else talk to a pet beside you, else swap
## in a weapon, else drink if you're standing in water.
func _interact() -> void:
	if focused_gatherable == null and is_instance_valid(focused_companion):
		talk_requested.emit(focused_companion)
		return
	if is_instance_valid(focused_gatherable):
		var got := focused_gatherable.gather(Game.rng)
		if got != "":
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
		Game.practice("Survival", 0.5)
		Audio.play("gear_rustle", null, 0.0, 1.5)


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
	Audio.play("nova", spot, -8.0, 0.6)


func _punch() -> void:
	if _punch_cooldown > 0.0 or frozen:
		return
	_punch_time = PUNCH_TIME
	_punch_cooldown = PUNCH_COOLDOWN
	_punch_landed = false
	if _punch_arm:
		_punch_arm.left = not _punch_arm.left
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
	_legs.rotation.y = facing
	_torso.rotation.y = facing
	_yaw = facing + PI
	_pitch = -0.28
	if _rig:
		_rig.rotation.y = facing
		_rig.play("getting_up", 0.8, 0.0)
		_rig.finished.connect(func(state: String):
			if state == "getting_up":
				_end_wake()
		)
	get_tree().create_timer(12.0).timeout.connect(_end_wake)  # safety net


func _end_wake() -> void:
	if not frozen:
		return
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
	Game.notify("Equipped %s" % new_weapon.display_name, new_weapon.color)


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
	var combat_pose := aiming or _shot_pose > 0.0
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
	var combat_pose := aiming or _shot_pose > 0.0
	var target_facing := _swim_facing
	if combat_pose:
		target_facing = _yaw
	elif moving:
		target_facing = atan2(-wish.x, -wish.z)
	_swim_facing = lerp_angle(_swim_facing, target_facing, smooth)
	var dive := clampf(-velocity.y / SWIM_SPRINT_SPEED, -1.0, 1.0)
	var target_tilt := -1.25 - dive * 0.3 if moving and not combat_pose else -0.15
	if _rig:
		target_tilt = -dive * 0.4  # the swim animation already lies the body flat
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
	_camera_rig.position = Vector3(0, 1.55, 0)
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
func _attach_rig() -> void:
	_rig = CharacterRig.create("hero", 1.93)
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
	# Hold the gun in front of the chest, where the aiming pose puts the hands.
	_gun_socket.position = Vector3(0.12, 1.38, -0.42) - Vector3(0, TORSO_HEIGHT, 0)
	_rig.play("idle")


## Picks the rig's animation from what the body is doing and keeps the rig
## facing with the legs while the spine twists toward the aim.
func _update_rig(combat_pose: bool) -> void:
	_rig.rotation.y = _legs.rotation.y
	_twist.yaw = angle_difference(_legs.rotation.y, _torso.rotation.y)
	var horizontal := Vector2(velocity.x, velocity.z).length()
	if swimming:
		_twist.yaw = 0.0
		if horizontal > 0.5 and not combat_pose:
			_rig.play("swim", clampf(horizontal / SWIM_SPEED, 0.6, 1.6))
		else:
			_rig.play("tread")
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
		_rig.play("aim_idle" if combat_pose else "idle")


func _limb(hip: Vector3, size: Vector3, material: Material) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = hip
	_legs.add_child(pivot)
	MeshKit.part(pivot, MeshKit.box(size), material, Vector3(0, -size.y * 0.5, 0))
	return pivot
