extends CharacterBody3D
## Обломок убитого меха или ящик с припасами.
## Обломок: чёрный дымящийся мех, по инерции проезжает несколько метров и замирает.
## Его можно толкать (чем тяжелее мех, тем легче), он закрывает от выстрелов, но не от вижена.
## Любой урон (свой, чужой, абилки) его ломает, тогда выпадают припасы.
## Ящик работает так же, только падает с неба и припасов в нём больше.

var team := -1                  # ничей: ломают все
var hp := 60.0
var weight := 60.0              # тонн, от этого зависит, как легко толкать
var radius := 1.8
var loot := 1                   # сколько припасов выпадет (0 = случайно от 1 до loot_max)
var is_crate := false
var _vel := Vector3.ZERO
var _visual: Node3D
var _smoke: CPUParticles3D
var _flash := 0.0
var _mats: Array = []
var _broken := false
var _cs: CollisionShape3D


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
	cyl.height = Cfg.hitbox_height
	cs.shape = cyl
	cs.position = Vector3(0, Cfg.hitbox_height * 0.5 + 0.15, 0)    # чуть над полом, чтобы не цеплять землю
	add_child(cs)


# обломок из меха: забираем его модель как есть и роняем
func setup_wreck(visual: Node3D, vel: Vector3, mech_weight: float, r: float) -> void:
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
	_visual.reparent(self, true)
	if _visual.has_method("set_charred"):
		_visual.set_charred()
	# ноги подкашиваются: модель оседает и чуть заваливается набок
	var drop: float = 2.05 * float(_visual.get("ls") if _visual.get("ls") != null else 1.0) * 0.55
	var tilt := Vector3(randf_range(-0.25, 0.25), 0, randf_range(-0.3, 0.3))
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_visual, "position:y", _visual.position.y - drop, 0.55).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(_visual, "rotation", _visual.rotation + tilt, 0.55).set_ease(Tween.EASE_IN)
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
	# скольжение по инерции после смерти
	if _vel.length() > 0.05:
		var c := move_and_collide(_vel * delta)
		if c != null:
			_vel = _vel.slide(c.get_normal()) * 0.5
		_vel = _vel.move_toward(Vector3.ZERO, Cfg.wreck_friction * delta)
	global_position.y = 0.0
	if _flash > 0.0:
		_flash -= delta


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
