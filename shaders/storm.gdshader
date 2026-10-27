shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, fog_disabled;

uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform vec3 col_a : source_color = vec3(0.55, 0.15, 0.95);
uniform vec3 col_b : source_color = vec3(0.95, 0.35, 0.95);

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float ang = atan(wpos.z - NODE_POSITION_WORLD.z, wpos.x - NODE_POSITION_WORLD.x);
	vec2 uv = vec2(ang * 3.0, wpos.y * 0.008);
	float n = texture(noise_tex, uv + vec2(TIME * 0.03, -TIME * 0.06)).r;
	float n2 = texture(noise_tex, uv * 2.3 - vec2(TIME * 0.05, TIME * 0.02)).r;
	float fres = pow(1.0 - abs(dot(NORMAL, VIEW)), 1.5);
	vec3 c = mix(col_a, col_b, n * n2 * 1.8);
	float streak = smoothstep(0.55, 0.9, n2) * 0.6;
	ALBEDO = c + streak;
	float dist = length(VERTEX);
	float near_fade = smoothstep(2.0, 25.0, dist);
	float h_fade = 1.0 - smoothstep(40.0, 260.0, wpos.y);
	ALPHA = clamp((0.16 + n * 0.22 + fres * 0.3 + streak * 0.25) * near_fade * (0.35 + 0.65 * h_fade), 0.0, 0.75);
}
