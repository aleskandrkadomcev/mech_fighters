extends Node
## СЛУЖЕБНЫЙ ФАЙЛ. В обычной игре не работает и ни на что не влияет.
## Нужен Claude, чтобы прогонять игру без человека: сценарий движения, снимки кадров,
## проверка, что клавиатура и мышь реально управляют мехом.
## Включается только особыми параметрами запуска.

var main: Node3D
var debug_yaw := 0.0
var _shot_dir := ""
var _demo := false
var _inputtest := false
var _paneltest := false
var _bottest := false
var _hittest := false
var _flattest := false
var _abiltest := false
var _cloaktest := false
var _mobatest := false
var _showcase := false
var _pushtest := false
var _minetest := false
var _markertest := false
var _steptest := false
var _starttest := false
var _turrettest := false
var _verbose := false
var _gallery := false
var _wallshot := false
var _fightshot := false
var _zap := false                # вместе с fxshot: мех и крип оглушены (молнии)
var _coreshot := false           # снимок и проверка: ядра штаба бьют Теслой, барьер на штабе
var _fxshot := false             # снимок: пыль, гильзы, дым подбитого меха, метка
var _dropshot := false
var _resultshot := false
var _stuckcheck := false
var _boom := false               # взрыв рядом с игроком на 5-м кадре (проверка следа гари)
var _moba_secs := 60
var _perf := false               # с mobatest: каждые 20 с сколько узлов, объектов, ресурсов и время кадра
var _moba_tp := Vector3.ZERO
var _dump_path := ""
var _hangartest := false
var _bots := 0
var _frame := 0
var _shots_left: Array = []


func setup(main_node: Node3D, args: PackedStringArray) -> void:
	main = main_node
	for a in args:
		if a.begins_with("--shot-dir="):
			_shot_dir = a.trim_prefix("--shot-dir=")
		elif a == "--demo":
			_demo = true
		elif a == "--inputtest":
			_inputtest = true
		elif a == "--paneltest":
			_paneltest = true
		elif a.begins_with("--dumpparts="):
			_dump_path = a.trim_prefix("--dumpparts=")
		elif a == "--stuckcheck":
			_stuckcheck = true
			_mobatest = true
			_bots = 3
		elif a == "--resultshot":
			_resultshot = true
			_mobatest = false
			_bots = 2
		elif a == "--dropshot":
			_dropshot = true
		elif a == "--fightshot":
			_fightshot = true
		elif a == "--coreshot":
			_coreshot = true
		elif a == "--fxshot":
			_fxshot = true
		elif a == "--zapshot":
			_fxshot = true
			_zap = true
		elif a == "--wallshot":
			_wallshot = true
		elif a == "--gallery":
			_gallery = true
		elif a == "--verbose":
			_verbose = true
		elif a == "--boom":
			_boom = true
		elif a == "--turrettest":
			_turrettest = true
		elif a == "--starttest":
			_starttest = true
		elif a == "--steptest":
			_steptest = true
		elif a == "--markertest":
			_markertest = true
			_bots = 1
		elif a == "--minetest":
			_minetest = true
			_bots = 1
		elif a == "--pushtest":
			_pushtest = true
		elif a == "--showcase":
			_showcase = true
			_bots = 1
		elif a == "--mobatest":
			_mobatest = true
			_bots = 3
		elif a.begins_with("--tp="):
			var xy := a.trim_prefix("--tp=").split(",")
			_moba_tp = Vector3(float(xy[0]), 0.05, float(xy[1]))
		elif a.begins_with("--enemies="):
			_bots = int(a.trim_prefix("--enemies="))
		elif a.begins_with("--secs="):
			_moba_secs = int(a.trim_prefix("--secs="))
		elif a == "--perf":
			_perf = true
		elif a == "--cloaktest":
			_cloaktest = true
		elif a == "--abiltest":
			_abiltest = true
		elif a == "--flattest":
			_flattest = true
		elif a == "--hittest":
			_hittest = true
		elif a == "--hangartest":
			_hangartest = true
		elif a == "--bottest":
			_bottest = true
			_bots = 2
		elif a.begins_with("--bots="):
			_bots = int(a.trim_prefix("--bots="))
		elif a.begins_with("--cam-dist="):
			Cfg.cam_distance = float(a.trim_prefix("--cam-dist="))
		elif a.begins_with("--cam-pitch="):
			Cfg.cam_pitch = float(a.trim_prefix("--cam-pitch="))
		elif a.begins_with("--cam-yaw="):
			debug_yaw = deg_to_rad(float(a.trim_prefix("--cam-yaw=")))
		elif a.begins_with("--shots="):
			for s in a.trim_prefix("--shots=").split(","):
				_shots_left.append(int(s))
	Cfg.bot_enemies = _bots
	# в проверках мехи появляются сразу, без высадки с неба (кроме --drop)
	if not args.has("--drop"):
		Cfg.drop_time = 0.0
	if not _mobatest:
		Cfg.bot_allies = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS     # работает и когда игра на паузе (ангар)
	if _dump_path != "":
		_dump_parts(_dump_path)
		return
	if _bottest:
		main.mech.demo = {"move": Vector2.ZERO, "run": false, "fire": true, "dash": false, "aim": Vector3(0, 1.5, -20)}
	if _demo:
		main.mech.demo = {"move": Vector2.ZERO, "run": false, "fire": false, "dash": false, "aim": Vector3(0, 1.5, -20)}


func _process(_delta: float) -> void:
	_frame += 1
	if _demo:
		_run_demo()
	if _inputtest:
		_run_inputtest()
	if _paneltest:
		_run_paneltest()
	if _bottest:
		_run_bottest()
	if _hittest:
		_run_hittest()
	if _flattest:
		_run_flattest()
	if _abiltest:
		_run_abiltest()
	if _cloaktest:
		_run_cloaktest()
	if _mobatest:
		_run_mobatest()
	if _showcase:
		_run_showcase()
	if _pushtest:
		_run_pushtest()
	if _minetest:
		_run_minetest()
	if _markertest:
		_run_markertest()
	if _steptest:
		_run_steptest()
	if _starttest:
		_run_starttest()
	if _turrettest:
		_run_turrettest()
	if _gallery:
		_run_gallery()
	if _wallshot:
		_run_wallshot()
	if _fightshot:
		_run_fightshot()
	if _fxshot:
		_run_fxshot()
	if _coreshot:
		_run_coreshot()
	if _dropshot:
		_run_dropshot()
	if _resultshot:
		_run_resultshot()
	if _boom and _frame == 5:
		Fx.explosion(main.mech.global_position + Vector3(7, 1.8, 3), 4.5)
		Fx.explosion(main.mech.global_position + Vector3(-6, 1.8, -4), 3.0)
	if _hangartest:
		_run_hangartest()
	if _shot_dir != "" and _shots_left.has(_frame):
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png("%s/f%04d.png" % [_shot_dir, _frame])
		_shots_left.erase(_frame)
		if _shots_left.is_empty() and not _inputtest and not _paneltest and not _bottest and not _hittest and not _hangartest and not _flattest and not _abiltest and not _cloaktest and not _mobatest and not _showcase and not _pushtest and not _minetest and not _markertest and not _steptest and not _starttest and not _turrettest and not _gallery and not _wallshot and not _fightshot and not _fxshot and not _coreshot and not _dropshot and not _resultshot:
			get_tree().quit()


