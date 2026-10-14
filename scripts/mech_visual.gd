extends Node3D
## Внешний вид меха и шагающие ноги.
## Корпус без головы, пушки по бокам, ноги с одним обратным коленом.
## Ноги не анимированы заранее: ступня ставится на землю, а колено досчитывается (IK).
## Модель собирается от деталей: размер ног, размер корпуса, вид корпуса (у каждого из 10 мехов свой:
## лёгкий клин, разведчик с радаром, таран с отвалом, мортира с упорами...), вид оружия на каждом подвесе,
## ракетные блоки на плечах только если стоит ракетная установка.
## Броня в текстурах из assets/textures (если их нет, рисуется своя фактура), грани скошены.

signal footstep(pos: Vector3)

# размеры при масштабе 1 (средние ноги, штурмовой корпус)
const HIP_H0 := 2.05     # высота таза над землёй
const WAIST_UP := 0.32   # от таза до поворотного круга корпуса
const L1 := 1.2          # длина бедра
const L2 := 1.25         # длина голени
const ANKLE_H := 0.32    # высота щиколотки над подошвой
const HIP_X := 0.9       # на сколько бёдра разнесены в стороны
const FOOT_X0 := 1.05    # на сколько ступни разнесены в стороны

# Средний класс по 3D-модели medium1 (Cfg.mid_look = 1 коробки по ней, 2 сама модель).
# Модель порезана скриптом tools/medium1_cut.py. Суставы в позе модели (метры игры, левая сторона):
const MID_HIP := Vector3(-0.983, 2.05, 0.0)
const MID_KNEE := Vector3(-1.053, 1.17, 0.445)
const MID_ANKLE := Vector3(-1.334, 0.608, 0.023)
const MID_STRETCH := 1.2  # кости в модели короче наших: без растяжки ступня не дотягивается при беге
const MID_POD := Vector3(1.266, 0.495, -0.1)   # подвес пушки в корпусе
const MID_MUZZLE := Vector3(0.0, -0.27, -2.35) # конец стволов автопушки модели (от подвеса)
const MEDIUM1 := "res://assets/mechs/medium1.glb"


class Foot:
	var pos := Vector3.ZERO      # где ступня стоит в мире
	var yaw := 0.0
	var swinging := false        # нога в воздухе
	var from := Vector3.ZERO
	var from_yaw := 0.0
	var start_lp := 0.0
	var quick := -1.0            # поправочный шаг: 0..1, -1 = нет
	var quick_dur := 0.16
	var air := 0.0               # 0..1, для наклона ступни
	var node: Node3D
	var thigh: Node3D
	var shin: Node3D
	var knee: Node3D


var st: Dictionary = {}          # числа меха (скорости, длина шага), даёт mech.gd
var ls := 1.0                    # масштаб ног
var hs := 1.0                    # масштаб корпуса

var legs_root: Node3D
var torso: Node3D
var gun_pods: Array[Node3D] = []
var muzzles: Array[Node3D] = []
var flashes: Array[MeshInstance3D] = []
var beams: Array[MeshInstance3D] = []
var thrusters: Array[MeshInstance3D] = []
var missile_ports: Array[Node3D] = []
var missile_flashes: Array[MeshInstance3D] = []
var missile_flash_t := [0.0, 0.0]
var feet: Array[Foot] = []

var phase := 0.0
var recoil := 0.0
var gun_kick := [0.0, 0.0]
var flash_t := [0.0, 0.0]
var _lean := Vector3.ZERO
var _was_moving := false
var _crouch := 0.0
var _inited := false
var _flash_t := 0.0
var stunned := false
var braced := false              # упор (Мортира): сзади опускаются опоры
var airborne := false            # летит при высадке: ноги поджаты, задние двигатели не горят
var style := "mid"
var cls := "mid"                # класс: light (птица), mid (штурмовик по референсу), heavy (крепость)
var look_mid := 0               # вид среднего: 0 старые коробки, 1 коробки по модели, 2 модель
var _hip_x := HIP_X
var _foot_x := FOOT_X0
var _l1 := L1
var _l2 := L2
var _ankle_h := ANKLE_H
var _jets: Array[MeshInstance3D] = []
var _jet_light: OmniLight3D
var _struts: Array[Node3D] = []
var _brace_k := 0.0
var _spinners: Array = [null, null]      # блок стволов Гатлинга по подвесам
var _charge_mats: Array = [null, null]   # свечение рельсотрона по подвесам
var _radar: Node3D

var m_armor: StandardMaterial3D
var m_armor2: StandardMaterial3D
var m_dark: StandardMaterial3D
var m_accent: StandardMaterial3D
var m_glow: StandardMaterial3D
var m_beam: StandardMaterial3D
var m_light: StandardMaterial3D
# для 3D-модели: те же материалы, но с затенением, запечённым в цвет вершин
var m_armor_v: StandardMaterial3D
var m_armor2_v: StandardMaterial3D
var m_dark_v: StandardMaterial3D
var _model_meshes := {}          # части модели по именам (берутся из файла при сборке)

const Art := preload("res://scripts/art.gd")


# ------------------------------------------------------------------
#  СБОРКА МОДЕЛИ ИЗ БЛОКОВ
# ------------------------------------------------------------------

# look: {legs_scale, hull_scale, weapons: [вид левого, вид правого], rockets: bool}
func build(team_color: Color, tint: Color, look: Dictionary) -> void:
	ls = look.get("legs_scale", 1.0)
	hs = look.get("hull_scale", 1.0)
	style = look.get("style", "mid")
	cls = "light" if style in ["light", "scout"] else ("heavy" if style in ["heavy", "bastion", "siege"] else "mid")
	_hip_x = {"light": 0.72, "mid": 0.95, "heavy": 1.15}[cls]
	_foot_x = {"light": 0.9, "mid": 1.12, "heavy": 1.38}[cls]
	look_mid = int(Cfg.mid_look) if cls == "mid" else 0
	if look_mid == 2 and _model_mesh("hull") == null:
		look_mid = 1     # файла модели нет: коробки по ней
	if look_mid > 0:
		# ноги как у модели: шире, щиколотка выше, кости чуть вытянуты
		_hip_x = -MID_HIP.x
		_foot_x = -MID_ANKLE.x
		_ankle_h = MID_ANKLE.y
		_l1 = MID_HIP.distance_to(MID_KNEE) * MID_STRETCH
		_l2 = MID_KNEE.distance_to(MID_ANKLE) * MID_STRETCH
	# броня слегка окрашена в цвет команды, чтобы мехи отличались не только полосками
	var paint := Color(0.42, 0.43, 0.44).lerp(team_color, 0.12) * tint
	m_armor = _mat(paint, 0.35, 0.5)
	m_armor.emission_enabled = true
	m_armor.emission = Color(0, 0, 0)
	m_armor2 = _mat(Color(0.26, 0.27, 0.285) * tint, 0.4, 0.55)
	m_armor2.emission_enabled = true
	m_armor2.emission = Color(0, 0, 0)
	m_dark = _mat(Color(0.2, 0.2, 0.21), 0.5, 0.5)
	m_accent = _mat(team_color.darkened(0.15), 0.1, 0.6)
	m_glow = StandardMaterial3D.new()
	m_glow.albedo_color = team_color
	m_glow.emission_enabled = true
	m_glow.emission = team_color
	m_glow.emission_energy_multiplier = 1.4
	m_beam = _unshaded((Color(0.55, 0.95, 1.0) if team_color == Cfg.player_color else Color(1.0, 0.35, 0.35)) * 2.2)
	# фактура брони: панели, швы, болты (или текстуры из assets/textures)
	Art.apply_panels(m_armor, 0.7, "armor")
	Art.apply_panels(m_armor2, 0.9, "armor")
	Art.apply_panels(m_dark, 1.4, "darkmetal")
	m_light = StandardMaterial3D.new()
	m_light.albedo_color = Color(1.0, 0.95, 0.8)
	m_light.emission_enabled = true
	m_light.emission = Color(1.0, 0.92, 0.75)
	m_light.emission_energy_multiplier = 3.0
	if look_mid == 2:
		m_armor_v = _vcol(m_armor)
		m_armor2_v = _vcol(m_armor2)
		m_dark_v = _vcol(m_dark)

	_build_pelvis()
	_build_torso(look.get("weapons", ["twin", "twin"]), look.get("rockets", false))
	for i in 2:
		feet.append(_build_leg(-1.0 if i == 0 else 1.0))
	_build_jets()
	# склеиваем неподвижные детали: меньше вызовов отрисовки
	var keep: Array = []
	keep.append_array(flashes)
	keep.append_array(beams)
	keep.append_array(thrusters)
	keep.append_array(missile_flashes)
	keep.append_array(_jets)
	Art.merge_meshes(self, [m_armor, m_armor2, m_dark, m_accent, m_glow, m_light], keep)


