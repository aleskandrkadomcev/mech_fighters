extends RefCounted
## Мозги бота. Каждый кадр решает за меха: куда идти, куда целиться, стрелять ли,
## когда рвануть в сторону и когда дать абилку. "Нажимает" те же кнопки, что и игрок.
##
## Поведение простое:
##   не видит цель или далеко  -> идёт на сближение в обход укрытий
##   слишком близко            -> пятится
##   на рабочей дистанции      -> меняет позицию (ищет точку, откуда цель видно), кружит боком,
##                                иногда встаёт ради точности
##   под ногами метка ракет    -> уходит из круга, если успел заметить
##   получил попадание         -> иногда рывок в сторону
##   цель невидима             -> идёт туда, где видел её последний раз
##   абилки                    -> атакующие по цели, щит под огнём, ремонт и невидимость/блинк когда мало здоровья
## В PvP (мехи против мехов, без баз) бот не уходит на базу: врага рядом нет — идёт к врагу, которого
## видит его команда, или обходит карту; патроны кончились — бежит к припасам.
## Все пороги и шансы лежат в настройках, группа "Боты".

var mech: CharacterBody3D
var nav                       # карта проходимости (nav.gd)

var _mode := "approach"
var _mode_t := 0.0
var _strafe := 1.0
var _goal := Vector3.ZERO      # точка, куда бот сейчас переходит
var _flips := 0               # сколько раз подряд упёрся в стену при стрейфе
var _path := PackedVector3Array()
var _path_t := 0.0
var _aim := Vector3.ZERO
var _aim_ready := false
var _burst_on := true
var _burst_t := 0.0
var _seed := 0.0
var _time := 0.0
var _ability_t := 2.0
var _dodge_cd := 0.0
var _want_dodge := false
var _zone_choice := {}        # по каждой метке ракет бот один раз решает, заметил он её или нет
var _since_hit := 99.0        # сколько секунд назад по боту попали
var _last_seen := Vector3.ZERO
var _last_seen_t := 99.0
var main: Node                # main.gd: базы, цели линии
var lane := "mid"             # по какой линии бот толкает турели
var _retreat := false
var _stuck_t := 0.0
var dbg := ""                 # что бот сейчас делает (для автопроверки)
var _loot_id := 0
var _loot_t := 0.0
var _loot_skip := {}
var _hunt := Vector3.ZERO      # PvP: куда бот идёт искать врагов
var _hunt_t := 0.0


func _init() -> void:
	_seed = randf() * 100.0
	_strafe = 1.0 if randf() < 0.5 else -1.0
	_ability_t = randf_range(2.0, 5.0)


# после возрождения бот начинает думать с чистого листа
func reset() -> void:
	_mode = "approach"
	_mode_t = 0.0
	_path = PackedVector3Array()
	_path_t = 0.0
	_aim_ready = false
	_want_dodge = false
	_flips = 0
	_ability_t = randf_range(2.0, 4.0)
	_since_hit = 99.0
	_last_seen_t = 99.0
	_retreat = false
	_hunt_t = 0.0


func on_damaged() -> void:
	_since_hit = 0.0
	if _dodge_cd <= 0.0 and randf() < Cfg.bot_dodge_chance:
		_want_dodge = true


