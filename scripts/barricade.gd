class_name Barricade
extends StaticBody3D
## Раскладная баррикада: мех ставит её перед собой в сторону прицела, она разворачивается из контейнера
## в бронещит. Держит пули, лучи и рельсу (свои и чужие), мехи через неё не проходят. Свои гранаты
## (гранатомёт и снаряды абилок) летят над ней (lob.gd исключает свои баррикады). Обзор не закрывает —
## мех выше неё. Ломается от урона врага или через «Длительность». Боты и крипы обходят (main._nav_boxes).
## Пока в месте постановки стоит мех, баррикада не твёрдая (иначе физика выкинет меха вверх), потом твердеет.

const W := 5.0                   # ширина, единиц
const H := 2.6                   # высота
const D := 0.6                   # толщина

var team := 0
var owner_mech: Node
var hp_max := 400.0
var life := 25.0
var hp := 400.0
var dead := false
var _shape: BoxShape3D
var _vis: Node3D


func _ready() -> void:
	add_to_group("damageable")
	add_to_group("barricades")
	collision_layer = 0
	collision_mask = 0
	hp = hp_max
	_shape = BoxShape3D.new()
	_shape.size = Vector3(W, H, D)
	var cs := CollisionShape3D.new()
	cs.shape = _shape
	cs.position.y = H * 0.5
	add_child(cs)
	_vis = Node3D.new()
	_vis.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_vis)
	var plate := Bolas.mat("barricade", Color(0.36, 0.38, 0.33))
	var dark := Bolas.mat("barricade_d", Color(0.2, 0.21, 0.19))
	# три бронеплиты, у краёв чуть развёрнуты к себе
	for k in 3:
		var pm := BoxMesh.new()
		pm.size = Vector3(W / 3.0 - 0.06, H, D * 0.6)
		var pl := MeshInstance3D.new()
		pl.mesh = pm
		pl.material_override = plate
		pl.position = Vector3((k - 1) * W / 3.0, H * 0.5, 0.0)
		if k != 1:
			pl.rotation.y = 0.12 * (1 - k)
			pl.position.z = -0.12
		_vis.add_child(pl)
	# рама по верху и подпорки сзади
	var tm := BoxMesh.new()
	tm.size = Vector3(W, 0.18, D)
	var top := MeshInstance3D.new()
	top.mesh = tm
	top.material_override = dark
	top.position.y = H - 0.09
	_vis.add_child(top)
	var sm := BoxMesh.new()
	sm.size = Vector3(0.15, 0.15, H * 0.9)
	for sx in [-1.0, 1.0]:
		var st := MeshInstance3D.new()
		st.mesh = sm
		st.material_override = dark
		st.position = Vector3(sx * W * 0.32, H * 0.42, -0.75)
		st.rotation.x = 1.0
		_vis.add_child(st)
	# раскрытие из контейнера
	_vis.scale = Vector3(0.25, 0.08, 1.0)
	var tw := create_tween()
	tw.tween_property(_vis, "scale", Vector3(1, 1, 1), 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	Sfx.play_at("wall", global_position, -4.0, 0.1)
	_nav_changed()


# коробка для карты проходимости: [x, z, ширина, высота, глубина] по осям мира
func box() -> Array:
	var a := rotation.y
	var wx := absf(cos(a)) * W + absf(sin(a)) * D
	var wz := absf(sin(a)) * W + absf(cos(a)) * D
	return [global_position.x, global_position.z, wx, H, wz]


func get_hit_radius() -> float:
	return D


# расстояние до края щита (взрывы бьют по прямоугольнику, а не по кругу)
func blast_distance(pos: Vector3) -> float:
	var l := global_transform.affine_inverse() * pos
	var dx := maxf(absf(l.x) - W * 0.5, 0.0)
	var dz := maxf(absf(l.z) - D * 0.5, 0.0)
	return Vector2(dx, dz).length()


func take_damage(amount: float, pos: Vector3, _dir: Vector3, _kind := "", src: Node = null) -> void:
	if dead or amount <= 0.0:
		return
	if src != null and is_instance_valid(src) and src.get("team") == team:
		return          # свои по своей баррикаде не ломают
	hp -= amount
	if hp <= 0.0:
		_break()


func _physics_process(delta: float) -> void:
	if dead:
		return
	life -= delta
	if life <= 0.0:
		_break()
		return
	if collision_layer == 0 and not _mech_inside():
		collision_layer = 16      # как обломки: держит пули и мехов, обзор не закрывает


func _mech_inside() -> bool:
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = _shape
	q.transform = global_transform * Transform3D(Basis(), Vector3(0, H * 0.5, 0))
	q.collision_mask = 2 | 64
	return not get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()


func _break() -> void:
	dead = true
	Fx.dust_cloud(global_position + Vector3.UP * 0.5, 2.5)
	Sfx.play_at("wallbreak", global_position, -3.0, 0.1)
	remove_from_group("barricades")
	_nav_changed()
	queue_free()


func _nav_changed() -> void:
	var g = get_tree().current_scene
	if g != null and g.has_method("obstacle_changed"):
		var b := box()
		g.obstacle_changed(Rect2(b[0] - b[2] * 0.5, b[1] - b[4] * 0.5, b[2], b[4]))
