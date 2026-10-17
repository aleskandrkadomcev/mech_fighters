extends CanvasLayer
## Надписи на экране: подсказка по кнопкам, здоровье, энергия, слоты рывка, телепорта и абилок, счёт,
## таймер боя, отметка попадания у прицела, красная вспышка при попадании, экран смерти, цифры для настройки (F1).

const COL_ENERGY := Color(0.98, 0.8, 0.25)
const COL_ACTIVE := Color(0.45, 0.85, 1.0)
const COL_DENY := Color(1.0, 0.3, 0.25)
const COL_BAD := Color(1.0, 0.38, 0.32)     # статус вредный (оглушён, ЭМИ, замедлен)
const COL_GOOD := Color(0.5, 0.95, 0.55)    # статус полезный (чинится, щит, невидим)
const SLOT := 62.0                # слот абилки, px
const SLOT_SMALL := 48.0          # слоты рывка и телепорта
const SLOT_SEP := 6
const STATUS_SIZE := 36.0         # значок статуса
const BAR_W := 420.0              # полоски здоровья и энергии не уже этого (иначе — по ширине ряда абилок)
# вид абилки — цвет подложки слота: 0 урон (оранжевый), 1 контроль (фиолетовый), 2 защита (синий), 3 прочее (зелёный)
const KIND_COL := [Color(1.0, 0.55, 0.2), Color(0.75, 0.45, 1.0), Color(0.35, 0.65, 1.0), Color(0.4, 0.9, 0.5)]
const AB_KIND := {"rockets": 0, "airstrike": 0, "mine": 0, "napalm": 0, "jump": 0, "turret": 0, "roller": 0, "slug": 0, "rapid": 0,
	"emp": 1, "bolas": 1, "jammer": 1, "emp_shell": 1, "gravity": 1, "repulse": 1, "marker": 1,
	"shield": 2, "repair": 2, "barricade": 2, "drone": 2, "stance": 2, "dome": 2, "matrix": 2, "purge": 2}