func think(delta: float) -> void:
	_time += delta
	_dodge_cd = maxf(_dodge_cd - delta, 0.0)
	_ability_t = maxf(_ability_t - delta, 0.0)
	_since_hit += delta
	_last_seen_t += delta
	mech._fire = false
	mech._fire2 = false
	mech._run = false

	if mech.is_landing():
		return
	_think_defense()
	var pos := mech.global_position
	var hp_k: float = mech.hp / maxf(mech.max_hp(), 1.0)
	# отход на базу: мало здоровья или кончились патроны (в PvP базы нет, бот не отходит)
	if _retreat:
		var home: Vector3 = main.base_center(mech.team) if main != null else pos
		if (hp_k >= 0.9 and mech.ammo_ratio() >= 0.85) or home.distance_to(pos) > 1e6 or Battle.pvp:
			_retreat = false
	elif not Battle.pvp and (hp_k < Cfg.bot_retreat_hp or _out_of_ammo()):
		_retreat = true
	# далеко от базы и надо чиниться: телепорт (если рядом нет врагов, иначе собьют)
	if _retreat and mech.can_tp() and main != null and main.base_center(mech.team).distance_to(pos) > 60.0 and _since_hit > 2.0:
		mech.press_tp()
	if mech.is_channeling():
		mech._move = Vector2.ZERO
		return

	var target := _find_target()
	dbg = "fight" if target != null else "roam"
	var move := Vector3.ZERO
	var dir := Vector3.FORWARD
	if target != null:
		_last_seen = target.global_position
		_last_seen_t = 0.0
		var tpos: Vector3 = target.global_position
		var to := tpos - pos
		to.y = 0
		var dist := to.length()
		dir = to / maxf(dist, 0.01)
		var los := _has_los(pos, tpos)
		_think_aim(delta, target, pos, tpos, dist)
		_think_abilities(target, pos, tpos, dir, dist, los)
		if not mech.is_cloaked():
			_think_fire(delta, dir, dist, los)
			_hold_charge(los, dist)
		var escape := _danger_escape(pos)
		if _retreat:
			move = _go_home(delta, pos)
			mech._run = true
		elif mech.is_cloaked():
			# невидимый бот уходит от цели, чтобы отлечиться и зайти заново
			move = -dir
			if _blocked(pos, move, 4.0):
				move = dir.cross(Vector3.UP) * _strafe
			mech._run = true
		elif escape != Vector3.ZERO:
			# под ногами метка вражеских ракет или мины: уходим из круга
			move = escape
			if mech.dash_cd <= 0.0:
				mech.press_dash()
		else:
			# PvP: патроны кончились — сперва к припасам рядом, если они есть
			if Battle.pvp and _out_of_ammo():
				move = _think_loot(delta, pos)
			if move == Vector3.ZERO:
				move = _think_move(delta, pos, tpos, dir, dist, los)
	else:
		_aim_ready = false
		var creep := _find_creep(pos)
		if creep != null and not _retreat:
			# мехов рядом нет: бьём вражеских крипов (они толкают линию)
			dbg = "creep"
			move = _attack_object(delta, pos, creep, mech.weapon_range() * 0.8)
			_hold_charge(true, 0.0)
		else:
			move = _think_roam(delta, pos)
		if move != Vector3.ZERO:
			dir = move.normalized()

	# рывок в сторону после попадания
	if _want_dodge:
		_want_dodge = false
		if mech.dash_cd <= 0.0:
			var side := dir.cross(Vector3.UP) * (1.0 if randf() < 0.5 else -1.0)
			if _blocked(pos, side, 6.0):
				side = -side
			move = side
			mech.press_dash()
			_dodge_cd = 1.5

	# не толпиться с другими ботами
	for other in mech.get_tree().get_nodes_in_group("mechs"):
		if other == mech or other.dead or other.team != mech.team:
			continue
		var away: Vector3 = pos - other.global_position
		away.y = 0
		var d := away.length()
		if d < 7.0 and d > 0.01:
			move += away / d * (1.0 - d / 7.0)

	if move.length() > 1.0:
		move = move.normalized()

	# застрял (обычно упёрся в кучу обломков): разбить ближайший обломок, иначе шагнуть в сторону
	var real_speed := Vector2(mech.velocity.x, mech.velocity.z).length()
	if move.length() > 0.5 and real_speed < 0.6 and not mech.is_stunned() and mech.blink_left <= 0.0:
		_stuck_t += delta
	else:
		_stuck_t = maxf(_stuck_t - delta * 2.0, 0.0)
	if _stuck_t > 1.0:
		dbg += " STUCK"
		var wr: Node3D = null
		var best := 7.0
		for w in mech.get_tree().get_nodes_in_group("wrecks"):
			var dw: float = w.global_position.distance_to(pos) - w.get_hit_radius()
			if dw < best:
				best = dw
				wr = w
		if wr != null:
			var wp: Vector3 = wr.global_position
			mech.aim_point = Vector3(wp.x, Cfg.aim_height, wp.z)
			var wd := (wp - pos).normalized()
			if mech.torso_forward().dot(Vector3(wd.x, 0, wd.z).normalized()) > 0.9:
				mech._fire = true
				mech._fire2 = true
		else:
			move = move.cross(Vector3.UP) * _strafe
		# зажат между постройкой и другим мехом: понемногу выдавливаемся на ближайшее свободное место
		if _stuck_t > 1.5 and nav != null and not nav.is_free(pos):
			var free: Vector3 = nav.cell_center(nav.nearest_free(nav.cell_of(pos)))
			var to_free := Vector3(free.x - pos.x, 0, free.z - pos.z)
			if to_free.length() > 0.05:
				mech.global_position += to_free.normalized() * minf(to_free.length(), 6.0 * delta)
		if _stuck_t > 4.0:
			_stuck_t = 0.0
			_strafe = -_strafe
			_path = PackedVector3Array()
	mech._move = Vector2(move.x, move.z)


