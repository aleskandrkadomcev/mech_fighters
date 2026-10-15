extends Node3D
## Редактор карт. Вид строго сверху. Слева инструменты (что ставить), справа свойства.
##   ЛКМ        поставить выбранное / выбрать и тащить (инструмент «Выбор»)
##   ПКМ        удалить то, что под курсором
##   R          повернуть стену (поменять длину и толщину местами)
##   Delete     удалить выбранное
##   Ctrl+Z     отменить          Ctrl+S  сохранить
##   WASD / стрелки / зажатое колесо  двигать камеру, колесо  приблизить
## Зеркало: всё, что ставишь, сразу появляется и на другой половине (постройки достаются другой команде).
## Линии для крипов и ботов строятся сами: от штаба через турели линии (и точки линии) к вражескому штабу.
## Их видно цветными линиями поверх карты.

const GameMenu := preload("res://scripts/game_menu.gd")

const TOOLS := [
	["Укрытия", [["wall", "Стена (разрушаемая)"], ["barrier", "Барьер (разрушаемый)"], ["rock", "Скала"]]],
	["Постройки", [["hq", "Штаб"], ["turret_t1", "Турель 1"], ["turret_t2", "Турель 2 (ЭМИ)"], ["turret_t3", "Турель 3 (осадная)"]]],
	["Точки", [["poi_regen", "Реактор"], ["poi_damage", "Арсенал"], ["poi_radar", "Радар"], ["poi_dock", "Ремонтный док"], ["crate", "Место ящика"], ["lanepoint", "Точка линии"]]],
	["Украшения", [["decor_container", "Контейнер"], ["decor_generator", "Генератор"], ["decor_tank", "Цистерна"],
		["decor_terminal", "Терминал"], ["decor_crates", "Ящики"], ["decor_antenna", "Антенна"], ["lamp", "Фонарь"], ["target", "Мишень"]]],
	["Инструменты", [["select", "Выбор и перенос"], ["erase", "Ластик"]]],
]
const DECOR_SIZE := {"container": Vector2(2.6, 6.2), "generator": Vector2(3.4, 2.4), "tank": Vector2(3.6, 3.6),
	"terminal": Vector2(1.6, 1.2), "crates": Vector2(3.2, 2.6), "antenna": Vector2(2.2, 2.2)}
const LANE_COLORS := {"top": Color(0.4, 0.8, 1.0), "mid": Color(1.0, 0.85, 0.3), "bot": Color(0.6, 1.0, 0.45), "base": Color(0.8, 0.8, 0.8)}
const TEAM_COLORS := [Color(1.0, 0.55, 0.15), Color(0.95, 0.2, 0.2)]

var data := {}
var file_path := ""               # куда сохранять (пусто = ещё не сохранена)
var tool := "wall"
var team := 0
var lane := "mid"
var mirror := 2                   # 0 нет, 1 слева-направо, 2 поворот вокруг центра, 3 сверху-вниз
var grid := 1.0
var dims := {"wall": Vector3(20, 4, 4), "barrier": Vector3(8, 3.5, 1.6), "rock": Vector3(6, 4.5, 6)}
var dirty := false

var _cam: Camera3D
var _zoom := 160.0
var _ground: MeshInstance3D
var _ground_mat: ShaderMaterial
var _objects: Node3D
var _lanes_mesh: MeshInstance3D
var _ghost: MeshInstance3D
var _sel = null                   # [список, номер]
var _drag := false
var _drag_twin = null
var _drag_off := Vector3.ZERO
var _pan_drag := false
var _undo: Array = []
var _mouse_world := Vector3.ZERO

var _ui: CanvasLayer
var _tool_buttons := {}
var _status: Label
var _name_edit: LineEdit
var _w_spin: SpinBox
var _d_spin: SpinBox
var _dim_spins: Array = []
var _sel_label: Label
var _team_opt: OptionButton
var _lane_opt: OptionButton
var _dialog: Control


func _ready() -> void:
	get_tree().paused = false
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_build_scene()
	_build_ui()
	if Maps.editor_path != "" and FileAccess.file_exists(Maps.editor_path):
		data = Maps.load_map(Maps.editor_path)
		file_path = Maps.get_meta("editor_file", "") if Maps.has_meta("editor_file") else ""
		dirty = Maps.get_meta("editor_dirty", false) if Maps.has_meta("editor_dirty") else false
	else:
		_new_map(160, 160, "Новая карта")
	_after_load()
	if OS.get_cmdline_user_args().has("--editortest"):
		_selftest.call_deferred()


# ------------------------------------------------------------------
#  Сцена: камера сверху, земля с сеткой
# ------------------------------------------------------------------

