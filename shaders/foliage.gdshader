shader_type spatial;
render_mode cull_disabled, diffuse_burley;

uniform vec3 tint : source_color = vec3(1.0);
uniform float wind = 0.08;

void vertex() {
	vec3 wp = MODEL_MATRIX[3].xyz;
	float h = max(VERTEX.y - 2.0, 0.0);
	float s = sin(TIME * 1.3 + wp.x * 0.1 + wp.z * 0.13) * wind * h * 0.12;
	VERTEX.x += s;
	VERTEX.z += s * 0.5;
}

void fragment() {
	ALBEDO = COLOR.rgb * tint;
	ROUGHNESS = 0.85;
	BACKLIGHT = COLOR.rgb * 0.35 * COLOR.a;
}