var mech: Node3D
var main: Node3D
var _hint: Label
var _dbg: Label
var _dash: ProgressBar
var _energy: ProgressBar
var _energy_fill: StyleBoxFlat
var _energy_label: Label
var _energy_tick: ColorRect
var _slots: Array = []
var _slot_row: HBoxContainer
var _status_row: HBoxContainer    # статусы своего меха над полосками здоровья и энергии
var _status_chips: Array = []     # [{panel, style, icon, label, name, desc, icon_name}], заводятся по мере надобности и прячутся
var _icons := {}                  # значки assets/ui/hud по имени (null — файла нет)
var _tip: PanelContainer          # подсказка на Alt
var _tip_title: Label
var _tip_sub: Label
var _tip_body: Label
var _tip_key := ""                # что сейчас в подсказке: текст пересобирается, только когда навели на другое
var _alt := false                 # Alt зажат: курсор-стрелка, наведение показывает подсказки
var _deny_t := 0.0
var _deny_slot := -1
var _cd_tip: Label               # таймер у курсора: нажал абилку на перезарядке — сколько ей осталось («2,35»), тает за 1 с
var _cd_tip_t := 0.0
var _cd_tip_i := 0
var _hp: ProgressBar
var _hp_fill: StyleBoxFlat
var _hp_label: Label
var _vignette: ColorRect
var _vignette_mat: ShaderMaterial
var _hit_t := 0.0
var _score: Label
var _death: Label
var _ammo: Label
var _ammo_deny := 0.0
var _root: Control
var _over: Label
var _timer: Label
var _dash_slot: Dictionary
var _tp_slot: Dictionary
var _hitmark: Control
# метки (пинги): Alt+клик — обычная метка; Alt + зажатая ЛКМ — круговое меню ~200 px вокруг места нажатия:
# повёл мышь в сторону и отпустил — метка этого вида; отпустил в середине — отмена
const PING_WHEEL_R := 100.0       # радиус круга (ширина 200 px)
const PING_WHEEL_IN := 26.0       # середина круга: отпустил здесь — отмена
const PING_HOLD := 0.18           # столько держать ЛКМ (или сдвинуть мышь), чтобы открылось меню
const PING_SECTORS := [["attack", -PI / 2.0], ["going", 0.0], ["help", PI / 2.0], ["attention", PI]]   # вверх, вправо, вниз, влево
var _wheel: Control
var _ping_hold := false
var _ping_t := 0.0
var _ping_press := Vector2.ZERO   # где нажали (экран): там середина меню
var _ping_pos := Vector3.ZERO     # куда встанет метка (мир): место прицела или точка миникарты в миг нажатия
var _ping_sel := ""               # что выбрано в меню («» — середина, отмена)
var _ping_mouse := Vector2.ZERO   # где мышь, пока держат Alt+ЛКМ (по событиям движения)
var _hitmark_shown := false
var _vignette_last := -1.0
var _hitmark_t := 0.0
var _hitmark_kill := false
var _hint_full := true
var _minimap: Control
var _feed: VBoxContainer          # лента убийств справа сверху
var _announce: Label              # крупная подпись по центру сверху: «Радар захвачен»
var _announce_tw: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS     # экран победы и R работают и на паузе
	var root := Control.new()
	_root = root
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# красная пелена: вспыхивает при попадании, слегка держится при малом здоровье
	_vignette = ColorRect.new()
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vsh := Shader.new()
	vsh.code = """shader_type canvas_item;
uniform float strength = 0.0;
void fragment() {
	// 0 в центре экрана, 1 в углах: краснеют только края
	float d = length(UV - vec2(0.5)) * 1.42;
	COLOR = vec4(0.9, 0.05, 0.05, smoothstep(0.5, 1.05, d) * strength);
}
"""
	_vignette_mat = ShaderMaterial.new()
	_vignette_mat.shader = vsh
	_vignette.material = _vignette_mat
	root.add_child(_vignette)

	_score = _label("", 22)
	_score.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_score.offset_left = -600
	_score.offset_right = 600
	_score.offset_top = 62
	_score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_score)

	_death = _label("", 44)
	_death.set_anchors_preset(Control.PRESET_CENTER)
	_death.offset_left = -500
	_death.offset_right = 500
	_death.offset_top = -160
	_death.offset_bottom = -40
	_death.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_death.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_death.visible = false
	root.add_child(_death)

	_hint = _label("", 16)
	_hint.position = Vector2(28, 20)
	_hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	root.add_child(_hint)
	_set_hint()

	_timer = _label("0:00", 30)
	_timer.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_timer.offset_left = -100
	_timer.offset_right = 100
	_timer.offset_top = 14
	_timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_timer)

	# отметка попадания: крестик у курсора, когда твой выстрел попал во врага
	_hitmark = Control.new()
	_hitmark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hitmark.size = Vector2(40, 40)
	_hitmark.draw.connect(_draw_hitmark)
	root.add_child(_hitmark)

	_wheel = Control.new()
	_wheel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wheel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_wheel.visible = false
	_wheel.draw.connect(_draw_wheel)
	root.add_child(_wheel)
	Battle.player_hit.connect(_on_player_hit)

	_dbg = _label("", 22)
	_dbg.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_dbg.offset_left = -420
	_dbg.offset_right = -28
	_dbg.offset_top = 20
	_dbg.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(_dbg)

	_feed = VBoxContainer.new()
	_feed.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_feed.offset_left = -620
	_feed.offset_right = -28
	_feed.offset_top = 160
	_feed.alignment = BoxContainer.ALIGNMENT_BEGIN
	_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_feed.add_theme_constant_override("separation", 4)
	root.add_child(_feed)
	Battle.feed.connect(_on_feed)

	_announce = _label("", 40)
	_announce.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_announce.offset_left = -500
	_announce.offset_right = 500
	_announce.offset_top = 150
	_announce.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_announce.add_theme_constant_override("outline_size", 10)
	_announce.visible = false
	root.add_child(_announce)
	Battle.poi_captured.connect(_on_poi_captured)

	# нижняя панель как в доте: снизу абилки, над ними здоровье и энергия, над ними статусы; под абилками патроны
	var bottom := VBoxContainer.new()
	bottom.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bottom.offset_left = -460
	bottom.offset_right = 460
	bottom.offset_top = -260
	bottom.offset_bottom = -12
	bottom.alignment = BoxContainer.ALIGNMENT_END
	bottom.add_theme_constant_override("separation", 5)
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bottom)

	_status_row = HBoxContainer.new()
	_status_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_status_row.add_theme_constant_override("separation", 5)
	_status_row.custom_minimum_size = Vector2(0, STATUS_SIZE)   # место под статусы есть всегда: полоски не прыгают
	_status_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_child(_status_row)

	_hp_fill = StyleBoxFlat.new()
	_hp_fill.bg_color = Color(0.4, 0.9, 0.4)
	_hp = _bar(Vector2(BAR_W, 22), _hp_fill)
	_hp.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	bottom.add_child(_hp)
	_hp_label = _bar_label(_hp, 16)

	_energy_fill = StyleBoxFlat.new()
	_energy_fill.bg_color = COL_ENERGY
	_energy = _bar(Vector2(BAR_W, 16), _energy_fill)
	_energy.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	bottom.add_child(_energy)
	_energy_tick = ColorRect.new()
	_energy_tick.color = Color(0, 0, 0, 0.75)
	_energy_tick.size = Vector2(2, 16)
	_energy_tick.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_energy.add_child(_energy_tick)
	_energy_label = _bar_label(_energy, 13)

	_slot_row = HBoxContainer.new()
	_slot_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_slot_row.add_theme_constant_override("separation", SLOT_SEP)
	_slot_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_child(_slot_row)

	_ammo = _label("", 15)
	_ammo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bottom.add_child(_ammo)

	_over = _label("", 72)
	_over.set_anchors_preset(Control.PRESET_CENTER)
	_over.offset_left = -600
	_over.offset_right = 600
	_over.offset_top = -200
	_over.offset_bottom = 0
	_over.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_over.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_over.visible = false
	root.add_child(_over)

	# подсказка на Alt: навёл на абилку или статус — окно с описанием, как в доте
	_tip = PanelContainer.new()
	_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip.visible = false
	var tsb := StyleBoxFlat.new()
	tsb.bg_color = Color(0.05, 0.06, 0.08, 0.94)
	tsb.border_color = Color(0.6, 0.65, 0.72, 0.8)
	tsb.set_border_width_all(2)
	tsb.set_corner_radius_all(4)
	tsb.content_margin_left = 12
	tsb.content_margin_right = 12
	tsb.content_margin_top = 8
	tsb.content_margin_bottom = 10
	_tip.add_theme_stylebox_override("panel", tsb)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 4)
	tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip.add_child(tv)
	_tip_title = _label("", 20)
	tv.add_child(_tip_title)
	_tip_sub = _label("", 14)
	_tip_sub.add_theme_color_override("font_color", Color(0.7, 0.76, 0.85))
	tv.add_child(_tip_sub)
	_tip_body = _label("", 15)
	_tip_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip_body.custom_minimum_size = Vector2(330, 0)
	tv.add_child(_tip_body)
	root.add_child(_tip)


