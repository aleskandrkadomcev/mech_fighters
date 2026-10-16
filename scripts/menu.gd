extends Control
## Главное меню: Играть (режим: моба или PvP, выбор карты и ботов), Редактор карт, Настройки, Выход.
## На фоне мех на платформе. При автопроверке (особые параметры запуска) сразу открывает бой.

const MechVisual := preload("res://scripts/mech_visual.gd")
const GameMenu := preload("res://scripts/game_menu.gd")
const WorldShader := preload("res://shaders/world.gdshader")

var _play: Control
var _settings: Control
var _maps: ItemList
var _map_info: Label
var _map_list: Array = []
var _pvp := false                 # выбран режим PvP (мехи против мехов): в списке только карты для PvP
var _mode_btns: Array = []
var _creeps_check: CheckBox
var _preview: Node3D
var _cam: Camera3D
var _angle := 0.4


func _ready() -> void:
	if not OS.get_cmdline_user_args().is_empty():
		# автопроверка: сразу в бой (или в редактор)
		var to := "res://editor.tscn" if OS.get_cmdline_user_args().has("--editortest") else "res://main.tscn"
		get_tree().change_scene_to_file.call_deferred(to)
		return
	get_tree().paused = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_background()
	_build_main()
	_build_play()
	_build_settings()


# ------------------------------------------------------------------
#  Фон: мех на платформе, камера медленно облетает
# ------------------------------------------------------------------

func _build_background() -> void:
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(svc)
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	svc.add_child(vp)
	var root := Node3D.new()
	root.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	vp.add_child(root)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.035, 0.045)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.45, 0.5, 0.62)
	env.ambient_light_energy = 0.4
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.fog_enabled = true
	env.fog_light_color = Color(0.04, 0.05, 0.07)
	env.fog_density = 0.04
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, 40, 0)
	key.light_energy = 1.3
	key.shadow_enabled = true
	root.add_child(key)
	var rim := OmniLight3D.new()
	rim.position = Vector3(-4, 4, -5)
	rim.light_color = Cfg.player_color
	rim.light_energy = 7.0
	rim.omni_range = 16.0
	root.add_child(rim)
	var fl := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(80, 80)
	fl.mesh = pm
	var fm := ShaderMaterial.new()
	fm.shader = WorldShader
	fm.set_shader_parameter("albedo", Color(0.2, 0.21, 0.23))
	fm.set_shader_parameter("mode", 2)
	fm.set_shader_parameter("roughness", 0.4)
	fm.set_shader_parameter("metallic", 0.5)
	fl.material_override = fm
	root.add_child(fl)
	_preview = MechVisual.new()
	var b := Parts.player_build
	var r := Parts.compute(b)
	_preview.st = r["stats"]
	root.add_child(_preview)
	_preview.build(Cfg.mech_accent, Color(1, 1, 1), {"legs_scale": r["stats"]["legs_scale"], "hull_scale": r["stats"]["hull_scale"],
		"style": r["stats"]["style"], "model": r["stats"].get("model", ""), "weapons": [r["weapons"][0]["look"], r["weapons"][1]["look"]],
		"rockets": r["abilities"].any(func(a): return a["type"] == "rockets")})
	_cam = Camera3D.new()
	_cam.fov = 38.0
	root.add_child(_cam)


func _process(delta: float) -> void:
	if _preview == null:
		return
	var t := Time.get_ticks_msec() * 0.001
	# мех смотрит в сторону камеры (вперёд у меха -Z, поэтому +PI)
	_preview.update_visual(delta, Vector3.ZERO, Vector3.ZERO, PI - 0.6, PI - 0.6 + sin(t * 0.5) * 0.4, false)
	# камера стоит, мех справа от кнопок, лёгкое покачивание
	_cam.position = Vector3(-8.0 + sin(t * 0.15) * 0.8, 5.0, 14.0)
	_cam.look_at(Vector3(-6.5, 2.2, 0), Vector3.UP)


# ------------------------------------------------------------------
#  Кнопки
# ------------------------------------------------------------------

func _build_main() -> void:
	var col := VBoxContainer.new()
	col.position = Vector2(110, 180)
	col.add_theme_constant_override("separation", 16)
	add_child(col)
	var t := Label.new()
	t.text = "MECH FIGHTERS"
	t.add_theme_font_size_override("font_size", 76)
	t.add_theme_color_override("font_color", Color(1.0, 0.75, 0.4))
	t.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	t.add_theme_constant_override("outline_size", 10)
	col.add_child(t)
	var sub := Label.new()
	sub.text = "моба на мехах"
	sub.add_theme_font_size_override("font_size", 24)
	sub.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	col.add_child(sub)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 40)
	col.add_child(gap)
	for it in [["Играть", _open_play], ["Редактор карт", _open_editor], ["Настройки", _open_settings], ["Выход", func() -> void: get_tree().quit()]]:
		var b := GameMenu.big_button(it[0], 360)
		b.pressed.connect(it[1])
		col.add_child(b)


