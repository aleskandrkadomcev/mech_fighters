extends Node3D
## Снаряд навесом: граната гранатомёта, ЭМИ-граната турели 2 уровня, снаряд осадного орудия турели 3 уровня.
## setup_ballistic (гранатомёт и турели): вылетает с постоянной скоростью и рвётся о то, во что врежется:
## стену (по её настоящей высоте — низкую может перелететь), меха, крипа, обломок или землю.
## Турели целятся по низкой дуге (aim_velocity): чем быстрее снаряд, тем прямее летит.
## setup (сейчас не используется): летит по дуге заданной высоты в точку, ни обо что не цепляется.
## Баллистика настоящая: гравитация Cfg.gravity() (земная при масштабе Cfg.METERS_PER_UNIT),
## поэтому граната и снаряд падают как настоящие.
## payload: kind "explosive" (урон по площади) или "emp" (урон + оглушение + энергия не растёт).

var team := 0
var shooter: Node
var marker: Node3D             # метка на земле (у турелей), убирается при взрыве
var _from := Vector3.ZERO
var _to := Vector3.ZERO
var _time := 1.0
var _vy := 0.0                 # скорость вверх при вылете
var _g := 6.6
var _t := 0.0
var _p := {}
var _ballistic := false        # гранатомёт меха: настоящая баллистика и удар о преграды
var _vel := Vector3.ZERO
var _exclude: Array[RID] = []
var _body: MeshInstance3D
var _trail: CPUParticles3D

static var _mats := {}


# сколько секунд летит снаряд из from в to, если в верхней точке он на arc выше более высокой из двух точек
static func flight_time(from: Vector3, to: Vector3, arc: float) -> float:
	var g: float = Cfg.gravity()
	var top := maxf(from.y, to.y) + maxf(arc, 0.1)
	return (sqrt(2.0 * g * (top - from.y)) + sqrt(2.0 * g * (top - to.y))) / g


# from: откуда, to: точка на земле, arc: на сколько верхняя точка полёта выше более высокой из двух точек
func setup(from: Vector3, to: Vector3, arc: float, who: Node, payload: Dictionary) -> void:
	_from = from
	_to = to
	_g = Cfg.gravity()
	var top := maxf(from.y, to.y) + maxf(arc, 0.1)
	_vy = sqrt(2.0 * _g * (top - from.y))
	_time = flight_time(from, to, arc)
	shooter = who
	_p = payload
	if who != null and "team" in who:
		team = who.team


# скорость вылета, чтобы снаряд со скоростью speed упал в точку to по низкой (прямой) дуге.
# Не долетает — под 45°, как можно дальше
static func aim_velocity(from: Vector3, to: Vector3, speed: float) -> Vector3:
	var v := maxf(speed, 1.0)
	var g: float = Cfg.gravity()
	var flat := Vector3(to.x - from.x, 0.0, to.z - from.z)
	var x := flat.length()
	var y := to.y - from.y
	var ang := PI * 0.25
	var disc := v * v * v * v - g * (g * x * x + 2.0 * y * v * v)
	if disc >= 0.0 and x > 0.01:
		ang = atan((v * v - sqrt(disc)) / (g * x))
	return flat / maxf(x, 0.001) * cos(ang) * v + Vector3.UP * sin(ang) * v


func setup_ballistic(from: Vector3, vel: Vector3, who: Node, payload: Dictionary) -> void:
	_from = from
	_to = from
	_vel = vel
	_ballistic = true
	_g = Cfg.gravity()
	_time = 8.0          # не дольше (если улетела за край карты)
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
	if _ballistic:
		_exclude = Fx.team_rids(team)       # свои мехи и постройки для гранаты прозрачны
		# стены и скалы проверяем сами, по настоящему объёму (см. _cast)
		for b in get_tree().get_nodes_in_group("solid_tops"):
			_exclude.append(b.get_rid())
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
	t = clampf(t, 0.0, _time)
	var p := _from.lerp(_to, t / _time)     # по земле летит равномерно
	p.y = _from.y + _vy * t - 0.5 * _g * t * t
	return p


func _physics_process(delta: float) -> void:
	if _ballistic:
		_fly_ballistic(delta)
		return
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


func _fly_ballistic(delta: float) -> void:
	_t += delta
	var from := global_position
	_vel.y -= _g * delta
	var to := from + _vel * delta
	var hit := _cast(from, to)
	if not hit.is_empty():
		_to = hit["position"]
		_land()
		return
	global_position = to
	if _vel.length() > 0.01:
		_body.look_at(to + _vel, Vector3.UP if absf(_vel.normalized().y) < 0.98 else Vector3.RIGHT)
	if _t >= _time or to.y < -2.0:
		_to = to
		_land()


# во что граната врезается на отрезке: хитбоксы, обломки, земля (физикой) и стены со скалами —
# по их настоящему объёму, от земли до верха (метка top). У стен столкновение для пуль выше, чем
# на вид, и граната, попавшая в этот объём сверху, физикой не видна — поэтому считаем сами,
# включая крышку: падающая сверху граната рвётся на стене, а не проходит её насквозь
func _cast(from: Vector3, to: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to, 1 | 4 | 16)
	q.collide_with_areas = true
	q.exclude = _exclude
	var best := get_world_3d().direct_space_state.intersect_ray(q)
	var seg := to - from
	var best_t := 2.0
	if not best.is_empty():
		best_t = from.distance_to(best["position"]) / maxf(seg.length(), 0.0001)
	for b in get_tree().get_nodes_in_group("solid_tops"):
		var box = _top_box(b)
		if box == null:
			continue
		var t := _seg_box(from, seg, box)
		if t >= 0.0 and t < best_t:
			best_t = t
			best = {"position": from + seg * t, "collider": b}
	return best


# настоящий объём стены или скалы: её коробка столкновения, но от земли до верха (null — сломана)
static func _top_box(b: Node):
	for c in b.get_children():
		if c is CollisionShape3D and c.shape is BoxShape3D:
			if c.disabled:
				return null
			var half: Vector3 = c.shape.size * 0.5
			var p: Vector3 = c.global_position
			var top := float(b.get_meta("top", p.y + half.y))
			return AABB(Vector3(p.x - half.x, 0.0, p.z - half.z), Vector3(half.x * 2.0, top, half.z * 2.0))
	return null


# где отрезок from + seg * t (t от 0 до 1) входит в коробку; -1 — не входит
static func _seg_box(from: Vector3, seg: Vector3, box: AABB) -> float:
	var t0 := 0.0
	var t1 := 1.0
	for k in 3:
		var lo: float = box.position[k]
		var hi: float = box.end[k]
		if absf(seg[k]) < 0.000001:
			if from[k] < lo or from[k] > hi:
				return -1.0
			continue
		var a: float = (lo - from[k]) / seg[k]
		var c: float = (hi - from[k]) / seg[k]
		t0 = maxf(t0, minf(a, c))
		t1 = minf(t1, maxf(a, c))
		if t0 > t1:
			return -1.0
	return t0


func _land() -> void:
	var pos := Vector3(_to.x, maxf(_to.y, 0.3) if _ballistic else 0.3, _to.z)
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
