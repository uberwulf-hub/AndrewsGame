class_name Enemy
extends CharacterBody3D
## Hostile construct of the old world. Three kinds share this script: melee Husks,
## hovering Rune Sentinels that shoot orbs, and Iron Brutes with telegraphed slams.

enum Kind { HUSK, SENTINEL, BRUTE }

const GRAVITY := 22.0
const AGGRO_RANGE := 26.0
const LEASH_RANGE := 70.0
const KIND_DATA := {
	Kind.HUSK: {"name": "Husk", "health": 60.0, "speed": 4.8, "damage": 12.0, "range": 2.2, "cooldown": 1.2,
		"xp": 12, "loot": 0.22, "height": 1.7, "radius": 0.45, "eye": Color(1.0, 0.35, 0.15)},
	Kind.SENTINEL: {"name": "Rune Sentinel", "health": 45.0, "speed": 4.0, "damage": 10.0, "range": 18.0, "cooldown": 1.8,
		"xp": 16, "loot": 0.28, "height": 1.4, "radius": 0.6, "eye": Color(0.95, 0.3, 0.85)},
	Kind.BRUTE: {"name": "Iron Brute", "health": 260.0, "speed": 3.0, "damage": 32.0, "range": 4.0, "cooldown": 2.6,
		"xp": 60, "loot": 0.85, "height": 2.8, "radius": 0.9, "eye": Color(1.0, 0.55, 0.1)},
}

var kind: Kind = Kind.HUSK
var level := 1
var max_health := 60.0
var health := 60.0
var home := Vector3.ZERO
var dead := false

var _data: Dictionary
var _height := 1.7
var _aggro := false
var _attack_timer := 0.0
var _windup := 0.0
var _windup_total := 0.0
var _burn_time := 0.0
var _burn_dps := 0.0
var _burn_tick := 0.0
var _slow_time := 0.0
var _knockback := Vector3.ZERO
var _strafe := 1.0
var _wander_target := Vector3.ZERO
var _wander_timer := 0.0
var _hit_flash := 0.0
var _model: Node3D
var _flash_mats: Array[StandardMaterial3D] = []
var _hp_root: Node3D
var _hp_fill: MeshInstance3D
var _telegraph: MeshInstance3D
var _spin: Node3D
var _was_aggro := false
var _step_timer := 0.0
var _impact_cooldown := 0.0


func setup(enemy_kind: Kind, enemy_level: int, camp_pos: Vector3) -> void:
	kind = enemy_kind
	level = enemy_level
	home = camp_pos


func _ready() -> void:
	add_to_group("enemies")
	_data = KIND_DATA[kind]
	collision_layer = 4
	collision_mask = 1 | 2 | 4
	max_health = _data["health"] * pow(1.18, level - 1)
	health = max_health
	_height = _data["height"]
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = _data["radius"]
	capsule.height = _height
	shape.shape = capsule
	shape.position.y = _height * 0.5
	add_child(shape)
	_build_model()
	_build_overhead()
	_wander_target = home
	_attack_timer = randf() * 1.5
	if kind == Kind.SENTINEL:
		var hum := Audio.attach_loop(self, "loop_sentinel", 0.0, 22.0, 3.0)
		if hum:
			hum.position.y = 0.7
			hum.pitch_scale = randf_range(0.9, 1.1)


func center() -> Vector3:
	return global_position + Vector3.UP * _height * 0.5


func xp_reward() -> int:
	return int(_data["xp"] * (1.0 + 0.3 * (level - 1)))


func is_engaged() -> bool:
	return _aggro


func knockback(impulse: Vector3) -> void:
	var resist := 0.3 if kind == Kind.BRUTE else 1.0
	_knockback += impulse * resist


# --- Damage ------------------------------------------------------------------

