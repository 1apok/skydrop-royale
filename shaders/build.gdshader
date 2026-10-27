shader_type spatial;
render_mode diffuse_burley;

uniform int mat_type = 0; // 0 wood, 1 brick, 2 metal, 3 plaster
uniform vec3 base : source_color = vec3(0.7, 0.5, 0.3);
instance uniform float progress : hint_range(0.0, 1.0) = 1.0;
instance uniform float damage : hint_range(0.0, 1.0) = 0.0;
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

vec2 tri_uv() {
	vec3 a = abs(wnrm);
	if (a.y > a.x && a.y > a.z) return wpos.xz;
	if (a.x > a.z) return wpos.zy;
	return wpos.xy;
}

void fragment() {
	vec2 uv = tri_uv();
	float n = texture(noise_tex, uv * 0.35).r;
	vec3 c = base;
	float rough = 0.8;
	float metal = 0.0;
	if (mat_type == 0) {
		float plank = fract(uv.y * 2.0);
		float edge = smoothstep(0.0, 0.06, plank) * smoothstep(1.0, 0.94, plank);
		float grain = texture(noise_tex, vec2(uv.x * 0.08, uv.y * 3.0)).r;
		c = base * (0.75 + grain * 0.45) * mix(0.55, 1.0, edge);
	} else if (mat_type == 1) {
		vec2 b = uv * vec2(1.6, 3.4);
		b.x += step(1.0, mod(b.y, 2.0)) * 0.5;
		vec2 f = fract(b);
		float mortar = smoothstep(0.02, 0.05, f.x) * smoothstep(0.03, 0.08, f.y);
		float var = texture(noise_tex, floor(b) * 0.13).r;
		c = mix(vec3(0.82, 0.8, 0.76), base * (0.85 + var * 0.4), mortar);
		rough = 0.9;
	} else if (mat_type == 2) {
		float ridge = smoothstep(0.4, 0.5, abs(fract(uv.x * 1.5) - 0.5));
		c = base * (0.75 + n * 0.3) * (1.0 - ridge * 0.25);
		rough = 0.35 + n * 0.25;
		metal = 0.75;
	} else {
		c = base * (0.88 + n * 0.18);
		rough = 0.95;
	}
	c *= 1.0 - damage * 0.35 * smoothstep(0.4, 0.8, n);
	ALBEDO = c;
	ROUGHNESS = rough;
	METALLIC = metal;
	float building = 1.0 - progress;
	EMISSION = vec3(0.2, 0.55, 1.0) * building * 0.9;
}
