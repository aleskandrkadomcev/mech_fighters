extends CanvasLayer
## Меню во время боя (Esc) и таблица после боя.
## Пауза: продолжить, ангар, настройки, заново, в редактор (если бой из редактора), в главное меню, выход.
## После боя: кто победил, сколько длился бой, и по каждому меху: убийства, смерти, урон, постройки, крипы.

var main: Node
var _pause: Control
var _results: Control
var _table: GridContainer
var _title: Label
var _sub: Label


func _ready() -> void:
	layer = 11
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_pause()
	_build_results()


func is_open() -> bool:
	return _pause.visible or _results.visible


func toggle_pause() -> void:
	if _results.visible:
		return
	_pause.visible = not _pause.visible
	get_tree().paused = _pause.visible


func _unhandled_input(event: InputEvent) -> void:
	if _pause.visible and event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
		toggle_pause()
		get_viewport().set_input_as_handled()


static func panel_style(alpha := 0.95) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.07, 0.09, alpha)
	sb.set_border_width_all(1)
	sb.border_color = Color(1, 1, 1, 0.18)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(24)
	return sb


static func big_button(text: String, w := 320.0) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(w, 54)
	b.add_theme_font_size_override("font_size", 22)
	return b


func _dim() -> ColorRect:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	return dim


func _build_pause() -> void:
	_pause = _dim()
	_pause.visible = false
	add_child(_pause)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause.add_child(center)
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", panel_style())
	center.add_child(pc)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	pc.add_child(col)
	var t := Label.new()
	t.text = "ПАУЗА"
	t.add_theme_font_size_override("font_size", 36)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(t)
	var items := [
		["Продолжить", func() -> void: toggle_pause()],
		["Ангар (B)", func() -> void:
			toggle_pause()
			if main.winner < 0:
				main.hangar.open(main.mech.build)],
		["Настройки (F2)", func() -> void: Cfg.panel.toggle()],     # пауза остаётся
		["Начать заново", func() -> void: main.restart()],
	]
	if Maps.from_editor:
		items.append(["Вернуться в редактор", func() -> void: main.to_editor()])
	items.append(["В главное меню", func() -> void: main.to_menu()])
	items.append(["Выйти из игры", func() -> void: get_tree().quit()])
	for it in items:
		var b := big_button(it[0])
		b.pressed.connect(it[1])
		col.add_child(b)


func _build_results() -> void:
	_results = _dim()
	_results.color = Color(0, 0, 0, 0.7)
	_results.visible = false
	add_child(_results)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_results.add_child(center)
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", panel_style(0.97))
	pc.custom_minimum_size = Vector2(1280, 0)
	center.add_child(pc)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	pc.add_child(col)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 56)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_title)
	_sub = Label.new()
	_sub.add_theme_font_size_override("font_size", 20)
	_sub.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_sub)
	_table = GridContainer.new()
	_table.columns = 8
	_table.add_theme_constant_override("h_separation", 26)
	_table.add_theme_constant_override("v_separation", 8)
	col.add_child(_table)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 16)
	col.add_child(buttons)
	var again := big_button("Ещё раз", 240)
	again.pressed.connect(func() -> void: main.restart())
	buttons.add_child(again)
	if Maps.from_editor:
		var ed := big_button("В редактор", 240)
		ed.pressed.connect(func() -> void: main.to_editor())
		buttons.add_child(ed)
	var menu_b := big_button("В меню", 240)
	menu_b.pressed.connect(func() -> void: main.to_menu())
	buttons.add_child(menu_b)


func _cell(text: String, size := 19, col := Color(1, 1, 1, 0.9), align := HORIZONTAL_ALIGNMENT_RIGHT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.horizontal_alignment = align
	return l


func show_results(won: bool, draw := false) -> void:
	_pause.visible = false
	_results.visible = true
	_title.text = "НИЧЬЯ" if draw else ("ПОБЕДА" if won else "ПОРАЖЕНИЕ")
	_title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4) if draw else (Color(0.5, 1.0, 0.5) if won else Color(1.0, 0.4, 0.35)))
	_sub.text = "Карта «%s»   ·   бой длился %s" % [main.map.get("name", ""), Battle.time_text()]
	# PvP: счёт команд, а в таблице только мехи (построек и крипов там нет)
	var pvp: bool = main.pvp
	if pvp:
		_sub.text = "Карта «%s»   ·   счёт %d : %d   ·   бой длился %s" % [main.map.get("name", ""), main.team_kills[0], main.team_kills[1], Battle.time_text()]
	for c in _table.get_children():
		c.queue_free()
	var heads := ["", "Мех", "Убийства", "Смерти", "Урон по мехам"]
	if not pvp:
		heads += ["Урон постройкам", "Крипы", "Турели"]
	_table.columns = heads.size()
	for i in heads.size():
		_table.add_child(_cell(heads[i], 16, Color(1, 1, 1, 0.5), HORIZONTAL_ALIGNMENT_LEFT if i < 2 else HORIZONTAL_ALIGNMENT_RIGHT))
	for team in 2:
		var rows: Array = []
		for id in Battle.rows:
			if Battle.rows[id]["team"] == team:
				rows.append(Battle.rows[id])
		if pvp:
			rows.sort_custom(func(a, b) -> bool: return a["kills"] > b["kills"] or (a["kills"] == b["kills"] and a["damage"] > b["damage"]))
		else:
			rows.sort_custom(func(a, b) -> bool: return a["damage"] + a["structures"] * 0.3 > b["damage"] + b["structures"] * 0.3)
		var tc := Cfg.player_color if team == 0 else Cfg.enemy_color
		_table.add_child(_cell("СВОИ" if team == 0 else "ВРАГИ", 18, tc, HORIZONTAL_ALIGNMENT_LEFT))
		for k in heads.size() - 1:
			_table.add_child(Control.new())
		for r in rows:
			var c := Color(1.0, 0.9, 0.5) if r["player"] else Color(1, 1, 1, 0.9)
			_table.add_child(_cell(r["name"], 20, c, HORIZONTAL_ALIGNMENT_LEFT))
			_table.add_child(_cell(r["mech"], 18, Color(1, 1, 1, 0.65), HORIZONTAL_ALIGNMENT_LEFT))
			_table.add_child(_cell(str(r["kills"]), 20, c))
			_table.add_child(_cell(str(r["deaths"]), 20, c))
			_table.add_child(_cell(str(int(r["damage"])), 20, c))
			if not pvp:
				_table.add_child(_cell(str(int(r["structures"])), 20, c))
				_table.add_child(_cell(str(r["creeps"]), 20, c))
				_table.add_child(_cell(str(r["towers"]), 20, c))
