class_name SmokeCloud
extends Node3D
## Дымовая граната Осадника: густое облако на «Длительность» секунд. Обзор сквозь дым не проходит
## (vision.gd: луч обзора через облако — не видно), ни у тех, кто снаружи, ни у тех, кто внутри.

var radius := 6.0
var life := 8.0
var _t := 0.0
var _puffs: Array[MeshInstance3D] = []
var _mat: StandardMaterial3D

const ALPHA := 0.62


func _ready() -> void:
	add_to_group("smoke")
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(0.62, 0.63, 0.62, 0.0)
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.roughness = 1.0
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	# несколько клубов разного размера: облако неровное
	for k in 7:
		var a := TAU * k / 6.0
		var off := Vector3.ZERO if k == 6 else Vector3(cos(a), 0, sin(a)) * radius * 0.5
		var r := radius * (0.75 if k == 6 else 0.5)
		var sm := SphereMesh.new()
		sm.radius = r
		sm.height = r * 1.3
		sm.radial_segments = 16
		sm.rings = 8
		var mi := MeshInstance3D.new()
		mi.mesh = sm
		mi.material_override = _mat
		mi.position = off + Vector3.UP * r * 0.45
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_puffs.append(mi)
	Fx.dust_cloud(global_position + Vector3.UP * 0.5, radius)
	Sfx.play_at("emp", global_position, -10.0, 0.1)


func _physics_process(delta: float) -> void:
	_t += delta
	if _t >= life:
		queue_free()


func _process(delta: float) -> void:
	# быстро густеет, в конце тает; клубы медленно поворачиваются
	var k := clampf(minf(_t * 2.0, (life - _t) / 1.5), 0.0, 1.0)
	_mat.albedo_color.a = ALPHA * k
	for i in _puffs.size():
		_puffs[i].rotation.y += delta * (0.1 + i * 0.02)


# закрывает ли облако обзор по отрезку a-b (на плоскости). Тающее облако (последние полсекунды) уже не закрывает
func blocks(a: Vector3, b: Vector3) -> bool:
	if _t > life - 0.5:
		return false
	var c := Vector2(global_position.x, global_position.z)
	var p := Vector2(a.x, a.z)
	var q := Vector2(b.x, b.z)
	var d := q - p
	var t := clampf((c - p).dot(d) / maxf(d.length_squared(), 0.0001), 0.0, 1.0)
	return (p + d * t).distance_to(c) < radius * 0.85
