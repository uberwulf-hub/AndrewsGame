class_name WeaponModel
extends RefCounted
## Builds a low-poly dream tool for a WeaponData: a wisp wand, an oak sling, a
## seed horn, a jar of fireflies, or a moonbow. Made of wood, cord, horn and
## glass, with a soft glow in the tool's element color. They point down -Z
## from the hand; the "muzzle" meta is where the shot leaves from.


static func build(w: WeaponData) -> Node3D:
	var root := Node3D.new()
	var wood := MeshKit.mat(Color(0.42, 0.28, 0.16), 0.9)
	var pale := MeshKit.mat(Color(0.7, 0.58, 0.4), 0.85)
	var cord := MeshKit.mat(w.color.lerp(Color(0.5, 0.4, 0.3), 0.35), 0.8)  # the wrap shows the rarity
	var light := MeshKit.glow(WeaponData.ELEMENT_COLORS[w.element], 3.0)
	var muzzle := Vector3(0, 0, -0.6)
	match w.archetype:
		"Hand Cannon":
			muzzle = _sling(root, wood, cord, light)
		"Scattergun":
			muzzle = _horn(root, pale, wood, cord, light)
		"Rune SMG":
			muzzle = _jar(root, wood, cord, w)
		"Sky Lance":
			muzzle = _bow(root, wood, cord, light)
		_:
			muzzle = _wand(root, wood, cord, light)
	root.set_meta("muzzle", muzzle)
	return root


## A crooked stick with a cord wrap at the grip and a little wisp of light
## caught in a twist of twigs at the tip.
static func _wand(root: Node3D, wood: Material, cord: Material, light: Material) -> Vector3:
	MeshKit.part(root, MeshKit.cyl(0.018, 0.03, 0.72, 6), wood, Vector3(0, 0.02, -0.28), Vector3(-PI / 2 + 0.03, 0, 0.02))
	MeshKit.part(root, MeshKit.cyl(0.034, 0.034, 0.16, 6), cord, Vector3(0, 0.0, 0.0), Vector3(PI / 2, 0, 0))
	for k in 3:
		var a := TAU * k / 3.0
		MeshKit.part(root, MeshKit.cyl(0.006, 0.01, 0.12, 4), wood, Vector3(cos(a) * 0.03, 0.05 + sin(a) * 0.03, -0.62), Vector3(-PI / 2 + sin(a) * 0.5, 0, cos(a) * 0.5))
	MeshKit.part(root, MeshKit.sphere(0.04), light, Vector3(0, 0.05, -0.66))
	return Vector3(0, 0.05, -0.7)


## A forked oak branch with a leather band and a glowing stone in the pouch.
static func _sling(root: Node3D, wood: Material, cord: Material, light: Material) -> Vector3:
	MeshKit.part(root, MeshKit.cyl(0.026, 0.03, 0.2, 6), wood, Vector3(0, -0.04, 0.0))
	MeshKit.part(root, MeshKit.cyl(0.032, 0.032, 0.08, 6), cord, Vector3(0, -0.06, 0.0))
	for side in [-1.0, 1.0]:
		MeshKit.part(root, MeshKit.cyl(0.016, 0.024, 0.2, 6), wood, Vector3(side * 0.05, 0.13, 0.0), Vector3(0, 0, -side * 0.45))
		MeshKit.part(root, MeshKit.cyl(0.006, 0.006, 0.16, 4), cord, Vector3(side * 0.05, 0.22, 0.07), Vector3(PI / 2 - 0.3, 0, side * 0.6)).name = "Band"
	MeshKit.part(root, MeshKit.sphere(0.035), light, Vector3(0, 0.2, 0.12)).name = "Band"
	# Where the band ties onto the fork, and its materials, so the hero can
	# draw it back with his other hand (see Player, "the sling's band").
	root.set_meta("band_tips", [Vector3(-0.095, 0.22, 0.0), Vector3(0.095, 0.22, 0.0)])
	root.set_meta("band_mats", [cord, light])
	return Vector3(0, 0.2, -0.1)


