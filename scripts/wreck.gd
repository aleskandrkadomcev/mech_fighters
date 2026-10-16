extends CharacterBody3D
## Обломок убитого меха или ящик с припасами.
## Обломок: чёрный дымящийся мех. Падает по инерции и тормозит о землю по физике: трение плюс сопротивление,
## растущее со скоростью (тушка пашет землю и кувыркается) — с бега проезжает несколько метров, из рывка ~25 м.
## Валится вперёд по ходу движения, бьётся о землю с пылью, пока едет быстро — тянет шлейф пыли и искрит;
## при падении отлетают 1–2 части (нога, пушка или кусок брони), тушка остаётся.
## Его можно толкать (чем тяжелее мех, тем легче), он закрывает от выстрелов, но не от вижена.
## Любой урон (свой, чужой, абилки) его ломает, тогда выпадают припасы.
## Ящик работает так же, только падает с неба и припасов в нём больше.

const Art := preload("res://scripts/art.gd")

var team := -1                  # ничей: ломают все
var hp := 60.0
var weight := 60.0              # тонн, от этого зависит, как легко толкать
var radius := 1.8
var loot := 1                   # сколько припасов выпадет (0 = случайно от 1 до loot_max)
var is_crate := false
var height := 2.0               # настоящая высота обломка или ящика (по ней попадают пули)
var _vel := Vector3.ZERO
var _visual: Node3D
var _smoke: CPUParticles3D
var _flash := 0.0
var _mats: Array = []
var _broken := false
var _cs: CollisionShape3D
var _tumble: Node3D             # держатель модели: валится вокруг передней кромки
var _fall_t := -1.0             # сколько секунд падает (-1 — не падает)
var _fall_axis := Vector3.RIGHT
var _fall_angle := 0.3
var _fall_drop := 1.0
var _landed := false
var _skid: CPUParticles3D       # шлейф пыли при скольжении
var _spark_t := 0.0
var _parts: Array = []          # отлетевшие части: {node, v, spin, rest, landed}


func _ready() -> void:
	collision_layer = 16        # слой обломков: мехи в него упираются, снаряды в него попадают, вижен сквозь
	collision_mask = 1 | 16 | 32
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	add_to_group("wrecks")
	add_to_group("damageable")
	var cs := CollisionShape3D.new()
	_cs = cs
	var cyl := CylinderShape3D.new()
	cyl.radius = radius
	cyl.height = height
	cs.shape = cyl
	cs.position = Vector3(0, height * 0.5 + 0.15, 0)    # чуть над полом, чтобы не цеплять землю
	add_child(cs)


# обломок из меха: забираем его модель как есть и роняем
func setup_wreck(visual: Node3D, vel: Vector3, mech_weight: float, r: float, h := 3.0) -> void:
	height = h
	hp = Cfg.wreck_hp
	weight = maxf(mech_weight, 5.0)
	radius = r * 0.85
	_vel = Vector3(vel.x, 0, vel.z)
	_visual = visual


# ящик с припасами
func setup_crate() -> void:
	is_crate = true
	hp = Cfg.crate_hp
	weight = 25.0
	radius = 1.5
	loot = Cfg.crate_loot


# вызывать после добавления в сцену и установки позиции
func start() -> void:
	if is_crate:
		_build_crate()
		return
	if _visual == null:
		return
	_tumble = Node3D.new()
	add_child(_tumble)
	_visual.reparent(_tumble, true)
	if _visual.has_method("set_charred"):
		_visual.set_charred()
	# ноги подкашиваются, тушка валится вперёд по ходу движения: чем быстрее ехала, тем ниже ложится
	var sp := _vel.length()
	var fwd := _vel / sp if sp > 0.5 else Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU)
	_fall_axis = Vector3.UP.cross(fwd).normalized().rotated(Vector3.UP, randf_range(-0.35, 0.35))
	_fall_angle = clampf(0.28 + sp * 0.022, 0.28, 1.15) * randf_range(0.85, 1.1)
	_fall_drop = 2.05 * float(_visual.get("ls") if _visual.get("ls") != null else 1.0) * 0.55
	_fall_t = 0.0
	_make_skid()
	_detach_parts(fwd, sp)
	_make_smoke(2.2)


