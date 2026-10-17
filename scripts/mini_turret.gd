class_name MiniTurret
extends Area3D
## Мини-турель: контейнер прилетел навесом и разложился в треногу с автопушкой. «Длительность» секунд
## стреляет в ближайшего видимого своей команде врага (меха или крипа) в радиусе, если стены не мешают.
## Её видно (обычным обзором) и можно сломать.

var team := 0
var owner_mech: Node
var p := {}
var seen := true
var dead := false
var hp := 150.0
var _t := 0.0
var _cool := 0.5
var _head: Node3D
var _target: Node3D
var _look_t := 0.0

const MUZZLE_H := 1.5
const Projectile := preload("res://scripts/projectile.gd")


func _ready() -> void:
	add_to_group("gadgets")
	add_to_group("damageable")
	add_to_group("team_hitbox")
	collision_layer = 4
	collision_mask = 0
	monitoring = false
	hp = float(p.get("hp", 150.0))
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = 0.8
	sh.height = 2.0
	cs.shape = sh
	cs.position.y = 1.0
	add_child(cs)
	var metal := Bolas.mat("turret", Color(0.33, 0.35, 0.31))
	var dark := Bolas.mat("turret_d", Color(0.18, 0.18, 0.18))
	var body := Node3D.new()
	body.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(body)
	# тренога
	var lm := BoxMesh.new()
	lm.size = Vector3(0.1, 1.5, 0.1)
	for k in 3:
		var a := TAU * k / 3.0
		var leg := MeshInstance3D.new()
		leg.mesh = lm
		leg.material_override = dark
		leg.position = Vector3(sin(a) * 0.45, 0.65, cos(a) * 0.45)
		leg.rotation = Vector3(cos(a) * 0.45, 0, -sin(a) * 0.45)
		body.add_child(leg)
	# голова с пушкой
	_head = Node3D.new()
	_head.position.y = MUZZLE_H
	body.add_child(_head)
	var bm := BoxMesh.new()
	bm.size = Vector3(0.7, 0.45, 0.8)
	var box := MeshInstance3D.new()
	box.mesh = bm
	box.material_override = metal
	_head.add_child(box)
	var gm := CylinderMesh.new()
	gm.top_radius = 0.07
	gm.bottom_radius = 0.09
	gm.height = 1.0
	gm.radial_segments = 8
	for sx in [-0.14, 0.14]:
		var g := MeshInstance3D.new()
		g.mesh = gm
		g.material_override = dark
		g.rotation.x = PI * 0.5
		g.position = Vector3(sx, 0.05, -0.8)
		_head.add_child(g)
	body.scale = Vector3(1.0, 0.1, 1.0)
	create_tween().tween_property(body, "scale", Vector3.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	Sfx.play_at("wall", global_position, -6.0, 0.1)


func get_hit_radius() -> float:
	return 0.8


func get_hit_height() -> float:
	return 2.0


func take_damage(amount: float, pos: Vector3, _dir: Vector3, _kind := "", _src: Node = null) -> void:
	if dead or amount <= 0.0:
		return
	hp -= amount
	if hp <= 0.0:
		_break(pos)


func _break(_pos: Vector3) -> void:
	dead = true
	if seen:
		Fx.explosion(global_position + Vector3.UP * 1.0, 1.5)
	Sfx.play_at("boom", global_position, -8.0, 0.1)
	queue_free()


func _physics_process(delta: float) -> void:
	visible = seen
	_t += delta
	if _t >= float(p.get("duration", 15.0)):
		_break(global_position)
		return
	if _t < 0.4:
		return          # ещё раскладывается
	_look_t -= delta
	if _look_t <= 0.0:
		_look_t = 0.2
		_target = _find_target()
	if _target == null or not is_instance_valid(_target) or _target.dead:
		return
	var aim: Vector3 = _target.global_position + Vector3.UP * _aim_h(_target)
	var origin := global_position + Vector3.UP * MUZZLE_H
	var flat := Vector3(aim.x - origin.x, 0, aim.z - origin.z)
	if flat.length() > 0.1:
		_head.rotation.y = atan2(-flat.x, -flat.z)
	_cool -= delta
	if _cool > 0.0:
		return
	_cool = 1.0 / maxf(float(p.get("fire_rate", 4.0)), 0.1)
	var dir := (aim - origin).normalized()
	var pr := Projectile.new()
	var who: Node = owner_mech if is_instance_valid(owner_mech) else self
	pr.setup(origin + dir * 1.0, dir * 70.0, float(p.get("damage", 6.0)), float(p.get("radius", 26.0)) + 4.0, who)
	pr.team = team
	pr.tracer = 0.08
	get_tree().current_scene.add_child(pr)
	if seen:
		Fx.spark(origin + dir * 1.2, dir, false, false)
		Fx.light_flash(origin, Color(1.0, 0.7, 0.35), 5.0, 1.5, 0.06)
	Sfx.play_at("shot", global_position, -12.0, 0.15)


func _aim_h(n: Node) -> float:
	return n.get_hit_height() * 0.5 if n.has_method("get_hit_height") else 0.8


# ближайший враг в радиусе, которого видит своя команда и до которого нет стены
func _find_target() -> Node3D:
	var g = get_tree().current_scene
	if g == null or not g.has_method("units"):
		return null
	var best: Node3D = null
	var bd := float(p.get("radius", 26.0))
	var origin := global_position + Vector3.UP * MUZZLE_H
	for u in g.units():
		if u[2] == team:
			continue
		var n = u[0]
		var d: float = Vector2(u[1].x - global_position.x, u[1].z - global_position.z).length()
		if d >= bd or (g.get("vision") != null and not g.vision.is_visible_to(team, n)):
			continue
		var q := PhysicsRayQueryParameters3D.create(origin, n.global_position + Vector3.UP * _aim_h(n), 1)
		if not get_world_3d().direct_space_state.intersect_ray(q).is_empty():
			continue
		best = n
		bd = d
	return best
