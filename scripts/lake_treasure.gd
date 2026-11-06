class_name LakeTreasure
extends Node3D
## A river stone on the lake bed, worn smooth, with a little house scratched
## into it. Dark until the Otter's dare; then it glows and trails bubbles, and
## E picks it up once you've dived close enough (not from the surface).

signal taken

const REACH := 2.8

var lit := false
var _glow: StandardMaterial3D
var _light: OmniLight3D
var _bubbles := 0.0


func use_radius() -> float:
	return 2.4


func use_prompt() -> String:
	return "[E] Take the glowing stone"


func use(_player: Player) -> void:
	if not lit:
		return
	lit = false
	remove_from_group("usables")
	Audio.play("loot_drop_2", null, -4.0, 1.2)
	taken.emit()
	queue_free()


func _ready() -> void:
	var stone := MeshKit.part(self, MeshKit.sphere(0.16, 0.12, 8, 4), MeshKit.mat(Color(0.5, 0.52, 0.5), 0.4))
	stone.scale = Vector3(1.0, 1.0, 0.75)
	_glow = MeshKit.glow(Color(0.65, 0.9, 1.0), 0.0)
	var mark := MeshKit.part(self, MeshKit.box(Vector3(0.12, 0.01, 0.09)), _glow, Vector3(0, 0.065, 0))
	mark.rotation.y = 0.4
	_light = OmniLight3D.new()
	_light.light_color = Color(0.65, 0.9, 1.0)
	_light.light_energy = 0.0
	_light.omni_range = 5.0
	_light.position.y = 0.4
	add_child(_light)


func light_up() -> void:
	lit = true
	var tw := create_tween().set_parallel()
	tw.tween_property(_glow, "emission_energy_multiplier", 4.0, 2.0)
	tw.tween_property(_light, "light_energy", 2.2, 2.0)


func _process(delta: float) -> void:
	if not lit:
		return
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.003)
	_light.light_energy = lerpf(1.4, 2.6, pulse)
	_bubbles -= delta
	if _bubbles <= 0.0:
		_bubbles = randf_range(0.8, 1.6)
		FX.burst(global_position + Vector3.UP * 0.2, Color(0.85, 0.95, 1.0), 3, 1.2, 0.04)
	# Only within reach once you've dived down to it.
	var p := Game.player
	var near := p != null and p.global_position.distance_to(global_position) < REACH
	if near != is_in_group("usables"):
		if near:
			add_to_group("usables")
		else:
			remove_from_group("usables")