func _build_scene() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.055, 0.065)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-60, 30, 0)
	sun.light_energy = 0.8
	add_child(sun)
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.rotation_degrees = Vector3(-90, 0, 0)
	_cam.position = Vector3(0, 100, 0)
	_cam.far = 400.0
	add_child(_cam)
	_ground = MeshInstance3D.new()
	_ground.mesh = PlaneMesh.new()
	var sh := Shader.new()
	sh.code = """shader_type spatial;
render_mode unshaded;
uniform vec2 size = vec2(160.0, 160.0);
uniform float step_m = 2.0;
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
float line(float v, float s, float w) {
	float f = abs(fract(v / s + 0.5) - 0.5) * s;
	return 1.0 - smoothstep(0.0, w, f);
}
void fragment() {
	vec2 p = wpos.xz;
	vec3 col = vec3(0.13, 0.17, 0.11);
	float g = max(line(p.x, step_m, 0.06), line(p.y, step_m, 0.06)) * 0.25;
	float g2 = max(line(p.x, 10.0, 0.12), line(p.y, 10.0, 0.12)) * 0.45;
	float c = max(line(p.x, 1000.0, 0.25), line(p.y, 1000.0, 0.25));
	col += vec3(max(g, g2)) * 0.35;
	col = mix(col, vec3(0.6, 0.6, 0.65), c * 0.6);
	vec2 inside = step(abs(p), size * 0.5);
	col *= mix(0.35, 1.0, inside.x * inside.y);
	ALBEDO = col;
}
"""
	_ground_mat = ShaderMaterial.new()
	_ground_mat.shader = sh
	_ground.material_override = _ground_mat
	add_child(_ground)
	_objects = Node3D.new()
	add_child(_objects)
	_lanes_mesh = MeshInstance3D.new()
	_lanes_mesh.mesh = ImmediateMesh.new()
	var lm := StandardMaterial3D.new()
	lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lm.vertex_color_use_as_albedo = true
	lm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	lm.no_depth_test = true
	lm.cull_mode = BaseMaterial3D.CULL_DISABLED
	lm.render_priority = 5
	_lanes_mesh.material_override = lm
	add_child(_lanes_mesh)
	_ghost = MeshInstance3D.new()
	add_child(_ghost)


# ------------------------------------------------------------------
#  Интерфейс
# ------------------------------------------------------------------

func _lbl(text: String, size := 17, alpha := 0.9) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color(1, 1, 1, alpha))
	return l


func _btn(text: String, cb: Callable, w := 0.0) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 17)
	if w > 0.0:
		b.custom_minimum_size = Vector2(w, 0)
	b.pressed.connect(cb)
	return b


func _panel(anchor_right: bool, top: float, width: float) -> VBoxContainer:
	var pc := PanelContainer.new()
	var sb := GameMenu.panel_style(0.92)
	sb.set_content_margin_all(12)
	pc.add_theme_stylebox_override("panel", sb)
	pc.anchor_top = 0.0
	pc.anchor_bottom = 1.0
	pc.offset_top = top
	pc.offset_bottom = -12
	if anchor_right:
		pc.anchor_left = 1.0
		pc.anchor_right = 1.0
		pc.offset_left = -width - 12
		pc.offset_right = -12
	else:
		pc.offset_left = 12
		pc.offset_right = 12 + width
	_ui.add_child(pc)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pc.add_child(scroll)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 6)
	scroll.add_child(col)
	return col


func _spin(vmin: float, vmax: float, step: float, val: float, cb: Callable) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = vmin
	s.max_value = vmax
	s.step = step
	s.value = val
	s.custom_minimum_size = Vector2(110, 0)
	s.value_changed.connect(cb)
	s.get_line_edit().add_theme_font_size_override("font_size", 16)
	return s


