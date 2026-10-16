extends CharacterBody3D
## Крип: маленький танк. Волнами выезжает с базы и едет по своей линии к вражеской базе.
## По дороге стреляет во всё вражеское рядом: крипов, мехов, турели, штаб.
## Крипы держат дистанцию друг от друга (настройка «Расстояние между крипами»), в кучу не сбиваются:
## каждый едет со своим смещением от середины линии и в бою занимает своё место вокруг цели.
## Числа танка лежат в parts.gd («Крипы»), волны в settings.gd (группа «Крипы»).

const Projectile := preload("res://scripts/projectile.gd")
const Hitbox := preload("res://scripts/hitbox.gd")
const HpBar := preload("res://scripts/hp_bar.gd")
const Art := preload("res://scripts/art.gd")

const ID := "creep_tank"

var team := 0
var lane := "mid"
var path: PackedVector3Array = PackedVector3Array()   # точки линии от своей базы к вражеской
var nav                           # карта проходимости
var slot := 0                     # место в колонне (от него смещение и угол атаки)
var hp := 100.0
var dead := false
var seen := true
var hitbox: Area3D
var last_attacker: Node = null
var stun_left := 0.0
var _stun_total := 1.0     # полное время оглушения — для шкалы контроля над полоской
var _wp := 1                      # к какой точке линии едем
var _side := 0.0                  # смещение от середины линии, метров
var _target: Node3D
var _think_t := 0.0
var _route := PackedVector3Array()
var _route_t := 0.0
var _route_goal := Vector3.INF
var _cool := 0.0
var _hull: Node3D
var _turret: Node3D
var _muzzle: Node3D
var _bar: Node3D
var _mats: Array = []
var _knock := Vector3.ZERO
var _yaw := 0.0

static var _shared := {}


func _ready() -> void:
	collision_layer = 64           # мехи сквозь крипов проходят, крипы упираются в мехов, стены и постройки
	collision_mask = 1 | 2 | 16 | 32
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	add_to_group("creeps")
	add_to_group("damageable")
	hp = max_hp()
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = 0.95
	sh.height = 1.6
	cs.shape = sh
	cs.position = Vector3(0, 0.9, 0)
	add_child(cs)
	hitbox = Hitbox.new()
	hitbox.mech = self
	add_child(hitbox)
	_build_visual()
	_bar = HpBar.new()
	_bar.color = Color(0.4, 0.9, 0.4) if team == Fx.player_team else Color(0.95, 0.25, 0.2)
	_bar.position = Vector3(0, 2.6, 0)
	_bar.scale = Vector3.ONE * 0.55
	add_child(_bar)
	# смещение от середины линии: крипы едут не гуськом, а свободным строем
	var spacing := Cfg.creep_spacing
	_side = (float(slot % 3) - 1.0) * spacing * 0.7
	if path.size() > 1:
		_yaw = _yaw_to(path[1] - global_position)
		_hull.rotation.y = _yaw
		_turret.rotation.y = _yaw


func max_hp() -> float:
	return Parts.v(ID, "hp")


func get_hit_radius() -> float:
	return Parts.v(ID, "hit_radius")


func get_hit_height() -> float:
	return 1.6      # настоящая высота танка с башней


func vision_radius() -> float:
	return Parts.v(ID, "vision")


func is_cloaked() -> bool:
	return false


func is_landing() -> bool:
	return false


func stun(seconds: float) -> void:
	if seconds > stun_left:
		_stun_total = seconds
	stun_left = maxf(stun_left, seconds)


func block_regen(_s: float) -> void:
	pass


func knock(v: Vector3) -> void:
	_knock += v * 0.8


func take_damage(amount: float, pos: Vector3, _dir: Vector3, _kind := "", src: Node = null) -> void:
	if dead or amount <= 0.0:
		return
	if src != null and is_instance_valid(src):
		last_attacker = src
	amount = minf(amount, hp)
	hp -= amount
	Battle.on_damage(src, self, amount, pos)
	if hp <= 0.0:
		_die()


