class_name NanoCloud
extends Node3D
## Нанооблако Механика: канистра лопнула, над землёй висит облако ремонтных нанитов. Пока висит, чинит
## своих (мехов и крипов) в круге. Врагов не трогает.

var team := 0
var shooter: Node
var radius := 6.0
var life := 6.0
var heal_per_sec := 15.0
var _t := 0.0
var _tick := 0.0
var _cloud: MeshInstance3D
var _mat: StandardMaterial3D

const TICK := 0.25               # раз в столько секунд чинит


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	# полупрозрачный зеленоватый купол-туман
	_cloud = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 0.7
	sm.radial_segments = 24
	sm.rings = 8
	_cloud.mesh = sm
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.albedo_color = Color(0.45, 1.0, 0.6, 0.0)
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_cloud.material_override = _mat
	_cloud.position.y = 0.4
	_cloud.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_cloud)
	Fx.burst(global_position + Vector3.UP * 1.0, Color(0.45, 1.0, 0.6), radius * 0.6)
	Fx.light_flash(global_position + Vector3.UP * 1.5, Color(0.45, 1.0, 0.6), radius * 2.5, 1.0, life, "nanocloud_%d" % get_instance_id(), true)
	Sfx.play_at("beep", global_position, -6.0, 0.0)


func _process(_delta: float) -> void:
	# облако чуть дышит и тает к концу
	var k := clampf(minf(_t * 3.0, (life + 0.8 - _t) / 0.8), 0.0, 1.0)
	var a := (0.16 + 0.04 * sin(_t * 3.0)) * k
	if absf(_mat.albedo_color.a - a) > 0.005:
		_mat.albedo_color.a = a


func _physics_process(delta: float) -> void:
	_t += delta
	if _t >= life + 0.8:
		queue_free()
		return
	if _t >= life:
		return
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = TICK
	var g = get_tree().current_scene
	if g == null or not g.has_method("units"):
		return
	for u in g.units():
		if u[2] != team:
			continue
		var d: Vector3 = u[1] - global_position
		d.y = 0
		if d.length() > radius + float(u[3]) * 0.5:
			continue
		if u[0].has_method("heal"):
			u[0].heal(heal_per_sec * TICK)
