extends Node3D
## Мина. Ставится под себя. Своим видна всегда, врагам не видна,
## пока её не засечёт омни-сенсор или пока она не сработала.
## Враг (мех или крип) подходит ближе радиуса срабатывания: мина пищит и мигает, через задержку взрывается.
## Взрыв бьёт врагов (с замедлением) и обломки в радиусе.
## Свои и вражеские мины выглядят по-разному: своя — гладкая шайба с зелёным огоньком,
## вражеская — ржавая, с четырьмя штырями-взрывателями и красным огоньком. Огонёк есть и на антенне над травой.

## Капкан Ловчего (kind "trap") — та же мина по видимости, но без взрыва: стальные челюсти захлопываются
## на ноге того, кто наступил (мех обездвижен, крип оглушён), и чуть ранят.

var team := 0
var owner_mech: Node
var kind := "mine"              # "trap" — капкан
var p := {}                     # числа минного укладчика (или капкана) из parts.gd
var _jaws: Array[Node3D] = []   # челюсти капкана: раскрыты, при срабатывании захлопываются
var seen := true                # видна ли команде игрока
var triggered := false
var _arm := 0.0
var _boom_in := 0.0
var _light_mat: StandardMaterial3D
var _t := 0.0
var _on := Color(1, 0.2, 0.15)          # огонёк мигает этим цветом
var _off := Color(0.35, 0.06, 0.05)


func _ready() -> void:
	add_to_group("mines")
	_arm = p.get("arm_time", 1.0)
	var friend: bool = team == Fx.player_team
	if friend:
		_on = Color(0.3, 1.0, 0.4)
		_off = Color(0.05, 0.25, 0.08)
	if kind == "trap":
		_build_trap()
		return
	var body := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.7
	cm.bottom_radius = 0.8
	cm.height = 0.22
	cm.radial_segments = 16
	body.mesh = cm
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0.2, 0.22, 0.2) if friend else Color(0.27, 0.17, 0.12)
	bm.roughness = 0.6
	body.material_override = bm
	body.position.y = 0.11
	add_child(body)
	if not friend:
		# штыри-взрыватели: вражескую мину видно по силуэту, а не только по цвету
		var pm := CylinderMesh.new()
		pm.top_radius = 0.05
		pm.bottom_radius = 0.07
		pm.height = 0.32
		pm.radial_segments = 6
		for k in 4:
			var prong := MeshInstance3D.new()
			prong.mesh = pm
			prong.material_override = bm
			var a := TAU * k / 4.0 + PI / 4.0
			prong.position = Vector3(cos(a) * 0.45, 0.32, sin(a) * 0.45)
			add_child(prong)
	var light := MeshInstance3D.new()
	var lm := CylinderMesh.new()
	lm.top_radius = 0.22
	lm.bottom_radius = 0.22
	lm.height = 0.1
	light.mesh = lm
	_light_mat = StandardMaterial3D.new()
	_light_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_light_mat.albedo_color = _on
	light.material_override = _light_mat
	light.position.y = 0.26
	add_child(light)
	# антенна с огоньком над травой: иначе мину в густой траве не видно
	var mast := MeshInstance3D.new()
	var mm := CylinderMesh.new()
	mm.top_radius = 0.025
	mm.bottom_radius = 0.035
	mm.height = 0.7
	mm.radial_segments = 6
	mast.mesh = mm
	mast.material_override = bm
	mast.position = Vector3(0.3, 0.55, 0.0)
	add_child(mast)
	var bulb := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.09
	sm.height = 0.18
	sm.radial_segments = 8
	sm.rings = 4
	bulb.mesh = sm
	bulb.material_override = _light_mat
	bulb.position = Vector3(0.3, 0.92, 0.0)
	add_child(bulb)


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
	_light_mat.albedo_color = _on if fmod(_t, 1.2) < 0.15 else _off
	# срабатывает от вражеских мехов и крипов (общий список тика main.units; падающих с неба там нет)
	var tr: float = p.get("trigger_radius", 3.5)
	var g = get_tree().current_scene
	if g == null or not g.has_method("units"):
		return
	for u in g.units():
		if u[2] == team:
			continue
		var d: Vector3 = u[1] - global_position
		d.y = 0
		if d.length() <= tr + float(u[3]) * 0.5:
			_trigger(u[0])
			return


