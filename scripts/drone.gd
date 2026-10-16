class_name RepairDrone
extends Node3D
## Ремонтный дрон: вылетает из меха к союзнику (или к самому меху), висит над ним и чинит сварочным
## лучом «Длительность» секунд, потом улетает вверх. Цель умерла — улетает сразу.

var owner_mech: Node
var target: Node3D
var p := {}
var _state := 0                  # 0 летит к цели, 1 чинит, 2 улетает
var _left := 6.0
var _gone := 0.0
var _rotors: Array = []
var _beam: MeshInstance3D

const SPEED := 30.0


func _ready() -> void:
	_left = float(p.get("duration", 6.0))
	var body_m := Bolas.mat("drone", Color(0.35, 0.37, 0.33))
	var bm := BoxMesh.new()
	bm.size = Vector3(0.6, 0.22, 0.6)
	var body := MeshInstance3D.new()
	body.mesh = bm
	body.material_override = body_m
	add_child(body)
	var rm := CylinderMesh.new()
	rm.top_radius = 0.28
	rm.bottom_radius = 0.28
	rm.height = 0.03
	rm.radial_segments = 10
	for k in 4:
		var a := TAU * k / 4.0 + PI / 4.0
		var r := MeshInstance3D.new()
		r.mesh = rm
		r.material_override = Bolas.mat("rotor", Color(0.15, 0.15, 0.15))
		r.position = Vector3(cos(a) * 0.5, 0.12, sin(a) * 0.5)
		add_child(r)
		_rotors.append(r)
	var lm := SphereMesh.new()
	lm.radius = 0.08
	lm.height = 0.16
	var l := MeshInstance3D.new()
	l.mesh = lm
	l.material_override = Bolas.mat("drone_l", Color(0.4, 1.0, 0.5) * 2.0, true)
	l.position.y = -0.14
	add_child(l)
	_beam = MeshInstance3D.new()
	_beam.mesh = QuadMesh.new()
	_beam.material_override = Fx.beam_material(Color(0.5, 1.0, 0.6), 2.5)
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_beam.top_level = true
	_beam.visible = false
	add_child(_beam)
	reset_physics_interpolation()
	Sfx.play_at("launch", global_position, -8.0, 0.1)


func _alive(n) -> bool:
	return n != null and is_instance_valid(n) and not n.dead


func _physics_process(delta: float) -> void:
	for r in _rotors:
		r.rotate_y(delta * 40.0)
	if _state < 2 and not _alive(target):
		_state = 2
	visible = _alive(target) and target.get("seen") != false or _state == 2
	match _state:
		0, 1:
			var hover: Vector3 = target.global_position + Vector3.UP * (target.get_hit_height() + 1.6)
			if _state == 0:
				global_position = global_position.move_toward(hover, SPEED * delta)
				if global_position.distance_to(hover) < 0.3:
					_state = 1
			else:
				global_position = global_position.lerp(hover, minf(1.0, delta * 10.0))
				_left -= delta
				target.heal(float(p.get("heal_per_sec", 25.0)) * delta)
				target.dock_left = maxf(target.dock_left, 0.2)     # в статусах цели — «Чинится»
				if _left <= 0.0:
					_state = 2
		2:
			global_position += Vector3.UP * 14.0 * delta
			_gone += delta
			if _gone > 1.2:
				queue_free()


func _process(_delta: float) -> void:
	var on := _state == 1 and _alive(target) and visible
	if on != _beam.visible:
		_beam.visible = on
	if on:
		Fx.place_beam(_beam, global_position + Vector3.DOWN * 0.15,
			target.get_global_transform_interpolated().origin + Vector3.UP * target.get_hit_height() * 0.6, 0.12)