func _build_crate() -> void:
	_visual = Node3D.new()
	add_child(_visual)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.32, 0.36, 0.28)
	m.roughness = 0.8
	var stripe := StandardMaterial3D.new()
	stripe.albedo_color = Color(0.95, 0.75, 0.2)
	stripe.emission_enabled = true
	stripe.emission = Color(0.95, 0.7, 0.15)
	stripe.emission_energy_multiplier = 0.6
	_mats = [m]
	_box(Vector3(2.4, 1.6, 2.4), Vector3(0, 0.8, 0), m)
	_box(Vector3(2.5, 0.25, 2.5), Vector3(0, 1.2, 0), stripe)
	_box(Vector3(0.3, 1.65, 2.5), Vector3(0, 0.8, 0), stripe)
	# падает с неба; твёрдым становится, когда упал
	_visual.position.y = 30.0
	_cs.disabled = true
	remove_from_group("damageable")
	var tw := create_tween()
	tw.tween_property(_visual, "position:y", 0.0, 0.6).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_callback(func() -> void:
		_cs.disabled = false
		add_to_group("damageable")
		Fx.burst(global_position + Vector3.UP, Color(0.95, 0.8, 0.4), 4.0)
		Sfx.play_at("boom", global_position, -8.0, 0.1))


func _box(size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	_visual.add_child(mi)


func _make_smoke(h: float) -> void:
	_smoke = CPUParticles3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	sm.radial_segments = 6
	sm.rings = 3
	_smoke.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_smoke.material_override = mat
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.2, 0.2, 0.2, 0.55))
	ramp.set_color(1, Color(0.35, 0.35, 0.37, 0.0))
	_smoke.color_ramp = ramp
	_smoke.amount = 14
	_smoke.lifetime = 2.2
	_smoke.direction = Vector3.UP
	_smoke.spread = 18.0
	_smoke.initial_velocity_min = 1.2
	_smoke.initial_velocity_max = 2.5
	_smoke.gravity = Vector3(0.4, 0.6, 0)
	_smoke.scale_amount_min = 0.8
	_smoke.scale_amount_max = 2.0
	_smoke.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_smoke.emission_sphere_radius = 0.8
	_smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_smoke.position = Vector3(0, h, 0)
	add_child(_smoke)
	_smoke.emitting = true


func _physics_process(delta: float) -> void:
	# скольжение по инерции после смерти: трение о землю плюс сопротивление на скорости (пашет землю).
	# Пока тушка ещё падает (первые 0,3 с), о землю трётся слабее
	var sp := _vel.length()
	if sp > 0.05:
		var c := move_and_collide(_vel * delta)
		if c != null:
			_vel = _vel.slide(c.get_normal()) * 0.5
			if sp > 4.0:
				Fx.spark(c.get_position() + Vector3.UP * 1.0, c.get_normal(), true, false)
		var dec := Cfg.wreck_friction + Cfg.wreck_drag * sp * sp
		if _fall_t >= 0.0 and _fall_t < 0.3:
			dec *= 0.6
		_vel = _vel.move_toward(Vector3.ZERO, dec * delta)
	global_position.y = 0.0
	if _flash > 0.0:
		_flash -= delta
	_update_fall(delta)
	_update_parts(delta)
	if _skid != null:
		var on := _vel.length() > 3.0 and _landed
		if _skid.emitting != on:
			_skid.emitting = on
		_spark_t -= delta
		if on and _spark_t <= 0.0:
			_spark_t = randf_range(0.06, 0.16)
			var back := -_vel.normalized()
			Fx.spark(global_position + back * radius * 0.6 + Vector3.UP * 0.3, (Vector3.UP + back).normalized(), true, false)


