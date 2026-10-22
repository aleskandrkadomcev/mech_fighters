extends Control
## Миникарта (левый нижний угол). Стены, базы, турели, точки интереса, ящики,
## союзники и враги, которых видит твоя команда. Туман: что команда не видит, темнее.

var main: Node3D
var vision: Node
var _map: TextureRect
var _overlay: Control
var _mat: ShaderMaterial
var _fog_dark_set := -1.0       # какая темнота тумана уже стоит в материале
var _ticked := true             # был тик игры после прошлой перерисовки
var _rect := Rect2(-120, -70, 240, 140)
var _pings: Array = []          # метки игроков: [{pos, born, kind}], расходящиеся круги и значок метки, 3 с


func setup(main_node: Node3D, vision_node: Node, map_rect: Rect2, covers: Array, size_px: Vector2) -> void:
	main = main_node
	vision = vision_node
	_rect = map_rect
	custom_minimum_size = size_px
	# прижата к левому нижнему углу (hud.gd): высоту отсчитываем от нижнего края, а не вниз за экран
	offset_top = offset_bottom - size_px.y
	offset_right = offset_left + size_px.x
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# картинка карты: пол и стены (перерисовывается, когда ломают стену)
	_map = TextureRect.new()
	_map.texture = ImageTexture.create_from_image(_draw_map(covers, []))
	_map.stretch_mode = TextureRect.STRETCH_SCALE
	_map.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_map.size = size_px
	_map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = """shader_type canvas_item;
uniform sampler2D fog_tex : filter_linear;
uniform float fog_dark = 0.6;
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float vis = texture(fog_tex, UV).r;
	COLOR = vec4(c.rgb * (1.0 - fog_dark * (1.0 - vis)), 0.92);
}
"""
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	_mat.set_shader_parameter("fog_tex", vision.mask_texture)
	_map.material = _mat
	add_child(_map)

	var frame := Panel.new()
	frame.size = size_px
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.set_border_width_all(2)
	sb.border_color = Color(1, 1, 1, 0.35)
	frame.add_theme_stylebox_override("panel", sb)
	add_child(frame)
	# значки рисуются поверх картинки карты
	_overlay = Control.new()
	_overlay.size = size_px
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_icons)
	add_child(_overlay)


func _draw_map(covers: Array, broken: Array) -> Image:
	var w := int(_rect.size.x * 2)
	var h := int(_rect.size.y * 2)
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.2, 0.22, 0.25))
	# дороги и площадки бледнее
	var gm = main.get_meta("ground_mask") if main != null and main.has_meta("ground_mask") else null
	if gm != null:
		for y in h:
			for x in w:
				var c: Color = gm.get_pixel(mini(x / 2, gm.get_width() - 1), mini(y / 2, gm.get_height() - 1))
				var k := clampf(maxf(c.r, maxf(c.g, c.b)) * 1.5 - 0.3, 0.0, 1.0)
				if k > 0.0:
					img.set_pixel(x, y, Color(0.2, 0.22, 0.25).lerp(Color(0.3, 0.3, 0.3), k))
	for c in covers:
		var x0 := int((c[0] - c[2] * 0.5 - _rect.position.x) * 2)
		var y0 := int((c[1] - c[4] * 0.5 - _rect.position.y) * 2)
		var col := Color(0.62, 0.64, 0.7)
		if broken.has(Vector2(c[0], c[1])):
			col = Color(0.32, 0.3, 0.28)
		elif c.size() > 5 and c[5] == "rock":
			col = Color(0.55, 0.5, 0.42)
		var rot := Maps.cover_rot(c)
		if rot == 0.0:
			img.fill_rect(Rect2i(x0, y0, maxi(int(c[2] * 2), 1), maxi(int(c[4] * 2), 1)), col)
			continue
		# повёрнутое укрытие: закрашиваем пиксели внутри него (2 пикселя на метр)
		var br := Maps.box_rect(c[0], c[1], c[2], c[4], rot)
		for y in range(maxi(int((br.position.y - _rect.position.y) * 2), 0), mini(int((br.end.y - _rect.position.y) * 2) + 1, h)):
			for x in range(maxi(int((br.position.x - _rect.position.x) * 2), 0), mini(int((br.end.x - _rect.position.x) * 2) + 1, w)):
				if Maps.in_box(_rect.position.x + (x + 0.5) * 0.5, _rect.position.y + (y + 0.5) * 0.5, c[0], c[1], c[2], c[4], rot, 0.25):
					img.set_pixel(x, y, col)
	return img


# стену сломали: перерисовать карту (разрушенные стены тёмные)
func redraw(m: Node) -> void:
	var broken: Array = []
	for w in m.walls:
		if w.is_destroyed():
			broken.append(Vector2(w.c[0], w.c[1]))
	_map.texture = ImageTexture.create_from_image(_draw_map(m.covers, broken))


func _to_px(p: Vector3) -> Vector2:
	return Vector2((p.x - _rect.position.x) / _rect.size.x * size.x, (p.z - _rect.position.y) / _rect.size.y * size.y)