func add_minimap(mm: Control) -> void:
	_minimap = mm
	_root.add_child(mm)
	mm.anchor_left = 0.0
	mm.anchor_right = 0.0
	mm.anchor_top = 1.0
	mm.anchor_bottom = 1.0
	mm.offset_left = 24
	mm.offset_bottom = -24
	mm.offset_top = -234
	mm.offset_right = 384


func show_game_over(won: bool, draw := false) -> void:
	_over.visible = true
	_over.text = "НИЧЬЯ" if draw else ("ПОБЕДА" if won else "ПОРАЖЕНИЕ")
	_over.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4) if draw else (Color(0.5, 1.0, 0.5) if won else Color(1.0, 0.4, 0.35)))


func bind(m: Node3D) -> void:
	mech = m
	mech.ability_denied.connect(_on_denied)
	mech.damaged.connect(_on_hit)
	mech.build_changed.connect(_rebuild_slots)
	if is_node_ready():
		_rebuild_slots()


func _rebuild_slots() -> void:
	if _slot_row == null or mech == null:
		return
	for c in _slot_row.get_children():
		_slot_row.remove_child(c)
		c.queue_free()
	_slots.clear()
	# рывок и телепорт есть у всех: отдельные слоты слева (в PvP базы нет — и телепорта нет)
	_dash_slot = _make_slot(_slot_row, -1, "Пробел", "dash")
	_tp_slot = {} if Battle.pvp else _make_slot(_slot_row, -1, "T", "teleport")
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(10, 0)
	_slot_row.add_child(gap)
	for i in mech.abilities.size():
		_slots.append(_make_slot(_slot_row, i))
	# полоски здоровья и энергии — по ширине ряда абилок
	var small := 1 if _tp_slot.is_empty() else 2
	var w: float = small * SLOT_SMALL + mech.abilities.size() * SLOT + 10.0 + SLOT_SEP * (_slot_row.get_child_count() - 1)
	var bw := maxf(BAR_W, w)
	_hp.custom_minimum_size.x = bw
	_energy.custom_minimum_size.x = bw


func _set_hint() -> void:
	if _hint_full:
		_hint.text = "WASD ходьба   Shift бег   Пробел рывок" + ("" if Battle.pvp else "   T на базу") + "\nЛКМ / ПКМ пушки   Q E R F C V G X абилки   B ангар\nF2 настройки   F3 хитбоксы   F1 цифры   Колесо зум\nAlt+клик метка (держать — меню меток)   Alt + навести — описание абилки или статуса\nH скрыть подсказку   Esc меню"
	else:
		_hint.text = "H  подсказка"


func _on_player_hit(target: Node, _amount: float) -> void:
	_hitmark_t = 0.18
	_hitmark_kill = target.get("dead") == true or (target.get("hp") != null and target.hp <= 0.0)
	if _hitmark_kill:
		_hitmark_t = 0.4


# строка ленты: «кто ✕ кого», свои голубым, враги красным; через 6 с тает
func _on_feed(killer: String, killer_team: int, victim: String, victim_team: int) -> void:
	var my_team: int = mech.team if mech != null else 0
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 10)
	var parts := []
	if killer != "":
		parts.append([killer, killer_team])
	parts.append(["✕", -2])
	parts.append([victim, victim_team])
	for pr in parts:
		var l := _label(pr[0], 18)
		var t: int = pr[1]
		var c := Color(1, 1, 1, 0.8)
		if t >= 0:
			c = Color(0.55, 0.85, 1.0) if t == my_team else Color(1.0, 0.45, 0.4)
		elif t == -2:
			c = Color(1.0, 0.85, 0.5)
		l.add_theme_color_override("font_color", c)
		row.add_child(l)
	_feed.add_child(row)
	while _feed.get_child_count() > 5:
		var old := _feed.get_child(0)
		_feed.remove_child(old)
		old.queue_free()
	var tw := row.create_tween()
	tw.tween_interval(6.0)
	tw.tween_property(row, "modulate:a", 0.0, 0.8)
	tw.tween_callback(row.queue_free)


func _on_poi_captured(title: String, team: int) -> void:
	var mine: bool = team == (mech.team if mech != null else 0)
	_announce.text = ("%s захвачен" % title) if mine else ("Враг захватил: %s" % title)
	_announce.add_theme_color_override("font_color", Color(0.55, 0.85, 1.0) if mine else Color(1.0, 0.45, 0.4))
	_announce.visible = true
	_announce.modulate.a = 1.0
	if _announce_tw != null:
		_announce_tw.kill()
	_announce_tw = _announce.create_tween()
	_announce_tw.tween_interval(2.2)
	_announce_tw.tween_property(_announce, "modulate:a", 0.0, 0.6)
	_announce_tw.tween_callback(func() -> void: _announce.visible = false)


func _send_ping(kind: String) -> void:
	Fx.ping(_ping_pos, mech.team, kind)
	if _minimap != null:
		_minimap.add_ping(_ping_pos, kind)


