extends Node
## Вижен как в доте.
## Каждый мех видит вокруг себя на радиус обзора (задаёт корпус), укрытия закрывают обзор.
## Турели, штаб, крипы и захваченные точки тоже дают обзор своей команде. Всё, что видит союзник, видит и вся команда.
## Невидимых врагов и чужие мины видно только в радиусе омни-сенсора (и тоже не сквозь укрытия).
##
## Туман на экране: рисуем видимые зоны команды игрока белым в маленькую картинку-маску,
## пол и стены по этой маске затемняются там, где команда ничего не видит.

const RAYS := 240                # лучей на один круг обзора
const RAYS_CREEP := 64           # у крипов обзор маленький, хватит меньше лучей
const EYE := 1.6                 # высота "глаз" для проверки видимости

var player_team := 0
var map_rect := Rect2(-120, -70, 240, 140)   # x, z, ширина, глубина карты
var mask_texture: Texture2D
var _vis := [{}, {}]             # что видит каждая команда: id узла -> true
var _t := 0.0
var _viewport: SubViewport
var _drawer: Node2D
var _fans := {}                  # id наблюдателя -> {pos, r, dists}
var _materials: Array = []
var _px := 4.0                   # пикселей маски на метр
var _fog_dark_set := -1.0       # какая темнота тумана уже стоит в материалах
var _fan_viewers: Array = []     # кто строит веер обзора (команда игрока), из последнего пересчёта
var _fan_cursor := 0             # с кого начинать пересчёт вееров в следующем кадре
var _fan_epoch := 0              # сломали стену: все веера надо пересчитать
const FAN_EVERY_MS := 100        # веер наблюдателя пересчитывается раз в 0,1 с
const FAN_BUDGET_US := 600       # и не больше 0,6 мс работы за кадр (остальное в следующих кадрах)
var _probe := SphereShape3D.new()  # круг обзора: какие укрытия в него попадают
static var _fan_cache := {}      # число лучей -> {dirs, cols, idx}: одинаковое у всех вееров


func _ready() -> void:
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(int(map_rect.size.x * _px), int(map_rect.size.y * _px))
	_viewport.disable_3d = true
	_viewport.transparent_bg = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.size = Vector2(_viewport.size)
	_viewport.add_child(bg)
	_drawer = Node2D.new()
	var cm := CanvasItemMaterial.new()
	cm.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_drawer.material = cm
	_drawer.draw.connect(_draw_fans)
	_viewport.add_child(_drawer)
	# размытие маски в два прохода (по горизонтали, потом по вертикали) в половинном размере:
	# край тумана становится мягким, без ступенек
	var tex: Texture2D = _viewport.get_texture()
	for dir in [Vector2(1, 0), Vector2(0, 1)]:
		tex = _blur_pass(tex, dir)
	mask_texture = tex


