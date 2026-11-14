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

float soft_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(grain(i), grain(i + vec2(1.0, 0.0)), f.x), mix(grain(i + vec2(0.0, 1.0)), grain(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	vec2 uv = center_uv + (UV - 0.5) * span_uv;
	bool inside = uv.x > 0.0 && uv.y > 0.0 && uv.x < 1.0 && uv.y < 1.0;
	vec3 blank = paper.rgb * (0.93 + 0.07 * grain(UV * 260.0));
	vec3 col = blank;
	if (inside) {
		// A wobbly, hand-drawn edge to what he's seen: the cell grid is broken
		// up with a little noise so it never looks blocky.
		float wobble = (soft_noise(uv * 90.0) - 0.5) * 0.35 + (soft_noise(uv * 260.0) - 0.5) * 0.15;
		float seen = smoothstep(0.32, 0.62, texture(seen_tex, uv).r + wobble);
		// Charcoal smudged along that edge.
		float edge = smoothstep(0.0, 0.5, seen) * smoothstep(1.0, 0.5, seen);
		// The land as a soft wash of colour on the paper, not a solid fill.
		vec3 land = texture(base_tex, uv).rgb;
		vec3 wash = mix(blank, land, 0.62) * (0.96 + 0.04 * grain(UV * 520.0));
		col = mix(blank, wash, seen);
		col = mix(col, vec3(0.16, 0.12, 0.09), 0.55 * edge);
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
