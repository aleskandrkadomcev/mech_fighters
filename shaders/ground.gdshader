shader_type spatial;
// Земля карты. Фото-текстуры (трава, грунт, грязь с колеями, сухая грязь, камни, бетон баз) лежат
// одной пачкой слоёв (Art.ground_arrays) и смешиваются по маскам, которые рисует main.gd:
//   ground_tex: красный = дорога по линии, зелёный = площадка базы, синий = площадка точки интереса;
//   biome_tex:  красный = сухая грязь, зелёный = грунт, синий = камни (остальное трава);
//   ruts_tex:   красный = колеи вдоль линий, зелёный = лужи.
// Бегущие тени облаков считаются здесь же. Цвета подогнаны под цель (docs/targets).
// Если текстур нет (проверки без окна), земля рисуется формулами. В тумане войны темнеет.
//
// Графика (Cfg.graphics): main.gd при старте боя вставляет после первой строки
//   GFX_MID — средние: один масштаб текстур, лужи без ряби и бликов, рельеф только крупный;
//   GFX_LOW — низкие: то же, плюс без рельефа (и карт нормалей), без теней облаков, небо в лужах не плывёт.
// Без них (высокие) всё как задумано.
#if defined(GFX_MID) || defined(GFX_LOW)
#define GFX_ONE_SCALE
#define GFX_NO_RIPPLE
#endif

uniform sampler2D fog_tex : filter_linear, repeat_disable;
uniform vec4 fog_rect = vec4(-120.0, -70.0, 240.0, 140.0);
uniform float fog_dark = 0.0;

uniform sampler2D ground_tex : filter_linear, repeat_disable;
uniform sampler2D biome_tex : filter_linear, repeat_disable;
uniform sampler2D ruts_tex : filter_linear, repeat_disable;
uniform sampler2DArray tex_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray tex_normal : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float use_tex = 0.0;

// оттенки слоёв под палитру цели и общая яркость земли
uniform vec3 tint_grass : source_color = vec3(0.84, 0.76, 0.56);
uniform vec3 tint_dirt : source_color = vec3(0.86, 0.80, 0.74);
uniform vec3 tint_mud : source_color = vec3(1.0, 0.88, 0.72);
uniform vec3 tint_dry : source_color = vec3(0.80, 0.74, 0.68);
uniform vec3 tint_rock : source_color = vec3(0.80, 0.76, 0.66);
uniform vec3 tint_conc : source_color = vec3(0.64, 0.62, 0.58);
uniform float gain = 0.62;
uniform float mud_gain = 1.6;              // грязь на фото тёмная, на дороге её светлее
uniform float normal_depth = 1.5;          // рельеф фото-текстур (камешки, трещины, протекторы)
uniform float relief = 1.0;                // крупный рельеф: бугры, кочки, колеи-жёлоба
uniform float puddles = 1.0;
uniform float cloud_shadow = 0.28;
uniform vec3 sky_reflect : source_color = vec3(0.62, 0.6, 0.56);   // небо в лужах (тёплое вечернее)
uniform float sky_reflect_power = 0.42;
uniform vec3 sun_dir = vec3(0.41, 0.56, -0.72);        // откуда светит солнце (main.gd)
uniform vec3 glint_col : source_color = vec3(1.0, 0.86, 0.62);
uniform float glint = 1.6;                              // блик солнца на ряби луж

// цвета для рисования формулами (если текстур нет)
uniform vec3 grass_a : source_color = vec3(0.13, 0.20, 0.07);
uniform vec3 grass_b : source_color = vec3(0.24, 0.27, 0.10);
uniform vec3 dirt : source_color = vec3(0.23, 0.18, 0.12);
uniform vec3 road : source_color = vec3(0.30, 0.26, 0.20);
uniform vec3 concrete : source_color = vec3(0.30, 0.31, 0.32);
uniform vec3 metal : source_color = vec3(0.20, 0.22, 0.25);

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

// то же, но 3 слоя шума: для масок, где мелочь не видна
float fbm3(vec2 p) {
	float v = vnoise(p) * 0.5;
	v += vnoise(p * 2.03 + vec2(17.1, 9.3)) * 0.25;
	v += vnoise(p * 4.12 + vec2(3.7, 41.0)) * 0.125;
	return v / 0.875;
}