func _build_ui() -> void:
	_ui = CanvasLayer.new()
	add_child(_ui)
	# верхняя полоса
	var top := PanelContainer.new()
	var sb := GameMenu.panel_style(0.92)
	sb.set_content_margin_all(8)
	top.add_theme_stylebox_override("panel", sb)
	top.anchor_right = 1.0
	top.offset_left = 12
	top.offset_right = -12
	top.offset_top = 12
	top.offset_bottom = 62
	_ui.add_child(top)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	top.add_child(bar)
	bar.add_child(_lbl("РЕДАКТОР КАРТ", 20))
	bar.add_child(_btn("Новая", _ask_new))
	bar.add_child(_btn("Открыть", _ask_open))
	bar.add_child(_btn("Сохранить", _save))
	bar.add_child(_btn("Сохранить как", _ask_save_as))
	bar.add_child(_btn("▶ Играть", _play))
	bar.add_child(_btn("Отменить", _undo_step))
	bar.add_child(_lbl("   Название:", 17, 0.6))
	_name_edit = LineEdit.new()
	_name_edit.custom_minimum_size = Vector2(240, 0)
	_name_edit.add_theme_font_size_override("font_size", 17)
	_name_edit.text_changed.connect(func(t: String) -> void:
		data["name"] = t
		dirty = true
		_update_status())
	bar.add_child(_name_edit)
	_status = _lbl("", 16, 0.65)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bar.add_child(_status)
	bar.add_child(_btn("В меню", _to_menu))

	# слева: что ставить
	var left := _panel(false, 74, 250)
	for group in TOOLS:
		left.add_child(_lbl(group[0].to_upper(), 14, 0.45))
		for t in group[1]:
			var b := Button.new()
			b.text = t[1]
			b.toggle_mode = true
			b.focus_mode = Control.FOCUS_NONE
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.add_theme_font_size_override("font_size", 16)
			var id: String = t[0]
			b.pressed.connect(func() -> void: _set_tool(id))
			left.add_child(b)
			_tool_buttons[id] = b

	# справа: свойства
	var right := _panel(true, 74, 300)
	right.add_child(_lbl("КАРТА", 14, 0.45))
	var row := HBoxContainer.new()
	right.add_child(row)
	row.add_child(_lbl("Ширина"))
	_w_spin = _spin(60, 500, 10, 160, func(_v: float) -> void: pass)
	row.add_child(_w_spin)
	var row2 := HBoxContainer.new()
	right.add_child(row2)
	row2.add_child(_lbl("Глубина"))
	_d_spin = _spin(60, 500, 10, 160, func(_v: float) -> void: pass)
	row2.add_child(_d_spin)
	right.add_child(_btn("Применить размер", func() -> void:
		_push_undo()
		data["size"] = [_w_spin.value, _d_spin.value]
		dirty = true
		_rebuild()))
	right.add_child(_lbl("Зеркало", 14, 0.45))
	var mo := OptionButton.new()
	for t in ["Нет", "Слева-направо", "Поворот вокруг центра", "Сверху-вниз"]:
		mo.add_item(t)
	mo.select(mirror)
	mo.focus_mode = Control.FOCUS_NONE
	mo.item_selected.connect(func(i: int) -> void: mirror = i)
	right.add_child(mo)
	var mh := _lbl("Всё, что ставишь, появляется и на другой половине карты. Постройки там достаются врагам.", 14, 0.5)
	mh.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(mh)
	right.add_child(_lbl("ПОСТРОЙКИ", 14, 0.45))
	_team_opt = OptionButton.new()
	_team_opt.add_item("Своя команда (оранжевые)")
	_team_opt.add_item("Враги (красные)")
	_team_opt.focus_mode = Control.FOCUS_NONE
	_team_opt.item_selected.connect(func(i: int) -> void:
		team = i
		_apply_to_selected("team", i))
	right.add_child(_team_opt)
	right.add_child(_lbl("Линия турели или точки"))
	_lane_opt = OptionButton.new()
	for k in ["top", "mid", "bot", "base"]:
		_lane_opt.add_item(Maps.LANE_NAMES[k])
	_lane_opt.select(1)
	_lane_opt.focus_mode = Control.FOCUS_NONE
	_lane_opt.item_selected.connect(func(i: int) -> void:
		lane = ["top", "mid", "bot", "base"][i]
		_apply_to_selected("lane", lane))
	right.add_child(_lane_opt)
	right.add_child(_lbl("УКРЫТИЕ: длина, высота, толщина", 14, 0.45))
	for k in 3:
		var r := HBoxContainer.new()
		right.add_child(r)
		r.add_child(_lbl(["По X", "Высота", "По Z"][k]))
		var idx := k
		var sp := _spin(0.5, 80, 0.5, 4, func(v: float) -> void: _on_dim(idx, v))
		r.add_child(sp)
		_dim_spins.append(sp)
	right.add_child(_btn("Повернуть (R)", _rotate))
	right.add_child(_lbl("Сетка, м", 14, 0.45))
	var go := OptionButton.new()
	for g in [0.5, 1.0, 2.0, 4.0]:
		go.add_item(str(g))
	go.select(1)
	go.focus_mode = Control.FOCUS_NONE
	go.item_selected.connect(func(i: int) -> void:
		grid = [0.5, 1.0, 2.0, 4.0][i]
		_ground_mat.set_shader_parameter("step_m", maxf(grid, 1.0) * 2.0))
	right.add_child(go)
	right.add_child(_lbl("ВЫБРАНО", 14, 0.45))
	_sel_label = _lbl("ничего", 16, 0.8)
	_sel_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(_sel_label)
	right.add_child(_btn("Удалить (Delete)", _delete_selected))
	var help := _lbl("ЛКМ поставить или выбрать · ПКМ удалить · R повернуть · Ctrl+Z отменить · Ctrl+S сохранить · WASD, колесо, зажатое колесо — камера", 14, 0.5)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(help)
	_set_tool("wall")


func _set_tool(id: String) -> void:
	tool = id
	for k in _tool_buttons:
		_tool_buttons[k].button_pressed = k == id
	if dims.has(id):
		_sel = null
		_show_dims(dims[id])
	_update_ghost()
	_update_sel_label()


func _show_dims(d: Vector3) -> void:
	for k in 3:
		_dim_spins[k].set_value_no_signal(d[k])


func _on_dim(k: int, v: float) -> void:
	if _sel != null and _sel[0] == "covers":
		_push_undo()
		var c: Array = data["covers"][_sel[1]]
		var idx: int = [2, 3, 4][k]
		c[idx] = v
		var twin = _twin_of("covers", _sel[1])
		if twin != null:
			data["covers"][twin][idx] = v
		dirty = true
		_rebuild()
		return
	if dims.has(tool):
		var d: Vector3 = dims[tool]
		d[k] = v
		dims[tool] = d
		_update_ghost()