## A curling horn, wide end forward, on a cord strap; seeds of light spray
## out of its mouth.
static func _horn(root: Node3D, horn: Material, wood: Material, cord: Material, light: Material) -> Vector3:
	MeshKit.part(root, MeshKit.cyl(0.11, 0.035, 0.5, 10), horn, Vector3(0, 0.03, -0.28), Vector3(-PI / 2, 0, 0))
	MeshKit.part(root, MeshKit.cyl(0.035, 0.02, 0.16, 8), horn, Vector3(0, 0.0, 0.03), Vector3(-PI / 2 + 0.5, 0, 0))
	for z in [-0.12, -0.36]:
		MeshKit.part(root, MeshKit.cyl(0.07 + absf(z) * 0.1, 0.07 + absf(z) * 0.1, 0.03, 10), cord, Vector3(0, 0.03, z), Vector3(PI / 2, 0, 0))
	var mouth := TorusMesh.new()
	mouth.inner_radius = 0.09
	mouth.outer_radius = 0.115
	MeshKit.part(root, mouth, light, Vector3(0, 0.03, -0.53), Vector3(PI / 2, 0, 0))
	MeshKit.part(root, MeshKit.box(Vector3(0.05, 0.12, 0.05)), wood, Vector3(0, -0.07, -0.08))
	return Vector3(0, 0.03, -0.58)


## A glass jar with a wooden lid, held out in front, full of fireflies.
static func _jar(root: Node3D, wood: Material, cord: Material, w: WeaponData) -> Vector3:
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.75, 0.9, 0.85, 0.25)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.05
	glass.metallic_specular = 1.0
	MeshKit.part(root, MeshKit.box(Vector3(0.05, 0.12, 0.05)), wood, Vector3(0, -0.07, 0.0))
	MeshKit.part(root, MeshKit.cyl(0.09, 0.09, 0.2, 10), glass, Vector3(0, 0.06, -0.16), Vector3(PI / 2, 0, 0))
	MeshKit.part(root, MeshKit.cyl(0.095, 0.095, 0.04, 10), wood, Vector3(0, 0.06, -0.04), Vector3(PI / 2, 0, 0))
	MeshKit.part(root, MeshKit.cyl(0.093, 0.093, 0.025, 10), cord, Vector3(0, 0.06, -0.08), Vector3(PI / 2, 0, 0))
	var bug := MeshKit.glow(WeaponData.ELEMENT_COLORS[w.element].lerp(Color(1.0, 0.95, 0.5), 0.4), 4.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for k in 6:
		MeshKit.part(root, MeshKit.sphere(0.015), bug, Vector3(rng.randf_range(-0.05, 0.05), 0.06 + rng.randf_range(-0.05, 0.05), -0.16 + rng.randf_range(-0.07, 0.07)))
	return Vector3(0, 0.06, -0.3)


## A bow of pale wood strung with light, an arrow nocked and ready.
static func _bow(root: Node3D, wood: Material, cord: Material, light: Material) -> Vector3:
	var z := -0.12
	MeshKit.part(root, MeshKit.cyl(0.024, 0.024, 0.12, 6), cord, Vector3(0, 0.0, z))
	for side in [-1.0, 1.0]:
		for k in 3:
			var t := (k + 0.5) / 3.0
			MeshKit.part(root, MeshKit.cyl(0.012, 0.02, 0.2, 5), wood,
				Vector3(0, side * (0.06 + t * 0.5), z + t * t * 0.18), Vector3(side * (0.25 + t * 0.6), 0, 0))
	var string := MeshKit.glow(Color(0.9, 0.95, 1.0), 2.0)
	MeshKit.part(root, MeshKit.cyl(0.003, 0.003, 0.84, 4), string, Vector3(0, 0, z + 0.2))
	MeshKit.part(root, MeshKit.cyl(0.007, 0.007, 0.62, 4), wood, Vector3(0, 0.0, z - 0.1), Vector3(PI / 2, 0, 0))
	MeshKit.part(root, MeshKit.cyl(0.0, 0.022, 0.06, 4), light, Vector3(0, 0.0, z - 0.43), Vector3(-PI / 2, 0, 0))
	return Vector3(0, 0.0, z - 0.48)