# тормозные двигатели под тазом: горят при высадке с неба
func _build_jets() -> void:
	var flame := _unshaded(Color(1.0, 0.7, 0.3) * 2.6)
	flame.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flame.albedo_color.a = 0.85
	var tex := Art.fx_tex("muzzle_05")
	for s in [-1.0, 1.0]:
		var j := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.45
		cm.bottom_radius = 0.04
		cm.height = 3.6
		cm.radial_segments = 10
		cm.rings = 1
		j.mesh = cm
		j.material_override = flame
		j.position = Vector3(_hip_x * 0.7 * s, -2.2, 0.1)
		j.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		j.visible = false
		legs_root.add_child(j)
		_jets.append(j)
		if tex != null:
			var q := MeshInstance3D.new()
			var qm := QuadMesh.new()
			qm.size = Vector2(1.4, 3.2)
			q.mesh = qm
			var qmat := StandardMaterial3D.new()
			qmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			qmat.albedo_texture = tex
			qmat.albedo_color = Color(1.0, 0.75, 0.4, 1.0)
			qmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			qmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			qmat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
			qmat.cull_mode = BaseMaterial3D.CULL_DISABLED
			q.material_override = qmat
			q.rotation.z = PI
			q.position = Vector3(0, -0.4, 0)
			q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			j.add_child(q)
	_jet_light = OmniLight3D.new()
	_jet_light.light_color = Color(1.0, 0.65, 0.3)
	_jet_light.omni_range = 9.0
	_jet_light.light_energy = 0.0
	_jet_light.position = Vector3(0, -2.0, 0)
	legs_root.add_child(_jet_light)


# сила тормозных двигателей 0..1
func set_jets(k: float) -> void:
	for j in _jets:
		j.visible = k > 0.02
		if k > 0.02:
			j.scale = Vector3(1, k * randf_range(0.8, 1.2), 1)
	if _jet_light != null:
		_jet_light.light_energy = k * 3.0


# раскрутка Гатлинга: блок стволов крутится
func spin(gun: int, k: float, delta: float) -> void:
	var sp = _spinners[gun]
	if sp != null:
		sp.rotation.z += k * 30.0 * delta


# заряд рельсотрона 0..1: щель между рельсами разгорается
func set_charge(gun: int, k: float) -> void:
	var m = _charge_mats[gun]
	if m != null:
		m.emission_energy_multiplier = 0.4 + k * 6.0
		m.albedo_color.a = 1.0


# обломок: всё чёрное и обгоревшее, огни погашены
func set_charred() -> void:
	set_fade(0.0)
	var burnt := Color(0.07, 0.065, 0.06)
	for m in [m_armor, m_armor2, m_accent, m_armor_v, m_armor2_v]:
		if m != null:
			m.albedo_color = burnt * randf_range(0.8, 1.3)
			m.emission_enabled = false
	for m in [m_dark, m_dark_v]:
		if m != null:
			m.albedo_color = Color(0.03, 0.03, 0.03)
	if m_glow != null:
		m_glow.albedo_color = Color(0.12, 0.05, 0.03)
		m_glow.emission = Color(0.35, 0.08, 0.02)
		m_glow.emission_energy_multiplier = 0.4
	for b in beams:
		b.visible = false
	for f in flashes:
		f.visible = false
	for f in missile_flashes:
		f.visible = false
	for t in thrusters:
		t.visible = false
	if m_light != null:
		m_light.emission_enabled = false
		m_light.albedo_color = Color(0.05, 0.05, 0.05)


# невидимость: 0 = обычный, 1 = совсем прозрачный
func set_fade(f: float) -> void:
	for m in [m_armor, m_armor2, m_dark, m_accent, m_glow, m_light, m_armor_v, m_armor2_v, m_dark_v]:
		if m == null:
			continue
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if f > 0.001 else BaseMaterial3D.TRANSPARENCY_DISABLED
		m.albedo_color.a = 1.0 - f


func hip_h() -> float:
	return HIP_H0 * ls


func _build_pelvis() -> void:
	legs_root = Node3D.new()
	add_child(legs_root)
	if look_mid == 2:
		_model(legs_root, "pelvis")
		return
	if look_mid == 1:
		var h := _holder(legs_root, Transform3D(Basis.IDENTITY, Vector3(0, -HIP_H0, 0)))
		_box(h, Vector3(0.85, 0.6, 1.2), Vector3(0, 2.05, 0.05), m_armor2)
		_box(h, Vector3(0.6, 0.35, 0.75), Vector3(0, 1.74, -0.12), m_armor2, Vector3(0.3, 0, 0))
		_box(h, Vector3(0.5, 0.12, 0.9), Vector3(0, 2.38, 0.05), m_dark)
		for s in [-1.0, 1.0]:
			_cyl(h, 0.17, 0.62, Vector3(0.62 * s, 2.05, 0), m_dark, Vector3(0, 0, PI / 2))
			_cyl(h, 0.24, 0.12, Vector3(0.4 * s, 2.05, 0), m_armor2, Vector3(0, 0, PI / 2))
		return
	var k: float = {"light": 0.75, "mid": 1.0, "heavy": 1.3}[cls]
	_box(legs_root, Vector3(1.25 * k, 0.5, 1.05), Vector3.ZERO, m_dark)
	_box(legs_root, Vector3(0.9 * k, 0.35, 1.25), Vector3(0, -0.12, 0), m_armor2)
	_box(legs_root, Vector3(0.7 * k, 0.3, 0.3), Vector3(0, 0.0, -0.62), m_armor)
	for s in [-1.0, 1.0]:
		_cyl(legs_root, 0.34 * k, 0.5, Vector3(_hip_x * s, 0, 0), m_armor2, Vector3(0, 0, PI / 2))
		_cyl(legs_root, 0.2 * k, 0.56, Vector3(_hip_x * s, 0, 0), m_dark, Vector3(0, 0, PI / 2))
		if cls != "light":
			# бронещиток над тазобедренным шарниром
			_box(legs_root, Vector3(0.3, 0.55 * k, 0.9 * k), Vector3((_hip_x + 0.32) * s, 0.12, 0), m_armor, Vector3(0, 0, -0.15 * s))
	_cyl(legs_root, 0.5 * k, WAIST_UP, Vector3(0, WAIST_UP * 0.5 + 0.2, 0), m_dark)


func _build_torso(weapon_looks: Array, rockets: bool) -> void:
	torso = Node3D.new()
	add_child(torso)
	# поворотный круг
	_cyl(torso, 0.62, 0.22, Vector3(0, 0.1, 0), m_armor2)
	var pods: Array
	var ports: Array
	var jets: Array
	match cls:
		"light":
			pods = _hull_light()
			ports = [Vector3(-0.42, 1.0, 0.55), Vector3(0.42, 1.0, 0.55)]
			jets = [Vector3(-0.22, 0.62, 2.35), Vector3(0.22, 0.62, 2.35)]
		"heavy":
			pods = _hull_heavy()
			ports = [Vector3(-0.75, 2.15, -0.1), Vector3(0.75, 2.15, -0.1)]
			jets = [Vector3(-0.55, 0.95, 1.9), Vector3(0.55, 0.95, 1.9)]
		_:
			if look_mid > 0:
				pods = _hull_mid_new()
				ports = [Vector3(-MID_POD.x, 1.1, -0.2), Vector3(MID_POD.x, 1.1, -0.2)]
				jets = [Vector3(-0.42, 0.5, 1.85), Vector3(0.42, 0.5, 1.85)]
			else:
				pods = _hull_mid()
				ports = [Vector3(-1.32, 2.05, -0.35), Vector3(1.32, 2.05, -0.35)]
				jets = [Vector3(-0.42, 0.95, 1.85), Vector3(0.42, 0.95, 1.85)]
	# двигатели рывка сзади
	for j in jets:
		_cyl(torso, 0.2, 0.35, j - Vector3(0, 0, 0.3), m_dark, Vector3(PI / 2, 0, 0))
		var th := _box(torso, Vector3(0.26, 0.26, 1.3), j + Vector3(0, 0, 0.6), _unshaded(Color(0.55, 0.85, 1.0) * 2.0))
		th.visible = false
		thrusters.append(th)
	_build_style_parts()
	for i in 2:
		var s := -1.0 if i == 0 else 1.0
		# ракетный блок: только если стоит ракетная установка
		var pp: Vector3 = ports[i]
		var port := Node3D.new()
		port.position = pp + Vector3(0, 0.05, -0.45)
		torso.add_child(port)
		missile_ports.append(port)
		var mfl := _box(torso, Vector3(0.5, 0.34, 0.5), pp + Vector3(0, 0, -0.55), _unshaded(Color(1.0, 0.75, 0.35) * 2.2))
		mfl.visible = false
		mfl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		missile_flashes.append(mfl)
		if rockets:
			var w := 0.55 if cls == "light" else 0.8
			_box(torso, Vector3(w, 0.5, 0.95), pp + Vector3(0, 0, 0.05), m_armor)
			_box(torso, Vector3(0.1, 0.06, 1.0), pp + Vector3(w * 0.3, 0.27, 0.05), m_accent)
			for r in 2:
				for c in (2 if cls == "light" else 3):
					var cx := (c - (0.5 if cls == "light" else 1.0)) * 0.22
					_cyl(torso, 0.08, 0.1, pp + Vector3(cx, (r - 0.5) * 0.2, -0.43), m_dark, Vector3(PI / 2, 0, 0))
		# орудийный модуль
		var pod := Node3D.new()
		pod.position = pods[i]
		torso.add_child(pod)
		gun_pods.append(pod)
		var look: String = weapon_looks[i] if i < weapon_looks.size() else "twin"
		var muzzle := Vector3(0, -0.05, 0)
		if look_mid > 0:
			# корпус пушки свой (модель или коробки по ней); у автопушки и стволы свои,
			# у остального оружия ставим только его стволы
			var own_barrels := _pod_mid_new(pod, s, look == "twin")
			if own_barrels:
				muzzle = MID_MUZZLE
			else:
				muzzle.z = _build_weapon(pod, look, s, i, false)
		else:
			muzzle.z = _build_weapon(pod, look, s, i)
		var muzzle_z := muzzle.z
		var mz := Node3D.new()
		mz.position = muzzle
		pod.add_child(mz)
		muzzles.append(mz)
		# вспышка выстрела: спрайт (если есть) или светящийся шар
		var fl := MeshInstance3D.new()
		var ftex := Art.fx_tex("muzzle_02")
		if ftex != null:
			var qm := QuadMesh.new()
			qm.size = Vector2(1.3, 2.4)
			fl.mesh = qm
			var fm := StandardMaterial3D.new()
			fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			fm.albedo_texture = ftex
			var fc := Color(0.5, 0.9, 1.0) if look == "blaster" or look == "rail" else Color(1.0, 0.8, 0.45)
			fm.albedo_color = Color(fc.r * 2.0, fc.g * 2.0, fc.b * 2.0, 1.0)
			fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			fm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			fm.cull_mode = BaseMaterial3D.CULL_DISABLED
			fl.material_override = fm
			fl.rotation = Vector3(-PI / 2, 0, 0)
			fl.position = Vector3(0, muzzle.y, muzzle_z - 0.9)
		else:
			var sm := SphereMesh.new()
			sm.radius = 0.38
			sm.height = 0.76
			sm.radial_segments = 8
			sm.rings = 4
			fl.mesh = sm
			fl.material_override = _unshaded(Color(1.0, 0.82, 0.4) * 2.5)
			fl.position = Vector3(0, muzzle.y, muzzle_z - 0.3)
			fl.scale = Vector3(0.8, 0.8, 1.8)
		fl.scale *= (1.5 if look == "heavy" or look == "shotgun" else 1.0)
		fl.visible = false
		fl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pod.add_child(fl)
		flashes.append(fl)
		# луч лазера (рисуется только у лазера, когда он светит)
		var beam := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(1, 1, 1)
		beam.mesh = bm
		beam.material_override = m_beam
		beam.top_level = true
		beam.visible = false
		beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(beam)
		beams.append(beam)


