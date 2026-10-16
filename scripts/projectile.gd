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

static var _mats := {}
var _glow_key := ""               # плазма: свет, который летит вместе со сгустком (Fx.light_flash)
var _glow_col := Color.WHITE
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


# свечение трассера: яркость растёт с толщиной трассера (тонкая дробь светит слабо)
static func _glow_mat(ours: bool, energy: float) -> ShaderMaterial:
	var key := "tr_glow_%s_%.1f" % [ours, energy]
	if not _mats.has(key):
		_mats[key] = Fx.beam_material(Color(1.0, 0.62, 0.22) if ours else Color(1.0, 0.28, 0.22), energy, 1.5, 0.25, true, 0.45)
	return _mats[key]


# яркая сердцевина снаряда: тоже мягкая светящаяся чёрточка, повёрнутая к камере (твёрдой болванки нет)
static func _core_mat(key: String, c: Color) -> ShaderMaterial:
	if not _mats.has(key):
		_mats[key] = Fx.beam_material(c, 2.2, 1.0, 0.5, true, 0.4)
	return _mats[key]


# светящаяся чёрточка вдоль полёта: длина len, ширина w, середина сдвинута назад на back
func _streak(mat: Material, w: float, len: float, back: float) -> void:
	var q := MeshInstance3D.new()
	q.mesh = Fx._unit_quad()
	q.material_override = mat
	q.transform = Transform3D(Basis(Vector3(w, 0, 0), Vector3(0, 0, len), Vector3(0, -1, 0)), Vector3(0, 0, back))
	q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(q)


func _ready() -> void:
	var friend := team == Fx.player_team
	if style == "plasma":
		# свет от сгустка на землю и мехов рядом — только если стрелка видно (иначе выдаст его в тумане)
		if friend or (is_instance_valid(shooter) and shooter.get("seen") == true):
			_glow_key = "pl%d" % get_instance_id()
			_glow_col = Color(0.5, 0.9, 1.0) if friend else Color(1.0, 0.4, 0.85)
		# сгусток плазмы: яркое ядро и мягкое свечение вокруг
		_streak(_core_mat("pl_core_%s" % friend, Color(0.55, 0.95, 1.0) if friend else Color(1.0, 0.4, 0.85)), tracer * 1.6, tracer * 4.0, 0.0)
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
		# трассер: яркая сердцевина и свечение за головой снаряда, шире и длиннее сердцевины
		# размер и яркость свечения — от толщины трассера (у каждой пушки в «Деталях») и общего множителя в F2
		var k: float = Cfg.shot_glow
		if k <= 0.0:
			k = 0.0
		var cl := (0.6 + tracer * 6.0) * maxf(k, 0.3)
		_streak(_core_mat("tr_core_%s" % (team == 0), Color(1.0, 0.85, 0.55) if team == 0 else Color(1.0, 0.5, 0.42)), (0.06 + tracer * 0.9) * maxf(k, 0.3), cl, cl * 0.35)
		if k > 0.0:
			var gl := (0.8 + tracer * 14.0) * k
			var ge := snappedf(clampf(0.8 + tracer * 7.0, 0.8, 2.6) * minf(k, 1.5), 0.1)
			_streak(_glow_mat(team == 0, ge), (0.12 + tracer * 2.6) * k, gl, gl * 0.45)
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
	if _glow_key != "":
		Fx.light_flash(to, _glow_col, 6.0, 2.0, 0.12, _glow_key, true)
	left_range -= step.length()
	if left_range <= 0.0:
		queue_free()
