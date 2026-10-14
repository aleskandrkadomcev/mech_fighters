shader_type spatial;
render_mode cull_disabled;
// Кусты травы (Art.grass_bush_mesh, тысячи одной пачкой на кусок карты). Качаются на ветру,
// у корня темнее, к кончикам светлее, у каждого куста свой оттенок (цвет экземпляра).
// Ловят тени от стен и построек. В тумане войны темнеют.

// сухая олива и солома, как в цели (docs/targets/fight.webp)
uniform vec3 root_col : source_color = vec3(0.08, 0.065, 0.04);
uniform vec3 tip_a : source_color = vec3(0.33, 0.28, 0.15);
uniform vec3 tip_b : source_color = vec3(0.44, 0.35, 0.20);
uniform float wind = 0.12;
uniform sampler2D fog_tex : filter_linear, repeat_disable;
uniform vec4 fog_rect = vec4(-120.0, -70.0, 240.0, 140.0);
uniform float fog_dark = 0.0;

varying vec3 wpos;
varying float h;
varying vec3 tint;

void vertex() {
	h = UV.y;                       // высота по травинке: 0 у корня, 1 на кончике
	tint = COLOR.rgb;               // оттенок куста
	vec3 base = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float t = TIME * 1.6 + base.x * 0.13 + base.z * 0.09;
	VERTEX.x += sin(t) * wind * h * h;
	VERTEX.z += cos(t * 0.8) * wind * 0.6 * h * h;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float r = fract(sin(dot(floor(wpos.xz * 0.5), vec2(12.9898, 78.233))) * 43758.5453);
	vec3 tip = mix(tip_a, tip_b, r);
	vec3 col = mix(root_col, tip, smoothstep(0.0, 0.85, h)) * tint;
	float vis = texture(fog_tex, (wpos.xz - fog_rect.xy) / fog_rect.zw).r;
	float fogk = (1.0 - vis) * step(0.001, fog_dark);
	col = mix(col, vec3(dot(col, vec3(0.3, 0.59, 0.11))) * vec3(0.8, 0.88, 1.0), fogk * 0.7);
	ALBEDO = col * (1.0 - fog_dark * (1.0 - vis));
	ROUGHNESS = 0.9;
	// травинки освещаются как земля под ними (иначе обратная сторона чёрная)
	NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
}