# лёгкий: низкий узкий корпус-"хищник" с острым носом, хвостом и килями; пушки висят низко по бокам
func _hull_light() -> Array:
	_box(torso, Vector3(1.2, 0.6, 2.2), Vector3(0, 0.55, 0.1), m_armor)
	_box(torso, Vector3(1.35, 0.25, 1.7), Vector3(0, 0.45, 0.2), m_armor2)
	# нос клином вниз
	_box(torso, Vector3(1.0, 0.32, 1.3), Vector3(0, 0.68, -1.3), m_armor, Vector3(-0.32, 0, 0))
	_box(torso, Vector3(0.75, 0.28, 0.9), Vector3(0, 0.36, -1.25), m_armor2, Vector3(0.25, 0, 0))
	_box(torso, Vector3(0.55, 0.06, 0.55), Vector3(0, 0.87, -1.05), m_glow, Vector3(-0.32, 0, 0))
	# хребет из пластин
	for i in 4:
		_box(torso, Vector3(0.5 - i * 0.06, 0.12, 0.42), Vector3(0, 0.9 - i * 0.02, -0.45 + i * 0.45), m_armor2 if i % 2 == 0 else m_armor)
	_box(torso, Vector3(0.12, 0.05, 1.8), Vector3(0, 0.98, 0.1), m_accent)
	# хвост с двумя килями
	_box(torso, Vector3(0.62, 0.42, 1.2), Vector3(0, 0.66, 1.55), m_armor2)
	for sx in [-1.0, 1.0]:
		_box(torso, Vector3(0.06, 0.65, 0.8), Vector3(0.33 * sx, 1.05, 1.7), m_armor, Vector3(0.35, 0, 0.3 * sx))
		# фары
		_box(torso, Vector3(0.14, 0.08, 0.06), Vector3(0.3 * sx, 0.45, -1.68), m_light)
		# короткие пилоны к пушкам
		_box(torso, Vector3(0.45, 0.16, 0.5), Vector3(0.78 * sx, 0.45, -0.1), m_dark)
	return [Vector3(-1.12, 0.38, -0.3), Vector3(1.12, 0.38, -0.3)]


# средний (по референсу): горбатый бронекорпус без головы, наклонный лоб в несколько слоёв,
# тяжёлые плечевые блоки, в которых сидят пушки, ракетные короба сверху на плечах, ранец сзади
func _hull_mid() -> Array:
	_box(torso, Vector3(1.8, 1.05, 1.9), Vector3(0, 0.78, 0.1), m_armor2)
	# лоб: наклонные плиты внахлёст
	_box(torso, Vector3(1.6, 0.95, 0.32), Vector3(0, 0.95, -0.95), m_armor, Vector3(0.45, 0, 0))
	_box(torso, Vector3(1.35, 0.55, 0.3), Vector3(0, 0.42, -1.0), m_armor, Vector3(-0.35, 0, 0))
	_box(torso, Vector3(1.1, 0.28, 0.32), Vector3(0, 0.12, -0.78), m_armor2, Vector3(-0.6, 0, 0))
	# козырёк и щель сенсора под ним
	_box(torso, Vector3(1.45, 0.22, 0.55), Vector3(0, 1.42, -0.95), m_armor)
	_box(torso, Vector3(0.9, 0.07, 0.05), Vector3(0, 1.24, -1.2), m_glow)
	for sx in [-1.0, 1.0]:
		_box(torso, Vector3(0.14, 0.09, 0.05), Vector3(0.58 * sx, 0.62, -1.2), m_light)
	# горб: верхняя палуба и хребет
	_box(torso, Vector3(1.7, 0.3, 1.5), Vector3(0, 1.45, 0.25), m_armor, Vector3(-0.08, 0, 0))
	_box(torso, Vector3(0.6, 0.22, 1.4), Vector3(0, 1.66, 0.3), m_armor2)
	_box(torso, Vector3(0.14, 0.06, 1.4), Vector3(0, 1.78, 0.3), m_accent)
	# антенна и сенсорный блок сзади
	_box(torso, Vector3(0.3, 0.22, 0.3), Vector3(-0.5, 1.75, 0.85), m_dark)
	_box(torso, Vector3(0.04, 1.2, 0.04), Vector3(-0.5, 2.4, 0.9), m_dark)
	_box(torso, Vector3(0.08, 0.08, 0.08), Vector3(-0.5, 3.0, 0.9), m_glow)
	# ранец с радиаторами
	_box(torso, Vector3(1.35, 0.9, 0.7), Vector3(0, 0.95, 1.4), m_armor)
	for i in 4:
		_box(torso, Vector3(1.1, 0.05, 0.08), Vector3(0, 0.7 + i * 0.15, 1.77), m_dark)
	for sx in [-1.0, 1.0]:
		# плечевой блок: в нём сидит пушка
		_box(torso, Vector3(0.9, 1.1, 1.6), Vector3(1.32 * sx, 1.0, 0.0), m_armor)
		_box(torso, Vector3(1.0, 0.28, 1.4), Vector3(1.36 * sx, 1.62, -0.05), m_armor2, Vector3(0, 0, -0.18 * sx))
		_box(torso, Vector3(0.14, 0.85, 1.3), Vector3(1.82 * sx, 0.95, 0.05), m_armor2)
		for k in 3:
			_box(torso, Vector3(0.16, 0.06, 1.0), Vector3(1.86 * sx, 0.75 + k * 0.18, 0.05), m_dark)
		_box(torso, Vector3(0.05, 0.12, 0.7), Vector3(1.9 * sx, 1.25, -0.2), m_accent)
	return [Vector3(-1.38, 0.95, -0.55), Vector3(1.38, 0.95, -0.55)]