func _run_demo() -> void:
	var mech = main.mech
	var t := _frame / 60.0
	var d: Dictionary = mech.demo
	if t < 1.0:
		d["move"] = Vector2.ZERO
		d["fire"] = t > 0.3
		d["aim"] = Vector3(0, 1.5, -20)
		if _frame == 20:
			d["q"] = true
	elif t < 2.5:
		d["move"] = Vector2(1, 0)
		d["run"] = false
		d["fire"] = true
		d["aim"] = mech.global_position + Vector3(2, 0, -18)
	elif t < 4.0:
		d["move"] = Vector2(-0.7, -0.7)
		d["run"] = true
		d["fire"] = true
		d["aim"] = mech.global_position + Vector3(-14, 0, -8)
	elif t < 4.5:
		if _frame == 241:
			d["dash"] = true
		d["move"] = Vector2(0, 1)
		d["run"] = false
		d["fire"] = false
	else:
		d["move"] = Vector2.ZERO
		d["fire"] = t > 5.0
		d["aim"] = mech.global_position + Vector3(6, 0, -14)
		if _frame == 300:
			d["e"] = true


# --- проверка настоящего ввода: шлём игре нажатия, как будто их сделал человек ---

func _key(code: Key, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.keycode = code
	ev.pressed = pressed
	Input.parse_input_event(ev)


func _tap(code: Key) -> void:
	_key(code, true)
	_key(code, false)


func _mouse_button(index: MouseButton, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = index
	ev.pressed = pressed
	ev.position = get_viewport().get_mouse_position()
	ev.global_position = ev.position
	if pressed and index == MOUSE_BUTTON_LEFT:
		ev.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(ev)


func _aim_at(world: Vector3) -> void:
	get_viewport().warp_mouse(main.cam.unproject_position(world))


func _nearest_target() -> Node3D:
	var best: Node3D = null
	var best_d := 1e9
	for n in get_tree().get_nodes_in_group("damageable"):
		if n.is_in_group("mechs") or n.is_in_group("walls") or n.is_in_group("creeps") or n.is_in_group("structures") or n.is_in_group("wrecks"):
			continue      # нужны только мишени-манекены
		var d: float = n.global_position.distance_to(main.mech.global_position)
		if d < best_d:
			best_d = d
			best = n
	return best


func _report(label: String) -> void:
	var mech = main.mech
	var sp := Vector2(mech.velocity.x, mech.velocity.z).length()
	print("[TEST] %s | pos=(%.1f, %.1f) speed=%.1f spread=%.1f energy=%.0f run=%s locked=%s cdQ=%.1f cdE=%.1f dash_cd=%.2f cam=%.0f" % [
		label, mech.global_position.x, mech.global_position.z, sp, mech.get_spread_deg(),
		mech.energy, mech.running, mech.run_locked, mech.ability_cd[0], mech.ability_cd[1],
		mech.dash_cd, main.cam.distance])


func _run_inputtest() -> void:
	var mech = main.mech
	match _frame:
		10:
			_report("start")
			mech.global_position = Vector3(-40, 0.05, 30)
		28:
			_aim_at(Vector3(-40, 1.5, 24))     # камера к этому кадру уже доехала до меха
		30:
			_tap(KEY_Q)
		34:
			_report("Q pressed (rockets)")
			var rockets := 0
			for c in main.get_children():
				if c.get_script() == load("res://scripts/rocket.gd"):
					rockets += 1
			print("[TEST] rockets in flight: %d" % rockets)
		40:
			_tap(KEY_Q)
		42:
			_report("Q again (must be on cooldown)")
		150:
			var t := _nearest_target()
			mech.global_position = Vector3(0, 0.05, 8)
			print("[TEST] after salvo: target at (%.0f, %.0f) hp=%.0f" % [t.global_position.x, t.global_position.z, t.hp])
			_key(KEY_W, true)
			_key(KEY_SHIFT, true)
		270:
			_report("ran 2s with Shift")
		600:
			_report("ran 7.5s (energy must be out, run locked)")
			_key(KEY_SHIFT, false)
			_key(KEY_W, false)
		610:
			_tap(KEY_E)
		612:
			_report("E with no energy (must be denied)")
		900:
			_report("rested 5s")
			# подойти к ближайшей мишени и дать импульс
			var t2 := _nearest_target()
			mech.global_position = t2.global_position + Vector3(0, 0.05, 5)
		905:
			_tap(KEY_E)
		910:
			var t3 := _nearest_target()
			_report("E pressed next to target")
			print("[TEST] target hp=%.0f stun=%.1f" % [t3.hp, t3._stun])
		920:
			_tap(KEY_F2)
		925:
			var panel = null
			for c in main.get_children():
				if c.get_script() == load("res://scripts/tuning_panel.gd"):
					panel = c
			print("[TEST] F2 pressed, panel visible: %s, rows: %d" % [panel._panel.visible, panel._rows.size()])
		930:
			print("[TEST] done")
			get_tree().quit()


# --- проверка панели настроек: открыть, раскрыть группы, подвигать числа общих правил и деталей ---

func _panel() -> Node:
	for c in main.get_children():
		if c.get_script() == load("res://scripts/tuning_panel.gd"):
			return c
	return null


func _run_paneltest() -> void:
	var panel = _panel()
	match _frame:
		5:
			print("[TEST] at start: mech_assault walk=%.1f rockets count=%d, mech walk=%.2f" % [Parts.v("mech_assault", "walk_speed"), int(Parts.v("mod_rockets", "count")), main.mech.stats["walk_speed"]])
		10:
			panel.toggle()
			panel._show_tab("parts")
		15:
			for g in panel._groups:
				if g["name"] == Parts.pname("mech_assault") or g["name"] == Parts.pname("mod_rockets"):
					g["box"].visible = true
			panel._refresh_all()
		20:
			panel._rows["part:mech_assault:walk_speed"]["slider"].value = 8.3
			panel._rows["part:mod_rockets:count"]["slider"].value = 5
			panel._rows["cfg:cam_distance"]["slider"].value = 44
		25:
			print("[TEST] after sliders: mech_assault walk=%.1f changed=%s, rockets count=%s, mech walk=%.2f, cam=%.0f" % [
				Parts.v("mech_assault", "walk_speed"), Parts.is_changed("mech_assault", "walk_speed"), Parts.v("mod_rockets", "count"),
				main.mech.stats["walk_speed"], Cfg.cam_distance])
		80:
			print("[TEST] tuning file exists: %s" % FileAccess.file_exists(Cfg._tuning_path()))
			if FileAccess.file_exists(Cfg._tuning_path()):
				print("[TEST] file: %s" % FileAccess.get_file_as_string(Cfg._tuning_path()).replace("\n", " / "))
		90:
			if _shots_left.is_empty():
				panel._on_reset_all()
				panel._show_tab("cfg")
				panel._on_reset_all()
		100:
			if _shots_left.is_empty():
				print("[TEST] after reset: mech_assault walk=%.1f cam=%.0f rows=%d" % [Parts.v("mech_assault", "walk_speed"), Cfg.cam_distance, panel._rows.size()])
		160:
			if _shots_left.is_empty():
				print("[TEST] file after reset: '%s'" % FileAccess.get_file_as_string(Cfg._tuning_path()).strip_edges().replace("\n", " / "))
				get_tree().quit()


# --- проверка ангара: открыть, собрать тяжёлого меха с лазером и тяжёлым орудием, пострелять по мишени ---

func _run_hangartest() -> void:
	var mech = main.mech
	match _frame:
		10:
			main.hangar.open(mech.build)
		30:
			var h = main.hangar
			h._build = {"mech": "mech_fortress", "core": "core_battery",
				"weapons": ["laser", "heavy_cannon"],
				"modules": ["mod_rockets", "mod_emp", "mod_armor", "mod_stabilizer", "mod_dampers", "mod_battery"]}
			h._refresh_rows()
			h._refresh_info()
			var r: Dictionary = Parts.compute(h._build)
			print("[HANGAR] valid=%s problems=%s weight=%.1f/%.0f speed x%.2f energy %.0f (reserve %.0f)" % [r["ok"], r["problems"],
				r["stats"]["weight"], r["stats"]["capacity"], r["stats"]["speed_factor"], r["stats"]["energy_max"], r["stats"]["energy_reserved"]])
		50:
			main.hangar._on_apply()
		55:
			print("[HANGAR] applied: hp=%.0f walk=%.2f weapons=%s,%s abilities=%d hit_r=%.2f paused=%s" % [mech.hp, mech.walk_speed(),
				mech.weapons[0]["name"], mech.weapons[1]["name"], mech.abilities.size(), mech.get_hit_radius(), get_tree().paused])
			mech.global_position = Vector3(-40, 0.05, 32)
			mech.demo = {"move": Vector2.ZERO, "fire": false, "aim": Vector3(-40, 1.5, 24)}
		90:
			mech.demo["fire"] = true
		150:
			var t := _nearest_target()
			print("[HANGAR] fired 1s: target hp=%.0f energy=%.0f beaming=%s" % [t.hp, mech.energy, mech.is_beaming()])
		200:
			mech.demo["fire"] = false
			var bad := 0
			for i in 300:
				var rb := Parts.random_build()
				if not Parts.compute(rb)["ok"]:
					bad += 1
			print("[HANGAR] 300 random builds, invalid: %d" % bad)
			if _shots_left.is_empty():
				get_tree().quit()


# --- проверка ботов: игрок стоит и стреляет в ближайшего, смотрим, как идёт бой ---

func _run_bottest() -> void:
	var mech = main.mech
	var d: Dictionary = mech.demo
	var near: Node3D = null
	var best := 1e9
	for b in main.bots:
		if b.dead:
			continue
		var dist: float = b.global_position.distance_to(mech.global_position)
		if dist < best:
			best = dist
			near = b
	if near != null:
		d["aim"] = near.global_position + Vector3.UP * 1.5
	d["fire"] = near != null
	# на 20-й секунде игрок перестаёт стрелять и даёт себя убить, чтобы проверить смерть и возрождение
	if _frame > 1200:
		d["fire"] = false
	if _frame % 120 == 0:
		var line := "[BOT] t=%2ds player hp=%3.0f dead=%s kills=%d deaths=%d |" % [_frame / 60, mech.hp, mech.dead, main.kills, main.deaths]
		for b in main.bots:
			line += " bot(%.0f,%.0f) hp=%.0f %s dist=%.0f%s |" % [b.global_position.x, b.global_position.z, b.hp,
				"DEAD" if b.dead else b.brain._mode, b.global_position.distance_to(mech.global_position),
				" STUN" if b.is_stunned() else ""]
		print(line)
	if _frame >= 3000 and _shots_left.is_empty():
		print("[BOT] done")
		get_tree().quit()


# --- проверка хитбокса: лучи на высоте стволов мимо и по меху, как это делает снаряд ---

func _probe(x: float, mask: int, areas: bool) -> String:
	var mech = main.mech
	var base: Vector3 = mech.global_position
	var from := Vector3(base.x + x, 3.0, base.z + 10.0)
	var to := Vector3(base.x + x, 3.0, base.z - 6.0)
	var q := PhysicsRayQueryParameters3D.create(from, to, mask)
	q.collide_with_areas = areas
	var hit := main.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return "мимо"
	var col = hit["collider"]
	return "ПОПАЛ (%s, урон проходит: %s)" % [col.get_class(), col.has_method("take_damage")]


func _run_hittest() -> void:
	if _frame == 20:
		# убираем игрока подальше от стен, чтобы лучи ни во что лишнее не упёрлись
		main.mech.global_position = Vector3(0, 0.05, 30)
	if _frame == 30:
		for x in [0.0, 1.0, 1.5, 1.85, 2.0, 2.5]:
			print("[HIT] сбоку от центра на %.2f м: снаряд -> %s | старая капсула -> %s" % [x, _probe(x, 1 | 4, true), _probe(x, 2, false)])
		var before: float = main.mech.hp
		var P = load("res://scripts/projectile.gd")
		var p = P.new()
		var enemy := Node3D.new()      # снаряд "от врага": команда 1
		p.setup(main.mech.global_position + Vector3(1.6, 3.0, 12.0), Vector3(0, 0, -70), 10.0, 40.0, null)
		p.team = 1
		main.add_child(p)
		set_meta("hp_before", before)
		enemy.free()
	if _frame == 60:
		print("[HIT] снаряд в 1.6 м от центра: здоровье %.0f -> %.0f" % [get_meta("hp_before"), main.mech.hp])
		Cfg.show_hitboxes = true
	if _frame == 90 and _shots_left.is_empty():
		print("[HIT] done")
		get_tree().quit()


# плоская игра: самый высокий мех с тяжёлыми пушками должен попадать в мишень,
# а энергия восстанавливаться даже во время бега
func _run_flattest() -> void:
	var m = main.mech
	if _frame == 10:
		m.set_build({"mech": "mech_fortress", "core": "core_battery",
			"weapons": ["heavy_cannon", "heavy_cannon"], "modules": []})
		m.respawn(Vector3(-40, 0.05, 40))
		m.demo = {"move": Vector2.ZERO, "run": false, "fire": false, "dash": false, "aim": Vector3(-40, 1.5, 24)}
	if _frame == 90:
		print("[FLAT] стволы на высоте %.2f / %.2f м, хитбокс %.1f м" % [m.visual.get_muzzle(0).y, m.visual.get_muzzle(1).y, m.get_hit_height()])
		var d = _nearest_dummy(Vector3(-40, 0, 24))
		set_meta("dummy", d)
		set_meta("hp0", d.hp)
		m.demo["fire"] = true
	if _frame == 240:
		m.demo["fire"] = false
		var d = get_meta("dummy")
		print("[FLAT] мишень: здоровье %.0f -> %.0f (попадания есть: %s)" % [get_meta("hp0"), d.hp, str(d.hp < get_meta("hp0") or d._dead)])
		# энергия: бег на месте 
		Cfg.run_energy_cost = 10.0
		Parts.set_value("core_battery", "energy_regen", 4.0)
		m.set_build(m.build)
		m.energy = 50.0
		set_meta("e0", 50.0)
		m.demo["move"] = Vector2(1, 0)
		m.demo["run"] = true
	if _frame == 300:
		print("[FLAT] энергия за 1 с бега (трата 10, восстановление 4): %.1f -> %.1f, бежал: %s" % [get_meta("e0"), m.energy, str(m.running)])
		m.demo["move"] = Vector2.ZERO
		m.demo["run"] = false
		m.energy = 50.0
		m.block_regen(1.0)
		m.shield_left = 0.0
	if _frame == 330:
		print("[FLAT] под запретом восстановления 0.5 с: %.1f (должно остаться 50)" % m.energy)
	if _frame == 400:
		print("[FLAT] после запрета: %.1f (должно расти)" % m.energy)
		print("[FLAT] " + Parts.describe("mod_ap_rounds") + " | " + Parts.describe("mod_rockets") + " | " + Parts.describe("mod_emp"))
		print("[FLAT] " + Parts.describe("mech_fortress") + " | " + Parts.describe("autocannon") + " | " + Parts.describe("laser"))
		print("[FLAT] " + Parts.describe("mod_dampers") + " | " + Parts.describe("mod_dash") + " | " + Parts.describe("core_combat"))
		print("[FLAT] done")
		get_tree().quit()


func _nearest_dummy(p: Vector3) -> Node:
	var best: Node = null
	for n in main.get_children():
		if n.get_script() == load("res://scripts/target_dummy.gd"):
			if best == null or n.global_position.distance_to(p) < best.global_position.distance_to(p):
				best = n
	return best


# абилки: авиаудар, щит, ремонт, невидимость, блинк (порядок модулей = Q E F C V G)
func _run_abiltest() -> void:
	var m = main.mech
	var d = _nearest_dummy(Vector3(-40, 0, 24))
	match _frame:
		10:
			m.set_build({"mech": "mech_fortress", "core": "core_battery",
				"weapons": ["autocannon", "autocannon"],
				"modules": ["mod_airstrike", "mod_shield", "mod_repair", "mod_cloak", "mod_blink", "mod_emp"]})
			m.respawn(Vector3(-40, 0.05, 40))
			m.shield_left = 0.0
			m.demo = {"move": Vector2.ZERO, "run": false, "fire": false, "dash": false, "aim": Vector3(-40, 1.5, 24)}
			print("[ABIL] build ok=%s abilities=%s" % [Parts.compute(m.build)["ok"], m.abilities.map(func(a): return a["type"])])
		30:
			set_meta("d_hp", d.hp)
			m.press_ability(0)
			print("[ABIL] airstrike cast, cd=%.1f energy=%.0f" % [m.ability_cd[0], m.energy])
		195:
			print("[ABIL] airstrike 2.75 s later: dummy hp %.0f (should be untouched)" % d.hp)
		230:
			print("[ABIL] airstrike after 3.3 s: dummy hp %.0f -> %.0f" % [get_meta("d_hp"), d.hp])
		240:
			m.energy = m.energy_max()
			m.press_ability(1)
		245:
			var e0: float = m.energy
			var h0: float = m.hp
			m.take_damage(50.0, m.global_position, Vector3.FORWARD)
			print("[ABIL] shield on=%s: 50 dmg -> hp %.0f->%.0f, energy %.1f->%.1f" % [m.barrier_on, h0, m.hp, e0, m.energy])
		280:
			m.energy = 10.0
			var h1: float = m.hp
			m.take_damage(50.0, m.global_position, Vector3.FORWARD)
			print("[ABIL] shield with 10 energy: hp %.1f->%.1f (expect -43.3), on=%s, cd=%.1f" % [h1, m.hp, m.barrier_on, m.ability_cd[1]])
		300:
			m.energy = m.energy_max()
			m.hp = 200.0
			m.press_ability(2)
		545:
			print("[ABIL] repair 4 s: hp 200 -> %.0f (expect 280), active=%.1f" % [m.hp, m.ability_active(2)])
		560:
			m.press_ability(3)
		590:
			print("[ABIL] cloak=%s left=%.1f fade=%.2f" % [m.is_cloaked(), m.cloak_left, m._fade])
		600:
			m.demo["fire"] = true
		606:
			m.demo["fire"] = false
			print("[ABIL] after firing: cloak=%s" % m.is_cloaked())
		620:
			m.demo["aim"] = Vector3(-20, 1.5, 40)
			set_meta("p0", m.global_position)
			m.press_ability(4)
		650:
			print("[ABIL] blink 0.5 s: moved %.2f m, left=%.2f" % [m.global_position.distance_to(get_meta("p0")), m.blink_left])
		690:
			print("[ABIL] blink done: pos x=%.1f z=%.1f (expect x=-26)" % [m.global_position.x, m.global_position.z])
			m.respawn(Vector3(-22, 0.05, 19))
			m.shield_left = 0.0
			m.ability_cd[4] = 0.0
			m.demo["aim"] = Vector3(-22, 1.5, 10)
		700:
			m.press_ability(4)
		770:
			print("[ABIL] blink into cover: pos z=%.2f (cover edge 12, expect >= 13.4)" % m.global_position.z)
			m.ability_cd[4] = 0.0
			m.press_ability(4)
		775:
			m.stun(1.0)
			print("[ABIL] stun during blink: blink_left=%.2f" % m.blink_left)
		790:
			# враг: бот с невидимостью
			Cfg.bot_enemies = 1
		800:
			var b = main.bots[0]
			b.set_build({"mech": "mech_assault", "core": "core_combat",
				"weapons": ["autocannon", "autocannon"], "modules": ["mod_cloak", "mod_shield", "mod_repair", "mod_rockets"]})
			b.respawn(Vector3(-30, 0.05, 30))
			b.shield_left = 0.0
			m.respawn(Vector3(-40, 0.05, 36))
			m.shield_left = 0.0
		820:
			var b2 = main.bots[0]
			print("[ABIL] bot sees player: %s" % str(b2.brain._find_target() != null))
			m.ability_cd[3] = 0.0
			m.press_ability(3)
			b2.press_ability(0)
		830:
			var b3 = main.bots[0]
			print("[ABIL] player cloaked -> bot target: %s; bot cloaked=%s" % [str(b3.brain._find_target()), b3.is_cloaked()])
		850:
			main.bots[0].press_ability(1)
		860:
			print("[ABIL] bot shield on=%s" % main.bots[0].barrier_on)
		900:
			print("[ABIL] done")
			get_tree().quit()


# вражеский бот в невидимости: как он выглядит для игрока
func _run_cloaktest() -> void:
	var m = main.mech
	match _frame:
		5:
			Cfg.bot_enemies = 1
		12:
			var b = main.bots[0]
			b.set_build({"mech": "mech_assault", "core": "core_combat",
				"weapons": ["autocannon", "autocannon"], "modules": ["mod_cloak", "mod_shield", "mod_repair", "mod_rockets"]})
			b.respawn(Vector3(-30, 0.05, 30))
			b.shield_left = 0.0
			m.respawn(Vector3(-40, 0.05, 36))
			m.shield_left = 0.0
			m.demo = {"move": Vector2.ZERO, "run": false, "fire": false, "dash": false, "aim": Vector3(-30, 1.5, 30)}
		20:
			main.bots[0].press_ability(0)
		60:
			var b2 = main.bots[0]
			print("[CLOAK] bot cloaked=%s fade=%.2f bar=%s" % [b2.is_cloaked(), b2._fade, b2._bar.visible])
			get_tree().quit()


# выгрузить все числа деталей (с учётом правок) и общие правила в файл, для разбора баланса
func _dump_parts(path: String) -> void:
	var data := {}
	for id in Parts.DATA:
		var e := {}
		for f in Parts.DATA[id]:
			var val = Parts.DATA[id][f]
			e[f] = Parts.v(id, f) if (val is float or val is int) else val
		data[id] = e
	var cfg := {}
	for k in ["load_free", "load_min_speed", "load_accel", "load_dash", "load_turn", "min_energy_pool", "run_energy_cost", "run_min_energy", "dash_energy_cost"]:
		cfg[k] = Cfg.get(k)
	var samples := []
	for b in [Parts.DEFAULT_BUILD, Parts.player_build, {"mech": "mech_fortress", "core": "core_reactor",
			"weapons": ["laser", "heavy_cannon"], "modules": ["mod_shield", "mod_servos", "mod_ap_rounds"]}]:
		samples.append({"build": b, "result": Parts.compute(b)})
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"parts": data, "cfg": cfg, "samples": samples}, "  "))
	f.close()
	print("[DUMP] " + path)
	get_tree().quit()


