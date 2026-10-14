extends CanvasLayer
## Ангар (клавиша B). Перед боем открывается сам (кнопка «В БОЙ»). Пока ангар открыт, игра на паузе.
##   слева   — выбор меха: 10 карточек (класс и особенность сразу видны);
##   в центре — мех в 3D на платформе, под ним масса и энергия;
##   справа  — плитки: ядро, пушка ЛКМ, пушка ПКМ и модули. Клик по плитке открывает список на выбор,
##             наведение мыши на вариант показывает все его числа;
##   внизу   — главные числа полосками (зелёным/красным: лучше/хуже, чем было), «Подробнее» — все числа.
## Сверху сохранённые сборки: выбрать, сохранить текущую под именем, удалить.

signal applied(build: Dictionary)

const MechVisual := preload("res://scripts/mech_visual.gd")
const WorldShader := preload("res://shaders/world.gdshader")
const COL_CLASS := {"Лёгкий": Color(0.5, 0.9, 1.0), "Средний": Color(1.0, 0.85, 0.4), "Тяжёлый": Color(1.0, 0.5, 0.35)}
# главные числа внизу: [ключ, подпись, максимум полоски]
const BARS := [["hp", "Здоровье", 700.0], ["run_speed", "Скорость бега", 18.0], ["energy_max", "Энергия в бою", 400.0],
	["dps", "Урон в секунду", 120.0], ["vision", "Обзор", 55.0]]

var _root: PanelContainer
var _build := {}
var _base := {}                   # числа сборки на момент открытия (для сравнения)
var _rows_box: VBoxContainer      # плитки оружия и модулей
var _cards: GridContainer
var _card_btns := {}
var _bars_box: HBoxContainer
var _bar_items := {}
var _problems: Label
var _mech_title: Label
var _mech_trait: Label
var _weight_bar: ProgressBar
var _weight_fill: StyleBoxFlat
var _weight_label: Label
var _energy_bar: ProgressBar
var _energy_fill: StyleBoxFlat
var _energy_label: Label
var _apply_btn: Button
var _cancel_btn: Button
var _hint: Label
var _title: Label
var _builds_opt: OptionButton
var _popup: PopupPanel
var _details: PopupPanel
var _details_text: RichTextLabel
var _start_mode := false
var _preview_vp: SubViewport
var _preview_root: Node3D
var _preview_mech: Node3D
var _preview_cam: Camera3D
var _cam_angle := 0.6
var _preview_key := ""
var _info: RichTextLabel          # все числа (во всплывающем окне «Подробнее»)


func _ready() -> void:
	layer = 9
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_root.visible = false


func is_open() -> bool:
	return _root.visible


func open(current: Dictionary) -> void:
	_build = Parts.upgrade_build(current).duplicate(true)
	_base = _summary(Parts.compute(_build))
	_root.visible = true
	get_tree().paused = true
	_set_mode(false)
	_refresh_builds()
	_refresh_rows()
	_refresh_info()


# ангар перед боем: без "Отмены", кнопка "В бой"
func open_start(current: Dictionary) -> void:
	open(current)
	_set_mode(true)


func _set_mode(start: bool) -> void:
	_start_mode = start
	_cancel_btn.visible = not start
	_apply_btn.text = "В БОЙ  ▶" if start else "Применить"
	_hint.text = "Собери меха и жми «В бой»   ·   Esc  в меню" if start else "B или Esc  закрыть без изменений"
	_title.text = "АНГАР  —  подготовка к бою" if start else "АНГАР"


func close() -> void:
	_root.visible = false
	_popup.hide()
	_details.hide()
	get_tree().paused = false


func _unhandled_input(event: InputEvent) -> void:
	if not _root.visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if _start_mode:
			if event.physical_keycode == KEY_ESCAPE:
				var g = get_tree().current_scene
				if g != null and g.has_method("to_menu"):
					g.to_menu()
			return
		if event.physical_keycode == KEY_B or event.physical_keycode == KEY_ESCAPE:
			close()
			get_viewport().set_input_as_handled()


