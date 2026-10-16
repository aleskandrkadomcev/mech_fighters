extends Node
## Счёт боя: время, кто сколько убил, сколько урона нанёс, сколько сломал построек и крипов.
## По этому строится таблица после боя. Ещё отсюда цифры урона и отметка попадания у прицела.

signal player_hit(target: Node, amount: float)   # игрок попал по врагу (для отметки у прицела)
signal poi_captured(title: String, team: int)   # точку интереса захватили: крупная подпись на экране
signal feed(killer: String, killer_team: int, victim: String, victim_team: int)   # строка в ленту убийств

var time := 0.0
var running := false
var pvp := false                # режим PvP: мехи против мехов, без баз (ставит main.gd по карте)
var rows := {}                  # id участника -> строка таблицы
var _player_id := 0
var _num_acc := {}              # накопленный урон для цифр (лучи бьют по чуть-чуть каждый кадр)


func reset() -> void:
	time = 0.0
	running = false
	pvp = false
	rows.clear()
	_num_acc.clear()


func _physics_process(delta: float) -> void:
	if running and not get_tree().paused:
		time += delta
	# цифры урона от лучей и Гатлинга: выводим накопленное раз в 0.25 с
	for id in _num_acc.keys():
		var a: Dictionary = _num_acc[id]
		a["t"] -= delta
		if a["t"] <= 0.0:
			if is_instance_valid(a["node"]) and Cfg.damage_numbers > 0:
				Fx.damage_number(a["node"].global_position, a["sum"], a["col"])
			_num_acc.erase(id)


# участник: мех игрока или бота
func register(m: Node, title: String) -> void:
	var id := m.get_instance_id()
	if m.get("is_player"):
		_player_id = id
	rows[id] = {"name": title, "team": m.team, "player": m.get("is_player") == true, "mech": "",
		"kills": 0, "deaths": 0, "damage": 0.0, "structures": 0.0, "creeps": 0, "towers": 0}
	if m.has_method("set_title"):
		m.set_title(title)     # ник над мехом


func set_mech(m: Node, mech_name: String) -> void:
	var id := m.get_instance_id()
	if rows.has(id):
		rows[id]["mech"] = mech_name


func _row(src):
	if src == null or not is_instance_valid(src):
		return null
	return rows.get(src.get_instance_id())


func on_damage(src, target: Node, amount: float, pos: Vector3) -> void:
	if src != null and not is_instance_valid(src):
		src = null
	if amount <= 0.0:
		return
	var r = _row(src)
	if r != null:
		if target.is_in_group("structures"):
			r["structures"] += amount
		elif target.is_in_group("mechs"):
			r["damage"] += amount
	# игрок попал: отметка у прицела и цифра над целью
	if src != null and is_instance_valid(src) and src.get_instance_id() == _player_id and target != src:
		player_hit.emit(target, amount)
		_number(target, amount, Color(1.0, 0.9, 0.5))
	elif target.get_instance_id() == _player_id:
		_number(target, amount, Color(1.0, 0.35, 0.3))


func _number(target: Node, amount: float, col: Color) -> void:
	if not (target is Node3D):
		return
	var id := target.get_instance_id()
	if not _num_acc.has(id):
		_num_acc[id] = {"node": target, "sum": 0.0, "t": 0.25, "col": col}
	_num_acc[id]["sum"] += amount


func on_kill(src, victim: Node) -> void:
	if src != null and not is_instance_valid(src):
		src = null
	# лента убийств: мехи и постройки (крипов не пишем, их слишком много)
	if victim.is_in_group("mechs") or victim.is_in_group("structures"):
		var k := _who(src)
		var w := _who(victim)
		feed.emit(k[0], k[1], w[0], w[1])
	var v = rows.get(victim.get_instance_id())
	if v != null:
		v["deaths"] += 1
	var r = _row(src)
	if r == null:
		return
	if victim.is_in_group("mechs"):
		if src != victim:
			r["kills"] += 1
	elif victim.is_in_group("creeps"):
		r["creeps"] += 1
	elif victim.is_in_group("structures"):
		r["towers"] += 1


# как подписать участника в ленте: имя и мех, или «Турель 2», «Штаб», «Крип»
func _who(n) -> Array:
	if n == null or not is_instance_valid(n):
		return ["", -1]
	var t: int = n.get("team") if n.get("team") != null else -1
	var r = rows.get(n.get_instance_id())
	if r != null:
		return ["%s (%s)" % [r["name"], r["mech"]] if r["mech"] != "" else r["name"], t]
	if n.is_in_group("structures"):
		var tier: int = n.get("tier") if n.get("tier") != null else 1
		if n.get("id") == "core":
			return ["Ядро", t]
		return ["Штаб" if tier == 0 else "Турель %d" % tier, t]
	if n.is_in_group("creeps"):
		return ["Крип", t]
	return ["", t]


func time_text() -> String:
	var s := int(time)
	return "%d:%02d" % [s / 60, s % 60]