# средний по 3D-модели medium1: длинный горбатый корпус с носом-клином, по бокам на коротких
# плечах орудийные блоки, сзади выхлопы. look_mid 2 — сама модель, 1 — коробки по её меркам.
# Коробки ниже заданы в координатах позы модели (метры игры, как на снимках модели с сеткой),
# держатель переносит их в корпус.
func _hull_mid_new() -> Array:
	var pods := [Vector3(-MID_POD.x, MID_POD.y, MID_POD.z), MID_POD]
	if look_mid == 2:
		_model(torso, "hull")
		# цвет команды: полосы по хребту и на плечевых коробах
		_box(torso, Vector3(0.12, 0.05, 1.6), Vector3(0, 1.16, 0.2), m_accent)
		for s in [-1.0, 1.0]:
			_box(torso, Vector3(0.08, 0.05, 0.9), Vector3(0.62 * s, 1.08, -0.1), m_accent)
		return pods
	var h := _holder(torso, Transform3D(Basis.IDENTITY, Vector3(0, -(HIP_H0 + WAIST_UP), 0)))
	# основное тело и горб
	_box(h, Vector3(1.15, 0.85, 2.7), Vector3(0, 2.95, 0.35), m_armor2)
	_box(h, Vector3(1.25, 0.32, 2.4), Vector3(0, 3.3, 0.25), m_armor, Vector3(-0.04, 0, 0))
	_box(h, Vector3(0.45, 0.2, 2.2), Vector3(0, 3.5, 0.3), m_armor2)
	_box(h, Vector3(0.12, 0.05, 2.0), Vector3(0, 3.61, 0.3), m_accent)
	# нос клином: верх уходит вниз к острию, снизу подбородок
	_box(h, Vector3(1.0, 0.5, 1.25), Vector3(0, 3.05, -1.1), m_armor, Vector3(-0.28, 0, 0))
	_box(h, Vector3(0.55, 0.38, 0.6), Vector3(0, 2.8, -1.55), m_armor, Vector3(-0.28, 0, 0))
	_box(h, Vector3(0.85, 0.3, 0.9), Vector3(0, 2.58, -0.95), m_armor2, Vector3(0.35, 0, 0))
	_box(h, Vector3(0.5, 0.06, 0.05), Vector3(0, 2.92, -1.73), m_glow, Vector3(-0.28, 0, 0))
	# корма и выхлопы
	_box(h, Vector3(1.4, 0.75, 0.9), Vector3(0, 2.95, 1.55), m_armor)
	for k in 4:
		_box(h, Vector3(0.15, 0.22, 0.45), Vector3((k - 1.5) * 0.3, 2.85, 2.0), m_dark)
	for s in [-1.0, 1.0]:
		# боковые секции, плечо к орудийному блоку, короб на плече
		_box(h, Vector3(0.42, 0.62, 2.2), Vector3(0.8 * s, 2.95, 0.35), m_armor)
		_box(h, Vector3(0.55, 0.42, 0.7), Vector3(0.78 * s, 2.86, -0.45), m_dark)
		_box(h, Vector3(0.32, 0.36, 0.7), Vector3(0.72 * s, 3.36, -0.35), m_armor2)
		_box(h, Vector3(0.08, 0.04, 0.6), Vector3(0.72 * s, 3.55, -0.35), m_accent)
		_box(h, Vector3(0.14, 0.08, 0.05), Vector3(0.3 * s, 2.62, -1.4), m_light)
	return pods


# орудийный блок среднего по модели. Возвращает true, если стволы автопушки поставлены свои
func _pod_mid_new(pod: Node3D, s: float, twin: bool) -> bool:
	var side := "l" if s < 0.0 else "r"
	if look_mid == 2:
		_model(pod, "pod_" + side)
		if twin:
			_model(pod, "barrels_" + side)
		return twin
	var h := _holder(pod, Transform3D(Basis.IDENTITY, -(Vector3(0, HIP_H0 + WAIST_UP, 0) + Vector3(MID_POD.x * s, MID_POD.y, MID_POD.z))))
	var x := MID_POD.x
	_box(h, Vector3(0.7, 0.62, 2.3), Vector3(x * s, 2.8, -0.05), m_armor)
	_box(h, Vector3(0.6, 0.18, 1.8), Vector3((x - 0.02) * s, 3.17, 0.1), m_armor2)
	_box(h, Vector3(0.14, 0.55, 1.6), Vector3((x + 0.4) * s, 2.8, 0.15), m_armor2)
	_box(h, Vector3(0.08, 0.05, 1.5), Vector3((x + 0.15) * s, 3.27, 0.1), m_accent)
	_box(h, Vector3(0.6, 0.5, 0.3), Vector3(x * s, 2.85, 1.2), m_dark)
	_box(h, Vector3(0.55, 0.5, 0.25), Vector3(x * s, 2.62, -1.22), m_dark)
	if twin:
		var my := HIP_H0 + WAIST_UP + MID_POD.y + MID_MUZZLE.y
		for b in [-0.08, 0.08]:
			_cyl(h, 0.055, 1.15, Vector3(x * s, my + b, -1.82), m_dark, Vector3(PI / 2, 0, 0))
			_cyl(h, 0.075, 0.15, Vector3(x * s, my + b, -1.75), m_armor2, Vector3(PI / 2, 0, 0))
			_cyl(h, 0.08, 0.2, Vector3(x * s, my + b, -2.3), m_armor2, Vector3(PI / 2, 0, 0))
	return twin


# тяжёлый: широкая плита-бункер с вертикальной лобовой бронёй, боковые спонсоны с пушками,
# рубка сверху, выхлопные трубы, юбки над ногами
func _hull_heavy() -> Array:
	_box(torso, Vector3(2.3, 1.25, 2.3), Vector3(0, 0.88, 0.05), m_armor2)
	_box(torso, Vector3(2.6, 0.4, 2.5), Vector3(0, 0.3, 0.05), m_dark)
	# лобовой лист почти вертикально, смотровые щели
	_box(torso, Vector3(2.45, 1.15, 0.38), Vector3(0, 0.88, -1.22), m_armor, Vector3(0.12, 0, 0))
	for k in 3:
		_box(torso, Vector3(0.36, 0.06, 0.05), Vector3((k - 1) * 0.5, 1.22, -1.43), m_glow)
	for sx in [-1.0, 1.0]:
		_box(torso, Vector3(0.18, 0.1, 0.05), Vector3(0.95 * sx, 0.55, -1.43), m_light)
	# палуба и рубка
	_box(torso, Vector3(2.2, 0.3, 2.1), Vector3(0, 1.65, 0.1), m_armor)
	_box(torso, Vector3(1.1, 0.5, 1.0), Vector3(0.35, 2.05, 0.35), m_armor2)
	_box(torso, Vector3(0.7, 0.07, 0.05), Vector3(0.35, 2.12, -0.16), m_glow)
	_box(torso, Vector3(0.16, 0.06, 2.0), Vector3(-0.7, 1.82, 0.1), m_accent)
	# выхлопные трубы сзади
	for sx in [-1.0, 1.0]:
		_cyl(torso, 0.16, 1.1, Vector3(0.7 * sx, 2.1, 1.05), m_dark)
		_cyl(torso, 0.2, 0.12, Vector3(0.7 * sx, 2.62, 1.05), m_armor2)
	# моторный отсек
	_box(torso, Vector3(1.9, 0.95, 0.6), Vector3(0, 0.95, 1.45), m_armor)
	for i in 4:
		_box(torso, Vector3(1.6, 0.05, 0.08), Vector3(0, 0.7 + i * 0.16, 1.77), m_dark)
	for sx in [-1.0, 1.0]:
		# спонсон с пушкой
		_box(torso, Vector3(0.75, 1.0, 2.0), Vector3(1.5 * sx, 0.85, -0.05), m_armor)
		_box(torso, Vector3(0.12, 0.8, 1.8), Vector3(1.9 * sx, 0.8, -0.05), m_armor2)
		for k in 4:
			_box(torso, Vector3(0.14, 0.12, 0.12), Vector3(1.97 * sx, 0.9, -0.75 + k * 0.5), m_dark)
		_box(torso, Vector3(0.05, 0.14, 1.2), Vector3(1.98 * sx, 1.15, -0.05), m_accent)
	return [Vector3(-1.72, 0.85, -0.55), Vector3(1.72, 0.85, -0.55)]


