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
var _target := ""                # --targetshot=fight|base|calm: постановка для целевых кадров (ROADMAP.md, 2.1)
var _nohud := false              # без интерфейса и прицела на земле: чистый кадр
var _actors: Array = []          # мехи постановки targetshot: [мех, в кого он стреляет]
var _stuckcheck := false
var _linktest := false           # две одинаковые пушки на ЛКМ: стреляют обе, по очереди; выключено — только левая
var _railtest := false           # рельсотрон: луч должен лежать вдоль выстрела (баг «полоса поперёк карты»)
var _gfxbench := false           # графика: драка у турели на каждом пресете подряд (бой перезапускается), снимок и замер кадров
var _boom := false               # взрыв рядом с игроком на 5-м кадре (проверка следа гари)
var _moba_secs := 60
var _perf := false               # с mobatest: каждые 20 с сколько узлов, объектов, ресурсов и время кадра
var _fxreel := false             # --fxreel: эффекты одним запуском — драка со взрывами, штурм базы, своя база
var _radartest := false          # --radartest (с --map=arena --enemies=1 --allies=0): круг обзора радара и F2 на паузе
var _ruintest := false           # --ruintest: развалина сломанной турели — бьют обе команды, разбили — припасы и путь свободен
var _slidetest := false          # --slidetest: убит в рывке и на бегу — тушка тормозит о землю по физике, отлетают части
var _lobtest := false            # --lobtest: ЭМИ и осадное орудие турелей летят быстро и низко и попадают в меха
var _spawntest := false         # --spawntest --drop --enemies=0 --allies=1: мех садится прямо на другого — никто не подпрыгивает
var _proptest := false           # --proptest: кучка ящиков не мешает пройти, ломается от меха и от взрыва
var _cdtest := false             # --cdtest: нажал рывок на перезарядке — у курсора таймер «2,35», тает за 1 с
var _capbench := false           # --capbench (окно, с --targetshot=ground или =fight): кадры и видеокарта при разных пределах кадров
var _coredmg := false            # --coredmg: по ядрам-Теслам проходит урон, когда турели 3 уровня сломаны (стреляем автопушкой)
var _creeptest := false          # --creeptest: у крипа после склейки деталей есть корпус, гусеницы и башня
var _aimtest := false            # --aimtest: прицел (земля / середина хитбокса), пределы стволов, гранатомёт
var _fancheck := false           # --fancheck: веер обзора с пропуском лучей совпадает с полным (все лучи)
var _cpubench := false           # --cpubench: что сколько стоит в обычном бою (окно, по очереди выключает тени, траву, крипов...)
var _prof := false               # --prof: сколько времени процессора берёт каждый вид объектов (раз в 10 с в лог)
var _moba_tp := Vector3.ZERO
var _dump_path := ""
var _hangartest := false
var _mechexport := ""            # выгрузка средних мехов (все виды) в .glb для снимков в Блендере
var _bots := 0
var _allies := -1                # --allies=N: союзных ботов (иначе как в настройке; у Сани 4)
var _frame := 0
var _shots_left: Array = []


func setup(main_node: Node3D, args: PackedStringArray) -> void:
	main = main_node
	# в проверках и снимках звука нет (не мешать Сане); обычная игра сюда не попадает
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), true)
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
		elif a == "--railtest":
			_railtest = true
		elif a == "--linktest":
			_linktest = true
		elif a == "--gfxbench":
			_gfxbench = true
			Cfg.graphics = BENCH[_bench_i][1]     # setup идёт до постройки карты: бой строится уже с этой графикой
		elif a.begins_with("--targetshot="):
			_target = a.trim_prefix("--targetshot=")
		elif a == "--nohud":
			_nohud = true
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
		elif a.begins_with("--allies="):
			_allies = int(a.trim_prefix("--allies="))
		elif a.begins_with("--secs="):
			_moba_secs = int(a.trim_prefix("--secs="))
		elif a.begins_with("--map="):
			# карта из папки maps: --map=arena (PvP) или --map=classic
			Maps.selected = "res://maps/%s.json" % a.trim_prefix("--map=")
		elif a == "--perf":
			_perf = true
		elif a == "--prof":
			_prof = true
		elif a == "--fancheck":
			_fancheck = true
		elif a == "--aimtest":
			_aimtest = true
		elif a == "--creeptest":
			_creeptest = true
		elif a == "--coredmg":
			_coredmg = true
		elif a == "--slidetest":
			_slidetest = true
		elif a == "--lobtest":
			_lobtest = true
		elif a == "--capbench":
			_capbench = true
		elif a == "--spawntest":
			_spawntest = true
		elif a == "--proptest":
			_proptest = true
		elif a == "--cdtest":
			_cdtest = true
		elif a == "--ruintest":
			_ruintest = true
		elif a == "--radartest":
			_radartest = true
		elif a == "--fxreel" or a.begins_with("--fxreel="):
			_fxreel = true
			_nohud = true
			# --fxreel=base: начать сразу со штурма базы (только при первом запуске, бой потом перезапускается)
			if not _reel_from_set:
				_reel_from_set = true
				for k in FX_REEL.size():
					if a == "--fxreel=" + FX_REEL[k][0]:
						_reel_i = k
						_reel_only = true
			_target = FX_REEL[_reel_i][0]
			for f in FX_REEL[_reel_i][1]:
				_shots_left.append(f)
		elif a == "--cpubench" or a == "--cpubench-gpu":
			_cpubench = true
			CB_RUNS = CB_RUNS_GPU if a == "--cpubench-gpu" else CB_RUNS_CPU
			_bots = 5          # как у Сани: 5 вражеских и 4 союзных бота
			_allies = 4
			Cfg.graphics = CB_RUNS[_cb_run][1]     # setup идёт до постройки карты
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
		elif a.begins_with("--mechexport="):
			_mechexport = a.trim_prefix("--mechexport=")
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
	if not _mobatest and not _cpubench:
		Cfg.bot_allies = 0
	if _allies >= 0:
		Cfg.bot_allies = _allies


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
	if _prof:
		_prof_frame(false)
	if _cpubench:
		_run_cpubench()
	if _fancheck and _frame == 10:
		_run_fancheck()
	if _aimtest:
		_run_aimtest()
	if _creeptest and _frame == 5:
		_run_creeptest()
	if _coredmg:
		_run_coredmg()
	if _slidetest:
		_run_slidetest()
	if _lobtest:
		_run_lobtest()
	if _spawntest:
		_run_spawntest()
	if _proptest:
		_run_proptest()
	if _cdtest:
		_run_cdtest()
	if _ruintest:
		_run_ruintest()
	if _radartest:
		_run_radartest()
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
	if _target != "":
		_run_targetshot()
	if _railtest:
		_run_railtest()
	if _linktest:
		_run_linktest()
	if _gfxbench:
		_run_gfxbench()
	if _fxreel and _target == "fight" and (_frame == 30 or _frame == 95):
		Fx.explosion(Vector3(58, 1.8, 0) if _frame == 30 else Vector3(61, 1.8, 8), 4.5)
	if _fxreel and _target == "fight" and _frame >= 14 and _frame <= 23 and (_frame - 14) % 3 == 0:
		_reel_rocket(_frame - 14)
	if _fxreel and _target == "fight" and _frame == 70:
		_reel_shotgun_rail()
	if _fxreel and _target == "base" and (_frame == 200 or _frame == 212):
		_reel_dome_hit(0.0 if _frame == 200 else 0.5)
	if _boom and _frame == 5:
		Fx.explosion(main.mech.global_position + Vector3(7, 1.8, 3), 4.5)
		Fx.explosion(main.mech.global_position + Vector3(-6, 1.8, -4), 3.0)
	if _hangartest:
		_run_hangartest()
	if _mechexport != "":
		_run_mechexport()
	if _shot_dir != "" and _shots_left.has(_frame):
		var shot_f := _frame     # пока ждём отрисовку, счётчик кадров может уйти вперёд
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png(("%s/%s_f%04d.png" % [_shot_dir, _target, shot_f]) if _fxreel else ("%s/f%04d.png" % [_shot_dir, shot_f]))
		_shots_left.erase(shot_f)
		if _shots_left.is_empty() and not _inputtest and not _paneltest and not _bottest and not _hittest and not _hangartest and not _flattest and not _abiltest and not _cloaktest and not _mobatest and not _showcase and not _pushtest and not _minetest and not _markertest and not _steptest and not _starttest and not _turrettest and not _gallery and not _wallshot and not _fightshot and not _fxshot and not _coreshot and not _dropshot and not _resultshot and _target == "" and not _railtest and not _linktest and _mechexport == "" and not _gfxbench and not _cpubench and not _fancheck and not _aimtest and not _creeptest and not _radartest and not _ruintest and not _coredmg and not _slidetest and not _lobtest and not _spawntest and not _proptest and not _cdtest:
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
		if n.is_in_group("mechs") or n.is_in_group("walls") or n.is_in_group("creeps") or n.is_in_group("structures") or n.is_in_group("wrecks") or n.is_in_group("props"):
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
			var panel = Cfg.panel
			print("[TEST] F2 pressed, panel visible: %s, rows: %d" % [panel._panel.visible, panel._rows.size()])
		930:
			print("[TEST] done")
			get_tree().quit()


# --- проверка панели настроек: открыть, раскрыть группы, подвигать числа общих правил и деталей ---

func _panel() -> Node:
	return Cfg.panel


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
			panel._rows["part:mech_assault:walk_speed"]["slider"].value = 8.3 * Cfg.METERS_PER_UNIT   # ползунок в метрах
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
				# сброс только со второго нажатия: первое лишь спрашивает
				panel._on_reset_all()
				print("[TEST] reset pressed once: mech_assault still changed=%s" % Parts.is_changed("mech_assault", "walk_speed"))
				panel._on_reset_all()
				panel._show_tab("cfg")
				panel._on_reset_all()
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
		if main.pvp:
			line += " pvp=%d:%d left=%ds" % [main.team_kills[0], main.team_kills[1], int(main.time_left())]
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
			# мина и вражеский крип: крип рядом с миной — она срабатывает
			b2.global_position = Vector3(-60, 0.05, -60)
			var mn3 = preload("res://scripts/mine.gd").new()
			mn3.team = m.team
			mn3.owner_mech = m
			mn3.p = m.abilities[0]["params"].duplicate()      # числа минного укладчика игрока
			mn3.p["arm_time"] = 0.0
			get_tree().current_scene.add_child(mn3)
			mn3.global_position = Vector3(-20, 0.0, -48)
			var c = main.Creep.new()
			c.team = 1 - m.team
			c.lane = "mid"
			c.path = PackedVector3Array([Vector3(-18, 0, -48), Vector3(-30, 0, -48)])
			c.nav = main.nav
			c.position = Vector3(-18, 0, -48)
			main.add_child(c)
			set_meta("creep", c)
			set_meta("creep_hp0", c.hp)
		330:
			var c2 = get_meta("creep")
			var gone := get_tree().get_nodes_in_group("mines").filter(func(x) -> bool: return x.global_position.distance_to(Vector3(-20, 0, -48)) < 1.0).is_empty()
			print("[MINE] вражеский крип у мины: мина сработала %s, крип %s — %s" % [gone,
				("здоровье %.0f -> %.0f" % [get_meta("creep_hp0"), c2.hp]) if is_instance_valid(c2) and not c2.dead else "уничтожен",
				"ВЕРНО" if gone else "ОШИБКА"])
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


# мехи из 3D-моделей и пара коробочных (для сравнения размеров) выгружаются в mechs.glb:
# первый ряд стоит с разным оружием, второй идёт. Снимки делает Блендер, окно игры не нужно
func _run_mechexport() -> void:
	if _frame != 3:
		return
	var MV := preload("res://scripts/mech_visual.gd")
	var sets := [["mech_wasp", "autocannon", "laser", true], ["mech_hound", "shotgun", "railgun", false],
		["mech_assault", "heavy_cannon", "minigun", true], ["mech_fortress", "autocannon", "grenade_launcher", true],
		["mech_ram", "autocannon", "autocannon", false], ["mech_mortar", "heavy_cannon", "laser", false]]
	var root := Node3D.new()
	root.name = "mechs"
	main.add_child(root)
	for row in 2:
		var walking := row == 1
		for i in sets.size():
			var e: Array = sets[i]
			var r := Parts.compute({"mech": e[0], "core": "core_combat", "weapons": [e[1], e[2]], "modules": ["mod_rockets"] if e[3] else []})
			var v = MV.new()
			v.st = r["stats"]
			root.add_child(v)
			v.build(Cfg.mech_accent, Color(1, 1, 1),
				{"legs_scale": r["stats"]["legs_scale"], "hull_scale": r["stats"]["hull_scale"], "style": r["stats"]["style"],
				"model": r["stats"].get("model", ""), "weapons": [r["weapons"][0]["look"], r["weapons"][1]["look"]], "rockets": e[3]})
			var pos := Vector3(i * 10.0, 0, row * 14.0)
			var run: float = r["stats"]["run_speed"]
			for k in 70:
				var vel := Vector3(0, 0, -run) if walking else Vector3.ZERO
				pos += vel / 60.0
				v.update_visual(1.0 / 60.0, pos, vel, 0.0, 0.0, false)
			if walking:
				# ряд идущих стоит там же, где стоящие, только ниже по z
				v.position.z += (70.0 / 60.0) * run
			print("[EXPORT] %s%s (%s + %s): модель %s, ноги %.2f+%.2f, колено %s, треугольников ~%d" % [Parts.pname(e[0]),
				" на бегу" if walking else "", e[1], e[2], v.model if v.model != "" else "коробки", v._l1, v._l2,
				"назад" if v._knee_dir > 0 else "вперёд", _tris(v)])
	# скрытое (вспышки, лучи, пламя) не выгружаем: Блендер не читает скрытые узлы
	var hidden := root.find_children("*", "Node3D", true, false).filter(func(n): return not n.visible)
	while not hidden.is_empty():
		var n: Node = hidden[0]
		n.get_parent().remove_child(n)
		n.free()
		hidden = root.find_children("*", "Node3D", true, false).filter(func(m): return not m.visible)
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	doc.append_from_scene(root, state)
	var path := "%s/mechs.glb" % _mechexport
	var err := doc.write_to_filesystem(state, path)
	print("[EXPORT] %s -> %s" % [path, error_string(err)])
	get_tree().quit()