# ------------------------------------------------------------------
#  Цель и видимость
# ------------------------------------------------------------------

# ближайший враг, которого видит команда бота (вижен), не дальше 45 м
func _find_target() -> CharacterBody3D:
	var best: CharacterBody3D = null
	var best_d := 45.0
	for m in mech.get_tree().get_nodes_in_group("mechs"):
		if m.team == mech.team or m.dead or m.is_landing():
			continue
		if main != null and not main.is_visible_to(mech.team, m):
			continue
		var d: float = m.global_position.distance_to(mech.global_position)
		if d < best_d:
			best_d = d
			best = m
	return best


# ближайший видимый вражеский крип в радиусе стрельбы (чуть дальше)
func _find_creep(pos: Vector3) -> Node3D:
	var best: Node3D = null
	var best_d: float = mech.weapon_range() + 8.0
	for c in mech.get_tree().get_nodes_in_group("creeps"):
		if c.team == mech.team or c.dead:
			continue
		if main != null and not main.is_visible_to(mech.team, c):
			continue
		var d: float = c.global_position.distance_to(pos)
		if d < best_d:
			best_d = d
			best = c
	return best


# рельсотрон стреляет, только когда зарядится: держим кнопку, пока цель видно
func _hold_charge(los: bool, _dist: float) -> void:
	if not los:
		return
	for i in mech.weapons.size():
		if mech.weapons[i]["type"] == "rail":
			if i == 0:
				mech._fire = true
			else:
				mech._fire2 = true


# видит ли бот цель: луч от груди до груди, мешают только стены
func _has_los(from: Vector3, to: Vector3) -> bool:
	var a := from + Vector3.UP * 2.4
	var b := to + Vector3.UP * 2.4
	var q := PhysicsRayQueryParameters3D.create(a, b, 1)
	return mech.get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _blocked(pos: Vector3, dir: Vector3, dist: float) -> bool:
	if nav != null and not nav.is_free(pos + dir * dist):
		return true
	var a := pos + Vector3.UP * 1.5
	var q := PhysicsRayQueryParameters3D.create(a, a + dir * dist, 1)
	return not mech.get_world_3d().direct_space_state.intersect_ray(q).is_empty()


# ------------------------------------------------------------------
#  Прицел и стрельба
# ------------------------------------------------------------------

func _think_aim(delta: float, target: CharacterBody3D, pos: Vector3, tpos: Vector3, dist: float) -> void:
	# упреждение: целимся туда, где цель будет, когда долетит снаряд
	var lead := Vector3.ZERO
	var ls: float = mech.lead_speed()
	if ls > 0.0:
		lead = target.velocity * (dist / ls)
	lead.y = 0
	var want := tpos + lead
	if not _aim_ready:
		_aim_ready = true
		_aim = want
	# реакция: прицел догоняет цель с запозданием
	_aim = _aim.lerp(want, 1.0 - exp(-delta / maxf(Cfg.bot_reaction, 0.02)))
	# ошибка: прицел плавно гуляет влево-вправо
	var wobble := sin(_time * 1.3 + _seed) * 0.6 + sin(_time * 2.9 + _seed * 2.0) * 0.4
	var aim_dir := _aim - pos
	aim_dir.y = 0
	var aimed := pos + aim_dir.rotated(Vector3.UP, deg_to_rad(Cfg.bot_aim_error) * wobble)
	aimed.y = Cfg.aim_height
	mech.aim_point = aimed