func _ping_end() -> void:
	_ping_hold = false
	Cfg.ping_hold = false
	if _wheel.visible:
		_wheel.visible = false


# пока держат Alt+ЛКМ: открыть меню (подержал или повёл мышь) и подсвечивать выбранное
func _update_ping_wheel(delta: float) -> void:
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_ping_end()           # отпускание ушло мимо (окно потеряло фокус) — просто закрыть
		return
	_ping_t += delta
	var mouse := _ping_mouse
	if not _wheel.visible and (_ping_t >= PING_HOLD or mouse.distance_to(_ping_press) > 12.0):
		# середина меню — там, где нажали, но круг целиком на экране
		var vs := get_viewport().get_visible_rect().size
		var m := PING_WHEEL_R + 8.0
		_ping_press = Vector2(clampf(_ping_press.x, m, vs.x - m), clampf(_ping_press.y, m, vs.y - m))
		_wheel.visible = true
		_wheel.queue_redraw()
	if _wheel.visible:
		var sel := _wheel_pick(mouse)
		if sel != _ping_sel:
			_ping_sel = sel
			_wheel.queue_redraw()


# какой сектор меню под точкой экрана («» — середина)
func _wheel_pick(p: Vector2) -> String:
	var d := p - _ping_press
	if d.length() < PING_WHEEL_IN:
		return ""
	var a := d.angle()
	for s in PING_SECTORS:
		if absf(angle_difference(a, s[1])) <= PI / 4.0:
			return s[0]
	return ""


func _draw_wheel() -> void:
	var c := _ping_press
	_wheel.draw_circle(c, PING_WHEEL_R, Color(0, 0, 0, 0.5))
	for s in PING_SECTORS:
		var info: Dictionary = Fx.PINGS[s[0]]
		var col: Color = info["col"]
		var on: bool = s[0] == _ping_sel
		# сектор: кольцо от середины до края на четверть круга
		var pts := PackedVector2Array()
		var a0: float = s[1] - PI / 4.0 + 0.04
		var a1: float = s[1] + PI / 4.0 - 0.04
		for i in 11:
			pts.append(c + Vector2.from_angle(lerpf(a0, a1, i / 10.0)) * (PING_WHEEL_R - 4.0))
		for i in 11:
			pts.append(c + Vector2.from_angle(lerpf(a1, a0, i / 10.0)) * (PING_WHEEL_IN + 4.0))
		_wheel.draw_colored_polygon(pts, Color(col.r, col.g, col.b, 0.55 if on else 0.16))
		var outline := pts.duplicate()
		outline.append(pts[0])
		_wheel.draw_polyline(outline, Color(col.r, col.g, col.b, 1.0 if on else 0.5), 2.0 if on else 1.0, true)
		# значок метки в середине сектора, выбранный крупнее
		var sz := 48.0 if on else 38.0
		var ic := c + Vector2.from_angle(s[1]) * 63.0
		_wheel.draw_texture_rect(info["icon"], Rect2(ic - Vector2(sz, sz) * 0.5, Vector2(sz, sz)), false, col if on else Color(col.r, col.g, col.b, 0.8))
	# середина: отпустил здесь — отмена
	_wheel.draw_arc(c, PING_WHEEL_IN - 2.0, 0, TAU, 24, Color(1, 1, 1, 0.35 if _ping_sel != "" else 0.8), 2.0, true)


func _draw_hitmark() -> void:
	if _hitmark_t <= 0.0:
		return
	var c := Color(1.0, 0.3, 0.25, minf(_hitmark_t * 6.0, 1.0)) if _hitmark_kill else Color(1, 1, 1, minf(_hitmark_t * 6.0, 1.0))
	var cpos := _hitmark.size * 0.5
	for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
		_hitmark.draw_line(cpos + d * 6.0, cpos + d * 14.0, c, 3.0)


func _label(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


# подпись по центру полоски («850 / 1200»)
func _bar_label(bar: Control, size: int) -> Label:
	var l := _label("", size)
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_constant_override("outline_size", 5)
	bar.add_child(l)
	return l


func _bar(min_size: Vector2, fill: StyleBoxFlat) -> ProgressBar:
	var b := ProgressBar.new()
	b.custom_minimum_size = min_size
	b.show_percentage = false
	b.min_value = 0.0
	b.max_value = 1.0
	b.step = 0.0
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.55)
	b.add_theme_stylebox_override("background", bg)
	b.add_theme_stylebox_override("fill", fill)
	return b


# значок интерфейса по имени (assets/ui/hud, рисует tools/make_hud_icons.py); null — файла нет
func _icon(n: String) -> Texture2D:
	if not _icons.has(n):
		var path := "res://assets/ui/hud/%s.png" % n
		_icons[n] = load(path) if ResourceLoader.exists(path) else null
	return _icons[n]


func _icon_rect(tex: Texture2D, pos: Vector2, side: float) -> TextureRect:
	var ic := TextureRect.new()
	ic.texture = tex
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.position = pos
	ic.size = Vector2(side, side)
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return ic