# ------------------------------------------------------------------
#  Интерфейс
# ------------------------------------------------------------------

func _label(text: String, size: int, alpha := 1.0) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	if alpha < 1.0:
		l.add_theme_color_override("font_color", Color(1, 1, 1, alpha))
	return l


func _button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 18)
	return b


func _flat(c: Color, border := Color(0, 0, 0, 0), bw := 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(10)
	if bw > 0:
		sb.set_border_width_all(bw)
		sb.border_color = border
	return sb


func _bar(fill: StyleBoxFlat, h := 16) -> ProgressBar:
	var b := ProgressBar.new()
	b.custom_minimum_size = Vector2(0, h)
	b.show_percentage = false
	b.min_value = 0.0
	b.max_value = 1.0
	b.step = 0.0
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(1, 1, 1, 0.08)
	bg.set_corner_radius_all(3)
	fill.set_corner_radius_all(3)
	b.add_theme_stylebox_override("background", bg)
	b.add_theme_stylebox_override("fill", fill)
	return b


func _build_ui() -> void:
	_root = PanelContainer.new()
	_root.set_anchors_preset(Control.PRESET_CENTER)
	_root.offset_left = -930
	_root.offset_right = 930
	_root.offset_top = -515
	_root.offset_bottom = 515
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.07, 0.09, 0.97)
	sb.set_border_width_all(1)
	sb.border_color = Color(1, 1, 1, 0.2)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(18)
	_root.add_theme_stylebox_override("panel", sb)
	add_child(_root)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	_root.add_child(col)

	# шапка: название, сохранённые сборки, подсказка
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	col.add_child(head)
	_title = _label("АНГАР", 30)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	head.add_child(_label("Сборки:", 18, 0.6))
	_builds_opt = OptionButton.new()
	_builds_opt.custom_minimum_size = Vector2(260, 0)
	_builds_opt.focus_mode = Control.FOCUS_NONE
	_builds_opt.add_theme_font_size_override("font_size", 17)
	_builds_opt.item_selected.connect(_on_build_picked)
	head.add_child(_builds_opt)
	var save_b := _button("Сохранить как…")
	save_b.pressed.connect(_ask_save_build)
	head.add_child(save_b)
	var del_b := _button("Удалить")
	del_b.pressed.connect(func() -> void:
		var i := _builds_opt.selected
		if i > 0:
			Parts.delete_build(_builds_opt.get_item_text(i))
			_refresh_builds())
	head.add_child(del_b)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(20, 0)
	head.add_child(gap)
	_hint = _label("", 16, 0.5)
	head.add_child(_hint)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 22)
	col.add_child(body)

	# слева: мехи карточками
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(470, 0)
	left.add_theme_constant_override("separation", 8)
	body.add_child(left)
	left.add_child(_label("МЕХ", 20, 0.8))
	_cards = GridContainer.new()
	_cards.columns = 2
	_cards.add_theme_constant_override("h_separation", 8)
	_cards.add_theme_constant_override("v_separation", 8)
	left.add_child(_cards)
	for id in Parts.ids_for("mech"):
		_cards.add_child(_mech_card(id))

	# в середине: мех в 3D, особенность, масса и энергия
	var center := VBoxContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.add_theme_constant_override("separation", 6)
	body.add_child(center)
	_mech_title = _label("", 28)
	center.add_child(_mech_title)
	_mech_trait = _label("", 18)
	_mech_trait.add_theme_color_override("font_color", Color(1.0, 0.8, 0.45))
	_mech_trait.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	center.add_child(_mech_trait)
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	svc.custom_minimum_size = Vector2(480, 420)
	center.add_child(svc)
	_build_preview(svc)
	_weight_label = _label("", 17)
	center.add_child(_weight_label)
	_weight_fill = StyleBoxFlat.new()
	_weight_bar = _bar(_weight_fill)
	center.add_child(_weight_bar)
	_energy_label = _label("", 17)
	center.add_child(_energy_label)
	_energy_fill = StyleBoxFlat.new()
	_energy_bar = _bar(_energy_fill)
	center.add_child(_energy_bar)

	# справа: плитки
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(540, 0)
	right.add_theme_constant_override("separation", 6)
	body.add_child(right)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(scroll)
	_rows_box = VBoxContainer.new()
	_rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows_box.add_theme_constant_override("separation", 6)
	scroll.add_child(_rows_box)

	# низ: главные числа, проблемы, кнопки
	_bars_box = HBoxContainer.new()
	_bars_box.add_theme_constant_override("separation", 18)
	col.add_child(_bars_box)
	for b in BARS:
		var bc := VBoxContainer.new()
		bc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_bars_box.add_child(bc)
		var l := _label(b[1], 16, 0.8)
		bc.add_child(l)
		var fill := StyleBoxFlat.new()
		fill.bg_color = Color(0.45, 0.8, 1.0)
		var bar := _bar(fill, 12)
		bc.add_child(bar)
		_bar_items[b[0]] = {"label": l, "bar": bar, "fill": fill, "title": b[1], "max": b[2]}

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 12)
	col.add_child(bottom)
	_problems = _label("", 18)
	_problems.add_theme_color_override("font_color", Color(1.0, 0.42, 0.33))
	_problems.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(_problems)
	var more := _button("Подробнее…")
	more.pressed.connect(func() -> void:
		_details.popup_centered(Vector2i(620, 760)))
	bottom.add_child(more)
	var reset := _button("Стандартная сборка")
	reset.pressed.connect(func() -> void:
		_build = Parts.DEFAULT_BUILD.duplicate(true)
		_refresh_rows()
		_refresh_info())
	bottom.add_child(reset)
	_cancel_btn = _button("Отмена")
	_cancel_btn.pressed.connect(close)
	bottom.add_child(_cancel_btn)
	_apply_btn = _button("Применить")
	_apply_btn.custom_minimum_size = Vector2(200, 46)
	_apply_btn.add_theme_font_size_override("font_size", 22)
	_apply_btn.pressed.connect(_on_apply)
	bottom.add_child(_apply_btn)

	# всплывающие окна: список вариантов для плитки и «подробнее»
	_popup = PopupPanel.new()
	_popup.add_theme_stylebox_override("panel", _flat(Color(0.08, 0.09, 0.11, 0.98), Color(1, 1, 1, 0.25), 1))
	add_child(_popup)
	_details = PopupPanel.new()
	_details.add_theme_stylebox_override("panel", _flat(Color(0.08, 0.09, 0.11, 0.98), Color(1, 1, 1, 0.25), 1))
	add_child(_details)
	_info = RichTextLabel.new()
	_info.bbcode_enabled = true
	_info.scroll_active = true
	_info.custom_minimum_size = Vector2(600, 740)
	_info.add_theme_font_size_override("normal_font_size", 17)
	_info.add_theme_font_size_override("bold_font_size", 18)
	_details.add_child(_info)