# моба: игрок стоит на базе (или идёт за ботами), боты воюют. Раз в 5 секунд печатаем состояние.
func _run_mobatest() -> void:
	var m = main.mech
	if _frame == 5:
		m.demo = {"move": Vector2.ZERO, "run": false, "fire": false, "dash": false, "aim": m.global_position + Vector3(10, 1.5, 0)}
		if _moba_tp != Vector3.ZERO:
			m.global_position = _moba_tp
			m.demo["aim"] = _moba_tp + Vector3(10, 1.5, 0)
	if _frame == 30:
		var n := 0
		var stack: Array = [main]
		while not stack.is_empty():
			var x = stack.pop_back()
			if x is MeshInstance3D:
				n += 1
			stack.append_array(x.get_children())
		var grass := 0
		for c in main.art.get_children():
			if c is MultiMeshInstance3D:
				grass += c.multimesh.instance_count
		print("[MOBA] meshes=%d multimesh instances=%d" % [n, grass])
	if _frame == 40 and _shot_dir != "":
		await RenderingServer.frame_post_draw
		main.vision._viewport.get_texture().get_image().save_png(_shot_dir + "/fogmask.png")
		print("[MOBA] fans=%d" % main.vision._fans.size())
	if _frame % 300 == 0:
		var line := "[MOBA] t=%3ds kills=%d deaths=%d turrets us=%d them=%d winner=%d |" % [_frame / 60, main.kills, main.deaths,
			main.structures_left(0), main.structures_left(1), main.winner]
		for b in main.bots:
			line += " %s%s(%d,%d) hp=%d am=%.0f%% %s |" % ["A" if b.team == 0 else "E", b.brain.lane, int(b.global_position.x), int(b.global_position.z),
				int(b.hp), b.ammo_ratio() * 100, "dead" if b.dead else ("ret" if b.brain._retreat else b.brain.dbg)]
			if _verbose:
				line += " [%s wp=%s path=%d land=%.1f tp=%.1f mv=%s] |" % [Parts.pname(b.build["mech"]), main.lane_waypoint(b.team, b.brain.lane, b.global_position).round(), b.brain._path.size(), b.landing_left, b.tp_left, b._move]
				if b.brain.dbg.contains("STUCK"):
					var cols := []
					for i in b.get_slide_collision_count():
						var c = b.get_slide_collision(i).get_collider()
						cols.append((c.name + ":" + c.get_class() + str(c.global_position.round()) + " L" + str(c.collision_layer)) if c != null else "null")
					line += " cols=%s vel=%s y=%.2f stun=%.1f slow=%.1f walk=%.1f floor=%s coldis=%s dash=%.2f" % [str(cols), b.velocity.round(), b.global_position.y, b.stun_left, b.slow_left, b.walk_speed(), b.is_on_floor(), b._col.disabled, b.dash_left]
		line += " creeps=%d time=%s" % [get_tree().get_nodes_in_group("creeps").size(), Battle.time_text()]
		line += " wrecks=%d pickups=%d mines=%d" % [get_tree().get_nodes_in_group("wrecks").size(), get_tree().get_nodes_in_group("pickups").size(), get_tree().get_nodes_in_group("mines").size()]
		for p in get_tree().get_nodes_in_group("pois"):
			line += " %s=%d" % [p.title, p.owner_team]
		print(line)
	if _stuckcheck and _frame == 200 and not main.bots.is_empty():
		var b0 = main.bots[0]
		b0.global_position = Vector3(-102, 0.05, 0)
		b0.brain.lane = "top"
	if _stuckcheck and _frame > 200 and _frame < 560 and _frame % 30 == 0 and not main.bots.is_empty():
		var b1 = main.bots[0]
		if _frame == 204:
			var q := PhysicsShapeQueryParameters3D.new()
			var cap := CapsuleShape3D.new()
			cap.radius = 1.3
			cap.height = 3.6
			q.shape = cap
			q.transform = Transform3D(Basis(), b1.global_position + Vector3.UP * 1.9)
			q.collision_mask = 0xFFFF
			q.collide_with_areas = false
			q.exclude = [b1.get_rid()]
			for h in b1.get_world_3d().direct_space_state.intersect_shape(q, 16):
				var cc = h["collider"]
				print("    overlap: %s %s L%d at %s parent=%s" % [cc.name, cc.get_class(), cc.collision_layer, cc.global_position.round(), cc.get_parent().name])
		print("  dbg f=%d pos=%s vel=%s mv=%s path=%s dbg=%s" % [_frame, b1.global_position.snapped(Vector3.ONE * 0.1), b1.velocity.snapped(Vector3.ONE * 0.1), b1._move, b1.brain._path.slice(0, 4), b1.brain.dbg])
	if _perf and _frame % 600 == 0:
		_print_perf()
	if _frame >= _moba_secs * 60:
		print("[MOBA] done")
		get_tree().quit()


