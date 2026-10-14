extends Node3D
## Снаряд. Летит по прямой, виден глазом, попадает во всё, что на пути.
## Сквозь своих пролетает, не задевая.
## style: "tracer" (обычный трассер) или "plasma" (светящийся сгусток бластера).
## falloff: какая доля урона остаётся на краю дальности (дробовик слабеет с расстоянием).

const Art := preload("res://scripts/art.gd")

var vel := Vector3.ZERO
var damage := 1.0
var left_range := 50.0
var shooter: Node
var team := 0
var tracer := 0.1             # толщина трассера (у тяжёлого орудия толще)
var style := "tracer"
var falloff := 1.0
var _start := Vector3.ZERO
var _max_range := 50.0
var _exclude: Array[RID] = []

static var _meshes := {}
static var _mats := {}
static var _plasma_mesh: QuadMesh


func setup(origin: Vector3, velocity: Vector3, dmg: float, max_range: float, who: Node) -> void:
	_start = origin
	vel = velocity
	damage = dmg
	left_range = max_range
	_max_range = max_range
	shooter = who
	if who != null and "team" in who:
		team = who.team


static func _mat(key: String, c: Color, tex: Texture2D = null) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	if tex != null:
		m.albedo_texture = tex
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats[key] = m
	return m


func _ready() -> void:
	var friend := team == Fx.player_team
	if style == "plasma":
		# сгусток плазмы: яркое ядро и мягкое свечение вокруг
		var core := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = tracer * 0.7
		sm.height = tracer * 3.2
		sm.radial_segments = 8
		sm.rings = 4
		core.mesh = sm
		core.rotation.x = PI / 2
		core.material_override = _mat("pl_core_%s" % friend, (Color(0.5, 0.95, 1.0) if friend else Color(1.0, 0.35, 0.8)) * 3.0)
		core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(core)
		var glow_t := Art.fx_tex("circle_05")
		if glow_t != null:
			var g := MeshInstance3D.new()
			if _plasma_mesh == null:
				_plasma_mesh = QuadMesh.new()
				_plasma_mesh.size = Vector2(1.6, 1.6)
			g.mesh = _plasma_mesh
			g.material_override = _mat("pl_glow_%s" % friend, (Color(0.3, 0.8, 1.0, 0.9) if friend else Color(1.0, 0.25, 0.7, 0.9)), glow_t)
			g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(g)
	else:
		if not _meshes.has(tracer):
			var bm := BoxMesh.new()
			bm.size = Vector3(tracer, tracer, 1.8 + tracer * 4.0)
			_meshes[tracer] = bm
		var mi := MeshInstance3D.new()
		mi.mesh = _meshes[tracer]
		mi.material_override = _mat("tr_%s" % (team == 0), Color(1.0, 0.72, 0.28) * 2.4 if team == 0 else Color(1.0, 0.25, 0.3) * 2.4)
		# снаряды из тумана видно только когда они долетают до видимой зоны (как в доте трассеры всё равно видны)
		mi.position = Vector3(0, 0, 0.9)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
	global_position = _start
	if vel.length() > 0.01:
		look_at(_start + vel, Vector3.UP)
	reset_physics_interpolation()
	# свои мехи и постройки для снаряда прозрачны
	_exclude = Fx.team_rids(team)


func _physics_process(delta: float) -> void:
	var from := global_position
	var step := vel * delta
	var to := from + step
	# снаряд видит стены (слой 1), хитбоксы (слой 3) и обломки (слой 5), но не капсулы для ходьбы
	var q := PhysicsRayQueryParameters3D.create(from, to, 1 | 4 | 16)
	q.collide_with_areas = true
	q.exclude = _exclude
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		var col = hit["collider"]
		var is_target := false
		if col != null and col.has_method("take_damage"):
			# дробь слабеет к краю дальности
			var k := 1.0
			if falloff < 0.999:
				k = lerpf(1.0, falloff, clampf(_start.distance_to(hit["position"]) / maxf(_max_range, 0.1), 0.0, 1.0))
			col.take_damage(damage * k, hit["position"], vel.normalized(), "", shooter if is_instance_valid(shooter) else null)
			is_target = col is Area3D
		if style == "plasma":
			Fx.plasma_hit(hit["position"], team == Fx.player_team)
		else:
			Fx.spark(hit["position"], hit["normal"], is_target)
		queue_free()
		return
	global_position = to
	left_range -= step.length()
	if left_range <= 0.0:
		queue_free()
