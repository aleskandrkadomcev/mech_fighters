extends Node3D
## Внешний вид меха и шагающие ноги.
## Корпус без головы, пушки по бокам, ноги с одним обратным коленом.
## Ноги не анимированы заранее: ступня ставится на землю, а колено досчитывается (IK).
## Модель собирается от деталей: размер ног, размер корпуса, вид корпуса (у каждого из 10 мехов свой:
## лёгкий клин, разведчик с радаром, таран с отвалом, мортира с упорами...), вид оружия на каждом подвесе,
## ракетные блоки на плечах только если стоит ракетная установка.
## Броня в текстурах из assets/textures (если их нет, рисуется своя фактура), грани скошены.
## Мехи, у которых в parts.gd задано "model", собираются из 3D-модели assets/mechs/<model>.glb
## (её режет tools/cut_mech.py): части в позе модели в метрах игры и точки — суставы j_hip/j_knee/j_ankle_l/_r,
## крепления пушек gun_l/_r, модулей mod_N, двигателей рывка jet_N, полосы цвета команды accent_N.

signal footstep(pos: Vector3)

# размеры при масштабе 1 (средние ноги, штурмовой корпус)
const HIP_H0 := 2.05     # высота таза над землёй
const WAIST_UP := 0.32   # от таза до поворотного круга корпуса
const L1 := 1.2          # длина бедра
const L2 := 1.25         # длина голени
const ANKLE_H := 0.32    # высота щиколотки над подошвой
const HIP_X := 0.9       # на сколько бёдра разнесены в стороны
const FOOT_X0 := 1.05    # на сколько ступни разнесены в стороны


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
var _hip_x := HIP_X
var _foot_x := FOOT_X0
var model := ""                 # 3D-модель (имя файла в assets/mechs) или "" — мех из коробок
var _hip_h := HIP_H0            # высота таза
var _hip_z := 0.0               # бёдра впереди (-) или сзади (+) середины меха
var _foot_z := 0.0              # где стоят ступни в покое: впереди (-) или сзади (+)
var _l1 := L1
var _l2 := L2
var _ankle_h := ANKLE_H
var _knee_dir := 1.0            # 1 колено назад (как у птицы), -1 вперёд (как у человека)
var _pts := {}                  # точки модели: имя -> Transform3D в позе модели
var _parts := {}                # части модели: имя -> Mesh из файла
var _model_mats := {}           # материал из файла -> его копия для этого меха (цвет команды, вспышки)
var _pod_z := [-0.1, -0.1]      # где по длине стоят подвесы пушек (их сдвигает отдача)
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
var _team_paint := Color(1, 1, 1)   # чем красится текстура 3D-модели (сейчас ничем: мехи в своих цветах)

const Art := preload("res://scripts/art.gd")


# ------------------------------------------------------------------
#  СБОРКА МОДЕЛИ ИЗ БЛОКОВ
# ------------------------------------------------------------------