func _tris(n: Node) -> int:
	var t := 0
	if n is MeshInstance3D and n.mesh != null:
		for si in n.mesh.get_surface_count():
			var arr: Array = n.mesh.surface_get_arrays(si)
			if arr.size() > Mesh.ARRAY_INDEX and arr[Mesh.ARRAY_INDEX] != null and arr[Mesh.ARRAY_INDEX].size() > 0:
				t += arr[Mesh.ARRAY_INDEX].size() / 3
			elif arr.size() > 0 and arr[Mesh.ARRAY_VERTEX] != null:
				t += arr[Mesh.ARRAY_VERTEX].size() / 3
	for c in n.get_children():
		t += _tris(c)
	return t


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
		# два крипа посередине: видно корпус между гусеницами
		for t in 2:
			var c = main.Creep.new()
			c.team = t
			c.lane = "mid"
			c.path = main.lane_path(t, "mid")
			c.nav = main.nav
			c.position = Vector3(-4.0 + t * 8.0, 0, 0)
			main.add_child(c)
			c.stun(99.0)
	if _frame == 6:
		for mm in get_tree().get_nodes_in_group("mechs"):
			mm.seen = true
	if _frame == 45:
		Cfg.cam_distance = 24.0     # второй снимок ближе (если в --shots есть кадр позже 45)
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


# ------------------------------------------------------------------
#  Целевые кадры (ROADMAP.md, 2.1): снимки, которые Саня дорисовывает нейросетью.
#  fight: мехи и крипы дерутся у вражеской турели 2 уровня;
#  base: штурм вражеской базы, ядра бьют молнией, на штабе барьер;
#  calm: спокойные места карты (стены и скалы, своя база, Реактор)
# ------------------------------------------------------------------

func _run_targetshot() -> void:
	var m = main.mech
	if _frame == 3:
		Cfg.creeps_enabled = 0
		m.shield_left = 0.0
		if _nohud:
			main.hud.visible = false
			for c in main.get_children():
				if c.get_script() == main.Crosshair:
					c.visible = false
		if _target == "fight":
			_stage_fight(m)
		elif _target == "base":
			_stage_base(m)
		elif _target == "mines":
			_stage_mines(m)
	if _target == "calm":
		_stage_calm(m)
	elif _target == "ground":
		_stage_ground(m)
	elif _target == "list":
		_stage_list(m)
	elif _target == "props":
		_stage_props(m)
	elif _target == "death":
		_stage_death(m)
	elif _target == "after":
		_stage_after(m)
	elif _target == "small":
		_stage_small(m)
	# все стреляют в свои цели и не умирают, пока идёт съёмка
	for a in _actors:
		var b = a[0]
		b.hp = maxf(b.hp, b.max_hp() * 0.6)
		var t = a[1]
		if t != null and is_instance_valid(t) and not t.dead:
			b.demo["aim"] = t.global_position + Vector3.UP * 1.5
	for a in _actors:
		if a[0].stun_left > 0.0 and not a[0].get_meta("was_stun", false):
			print("[TARGET] f=%d молния в %s" % [_frame, Parts.pname(a[0].build["mech"])])
			if _shot_dir != "" and _cap_i < 0:      # во время замера кадров не снимаем
				for f in [_frame + 2, _frame + 6]:     # молния видна доли секунды: снимаем сразу
					if not _shots_left.has(f):         # два меха под молнией в один кадр — не снимать дважды
						_shots_left.append(f)
		a[0].set_meta("was_stun", a[0].stun_left > 0.0)
	var end_f: int = {"fight": 200, "base": 500, "calm": 220, "ground": 250, "list": 530, "props": 330, "death": 420, "after": 1400, "small": 620}.get(_target, 300)
	if _frame >= end_f and _shots_left.is_empty():
		if _capbench:
			_run_capbench()
		elif _fxreel:
			_reel_next()
		else:
			get_tree().quit()


# --fxreel: постановки по очереди (бой перезапускается), снимки с именем постановки
const FX_REEL := [["fight", [33, 38, 45, 60, 73, 76, 100, 103, 110, 140, 175]], ["base", [150, 204, 214, 226, 240, 300, 450]], ["calm", [60, 130]]]


# попадание в купол вражеского штаба со стороны камеры (волны на куполе). side — сдвиг вбок
func _reel_dome_hit(side: float) -> void:
	var cam := get_viewport().get_camera_3d()
	for st in get_tree().get_nodes_in_group("structures"):
		if st.id == "hq" and st.team != main.mech.team and cam != null:
			var to_cam: Vector3 = cam.global_position - st.global_position
			to_cam.y = 0.0
			to_cam = to_cam.normalized()
			var dir := (to_cam * 0.7 + to_cam.cross(Vector3.UP) * side + Vector3.UP * 0.7).normalized()
			st.take_damage(1.0, st.global_position + dir * 12.0, -dir, "", main.mech)
static var _reel_i := 0
static var _reel_from_set := false
static var _reel_only := false      # --fxreel=<этап>: снять только этот этап
var _reel_done := false


# дробь (тонкий трассер 0,07, 8 дробин) и выстрел рельсы из меха игрока (снимки 73 и 76)
func _reel_shotgun_rail() -> void:
	var m = main.mech
	var from: Vector3 = m.global_position + Vector3(0.8, 2.6, 0)
	var Proj = load("res://scripts/projectile.gd")
	for k in 8:
		var dir := (Vector3(60.0, 1.0, 4.0) - from).normalized().rotated(Vector3.UP, deg_to_rad(randf_range(-6.0, 6.0)))
		var pr = Proj.new()
		pr.setup(from, dir * 90.0, 1.0, 40.0, m)
		pr.tracer = 0.07
		get_tree().current_scene.add_child(pr)
	var from2: Vector3 = m.global_position + Vector3(-0.8, 2.6, 0)
	Fx.rail_beam(from2, Vector3(62.0, 1.5, -2.0), m.team)


# ракета из меха игрока в сторону драки (снимки 33/38/45 — полёт и дым, 60 — взрыв без колец)
func _reel_rocket(k: int) -> void:
	var m = main.mech
	var rk = load("res://scripts/rocket.gd").new()
	var from: Vector3 = m.global_position + Vector3(0.6 if k % 2 == 0 else -0.6, 3.2, 0)
	var p := {"speed": Parts.v("mod_rockets", "speed"), "radius": 24.6,      # огромный радиус, как у Сани в F2
		"damage": Parts.v("mod_rockets", "damage"), "edge_damage": 0.4}
	rk.setup(from, Vector3(60.0 + k * 0.4, 0.0, 4.0 - k * 0.5), m, null, p)
	get_tree().current_scene.add_child(rk)


func _reel_next() -> void:
	if _reel_done:
		return
	_reel_done = true
	if _reel_only:
		get_tree().quit()
		return
	_reel_i += 1
	if _reel_i < FX_REEL.size():
		get_tree().reload_current_scene()
	else:
		get_tree().quit()


# мех постановки: сборка, место, стрельба по цели (цель задаётся потом в _actors)
func _stage_mech(b, mech_id: String, weapons: Array, pos: Vector3) -> Node:
	b.brain = null
	b.set_build({"mech": mech_id, "core": "core_combat", "weapons": weapons, "modules": []})
	b.global_position = pos
	b.shield_left = 0.0
	b.demo = {"move": Vector2.ZERO, "fire": true, "aim": pos + Vector3(10, 1.5, 0)}
	b.snap_interpolation(b)
	return b


func _stage_creeps(team: int, n: int, x: float, z0: float) -> void:
	for k in n:
		var c = main.Creep.new()
		c.team = team
		c.lane = "mid"
		c.path = main.lane_path(team, "mid")
		c.nav = main.nav
		c.slot = k
		c.position = Vector3(x, 0, z0 + k * 5.0)
		main.add_child(c)


func _enemy_structure(id: String, lane := "") -> Node3D:
	for s in get_tree().get_nodes_in_group("structures"):
		if s.team == 1 and s.id == id and (lane == "" or s.get_meta("lane", "") == lane):
			return s
	return null


func _stage_fight(m) -> void:
	Cfg.bot_allies = 1      # иначе бой уберёт ботов сверх настройки
	Cfg.bot_enemies = 2
	var p = _stage_mech(m, "mech_fortress", ["autocannon", "laser"], Vector3(50, 0.05, 4))
	var ally = _stage_mech(main._spawn_bot(0), "mech_assault", ["autocannon", "heavy_cannon"], Vector3(47, 0.05, -8))
	var wasp = _stage_mech(main._spawn_bot(1), "mech_wasp", ["laser", "autocannon"], Vector3(64, 0.05, 6))
	var hound = _stage_mech(main._spawn_bot(1), "mech_hound", ["shotgun", "grenade_launcher"], Vector3(66, 0.05, -7))
	_actors = [[p, wasp], [ally, hound], [wasp, p], [hound, ally]]
	_stage_creeps(0, 4, 55.0, -10.0)
	_stage_creeps(1, 4, 63.0, -10.0)
	var t2 = _enemy_structure("turret_t2", "mid")
	if t2 != null:
		t2._emp_cd = 0.0


func _stage_base(m) -> void:
	# линия уже продавлена: средние турели 1 и 2 уровня сломаны
	for id in ["turret_t1", "turret_t2"]:
		var s = _enemy_structure(id, "mid")
		if s != null:
			s.take_damage(1e9, s.global_position, Vector3.ZERO, "", m)
	var hq = _enemy_structure("hq")
	Cfg.bot_allies = 1
	Cfg.bot_enemies = 1
	var p = _stage_mech(m, "mech_fortress", ["autocannon", "laser"], Vector3(91, 0.05, 3))
	var ally = _stage_mech(main._spawn_bot(0), "mech_assault", ["autocannon", "heavy_cannon"], Vector3(88, 0.05, -7))
	var hound = _stage_mech(main._spawn_bot(1), "mech_hound", ["shotgun", "grenade_launcher"], Vector3(100, 0.05, -5))
	_actors = [[p, hq], [ally, hound], [hound, ally]]
	_stage_creeps(0, 4, 94.0, -9.0)


# мины: слева своя, справа вражеская (её «засёк» омни-сенсор), камера близко
func _stage_mines(m) -> void:
	m.global_position = Vector3(-46, 0.05, -30)
	m.snap_interpolation(m)
	m.demo = {"move": Vector2.ZERO, "fire": false, "aim": Vector3(-30, 1.5, -30)}
	m.stats["omni"] = 20.0      # омни-сенсор засекает вражескую мину рядом
	main.cam._started = false
	for k in 2:
		var mn = preload("res://scripts/mine.gd").new()
		mn.team = k
		mn.p = {"arm_time": 0.0, "trigger_radius": 0.1}
		get_tree().current_scene.add_child(mn)
		mn.global_position = Vector3(-54.0 + k * 4.0, 0.0, -31.0)
		mn.seen = true


# три спокойных места; камеру сразу ставим на меха, без доводки
func _stage_calm(m) -> void:
	var spots := {3: [Vector3(-46, 0.05, -30), Vector3(-30, 1.5, -30)],
		70: [Vector3(-88, 0.05, 0), Vector3(-108, 1.5, 0)],
		140: [Vector3(0, 0.05, -46), Vector3(0, 1.5, -58)]}
	if not spots.has(_frame):
		return
	var s: Array = spots[_frame]
	m.global_position = s[0]
	m.snap_interpolation(m)
	m.demo = {"move": Vector2.ZERO, "fire": false, "aim": s[1]}
	main.cam._started = false


# земля крупно (--targetshot=ground): площадка своей базы (камера 90 и 40), колеи на линии,
# самая большая группа луж (камера 32 и 90). Снимки на кадрах 45, 95, 145, 195, 245
var _ground_spots: Array = []


func _stage_ground(m) -> void:
	if _frame == 3:
		Cfg.bot_allies = 0
		Cfg.bot_enemies = 0
		var hq: Vector3 = main.base_center(0)
		var mid: PackedVector3Array = main.lane_path(0, "mid")
		var out: Vector3 = (mid[mini(2, mid.size() - 1)] - hq).normalized()
		var rut: Vector3 = mid[mid.size() / 4] if mid.size() > 4 else hq + out * 40.0
		var pud := hq
		var best := -1
		for a in main.puddles:
			var n := 0
			for b in main.puddles:
				if Vector2(a.x - b.x, a.z - b.z).length() < 8.0:
					n += 1
			if n > best:
				best = n
				pud = Vector3(a.x, 0, a.z)
		_ground_spots = [[3, hq + out * 14.0, 90.0], [55, hq + out * 14.0, 40.0], [105, rut, 40.0],
			[155, pud, 32.0], [205, pud, 90.0]]
		print("[GROUND] база %s, колеи %s, лужи %s (кругов рядом %d)" % [hq + out * 14.0, rut, pud, best])
		for f in [45, 95, 145, 195, 245]:
			if _shot_dir != "" and not _shots_left.has(f):
				_shots_left.append(f)
	for s in _ground_spots:
		if s[0] != _frame:
			continue
		var at: Vector3 = s[1]
		m.global_position = at + Vector3(-5.0, 0.05, 3.0)       # мех сбоку, чтобы не закрывал место
		m.snap_interpolation(m)
		m.demo = {"move": Vector2.ZERO, "fire": false, "aim": at + Vector3(0, 1.5, 0)}
		Cfg.cam_distance = s[2]
		main.cam._started = false


