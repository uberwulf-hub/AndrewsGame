shader_type canvas_item;
// The hand-drawn map: the world's look (from the World) shows only where the
// hero has been; everywhere else is blank bark-paper. Optionally round, for
// the little map in the corner.

uniform sampler2D base_tex : filter_linear, source_color;
uniform sampler2D seen_tex : filter_linear;
uniform vec2 center_uv = vec2(0.5);
uniform float span_uv = 1.0;
uniform bool round_mask = false;
uniform vec4 paper : source_color = vec4(0.84, 0.76, 0.6, 1.0);

float grain(vec2 p) {
	return fract(sin(dot(floor(p), vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = center_uv + (UV - 0.5) * span_uv;
	bool inside = uv.x > 0.0 && uv.y > 0.0 && uv.x < 1.0 && uv.y < 1.0;
	vec3 blank = paper.rgb * (0.93 + 0.07 * grain(UV * 260.0));
	vec3 col = blank;
	if (inside) {
		float seen = smoothstep(0.25, 0.75, texture(seen_tex, uv).r);
		// Charcoal-smudged edge where the known world meets the blank.
		float edge = seen * (1.0 - seen) * 4.0;
		col = mix(blank, texture(base_tex, uv).rgb, seen) * (1.0 - 0.35 * edge);
	}
	float a = 1.0;
	if (round_mask) {
		float d = length(UV - 0.5) * 2.0;
		a = 1.0 - smoothstep(0.95, 1.0, d);
		col *= mix(1.0, 0.55, smoothstep(0.82, 1.0, d));
	} else {
		vec2 e = min(UV, 1.0 - UV);
		col *= mix(0.6, 1.0, smoothstep(0.0, 0.06, min(e.x, e.y)));
	}
	COLOR = vec4(col, a);
}