## Returns true if this hit killed the enemy.
func take_damage(amount: float, crit := false, element := 0) -> bool:
	if dead:
		return false
	match element:
		WeaponData.Element.FIRE:
			_burn_dps = maxf(_burn_dps, amount * 0.3)
			_burn_time = 3.0
		WeaponData.Element.FROST:
			_slow_time = 2.5
	_aggro = true
	var color := Color(1.0, 0.9, 0.3) if crit else Color.WHITE
	if element != WeaponData.Element.KINETIC:
		color = color.lerp(WeaponData.ELEMENT_COLORS[element], 0.6)
	if _impact_cooldown <= 0.0:
		_impact_cooldown = 0.06
		Audio.play("impact_metal" if kind == Kind.SENTINEL else "impact_stone", center(), 0.0, 0.75 if kind == Kind.BRUTE else 1.0, 0.12)
	return _apply_damage(amount, crit, color)


func _apply_damage(amount: float, crit: bool, color: Color) -> bool:
	if dead:
		return false
	health -= amount
	_hit_flash = 1.0
	FX.damage_number(center() + Vector3.UP * (_height * 0.5 + 0.2), amount, color, crit)
	if health <= 0.0:
		_die()
		return true
	return false


func _die() -> void:
	dead = true
	FX.burst(center(), Color(0.8, 0.75, 0.65), 24, 6.0, 0.14)
	FX.burst(center(), _data["eye"], 14, 4.0)
	match kind:
		Kind.SENTINEL:
			Audio.play("death_sentinel", center())
		Kind.BRUTE:
			Audio.play("death_stone", center(), 4.0, 0.6)
		_:
			Audio.play("death_stone", center())
	if Game.player:
		Game.player.on_enemy_killed(self)
	if randf() < float(_data["loot"]):
		var w := WeaponData.generate(level, Game.rng, 0.8 if kind == Kind.BRUTE else 0.0)
		var drop_pos := global_position
		if kind == Kind.SENTINEL:
			drop_pos.y = Game.height_at(drop_pos.x, drop_pos.z)
		LootDrop.spawn(get_tree().current_scene, w, drop_pos)
		if w.rarity >= 3:
			Game.notify("%s drop: %s" % [WeaponData.RARITY_NAMES[w.rarity], w.display_name], w.color)
	queue_free()


func _tick_status(delta: float) -> void:
	_slow_time = maxf(0.0, _slow_time - delta)
	if _burn_time > 0.0:
		_burn_time -= delta
		_burn_tick -= delta
		if _burn_tick <= 0.0:
			_burn_tick = 0.5
			_apply_damage(_burn_dps * 0.5, false, WeaponData.ELEMENT_COLORS[WeaponData.Element.FIRE])
		if _burn_time <= 0.0:
			_burn_dps = 0.0


# --- AI ----------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if dead:
		return
	_tick_status(delta)
	if dead:
		return
	var player := Game.player
	var to_player := Vector3.ZERO
	var dist := INF
	if player and player.alive:
		to_player = player.global_position - global_position
		dist = to_player.length()
		if dist < AGGRO_RANGE:
			_aggro = true
	else:
		_aggro = false
	if _aggro and (dist > AGGRO_RANGE * 2.2 or global_position.distance_to(home) > LEASH_RANGE):
		_aggro = false
	if _aggro and not _was_aggro:
		_play_aggro_sound()
	_was_aggro = _aggro
	_attack_timer -= delta
	_impact_cooldown -= delta

	var move := Vector3.ZERO
	if _aggro:
		_face(to_player, delta)
		if kind == Kind.SENTINEL:
			move = _ranged_ai(player, to_player, dist, delta)
		else:
			move = _melee_ai(player, dist, to_player, delta)
	else:
		_windup = 0.0
		if _telegraph:
			_telegraph.visible = false
		move = _wander(delta)
		health = minf(max_health, health + max_health * 0.15 * delta)

	var speed: float = _data["speed"] * (0.5 if _slow_time > 0.0 else 1.0)
	velocity.x = move.x * speed + _knockback.x
	velocity.z = move.z * speed + _knockback.z
	_knockback = _knockback.lerp(Vector3.ZERO, 1.0 - exp(-6.0 * delta))
	if kind == Kind.SENTINEL:
		var hover := Game.height_at(global_position.x, global_position.z) + 1.8 + sin(Time.get_ticks_msec() * 0.003 + home.x) * 0.25
		velocity.y = (hover - global_position.y) * 4.0
	elif is_on_floor():
		velocity.y = -0.5
	else:
		velocity.y -= GRAVITY * delta
	move_and_slide()
	_tick_footsteps(delta, move.length() * speed)