# правки по списку Сани одной постановкой (--targetshot=list): ник над полоской (рядом союзник),
# мех проходит сквозь кучку ящиков (снимки через 3, 10 и 40 кадров после поломки), рывок со струёй,
# щит со светом (и попадание в него), метка авиаудара от вызова до падения ракеты.
# Снимки 30, поломка+3/+10/+40, 184, 196, 205, 262, 274, 310, 400, 460, 478, 486
func _stage_list(m) -> void:
	var crates := Vector3(-62, 0, -16)
	if _frame == 3:
		Cfg.bot_allies = 1
		Cfg.bot_enemies = 0
		Cfg.cam_distance = 36.0
		m.set_build({"mech": "mech_fortress", "core": "core_combat", "weapons": ["autocannon", "laser"], "modules": ["mod_shield", "mod_airstrike"]})
		m.global_position = crates + Vector3(-8, 0.05, 0)
		m.snap_interpolation(m)
		main.cam._started = false
		var ally = _stage_mech(main._spawn_bot(0), "mech_assault", ["autocannon", "heavy_cannon"], crates + Vector3(-6, 0.05, 7))
		ally.demo = {"move": Vector2.ZERO, "fire": false, "aim": crates + Vector3(20, 1.5, 7)}
		if _shot_dir != "":
			for f in [30, 184, 196, 205, 262, 274, 310, 400, 460, 478, 486]:
				if not _shots_left.has(f):
					_shots_left.append(f)
	if _frame < 4:
		return
	m.energy = m.energy_max()
	m.hp = m.max_hp()
	if not has_meta("crate_broke") and _pt_prop(crates).broken:
		set_meta("crate_broke", _frame)
		print("[LIST] кучка ящиков сломана на кадре %d" % _frame)
		if _shot_dir != "":
			for f in [_frame + 3, _frame + 10, _frame + 40]:
				_shots_left.append(f)
	var aim: Vector3 = m.global_position + Vector3(14, 1.5, -3)
	if _frame < 31 or _frame >= 140:
		m.demo = {"move": Vector2.ZERO, "fire": false, "aim": aim}
	elif _frame < 140:
		m.demo = {"move": Vector2(1, 0), "fire": false, "aim": aim}
	if _frame == 180:
		m.dash_stock = 2.0
		m.demo = {"move": Vector2(1, 0), "fire": false, "dash": true, "aim": aim}
	if _frame == 240:
		m.press_ability(0)          # щит
	if _frame == 272:
		m.take_damage(15.0, m.global_position + Vector3(2, 2, 0), Vector3.LEFT, "", null)
	if _frame == 300:
		m.press_ability(0)          # щит выключить
		m.ability_cd[1] = 0.0
		m.press_ability(1)          # авиаудар
		print("[LIST] авиаудар: задержка %.2f с" % m.abilities[1]["params"]["delay"])


# мелочь и провода (--targetshot=props): провода от своего штаба (камера 60, кадр 40), ящики крупно
# (камера 26, кадр 85), мех задевает фонарь — снимки через 4, 14 и 45 кадров, провода на линии сверху (кадр 320)
func _stage_props(m) -> void:
	if _frame == 3:
		Cfg.bot_allies = 0
		Cfg.bot_enemies = 0
		_props_at(m, Vector3(-80, 0.05, -10), 60.0)
		if _shot_dir != "":
			_shots_left.append_array([40, 85, 320])
	if _frame == 50:
		_props_at(m, Vector3(-66, 0.05, -20), 26.0)
	if _frame == 100:
		var best: Node3D = null
		for p in get_tree().get_nodes_in_group("props"):
			if p.kind == "post" and (best == null or p.global_position.distance_to(m.global_position) < best.global_position.distance_to(m.global_position)):
				best = p
		set_meta("post", best)
		_props_at(m, best.global_position + Vector3(-5, 0.05, 1.0), 30.0)
		m.demo = {"move": Vector2(1, 0), "fire": false, "aim": best.global_position + Vector3(10, 1.5, 0)}
	if has_meta("post") and not has_meta("post_f") and get_meta("post").broken:
		set_meta("post_f", _frame)
		if _shot_dir != "":
			_shots_left.append_array([_frame + 4, _frame + 14, _frame + 45])
	if _frame == 250:
		_props_at(m, Vector3(-40, 0.05, -8), 90.0)
		Cfg.cam_pitch = 80.0


# смерть меха (--targetshot=death): вражеский мех убит в рывке у камеры — падает, скользит, отлетают части,
# снимки через 4, 16, 34, 50, 75 и 150 кадров; потом ящики крупно (кадр 380)
func _stage_death(m) -> void:
	var at := Vector3(0, 0.05, -20)        # открытое место (по нему же проверяет slidetest)
	if _frame == 3:
		Cfg.bot_allies = 0
		Cfg.bot_enemies = 1
		Cfg.creeps_enabled = 0
		_props_at(m, at + Vector3(5, 0, 8), 28.0)
		m.demo = {"move": Vector2.ZERO, "fire": false, "aim": at + Vector3(5, 1.5, -2)}
	if _frame == 60:
		for b in main.bots:
			b.brain = null
			b.set_build({"mech": "mech_assault", "core": "core_combat", "weapons": ["autocannon", "heavy_cannon"], "modules": []})
			b.global_position = at + Vector3(-8, 0.0, 0)
			b.snap_interpolation(b)
			b.shield_left = 0.0
			b.velocity = Vector3(50, 0, 0)
			b.take_damage(1e6, b.global_position + Vector3.UP * 2.0, Vector3.RIGHT, "", m)
			if _shot_dir != "":
				_shots_left.append_array([63, 70, 80, 94, 110, 135, 210])
	if _frame == 340:
		_props_at(m, Vector3(-66, 0.05, -20), 26.0)
		if _shot_dir != "":
			_shots_left.append(380)


# последствия боя (--targetshot=after): автопушка по стене — следы попаданий (кадр 110), стена рушится —
# пыль (140, 175, 240); вражеский мех погибает рядом — большой взрыв и тушка горит (290, 330, 520, 900);
# вражеская турель 1 уровня гибнет — развалина горит (1010, 1300)
func _stage_after(m) -> void:
	if _frame == 3:
		Cfg.bot_allies = 0
		Cfg.bot_enemies = 1
		Cfg.creeps_enabled = 0
		var best = null
		for w in main.walls:
			if best == null or w.global_position.distance_to(Vector3(-46, 0, -30)) < best.global_position.distance_to(Vector3(-46, 0, -30)):
				best = w
		set_meta("wall", best)
		m.set_build({"mech": "mech_assault", "core": "core_combat", "weapons": ["autocannon", "autocannon"], "modules": []})
		_props_at(m, best.global_position + Vector3(0, 0.05, 11), 30.0)
		if _shot_dir != "":
			_shots_left.append_array([110, 140, 175, 240, 290, 330, 520, 900, 1010, 1300])
	var wall = get_meta("wall") if has_meta("wall") else null
	if _frame > 3 and _frame < 115 and wall != null:
		m.demo = {"move": Vector2.ZERO, "fire": true, "aim": wall.global_position + Vector3(randf_range(-2, 2), 1.4, 0)}
		m.refill_all()
		wall.hp = maxf(wall.hp, wall.hp_max * 0.6)      # пусть стоит, пока стреляем
	if _frame == 115:
		m.demo = {"move": Vector2.ZERO, "fire": false, "aim": wall.global_position}
	if _frame == 125 and wall != null:
		wall.take_damage(1e6, wall.global_position + Vector3.UP, Vector3.FORWARD, "explosion", m)
	if _frame == 260:
		for b in main.bots:
			b.brain = null
			b.global_position = m.global_position + Vector3(-7, 0.0, -2)
			b.snap_interpolation(b)
			b.shield_left = 0.0
			b.velocity = Vector3(6, 0, 0)
			b.take_damage(1e6, b.global_position + Vector3.UP * 2.0, Vector3.RIGHT, "", m)
	if _frame == 960:
		var t1 = _enemy_structure("turret_t1", "mid")
		if t1 != null:
			_props_at(m, t1.global_position + Vector3(-9, 0.05, 7), 30.0)
			t1.take_damage(1e9, t1.global_position, Vector3.ZERO, "", m)


# новая мелочь (--targetshot=small): мешки перед своей турелью (кадр 40) и взрыв у них (60, 75), бетонные блоки
# у дороги — мех упирается (снимки до 150, через 6 и 30 кадров после), забор у точки интереса — мех проходит (то же)
func _stage_small(m) -> void:
	if _frame == 3:
		Cfg.bot_allies = 0
		Cfg.bot_enemies = 0
		Cfg.creeps_enabled = 0
		_props_at(m, Vector3(-48, 0.05, -8), 26.0)
		m.demo = {"move": Vector2.ZERO, "fire": false, "aim": Vector3(-40, 1.5, 0)}
		if _shot_dir != "":
			_shots_left.append_array([40, 60, 75, 150, 330])
	if _frame == 55:
		var bags := _pt_kind("sandbags", Vector3(-45, 0, 0))
		Fx.explosion(bags.global_position + Vector3(4.6, 0.5, 1.0), 2.5)
		Fx.blast(bags.global_position + Vector3(4.6, 0.5, 1.0), 2.5, 10.0, 0.5, 1, null)
	if _frame == 120:
		var jer := _pt_kind("jersey", Vector3(-50, 0, 9))
		set_meta("sm_j", jer)
		_props_at(m, jer.global_position + Vector3(0, 0.05, 7), 24.0)
		m.demo = {"move": Vector2(0, -1), "fire": false, "aim": jer.global_position + Vector3(0, 1.5, -10)}
	if _frame == 300:
		var fen := _pt_kind("fence", Vector3(-13, 0, -55))
		set_meta("sm_f", fen)
		_props_at(m, fen.global_position + Vector3(-7, 0.05, 1.5), 24.0)
		m.demo = {"move": Vector2(1, 0), "fire": false, "aim": fen.global_position + Vector3(10, 1.5, 0)}
	for key in ["sm_j", "sm_f"]:
		if has_meta(key) and not has_meta(key + "_t") and get_meta(key).broken:
			set_meta(key + "_t", _frame)
			if _shot_dir != "":
				_shots_left.append_array([_frame + 6, _frame + 30])


func _props_at(m, at: Vector3, cam: float) -> void:
	m.global_position = at
	m.snap_interpolation(m)
	m.demo = {"move": Vector2.ZERO, "fire": false, "aim": at + Vector3(8, 1.5, 0)}
	Cfg.cam_distance = cam
	main.cam._started = false


# ------------------------------------------------------------------
#  Замер графики (--gfxbench, запуск в окне с --disable-vsync): постановка драки из --targetshot=fight
#  на каждом пресете. Через 3 с снимок gfx_<пресет>.png в --shot-dir, с 4-й по 14-ю секунду замер кадров
#  (среднее, 1% худших, время видеокарты, треугольники и вызовы отрисовки), потом бой перезапускается
#  со следующим пресетом. Последний прогон — низкие без теней солнца, только для сравнения.
# ------------------------------------------------------------------

const BENCH := [["low", 0, true], ["mid", 1, true], ["high", 2, true], ["low_noshadow", 0, false]]
static var _bench_i := 0
static var _bench_out: Array = []
var _bench_t0 := 0
var _bench_last := 0
var _bench_ms: Array = []
var _bench_gpu := 0.0
var _bench_prims := 0.0
var _bench_calls := 0.0
var _bench_shot := false


func _run_gfxbench() -> void:
	var m = main.mech
	var vp_rid := get_viewport().get_viewport_rid()
	if _frame == 3:
		Cfg.creeps_enabled = 0
		m.shield_left = 0.0
		if _nohud:
			main.hud.visible = false
			for c in main.get_children():
				if c.get_script() == main.Crosshair:
					c.visible = false
		_stage_fight(m)
		if not BENCH[_bench_i][2]:
			for c in main.get_children():
				if c is DirectionalLight3D:
					c.shadow_enabled = false
		RenderingServer.viewport_set_measure_render_time(vp_rid, true)
		_bench_t0 = Time.get_ticks_usec()
		_bench_last = _bench_t0
	if _frame < 3:
		return
	for a in _actors:
		a[0].hp = maxf(a[0].hp, a[0].max_hp() * 0.6)
		var t = a[1]
		if t != null and is_instance_valid(t) and not t.dead:
			a[0].demo["aim"] = t.global_position + Vector3.UP * 1.5
	var now := Time.get_ticks_usec()
	var secs := (now - _bench_t0) / 1e6
	var label: String = BENCH[_bench_i][0]
	if secs >= 3.0 and not _bench_shot and _shot_dir != "":
		_bench_shot = true
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/gfx_%s.png" % [_shot_dir, label])
		return
	if secs >= 4.0 and secs < 14.0:
		_bench_ms.append((now - _bench_last) / 1000.0)
		_bench_gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp_rid)
		_bench_prims += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		_bench_calls += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	_bench_last = now
	if secs < 14.0 or _bench_ms.is_empty():
		return
	var n := _bench_ms.size()
	var sorted_ms := _bench_ms.duplicate()
	sorted_ms.sort()
	var worst: Array = sorted_ms.slice(int(n * 0.99))
	var avg_ms: float = sorted_ms.reduce(func(acc, x): return acc + x, 0.0) / n
	var low1: float = worst.reduce(func(acc, x): return acc + x, 0.0) / maxf(worst.size(), 1.0)
	var line := "[GFX] %-12s %4d кадр/с (%.2f мс), 1%% худших %4d кадр/с (%.1f мс), видеокарта %.2f мс, треугольников %d тыс., вызовов %d" % [
		label, int(1000.0 / avg_ms), avg_ms, int(1000.0 / low1), low1, _bench_gpu / n, int(_bench_prims / n / 1000.0), int(_bench_calls / n)]
	print(line)
	_bench_out.append(line)
	_bench_i += 1
	if _bench_i < BENCH.size():
		get_tree().reload_current_scene()
		return
	print("[GFX] ---- итог (%s) ----" % [str(DisplayServer.window_get_size())])
	for l in _bench_out:
		print(l)
	get_tree().quit()


# две автопушки, зажата только ЛКМ. С настройкой «на ЛКМ» стреляют обе, по очереди; без неё — только левая
var _link_shots := [[], []]