// линии панелей на бетоне и металле
float panels(vec2 p, vec2 cell) {
	vec2 g = abs(fract(p / cell) - 0.5) * cell;
	float w = 0.05;
	return 1.0 - smoothstep(cell.x * 0.5 - w, cell.x * 0.5 - w * 0.4, max(g.x, g.y * cell.x / cell.y));
}

// высота земли (м) для рельефа: бугры ~8 м, кочки ~1 м, мелкая неровность. Сама земля плоская,
// по высоте считается только наклон: низкое солнце освещает склоны и кладёт тень на обратные
float relief_h(vec2 q) {
#ifdef GFX_MID
	return (vnoise(q * 0.13) - 0.5) * 0.9 + (vnoise(q * 0.9) - 0.5) * 0.18;
#else
	return (fbm3(q * 0.13) - 0.5) * 0.9 + (vnoise(q * 0.9) - 0.5) * 0.18 + (vnoise(q * 3.1) - 0.5) * 0.05;
#endif
}

// слой текстуры: tile = сколько метров на один повтор. Там, где k = 1, берётся второй, крупный масштаб
// со сдвигом: так не видно, что текстура повторяется. Производные считаются заранее (можно звать внутри if)
vec4 layer_tex(sampler2DArray t, vec2 p, float tile, float id, float k, vec2 dx, vec2 dy) {
	vec2 uv = p / tile;
	vec4 a = textureGrad(t, vec3(uv, id), dx / tile, dy / tile);
#ifdef GFX_ONE_SCALE
	return a;
#else
	vec4 b = textureGrad(t, vec3(uv * 0.57 + vec2(0.31, 0.77), id), dx * 0.57 / tile, dy * 0.57 / tile);
	return mix(a, b, k);
#endif
}

// карта нормалей слоя (на низкой графике её нет: земля без мелкого рельефа)
#ifdef GFX_LOW
#define NORMAL_TEX(tile, id) vec3(0.5, 0.5, 1.0)
#else
#define NORMAL_TEX(tile, id) layer_tex(tex_normal, p, tile, id, k, dx, dy).rgb
#endif