func _trigger(who: Node = null) -> void:
	if kind == "trap":
		_snap(who)
		return
	triggered = true
	_boom_in = p.get("delay", 0.5)
	Sfx.play_at("beep", global_position, -2.0, 0.0)
	Fx.danger_zones.append({"pos": Vector3(global_position.x, 0, global_position.z), "radius": p.get("radius", 6.0),
		"team": team, "node": self, "born": Time.get_ticks_msec()})


func _explode() -> void:
	if kind == "trap":
		queue_free()          # капкан захлопнулся и отпустил: убираем
		return
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


# капкан: стальное кольцо-основание и зубастые челюсти по кругу, раскрыты наружу; огонёк в середине
func _build_trap() -> void:
	var friend: bool = team == Fx.player_team
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.32, 0.33, 0.34) if friend else Color(0.36, 0.26, 0.2)
	steel.metallic = 0.7
	steel.roughness = 0.45
	var base := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.55
	bm.bottom_radius = 0.65
	bm.height = 0.1
	bm.radial_segments = 14
	base.mesh = bm
	base.material_override = steel
	base.position.y = 0.05
	add_child(base)
	var tm := BoxMesh.new()
	tm.size = Vector3(0.1, 0.32, 0.05)
	for side in [-1.0, 1.0]:
		var jaw := Node3D.new()
		jaw.position = Vector3(0, 0.08, 0.3 * side)
		jaw.rotation.x = 1.15 * side          # раскрыт: челюсть отогнута наружу
		add_child(jaw)
		_jaws.append(jaw)
		var bar := MeshInstance3D.new()
		var bbm := BoxMesh.new()
		bbm.size = Vector3(1.1, 0.06, 0.06)
		bar.mesh = bbm
		bar.material_override = steel
		bar.position.y = 0.3
		jaw.add_child(bar)
		for k in 6:
			var tooth := MeshInstance3D.new()
			tooth.mesh = tm
			tooth.material_override = steel
			tooth.position = Vector3(-0.45 + k * 0.18, 0.15, 0)
			jaw.add_child(tooth)
	var light := MeshInstance3D.new()
	var lm := CylinderMesh.new()
	lm.top_radius = 0.12
	lm.bottom_radius = 0.12
	lm.height = 0.06
	light.mesh = lm
	_light_mat = StandardMaterial3D.new()
	_light_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_light_mat.albedo_color = _on
	light.material_override = _light_mat
	light.position.y = 0.12
	add_child(light)


# капкан сработал: челюсти схлопываются на ноге, мех обездвижен (крип оглушён), немного урона
func _snap(who: Node) -> void:
	triggered = true
	_boom_in = 0.9
	for jaw in _jaws:
		var tw := create_tween()
		tw.tween_property(jaw, "rotation:x", 0.0, 0.08)
	Sfx.play_at("hit", global_position, 0.0, 0.05)
	Fx.spark(global_position + Vector3.UP * 0.3, Vector3.UP, true, false)
	if who == null or not is_instance_valid(who):
		return
	var t: float = p.get("duration", 2.5)
	if who.has_method("root"):
		who.root(t)
	elif who.has_method("stun"):
		who.stun(t * 0.5)
	var k: float = owner_mech.damage_mult() if is_instance_valid(owner_mech) else 1.0
	who.take_damage(float(p.get("damage", 15.0)) * k, who.global_position + Vector3.UP * 0.5, Vector3.ZERO, "",
		owner_mech if is_instance_valid(owner_mech) else null)
