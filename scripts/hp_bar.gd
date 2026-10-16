extends Node3D
## Полоска здоровья над мехом, над ней ник. Повёрнута лицом к камере. Цвет: свой мех, союзник или враг.
## Пока на юните контроль (оглушение, ЭМИ, замедление), над полоской белая шкала во всю её ширину,
## сжимается к центру до конца контроля, над шкалой название контроля; ник на это время поднимается выше.

const W := 3.2
const NICK_GAP := 0.16     # зазор между полоской и ником (в плоскости полоски): пара пикселей на экране

var color := Color(0.95, 0.25, 0.2)
var title := ""
var _label: Label3D
var _bar: MeshInstance3D
var _mat: StandardMaterial3D
var _back: MeshInstance3D
var _ratio := -1.0
var _ctl_back: MeshInstance3D    # шкала контроля: тёмная подложка
var _ctl: MeshInstance3D         # белая полоска (сжимается к центру)
var _ctl_label: Label3D          # название контроля
var _ctl_name := ""
var _ctl_k := -1.0
var _nick_y := 0.0               # где ник без контроля
var _nick_lift := 0.0            # насколько поднять ник, пока виден контроль


func _ready() -> void:
	_back = MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(W + 0.14, 0.4)
	_back.mesh = qm
	_back.material_override = _flat(Color(0, 0, 0, 0.75))
	_back.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_back)

	_bar = MeshInstance3D.new()
	var qm2 := QuadMesh.new()
	qm2.size = Vector2(W, 0.26)
	_bar.mesh = qm2
	_mat = _flat(color)
	_mat.render_priority = 1
	_bar.material_override = _mat
	_bar.position = Vector3(0, 0, 0.02)
	_bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_back.add_child(_bar)

	_label = Label3D.new()
	_label.text = title
	_label.modulate = color
	_label.outline_modulate = Color(0, 0, 0, 0.85)
	_label.font_size = 44
	_label.outline_size = 10
	_label.pixel_size = 0.013
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.render_priority = 2
	# ник стоит в плоскости полоски (она наклонена к камере), иначе на экране он садится на полоску.
	# Нижний край букв — по размерам шрифта: от середины подписи до строки плюс обводка
	var f: Font = ThemeDB.fallback_font
	var below := ((f.get_ascent(44) + f.get_descent(44)) * 0.5 - f.get_descent(44) + _label.outline_size * 0.5) * _label.pixel_size
	_nick_y = 0.2 + NICK_GAP + below
	_label.position = Vector3(0, _nick_y, 0.03)
	_back.add_child(_label)

	# шкала контроля: прямо над полоской здоровья, той же ширины; над ней название. Скрыта, пока контроля нет
	const CTL_Y := 0.33          # середина шкалы (верх полоски здоровья — 0.2)
	_ctl_back = MeshInstance3D.new()
	var qm3 := QuadMesh.new()
	qm3.size = Vector2(W + 0.14, 0.17)
	_ctl_back.mesh = qm3
	_ctl_back.material_override = _back.material_override
	_ctl_back.position = Vector3(0, CTL_Y, 0)
	_ctl_back.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ctl_back.visible = false
	_back.add_child(_ctl_back)
	_ctl = MeshInstance3D.new()
	var qm4 := QuadMesh.new()
	qm4.size = Vector2(W, 0.08)
	_ctl.mesh = qm4
	var cm := _flat(Color(1, 1, 1, 0.95))
	cm.render_priority = 1
	_ctl.material_override = cm
	_ctl.position = Vector3(0, 0, 0.02)
	_ctl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ctl_back.add_child(_ctl)
	_ctl_label = Label3D.new()
	_ctl_label.modulate = Color(1, 1, 1)
	_ctl_label.outline_modulate = Color(0, 0, 0, 0.85)
	_ctl_label.font_size = 34
	_ctl_label.outline_size = 9
	_ctl_label.pixel_size = 0.013
	_ctl_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_ctl_label.no_depth_test = true
	_ctl_label.render_priority = 2
	var below2 := ((f.get_ascent(34) + f.get_descent(34)) * 0.5 - f.get_descent(34) + _ctl_label.outline_size * 0.5) * _ctl_label.pixel_size
	var ctl_top := CTL_Y + 0.085
	_ctl_label.position = Vector3(0, ctl_top + NICK_GAP * 0.6 + below2, 0.03)
	_ctl_label.visible = false
	_back.add_child(_ctl_label)
	var lab_h := (f.get_ascent(34) + f.get_descent(34) + _ctl_label.outline_size) * _ctl_label.pixel_size
	_nick_lift = ctl_top + NICK_GAP * 0.6 + lab_h - 0.2


func _process(_delta: float) -> void:
	# всегда лицом к камере, даже если родитель развёрнут (вражеские турели повёрнуты на 180°)
	var sc := global_basis.get_scale()
	var want := Basis.from_euler(Vector3(deg_to_rad(Cfg.cam_pitch - 90.0), 0, 0)).scaled(sc)
	# поворачиваем, только если что-то поменялось: лишний поворот заставляет движок пересчитывать
	# положение полоски и отправлять его в отрисовку (полосок десятки)
	if not _back.global_basis.is_equal_approx(want):
		_back.global_basis = want


func _flat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.no_depth_test = true
	return m


func set_title(t: String) -> void:
	title = t
	if _label != null:
		_label.text = t


func set_ratio(k: float) -> void:
	k = clampf(k, 0.0, 1.0)
	if k == _ratio:
		return
	_ratio = k
	_bar.scale.x = maxf(k, 0.001)
	_bar.position.x = -W * 0.5 * (1.0 - k)


# контроль на юните: название и сколько его осталось (1 — только начался, 0 — кончился; пустое название — нет контроля).
# Меняем только то, что правда изменилось (см. hud.gd: каждая установка гоняет данные в отрисовку)
func set_control(ctl_name: String, k: float) -> void:
	if _ctl == null:
		return
	if ctl_name == "" or k <= 0.0:
		ctl_name = ""
		k = 0.0
	if ctl_name != _ctl_name:
		var on := ctl_name != ""
		if on != (_ctl_name != ""):
			_ctl_back.visible = on
			_ctl_label.visible = on
			_label.position.y = _nick_y + (_nick_lift if on else 0.0)
		_ctl_name = ctl_name
		_ctl_label.text = ctl_name
	k = clampf(k, 0.0, 1.0)
	if k != _ctl_k:
		_ctl_k = k
		_ctl.scale.x = maxf(k, 0.001)     # сжимается к центру: середина на месте