func _run_linktest() -> void:
	var m = main.mech
	if _frame == 3:
		Cfg.creeps_enabled = 0
		Cfg.link_guns = 1
		m.set_build({"mech": "mech_assault", "core": "core_combat", "weapons": ["autocannon", "autocannon"], "modules": []})
		m.global_position = Vector3(-8, 0.05, 10)
		m.fired.connect(func(i: int) -> void: _link_shots[i].append(_frame))
	if _frame >= 5:
		m.demo = {"move": Vector2.ZERO, "fire": _frame < 125 or (_frame > 140 and _frame < 260), "fire2": false, "aim": m.global_position + Vector3(30, 1.5, 0)}
	if _frame == 130:
		var a: Array = _link_shots[0]
		var b: Array = _link_shots[1]
		var gap: int = (b[0] - a[0]) if not a.is_empty() and not b.is_empty() else -1
		print("[LINK] на ЛКМ: левая %d выстрелов, правая %d, правая позже левой на %d кадров — %s" % [a.size(), b.size(), gap,
			"ВЕРНО" if a.size() > 2 and b.size() > 2 and gap > 0 else "НЕ ТАК"])
		_link_shots = [[], []]
		Cfg.link_guns = 0
	if _frame == 265:
		print("[LINK] настройка выключена: левая %d выстрелов, правая %d — %s" % [_link_shots[0].size(), _link_shots[1].size(),
			"ВЕРНО" if _link_shots[0].size() > 2 and _link_shots[1].is_empty() else "НЕ ТАК"])
		Cfg.link_guns = 1
		get_tree().quit()


# рельсотрон стреляет вдоль линии (X), поперёк (Z) и по диагонали; меряем, куда вытянут нарисованный луч.
# Длинная сторона луча должна совпадать с направлением выстрела
var _rail_dirs := [Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(1, 0, 1).normalized()]
var _rail_seen := {}


func _run_railtest() -> void:
	var m = main.mech
	var k := _frame / 180
	if _frame == 3:
		Cfg.creeps_enabled = 0
		m.set_build({"mech": "mech_fortress", "core": "core_combat", "weapons": ["railgun", "railgun"], "modules": []})
		m.global_position = Vector3(-8, 0.05, 10)
		m.shield_left = 0.0
		m.snap_interpolation(m)
	if _frame >= 5 and k < _rail_dirs.size():
		var dir: Vector3 = _rail_dirs[k]
		m.demo = {"move": Vector2.ZERO, "fire": _frame % 180 > 50, "fire2": false, "aim": m.global_position + dir * 30.0 + Vector3.UP * 1.5}
	for c in get_tree().current_scene.get_children():
		if c is MeshInstance3D and c.mesh is BoxMesh and not _rail_seen.has(c.get_instance_id()):
			_rail_seen[c.get_instance_id()] = true
			var bb: AABB = c.global_transform * c.get_aabb()
			var want: Vector3 = _rail_dirs[mini(k, _rail_dirs.size() - 1)]
			# луч длинный и лежит под тем же углом, что выстрел (до 12°: пушка сбоку корпуса, сведение на прицел)
			var ang := rad_to_deg(absf(atan2(bb.size.z, bb.size.x) - atan2(absf(want.z), absf(want.x))))
			var ok := Vector2(bb.size.x, bb.size.z).length() > 1.0 and ang < 12.0
			print("[RAIL] f=%d выстрел %s размер луча=(%.1f, %.1f, %.1f) %s" % [_frame, want.snapped(Vector3.ONE * 0.01), bb.size.x, bb.size.y, bb.size.z, "ВЕРНО" if ok else "НЕ ТУДА"])
	if _frame >= 180 * _rail_dirs.size() + 10:
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
	var vis_per := {}
	var sh_per := {}
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
		if mi.is_visible_in_tree():
			vis_per[owner_k] = vis_per.get(owner_k, 0) + 1
			if mi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
				sh_per[owner_k] = sh_per.get(owner_k, 0) + 1
	print("[MESHES] ", per)
	print("[MESHES] видимые: ", vis_per)
	print("[MESHES] видимые с тенью: ", sh_per)
	# всё, что рисуется (любые видимые 3D-объекты), по хозяину и виду: ищем, что копится со временем
	var geo := {}
	for gi in get_tree().current_scene.find_children("*", "GeometryInstance3D", true, false):
		if not gi.is_visible_in_tree():
			continue
		var n2: Node = gi
		var ow := "main"
		while n2 != null and n2 != get_tree().current_scene:
			if n2.get_script() != null:
				ow = n2.get_script().resource_path.get_file()
				break
			n2 = n2.get_parent()
		var kind: String = gi.get_class()
		if gi is MeshInstance3D and gi.mesh != null:
			kind += ":" + gi.mesh.get_class()
		var key := ow + " " + kind
		geo[key] = geo.get(key, 0) + 1
	var gk := geo.keys()
	gk.sort_custom(func(a, b): return geo[a] > geo[b])
	var gl := []
	for k in gk.slice(0, 16):
		gl.append("%s=%d" % [k, geo[k]])
	print("[GEO] ", ", ".join(gl))
	print("[PHYS] active=%d pairs=%d islands=%d" % [Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS), Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS), Performance.get_monitor(Performance.PHYSICS_3D_ISLAND_COUNT)])
	print("[PERF] t=%ds nodes=%d objs=%d res=%d proc=%.2fms phys=%.2fms vis_mats=%d | %s" % [_frame / 60,
		Performance.get_monitor(Performance.OBJECT_NODE_COUNT), Performance.get_monitor(Performance.OBJECT_COUNT),
		Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT), Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, mats, ", ".join(parts)])


# ------------------------------------------------------------------
#  Замер процессора по видам объектов (--prof). У всех узлов со скриптом движок больше не зовёт
#  _physics_process и _process — их зовёт этот замер сам, с секундомером, и копит время по файлу
#  скрипта. Раз в 10 с печатает средние мс на тик (физика, 30 в секунду) и на кадр (вид).
#  «прочее» — всё, что движок делает сам (столкновения, частицы, сглаживание), без наших скриптов.
# ------------------------------------------------------------------

var _prof_nodes: Array = []          # [узел, имя скрипта, есть _physics_process, есть _process]
var _prof_pending: Array = []
var _prof_methods := {}              # скрипт -> [есть физика, есть вид]
var _prof_t := {}                    # "phys имя" / "proc имя" -> мкс
var _prof_n := {}                    # сколько раз вызвали
var _prof_ticks := 0
var _prof_frames := 0
var _prof_engine_phys := 0.0
var _prof_engine_proc := 0.0
var _prof_started := false
var _prof_wall := 0                  # настоящее время между кадрами, мкс
var _prof_last := 0
var _prof_tick_in_frame := false     # в этом кадре был тик физики
var _prof_ft_tick: Array = []        # время кадров с тиком, мс
var _prof_ft_plain: Array = []       # время кадров без тика
var _prof_tick_sum := 0              # скрипты в текущем тике, мкс
var _prof_tick_list: Array = []      # скрипты по тикам, мс
var _prof_tick_max := {}             # имя -> худший тик, мкс
var _prof_cur := {}                  # имя -> мкс в текущем тике


func _physics_process(_delta: float) -> void:
	if _prof:
		_prof_frame(true)
	_cb_ticked = true


func _prof_take(n: Node) -> void:
	if n == self or not is_instance_valid(n) or n.get_script() == null:
		return
	var sc: Script = n.get_script()
	if not _prof_methods.has(sc):
		var names := {}
		var s2: Script = sc
		while s2 != null:
			for m in s2.get_script_method_list():
				names[m["name"]] = true
			s2 = s2.get_base_script()
		_prof_methods[sc] = [names.has("_physics_process"), names.has("_process")]
	var hm: Array = _prof_methods[sc]
	if not hm[0] and not hm[1]:
		return
	if hm[0]:
		n.set_physics_process(false)
	if hm[1]:
		n.set_process(false)
	var nm := sc.resource_path.get_file()
	if nm == "":
		nm = n.get_class()
	_prof_nodes.append([n, nm, hm[0], hm[1]])


func _prof_frame(phys: bool) -> void:
	if not _prof_started:
		if _frame < 10:
			return
		_prof_started = true
		var stack: Array = [get_tree().root]
		while not stack.is_empty():
			var x: Node = stack.pop_back()
			_prof_take(x)
			stack.append_array(x.get_children())
		get_tree().node_added.connect(func(n: Node) -> void: _prof_pending.append(n))
	# новые узлы (снаряды, крипы, эффекты): забираем, когда они готовы (после _ready движок включает обработку сам)
	var still: Array = []
	for n in _prof_pending:
		if not is_instance_valid(n):
			continue
		if n.is_node_ready():
			_prof_take(n)
		else:
			still.append(n)
	_prof_pending = still
	var dt := get_physics_process_delta_time() if phys else get_process_delta_time()
	var alive: Array = []
	for e in _prof_nodes:
		var n = e[0]
		if not is_instance_valid(n):
			continue
		alive.append(e)
		if not n.is_inside_tree() or not n.can_process():
			continue
		if phys and e[2]:
			var t0 := Time.get_ticks_usec()
			n._physics_process(dt)
			var k: String = "phys " + e[1]
			var us := Time.get_ticks_usec() - t0
			_prof_t[k] = _prof_t.get(k, 0) + us
			_prof_n[k] = _prof_n.get(k, 0) + 1
			_prof_cur[k] = _prof_cur.get(k, 0) + us
			_prof_tick_sum += us
		elif not phys and e[3]:
			var t1 := Time.get_ticks_usec()
			n._process(dt)
			var k2: String = "proc " + e[1]
			_prof_t[k2] = _prof_t.get(k2, 0) + Time.get_ticks_usec() - t1
			_prof_n[k2] = _prof_n.get(k2, 0) + 1
	_prof_nodes = alive
	if phys:
		_prof_ticks += 1
		_prof_engine_phys += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		_prof_tick_in_frame = true
		_prof_tick_list.append(_prof_tick_sum / 1000.0)
		_prof_tick_sum = 0
		for k3 in _prof_cur:
			_prof_tick_max[k3] = maxi(_prof_tick_max.get(k3, 0), _prof_cur[k3])
		_prof_cur.clear()
	else:
		_prof_frames += 1
		_prof_engine_proc += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		var now := Time.get_ticks_usec()
		if _prof_last > 0:
			_prof_wall += now - _prof_last
			(_prof_ft_tick if _prof_tick_in_frame else _prof_ft_plain).append((now - _prof_last) / 1000.0)
		_prof_last = now
		_prof_tick_in_frame = false
		if _prof_frames % 600 == 0:
			_prof_print()


func _prof_print() -> void:
	var keys := _prof_t.keys()
	keys.sort_custom(func(a, b): return _prof_t[a] > _prof_t[b])
	var sum_phys := 0.0
	var sum_proc := 0.0
	for k in keys:
		if k.begins_with("phys"):
			sum_phys += _prof_t[k] / 1000.0
		else:
			sum_proc += _prof_t[k] / 1000.0
	# счётчики движка (TIME_PROCESS, TIME_PHYSICS_PROCESS) — худший кадр за секунду, поэтому меряем и сами
	print("[PROF] t=%ds  за последние 10 с игры: всё %.0f мс на %d кадров и %d тиков; скрипты тиков %.0f мс, скрипты кадров %.0f мс, остальное (движок) %.0f мс" % [_frame / 60,
		_prof_wall / 1000.0, _prof_frames, _prof_ticks, sum_phys, sum_proc, _prof_wall / 1000.0 - sum_phys - sum_proc])
	print("[PROF]   в среднем: кадр %.2f мс, тик скриптов %.2f мс, кадр скриптов %.2f мс (худший тик движка %.1f мс)" % [_prof_wall / 1000.0 / maxf(_prof_frames, 1),
		sum_phys / maxf(_prof_ticks, 1), sum_proc / maxf(_prof_frames, 1), _prof_engine_phys / maxf(_prof_ticks, 1)])
	var stat := func(a: Array) -> String:
		if a.is_empty():
			return "-"
		var b := a.duplicate()
		b.sort()
		return "в среднем %.2f, 90%% %.2f, худший %.2f мс" % [b.reduce(func(x, y): return x + y, 0.0) / b.size(), b[int(b.size() * 0.9)], b[-1]]
	print("[PROF]   кадры с тиком: %s | без тика: %s" % [stat.call(_prof_ft_tick), stat.call(_prof_ft_plain)])
	print("[PROF]   скрипты в тике: %s" % stat.call(_prof_tick_list))
	var mk := _prof_tick_max.keys()
	mk.sort_custom(func(a, b): return _prof_tick_max[a] > _prof_tick_max[b])
	var ml := []
	for k4 in mk.slice(0, 8):
		ml.append("%s %.2f" % [k4.trim_prefix("phys "), _prof_tick_max[k4] / 1000.0])
	print("[PROF]   худший тик по скриптам, мс: ", ", ".join(ml))
	_prof_ft_tick.clear()
	_prof_ft_plain.clear()
	_prof_tick_list.clear()
	_prof_tick_max.clear()
	_prof_wall = 0
	for k in keys.slice(0, 14):
		var per: float = _prof_t[k] / 1000.0 / maxf(_prof_ticks if k.begins_with("phys") else _prof_frames, 1)
		print("[PROF]   %-26s %6.3f мс на %s, вызовов %d" % [k, per, "тик" if k.begins_with("phys") else "кадр", _prof_n[k]])
	_prof_t.clear()
	_prof_n.clear()
	_prof_ticks = 0
	_prof_frames = 0
	_prof_engine_phys = 0.0
	_prof_engine_proc = 0.0


# ------------------------------------------------------------------
#  Что сколько стоит (--cpubench, окно с --disable-vsync). Обычный бой как у Сани: 4 союзных и
#  5 вражеских ботов, крипы, камера с высоты 90; мех игрока стоит у середины. Бой идёт несколько раз
#  подряд (сам перезапускается), по разу на набор из CB_RUNS. После разгона (20 с) меряем по 4 с:
#  «как есть», «с синхронизацией» (как видит игрок: монитор задаёт предел кадров) и по очереди без
#  части картинки — разница с соседними «как есть» = цена этой части. --cpubench-gpu: разбор нагрузки
#  на видеокарту (трава, тени, свечение, вспышки, частицы) на Высоких.
#  В лог строки [CPU]: кадр, кадры с тиком и без, из чего состоит кадр (тик, кадр скриптов и движка,
#  отрисовка, прочее), отрисовка на процессоре и видеокарте по замеру Godot, вызовы отрисовки.
# ------------------------------------------------------------------