# карточка меха: имя, класс, особенность
func _mech_card(id: String) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(228, 96)
	b.clip_text = false
	b.tooltip_text = Parts.describe(id).replace(" · ", "\n")
	var normal := _flat(Color(1, 1, 1, 0.05), Color(1, 1, 1, 0.12), 1)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", _flat(Color(1, 1, 1, 0.1), Color(1, 1, 1, 0.3), 1))
	b.add_theme_stylebox_override("pressed", normal)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 10
	box.offset_top = 6
	box.offset_right = -8
	box.add_theme_constant_override("separation", 0)
	b.add_child(box)
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(top)
	var n := _label(Parts.pname(id), 21)
	n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(n)
	var cls: String = Parts.text(id, "class")
	var c := _label(cls, 14)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_theme_color_override("font_color", COL_CLASS.get(cls, Color.WHITE))
	top.add_child(c)
	var t := _label(Parts.text(id, "trait"), 14, 0.65)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.custom_minimum_size = Vector2(205, 0)
	box.add_child(t)
	b.pressed.connect(func() -> void:
		_build["mech"] = id
		_refresh_rows()
		_refresh_info())
	_card_btns[id] = b
	return b


func _refresh_cards() -> void:
	for id in _card_btns:
		var b: Button = _card_btns[id]
		var on: bool = _build.get("mech", "") == id
		var sb := _flat(Color(1.0, 0.55, 0.15, 0.16) if on else Color(1, 1, 1, 0.05), Cfg.player_color if on else Color(1, 1, 1, 0.12), 2 if on else 1)
		b.add_theme_stylebox_override("normal", sb)
		b.add_theme_stylebox_override("pressed", sb)