# витрина новых механик со снимками: обломок, припасы, ящик, мина, туман, невидимка, победа
func _run_showcase() -> void:
	var m = main.mech
	match _frame:
		5:
			m.set_build({"mech": "mech_assault", "core": "core_combat",
				"weapons": ["autocannon", "heavy_cannon"], "modules": ["mod_mines", "mod_cloak", "mod_rockets", "mod_armor"]})
			m.global_position = Vector3(-14, 0.05, -40)
			m.shield_left = 0.0
			m.demo = {"move": Vector2.ZERO, "run": false, "fire": false, "dash": false, "aim": Vector3(10, 1.5, -40)}
		12:
			var b = main.bots[0]
			b.brain = null
			b.global_position = Vector3(2, 0.05, -40)
			b.shield_left = 0.0
		28:
			main.bots[0].cloak_left = 30.0     # враг уходит в невидимость: его обломок всё равно должен быть виден
		40:
			var b2 = main.bots[0]
			print("[SHOW] enemy seen=%s" % b2.seen)
			b2.velocity = Vector3(14, 0, 0)
			b2.take_damage(99999, b2.global_position, Vector3.RIGHT)
		75:
			var w = get_tree().get_nodes_in_group("wrecks")
			print("[SHOW] wrecks=%d at %s (died at 2, slid by inertia) model visible=%s" % [w.size(), str(w[0].global_position) if w.size() > 0 else "-", str(w[0]._visual.is_visible_in_tree()) if w.size() > 0 else "-"])
		80:
			var ww = get_tree().get_nodes_in_group("wrecks")[0]
			m.demo["aim"] = ww.global_position + Vector3.UP * 1.5
			m.demo["fire"] = true
		140:
			m.demo["fire"] = false
			print("[SHOW] wrecks after shooting=%d pickups=%d" % [get_tree().get_nodes_in_group("wrecks").size(), get_tree().get_nodes_in_group("pickups").size()])
			m.press_ability(0)   # мина под себя
			Cfg.crate_warning = 1.0
			main._crate_t = 0.0
		150:
			print("[SHOW] mines=%d crate spot=%s" % [get_tree().get_nodes_in_group("mines").size(), str(main.crate_warning_pos())])
			m.demo["move"] = Vector2(-1, 0)
		175:
			m.demo["move"] = Vector2.ZERO
		190:
			# толкаем ящик: подходим к нему
			var cr = get_tree().get_nodes_in_group("wrecks").filter(func(x): return x.is_crate)
			if cr.size() > 0:
				set_meta("crate_x", cr[0].global_position.x)
		230:
			var crates := get_tree().get_nodes_in_group("wrecks").filter(func(x): return x.is_crate)
			print("[SHOW] crates=%d" % crates.size())
			# враг далеко за туманом
			var b3 = main.bots[0]
			b3.respawn(Vector3(40, 0.05, -40))
			b3.brain = null
			b3.shield_left = 0.0
		260:
			print("[SHOW] far enemy seen=%s (should be false)" % main.bots[0].seen)
			var b4 = main.bots[0]
			b4.global_position = Vector3(-4, 0.05, -40)
			b4.press_ability(b4.ability_index("cloak")) if b4.ability_index("cloak") >= 0 else null
		262:
			var b5 = main.bots[0]
			if b5.ability_index("cloak") < 0:
				b5.set_build({"mech": "mech_assault", "core": "core_combat",
					"weapons": ["autocannon", "autocannon"], "modules": ["mod_cloak"]})
				b5.press_ability(0)
		290:
			var b6 = main.bots[0]
			print("[SHOW] cloaked enemy at 10 m: cloaked=%s seen=%s (omni 14 m -> true)" % [b6.is_cloaked(), b6.seen])
			b6.global_position = Vector3(16, 0.05, -40)
		310:
			var b7 = main.bots[0]
			print("[SHOW] cloaked enemy at 30 m: seen=%s (should be false)" % b7.seen)
			for s in get_tree().get_nodes_in_group("structures"):
				if s.team == 1 and s.tier == 3:
					s.take_damage(1e9, s.global_position, Vector3.ZERO)
			for s in get_tree().get_nodes_in_group("structures"):
				if s.team == 1 and s.id == "core":
					s.take_damage(1e9, s.global_position, Vector3.ZERO)
			for s in get_tree().get_nodes_in_group("structures"):
				if s.team == 1 and s.id == "hq":
					s.take_damage(1e9, s.global_position, Vector3.ZERO)
		330:
			print("[SHOW] winner=%d" % main.winner)
		400:
			print("[SHOW] done")
			get_tree().quit()


