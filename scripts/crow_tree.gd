class_name CrowTree
extends StaticBody3D
## The third marble's hiding place: a tall dead tree out in the open, where a
## pair of crows have built an enormous nest of sticks and stolen shiny things.
## The marble glints at the top. A well-timed, full sling shot (see Player's
## sling draw) knocks the whole nest down; a weak one only makes it wobble and
## the crows complain. Then you can look through what fell.

signal knocked_down
signal searched

const HEIGHT := 13.0
## How hard the stone has to fly: a full pull let go on time (shaky or perfect).
const POWER_NEEDED := 0.95

var nest: Node3D
var treasure: Treasure
var _nest_body: NestBody
var _glint: OmniLight3D
var _marble: MeshInstance3D
var _crows: Array[Node3D] = []
var _caw := 5.0
var _t := 0.0
var down := false
## Set by the World once the marble starts humming this way; before that the
## nest is wedged in too tight to come down.
var armed := false


## An open spot at the woods' edge, between the Sanctum and the hills, away
## from the other places the story has already been.
static func find_spot(avoid: Array) -> Vector3:
	var best := Vector3.INF
	var best_score := -INF
	for ring in range(40, 112, 4):
		for k in 72:
			var a := TAU * (k + 0.5) / 72.0
			var p := Vector3(cos(a), 0, sin(a)) * ring
			p.y = Game.height_at(p.x, p.z)
			if p.y < Game.WATER_LEVEL + 2.0:
				continue
			if avoid.any(func(q: Vector3): return Vector2(p.x - q.x, p.z - q.z).length() < 40.0):
				continue
			if Vector2(p.x - Game.ISLE.x, p.z - Game.ISLE.y).length() < 30.0:
				continue
			var spread := 0.0
			for j in 8:
				var b := TAU * j / 8.0
				spread = maxf(spread, absf(Game.height_at(p.x + cos(b) * 5.0, p.z + sin(b) * 5.0) - p.y))
			if spread > 1.4:
				continue
			# Open enough to see up into it, but with woods not far off.
			var close := 0
			var near := 0
			for t in Animal.trunks:
				var d := Vector2((t[0] as Vector3).x - p.x, (t[0] as Vector3).z - p.z).length()
				if d < 7.0:
					close += 1
				elif d < 25.0:
					near += 1
			if close > 0:
				continue
			var score := -spread * 2.0 + minf(near, 6) * 0.5 - absf(ring - 70.0) * 0.05
			if score > best_score:
				best_score = score
				best = p
	return best


static func build(parent: Node3D, at: Vector3) -> CrowTree:
	var t := CrowTree.new()
	t.name = "CrowTree"
	parent.add_child(t)
	t.global_position = Vector3(at.x, Game.ground_at(at.x, at.z) - 0.3, at.z)
	t.rotation.y = at.x * 0.37
	t._build()
	# Clear scattered rocks and bushes from around the trunk, where the nest lands.
	for n in parent.get_children():
		if n is StaticBody3D and n != t and String(n.name).begins_with("@"):
			if Vector2((n as Node3D).position.x - at.x, (n as Node3D).position.z - at.z).length() < 7.0:
				n.queue_free()
		elif n is MultiMeshInstance3D:
			var mm: MultiMesh = (n as MultiMeshInstance3D).multimesh
			for i in mm.instance_count:
				var x := mm.get_instance_transform(i)
				if Vector2(x.origin.x - at.x, x.origin.z - at.z).length() < 5.0:
					mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ZERO), x.origin))
	return t


func _build() -> void:
	var bark := MeshKit.mat(Color(0.42, 0.38, 0.34), 0.95)
	var pale := MeshKit.mat(Color(0.55, 0.5, 0.45), 0.95)
	# A tall, bare trunk that leans a little, with a few stubby branches.
	MeshKit.part(self, MeshKit.cyl(0.32, 0.75, HEIGHT, 9), bark, Vector3(0, HEIGHT * 0.5, 0))
	MeshKit.part(self, MeshKit.cyl(0.0, 0.34, 2.0, 7), bark, Vector3(0, HEIGHT + 0.8, 0), Vector3(0.12, 0, 0.05))
	for root in 5:
		var a := TAU * root / 5.0 + 0.3
		MeshKit.part(self, MeshKit.cyl(0.08, 0.3, 1.8, 6), bark, Vector3(cos(a) * 0.75, 0.35, sin(a) * 0.75), Vector3(sin(a) * 1.1, 0, -cos(a) * 1.1))
	var branches := [[5.5, 0.4, 3.2], [7.6, 2.4, 2.6], [9.4, 4.3, 2.4], [11.2, 1.1, 2.2], [12.2, 3.4, 1.8]]
	for b in branches:
		var a: float = b[1]
		var length: float = b[2]
		var dir := Vector3(cos(a), 0.75, sin(a)).normalized()
		var mi := MeshKit.part(self, MeshKit.cyl(0.05, 0.16, length, 6), pale if b[0] > 9.0 else bark, Vector3(0, b[0], 0) + dir * length * 0.5)
		mi.basis = Basis(Quaternion(Vector3.UP, dir))
	var col := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.6
	cyl.height = HEIGHT
	col.shape = cyl
	col.position.y = HEIGHT * 0.5
	add_child(col)
	_build_nest()
	_build_crows()


