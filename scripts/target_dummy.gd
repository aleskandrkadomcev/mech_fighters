extends AnimatableBody3D
## Мишень-манекен. Стоит или ходит туда-сюда, имеет здоровье, после смерти появляется снова.

var hp := 100.0
var patrol_a := Vector3.ZERO
var patrol_b := Vector3.ZERO
var patrol_speed := 0.0
var _dir := 1.0
var _dead := false
var _flash := 0.0
var _stun := 0.0
var _body_mat: StandardMaterial3D
var _bar: MeshInstance3D
var _bar_mat: StandardMaterial3D
var _visual: Node3D
var _shape: CollisionShape3D
var _hit_vis: MeshInstance3D
var _hit_mesh: BoxMesh
var _box_shape: BoxShape3D
var _h := -1.0

const BASE_COLOR := Color(0.55, 0.2, 0.18)
const BAR_W := 2.4


func _ready() -> void:
	collision_layer = 2 | 4     # слой 2: мех в неё упирается; слой 3: по ней можно попасть
	collision_mask = 0
	sync_to_physics = false
	add_to_group("damageable")
	hp = Cfg.target_hp

	# хитбокс высокий, как у мехов: игра плоская, попадать должен любой ствол
	_shape = CollisionShape3D.new()
	_box_shape = BoxShape3D.new()
	_shape.shape = _box_shape
	add_child(_shape)

	# видимый контур хитбокса (F3)
	_hit_vis = MeshInstance3D.new()
	_hit_mesh = BoxMesh.new()
	_hit_vis.mesh = _hit_mesh
	var hmat := StandardMaterial3D.new()
	hmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hmat.albedo_color = Color(0.2, 1.0, 0.4, 0.2)
	hmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_hit_vis.material_override = hmat
	_hit_vis.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_hit_vis.visible = false
	add_child(_hit_vis)
	_apply_height()

	_visual = Node3D.new()
	add_child(_visual)
	_body_mat = StandardMaterial3D.new()
	_body_mat.albedo_color = BASE_COLOR
	_body_mat.roughness = 0.7
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.12, 0.12, 0.13)
	_box(Vector3(2.2, 1.5, 2.0), Vector3(0, 2.9, 0), _body_mat)
	_box(Vector3(1.0, 0.5, 0.9), Vector3(0, 2.0, 0), dark)
	for s in [-1.0, 1.0]:
		_box(Vector3(0.5, 1.9, 0.6), Vector3(0.75 * s, 0.95, 0), dark)
		_box(Vector3(0.7, 0.9, 1.4), Vector3(1.45 * s, 2.9, -0.1), dark)

	# полоска здоровья, повёрнута лицом к камере
	var tilt := deg_to_rad(Cfg.cam_pitch - 90.0)
	var back := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(BAR_W + 0.12, 0.34)
	back.mesh = qm
	back.material_override = _flat(Color(0, 0, 0, 0.7))
	back.position = Vector3(0, 4.7, 0)
	back.rotation.x = tilt
	back.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(back)

	_bar = MeshInstance3D.new()
	var qm2 := QuadMesh.new()
	qm2.size = Vector2(BAR_W, 0.22)
	_bar.mesh = qm2
	_bar_mat = _flat(Color(0.4, 0.9, 0.4))
	_bar_mat.render_priority = 1
	_bar.material_override = _bar_mat
	_bar.position = Vector3(0, 0, 0.02)
	_bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	back.add_child(_bar)


func _flat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.no_depth_test = true
	return m


func _box(size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	_visual.add_child(mi)


const HEIGHT := 3.0      # настоящая высота мишени


func _apply_height() -> void:
	_h = HEIGHT
	_box_shape.size = Vector3(2.4, _h, 2.2)
	_hit_mesh.size = _box_shape.size
	_shape.position = Vector3(0, _h * 0.5, 0)
	_hit_vis.position = _shape.position


func get_hit_radius() -> float:
	return 1.2


func take_damage(amount: float, _pos: Vector3, _dir_hit: Vector3, _kind := "", _src: Node = null) -> void:
	if _dead:
		return
	hp -= amount
	_flash = 0.09
	_update_bar()
	if hp <= 0.0:
		_die()


# оглушение: мишень встаёт на месте и синеет
func stun(seconds: float) -> void:
	if _dead:
		return
	_stun = maxf(_stun, seconds)


func _update_bar() -> void:
	var k := clampf(hp / Cfg.target_hp, 0.0, 1.0)
	_bar.scale.x = maxf(k, 0.001)
	_bar.position.x = -BAR_W * 0.5 * (1.0 - k)
	_bar_mat.albedo_color = Color(0.9, 0.3, 0.25).lerp(Color(0.4, 0.9, 0.4), k)


func _die() -> void:
	_dead = true
	visible = false
	_shape.set_deferred("disabled", true)
	Sfx.play_at("dash", global_position, -6.0, 0.1)
	get_tree().create_timer(Cfg.target_respawn).timeout.connect(_respawn)


func _respawn() -> void:
	_dead = false
	_stun = 0.0
	hp = Cfg.target_hp
	visible = true
	_shape.set_deferred("disabled", false)
	_update_bar()


func _physics_process(delta: float) -> void:
	_hit_vis.visible = Cfg.show_hitboxes
	if _h != HEIGHT:
		_apply_height()
	var base := BASE_COLOR
	if _stun > 0.0:
		_stun -= delta
		# мерцает синим, пока оглушена
		base = Color(0.25, 0.5, 0.95).lerp(Color(0.5, 0.8, 1.0), 0.5 + 0.5 * sin(_stun * 22.0))
	if _flash > 0.0:
		_flash -= delta
	_body_mat.albedo_color = Color(1, 1, 1) if _flash > 0.0 else base
	if patrol_speed > 0.0 and not _dead and _stun <= 0.0:
		var goal := patrol_b if _dir > 0.0 else patrol_a
		var to := goal - global_position
		to.y = 0
		if to.length() < 0.3:
			_dir = -_dir
		else:
			global_position += to.normalized() * patrol_speed * Cfg.walker_speed * delta
