shader_type canvas_item;
// Full-screen underwater pass: wavy refraction, blue-green tint, drifting caustic
// light from above and a darker vignette. `faint` (running out of air) blurs and
// doubles the view, drains the color and closes a dark tunnel in from the edges
// that tightens on each heartbeat (`pulse`).

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform float strength : hint_range(0.0, 1.0) = 1.0;
uniform float faint : hint_range(0.0, 1.0) = 0.0;
uniform float pulse : hint_range(0.0, 1.0) = 0.0;

float caustic(vec2 p, float t) {
	float c = sin(p.x * 9.0 + t * 1.3 + sin(p.y * 7.0 + t)) * sin(p.y * 11.0 - t * 1.1 + sin(p.x * 5.0 - t * 0.7));
	return pow(abs(c), 6.0);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 wobble = vec2(sin(uv.y * 28.0 + TIME * 2.1), cos(uv.x * 22.0 + TIME * 1.7)) * 0.004 * strength;
	float blur = faint * 3.0;
	vec3 col = textureLod(screen_texture, uv + wobble, blur).rgb;
	// Seeing double: a drifting ghost of the view on top.
	vec2 ghost = vec2(sin(TIME * 1.3), cos(TIME * 0.9)) * 0.014 * faint;
	col = mix(col, textureLod(screen_texture, uv + wobble + ghost, blur).rgb, 0.45 * faint);
	vec3 tint = vec3(0.35, 0.85, 0.95);
	col = mix(col, col * tint + vec3(0.0, 0.03, 0.05), strength);
	float light = caustic(uv * vec2(1.6, 1.0), TIME) * smoothstep(0.9, 0.0, uv.y);
	col += vec3(0.25, 0.45, 0.45) * light * 0.35 * strength;
	vec2 d = uv - 0.5;
	col *= 1.0 - dot(d, d) * 1.4 * strength;
	// Low on air: gray, a little red on each beat, and the dark closing in.
	float gray = dot(col, vec3(0.3, 0.59, 0.11));
	col = mix(col, vec3(gray), faint * 0.75);
	col = mix(col, col * vec3(1.15, 0.7, 0.7), faint * pulse * 0.5);
	float r = length(d * vec2(1.5, 1.0));
	float edge = 0.95 - faint * 0.6 - pulse * faint * 0.08;
	col *= 1.0 - smoothstep(edge - 0.3, edge + 0.12, r) * min(faint * 1.6, 1.0);
	COLOR = vec4(col, 1.0);
}
