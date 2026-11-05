class_name RainCatcher
extends Node3D
## A bowl folded from birch bark, propped on three sticks tied with a vine. Dew
## and rain slowly fill it; E beside it drinks and tops up the canteen.

const FILL_TIME := 120.0  # empty to full
const USE_RADIUS := 1.8

## 0 (empty) to 1 (full).
var water := 0.6
var _surface: MeshInstance3D


static func build(parent: Node, at: Vector3) -> RainCatcher:
	var r := RainCatcher.new()
	r.position = at
	parent.add_child(r)
	return r


static func ghost(material: Material) -> Node3D:
	var g := Node3D.new()
	_shape(g, material, material)
	return g


static func _shape(parent: Node3D, wood: Material, bark: Material) -> void:
	for k in 3:
		var a := TAU * k / 3.0
		MeshKit.part(parent, MeshKit.cyl(0.025, 0.03, 0.75, 5), wood, Vector3(cos(a) * 0.22, 0.34, sin(a) * 0.22), Vector3(sin(a) * 0.3, 0, -cos(a) * 0.3))
	var bowl := MeshKit.part(parent, MeshKit.cyl(0.36, 0.2, 0.16, 12), bark, Vector3(0, 0.72, 0))
	bowl.scale = Vector3(1.0, 1.0, 0.8)


func _ready() -> void:
	add_to_group("usables")
	add_to_group("rain_catchers")
	_shape(self, MeshKit.mat(Color(0.36, 0.26, 0.17), 0.95), MeshKit.mat(Color(0.88, 0.85, 0.78), 0.9))
	var m := MeshKit.mat(Color(0.35, 0.55, 0.75), 0.05)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color.a = 0.75
	_surface = MeshKit.part(self, MeshKit.cyl(0.33, 0.33, 0.01, 12), m)
	_update_surface()


func _process(delta: float) -> void:
	if water < 1.0:
		water = minf(1.0, water + delta / FILL_TIME)
		_update_surface()


func _update_surface() -> void:
	# A pool on top of the bowl that spreads as it fills.
	_surface.visible = water > 0.05
	_surface.position.y = 0.805
	var r := lerpf(0.4, 1.0, water)
	_surface.scale = Vector3(r, 1.0, r * 0.8)


# --- Used with E (the player looks for nodes in "usables") -----------------------

func use_radius() -> float:
	return USE_RADIUS


func use_prompt() -> String:
	return "[E] Drink from the rain catcher" if water >= 0.25 else "The rain catcher is still filling..."


func use(_player: Player) -> void:
	if water < 0.25:
		return
	Game.thirst = minf(100.0, Game.thirst + water * 60.0)
	Game.canteen_sips = maxi(Game.canteen_sips, 1 + int(water * 2.0))
	water = 0.0
	_update_surface()
	Game.practice("Survival", 1.0)
	Audio.play("swim_stroke", global_position, -2.0, 1.2)
	Game.notify("Cool, clean water. You drink, and top up your canteen.", Color(0.6, 0.85, 1.0))