func _panel_box(pos: Vector2, size: Vector2) -> VBoxContainer:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", GameMenu.panel_style(0.93))
	pc.position = pos
	pc.size = size
	pc.custom_minimum_size = size
	pc.visible = false
	add_child(pc)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	pc.add_child(col)
	return col


func _title(parent: Control, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 30)
	parent.add_child(l)


func _build_play() -> void:
	var col := _panel_box(Vector2(720, 160), Vector2(760, 700))
	_play = col.get_parent()
	_title(col, "ИГРАТЬ")
	_mode_row(col)
	var l := Label.new()
	l.text = "Карта"
	l.add_theme_font_size_override("font_size", 18)
	l.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	col.add_child(l)
	_maps = ItemList.new()
	_maps.custom_minimum_size = Vector2(0, 280)
	_maps.add_theme_font_size_override("font_size", 20)
	_maps.item_selected.connect(_on_map_selected)
	col.add_child(_maps)
	_map_info = Label.new()
	_map_info.add_theme_font_size_override("font_size", 17)
	_map_info.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	_map_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_map_info)
	_slider_row(col, "Союзных ботов", "bot_allies", 0, 4)
	_slider_row(col, "Вражеских ботов", "bot_enemies", 0, 5)
	_creeps_check = _check_row(col, "Крипы на линиях", "creeps_enabled")
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 12)
	col.add_child(row)
	var back := GameMenu.big_button("Назад", 180)
	back.pressed.connect(func() -> void: _play.visible = false)
	row.add_child(back)
	var go := GameMenu.big_button("К АНГАРУ  ▶", 260)
	go.pressed.connect(_start)
	row.add_child(go)


func _slider_row(parent: Control, text: String, key: String, vmin: float, vmax: float) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)
	var l := Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(240, 0)
	l.add_theme_font_size_override("font_size", 19)
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = vmin
	s.max_value = vmax
	s.step = 1 if vmax > 1.5 else 0.05
	s.value = float(Cfg.get(key))
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.focus_mode = Control.FOCUS_NONE
	row.add_child(s)
	var v := Label.new()
	v.custom_minimum_size = Vector2(60, 0)
	v.add_theme_font_size_override("font_size", 19)
	v.text = Parts._n(snappedf(s.value, 0.01))
	row.add_child(v)
	s.value_changed.connect(func(x: float) -> void:
		Cfg.set_value(key, x)
		v.text = Parts._n(snappedf(x, 0.01)))


func _check_row(parent: Control, text: String, key: String) -> CheckBox:
	var c := CheckBox.new()
	c.text = text
	c.add_theme_font_size_override("font_size", 19)
	c.button_pressed = int(Cfg.get(key)) == 1
	c.focus_mode = Control.FOCUS_NONE
	c.toggled.connect(func(on: bool) -> void: Cfg.set_value(key, 1.0 if on else 0.0))
	parent.add_child(c)
	return c


# режим боя: две кнопки, нажата одна. От режима зависит список карт
func _mode_row(parent: Control) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)
	var l := Label.new()
	l.text = "Режим"
	l.custom_minimum_size = Vector2(120, 0)
	l.add_theme_font_size_override("font_size", 19)
	row.add_child(l)
	var group := ButtonGroup.new()
	for q in 2:
		var b := Button.new()
		b.text = ["Моба: базы, турели, крипы", "PvP: мехи против мехов"][q]
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(280, 44)
		b.add_theme_font_size_override("font_size", 19)
		b.pressed.connect(func() -> void: _set_mode(q == 1))
		row.add_child(b)
		_mode_btns.append(b)


func _set_mode(pvp: bool) -> void:
	_pvp = pvp
	for q in _mode_btns.size():
		_mode_btns[q].set_pressed_no_signal(q == (1 if pvp else 0))
	_creeps_check.visible = not pvp       # в PvP крипов нет
	_fill_maps()


