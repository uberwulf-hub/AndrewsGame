extends SceneTree
## Renders all generated audio into the project.
##   Sound effects -> res://audio/generated/<name>_<n>.wav
##   Music         -> res://audio/music/<theme>.wav
## Usage:
##   godot --headless --path . --script res://tools/render_audio.gd -- --sfx
##   godot --headless --path . --script res://tools/render_audio.gd -- --music [--only=wilds]


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var only := ""
	for arg in args:
		if arg.begins_with("--only="):
			only = arg.get_slice("=", 1)
	if args.has("--sfx") or args.has("--all"):
		_render_sfx(only)
	if args.has("--music") or args.has("--all"):
		_render_music(only)
	quit()


func _render_sfx(only: String) -> void:
	var dir := ProjectSettings.globalize_path("res://audio/generated")
	DirAccess.make_dir_recursive_absolute(dir)
	var recipes := SfxRecipes.new()
	var started := Time.get_ticks_msec()
	var files := 0
	for sound in SfxRecipes.SOUNDS:
		if only != "" and sound != only:
			continue
		var variants: int = SfxRecipes.SOUNDS[sound][0]
		for v in variants:
			var synth := recipes.build(sound, v)
			synth.normalize(0.85 if sound.begins_with("loop_") else 0.9)
			synth.save("%s/%s_%d.wav" % [dir, sound, v + 1], sound.begins_with("loop_"))
			files += 1
	print("Rendered %d sound files in %.1fs" % [files, (Time.get_ticks_msec() - started) / 1000.0])


func _render_music(only: String) -> void:
	var dir := ProjectSettings.globalize_path("res://audio/music")
	DirAccess.make_dir_recursive_absolute(dir)
	for theme in MusicThemes.THEMES + ["dream"]:
		if only != "" and theme != only:
			continue
		var started := Time.get_ticks_msec()
		var synth := MusicThemes.compose(theme)
		synth.save("%s/%s.wav" % [dir, theme])
		print("Rendered music '%s' in %.1fs" % [theme, (Time.get_ticks_msec() - started) / 1000.0])