func _update_status() -> void:
	var p := Maps.problems(data)
	var t := ("● не сохранено   " if dirty else "") + (file_path.get_file() if file_path != "" else "новая карта")
	if not p.is_empty():
		t += "   ·   " + ", ".join(p)
	_status.text = t


# ------------------------------------------------------------------
#  Карта: новая, открыть, сохранить, играть
# ------------------------------------------------------------------

func _new_map(w: float, d: float, title: String) -> void:
	data = Maps.empty_map(w, d, title)
	# сразу два штаба друг напротив друга (их можно перенести)
	data["structures"].append(["hq", 0, -w * 0.5 + 14.0, 0, "base"])
	data["structures"].append(["hq", 1, w * 0.5 - 14.0, 0, "base"])
	file_path = ""
	dirty = false
	_undo.clear()


func _after_load() -> void:
	_name_edit.text = data.get("name", "")
	_w_spin.set_value_no_signal(float(data["size"][0]))
	_d_spin.set_value_no_signal(float(data["size"][1]))
	_zoom = maxf(float(data["size"][0]), float(data["size"][1])) * 1.15
	_cam.position = Vector3(30, 100, 0)
	_sel = null
	_rebuild()


func _save() -> void:
	if file_path == "" or not file_path.begins_with(Maps.save_dir()):
		file_path = Maps.save_dir().path_join(Maps.file_name_for(data.get("name", "map")))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(Maps.save_dir()))
	Maps.save_to(data, file_path)
	dirty = false
	_update_status()
	_flash_status("Сохранено: " + file_path.get_file())


func _flash_status(t: String) -> void:
	_status.text = t
	get_tree().create_timer(2.0).timeout.connect(_update_status)


func _play() -> void:
	var p := Maps.problems(data)
	if not p.is_empty():
		_flash_status("Нельзя играть: " + ", ".join(p))
		return
	Maps.save_to(data, Maps.TEST_PATH)
	Maps.selected = Maps.TEST_PATH
	Maps.from_editor = true
	Maps.editor_path = Maps.TEST_PATH
	Maps.set_meta("editor_file", file_path)
	Maps.set_meta("editor_dirty", dirty)
	get_tree().change_scene_to_file("res://main.tscn")


func _to_menu() -> void:
	Maps.editor_path = ""
	Maps.from_editor = false
	get_tree().change_scene_to_file("res://menu.tscn")


# окошко посреди экрана: заголовок, содержимое, кнопки
func _modal(title: String) -> VBoxContainer:
	_close_modal()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.add_child(dim)
	_dialog = dim
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.add_child(cc)
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", GameMenu.panel_style())
	pc.custom_minimum_size = Vector2(520, 0)
	cc.add_child(pc)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	pc.add_child(col)
	col.add_child(_lbl(title, 26))
	return col


func _close_modal() -> void:
	if _dialog != null and is_instance_valid(_dialog):
		_dialog.queue_free()
	_dialog = null


func _ask_new() -> void:
	var col := _modal("НОВАЯ КАРТА")
	var n := LineEdit.new()
	n.text = "Новая карта"
	n.add_theme_font_size_override("font_size", 18)
	col.add_child(n)
	var r := HBoxContainer.new()
	col.add_child(r)
	r.add_child(_lbl("Ширина"))
	var w := _spin(60, 500, 10, 160, func(_v: float) -> void: pass)
	r.add_child(w)
	r.add_child(_lbl("  Глубина"))
	var d := _spin(60, 500, 10, 160, func(_v: float) -> void: pass)
	r.add_child(d)
	col.add_child(_lbl("Квадратная карта: ширина = глубина", 14, 0.5))
	var b := HBoxContainer.new()
	b.alignment = BoxContainer.ALIGNMENT_END
	col.add_child(b)
	b.add_child(_btn("Отмена", _close_modal))
	b.add_child(_btn("Создать", func() -> void:
		_new_map(w.value, d.value, n.text)
		_close_modal()
		_after_load(), 140))


func _ask_open() -> void:
	var col := _modal("ОТКРЫТЬ КАРТУ")
	var list := ItemList.new()
	list.custom_minimum_size = Vector2(0, 320)
	list.add_theme_font_size_override("font_size", 18)
	col.add_child(list)
	var maps := Maps.list_maps()
	for m in maps:
		list.add_item("%s   (%s)" % [m["name"], m["file"]])
	var b := HBoxContainer.new()
	b.alignment = BoxContainer.ALIGNMENT_END
	col.add_child(b)
	b.add_child(_btn("Отмена", _close_modal))
	var open := func() -> void:
		var s := list.get_selected_items()
		if s.is_empty():
			return
		data = Maps.load_map(maps[s[0]]["path"])
		file_path = maps[s[0]]["path"]
		dirty = false
		_undo.clear()
		_close_modal()
		_after_load()
	list.item_activated.connect(func(_i: int) -> void: open.call())
	b.add_child(_btn("Открыть", open, 140))


