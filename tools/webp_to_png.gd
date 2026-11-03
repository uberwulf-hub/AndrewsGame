extends SceneTree
## godot_console --headless --path . -s res://tools/webp_to_png.gd -- in.webp out.png


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var img := Image.load_from_file(args[0])
	img.save_png(args[1])
	quit()
