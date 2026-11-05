class_name Burns
## Fire is hot. Anyone who steps into a campfire or brushes a torch flame
## yelps, hops back out, loses a little health and wears a soot mark for a
## while. Campfires and torches call `check` a few times a second.

const COOLDOWN_MS := 1400
const MARK_LIFE := 150.0  # seconds before a soot mark fades away
const HERO_LINES := [
	"Ow! Hot hot hot!",
	"Yep. Fire's still hot. Good to know.",
	"Ouch! Note to self: don't hug the fire.",
	"Eep! Toasty. Too toasty.",
	"Ah! My poor ankle!",
	"Okay, okay, I'm moving!",
]
const FOX_LINES := [
	"YOWCH! My tail! ...Is it still there? It's still there.",
	"I meant to do that. Testing the fire. It works.",
	"Ow ow ow! Who put a fire THERE?",
	"Hot! Okay. Not stepping there again. Probably.",
]
const OTTER_LINES := [
	"Ouchie! Hot hot hot!",
	"Eep! My whiskers went crispy!",
	"I'm okay! I'm okay! ...That was HOT.",
	"The fire bit me! Bad fire!",
]
## What the other pet says when someone else gets singed.
const FOX_TEASES := [
	"Smooth. Real smooth.",
	"You okay? ...Can I laugh now? I'm laughing now.",
	"Rule one of fire: don't stand IN it.",
]
const OTTER_WORRIES := [
	"Are you okay?! Blow on it! Blow on it!",
	"Oh no! Want me to get some water?",
	"Careful! The fire's grumpy today.",
]


## Burns whoever is inside the fire at `center`: within `radius` sideways, with
## their feet between `low` and `high` meters relative to the fire's base.
## `flame_y` (above the base) also counts anyone whose body reaches that high.
static func check(fire: Node3D, radius: float, low: float, high: float, flame_y := -1.0) -> void:
	var c := fire.global_position
	var p := Game.player
	if p and p.alive and _inside(p.global_position, c, radius, low, high, flame_y, 1.8):
		if _ready_to_burn(p):
			p.burn(c)
			_bystanders_react(fire.get_tree(), null)
	for comp in fire.get_tree().get_nodes_in_group("companions"):
		var pet := comp as Companion
		if pet.can_burn() and _inside(pet.body.global_position, c, radius, low, high, flame_y, pet.head_height):
			if _ready_to_burn(pet.body):
				pet.burn(c)
				_bystanders_react(fire.get_tree(), pet)
	for e in fire.get_tree().get_nodes_in_group("enemies"):
		var enemy := e as Enemy
		if not enemy.dead and _inside(enemy.global_position, c, radius + 0.3, low, high, flame_y, 1.8):
			if _ready_to_burn(enemy):
				var away := _away(c, enemy.global_position)
				enemy.take_damage(8.0, false, WeaponData.Element.FIRE)
				enemy.knockback(away * 9.0)
				FX.burst(enemy.global_position + Vector3.UP * 0.5, Color(0.25, 0.22, 0.2), 10, 1.8, 0.06)


static func _inside(pos: Vector3, c: Vector3, radius: float, low: float, high: float, flame_y: float, height: float) -> bool:
	if Vector2(pos.x - c.x, pos.z - c.z).length() > radius:
		return false
	var feet := pos.y - c.y
	if flame_y >= 0.0:
		return feet <= flame_y and feet + height >= flame_y - 0.1
	return feet >= low and feet <= high


static func _ready_to_burn(who: Node) -> bool:
	var now := Time.get_ticks_msec()
	if now - int(who.get_meta("burnt_at", -COOLDOWN_MS)) < COOLDOWN_MS:
		return false
	who.set_meta("burnt_at", now)
	return true


## Which way to hop: straight out from the fire, along the ground.
static func _away(c: Vector3, pos: Vector3) -> Vector3:
	var away := Vector3(pos.x - c.x, 0.0, pos.z - c.z)
	if away.length() < 0.05:
		away = Vector3(randf_range(-1, 1), 0.0, randf_range(-1, 1))
	return away.normalized()


## The pets notice when someone gets singed, now and then. `burnt` is the pet
## that got burnt (null for the hero), which never comments on itself.
static func _bystanders_react(tree: SceneTree, burnt: Companion) -> void:
	if randf() > 0.6:
		return
	var p := Game.player
	for comp in tree.get_nodes_in_group("companions"):
		var pet := comp as Companion
		if pet == burnt or not pet.can_burn() or pet.body.global_position.distance_to(p.global_position) > 12.0:
			continue
		var lines: Array = FOX_TEASES if pet.who == "fox" else OTTER_WORRIES
		tree.create_timer(1.6).timeout.connect(func():
			if is_instance_valid(pet):
				pet.say([lines.pick_random()]))
		return


# --- Soot marks ----------------------------------------------------------------

## Leaves a sooty smudge on `holder`'s surface at `point` (world space), facing
## out along `out`. Smudges fade after a while; `wash_off` clears them early.
static func mark(holder: Node3D, point: Vector3, out: Vector3, size := 0.07) -> void:
	var m := MeshInstance3D.new()
	m.mesh = MeshKit.sphere(size, size * 0.5, 7, 4)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.08, 0.06, 0.05, 0.82)
	mat.roughness = 1.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.add_to_group("soot")
	holder.add_child(m)
	# A flat blotch lying on the surface, a little lopsided so no two match.
	var up := out.normalized()
	var side := up.cross(Vector3.UP if absf(up.y) < 0.9 else Vector3.RIGHT).normalized()
	var basis := Basis(side, up, side.cross(up)).rotated(up, randf() * TAU)
	basis = basis.scaled_local(Vector3(randf_range(0.8, 1.3), 0.35, randf_range(0.7, 1.1)))
	m.global_transform = Transform3D(basis, point)
	# A thin curl of smoke off the fresh mark.
	var smoke := CPUParticles3D.new()
	var puff := MeshKit.sphere(0.03, -1.0, 5, 3)
	var smoke_mat := MeshKit.mat(Color(0.5, 0.48, 0.46, 0.5))
	smoke_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	puff.material = smoke_mat
	smoke.mesh = puff
	smoke.amount = 8
	smoke.lifetime = 1.2
	smoke.direction = Vector3.UP
	smoke.spread = 15.0
	smoke.initial_velocity_min = 0.3
	smoke.initial_velocity_max = 0.6
	smoke.gravity = Vector3(0, 0.3, 0)
	smoke.local_coords = false
	m.add_child(smoke)
	smoke.top_level = true
	smoke.global_position = point
	var tw := m.create_tween()
	tw.tween_interval(2.5)
	tw.tween_callback(func(): smoke.emitting = false)
	tw.tween_interval(MARK_LIFE)
	tw.tween_property(mat, "albedo_color:a", 0.0, 6.0)
	tw.tween_callback(m.queue_free)


## Rinses every soot mark off `holder` (a dip in the water does it).
static func wash_off(holder: Node) -> bool:
	var washed := false
	for m in holder.find_children("*", "MeshInstance3D", true, false):
		if m.is_in_group("soot"):
			m.queue_free()
			washed = true
	return washed
