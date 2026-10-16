extends Node3D
## Ракета. Летит по прямой к точке на земле, оставляет дымный след,
## взрывается в точке назначения или об первое препятствие. Урон по площади.
## Её же использует авиаудар: тогда она падает сверху и ни обо что не цепляется.

var shooter: Node
var team := 0
var damage_mult := 1.0
var _exclude: Array[RID] = []
var marker: Node3D             # метка на земле, которую надо убрать после взрыва
var _from := Vector3.ZERO
var _to := Vector3.ZERO
var _dir := Vector3.FORWARD
var _left := 0.0
var _age := 0.0
var _trail: CPUParticles3D
var _p := {}
var born := 0

static var _body_mesh: CylinderMesh
static var _nose_mesh: CylinderMesh
static var _body_mat: StandardMaterial3D
static var _core_mat: Material       # выхлоп: яркая сердцевина
static var _glow_mat: Material       # выхлоп: оранжевое свечение
static var _smoke_ramp: Gradient
static var _smoke_grow: Curve


# p: числа ракетной установки (скорость, урон, радиус, урон на краю)
func setup(from: Vector3, to: Vector3, who: Node, ground_marker: Node3D, p: Dictionary) -> void:
	_p = p
	_from = from
	_to = to
	shooter = who
	marker = ground_marker
	_dir = (to - from).normalized()
	_left = from.distance_to(to)
	if who != null and "team" in who:
		team = who.team
		damage_mult = who.damage_mult()


func _ready() -> void:
	add_to_group("rockets")
	born = Time.get_ticks_msec()
	if _body_mesh == null:
		# корпус — тонкий цилиндр с носовым конусом
		_body_mesh = CylinderMesh.new()
		_body_mesh.top_radius = 0.11
		_body_mesh.bottom_radius = 0.11
		_body_mesh.height = 0.95
		_body_mesh.radial_segments = 8
		_body_mesh.rings = 1
		_nose_mesh = CylinderMesh.new()
		_nose_mesh.top_radius = 0.0
		_nose_mesh.bottom_radius = 0.11
		_nose_mesh.height = 0.3
		_nose_mesh.radial_segments = 8
		_nose_mesh.rings = 1
		_body_mat = StandardMaterial3D.new()
		_body_mat.albedo_color = Color(0.5, 0.51, 0.53)
		_body_mat.metallic = 0.4
		_body_mat.roughness = 0.5
		# выхлоп — мягкие светящиеся чёрточки, повёрнутые к камере (как у трассеров)
		_core_mat = Fx.beam_material(Color(1.0, 0.86, 0.6), 2.4, 1.0, 0.5, true, 0.35)
		_glow_mat = Fx.beam_material(Color(1.0, 0.5, 0.15), 1.8, 1.6, 0.0, true, 0.4)
		# дым: светлый у сопла, темнеет, растёт и тает
		_smoke_ramp = Fx._ramp("rocket_smoke", [[0.0, Color(1.0, 0.82, 0.6, 0.0)], [0.08, Color(0.9, 0.87, 0.82, 0.5)],
			[0.5, Color(0.62, 0.6, 0.58, 0.28)], [1.0, Color(0.48, 0.48, 0.5, 0.0)]])
		_smoke_grow = Curve.new()
		_smoke_grow.max_value = 4.0
		_smoke_grow.add_point(Vector2(0.0, 0.45))
		_smoke_grow.add_point(Vector2(1.0, 1.9))

	var body := MeshInstance3D.new()
	body.mesh = _body_mesh
	body.material_override = _body_mat
	body.rotation.x = PI / 2
	add_child(body)
	var nose := MeshInstance3D.new()
	nose.mesh = _nose_mesh
	nose.material_override = _body_mat
	nose.rotation.x = -PI / 2         # остриё вперёд (-Z)
	nose.position = Vector3(0, 0, -0.62)
	add_child(nose)
	_exhaust(_glow_mat, 0.9, 2.2, 1.45)
	_exhaust(_core_mat, 0.32, 0.9, 0.85)

	_trail = CPUParticles3D.new()
	_trail.mesh = Fx._quad()
	_trail.material_override = Fx._sprite_mat("smoke_07")
	_trail.local_coords = false
	_trail.amount = maxi(int(round(36 * Fx._gfx_k())), 12)
	_trail.lifetime = 1.1
	_trail.direction = Vector3(0, 0, 1)
	_trail.spread = 10.0
	_trail.initial_velocity_min = 0.3
	_trail.initial_velocity_max = 1.2
	_trail.gravity = Vector3(0, 0.5, 0)
	_trail.scale_amount_min = 0.55
	_trail.scale_amount_max = 0.9
	_trail.scale_amount_curve = _smoke_grow
	_trail.angle_min = 0.0
	_trail.angle_max = 360.0
	_trail.angular_velocity_min = -40.0
	_trail.angular_velocity_max = 40.0
	_trail.color_ramp = _smoke_ramp
	_trail.position = Vector3(0, 0, 1.0)
	_trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_trail)

	global_position = _from
	if _from.distance_to(_to) > 0.05:
		look_at(_to, Vector3.UP)
	reset_physics_interpolation()
	# сквозь своих ракета пролетает
	_exclude = Fx.team_rids(team)


