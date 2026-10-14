shader_type spatial;
render_mode cull_disabled, shadows_disabled;
// Пучки травы (рисуются тысячами одной пачкой). Качаются на ветру,
// у корня темнее, к кончикам светлее. В тумане войны темнеют.

uniform vec3 root_col : source_color = vec3(0.12, 0.18, 0.06);
uniform vec3 tip_a : source_color = vec3(0.32, 0.42, 0.14);
uniform vec3 tip_b : source_color = vec3(0.45, 0.44, 0.18);
uniform float wind = 0.18;
uniform sampler2D fog_tex : filter_linear, repeat_disable;
uniform vec4 fog_rect = vec4(-120.0, -70.0, 240.0, 140.0);
uniform float fog_dark = 0.0;

varying vec3 wpos;
varying float h;

void vertex() {
	h = clamp(VERTEX.y / 0.8, 0.0, 1.0);
	vec3 base = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float t = TIME * 1.6 + base.x * 0.13 + base.z * 0.09;
	VERTEX.x += sin(t) * wind * h * h;
	VERTEX.z += cos(t * 0.8) * wind * 0.6 * h * h;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float r = fract(sin(dot(floor(wpos.xz * 0.5), vec2(12.9898, 78.233))) * 43758.5453);
	vec3 tip = mix(tip_a, tip_b, r);
	vec3 col = mix(root_col, tip, h);
	float vis = texture(fog_tex, (wpos.xz - fog_rect.xy) / fog_rect.zw).r;
	float fogk = (1.0 - vis) * step(0.001, fog_dark);
	col = mix(col, vec3(dot(col, vec3(0.3, 0.59, 0.11))) * vec3(0.8, 0.88, 1.0), fogk * 0.7);
	ALBEDO = col * (1.0 - fog_dark * (1.0 - vis));
	ROUGHNESS = 0.9;
	// травинки освещаются как земля под ними (иначе обратная сторона чёрная)
	NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
}