func _ask_save_as() -> void:
	var col := _modal("СОХРАНИТЬ КАК")
	var n := LineEdit.new()
	n.text = data.get("name", "")
	n.add_theme_font_size_override("font_size", 18)
	col.add_child(n)
	col.add_child(_lbl("Файл ляжет в папку maps проекта", 14, 0.5))
	var b := HBoxContainer.new()
	b.alignment = BoxContainer.ALIGNMENT_END
	col.add_child(b)
	b.add_child(_btn("Отмена", _close_modal))
	b.add_child(_btn("Сохранить", func() -> void:
		data["name"] = n.text
		_name_edit.text = n.text
		file_path = Maps.save_dir().path_join(Maps.file_name_for(n.text))
		_close_modal()
		_save(), 140))


# ------------------------------------------------------------------
#  Ввод
# ------------------------------------------------------------------

func _over_ui() -> bool:
	return get_viewport().gui_get_hovered_control() != null or _dialog != null


func _unhandled_input(event: InputEvent) -> void:
	if _dialog != null:
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_zoom = maxf(_zoom * 0.88, 20.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_zoom = minf(_zoom * 1.12, 700.0)
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			_pan_drag = event.pressed
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_on_click(_snap(_mouse_world))
			else:
				if _drag:
					_drag = false
					_rebuild()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			var hit = _pick(_mouse_world)
			if hit != null:
				_push_undo()
				_remove(hit[0], hit[1], true)
	elif event is InputEventMouseMotion:
		if _pan_drag:
			var k := _zoom / get_viewport().get_visible_rect().size.y
			_cam.position -= Vector3(event.relative.x, 0, event.relative.y) * k
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_R:
				_rotate()
			KEY_DELETE:
				_delete_selected()
			KEY_ESCAPE:
				_sel = null
				_set_tool("select")
			KEY_Z:
				if event.ctrl_pressed:
					_undo_step()
			KEY_S:
				if event.ctrl_pressed:
					_save()


func _process(delta: float) -> void:
	_cam.size = _zoom
	var mp := get_viewport().get_mouse_position()
	var o := _cam.project_ray_origin(mp)
	var d := _cam.project_ray_normal(mp)
	var hit = Plane(Vector3.UP, 0.0).intersects_ray(o, d)
	if hit != null:
		_mouse_world = hit
	if _dialog == null and not (get_viewport().gui_get_focus_owner() is LineEdit):
		var pan := Vector3.ZERO
		if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
			pan.x -= 1
		if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
			pan.x += 1
		if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
			pan.z -= 1
		if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
			if not Input.is_key_pressed(KEY_CTRL):
				pan.z += 1
		_cam.position += pan * _zoom * 0.8 * delta
	# перетаскивание выбранного
	if _drag and _sel != null:
		var p := _snap(_mouse_world - _drag_off)
		_move_item(_sel[0], _sel[1], p)
		if _drag_twin != null:
			_move_item(_sel[0], _drag_twin, _mirror_pos(p))
		_rebuild_objects()
	_ghost.visible = not _over_ui() and tool != "select" and tool != "erase"
	if _ghost.visible:
		_ghost.position = _snap(_mouse_world)


func _snap(p: Vector3) -> Vector3:
	return Vector3(snappedf(p.x, grid), 0, snappedf(p.z, grid))


func _on_click(p: Vector3) -> void:
	if _over_ui():
		return
	if tool == "select":
		var hit = _pick(_mouse_world)
		_sel = hit
		if hit != null:
			_push_undo()
			_drag = true
			_drag_off = _mouse_world - _item_pos(hit[0], hit[1])
			_drag_off.y = 0
			_drag_twin = _twin_of(hit[0], hit[1])
			_sync_panel_to_selection()
		_update_sel_label()
		_rebuild_objects()
		return
	if tool == "erase":
		var hit2 = _pick(_mouse_world)
		if hit2 != null:
			_push_undo()
			_remove(hit2[0], hit2[1], true)
		return
	_push_undo()
	_place(tool, p)
	var mp := _mirror_pos(p)
	if mirror > 0 and mp.distance_to(p) > 1.0:
		_place(tool, mp, true)
	dirty = true
	_rebuild()


# ------------------------------------------------------------------
#  Предметы карты
# ------------------------------------------------------------------

func _mirror_pos(p: Vector3) -> Vector3:
	match mirror:
		1:
			return Vector3(-p.x, 0, p.z)
		2:
			return Vector3(-p.x, 0, -p.z)
		3:
			return Vector3(p.x, 0, -p.z)
	return p


func _mirror_lane(l: String) -> String:
	if mirror == 2:
		return {"top": "bot", "bot": "top"}.get(l, l)
	return l


func _place(t: String, p: Vector3, mirrored := false) -> void:
	var x := p.x
	var z := p.z
	if dims.has(t):
		var d: Vector3 = dims[t]
		data["covers"].append([x, z, d.x, d.y, d.z, t])
	elif t == "hq" or t.begins_with("turret"):
		var tm := 1 - team if mirrored else team
		var ln := "base" if t == "hq" else (_mirror_lane(lane) if mirrored else lane)
		if t == "hq":
			# штаб у команды один: старый убираем
			for i in range(data["structures"].size() - 1, -1, -1):
				var s: Array = data["structures"][i]
				if s[0] == "hq" and int(s[1]) == tm:
					data["structures"].remove_at(i)
		data["structures"].append([t, tm, x, z, ln])
	elif t.begins_with("poi_"):
		data["pois"].append([x, z, t.trim_prefix("poi_")])
	elif t == "crate":
		data["crates"].append([x, z])
	elif t == "lanepoint":
		data["lanepoints"].append([x, z, _mirror_lane(lane) if mirrored else lane])
	elif t.begins_with("decor_"):
		var rot := 0.0
		data["decor"].append([t.trim_prefix("decor_"), x, z, rot + (180.0 if mirrored and mirror == 2 else 0.0)])
	elif t == "lamp":
		data["lamps"].append([x, z])
	elif t == "target":
		data["targets"].append([x, z])


# где предмет на карте
func _item_pos(list: String, i: int) -> Vector3:
	var it: Array = data[list][i]
	match list:
		"structures":
			return Vector3(float(it[2]), 0, float(it[3]))
		"decor":
			return Vector3(float(it[1]), 0, float(it[2]))
	return Vector3(float(it[0]), 0, float(it[1]))


func _move_item(list: String, i: int, p: Vector3) -> void:
	var it: Array = data[list][i]
	match list:
		"structures":
			it[2] = p.x
			it[3] = p.z
		"decor":
			it[1] = p.x
			it[2] = p.z
		_:
			it[0] = p.x
			it[1] = p.z
	dirty = true


# такой же предмет в зеркальной точке (его двигаем и удаляем вместе)
func _twin_of(list: String, i: int):
	if mirror == 0:
		return null
	var p := _item_pos(list, i)
	var mp := _mirror_pos(p)
	if mp.distance_to(p) < 1.0:
		return null
	var it: Array = data[list][i]
	for j in data[list].size():
		if j == i:
			continue
		var other: Array = data[list][j]
		if _item_pos(list, j).distance_to(mp) > 1.5:
			continue
		if list == "structures" and other[0] != it[0]:
			continue
		if list == "covers" and other[5] != it[5]:
			continue
		return j
	return null


func _remove(list: String, i: int, with_twin: bool) -> void:
	var twin = _twin_of(list, i) if with_twin else null
	var idx: Array = [i]
	if twin != null:
		idx.append(twin)
	idx.sort()
	idx.reverse()
	for k in idx:
		data[list].remove_at(k)
	_sel = null
	dirty = true
	_rebuild()


func _delete_selected() -> void:
	if _sel == null:
		return
	_push_undo()
	_remove(_sel[0], _sel[1], true)


# что под курсором: [список, номер] или null
func _pick(p: Vector3):
	var best = null
	var best_d := 1e9
	for list in ["structures", "pois", "crates", "lanepoints", "decor", "lamps", "targets", "covers"]:
		for i in data[list].size():
			var it: Array = data[list][i]
			var c := _item_pos(list, i)
			var d := Vector2(p.x - c.x, p.z - c.z).length()
			var r := 2.5
			match list:
				"structures":
					r = 5.0 if it[0] == "hq" else 3.0
				"pois":
					r = 5.0
				"covers":
					if absf(p.x - c.x) <= float(it[2]) * 0.5 + 0.5 and absf(p.z - c.z) <= float(it[4]) * 0.5 + 0.5:
						d = 0.5
					else:
						continue
			if d <= r and d < best_d:
				best_d = d
				best = [list, i]
	return best


func _rotate() -> void:
	if _sel != null and _sel[0] == "covers":
		_push_undo()
		var c: Array = data["covers"][_sel[1]]
		var t = c[2]
		c[2] = c[4]
		c[4] = t
		var twin = _twin_of("covers", _sel[1])
		if twin != null:
			var c2: Array = data["covers"][twin]
			c2[2] = c[2]
			c2[4] = c[4]
		_sync_panel_to_selection()
		dirty = true
		_rebuild()
	elif _sel != null and _sel[0] == "decor":
		_push_undo()
		data["decor"][_sel[1]][3] = fmod(float(data["decor"][_sel[1]][3]) + 90.0, 360.0)
		dirty = true
		_rebuild()
	elif dims.has(tool):
		var d: Vector3 = dims[tool]
		dims[tool] = Vector3(d.z, d.y, d.x)
		_show_dims(dims[tool])
		_update_ghost()


func _apply_to_selected(field: String, value) -> void:
	if _sel == null:
		return
	if field == "team" and _sel[0] == "structures":
		_push_undo()
		data["structures"][_sel[1]][1] = value
	elif field == "lane" and (_sel[0] == "structures" or _sel[0] == "lanepoints"):
		_push_undo()
		var it: Array = data[_sel[0]][_sel[1]]
		if _sel[0] == "structures" and it[0] != "hq":
			it[4] = value
		elif _sel[0] == "lanepoints":
			it[2] = value
	else:
		return
	dirty = true
	_rebuild()


func _sync_panel_to_selection() -> void:
	if _sel == null:
		return
	var it: Array = data[_sel[0]][_sel[1]]
	if _sel[0] == "covers":
		_show_dims(Vector3(float(it[2]), float(it[3]), float(it[4])))
	elif _sel[0] == "structures":
		_team_opt.select(int(it[1]))
		var ln: String = it[4] if it.size() > 4 else "mid"
		_lane_opt.select(["top", "mid", "bot", "base"].find(ln))
	elif _sel[0] == "lanepoints":
		_lane_opt.select(["top", "mid", "bot", "base"].find(it[2]))


func _update_sel_label() -> void:
	if _sel == null:
		_sel_label.text = "ничего (инструмент «Выбор», клик по предмету)"
		return
	var it: Array = data[_sel[0]][_sel[1]]
	var p := _item_pos(_sel[0], _sel[1])
	var t := ""
	match _sel[0]:
		"covers":
			t = {"wall": "Стена", "barrier": "Барьер", "rock": "Скала"}.get(it[5], it[5]) + "  %s × %s м" % [it[2], it[4]]
		"structures":
			t = Parts.pname(it[0]) + ", " + ("своя команда" if int(it[1]) == 0 else "враги") + ", линия: " + Maps.LANE_NAMES.get(it[4] if it.size() > 4 else "mid", "")
		"pois":
			t = Maps.POI_NAMES.get(it[2], "Точка")
		"lanepoints":
			t = "Точка линии: " + Maps.LANE_NAMES.get(it[2], "")
		"decor":
			t = "Украшение: " + it[0]
		_:
			t = {"crates": "Место ящика", "lamps": "Фонарь", "targets": "Мишень"}.get(_sel[0], _sel[0])
	_sel_label.text = "%s\nx %d, z %d" % [t, int(p.x), int(p.z)]


func _push_undo() -> void:
	_undo.append(data.duplicate(true))
	if _undo.size() > 60:
		_undo.pop_front()


func _undo_step() -> void:
	if _undo.is_empty():
		return
	data = _undo.pop_back()
	_sel = null
	dirty = true
	_name_edit.text = data.get("name", "")
	_rebuild()


# ------------------------------------------------------------------
#  Отрисовка предметов (простые фигуры: в бою карта выглядит по-настоящему)
# ------------------------------------------------------------------

var _mat_cache := {}


func _m(c: Color) -> StandardMaterial3D:
	var key := c.to_html()
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.8
	_mat_cache[key] = m
	return m


func _add_box(parent: Node3D, size: Vector3, pos: Vector3, col: Color, rot := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _m(col)
	mi.position = pos + Vector3.UP * size.y * 0.5
	mi.rotation.y = deg_to_rad(rot)
	parent.add_child(mi)
	return mi


func _add_cyl(parent: Node3D, r: float, h: float, pos: Vector3, col: Color) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = 20
	mi.mesh = cm
	mi.material_override = _m(col)
	mi.position = pos + Vector3.UP * h * 0.5
	parent.add_child(mi)


func _add_label(parent: Node3D, text: String, pos: Vector3, col := Color.WHITE, size := 96) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.045
	l.outline_size = 16
	l.modulate = col
	l.rotation_degrees = Vector3(-90, 0, 0)
	l.position = pos + Vector3.UP * 9.0
	l.no_depth_test = true
	parent.add_child(l)


func _rebuild() -> void:
	_ground.mesh.size = Vector2(float(data["size"][0]) + 400.0, float(data["size"][1]) + 400.0)
	_ground_mat.set_shader_parameter("size", Vector2(float(data["size"][0]), float(data["size"][1])))
	_rebuild_objects()
	_update_sel_label()
	_update_status()


func _rebuild_objects() -> void:
	for c in _objects.get_children():
		c.queue_free()
	var root := _objects
	for i in data["covers"].size():
		var c: Array = data["covers"][i]
		var col: Color = {"wall": Color(0.62, 0.63, 0.66), "barrier": Color(0.75, 0.68, 0.45), "rock": Color(0.5, 0.42, 0.33)}.get(c[5], Color.GRAY)
		_add_box(root, Vector3(c[2], c[3], c[4]), Vector3(c[0], 0, c[1]), col)
	for s in data["structures"]:
		var tc: Color = TEAM_COLORS[int(s[1])]
		var p := Vector3(float(s[2]), 0, float(s[3]))
		if s[0] == "hq":
			_add_box(root, Vector3(8, 6, 8), p, tc)
			_add_label(root, "ШТАБ", p, Color.WHITE, 120)
		else:
			_add_cyl(root, 1.8, 5.0, p, tc.darkened(0.2))
			var ln: String = s[4] if s.size() > 4 else "mid"
			_add_label(root, "T" + String(s[0]).right(1), p, LANE_COLORS.get(ln, Color.WHITE))
	for p in data["pois"]:
		var pos := Vector3(float(p[0]), 0, float(p[1]))
		_add_cyl(root, Cfg.poi_radius, 0.2, pos, Color(0.3, 0.4, 0.55))
		_add_cyl(root, 1.4, 3.0, pos, Color(0.5, 0.8, 1.0))
		_add_label(root, Maps.POI_NAMES.get(p[2], "Точка"), pos, Color(0.6, 0.9, 1.0))
	for p in data["crates"]:
		_add_box(root, Vector3(2.4, 1.6, 2.4), Vector3(float(p[0]), 0, float(p[1])), Color(1.0, 0.8, 0.25))
	for p in data["lanepoints"]:
		var lc: Color = LANE_COLORS.get(p[2], Color.WHITE)
		_add_cyl(root, 1.2, 0.6, Vector3(float(p[0]), 0, float(p[1])), lc)
	for d in data["decor"]:
		var sz: Vector2 = DECOR_SIZE.get(d[0], Vector2(2.5, 2.5))
		_add_box(root, Vector3(sz.x, 2.4, sz.y), Vector3(float(d[1]), 0, float(d[2])), Color(0.35, 0.45, 0.55), float(d[3]) if d.size() > 3 else 0.0)
	for p in data["lamps"]:
		_add_cyl(root, 0.4, 4.5, Vector3(float(p[0]), 0, float(p[1])), Color(1.0, 0.9, 0.6))
	for p in data["targets"]:
		_add_box(root, Vector3(2.2, 3, 2.0), Vector3(float(p[0]), 0, float(p[1])), Color(0.6, 0.2, 0.18))
	# выделение
	if _sel != null and _sel[1] < data[_sel[0]].size():
		var sp := _item_pos(_sel[0], _sel[1])
		var r := 4.0
		if _sel[0] == "covers":
			var c2: Array = data["covers"][_sel[1]]
			r = maxf(float(c2[2]), float(c2[4])) * 0.6
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = r
		tm.outer_radius = r + 0.6
		ring.mesh = tm
		var rm := StandardMaterial3D.new()
		rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		rm.albedo_color = Color(0.3, 1.0, 0.4)
		ring.material_override = rm
		ring.position = sp + Vector3.UP * 8.0
		root.add_child(ring)
	_draw_lanes()


# линии (как по ним поедут крипы): цветные полосы поверх карты
func _draw_lanes() -> void:
	var im: ImmediateMesh = _lanes_mesh.mesh
	im.clear_surfaces()
	var lanes := Maps.lanes(data)
	if lanes.is_empty():
		return
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for ln in lanes:
		var path: PackedVector3Array = lanes[ln]
		var c: Color = LANE_COLORS.get(ln, Color.WHITE)
		c.a = 0.55
		for i in path.size() - 1:
			var a := path[i] + Vector3.UP * 10.0
			var b := path[i + 1] + Vector3.UP * 10.0
			var dir := b - a
			if dir.length() < 0.1:
				continue
			var side := dir.normalized().cross(Vector3.UP) * 1.0
			for v in [a - side, a + side, b + side, a - side, b + side, b - side]:
				im.surface_set_color(c)
				im.surface_add_vertex(v)
	im.surface_end()


func _update_ghost() -> void:
	var mesh: Mesh = null
	if dims.has(tool):
		var bm := BoxMesh.new()
		bm.size = dims[tool]
		mesh = bm
	elif tool == "hq":
		var bm2 := BoxMesh.new()
		bm2.size = Vector3(8, 6, 8)
		mesh = bm2
	else:
		var cm := CylinderMesh.new()
		cm.top_radius = 1.8
		cm.bottom_radius = 1.8
		cm.height = 3.0
		mesh = cm
	_ghost.mesh = mesh
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.4, 1.0, 0.5, 0.45)
	_ghost.material_override = m


# ------------------------------------------------------------------
#  Самопроверка (только для Claude: --editortest)
# ------------------------------------------------------------------

func _selftest() -> void:
	_new_map(200, 200, "Тест квадрат")
	mirror = 2
	_set_tool("wall")
	_on_click(Vector3(-30, 0, -20))
	_set_tool("turret_t1")
	team = 0
	lane = "top"
	_on_click(Vector3(-40, 0, -60))
	_set_tool("poi_regen")
	_on_click(Vector3(0, 0, -50))
	print("[EDITOR] covers=%d structures=%d pois=%d lanes=%s problems=%s" % [data["covers"].size(), data["structures"].size(),
		data["pois"].size(), Maps.lanes(data).keys(), Maps.problems(data)])
	var path := "user://editortest_map.json"
	Maps.save_to(data, path)
	var back := Maps.load_map(path)
	print("[EDITOR] saved and loaded back: covers=%d structures=%d size=%s" % [back["covers"].size(), back["structures"].size(), back["size"]])
	_undo_step()
	print("[EDITOR] after undo: pois=%d" % data["pois"].size())
	if not OS.get_cmdline_user_args().has("--stay"):
		get_tree().quit()