# плитки: ядро, две пушки, модули (сколько даёт мех)
func _refresh_rows() -> void:
	_refresh_cards()
	for c in _rows_box.get_children():
		c.queue_free()
	_rows_box.add_child(_label("ВООРУЖЕНИЕ", 20, 0.8))
	_rows_box.add_child(_tile("Ядро", "core", _build["core"], func(id: String) -> void: _build["core"] = id))
	for i in 2:
		var n := i
		_rows_box.add_child(_tile("Оружие " + ("ЛКМ" if i == 0 else "ПКМ"), "weapon", _build["weapons"][i], func(id: String) -> void: _build["weapons"][n] = id))
	var slots := int(Parts.v(_build["mech"], "slots"))
	var mods: Array = _build.get("modules", [])
	while mods.size() < slots:
		mods.append("")
	_build["modules"] = mods
	_rows_box.add_child(_label("МОДУЛИ  ·  слотов: %d   (★ абилка, клавиша в углу)" % slots, 18, 0.8))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	_rows_box.add_child(grid)
	# клавиши абилок по порядку модулей
	var key_i := 0
	for i in slots:
		var n2 := i
		var key := ""
		var m: String = mods[i]
		if m != "" and Parts.DATA.has(m) and Parts.DATA[m].has("ability") and key_i < Parts.ABILITY_KEY_NAMES.size():
			key = Parts.ABILITY_KEY_NAMES[key_i]
			key_i += 1
		grid.add_child(_tile("Модуль %d" % (i + 1), "module", m, func(id: String) -> void: _build["modules"][n2] = id, true, key, 264))
	if slots < mods.size() and mods.slice(slots).any(func(x) -> bool: return x != ""):
		var extra := _label("Лишние модули не влезут в этого меха", 15)
		extra.add_theme_color_override("font_color", Color(1, 0.6, 0.3))
		_rows_box.add_child(extra)


# плитка: что стоит сейчас и главное число; клик — выбор из списка
func _tile(title: String, slot: String, current: String, on_pick: Callable, allow_empty := false, key := "", width := 534) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(width, 66)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.tooltip_text = Parts.describe(current).replace(" · ", "\n") if current != "" else "Пустой слот: нажми, чтобы выбрать"
	b.add_theme_stylebox_override("normal", _flat(Color(1, 1, 1, 0.05), Color(1, 1, 1, 0.12), 1))
	b.add_theme_stylebox_override("hover", _flat(Color(1, 1, 1, 0.1), Color(1, 1, 1, 0.35), 1))
	b.add_theme_stylebox_override("pressed", _flat(Color(1, 1, 1, 0.1), Color(1, 1, 1, 0.35), 1))
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 10
	box.offset_top = 4
	box.offset_right = -8
	box.add_theme_constant_override("separation", -2)
	b.add_child(box)
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(top)
	var tl := _label(title, 13, 0.5)
	tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(tl)
	if key != "":
		var kl := _label(key, 16)
		kl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		kl.add_theme_color_override("font_color", Color(0.45, 0.85, 1.0))
		top.add_child(kl)
	var name_text := Parts.pname(current) if current != "" else "+ пусто"
	if current != "" and Parts.DATA[current].has("ability"):
		name_text = "★ " + name_text
	var nl := _label(name_text, 19, 1.0 if current != "" else 0.4)
	nl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nl.clip_text = true
	box.add_child(nl)
	var sl := _label(Parts.short_line(current) if current != "" else "", 14, 0.6)
	sl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sl.clip_text = true
	box.add_child(sl)
	b.pressed.connect(func() -> void: _open_picker(slot, current, on_pick, allow_empty, b))
	return b


