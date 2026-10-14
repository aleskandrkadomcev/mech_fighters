extends Node3D
## Полоска здоровья над мехом. Повёрнута лицом к камере.

const W := 3.2

var color := Color(0.95, 0.25, 0.2)
var _bar: MeshInstance3D
var _mat: StandardMaterial3D
var _back: MeshInstance3D


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


func _process(_delta: float) -> void:
	# всегда лицом к камере, даже если родитель развёрнут (вражеские турели повёрнуты на 180°)
	var sc := global_basis.get_scale()
	_back.global_basis = Basis.from_euler(Vector3(deg_to_rad(Cfg.cam_pitch - 90.0), 0, 0)).scaled(sc)


func _flat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.no_depth_test = true
	return m


func set_ratio(k: float) -> void:
	k = clampf(k, 0.0, 1.0)
	_bar.scale.x = maxf(k, 0.001)
	_bar.position.x = -W * 0.5 * (1.0 - k)
