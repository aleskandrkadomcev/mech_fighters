extends Node3D
## Постройка: турель (3 уровня) или штаб. Числа лежат в parts.gd ("Постройки").
## Турель сама стреляет по ближайшему видимому врагу в радиусе (сначала по крипам, как в доте).
## Турель 2 уровня ещё кидает в мехов ЭМИ-гранату, турель 3 уровня бьёт по мехам навесом из осадного орудия.
## У гранаты и снаряда на земле видна метка, от них можно увернуться.
## Штаб не стреляет; когда его ломают, команда проигрывает.
## По бокам от штаба стоят два ядра (id "core"): раз в несколько секунд заряжаются и бьют молнией
## ближайшего врага, оглушая его. Пока стоит хоть одно ядро, на штабе защитный барьер — урон не проходит.

const Hitbox := preload("res://scripts/hitbox.gd")
const HpBar := preload("res://scripts/hp_bar.gd")
const Projectile := preload("res://scripts/projectile.gd")
const Art := preload("res://scripts/art.gd")
const Lob := preload("res://scripts/lob.gd")

signal destroyed(who: Node3D)
signal ruin_cleared(who: Node3D)     # развалину сломанной турели разбили: путь свободен

var id := "turret_t1"
var team := 0
var tier := 1                    # 1-3 у турелей, 0 у штаба
var hp := 1000.0
var dead := false
var ruin_hp := 0.0              # прочность развалины после смерти (у штаба развалины нет — его смерть конец боя)
var cleared := false            # развалину разбили: постройки больше нет
var _body: StaticBody3D         # тело, в которое упираются мехи
var velocity := Vector3.ZERO     # для упреждения ботов: постройки не двигаются
var seen := true
var hitbox: Area3D
var _bar: Node3D
var _head: Node3D
var _muzzle: Node3D
var _cool := 0.0
var _mats: Array = []
var _target: Node3D
var _emp_cd := 3.0               # ЭМИ-граната (турель 2 уровня)
var _mortar_cd := 3.0            # осадное орудие (турель 3 уровня)
var _mortar: Node3D              # ствол осадного орудия (поднимается при выстреле)
var last_attacker: Node = null
# ядро (Тесла)
var _orb: MeshInstance3D
var _orb_mat: StandardMaterial3D
var _halo: MeshInstance3D            # ореол вокруг шара ядра: пульсирует, при зарядке разгорается
var _rings: Array = []
var _zap_cd := 2.0
var _charge_left := 0.0
var _zap_target: Node3D
# барьер штаба
var _barrier: MeshInstance3D
var _barrier_mat: ShaderMaterial
var _barrier_on := false
var _waves: Array[Vector4] = []     # волны на куполе от попаданий: xyz — место удара, w — возраст, с
const WAVE_LIFE := 1.0
const WAVES_MAX := 4


func _ready() -> void:
	set_process(false)          # кадр нужен только штабу, пока по куполу бегут волны
	add_to_group("structures")
	add_to_group("damageable")
	hp = max_hp()
	var is_hq := id == "hq"
	var is_core := id == "core"
	# тело: в него упираются мехи (слой построек), вижен сквозь него проходит
	var body := StaticBody3D.new()
	body.collision_layer = 32
	body.collision_mask = 0
	add_child(body)
	_body = body
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	var size := 8.0 if is_hq else 3.2
	bs.size = Vector3(size, 6.0, size)
	cs.shape = bs
	cs.position = Vector3(0, 3.0, 0)
	body.add_child(cs)

	hitbox = Hitbox.new()
	hitbox.mech = self
	add_child(hitbox)

	var team_col := Cfg.player_color if team == 0 else Cfg.enemy_color
	if is_hq:
		_build_hq(team_col)
		_build_barrier(team_col)
	elif is_core:
		_build_core(team_col)
		_zap_cd = randf_range(1.5, 3.0)     # два ядра бьют не одновременно
	else:
		_build_turret(team_col)

	# склеиваем неподвижные детали в одну модель на материал (меньше вызовов отрисовки)
	var keep: Array = [_orb]
	keep.append_array(_rings)
	Art.merge_meshes(self, _mats + _glows.values(), keep)

	_bar = HpBar.new()
	_bar.color = Color(0.4, 0.9, 0.4) if team == 0 else Color(0.95, 0.25, 0.2)
	add_child(_bar)
	_bar.position = Vector3(0, 11.0 if is_hq else (7.4 if is_core else 6.4), 0)
	_bar.scale = Vector3.ONE * (2.2 if is_hq else 1.2)