# всплывающий список вариантов
func _open_picker(slot: String, current: String, on_pick: Callable, allow_empty: bool, near: Control) -> void:
	for c in _popup.get_children():
		c.queue_free()
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_popup.add_child(scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 4)
	list.custom_minimum_size = Vector2(560, 0)
	scroll.add_child(list)
	var ids: Array = Parts.ids_for(slot)
	# модули: сначала абилки, потом пассивки
	if slot == "module":
		ids.sort_custom(func(a, b) -> bool: return Parts.DATA[a].has("ability") and not Parts.DATA[b].has("ability"))
	if allow_empty:
		ids.push_front("")
	for id in ids:
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(540, 52)
		b.add_theme_font_size_override("font_size", 17)
		var on: bool = id == current
		b.add_theme_stylebox_override("normal", _flat(Color(1.0, 0.55, 0.15, 0.18) if on else Color(1, 1, 1, 0.04)))
		b.add_theme_stylebox_override("hover", _flat(Color(1, 1, 1, 0.12)))
		if id == "":
			b.text = "— пусто —"
		else:
			var cost := "%.0f т" % Parts.v(id, "weight")
			if Parts.v(id, "energy") > 0.0:
				cost += ", %.0f эн." % Parts.v(id, "energy")
			b.text = "%s%s   (%s)\n%s" % ["★ " if Parts.DATA[id].has("ability") else "", Parts.pname(id), cost, Parts.short_line(id)]
			b.tooltip_text = Parts.describe(id).replace(" · ", "\n")
		var pick: String = id
		b.pressed.connect(func() -> void:
			on_pick.call(pick)
			_popup.hide()
			_refresh_rows()
			_refresh_info())
		list.add_child(b)
	var h := mini(ids.size() * 56 + 20, 720)
	scroll.custom_minimum_size = Vector2(560, h)
	var r := near.get_global_rect()
	_popup.popup(Rect2i(int(r.position.x - 580), int(clampf(r.position.y - 40, 20, 1080 - h - 40)), 580, h + 20))


# главные числа сборки (для полосок и сравнения)
func _summary(r: Dictionary) -> Dictionary:
	var st: Dictionary = r["stats"]
	var dps := 0.0
	for w in r["weapons"]:
		match w["type"]:
			"beam":
				dps += w["dps"]
			"rail":
				dps += w["damage"] / maxf(w["charge_time"] + 1.0 / maxf(w["fire_rate"], 0.05), 0.05)
			_:
				dps += w["damage"] * w["pellets"] * w["fire_rate"]
	return {"hp": st["hp"], "run_speed": st["run_speed"], "energy_max": st["energy_max"], "dps": dps, "vision": st["vision"]}