# слот абилки: значок, клавиша, цена, затемнение пока перезаряжается
func _make_slot(parent: Control, index: int, key_text := "", icon_name := "") -> Dictionary:
	var small := index < 0
	var side := SLOT_SMALL if small else SLOT
	if not small:
		icon_name = mech.abilities[index]["type"]
	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(side, side)
	panel.size_flags_vertical = Control.SIZE_SHRINK_END     # маленькие слоты стоят по низу ряда
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.clip_contents = true
	var sb := StyleBoxFlat.new()
	var kc: Color = KIND_COL[AB_KIND.get(icon_name, 3)]
	sb.bg_color = Color(kc.r * 0.28, kc.g * 0.28, kc.b * 0.28, 0.9)
	sb.set_border_width_all(2)
	sb.border_color = Color(1, 1, 1, 0.5)
	sb.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", sb)
	parent.add_child(panel)

	var tex := _icon(icon_name)
	if tex != null:
		var m := side * 0.15
		panel.add_child(_icon_rect(tex, Vector2(m, m), side - m * 2.0))
	else:     # значка нет — название словом
		var title := _label(mech.abilities[index]["short"] if not small else icon_name, 12)
		title.set_anchors_preset(Control.PRESET_FULL_RECT)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		panel.add_child(title)

	var key := _label(key_text if small else Parts.ABILITY_KEY_NAMES[index], 11 if key_text.length() > 2 else 15)
	key.position = Vector2(4, 0)
	key.add_theme_constant_override("outline_size", 5)
	panel.add_child(key)

	var cost := _label("", 12)
	cost.position = Vector2(0, side - 19)
	cost.size = Vector2(side - 4, 18)
	cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cost.add_theme_color_override("font_color", COL_ENERGY)
	panel.add_child(cost)

	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.62)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.size = Vector2(side, 0)
	panel.add_child(shade)

	var cd := _label("", 18 if small else 22)
	cd.set_anchors_preset(Control.PRESET_FULL_RECT)
	cd.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cd.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	panel.add_child(cd)

	return {"panel": panel, "style": sb, "cost": cost, "shade": shade, "cd": cd, "index": index, "icon": icon_name}


func _on_hit(amount: float) -> void:
	_hit_t = clampf(_hit_t + 0.25 + amount * 0.02, 0.0, 1.0)


func _on_denied(index: int, reason: String) -> void:
	if reason == "ammo":
		_ammo_deny = 0.35
		return
	_deny_t = 0.3
	_deny_slot = index if (reason == "cooldown" or reason == "charges") else -2    # -2 = не хватило энергии
	if reason == "cooldown" and mech != null and mech.cooldown_left(index) > 0.01:
		if _cd_tip == null:
			_cd_tip = _label("", 18)
			_root.add_child(_cd_tip)
		_cd_tip_i = index
		_cd_tip_t = 1.0
		_update_cd_tip(0.0)


# таймер у курсора идёт вместе с перезарядкой и тает за секунду
func _update_cd_tip(delta: float) -> void:
	if _cd_tip == null:
		return
	_cd_tip_t = maxf(_cd_tip_t - delta, 0.0)
	_cd_tip.visible = _cd_tip_t > 0.0
	if not _cd_tip.visible:
		return
	_txt(_cd_tip, ("%.2f" % mech.cooldown_left(_cd_tip_i)).replace(".", ","))
	_cd_tip.position = get_viewport().get_mouse_position() + Vector2(18, -30)
	_cd_tip.modulate.a = _cd_tip_t


func _input(event: InputEvent) -> void:
	if _ping_hold and event is InputEventMouseMotion:
		_ping_mouse = event.position


func _unhandled_input(event: InputEvent) -> void:
	# Alt+ЛКМ: метка для своей команды (по миникарте или по месту прицела). Ставится, когда ЛКМ отпустили:
	# быстрый клик — обычная метка, зажал — круговое меню
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and mech != null:
		if event.pressed and event.alt_pressed and _tip.visible:
			get_viewport().set_input_as_handled()     # клик по значку под подсказкой — не метка
			return
		if event.pressed and event.alt_pressed:
			var pos = _minimap.world_at(event.position) if _minimap != null else null
			if pos == null:
				pos = Vector3(mech.aim_point.x, 0, mech.aim_point.z)
			_ping_pos = pos
			_ping_press = event.position
			_ping_mouse = event.position
			_ping_hold = true
			_ping_t = 0.0
			_ping_sel = ""
			Cfg.ping_hold = true
			get_viewport().set_input_as_handled()
			return
		if not event.pressed and _ping_hold:
			if _wheel.visible:
				_ping_sel = _wheel_pick(event.position)
				if _ping_sel != "":
					_send_ping(_ping_sel)
			else:
				_send_ping("")
			_ping_end()
			get_viewport().set_input_as_handled()
			return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_F1:
			_dbg.visible = not _dbg.visible
		elif event.physical_keycode == KEY_H:
			_hint_full = not _hint_full
			_set_hint()