func _build_nest() -> void:
	nest = Node3D.new()
	nest.name = "Nest"
	nest.position = Vector3(0, HEIGHT + 0.2, 0)
	add_child(nest)
	var sticks := MeshKit.mat(Color(0.36, 0.27, 0.18), 1.0)
	var light_sticks := MeshKit.mat(Color(0.5, 0.4, 0.28), 1.0)
	MeshKit.part(nest, MeshKit.cyl(1.25, 0.7, 0.75, 12), sticks)
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	for k in 46:
		var a := rng.randf() * TAU
		var r := rng.randf_range(0.7, 1.35)
		var y := rng.randf_range(-0.3, 0.42)
		var mi := MeshKit.part(nest, MeshKit.box(Vector3(rng.randf_range(0.7, 1.4), 0.06, 0.06)), sticks if k % 3 else light_sticks, Vector3(cos(a) * r, y, sin(a) * r))
		mi.rotation = Vector3(rng.randf_range(-0.4, 0.4), -a + PI * 0.5 + rng.randf_range(-0.6, 0.6), rng.randf_range(-0.3, 0.3))
	# The stolen treasures peeking over the rim: the marble glints brightest.
	_marble = MeshKit.part(nest, MeshKit.sphere(0.13), MeshKit.glow(Color(0.7, 0.85, 1.0), 2.5), Vector3(0.25, 0.48, -0.15))
	MeshKit.part(nest, MeshKit.cyl(0.11, 0.11, 0.02, 10), MeshKit.mat(Color(0.85, 0.85, 0.9), 0.2, 1.0), Vector3(-0.35, 0.45, 0.2), Vector3(0.5, 0, 0.3))
	MeshKit.part(nest, MeshKit.box(Vector3(0.5, 0.03, 0.08)), MeshKit.mat(Color(0.9, 0.9, 0.95), 0.15, 1.0), Vector3(0.0, 0.47, 0.4), Vector3(0, 0.6, 0.4))
	_glint = OmniLight3D.new()
	_glint.light_color = Color(0.75, 0.88, 1.0)
	_glint.light_energy = 0.8
	_glint.omni_range = 3.0
	_glint.position = Vector3(0.25, 0.8, -0.15)
	nest.add_child(_glint)
	_nest_body = NestBody.new()
	_nest_body.tree = self
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 1.5
	shape.shape = sphere
	_nest_body.add_child(shape)
	nest.add_child(_nest_body)


func _build_crows() -> void:
	var black := MeshKit.mat(Color(0.07, 0.07, 0.09), 0.6)
	var beak := MeshKit.mat(Color(0.15, 0.14, 0.12), 0.5)
	for k in 2:
		var crow := Node3D.new()
		var body := MeshKit.part(crow, MeshKit.sphere(0.16), black)
		body.scale = Vector3(0.8, 0.75, 1.5)
		MeshKit.part(crow, MeshKit.sphere(0.1), black, Vector3(0, 0.06, -0.24))
		MeshKit.part(crow, MeshKit.cyl(0.0, 0.035, 0.12, 4), beak, Vector3(0, 0.05, -0.36), Vector3(-PI * 0.5, 0, 0))
		MeshKit.part(crow, MeshKit.box(Vector3(0.12, 0.02, 0.2)), black, Vector3(0, 0.0, 0.3))
		for side in [-1.0, 1.0]:
			var wing := Node3D.new()
			wing.name = "WingL" if side < 0 else "WingR"
			wing.position = Vector3(0.1 * side, 0.04, 0)
			crow.add_child(wing)
			MeshKit.part(wing, MeshKit.box(Vector3(0.5, 0.02, 0.22)), black, Vector3(0.25 * side, 0, 0))
		add_child(crow)
		_crows.append(crow)