func _think_fire(delta: float, dir: Vector3, dist: float, los: bool) -> void:
	# стреляет очередями: это даёт игроку окна, чтобы высунуться
	_burst_t -= delta
	if _burst_t <= 0.0:
		_burst_on = not _burst_on
		var base := Cfg.bot_burst_time if _burst_on else Cfg.bot_burst_pause
		_burst_t = base * randf_range(0.7, 1.3)
		if base <= 0.0:
			_burst_on = true
			_burst_t = 0.5
	var facing: float = mech.torso_forward().dot(dir)
	if los and _burst_on and dist < mech.weapon_range() * 0.95 and facing > 0.96:
		mech._fire = true
		mech._fire2 = true


# щит и ремонт работают и без цели в прямой видимости
func _think_defense() -> void:
	if Cfg.bot_use_abilities != 1:
		return
	var hp_k: float = mech.hp / maxf(mech.max_hp(), 1.0)
	var en_k: float = mech.energy / maxf(mech.energy_max(), 1.0)
	var ish: int = mech.ability_index("shield")
	if ish >= 0:
		if mech.barrier_on:
			if _since_hit > 2.5 or en_k < 0.2:
				mech.press_ability(ish)          # выключить
		elif _since_hit < 0.5 and en_k > 0.45 and mech.can_cast(ish):
			mech.press_ability(ish)
	var irp: int = mech.ability_index("repair")
	if irp >= 0 and hp_k < 0.55 and mech.can_cast(irp):
		mech.press_ability(irp)


func _think_abilities(target: CharacterBody3D, pos: Vector3, tpos: Vector3, dir: Vector3, dist: float, los: bool) -> void:
	if Cfg.bot_use_abilities != 1 or _ability_t > 0.0:
		return
	var hp_k: float = mech.hp / maxf(mech.max_hp(), 1.0)

	# мало здоровья: спрятаться в невидимость или отпрыгнуть
	if hp_k < 0.35:
		var ic: int = mech.ability_index("cloak")
		if ic >= 0 and mech.can_cast(ic) and not mech.is_cloaked():
			mech.press_ability(ic)
			_ability_t = Cfg.bot_ability_delay
			return
		var ib: int = mech.ability_index("blink")
		if ib >= 0 and mech.can_cast(ib):
			mech.ability_aim_override = pos - dir * mech.ability_param(ib, "range")
			mech.press_ability(ib)
			_ability_t = Cfg.bot_ability_delay
			return
	# мина: бросить под себя, когда враг близко или когда отходишь
	var im: int = mech.ability_index("mine")
	if im >= 0 and mech.can_cast(im) and (dist < 16.0 or _retreat) and randf() < 0.5:
		mech.press_ability(im)
		_ability_t = Cfg.bot_ability_delay
		return
	if not los or mech.is_cloaked():
		return

	# абилки берутся из модулей сборки бота: если модуля нет, абилки нет
	var ie: int = mech.ability_index("emp")
	var ir: int = mech.ability_index("rockets")
	var ia: int = mech.ability_index("airstrike")
	var ib2: int = mech.ability_index("blink")
	if ie >= 0 and dist < mech.ability_param(ie, "radius") * 0.8 and mech.can_cast(ie):
		mech.press_ability(ie)
	elif ir >= 0 and dist > 8.0 and dist < mech.ability_param(ir, "range") and mech.can_cast(ir):
		# ракеты медленные: бросаем с упреждением, но не идеальным
		var lead: Vector3 = target.velocity * (dist / maxf(mech.ability_param(ir, "speed"), 1.0)) * 0.6
		lead.y = 0
		mech.ability_aim_override = tpos + lead
		mech.press_ability(ir)
	elif ia >= 0 and dist < mech.ability_param(ia, "range") and mech.can_cast(ia):
		# авиаудар падает через несколько секунд: целимся туда, куда цель идёт
		var lead2: Vector3 = target.velocity * mech.ability_param(ia, "delay") * 0.5
		lead2.y = 0
		mech.ability_aim_override = tpos + lead2
		mech.press_ability(ia)
	elif ib2 >= 0 and dist > Cfg.bot_range_max + 4.0 and mech.can_cast(ib2):
		# далеко от цели: прыжок ближе
		var mid := (Cfg.bot_range_min + Cfg.bot_range_max) * 0.5
		mech.ability_aim_override = pos + dir * minf(mech.ability_param(ib2, "range"), dist - mid)
		mech.press_ability(ib2)
	else:
		return
	_ability_t = Cfg.bot_ability_delay


