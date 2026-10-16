shader_type spatial;
// Всё на карте, кроме земли: стены, скалы, постройки, мачты, провода.
// Фактура рисуется формулами по мировым координатам, без картинок:
//   mode 0 — бетон с панелями и грязью снизу
//   mode 1 — камень с мхом сверху
//   mode 2 — металл с мелкими панелями
//   mode 3 — светящаяся полоса (цвет glow)
// В тумане войны темнеет (кроме свечения: огни видно издалека, но тоже тусклее).
// Если заданы текстуры (use_tex = 1), фактура берётся из картинок assets/textures (цвет, рельеф, шероховатость).
// crack: трещины на разрушаемой стене (0 = целая, 1 = вся в трещинах).
// obj_space = 1: текстура по координатам самого предмета (доски идут вдоль ящика, а не по сетке мира).

uniform vec4 albedo : source_color = vec4(0.36, 0.38, 0.42, 1.0);
uniform float roughness = 0.85;
uniform float metallic = 0.0;
uniform int mode = 0;
uniform vec4 glow : source_color = vec4(0.3, 0.8, 1.0, 1.0);
uniform float glow_power = 0.0;
uniform sampler2D fog_tex : filter_linear, repeat_disable;
uniform vec4 fog_rect = vec4(-120.0, -70.0, 240.0, 140.0);
uniform float fog_dark = 0.0;
uniform float use_tex = 0.0;
uniform float use_normal = 1.0;
uniform sampler2D tex_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_rough : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float tex_scale = 0.25;
uniform vec3 tex_tint : source_color = vec3(1.0);
uniform float tex_sat = 1.0;           // насыщенность цвета текстуры (меньше 1 — бледнее, например зелёный мох на скалах)
uniform float crack = 0.0;
uniform float obj_space = 0.0;

varying vec3 wpos;
varying vec3 wnorm;
varying vec3 lpos;
varying vec3 lnorm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	lpos = VERTEX;
	lnorm = NORMAL;
}

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vnoise3(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), f.x),
			mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y),
			mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x),
			mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm3(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += vnoise3(p) * a;
		p = p * 2.02 + vec3(5.3, 1.7, 9.1);
		a *= 0.5;
	}
	return v;
}

// линии панелей: развёртка по той оси, куда смотрит грань
float panel_lines(vec3 p, vec3 n, vec2 cell) {
	vec3 an = abs(n);
	vec2 uv = an.y > max(an.x, an.z) ? p.xz : (an.x > an.z ? p.zy : p.xy);
	vec2 g = abs(fract(uv / cell) - 0.5);
	float lx = smoothstep(0.47, 0.5, g.x);
	float ly = smoothstep(0.46, 0.5, g.y);
	return max(lx, ly);
}

// трещины: края ячеек (как у битого бетона)
float crack_lines(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = vec2(hash3(vec3(i + g, 1.0)), hash3(vec3(i + g, 7.0)));
			float d = length(g + o - f);
			if (d < d1) { d2 = d1; d1 = d; } else if (d < d2) { d2 = d; }
		}
	}
	return d2 - d1;
}

void fragment() {
	vec3 col = albedo.rgb;
	vec3 emis = vec3(0.0);
	float n = fbm3(wpos * 0.7);
	vec3 an = abs(wnorm);
	vec2 tuv = an.y > max(an.x, an.z) ? wpos.xz : (an.x > an.z ? wpos.zy : wpos.xy);
	if (obj_space > 0.5) {
		vec3 ln = abs(lnorm);
		tuv = ln.y > max(ln.x, ln.z) ? lpos.xz : (ln.x > ln.z ? lpos.zy : lpos.xy);
	}
	float rough_k = roughness;
	if (use_tex > 0.5 && mode != 3) {
		vec2 uv = tuv * tex_scale;
		col = texture(tex_albedo, uv).rgb;
		col = mix(vec3(dot(col, vec3(0.3, 0.59, 0.11))), col, tex_sat) * tex_tint;
		rough_k = texture(tex_rough, uv).r;
		if (use_normal > 0.5) {
			NORMAL_MAP = texture(tex_normal, uv).rgb;
			NORMAL_MAP_DEPTH = 1.0;
		}
		// грязь снизу и пятна, чтобы плитки не повторялись глазу
		col *= mix(0.7, 1.0, clamp(wpos.y / 1.4, 0.0, 1.0));
		col *= 0.85 + n * 0.3;
		if (mode == 1) {
			float moss = smoothstep(0.45, 0.85, wnorm.y) * smoothstep(0.42, 0.62, fbm3(wpos * 0.9 + 3.0));
			col = mix(col, vec3(0.14, 0.22, 0.08) * (0.8 + n * 0.4), moss * 0.7);
		}
	} else if (mode == 0) {
		col *= 1.0 - panel_lines(wpos, wnorm, vec2(2.0, 1.2)) * 0.35;
		col *= 0.82 + n * 0.35;
		// грязь и подтёки снизу
		col *= mix(0.62, 1.0, clamp(wpos.y / 1.6, 0.0, 1.0));
		col = mix(col, col * vec3(0.8, 0.75, 0.65), smoothstep(0.55, 0.75, fbm3(wpos * 1.6 + 4.0)) * 0.6);
	} else if (mode == 1) {
		float nn = fbm3(wpos * 1.4);
		col *= 0.7 + nn * 0.55;
		float moss = smoothstep(0.45, 0.85, wnorm.y) * smoothstep(0.42, 0.62, fbm3(wpos * 0.9 + 3.0));
		col = mix(col, vec3(0.14, 0.22, 0.08) * (0.8 + nn * 0.4), moss * 0.85);
	} else if (mode == 2) {
		col *= 1.0 - panel_lines(wpos, wnorm, vec2(0.8, 0.8)) * 0.3;
		col *= 0.88 + n * 0.22;
	} else {
		emis = glow.rgb * glow_power;
		col = glow.rgb * 0.2;
	}
	if (mode != 3 && glow_power > 0.0) {
		emis = glow.rgb * glow_power;
	}
	if (crack > 0.0 && mode != 3) {
		float e = crack_lines(tuv * 0.5 + vec2(3.1, 7.7));
		float e2 = crack_lines(tuv * 1.4 + vec2(1.3, 2.9));
		float region = smoothstep(1.0 - crack, 1.0 - crack + 0.25, fbm3(wpos * 0.35 + 11.0) + 0.25);
		float lines = max(1.0 - smoothstep(0.0, 0.03, e), (1.0 - smoothstep(0.0, 0.015, e2)) * 0.6) * region;
		col *= 1.0 - lines * 0.7;
		col *= 1.0 - crack * 0.18;
	}
	float vis = texture(fog_tex, (wpos.xz - fog_rect.xy) / fog_rect.zw).r;
	float k = 1.0 - fog_dark * (1.0 - vis);
	float fogk = (1.0 - vis) * step(0.001, fog_dark);
	col = mix(col, vec3(dot(col, vec3(0.3, 0.59, 0.11))) * vec3(0.8, 0.88, 1.0), fogk * 0.7);
	ALBEDO = col * k;
	EMISSION = emis * mix(0.6, 1.0, vis);
	ROUGHNESS = rough_k;
	METALLIC = metallic;
}