func _die() -> void:
	dead = true
	hitbox.set_active(false)
	Battle.on_kill(last_attacker, self)
	if seen:
		Fx.explosion(global_position + Vector3.UP * 0.8, 2.6)
	Sfx.play_at("boom", global_position, -8.0, 0.15)
	if randf() < Cfg.creep_loot_chance:
		var g = get_tree().current_scene
		if g != null and g.has_method("spawn_loot"):
			g.spawn_loot(global_position, 1)
	queue_free()


# ------------------------------------------------------------------
#  Каждый кадр
# ------------------------------------------------------------------

# мысли крипа (цель, перезарядка) — каждый тик игры
func _tick(delta: float) -> void:
	visible = seen
	_cool = maxf(_cool - delta, 0.0)
	stun_left = maxf(stun_left - delta, 0.0)
	_bar.visible = seen and (hp < max_hp() - 0.5 or stun_left > 0.0)
	_bar.set_ratio(hp / maxf(max_hp(), 1.0))
	_bar.set_control("Оглушён" if stun_left > 0.0 else "", stun_left / maxf(_stun_total, 0.01))
	if stun_left > 0.0 and seen and Cfg.stun_zaps > 0 and randf() < 0.35:
		Fx.zap(global_position, 1.6, 1.8)
	_think_t -= delta
	if _think_t <= 0.0:
		_think_t = 0.2 + randf() * 0.05
		_target = _pick_target()
	if _target != null and (not is_instance_valid(_target) or _target.get("dead")):
		_target = null


func _physics_process(delta: float) -> void:
	if dead:
		return
	_tick(delta)
	if dead:
		return
	var pos := global_position
	var want := Vector3.ZERO
	var speed := Parts.v(ID, "move_speed")
	if stun_left > 0.0:
		want = Vector3.ZERO
	elif _target != null:
		want = _engage(delta, pos)
	else:
		want = _follow_lane(delta, pos)
	want += _separation(pos) * 0.9
	if want.length() > 1.0:
		want = want.normalized()
	var hv := Vector3(velocity.x, 0, velocity.z).move_toward(want * speed, 14.0 * delta)
	_knock = _knock.move_toward(Vector3.ZERO, 30.0 * delta)
	velocity = hv + _knock
	velocity.y = 0.0
	move_and_slide()
	global_position.y = 0.0
	# корпус разворачивается туда, куда едет; башня на цель
	var flat := Vector3(velocity.x, 0, velocity.z)
	if flat.length() > 0.5:
		_yaw = rotate_toward(_yaw, _yaw_to(flat), deg_to_rad(200.0) * delta)
	_hull.rotation.y = _yaw
	var aim_yaw := _yaw
	if _target != null and is_instance_valid(_target):
		aim_yaw = _yaw_to(_target.global_position - pos)
	_turret.rotation.y = rotate_toward(_turret.rotation.y, aim_yaw, deg_to_rad(220.0) * delta)
	if _target != null and is_instance_valid(_target) and stun_left <= 0.0 and _cool <= 0.0:
		if absf(angle_difference(_turret.rotation.y, aim_yaw)) < 0.12:
			_fire()


func _yaw_to(v: Vector3) -> float:
	return atan2(-v.x, -v.z)


# ехать по линии: к следующей точке, со своим смещением вбок
func _follow_lane(delta: float, pos: Vector3) -> Vector3:
	if path.size() < 2:
		return Vector3.ZERO
	_wp = clampi(_wp, 1, path.size() - 1)
	var goal := path[_wp]
	var seg := path[_wp] - path[_wp - 1]
	seg.y = 0
	if seg.length() > 0.1 and _wp < path.size() - 1:
		var perp := Vector3(-seg.z, 0, seg.x).normalized()
		goal += perp * _side
	var to := goal - pos
	to.y = 0
	if to.length() < 6.0 and _wp < path.size() - 1:
		_wp += 1
		return to.normalized()
	return _route_to(delta, pos, goal)


