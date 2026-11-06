class_name Placer
extends Node3D
## Choosing where to build something: a see-through copy of it floats a couple
## of steps in front of the hero, blue where it can go and red where it can't
## (water, a steep slope, or bumping into a tree, rock, fire or shelter).

## Per buildable: how far ahead the preview floats, its footprint radius, and
## how close it may be to an existing fire.
const SIZES := {
	"campfire": {"distance": 2.4, "radius": 0.7, "fire_gap": 3.0},
	"lean_to": {"distance": 3.2, "radius": 1.1, "fire_gap": 1.6},
	"torch_post": {"distance": 1.6, "radius": 0.25, "fire_gap": 1.2, "shelter_gap": 1.0},
	"rain_catcher": {"distance": 1.8, "radius": 0.45, "fire_gap": 1.8, "shelter_gap": 1.6},
	"hearth": {"distance": 2.8, "radius": 1.0, "fire_gap": 3.5},
	"bedroll": {"distance": 2.0, "radius": 0.6, "fire_gap": 1.6, "shelter_gap": 1.0},
	"chest": {"distance": 1.8, "radius": 0.5, "fire_gap": 1.4, "shelter_gap": 1.0},
	# Goes up over other things: only its four poles need clear ground.
	"rain_cover": {"distance": 2.6, "radius": 1.35, "fire_gap": 0.0, "shelter_gap": 2.0, "poles": true},
}

var id := ""
var valid := false
var _blue := _ghost_mat(Color(0.35, 0.7, 1.0))
var _red := _ghost_mat(Color(1.0, 0.3, 0.25))
var _ghost: Node3D
var _parts: Array[MeshInstance3D] = []
var _painted := false


static func create(what: String) -> Placer:
	var p := Placer.new()
	p.id = what
	return p


func _ready() -> void:
	top_level = true
	match id:
		"campfire":
			_ghost = Campfire.ghost(_blue)
		"lean_to":
			_ghost = Shelter.ghost(_blue)
		"torch_post":
			_ghost = TorchPost.ghost(_blue)
		"rain_catcher":
			_ghost = RainCatcher.ghost(_blue)
		"hearth":
			_ghost = Hearth.hearth_ghost(_blue)
		"bedroll":
			_ghost = Bedroll.ghost(_blue)
		"chest":
			_ghost = StorageChest.ghost(_blue)
		"rain_cover":
			_ghost = RainCover.ghost(_blue)
	add_child(_ghost)
	for n in _ghost.find_children("*", "MeshInstance3D", true, false):
		_parts.append(n)


## Moves the preview in front of `from`, facing `forward`, and rechecks the spot.
func follow(from: Vector3, forward: Vector3) -> void:
	var spot: Vector3 = from + forward * SIZES[id].distance
	spot.y = _surface(spot.x, spot.z)
	global_position = spot
	rotation.y = atan2(-forward.x, -forward.z)  # open side (local +Z) toward the hero
	var ok := _fits(spot)
	if ok != valid or not _painted:
		_painted = true
		valid = ok
		for m in _parts:
			m.material_override = _blue if ok else _red


## The top of whatever's underfoot: the ground, or a stone floor built on it
## (like the Sanctum's), so things sit on the floor instead of inside it.
func _surface(x: float, z: float) -> float:
	var ground := Game.ground_at(x, z)
	var query := PhysicsRayQueryParameters3D.create(Vector3(x, ground + 2.5, z), Vector3(x, ground - 0.5, z), 1)
	if Game.player:
		query.exclude = [Game.player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return maxf(ground, hit.position.y) if not hit.is_empty() else ground


func _fits(spot: Vector3) -> bool:
	var size: Dictionary = SIZES[id]
	var radius: float = size.radius
	if spot.y < Game.WATER_LEVEL + 0.15:
		return false
	for s in get_tree().get_nodes_in_group("shelters"):
		if (s as Node3D).global_position.distance_to(spot) < size.get("shelter_gap", 3.0):
			return false
	for f in get_tree().get_nodes_in_group("campfires"):
		if (f as Node3D).global_position.distance_to(spot) < size.fire_gap:
			return false
	if size.get("poles", false):
		# Something to stand over things (a rain cover): only the corners matter.
		for c in _corners(spot, radius):
			if absf(_surface(c.x, c.z) - spot.y) > 0.4 or not _clear(c, 0.15):
				return false
		for n in get_tree().get_nodes_in_group("rain_covers"):
			if (n as Node3D).global_position.distance_to(spot) < radius * 2.0:
				return false
		return true
	for k in 6:
		var a := TAU * k / 6.0
		if absf(_surface(spot.x + cos(a) * radius, spot.z + sin(a) * radius) - spot.y) > 0.3:
			return false
	for group in ["torches", "usables"]:
		for n in get_tree().get_nodes_in_group(group):
			if not n is Campfire and (n as Node3D).global_position.distance_to(spot) < radius + 0.7:
				return false
	# A rain cover's poles mustn't end up in the middle of it.
	for n in get_tree().get_nodes_in_group("rain_covers"):
		for c in _corners((n as Node3D).global_position, RainCover.HALF, (n as Node3D).rotation.y):
			if Vector2(c.x - spot.x, c.z - spot.z).length() < radius + 0.15:
				return false
	return _clear(spot, radius)


## Nothing solid in a footprint, a little above the ground so the ground (or
## floor) itself doesn't count.
func _clear(spot: Vector3, radius: float) -> bool:
	var probe := SphereShape3D.new()
	probe.radius = radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = probe
	query.transform = Transform3D(Basis(), spot + Vector3(0, radius + 0.25, 0))
	query.collision_mask = 1
	if Game.player:
		query.exclude = [Game.player.get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


func _corners(center: Vector3, half: float, yaw := INF) -> Array[Vector3]:
	if yaw == INF:
		yaw = rotation.y
	var out: Array[Vector3] = []
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			out.append(center + Basis(Vector3.UP, yaw) * Vector3(sx * half, 0, sz * half))
	return out


static func _ghost_mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(color, 0.45)
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 0.6
	return m
