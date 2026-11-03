class_name EnemyProjectile
extends Area3D
## Glowing orb fired by Rune Sentinels. Hurts the player; pops on terrain.

var velocity := Vector3.ZERO
var damage := 10.0
var color := Color(0.95, 0.3, 0.85)
var _life := 4.0


func _ready() -> void:
	collision_layer = 0
	collision_mask = 1 | 2
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.3
	shape.shape = sphere
	add_child(shape)
	var orb := MeshKit.part(self, MeshKit.sphere(0.22), MeshKit.glow(color, 6.0))
	orb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 1.5
	light.omni_range = 3.5
	add_child(light)
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	global_position += velocity * delta
	_life -= delta
	if _life <= 0.0:
		queue_free()


func _on_body_entered(body: Node3D) -> void:
	if body is Player:
		body.take_damage(damage)
	FX.burst(global_position, color, 8, 3.0)
	Audio.play("orb_impact", global_position)
	queue_free()