# в бою: подъехать на дистанцию стрельбы и встать на своё место вокруг цели
func _engage(delta: float, pos: Vector3) -> Vector3:
	var tp := _target.global_position
	var to := tp - pos
	to.y = 0
	var dist := to.length()
	var rng := Parts.v(ID, "range")
	var size: float = _target.get_hit_radius() if _target.has_method("get_hit_radius") else 1.0
	if dist - size > rng * 0.85 or not _clear_shot(pos, tp):
		return _route_to(delta, pos, tp)
	# своё место: смещение по кругу вокруг цели (у каждого крипа свой угол)
	var a := (float(slot % 5) - 2.0) * 0.35
	var spot := tp - to.normalized().rotated(Vector3.UP, a) * minf(dist, rng * 0.75)
	var off := spot - pos
	off.y = 0
	if off.length() < 1.5:
		return Vector3.ZERO
	return off.normalized() * 0.6


func _route_to(delta: float, pos: Vector3, goal: Vector3) -> Vector3:
	var to := goal - pos
	to.y = 0
	if nav == null:
		return to.normalized()
	_route_t -= delta
	if _route_t <= 0.0 or _route.is_empty() or goal.distance_to(_route_goal) > 4.0:
		_route = nav.find_path(pos, goal)
		_route_goal = goal
		_route_t = 1.0 + randf() * 0.3
	if _route.size() <= 2:
		return to.normalized()
	for i in range(1, _route.size()):
		var d := Vector3(_route[i].x - pos.x, 0, _route[i].z - pos.z)
		if d.length() > 2.4:
			return d.normalized()
	return to.normalized()


# свои рядом: отъезжаем, чтобы не сбиваться в кучу
func _separation(pos: Vector3) -> Vector3:
	var push := Vector3.ZERO
	var r := Cfg.creep_spacing
	var g = get_tree().current_scene
	if g == null or not g.has_method("units"):
		return push
	for u in g.units():
		if u[4] or u[2] != team or u[0] == self:
			continue
		var d: Vector3 = pos - u[1]
		d.y = 0
		var l := d.length()
		if l < r and l > 0.01:
			push += d / l * (1.0 - l / r)
	return push


