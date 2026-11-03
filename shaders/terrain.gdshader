shader_type spatial;
// Ground: the painted base color (grass, sand, snow, forest soil) broken up by
// noise at several scales - uneven brightness, bare dirt patches in the grass,
// damp dark areas, and a speckle of pebbles and specks - plus a rough bump.

uniform sampler2D noise_large : repeat_enable, filter_linear_mipmap;
uniform sampler2D noise_med : repeat_enable, filter_linear_mipmap;
uniform sampler2D noise_fine : repeat_enable, filter_linear_mipmap;
uniform sampler2D noise_normal : hint_normal, repeat_enable, filter_linear_mipmap;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 base = COLOR.rgb;
	vec2 p = world_pos.xz;
	float large = texture(noise_large, p * 0.007).r;
	float med = texture(noise_med, p * 0.045).r;
	float fine = texture(noise_fine, p * 0.33).r;
	float speck = texture(noise_fine, p * 1.9 + vec2(17.0, 3.0)).r;

	// Uneven brightness and hue drift.
	vec3 c = base * mix(0.8, 1.16, med) * mix(0.92, 1.06, fine);
	c = mix(c, c * vec3(1.06, 1.0, 0.86), smoothstep(0.55, 0.8, large) * 0.5);

	// Bare dirt worn through the grass, in irregular patches.
	float grassy = smoothstep(0.0, 0.08, base.g - base.r);
	float dirt = smoothstep(0.64, 0.78, large * 0.65 + med * 0.35) * grassy;
	vec3 dirt_col = mix(vec3(0.3, 0.23, 0.15), vec3(0.44, 0.35, 0.23), fine);
	c = mix(c, dirt_col * mix(0.8, 1.1, med), dirt * 0.85);

	// Damp, darker, mossier hollows.
	float damp = smoothstep(0.6, 0.82, 1.0 - large);
	c = mix(c, c * vec3(0.72, 0.84, 0.68), damp * 0.5);

	// Impurities: light pebbles and dark specks.
	c = mix(c, vec3(0.56, 0.53, 0.49), smoothstep(0.8, 0.84, speck) * 0.55);
	c = mix(c, c * 0.5, smoothstep(0.22, 0.17, speck) * 0.6);

	ALBEDO = c;
	ROUGHNESS = 0.96;
	NORMAL_MAP = texture(noise_normal, p * 0.22).rgb;
	NORMAL_MAP_DEPTH = 0.7;
}