# детали, по которым конкретного меха узнают издалека
func _build_style_parts() -> void:
	match style:
		"scout":
			# разведчик: тарелка радара (крутится) и две длинные антенны на хвосте
			_radar = Node3D.new()
			_radar.position = Vector3(0, 1.0, 0.2)
			torso.add_child(_radar)
			_cyl(_radar, 0.08, 0.35, Vector3(0, 0.1, 0), m_dark)
			_cyl(_radar, 0.55, 0.06, Vector3(0, 0.32, 0), m_armor2, Vector3(0.35, 0, 0))
			_box(_radar, Vector3(0.1, 0.1, 0.1), Vector3(0, 0.45, -0.2), m_glow)
			for s in [-1.0, 1.0]:
				_box(torso, Vector3(0.03, 2.0, 0.03), Vector3(0.25 * s, 1.9, 1.9), m_dark)
				_box(torso, Vector3(0.07, 0.07, 0.07), Vector3(0.25 * s, 2.9, 1.9), m_glow)
		"repair":
			# механик: ящик с инструментом на ранце, кран-манипулятор, зелёный маячок
			# (у среднего по модели корпус ниже: всё опускаем)
			var up := Vector3(0, -0.6, 0) if look_mid > 0 else Vector3.ZERO
			_box(torso, Vector3(1.1, 0.6, 0.7), Vector3(0, 1.7, 1.25) + up, m_armor2)
			var green := _unshaded(Color(0.35, 1.0, 0.5) * 2.0)
			_cyl(torso, 0.1, 0.18, Vector3(0.35, 2.1, 1.35) + up, green)
			_box(torso, Vector3(0.12, 0.12, 1.5), Vector3(-0.42, 2.05, 0.75) + up, m_dark, Vector3(0.5, 0, 0))
			_box(torso, Vector3(0.16, 0.4, 0.16), Vector3(-0.42, 2.15, 0.05) + up, m_accent)
		"ram":
			# таран: отвал спереди и рога (у среднего по модели нос длиннее, а пушки шире:
			# отвал уже и вынесен вперёд)
			var w := 0.7 if look_mid > 0 else 1.0
			var dz := -0.4 if look_mid > 0 else 0.0
			_box(torso, Vector3(2.4 * w, 1.1, 0.32), Vector3(0, 0.55, -1.45 + dz), m_armor, Vector3(-0.25, 0, 0))
			_box(torso, Vector3(2.5 * w, 0.12, 0.38), Vector3(0, 0.05, -1.55 + dz), m_dark)
			for s in [-1.0, 1.0]:
				_box(torso, Vector3(0.2, 0.2, 0.9), Vector3(1.05 * w * s, 0.6, -1.85 + dz), m_dark, Vector3(0, 0.25 * s, 0))
			for i in 3:
				_box(torso, Vector3(2.1 * w, 0.06, 0.05), Vector3(0, 0.3 + i * 0.3, -1.63 + dz), m_accent, Vector3(-0.25, 0, 0))
		"siege":
			# мортира: короба боезапаса на палубе и упоры сзади (опускаются, когда стоит)
			_box(torso, Vector3(1.0, 0.5, 0.9), Vector3(-0.55, 2.05, -0.25), m_armor2)
			for i in 3:
				_box(torso, Vector3(1.02, 0.06, 0.06), Vector3(-0.55, 1.9 + i * 0.15, 0.21), m_accent)
			for s in [-1.0, 1.0]:
				var strut := Node3D.new()
				strut.position = Vector3(0.95 * s, 0.5, 1.75)
				torso.add_child(strut)
				_box(strut, Vector3(0.2, 0.2, 1.7), Vector3(0, 0, 0.85), m_dark)
				_box(strut, Vector3(0.5, 0.14, 0.5), Vector3(0, -0.05, 1.7), m_armor2)
				_struts.append(strut)
		"bastion":
			# бастион: наслоенные лобовые плиты и бортовые юбки
			for i in 3:
				_box(torso, Vector3(2.3 - i * 0.3, 0.34, 0.24), Vector3(0, 0.45 + i * 0.36, -1.5 - i * 0.04), m_armor, Vector3(-0.25, 0, 0))
			for s in [-1.0, 1.0]:
				_box(torso, Vector3(0.12, 0.8, 2.3), Vector3(2.1 * s, 0.5, 0.0), m_armor2)
				for k in 4:
					_box(torso, Vector3(0.14, 0.08, 0.08), Vector3(2.17 * s, 0.7, -0.85 + k * 0.55), m_dark)


# строит пушку на подвесе, возвращает, где кончается ствол.
# housing = false: только стволы, кожух даёт сам корпус меха (средний по модели)
func _build_weapon(pod: Node3D, look: String, s: float, gun := 0, housing := true) -> float:
	var hp: Node3D = pod if housing else Node3D.new()
	var muzzle_z := _weapon_parts(pod, hp, look, s, gun)
	if not housing:
		hp.free()
	return muzzle_z


# строит пушку на подвесе (кожух в hp, стволы в pod), возвращает, где кончается ствол
func _weapon_parts(pod: Node3D, hp: Node3D, look: String, s: float, gun: int) -> float:
	match look:
		"heavy":
			# тяжёлое орудие: один толстый длинный ствол
			_box(hp, Vector3(0.86, 0.9, 1.7), Vector3.ZERO, m_armor)
			_box(hp, Vector3(0.14, 1.0, 1.4), Vector3(0.48 * s, 0.06, 0.0), m_armor2)
			_box(hp, Vector3(0.2, 0.05, 1.4), Vector3(0, 0.47, 0.0), m_accent)
			_box(hp, Vector3(0.7, 0.6, 0.35), Vector3(0, 0, 0.95), m_dark)
			_cyl(pod, 0.2, 2.0, Vector3(0, -0.05, -1.75), m_dark, Vector3(PI / 2, 0, 0))
			_cyl(pod, 0.27, 0.45, Vector3(0, -0.05, -1.05), m_armor2, Vector3(PI / 2, 0, 0))
			_box(pod, Vector3(0.5, 0.36, 0.42), Vector3(0, -0.05, -2.75), m_armor2)
			return -2.95
		"laser":
			# лазер: гладкий кожух со светящейся линзой
			_box(hp, Vector3(0.72, 0.72, 1.6), Vector3.ZERO, m_armor)
			_box(hp, Vector3(0.12, 0.8, 1.3), Vector3(0.42 * s, 0.04, 0.0), m_armor2)
			_box(hp, Vector3(0.2, 0.05, 1.3), Vector3(0, 0.39, 0.0), m_accent)
			_box(pod, Vector3(0.5, 0.5, 1.0), Vector3(0, -0.05, -1.25), m_armor2)
			_box(pod, Vector3(0.36, 0.36, 0.5), Vector3(0, -0.05, -1.9), m_dark)
			_box(pod, Vector3(0.24, 0.24, 0.08), Vector3(0, -0.05, -2.17), m_beam)
			return -2.2
		"blaster":
			# бластер: ствол с катушками, светятся голубым
			_box(hp, Vector3(0.7, 0.7, 1.4), Vector3.ZERO, m_armor)
			_box(hp, Vector3(0.2, 0.05, 1.2), Vector3(0, 0.37, 0.0), m_accent)
			_cyl(pod, 0.12, 1.7, Vector3(0, -0.05, -1.3), m_dark, Vector3(PI / 2, 0, 0))
			var coil := _unshaded(Color(0.4, 0.9, 1.0) * 2.2)
			for k in 4:
				_cyl(pod, 0.22, 0.1, Vector3(0, -0.05, -0.75 - k * 0.32), coil, Vector3(PI / 2, 0, 0))
			_cyl(pod, 0.2, 0.25, Vector3(0, -0.05, -2.15), m_armor2, Vector3(PI / 2, 0, 0))
			return -2.3
		"grenade":
			# гранатомёт: толстая короткая труба и барабан
			_box(hp, Vector3(0.78, 0.8, 1.3), Vector3.ZERO, m_armor)
			_cyl(hp, 0.45, 0.5, Vector3(0, 0.1, 0.15), m_armor2, Vector3(0, 0, PI / 2))
			_cyl(pod, 0.26, 1.4, Vector3(0, -0.05, -1.15), m_dark, Vector3(PI / 2, 0, 0))
			_cyl(pod, 0.31, 0.2, Vector3(0, -0.05, -1.75), m_armor2, Vector3(PI / 2, 0, 0))
			_box(hp, Vector3(0.2, 0.05, 1.1), Vector3(0, 0.41, 0.0), m_accent)
			return -1.85
		"shotgun":
			# дробовик: два широких коротких ствола
			_box(hp, Vector3(0.8, 0.75, 1.3), Vector3.ZERO, m_armor)
			_box(hp, Vector3(0.2, 0.05, 1.1), Vector3(0, 0.39, 0.0), m_accent)
			for b in [-0.18, 0.18]:
				_cyl(pod, 0.16, 1.2, Vector3(b, -0.05, -1.2), m_dark, Vector3(PI / 2, 0, 0))
			_box(pod, Vector3(0.75, 0.42, 0.3), Vector3(0, -0.05, -0.7), m_armor2)
			return -1.8
		"rail":
			# рельсотрон: две длинные рельсы, между ними разгорается заряд
			_box(hp, Vector3(0.8, 0.8, 1.6), Vector3.ZERO, m_armor)
			_box(hp, Vector3(0.2, 0.05, 1.4), Vector3(0, 0.42, 0.0), m_accent)
			for b in [-0.2, 0.2]:
				_box(pod, Vector3(0.12, 0.34, 2.6), Vector3(b, -0.05, -1.9), m_armor2)
			var cm := StandardMaterial3D.new()
			cm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			cm.albedo_color = Color(0.5, 0.9, 1.0)
			cm.emission_enabled = true
			cm.emission = Color(0.5, 0.9, 1.0)
			cm.emission_energy_multiplier = 0.4
			_box(pod, Vector3(0.12, 0.12, 2.4), Vector3(0, -0.05, -1.9), cm)
			_charge_mats[gun] = cm
			return -3.2
		"minigun":
			# Гатлинг: блок из шести стволов, крутится при стрельбе
			_box(hp, Vector3(0.8, 0.8, 1.3), Vector3.ZERO, m_armor)
			_box(hp, Vector3(0.2, 0.05, 1.1), Vector3(0, 0.42, 0.0), m_accent)
			var sp := Node3D.new()
			sp.position = Vector3(0, -0.05, -0.65)
			pod.add_child(sp)
			for k in 6:
				var a := TAU * k / 6.0
				_cyl(sp, 0.06, 1.7, Vector3(cos(a) * 0.17, sin(a) * 0.17, -0.85), m_dark, Vector3(PI / 2, 0, 0))
			_cyl(sp, 0.26, 0.12, Vector3(0, 0, -1.5), m_armor2, Vector3(PI / 2, 0, 0))
			_cyl(sp, 0.26, 0.12, Vector3(0, 0, -0.3), m_armor2, Vector3(PI / 2, 0, 0))
			_spinners[gun] = sp
			return -2.4
		_:
			# автопушка: два ствола
			_box(hp, Vector3(0.78, 0.8, 1.55), Vector3.ZERO, m_armor)
			_box(hp, Vector3(0.14, 0.95, 1.3), Vector3(0.44 * s, 0.06, 0.0), m_armor2)
			_box(hp, Vector3(0.2, 0.05, 1.3), Vector3(0, 0.42, 0.0), m_accent)
			_box(hp, Vector3(0.6, 0.5, 0.3), Vector3(0, 0, 0.85), m_dark)
			for b in [-0.17, 0.17]:
				_cyl(pod, 0.1, 1.5, Vector3(b, -0.05, -1.45), m_dark, Vector3(PI / 2, 0, 0))
				_cyl(pod, 0.145, 0.3, Vector3(b, -0.05, -2.1), m_armor2, Vector3(PI / 2, 0, 0))
			_box(pod, Vector3(0.6, 0.34, 0.5), Vector3(0, -0.05, -0.95), m_armor2)
			return -2.25