# толкание обломка: лёгкий и тяжёлый мех упираются в один и тот же обломок 2 секунды
func _run_pushtest() -> void:
	var m = main.mech
	var builds := [
		{"mech": "mech_hound", "core": "core_reactor", "weapons": ["autocannon", "autocannon"], "modules": []},
		{"mech": "mech_fortress", "core": "core_battery", "weapons": ["heavy_cannon", "heavy_cannon"], "modules": ["mod_armor", "mod_armor"]},
	]
	var phase := _frame / 200
	var f := _frame % 200
	if phase >= builds.size():
		print("[PUSH] done")
		get_tree().quit()
		return
	if f == 1:
		for w in get_tree().get_nodes_in_group("wrecks"):
			w.queue_free()
		m.set_build(builds[phase])
		m.respawn(Vector3(-30, 0.05, -40))
		m.shield_left = 0.0
		m.demo = {"move": Vector2.ZERO, "run": false, "fire": false, "dash": false, "aim": Vector3(0, 1.5, -40)}
		var W = load("res://scripts/wreck.gd")
		var w2 = W.new()
		w2.setup_wreck(null, Vector3.ZERO, 60.0, 1.9)
		main.add_child(w2)
		w2.global_position = Vector3(-24, 0, -40)
		set_meta("w", w2)
	if f == 10:
		m.demo["move"] = Vector2(1, 0)
		set_meta("x0", get_meta("w").global_position.x)
	if f > 10 and f < 130 and f % 10 == 0:
		var cols := []
		for i in m.get_slide_collision_count():
			var c = m.get_slide_collision(i).get_collider()
			cols.append((c.get_class() + str(c.global_position.round()) + str(c.collision_layer)) if c != null else "null")
		print("  f=%d mech x=%.2f wreck x=%.2f vel=%.2f cols=%s" % [f, m.global_position.x, get_meta("w").global_position.x, m.velocity.length(), str(cols)])
	if f == 130:
		var w3 = get_meta("w")
		print("[PUSH] %s (%.0f т) толкает обломок 60 т: за 2 с сдвинул на %.1f м, мех шёл %.1f м/с" % [builds[phase]["mech"], m.stats["weight"],
			w3.global_position.x - get_meta("x0"), m.walk_speed()])
		m.demo["move"] = Vector2.ZERO


