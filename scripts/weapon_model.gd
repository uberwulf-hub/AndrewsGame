class_name WeaponModel
extends RefCounted
## Builds a procedural low-poly gun for a WeaponData. Guns point down -Z; the muzzle
## position is stored as the "muzzle" meta on the returned node.

const SHAPES := {
	"Rifle": {"body": 0.55, "barrel": 0.4, "stock": true, "scope": false, "drum": false, "wide": false},
	"Hand Cannon": {"body": 0.32, "barrel": 0.22, "stock": false, "scope": false, "drum": true, "wide": false},
	"Scattergun": {"body": 0.5, "barrel": 0.35, "stock": true, "scope": false, "drum": false, "wide": true},
	"Rune SMG": {"body": 0.4, "barrel": 0.18, "stock": false, "scope": false, "drum": true, "wide": false},
	"Sky Lance": {"body": 0.7, "barrel": 0.7, "stock": true, "scope": true, "drum": false, "wide": false},
}


static func build(w: WeaponData) -> Node3D:
	var root := Node3D.new()
	var shape: Dictionary = SHAPES.get(w.archetype, SHAPES["Rifle"])
	var body_len: float = shape["body"]
	var barrel_len: float = shape["barrel"]
	var wide: bool = shape["wide"]
	var dark := MeshKit.mat(Color(0.14, 0.14, 0.17), 0.4, 0.75)
	var trim := MeshKit.mat(w.color, 0.35, 0.8)
	var rune := MeshKit.glow(WeaponData.ELEMENT_COLORS[w.element], 3.5)

	MeshKit.part(root, MeshKit.box(Vector3(0.11, 0.15, body_len)), dark, Vector3(0, 0, -body_len * 0.5))
	MeshKit.part(root, MeshKit.box(Vector3(0.12, 0.04, body_len * 0.7)), trim, Vector3(0, 0.085, -body_len * 0.5))
	MeshKit.part(root, MeshKit.box(Vector3(0.125, 0.025, body_len * 0.6)), rune, Vector3(0, 0.0, -body_len * 0.55))
	MeshKit.part(root, MeshKit.box(Vector3(0.08, 0.2, 0.09)), dark, Vector3(0, -0.14, -0.06), Vector3(-0.25, 0, 0))

	var barrel_r := 0.035 if wide else 0.045
	var offsets := [-0.035, 0.035] if wide else [0.0]
	for ox in offsets:
		MeshKit.part(root, MeshKit.cyl(barrel_r, barrel_r, barrel_len, 8), dark,
			Vector3(ox, 0.02, -body_len - barrel_len * 0.5), Vector3(PI / 2, 0, 0))
	MeshKit.part(root, MeshKit.cyl(barrel_r * 1.7, barrel_r * 1.7, 0.05, 8), trim,
		Vector3(0, 0.02, -body_len - barrel_len), Vector3(PI / 2, 0, 0))

	if shape["stock"]:
		MeshKit.part(root, MeshKit.box(Vector3(0.09, 0.13, 0.26)), trim, Vector3(0, -0.02, 0.13))
	if shape["scope"]:
		MeshKit.part(root, MeshKit.cyl(0.04, 0.04, 0.26, 8), dark, Vector3(0, 0.13, -body_len * 0.45), Vector3(PI / 2, 0, 0))
		MeshKit.part(root, MeshKit.cyl(0.03, 0.03, 0.02, 8), rune, Vector3(0, 0.13, -body_len * 0.45 - 0.14), Vector3(PI / 2, 0, 0))
	if shape["drum"]:
		MeshKit.part(root, MeshKit.cyl(0.09, 0.09, 0.1, 10), trim, Vector3(0, -0.04, -body_len * 0.45), Vector3(0, 0, PI / 2))

	root.set_meta("muzzle", Vector3(0, 0.02, -body_len - barrel_len - 0.05))
	return root