func _process(delta: float) -> void:
	if mech == null:
		return
	_deny_t = maxf(_deny_t - delta, 0.0)
	if _ping_hold:
		_update_ping_wheel(delta)
	_ammo_deny = maxf(_ammo_deny - delta, 0.0)
	if _cd_tip_t > 0.0:
		_update_cd_tip(delta)

	# патроны: ЛКМ и ПКМ (две одинаковые пушки при настройке «на ЛКМ» обе подписаны ЛКМ)
	var parts: Array = []
	var linked: bool = Cfg.link_guns > 0 and mech.weapons[0]["id"] == mech.weapons[1]["id"]
	for i in 2:
		var w: Dictionary = mech.weapons[i]
		var key := "ЛКМ" if i == 0 or linked else "ПКМ"
		var mx: float = mech.ammo_max(i)
		if mx > 0.0:
			parts.append("%s  %s  %d / %d" % [key, w["name"], int(mech.ammo[i]), int(mx)])
		else:
			parts.append("%s  %s  ∞" % [key, w["name"]])
	_txt(_ammo, "        ".join(parts))
	var empty: bool = (mech.ammo_max(0) > 0.0 and mech.ammo[0] < 1.0) or (mech.ammo_max(1) > 0.0 and mech.ammo[1] < 1.0)
	_font_col(_ammo, COL_DENY if (_ammo_deny > 0.0 or empty) else Color(1, 1, 1, 0.85))

	# здоровье
	var hp: float = mech.hp
	var hp_max: float = maxf(mech.max_hp(), 1.0)
	var hk := clampf(hp / hp_max, 0.0, 1.0)
	_hp.value = hk
	_bg(_hp_fill, Color(0.9, 0.25, 0.2).lerp(Color(0.4, 0.9, 0.4), hk))
	_txt(_hp_label, "%d / %d" % [int(ceil(maxf(hp, 0.0))), int(hp_max)])
	_update_statuses()
	_hit_t = maxf(_hit_t - delta * 2.5, 0.0)
	var low := clampf((0.3 - hk) / 0.3, 0.0, 1.0) * 0.22 if not mech.dead else 0.0
	var vig := clampf(_hit_t * 0.8 + low, 0.0, 0.9)
	if vig != _vignette_last:
		_vignette_last = vig
		_vignette_mat.set_shader_parameter("strength", vig)

	# счёт и экран смерти
	if main != null:
		var bonus: Array = []
		for p in get_tree().get_nodes_in_group("pois"):
			if p.owner_team == mech.team:
				bonus.append("%s: %s" % [p.title, p.bonus_text()])
		var score := ""
		if main.pvp:
			score = "Свои %d : %d Враги   (до %d)\nУбито: %d    Смертей: %d" % [main.team_kills[mech.team], main.team_kills[1 - mech.team],
				Cfg.pvp_kills_to_win, main.kills, main.deaths]
		else:
			score = "Убито: %d    Смертей: %d    Турели: наши %d, вражеские %d" % [main.kills, main.deaths, main.structures_left(mech.team), main.structures_left(1 - mech.team)]
		if not bonus.is_empty():
			score += "\n" + "    ".join(bonus)
		_txt(_score, score)
		if mech.dead:
			_death.visible = true
			_txt(_death, "МЕХ УНИЧТОЖЕН\nвозрождение через %.1f" % main.respawn_left())
		else:
			_death.visible = false

	# таймер боя (в PvP — сколько осталось) и отметка попадания
	if main != null and main.pvp:
		var left := int(ceil(main.time_left()))
		_txt(_timer, "%d:%02d" % [left / 60, left % 60])
	else:
		_txt(_timer, Battle.time_text())
	_hitmark_t = maxf(_hitmark_t - delta, 0.0)
	# отметку перерисовываем, только пока она видна (и ещё раз, чтобы стереть)
	if _hitmark_t > 0.0 or _hitmark_shown:
		_hitmark.position = get_viewport().get_mouse_position() - _hitmark.size * 0.5
		_hitmark.queue_redraw()
		_hitmark_shown = _hitmark_t > 0.0

	# рывок: заряды и перезарядка; телепорт: канал или перезарядка
	if not _dash_slot.is_empty():
		var chm: float = mech.stats.get("dash_charges", 1.0)
		var dk := 0.0
		if mech.dash_stock < 1.0:
			dk = clampf(mech.dash_cd / maxf(mech.stats["dash_cooldown"], 0.01), 0.0, 1.0)
		_slot_state(_dash_slot, dk, ("%.1f" % mech.dash_cd) if mech.dash_stock < 1.0 else "", "×%d" % int(mech.dash_stock) if chm > 1.0 else "", 0.0)
		if not _tp_slot.is_empty():
			var tk := clampf(mech.tp_cd / maxf(Cfg.tp_cooldown, 0.01), 0.0, 1.0)
			var tp_txt := ("%.0f" % mech.tp_cd) if mech.tp_cd > 0.05 else ""
			_slot_state(_tp_slot, tk, tp_txt, "", mech.tp_left)

	# энергия
	var en: float = mech.energy
	var en_max: float = maxf(mech.energy_max(), 1.0)
	_energy.value = clampf(en / en_max, 0.0, 1.0)
	var locked: bool = mech.run_locked
	var col := COL_ENERGY
	if _deny_t > 0.0 and _deny_slot == -2:
		col = COL_DENY
	elif locked:
		col = Color(0.95, 0.5, 0.2)
	_bg(_energy_fill, col)
	_txt(_energy_label, "%d / %d" % [int(en), int(en_max)] if not locked else "%d / %d   бег недоступен" % [int(en), int(en_max)])
	_energy_tick.visible = Cfg.run_energy_cost > 0.0
	var tick_pos := Vector2(_energy.size.x * clampf(Cfg.run_min_energy / en_max, 0.0, 1.0) - 1.0, 0)
	if _energy_tick.position != tick_pos:
		_energy_tick.position = tick_pos
	if _energy_tick.size != Vector2(2, _energy.size.y):
		_energy_tick.size = Vector2(2, _energy.size.y)

	# слоты абилок
	if _slots.size() != mech.abilities.size():
		_rebuild_slots()
	for i in mini(_slots.size(), mech.abilities.size()):
		var s: Dictionary = _slots[i]
		var cd: float = mech.ability_cd[i]
		var cd_max: float = maxf(mech.ability_cooldown_max(i), 0.01)
		var cost: float = mech.ability_cost(i)
		var enough: bool = en >= cost and (mech.ability_charges_max(i) <= 0.0 or mech.ability_charges[i] >= 1.0)
		var panel: Panel = s["panel"]
		var shade: ColorRect = s["shade"]
		var k := clampf(cd / cd_max, 0.0, 1.0)
		var shade_size := Vector2(panel.size.x, panel.size.y * k)
		var cd_text := ("%.1f" % cd) if cd > 0.05 else ""
		var cd_col = null
		# абилка действует прямо сейчас: голубая рамка и сколько осталось
		var act: float = mech.ability_active(i)
		var is_shield: bool = mech.abilities[i]["type"] == "shield"
		if act > 0.0:
			cd_text = "ВКЛ" if is_shield or mech.abilities[i]["type"] == "stance" else "%.1f" % act
			cd_col = COL_ACTIVE
			shade_size = Vector2.ZERO
		_shade(shade, shade_size, Vector2(0, panel.size.y * (1.0 - k)))
		_txt(s["cd"], cd_text)
		_font_col(s["cd"], cd_col)
		var cost_text := "%d" % int(cost)
		var chm: float = mech.ability_charges_max(i)
		if chm > 0.0:
			cost_text = "×%d  %s" % [int(mech.ability_charges[i]), cost_text]
		_txt(s["cost"], cost_text)
		_font_col(s["cost"], COL_ENERGY if enough else COL_DENY)
		var border := Color(1, 1, 1, 0.75)
		if cd > 0.0:
			border = Color(1, 1, 1, 0.25)
		elif not enough:
			border = Color(COL_DENY.r, COL_DENY.g, COL_DENY.b, 0.7)
		if act > 0.0:
			border = COL_ACTIVE
		if _deny_t > 0.0 and _deny_slot == i:
			border = COL_DENY
		_border(s["style"], border)

	_update_tip()

	if _dbg.visible:
		var speed := Vector2(mech.velocity.x, mech.velocity.z).length()
		_txt(_dbg, "скорость  %.1f м/с\nразброс  %.1f°\nэнергия  %d\nкадров  %d" % [speed, mech.get_spread_deg(), int(en), Engine.get_frames_per_second()])


