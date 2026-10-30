class_name RelayMast
extends Area3D
## Ретранслятор Командира: контейнер прилетел навесом и раскрылся в мачту с антенной. «Длительность» секунд
## свои мехи в «Радиусе» бьют сильнее на «Усиление». Мачту видно (обычным обзором) и можно сломать.

var team := 0
var owner_mech: Node
var p := {}
var seen := true
var dead := false
var hp := 150.0
var _t := 0.0
var _tick := 0.0
var _lamp: StandardMaterial3D
var _dish: Node3D

const TICK := 0.25


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
	sh.radius = 0.6
	sh.height = 3.2
	cs.shape = sh
	cs.position.y = 1.6
	add_child(cs)
	var metal := Bolas.mat("relay", Color(0.34, 0.36, 0.33))
	var dark := Bolas.mat("turret_d", Color(0.18, 0.18, 0.18))
	var body := Node3D.new()
	body.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(body)
	# основание-контейнер и три опоры
	var bm := BoxMesh.new()
	bm.size = Vector3(0.9, 0.5, 0.9)
	var base := MeshInstance3D.new()
	base.mesh = bm
	base.material_override = metal
	base.position.y = 0.25
	body.add_child(base)
	var lm := BoxMesh.new()
	lm.size = Vector3(0.08, 0.9, 0.08)
	for k in 3:
		var a := TAU * k / 3.0
		var leg := MeshInstance3D.new()
		leg.mesh = lm
		leg.material_override = dark
		leg.position = Vector3(sin(a) * 0.6, 0.3, cos(a) * 0.6)
		leg.rotation = Vector3(cos(a) * 0.7, 0, -sin(a) * 0.7)
		body.add_child(leg)
	# мачта и антенна-тарелка наверху (крутится)
	var mm := CylinderMesh.new()
	mm.top_radius = 0.06
	mm.bottom_radius = 0.11
	mm.height = 2.8
	mm.radial_segments = 8
	var mast := MeshInstance3D.new()
	mast.mesh = mm
	mast.material_override = dark
	mast.position.y = 1.9
	body.add_child(mast)
	_dish = Node3D.new()
	_dish.position.y = 3.1
	body.add_child(_dish)
	var dm := CylinderMesh.new()
	dm.top_radius = 0.55
	dm.bottom_radius = 0.1
	dm.height = 0.25
	dm.radial_segments = 12
	var dish := MeshInstance3D.new()
	dish.mesh = dm
	dish.material_override = metal
	dish.rotation.x = 1.1
	_dish.add_child(dish)
	# лампа на верхушке: мигает цветом команды
	var sm := SphereMesh.new()
	sm.radius = 0.12
	sm.height = 0.24
	sm.radial_segments = 8
	sm.rings = 4
	var lamp := MeshInstance3D.new()
	lamp.mesh = sm
	_lamp = StandardMaterial3D.new()
	_lamp.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_lamp.albedo_color = Color(0.4, 0.7, 1.0) if team == Fx.player_team else Color(1.0, 0.3, 0.25)
	lamp.material_override = _lamp
	lamp.position.y = 3.4
	body.add_child(lamp)
	Sfx.play_at("wall", global_position, -6.0, 0.1)


func get_hit_radius() -> float:
	return 0.6


func get_hit_height() -> float:
	return 3.2


func take_damage(amount: float, pos: Vector3, _dir: Vector3, _kind := "", _src: Node = null) -> void:
	if dead or amount <= 0.0:
		return
	hp -= amount
	if hp <= 0.0:
		dead = true
		if seen:
			Fx.explosion(global_position + Vector3.UP * 1.5, 1.5)
		Sfx.play_at("boom", global_position, -8.0, 0.1)
		queue_free()


func _process(delta: float) -> void:
	_dish.rotation.y += delta * 1.5
	var on := fmod(_t, 1.0) < 0.2
	var a := 1.0 if on else 0.25
	if absf(_lamp.albedo_color.a - a) > 0.01:
		_lamp.albedo_color.a = a
		_lamp.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if a < 1.0 else BaseMaterial3D.TRANSPARENCY_DISABLED


func _physics_process(delta: float) -> void:
	visible = seen
	_t += delta
	if _t >= float(p.get("duration", 15.0)):
		dead = true
		queue_free()
		return
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = TICK
	var r: float = p.get("radius", 12.0)
	var k: float = p.get("boost", 0.2)
	for m in get_tree().get_nodes_in_group("mechs"):
		if m.dead or m.team != team:
			continue
		var d: Vector3 = m.global_position - global_position
		d.y = 0
		if d.length() <= r:
			m.relay_buff(k, TICK + 0.1)