# ------------------------------------------------------------------
#  Движение
# ------------------------------------------------------------------

func _think_move(delta: float, pos: Vector3, tpos: Vector3, dir: Vector3, dist: float, los: bool) -> Vector3:
	_mode_t -= delta
	var lost := not los and _mode != "approach" and _mode != "reposition"
	var too_far := dist > Cfg.bot_range_max + 6.0 and _mode != "approach"
	if _mode_t <= 0.0 or lost or too_far:
		_pick_mode(pos, tpos, dist, los)

	var move := Vector3.ZERO
	match _mode:
		"approach":
			move = _follow_path(delta, pos, tpos, dir)
			mech._run = dist > 30.0 and mech.energy > 40.0
		"reposition":
			var togo := _goal - pos
			togo.y = 0
			if togo.length() < 2.5:
				_mode_t = 0.0          # дошёл: на следующем кадре выберет новое действие
			else:
				move = _follow_path(delta, pos, _goal, togo.normalized())
		"back":
			move = (-dir + dir.cross(Vector3.UP) * _strafe * 0.7).normalized()
		"strafe":
			var mid := (Cfg.bot_range_min + Cfg.bot_range_max) * 0.5
			var drift := 0.0
			if dist > mid + 3.0:
				drift = 0.45
			elif dist < mid - 3.0:
				drift = -0.45
			move = (dir.cross(Vector3.UP) * _strafe + dir * drift).normalized()
		"plant":
			move = Vector3.ZERO

	# упёрся в стену при стрейфе или отходе: меняем сторону
	if (_mode == "strafe" or _mode == "back") and move != Vector3.ZERO and _blocked(pos, move, 4.0):
		_strafe = -_strafe
		_mode_t = minf(_mode_t, 0.3)
		move = Vector3.ZERO
		_flips += 1
		if _flips >= 2 and _pick_goal(pos, tpos):
			# зажат между стенами: уходим на другую позицию
			_flips = 0
			_mode = "reposition"
			_mode_t = 5.0
	return move


func _pick_mode(pos: Vector3, tpos: Vector3, dist: float, los: bool) -> void:
	_path_t = 0.0
	if not los or dist > Cfg.bot_range_max:
		_mode = "approach"
		_mode_t = 0.6
	elif dist < Cfg.bot_range_min:
		_mode = "back"
		_mode_t = randf_range(0.5, 1.0)
	elif randf() < Cfg.bot_plant_chance:
		_mode = "plant"
		_mode_t = randf_range(0.6, 1.1)
	elif randf() < 0.55 and _pick_goal(pos, tpos):
		_mode = "reposition"
		_mode_t = 5.0
	else:
		_mode = "strafe"
		_mode_t = randf_range(0.8, 2.0)
		_flips = 0
		if randf() < 0.4:
			_strafe = -_strafe


# ищет новую огневую позицию: точка на рабочей дистанции сбоку от текущей, откуда цель видно
func _pick_goal(pos: Vector3, tpos: Vector3) -> bool:
	if nav == null:
		return false
	var bearing := atan2(pos.z - tpos.z, pos.x - tpos.x)
	var r_min := Cfg.bot_range_min + 2.0
	var r_max := maxf(Cfg.bot_range_max - 2.0, r_min + 1.0)
	for i in 8:
		var side := _strafe if i < 4 else -_strafe
		var a := bearing + side * randf_range(0.5, 1.5)
		var p := tpos + Vector3(cos(a), 0, sin(a)) * randf_range(r_min, r_max)
		if nav.is_free(p) and _has_los(p, tpos):
			_goal = p
			_path = PackedVector3Array()
			_path_t = 0.0
			if i >= 4:
				_strafe = -_strafe
			return true
	return false