# нога: бедро, колено (одно, назад), голень, ступня. Вид зависит от класса:
#   лёгкий  — тонкие ноги и птичья лапа (три пальца вперёд, шпора назад, как в батлтеке);
#   средний — массивные бронированные бёдра и голени, тяжёлый ботинок (как на референсе);
#   тяжёлый — толстые колонны с наслоенной бронёй и широкая платформа-ступня на четырёх опорах
func _build_leg(side: float) -> Foot:
	var f := Foot.new()
	f.thigh = Node3D.new()
	add_child(f.thigh)
	f.knee = Node3D.new()
	add_child(f.knee)
	f.shin = Node3D.new()
	add_child(f.shin)
	f.node = Node3D.new()
	add_child(f.node)
	if look_mid > 0:
		_leg_mid_new(f, side)
		return f
	match cls:
		"light":
			_box(f.thigh, Vector3(0.26, L1, 0.32), Vector3.ZERO, m_dark)
			_box(f.thigh, Vector3(0.42, L1 * 0.7, 0.24), Vector3(0.04 * side, 0.08, -0.22), m_armor)
			_cyl(f.thigh, 0.05, L1 * 0.8, Vector3(-0.04 * side, 0.0, 0.22), m_accent)
			_cyl(f.knee, 0.22, 0.45, Vector3.ZERO, m_armor2, Vector3(0, 0, PI / 2))
			_box(f.shin, Vector3(0.22, L2, 0.28), Vector3.ZERO, m_dark)
			_box(f.shin, Vector3(0.36, L2 * 0.55, 0.36), Vector3(0, 0.12, -0.08), m_armor)
			_cyl(f.shin, 0.045, L2 * 0.85, Vector3(0, 0.0, 0.2), m_accent)
			# птичья лапа
			_cyl(f.node, 0.16, 0.36, Vector3(0, ANKLE_H, 0), m_dark, Vector3(0, 0, PI / 2))
			_box(f.node, Vector3(0.36, 0.2, 0.36), Vector3(0, 0.16, 0), m_armor2)
			for t in [-0.42, 0.0, 0.42]:
				var toe := Node3D.new()
				toe.position = Vector3(0, 0.1, -0.1)
				toe.rotation.y = t
				f.node.add_child(toe)
				_box(toe, Vector3(0.16, 0.14, 0.75), Vector3(0, 0.0, -0.38), m_armor)
				_box(toe, Vector3(0.12, 0.1, 0.25), Vector3(0, -0.03, -0.82), m_dark, Vector3(0.35, 0, 0))
			_box(f.node, Vector3(0.14, 0.12, 0.55), Vector3(0, 0.08, 0.38), m_armor, Vector3(-0.25, 0, 0))
		"heavy":
			_box(f.thigh, Vector3(0.6, L1, 0.7), Vector3.ZERO, m_dark)
			_box(f.thigh, Vector3(0.95, L1 * 0.9, 0.42), Vector3(0.05 * side, 0.02, -0.38), m_armor)
			_box(f.thigh, Vector3(0.26, L1 * 0.85, 1.0), Vector3(0.5 * side, 0.0, -0.05), m_armor2)
			_box(f.thigh, Vector3(0.75, L1 * 0.5, 0.3), Vector3(0, -0.15, 0.4), m_armor2)
			_cyl(f.thigh, 0.1, L1 * 0.85, Vector3(-0.1 * side, 0.0, 0.45), m_accent)
			_cyl(f.knee, 0.45, 0.95, Vector3.ZERO, m_armor2, Vector3(0, 0, PI / 2))
			_box(f.knee, Vector3(0.8, 0.5, 0.45), Vector3(0, 0.05, 0.38), m_armor)
			_box(f.shin, Vector3(0.55, L2, 0.6), Vector3.ZERO, m_dark)
			_box(f.shin, Vector3(0.92, L2 * 0.75, 0.85), Vector3(0.04 * side, -0.1, -0.12), m_armor)
			_box(f.shin, Vector3(0.24, L2 * 0.6, 0.95), Vector3(0.52 * side, -0.12, 0.0), m_armor2)
			for k in 3:
				_box(f.shin, Vector3(0.94, 0.06, 0.05), Vector3(0.04 * side, -0.4 + k * 0.28, -0.56), m_dark)
			# платформа на четырёх опорах
			_cyl(f.node, 0.3, 0.7, Vector3(0, ANKLE_H, 0), m_dark, Vector3(0, 0, PI / 2))
			_box(f.node, Vector3(1.2, 0.32, 1.5), Vector3(0, 0.2, -0.1), m_armor2)
			_box(f.node, Vector3(1.05, 0.2, 1.2), Vector3(0, 0.42, -0.1), m_armor)
			for px in [-0.5, 0.5]:
				for pz in [-0.75, 0.55]:
					_box(f.node, Vector3(0.45, 0.16, 0.45), Vector3(px, 0.08, pz), m_dark)
		_:
			_box(f.thigh, Vector3(0.42, L1, 0.5), Vector3.ZERO, m_dark)
			_box(f.thigh, Vector3(0.8, L1 * 0.88, 0.4), Vector3(0.06 * side, 0.02, -0.32), m_armor)
			_box(f.thigh, Vector3(0.22, L1 * 0.8, 0.85), Vector3(0.42 * side, 0.0, -0.04), m_armor2)
			_box(f.thigh, Vector3(0.55, 0.25, 0.5), Vector3(0, L1 * 0.36, -0.42), m_armor2, Vector3(0.4, 0, 0))
			_cyl(f.thigh, 0.08, L1 * 0.8, Vector3(-0.06 * side, 0.0, 0.34), m_accent)
			_cyl(f.knee, 0.36, 0.78, Vector3.ZERO, m_armor2, Vector3(0, 0, PI / 2))
			_cyl(f.knee, 0.2, 0.86, Vector3.ZERO, m_dark, Vector3(0, 0, PI / 2))
			_box(f.knee, Vector3(0.6, 0.42, 0.32), Vector3(0, 0.05, 0.32), m_armor)
			_box(f.shin, Vector3(0.4, L2, 0.48), Vector3.ZERO, m_dark)
			_box(f.shin, Vector3(0.76, L2 * 0.7, 0.72), Vector3(0.04 * side, -0.12, -0.1), m_armor)
			_box(f.shin, Vector3(0.2, L2 * 0.55, 0.85), Vector3(0.42 * side, -0.12, 0.0), m_armor2)
			_cyl(f.shin, 0.06, L2 * 0.8, Vector3(0, 0.05, 0.32), m_accent)
			# тяжёлый ботинок с носком и пяткой
			_cyl(f.node, 0.24, 0.55, Vector3(0, ANKLE_H, 0), m_dark, Vector3(0, 0, PI / 2))
			_box(f.node, Vector3(0.9, 0.3, 1.45), Vector3(0, 0.15, -0.2), m_armor2)
			_box(f.node, Vector3(1.0, 0.26, 0.65), Vector3(0, 0.24, -0.72), m_armor, Vector3(-0.12, 0, 0))
			_box(f.node, Vector3(0.6, 0.24, 0.5), Vector3(0, 0.18, 0.62), m_dark)
			_box(f.node, Vector3(0.7, 0.3, 0.45), Vector3(0, 0.45, -0.05), m_armor)
	return f