func _play_aggro_sound() -> void:
	match kind:
		Kind.HUSK:
			Audio.play("husk_aggro", center(), 0.0, randf_range(0.85, 1.15))
		Kind.SENTINEL:
			Audio.play("sentinel_alert", center())
		Kind.BRUTE:
			Audio.play("brute_roar", center(), 0.0, 1.0, 0.05, 90.0)


func _tick_footsteps(delta: float, speed: float) -> void:
	if kind == Kind.SENTINEL or speed < 0.8 or not is_on_floor():
		return
	_step_timer -= delta
	if _step_timer > 0.0:
		return
	if kind == Kind.BRUTE:
		_step_timer = 0.7
		Audio.play("brute_step", global_position, 0.0, 1.0, 0.1, 50.0)
	else:
		_step_timer = clampf(1.6 / speed, 0.3, 0.6)
		Audio.play("husk_step", global_position, 0.0, 1.0, 0.15, 30.0)


func _melee_ai(player: Player, dist: float, to_player: Vector3, delta: float) -> Vector3:
	var reach: float = _data["range"]
	if _windup > 0.0:
		_windup -= delta
		if _windup <= 0.0:
			_resolve_melee(player)
		return Vector3.ZERO
	if dist <= reach and _attack_timer <= 0.0:
		_windup_total = 0.9 if kind == Kind.BRUTE else 0.45
		_windup = _windup_total
		_attack_timer = _data["cooldown"]
		if _telegraph:
			_telegraph.visible = true
		if kind == Kind.BRUTE:
			Audio.play("brute_windup", center(), 0.0, 1.0, 0.03)
		return Vector3.ZERO
	if dist > reach * 0.8:
		return Vector3(to_player.x, 0.0, to_player.z).normalized()
	return Vector3.ZERO


func _resolve_melee(player: Player) -> void:
	var reach: float = _data["range"]
	if kind == Kind.BRUTE:
		_telegraph.visible = false
		FX.ring(global_position + Vector3.UP * 0.15, reach, Color(1.0, 0.5, 0.15), 0.3)
		FX.burst(global_position + Vector3.UP * 0.3, Color(0.7, 0.6, 0.5), 20, 6.0, 0.12)
		Audio.play("brute_slam", global_position, 0.0, 1.0, 0.05, 90.0)
	else:
		_knockback += -global_basis.z * 6.0
		Audio.play("husk_attack", center())
	if player and player.alive and player.global_position.distance_to(global_position) <= reach + 0.6:
		player.take_damage(_scaled_damage())


func _ranged_ai(player: Player, to_player: Vector3, dist: float, delta: float) -> Vector3:
	var dir := Vector3(to_player.x, 0.0, to_player.z).normalized()
	var move := Vector3.ZERO
	if dist > 16.0:
		move = dir
	elif dist < 9.0:
		move = -dir
	move += dir.cross(Vector3.UP) * _strafe * 0.6
	if randf() < delta * 0.4:
		_strafe *= -1.0
	if _attack_timer <= 0.0 and dist < AGGRO_RANGE and _has_line_of_sight(player):
		_attack_timer = _data["cooldown"]
		_shoot(player)
	return move.limit_length(1.0)


