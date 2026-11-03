shader_type spatial;
// Grass clumps: blades sway in a slow, uneven wind (more at the tips), with a
// dark root fading to a lighter tip and a little light shining through.
render_mode cull_disabled, diffuse_lambert_wrap;

uniform float wind_strength = 0.06;

void vertex() {
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float tip = clamp(VERTEX.y / 0.5, 0.0, 1.0);
	float gust = sin(TIME * 1.6 + world_pos.x * 0.32 + world_pos.z * 0.21)
		+ 0.45 * sin(TIME * 3.3 + world_pos.x * 1.1 - world_pos.z * 0.7);
	VERTEX.x += gust * wind_strength * tip * tip;
	VERTEX.z += gust * wind_strength * 0.5 * tip * tip;
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.92;
	BACKLIGHT = COLOR.rgb * 0.35;
}
