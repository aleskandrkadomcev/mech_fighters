class_name FireWall
extends Node3D
## Огненная стена Поджигателя: канистра разлилась по земле полосой поперёк броска. Пока горит, жжёт врагов
## (мехов и крипов), которые в полосе или переходят её, и липнет к ногам — замедляет, как напалм.

var team := 0
var shooter: Node
var dir := Vector3.FORWARD      # куда бросали (стена — поперёк)
var length := 12.0
var width := 2.4
var life := 6.0
var dps := 20.0
var slow := 0.3
var _t := 0.0
var _tick := 0.0
var _strip: MeshInstance3D
var _mat: StandardMaterial3D

const TICK := 0.25               # раз в столько секунд жжёт
const STICK := 0.6               # столько секунд замедление держится после выхода из огня


func _ready() -> void:
	add_to_group("napalm")
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var fwd := Vector3(dir.x, 0, dir.z).normalized() if Vector3(dir.x, 0, dir.z).length() > 0.01 else Vector3.FORWARD
	look_at(global_position + fwd, Vector3.UP)      # локальная X — вдоль стены
	# тёмная горящая полоса
	_strip = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(length, 0.04, width)
	_strip.mesh = bm
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(0.12, 0.06, 0.03, 0.85)
	_mat.emission_enabled = true
	_mat.emission = Color(0.9, 0.3, 0.05)
	_mat.emission_energy_multiplier = 0.7
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.roughness = 0.3
	_strip.material_override = _mat
	_strip.position.y = 0.06
	_strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_strip)
	# языки огня вдоль полосы
	var n := maxi(int(ceil(length / 2.4)), 2)
	for k in n:
		var x := -length * 0.5 + length * (k + 0.5) / n
		Fx.smolder(self, Vector3(x, 0, 0), width * 0.55, life)
	Fx.light_flash(global_position + Vector3.UP * 1.5, Color(1.0, 0.5, 0.15), length * 1.2, 1.8, life, "firewall_%d" % get_instance_id(), true)
	Sfx.play_at("boom", global_position, -4.0, 0.1)


func _physics_process(delta: float) -> void:
	_t += delta
	if _t >= life:
		_mat.albedo_color.a = maxf(0.0, 0.85 - (_t - life) * 0.8)
		_mat.emission_energy_multiplier = maxf(0.0, 0.7 - (_t - life))
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
	var along := global_basis.x.normalized()
	var across := global_basis.z.normalized()
	for u in g.units():
		if u[2] == team:
			continue
		var d: Vector3 = u[1] - global_position
		var r := float(u[3]) * 0.5
		if absf(d.dot(along)) > length * 0.5 + r or absf(d.dot(across)) > width * 0.5 + r:
			continue
		var n = u[0]
		n.take_damage(dps * TICK, n.global_position + Vector3.UP * 1.0, Vector3.ZERO, "", src)
		if n.has_method("apply_slow"):
			n.apply_slow(slow, TICK + STICK)