# мина: ставим, враг идёт на неё, проверяем урон, замедление, видимость
func _run_minetest() -> void:
	var m = main.mech
	match _frame:
		5:
			m.set_build({"mech": "mech_assault", "core": "core_combat",
				"weapons": ["autocannon", "autocannon"], "modules": ["mod_mines"]})
			m.global_position = Vector3(-20, 0.05, -40)
			m.shield_left = 0.0
			m.demo = {"move": Vector2.ZERO, "run": false, "fire": false, "dash": false, "aim": Vector3(0, 1.5, -40)}
		10:
			m.press_ability(0)
		20:
			m.global_position = Vector3(-36, 0.05, -40)
			var b = main.bots[0]
			b.brain = null
			b.global_position = Vector3(-6, 0.05, -40)
			b.shield_left = 0.0
			b.demo = {"move": Vector2(-1, 0), "run": false, "fire": false, "dash": false, "aim": Vector3(-30, 1.5, -40)}
			set_meta("hp0", b.hp)
			var mn = get_tree().get_nodes_in_group("mines")[0]
			print("[MINE] charges left=%d, mine visible to player=%s" % [int(m.ability_charges[0]), mn.seen])
		40:
			var mn2 = get_tree().get_nodes_in_group("mines")
			print("[MINE] enemy team sees mine: %s" % (main.is_visible_to(1, mn2[0]) if mn2.size() > 0 else "gone"))
		200:
			var b2 = main.bots[0]
			print("[MINE] bot at x=%.1f" % b2.global_position.x)
			print("[MINE] enemy hp %.0f -> %.0f, slowed %.1f s, speed x%.2f, mines left on map %d" % [get_meta("hp0"), b2.hp, b2.slow_left,
				b2.walk_speed() / maxf(b2.stats["walk_speed"], 0.01) / Cfg.bot_speed, get_tree().get_nodes_in_group("mines").size()])
			get_tree().quit()


# метки залпа, авиаудара и блинка: свои видны, вражеские нет
func _run_markertest() -> void:
	var m = main.mech
	var mods := ["mod_rockets", "mod_airstrike", "mod_blink"]
	match _frame:
		5:
			m.set_build({"mech": "mech_fortress", "core": "core_battery",
				"weapons": ["autocannon", "autocannon"], "modules": mods})
			m.global_position = Vector3(-20, 0.05, -40)
			m.shield_left = 0.0
			m.demo = {"move": Vector2.ZERO, "run": false, "fire": false, "dash": false, "aim": Vector3(0, 1.5, -40)}
			var b = main.bots[0]
			b.brain = null
			b.set_build({"mech": "mech_fortress", "core": "core_battery",
				"weapons": ["autocannon", "autocannon"], "modules": mods})
			b.global_position = Vector3(0, 0.05, -40)
			b.shield_left = 0.0
			b.demo = {"move": Vector2.ZERO, "run": false, "fire": false, "dash": false, "aim": Vector3(-20, 1.5, -40)}
		10:
			for i in 3:
				m.press_ability(i)
				main.bots[0].press_ability(i)
		14:
			var mine_vis := []
			var their_vis := []
			for z in Fx.danger_zones:
				if not is_instance_valid(z["node"]):
					continue
				if z["team"] == 0:
					mine_vis.append(z["node"].visible)
				else:
					their_vis.append(z["node"].visible)
			var blink_m = m._blink_marker
			var blink_e = main.bots[0]._blink_marker
			print("[MARK] мои метки залп/удар видны: %s, вражеские видны: %s" % [str(mine_vis), str(their_vis)])
			print("[MARK] мой блинк виден: %s, вражеский блинк виден: %s" % [blink_m.visible if blink_m else "нет", blink_e.visible if blink_e else "нет"])
			get_tree().quit()


