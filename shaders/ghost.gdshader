shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded, fog_disabled;

uniform vec3 col : source_color = vec3(0.25, 0.6, 1.0);
uniform bool valid = true;

void fragment() {
	vec3 c = valid ? col : vec3(1.0, 0.25, 0.2);
	float edge = pow(1.0 - abs(dot(NORMAL, VIEW)), 2.0);
	float lines = smoothstep(0.92, 1.0, fract((UV.x + UV.y) * 8.0 - TIME));
	ALBEDO = c;
	ALPHA = 0.25 + edge * 0.5 + lines * 0.2;
}