func _wander(delta: float) -> Vector3:
	_wander_timer -= delta
	if _wander_timer <= 0.0:
		_wander_timer = randf_range(2.5, 6.0)
		_wander_target = home + Vector3(randf_range(-7.0, 7.0), 0.0, randf_range(-7.0, 7.0))
	var to := _wander_target - global_position
	to.y = 0.0
	if to.length() < 1.0:
		return Vector3.ZERO
	_face(to, delta)
	return to.normalized() * 0.45


func _face(direction: Vector3, delta: float) -> void:
	if Vector2(direction.x, direction.z).length() < 0.01:
		return
	rotation.y = lerp_angle(rotation.y, atan2(-direction.x, -direction.z), 1.0 - exp(-8.0 * delta))


func _has_line_of_sight(player: Player) -> bool:
	var query := PhysicsRayQueryParameters3D.create(center(), player.global_position + Vector3.UP * 1.2, 1)
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _shoot(player: Player) -> void:
	var from := center() - global_basis.z * 0.7
	var aim := player.global_position + Vector3.UP * 1.1 + player.velocity * 0.25
	var orb := EnemyProjectile.new()
	orb.velocity = (aim - from).normalized() * 22.0
	orb.damage = _scaled_damage()
	get_tree().current_scene.add_child(orb)
	orb.global_position = from
	FX.flash(from, _data["eye"], 3.0, 5.0, 0.15)
	Audio.play("sentinel_shoot", from)


func _scaled_damage() -> float:
	return _data["damage"] * pow(1.12, level - 1)


# --- Visuals -----------------------------------------------------------------

func _process(delta: float) -> void:
	if _hit_flash > 0.0:
		_hit_flash = maxf(0.0, _hit_flash - delta * 6.0)
		for m in _flash_mats:
			m.emission_energy_multiplier = _hit_flash * 2.5
	_model.rotation.x = lerpf(_model.rotation.x, 0.35 if _windup > 0.0 else 0.0, 1.0 - exp(-12.0 * delta))
	if _spin:
		_spin.rotate_y(delta * 2.5)
	if _telegraph and _telegraph.visible:
		var s := lerpf(0.2, 1.0, 1.0 - _windup / _windup_total)
		_telegraph.scale = Vector3(s, 1.0, s)
	_hp_fill.scale.x = maxf(health / max_health, 0.001)
	_hp_root.visible = _aggro or health < max_health - 0.5


func _flash_mat(color: Color, roughness := 0.85, metallic := 0.0) -> StandardMaterial3D:
	var m := MeshKit.mat(color, roughness, metallic)
	m.emission_enabled = true
	m.emission = Color.WHITE
	m.emission_energy_multiplier = 0.0
	_flash_mats.append(m)
	return m