func _blur_pass(src: Texture2D, dir: Vector2) -> Texture2D:
	var vp := SubViewport.new()
	vp.size = Vector2i(int(map_rect.size.x * _px * 0.5), int(map_rect.size.y * _px * 0.5))
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var tr := TextureRect.new()
	tr.texture = src
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.size = Vector2(vp.size)
	var sh := Shader.new()
	sh.code = """shader_type canvas_item;
uniform vec2 dir;
uniform float radius = 2.4;   // в пикселях исходника на шаг
void fragment() {
	vec2 st = dir * TEXTURE_PIXEL_SIZE * radius;
	float w[7] = float[](0.2, 0.17, 0.12, 0.08, 0.045, 0.022, 0.009);
	float v = texture(TEXTURE, UV).r * w[0];
	for (int i = 1; i < 7; i++) {
		v += texture(TEXTURE, UV + st * float(i)).r * w[i];
		v += texture(TEXTURE, UV - st * float(i)).r * w[i];
	}
	v /= (w[0] + 2.0 * (w[1] + w[2] + w[3] + w[4] + w[5] + w[6]));
	COLOR = vec4(v, v, v, 1.0);
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("dir", dir)
	tr.material = m
	vp.add_child(tr)
	return vp.get_texture()


# материалы, которые затемняются туманом (пол, стены, миникарта)
func register_material(m: ShaderMaterial) -> void:
	_materials.append(m)
	m.set_shader_parameter("fog_tex", mask_texture)
	m.set_shader_parameter("fog_rect", Vector4(map_rect.position.x, map_rect.position.y, map_rect.size.x, map_rect.size.y))
	m.set_shader_parameter("fog_dark", Cfg.fog_darkness)


func is_visible_to(team: int, node: Node) -> bool:
	if node == null or not is_instance_valid(node):
		return false
	var t = node.get("team")
	if t == team:
		return true
	if node.is_in_group("structures"):
		return true
	return _vis[clampi(team, 0, 1)].has(node.get_instance_id())


# веера обзора — только картинка тумана (кто кого видит, считает _update на тиках), поэтому строятся
# здесь, понемногу в каждом кадре. Раньше все веера строились разом в одном тике из трёх,
# и такой тик не успевал к обновлению монитора: кадр показывался дважды
func _process(_delta: float) -> void:
	# темнота тумана: в материалы только когда её поменяли (F2), а не каждый кадр во все ~40 материалов
	if Cfg.fog_darkness != _fog_dark_set:
		_fog_dark_set = Cfg.fog_darkness
		for m in _materials:
			m.set_shader_parameter("fog_dark", Cfg.fog_darkness)
	_update_fans()
	_drawer.queue_redraw()


# кто кого видит: пересчёт на тиках игры (не зависит от кадров)
func _physics_process(delta: float) -> void:
	_t -= delta
	if _t <= 0.0:
		_t = 0.1
		_update()


# все, кто даёт обзор команде: [{node, pos, r, omni}]
func _viewers(team: int) -> Array:
	var out: Array = []
	for m in get_tree().get_nodes_in_group("mechs"):
		if m.dead or m.team != team:
			continue
		out.append({"node": m, "pos": m.global_position, "r": m.vision_r(), "omni": m.omni_r()})
	for s in get_tree().get_nodes_in_group("structures"):
		if s.dead or s.team != team:
			continue
		out.append({"node": s, "pos": s.global_position, "r": s.vision_radius(), "omni": 0.0})
	for p in get_tree().get_nodes_in_group("pois"):
		if p.owner_team == team and Cfg.poi_vision > 0.0:
			out.append({"node": p, "pos": p.global_position, "r": Cfg.poi_vision, "omni": 0.0})
		# радар: большой круг обзора сквозь стены (nolos), пока у вышки стоят свои
		if p.kind == "radar" and p.owner_team == team and p.radar_r > 0.5 and p.radar_eye != null:
			out.append({"node": p.radar_eye, "pos": p.global_position, "r": p.radar_r,
				"omni": p.radar_r if Cfg.poi_radar_cloak == 1 else 0.0, "nolos": true})
	for c in get_tree().get_nodes_in_group("creeps"):
		if c.dead or c.team != team:
			continue
		out.append({"node": c, "pos": c.global_position, "r": c.vision_radius(), "omni": 0.0})
	# скан-зонды: обзор как у меха (стены закрывают) и омни вблизи
	for pr in get_tree().get_nodes_in_group("probes"):
		if pr.dead or pr.team != team:
			continue
		out.append({"node": pr, "pos": pr.global_position, "r": float(pr.p.get("radius", 22.0)), "omni": float(pr.p.get("omni", 6.0))})
	return out


# стену сломали: обзор неподвижных (турелей, точек) надо пересчитать
func invalidate_static() -> void:
	_fan_epoch += 1      # старые веера рисуются, пока их не пересчитают (доли секунды), без чёрной вспышки


# видит ли команда точку обычным обзором (мелочь, сломанная в тумане, показывается сломанной только так)
func point_visible(team: int, pos: Vector3, radius: float) -> bool:
	return _seen_by(_viewers(team), pos, radius, false)


func _los(a: Vector3, b: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(Vector3(a.x, EYE, a.z), Vector3(b.x, EYE, b.z), 1)
	return get_viewport().get_world_3d().direct_space_state.intersect_ray(q).is_empty()


# видит ли кто-то из наблюдателей точку: обычный обзор или (для невидимок и мин) омни
func _seen_by(viewers: Array, pos: Vector3, radius: float, hidden: bool) -> bool:
	for v in viewers:
		var d: Vector3 = pos - v["pos"]
		d.y = 0
		var reach: float = (v["omni"] if hidden else v["r"]) + radius
		if d.length() > reach:
			continue
		if v.get("nolos", false) or _los(v["pos"], pos):
			return true
	return false


func _update() -> void:
	for team in 2:
		var viewers := _viewers(team)
		var vis := {}
		for m in get_tree().get_nodes_in_group("mechs"):
			if m.dead or m.team == team:
				continue
			if _seen_by(viewers, m.global_position, m.get_hit_radius(), m.is_cloaked()):
				vis[m.get_instance_id()] = true
		for c in get_tree().get_nodes_in_group("creeps"):
			if c.dead or c.team == team:
				continue
			if _seen_by(viewers, c.global_position, c.get_hit_radius(), false):
				vis[c.get_instance_id()] = true
		for mn in get_tree().get_nodes_in_group("mines"):
			if mn.team == team:
				continue
			if mn.triggered or _seen_by(viewers, mn.global_position, 0.5, true):
				vis[mn.get_instance_id()] = true
		# турели, шары, купола врага видны обычным обзором
		for gd in get_tree().get_nodes_in_group("gadgets"):
			if gd.team != team and not gd.dead and _seen_by(viewers, gd.global_position, gd.get_hit_radius(), false):
				vis[gd.get_instance_id()] = true
		# вражеский зонд, как мина, виден только омни-сенсором (вблизи)
		for pr in get_tree().get_nodes_in_group("probes"):
			if pr.team != team and not pr.dead and _seen_by(viewers, pr.global_position, 0.5, true):
				vis[pr.get_instance_id()] = true
		if team == player_team:
			for pk in get_tree().get_nodes_in_group("pickups"):
				if _seen_by(viewers, pk.global_position, 0.5, false):
					vis[pk.get_instance_id()] = true
			_set_fan_viewers(viewers)
		_vis[team] = vis
	# что показывать на экране игрока
	for m in get_tree().get_nodes_in_group("mechs"):
		m.seen = is_visible_to(player_team, m)
	for c in get_tree().get_nodes_in_group("creeps"):
		c.seen = is_visible_to(player_team, c)
	for mn in get_tree().get_nodes_in_group("mines"):
		mn.seen = is_visible_to(player_team, mn)
	for pr in get_tree().get_nodes_in_group("probes"):
		pr.seen = is_visible_to(player_team, pr)
	for gd in get_tree().get_nodes_in_group("gadgets"):
		gd.seen = is_visible_to(player_team, gd)
	for pk in get_tree().get_nodes_in_group("pickups"):
		pk.seen = _vis[player_team].has(pk.get_instance_id())


# ------------------------------------------------------------------
#  Маска тумана
# ------------------------------------------------------------------

# новый список наблюдателей: веера тех, кого больше нет, убираем
func _set_fan_viewers(viewers: Array) -> void:
	_fan_viewers = viewers
	var alive := {}
	for v in viewers:
		alive[v["node"].get_instance_id()] = true
	for id in _fans.keys():
		if not alive.has(id):
			_fans.erase(id)


# пересчёт вееров, которым пора (раз в 0,1 с), пока не кончится время кадра; по кругу, с места,
# где остановились в прошлом кадре
func _update_fans() -> void:
	var n := _fan_viewers.size()
	if n == 0:
		return
	var space := get_viewport().get_world_3d().direct_space_state
	var t0 := Time.get_ticks_usec()
	var now := Time.get_ticks_msec()
	_fan_cursor = _fan_cursor % n
	for k in n:
		if Time.get_ticks_usec() - t0 > FAN_BUDGET_US:
			return
		var v: Dictionary = _fan_viewers[_fan_cursor]
		_fan_cursor = (_fan_cursor + 1) % n
		var node = v["node"]
		if not is_instance_valid(node):
			continue
		var id: int = node.get_instance_id()
		var moving: bool = node.is_in_group("mechs") or node.is_in_group("creeps")
		var pos: Vector3 = node.global_position if moving else v["pos"]
		var r: float = v["r"]
		var old = _fans.get(id)
		if old != null and old["epoch"] == _fan_epoch and is_equal_approx(old["r"], r):
			# неподвижные (турели, точки) считаем один раз; мехи и крипы — раз в 0,1 с и только если
			# сдвинулись (веер рисуется там, где наблюдатель сейчас)
			if not moving and old["pos"].distance_to(pos) < 0.1:
				continue
			if moving and (now - old["t"] < FAN_EVERY_MS or old["pos"].distance_to(pos) < 0.05):
				continue
		var n_rays := RAYS_CREEP if node.is_in_group("creeps") else RAYS
		if v.get("nolos", false):
			# радар видит сквозь стены: веер — полный круг, лучи не нужны
			var full := PackedFloat32Array()
			full.resize(n_rays)
			full.fill(r)
			_fans[id] = _make_fan(node, pos, r, full)
		else:
			_fans[id] = _make_fan(node, pos, r, _fan_dists(space, Vector3(pos.x, EYE, pos.z), r, n_rays))


# дальность обзора по лучам веера. Луч пускаем, только если в его сторону есть укрытие внутри круга
# обзора; в остальные стороны обзор и так полный. Результат тот же (тест fancheck), лучей меньше
func _fan_dists(space: PhysicsDirectSpaceState3D, from: Vector3, r: float, n_rays: int) -> PackedFloat32Array:
	var dists := PackedFloat32Array()
	dists.resize(n_rays)
	dists.fill(r)
	var spans := _obstacle_spans(space, from, r)
	if spans.is_empty():
		return dists
	var step := TAU / n_rays
	var cast := PackedByteArray()
	cast.resize(n_rays)
	for s in spans:
		for i in range(int(ceil(s.x / step)), int(floor((s.x + s.y) / step)) + 1):
			cast[posmod(i, n_rays)] = 1
	var q := PhysicsRayQueryParameters3D.new()
	q.from = from
	q.collision_mask = 1
	for i in n_rays:
		if cast[i] == 0:
			continue
		var a := step * i
		q.to = from + Vector3(cos(a), 0, sin(a)) * r
		var hit := space.intersect_ray(q)
		# луч заходит чуть за стену, чтобы стена, которую видишь, была освещена
		if not hit.is_empty():
			dists[i] = minf(from.distance_to(hit["position"]) + 1.2, r)
	return dists


# в какие стороны от точки (углы как у лучей веера) лежат укрытия внутри круга обзора:
# [Vector2(начало, ширина)]. Если укрытие не разобрать или их слишком много — все стороны
func _obstacle_spans(space: PhysicsDirectSpaceState3D, from: Vector3, r: float) -> Array:
	var all := [Vector2(0.0, TAU)]
	_probe.radius = r
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = _probe
	q.transform = Transform3D(Basis(), from)
	q.collision_mask = 1
	var res := space.intersect_shape(q, 64)
	if res.size() >= 64:
		return all
	var margin := TAU / RAYS_CREEP     # запас в целый луч редкого веера
	var spans: Array = []
	for h in res:
		var co = h["collider"]
		if not (co is CollisionObject3D):
			return all
		var cs = co.shape_owner_get_owner(co.shape_find_owner(h["shape"]))
		if not (cs is CollisionShape3D) or not (cs.shape is BoxShape3D):
			return all
		var half: Vector3 = cs.shape.size * 0.5
		var xf: Transform3D = cs.global_transform
		var c0 := xf.origin - from
		var a0 := atan2(c0.z, c0.x)
		var lo := INF
		var hi := -INF
		var y0 := INF
		var y1 := -INF
		for k in 8:
			var p: Vector3 = xf * Vector3(half.x * (1 if k & 1 else -1), half.y * (1 if k & 2 else -1), half.z * (1 if k & 4 else -1))
			y0 = minf(y0, p.y)
			y1 = maxf(y1, p.y)
			var d := wrapf(atan2(p.z - from.z, p.x - from.x) - a0, -PI, PI)
			lo = minf(lo, d)
			hi = maxf(hi, d)
		if y1 < from.y - 0.01 or y0 > from.y + 0.01:
			continue        # пол под ногами и то, что выше глаз, лучи не задевают
		if hi - lo > PI * 0.9:
			return all      # стоим вплотную или внутри
		spans.append(Vector2(a0 + lo - margin, hi - lo + margin * 2.0))
	return spans


func _to_px(x: float, z: float) -> Vector2:
	return Vector2((x - map_rect.position.x) * _px, (z - map_rect.position.y) * _px)


# фигура обзора строится один раз при пересчёте (вокруг нуля, в пикселях маски),
# а в кадре её только сдвигаем туда, где сейчас мех. Раньше её собирали заново каждый кадр — это было дорого
func _make_fan(node: Node, pos: Vector3, r: float, dists: PackedFloat32Array) -> Dictionary:
	var skirt := 3.0
	var nr := dists.size()
	var base := _fan_base(nr)
	var dirs: PackedVector2Array = base["dirs"]
	var pts := PackedVector2Array()
	pts.resize(1 + nr * 2)
	for i in nr:
		pts[1 + i] = dirs[i] * dists[i]
		pts[1 + nr + i] = dirs[i] * (dists[i] + skirt)
	var moving: bool = node.is_in_group("mechs") or node.is_in_group("creeps")
	return {"node": node, "pos": pos, "r": r, "pts": pts, "cols": base["cols"], "idx": base["idx"], "moving": moving,
		"epoch": _fan_epoch, "t": Time.get_ticks_msec()}


# направления лучей, цвета и треугольники веера зависят только от числа лучей: считаются один раз
func _fan_base(nr: int) -> Dictionary:
	if _fan_cache.has(nr):
		return _fan_cache[nr]
	var dirs := PackedVector2Array()
	var cols := PackedColorArray()
	dirs.resize(nr)
	cols.resize(1 + nr * 2)
	cols[0] = Color.WHITE
	for i in nr:
		var a := TAU * i / nr
		dirs[i] = Vector2(cos(a), sin(a)) * _px
		cols[1 + i] = Color.WHITE
		cols[1 + nr + i] = Color(1, 1, 1, 0)
	var idx := PackedInt32Array()
	idx.resize(nr * 9)
	for i in nr:
		var jn := (i + 1) % nr
		var k := i * 9
		idx[k] = 0
		idx[k + 1] = 1 + i
		idx[k + 2] = 1 + jn
		idx[k + 3] = 1 + i
		idx[k + 4] = 1 + nr + i
		idx[k + 5] = 1 + nr + jn
		idx[k + 6] = 1 + i
		idx[k + 7] = 1 + nr + jn
		idx[k + 8] = 1 + jn
	_fan_cache[nr] = {"dirs": dirs, "cols": cols, "idx": idx}
	return _fan_cache[nr]


func _draw_fans() -> void:
	var ci := _drawer.get_canvas_item()
	for id in _fans:
		var f: Dictionary = _fans[id]
		var node = f["node"]
		var c: Vector3 = f["pos"]
		# мехи рисуем в текущей точке, чтобы край тумана не дёргался между пересчётами
		if f["moving"] and is_instance_valid(node):
			c = node.global_position
		RenderingServer.canvas_item_add_set_transform(ci, Transform2D(0.0, _to_px(c.x, c.z)))
		RenderingServer.canvas_item_add_triangle_array(ci, f["idx"], f["pts"], f["cols"])
	RenderingServer.canvas_item_add_set_transform(ci, Transform2D.IDENTITY)
