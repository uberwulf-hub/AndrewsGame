shader_type spatial;
// For characters painted from a single front picture: surfaces that face
// sideways only ever got the picture's edge pixels, which stretch into streaks
// across the cheeks and the side of the head. There, use a blurred sample of
// the same spot instead (a smaller mip level), so the side reads as smooth color
// that still matches what's next to it. Front-facing surfaces stay sharp.
//
// Optional beard wrap: on the side of the jaw (between beard_top and beard_bottom
// in the picture, in front of the ear) the side takes the beard's own color, so
// a beard seen from the front carries around to the ear instead of fading to skin.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform float blur_lod = 4.0;
uniform float roughness = 0.85;
uniform float beard_strength = 0.0;
// Picture-space (UV) box of the head column and the beard's height band.
uniform vec4 beard_box = vec4(0.0);  // u_min, v_top, u_max, v_bottom
uniform vec2 beard_uv_a;  // two spots on the beard to take its color from
uniform vec2 beard_uv_b;
// Picture-space oval around the eyes, nose and mouth: left exactly as painted.
uniform vec4 front_oval = vec4(0.0);  // center u, center v, radius u, radius v

varying vec3 model_normal;

void vertex() {
	model_normal = NORMAL;
}

void fragment() {
	vec3 n = normalize(model_normal);
	float keep_out = 1.0;
	if (front_oval.z > 0.0) {
		float d = length((UV - front_oval.xy) / front_oval.zw);
		keep_out = smoothstep(0.8, 1.0, d);
	}
	// Picture faces along model Z: |n.z| near 1 is front/back, near 0 is a side.
	float side = (1.0 - smoothstep(0.18, 0.6, abs(n.z))) * keep_out;
	vec3 sharp = texture(albedo_tex, UV).rgb;
	vec3 soft = textureLod(albedo_tex, UV, blur_lod).rgb;
	vec3 color = mix(sharp, soft, side);
	if (beard_strength > 0.0) {
		vec3 beard = (textureLod(albedo_tex, beard_uv_a, 2.0).rgb + textureLod(albedo_tex, beard_uv_b, 2.0).rgb) * 0.5;
		float in_column = step(beard_box.x, UV.x) * step(UV.x, beard_box.z);
		// Under the chin and jaw (surfaces facing down) the beard reaches a bit lower.
		float under_chin = smoothstep(-0.2, -0.5, n.y);
		float bottom = beard_box.w + under_chin * 0.016;
		float in_band = smoothstep(beard_box.y, beard_box.y + 0.004, UV.y) * (1.0 - smoothstep(bottom - 0.012, bottom, UV.y));
		float before_ear = smoothstep(-0.12, 0.08, n.z);  // the ear and behind it keep their skin
		// Shape like a real beard seen from the side: a narrow sideburn right under
		// the cap, in front of the ear, widening down the jaw so that by the mouth
		// it wraps nearly to the front. `t` runs 0 (cap) to 1 (jawline).
		float t = clamp((UV.y - beard_box.y) / (beard_box.w - beard_box.y), 0.0, 1.0);
		float reach = mix(0.22, 0.9, smoothstep(0.35, 0.9, t));
		float sideways = max(1.0 - smoothstep(reach - 0.14, reach, abs(n.z)), under_chin);
		// A little of the texture's light and dark keeps it from looking flat.
		float grain = dot(soft, vec3(0.333)) / max(dot(beard, vec3(0.333)), 0.01);
		// Lifted a touch: the sides catch less light than the front the color came from.
		vec3 beard_here = beard * 1.5 * mix(1.0, clamp(grain, 0.75, 1.15), 0.4);
		color = mix(color, beard_here, beard_strength * in_column * in_band * before_ear * sideways * keep_out);
	}
	ALBEDO = color;
	ROUGHNESS = roughness;
}