func _build_model() -> void:
	_model = Node3D.new()
	add_child(_model)
	var eye := MeshKit.glow(_data["eye"], 5.0)
	match kind:
		Kind.HUSK:
			var stone := _flash_mat(Color(0.42, 0.4, 0.36))
			var bronze := _flash_mat(Color(0.5, 0.36, 0.2), 0.4, 0.7)
			MeshKit.part(_model, MeshKit.box(Vector3(0.6, 0.75, 0.45)), stone, Vector3(0, 1.05, 0), Vector3(-0.25, 0, 0))
			MeshKit.part(_model, MeshKit.box(Vector3(0.36, 0.32, 0.34)), bronze, Vector3(0, 1.5, -0.18))
			MeshKit.part(_model, MeshKit.box(Vector3(0.24, 0.06, 0.05)), eye, Vector3(0, 1.52, -0.36))
			for side in [-1.0, 1.0]:
				MeshKit.part(_model, MeshKit.box(Vector3(0.18, 0.75, 0.2)), stone, Vector3(0.42 * side, 0.95, -0.15), Vector3(0.3, 0, 0))
				MeshKit.part(_model, MeshKit.box(Vector3(0.2, 0.7, 0.22)), bronze, Vector3(0.17 * side, 0.35, 0))
		Kind.SENTINEL:
			var brass := _flash_mat(Color(0.62, 0.46, 0.22), 0.3, 0.85)
			MeshKit.part(_model, MeshKit.sphere(0.5, 1.3, 4, 2), brass, Vector3(0, 0.7, 0))
			MeshKit.part(_model, MeshKit.sphere(0.17), eye, Vector3(0, 0.75, -0.42))
			_spin = Node3D.new()
			_spin.position = Vector3(0, 0.7, 0)
			_model.add_child(_spin)
			var halo := TorusMesh.new()
			halo.inner_radius = 0.72
			halo.outer_radius = 0.8
			MeshKit.part(_spin, halo, MeshKit.glow(_data["eye"], 2.5), Vector3.ZERO, Vector3(0.4, 0, 0))
			var light := OmniLight3D.new()
			light.light_color = _data["eye"]
			light.light_energy = 1.2
			light.omni_range = 4.0
			light.position = Vector3(0, 0.7, -0.5)
			_model.add_child(light)
		Kind.BRUTE:
			var iron := _flash_mat(Color(0.3, 0.3, 0.33), 0.45, 0.8)
			var stone := _flash_mat(Color(0.4, 0.37, 0.33))
			for side in [-1.0, 1.0]:
				MeshKit.part(_model, MeshKit.box(Vector3(0.45, 1.1, 0.5)), stone, Vector3(0.4 * side, 0.55, 0))
				MeshKit.part(_model, MeshKit.box(Vector3(0.4, 1.2, 0.45)), iron, Vector3(0.98 * side, 1.6, -0.1))
				MeshKit.part(_model, MeshKit.box(Vector3(0.6, 0.5, 0.6)), stone, Vector3(1.0 * side, 0.85, -0.2))
			MeshKit.part(_model, MeshKit.box(Vector3(1.5, 1.2, 1.0)), iron, Vector3(0, 1.75, 0))
			MeshKit.part(_model, MeshKit.sphere(0.22), eye, Vector3(0, 1.8, -0.5))
			MeshKit.part(_model, MeshKit.box(Vector3(0.5, 0.4, 0.5)), stone, Vector3(0, 2.5, -0.15))
			MeshKit.part(_model, MeshKit.box(Vector3(0.3, 0.06, 0.05)), eye, Vector3(0, 2.52, -0.41))
			var reach: float = _data["range"]
			_telegraph = MeshKit.part(self, MeshKit.cyl(reach, reach, 0.05, 32),
				MeshKit.glow(Color(1.0, 0.25, 0.1, 0.35), 1.5, true), Vector3(0, 0.12, 0))
			_telegraph.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_telegraph.visible = false


func _build_overhead() -> void:
	_hp_root = Node3D.new()
	_hp_root.position.y = _height + 0.45
	add_child(_hp_root)
	MeshKit.part(_hp_root, _bar_quad(), _bar_mat(Color(0, 0, 0, 0.6), 0))
	_hp_fill = MeshKit.part(_hp_root, _bar_quad(), _bar_mat(Color(0.9, 0.2, 0.15, 1.0), 1))
	var label := Label3D.new()
	label.text = "Lv %d %s" % [level, _data["name"]]
	label.font_size = 32
	label.outline_size = 10
	label.pixel_size = 0.0006
	label.fixed_size = true
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position.y = 0.3
	label.modulate = Color(1.0, 0.55, 0.4) if kind == Kind.BRUTE else Color(1.0, 0.88, 0.78)
	_hp_root.add_child(label)
	_hp_root.visible = false


func _bar_quad() -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(0.15, 0.012)
	return q


func _bar_mat(color: Color, priority: int) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	m.fixed_size = true
	m.no_depth_test = true
	m.render_priority = priority
	return m