func _refresh_info() -> void:
	var r := Parts.compute(_build)
	var st: Dictionary = r["stats"]
	_update_preview(r)
	var mid: String = _build["mech"]
	_mech_title.text = "%s  ·  %s" % [Parts.pname(mid), Parts.text(mid, "class")]
	_mech_trait.text = Parts.text(mid, "trait")

	var cap: float = st["capacity"]
	var w: float = st["weight"]
	_weight_bar.value = clampf(w / maxf(cap, 1.0), 0.0, 1.0)
	# цвет полосы: голубой лёгкий, жёлтый тяжёлый, красный перегруз
	_weight_fill.bg_color = Color(1.0, 0.3, 0.25) if w > cap else Color(0.45, 0.8, 1.0).lerp(Color(1.0, 0.75, 0.3), clampf(w / maxf(cap, 1.0), 0.0, 1.0))
	_weight_label.text = "Масса  %.1f / %.0f т      скорость ×%.2f" % [w, cap, st["speed_factor"]]
	var total: float = st["energy_total"]
	var res: float = st["energy_reserved"]
	_energy_bar.value = clampf(res / maxf(total, 1.0), 0.0, 1.0)
	_energy_fill.bg_color = Color(0.98, 0.8, 0.25) if total - res >= Cfg.min_energy_pool else Color(1.0, 0.3, 0.25)
	_energy_label.text = "Резерв энергии  %.0f / %.0f      в бою останется %.0f" % [res, total, maxf(total - res, 0.0)]

	# полоски главных чисел и сравнение с тем, что было при открытии
	var sm := _summary(r)
	for k in _bar_items:
		var it: Dictionary = _bar_items[k]
		var v: float = sm[k]
		it["bar"].value = clampf(v / it["max"], 0.0, 1.0)
		var d: float = v - _base.get(k, v)
		var dt := ""
		if absf(d) > 0.05:
			dt = "  (%s%s)" % ["+" if d > 0 else "−", Parts._n(snappedf(absf(d), 0.1 if absf(d) < 10.0 else 1.0))]
		it["label"].text = "%s  %s%s" % [it["title"], Parts._n(snappedf(v, 0.1 if v < 30.0 else 1.0)), dt]
		it["fill"].bg_color = Color(0.45, 0.8, 1.0)
		if dt != "":
			it["label"].add_theme_color_override("font_color", Color(0.5, 1.0, 0.5) if d > 0 else Color(1.0, 0.5, 0.4))
		else:
			it["label"].add_theme_color_override("font_color", Color(1, 1, 1, 0.8))

	_problems.text = "  ·  ".join(r["problems"]) if not r["ok"] else ""
	_apply_btn.disabled = not r["ok"]
	_info.text = _full_text(r)


# все числа сборки (окно «Подробнее»)
func _full_text(r: Dictionary) -> String:
	var st: Dictionary = r["stats"]
	var t := ""
	t += "[b]%s[/b]  ·  %s\n%s\n\n" % [Parts.pname(st["mech"]), Parts.text(st["mech"], "class"), Parts.text(st["mech"], "trait")]
	t += "Здоровье  %.0f\n" % st["hp"]
	t += "Скорость  %.1f ходьба / %.1f бег\n" % [st["walk_speed"], st["run_speed"]]
	t += "Разгон  %.0f      Рывок  %.1f м каждые %.1f с%s\n" % [st["accel"], st["dash_speed"] * st["dash_time"], st["dash_cooldown"],
		(", зарядов %d" % int(st["dash_charges"])) if st["dash_charges"] > 1.0 else ""]
	t += "Поворот  ноги %.0f°/с, корпус %.0f°/с\n" % [st["legs_turn_speed"], st["torso_turn_speed"]]
	t += "Энергия  %.0f, восстановление %.1f/с\n" % [st["energy_max"], st["energy_regen"]]
	t += "Хитбокс  радиус %.2f м\n" % st["hit_radius"]
	t += "Обзор  %.0f м, омни-сенсор %.0f м\n" % [st["vision"], st["omni"]]
	if st["resist_explosion"] > 0.0 or st["resist_stun"] > 0.0:
		t += "Защита  от взрывов %d%%, от оглушения %d%%\n" % [int(st["resist_explosion"] * 100), int(st["resist_stun"] * 100)]
	if st["armor_flat"] > 0.0:
		t += "Бронеплиты  −%.1f урона с каждого попадания\n" % st["armor_flat"]
	if st["regen_hp"] > 0.0:
		t += "Самопочинка  %.1f HP/с после %.1f с без урона\n" % [st["regen_hp"], st["regen_delay"]]
	if st["brace_bonus"] > 0.0:
		t += "Упор  стоя %.1f с: дальность +%d%%\n" % [st["brace_time"], int(st["brace_bonus"] * 100)]
	if st["ram_damage"] > 0.0:
		t += "Таран  %.0f урона и оглушение %.1f с\n" % [st["ram_damage"], st["ram_stun"]]
	if st["cd_mult"] < 0.999:
		t += "Перезарядка абилок  быстрее на %d%%\n" % int(round((1.0 - st["cd_mult"]) * 100))
	t += "\n[b]Оружие[/b]\n"
	for i in r["weapons"].size():
		var ws: Dictionary = r["weapons"][i]
		t += "%s  %s: %s\n" % ["ЛКМ" if i == 0 else "ПКМ", ws["name"], Parts.describe(ws["id"])]
	t += "\n[b]Абилки[/b]\n"
	if r["abilities"].is_empty():
		t += "нет\n"
	for i in r["abilities"].size():
		var a: Dictionary = r["abilities"][i]
		t += "%s  %s: %.0f эн., перезарядка %.1f с" % [Parts.ABILITY_KEY_NAMES[i], a["name"], a["params"]["cost"], a["params"]["cooldown"] * st["cd_mult"]]
		if a["params"].get("charges", 0.0) > 0.0:
			t += ", зарядов %d" % int(a["params"]["charges"])
		t += "\n"
	return t


