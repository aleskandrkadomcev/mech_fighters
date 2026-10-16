extends CanvasLayer
## Панель настроек (F2). Две вкладки:
##   "Правила игры"   - общее из settings.gd (вес, энергия, камера, боты, тряска...)
##   "Детали мехов"   - числа каждой детали из parts.gd: ноги (ходьба, бег, рывок), корпуса,
##                      ядра, оружие (урон, разброс, скорострельность), модули (ракеты, импульс, пассивки)
## На каждое число ползунок, группы сворачиваются, изменения применяются сразу и сохраняются сами.

const WIDTH := 600.0

var _panel: PanelContainer
var _rows := {}          # ключ строки -> {slider, value, reset, name, item, get, set, reset_fn, changed}
var _groups: Array = []  # [{button, box, name, keys}]
var _tabs := {}          # "cfg"/"parts" -> ScrollContainer
var _tab_buttons := {}
var _tab := "cfg"
var _updating := false


func _ready() -> void:
	layer = 20       # поверх ангара и меню паузы
	_build()
	_panel.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_F2:
			toggle()


func toggle() -> void:
	_panel.visible = not _panel.visible
	if _panel.visible:
		_refresh_all()
	else:
		Cfg.ui_hover = false


func _process(_delta: float) -> void:
	if not _panel.visible:
		return
	# пока мышь над панелью, мех не стреляет и не целится
	Cfg.ui_hover = _panel.get_global_rect().has_point(_panel.get_global_mouse_position())
	# колесо мыши могло поменять число снаружи: обновляем только то, что изменилось
	_refresh_all(false)


func _build() -> void:
	_panel = PanelContainer.new()
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.anchor_top = 0.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = -WIDTH - 16
	_panel.offset_right = -16
	_panel.offset_top = 16
	_panel.offset_bottom = -16
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.08, 0.1, 0.94)
	sb.set_border_width_all(1)
	sb.border_color = Color(1, 1, 1, 0.18)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(14)
	_panel.add_theme_stylebox_override("panel", sb)
	add_child(_panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	_panel.add_child(col)

	var head := HBoxContainer.new()
	col.add_child(head)
	var title := Label.new()
	title.text = "НАСТРОЙКИ"
	title.add_theme_font_size_override("font_size", 24)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var reset_all := _button("Сбросить вкладку")
	reset_all.pressed.connect(_on_reset_all)
	head.add_child(reset_all)
	var close := _button("Закрыть (F2)")
	close.pressed.connect(toggle)
	head.add_child(close)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	col.add_child(tabs)
	for t in [["parts", "Детали мехов: ходьба, оружие, абилки"], ["cfg", "Правила игры"]]:
		var b := _button(t[1])
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(140, 0)
		var tab_id: String = t[0]
		b.pressed.connect(func() -> void: _show_tab(tab_id))
		tabs.add_child(b)
		_tab_buttons[t[0]] = b

	var note := Label.new()
	note.text = "Меняется сразу, сохраняется само. Нажми на группу, чтобы раскрыть.\nНаведи мышь на название, чтобы увидеть пояснение."
	note.add_theme_font_size_override("font_size", 15)
	note.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	col.add_child(note)

	# вкладка "Общие"
	var list_cfg := _make_tab(col, "cfg")
	var current_group := ""
	var box: VBoxContainer = null
	var g: Dictionary = {}
	for item in Cfg.get_items():
		if item["group"] != current_group or box == null:
			current_group = item["group"]
			g = _add_group(list_cfg, current_group)
			box = g["box"]
		var key: String = item["name"]
		_add_row(box, g, "cfg:" + key, item["label"], item["hint"], item["min"], item["max"], item["step"], item["is_int"],
			func() -> float: return float(Cfg.get(key)),
			func(val: float) -> void: Cfg.set_value(key, val),
			func() -> void: Cfg.reset_value(key),
			func() -> bool: return Cfg.is_changed(key))

	# вкладка "Детали": по группе на каждую деталь
	var list_parts := _make_tab(col, "parts")
	for slot in Parts.SLOT_ORDER:
		var head_l := Label.new()
		head_l.text = Parts.SLOT_NAMES[slot].to_upper()
		head_l.add_theme_font_size_override("font_size", 15)
		head_l.add_theme_color_override("font_color", Color(1, 1, 1, 0.45))
		list_parts.add_child(head_l)
		for id in Parts.ids_for(slot):
			var gp := _add_group(list_parts, Parts.pname(id))
			# сверху группы: что деталь даёт сейчас, обновляется вместе с ползунками
			var dl := Label.new()
			dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			dl.add_theme_font_size_override("font_size", 15)
			dl.add_theme_color_override("font_color", Color(0.6, 0.85, 1.0, 0.85))
			gp["box"].add_child(dl)
			gp["part"] = id
			gp["desc"] = dl
			for f in Parts.numeric_fields(id):
				var meta: Array = Parts.FIELDS[f]
				var pid: String = id
				var field: String = f
				_add_row(gp["box"], gp, "part:%s:%s" % [id, f], meta[0], meta[4], meta[1], meta[2], meta[3], typeof(Parts.DATA[id][f]) == TYPE_INT,
					func() -> float: return Parts.v(pid, field),
					func(val: float) -> void: Parts.set_value(pid, field, val),
					func() -> void: Parts.reset_value(pid, field),
					func() -> bool: return Parts.is_changed(pid, field))

	_show_tab("parts")
	_update_group_titles()


func _make_tab(col: VBoxContainer, id: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	_tabs[id] = scroll
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 4)
	scroll.add_child(list)
	return list


func _show_tab(id: String) -> void:
	_tab = id
	for k in _tabs:
		_tabs[k].visible = k == id
		_tab_buttons[k].button_pressed = k == id


func _button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 16)
	return b


