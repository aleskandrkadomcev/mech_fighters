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

static var _body_mesh: BoxMesh
static var _body_mat: StandardMaterial3D
static var _flame_mat: StandardMaterial3D
static var _smoke_mesh: SphereMesh
static var _smoke_mat: StandardMaterial3D
static var _smoke_ramp: Gradient


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
		_body_mesh = BoxMesh.new()
		_body_mesh.size = Vector3(0.26, 0.26, 1.1)
		_body_mat = StandardMaterial3D.new()
		_body_mat.albedo_color = Color(0.75, 0.76, 0.78)
		_flame_mat = StandardMaterial3D.new()
		_flame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_flame_mat.albedo_color = Color(1.0, 0.7, 0.25)
		_smoke_mesh = SphereMesh.new()
		_smoke_mesh.radius = 0.3
		_smoke_mesh.height = 0.6
		_smoke_mesh.radial_segments = 6
		_smoke_mesh.rings = 3
		_smoke_mat = StandardMaterial3D.new()
		_smoke_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_smoke_mat.vertex_color_use_as_albedo = true
		_smoke_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_smoke_ramp = Gradient.new()
		_smoke_ramp.set_color(0, Color(0.85, 0.82, 0.78, 0.55))
		_smoke_ramp.set_color(1, Color(0.45, 0.45, 0.47, 0.0))

	var body := MeshInstance3D.new()
	body.mesh = _body_mesh
	body.material_override = _body_mat
	add_child(body)
	var flame := MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = Vector3(0.2, 0.2, 0.9)
	flame.mesh = fm
	flame.material_override = _flame_mat
	flame.position = Vector3(0, 0, 0.95)
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(flame)

	_trail = CPUParticles3D.new()
	_trail.mesh = _smoke_mesh
	_trail.material_override = _smoke_mat
	_trail.local_coords = false
	_trail.amount = 28
	_trail.lifetime = 0.7
	_trail.direction = Vector3(0, 0, 1)
	_trail.spread = 12.0
	_trail.initial_velocity_min = 0.5
	_trail.initial_velocity_max = 2.0
	_trail.gravity = Vector3(0, 0.8, 0)
	_trail.scale_amount_min = 0.7
	_trail.scale_amount_max = 1.5
	_trail.color_ramp = _smoke_ramp
	_trail.position = Vector3(0, 0, 0.8)
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
		get_tree().create_timer(1.0).timeout.connect(_trail.queue_free)
	queue_free()


# куда летит и с каким радиусом (боты видят летящую ракету и уходят с её пути)
func target_point() -> Vector3:
	return _to


func blast_radius() -> float:
	return _p.get("radius", 4.0)


func is_falling() -> bool:
	return _p.get("fall", false)
