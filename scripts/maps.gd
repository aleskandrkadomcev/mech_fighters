extends Node
## Карты. Каждая карта лежит отдельным файлом .json в папке maps (свои карты из редактора
## тоже туда). В файле: размер, укрытия, постройки обеих команд, точки интереса, места ящиков,
## точки линий и украшения. Читать и сохранять карты, строить по ним линии для крипов и ботов.
##
## Формат (всё в метрах, x вправо, z вниз, центр карты = 0,0):
##   mode        "pvp" = бой мехов без баз, турелей и крипов (по счёту убийств); нет поля = моба
##   size        [ширина, глубина]
##   spawns      [x, z, команда]                       точки появления (только для PvP)
##   covers      [x, z, ширина, высота, глубина, вид, поворот]   вид: wall (стена), barrier (барьер), rock (скала);
##                                                     поворот в градусах вокруг центра (можно не писать = 0)
##   structures  [деталь, команда, x, z]               деталь: turret_t1/t2/t3, hq. Линию турели игра находит сама
##                                                     (ближайшая дорога), старое 5-е поле «линия» не используется
##   pois        [x, z, вид]                           вид: regen (Реактор), damage (Арсенал), radar (Радар), dock (Ремонтный док)
##   crates      [x, z]                                куда падают ящики
##   lanepoints  [x, z, линия]                         дороги: линия top/mid/bot идёт от своего штаба через свои точки
##                                                     к вражескому штабу (турели на путь не влияют)
##   version     2 = дороги только по точкам (в старых картах точки дорог были ещё и на турелях —
##               при чтении они переносятся в lanepoints сами)
##   decor       [вид, x, z, поворот]                  низкие постройки (контейнеры, генераторы...)
##   lamps       [x, z]                                фонари
##   pylons      [[x, z], [x, z]...]                   цепочка мачт с проводами
##   targets     [x, z]                                мишени для пристрелки
##   walkers     [x1, z1, x2, z2, скорость]            ходячие мишени

const POI_NAMES := {"regen": "Реактор", "damage": "Арсенал", "radar": "Радар", "dock": "Ремонтный док"}
const DIR_RES := "res://maps"
const DIR_USER := "user://maps"
const DEFAULT := "res://maps/classic.json"
const TEST_PATH := "user://editor_test.json"
const LANE_NAMES := {"top": "Верх", "mid": "Центр", "bot": "Низ", "base": "База"}

var selected := DEFAULT          # какую карту грузит бой
var from_editor := false         # бой запущен из редактора (из меню паузы можно вернуться в редактор)
var editor_path := ""            # какую карту открыть в редакторе при возврате


# куда сохранять свои карты: при запуске из Godot прямо в папку проекта, в собранной игре в папку пользователя
func save_dir() -> String:
	return DIR_RES if OS.has_feature("editor") else DIR_USER


func list_maps() -> Array:
	var out: Array = []
	var seen := {}
	for dir in [DIR_RES, DIR_USER]:
		var da := DirAccess.open(dir)
		if da == null:
			continue
		for f in da.get_files():
			if not f.ends_with(".json"):
				continue
			var path: String = dir.path_join(f)
			if seen.has(f):
				continue
			seen[f] = true
			var d := load_map(path)
			if d.is_empty():
				continue
			out.append({"name": d.get("name", f.get_basename()), "path": path, "file": f, "pvp": is_pvp(d)})
	out.sort_custom(func(a, b) -> bool: return a["file"] == "classic.json" or (b["file"] != "classic.json" and a["name"] < b["name"]))
	return out