# первый шаг: сколько кадров обе ноги одновременно в воздухе в начале ходьбы
func _run_steptest() -> void:
	var m = main.mech
	if _frame == 5:
		Parts.set_value("mech_assault", "stride_walk", 5.7)
		Parts.set_value("mech_assault", "stride_run", 6.2)
		m.set_build(Parts.DEFAULT_BUILD)
		m.global_position = Vector3(-60, 0.05, 0)
		m.demo = {"move": Vector2.ZERO, "run": false, "fire": false, "dash": false, "aim": Vector3(0, 1.5, 0)}
	if _frame == 60:
		m.demo["move"] = Vector2(1, 0)
		set_meta("both", 0)
		set_meta("log", "")
	if _frame > 60 and _frame <= 180:
		var f = m.visual.feet
		var a0: bool = f[0].air > 0.05 or f[0].quick >= 0.0
		var a1: bool = f[1].air > 0.05 or f[1].quick >= 0.0
		if a0 and a1:
			set_meta("both", get_meta("both") + 1)
		if _frame % 6 == 0:
			set_meta("log", get_meta("log") + ("%s%s " % ["L" if a0 else "_", "R" if a1 else "_"]))
	if _frame == 181:
		print("[STEP] кадров обе ноги в воздухе за 2 с: %d" % get_meta("both"))
		print("[STEP] " + get_meta("log"))
		get_tree().quit()


# стартовый ангар: открыть, сменить сборку (3D-мех перестраивается), нажать "В бой"
func _run_starttest() -> void:
	var h = main.hangar
	match _frame:
		5:
			h.open_start(main.mech.build)
		60:
			h._build = {"mech": "mech_fortress", "core": "core_battery",
				"weapons": ["heavy_cannon", "laser"], "modules": ["mod_rockets", "mod_shield", "mod_armor"]}
			h._refresh_rows()
			h._refresh_info()
		150:
			print("[START] paused=%s button=%s" % [get_tree().paused, h._apply_btn.text])
			h._on_apply()
		160:
			print("[START] after: paused=%s weapons=%s,%s" % [get_tree().paused, main.mech.weapons[0]["name"], main.mech.weapons[1]["name"]])
			get_tree().quit()


# вражеская турель: смотрит ли на цель и с какой дистанции стреляет
func _run_turrettest() -> void:
	var m = main.mech
	var tur = null
	for s in get_tree().get_nodes_in_group("structures"):
		if s.team == 1 and s.id == "turret_t1" and s.get_meta("lane", "") == "mid":
			tur = s
	match _frame:
		5:
			m.global_position = tur.global_position + Vector3(-44, 0, 6)
			m.shield_left = 0.0
			m.demo = {"move": Vector2.ZERO, "run": false, "fire": false, "dash": false, "aim": tur.global_position}
			set_meta("hp0", m.hp)
		180:
			var fwd: Vector3 = -tur._head.global_basis.z
			var to: Vector3 = (m.global_position - tur.global_position)
			to.y = 0
			print("[TUR] на дистанции %.0f м: смотрит на цель %.2f (1 = прямо), моё здоровье %.0f -> %.0f" % [to.length(), fwd.normalized().dot(to.normalized()), get_meta("hp0"), m.hp])
			get_tree().quit()


# все 10 мехов рядом с разным оружием (для снимков)
func _run_gallery() -> void:
	var m = main.mech
	if _frame == 3:
		var weps := ["autocannon", "heavy_cannon", "laser", "blaster", "grenade_launcher", "shotgun", "railgun", "minigun", "autocannon", "laser"]
		var ids: Array = Parts.ids_for("mech")
		m.global_position = Vector3(0, 0.05, 0)
		m.demo = {"move": Vector2.ZERO, "fire": false, "aim": Vector3(0, 1.5, -20)}
		for i in ids.size():
			var mm = main.Mech.new()
			mm.team = i % 2
			var w: String = weps[i]
			var w2: String = weps[(i + 3) % weps.size()]
			mm.build = {"mech": ids[i], "core": "core_combat", "weapons": [w, w2], "modules": ["mod_rockets"] if i % 3 == 0 else []}
			mm.position = Vector3(-17.5 + (i % 5) * 8.75, 0.05, -7.5 if i < 5 else 7.5)
			main.add_child(mm)
			mm.demo = {"move": Vector2.ZERO, "fire": false, "aim": mm.position + Vector3(0, 1.5, 10 if i < 5 else -10)}
			mm.torso_yaw = PI if i < 5 else 0.0
			mm.legs_yaw = mm.torso_yaw
			print("[GAL] %s: %s + %s" % [Parts.pname(ids[i]), Parts.pname(w), Parts.pname(w2)])
	if _frame == 6:
		for mm in get_tree().get_nodes_in_group("mechs"):
			mm.seen = true
	if _frame >= 40 and _shots_left.is_empty():
		get_tree().quit()


# стены: одну до трещины, другую сломать; крипы сразу; печать состояния
func _wall_at(x: float, z: float) -> Node:
	for w in main.walls:
		if absf(w.c[0] - x) < 0.5 and absf(w.c[1] - z) < 0.5:
			return w
	return null


func _run_wallshot() -> void:
	var m = main.mech
	var a = _wall_at(-64, -25)
	var b = _wall_at(-28, -27)
	match _frame:
		3:
			m.global_position = Vector3(-46, 0.05, -34)
			m.demo = {"move": Vector2.ZERO, "fire": false, "aim": Vector3(-46, 1.5, -20)}
			main._creep_t = 0.0
		10:
			a.take_damage(a.hp_max * 0.6, a.global_position, Vector3.ZERO)
			print("[WALL] A state=%d hp=%.0f/%.0f" % [a.state, a.hp, a.hp_max])
		20:
			b.take_damage(b.hp_max + 10.0, b.global_position, Vector3.ZERO)
			print("[WALL] B state=%d free path through B: %s" % [b.state, main.nav.is_free(Vector3(-28, 0, -27))])
		60:
			var q := PhysicsRayQueryParameters3D.create(Vector3(-28, 2, -35), Vector3(-28, 2, -20), 1)
			print("[WALL] ray through B blocked: %s, creeps=%d" % [not m.get_world_3d().direct_space_state.intersect_ray(q).is_empty(), get_tree().get_nodes_in_group("creeps").size()])
	if _frame >= 90 and _shots_left.is_empty():
		get_tree().quit()


