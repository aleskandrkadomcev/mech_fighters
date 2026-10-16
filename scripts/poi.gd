extends Node3D
## Точка интереса. Встань на неё без врагов рядом и подержи: точка станет твоей командой.
## Пока точка твоя, вся команда получает бонус (какой — задаёт kind) и видит вокруг точки.
## Если на точке стоят обе команды, захват замирает.
## Виды: regen — Реактор (+восстановление энергии), damage — Арсенал (+урон),
## radar — Радар (захватывается быстро; пока у вышки стоит мех команды-владельца, вокруг неё большой круг обзора
##         сквозь стены — быстро раскрывается, без своих у вышки быстро сворачивается; см. vision.gd),
## dock — Ремонтный док (чинит и пополняет патроны своим мехам в круге).

var kind := "regen"
var title := "Реактор"
var owner_team := -1             # -1 ничья
var progress := 0.0              # -1..1: к команде 0 минус, к команде 1 плюс
var _ring_mat: StandardMaterial3D
var _core_mat: StandardMaterial3D
var _ring: MeshInstance3D
var _label: Label3D
var radar_r := 0.0               # радар: нынешний радиус круга обзора (vision.gd)
var radar_eye: Node3D            # радар: «глаз» круга обзора (свой узел, чтобы не путаться с обзором самой точки)
var _radar_ring: MeshInstance3D  # радар: граница круга на земле, видна только команде-владельцу
var _radar_ring_mat: StandardMaterial3D
var _dish: Node3D                # радар: вращающаяся антенна (только вид)


func _ready() -> void:
	add_to_group("pois")
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring_mat.albedo_color = Color(0.8, 0.8, 0.8, 0.5)
	_ring = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.92
	tm.outer_radius = 1.0
	tm.rings = 64
	_ring.mesh = tm
	_ring.material_override = _ring_mat
	_ring.position.y = 0.08
	_ring.scale = Vector3(Cfg.poi_radius, 0.2, Cfg.poi_radius)
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)

	# столб в центре: цвет команды-владельца
	_core_mat = StandardMaterial3D.new()
	_core_mat.albedo_color = Color(0.7, 0.7, 0.7)
	_core_mat.emission_enabled = true
	_core_mat.emission = Color(0.5, 0.5, 0.5)
	_core_mat.emission_energy_multiplier = 2.5
	var base := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 1.2
	bm.bottom_radius = 1.6
	bm.height = 0.8
	base.mesh = bm
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.1, 0.1, 0.11)
	base.material_override = dark
	base.position.y = 0.4
	add_child(base)
	# маяк: четыре стойки и светящееся ядро цвета команды-владельца
	var frame := StandardMaterial3D.new()
	frame.albedo_color = Color(0.2, 0.21, 0.23)
	frame.metallic = 0.5
	frame.roughness = 0.5
	for i in 4:
		var a := TAU * i / 4.0 + PI / 4.0
		var post := MeshInstance3D.new()
		var pb := BoxMesh.new()
		pb.size = Vector3(0.25, 3.4, 0.25)
		post.mesh = pb
		post.material_override = frame
		post.position = Vector3(cos(a) * 1.1, 2.1, sin(a) * 1.1)
		add_child(post)
	var cap := MeshInstance3D.new()
	var capm := CylinderMesh.new()
	capm.top_radius = 0.9
	capm.bottom_radius = 1.3
	capm.height = 0.35
	cap.mesh = capm
	cap.material_override = frame
	cap.position.y = 3.9
	add_child(cap)
	var core := MeshInstance3D.new()
	var cm := SphereMesh.new()
	cm.radius = 0.55
	cm.height = 1.6
	core.mesh = cm
	core.material_override = _core_mat
	core.position.y = 2.3
	add_child(core)
	if kind == "radar":
		# антенна радара на крыше маяка, крутится (_process)
		_dish = Node3D.new()
		_dish.position.y = 4.15
		add_child(_dish)
		var mast := MeshInstance3D.new()
		var mm := CylinderMesh.new()
		mm.top_radius = 0.12
		mm.bottom_radius = 0.16
		mm.height = 0.8
		mast.mesh = mm
		mast.material_override = frame
		mast.position.y = 0.4
		_dish.add_child(mast)
		var plate := MeshInstance3D.new()
		var pm := BoxMesh.new()
		pm.size = Vector3(3.2, 1.1, 0.14)
		plate.mesh = pm
		plate.material_override = frame
		plate.position = Vector3(0, 1.0, 0.25)
		plate.rotation.x = -0.35
		_dish.add_child(plate)
		radar_eye = Node3D.new()
		add_child(radar_eye)
		_radar_ring_mat = StandardMaterial3D.new()
		_radar_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_radar_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_radar_ring = MeshInstance3D.new()
		var rt := TorusMesh.new()
		rt.inner_radius = 0.985
		rt.outer_radius = 1.0
		rt.rings = 96
		_radar_ring.mesh = rt
		_radar_ring.material_override = _radar_ring_mat
		_radar_ring.position.y = 0.1
		_radar_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_radar_ring.visible = false
		add_child(_radar_ring)
	elif kind == "dock":
		# ремонтный док: две стрелы-манипулятора над площадкой
		for sgn in [-1.0, 1.0]:
			var arm := MeshInstance3D.new()
			var am := BoxMesh.new()
			am.size = Vector3(0.3, 0.3, 4.2)
			arm.mesh = am
			arm.material_override = frame
			arm.position = Vector3(sgn * 0.6, 3.6, 1.6)
			arm.rotation.x = 0.25
			add_child(arm)
			var tool := MeshInstance3D.new()
			var tm2 := CylinderMesh.new()
			tm2.top_radius = 0.18
			tm2.bottom_radius = 0.1
			tm2.height = 0.7
			tool.mesh = tm2
			tool.material_override = _core_mat
			tool.position = Vector3(sgn * 0.6, 2.9, 3.5)
			add_child(tool)

	_label = Label3D.new()
	_label.text = title
	_label.font_size = 64
	_label.pixel_size = 0.014
	_label.outline_size = 12
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.position = Vector3(0, 5.0, 0)
	_label.modulate = Color(1, 1, 1, 0.8)
	add_child(_label)


