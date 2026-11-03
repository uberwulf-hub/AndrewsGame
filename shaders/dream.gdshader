shader_type canvas_item;
// Dream look: soft focus toward the edges, a bloom haze, mood tint and saturation,
// a gentle vignette and film grain.

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform vec3 tint : source_color = vec3(1.0, 0.95, 0.85);
uniform float saturation = 1.1;
uniform float haze = 0.3;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 d = uv - 0.5;
	float edge = smoothstep(0.12, 0.75, length(d));
	vec3 col = textureLod(screen_texture, uv, edge * 3.5).rgb;
	col += textureLod(screen_texture, uv, 4.5).rgb * haze;
	float luma = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(vec3(luma), col, saturation) * tint;
	col *= 1.0 - edge * 0.5;
	float grain = fract(sin(dot(uv * (TIME + 1.0), vec2(12.9898, 78.233))) * 43758.5453) - 0.5;
	COLOR = vec4(col + grain * 0.035, 1.0);
}
