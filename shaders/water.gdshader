shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D depth_tex : hint_depth_texture, filter_linear;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D wave_normal_a : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D wave_normal_b : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec3 shallow_col : source_color = vec3(0.12, 0.78, 0.78);
uniform vec3 deep_col : source_color = vec3(0.02, 0.18, 0.38);
uniform float wave_height = 0.35;
uniform float clarity = 6.0;

varying vec3 wpos;

float wave(vec2 p, vec2 dir, float freq, float speed, float t) {
	return sin(dot(p, normalize(dir)) * freq + t * speed);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float t = TIME;
	float h = wave(wpos.xz, vec2(1.0, 0.3), 0.08, 1.1, t) * 0.6
		+ wave(wpos.xz, vec2(-0.4, 1.0), 0.13, 1.6, t) * 0.3
		+ wave(wpos.xz, vec2(0.7, -0.8), 0.31, 2.3, t) * 0.12;
	VERTEX.y += h * wave_height;
	wpos.y += h * wave_height;
}

void fragment() {
	vec2 uv1 = wpos.xz * 0.035 + vec2(TIME * 0.018, TIME * 0.011);
	vec2 uv2 = wpos.xz * 0.06 - vec2(TIME * 0.013, -TIME * 0.02);
	vec3 n1 = texture(wave_normal_a, uv1).rgb;
	vec3 n2 = texture(wave_normal_b, uv2).rgb;
	NORMAL_MAP = normalize(mix(n1, n2, 0.5));
	NORMAL_MAP_DEPTH = 0.9;

	float raw_depth = texture(depth_tex, SCREEN_UV).r;
	vec4 ndc = vec4(SCREEN_UV * 2.0 - 1.0, raw_depth, 1.0);
	vec4 view = INV_PROJECTION_MATRIX * ndc;
	view.xyz /= view.w;
	float scene_dist = -view.z;
	float water_dist = -VERTEX.z;
	float thickness = max(scene_dist - water_dist, 0.0);

	float depth_f = clamp(1.0 - exp(-thickness / clarity), 0.0, 1.0);
	vec2 distort = (NORMAL_MAP.xy - 0.5) * 0.03 * (1.0 - exp(-thickness * 0.5));
	vec3 refr = textureLod(screen_tex, SCREEN_UV + distort, 1.0).rgb;
	vec3 water = mix(shallow_col, deep_col, depth_f);
	vec3 col = mix(refr * shallow_col * 1.4, water, clamp(depth_f * 1.15, 0.0, 1.0));

	float foam = 1.0 - smoothstep(0.0, 0.9, thickness);
	float foam_n = texture(wave_normal_a, wpos.xz * 0.2 + TIME * 0.05).r;
	foam *= smoothstep(0.35, 0.65, foam_n + foam * 0.5);
	col = mix(col, vec3(0.95, 0.98, 1.0), foam * 0.85);

	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	ALBEDO = col * (1.0 - fres * 0.4);
	ROUGHNESS = mix(0.04, 0.5, foam);
	METALLIC = 0.0;
	SPECULAR = 0.6;
	EMISSION = col * 0.05;
}
