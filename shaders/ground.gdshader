shader_type spatial;
// Земля карты: трава с пятнами земли, грунтовые дороги по линиям,
// бетонные площадки баз и металлические площадки точек интереса.
// Где дороги и площадки, задаёт маленькая картинка-маска (её рисует main.gd по файлу карты):
// красный = дорога, зелёный = площадка базы, синий = площадка точки интереса.
// Остальное рисуется формулами. В тумане войны темнеет.

uniform sampler2D fog_tex : filter_linear, repeat_disable;
uniform vec4 fog_rect = vec4(-120.0, -70.0, 240.0, 140.0);
uniform float fog_dark = 0.0;

uniform vec3 grass_a : source_color = vec3(0.13, 0.20, 0.07);
uniform vec3 grass_b : source_color = vec3(0.24, 0.27, 0.10);
uniform vec3 dirt : source_color = vec3(0.23, 0.18, 0.12);
uniform vec3 road : source_color = vec3(0.30, 0.26, 0.20);
uniform vec3 concrete : source_color = vec3(0.30, 0.31, 0.32);
uniform vec3 metal : source_color = vec3(0.20, 0.22, 0.25);

uniform sampler2D ground_tex : filter_linear, repeat_disable;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += vnoise(p) * a;
		p = p * 2.03 + vec2(17.1, 9.3);
		a *= 0.5;
	}
	return v;
}

// линии панелей на бетоне и металле
float panels(vec2 p, vec2 cell) {
	vec2 g = abs(fract(p / cell) - 0.5) * cell;
	float w = 0.05;
	return 1.0 - smoothstep(cell.x * 0.5 - w, cell.x * 0.5 - w * 0.4, max(g.x, g.y * cell.x / cell.y));
}

void fragment() {
	vec2 p = wpos.xz;
	float big = fbm(p * 0.035);
	float mid = fbm(p * 0.18 + 7.0);
	float fine = vnoise(p * 2.7);

	// трава: два оттенка пятнами, мелкая рябь
	vec3 col = mix(grass_a, grass_b, smoothstep(0.35, 0.7, big));
	col *= 0.85 + fine * 0.3;
	// проплешины земли
	float bald = smoothstep(0.58, 0.68, fbm(p * 0.09 + 31.0));
	col = mix(col, dirt * (0.85 + mid * 0.3), bald * 0.85);

	// маска карты: дороги, площадки баз и точек
	vec4 gm = texture(ground_tex, (p - fog_rect.xy) / fog_rect.zw);
	float edge_noise = (mid - 0.5) * 2.0;
	float road_k = smoothstep(0.32, 0.62, gm.r + edge_noise * 0.12);
	vec3 road_col = road * (0.8 + mid * 0.35) * (0.9 + fine * 0.2);
	col = mix(col, road_col, road_k);

	// бетонные площадки баз
	float pad = smoothstep(0.3, 0.6, gm.g + edge_noise * 0.08);
	vec3 conc = concrete * (0.85 + mid * 0.25) * (1.0 - panels(p, vec2(4.0, 4.0)) * 0.25);
	conc *= 1.0 - smoothstep(0.62, 0.8, fbm(p * 0.5 + 3.0)) * 0.3;   // пятна грязи
	col = mix(col, conc, pad);

	// металлические площадки точек интереса
	float ppad = smoothstep(0.45, 0.6, gm.b);
	vec3 met = metal * (0.9 + fine * 0.15) * (1.0 - panels(p, vec2(2.0, 2.0)) * 0.35);
	col = mix(col, met, ppad);

	// туман войны
	float vis = texture(fog_tex, (p - fog_rect.xy) / fog_rect.zw).r;
	float fogk = (1.0 - vis) * step(0.001, fog_dark);
	col = mix(col, vec3(dot(col, vec3(0.3, 0.59, 0.11))) * vec3(0.8, 0.88, 1.0), fogk * 0.7);
	col *= 1.0 - fog_dark * (1.0 - vis);
	ALBEDO = col;
	ROUGHNESS = mix(0.95, 0.75, max(pad, ppad));
	METALLIC = ppad * 0.3;
}