func _add_group(list: VBoxContainer, group_name: String) -> Dictionary:
	var btn := Button.new()
	btn.focus_mode = Control.FOCUS_NONE
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.add_theme_font_size_override("font_size", 19)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.07)
	sb.set_content_margin_all(7)
	sb.set_corner_radius_all(4)
	btn.add_theme_stylebox_override("normal", sb)
	var sbh := sb.duplicate()
	sbh.bg_color = Color(1, 1, 1, 0.13)
	btn.add_theme_stylebox_override("hover", sbh)
	btn.add_theme_stylebox_override("pressed", sbh)
	list.add_child(btn)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.visible = false
	list.add_child(box)

	var g := {"button": btn, "box": box, "name": group_name, "keys": []}
	_groups.append(g)
	btn.pressed.connect(func() -> void:
		box.visible = not box.visible
		_update_group_titles())
	return g


func _add_row(box: VBoxContainer, g: Dictionary, key: String, label: String, hint: String, vmin: float, vmax: float, step: float, is_int: bool,
		getter: Callable, setter: Callable, resetter: Callable, changed: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)

	var name_label := Label.new()
	name_label.text = label
	name_label.tooltip_text = hint if hint != "" else label
	name_label.mouse_filter = Control.MOUSE_FILTER_STOP
	name_label.custom_minimum_size = Vector2(250, 0)
	name_label.clip_text = true
	name_label.add_theme_font_size_override("font_size", 16)
	row.add_child(name_label)

	# расстояния и скорости (пояснение начинается с «метров» или «м/с») показываем в настоящих метрах:
	# игра считает в единицах, 1 единица = Cfg.METERS_PER_UNIT м. Игра от этого не меняется
	var k: float = Cfg.METERS_PER_UNIT if (hint.begins_with("метр") or hint.begins_with("м/с")) else 1.0
	var slider := HSlider.new()
	slider.focus_mode = Control.FOCUS_NONE
	slider.min_value = vmin * k
	slider.max_value = vmax * k
	slider.step = step
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.scrollable = false     # колесо мыши листает список, а не дёргает ползунок
	row.add_child(slider)

	var value_label := Label.new()
	value_label.custom_minimum_size = Vector2(64, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.add_theme_font_size_override("font_size", 16)
	row.add_child(value_label)

	var reset := _button("x")
	reset.tooltip_text = "Вернуть как было"
	reset.custom_minimum_size = Vector2(28, 0)
	reset.pressed.connect(func() -> void:
		resetter.call()
		_refresh_row(key))
	row.add_child(reset)

	slider.value_changed.connect(func(val: float) -> void:
		if _updating:
			return
		setter.call(val / k)
		_refresh_row(key))

	_rows[key] = {"slider": slider, "value": value_label, "reset": reset, "name": name_label,
		"step": step, "is_int": is_int and k == 1.0, "get": getter, "changed": changed, "group": g, "k": k}
	g["keys"].append(key)
	_refresh_row(key)


func _format(r: Dictionary, v: float) -> String:
	if r["is_int"]:
		return str(int(round(v)))
	var step: float = r["step"]
	if step >= 1.0:
		return "%d" % int(round(v))
	if step >= 0.1:
		return "%.1f" % v
	if step >= 0.01:
		return "%.2f" % v
	return "%.3f" % v


func _refresh_row(key: String, force := true) -> void:
	var r: Dictionary = _rows[key]
	var v: float = r["get"].call()
	var changed_now: bool = r["changed"].call()
	if not force and r.get("last") == v and r.get("last_changed") == changed_now:
		return
	r["last"] = v
	r["last_changed"] = changed_now
	_updating = true
	r["slider"].set_value_no_signal(v * r["k"])
	_updating = false
	r["value"].text = _format(r, v * r["k"])
	r["reset"].modulate = Color(1, 1, 1, 1.0 if changed_now else 0.0)
	r["reset"].disabled = not changed_now
	r["name"].add_theme_color_override("font_color", Color(1.0, 0.8, 0.35) if changed_now else Color(1, 1, 1, 0.9))


func _refresh_all(force := true) -> void:
	for key in _rows:
		_refresh_row(key, force)
	_update_group_titles()


# в заголовке группы видно, раскрыта ли она и сколько чисел в ней изменено
func _update_group_titles() -> void:
	for g in _groups:
		var changed := 0
		for key in g["keys"]:
			if _rows[key].get("last_changed", false):
				changed += 1
		var arrow := "–" if g["box"].visible else "+"
		var suffix := ("   (изменено: %d)" % changed) if changed > 0 else ""
		var text := "%s  %s%s" % [arrow, g["name"], suffix]
		if g["button"].text != text:
			g["button"].text = text
		if g.has("desc") and g["box"].visible:
			var d := Parts.describe(g["part"])
			if g["desc"].text != d:
				g["desc"].text = d


func _on_reset_all() -> void:
	if _tab == "cfg":
		Cfg.reset_all()
	else:
		Parts.reset_all()
	_refresh_all()