func load_map(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var txt := FileAccess.get_file_as_string(path)
	var d = JSON.parse_string(txt)
	if not (d is Dictionary):
		return {}
	return normalize(d)


# недостающие поля заполняем пустыми, числа приводим к числам
func normalize(d: Dictionary) -> Dictionary:
	var out := d.duplicate(true)
	if not out.has("name"):
		out["name"] = "Без названия"
	if not out.has("size") or out["size"].size() < 2:
		out["size"] = [240, 140]
	for k in ["covers", "structures", "pois", "crates", "lanepoints", "decor", "lamps", "pylons", "targets", "walkers", "spawns"]:
		if not out.has(k) or not (out[k] is Array):
			out[k] = []
	for s in out["structures"]:
		s[1] = int(s[1])
	# старая карта: дорога шла ещё и через турели своей линии. Теперь дороги отдельно —
	# переносим эти точки в точки дорог, чтобы путь крипов остался прежним
	if int(out.get("version", 1)) < 2:
		for s in out["structures"]:
			var ln: String = String(s[4]) if s.size() > 4 else ""
			if String(s[0]).begins_with("turret") and ln in ["top", "mid", "bot"]:
				out["lanepoints"].append([s[2], s[3], ln])
		out["version"] = 2
	return out


func empty_map(w: float, d: float, title: String) -> Dictionary:
	return normalize({"name": title, "size": [w, d], "version": 2})


# ------------------------------------------------------------------
#  Повёрнутые укрытия: поворот в градусах (7-е поле), 0 — вдоль осей
# ------------------------------------------------------------------

func cover_rot(c: Array) -> float:
	return float(c[6]) if c.size() > 6 else 0.0


# лежит ли точка внутри прямоугольника с центром x, z, размером w × d, повёрнутого на rot градусов (с запасом pad)
func in_box(px: float, pz: float, x: float, z: float, w: float, d: float, rot: float, pad := 0.0) -> bool:
	var l := Vector2(px - x, pz - z)
	if rot != 0.0:
		l = l.rotated(deg_to_rad(rot))      # в оси самого прямоугольника (поворот как у узла rotation.y)
	return absf(l.x) <= w * 0.5 + pad and absf(l.y) <= d * 0.5 + pad


# прямоугольник по осям карты, в который помещается повёрнутый прямоугольник
func box_rect(x: float, z: float, w: float, d: float, rot: float) -> Rect2:
	var a := deg_to_rad(rot)
	var hx := absf(cos(a)) * w * 0.5 + absf(sin(a)) * d * 0.5
	var hz := absf(sin(a)) * w * 0.5 + absf(cos(a)) * d * 0.5
	return Rect2(x - hx, z - hz, hx * 2.0, hz * 2.0)


func current() -> Dictionary:
	var d := load_map(selected)
	if d.is_empty():
		d = load_map(DEFAULT)
	return d


# сохранить карту; file_name без пути. Возвращает путь
func save_map(data: Dictionary, file_name: String) -> String:
	var dir := save_dir()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	if not file_name.ends_with(".json"):
		file_name += ".json"
	var path := dir.path_join(file_name)
	save_to(data, path)
	return path


func save_to(data: Dictionary, path: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("Не получилось сохранить карту: " + path)
		return
	f.store_string(to_text(data))
	f.close()


# читаемый файл: каждый предмет на своей строке
func to_text(data: Dictionary) -> String:
	var lines := PackedStringArray(["{"])
	var keys := data.keys()
	for i in keys.size():
		var k: String = keys[i]
		var v = data[k]
		var end := "," if i < keys.size() - 1 else ""
		if v is Array and not v.is_empty() and v[0] is Array:
			lines.append(' "%s": [' % k)
			for j in v.size():
				lines.append("  " + JSON.stringify(_clean(v[j])) + ("," if j < v.size() - 1 else ""))
			lines.append(" ]" + end)
		else:
			lines.append(' "%s": %s%s' % [k, JSON.stringify(_clean(v)), end])
	lines.append("}")
	return "\n".join(lines) + "\n"


# 12.0 -> 12, чтобы файл был короче
func _clean(v):
	if v is float and is_equal_approx(v, round(v)):
		return int(round(v))
	if v is Array:
		var a: Array = []
		for x in v:
			a.append(_clean(x))
		return a
	return v


func file_name_for(title: String) -> String:
	var s := title.strip_edges().to_lower()
	var out := ""
	for ch in s:
		if ch == " " or ch == "-":
			out += "_"
		elif ch.is_valid_identifier() or ch.is_valid_int() or ch == "_" or (ch.unicode_at(0) >= 0x0400 and ch.unicode_at(0) <= 0x04FF):
			out += ch
	if out == "":
		out = "map"
	return out + ".json"


# ------------------------------------------------------------------
#  Что из карты нужно бою
# ------------------------------------------------------------------

func rect(data: Dictionary) -> Rect2:
	var w: float = float(data["size"][0])
	var d: float = float(data["size"][1])
	return Rect2(-w * 0.5, -d * 0.5, w, d)


func hq_pos(data: Dictionary, team: int) -> Vector3:
	for s in data["structures"]:
		if s[0] == "hq" and int(s[1]) == team:
			return Vector3(float(s[2]), 0, float(s[3]))
	var r := rect(data)
	return Vector3(r.position.x + 12.0 if team == 0 else r.end.x - 12.0, 0, 0)


# карта для PvP: мехи против мехов, без баз
func is_pvp(data: Dictionary) -> bool:
	return data.get("mode", "") == "pvp"


# точка появления команды в PvP (если её нет на карте — там, где был бы штаб)
func spawn_pos(data: Dictionary, team: int) -> Vector3:
	for p in data.get("spawns", []):
		if p.size() > 2 and int(p[2]) == team:
			return Vector3(float(p[0]), 0, float(p[1]))
	return hq_pos(data, team)


# линии (дороги): имя -> точки от базы команды 0 до базы команды 1.
# Только точки дорог из редактора, по порядку от базы к базе; турели на путь не влияют.
# Нет ни одной точки — прямая центральная линия от штаба к штабу. В PvP линий нет
func lanes(data: Dictionary) -> Dictionary:
	if is_pvp(data):
		return {}
	var a := hq_pos(data, 0)
	var b := hq_pos(data, 1)
	var pts := {}
	for p in data["lanepoints"]:
		var lane2: String = p[2] if p.size() > 2 else "mid"
		if not pts.has(lane2):
			pts[lane2] = []
		pts[lane2].append(Vector3(float(p[0]), 0, float(p[1])))
	var out := {}
	for lane in pts:
		var list: Array = pts[lane]
		list.sort_custom(func(p, q) -> bool: return _progress(p, a, b) < _progress(q, a, b))
		var path := PackedVector3Array([a])
		for p in list:
			path.append(p)
		path.append(b)
		out[lane] = path
	if out.is_empty():
		out["mid"] = PackedVector3Array([a, b])
	return out


# какая линия ближе всего к точке (для турели: по какой линии её толкают боты)
func nearest_lane(lane_paths: Dictionary, p: Vector3) -> String:
	var best := ""
	var best_d := 1e9
	for ln in lane_paths:
		var path: PackedVector3Array = lane_paths[ln]
		for i in path.size() - 1:
			var a := Vector2(path[i].x, path[i].z)
			var b := Vector2(path[i + 1].x, path[i + 1].z)
			var q := Vector2(p.x, p.z)
			var ab := b - a
			var t := clampf((q - a).dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
			var d := (a + ab * t).distance_to(q)
			if d < best_d:
				best_d = d
				best = ln
	return best


# насколько точка близка к вражеской базе: 0 у своей базы, 1 у вражеской
func _progress(p: Vector3, a: Vector3, b: Vector3) -> float:
	var da := p.distance_to(a)
	var db := p.distance_to(b)
	return da / maxf(da + db, 0.001)


# проблемы карты, из-за которых в неё нельзя играть
func problems(data: Dictionary) -> Array:
	var out: Array = []
	if is_pvp(data):
		for team in 2:
			if not data.get("spawns", []).any(func(p) -> bool: return p.size() > 2 and int(p[2]) == team):
				out.append("Нет точки появления у %s" % ("своей команды" if team == 0 else "врагов"))
		return out
	for team in 2:
		var n := 0
		for s in data["structures"]:
			if s[0] == "hq" and int(s[1]) == team:
				n += 1
		if n == 0:
			out.append("Нет штаба у %s" % ("своей команды" if team == 0 else "врагов"))
		elif n > 1:
			out.append("Два штаба у %s" % ("своей команды" if team == 0 else "врагов"))
	return out