func max_hp() -> float:
	return Parts.v(id, "hp")


func get_hit_radius() -> float:
	return Parts.v(id, "hit_radius")


# настоящая высота постройки
func get_hit_height() -> float:
	if id == "hq":
		return 13.0
	if id == "core":
		return 7.2
	return 5.0


func vision_radius() -> float:
	return Parts.v(id, "vision") + Cfg.structure_vision


func is_cloaked() -> bool:
	return false


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.7
	m.emission_enabled = true
	m.emission = Color.BLACK
	Art.apply_panels(m, 0.9, "plates")
	_mats.append(m)
	return m


var _glows := {}   # светящиеся материалы по цвету (одинаковые склеиваются в одну модель)


func _glow(c: Color) -> StandardMaterial3D:
	if _glows.has(c):
		return _glows[c]
	var m := StandardMaterial3D.new()
	_glows[c] = m
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = 2.2
	return m


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = Art.bevel_box(size)
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


func _cyl(parent: Node3D, r_top: float, r_bot: float, h: float, pos: Vector3, mat: Material, segs := 8, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r_top
	cm.bottom_radius = r_bot
	cm.height = h
	cm.radial_segments = segs
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


# турель: восьмигранный бетонный постамент, бронированная колонна с огнями команды,
# поворотная башня со стволами (у 1 уровня один ствол, у 2 два, у 3 три) и светящимся глазом
func _build_turret(col: Color) -> void:
	var s := 0.9 + tier * 0.13
	var armor := _mat(Color(0.38, 0.4, 0.43))
	var armor2 := _mat(Color(0.25, 0.27, 0.3))
	var dark := _mat(Color(0.07, 0.075, 0.08))
	var conc := _mat(Color(0.42, 0.42, 0.41))
	# постамент
	_cyl(self, 2.1 * s, 2.4 * s, 0.6, Vector3(0, 0.3, 0), conc, 8)
	_cyl(self, 1.6 * s, 1.9 * s, 0.5, Vector3(0, 0.85, 0), dark, 8)
	# колонна с бронеплитами
	_cyl(self, 1.0 * s, 1.25 * s, 2.6, Vector3(0, 2.4, 0), armor2, 8)
	for i in 4:
		var a := TAU * i / 4.0 + PI / 4.0
		var plate := _box(self, Vector3(0.9 * s, 2.2, 0.2), Vector3(cos(a) * 1.12 * s, 2.35, sin(a) * 1.12 * s), armor)
		plate.rotation.y = -a + PI / 2.0
	# огни уровня: сколько уровень, столько светящихся колец
	for i in tier:
		_cyl(self, 1.18 * s, 1.18 * s, 0.12, Vector3(0, 1.4 + i * 0.45, 0), _glow(col), 8)
	# поворотная башня
	_head = Node3D.new()
	_head.position = Vector3(0, 4.15, 0)
	add_child(_head)
	_cyl(_head, 1.05 * s, 1.15 * s, 0.35, Vector3(0, -0.35, 0), dark, 12)
	_box(_head, Vector3(2.0, 1.0, 2.3) * s, Vector3(0, 0.1, 0.1 * s), armor)
	# скошенный лоб
	var brow := _box(_head, Vector3(1.9 * s, 0.5 * s, 1.0 * s), Vector3(0, 0.55 * s, -0.7 * s), armor2)
	brow.rotation.x = -0.45
	# бортовые короба
	for sx in [-1.0, 1.0]:
		_box(_head, Vector3(0.45, 0.8, 1.6) * s, Vector3(1.15 * s * sx, 0.05, 0.25 * s), armor2)
		_box(_head, Vector3(0.05, 0.12, 1.2) * s, Vector3(1.39 * s * sx, 0.25 * s, 0.25 * s), _glow(col))
	# глаз-сенсор
	_box(_head, Vector3(0.7, 0.18, 0.1) * s, Vector3(0, 0.45 * s, -1.25 * s), _glow(Color(1.0, 0.3, 0.2) if team != 0 else Color(0.4, 0.9, 1.0)))
	# стволы с дульными тормозами
	var barrels := maxi(tier, 1)
	for i in barrels:
		var x := (i - (barrels - 1) * 0.5) * 0.42 * s
		_cyl(_head, 0.13 * s, 0.16 * s, 2.6 * s, Vector3(x, -0.05, -2.0 * s), dark, 8, Vector3(PI / 2, 0, 0))
		_box(_head, Vector3(0.36, 0.3, 0.45) * s, Vector3(x, -0.05, -3.25 * s), armor2)
	# короб с лентой сзади
	_box(_head, Vector3(1.4, 0.7, 0.6) * s, Vector3(0, 0.1, 1.45 * s), dark)
	_muzzle = Node3D.new()
	_muzzle.position = Vector3(0, -0.05, -3.5 * s)
	_head.add_child(_muzzle)
	if tier == 2:
		# пусковая труба ЭМИ-гранат сверху башни: голубые кольца
		var tube := _cyl(_head, 0.28 * s, 0.32 * s, 1.1 * s, Vector3(0.75 * s, 0.85 * s, 0.3 * s), dark, 10, Vector3(-0.6, 0, 0))
		_cyl(tube, 0.33 * s, 0.33 * s, 0.12, Vector3(0, 0.3, 0), _glow(Color(0.4, 0.8, 1.0)), 10)
		_cyl(tube, 0.33 * s, 0.33 * s, 0.12, Vector3(0, -0.1, 0), _glow(Color(0.4, 0.8, 1.0)), 10)
	elif tier == 3:
		# осадное орудие: толстая короткая мортира на поворотной башне, смотрит вверх
		_mortar = Node3D.new()
		_mortar.position = Vector3(0, 0.9 * s, 0.9 * s)
		_head.add_child(_mortar)
		_box(_mortar, Vector3(1.3, 0.7, 1.2) * s, Vector3(0, 0, 0), armor2)
		var barrel := _cyl(_mortar, 0.42 * s, 0.5 * s, 1.9 * s, Vector3(0, 0.75 * s, -0.35 * s), dark, 12, Vector3(-0.45, 0, 0))
		_cyl(barrel, 0.5 * s, 0.5 * s, 0.22, Vector3(0, 0.85 * s, 0), armor, 12)
		_cyl(barrel, 0.52 * s, 0.52 * s, 0.08, Vector3(0, 0.4 * s, 0), _glow(col), 12)


func _build_hq(col: Color) -> void:
	var armor := _mat(Color(0.32, 0.34, 0.37))
	var dark := _mat(Color(0.08, 0.085, 0.09))
	_box(self, Vector3(9.0, 1.4, 9.0), Vector3(0, 0.7, 0), dark)
	_box(self, Vector3(7.5, 5.0, 7.5), Vector3(0, 3.9, 0), armor)
	_box(self, Vector3(4.5, 2.4, 4.5), Vector3(0, 7.6, 0), armor)
	_box(self, Vector3(7.7, 0.3, 7.7), Vector3(0, 6.2, 0), _glow(col))
	_box(self, Vector3(0.4, 4.0, 0.4), Vector3(1.6, 10.6, 1.6), dark)
	_box(self, Vector3(1.2, 0.6, 1.2), Vector3(1.6, 12.6, 1.6), _glow(col))
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_box(self, Vector3(1.4, 6.0, 1.4), Vector3(3.9 * sx, 3.0, 3.9 * sz), dark)


# ядро штаба: бетонная плита, колонна-катушка с кольцами, сверху светящийся шар.
# Перед ударом шар разгорается и по нему бегают искры
func _build_core(col: Color) -> void:
	var armor := _mat(Color(0.34, 0.36, 0.4))
	var dark := _mat(Color(0.07, 0.075, 0.08))
	var conc := _mat(Color(0.42, 0.42, 0.41))
	_cyl(self, 2.3, 2.6, 0.6, Vector3(0, 0.3, 0), conc, 8)
	_cyl(self, 1.7, 2.0, 0.6, Vector3(0, 0.9, 0), dark, 8)
	# четыре опоры-изолятора вокруг катушки
	for i in 4:
		var a := TAU * i / 4.0 + PI / 4.0
		var leg := _box(self, Vector3(0.45, 3.2, 0.45), Vector3(cos(a) * 1.45, 2.6, sin(a) * 1.45), armor)
		leg.rotation = Vector3(sin(a) * -0.12, 0, cos(a) * 0.12)
		_box(self, Vector3(0.55, 0.18, 0.55), Vector3(cos(a) * 1.35, 4.2, sin(a) * 1.35), _glow(col))
	# катушка: тёмный стержень и кольца, от широкого к узкому
	_cyl(self, 0.45, 0.6, 4.6, Vector3(0, 3.4, 0), dark, 10)
	var ring_mat := _glow(Color(0.45, 0.8, 1.0))
	for i in 4:
		var r := 1.15 - i * 0.18
		var ring := _cyl(self, r, r, 0.16, Vector3(0, 2.2 + i * 0.75, 0), ring_mat, 14)
		_rings.append(ring)
	# шар
	_orb = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.85
	sm.height = 1.7
	sm.radial_segments = 16
	sm.rings = 8
	_orb.mesh = sm
	_orb_mat = StandardMaterial3D.new()
	_orb_mat.albedo_color = Color(0.6, 0.85, 1.0)
	_orb_mat.emission_enabled = true
	_orb_mat.emission = Color(0.45, 0.75, 1.0)
	_orb_mat.emission_energy_multiplier = 1.5
	_orb.material_override = _orb_mat
	_orb.position = Vector3(0, 6.3, 0)
	add_child(_orb)
	_halo = MeshInstance3D.new()
	var hq := QuadMesh.new()
	hq.size = Vector2.ONE
	_halo.mesh = hq
	var hm := StandardMaterial3D.new()
	hm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	hm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	hm.cull_mode = BaseMaterial3D.CULL_DISABLED
	hm.albedo_texture = Art.fx_tex("circle_05")
	hm.albedo_color = Color(0.4, 0.72, 1.0, 0.9)
	_halo.material_override = hm
	_halo.scale = Vector3.ONE * 4.0
	_halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_orb.add_child(_halo)
	# кольцо цвета команды под шаром
	_cyl(self, 0.9, 1.0, 0.22, Vector3(0, 5.45, 0), _glow(col), 14)


# защитный барьер штаба: пузырь цвета команды, как щиты в Supreme Commander. Края светятся,
# середина почти прозрачная (здание видно, окраска ~10%) с лёгким мерцанием; попадания пускают волны
func _build_barrier(col: Color) -> void:
	var sh := Shader.new()
	sh.code = """shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec3 col = vec3(0.4, 0.8, 1.0);
uniform vec4 hits[4];
uniform float fade = 1.0;
varying vec3 wpos;
varying vec3 cpos;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	cpos = wpos - MODEL_MATRIX[3].xyz;
}
float h1(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}
float vn(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	float a = mix(mix(h1(i), h1(i + vec3(1.0, 0.0, 0.0)), f.x), mix(h1(i + vec3(0.0, 1.0, 0.0)), h1(i + vec3(1.0, 1.0, 0.0)), f.x), f.y);
	float b = mix(mix(h1(i + vec3(0.0, 0.0, 1.0)), h1(i + vec3(1.0, 0.0, 1.0)), f.x), mix(h1(i + vec3(0.0, 1.0, 1.0)), h1(i + vec3(1.0, 1.0, 1.0)), f.x), f.y);
	return mix(a, b, f.z);
}
void fragment() {
	// волны от попаданий: два кольца расходятся от места удара и гаснут
	float waves = 0.0;
	float flash = 0.0;
	for (int i = 0; i < 4; i++) {
		float age = hits[i].w;
		if (age < 1.0) {
			vec3 dv = wpos - hits[i].xyz;
			float d = length(dv);
			float r = age * 4.5;
			float env = (1.0 - age) * (1.0 - smoothstep(3.0, 5.0, d));
			float w1 = exp(-pow((d - r) * 2.4, 2.0));
			float w2 = exp(-pow((d - r * 0.55) * 2.8, 2.0)) * 0.6;
			waves += (w1 + w2) * env;
			flash += exp(-d * 1.3) * max(1.0 - age * 4.0, 0.0);
		}
	}
	// мерцание: пятна и тонкие извилистые прожилки неровной формы, текут (искажение шумом),
	// а маска сама зажигает и гасит их то в одном, то в другом месте щита
	vec3 q = cpos * 0.3 + vec3(0.0, TIME * 0.3, TIME * 0.15);
	vec3 wq = (vec3(vn(cpos * 0.18 + TIME * 0.12), vn(cpos * 0.18 + 7.7 - TIME * 0.1), vn(cpos * 0.18 + 19.3)) - 0.5) * 2.0;
	float cl = vn(q + wq) * 0.55 + vn(q * 2.1 + wq + 5.1) * 0.3 + vn(q * 4.3 + 11.7) * 0.15;
	float where = smoothstep(0.35, 0.65, vn(cpos * 0.22 + vec3(TIME * 0.4, TIME * 0.9, -TIME * 0.3)));
	float vein = exp(-pow((cl - 0.46) * 14.0, 2.0));
	float spot = smoothstep(0.5, 0.65, cl);
	float shimmer = max(vein, spot) * where;
	// края светятся (свет вдоль поверхности, как у мыльного пузыря), середина почти прозрачная
	float fr = 1.0 - abs(dot(NORMAL, VIEW));
	float rim = pow(fr, 2.6) * 0.9 + pow(fr, 7.0) * 0.9;
	float a = 0.035 + shimmer * 0.18 + rim + waves * 1.5 + flash * 0.7;
	vec3 c = mix(col, vec3(1.0, 0.9, 0.86), clamp(pow(fr, 6.0) * 0.45 + flash * 0.6 + waves * 0.35, 0.0, 1.0));
	ALBEDO = c * 1.6;
	ALPHA = clamp(a * fade, 0.0, 1.0);
}
"""
	_barrier_mat = ShaderMaterial.new()
	_barrier_mat.shader = sh
	_barrier_mat.set_shader_parameter("col", Vector3(col.r, col.g, col.b).lerp(Vector3(0.5, 0.85, 1.0), 0.15))
	_send_waves()
	_barrier = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 8.6
	sm.height = 17.2
	sm.radial_segments = 32
	sm.rings = 16
	_barrier.mesh = sm
	_barrier.scale = Vector3(1.0, 0.95, 1.0)
	_barrier.material_override = _barrier_mat
	_barrier.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_barrier.visible = false
	add_child(_barrier)


func cores_alive() -> int:
	var n := 0
	for s in get_tree().get_nodes_in_group("structures"):
		if s.team == team and s.id == "core" and not s.dead:
			n += 1
	return n


# под барьером ли штаб (пока живо хоть одно ядро)
func shielded() -> bool:
	return id == "hq" and Parts.v("hq", "barrier") > 0.5 and cores_alive() > 0


# штаб и ядра неуязвимы, пока стоит турель 3 уровня их команды (если так настроено); штаб ещё и под барьером
func protected() -> bool:
	if id != "hq" and id != "core":
		return false
	if shielded():
		return true
	if Cfg.hq_needs_t3 != 1:
		return false
	for s in get_tree().get_nodes_in_group("structures"):
		if s.team == team and s.tier == 3 and not s.dead:
			return true
	return false


func take_damage(amount: float, pos: Vector3, _dir: Vector3, _kind := "", src: Node = null) -> void:
	if dead and ruin_hp > 0.0 and amount > 0.0:
		_ruin_damage(amount)
		return
	if dead or amount <= 0.0:
		return
	if protected():
		if _barrier_on:
			# место удара на куполе: искры и волна оттуда
			var dv := pos - global_position
			if dv.length() < 0.1:
				dv = Vector3.UP
			dv = dv.normalized()
			var hp := global_position + Vector3(dv.x * 8.6, dv.y * 8.6 * 0.95, dv.z * 8.6)
			if _barrier.visible:
				# лазер и скорострелки бьют в одно место каждый тик: новая волна оттуда не чаще 4 раз в секунду
				var last: Vector4 = _waves[-1] if not _waves.is_empty() else Vector4(0, -1000, 0, 99)
				if last.w > 0.25 or Vector3(last.x, last.y, last.z).distance_to(hp) > 2.5:
					_waves.append(Vector4(hp.x, hp.y, hp.z, 0.0))
					if _waves.size() > WAVES_MAX:
						_waves.pop_front()
					set_process(true)
				Fx.spark(hp, dv, true, false)
		return
	if src != null and is_instance_valid(src):
		last_attacker = src
	amount = minf(amount, hp)
	hp -= amount
	Battle.on_damage(src, self, amount, pos)
	if hp <= 0.0:
		_die()


func stun(_s: float) -> void:
	pass


func block_regen(_s: float) -> void:
	pass


func _die() -> void:
	dead = true
	hp = 0.0
	if id == "hq":
		hitbox.set_active(false)
	else:
		# остаётся развалина: по ней стреляют обе команды (хитбокс больше не «свой»), разбить — реклейм
		ruin_hp = Cfg.ruin_hp
		hitbox.remove_from_group("team_hitbox")
	var big := id == "hq"
	for i in (5 if big else 2):
		var off := Vector3(randf_range(-3, 3), randf_range(0.5, 4), randf_range(-3, 3)) * (1.5 if big else 0.6)
		Fx.explosion(global_position + off, 6.0 if big else 4.5)
	Sfx.play_at("boom", global_position, 2.0, 0.05)
	# остаётся чёрная развалина
	for m in _mats:
		m.albedo_color = Color(0.06, 0.055, 0.05)
	if _head != null:
		var tw := create_tween()
		tw.tween_property(_head, "position:y", 2.2, 0.4).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(_head, "rotation:z", 0.5, 0.4)
	_bar.visible = false
	if _orb_mat != null:
		_orb_mat.emission = Color.BLACK
		_orb_mat.albedo_color = Color(0.08, 0.08, 0.09)
		Fx.pulse(_orb.global_position, 6.0)
	Battle.on_kill(last_attacker, self)
	destroyed.emit(self)


# развалина сломанной турели: в неё стреляют обе команды
func is_ruin() -> bool:
	return dead and ruin_hp > 0.0


func _ruin_damage(amount: float) -> void:
	ruin_hp -= amount
	if ruin_hp <= 0.0:
		_ruin_break()


# развалину разбили: взрыв, припасы, тело и вид исчезают, путь свободен (main пересчитывает проходимость)
func _ruin_break() -> void:
	ruin_hp = 0.0
	cleared = true
	for i in 2:
		Fx.explosion(global_position + Vector3(randf_range(-1.5, 1.5), randf_range(0.8, 2.5), randf_range(-1.5, 1.5)), 4.0)
	Sfx.play_at("wallbreak", global_position, 0.0, 0.05)
	var g = get_tree().current_scene
	if g != null and g.has_method("spawn_loot") and Cfg.ruin_loot > 0:
		g.spawn_loot(global_position, Cfg.ruin_loot)
	hitbox.set_active(false)
	if _body != null:
		_body.queue_free()
		_body = null
	remove_from_group("damageable")
	visible = false
	ruin_cleared.emit(self)


func _physics_process(delta: float) -> void:
	if dead:
		return
	_bar.set_ratio(hp / maxf(max_hp(), 1.0))
	if id == "hq":
		_update_barrier(delta)
	elif id == "core":
		_update_core(delta)
	if _head == null:
		return
	_cool = maxf(_cool - delta, 0.0)
	_emp_cd = maxf(_emp_cd - delta, 0.0)
	_mortar_cd = maxf(_mortar_cd - delta, 0.0)
	_target = _pick_target()
	if tier == 2 and _emp_cd <= 0.0:
		_try_emp()
	if tier == 3 and _mortar_cd <= 0.0:
		_try_mortar()
	if _mortar != null:
		_mortar.position.z = move_toward(_mortar.position.z, 0.9 * (0.9 + tier * 0.13), delta * 2.0)
	if _target == null:
		return
	var to: Vector3 = _target.global_position - _head.global_position
	to.y = 0
	var want := atan2(-to.x, -to.z)
	# поворачиваем в мировых координатах (вражеские турели сами развёрнуты на 180°)
	var cur := _head.global_rotation.y
	_head.global_rotation.y = rotate_toward(cur, want, deg_to_rad(240.0) * delta)
	if _cool <= 0.0 and absf(angle_difference(_head.global_rotation.y, want)) < 0.15:
		_cool = 1.0 / maxf(Parts.v(id, "fire_rate"), 0.05)
		_fire()


# ближайший враг в радиусе, которого видит команда турели и до которого не мешают стены.
# Как в доте: сначала крипы, мехов турель бьёт, когда крипов рядом нет
func _pick_target() -> Node3D:
	var rng := Parts.v(id, "range")
	var best: Node3D = null
	var best_d := 1e9
	var g = get_tree().current_scene
	if g == null or not g.has_method("units"):
		return null
	var here := global_position
	for u in g.units():
		if u[2] == team:
			continue
		var m = u[0]
		if not is_instance_valid(m) or m.dead:
			continue
		var d: float = (u[1] - here).length() - u[3]
		if d > rng:
			continue
		if u[4]:
			d += 1000.0      # мехи после крипов
		if d >= best_d:
			continue
		if not g.is_visible_to(team, m):
			continue
		best = m
		best_d = d
	return best


# ближайший видимый вражеский мех между min и max
func _pick_mech(min_r: float, max_r: float) -> Node3D:
	var best: Node3D = null
	var best_d := 1e9
	var g = get_tree().current_scene
	for m in get_tree().get_nodes_in_group("mechs"):
		if m.dead or m.team == team or m.is_landing():
			continue
		var d: float = (m.global_position - global_position).length()
		if d < min_r or d > max_r or d >= best_d:
			continue
		if g != null and g.has_method("is_visible_to") and not g.is_visible_to(team, m):
			continue
		best = m
		best_d = d
	return best


# куда турель стреляет: в цель с лёгким упреждением, ровно горизонтально
func _aim_dir() -> Vector3:
	var origin: Vector3 = _muzzle.global_position
	var tp: Vector3 = _target.global_position
	var aim: Vector3 = tp
	var spd := Parts.v(id, "bullet_speed")
	aim += _target.velocity * (origin.distance_to(aim) / maxf(spd, 1.0)) * 0.7
	# в середину хитбокса цели по высоте
	aim.y = tp.y + (_target.get_hit_height() * 0.5 if _target.has_method("get_hit_height") else 1.0)
	return (aim - origin).normalized()


func _fire() -> void:
	var origin: Vector3 = _muzzle.global_position
	var spd := Parts.v(id, "bullet_speed")
	var dir := _aim_dir()
	var p := Projectile.new()
	p.setup(origin, dir * spd, Parts.v(id, "damage"), Parts.v(id, "range") + 6.0, self)
	p.tracer = 0.3
	get_tree().current_scene.add_child(p)
	Sfx.play_at("cannon", global_position, -6.0, 0.1)
	Fx.spark(origin, dir, false, false)
	Fx.light_flash(origin, Color(1.0, 0.7, 0.35), 9.0, 3.5, 0.09)


# снаряд в точку, куда цель придёт (с лёгким упреждением): вылетает с постоянной скоростью по низкой,
# почти прямой дуге и рвётся о то, во что врежется (стена, мех, крип, земля). Меток на земле нет:
# подсказок в игре нет, снаряд видно только в полёте
func _lob_at(m: Node3D, speed: float, payload: Dictionary) -> void:
	var from := global_position + Vector3.UP * 6.0
	var to: Vector3 = m.global_position
	to.y = 0.0
	to += m.velocity * (from.distance_to(to) / maxf(speed, 1.0)) * 0.5
	var lob := Lob.new()
	lob.setup_ballistic(from, Lob.aim_velocity(from, to, speed), self, payload)
	get_tree().current_scene.add_child(lob)


func _try_emp() -> void:
	var m := _pick_mech(0.0, Parts.v(id, "emp_range"))
	if m == null:
		return
	_emp_cd = Parts.v(id, "emp_cooldown")
	var r := Parts.v(id, "emp_radius")
	_lob_at(m, Parts.v(id, "emp_speed"), {"kind": "emp", "radius": r, "stun": Parts.v(id, "emp_stun"),
		"no_regen": 2.0, "damage": Parts.v(id, "emp_damage")})
	Sfx.play_at("launch", global_position, -4.0, 0.05)


func _try_mortar() -> void:
	var m := _pick_mech(Parts.v(id, "mortar_min_range"), Parts.v(id, "mortar_range"))
	if m == null:
		return
	_mortar_cd = Parts.v(id, "mortar_cooldown")
	var r := Parts.v(id, "mortar_radius")
	_lob_at(m, Parts.v(id, "mortar_speed"), {"kind": "explosive", "radius": r,
		"damage": Parts.v(id, "mortar_damage"), "edge_damage": 0.3})
	Sfx.play_at("mortar", global_position, 0.0, 0.05)
	Fx.shake_at.emit(global_position, Cfg.shake_explosion * 0.3)
	if _mortar != null:
		_mortar.position.z += 0.5


# ------------------------------------------------------------------
#  Барьер штаба и ядра-Теслы
# ------------------------------------------------------------------

func _update_barrier(_delta: float) -> void:
	var want := shielded()
	if want != _barrier_on:
		_barrier_on = want
		if not want:
			# последнее ядро сломано: барьер лопается
			Fx.pulse(global_position + Vector3.UP * 3.0, 10.0)
			Fx.burst(global_position + Vector3.UP * 5.0, Color(0.5, 0.85, 1.0), 9.0)
			Sfx.play_at("wallbreak", global_position, 2.0, 0.05)
			Sfx.play_at("emp", global_position, 0.0, 0.05)
		_barrier.visible = _barrier_on


func _process(delta: float) -> void:
	for i in range(_waves.size() - 1, -1, -1):
		var w := _waves[i]
		w.w += delta
		if w.w >= WAVE_LIFE:
			_waves.remove_at(i)
		else:
			_waves[i] = w
	_send_waves()
	if _waves.is_empty():
		set_process(false)


func _send_waves() -> void:
	var arr := PackedVector4Array()
	for w in _waves:
		arr.append(w)
	while arr.size() < WAVES_MAX:
		arr.append(Vector4(0.0, -1000.0, 0.0, 99.0))
	_barrier_mat.set_shader_parameter("hits", arr)


# раз в «Перезарядку» ядро выбирает врага в радиусе, заряжается и бьёт молнией.
# Цель выбирается в начале зарядки; если за это время она ушла из радиуса или из вида, удар срывается
func _update_core(delta: float) -> void:
	var t := Time.get_ticks_msec() * 0.001
	for i in _rings.size():
		_rings[i].position.y = 2.2 + i * 0.75 + sin(t * 3.0 + i) * 0.05
	var glow := 1.5 + sin(t * 4.0) * 0.3
	if _charge_left > 0.0:
		_charge_left -= delta
		var k := 1.0 - _charge_left / maxf(Parts.v(id, "charge"), 0.05)
		glow = 2.0 + k * 6.0
		if randf() < 0.7:
			Fx.zap(_orb.global_position + Vector3.DOWN * 1.2, 1.1, 2.2)
		if _charge_left <= 0.0:
			_strike()
	else:
		_zap_cd = maxf(_zap_cd - delta, 0.0)
		if _zap_cd <= 0.0:
			_zap_target = _pick_zap()
			if _zap_target != null:
				_charge_left = maxf(Parts.v(id, "charge"), 0.01)
				_zap_cd = Parts.v(id, "cooldown")
				Sfx.play_at("beep", global_position, -10.0, 0.05)
			else:
				_zap_cd = 0.3
	_orb_mat.emission_energy_multiplier = glow
	if _halo != null:
		_halo.scale = Vector3.ONE * (2.8 + glow * 0.75)


# цель Теслы: сначала мехи, потом крипы; только видимые команде ядра
func _pick_zap() -> Node3D:
	var rng := Parts.v(id, "range")
	var best: Node3D = null
	var best_d := 1e9
	var g = get_tree().current_scene
	for m in get_tree().get_nodes_in_group("mechs") + get_tree().get_nodes_in_group("creeps"):
		if m.dead or m.team == team:
			continue
		if m.is_in_group("mechs") and m.is_landing():
			continue
		var d: float = (m.global_position - global_position).length() - m.get_hit_radius()
		if d > rng:
			continue
		if not m.is_in_group("mechs"):
			d += 1000.0
		if d >= best_d:
			continue
		if g != null and g.has_method("is_visible_to") and not g.is_visible_to(team, m):
			continue
		best = m
		best_d = d
	return best


func _strike() -> void:
	var m := _zap_target
	_zap_target = null
	if m == null or not is_instance_valid(m) or m.dead:
		return
	var d: float = (m.global_position - global_position).length() - m.get_hit_radius()
	var g = get_tree().current_scene
	var from := _orb.global_position
	if d > Parts.v(id, "range") + 3.0 or (g != null and g.has_method("is_visible_to") and not g.is_visible_to(team, m)):
		# цель ушла: молния бьёт в землю рядом с ядром
		Fx.tesla_bolt(from, global_position + Vector3(randf_range(-4, 4), 0.1, randf_range(-4, 4)))
		Sfx.play_at("tesla", global_position, -6.0, 0.1)
		return
	var h := 2.2 if m.is_in_group("mechs") else 1.0
	var to: Vector3 = m.global_position + Vector3.UP * h
	Fx.tesla_bolt(from, to)
	Sfx.play_at("tesla", to, 0.0, 0.1)
	if m.has_method("take_damage"):
		m.take_damage(Parts.v(id, "damage"), to, (to - from).normalized(), "", self)
	if m.has_method("stun") and not m.dead:
		m.stun(Parts.v(id, "stun"))
