shader_type canvas_item;
// Full-screen underwater pass: wavy refraction, blue-green tint, drifting caustic
// light from above and a darker vignette.

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform float strength : hint_range(0.0, 1.0) = 1.0;

float caustic(vec2 p, float t) {
	float c = sin(p.x * 9.0 + t * 1.3 + sin(p.y * 7.0 + t)) * sin(p.y * 11.0 - t * 1.1 + sin(p.x * 5.0 - t * 0.7));
	return pow(abs(c), 6.0);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 wobble = vec2(sin(uv.y * 28.0 + TIME * 2.1), cos(uv.x * 22.0 + TIME * 1.7)) * 0.004 * strength;
	vec3 col = textureLod(screen_texture, uv + wobble, 0.0).rgb;
	vec3 tint = vec3(0.35, 0.85, 0.95);
	col = mix(col, col * tint + vec3(0.0, 0.03, 0.05), strength);
	float light = caustic(uv * vec2(1.6, 1.0), TIME) * smoothstep(0.9, 0.0, uv.y);
	col += vec3(0.25, 0.45, 0.45) * light * 0.35 * strength;
	vec2 d = uv - 0.5;
	col *= 1.0 - dot(d, d) * 1.4 * strength;
	COLOR = vec4(col, 1.0);
}