# статусы своего меха над полосками: значки, вредные красным, полезные зелёным, у временных — сколько осталось
func _update_statuses() -> void:
	var list: Array = mech.status_list()
	while _status_chips.size() < list.size():
		_status_chips.append(_make_status_chip())
	for i in _status_chips.size():
		var c: Dictionary = _status_chips[i]
		var on := i < list.size()
		if c["panel"].visible != on:
			c["panel"].visible = on
		if not on:
			continue
		var st: Array = list[i]
		c["name"] = st[0]
		c["desc"] = st[4] if st.size() > 4 else ""
		var ic: String = st[3] if st.size() > 3 else ""
		if c["icon_name"] != ic:
			c["icon_name"] = ic
			c["icon"].texture = _icon(ic)
		var t := ""
		if st[1] >= 0.0:
			t = ("%.1f" % st[1]).replace(".", ",") if st[1] < 10.0 else "%d" % int(st[1])
		_txt(c["label"], t)
		var col: Color = COL_GOOD if st[2] else COL_BAD
		if c["icon"].modulate != col:
			c["icon"].modulate = col
		_border(c["style"], col)


func _make_status_chip() -> Dictionary:
	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(STATUS_SIZE, STATUS_SIZE)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0, 0, 0, 0.6)
	st.border_color = COL_BAD
	st.set_border_width_all(2)
	st.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", st)
	var ic := _icon_rect(null, Vector2(4, 3), STATUS_SIZE - 8.0)
	panel.add_child(ic)
	var l := _label("", 12)
	l.add_theme_constant_override("outline_size", 5)
	l.position = Vector2(0, STATUS_SIZE - 17)
	l.size = Vector2(STATUS_SIZE, 16)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(l)
	_status_row.add_child(panel)
	return {"panel": panel, "style": st, "icon": ic, "label": l, "name": "", "desc": "", "icon_name": ""}


# Alt зажат: курсор-стрелка, навёл на абилку или статус — подсказка над ним (мех в это время не стреляет — mech.gd)
func _update_tip() -> void:
	var alt := Input.is_key_pressed(KEY_ALT) and not _ping_hold and not get_tree().paused
	if alt != _alt:
		_alt = alt
		Input.set_default_cursor_shape(Input.CURSOR_ARROW if alt else Input.CURSOR_CROSS)
	var hit := _hover_item(get_viewport().get_mouse_position()) if alt else {}
	if hit.is_empty():
		if _tip.visible:
			_tip.visible = false
		_tip_key = ""
		return
	if hit["key"] != _tip_key:
		_tip_key = hit["key"]
		_tip_title.text = hit["title"]
		_tip_title.add_theme_color_override("font_color", hit["col"])
		_tip_sub.text = hit["sub"]
		_tip_sub.visible = hit["sub"] != ""
		_tip_body.text = hit["body"]
		_tip.visible = true
		_tip.reset_size()
	var r: Rect2 = hit["rect"]
	var vs := get_viewport().get_visible_rect().size
	var sz := _tip.get_combined_minimum_size()
	var pos := Vector2(r.get_center().x - sz.x * 0.5, r.position.y - sz.y - 10.0)
	pos = Vector2(clampf(pos.x, 8.0, maxf(vs.x - sz.x - 8.0, 8.0)), maxf(pos.y, 8.0))
	if _tip.position != pos:
		_tip.position = pos