func _physics_process(delta: float) -> void:
	_age += delta
	# короткий разгон после старта, чтобы пуск читался глазом
	# ракета авиаудара падает с неба точно в метку: без разгона и ни обо что не цепляется
	var falling: bool = _p.get("fall", false)
	var speed: float = _p.get("speed", 24.0)
	if not falling:
		speed *= lerpf(0.45, 1.0, clampf(_age / 0.25, 0.0, 1.0))
	var step_len := minf(speed * delta, _left)
	var from := global_position
	var to := from + _dir * step_len

	if not falling:
		var q := PhysicsRayQueryParameters3D.create(from, to, 1 | 4 | 16)
		q.collide_with_areas = true
		q.exclude = _exclude
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty():
			_explode(hit["position"] + hit["normal"] * 0.2)
			return

	global_position = to
	_left -= step_len
	if _left <= 0.001:
		_explode(to)


func _explode(pos: Vector3) -> void:
	var radius: float = _p.get("radius", 4.0)
	var dmg_c: float = _p.get("damage", 22.0)
	Fx.explosion(pos, radius)
	Sfx.play_at("boom", pos, -2.0, 0.1)

	Fx.blast(pos, radius, dmg_c * damage_mult, float(_p.get("edge_damage", 0.4)), team, shooter if is_instance_valid(shooter) else null)

	if marker != null and is_instance_valid(marker):
		marker.queue_free()

	# дымный след остаётся висеть и растворяется сам
	if _trail != null:
		var scene := get_tree().current_scene
		var gp := _trail.global_position
		remove_child(_trail)
		scene.add_child(_trail)
		_trail.global_position = gp
		_trail.emitting = false
		get_tree().create_timer(1.4).timeout.connect(_trail.queue_free)
	queue_free()


# светящаяся чёрточка выхлопа за соплом: ширина w, длина len, середина сдвинута назад на back
func _exhaust(mat: Material, w: float, len: float, back: float) -> void:
	var q := MeshInstance3D.new()
	q.mesh = Fx._unit_quad()
	q.material_override = mat
	q.transform = Transform3D(Basis(Vector3(w, 0, 0), Vector3(0, 0, len), Vector3(0, -1, 0)), Vector3(0, 0, back))
	q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(q)


# куда летит и с каким радиусом (боты видят летящую ракету и уходят с её пути)
func target_point() -> Vector3:
	return _to


func blast_radius() -> float:
	return _p.get("radius", 4.0)


func is_falling() -> bool:
	return _p.get("fall", false)