func _process(delta: float) -> void:
	_t += delta
	if not down and _glint:
		_glint.light_energy = 0.6 + 0.5 * maxf(0.0, sin(_t * 2.3)) ** 6  # a twinkle now and then
	for k in _crows.size():
		var crow := _crows[k]
		var a := _t * (0.55 + k * 0.12) + k * PI
		var r := 5.5 + k * 1.5 + (6.0 if down else 0.0)
		var y := HEIGHT + 3.0 + sin(_t * 0.7 + k) * 0.8 + (2.0 if down else 0.0)
		crow.position = Vector3(cos(a) * r, y, sin(a) * r)
		crow.rotation.y = -a  # flying along the circle
		var flap := sin(_t * (9.0 if down else 5.0) + k) * 0.6
		crow.get_node("WingL").rotation.z = flap
		crow.get_node("WingR").rotation.z = -flap
	_caw -= delta
	if _caw <= 0.0 and Game.player and Game.player.global_position.distance_to(global_position) < 70.0:
		_caw = randf_range(3.5, 7.0) if down else randf_range(7.0, 14.0)
		Audio.play("crow_caw", _crows[randi() % _crows.size()], 0.0, 1.0, 0.1, 80.0)


## A stone from the sling hit the nest with `power` (see Player._fire_ray).
func hit_by_stone(power: float) -> void:
	if down:
		return
	FX.burst(nest.global_position + Vector3.UP * 0.4, Color(0.45, 0.35, 0.22), 10, 3.0, 0.06)
	Audio.play("impact_stone", nest.global_position, -4.0, 0.8)
	if power < POWER_NEEDED or not armed:
		# It only wobbles; the crows are not impressed.
		var tw := nest.create_tween()
		tw.tween_property(nest, "rotation:z", 0.12, 0.1)
		tw.tween_property(nest, "rotation:z", -0.08, 0.15)
		tw.tween_property(nest, "rotation:z", 0.0, 0.25)
		Audio.play("crow_caw", nest.global_position, 2.0, 1.1, 0.1, 80.0)
		if armed:
			Game.notify("Thunk. The nest wobbles... it'll take a full pull, let go right on time.", Color(0.95, 0.9, 0.8))
		return
	_fall()


func _fall() -> void:
	down = true
	_nest_body.queue_free()
	Audio.play("crow_caw", nest.global_position, 4.0, 0.95, 0.1, 80.0)
	FX.burst(nest.global_position, Color(0.1, 0.1, 0.12), 14, 4.0, 0.07)  # feathers everywhere
	var land := _landing()
	var tw := nest.create_tween()
	tw.tween_property(nest, "position", Vector3(land.x, land.y + 3.0, land.z), 0.25).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(nest, "rotation", Vector3(0.6, 1.2, 0.4), 1.1)
	tw.tween_property(nest, "position", land, 0.7).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_callback(func():
		Audio.play("land", nest.global_position, 4.0, 0.6)
		FX.burst(nest.global_position, Color(0.5, 0.42, 0.3), 18, 4.0, 0.08)
		_scatter()
		knocked_down.emit())
	tw.tween_property(nest, "rotation", Vector3(0.12, 1.2, 0.05), 0.3).set_trans(Tween.TRANS_BOUNCE)


## Where the nest ends up: on the ground a few steps out from the trunk.
func _landing() -> Vector3:
	var local := Vector3(2.6, 0, 1.4)
	var g := to_global(local)
	return to_local(Vector3(g.x, Game.ground_at(g.x, g.z) + 0.3, g.z))


## On the ground the treasures spill out around it, and it can be searched.
func _scatter() -> void:
	_glint.light_energy = 1.2
	if treasure == null:
		treasure = Treasure.new()
		treasure.tree = self
		nest.add_child(treasure)
		treasure.add_to_group("usables")


## Puts the nest on the ground straight away (when a saved game already got
## this far). `searched_already` leaves nothing in it.
func set_down(searched_already: bool) -> void:
	down = true
	if is_instance_valid(_nest_body):
		_nest_body.queue_free()
	nest.position = _landing()
	nest.rotation = Vector3(0.12, 1.2, 0.05)
	if searched_already:
		_marble.visible = false
		_glint.light_energy = 0.0
	else:
		_scatter()


func _search() -> void:
	_marble.visible = false
	_glint.light_energy = 0.0
	searched.emit()


## The stick ball itself, so stones (and the hero) bump into it up there.
class NestBody:
	extends StaticBody3D
	var tree: CrowTree

	func on_sling_hit(power: float) -> void:
		tree.hit_by_stone(power)

	func on_shot() -> void:
		tree.hit_by_stone(0.0)


## E on the fallen nest: dig out the marble (and some other shiny things).
class Treasure:
	extends Node3D
	var tree: CrowTree

	func use_radius() -> float:
		return 3.5

	func use_prompt() -> String:
		return "[E] Look through the nest"

	func use(_player: Player) -> void:
		remove_from_group("usables")
		tree._search()
		queue_free()