# идёт к точке по найденному пути, путь пересчитывается дважды в секунду
func _follow_path(delta: float, pos: Vector3, tpos: Vector3, dir: Vector3) -> Vector3:
	if nav == null:
		return dir
	_path_t -= delta
	if _path_t <= 0.0 or _path.is_empty():
		_path = nav.find_path(pos, tpos)
		_path_t = 0.5
	if _path.size() <= 2:
		return dir
	# следующая точка пути: первая, до которой ещё не дошли
	for i in range(1, _path.size()):
		var wp := _path[i]
		var d := Vector3(wp.x - pos.x, 0, wp.z - pos.z)
		if d.length() > 2.4:
			return d.normalized()
	return dir


# есть ли под ногами метка вражеского залпа; если да, в какую сторону уходить
# куда уходить от опасности. Бот знает только то, что видно и врагу-человеку:
# метку сработавшей мины и летящие ракеты (куда прицелились, видно по полёту).
# Метки чужих залпов и авиаударов секретные, их бот не видит.
func _danger_escape(pos: Vector3) -> Vector3:
	var now := Time.get_ticks_msec()
	var zones: Array = []
	for z in Fx.danger_zones:
		if z["team"] == mech.team or not is_instance_valid(z["node"]) or z.get("secret", false):
			continue
		zones.append({"id": z["node"].get_instance_id(), "pos": z["pos"], "r": z["radius"], "born": z["born"]})
	for rk in mech.get_tree().get_nodes_in_group("rockets"):
		if rk.team == mech.team or rk.is_falling():
			continue
		if rk.global_position.distance_to(pos) > 40.0:
			continue
		zones.append({"id": rk.get_instance_id(), "pos": rk.target_point(), "r": rk.blast_radius(), "born": rk.born})
	for z in zones:
		var id: int = z["id"]
		if not _zone_choice.has(id):
			# заметил ли бот опасность: решается один раз
			_zone_choice[id] = randf() < clampf(Cfg.bot_dodge_chance * 1.6, 0.0, 1.0)
			if _zone_choice.size() > 60:
				_zone_choice.clear()
				_zone_choice[id] = false
		if not _zone_choice[id]:
			continue
		# и замечает её не мгновенно
		if now - int(z["born"]) < int(Cfg.bot_reaction * 1500.0):
			continue
		var away: Vector3 = pos - z["pos"]
		away.y = 0
		var r: float = z["r"] + 2.0
		if away.length() < r:
			if away.length() < 0.5:
				away = Vector3(cos(_seed), 0, sin(_seed))
			var out := away.normalized()
			if _blocked(pos, out, 4.0):
				out = out.cross(Vector3.UP)
			return out
	return Vector3.ZERO


# ------------------------------------------------------------------
#  Моба: без врага рядом бот лутает, идёт к последней точке, где видел врага, или толкает турели
# ------------------------------------------------------------------

func _has_beam() -> bool:
	for w in mech.weapons:
		if w["type"] == "beam":
			return true
	return false


# стрелять нечем: патроны кончились, а лазера (он без патронов) нет
func _out_of_ammo() -> bool:
	return mech.ammo_ratio() < 0.03 and not _has_beam()


func _go_home(delta: float, pos: Vector3) -> Vector3:
	if main == null:
		return Vector3.ZERO
	var home: Vector3 = main.base_center(mech.team)
	var to := home - pos
	to.y = 0
	if to.length() < 6.0:
		return Vector3.ZERO
	return _follow_path(delta, pos, home, to.normalized())