func bonus_text() -> String:
	match kind:
		"regen":
			return "+%d%% восстановления энергии" % int(round(Cfg.poi_regen_bonus * 100))
		"radar":
			return "обзор %d м, пока свои у вышки" % int(round(Cfg.poi_radar_range * Cfg.METERS_PER_UNIT))
		"dock":
			return "ремонт и патроны своим в круге"
	return "+%d%% урона" % int(round(Cfg.poi_damage_bonus * 100))


func _process(delta: float) -> void:
	if _dish != null:
		_dish.rotation.y += delta * (1.6 if owner_team >= 0 else 0.4)


func _physics_process(delta: float) -> void:
	_ring.scale = Vector3(Cfg.poi_radius, 0.2, Cfg.poi_radius)
	var inside := [0, 0]
	for m in get_tree().get_nodes_in_group("mechs"):
		if m.dead or m.team < 0 or m.team > 1:
			continue
		var d: Vector3 = m.global_position - global_position
		d.y = 0
		if d.length() <= Cfg.poi_radius:
			inside[m.team] += 1
	var step := delta / maxf(Cfg.poi_radar_capture if kind == "radar" else Cfg.poi_capture_time, 0.1)
	if inside[0] > 0 and inside[1] == 0:
		progress = maxf(progress - step, -1.0)
	elif inside[1] > 0 and inside[0] == 0:
		progress = minf(progress + step, 1.0)
	elif inside[0] == 0 and inside[1] == 0 and owner_team == -1:
		progress = move_toward(progress, 0.0, step * 0.5)
	if progress <= -1.0 and owner_team != 0:
		_set_owner(0)
	elif progress >= 1.0 and owner_team != 1:
		_set_owner(1)
	elif owner_team == 0 and progress > 0.0:
		_set_owner(-1)
	elif owner_team == 1 and progress < 0.0:
		_set_owner(-1)

	# кольцо: цвет того, кто захватывает, яркость = прогресс
	var col := Color(0.8, 0.8, 0.8)
	if progress < 0.0:
		col = Color(0.8, 0.8, 0.8).lerp(Cfg.player_color, -progress)
	elif progress > 0.0:
		col = Color(0.8, 0.8, 0.8).lerp(Cfg.enemy_color, progress)
	_ring_mat.albedo_color = Color(col.r, col.g, col.b, 0.35 + 0.5 * absf(progress))
	var own := Color(0.6, 0.6, 0.6) if owner_team == -1 else (Cfg.player_color if owner_team == 0 else Cfg.enemy_color)
	_core_mat.albedo_color = own
	_core_mat.emission = own

	if kind == "radar":
		_update_radar(delta, inside)
	if owner_team < 0:
		return
	if kind == "dock":
		for m in get_tree().get_nodes_in_group("mechs"):
			if m.dead or m.team != owner_team:
				continue
			var d: Vector3 = m.global_position - global_position
			d.y = 0
			if d.length() <= Cfg.poi_radius:
				m.heal(Cfg.poi_dock_heal * delta)
				m.add_ammo(Cfg.poi_dock_refill * delta)


# радар: круг обзора, пока у вышки стоит мех команды-владельца; быстро раскрывается и быстро сворачивается
func _update_radar(delta: float, inside: Array) -> void:
	var want: float = Cfg.poi_radar_range if owner_team >= 0 and inside[owner_team] > 0 else 0.0
	var secs: float = Cfg.poi_radar_grow if want > radar_r else Cfg.poi_radar_shrink
	radar_r = move_toward(radar_r, want, Cfg.poi_radar_range / maxf(secs, 0.05) * delta)
	# граница круга на земле — только своей команде (враг не знает, что вышка смотрит)
	var ring_on := owner_team == Fx.player_team and radar_r > 0.3
	if _radar_ring.visible != ring_on:
		_radar_ring.visible = ring_on
	if ring_on:
		var sc := Vector3(radar_r, 0.3, radar_r)
		if not _radar_ring.scale.is_equal_approx(sc):
			_radar_ring.scale = sc
		var c: Color = Cfg.player_color if owner_team == 0 else Cfg.enemy_color
		var cc := Color(c.r, c.g, c.b, 0.55)
		if _radar_ring_mat.albedo_color != cc:
			_radar_ring_mat.albedo_color = cc


func _set_owner(t: int) -> void:
	if t == owner_team:
		return
	owner_team = t
	radar_r = 0.0      # круг прежнего владельца гаснет сразу, новый раскрывается с нуля
	if t >= 0:
		Battle.poi_captured.emit(title, t)
		Fx.burst(global_position + Vector3.UP * 2.0, Cfg.player_color if t == 0 else Cfg.enemy_color, Cfg.poi_radius)
		Sfx.play_at("emp", global_position, -6.0, 0.0)