# look: {legs_scale, hull_scale, weapons: [вид левого, вид правого], rockets: bool}
# accent: цвет полос и огней на мехе (пока у всех нейтральный — свой/чужой видно по полоске здоровья и нику);
# friend: свой или чужой — от этого только цвет луча лазера
func build(accent: Color, tint: Color, look: Dictionary, friend := true) -> void:
	ls = look.get("legs_scale", 1.0)
	hs = look.get("hull_scale", 1.0)
	style = look.get("style", "mid")
	cls = "light" if style in ["light", "scout"] else ("heavy" if style in ["heavy", "bastion", "siege"] else "mid")
	_hip_x = {"light": 0.72, "mid": 0.95, "heavy": 1.15}[cls]
	_foot_x = {"light": 0.9, "mid": 1.12, "heavy": 1.38}[cls]
	model = look.get("model", "")
	if model != "" and not _load_model(model):
		model = ""     # файла нет: мех из коробок
	if model != "":
		_setup_model_legs()
	_team_paint = tint
	_team_paint.a = 1.0
	var paint := Color(0.42, 0.43, 0.44) * tint
	m_armor = _mat(paint, 0.35, 0.5)
	m_armor.emission_enabled = true
	m_armor.emission = Color(0, 0, 0)
	m_armor2 = _mat(Color(0.26, 0.27, 0.285) * tint, 0.4, 0.55)
	m_armor2.emission_enabled = true
	m_armor2.emission = Color(0, 0, 0)
	m_dark = _mat(Color(0.2, 0.2, 0.21), 0.5, 0.5)
	m_accent = _mat(accent.darkened(0.15), 0.1, 0.6)
	m_glow = StandardMaterial3D.new()
	m_glow.albedo_color = accent
	m_glow.emission_enabled = true
	m_glow.emission = accent
	m_glow.emission_energy_multiplier = 1.4
	m_beam = _unshaded((Color(0.55, 0.95, 1.0) if friend else Color(1.0, 0.35, 0.35)) * 2.2)
	# фактура брони: панели, швы, болты (или текстуры из assets/textures)
	Art.apply_panels(m_armor, 0.7, "armor")
	Art.apply_panels(m_armor2, 0.9, "armor")
	Art.apply_panels(m_dark, 1.4, "darkmetal")
	m_light = StandardMaterial3D.new()
	m_light.albedo_color = Color(1.0, 0.95, 0.8)
	m_light.emission_enabled = true
	m_light.emission = Color(1.0, 0.92, 0.75)
	m_light.emission_energy_multiplier = 3.0

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
	for m in [m_armor, m_armor2, m_accent] + _model_mats.values():
		if m != null:
			m.albedo_color = burnt * randf_range(0.8, 1.3)
			m.emission_enabled = false
	if m_dark != null:
		m_dark.albedo_color = Color(0.03, 0.03, 0.03)
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
	for m in [m_armor, m_armor2, m_dark, m_accent, m_glow, m_light] + _model_mats.values():
		if m == null:
			continue
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if f > 0.001 else BaseMaterial3D.TRANSPARENCY_DISABLED
		m.albedo_color.a = 1.0 - f


func hip_h() -> float:
	return _hip_h * ls


func _build_pelvis() -> void:
	legs_root = Node3D.new()
	add_child(legs_root)
	if model != "":
		_model_part(_holder(legs_root, Transform3D(Basis.IDENTITY, Vector3(0, -_hip_h, 0))), "pelvis")
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
	if model != "":
		var res := _hull_model()
		pods = res[0]
		ports = res[1]
		jets = res[2]
	else:
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
				pods = _hull_mid()
				ports = [Vector3(-1.32, 2.05, -0.35), Vector3(1.32, 2.05, -0.35)]
				jets = [Vector3(-0.42, 0.95, 1.85), Vector3(0.42, 0.95, 1.85)]
	# двигатели рывка сзади
	for j in jets:
		_cyl(torso, 0.2, 0.35, j - Vector3(0, 0, 0.3), m_dark, Vector3(PI / 2, 0, 0))
		var th := _box(torso, Vector3(0.26, 0.26, 1.3), j + Vector3(0, 0, 0.6), _unshaded(Color(0.55, 0.85, 1.0) * 2.0))
		th.visible = false
		thrusters.append(th)
	if model == "":
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
		_pod_z[i] = pods[i].z
		torso.add_child(pod)
		gun_pods.append(pod)
		var look: String = weapon_looks[i] if i < weapon_looks.size() else "twin"
		var muzzle_z := _build_weapon(pod, look, s, i)
		var mz := Node3D.new()
		mz.position = Vector3(0, -0.05, muzzle_z)
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
			fl.position = Vector3(0, -0.05, muzzle_z - 0.9)
		else:
			var sm := SphereMesh.new()
			sm.radius = 0.38
			sm.height = 0.76
			sm.radial_segments = 8
			sm.rings = 4
			fl.mesh = sm
			fl.material_override = _unshaded(Color(1.0, 0.82, 0.4) * 2.5)
			fl.position = Vector3(0, -0.05, muzzle_z - 0.3)
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
			_box(torso, Vector3(1.1, 0.6, 0.7), Vector3(0, 1.7, 1.25), m_armor2)
			var green := _unshaded(Color(0.35, 1.0, 0.5) * 2.0)
			_cyl(torso, 0.1, 0.18, Vector3(0.35, 2.1, 1.35), green)
			_box(torso, Vector3(0.12, 0.12, 1.5), Vector3(-0.42, 2.05, 0.75), m_dark, Vector3(0.5, 0, 0))
			_box(torso, Vector3(0.16, 0.4, 0.16), Vector3(-0.42, 2.15, 0.05), m_accent)
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


