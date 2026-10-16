class_name NapalmFire
extends Node3D
## Горящее пятно напалма: снаряд напалм-мортирки разлился по земле. Пока горит, жжёт врагов
## (мехов и крипов) в круге и липнет к ногам — замедляет и ещё чуть-чуть после выхода из огня.

var team := 0
var shooter: Node
var radius := 4.5
var life := 5.0
var dps := 16.0
var slow := 0.35
var _t := 0.0
var _tick := 0.0
var _pool: MeshInstance3D
var _mat: StandardMaterial3D

const TICK := 0.25               # раз в столько секунд жжёт
const STICK := 0.6               # столько секунд замедление держится после выхода из огня


func _ready() -> void:
	add_to_group("napalm")
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	# тёмное липкое пятно с тлеющим краем
	_pool = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = 0.04
	cm.radial_segments = 24
	_pool.mesh = cm
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(0.12, 0.06, 0.03, 0.85)
	_mat.emission_enabled = true
	_mat.emission = Color(0.9, 0.3, 0.05)
	_mat.emission_energy_multiplier = 0.6
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.roughness = 0.3
	_pool.material_override = _mat
	_pool.position.y = 0.06
	_pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_pool)
	# огонь: в центре и по кругу
	Fx.smolder(self, Vector3.ZERO, radius * 0.45, life)
	for k in 5:
		var a := TAU * k / 5.0
		Fx.smolder(self, Vector3(cos(a), 0, sin(a)) * radius * 0.6, radius * 0.3, life)
	Fx.light_flash(global_position + Vector3.UP * 1.5, Color(1.0, 0.5, 0.15), radius * 3.0, 1.5, life, "napalm_%d" % get_instance_id(), true)
	Sfx.play_at("boom", global_position, -6.0, 0.1)


func _physics_process(delta: float) -> void:
	_t += delta
	if _t >= life:
		_mat.albedo_color.a = maxf(0.0, 0.85 - (_t - life) * 0.8)
		_mat.emission_energy_multiplier = maxf(0.0, 0.6 - (_t - life))
		if _t >= life + 1.2:
			queue_free()
		return
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = TICK
	var g = get_tree().current_scene
	if g == null or not g.has_method("units"):
		return
	var src: Node = shooter if is_instance_valid(shooter) else null
	for u in g.units():
		if u[2] == team:
			continue
		var d: Vector3 = u[1] - global_position
		d.y = 0
		if d.length() > radius + float(u[3]) * 0.5:
			continue
		var n = u[0]
		n.take_damage(dps * TICK, n.global_position + Vector3.UP * 1.0, Vector3.ZERO, "", src)
		if n.has_method("apply_slow"):
			n.apply_slow(slow, TICK + STICK)
