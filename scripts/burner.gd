class_name BurnerBeam
extends Node3D
## Выжигатель Глушителя: синий луч от меха к вражескому меху, «Длительность» секунд жжёт его энергию
## (и не даёт ей расти). Рвётся, если цель ушла дальше «Дальности», за стену, погибла или стрелка оглушили.

var shooter: Node3D
var target: Node3D
var life := 4.0
var burn := 30.0                 # энергии в секунду
var rng := 26.0
var _t := 0.0
var _los_t := 0.0
var _beam: MeshInstance3D
var _spark_t := 0.0


func _ready() -> void:
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_beam = MeshInstance3D.new()
	_beam.mesh = Fx._unit_quad()
	_beam.material_override = Fx.beam_material(Color(0.3, 0.55, 1.0), 2.5, 1.8, 0.25)
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.top_level = true
	add_child(_beam)


func _from() -> Vector3:
	var h: float = shooter.get_hit_height() * 0.7 if shooter.has_method("get_hit_height") else 2.0
	return shooter.global_position + Vector3.UP * h


func _to() -> Vector3:
	var h: float = target.get_hit_height() * 0.5 if target.has_method("get_hit_height") else 1.5
	return target.global_position + Vector3.UP * h


func _alive() -> bool:
	return is_instance_valid(shooter) and is_instance_valid(target) and not shooter.dead and not target.dead \
		and not (shooter.has_method("is_stunned") and shooter.is_stunned())


func _physics_process(delta: float) -> void:
	_t += delta
	if _t >= life or not _alive():
		queue_free()
		return
	var d := target.global_position - shooter.global_position
	d.y = 0
	if d.length() > rng:
		queue_free()
		return
	# стена между ними рвёт луч (проверка 5 раз в секунду)
	_los_t -= delta
	if _los_t <= 0.0:
		_los_t = 0.2
		var q := PhysicsRayQueryParameters3D.create(_from(), _to(), 1)
		if not get_world_3d().direct_space_state.intersect_ray(q).is_empty():
			queue_free()
			return
	if target.has_method("drain_energy"):
		target.drain_energy(burn * delta)
	if target.has_method("block_regen"):
		target.block_regen(0.3)


func _process(delta: float) -> void:
	if not _alive():
		return
	var vis: bool = shooter.get("seen") != false or target.get("seen") != false
	_beam.visible = vis
	if not vis:
		return
	var a := _from()
	var b := _to()
	Fx.place_beam(_beam, a, b, 0.35)
	_spark_t -= delta
	if _spark_t <= 0.0:
		_spark_t = 0.15
		Fx.spark(b, (a - b).normalized(), true, false)