# строит пушку на подвесе, возвращает, где кончается ствол
func _build_weapon(pod: Node3D, look: String, s: float, gun := 0) -> float:
	match look:
		"heavy":
			# тяжёлое орудие: один толстый длинный ствол
			_box(pod, Vector3(0.86, 0.9, 1.7), Vector3.ZERO, m_armor)
			_box(pod, Vector3(0.14, 1.0, 1.4), Vector3(0.48 * s, 0.06, 0.0), m_armor2)
			_box(pod, Vector3(0.2, 0.05, 1.4), Vector3(0, 0.47, 0.0), m_accent)
			_box(pod, Vector3(0.7, 0.6, 0.35), Vector3(0, 0, 0.95), m_dark)
			_cyl(pod, 0.2, 2.0, Vector3(0, -0.05, -1.75), m_dark, Vector3(PI / 2, 0, 0))
			_cyl(pod, 0.27, 0.45, Vector3(0, -0.05, -1.05), m_armor2, Vector3(PI / 2, 0, 0))
			_box(pod, Vector3(0.5, 0.36, 0.42), Vector3(0, -0.05, -2.75), m_armor2)
			return -2.95
		"laser":
			# лазер: гладкий кожух со светящейся линзой
			_box(pod, Vector3(0.72, 0.72, 1.6), Vector3.ZERO, m_armor)
			_box(pod, Vector3(0.12, 0.8, 1.3), Vector3(0.42 * s, 0.04, 0.0), m_armor2)
			_box(pod, Vector3(0.2, 0.05, 1.3), Vector3(0, 0.39, 0.0), m_accent)
			_box(pod, Vector3(0.5, 0.5, 1.0), Vector3(0, -0.05, -1.25), m_armor2)
			_box(pod, Vector3(0.36, 0.36, 0.5), Vector3(0, -0.05, -1.9), m_dark)
			_box(pod, Vector3(0.24, 0.24, 0.08), Vector3(0, -0.05, -2.17), m_beam)
			return -2.2
		"blaster":
			# бластер: ствол с катушками, светятся голубым
			_box(pod, Vector3(0.7, 0.7, 1.4), Vector3.ZERO, m_armor)
			_box(pod, Vector3(0.2, 0.05, 1.2), Vector3(0, 0.37, 0.0), m_accent)
			_cyl(pod, 0.12, 1.7, Vector3(0, -0.05, -1.3), m_dark, Vector3(PI / 2, 0, 0))
			var coil := _unshaded(Color(0.4, 0.9, 1.0) * 2.2)
			for k in 4:
				_cyl(pod, 0.22, 0.1, Vector3(0, -0.05, -0.75 - k * 0.32), coil, Vector3(PI / 2, 0, 0))
			_cyl(pod, 0.2, 0.25, Vector3(0, -0.05, -2.15), m_armor2, Vector3(PI / 2, 0, 0))
			return -2.3
		"grenade":
			# гранатомёт: толстая короткая труба и барабан
			_box(pod, Vector3(0.78, 0.8, 1.3), Vector3.ZERO, m_armor)
			_cyl(pod, 0.45, 0.5, Vector3(0, 0.1, 0.15), m_armor2, Vector3(0, 0, PI / 2))
			_cyl(pod, 0.26, 1.4, Vector3(0, -0.05, -1.15), m_dark, Vector3(PI / 2, 0, 0))
			_cyl(pod, 0.31, 0.2, Vector3(0, -0.05, -1.75), m_armor2, Vector3(PI / 2, 0, 0))
			_box(pod, Vector3(0.2, 0.05, 1.1), Vector3(0, 0.41, 0.0), m_accent)
			return -1.85
		"shotgun":
			# дробовик: два широких коротких ствола
			_box(pod, Vector3(0.8, 0.75, 1.3), Vector3.ZERO, m_armor)
			_box(pod, Vector3(0.2, 0.05, 1.1), Vector3(0, 0.39, 0.0), m_accent)
			for b in [-0.18, 0.18]:
				_cyl(pod, 0.16, 1.2, Vector3(b, -0.05, -1.2), m_dark, Vector3(PI / 2, 0, 0))
			_box(pod, Vector3(0.75, 0.42, 0.3), Vector3(0, -0.05, -0.7), m_armor2)
			return -1.8
		"rail":
			# рельсотрон: две длинные рельсы, между ними разгорается заряд
			_box(pod, Vector3(0.8, 0.8, 1.6), Vector3.ZERO, m_armor)
			_box(pod, Vector3(0.2, 0.05, 1.4), Vector3(0, 0.42, 0.0), m_accent)
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
			_box(pod, Vector3(0.8, 0.8, 1.3), Vector3.ZERO, m_armor)
			_box(pod, Vector3(0.2, 0.05, 1.1), Vector3(0, 0.42, 0.0), m_accent)
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
			_box(pod, Vector3(0.78, 0.8, 1.55), Vector3.ZERO, m_armor)
			_box(pod, Vector3(0.14, 0.95, 1.3), Vector3(0.44 * s, 0.06, 0.0), m_armor2)
			_box(pod, Vector3(0.2, 0.05, 1.3), Vector3(0, 0.42, 0.0), m_accent)
			_box(pod, Vector3(0.6, 0.5, 0.3), Vector3(0, 0, 0.85), m_dark)
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
	if model != "":
		_leg_model(f, side)
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


