class_name GravityWell
extends Node3D
## Гравитационный якорь: снаряд вбился в землю, раскрыл лапы и «Длительность» секунд медленно тянет
## вражеских мехов к себе. Тяжёлого тянет слабее (F2 → «Контроль», базовая масса). Стены держат:
## сквозь стену не протащит. Крипов не тянет.

var team := 0
var shooter: Node
var radius := 9.0
var life := 2.5
var push := 6.0                  # скорость притяжения меха базовой массы, единиц/с
var _t := 0.0
var _ring: Node3D
var _ring2: Node3D
var _core_m: StandardMaterial3D


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var metal := Bolas.mat("anchor", Color(0.22, 0.22, 0.25))
	var cm := CylinderMesh.new()
	cm.top_radius = 0.35
	cm.bottom_radius = 0.55
	cm.height = 0.6
	cm.radial_segments = 10
	var base := MeshInstance3D.new()
	base.mesh = cm
	base.material_override = metal
	base.position.y = 0.3
	add_child(base)
	# лапы, вбитые в землю
	var lm := BoxMesh.new()
	lm.size = Vector3(0.18, 0.12, 1.3)
	for k in 3:
		var a := TAU * k / 3.0
		var leg := MeshInstance3D.new()
		leg.mesh = lm
		leg.material_override = metal
		leg.position = Vector3(sin(a) * 0.7, 0.12, cos(a) * 0.7)
		leg.rotation = Vector3(0.35, a, 0)
		add_child(leg)
	# светящееся ядро и два кольца, которые крутятся навстречу
	_core_m = StandardMaterial3D.new()
	_core_m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_core_m.albedo_color = Color(0.7, 0.4, 1.0) * 2.5
	var sm := SphereMesh.new()
	sm.radius = 0.3
	sm.height = 0.6
	var core := MeshInstance3D.new()
	core.mesh = sm
	core.material_override = _core_m
	core.position.y = 1.0
	add_child(core)
	var tm := TorusMesh.new()
	tm.inner_radius = 0.75
	tm.outer_radius = 0.85
	_ring = MeshInstance3D.new()
	_ring.mesh = tm
	_ring.material_override = Bolas.mat("anchor_ring", Color(0.6, 0.35, 1.0) * 1.6, true)
	_ring.position.y = 1.0
	add_child(_ring)
	_ring2 = _ring.duplicate()
	_ring2.scale = Vector3.ONE * 0.7
	add_child(_ring2)
	Fx.light_flash(global_position + Vector3.UP * 1.5, Color(0.6, 0.35, 1.0), radius * 1.5, 1.2, life, "grav_%d" % get_instance_id(), true)
	Fx.dust_ring(global_position, radius)
	Sfx.play_at("emp", global_position, -3.0, 0.05)


func _physics_process(delta: float) -> void:
	_t += delta
	_ring.rotate_x(delta * 5.0)
	_ring.rotate_y(delta * 3.0)
	_ring2.rotate_z(-delta * 6.0)
	if _t >= life:
		Fx.burst(global_position + Vector3.UP, Color(0.6, 0.35, 1.0), 2.0)
		queue_free()
		return
	var g = get_tree().current_scene
	if g == null or not g.has_method("units"):
		return
	for u in g.units():
		if u[2] == team or not u[4]:
			continue
		var d: Vector3 = global_position - u[1]
		d.y = 0
		var dist := d.length()
		if dist > radius or dist < 1.2:
			continue
		u[0].pull(d / dist * push)