# ------------------------------------------------------------------
#  Сохранённые сборки
# ------------------------------------------------------------------

func _refresh_builds() -> void:
	_builds_opt.clear()
	_builds_opt.add_item("— выбрать —")
	var names := Parts.saved_builds.keys()
	names.sort()
	for n in names:
		_builds_opt.add_item(n)
	_builds_opt.select(0)


func _on_build_picked(i: int) -> void:
	if i <= 0:
		return
	var n := _builds_opt.get_item_text(i)
	if Parts.saved_builds.has(n):
		_build = Parts.saved_builds[n].duplicate(true)
		_refresh_rows()
		_refresh_info()


func _ask_save_build() -> void:
	for c in _popup.get_children():
		c.queue_free()
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(420, 0)
	col.add_theme_constant_override("separation", 8)
	_popup.add_child(col)
	col.add_child(_label("Название сборки", 18))
	var le := LineEdit.new()
	le.text = Parts.pname(_build["mech"]) + " " + Parts.pname(_build["weapons"][0])
	le.add_theme_font_size_override("font_size", 18)
	col.add_child(le)
	var ok := _button("Сохранить")
	var do_save := func() -> void:
		Parts.save_build(le.text, _clean_build())
		_popup.hide()
		_refresh_builds()
		for k in _builds_opt.item_count:
			if _builds_opt.get_item_text(k) == le.text.strip_edges():
				_builds_opt.select(k)
	ok.pressed.connect(do_save)
	le.text_submitted.connect(func(_t: String) -> void: do_save.call())
	col.add_child(ok)
	_popup.popup_centered(Vector2i(460, 160))
	le.grab_focus()
	le.select_all()


func _clean_build() -> Dictionary:
	var b := _build.duplicate(true)
	# пустые слоты модулей не храним
	var mods: Array = []
	for m in b["modules"]:
		if m != "":
			mods.append(m)
	b["modules"] = mods
	return b


func _on_apply() -> void:
	var b := _clean_build()
	close()
	applied.emit(b)


# ------------------------------------------------------------------
#  3D-витрина: мех на платформе в своём маленьком мире, камера медленно облетает
# ------------------------------------------------------------------