func _think_roam(delta: float, pos: Vector3) -> Vector3:
	if _retreat:
		var mv := _go_home(delta, pos)
		mech._run = mv != Vector3.ZERO and mech.energy > 30.0
		if mv != Vector3.ZERO:
			mech.aim_point = pos + mv * 10.0
		return mv
	# припасы рядом, которые нужны
	var loot := _think_loot(delta, pos)
	if loot != Vector3.ZERO:
		return loot
	# обломок или ящик рядом, а патроны на исходе: разбить его ради припасов
	# (в PvP раньше: патроны пополнять больше негде)
	if mech.ammo_ratio() < (0.6 if Battle.pvp else 0.35) and not _out_of_ammo():
		var wr := _find_wreck(pos)
		if wr != null:
			dbg = "wreck"
			return _attack_object(delta, pos, wr, 12.0)
	# враг пропал из вида: идём туда, где его видели
	if _last_seen_t < 4.0:
		var togo := _last_seen - pos
		togo.y = 0
		if togo.length() > 3.0:
			mech.aim_point = Vector3(_last_seen.x, Cfg.aim_height, _last_seen.z)
			return _follow_path(delta, pos, _last_seen, togo.normalized())
	if main == null:
		return Vector3.ZERO
	if Battle.pvp:
		return _think_hunt(delta, pos)
	# ничья или чужая точка интереса рядом: встать на неё и захватить
	for poi in mech.get_tree().get_nodes_in_group("pois"):
		if poi.owner_team == mech.team:
			continue
		var pp: Vector3 = poi.global_position
		var dpoi := Vector3(pp.x - pos.x, 0, pp.z - pos.z)
		if dpoi.length() < 28.0:
			if dpoi.length() < Cfg.poi_radius * 0.5:
				return dir_strafe(pos, dpoi)
			return _follow_path(delta, pos, pp, dpoi.normalized())
	# толкаем свою линию: ближайшая вражеская постройка по порядку
	var obj: Node3D = main.objective_for(mech.team, lane)
	if obj == null:
		return Vector3.ZERO
	dbg = "obj " + obj.id
	# сначала выйти на свою линию, а уже по ней идти к турели
	var to_obj: float = obj.global_position.distance_to(pos)
	if to_obj > mech.weapon_range() + 10.0:
		var wp: Vector3 = main.lane_waypoint(mech.team, lane, pos)
		if wp.distance_to(pos) > 6.0:
			mech.aim_point = Vector3(wp.x, Cfg.aim_height, wp.z)
			mech._run = mech.energy > 40.0
			return _follow_path(delta, pos, wp, (wp - pos).normalized())
	return _attack_object(delta, pos, obj, mech.weapon_range() * 0.8)


# припас рядом, который нужен: идём подбирать. Не дошёл за 8 секунд — значит не добраться, забываем про него
func _think_loot(delta: float, pos: Vector3) -> Vector3:
	var pk := _find_pickup(pos)
	if pk == null:
		return Vector3.ZERO
	dbg = "loot"
	var pid: int = pk.get_instance_id()
	if pid != _loot_id:
		_loot_id = pid
		_loot_t = 0.0
	_loot_t += delta
	if _loot_t > 8.0:
		_loot_skip[pid] = true
		_loot_id = 0
	var tp: Vector3 = pk.global_position
	mech.aim_point = Vector3(tp.x, Cfg.aim_height, tp.z)
	return _follow_path(delta, pos, tp, (tp - pos).normalized())


# PvP: врага рядом не видно — ищем. Если врага видит кто-то из своей команды, идём к нему.
# Иначе к месту, куда сейчас упадёт ящик (если патронов меньше половины), или обходим карту
func _think_hunt(delta: float, pos: Vector3) -> Vector3:
	var goal := Vector3.ZERO
	var known := _nearest_seen_enemy(pos)
	var crate = main.crate_warning_pos()
	var dock = _dock_goal()
	var poi = _poi_goal(pos)
	if dock != null:
		dbg = "dock"
		goal = dock
	elif known != null:
		dbg = "hunt"
		goal = known.global_position
	elif poi != null:
		dbg = "poi"
		goal = poi
	elif crate != null and mech.ammo_ratio() < 0.5:
		dbg = "crate"
		goal = crate
	else:
		dbg = "search"
		_hunt_t -= delta
		var near := Vector3(_hunt.x - pos.x, 0, _hunt.z - pos.z).length() < 6.0
		if _hunt_t <= 0.0 or near:
			_hunt = _pick_hunt_point(pos)
			_hunt_t = randf_range(8.0, 14.0)
		goal = _hunt
	var to := goal - pos
	to.y = 0
	if to.length() < 3.0:
		return Vector3.ZERO
	mech._run = to.length() > 25.0 and mech.energy > 40.0
	mech.aim_point = Vector3(goal.x, Cfg.aim_height, goal.z)
	return _follow_path(delta, pos, goal, to.normalized())