# падение: угол растёт как у валящегося столба (медленно, потом быстрее), у земли удар — пыль и звук,
# лёгкий отскок, дальше лежит. Валится через переднюю кромку и оседает
func _update_fall(delta: float) -> void:
	if _fall_t < 0.0 or _tumble == null:
		return
	_fall_t += delta
	var T := 0.55
	var k := clampf(_fall_t / T, 0.0, 1.0)
	var a := _fall_angle * k * k
	if _fall_t > T:
		a = _fall_angle - sin(clampf((_fall_t - T) / 0.25, 0.0, 1.0) * PI) * 0.07
	var dir := Vector3.UP.cross(_fall_axis)          # куда падает (вперёд)
	var pivot := dir * radius * 0.5
	var b := Basis(_fall_axis, -a)
	_tumble.transform = Transform3D(b, pivot - b * pivot + Vector3.DOWN * _fall_drop * k * k)
	if not _landed and _fall_t >= T:
		_landed = true
		Fx.dust_ring(global_position + dir * radius, radius * 2.6)
		Fx.dust_ring(global_position, radius * 1.8)
		Sfx.play_at("land", global_position, 0.0, 0.08)
		Sfx.play_at("wall", global_position, -4.0, 0.1)
	if _fall_t > T + 0.3:
		_fall_t = -1.0


# шлейф пыли за скользящей тушкой (в мире, тает)
func _make_skid() -> void:
	_skid = CPUParticles3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(2.2, 2.2)
	_skid.mesh = qm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	var tex := Art.fx_tex("smoke_07")
	if tex != null:
		mat.albedo_texture = tex
	_skid.material_override = mat
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.5, 0.44, 0.34, 0.55))
	ramp.set_color(1, Color(0.48, 0.45, 0.4, 0.0))
	_skid.color_ramp = ramp
	var grow := Curve.new()
	grow.add_point(Vector2(0, 0.6))
	grow.add_point(Vector2(1, 1.8))
	_skid.scale_amount_curve = grow
	_skid.local_coords = false
	_skid.amount = int(40 * Cfg.gfx(0.4, 0.7, 1.0))
	_skid.lifetime = 1.4
	_skid.emitting = false
	_skid.direction = Vector3.UP
	_skid.spread = 60.0
	_skid.initial_velocity_min = 1.0
	_skid.initial_velocity_max = 2.5
	_skid.damping_min = 2.0
	_skid.damping_max = 3.0
	_skid.gravity = Vector3(0, 0.3, 0)
	_skid.angle_max = 360.0
	_skid.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_skid.emission_sphere_radius = radius * 0.6
	_skid.position = Vector3(0, 0.4, 0)
	_skid.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_skid)


# отлетают 1–2 части: нога, пушка или кусок брони. Летят по инерции тушки плюс в сторону и вверх,
# кувыркаются, бьются о землю с пылью и остаются лежать рядом (уходят вместе с тушкой)
func _detach_parts(fwd: Vector3, sp: float) -> void:
	var v = _visual
	var kinds: Array = ["plate"]
	if "gun_pods" in v:
		for i in v.gun_pods.size():
			if is_instance_valid(v.gun_pods[i]):
				kinds.append("gun%d" % i)
	if "feet" in v:
		for i in v.feet.size():
			if v.feet[i].thigh != null:
				kinds.append("leg%d" % i)
	kinds.shuffle()
	var n := 2 if randf() < 0.35 + clampf(sp / 60.0, 0.0, 0.4) else 1
	for kind in kinds.slice(0, n):
		var holder := Node3D.new()
		holder.top_level = true
		add_child(holder)
		var nodes: Array = []
		if kind.begins_with("gun"):
			nodes = [v.gun_pods[int(kind.right(1))]]
		elif kind.begins_with("leg"):
			var f = v.feet[int(kind.right(1))]
			nodes = [f.thigh, f.shin, f.node]
		if nodes.is_empty():
			# кусок брони: плита с корпуса
			var mi := MeshInstance3D.new()
			var hs: float = float(v.get("hs")) if v.get("hs") != null else 1.0
			var s := Vector3(randf_range(0.8, 1.4), randf_range(0.12, 0.22), randf_range(0.6, 1.1)) * hs
			mi.mesh = Art.bevel_box(s, 0.05)
			mi.material_override = v.get("m_armor")
			holder.global_position = global_position + Vector3(randf_range(-0.6, 0.6), 2.6, randf_range(-0.6, 0.6))
			holder.add_child(mi)
		else:
			holder.global_position = (nodes[0] as Node3D).global_position
			for nd in nodes:
				if nd != null and is_instance_valid(nd):
					nd.reparent(holder, true)
		var out := Vector3(holder.global_position.x - global_position.x, 0, holder.global_position.z - global_position.z)
		out = out.normalized() if out.length() > 0.1 else fwd.cross(Vector3.UP)
		var vel := _vel * randf_range(0.7, 1.0) + out * randf_range(3.0, 7.0) + Vector3.UP * randf_range(4.0, 8.0)
		var spin := Vector3(randf_range(-6, 6), randf_range(-4, 4), randf_range(-6, 6))
		_parts.append({"node": holder, "v": vel, "spin": spin, "rest": 0.35, "landed": false})