func _build_preview(svc: SubViewportContainer) -> void:
	_preview_vp = SubViewport.new()
	_preview_vp.own_world_3d = true
	_preview_vp.msaa_3d = Viewport.MSAA_4X
	_preview_vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	svc.add_child(_preview_vp)
	_preview_root = Node3D.new()
	_preview_root.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_preview_vp.add_child(_preview_root)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.035, 0.04, 0.05)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.56, 0.68)
	env.ambient_light_energy = 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.1
	env.glow_enabled = true
	env.glow_intensity = 0.8
	env.glow_hdr_threshold = 0.9
	env.fog_enabled = true
	env.fog_light_color = Color(0.05, 0.06, 0.08)
	env.fog_density = 0.035
	var we := WorldEnvironment.new()
	we.environment = env
	_preview_root.add_child(we)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-40, 35, 0)
	key.light_energy = 1.4
	key.light_color = Color(1.0, 0.95, 0.88)
	key.shadow_enabled = true
	_preview_root.add_child(key)
	# контровой свет цвета команды сзади и холодный сбоку
	for l in [[Vector3(-4, 4, -5), Cfg.player_color, 6.0], [Vector3(6, 3, 2), Color(0.4, 0.6, 1.0), 3.0]]:
		var o := OmniLight3D.new()
		o.position = l[0]
		o.light_color = l[1]
		o.light_energy = l[2]
		o.omni_range = 14.0
		_preview_root.add_child(o)

	# пол ангара: металлические плиты, платформа с огнями
	var floor_m := ShaderMaterial.new()
	floor_m.shader = WorldShader
	floor_m.set_shader_parameter("albedo", Color(0.2, 0.21, 0.23))
	floor_m.set_shader_parameter("mode", 2)
	floor_m.set_shader_parameter("roughness", 0.45)
	floor_m.set_shader_parameter("metallic", 0.5)
	var fl := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	fl.mesh = pm
	fl.material_override = floor_m
	_preview_root.add_child(fl)
	var plat := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 4.2
	cm.bottom_radius = 4.5
	cm.height = 0.3
	cm.radial_segments = 48
	plat.mesh = cm
	var plat_m := StandardMaterial3D.new()
	plat_m.albedo_color = Color(0.13, 0.14, 0.16)
	plat_m.metallic = 0.6
	plat_m.roughness = 0.35
	plat.material_override = plat_m
	plat.position.y = 0.15
	_preview_root.add_child(plat)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 4.1
	tm.outer_radius = 4.3
	tm.rings = 64
	ring.mesh = tm
	var ring_m := StandardMaterial3D.new()
	ring_m.albedo_color = Cfg.player_color
	ring_m.emission_enabled = true
	ring_m.emission = Cfg.player_color
	ring_m.emission_energy_multiplier = 2.5
	ring.material_override = ring_m
	ring.scale = Vector3(1, 0.3, 1)
	ring.position.y = 0.3
	_preview_root.add_child(ring)

	_preview_cam = Camera3D.new()
	_preview_cam.fov = 40.0
	_preview_root.add_child(_preview_cam)


func _update_preview(r: Dictionary) -> void:
	var st: Dictionary = r["stats"]
	var look := {
		"legs_scale": st["legs_scale"],
		"hull_scale": st["hull_scale"],
		"style": st["style"],
		"weapons": [r["weapons"][0]["look"], r["weapons"][1]["look"]],
		"rockets": r["abilities"].any(func(a): return a["type"] == "rockets"),
	}
	var key := str(look)
	if key == _preview_key and _preview_mech != null:
		_preview_mech.st = st
		return
	_preview_key = key
	if _preview_mech != null:
		_preview_mech.queue_free()
	_preview_mech = MechVisual.new()
	_preview_mech.st = st
	_preview_root.add_child(_preview_mech)
	_preview_mech.build(Cfg.player_color, Color(1, 1, 1), look)
	_preview_mech.position.y = 0.3


func _process(delta: float) -> void:
	if not _root.visible or _preview_mech == null:
		return
	# мех стоит на платформе, корпус чуть поворачивается, камера облетает
	var t := Time.get_ticks_msec() * 0.001
	_preview_mech.update_visual(delta, Vector3(0, 0.3, 0), Vector3.ZERO, 0.0, sin(t * 0.6) * 0.35, false)
	_cam_angle += delta * 0.25
	var size: float = 2.0 + (_preview_mech.ls + _preview_mech.hs) * 2.6
	var target := Vector3(0, 1.6 + _preview_mech.ls * 0.9, 0)
	_preview_cam.position = target + Vector3(sin(_cam_angle) * size * 1.9, size * 0.5, cos(_cam_angle) * size * 1.9)
	_preview_cam.look_at(target, Vector3.UP)
