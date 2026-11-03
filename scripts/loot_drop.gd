class_name LootDrop
extends Area3D
## A weapon lying in the world: spinning model, rarity-colored light beam and name tag.
## Tells the player when they are in pickup range.

var weapon: WeaponData
var _model: Node3D
var _t := 0.0


## `announce` plays the rarity chime (skip it for drops placed at load or swapped).
static func spawn(parent: Node, w: WeaponData, pos: Vector3, announce := true) -> LootDrop:
	var drop := LootDrop.new()
	drop.weapon = w
	parent.add_child(drop)
	drop.global_position = pos
	if announce:
		Audio.play("loot_drop_%d" % w.rarity, pos, 0.0, 1.0, 0.0, 80.0)
	return drop


func _ready() -> void:
	collision_layer = 8
	collision_mask = 2
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 1.8
	shape.shape = sphere
	add_child(shape)

	var color := weapon.color
	_model = WeaponModel.build(weapon)
	_model.position.y = 0.8
	_model.scale = Vector3.ONE * 1.4
	add_child(_model)

	var beam_height := 3.0 + weapon.rarity * 1.5
	var beam := MeshKit.part(self, MeshKit.cyl(0.03, 0.12, beam_height, 8),
		MeshKit.glow(Color(color, 0.35), 3.0, true), Vector3(0, beam_height * 0.5, 0))
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 1.5
	light.omni_range = 4.0
	light.position.y = 1.0
	add_child(light)

	var label := Label3D.new()
	label.text = weapon.display_name
	label.modulate = color
	label.font_size = 32
	label.outline_size = 10
	label.pixel_size = 0.006
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position.y = 1.7
	add_child(label)

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _process(delta: float) -> void:
	_t += delta
	_model.rotation.y += delta * 1.5
	_model.position.y = 0.8 + sin(_t * 2.0) * 0.12


func _on_body_entered(body: Node3D) -> void:
	if body is Player:
		body.register_loot(self, true)


func _on_body_exited(body: Node3D) -> void:
	if body is Player:
		body.register_loot(self, false)