const CB_RUNS_CPU := [
	["Низкие", 0, ["base", "no_hud", "base", "no_fog", "base", "no_labels", "base", "no_mechs", "base",
		"no_creeps", "base", "vsync"]],
	["Средние", 1, ["base", "vsync"]],
	["Высокие", 2, ["base", "vsync"]],
]
const CB_RUNS_GPU := [
	["Высокие", 2, ["base", "vsync", "no_grass", "base", "no_sun_shadow", "base", "no_ssao_glow", "base",
		"no_flash", "base", "no_particles", "base", "no_mechs", "base", "no_creeps", "base"]],
]
static var CB_RUNS: Array = CB_RUNS_CPU
static var _cb_run := 0
static var _cb_out: Array = []
var _cb_t0 := 0
var _cb_step := -1
var _cb_last := 0
var _cb_acc := {}
var _cb_res: Array = []
var _cb_saved := {}
var _cb_ticked := false
var _cb_scan := 0.0
var _cb_ph := {}                 # отметки времени внутри кадра (мкс): начало тика, кадра, отрисовки


func _cb_steps() -> Array:
	return CB_RUNS[_cb_run][2]


func _cb_env() -> Environment:
	for c in main.get_children():
		if c is WorldEnvironment:
			return c.environment
	return null


func _cb_sun() -> DirectionalLight3D:
	if _cb_saved.has("sun"):
		return _cb_saved["sun"]
	for c in main.get_children():
		if c is DirectionalLight3D and c.shadow_enabled:
			_cb_saved["sun"] = c
			return c
	return null


func _cb_apply(step: String, on: bool) -> void:
	# on = выключить часть картинки; каждый кадр, потому что игра сама возвращает видимость
	match step:
		"vsync":
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if on else DisplayServer.VSYNC_DISABLED)
		"no_sun_shadow":
			var sun := _cb_sun()
			if sun != null:
				sun.shadow_enabled = not on
		"no_grass":
			for c in main.art.get_children():
				if c is MultiMeshInstance3D and c.multimesh != null and c.multimesh.use_colors:
					c.visible = not on
		"no_ssao_glow":
			var env := _cb_env()
			if on and not _cb_saved.has("ssao"):
				_cb_saved["ssao"] = env.ssao_enabled
				_cb_saved["glow"] = env.glow_enabled
			if _cb_saved.has("ssao"):
				env.ssao_enabled = false if on else _cb_saved["ssao"]
				env.glow_enabled = false if on else _cb_saved["glow"]
		"no_flash":
			Cfg.graphics = 0 if on else CB_RUNS[_cb_run][1]     # вспышки света считаются по графике
		"no_particles":
			_cb_scan -= get_process_delta_time()
			if on and _cb_scan <= 0.0:
				_cb_scan = 0.3
				for p in main.find_children("*", "CPUParticles3D", true, false):
					if not p.has_meta("cb_vis"):
						p.set_meta("cb_vis", p.visible)
					p.visible = false
			elif not on:
				for p in main.find_children("*", "CPUParticles3D", true, false):
					if p.has_meta("cb_vis"):
						p.visible = p.get_meta("cb_vis")
						p.remove_meta("cb_vis")
		"no_creeps":
			if on:
				for c in get_tree().get_nodes_in_group("creeps"):
					c.visible = false
		"no_hud":
			main.hud.visible = not on
		"no_fog":
			for vp in main.vision.find_children("*", "SubViewport", true, false):
				vp.render_target_update_mode = SubViewport.UPDATE_DISABLED if on else SubViewport.UPDATE_ALWAYS
		"no_labels":
			_cb_scan -= get_process_delta_time()
			if on and _cb_scan <= 0.0:
				_cb_scan = 0.3
				for n in main.find_children("*", "Label3D", true, false):
					n.visible = false
				for n in main.find_children("*", "Node3D", true, false):
					if n.get_script() != null and n.get_script().resource_path.ends_with("hp_bar.gd"):
						n.visible = false
		"no_mechs":
			if on:
				for m in get_tree().get_nodes_in_group("mechs"):
					if m.visual != null:
						m.visual.visible = false


func _run_cpubench() -> void:
	var m = main.mech
	var vp_rid := get_viewport().get_viewport_rid()
	if _frame == 5:
		process_priority = 1000      # после игры: успеваем спрятать то, что игра только что показала
		Cfg.cam_distance = 90.0
		m.global_position = Vector3(-30, 0.05, 6)
		m.snap_interpolation(m)
		m.demo = {"move": Vector2.ZERO, "run": false, "fire": false, "dash": false, "aim": Vector3(0, 1.5, 6)}
		RenderingServer.viewport_set_measure_render_time(vp_rid, true)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		_cb_t0 = Time.get_ticks_usec()
		# части кадра: тик (от начала тика до начала кадра), кадр (скрипты и движок до отрисовки),
		# отрисовка (вся, со сменой картинки на экране), прочее (до начала следующего кадра)
		get_tree().physics_frame.connect(_cb_on_phys)
		get_tree().process_frame.connect(_cb_on_proc)
		RenderingServer.frame_pre_draw.connect(_cb_on_pre)
		RenderingServer.frame_post_draw.connect(_cb_post_draw)
		if _cb_run == 0:
			print("[CPU] синхронизация в проекте: %s (1 = включена); монитор %.0f Гц; окно %s; ботов %d+%d" % [
				str(ProjectSettings.get_setting("display/window/vsync/vsync_mode")), DisplayServer.screen_get_refresh_rate(),
				str(DisplayServer.window_get_size()), Cfg.bot_allies, Cfg.bot_enemies])
	if _frame < 5:
		return
	m.hp = m.max_hp()
	var steps := _cb_steps()
	var now := Time.get_ticks_usec()
	var t := (now - _cb_t0) / 1e6
	var warm := 20.0
	var step_i := int((t - warm) / 4.0) if t >= warm else -1
	if step_i != _cb_step:
		if _cb_step >= 0 and _cb_step < steps.size():
			_cb_apply(steps[_cb_step], false)
			_cb_finish(steps[_cb_step])
		_cb_step = step_i
		_cb_acc = {"ft": [], "tick": [], "plain": []}
		if _cb_step >= steps.size():
			_cb_next()
			return
	if _cb_step >= 0:
		_cb_apply(steps[_cb_step], true)
		var into := t - warm - _cb_step * 4.0
		if into > 0.5 and _cb_last > 0:
			var ms := (now - _cb_last) / 1000.0
			_cb_acc["ft"].append(ms)
			_cb_acc["tick" if _cb_ticked else "plain"].append(ms)
			_cb_acc["cpu"] = _cb_acc.get("cpu", 0.0) + RenderingServer.viewport_get_measured_render_time_cpu(vp_rid)
			_cb_acc["gpu"] = _cb_acc.get("gpu", 0.0) + RenderingServer.viewport_get_measured_render_time_gpu(vp_rid)
			_cb_acc["calls"] = _cb_acc.get("calls", 0.0) + Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
			_cb_acc["prims"] = _cb_acc.get("prims", 0.0) + Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	_cb_ticked = false
	_cb_last = now


func _cb_on_phys() -> void:
	if not _cb_ph.has("phys"):
		_cb_ph["phys"] = Time.get_ticks_usec()


func _cb_on_proc() -> void:
	_cb_ph["proc"] = Time.get_ticks_usec()


func _cb_on_pre() -> void:
	_cb_ph["pre"] = Time.get_ticks_usec()


# кадр нарисован: раскладываем его время на части
func _cb_post_draw() -> void:
	var post := Time.get_ticks_usec()
	if _cb_ph.has("proc") and _cb_ph.has("pre") and _cb_acc.has("ft"):
		var start: int = _cb_ph.get("phys", _cb_ph["proc"])
		if _cb_ph.has("last_post"):
			_cb_acc["p_other"] = _cb_acc.get("p_other", 0.0) + (start - _cb_ph["last_post"]) / 1000.0
		if _cb_ph.has("phys"):
			_cb_acc["p_tick"] = _cb_acc.get("p_tick", 0.0) + (_cb_ph["proc"] - _cb_ph["phys"]) / 1000.0
			_cb_acc["n_tick"] = _cb_acc.get("n_tick", 0) + 1
		_cb_acc["p_proc"] = _cb_acc.get("p_proc", 0.0) + (_cb_ph["pre"] - _cb_ph["proc"]) / 1000.0
		_cb_acc["p_draw"] = _cb_acc.get("p_draw", 0.0) + (post - _cb_ph["pre"]) / 1000.0
		_cb_acc["p_n"] = _cb_acc.get("p_n", 0) + 1
	_cb_ph = {"last_post": post}


func _cb_avg(a: Array) -> float:
	return a.reduce(func(x, y): return x + y, 0.0) / maxf(a.size(), 1)


func _cb_finish(step: String) -> void:
	var a: Dictionary = _cb_acc
	var ft: Array = a["ft"]
	var n := float(maxi(ft.size(), 1))
	var srt := ft.duplicate()
	srt.sort()
	var slow := ft.filter(func(x): return x > 1000.0 / 144.0).size()
	var line := "[CPU] %-8s %-13s %4d кадр/с, кадр %.2f мс (с тиком %.2f, без тика %.2f, 90%% %.2f), дольше 6,9 мс: %d%% кадров | отрисовка на проц. %.2f мс, видеокарта %.2f мс, вызовов %d, треуг. %d тыс., крипов %d" % [
		CB_RUNS[_cb_run][0], step, int(1000.0 * n / maxf(_cb_avg(ft) * n, 1.0)), _cb_avg(ft), _cb_avg(a["tick"]), _cb_avg(a["plain"]),
		srt[int(srt.size() * 0.9)] if not srt.is_empty() else 0.0, int(100.0 * slow / n),
		a.get("cpu", 0.0) / n, a.get("gpu", 0.0) / n, int(a.get("calls", 0.0) / n), int(a.get("prims", 0.0) / n / 1000.0),
		get_tree().get_nodes_in_group("creeps").size()]
	var pn := float(maxi(a.get("p_n", 0), 1))
	line += "\n[CPU]          из чего кадр: тик %.2f мс (на кадр с тиком, таких %d%%), скрипты и движок кадра %.2f, отрисовка %.2f, прочее %.2f" % [
		a.get("p_tick", 0.0) / maxf(a.get("n_tick", 0), 1), int(100.0 * a.get("n_tick", 0) / pn), a.get("p_proc", 0.0) / pn,
		a.get("p_draw", 0.0) / pn, a.get("p_other", 0.0) / pn]
	print(line)
	_cb_res.append([step, _cb_avg(ft), a.get("cpu", 0.0) / n, a.get("gpu", 0.0) / n])
	_cb_out.append(line)


func _cb_next() -> void:
	print("[CPU] ---- %s: сколько стоит каждая часть (разница с соседними «как есть») ----" % CB_RUNS[_cb_run][0])
	for i in _cb_res.size():
		var r: Array = _cb_res[i]
		if r[0] == "base" or r[0] == "vsync" or i == 0 or i + 1 >= _cb_res.size():
			continue
		var bw: float = (_cb_res[i - 1][1] + _cb_res[i + 1][1]) * 0.5
		var bc: float = (_cb_res[i - 1][2] + _cb_res[i + 1][2]) * 0.5
		var bg: float = (_cb_res[i - 1][3] + _cb_res[i + 1][3]) * 0.5
		var l := "[CPU]   %-13s кадр %+.2f мс, отрисовка на проц. %+.2f мс, видеокарта %+.2f мс" % [r[0], r[1] - bw, r[2] - bc, r[3] - bg]
		print(l)
		_cb_out.append(l)
	_cb_run += 1
	if _cb_run < CB_RUNS.size():
		get_tree().reload_current_scene()
		return
	print("[CPU] ======== итог ========")
	for l in _cb_out:
		print(l)
	get_tree().quit()


# веер обзора: лучи пускаются только в сторону укрытий (vision._fan_dists). Сравниваем с полным
# веером (все лучи) в точках по всей карте, в том числе вплотную к стенам и краям
func _run_fancheck() -> void:
	var v = main.vision
	var space: PhysicsDirectSpaceState3D = main.get_world_3d().direct_space_state
	var r: Rect2 = main.map_rect()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var worst := 0.0
	var bad := 0
	var total_rays := 0
	var cast_rays := 0
	for i in 400:
		var from := Vector3(rng.randf_range(r.position.x + 1, r.end.x - 1), v.EYE, rng.randf_range(r.position.y + 1, r.end.y - 1))
		var rad: float = [35.0, 22.0, 14.0][i % 3]
		var n: int = v.RAYS if i % 2 == 0 else v.RAYS_CREEP
		var fast: PackedFloat32Array = v._fan_dists(space, from, rad, n)
		var spans: Array = v._obstacle_spans(space, from, rad)
		for k in n:
			var a := TAU * k / n
			var q := PhysicsRayQueryParameters3D.create(from, from + Vector3(cos(a), 0, sin(a)) * rad, 1)
			var hit := space.intersect_ray(q)
			var full := rad if hit.is_empty() else minf(from.distance_to(hit["position"]) + 1.2, rad)
			var diff := absf(full - fast[k])
			worst = maxf(worst, diff)
			if diff > 0.01:
				bad += 1
			total_rays += 1
			for sp in spans:
				if wrapf(a - sp.x, 0.0, TAU) <= sp.y:
					cast_rays += 1
					break
	print("[FAN] точек 400, лучей %d, из них пущено %d (%.0f%%), расхождений %d, худшее %.3f м — %s" % [total_rays, cast_rays,
		100.0 * cast_rays / maxf(total_rays, 1), bad, worst, "ВЕРНО" if bad == 0 else "ОШИБКА"])
	get_tree().quit()


# ------------------------------------------------------------------
#  Прицел и стрельба (--aimtest). Мех стоит в (0, -30) лицом к барьеру (0, -14), высота барьера 3,5.
#  Пули и гранаты отслеживаются: где пропали (там и попали) и сколько летели.
# ------------------------------------------------------------------