func _build_settings() -> void:
	var col := _panel_box(Vector2(720, 160), Vector2(760, 640))
	_settings = col.get_parent()
	_title(col, "НАСТРОЙКИ")
	_graphics_row(col)
	_fps_row(col)
	_slider_row(col, "Громкость", "sound_volume", 0, 1)
	_slider_row(col, "Тряска камеры", "shake", 0, 3)
	_slider_row(col, "Темнота тумана", "fog_darkness", 0, 1)
	_check_row(col, "Цифры урона", "damage_numbers")
	_check_row(col, "Две одинаковые пушки — обе на ЛКМ (по очереди, рельсы залпом)", "link_guns")
	var note := Label.new()
	note.text = "Все остальные числа игры (мехи, оружие, турели, крипы, боты) — на F2 (в меню, в бою и на паузе)."
	note.add_theme_font_size_override("font_size", 16)
	note.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(note)
	var back := GameMenu.big_button("Назад", 180)
	back.pressed.connect(func() -> void: _settings.visible = false)
	col.add_child(back)


# графика: три кнопки, нажата одна. Сохраняется сразу, в бою применяется со следующего боя
func _graphics_row(parent: Control) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)
	var l := Label.new()
	l.text = "Графика"
	l.custom_minimum_size = Vector2(240, 0)
	l.add_theme_font_size_override("font_size", 19)
	row.add_child(l)
	var group := ButtonGroup.new()
	for q in 3:
		var b := Button.new()
		b.text = Cfg.GFX_NAMES[q]
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = Cfg.graphics == q
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(140, 44)
		b.add_theme_font_size_override("font_size", 19)
		b.pressed.connect(func() -> void: Cfg.set_graphics(q))
		row.add_child(b)
	var note := Label.new()
	note.text = "Низкие — для слабых видеокарт: меньше травы, проще земля, тени и свет. Меняется со следующего боя."
	note.add_theme_font_size_override("font_size", 15)
	note.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(note)


# ограничение кадров: пять кнопок, нажата одна. Сохраняется и применяется сразу
func _fps_row(parent: Control) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)
	var l := Label.new()
	l.text = "Ограничение кадров"
	l.custom_minimum_size = Vector2(240, 0)
	l.add_theme_font_size_override("font_size", 19)
	row.add_child(l)
	var group := ButtonGroup.new()
	for fps in Cfg.FPS_LIMITS:
		var b := Button.new()
		b.text = str(fps) if fps > 0 else "Нет"
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = Cfg.fps_limit == fps
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(76, 44)
		b.add_theme_font_size_override("font_size", 19)
		b.pressed.connect(func() -> void: Cfg.set_fps_limit(fps))
		row.add_child(b)
	var note := Label.new()
	note.text = "Меньше кадров — меньше греется видеокарта. Выше частоты монитора игра всё равно не покажет."
	note.add_theme_font_size_override("font_size", 15)
	note.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(note)


func _open_play() -> void:
	_settings.visible = false
	_play.visible = true
	# режим как у карты, на которой играли в прошлый раз
	_set_mode(Maps.is_pvp(Maps.load_map(Maps.selected)))


# список карт выбранного режима
func _fill_maps() -> void:
	_maps.clear()
	_map_list = Maps.list_maps().filter(func(m) -> bool: return m["pvp"] == _pvp)
	var sel := 0
	for i in _map_list.size():
		_maps.add_item(_map_list[i]["name"])
		if _map_list[i]["path"] == Maps.selected:
			sel = i
	if not _map_list.is_empty():
		_maps.select(sel)
		_on_map_selected(sel)
	else:
		_map_info.text = "Нет карт для этого режима"


func _on_map_selected(i: int) -> void:
	var d := Maps.load_map(_map_list[i]["path"])
	var lanes := Maps.lanes(d)
	var problems := Maps.problems(d)
	if Maps.is_pvp(d):
		_map_info.text = "%d × %d м   ·   стен и укрытий: %d   ·   победа: %d убийств или больше всех за %s мин" % [int(d["size"][0]), int(d["size"][1]),
			d["covers"].size(), Cfg.pvp_kills_to_win, Parts._n(Cfg.pvp_time)]
	else:
		_map_info.text = "%d × %d м   ·   линий: %d   ·   турелей: %d   ·   стен и укрытий: %d" % [int(d["size"][0]), int(d["size"][1]),
			lanes.size(), d["structures"].filter(func(s) -> bool: return s[0] != "hq").size(), d["covers"].size()]
	if not problems.is_empty():
		_map_info.text += "\nНельзя играть: " + ", ".join(problems)


func _open_settings() -> void:
	_play.visible = false
	_settings.visible = true


func _open_editor() -> void:
	Maps.editor_path = ""
	get_tree().change_scene_to_file("res://editor.tscn")


func _start() -> void:
	var sel := _maps.get_selected_items()
	if sel.is_empty():
		return
	var path: String = _map_list[sel[0]]["path"]
	if not Maps.problems(Maps.load_map(path)).is_empty():
		return
	Maps.selected = path
	Maps.from_editor = false
	get_tree().change_scene_to_file("res://main.tscn")
