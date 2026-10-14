extends Node3D
## Снаряд навесом: граната гранатомёта, ЭМИ-граната турели 2 уровня, снаряд осадного орудия турели 3 уровня.
## Летит по дуге над укрытиями и срабатывает в точке падения. Ни обо что по пути не цепляется.
## payload: kind "explosive" (урон по площади) или "emp" (урон + оглушение + энергия не растёт).

var team := 0
var shooter: Node
var marker: Node3D             # метка на земле (у турелей), убирается при взрыве
var _from := Vector3.ZERO
var _to := Vector3.ZERO
var _time := 1.0
var _arc := 6.0
var _t := 0.0
var _p := {}
var _body: MeshInstance3D
var _trail: CPUParticles3D

static var _mats := {}


# from: откуда, to: точка на земле, flight: секунд полёта, arc: высота дуги над прямой
func setup(from: Vector3, to: Vector3, flight: float, arc: float, who: Node, payload: Dictionary) -> void:
	_from = from
	_to = to
	_time = maxf(flight, 0.15)
	_arc = arc
	shooter = who
	_p = payload
	if who != null and "team" in who:
		team = who.team


static func _m(key: String, c: Color, unshaded := false) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	else:
		m.metallic = 0.5
		m.roughness = 0.4
	_mats[key] = m
	return m


func _ready() -> void:
	add_to_group("lobs")
	var big: bool = _p.get("kind", "") == "explosive" and _p.get("radius", 4.0) > 5.0
	var emp: bool = _p.get("kind", "") == "emp"
	_body = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.45 if big else 0.28
	sm.height = sm.radius * 2.6
	sm.radial_segments = 10
	sm.rings = 5
	_body.mesh = sm
	_body.material_override = _m("emp" if emp else ("big" if big else "gr"), Color(0.4, 0.75, 1.0) * 2.0 if emp else Color(0.2, 0.22, 0.2), emp)
	add_child(_body)
	# огонёк сзади, чтобы граната читалась в полёте
	var glow := MeshInstance3D.new()
	var gm := SphereMesh.new()
	gm.radius = sm.radius * 0.55
	gm.height = gm.radius * 2.0
	gm.radial_segments = 6
	gm.rings = 3
	glow.mesh = gm
	glow.material_override = _m("glow_e" if emp else "glow", Color(0.5, 0.9, 1.0) * 3.0 if emp else Color(1.0, 0.6, 0.2) * 3.0, true)
	glow.position = Vector3(0, 0, sm.radius)
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_body.add_child(glow)

	_trail = CPUParticles3D.new()
	var tm := SphereMesh.new()
	tm.radius = 0.18
	tm.height = 0.36
	tm.radial_segments = 4
	tm.rings = 2
	_trail.mesh = tm
	var trail_m := StandardMaterial3D.new()
	trail_m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	trail_m.vertex_color_use_as_albedo = true
	trail_m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_trail.material_override = trail_m
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.6, 0.85, 1.0, 0.7) if emp else Color(0.8, 0.78, 0.74, 0.45))
	ramp.set_color(1, Color(0.4, 0.4, 0.45, 0.0))
	_trail.color_ramp = ramp
	_trail.local_coords = false
	_trail.amount = 16
	_trail.lifetime = 0.45
	_trail.gravity = Vector3.ZERO
	_trail.initial_velocity_min = 0.2
	_trail.initial_velocity_max = 0.6
	_trail.scale_amount_min = 0.8
	_trail.scale_amount_max = 1.6
	_trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_trail)
	global_position = _from
	reset_physics_interpolation()


func _pos_at(t: float) -> Vector3:
	var k := clampf(t / _time, 0.0, 1.0)
	var p := _from.lerp(_to, k)
	p.y += 4.0 * _arc * k * (1.0 - k)
	return p


func _physics_process(delta: float) -> void:
	_t += delta
	var p := _pos_at(_t)
	var nxt := _pos_at(_t + 0.03)
	global_position = p
	if p.distance_to(nxt) > 0.001:
		_body.look_at(nxt, Vector3.UP if absf((nxt - p).normalized().y) < 0.98 else Vector3.RIGHT)
	if _t >= _time:
		_land()


# куда упадёт и с каким радиусом (боты уходят из-под турельных снарядов)
func target_point() -> Vector3:
	return _to


func blast_radius() -> float:
	return _p.get("radius", 4.0)


func _land() -> void:
	var pos := Vector3(_to.x, 0.3, _to.z)
	var radius: float = _p.get("radius", 4.0)
	var src: Node = shooter if is_instance_valid(shooter) else null
	if _p.get("kind", "") == "emp":
		Fx.pulse(pos + Vector3.UP * 0.9, radius)
		Sfx.play_at("emp", pos, -2.0, 0.05)
		for n in get_tree().get_nodes_in_group("damageable"):
			if not (n is Node3D) or n.get("team") == team or n.is_in_group("walls"):
				continue
			var d: Vector3 = n.global_position - pos
			d.y = 0
			var size: float = n.get_hit_radius() if n.has_method("get_hit_radius") else 1.0
			if d.length() > radius + size:
				continue
			if n.has_method("stun"):
				n.stun(_p.get("stun", 1.0))
			if n.has_method("block_regen"):
				n.block_regen(_p.get("no_regen", 2.0))
			if _p.get("damage", 0.0) > 0.0 and n.has_method("take_damage"):
				n.take_damage(_p["damage"], n.global_position + Vector3.UP * 2.0, d.normalized(), "", src)
	else:
		Fx.explosion(pos, radius)
		Sfx.play_at("boom", pos, -3.0 if radius < 5.0 else 1.0, 0.1)
		Fx.blast(pos, radius, _p.get("damage", 40.0), _p.get("edge_damage", 0.35), team, src)
	if marker != null and is_instance_valid(marker):
		marker.queue_free()
	if _trail != null:
		var gp := _trail.global_position
		remove_child(_trail)
		get_tree().current_scene.add_child(_trail)
		_trail.global_position = gp
		_trail.emitting = false
		get_tree().create_timer(0.6).timeout.connect(_trail.queue_free)
	queue_free()
