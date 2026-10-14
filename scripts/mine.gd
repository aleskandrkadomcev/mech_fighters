extends Node3D
## Мина. Ставится под себя. Своим видна всегда, врагам не видна,
## пока её не засечёт омни-сенсор или пока она не сработала.
## Враг подходит ближе радиуса срабатывания: мина пищит и мигает, через задержку взрывается.
## Взрыв бьёт врагов (с замедлением) и обломки в радиусе.

var team := 0
var owner_mech: Node
var p := {}                     # числа минного укладчика из parts.gd
var seen := true                # видна ли команде игрока
var triggered := false
var _arm := 0.0
var _boom_in := 0.0
var _light_mat: StandardMaterial3D
var _t := 0.0


func _ready() -> void:
	add_to_group("mines")
	_arm = p.get("arm_time", 1.0)
	var body := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.7
	cm.bottom_radius = 0.8
	cm.height = 0.22
	cm.radial_segments = 16
	body.mesh = cm
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0.2, 0.21, 0.2)
	bm.roughness = 0.6
	body.material_override = bm
	body.position.y = 0.11
	add_child(body)
	var light := MeshInstance3D.new()
	var lm := CylinderMesh.new()
	lm.top_radius = 0.22
	lm.bottom_radius = 0.22
	lm.height = 0.1
	light.mesh = lm
	_light_mat = StandardMaterial3D.new()
	_light_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_light_mat.albedo_color = Color(1.0, 0.2, 0.15)
	light.material_override = _light_mat
	light.position.y = 0.26
	add_child(light)


func _physics_process(delta: float) -> void:
	_t += delta
	visible = seen or triggered
	if triggered:
		_light_mat.albedo_color = Color(1, 0.15, 0.1) if fmod(_t, 0.12) < 0.06 else Color(1, 1, 0.6)
		_boom_in -= delta
		if _boom_in <= 0.0:
			_explode()
		return
	if _arm > 0.0:
		_arm -= delta
		_light_mat.albedo_color = Color(0.4, 0.4, 0.4)
		return
	# медленно мигает, пока ждёт
	_light_mat.albedo_color = Color(1, 0.2, 0.15) if fmod(_t, 1.2) < 0.15 else Color(0.35, 0.06, 0.05)
	var tr: float = p.get("trigger_radius", 3.5)
	for m in get_tree().get_nodes_in_group("mechs"):
		if m.dead or m.team == team:
			continue
		var d: Vector3 = m.global_position - global_position
		d.y = 0
		if d.length() <= tr + m.get_hit_radius() * 0.5:
			_trigger()
			return


func _trigger() -> void:
	triggered = true
	_boom_in = p.get("delay", 0.5)
	Sfx.play_at("beep", global_position, -2.0, 0.0)
	Fx.danger_zones.append({"pos": Vector3(global_position.x, 0, global_position.z), "radius": p.get("radius", 6.0),
		"team": team, "node": self, "born": Time.get_ticks_msec()})


func _explode() -> void:
	var radius: float = p.get("radius", 6.0)
	var dmg_c: float = p.get("damage", 60.0)
	var k_owner: float = owner_mech.damage_mult() if is_instance_valid(owner_mech) else 1.0
	Fx.explosion(global_position + Vector3.UP * 0.3, radius)
	Sfx.play_at("boom", global_position, -1.0, 0.1)
	var hit := Fx.blast(global_position, radius, dmg_c * k_owner, float(p.get("edge_damage", 0.5)), team, owner_mech if is_instance_valid(owner_mech) else null)
	for n in hit:
		if is_instance_valid(n) and n.has_method("apply_slow"):
			n.apply_slow(p.get("slow", 0.3), p.get("slow_time", 4.0))
	queue_free()