# нога среднего по модели: массивное бедро с бронеплитой вперёд, колено сзади, голень к щиколотке,
# широкая ступня. Коробки заданы в позе модели (метры игры), держатели переносят их в кости.
func _leg_mid_new(f: Foot, s: float) -> void:
	var hip := Vector3(absf(MID_HIP.x) * s, MID_HIP.y, MID_HIP.z)
	var knee := Vector3(absf(MID_KNEE.x) * s, MID_KNEE.y, MID_KNEE.z)
	var ankle := Vector3(absf(MID_ANKLE.x) * s, MID_ANKLE.y, MID_ANKLE.z)
	var thigh_tr := _bone_tr(hip, knee, _l1)
	var shin_tr := _bone_tr(knee, ankle, _l2)
	var knee_tr := _bone_tr(hip, knee, -1.0)
	knee_tr.origin = knee_tr.basis * -knee
	var foot_tr := Transform3D(Basis.IDENTITY, -Vector3(ankle.x, 0, ankle.z))
	if look_mid == 2:
		var side := "l" if s < 0.0 else "r"
		_model(f.thigh, "thigh_" + side).scale = Vector3(1, _l1, 1)
		_model(f.knee, "knee_" + side)
		_model(f.shin, "shin_" + side).scale = Vector3(1, _l2, 1)
		_model(f.node, "foot_" + side)
		return
	var x := absf(MID_HIP.x)
	# бедро
	var t := _holder(f.thigh, thigh_tr)
	_box(t, Vector3(0.75, 0.95, 1.35), Vector3((x + 0.1) * s, 1.85, -0.2), m_armor)
	_box(t, Vector3(0.7, 0.45, 0.5), Vector3((x + 0.1) * s, 1.48, -0.75), m_armor2, Vector3(-0.6, 0, 0))
	_box(t, Vector3(0.66, 0.12, 1.1), Vector3((x + 0.1) * s, 2.36, -0.1), m_armor2)
	_box(t, Vector3(0.12, 0.7, 1.0), Vector3((x + 0.5) * s, 1.85, -0.25), m_armor2)
	_box(t, Vector3(0.42, 0.8, 0.42), Vector3((x + 0.05) * s, 1.65, 0.42), m_dark, Vector3(0.45, 0, 0))
	_box(t, Vector3(0.3, 0.45, 0.45), Vector3((x - 0.2) * s, 2.05, 0), m_dark)
	# колено
	var k := _holder(f.knee, knee_tr)
	_cyl(k, 0.22, 0.75, knee, m_dark, Vector3(0, 0, PI / 2))
	_cyl(k, 0.26, 0.12, knee + Vector3(0.36 * s, 0, 0), m_armor2, Vector3(0, 0, PI / 2))
	# голень
	var sh := _holder(f.shin, shin_tr)
	_box(sh, Vector3(0.7, 0.9, 0.7), Vector3(1.2 * s, 1.0, 0.25), m_armor2, Vector3(0.6, 0, 0))
	_box(sh, Vector3(0.6, 0.8, 0.2), Vector3(1.22 * s, 1.0, -0.15), m_armor, Vector3(0.6, 0, 0))
	_box(sh, Vector3(0.25, 0.7, 0.25), Vector3(1.15 * s, 1.0, 0.72), m_dark, Vector3(0.3, 0, 0))
	# ступня
	var ft := _holder(f.node, foot_tr)
	var fx := absf(MID_ANKLE.x) + 0.05
	_box(ft, Vector3(1.0, 0.25, 1.85), Vector3(fx * s, 0.13, 0.05), m_armor2)
	_box(ft, Vector3(0.9, 0.35, 0.7), Vector3(fx * s, 0.35, -0.55), m_armor, Vector3(-0.25, 0, 0))
	_box(ft, Vector3(0.75, 0.3, 0.55), Vector3(fx * s, 0.3, 0.7), m_armor2)
	_box(ft, Vector3(0.65, 0.45, 0.6), Vector3(ankle.x, 0.5, 0.05), m_armor)
	_cyl(ft, 0.18, 0.55, ankle, m_dark, Vector3(0, 0, PI / 2))


# перевод из позы модели в координаты кости (как в tools/medium1_cut.py): ось Y вдоль кости,
# длина кости растягивается до length (length < 0 — без растяжки, только поворот)
func _bone_tr(top: Vector3, bottom: Vector3, length: float) -> Transform3D:
	var yv := (top - bottom).normalized()
	var zv := Vector3.RIGHT.cross(yv).normalized()
	var xv := yv.cross(zv).normalized()
	var b := Basis(xv, yv, zv).transposed()
	if length > 0.0:
		b = Basis.from_scale(Vector3(1, length / top.distance_to(bottom), 1)) * b
	return Transform3D(b, b * -((top + bottom) * 0.5))


# узел-держатель для деталей, заданных в позе модели
func _holder(parent: Node3D, tr: Transform3D) -> Node3D:
	var h := Node3D.new()
	h.transform = tr
	parent.add_child(h)
	return h


