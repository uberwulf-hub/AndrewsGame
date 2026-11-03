shader_type spatial;
// Lake water: rolling vertex waves, two scrolling normal maps for flowing ripples,
// depth-based color and transparency, and foam where the water meets the shore.
render_mode cull_disabled, specular_schlick_ggx;

uniform vec3 shallow_color : source_color = vec3(0.18, 0.58, 0.6);
uniform vec3 deep_color : source_color = vec3(0.03, 0.17, 0.28);
uniform vec3 foam_color : source_color = vec3(0.92, 0.97, 1.0);
uniform vec3 underside_color : source_color = vec3(0.25, 0.55, 0.6);
uniform float wave_height = 0.14;
uniform vec2 flow = vec2(0.035, 0.018);
uniform float absorption = 0.45;
uniform sampler2D ripple_a : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D ripple_b : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D depth_texture : hint_depth_texture, filter_linear;

varying vec3 world_pos;

float wave(vec2 p, vec2 dir, float freq, float speed) {
	return sin(dot(p, normalize(dir)) * freq + TIME * speed);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 p = world_pos.xz;
	float h = wave(p, vec2(1.0, 0.3), 0.32, 1.2) * 0.5
		+ wave(p, vec2(-0.4, 1.0), 0.57, 1.8) * 0.3
		+ wave(p, vec2(0.7, -0.8), 1.05, 2.5) * 0.2;
	VERTEX.y += h * wave_height;
	world_pos.y += h * wave_height;
}

void fragment() {
	vec2 uv = world_pos.xz;
	vec3 n1 = texture(ripple_a, uv * 0.045 + TIME * flow).rgb;
	vec3 n2 = texture(ripple_b, uv * 0.09 - TIME * flow.yx * 1.4).rgb;
	vec3 ripple = normalize(n1 + n2 - 1.0);
	NORMAL_MAP = ripple * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 0.7;
	ROUGHNESS = 0.04;
	METALLIC = 0.05;
	SPECULAR = 0.7;

	if (!FRONT_FACING) {
		// Seen from underneath: a bright, wobbly ceiling of light.
		ALBEDO = underside_color;
		EMISSION = underside_color * 0.35 * (0.8 + 0.4 * ripple.x);
		ALPHA = 0.8;
	} else {
		float raw = texture(depth_texture, SCREEN_UV).r;
		vec4 view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, raw, 1.0);
		view.xyz /= view.w;
		float thickness = max(VERTEX.z - view.z, 0.0);
		float absorb = 1.0 - exp(-thickness * absorption);
		float foam = smoothstep(0.7, 0.0, thickness) * smoothstep(0.35, 0.65, n1.r + n2.g * 0.5);
		float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
		ALBEDO = mix(mix(shallow_color, deep_color, absorb), foam_color, foam);
		ALPHA = clamp(mix(0.3, 0.96, absorb) + fresnel * 0.4 + foam, 0.0, 1.0);
	}
}
