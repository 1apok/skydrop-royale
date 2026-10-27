shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D detail_noise : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D detail_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D macro_noise : hint_default_white, filter_linear_mipmap, repeat_enable;

uniform vec3 grass_a : source_color = vec3(0.30, 0.55, 0.16);
uniform vec3 grass_b : source_color = vec3(0.50, 0.66, 0.20);
uniform vec3 forest_col : source_color = vec3(0.20, 0.38, 0.12);
uniform vec3 sand_col : source_color = vec3(0.90, 0.80, 0.58);
uniform vec3 wet_sand_col : source_color = vec3(0.62, 0.52, 0.38);
uniform vec3 rock_col : source_color = vec3(0.47, 0.45, 0.43);
uniform vec3 rock_dark : source_color = vec3(0.30, 0.29, 0.29);
uniform vec3 dirt_col : source_color = vec3(0.52, 0.40, 0.27);
uniform vec3 snow_col : source_color = vec3(0.95, 0.97, 1.0);

varying vec3 world_pos;
varying vec3 world_nrm;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float sat(float x) { return clamp(x, 0.0, 1.0); }

void fragment() {
	vec2 uv_d = world_pos.xz * 0.11;
	vec2 uv_m = world_pos.xz * 0.006;
	float d = texture(detail_noise, uv_d).r;
	float d2 = texture(detail_noise, uv_d * 0.23 + 0.37).r;
	float m = texture(macro_noise, uv_m).r;

	vec3 grass = mix(grass_a, grass_b, sat(m * 1.6 - 0.3));
	grass *= 0.82 + d * 0.32;
	grass = mix(grass, forest_col, sat(COLOR.b * 0.0 + (m - 0.62) * 3.0) * 0.6);

	float slope = 1.0 - world_nrm.y;
	float rock_w = sat(max(COLOR.g, smoothstep(0.28, 0.42, slope + (d2 - 0.5) * 0.12)));
	float sand_w = sat(COLOR.r + (d2 - 0.5) * 0.4);
	sand_w = smoothstep(0.35, 0.65, sand_w);
	float dirt_w = smoothstep(0.3, 0.7, COLOR.b + (d - 0.5) * 0.5);
	float snow_w = smoothstep(0.4, 0.6, COLOR.a + (d2 - 0.5) * 0.3) * (1.0 - smoothstep(0.45, 0.6, slope));

	vec3 sand = mix(wet_sand_col, sand_col, smoothstep(0.2, 1.4, world_pos.y)) * (0.92 + d * 0.16);
	vec3 rock = mix(rock_dark, rock_col, d * 0.7 + d2 * 0.4);
	vec3 dirt = dirt_col * (0.8 + d * 0.35);

	vec3 col = grass;
	col = mix(col, dirt, dirt_w);
	col = mix(col, sand, sand_w);
	col = mix(col, rock, rock_w);
	col = mix(col, snow_col, snow_w);

	ALBEDO = col;
	float rough = mix(0.92, 0.75, rock_w);
	rough = mix(rough, 0.55, snow_w);
	rough = mix(rough, 0.6, sand_w * (1.0 - smoothstep(0.0, 0.8, world_pos.y)));
	ROUGHNESS = rough;
	SPECULAR = 0.35;
	NORMAL_MAP = texture(detail_normal, uv_d * mix(1.0, 0.5, rock_w)).rgb;
	NORMAL_MAP_DEPTH = mix(0.6, 1.6, rock_w);
}