# PvP: побитый или пустой бот идёт чиниться к своему ремонтному доку и стоит там, пока не починится
func _dock_goal():
	var full: bool = mech.hp >= mech.max_hp() * 0.95 and mech.ammo_ratio() >= 0.9
	var hurt: bool = mech.hp < mech.max_hp() * 0.6 or mech.ammo_ratio() < 0.4
	for p in mech.get_tree().get_nodes_in_group("pois"):
		if p.kind == "dock" and p.owner_team == mech.team:
			if hurt or (dbg == "dock" and not full):
				return p.global_position
	return null


# ближайшая точка, которая не наша (радар, док): её стоит захватить
func _poi_goal(pos: Vector3):
	var best = null
	var best_d := 1e9
	for p in mech.get_tree().get_nodes_in_group("pois"):
		if p.owner_team == mech.team:
			continue
		var pp: Vector3 = p.global_position
		var d := Vector3(pp.x - pos.x, 0, pp.z - pos.z).length()
		if d < best_d:
			best_d = d
			best = pp
	return best


# ближайший враг, которого сейчас видит команда бота (на любом расстоянии)
func _nearest_seen_enemy(pos: Vector3) -> Node3D:
	var best: Node3D = null
	var best_d := 1e9
	for m in mech.get_tree().get_nodes_in_group("mechs"):
		if m.team == mech.team or m.dead or m.is_landing():
			continue
		if not main.is_visible_to(mech.team, m):
			continue
		var d: float = m.global_position.distance_to(pos)
		if d < best_d:
			best_d = d
			best = m
	return best


# куда пойти искать врагов: случайное проходимое место, половина точек ближе к центру карты;
# не у своей точки появления и не прямо под ногами
func _pick_hunt_point(pos: Vector3) -> Vector3:
	var r: Rect2 = main.map_rect().grow(-8.0)
	var center := Vector3(r.get_center().x, 0, r.get_center().y)
	var home: Vector3 = main.base_center(mech.team)
	for i in 16:
		var p := Vector3(randf_range(r.position.x, r.end.x), 0, randf_range(r.position.y, r.end.y))
		if randf() < 0.5:
			p = p.lerp(center, 0.5)
		if nav != null and not nav.is_free(p):
			continue
		if p.distance_to(home) < 25.0 or p.distance_to(pos) < 15.0:
			continue
		return p
	return center


# стоит на точке: чуть переминается, чтобы не торчать столбом
func dir_strafe(pos: Vector3, to_center: Vector3) -> Vector3:
	var side := Vector3(-to_center.z, 0, to_center.x).normalized() * 0.3
	if _blocked(pos, side, 3.0):
		return Vector3.ZERO
	return side


# подойти к неподвижной цели на дистанцию стрельбы и бить по ней
func _attack_object(delta: float, pos: Vector3, obj: Node3D, reach: float) -> Vector3:
	var tp: Vector3 = obj.global_position
	var to := tp - pos
	to.y = 0
	var dist: float = to.length() - obj.get_hit_radius()
	var dir := to.normalized()
	var los := _has_los(pos, tp)
	mech.aim_point = Vector3(tp.x, Cfg.aim_height, tp.z)
	if dist > reach or not los:
		mech._run = dist > 30.0 and mech.energy > 40.0
		return _follow_path(delta, pos, tp, dir)
	var facing: float = mech.torso_forward().dot(dir)
	if facing > 0.95:
		mech._fire = true
		mech._fire2 = true
	# медленно ходит боком, чтобы не стоять столбом
	var side := dir.cross(Vector3.UP) * _strafe * 0.5
	if _blocked(pos, side, 4.0):
		_strafe = -_strafe
		side = -side
	return side


func _find_pickup(pos: Vector3) -> Node3D:
	var best: Node3D = null
	var best_d := 22.0
	for pk in mech.get_tree().get_nodes_in_group("pickups"):
		if not pk.useful_for(mech) or _loot_skip.has(pk.get_instance_id()):
			continue
		var d: float = pk.global_position.distance_to(pos)
		if d < best_d and _has_los(pos, pk.global_position):
			best_d = d
			best = pk
	return best


func _find_wreck(pos: Vector3) -> Node3D:
	var best: Node3D = null
	var best_d := 18.0
	for w in mech.get_tree().get_nodes_in_group("wrecks"):
		var d: float = w.global_position.distance_to(pos)
		if d < best_d and _has_los(pos, w.global_position):
			best_d = d
			best = w
	return best
