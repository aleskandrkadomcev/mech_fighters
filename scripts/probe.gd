class_name ScanProbe
extends Area3D
## Скан-зонд: снаряд прилетел навесом, воткнулся в землю, раскрыл антенну. Пока стоит, даёт своей
## команде обзор вокруг себя (как мех: стены закрывают) и омни рядом (видно невидимок).
## Врагу зонд не виден, пока тот не подойдёт вплотную (омни-сенсор, как с минами). Зонд можно сломать.
## Обзор считает vision.gd (группа "probes").

var team := 0
var owner_mech: Node
var p := {}                     # числа модуля из parts.gd: radius (обзор), omni, duration, hp
var seen := true                # видит ли его команда игрока
var dead := false
var hp := 50.0
var _t := 0.0
var _dish: Node3D
var _light: StandardMaterial3D
var _body: Node3D
var _base := Color.WHITE
var _lit := true


func _ready() -> void:
	add_to_group("probes")
	add_to_group("damageable")
	add_to_group("team_hitbox")          # свои пули сквозь свой зонд (Fx.team_rids)
	collision_layer = 4
	collision_mask = 0
	monitoring = false
	hp = float(p.get("hp", 50.0))
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = 0.6
	sh.height = 2.6
	cs.shape = sh
	cs.position.y = 1.3
	add_child(cs)

	_body = Node3D.new()
	add_child(_body)
	var metal := Bolas.mat("probe", Color(0.32, 0.34, 0.3))
	# корпус-цилиндр, наполовину в земле
	var cm := CylinderMesh.new()
	cm.top_radius = 0.22
	cm.bottom_radius = 0.3
	cm.height = 1.1
	cm.radial_segments = 10
	var c := MeshInstance3D.new()
	c.mesh = cm
	c.material_override = metal
	c.position.y = 0.45
	_body.add_child(c)
	# три упора
	var lm := BoxMesh.new()
	lm.size = Vector3(0.08, 0.08, 0.8)
	for k in 3:
		var leg := MeshInstance3D.new()
		leg.mesh = lm
		leg.material_override = metal
		var a := TAU * k / 3.0
		leg.position = Vector3(sin(a) * 0.35, 0.15, cos(a) * 0.35)
		leg.rotation = Vector3(0.5, a, 0)
		_body.add_child(leg)
	# мачта и вращающаяся тарелка
	var mm := CylinderMesh.new()
	mm.top_radius = 0.03
	mm.bottom_radius = 0.05
	mm.height = 1.4
	mm.radial_segments = 6
	var mast := MeshInstance3D.new()
	mast.mesh = mm
	mast.material_override = metal
	mast.position.y = 1.7
	_body.add_child(mast)
	_dish = Node3D.new()
	_dish.position.y = 2.35
	_body.add_child(_dish)
	var dm := BoxMesh.new()
	dm.size = Vector3(0.9, 0.06, 0.25)
	var dish := MeshInstance3D.new()
	dish.mesh = dm
	dish.material_override = metal
	_dish.add_child(dish)
	_light = StandardMaterial3D.new()
	_light.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var friend: bool = team == Fx.player_team
	_base = Color(0.3, 1.0, 0.4) if friend else Color(1.0, 0.25, 0.2)
	_light.albedo_color = _base
	var bm := SphereMesh.new()
	bm.radius = 0.08
	bm.height = 0.16
	var bulb := MeshInstance3D.new()
	bulb.mesh = bm
	bulb.material_override = _light
	bulb.position.y = 2.5
	_body.add_child(bulb)
	Sfx.play_at("step", global_position, -4.0, 0.1)


func get_hit_radius() -> float:
	return 0.6


func take_damage(amount: float, pos: Vector3, _dir: Vector3, _kind := "", _src: Node = null) -> void:
	if dead or amount <= 0.0:
		return
	hp -= amount
	if hp <= 0.0:
		_break(pos)


func _break(pos: Vector3) -> void:
	dead = true
	if seen:
		Fx.spark(pos, Vector3.UP, true, false)
		Sfx.play_at("hit", global_position, -3.0, 0.1)
	queue_free()


func _physics_process(delta: float) -> void:
	_t += delta
	visible = seen
	_dish.rotate_y(delta * 2.5)
	var lit := fmod(_t, 1.0) < 0.15        # мигает раз в секунду; материал трогаем только при смене
	if lit != _lit:
		_lit = lit
		_light.albedo_color = _base * (1.0 if lit else 0.35)
	if _t >= float(p.get("duration", 60.0)):
		dead = true
		queue_free()