void fragment() {
	vec2 p = wpos.xz;
	vec2 muv = (p - fog_rect.xy) / fog_rect.zw;
	vec4 gm = texture(ground_tex, muv);
#ifdef GFX_LOW
	float mid = fbm3(p * 0.18 + 7.0);
#else
	float mid = fbm(p * 0.18 + 7.0);
#endif
	float edge_noise = (mid - 0.5) * 2.0;
	float road_k = smoothstep(0.32, 0.62, gm.r + edge_noise * 0.12);
	float pad = smoothstep(0.3, 0.6, gm.g + edge_noise * 0.08);
	float ppad = smoothstep(0.45, 0.6, gm.b);
	vec3 col;
	vec3 nmap = vec3(0.5, 0.5, 1.0);
	vec3 nw = vec3(0.0, 1.0, 0.0);      // наклон земли в мире
	float rough = 0.95;
	float spec = 0.5;
	vec3 sky = vec3(0.0);                 // отражение неба в лужах

	if (use_tex > 0.5) {
		vec3 bio = texture(biome_tex, muv).rgb;
		vec2 wet = texture(ruts_tex, muv).rg;
		float rut = wet.r;
		float pm = wet.g;
		vec2 dx = dFdx(p);
		vec2 dy = dFdy(p);
		float k = smoothstep(0.35, 0.65, vnoise(p * 0.045));
		// веса слоёв: маски с рваными краями
		float w_dirt = smoothstep(0.3, 0.7, max(bio.g, smoothstep(0.03, 0.3, gm.r)) + edge_noise * 0.3);
		float w_dry = smoothstep(0.3, 0.7, bio.r + edge_noise * 0.3);
		float w_rock = smoothstep(0.3, 0.7, bio.b + edge_noise * 0.25);

		// трава — основа
		vec4 a = layer_tex(tex_albedo, p, 9.0, 0.0, k, dx, dy);
		col = a.rgb * tint_grass;
		nmap = NORMAL_TEX(9.0, 0.0);
		if (w_dirt > 0.002) {
			col = mix(col, layer_tex(tex_albedo, p, 8.0, 1.0, k, dx, dy).rgb * tint_dirt, w_dirt);
			nmap = mix(nmap, NORMAL_TEX(8.0, 1.0), w_dirt);
		}
		if (w_dry > 0.002) {
			col = mix(col, layer_tex(tex_albedo, p, 11.0, 3.0, k, dx, dy).rgb * tint_dry, w_dry);
			nmap = mix(nmap, NORMAL_TEX(11.0, 3.0), w_dry);
		}
		if (w_rock > 0.002) {
			vec3 rk = layer_tex(tex_albedo, p, 8.0, 4.0, k, dx, dy).rgb;
			rk = mix(vec3(dot(rk, vec3(0.3, 0.59, 0.11))), rk, 0.45);     // мох на фото слишком зелёный
			col = mix(col, rk * tint_rock, w_rock);
			nmap = mix(nmap, NORMAL_TEX(8.0, 4.0), w_rock);
		}
		// дорога: светлая укатанная сухая грязь со следами техники, немного разбитой грязи с протекторами,
		// тёмные колеи
		if (road_k > 0.002) {
			vec3 mud = layer_tex(tex_albedo, p, 6.0, 2.0, 0.0, dx, dy).rgb * tint_mud * mud_gain;
			vec3 track = layer_tex(tex_albedo, p, 12.0, 3.0, k, dx, dy).rgb * tint_dry * 1.15;
			col = mix(col, mix(track, mud, 0.3), road_k);
			rough = mix(rough, 0.72, road_k);     // укатанная дорога глаже травы: ловит солнце
			nmap = mix(nmap, NORMAL_TEX(12.0, 3.0), road_k);
			float rr = rut * road_k;
			col *= 1.0 - rr * 0.38;
			rough = mix(rough, 0.6, rr);
		}
		// лужи — по карте луж (main.gd), край неровный от шума, ничем не обрезан; вокруг мокрая тёмная кайма.
		// Вода серая (в ней отражается небо), гладкая с лёгкой рябью: ловит блик солнца
		float pe = (fbm3(p * 0.9 + 17.0) - 0.5) * 0.35;
		float damp = smoothstep(0.1, 0.45, pm + pe) * (1.0 - pad) * (1.0 - ppad);
		float puddle = smoothstep(0.45, 0.53, pm + pe) * (1.0 - pad) * (1.0 - ppad) * puddles;
		col *= 1.0 - damp * 0.3;
		col = mix(col, col * 0.25, puddle);
		// в воде отражается небо: светится само, тень на него не влияет (неба в сцене нет — подделываем)
		// облака отражаются пятнами, к краю лужи отражение слабее (там мелко и грязно)
		float core = smoothstep(0.45, 0.8, pm + pe);
#ifdef GFX_LOW
		float clouds_in_water = 0.4;
#else
		float clouds_in_water = fbm3(p * 0.25 + TIME * 0.015);
#endif
		sky = sky_reflect * sky_reflect_power * puddle * (0.45 + 0.8 * clouds_in_water) * (0.55 + 0.45 * core);
		nmap = mix(nmap, vec3(0.5, 0.5, 1.0), puddle);
		rough = mix(rough, 0.5, damp * 0.7);
		rough = mix(rough, 0.08, puddle);
		spec = mix(0.5, 0.4, puddle);
		// бетонные площадки баз: плиты со швами, масляные пятна, натёки грязи
		if (pad > 0.002) {
			vec3 conc = layer_tex(tex_albedo, p, 4.5, 5.0, k, dx, dy).rgb * tint_conc;
			conc *= 1.0 - panels(p, vec2(4.0, 4.0)) * 0.35;
			conc *= 1.0 - smoothstep(0.5, 0.78, fbm3(p * 0.45 + 3.0)) * 0.6;
			conc *= 0.8 + 0.4 * vnoise(p * 1.7);     // плиты разного тона
			conc = mix(conc, layer_tex(tex_albedo, p, 6.0, 2.0, 0.0, dx, dy).rgb * tint_mud * 0.8,
				smoothstep(0.55, 0.75, fbm3(p * 0.12 + 9.0)) * 0.6);
			col = mix(col, conc, pad);
			nmap = mix(nmap, NORMAL_TEX(4.5, 5.0), pad);
			rough = mix(rough, 0.82, pad);
		}
		// наклон земли: рельеф по шуму (кроме площадок) и колеи-жёлоба на дороге,
		// плюс рельеф фото-текстур. Лужи гладкие
#ifndef GFX_LOW
		float flat_k = max(pad, ppad);
		float h0 = relief_h(p);
		vec2 grad = vec2(relief_h(p + vec2(0.15, 0.0)) - h0, relief_h(p + vec2(0.0, 0.15)) - h0) / 0.15 * (1.0 - flat_k);
		vec2 rpx = vec2(0.25, 0.0) / fog_rect.zw;
		vec2 rpz = vec2(0.0, 0.25) / fog_rect.zw;
		grad -= vec2(texture(ruts_tex, muv + rpx).r - rut, texture(ruts_tex, muv + rpz).r - rut) / 0.25 * 0.14 * road_k;
		grad *= relief;
		vec3 tn = nmap * 2.0 - 1.0;
		nw = normalize(vec3(-grad.x + tn.x * normal_depth, 1.0, -grad.y - tn.y * normal_depth));
#endif
#ifdef GFX_NO_RIPPLE
		nw = normalize(mix(nw, vec3(0.0, 1.0, 0.0), puddle));       // вода ровная
#else
		vec2 rip = vec2(vnoise(p * 7.0 + TIME * 0.4) - 0.5, vnoise(p * 7.0 + 31.0 - TIME * 0.3) - 0.5) * 0.12
			+ vec2(vnoise(p * 23.0 - TIME * 0.9) - 0.5, vnoise(p * 23.0 + 7.0 + TIME * 0.7) - 0.5) * 0.1;
		nw = normalize(mix(nw, vec3(rip.x, 1.0, rip.y), puddle));     // вода ровная, только рябь
		// блик солнца: где рябь отражает солнце в камеру, вода искрит (на мокрой земле слабее)
		vec3 vw = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
		float g = pow(max(dot(reflect(-vw, nw), normalize(sun_dir)), 0.0), 48.0);
		sky += glint_col * glint * g * (puddle + damp * 0.15);
#endif
		col *= gain;
	} else {
		float big = fbm(p * 0.035);
		float fine = vnoise(p * 2.7);
		col = mix(grass_a, grass_b, smoothstep(0.35, 0.7, big));
		col *= 0.85 + fine * 0.3;
		float bald = smoothstep(0.58, 0.68, fbm(p * 0.09 + 31.0));
		col = mix(col, dirt * (0.85 + mid * 0.3), bald * 0.85);
		vec3 road_col = road * (0.8 + mid * 0.35) * (0.9 + fine * 0.2);
		col = mix(col, road_col, road_k);
		vec3 conc = concrete * (0.85 + mid * 0.25) * (1.0 - panels(p, vec2(4.0, 4.0)) * 0.25);
		conc *= 1.0 - smoothstep(0.62, 0.8, fbm(p * 0.5 + 3.0)) * 0.3;
		col = mix(col, conc, pad);
		rough = mix(0.95, 0.75, pad);
	}

	// металлические площадки точек интереса
	vec3 met = metal * (0.9 + vnoise(p * 2.7) * 0.15) * (1.0 - panels(p, vec2(2.0, 2.0)) * 0.35);
	col = mix(col, met, ppad);
	rough = mix(rough, 0.6, ppad);
	nw = normalize(mix(nw, vec3(0.0, 1.0, 0.0), ppad));

	// тени облаков медленно плывут по земле
#ifndef GFX_LOW
	float cl = smoothstep(0.45, 0.68, fbm3(p * 0.011 + TIME * vec2(0.010, 0.004)));
	col *= 1.0 - cl * cloud_shadow * use_tex;
#endif

	// туман войны
	float vis = texture(fog_tex, muv).r;
	float fogk = (1.0 - vis) * step(0.001, fog_dark);
	col = mix(col, vec3(dot(col, vec3(0.3, 0.59, 0.11))) * vec3(0.8, 0.88, 1.0), fogk * 0.7);
	col *= 1.0 - fog_dark * (1.0 - vis);
	ALBEDO = col;
	EMISSION = sky * (1.0 - fog_dark * (1.0 - vis)) * (1.0 - fogk * 0.5);
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	ROUGHNESS = rough;
	SPECULAR = spec;
	METALLIC = ppad * 0.3;
}
