class_name Roller
extends Area3D
## Шар-самоубийца: бронированный шар-мина выкатывается из-под меха в сторону прицела, отскакивает от
## стен, а увидев врага рядом — доворачивает к нему. Доехал до врага или проехал «Дальность» — сильный
## взрыв. Его видно (обычным обзором) и можно расстрелять: тогда лопается без урона.

var team := 0
var owner_mech: Node
var p := {}
var dir := Vector3.FORWARD
var seen := true
var dead := false
var hp := 50.0
var _left := 40.0
var _ball: Node3D
var _light: StandardMaterial3D
var _t := 0.0
var _lit := false

const R := 0.6                   # радиус шара
const SEEK := 9.0                # с какого расстояния доворачивает к врагу
const TURN := 3.0                # радиан в секунду


func _ready() -> void:
	add_to_group("gadgets")
	add_to_group("damageable")
	add_to_group("team_hitbox")
	collision_layer = 4
	collision_mask = 0
	monitoring = false
	hp = float(p.get("hp", 50.0))
	_left = float(p.get("range", 40.0))
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = R
	cs.shape = sh
	cs.position.y = R
	add_child(cs)
	_ball = Node3D.new()
	_ball.position.y = R
	add_child(_ball)
	var sm := SphereMesh.new()
	sm.radius = R
	sm.height = R * 2.0
	sm.radial_segments = 16
	sm.rings = 8
	var b := MeshInstance3D.new()
	b.mesh = sm
	b.material_override = Bolas.mat("roller", Color(0.25, 0.26, 0.24))
	_ball.add_child(b)
	# опоясывающая полоса, по ней видно, что шар катится
	var tm := TorusMesh.new()
	tm.inner_radius = R * 0.92
	tm.outer_radius = R * 1.04
	var band := MeshInstance3D.new()
	band.mesh = tm
	band.material_override = Bolas.mat("roller_band", Color(0.6, 0.45, 0.1))
	band.rotation.z = PI * 0.5
	_ball.add_child(band)
	_light = StandardMaterial3D.new()
	_light.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_light.albedo_color = Color(0.4, 0.1, 0.05)
	var lm := SphereMesh.new()
	lm.radius = 0.12
	lm.height = 0.24
	var l := MeshInstance3D.new()
	l.mesh = lm
	l.material_override = _light
	l.position = Vector3(0, R * 0.95, 0)
	_ball.add_child(l)


func get_hit_radius() -> float:
	return R


func take_damage(amount: float, _pos: Vector3, _dir: Vector3, _kind := "", _src: Node = null) -> void:
	if dead or amount <= 0.0:
		return
	hp -= amount
	if hp <= 0.0:
		dead = true
		if seen:
			Fx.explosion(global_position + Vector3.UP * R, 1.2)
		Sfx.play_at("boom", global_position, -10.0, 0.1)
		queue_free()


func _physics_process(delta: float) -> void:
	if dead:
		return
	visible = seen
	_t += delta
	var lit := fmod(_t, 0.4) < 0.12
	if lit != _lit:
		_lit = lit
		_light.albedo_color = Color(1.0, 0.25, 0.1) * 2.0 if lit else Color(0.4, 0.1, 0.05)
	# ищем врага рядом
	var g = get_tree().current_scene
	var near: Node3D = null
	var nd := SEEK
	if g != null and g.has_method("units"):
		for u in g.units():
			if u[2] == team:
				continue
			var d: float = Vector2(u[1].x - global_position.x, u[1].z - global_position.z).length() - float(u[3])
			if d < 1.0:
				_explode()
				return
			if d < nd:
				near = u[0]
				nd = d
	if near != null:
		var want := near.global_position - global_position
		want.y = 0
		var a := dir.signed_angle_to(want.normalized(), Vector3.UP)
		dir = dir.rotated(Vector3.UP, clampf(a, -TURN * delta, TURN * delta))
	# катимся; стена впереди — отскок
	var speed := float(p.get("speed", 12.0))
	var step := dir * speed * delta
	var q := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * R, global_position + Vector3.UP * R + dir * (speed * delta + R), 1 | 16)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		var n: Vector3 = hit["normal"]
		n.y = 0
		if n.length() > 0.1:
			dir = dir.bounce(n.normalized()).normalized()
		step = Vector3.ZERO
	global_position += step
	_left -= step.length()
	_ball.rotate(dir.cross(Vector3.UP).normalized() * -1.0, step.length() / R)
	if _left <= 0.0:
		_explode()


func _explode() -> void:
	dead = true
	var c := global_position + Vector3.UP * R
	var who: Node = owner_mech if is_instance_valid(owner_mech) else null
	var k: float = owner_mech.damage_mult() if is_instance_valid(owner_mech) else 1.0
	Fx.explosion(c, float(p.get("radius", 5.0)))
	Sfx.play_at("boom", c, 0.0, 0.1)
	Fx.blast(c, float(p.get("radius", 5.0)), float(p.get("damage", 90.0)) * k, float(p.get("edge_damage", 0.4)), team, who)
	queue_free()