func _clear_shot(a: Vector3, b: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(a + Vector3.UP * 1.2, b + Vector3.UP * 1.2, 1)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


# ближайший видимый враг в обзоре: крипы и мехи, постройки только вблизи
func _pick_target() -> Node3D:
	var pos := global_position
	var vis := Parts.v(ID, "vision")
	var rng := Parts.v(ID, "range")
	var g = get_tree().current_scene
	var best: Node3D = null
	var best_s := 1e9
	if g == null or not g.has_method("units"):
		return null
	# мехи и крипы — из общего списка тика (main.units), постройки — по группе
	for u in g.units():
		if u[2] == team:
			continue
		var n = u[0]
		if not is_instance_valid(n) or n.dead or (u[4] and n.shield_left > 0.0):
			continue
		var d: float = (u[1] - pos).length() - u[3]
		if d > vis:
			continue
		var score := d + (6.0 if u[4] else 0.0)
		if score >= best_s:
			continue
		if not g.is_visible_to(team, n):
			continue
		best_s = score
		best = n
	for n in get_tree().get_nodes_in_group("structures"):
		if n.team == team or n.dead:
			continue
		var d2: float = n.global_position.distance_to(pos) - n.get_hit_radius()
		if d2 > rng + 6.0 or d2 >= best_s:
			continue
		if n.has_method("protected") and n.protected():
			continue
		best_s = d2
		best = n
	return best


func _fire() -> void:
	var origin: Vector3 = _muzzle.global_position
	var tp: Vector3 = _target.global_position
	var spd := Parts.v(ID, "bullet_speed")
	var aim: Vector3 = tp + _target.velocity * (origin.distance_to(tp) / maxf(spd, 1.0)) * 0.5
	# в середину хитбокса цели по высоте
	aim.y = tp.y + (_target.get_hit_height() * 0.5 if _target.has_method("get_hit_height") else 1.0)
	var dir: Vector3 = (aim - origin).normalized().rotated(Vector3.UP, randf_range(-0.04, 0.04))
	if not _clear_shot(global_position, tp) and not _target.is_in_group("structures"):
		return
	_cool = 1.0 / maxf(Parts.v(ID, "fire_rate"), 0.05)
	var p := Projectile.new()
	p.setup(origin, dir * spd, Parts.v(ID, "damage"), Parts.v(ID, "range") + 4.0, self)
	p.tracer = 0.12
	get_tree().current_scene.add_child(p)
	if seen:
		Fx.spark(origin, dir, false, false)
		Fx.light_flash(origin, Color(1.0, 0.7, 0.35), 6.0, 2.0, 0.07)
	Sfx.play_at("shot", global_position, -12.0, 0.15)


# ------------------------------------------------------------------
#  Вид: маленький танк на гусеницах, башня с пушкой, полоса цвета команды
# ------------------------------------------------------------------

func _mat(c: Color, kind := "armor", metal := 0.3, rough := 0.6) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metal
	m.roughness = rough
	m.emission_enabled = true
	m.emission = Color.BLACK
	Art.apply_panels(m, 1.4, kind)
	_mats.append(m)
	return m


func _part(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = Art.bevel_box(size)
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


func _build_visual() -> void:
	var team_col := Cfg.player_color if team == 0 else Cfg.enemy_color
	var body := _mat(Color(0.42, 0.44, 0.4) if team == 0 else Color(0.44, 0.38, 0.37))
	var dark := _mat(Color(0.12, 0.12, 0.13), "darkmetal", 0.4, 0.6)
	var glow := StandardMaterial3D.new()
	glow.albedo_color = team_col
	glow.emission_enabled = true
	glow.emission = team_col
	glow.emission_energy_multiplier = 0.9
	_hull = Node3D.new()
	add_child(_hull)
	# корпус
	_part(_hull, Vector3(1.5, 0.55, 2.3), Vector3(0, 0.62, 0), body)
	_part(_hull, Vector3(1.3, 0.35, 0.8), Vector3(0, 0.62, -1.15), body, Vector3(-0.5, 0, 0))
	for sx in [-1.0, 1.0]:
		_part(_hull, Vector3(0.12, 0.06, 1.4), Vector3(0.62 * sx, 0.92, 0.3), glow)
	# гусеницы с катками
	for s in [-1.0, 1.0]:
		_part(_hull, Vector3(0.42, 0.55, 2.5), Vector3(0.88 * s, 0.32, 0), dark)
		for k in 4:
			var wheel := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.22
			cm.bottom_radius = 0.22
			cm.height = 0.46
			cm.radial_segments = 10
			cm.rings = 1
			wheel.mesh = cm
			wheel.material_override = body
			wheel.rotation.z = PI / 2
			wheel.position = Vector3(0.9 * s, 0.28, -0.9 + k * 0.6)
			_hull.add_child(wheel)
	# башня
	_turret = Node3D.new()
	_turret.position = Vector3(0, 0.95, 0.1)
	add_child(_turret)
	_part(_turret, Vector3(1.0, 0.42, 1.1), Vector3(0, 0.2, 0), body)
	_part(_turret, Vector3(0.7, 0.2, 0.5), Vector3(0, 0.46, 0.2), dark)
	var barrel := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.09
	bm.bottom_radius = 0.11
	bm.height = 1.5
	bm.radial_segments = 8
	bm.rings = 1
	barrel.mesh = bm
	barrel.material_override = dark
	barrel.rotation.x = PI / 2
	barrel.position = Vector3(0, 0.2, -1.2)
	_turret.add_child(barrel)
	_part(_turret, Vector3(0.12, 0.08, 0.12), Vector3(-0.3, 0.45, 0.45), glow)
	_muzzle = Node3D.new()
	_muzzle.position = Vector3(0, 0.2, -2.0)
	_turret.add_child(_muzzle)
	for mi in _hull.find_children("*", "MeshInstance3D", true, false) + _turret.find_children("*", "MeshInstance3D", true, false):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	# склеиваем детали корпуса и башни: по одной модели на материал (было 18 деталей на крипа, стало 6).
	# Катки больше не крутятся: с высоты камеры этого не видно, а каждый каток был отдельной деталью
	Art.merge_meshes(_hull, [body, dark, glow])
	Art.merge_meshes(_turret, [body, dark, glow], [_muzzle])
