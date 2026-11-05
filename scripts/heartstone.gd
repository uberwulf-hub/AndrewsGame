class_name Heartstone
extends Node3D
## The small pale stone on the Sanctum's altar. When it has a memory to give
## back (the World puts it in the "usables" group then), E touches it.

signal touched


func use_radius() -> float:
	return 2.6


func use_prompt() -> String:
	return "[E] Touch the heartstone"


func use(_player: Player) -> void:
	touched.emit()