var _at_track := {}      # id -> [узел, последняя позиция, кадр вылета, вид]
var _at_done: Array = []  # [вид, где пропал, сколько кадров летел, скорость в начале]
var _at_creep: Node3D
var _at_fails := 0


func _at_check(ok: bool, text: String) -> void:
	print("[AIM] %s — %s" % [text, "ВЕРНО" if ok else "ОШИБКА"])
	if not ok:
		_at_fails += 1


func _at_collect() -> void:
	for c in main.get_children():
		var sc = c.get_script()
		if sc == null:
			continue
		var kind := ""
		if sc == main.mech.Projectile:
			kind = "bullet"
		elif sc == main.mech.Lob:
			kind = "lob"
		if kind == "":
			continue
		var id := c.get_instance_id()
		if not _at_track.has(id):
			var v0: Vector3 = c.vel if kind == "bullet" else c._vel
			_at_track[id] = [c, c.global_position, _frame, kind, v0]
		else:
			_at_track[id][1] = c.global_position
	for id in _at_track.keys():
		var e: Array = _at_track[id]
		if not is_instance_valid(e[0]) or e[0].is_queued_for_deletion():
			_at_done.append([e[3], e[1], _frame - e[2], e[4]])
			_at_track.erase(id)


func _at_shots(kind: String) -> Array:
	var out := _at_done.filter(func(x): return x[0] == kind)
	_at_done.clear()
	return out


func _run_aimtest() -> void:
	var m = main.mech
	var fwd := Vector3(0, 0, 1)
	if _frame == 3:
		Cfg.creeps_enabled = 0
		m.set_build({"mech": "mech_fortress", "core": "core_combat", "weapons": ["autocannon", "grenade_launcher"], "modules": []})
		m.global_position = Vector3(0, 0.05, -30)
		m.torso_yaw = PI
		m.legs_yaw = PI
		m.shield_left = 0.0
		m.snap_interpolation(m)
		m.demo = {"move": Vector2.ZERO, "fire": false, "fire2": false, "aim": Vector3(0, 0, -18)}
		print("[AIM] высота хитбокса Крепости %.2f" % m.get_hit_height())
	if _frame < 5:
		return
	_at_collect()
	var d: Dictionary = m.demo
	m.ammo[0] = 99.0
	m.ammo[1] = 99.0
	# A: автопушка в землю на 12 м
	if _frame == 40:
		d["aim"] = Vector3(0, 0, -18)
	d["fire"] = _frame >= 60 and _frame < 66
	if _frame == 150:
		var b := _at_shots("bullet")
		var ok := not b.is_empty()
		for x in b:
			ok = ok and absf(x[1].z - (-18.0)) < 3.5 and x[1].y < 1.5
		_at_check(ok, "выстрел в землю на 12 м: пули упали у точки (%s)" % ", ".join(b.map(func(x): return "z=%.1f y=%.1f" % [x[1].z, x[1].y])))
		d["aim"] = Vector3(0, 0, -28)          # B: в упор (2 м)
	d["fire"] = d["fire"] or (_frame >= 180 and _frame < 186)
	if _frame == 270:
		var b2 := _at_shots("bullet")
		var ok2 := not b2.is_empty()
		var angs := []
		for x in b2:
			var flat := Vector3(x[3].x, 0, x[3].z).normalized()
			var ang := rad_to_deg(flat.angle_to(fwd))
			angs.append("%.0f°" % ang)
			ok2 = ok2 and ang <= 13.0 + 6.0 and x[1].z > -26.0
		_at_check(ok2, "прицел в упор: стволы повёрнуты не больше 12° (+разброс): %s, пули ушли вперёд дальше 4 м" % ", ".join(angs))
		# C: враг под курсором — прицел на середину его хитбокса
		_at_creep = main.Creep.new()
		_at_creep.team = 1
		_at_creep.lane = "mid"
		_at_creep.path = main.lane_path(1, "mid")
		_at_creep.nav = main.nav
		_at_creep.position = Vector3(5, 0, -18)
		main.add_child(_at_creep)
	if _frame == 280:
		_at_creep.seen = true
		var c: Vector3 = _at_creep.global_position
		var o := c + Vector3(0, 45, 26)
		var dir := (c + Vector3(0.6, 0.5, 0.3) - o).normalized()
		var ap: Vector3 = m.aim_from_ray(o, dir)
		var want = Plane(Vector3.UP, c.y + _at_creep.get_hit_height() * 0.5).intersects_ray(o, dir)
		_at_check(want != null and ap.distance_to(want) < 0.05 and Vector2(ap.x - c.x, ap.z - c.z).length() > 0.3,
			"курсор на крипе: прицел на высоте середины хитбокса (y=%.2f, высота крипа %.2f), но там, куда показывает курсор (%.1f м от центра — можно брать упреждение)" % [ap.y, _at_creep.get_hit_height(), Vector2(ap.x - c.x, ap.z - c.z).length()])
		var o2 := Vector3(-6, 45, 0)
		var ap2: Vector3 = m.aim_from_ray(o2, (Vector3(-6, 0, -22) - o2).normalized())
		_at_check(absf(ap2.y) < 0.05, "курсор на земле: прицел на земле (y=%.2f)" % ap2.y)
		d["aim"] = Vector3(c.x, c.y + _at_creep.get_hit_height() * 0.5, c.z)
		_at_creep.set_meta("hp0", _at_creep.hp)
	d["fire"] = d["fire"] or (_frame >= 300 and _frame < 330)
	if _frame == 380:
		_at_creep.stun(99.0)
		_at_check(_at_creep.dead or _at_creep.hp < _at_creep.get_meta("hp0"), "стреляем в середину крипа: попадания есть (здоровье %d из %d)" % [int(_at_creep.hp), int(_at_creep.get_meta("hp0"))])
		_at_shots("bullet")
		if is_instance_valid(_at_creep):
			_at_creep.queue_free()
		d["aim"] = Vector3(0, 0, -20)           # D: граната в землю на 10 м
	d["fire2"] = (_frame >= 400 and _frame < 402) or (_frame >= 520 and _frame < 522) or (_frame >= 640 and _frame < 642)
	if _frame == 500:
		var g := _at_shots("lob")
		var ok3 := g.size() >= 1
		for x in g:
			ok3 = ok3 and absf(x[1].z - (-20.0)) < 3.0 and x[2] < 40
		_at_check(ok3, "граната на 10 м перед барьером: упала у точки быстро (%s)" % ", ".join(g.map(func(x): return "z=%.1f y=%.1f за %.2f с" % [x[1].z, x[1].y, x[2] / 60.0])))
		d["aim"] = Vector3(0, 0, -10)           # E: сразу за барьером
	if _frame == 620:
		var g2 := _at_shots("lob")
		var ok4 := g2.size() >= 1
		for x in g2:
			ok4 = ok4 and x[1].z < -12.5 and x[1].z > -16.5 and x[1].y > 0.2
		_at_check(ok4, "граната сразу за барьер: врезалась в барьер (%s)" % ", ".join(g2.map(func(x): return "z=%.1f y=%.1f" % [x[1].z, x[1].y])))
		d["aim"] = Vector3(0, 0, 20)            # F: далеко за барьер (дальше дальности)
	if _frame == 760:
		var g3 := _at_shots("lob")
		var ok5 := g3.size() >= 1
		for x in g3:
			ok5 = ok5 and x[1].z > -12.0 and x[1].y < 1.0
		_at_check(ok5, "граната вдаль: перелетела барьер и упала на землю (%s)" % ", ".join(g3.map(func(x): return "z=%.1f за %.2f с" % [x[1].z, x[2] / 60.0])))
		# G: граната падает на барьер сверху (высота барьера 3,5) — должна врезаться в крышку, а не пройти
		var probe = main.mech.Lob.new()
		probe.setup_ballistic(Vector3(0, 60, 100), Vector3.ZERO, m, {"kind": "explosive", "damage": 0.0, "radius": 1.0})
		main.add_child(probe)
		var down: Dictionary = probe._cast(Vector3(0.5, 6.0, -14.2), Vector3(0.5, 2.0, -14.0))
		_at_check(not down.is_empty() and absf(down["position"].y - 3.5) < 0.05, "граната падает на барьер сверху: врезается в его верх (y=%s)" % ("%.2f" % down["position"].y if not down.is_empty() else "мимо"))
		var over: Dictionary = probe._cast(Vector3(0.5, 4.2, -17.0), Vector3(0.5, 3.9, -11.0))
		_at_check(over.is_empty() or over["position"].y < 0.1, "граната над барьером выше его верха: пролетает")
		var side: Dictionary = probe._cast(Vector3(0.5, 2.0, -17.0), Vector3(0.5, 2.0, -11.0))
		_at_check(not side.is_empty() and absf(side["position"].z - (-14.8)) < 0.05, "граната в бок барьера: врезается в стенку (z=%s)" % ("%.2f" % side["position"].z if not side.is_empty() else "мимо"))
		probe.queue_free()
		print("[AIM] итог: %s" % ("ВСЁ ВЕРНО" if _at_fails == 0 else "ошибок %d" % _at_fails))
		get_tree().quit()


# ------------------------------------------------------------------
#  Крип (--creeptest): после склейки деталей у него должны остаться корпус, гусеницы и башня.
#  Печатает каждую модель крипа: материал, сколько вершин и габарит
# ------------------------------------------------------------------

