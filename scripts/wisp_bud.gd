class_name WispBud
extends StaticBody3D
## A sleepy light curled up on top of a standing stone: a pale, dim bud that a
## dream tool's shot wakes into a warm glow. The World decides when they may
## wake (shot() is only a knock until then).

signal shot(bud: WispBud)

const SLEEP_COLOR := Color(0.62, 0.7, 0.66)
const AWAKE_COLOR := Color(1.0, 0.82, 0.5)

var awake := false
var _mat: StandardMaterial3D
var _light: OmniLight3D
var _ball: Node3D
var _t := randf() * TAU


func _ready() -> void:
	collision_layer = 4  # where shots look, with the enemies
	collision_mask = 0
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.4  # a little generous, it's a long way up
	shape.shape = sphere
	add_child(shape)
	_mat = MeshKit.glow(SLEEP_COLOR, 0.35)
	_ball = MeshKit.part(self, MeshKit.sphere(0.2, 0.36, 8, 5), _mat, Vector3.ZERO)
	_light = OmniLight3D.new()
	_light.light_color = AWAKE_COLOR
	_light.light_energy = 0.0
	_light.omni_range = 8.5
	_light.position.y = 0.25
	add_child(_light)


## Called by a dream tool's shot.
func on_shot() -> void:
	shot.emit(self)


## Wakes into a warm glow (quietly when loading a save).
func wake(fanfare := true, pitch := 1.0) -> void:
	if awake:
		return
	awake = true
	var tw := create_tween().set_parallel()
	var d := 1.2 if fanfare else 0.01
	tw.tween_property(_mat, "albedo_color", AWAKE_COLOR, d)
	tw.tween_property(_mat, "emission", AWAKE_COLOR, d)
	tw.tween_property(_mat, "emission_energy_multiplier", 2.6, d)
	tw.tween_property(_light, "light_energy", 2.0, d)
	if fanfare:
		FX.burst(global_position, AWAKE_COLOR, 18, 2.5, 0.06)
		Audio.play("loot_drop_2", global_position, 2.0, pitch, 0.0, 80.0)


## A little wobble when shot before it's ready to wake, like it rolled over.
func stir() -> void:
	var tw := create_tween()
	tw.tween_property(_ball, "scale", Vector3(1.25, 0.8, 1.25), 0.12)
	tw.tween_property(_ball, "scale", Vector3.ONE, 0.3)


func _process(delta: float) -> void:
	_t += delta
	# Asleep: a slow, faint pulse. Awake: a gentle bob and flicker.
	if awake:
		_ball.position.y = sin(_t * 1.6) * 0.05
		_light.light_energy = 1.9 + sin(_t * 5.0) * 0.12
	else:
		_mat.emission_energy_multiplier = 0.25 + 0.15 * (0.5 + 0.5 * sin(_t * 0.8))
