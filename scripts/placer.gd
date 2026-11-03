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
	add_child(_ghost)
	for n in _ghost.find_children("*", "MeshInstance3D", true, false):
		_parts.append(n)


## Moves the preview in front of `from`, facing `forward`, and rechecks the spot.
func follow(from: Vector3, forward: Vector3) -> void:
	var spot: Vector3 = from + forward * SIZES[id].distance
	spot.y = Game.ground_at(spot.x, spot.z)
	global_position = spot
	rotation.y = atan2(-forward.x, -forward.z)  # open side (local +Z) toward the hero
	var ok := _fits(spot)
	if ok != valid or not _painted:
		_painted = true
		valid = ok
		for m in _parts:
			m.material_override = _blue if ok else _red


func _fits(spot: Vector3) -> bool:
	var radius: float = SIZES[id].radius
	if spot.y < Game.WATER_LEVEL + 0.15:
		return false
	for k in 6:
		var a := TAU * k / 6.0
		if absf(Game.ground_at(spot.x + cos(a) * radius, spot.z + sin(a) * radius) - spot.y) > 0.3:
			return false
	for s in get_tree().get_nodes_in_group("shelters"):
		if (s as Node3D).global_position.distance_to(spot) < 3.0:
			return false
	for f in get_tree().get_nodes_in_group("campfires"):
		if (f as Node3D).global_position.distance_to(spot) < SIZES[id].fire_gap:
			return false
	# Anything solid in the footprint, a little above the ground so the ground
	# itself doesn't count.
	var probe := SphereShape3D.new()
	probe.radius = radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = probe
	query.transform = Transform3D(Basis(), spot + Vector3(0, radius + 0.25, 0))
	query.collision_mask = 1
	if Game.player:
		query.exclude = [Game.player.get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


static func _ghost_mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(color, 0.45)
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 0.6
	return m