# ------------------------------------------------------------------
#  МЕХ ИЗ 3D-МОДЕЛИ
# ------------------------------------------------------------------

# читает assets/mechs/<имя>.glb: части (сетки) и точки (суставы, крепления)
func _load_model(name: String) -> bool:
	var scene: PackedScene = Parts.mech_model(name)
	if scene == null:
		push_warning("нет 3D-модели меха: assets/mechs/%s.glb" % name)
		return false
	var root: Node = scene.instantiate()
	for n in root.find_children("*", "Node3D", true, false):
		var tr := Transform3D.IDENTITY
		var p: Node = n
		while p != root and p is Node3D:
			tr = (p as Node3D).transform * tr
			p = p.get_parent()
		if n is MeshInstance3D:
			_parts[String(n.name)] = [(n as MeshInstance3D).mesh, tr]
		else:
			_pts[String(n.name)] = tr
	root.free()
	return _parts.has("hull") and _pts.has("j_hip_l")


func _pt(name: String) -> Vector3:
	return (_pts[name] as Transform3D).origin if _pts.has(name) else Vector3.ZERO


# ноги по суставам модели. Кости моделей обычно короче, чем нужно: при беге ступня уходит далеко
# вперёд и не дотягивается до земли. Поэтому кости вытягиваются ровно настолько, насколько нужно (до 1.4 раза)
func _setup_model_legs() -> void:
	var hip := _pt("j_hip_l")
	var knee := _pt("j_knee_l")
	var ankle := _pt("j_ankle_l")
	_hip_h = hip.y
	_hip_x = absf(hip.x)
	_hip_z = hip.z
	# ступни можно свести к бёдрам (число «stance» у меха): у некоторых моделей ноги расставлены слишком широко
	_foot_x = lerpf(_hip_x, absf(ankle.x), _s("stance", 1.0))
	_foot_z = ankle.z
	_ankle_h = ankle.y
	# колено сзади линии бедро-щиколотка (птичья нога) или впереди (человеческая)
	var t := (hip.y - knee.y) / maxf(hip.y - ankle.y, 0.01)
	_knee_dir = 1.0 if knee.z >= lerpf(hip.z, ankle.z, t) else -1.0
	var l1 := hip.distance_to(knee)
	var l2 := knee.distance_to(ankle)
	var reach := absf(_foot_z - _hip_z) + 0.26 * _s("stride_run", 6.0)
	var lat := absf(_foot_x - _hip_x)
	var vert := _hip_h - _ankle_h
	var need := sqrt(vert * vert + reach * reach + lat * lat) + 0.05
	var k := clampf(need / (l1 + l2), 1.0, 1.4)
	_l1 = l1 * k
	_l2 = l2 * k