func _update_parts(delta: float) -> void:
	for p in _parts:
		var h: Node3D = p["node"]
		if not is_instance_valid(h) or p.get("done", false):
			continue
		var vel: Vector3 = p["v"]
		vel.y -= Cfg.gravity() * 2.2 * delta          # тяжёлая железка: падает быстро
		var pos := h.global_position + vel * delta
		if pos.y < p["rest"]:
			pos.y = p["rest"]
			if not p["landed"] or absf(vel.y) > 2.0:
				Fx.dust_ring(pos, 1.3)
				Fx.spark(pos, Vector3.UP, true, false)
			p["landed"] = true
			vel.y = -vel.y * 0.25
			vel.x *= 0.5
			vel.z *= 0.5
			p["spin"] = p["spin"] * 0.4
		var horiz := Vector3(vel.x, 0, vel.z)
		if p["landed"]:
			horiz = horiz.move_toward(Vector3.ZERO, (Cfg.wreck_friction + Cfg.wreck_drag * horiz.length_squared()) * delta)
			vel.x = horiz.x
			vel.z = horiz.z
		p["v"] = vel
		h.global_position = pos
		h.rotate(Vector3.RIGHT, p["spin"].x * delta)
		h.rotate(Vector3.FORWARD, p["spin"].z * delta)
		if p["landed"] and vel.length() < 0.2 and pos.y <= p["rest"] + 0.01:
			p["done"] = true


# толкнули: двигаемся, упираясь в стены и другие обломки (их тоже чуть подталкиваем)
# возвращает, на сколько реально сдвинулся
func shove(offset: Vector3, depth := 0) -> float:
	offset.y = 0
	if offset.length() < 0.0005:
		return 0.0
	var before := global_position
	var c := move_and_collide(offset)
	if c != null and depth < 2:
		var other = c.get_collider()
		if other != null and other.has_method("shove"):
			other.shove(c.get_remainder() * 0.6, depth + 1)
			move_and_collide(c.get_remainder() * 0.4)
	global_position.y = 0.0
	return Vector2(global_position.x - before.x, global_position.z - before.z).length()


func get_hit_radius() -> float:
	return radius


func get_hit_height() -> float:
	return height


func take_damage(amount: float, _pos: Vector3, _dir: Vector3, _kind := "", _src: Node = null) -> void:
	if _broken or amount <= 0.0:
		return
	hp -= amount
	if hp <= 0.0:
		_break()


func stun(_s: float) -> void:
	pass


func block_regen(_s: float) -> void:
	pass


func _break() -> void:
	_broken = true
	Fx.explosion(global_position + Vector3.UP * 1.0, 3.5 if not is_crate else 3.0)
	Sfx.play_at("boom", global_position, -6.0, 0.1)
	var count := loot if is_crate else randi_range(1, maxi(Cfg.loot_max, 1))
	var g = get_tree().current_scene
	if g != null and g.has_method("spawn_loot"):
		g.spawn_loot(global_position, count, is_crate)
	if _smoke != null:
		# дым остаётся и рассеивается
		var gp := _smoke.global_position
		remove_child(_smoke)
		get_tree().current_scene.add_child(_smoke)
		_smoke.global_position = gp
		_smoke.emitting = false
		get_tree().create_timer(2.5).timeout.connect(_smoke.queue_free)
	queue_free()