# бой крипов рядом с игроком и турель 2 уровня кидает ЭМИ-гранату
func _run_coreshot() -> void:
	var m = main.mech
	var hq: Node3D = null
	for s in get_tree().get_nodes_in_group("structures"):
		if s.team == 1 and s.id == "hq":
			hq = s
	if _frame == 3:
		Cfg.creeps_enabled = 0
		m.global_position = hq.global_position + Vector3(-13, 0.05, 19)
		m.shield_left = 0.0
		m.snap_interpolation(m)
		for s in get_tree().get_nodes_in_group("structures"):
			if s.team == 1 and s.tier == 3:
				s.take_damage(1e9, s.global_position, Vector3.ZERO, "", m)
	if m.stun_left > 0.0 and not get_meta("was_stun", false):
		print("[CORE] f=%d оглушён на %.2f с, hp=%.0f" % [_frame, m.stun_left, m.hp])
	set_meta("was_stun", m.stun_left > 0.0)
	if _frame >= 3:
		m.demo = {"move": Vector2.ZERO, "fire": _frame > 20, "aim": hq.global_position + Vector3(0, 1.5, 0)}
	if _frame % 30 == 0:
		var cores := []
		for s in get_tree().get_nodes_in_group("structures"):
			if s.id == "core":
				cores.append("t%d %.0f %s" % [s.team, s.hp, s.position.round()])
		print("[CORE] f=%d hp=%.0f stun=%.2f hq=%.0f shielded=%s protected=%s cores=%s" % [_frame, m.hp, m.stun_left, hq.hp, hq.shielded(), hq.protected(), cores])
	if _frame == 400:
		for s in get_tree().get_nodes_in_group("structures"):
			if s.team == 1 and (s.tier == 3 or s.id == "core"):
				s.take_damage(1e9, s.global_position, Vector3.ZERO, "", m)
	if _frame >= 480 and _shots_left.is_empty():
		get_tree().quit()


func _run_fxshot() -> void:
	var m = main.mech
	if _frame == 3:
		m.global_position = Vector3(-20, 0.05, 4)
		m.shield_left = 0.0
		Cfg.creeps_enabled = 0
	if _frame >= 3:
		m.hp = m.max_hp() * 0.2
		m.demo = {"move": Vector2(1, 0), "fire": true, "aim": m.global_position + Vector3(20, 1.5, -6)}
		if _zap:
			m.stun(0.5)
			for c in get_tree().get_nodes_in_group("creeps"):
				c.stun(0.5)
	if _zap and _frame == 5:
		var c = main.Creep.new()
		c.team = 1
		c.lane = "mid"
		c.path = main.lane_path(1, "mid")
		c.nav = main.nav
		c.position = m.global_position + Vector3(7, 0, 3)
		main.add_child(c)
	if _frame == 60:
		main.hud._unhandled_input(_alt_click())
	if _frame >= 100 and _shots_left.is_empty():
		get_tree().quit()


func _alt_click() -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.alt_pressed = true
	e.position = Vector2(-100, -100)
	return e


func _run_fightshot() -> void:
	var m = main.mech
	match _frame:
		3:
			m.global_position = Vector3(20, 0.05, 4)
			m.shield_left = 0.0
			m.demo = {"move": Vector2.ZERO, "fire": false, "aim": Vector3(30, 1.5, 0)}
			Cfg.creeps_enabled = 0
			for team in 2:
				for k in 4:
					var c = main.Creep.new()
					c.team = team
					c.lane = "mid"
					c.path = main.lane_path(team, "mid")
					c.nav = main.nav
					c.slot = k
					c.position = Vector3(8.0 + team * 22.0, 0, -6.0 + k * 4.0)
					main.add_child(c)
		30:
			var t2 = null
			for s in get_tree().get_nodes_in_group("structures"):
				if s.team == 1 and s.id == "turret_t2" and s.get_meta("lane", "") == "mid":
					t2 = s
			t2._emp_cd = 0.0
			m.global_position = t2.global_position + Vector3(-34, 0, 3)
			print("[FIGHT] creeps alive=%d" % get_tree().get_nodes_in_group("creeps").size())
		70:
			print("[FIGHT] stun=%.1f hp=%.0f lobs=%d creeps=%d" % [m.stun_left, m.hp, get_tree().get_nodes_in_group("lobs").size(), get_tree().get_nodes_in_group("creeps").size()])
	if _frame >= 100 and _shots_left.is_empty():
		get_tree().quit()


# высадка с неба: снимки в полёте, на торможении и после посадки
func _run_dropshot() -> void:
	var m = main.mech
	if _frame == 5:
		Cfg.drop_time = 2.2
		m.demo = {"move": Vector2.ZERO, "fire": false, "aim": m.global_position + Vector3(10, 1.5, 0)}
		m.respawn(Vector3(-60, 0.05, 0))
	if _frame % 20 == 0 and _frame < 160:
		print("[DROP] f=%d landing=%.2f hit=%s" % [_frame, m.landing_left, m.hitbox._cs.disabled])
	if _frame >= 170 and _shots_left.is_empty():
		get_tree().quit()


# победа: ломаем вражеский штаб и смотрим таблицу после боя
func _run_resultshot() -> void:
	if _frame == 300:
		Cfg.hq_needs_t3 = 0
		for s in get_tree().get_nodes_in_group("structures"):
			if s.team == 1 and s.id == "core":
				s.take_damage(99999.0, s.global_position, Vector3.ZERO, "", main.mech)
		for s in get_tree().get_nodes_in_group("structures"):
			if s.team == 1 and s.id == "hq":
				s.take_damage(99999.0, s.global_position, Vector3.ZERO, "", main.mech)
	if _frame == 520:
		print("[RESULT] winner=%d paused=%s results=%s time=%s rows=%d" % [main.winner, get_tree().paused, main.menu._results.visible, Battle.time_text(), Battle.rows.size()])
	if _frame >= 530 and _shots_left.is_empty():
		get_tree().quit()


# что копится в сцене: всего узлов/объектов/ресурсов, время кадра, и какие узлы верхнего уровня самые частые
func _print_perf() -> void:
	var counts := {}
	for c in get_tree().current_scene.get_children():
		var k: String = c.get_class()
		var sc = c.get_script()
		if sc != null:
			k = sc.resource_path.get_file()
		counts[k] = counts.get(k, 0) + 1
	var top := counts.keys()
	top.sort_custom(func(a, b): return counts[a] > counts[b])
	var parts := []
	for k in top.slice(0, 10):
		parts.append("%s=%d" % [k, counts[k]])
	var mats := 0
	var g = get_tree().current_scene
	if "vision" in g and g.vision != null and "_materials" in g.vision:
		mats = g.vision._materials.size()
	var cells := {}
	for c in get_tree().get_nodes_in_group("creeps"):
		var key := "%s t%d (%d,%d) st=%s" % [c.lane, c.team, int(c.global_position.x / 10) * 10, int(c.global_position.z / 10) * 10, ("tgt" if c._target != null else "lane")]
		cells[key] = cells.get(key, 0) + 1
	var ck := cells.keys()
	ck.sort_custom(func(a, b): return cells[a] > cells[b])
	var cl := []
	for k in ck.slice(0, 8):
		cl.append("%s:%d" % [k, cells[k]])
	print("[CREEPS] ", ", ".join(cl))
	print("[RENDER] draw_calls=%d objects=%d prims=%d video_mem=%.0fMB meshes_total=%d" % [Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME), Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, get_tree().current_scene.find_children("*", "MeshInstance3D", true, false).size()])
	var per := {}
	for mi in get_tree().current_scene.find_children("*", "MeshInstance3D", true, false):
		var n: Node = mi
		var owner_k := "other"
		while n != null and n != get_tree().current_scene:
			var sc = n.get_script()
			if sc != null:
				owner_k = sc.resource_path.get_file()
				break
			n = n.get_parent()
		per[owner_k] = per.get(owner_k, 0) + 1
	print("[MESHES] ", per)
	print("[PHYS] active=%d pairs=%d islands=%d" % [Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS), Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS), Performance.get_monitor(Performance.PHYSICS_3D_ISLAND_COUNT)])
	print("[PERF] t=%ds nodes=%d objs=%d res=%d proc=%.2fms phys=%.2fms vis_mats=%d | %s" % [_frame / 60,
		Performance.get_monitor(Performance.OBJECT_NODE_COUNT), Performance.get_monitor(Performance.OBJECT_COUNT),
		Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT), Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, mats, ", ".join(parts)])