func _run_creeptest() -> void:
	var c = main.Creep.new()
	c.team = 1
	c.lane = "mid"
	c.path = main.lane_path(1, "mid")
	c.nav = main.nav
	c.position = Vector3(0, 0, -20)
	main.add_child(c)
	var body_ok := false
	var fails := 0
	for mi in c.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi
		var box: AABB = m.mesh.get_aabb() if m.mesh != null else AABB()
		var verts := 0
		var lost := 0          # вершины, на которые не ссылается ни один треугольник (не рисуются)
		if m.mesh != null:
			for si in m.mesh.get_surface_count():
				var arr := m.mesh.surface_get_arrays(si)
				var nv := (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
				verts += nv
				if arr[Mesh.ARRAY_INDEX] != null and (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() > 0:
					var used := {}
					for ix in arr[Mesh.ARRAY_INDEX]:
						used[ix] = true
					lost += nv - used.size()
		var col: Color = m.material_override.albedo_color if m.material_override is StandardMaterial3D else Color.BLACK
		print("[CREEP] %s: вершин %d, из них не рисуются %d, габарит %s, цвет %s" % [m.get_parent().name, verts, lost, box.size, col])
		if lost > 0:
			fails += 1
		# корпус: модель светлой брони шириной больше 1,4 и длиной больше 2,2
		if col.r > 0.3 and box.size.x > 1.4 and box.size.z > 2.2 and verts > 0 and lost == 0:
			body_ok = true
	print("[CREEP] корпус на месте — %s" % ("ВЕРНО" if body_ok else "ОШИБКА"))
	print("[CREEP] все склеенные детали рисуются — %s" % ("ВЕРНО" if fails == 0 else "ОШИБКА (%d моделей с пропавшими кусками)" % fails))
	get_tree().quit()


# ------------------------------------------------------------------
#  Радар (--radartest --map=arena --enemies=1 --allies=0): стоишь у вышки — захват, круг обзора раскрывается,
#  враг далеко за пределами обзора меха виден; ушёл — круг сворачивается, враг пропадает, радар остаётся твоим.
#  В конце F2 на паузе открывает панель
# ------------------------------------------------------------------

var _rt_radar: Node3D
var _rt_enemy: Node3D
var _rt_fails := 0


func _rt_check(ok: bool, text: String) -> void:
	print("[RADAR] %s — %s" % [text, "ВЕРНО" if ok else "ОШИБКА"])
	if not ok:
		_rt_fails += 1


func _run_radartest() -> void:
	var m = main.mech
	if _frame == 5:
		for p in get_tree().get_nodes_in_group("pois"):
			if p.kind == "radar":
				_rt_radar = p
		for mm in get_tree().get_nodes_in_group("mechs"):
			if mm.team != m.team:
				_rt_enemy = mm
		if _rt_radar == null or _rt_enemy == null:
			print("[RADAR] нет радара или врага на карте — ОШИБКА")
			get_tree().quit()
			return
		Cfg.poi_radar_range = 80.0
		var rp: Vector3 = _rt_radar.global_position
		var dir := Vector3(-rp.x, 0, -rp.z).normalized()
		m.global_position = rp + Vector3(0, 0.05, 0)
		m.snap_interpolation(m)
		m.demo = {"move": Vector2.ZERO, "fire": false, "aim": rp + dir * 10.0}
		_rt_enemy.global_position = rp + dir * 68.0 + Vector3(0, 0.05, 0)
		_rt_enemy.snap_interpolation(_rt_enemy)
		_rt_enemy.stun(99.0)
		print("[RADAR] обзор меха %.0f, враг в %.0f от вышки" % [m.stats.get("vision", 35.0), 68.0])
	if _rt_radar == null:
		return
	if _frame == 60:
		_rt_check(_rt_radar.owner_team == -1 and not main.vision.is_visible_to(m.team, _rt_enemy),
			"через 1 с ещё не захвачен, врага не видно")
	if _frame == 200:
		var r: float = _rt_radar.radar_r
		_rt_check(_rt_radar.owner_team == m.team and r > 79.0, "захват за 2 с, круг раскрылся до %.0f" % r)
		_rt_check(main.vision.is_visible_to(m.team, _rt_enemy), "враг в 68 от вышки (дальше обзора меха) виден")
		var dir2: Vector3 = (_rt_enemy.global_position - _rt_radar.global_position).normalized()
		m.global_position = _rt_radar.global_position + dir2.cross(Vector3.UP) * 15.0 + Vector3(0, 0.05, 0)
		m.snap_interpolation(m)
	if _frame == 222:
		_rt_check(_rt_radar.radar_r < 79.0 and _rt_radar.radar_r > 0.0, "ушёл от вышки: круг сужается (%.0f)" % _rt_radar.radar_r)
	if _frame == 260:
		_rt_check(_rt_radar.radar_r == 0.0, "через 0,6 с круг свернулся")
		_rt_check(not main.vision.is_visible_to(m.team, _rt_enemy), "врага больше не видно")
		_rt_check(_rt_radar.owner_team == m.team, "радар остаётся твоим")
		get_tree().paused = true
		_tap(KEY_F2)
	if _frame == 266:
		_rt_check(Cfg.panel._panel.visible, "на паузе F2 открыл панель")
		Cfg.panel.toggle()
		get_tree().paused = false
		print("[RADAR] итог: %s" % ("ВСЁ ВЕРНО" if _rt_fails == 0 else "ошибок %d" % _rt_fails))
		get_tree().quit()


# ------------------------------------------------------------------
#  Развалина турели (--ruintest): ломаем вражескую турель 1-го уровня, по развалине бьют обе команды,
#  разбили — выпали припасы, тела нет, путь для ботов свободен
# ------------------------------------------------------------------

var _ru: Node3D
var _ru_fails := 0


func _ru_check(ok: bool, text: String) -> void:
	print("[RUIN] %s — %s" % [text, "ВЕРНО" if ok else "ОШИБКА"])
	if not ok:
		_ru_fails += 1


func _run_ruintest() -> void:
	if _frame == 5:
		Cfg.creeps_enabled = 0
		var best_d := 1e9
		for st in get_tree().get_nodes_in_group("structures"):
			if st.team != main.mech.team and st.tier == 1 and st.id != "hq" and st.id != "core":
				var d: float = st.global_position.distance_to(main.mech.global_position)
				if d < best_d:
					best_d = d
					_ru = st
		if _ru == null:
			print("[RUIN] нет вражеской турели 1-го уровня — ОШИБКА")
			get_tree().quit()
			return
		_ru.take_damage(1e6, _ru.global_position, Vector3.FORWARD, "", main.mech)
	if _frame == 10:
		_ru_check(_ru.dead and _ru.is_ruin() and absf(_ru.ruin_hp - Cfg.ruin_hp) < 0.1,
			"турель сломана, осталась развалина: прочность %.0f (у обломка меха %.0f)" % [_ru.ruin_hp, Cfg.wreck_hp])
		_ru_check(not Fx.team_rids(_ru.team).has(_ru.hitbox.get_rid()), "снаряды команды-хозяина по развалине не пролетают")
		_ru_check(not main.nav.is_free(_ru.global_position), "пока развалина стоит, боты её обходят")
		var h0: float = _ru.ruin_hp
		Fx.blast(_ru.global_position, 6.0, 100.0, 1.0, _ru.team)
		_ru_check(_ru.ruin_hp < h0, "взрыв команды-хозяина её задевает (%.0f → %.0f)" % [h0, _ru.ruin_hp])
		var h1: float = _ru.ruin_hp
		_ru.hitbox.take_damage(100.0, _ru.global_position, Vector3.FORWARD, "", main.mech)
		_ru_check(_ru.ruin_hp < h1, "попадание в хитбокс развалины (%.0f → %.0f)" % [h1, _ru.ruin_hp])
		_ru.set_meta("loot0", get_tree().get_nodes_in_group("pickups").size())
		_ru.take_damage(1e6, _ru.global_position, Vector3.FORWARD, "", main.mech)
	if _frame == 20:
		var loot: int = get_tree().get_nodes_in_group("pickups").size() - int(_ru.get_meta("loot0"))
		_ru_check(_ru.cleared and not _ru.visible and _ru._body == null, "развалину разбили: тела и вида нет")
		_ru_check(loot >= Cfg.ruin_loot, "выпали припасы: %d" % loot)
		_ru_check(main.nav.is_free(_ru.global_position), "путь через это место свободен")
		print("[RUIN] итог: %s" % ("ВСЁ ВЕРНО" if _ru_fails == 0 else "ошибок %d" % _ru_fails))
		get_tree().quit()


# ------------------------------------------------------------------
#  Ядра-Теслы (--coredmg): пока стоят турели 3 уровня — неуязвимы; сломали турели 3 уровня — мех
#  стреляет в ядро автопушкой с 20 м и должен снимать здоровье. В лог — куда попадают пули
# ------------------------------------------------------------------

var _cd_core: Node3D
var _cd_fails := 0


func _cd_check(ok: bool, text: String) -> void:
	print("[CORE] %s — %s" % [text, "ВЕРНО" if ok else "ОШИБКА"])
	if not ok:
		_cd_fails += 1


func _run_coredmg() -> void:
	var m = main.mech
	if _frame == 5:
		Cfg.creeps_enabled = 0
		for st in get_tree().get_nodes_in_group("structures"):
			if st.team != m.team and st.id == "core" and _cd_core == null:
				_cd_core = st
		_cd_check(_cd_core.protected(), "пока стоят турели 3 уровня, ядро неуязвимо")
		for st in get_tree().get_nodes_in_group("structures"):
			if st.team != m.team and st.tier == 3:
				st.take_damage(1e6, st.global_position, Vector3.FORWARD, "", m)
	if _frame == 8:
		_cd_check(not _cd_core.protected(), "турели 3 уровня сломаны — ядро не защищено")
		m.set_build({"mech": "mech_fortress", "core": "core_combat", "weapons": ["autocannon", "autocannon"], "modules": []})
		var cp: Vector3 = _cd_core.global_position
		var away := Vector3(-cp.x, 0, -cp.z).normalized()      # от ядра к середине карты, откуда идёт атака
		m.global_position = cp + away * 14.0 + Vector3(0, 0.05, 0)
		m.snap_interpolation(m)
		m.shield_left = 0.0
		m.demo = {"move": Vector2.ZERO, "fire": false, "aim": Vector3(cp.x, _cd_core.get_hit_height() * 0.5, cp.z)}
		_cd_core.set_meta("hp0", _cd_core.hp)
		print("[CORE] ядро в %s, мех в %s, расстояние %.1f, здоровье %.0f" % [cp, m.global_position, m.global_position.distance_to(cp), _cd_core.hp])
	if _frame >= 30 and _frame < 150:
		m.ammo[0] = 99.0
		m.ammo[1] = 99.0
		m.demo["fire"] = true
		var cp2: Vector3 = _cd_core.global_position
		m.demo["aim"] = Vector3(cp2.x, _cd_core.get_hit_height() * 0.5, cp2.z)
	if _frame >= 30 and _frame < 150 and _frame % 20 == 0:
		# куда летит выстрел: луч от ствола к прицелу
		var o: Vector3 = m.visual.get_muzzle(0)
		var q := PhysicsRayQueryParameters3D.create(o, o + (m.aim_point - o).normalized() * 40.0, 1 | 4 | 16)
		q.collide_with_areas = true
		q.exclude = Fx.team_rids(m.team)
		var hit: Dictionary = m.get_world_3d().direct_space_state.intersect_ray(q)
		var what := "ничего"
		if not hit.is_empty():
			var c = hit["collider"]
			what = "%s (%s) в %s" % [c.name, c.get_parent().get("id") if c.get_parent() != null else "", hit["position"]]
		print("[CORE] кадр %d: ствол %s, прицел %s, первым на пути: %s" % [_frame, o, m.aim_point, what])
	if _frame == 160:
		_cd_check(_cd_core.hp < float(_cd_core.get_meta("hp0")), "автопушка снимает здоровье ядра: %.0f → %.0f" % [float(_cd_core.get_meta("hp0")), _cd_core.hp])
		print("[CORE] итог: %s" % ("ВСЁ ВЕРНО" if _cd_fails == 0 else "ошибок %d" % _cd_fails))
		get_tree().quit()


# ------------------------------------------------------------------
#  Обломок после смерти в рывке (--slidetest): вражеский бот на открытом месте делает рывок и сразу
#  погибает; обломок должен проехать не дальше нескольких метров
# ------------------------------------------------------------------

var _sl_bot: Node3D
var _sl_track: Array = []      # [кадр, обломок, откуда, путь по кадрам]
var _sl_fails := 0


func _sl_kill(mm: Node3D, at: Vector3, vel: Vector3) -> void:
	mm.global_position = at
	mm.snap_interpolation(mm)
	mm.shield_left = 0.0
	mm.velocity = vel
	var before := get_tree().get_nodes_in_group("wrecks")
	mm.take_damage(1e6, at, vel.normalized(), "", null)
	for w in get_tree().get_nodes_in_group("wrecks"):
		if not before.has(w):
			_sl_track.append({"w": w, "from": at, "d": [], "what": "рывок 50 ед/с" if vel.length() > 20.0 else "бег 8 ед/с"})


func _run_slidetest() -> void:
	if _frame == 5:
		Cfg.creeps_enabled = 0
		for mm in get_tree().get_nodes_in_group("mechs"):
			if mm.team != main.mech.team and _sl_bot == null:
				_sl_bot = mm
	if _frame == 6:
		_sl_kill(_sl_bot, Vector3(0, 0.05, -20), Vector3(50.0, 0, 0))       # убит в рывке
		_sl_kill(main.mech, Vector3(0, 0.05, 20), Vector3(8.0, 0, 0))       # убит на бегу
	for t in _sl_track:
		if is_instance_valid(t["w"]):
			t["d"].append(Vector2(t["w"].global_position.x - t["from"].x, t["w"].global_position.z - t["from"].z).length())
	if _frame == 400:
		for t in _sl_track:
			var d: Array = t["d"]
			var total: float = d[d.size() - 1] * Cfg.METERS_PER_UNIT
			var stop_f := d.size() - 1
			while stop_f > 0 and absf(d[stop_f] - d[stop_f - 1]) < 0.002:
				stop_f -= 1
			var last := 0      # сколько кадров заняли последние 20% пути — плавно ли встал
			for k in range(stop_f, -1, -1):
				if d[k] < d[stop_f] * 0.8:
					break
				last += 1
			var parts: int = t["w"]._parts.size() if is_instance_valid(t["w"]) else -1
			var fast: bool = t["what"].begins_with("рывок")
			var ok: bool = (total > 15.0 and total < 40.0 if fast else total > 2.0 and total < 14.0) and last >= 12 and parts >= 1
			print("[SLIDE] %s: проехал %.1f м за %.2f с, последние 20%% пути — %.2f с, отлетело частей %d — %s" % [t["what"], total,
				stop_f / 60.0, last / 60.0, parts, "ВЕРНО" if ok else "ОШИБКА"])
			if not ok:
				_sl_fails += 1
		print("[SLIDE] итог: %s" % ("ВСЁ ВЕРНО" if _sl_fails == 0 else "ошибок %d" % _sl_fails))
		get_tree().quit()


# ------------------------------------------------------------------
#  Снаряды турелей (--lobtest): ЭМИ-граната турели 2 уровня, потом снаряд осадного орудия турели 3 уровня
#  в стоящего на открытом месте меха. В лог: сколько летел (и сколько летел бы по старой высокой дуге),
#  на сколько поднялся над точкой вылета, где взорвался и что стало с мехом
# ------------------------------------------------------------------

var _lt_lobs := {}       # снаряд -> что о нём известно
var _lt_stage := 0
var _lt_hp := 0.0
var _lt_fails := 0


func _lt_turret(id: String) -> Node3D:
	for s in get_tree().get_nodes_in_group("structures"):
		if s.team != main.mech.team and s.id == id and s.get_meta("lane", "") in ["mid", "base"]:
			return s
	return null


func _run_lobtest() -> void:
	var m = main.mech
	if _frame == 5:
		Cfg.creeps_enabled = 0
		m.shield_left = 0.0
		var t2 := _lt_turret("turret_t2")
		m.global_position = t2.global_position + Vector3(-30, 0.05, 3)
		m.snap_interpolation(m)
		m.demo = {"move": Vector2.ZERO, "fire": false, "aim": t2.global_position}
		t2._emp_cd = 0.0
		_lt_stage = 1
	if _lt_stage == 2:
		_lt_stage = 3
		var t3 := _lt_turret("turret_t3")
		_lt_turret("turret_t2")._emp_cd = 99.0
		m.global_position = t3.global_position + Vector3(-40, 0.05, 3)
		m.snap_interpolation(m)
		m.demo = {"move": Vector2.ZERO, "fire": false, "aim": t3.global_position}
		m.hp = m.max_hp()
		t3._mortar_cd = 0.0
	for l in get_tree().get_nodes_in_group("lobs"):
		var k: int = l.get_instance_id()
		if not _lt_lobs.has(k):
			var to: Vector3 = m.global_position
			to.y = 0.0
			var arc := 3.0 if l._p.get("kind", "") == "emp" else 12.0
			_lt_lobs[k] = {"f": _frame, "from": l.global_position, "top": l.global_position.y, "kind": l._p.get("kind", ""),
				"old": main.mech.Lob.flight_time(l.global_position, to, arc), "pos": l.global_position}
		_lt_lobs[k]["top"] = maxf(_lt_lobs[k]["top"], l.global_position.y)
		_lt_lobs[k]["pos"] = l.global_position
	for k in _lt_lobs.keys():
		if is_instance_id_valid(k) or _lt_lobs[k].get("done", false):
			continue
		var e: Dictionary = _lt_lobs[k]
		e["done"] = true
		var secs: float = (_frame - int(e["f"])) / 60.0
		var dist: float = Vector2(e["pos"].x - e["from"].x, e["pos"].z - e["from"].z).length() * Cfg.METERS_PER_UNIT
		var miss: float = Vector2(e["pos"].x - m.global_position.x, e["pos"].z - m.global_position.z).length() * Cfg.METERS_PER_UNIT
		var rise: float = (float(e["top"]) - e["from"].y) * Cfg.METERS_PER_UNIT
		var emp: bool = e["kind"] == "emp"
		var hit: bool = m.stun_left > 0.0 if emp else m.hp < _lt_hp - 20.0
		print("[LOB] %s: летел %.2f с (по старой дуге было бы %.2f с), %.0f м, поднялся над вылетом на %.1f м, взрыв в %.1f м от меха; %s — %s" % [
			"ЭМИ-граната" if emp else "осадное орудие", secs, e["old"], dist, rise, miss,
			("оглушение %.1f с" % m.stun_left) if emp else ("урон %.0f" % (_lt_hp - m.hp)), "ВЕРНО" if hit and secs < e["old"] else "ОШИБКА"])
		if not (hit and secs < e["old"]):
			_lt_fails += 1
		_lt_stage += 1
	if _frame > 5:
		m.hp = maxf(m.hp, m.max_hp() * 0.5)      # обычные пушки турелей не должны убить меха
	_lt_hp = m.hp
	if _lt_stage >= 4 or _frame > 900:
		print("[LOB] итог: %s" % ("ВСЁ ВЕРНО" if _lt_fails == 0 and _lt_stage >= 4 else "ошибок %d, этап %d" % [_lt_fails, _lt_stage]))
		get_tree().quit()


# ------------------------------------------------------------------
#  Ограничение кадров (--capbench, окно, синхронизация включена, БЕЗ --fixed-fps: с ним Godot предел
#  кадров не применяет; после постановки --targetshot=fight или =ground): драка у турели на той же высоте камеры, предел кадров по очереди — без ограничения,
#  144, 120, 90, 60 (как в «Настройках», через Cfg.set_fps_limit). На каждом 3 с на установку, потом 8 с
#  замер: кадры, время видеокарты на кадр и доля времени, когда она занята. Строки [CAP] со временем
#  часов — по ним сверяется журнал nvidia-smi (мощность и нагрев видеокарты)
# ------------------------------------------------------------------

const CAPS := [0, 144, 120, 90, 60]
var _cap_i := -1
var _cap_t0 := 0
var _cap_last := 0
var _cap_ms: Array = []
var _cap_gpu := 0.0
var _cap_out: Array = []


func _cap_set(i: int) -> void:
	_cap_i = i
	Cfg.set_fps_limit(CAPS[i])
	_cap_t0 = Time.get_ticks_usec()
	_cap_last = _cap_t0
	_cap_ms.clear()
	_cap_gpu = 0.0


func _run_capbench() -> void:
	var vp_rid := get_viewport().get_viewport_rid()
	if _cap_i < 0:
		if _actors.is_empty():
			_stage_fight(main.mech)
			main.cam._started = false
		RenderingServer.viewport_set_measure_render_time(vp_rid, true)
		_cap_set(0)
		return
	var now := Time.get_ticks_usec()
	var secs := (now - _cap_t0) / 1e6
	if secs >= 3.0 and secs < 11.0:
		if _cap_ms.is_empty():
			print("[CAP] %s начало: предел %s (Engine.max_fps=%d, монитор %.0f Гц)" % [Time.get_time_string_from_system(),
				str(CAPS[_cap_i]) if CAPS[_cap_i] > 0 else "нет", Engine.max_fps, DisplayServer.screen_get_refresh_rate()])
		_cap_ms.append((now - _cap_last) / 1000.0)
		_cap_gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp_rid)
	_cap_last = now
	if secs < 11.0 or _cap_ms.is_empty():
		return
	var n := _cap_ms.size()
	var total: float = _cap_ms.reduce(func(acc, x): return acc + x, 0.0)
	var line := "[CAP] %s конец: предел %-4s → %4d кадр/с, видеокарта %.2f мс на кадр, занята %d%% времени" % [
		Time.get_time_string_from_system(), str(CAPS[_cap_i]) if CAPS[_cap_i] > 0 else "нет",
		int(n * 1000.0 / total), _cap_gpu / n, int(_cap_gpu / total * 100.0)]
	print(line)
	_cap_out.append(line)
	if _cap_i + 1 < CAPS.size():
		_cap_set(_cap_i + 1)
		return
	Cfg.set_fps_limit(0)
	print("[CAP] ---- итог (%s, графика %s) ----" % [str(DisplayServer.window_get_size()), Cfg.GFX_NAMES[Cfg.graphics]])
	for l in _cap_out:
		print(l)
	get_tree().quit()


# ------------------------------------------------------------------
#  Появление на другом мехе (--spawntest --drop --enemies=0 --allies=1): союзник стоит на месте, мех
#  игрока сначала садится на него с неба, потом появляется на нём сразу (как телепорт на базу).
#  Никто не должен подпрыгнуть (высота не выше 0,3), и мехи должны разойтись
# ------------------------------------------------------------------

var _sp_bot: Node3D
var _sp_top := [0.0, 0.0]
var _sp_fails := 0
const SP_AT := Vector3(0, 0.05, -20)


func _sp_report(what: String) -> void:
	var m = main.mech
	var d := Vector2(m.global_position.x - _sp_bot.global_position.x, m.global_position.z - _sp_bot.global_position.z).length()
	var ok: bool = _sp_top[0] < 0.3 and _sp_top[1] < 0.3 and d > 2.4
	print("[SPAWN] %s: наибольшая высота — мех %.2f, стоящий %.2f; разошлись на %.1f м — %s" % [
		what, _sp_top[0], _sp_top[1], d * Cfg.METERS_PER_UNIT, "ВЕРНО" if ok else "ОШИБКА"])
	if not ok:
		_sp_fails += 1
	_sp_top = [0.0, 0.0]


func _run_spawntest() -> void:
	var m = main.mech
	if _frame == 3:
		Cfg.creeps_enabled = 0
		for b in main.bots:
			_sp_bot = b
	if _sp_bot == null or _frame < 4:
		return
	if _frame == 4 or _frame == 330:
		_sp_bot.brain = null
		_sp_bot.global_position = SP_AT
		_sp_bot.snap_interpolation(_sp_bot)
		_sp_bot.demo = {"move": Vector2.ZERO, "fire": false, "aim": SP_AT + Vector3(10, 1.5, 0)}
	if _frame == 10:
		m.respawn(SP_AT + Vector3(0.0, 0, 0.0))                 # с неба прямо на союзника
	if _frame == 340:
		m.respawn(SP_AT + Vector3(0.0, 0, 0.01), false)         # сразу в нём, как телепорт на базу
	m.demo = {"move": Vector2.ZERO, "fire": false, "aim": SP_AT + Vector3(10, 1.5, 0)}
	if _frame > 10:
		if not m.is_landing():
			_sp_top[0] = maxf(_sp_top[0], m.global_position.y)
		_sp_top[1] = maxf(_sp_top[1], _sp_bot.global_position.y)
	if _frame == 320:
		_sp_report("сел с неба на стоящего меха")
	if _frame == 520:
		_sp_report("появился прямо в стоящем мехе")
		print("[SPAWN] итог: %s" % ("ВСЁ ВЕРНО" if _sp_fails == 0 else "ошибок %d" % _sp_fails))
		get_tree().quit()


# ------------------------------------------------------------------
#  Разрушаемая мелочь (--proptest, карта classic): мех идёт прямо на кучку ящиков и проходит сквозь неё,
#  кучка ломается; для ботов на её месте проход свободен; вторую кучку ломает взрыв
# ------------------------------------------------------------------

var _pt_fails := 0


func _pt_prop(at: Vector3) -> Node3D:
	var best: Node3D = null
	for p in get_tree().get_nodes_in_group("props"):
		if best == null or p.global_position.distance_to(at) < best.global_position.distance_to(at):
			best = p
	return best


func _pt_kind(k: String, at: Vector3) -> Node3D:
	var best: Node3D = null
	for p in get_tree().get_nodes_in_group("props"):
		if p.kind == k and (best == null or p.global_position.distance_to(at) < best.global_position.distance_to(at)):
			best = p
	return best


func _pt_check(ok: bool, what: String) -> void:
	print("[PROP] %s — %s" % [what, "ВЕРНО" if ok else "ОШИБКА"])
	if not ok:
		_pt_fails += 1


func _run_proptest() -> void:
	var m = main.mech
	var a := Vector3(-62, 0, -16)
	var b := Vector3(-62, 0, 16)
	if _frame == 5:
		Cfg.creeps_enabled = 0
		var kinds := {}
		for x in get_tree().get_nodes_in_group("props"):
			kinds[x.kind] = kinds.get(x.kind, 0) + 1
		print("[PROP] мелочи на карте: %s" % str(kinds))
		_pt_check(main.nav.is_free(a), "на месте кучки ящиков боты проходят (карта проходимости)")
		m.global_position = a + Vector3(-8, 0.05, 0)
		m.snap_interpolation(m)
	if _frame >= 5 and _frame < 150:
		m.demo = {"move": Vector2(1, 0), "fire": false, "aim": a + Vector3(20, 1.5, 0)}
	if _frame == 150:
		m.demo = {"move": Vector2.ZERO, "fire": false, "aim": a + Vector3(20, 1.5, 0)}
		_pt_check(m.global_position.x > a.x + 4.0, "мех прошёл сквозь кучку (x %.1f, кучка на %.0f)" % [m.global_position.x, a.x])
		_pt_check(_pt_prop(a).broken, "кучка, через которую прошёл мех, сломана")
		_pt_check(not _pt_prop(b).broken, "другая кучка цела")
		Fx.blast(b + Vector3(2.5, 0.5, 0), 3.0, 10.0, 0.5, 1, null)
	if _frame == 152:
		_pt_check(_pt_prop(b).broken, "взрыв рядом ломает кучку")
		# столбик-фонарь: мех идёт на него — столб падает
		var posts := get_tree().get_nodes_in_group("props").filter(func(x) -> bool: return x.kind == "post")
		if not posts.is_empty():
			var pst: Node3D = posts[0]
			set_meta("post", pst)
			m.global_position = pst.global_position + Vector3(0, 0.05, 6)
			m.snap_interpolation(m)
			m.demo = {"move": Vector2(0, -1), "fire": false, "aim": pst.global_position + Vector3(0, 1.5, -10)}
	# бетонные блоки и забор: мех идёт на них; мешки перед турелью — взрыв рядом
	if _frame == 310:
		var jer := _pt_kind("jersey", Vector3(-50, 0, 9))
		set_meta("jer", jer)
		m.global_position = jer.global_position + Vector3(0, 0.05, 6)
		m.snap_interpolation(m)
		m.demo = {"move": Vector2(0, -1), "fire": false, "aim": jer.global_position + Vector3(0, 1.5, -10)}
		var bags := _pt_kind("sandbags", Vector3(-45, 0, 0))
		set_meta("bags", bags)
		Fx.blast(bags.global_position + Vector3(4.4, 0.5, 0), 2.0, 10.0, 0.5, 1, null)
	if _frame == 420:
		var fen := _pt_kind("fence", Vector3(-13, 0, -55))
		set_meta("fen", fen)
		m.global_position = fen.global_position + Vector3(-6, 0.05, 1)
		m.snap_interpolation(m)
		m.demo = {"move": Vector2(1, 0), "fire": false, "aim": fen.global_position + Vector3(10, 1.5, 0)}
	if _frame == 560:
		_pt_check(get_meta("jer").broken, "мех упёрся в бетонные блоки — сдвинул и завалил")
		_pt_check(get_meta("bags").broken, "взрыв у мешков с песком перед турелью — разлетелись")
		var fen2: Node3D = get_meta("fen")
		var tilt := rad_to_deg(acos(clampf(fen2._pivot.global_basis.y.normalized().dot(Vector3.UP), -1.0, 1.0)))
		_pt_check(fen2.broken and tilt > 70.0, "мех прошёл через забор — упал плашмя (наклон %.0f°)" % tilt)
		m.demo = {"move": Vector2.ZERO, "fire": false, "aim": m.global_position + Vector3(10, 1.5, 0)}
	if _frame == 300 and has_meta("post"):
		var pst2: Node3D = get_meta("post")
		var tilt := rad_to_deg(acos(clampf(pst2._pivot.global_basis.y.normalized().dot(Vector3.UP), -1.0, 1.0)))
		_pt_check(pst2.broken and tilt > 70.0, "мех задел фонарь — столб упал (наклон %.0f°)" % tilt)
		m.demo = {"move": Vector2.ZERO, "fire": false, "aim": m.global_position + Vector3(10, 1.5, 0)}
	if _frame == 640:
		var left := 0
		for n in get_tree().current_scene.get_children():
			if n is MeshInstance3D and n.physics_interpolation_mode == Node.PHYSICS_INTERPOLATION_MODE_OFF and n.material_override == _pt_prop(a)._mat:
				left += 1
		_pt_check(left == 0, "куски ушли в землю через несколько секунд (осталось %d)" % left)
		print("[PROP] итог: %s" % ("ВСЁ ВЕРНО" if _pt_fails == 0 else "ошибок %d" % _pt_fails))
		get_tree().quit()


# ------------------------------------------------------------------
#  Таймер у курсора (--cdtest): рывок на перезарядке — рядом с курсором оставшееся время «2,35»,
#  оно идёт вниз и тает за секунду
# ------------------------------------------------------------------

func _run_cdtest() -> void:
	var m = main.mech
	var hud = main.hud
	if _frame == 5:
		m.demo = {"move": Vector2.ZERO, "fire": false, "aim": m.global_position + Vector3(10, 1.5, 0)}
		m.dash_stock = 0.0
		m.dash_cd = 2.35
	if _frame == 6:
		m.demo["dash"] = true
	if _frame == 10:
		set_meta("t0", hud._cd_tip.text if hud._cd_tip != null else "")
		set_meta("vis0", hud._cd_tip != null and hud._cd_tip.visible)
	if _frame == 40:
		set_meta("t1", hud._cd_tip.text if hud._cd_tip != null else "")
		set_meta("a1", hud._cd_tip.modulate.a if hud._cd_tip != null else -1.0)
	if _frame == 80:
		var ok: bool = get_meta("vis0") and str(get_meta("t0")).begins_with("2,") and str(get_meta("t1")) < str(get_meta("t0")) 			and float(get_meta("a1")) < 0.8 and hud._cd_tip != null and not hud._cd_tip.visible
		print("[CD] у курсора «%s», через полсекунды «%s» (прозрачность %.2f), через секунду скрыт: %s — %s" % [get_meta("t0"), get_meta("t1"),
			float(get_meta("a1")), not hud._cd_tip.visible if hud._cd_tip != null else false, "ВЕРНО" if ok else "ОШИБКА"])
		get_tree().quit()