# точка экрана -> точка на карте (или null, если мимо миникарты)
func world_at(screen_pos: Vector2):
	var local := get_global_transform_with_canvas().affine_inverse() * screen_pos
	if not Rect2(Vector2.ZERO, size).has_point(local):
		return null
	return Vector3(_rect.position.x + local.x / size.x * _rect.size.x, 0, _rect.position.y + local.y / size.y * _rect.size.y)


func add_ping(pos: Vector3, kind := "") -> void:
	_pings.append({"pos": pos, "born": Time.get_ticks_msec(), "kind": kind})


func _process(_delta: float) -> void:
	if _mat != null and Cfg.fog_darkness != _fog_dark_set:
		_fog_dark_set = Cfg.fog_darkness
		_mat.set_shader_parameter("fog_dark", Cfg.fog_darkness)
	# мехи и крипы сдвигаются только на тиках игры: перерисовываем после тика, а каждый кадр —
	# только пока мигают метки или место падения ящика
	if _overlay != null and (_ticked or not _pings.is_empty() or (main != null and main.has_method("crate_warning_pos") and main.crate_warning_pos() != null)):
		_ticked = false
		_overlay.queue_redraw()


func _physics_process(_delta: float) -> void:
	_ticked = true


func _team_col(t: int) -> Color:
	return Cfg.player_color if t == 0 else (Cfg.enemy_color if t == 1 else Color(0.8, 0.8, 0.8))


func _draw_icons() -> void:
	if main == null:
		return
	var tree := get_tree()
	# базы
	for s in tree.get_nodes_in_group("structures"):
		if s.cleared:          # развалину разбили — на карте её больше нет
			continue
		var c := _team_col(s.team)
		if s.dead:
			c = Color(0.25, 0.25, 0.25)
		var r := 7.0 if s.id == "hq" else 4.0
		var p := _to_px(s.global_position)
		_overlay.draw_rect(Rect2(p - Vector2(r, r), Vector2(r, r) * 2), c)
		_overlay.draw_rect(Rect2(p - Vector2(r, r), Vector2(r, r) * 2), Color(0, 0, 0, 0.8), false, 1.0)
	# точки интереса
	for poi in tree.get_nodes_in_group("pois"):
		var p2 := _to_px(poi.global_position)
		var rr := Cfg.poi_radius / _rect.size.x * size.x
		_overlay.draw_arc(p2, rr, 0, TAU, 24, _team_col(poi.owner_team), 2.0)
		_overlay.draw_circle(p2, 2.5, _team_col(poi.owner_team))
	# ящики и места, куда они сейчас упадут
	for cr in tree.get_nodes_in_group("wrecks"):
		if cr.is_crate:
			_overlay.draw_rect(Rect2(_to_px(cr.global_position) - Vector2(3, 3), Vector2(6, 6)), Color(1.0, 0.8, 0.25))
	if main.has_method("crate_warning_pos"):
		var wp = main.crate_warning_pos()
		if wp != null:
			var blink := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.012)
			_overlay.draw_arc(_to_px(wp), 6.0, 0, TAU, 16, Color(1.0, 0.8, 0.25, blink), 2.0)
	# крипы
	for c in tree.get_nodes_in_group("creeps"):
		if c.dead:
			continue
		if c.team != vision.player_team and not vision.is_visible_to(vision.player_team, c):
			continue
		_overlay.draw_rect(Rect2(_to_px(c.global_position) - Vector2(1.5, 1.5), Vector2(3, 3)), _team_col(c.team).darkened(0.15))
	# мехи: союзники всегда, враги только если их видит команда
	for m in tree.get_nodes_in_group("mechs"):
		if m.dead:
			continue
		if m.team != vision.player_team and not vision.is_visible_to(vision.player_team, m):
			continue
		var p3 := _to_px(m.global_position)
		if m.is_player:
			var f: Vector3 = m.torso_forward()
			var tip := p3 + Vector2(f.x, f.z) * 8.0
			_overlay.draw_circle(p3, 4.5, Color.WHITE)
			_overlay.draw_line(p3, tip, Color.WHITE, 2.0)
		else:
			_overlay.draw_circle(p3, 3.5, _team_col(m.team))
			_overlay.draw_arc(p3, 3.5, 0, TAU, 10, Color(0, 0, 0, 0.8), 1.0)
	# метки: три расходящихся круга
	var now := Time.get_ticks_msec()
	for i in range(_pings.size() - 1, -1, -1):
		var age := (now - int(_pings[i]["born"])) / 1000.0
		if age > 3.0:
			_pings.remove_at(i)
			continue
		var pp := _to_px(_pings[i]["pos"])
		var k := fmod(age, 1.0)
		var info: Dictionary = Fx.ping_info(_pings[i]["kind"])
		var pc: Color = info["col"]
		var col := Color(pc.r, pc.g, pc.b, (1.0 - k) * (1.0 - age / 3.0) + 0.2)
		_overlay.draw_arc(pp, 4.0 + k * 14.0, 0, TAU, 20, col, 2.0)
		_overlay.draw_texture_rect(info["icon"], Rect2(pp - Vector2(9, 9), Vector2(18, 18)), false, pc)