# что под курсором: слот (абилка, рывок, телепорт) или статус; {} — ничего
func _hover_item(p: Vector2) -> Dictionary:
	var m := Cfg.METERS_PER_UNIT
	for sl in [_dash_slot, _tp_slot] + _slots:
		if sl.is_empty() or not sl["panel"].get_global_rect().has_point(p):
			continue
		var r: Rect2 = sl["panel"].get_global_rect()
		var i: int = sl["index"]
		if sl["icon"] == "dash":
			var ch := int(mech.stats.get("dash_charges", 1.0))
			var dist: float = mech.stats.get("dash_speed", 0.0) * mech.stats.get("dash_time", 0.0) * m
			return {"key": "dash", "rect": r, "col": KIND_COL[3], "title": "Рывок", "sub": "Пробел",
				"body": "Резкий бросок двигателями в сторону движения.\nДальность %d м, перезарядка %s с%s" % [roundi(dist),
					str(snappedf(mech.stats.get("dash_cooldown", 0.0), 0.1)), (", зарядов %d" % ch) if ch > 1 else ""]}
		if sl["icon"] == "teleport":
			return {"key": "tp", "rect": r, "col": KIND_COL[3], "title": "Телепорт на базу", "sub": "T",
				"body": "Постой %s с — и мех на своей базе. Движение и выстрел сбивают.\nПерезарядка %d с" % [str(snappedf(Cfg.tp_channel, 0.1)), int(Cfg.tp_cooldown)]}
		var ab: Dictionary = mech.abilities[i]
		var sub := "%s · %d эн. · перезарядка %s с" % [Parts.ABILITY_KEY_NAMES[i], int(mech.ability_cost(i)), str(snappedf(mech.ability_cooldown_max(i), 0.1))]
		if mech.ability_charges_max(i) > 0.0:
			sub += " · зарядов %d" % int(mech.ability_charges_max(i))
		var body := PackedStringArray()
		for ln in Parts.describe(ab["id"]).split(" · "):     # цену и перезарядку уже написали строкой выше
			if not (ln.contains(" эн., кд ") or ln.begins_with("зарядов")):
				body.append(ln.left(1).to_upper() + ln.substr(1))
		return {"key": "ab%d" % i, "rect": r, "col": KIND_COL[AB_KIND.get(ab["type"], 3)], "title": ab["name"], "sub": sub, "body": "\n".join(body)}
	for c in _status_chips:
		if not c["panel"].visible or not c["panel"].get_global_rect().has_point(p):
			continue
		var good: bool = c["icon"].modulate == COL_GOOD
		return {"key": "st_%s_%s" % [c["name"], c["desc"]], "rect": c["panel"].get_global_rect(), "col": COL_GOOD if good else COL_BAD,
			"title": c["name"], "sub": "полезный" if good else "вредный", "body": c["desc"]}
	return {}


func _exit_tree() -> void:
	if _alt:
		Input.set_default_cursor_shape(Input.CURSOR_CROSS)


# состояние маленького слота (рывок, телепорт): затемнение, цифра перезарядки, подпись, активность
func _slot_state(sl: Dictionary, k: float, cd_text: String, sub: String, active: float) -> void:
	var panel: Panel = sl["panel"]
	var shade: ColorRect = sl["shade"]
	var shade_size := Vector2(panel.size.x, panel.size.y * k)
	var cd_col = null
	var border := Color(1, 1, 1, 0.75) if k <= 0.0 else Color(1, 1, 1, 0.25)
	if active > 0.0:
		cd_text = "%.1f" % active
		cd_col = COL_ACTIVE
		shade_size = Vector2.ZERO
		border = COL_ACTIVE
	_shade(shade, shade_size, Vector2(0, panel.size.y * (1.0 - k)))
	_txt(sl["cd"], cd_text)
	_font_col(sl["cd"], cd_col)
	_txt(sl["cost"], sub)
	_border(sl["style"], border)


# Интерфейс обновляется каждый кадр, но менять подпись, цвет, рамку или полоску можно только когда они
# правда изменились: любая установка (даже того же цвета) заставляет движок заново собирать текст
# и раскладку. Раньше так уходило около 2 мс на каждый кадр
static func _txt(l: Label, t: String) -> void:
	if l.text != t:
		l.text = t


# цвет надписи; null — цвет из темы (без своего цвета)
static func _font_col(l: Label, c) -> void:
	var old = l.get_meta("font_col", "unset")
	if typeof(old) == typeof(c) and old == c:
		return
	l.set_meta("font_col", c)
	if c == null:
		l.remove_theme_color_override("font_color")
	else:
		l.add_theme_color_override("font_color", c)


static func _bg(sb: StyleBoxFlat, c: Color) -> void:
	if sb.bg_color != c:
		sb.bg_color = c


static func _border(sb: StyleBoxFlat, c: Color) -> void:
	if sb.border_color != c:
		sb.border_color = c


static func _shade(r: Control, sz: Vector2, pos: Vector2) -> void:
	if r.size != sz:
		r.size = sz
	if r.position != pos:
		r.position = pos