# корпус модели, полосы цвета команды; возвращает [подвесы пушек, ракетные блоки, двигатели рывка]
# в координатах корпуса
func _hull_model() -> Array:
	var off := Vector3(0, _hip_h + WAIST_UP, 0)
	var h := _holder(torso, Transform3D(Basis.IDENTITY, -off))
	_model_part(h, "hull")
	for nm in _pts:
		if String(nm).begins_with("accent_"):
			var tr: Transform3D = _pts[nm]
			_box(h, tr.basis.get_scale(), tr.origin, m_accent)
	var pods := [_pt("gun_l") - off, _pt("gun_r") - off]
	# ракетные блоки на первые два крепления модулей (левый — слева)
	var ports := []
	for i in 2:
		if _pts.has("mod_%d" % i):
			ports.append(_pt("mod_%d" % i) - off + Vector3(0, 0.25, 0))
		else:
			ports.append(pods[i] + Vector3(0, 0.7, 0.3))
	if ports[0].x > ports[1].x:
		ports.reverse()
	var jets := []
	for i in 2:
		var jn := "jet_%d" % i
		jets.append(_pt(jn) - off if _pts.has(jn) else Vector3(0.4 * (i * 2 - 1), 0.5, 1.5))
	return [pods, ports, jets]


# нога модели: части стоят в позе модели, держатели переносят их в кости
func _leg_model(f: Foot, side: float) -> void:
	var sn := "l" if side < 0.0 else "r"
	var hip := _pt("j_hip_" + sn)
	var knee := _pt("j_knee_" + sn)
	var ankle := _pt("j_ankle_" + sn)
	_model_part(_holder(f.thigh, _bone_tr(hip, knee, _l1)), "thigh_" + sn)
	_model_part(_holder(f.shin, _bone_tr(knee, ankle, _l2)), "shin_" + sn)
	_model_part(_holder(f.node, Transform3D(Basis.IDENTITY, -Vector3(ankle.x, 0, ankle.z))), "foot_" + sn)


# часть модели; её материал (текстура модели) копируется на этого меха: цвет команды, вспышка, прозрачность
func _model_part(parent: Node3D, part: String) -> MeshInstance3D:
	if not _parts.has(part):
		return null
	var mi := MeshInstance3D.new()
	mi.mesh = _parts[part][0]
	mi.transform = _parts[part][1]
	for si in mi.mesh.get_surface_count():
		var src := mi.mesh.surface_get_material(si)
		if src is StandardMaterial3D:
			if not _model_mats.has(src):
				var m: StandardMaterial3D = src.duplicate()
				m.albedo_color = m.albedo_color * _team_paint
				m.emission_enabled = true
				m.emission = Color(0, 0, 0)
				_model_mats[src] = m
			mi.set_surface_override_material(si, _model_mats[src])
	parent.add_child(mi)
	return mi


# перевод из позы модели в координаты кости: ось Y вдоль кости, длина кости растягивается до length
func _bone_tr(top: Vector3, bottom: Vector3, length: float) -> Transform3D:
	var yv := (top - bottom).normalized()
	var zv := Vector3.RIGHT.cross(yv).normalized()
	var xv := yv.cross(zv).normalized()
	var b := Basis.from_scale(Vector3(1, length / top.distance_to(bottom), 1)) * Basis(xv, yv, zv).transposed()
	return Transform3D(b, b * -((top + bottom) * 0.5))


# узел-держатель для деталей, заданных в позе модели
func _holder(parent: Node3D, tr: Transform3D) -> Node3D:
	var h := Node3D.new()
	h.transform = tr
	parent.add_child(h)
	return h


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


var _glow_set := Color(-1, -1, -1)     # какая подсветка брони уже стоит в материалах


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
	# в материалы только когда подсветка меняется: каждая установка заставляет отрисовку заново
	# отправлять материал в видеокарту (на 10 мехах это сотни материалов за тик)
	if glow != _glow_set:
		_glow_set = glow
		m_armor.emission = glow
		m_armor2.emission = glow
		for m in _model_mats.values():
			m.emission = glow

	if not _inited:
		_inited = true
		var r0 := Vector3(cos(legs_yaw), 0, -sin(legs_yaw))
		for i in 2:
			var s := -1.0 if i == 0 else 1.0
			feet[i].pos = body_pos + (r0 * s * _foot_x + Vector3(-r0.z, 0, r0.x) * _foot_z) * ls
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
		gun_pods[i].position.z = _pod_z[i] + gun_kick[i]
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
		var hip := legs_root.global_transform * Vector3(_hip_x * s, 0, _hip_z)
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
		var home := body_pos + right * side * foot_x + Vector3(-right.z, 0, right.x) * _foot_z * ls
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
	var bend := (back - dn * back.dot(dn)) * _knee_dir
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