# часть 3D-модели medium1; её материалы заменяются на материалы меха (с затенением из цвета вершин)
func _model(parent: Node3D, part: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh: Mesh = _model_mesh(part)
	mi.mesh = mesh
	for si in mesh.get_surface_count():
		var src := mesh.surface_get_material(si)
		var nm := src.resource_name if src != null else ""
		mi.set_surface_override_material(si, m_dark_v if nm == "dark" else (m_armor2_v if nm == "armor2" else m_armor_v))
	parent.add_child(mi)
	return mi


func _model_mesh(part: String) -> Mesh:
	if not _model_meshes.has("_loaded"):
		_model_meshes["_loaded"] = true
		if ResourceLoader.exists(MEDIUM1):
			var scene: PackedScene = load(MEDIUM1)
			var root := scene.instantiate()
			for n in root.find_children("*", "MeshInstance3D", true, false):
				_model_meshes[String(n.name)] = (n as MeshInstance3D).mesh
			root.free()
	return _model_meshes.get(part)


func _vcol(m: StandardMaterial3D) -> StandardMaterial3D:
	var v: StandardMaterial3D = m.duplicate()
	v.vertex_color_use_as_albedo = true
	# верх (его и видно сверху) почти без затенения, а щели тёмные: чуть подсветим, чтобы яркость была как у коробок
	var a := v.albedo_color.a
	v.albedo_color = v.albedo_color * 1.1
	v.albedo_color.a = a
	return v


# ------------------------------------------------------------------
#  ОБНОВЛЕНИЕ КАЖДЫЙ КАДР
# ------------------------------------------------------------------

func _s(key: String, def: float) -> float:
	return float(st.get(key, def))


# короткая белая вспышка: по меху попали
func flash() -> void:
	_flash_t = 0.07


# после возрождения ноги ставятся заново под корпус
func reset() -> void:
	_inited = false
	_flash_t = 0.0
	stunned = false
	recoil = 0.0
	phase = 0.0
	_lean = Vector3.ZERO
	for f in feet:
		f.swinging = false
		f.quick = -1.0
		f.air = 0.0
	for b in beams:
		b.visible = false


func kick(gun: int, amount: float) -> void:
	gun_kick[gun] = amount * Cfg.recoil_kick
	flash_t[gun] = 0.05
	recoil = minf(recoil + 0.05 + amount * 0.1, 0.18)


func get_muzzle(gun: int) -> Vector3:
	return muzzles[gun].global_position


func get_missile_port(side: int) -> Vector3:
	return missile_ports[side].global_position


func kick_missile(side: int) -> void:
	missile_flash_t[side] = 0.07
	recoil = minf(recoil + 0.06, 0.14)


# луч лазера от ствола до точки попадания
func set_beam(gun: int, on: bool, from := Vector3.ZERO, to := Vector3.ZERO) -> void:
	var b := beams[gun]
	var was_on := b.visible
	b.visible = on
	if not on:
		return
	var d := to - from
	var len := maxf(d.length(), 0.05)
	var w := 0.12 + 0.05 * sin(Time.get_ticks_msec() * 0.05 + gun)
	var basis := Basis.looking_at(d.normalized(), Vector3.UP if absf(d.normalized().y) < 0.99 else Vector3.RIGHT)
	b.global_transform = Transform3D((basis * Basis.from_scale(Vector3(w, w, len))), from + d * 0.5)
	# луч только что включился: не сглаживать от старого положения (иначе на один кадр
	# мелькает длинная полоса через полкарты — от места, где луч горел в прошлый раз)
	if not was_on:
		b.reset_physics_interpolation()


func update_visual(delta: float, body_pos: Vector3, vel: Vector3, legs_yaw: float, torso_yaw: float, dashing: bool) -> void:
	var vel_h := Vector3(vel.x, 0, vel.z)
	var speed := vel_h.length()
	var walk := maxf(_s("walk_speed", 6.0), 0.1)
	var run := maxf(_s("run_speed", 9.5), 0.1)

	# подсветка брони: белая вспышка при попадании, синее мерцание при оглушении
	_flash_t = maxf(_flash_t - delta, 0.0)
	var glow := Color(0, 0, 0)
	if _flash_t > 0.0:
		glow = Color(0.2, 0.2, 0.2)
	elif stunned:
		glow = Color(0.1, 0.3, 0.8) * (0.6 + 0.4 * sin(Time.get_ticks_msec() * 0.025))
	m_armor.emission = glow
	m_armor2.emission = glow
	if m_armor_v != null:
		m_armor_v.emission = glow
		m_armor2_v.emission = glow

	if not _inited:
		_inited = true
		var r0 := Vector3(cos(legs_yaw), 0, -sin(legs_yaw))
		for i in 2:
			var s := -1.0 if i == 0 else 1.0
			feet[i].pos = body_pos + r0 * s * _foot_x * ls
			feet[i].yaw = legs_yaw

	_update_feet(delta, body_pos, vel_h, legs_yaw, dashing, walk, run)

	# посадка и покачивание корпуса
	var t := clampf(speed / run, 0.0, 1.0)
	var crouch_target := (0.1 * t + (0.22 if dashing else 0.0)) * ls
	_crouch = lerpf(_crouch, crouch_target, 1.0 - exp(-12.0 * delta))
	var bob := cos(phase * TAU * 2.0) * 0.05 * ls * minf(speed / walk, 1.0)
	var hip_y := hip_h() - _crouch + bob

	# наклон в сторону движения
	var lean_target := vel_h / run * deg_to_rad(Cfg.lean_deg)
	if dashing:
		lean_target *= 1.6
	_lean = _lean.lerp(lean_target, 1.0 - exp(-9.0 * delta))
	var lean_b := Basis.IDENTITY
	var lean_half := Basis.IDENTITY
	var la := _lean.length()
	if la > 0.001:
		var axis := Vector3.UP.cross(_lean / la).normalized()
		lean_b = Basis(axis, la)
		lean_half = Basis(axis, la * 0.5)

	var hip_pos := body_pos + Vector3.UP * hip_y
	var legs_b := lean_half * Basis(Vector3.UP, legs_yaw)
	legs_root.global_transform = Transform3D((legs_b * Basis.from_scale(Vector3.ONE * ls)), hip_pos)

	# корпус с отдачей
	recoil *= exp(-14.0 * delta)
	var tfwd := Vector3(-sin(torso_yaw), 0, -cos(torso_yaw))
	var sway := sin(phase * TAU) * 0.025 * minf(speed / walk, 1.0)
	var tb := lean_b * Basis(Vector3.UP, torso_yaw) * Basis(Vector3.FORWARD, sway)
	torso.global_transform = Transform3D((tb * Basis.from_scale(Vector3.ONE * hs)), hip_pos + lean_half * (Vector3.UP * WAIST_UP * ls) - tfwd * recoil)

	for i in 2:
		gun_kick[i] *= exp(-16.0 * delta)
		gun_pods[i].position.z = -0.1 + gun_kick[i]
		flash_t[i] -= delta
		flashes[i].visible = flash_t[i] > 0.0
		missile_flash_t[i] -= delta
		missile_flashes[i].visible = missile_flash_t[i] > 0.0
	if _radar != null:
		_radar.rotation.y += delta * 2.0
	_brace_k = move_toward(_brace_k, 1.0 if braced else 0.0, delta * 3.0)
	for st_i in _struts.size():
		_struts[st_i].rotation.x = lerpf(-0.15, 0.55, _brace_k)
	for th in thrusters:
		th.visible = dashing and not airborne
		if dashing:
			th.scale = Vector3(1, 1, randf_range(0.7, 1.3))

	# ноги: от бедра до ступни
	var right := legs_b.x.normalized()
	var back := legs_b.z.normalized()
	for i in 2:
		var s := -1.0 if i == 0 else 1.0
		var hip := legs_root.global_transform * Vector3(_hip_x * s, 0, 0)
		_solve_leg(feet[i], hip, back, right)


func _update_feet(delta: float, body_pos: Vector3, vel_h: Vector3, legs_yaw: float, dashing: bool, walk: float, run: float) -> void:
	var speed := vel_h.length()
	var moving := speed > 0.6
	var dirv := vel_h / speed if speed > 0.01 else Vector3.ZERO
	var t := clampf(speed / run, 0.0, 1.0)
	var stride := lerpf(_s("stride_walk", 3.4), _s("stride_run", 5.4), t) * ls
	var swing_frac := lerpf(0.42, 0.55, t)
	var stance_half := stride * (1.0 - swing_frac) * 0.5
	var right := Vector3(cos(legs_yaw), 0, -sin(legs_yaw))
	var ground := body_pos.y
	var lift := Cfg.step_lift * ls
	var foot_x := _foot_x * ls

	if moving and not _was_moving:
		phase = 0.0
	_was_moving = moving
	if moving and not dashing:
		phase = fposmod(phase + speed * delta / stride, 1.0)

	for i in 2:
		var f := feet[i]
		var other := feet[1 - i]
		var side := -1.0 if i == 0 else 1.0
		var home := body_pos + right * side * foot_x
		home.y = ground

		# рывок: ноги поджаты и скользят за корпусом
		if dashing:
			var tgt := home - dirv * 0.7 * ls + Vector3.UP * 0.22 * ls
			f.pos = f.pos.lerp(tgt, 1.0 - exp(-25.0 * delta))
			f.yaw = lerp_angle(f.yaw, legs_yaw, 1.0 - exp(-20.0 * delta))
			f.swinging = true
			f.quick = 0.0
			f.from = f.pos
			f.from_yaw = f.yaw
			f.air = 0.6
			continue

		# поправочный шаг: быстро переставить ногу на место
		if f.quick >= 0.0:
			f.quick += delta / f.quick_dur
			var q := minf(f.quick, 1.0)
			var e := smoothstep(0.0, 1.0, q)
			var target := home + dirv * (stance_half * 0.5 if moving else 0.0)
			f.pos = f.from.lerp(target, e)
			f.pos.y = lerpf(f.from.y, ground, e) + sin(q * PI) * lift * 0.6
			f.yaw = lerp_angle(f.from_yaw, legs_yaw, e)
			f.air = sin(q * PI)
			if f.quick >= 1.0:
				f.quick = -1.0
				_land(f, ground)
			continue

		var flat_dist := Vector2(home.x - f.pos.x, home.z - f.pos.z).length()

		if moving:
			var lp := fposmod(phase + 0.5 * i, 1.0)
			if lp < swing_frac:
				if not f.swinging and swing_frac - lp > 0.12:
					f.swinging = true
					f.from = f.pos
					f.from_yaw = f.yaw
					f.start_lp = lp
				if f.swinging:
					var sw := clampf((lp - f.start_lp) / maxf(swing_frac - f.start_lp, 0.01), 0.0, 1.0)
					var remaining := (swing_frac - lp) * stride
					var land := home + dirv * (remaining + stance_half)
					var e2 := smoothstep(0.0, 1.0, sw)
					f.pos = f.from.lerp(land, e2)
					f.pos.y = lerpf(f.from.y, ground, e2) + sin(sw * PI) * lift
					f.yaw = lerp_angle(f.from_yaw, legs_yaw, e2)
					f.air = sin(sw * PI)
			else:
				if f.swinging:
					_land(f, ground)
				# опорная нога отстала слишком сильно: поправочный шаг. Порог зависит от длины шага,
				# иначе на старте (пока первая нога в воздухе) вторая тоже дёргалась и шли "двумя сразу"
				elif flat_dist > maxf(1.75 * ls, stride * 0.9) and not other.swinging:
					_start_quick(f)
		else:
			if f.swinging:
				_start_quick(f)
			elif flat_dist > 0.35 * ls and other.quick < 0.0 and not other.swinging:
				_start_quick(f)
			elif absf(angle_difference(f.yaw, legs_yaw)) > 0.5 and other.quick < 0.0 and not other.swinging:
				_start_quick(f)


func _start_quick(f: Foot) -> void:
	f.quick = 0.0
	f.swinging = true
	f.from = f.pos
	f.from_yaw = f.yaw


func _land(f: Foot, ground: float) -> void:
	f.swinging = false
	f.pos.y = ground
	f.air = 0.0
	footstep.emit(f.pos)


func _solve_leg(f: Foot, hip: Vector3, back: Vector3, right: Vector3) -> void:
	var l1 := _l1 * ls
	var l2 := _l2 * ls
	var ankle := f.pos + Vector3.UP * _ankle_h * ls
	var d := ankle - hip
	var dist := clampf(d.length(), 0.4 * ls, l1 + l2 - 0.02)
	var dn := d.normalized()
	ankle = hip + dn * dist
	var a := (l1 * l1 - l2 * l2 + dist * dist) / (2.0 * dist)
	var h := sqrt(maxf(l1 * l1 - a * a, 0.0))
	var bend := back - dn * back.dot(dn)
	if bend.length() < 0.001:
		bend = Vector3.BACK
	bend = bend.normalized()
	var knee := hip + dn * a + bend * h
	_place_bone(f.thigh, hip, knee, right)
	_place_bone(f.shin, knee, ankle, right)
	f.knee.global_transform = Transform3D(f.thigh.global_basis, knee)
	var fb := Basis(Vector3.UP, f.yaw) * Basis(Vector3.RIGHT, -f.air * 0.3)
	f.node.global_transform = Transform3D((fb * Basis.from_scale(Vector3.ONE * ls)), ankle - Vector3.UP * _ankle_h * ls)


func _place_bone(node: Node3D, top: Vector3, bottom: Vector3, right: Vector3) -> void:
	var y := (top - bottom).normalized()
	var z := right.cross(y).normalized()
	var x := y.cross(z).normalized()
	node.global_transform = Transform3D(Basis(x * ls, y * ls, z * ls), (top + bottom) * 0.5)


# ------------------------------------------------------------------
#  ПОМОЩНИКИ
# ------------------------------------------------------------------

func _mat(c: Color, metallic: float, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metallic
	m.roughness = rough
	return m


func _unshaded(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	return m


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = Art.bevel_box(size, minf(minf(size.x, size.y), size.z) * 0.14)
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


func _cyl(parent: Node3D, radius: float, height: float, pos: Vector3, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = 14
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi
