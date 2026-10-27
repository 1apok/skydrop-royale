shader_type spatial;
render_mode cull_disabled, skip_vertex_transform, diffuse_lambert_wrap, specular_disabled;

uniform sampler2D height_map : filter_linear;
uniform sampler2D splat_map : filter_linear;
uniform float map_size = 800.0;
uniform vec3 cam_pos = vec3(0.0);
uniform float radius = 40.0;
uniform vec3 base_col : source_color = vec3(0.18, 0.40, 0.08);
uniform vec3 tip_col : source_color = vec3(0.62, 0.78, 0.25);
uniform vec3 dry_col : source_color = vec3(0.78, 0.72, 0.35);

varying float v_tip;
varying float v_var;

void vertex() {
	vec3 inst = MODEL_MATRIX[3].xyz;
	vec3 local = mat3(MODEL_MATRIX) * VERTEX;
	vec2 span = vec2(radius * 2.0);
	vec2 rel = mod(inst.xz - cam_pos.xz + radius, span) - radius;
	vec2 wxz = cam_pos.xz + rel;
	vec2 uv = wxz / map_size + 0.5;
	float h = texture(height_map, uv).r;
	vec4 s = texture(splat_map, uv);
	float allowed = (1.0 - clamp(s.r + s.g + s.b * 0.8 + s.a, 0.0, 1.0)) * step(0.6, h);
	float fade = 1.0 - smoothstep(radius * 0.6, radius, length(rel));
	float sc = allowed * fade;
	v_tip = clamp(VERTEX.y / 0.6, 0.0, 1.0);
	v_var = fract(sin(dot(inst.xz, vec2(12.9898, 78.233))) * 43758.5453);
	float sway = sin(TIME * 1.7 + wxz.x * 0.21 + wxz.y * 0.17) * 0.12 + sin(TIME * 3.1 + wxz.x * 0.7) * 0.04;
	vec3 world = vec3(wxz.x, h, wxz.y) + local * sc;
	world.x += sway * v_tip * v_tip * sc;
	world.z += sway * 0.6 * v_tip * v_tip * sc;
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
}

void fragment() {
	vec3 c = mix(base_col, tip_col, v_tip);
	c = mix(c, dry_col, smoothstep(0.7, 1.0, v_var) * 0.6);
	ALBEDO = c * (0.55 + 0.45 * v_tip);
	BACKLIGHT = vec3(0.35, 0.45, 0.15) * v_tip;
	ROUGHNESS = 0.9;
}
