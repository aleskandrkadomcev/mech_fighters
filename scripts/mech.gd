extends CharacterBody3D
## Логика меха: движение, рывок, энергия, поворот корпуса, стрельба, разброс, абилки,
## здоровье и смерть. Один и тот же мех используется и для игрока, и для ботов:
## игроком управляют клавиатура и мышь, ботом управляет bot_brain.gd.
##
## Все числа меха берутся из его сборки (детали, parts.gd): ноги дают скорость,
## корпус здоровье, ядро энергию, оружие свои числа, модули абилки и пассивки.
## Общие правила (цена бега, камера, боты) лежат в settings.gd (в коде это Cfg).

const MechVisual := preload("res://scripts/mech_visual.gd")
const Projectile := preload("res://scripts/projectile.gd")
const Rocket := preload("res://scripts/rocket.gd")
const Art := preload("res://scripts/art.gd")
const Mine := preload("res://scripts/mine.gd")
const HpBar := preload("res://scripts/hp_bar.gd")
const Hitbox := preload("res://scripts/hitbox.gd")
const Lob := preload("res://scripts/lob.gd")

signal fired(mount: int)
signal dashed
signal stepped
signal ability_used(index: int)
signal ability_denied(index: int, reason: String)   # reason: "energy" или "cooldown"
signal damaged(amount: float)
signal died(who: Node3D)
signal build_changed
signal landed                   # приземлился после высадки с неба
signal teleported               # телепорт на базу завершён

var team := 0                   # 0 = игрок, 1 = враги. Свои своих не бьют
var is_player := false
var brain = null                # мозги бота (если это бот)
var camera: Camera3D
var demo = null                 # для автопроверки: словарь с "нажатыми кнопками"

var build := {}                 # из каких деталей собран
var stats := {}                 # итоговые числа меха
var weapons: Array = []         # числа оружия на левом и правом подвесе
var abilities: Array = []       # абилки из модулей: [{type, name, params}]

var hp := 100.0
var dead := false
var seen := true                # видит ли этого меха команда игрока (для врагов: вижен и туман)
var ammo := [0.0, 0.0]          # сколько патронов осталось у ЛКМ и ПКМ
var ability_charges: Array = [] # сколько зарядов осталось у абилок с зарядами
var slow_left := 0.0            # замедление (мина): сколько ещё секунд
var death_velocity := Vector3.ZERO
var _slow_k := 0.0
var stun_left := 0.0
var _stun_total := 1.0          # полное время текущего оглушения, замедления, ЭМИ — для шкалы контроля над полоской
var _slow_total := 1.0
var _no_regen_total := 1.0
var dock_left := 0.0            # стоит в круге своего ремонтного дока (ставит poi.gd каждый тик) — для статусов
var shield_left := 0.0          # неуязвимость после возрождения
var landing_left := 0.0         # высадка с неба: сколько ещё лететь (пока летит, неуязвим и не управляется)
var _landing_total := 1.0
var _landing_marker: Node3D
var tp_left := 0.0              # телепорт на базу: сколько ещё стоять (канал)
var tp_cd := 0.0                # перезарядка телепорта на базу
var _tp_fx: Node3D
var _tp_pressed := false
var last_attacker: Node = null  # кто последним попал (для счёта убийств)
var _since_damage := 99.0       # секунд с последнего урона (самопочинка)
var _still_t := 0.0             # сколько стоит на месте (упор)
var braced := false             # упор включён: бьёт дальше и точнее
var dash_stock := 1.0           # сколько рывков готово (у Осы до двух)
var _rammed := {}               # кого уже ударил этим рывком
var _snap_next := true          # мех телепортировался или модель новая: не сглаживать переход между тиками
var _ghost := false             # только что появился и стоит в другом мехе или обломке: проходит сквозь них (см. _update_ghost)
var _ghost_push := Vector3.ZERO

var aim_point := Vector3(0, 0, -10)
var aim_ground := Vector3(0, 0, -10)   # точка на земле под курсором: туда стреляет гранатомёт
var _hit_h := 0.0               # высота хитбокса по модели (0 — ещё не мерили)
var ability_aim_override = null # бот может указать точку для ракет отдельно от прицела пушек
var torso_yaw := 0.0
var legs_yaw := 0.0
var dash_left := 0.0
var dash_cd := 0.0
var dash_dir := Vector3.FORWARD
var visual: Node3D
var hitbox: Area3D              # цилиндр для попаданий (отдельно от капсулы для ходьбы)

# энергия
var energy := 100.0
var running := false            # прямо сейчас бежит
var run_locked := false         # выдохся: бег недоступен, пока энергия не наберётся до порога
var no_regen_left := 0.0       # пока больше нуля, энергия не восстанавливается (импульс и подобное)

# абилки
var ability_cd: Array = []
var _salvo_left := 0
var _salvo_timer := 0.0
var _salvo_target := Vector3.ZERO
var _salvo_marker: Node3D
var _salvo_index := 0
var _salvo_params := {}
var cloak_left := 0.0           # невидимость: сколько ещё секунд
var _cloak_break := true        # снимается ли выстрелом
var repair_left := 0.0          # наноремонт: сколько ещё секунд лечится
var _repair_rate := 0.0
var barrier_on := false         # щит включён
var _barrier_i := -1
var _barrier_hit := 0.0
var _barrier: MeshInstance3D
var _barrier_mat: ShaderMaterial
var blink_left := 0.0           # блинк: сколько ещё стоять до прыжка
var root_left := 0.0            # обездвижен (связка): ноги не ходят, корпус крутится, стреляет
var _root_total := 1.0
var disarm_left := 0.0          # обезоружен (глушащий дротик): не стреляет, абилки и ходьба есть
var _disarm_total := 1.0
var stance_on := false          # оборонительная позиция: стоит, стреляет, урон меньше
var _stance_i := -1
var _pull := Vector3.ZERO       # притяжение гравитационного якоря за этот тик (не копится в скорости)
var _jump_up := 0.0             # прыжок: сколько ещё взлетать (потом падает на точку, как при высадке)
var _jump_i := -1
var _jump_dest := Vector3.ZERO
var _jump_land := false         # текущее приземление — после прыжка: удар вместо защиты
var purge_left := 0.0           # аварийный перезапуск: контроль не берёт
var overdrive_left := 0.0       # форсаж: быстрее ходит
var _overdrive_k := 0.0
var rapid_left := 0.0           # форсированная подача: чаще стреляет
var _rapid_k := 0.0
var matrix_left := 0.0          # матрица брони: меньше урона
var _matrix_k := 0.0
var periscope_left := 0.0       # перископ: дальше видит, сильнее омни
var relay_left := 0.0           # рядом свой ретранслятор: урон больше (держит, пока мех в его круге)
var scope_on := false           # прицеливание (Ястреб): дальше бьёт и видит, рельса сильнее, ход медленнее
var _scope_i := -1
var net_left := 0.0             # маскировочная сеть: пока стоит на месте — невидим
var siege_on := false           # осадный режим (Осадник): стоит, вместо пушек бьёт мортирой далеко
var _siege_i := -1
var _siege_cd := 0.0
var intercept_left := 0.0       # ПРО-перехват (Бастион): сбивает вражеские ракеты и гранаты рядом
var _icpt_i := -1
var _icpt_t := 0.0
var _jump_from := Vector3.ZERO   # откуда прыгнул (десантный прыжок отбрасывает врагов в эту сторону)
var burn_left := 0.0            # подожгли пулями Поджигателя: теряет здоровье
var _burn_dps := 0.0
var _burn_src: Node = null
var _burn_tick := 0.0
var _net_still := false
var _relay_k := 0.0
var _peri_k := 0.0
var _peri_omni := 0.0
var marked_left := 0.0          # на мне дротик-целеуказатель: получаю больше урона
var _mark_k := 0.0
var _shove_v := Vector3.ZERO    # толчок ударной волны: скорость и сколько ещё секунд
var _shove_t := 0.0
var _matrix_vis: MeshInstance3D
var _ip_yaw := 0.0              # значения прошлого тика: прицел на земле рисуется каждый кадр и плавно
var _ip_aim := Vector3.ZERO     # переходит от прошлого тика к текущему (как движок сглаживает модель меха)
var _ip_ground := Vector3.ZERO
var _ip_spread := [0.0, 0.0]
const SHOVE_SPEED := 30.0       # единиц/с, с которой отлетает мех от ударной волны
const JUMP_UP := 0.35           # секунд взлёта на двигателях до ухода из кадра
const PROBE_ARC := 6.0          # на сколько единиц зонд в полёте выше точки броска (перелетает стены)
var _blink_dest := Vector3.ZERO
var _blink_marker: Node3D
var _repair_fx: CPUParticles3D
var _smoke_fx: CPUParticles3D    # дым из подбитого меха (мало здоровья)
var _spark_t := 0.0
var _fade := 0.0

# состояние оружия по подвесам
var _w_timer := [0.0, 0.0]
var _w_bloom := [0.0, 0.0]
var _w_spread := [0.0, 0.0]
var _beam_on := [false, false]
var _beam_fx_t := [0.0, 0.0]
var _beam_exclude: Array[RID] = []
var _beam_ex_t := 0.0
var _w_spin := [0.0, 0.0]       # раскрутка Гатлинга 0..1
var _w_charge := [0.0, 0.0]     # заряд рельсотрона 0..1
var _energy_warned := [false, false]

var _move := Vector2.ZERO
var _run := false
var _fire := false               # ЛКМ
var _fire2 := false              # ПКМ
var _fire_prev := [false, false]
var _ammo_warned := [false, false]
var _dash_pressed := false
var _ability_pressed: Array = []
var _col: CollisionShape3D
var _bar: Node3D
var _parts_version := -1
var _look := {}


func _ready() -> void:
	_set_ghost(true)      # обычно: layer 2, mask 1 | 2 | 16 | 32 — стены, другие мехи, обломки, постройки
	add_to_group("mechs")
	add_to_group("damageable")
	# капсула только для ходьбы: узкая, чтобы не цепляться боками за стены. Снаряды её не видят
	_col = CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 1.25
	cap.height = 3.6
	_col.shape = cap
	_col.position = Vector3(0, 1.8, 0)
	add_child(_col)

	hitbox = Hitbox.new()
	hitbox.mech = self
	add_child(hitbox)

	_bar = HpBar.new()
	_bar.color = Cfg.bar_self if is_player else (Cfg.bar_ally if team == 0 else Cfg.bar_enemy)
	add_child(_bar)
	_make_ability_fx()

	if build.is_empty():
		build = Parts.DEFAULT_BUILD.duplicate(true)
	build = Parts.upgrade_build(build)
	_apply_build()
	hp = max_hp()
	energy = energy_max()
	dash_stock = stats.get("dash_charges", 1.0)
	refill_all()


func _unhandled_input(event: InputEvent) -> void:
	if not is_player:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_SPACE:
			_dash_pressed = true
			return
		if event.physical_keycode == KEY_T:
			_tp_pressed = true
			return
		for i in abilities.size():
			if event.physical_keycode == Parts.ABILITY_KEYS[i]:
				_ability_pressed[i] = true


# ------------------------------------------------------------------
#  СБОРКА
# ------------------------------------------------------------------

func set_build(b: Dictionary) -> void:
	build = Parts.upgrade_build(b).duplicate(true)
	if is_inside_tree():
		_apply_build()
		hp = max_hp()
		energy = energy_max()
		dash_stock = stats.get("dash_charges", 1.0)
		refill_all()


# пересчитать числа из деталей; модель пересобирается, только если поменялся внешний вид
func _apply_build() -> void:
	var r := Parts.compute(build)
	stats = r["stats"]
	weapons = r["weapons"]
	abilities = r["abilities"]
	_parts_version = Parts.version
	while ability_cd.size() < abilities.size():
		ability_cd.append(0.0)
	ability_cd.resize(abilities.size())
	var old_charges := ability_charges.duplicate()
	ability_charges.resize(abilities.size())
	for i in abilities.size():
		var mx := ability_charges_max(i)
		ability_charges[i] = mx if i >= old_charges.size() or old_charges[i] == null else minf(old_charges[i], mx)
	_ability_pressed.resize(abilities.size())
	for i in _ability_pressed.size():
		_ability_pressed[i] = false

	var look := look_of(stats, weapons, abilities)
	if visual == null or look != _look:
		_look = look
		if visual != null:
			visual.queue_free()
		visual = MechVisual.new()
		visual.st = stats
		add_child(visual)
		# мехи без краски команды: свой/чужой видно по полоске здоровья и нику над мехом
		visual.build(Cfg.mech_accent, Color(1, 1, 1), look, team == 0)
		visual.footstep.connect(_on_footstep)
		_hit_h = 0.0      # новая модель: высоту хитбокса перемерить
		_fade = 0.0
		_snap_next = true
		dash_stock = minf(dash_stock, stats["dash_charges"])
	else:
		visual.st = stats
	if _bar != null:
		_bar.position = Vector3(0, 2.37 * stats["legs_scale"] + 1.7 * stats["hull_scale"] + 1.0, 0)
	if _barrier != null:
		var br: float = stats["hit_radius"] + 1.1
		_barrier.scale = Vector3(br, br * 0.95, br)
		_barrier.position = Vector3(0, 2.1 * stats["legs_scale"], 0)
	if _barrier_i >= abilities.size() or (_barrier_i >= 0 and abilities[_barrier_i]["type"] != "shield"):
		_set_barrier(false)
	if _stance_i >= abilities.size() or (_stance_i >= 0 and abilities[_stance_i]["type"] != "stance"):
		stance_on = false
		_stance_i = -1
	hp = minf(hp, max_hp())
	build_changed.emit()


# как выглядит мех (из этого собирается модель; одинаковый вид = модель не пересобирается)
static func look_of(st: Dictionary, wl: Array, al: Array) -> Dictionary:
	return {
		"legs_scale": st["legs_scale"],
		"hull_scale": st["hull_scale"],
		"style": st.get("style", "mid"),
		"model": st.get("model", ""),
		"weapons": [wl[0]["look"], wl[1]["look"]],
		"rockets": al.any(func(a): return a["type"] == "rockets"),
	}


# игра идёт тиками (30 в секунду), картинка между тиками сглаживается.
# После телепорта или новой модели сглаживать нельзя (мех "проедет" через полкарты): сбрасываем
static func snap_interpolation(n: Node) -> void:
	if n is Node3D:
		n.reset_physics_interpolation()
	for c in n.get_children():
		snap_interpolation(c)


# ------------------------------------------------------------------
#  Справочные функции
# ------------------------------------------------------------------

func get_hit_radius() -> float:
	return stats.get("hit_radius", 1.9)


# хитбокс — столб настоящей высоты меха (по модели, меряется после постройки)
func get_hit_height() -> float:
	if _hit_h > 0.0:
		return _hit_h
	return 2.37 * stats.get("legs_scale", 1.0) + 1.7 * stats.get("hull_scale", 1.0)


func _measure_height() -> float:
	var top := 0.0
	for mi in visual.find_children("*", "MeshInstance3D", true, false):
		if not mi.visible or mi.mesh == null or mi.top_level:
			continue
		var bb: AABB = mi.global_transform * mi.get_aabb()
		top = maxf(top, bb.end.y - global_position.y)
	return clampf(top, 2.0, 8.0)


func max_hp() -> float:
	return stats.get("hp", 300.0)


func energy_max() -> float:
	return stats.get("energy_max", 100.0)


func walk_speed() -> float:
	return stats["walk_speed"] * _speed_mult()


func run_speed() -> float:
	return stats["run_speed"] * _speed_mult()


func _speed_mult() -> float:
	var k := 1.0 if is_player else Cfg.bot_speed
	if slow_left > 0.0:
		k *= 1.0 - _slow_k
	if overdrive_left > 0.0:
		k *= 1.0 + _overdrive_k
	if scope_on:
		k *= 1.0 - ability_param(_scope_i, "slow")
	return k


# урон: у ботов свой множитель, плюс бонус команды с точки «Арсенал»
func damage_mult() -> float:
	var k := 1.0 if is_player else Cfg.bot_damage
	if relay_left > 0.0:
		k *= 1.0 + _relay_k
	# Призрак: первый выстрел из невидимости сильнее (выстрел тут же снимает невидимость)
	if is_cloaked() and stats.get("ambush", 0.0) > 0.0:
		k *= 1.0 + stats["ambush"]
	return k * _game_mult("damage")


# ретранслятор Командира рядом: урон больше, пока держит (сам ретранслятор продлевает раз в четверть секунды)
func relay_buff(k: float, seconds: float) -> void:
	relay_left = maxf(relay_left, seconds)
	_relay_k = k


func _game_mult(kind: String) -> float:
	var g = get_tree().current_scene if is_inside_tree() else null
	if g != null and g.has_method("team_mult"):
		return g.team_mult(team, kind)
	return 1.0


# ------------------------------------------------------------------
#  Патроны и заряды
# ------------------------------------------------------------------

func ammo_max(i: int) -> float:
	return weapons[i].get("ammo", 0.0) if i < weapons.size() else 0.0


func ability_charges_max(i: int) -> float:
	return ability_param(i, "charges")


func refill_all() -> void:
	for i in 2:
		ammo[i] = ammo_max(i)
	for i in abilities.size():
		ability_charges[i] = ability_charges_max(i)


# доля боезапаса обеих пушек; true, если что-то добавилось
func add_ammo(frac: float) -> bool:
	var got := false
	for i in 2:
		var mx := ammo_max(i)
		if mx > 0.0 and ammo[i] < mx:
			ammo[i] = minf(ammo[i] + mx * frac, mx)
			got = true
	return got


func needs_ammo() -> bool:
	for i in 2:
		if ammo_max(i) > 0.0 and ammo[i] < ammo_max(i):
			return true
	return false


func ammo_ratio() -> float:
	var tot := 0.0
	var cur := 0.0
	for i in 2:
		tot += ammo_max(i)
		cur += ammo[i]
	return 1.0 if tot <= 0.0 else cur / tot


# заряд случайной абилке, у которой их не полно; true, если было куда
func add_charge(n: int) -> bool:
	var need: Array = []
	for i in abilities.size():
		var mx := ability_charges_max(i)
		if mx > 0.0 and ability_charges[i] < mx:
			need.append(i)
	if need.is_empty():
		return false
	var i: int = need.pick_random()
	ability_charges[i] = minf(ability_charges[i] + n, ability_charges_max(i))
	return true


func needs_charges() -> bool:
	for i in abilities.size():
		if ability_charges_max(i) > 0.0 and ability_charges[i] < ability_charges_max(i):
			return true
	return false


func add_energy(v: float) -> bool:
	if energy >= energy_max() - 0.5:
		return false
	energy = minf(energy + v, energy_max())
	return true


func heal(v: float) -> void:
	hp = minf(hp + v, max_hp())


func apply_slow(k: float, seconds: float) -> void:
	if dead or shield_left > 0.0 or seconds <= 0.0:
		return
	_slow_k = maxf(_slow_k if slow_left > 0.0 else 0.0, k)
	if seconds > slow_left:
		_slow_total = seconds
	slow_left = maxf(slow_left, seconds)


func is_dashing() -> bool:
	return dash_left > 0.0


func is_stunned() -> bool:
	return stun_left > 0.0


func is_cloaked() -> bool:
	return cloak_left > 0.0 or (net_left > 0.0 and _net_still)


# контроль для шкалы над полоской здоровья: самый жёсткий из действующих — [название, сколько осталось 0..1]
func control_info() -> Array:
	if stun_left > 0.0:
		return ["Оглушён", stun_left / maxf(_stun_total, 0.01)]
	if disarm_left > 0.0:
		return ["Обезоружен", disarm_left / maxf(_disarm_total, 0.01)]
	if root_left > 0.0:
		return ["Обездвижен", root_left / maxf(_root_total, 0.01)]
	if no_regen_left > 0.0:
		return ["ЭМИ", no_regen_left / maxf(_no_regen_total, 0.01)]
	if slow_left > 0.0:
		return ["Замедлен", slow_left / maxf(_slow_total, 0.01)]
	return ["", 0.0]


# статусы своего меха для интерфейса: [название, сколько осталось секунд (-1 — без срока), полезный ли,
# значок (assets/ui/hud), описание для подсказки на Alt].
# Сначала вредные, потом полезные
func status_list() -> Array:
	var out: Array = []
	if dead:
		return out
	if stun_left > 0.0:
		out.append(["Оглушён", stun_left, false, "stun", "Не ходит, не стреляет и не жмёт абилки."])
	if disarm_left > 0.0:
		out.append(["Обезоружен", disarm_left, false, "jammer", "Глушащий дротик: пушки не стреляют. Ходить и жать абилки можно."])
	if marked_left > 0.0:
		out.append(["Метка", marked_left, false, "marker", "Дротик-целеуказатель: по тебе проходит на %d%% больше урона." % roundi(_mark_k * 100.0)])
	if root_left > 0.0:
		out.append(["Обездвижен", root_left, false, "bolas", "Связка или капкан держит ноги: не ходит и не делает рывок. Корпус и пушки работают."])
	if no_regen_left > 0.0:
		out.append(["ЭМИ", no_regen_left, false, "noregen", "Энергия не восстанавливается."])
	if burn_left > 0.0:
		out.append(["Горит", burn_left, false, "napalm", "Подожгли пулями: теряет здоровье, пока горит."])
	if slow_left > 0.0:
		out.append(["Замедлен", slow_left, false, "slow", "Скорость меньше на %d%%." % roundi(_slow_k * 100.0)])
	if run_locked:
		out.append(["Выдохся", -1.0, false, "tired", "Энергия кончилась на бегу: бег вернётся, когда энергия поднимется до отметки на полоске."])
	if shield_left > 0.0:
		out.append(["Неуязвим", shield_left, true, "invuln", "Урон не проходит."])
	if repair_left > 0.0:
		out.append(["Чинится", repair_left, true, "repair", "Наноремонт: здоровье растёт."])
	elif hp < max_hp() - 0.5 and (dock_left > 0.0 or (stats.get("regen_hp", 0.0) > 0.0 and _since_damage >= stats.get("regen_delay", 4.0))):
		out.append(["Чинится", -1.0, true, "repair", "Ремонтный док или самопочинка шасси: здоровье растёт, пока не получаешь урон."])
	if barrier_on:
		out.append(["Щит", -1.0, true, "shield", "Генератор щита включён: урон уходит в щит и ест энергию."])
	if cloak_left > 0.0:
		out.append(["Невидим", cloak_left, true, "cloak", "Враги не видят тебя, кроме омни-сенсора вблизи. Выстрел снимает маскировку."])
	if braced:
		out.append(["Упор", -1.0, true, "brace", "Мех стоит на упорах: точнее стреляет."])
	if purge_left > 0.0:
		out.append(["Перезапуск", purge_left, true, "purge", "Аварийный перезапуск: оглушение, ЭМИ, замедление и прочий контроль не действуют."])
	if matrix_left > 0.0:
		out.append(["Матрица брони", matrix_left, true, "matrix", "Входящий урон меньше на %d%%." % roundi(_matrix_k * 100.0)])
	if overdrive_left > 0.0:
		out.append(["Форсаж", overdrive_left, true, "overdrive", "Скорость больше на %d%%." % roundi(_overdrive_k * 100.0)])
	if rapid_left > 0.0:
		out.append(["Форсированная подача", rapid_left, true, "rapid", "Пушки стреляют на %d%% чаще." % roundi(_rapid_k * 100.0)])
	if periscope_left > 0.0:
		out.append(["Перископ", periscope_left, true, "periscope", "Обзор и омни-сенсор дальше."])
	if relay_left > 0.0:
		out.append(["Ретранслятор", -1.0, true, "relay", "Рядом свой ретранслятор: урон больше на %d%%." % roundi(_relay_k * 100.0)])
	if scope_on:
		out.append(["Прицеливание", -1.0, true, "scope", "Пушки и обзор дальше, рельса сильнее, ход медленнее. Повторное нажатие — выключить."])
	if siege_on:
		out.append(["Осадный режим", -1.0, true, "siege", "Стоит на упорах: пушки молчат, ЛКМ/ПКМ — снаряд по дуге далеко. Повторное нажатие — сложиться."])
	if intercept_left > 0.0:
		out.append(["ПРО-перехват", intercept_left, true, "intercept", "Сбивает вражеские ракеты и гранаты рядом."])
	if net_left > 0.0:
		out.append(["Маскировочная сеть", net_left, true, "camo", "Стоишь — враги не видят (кроме омни-сенсора вблизи). Пошёл — видно. Выстрел снимает сеть."])
	if stance_on:
		out.append(["Оборона", -1.0, true, "stance", "Стоит на месте и стреляет, входящий урон меньше на %d%%." % roundi(ability_param(_stance_i, "reduce") * 100.0)])
	if _game_mult("damage") > 1.0:
		out.append(["Арсенал", -1.0, true, "arsenal", "Точка «Арсенал» у твоей команды: урон больше."])
	if _game_mult("regen") > 1.0:
		out.append(["Реактор", -1.0, true, "reactor", "Точка «Реактор» у твоей команды: энергия растёт быстрее."])
	return out


# сколько ещё действует абилка (секунды); для щита 1, пока включён; 0 = не действует
func ability_active(index: int) -> float:
	match abilities[index]["type"]:
		"cloak":
			return cloak_left
		"repair":
			return repair_left
		"shield":
			return 1.0 if barrier_on and _barrier_i == index else 0.0
		"blink":
			return blink_left
		"stance":
			return 1.0 if stance_on and _stance_i == index else 0.0
		"siege":
			return 1.0 if siege_on and _siege_i == index else 0.0
		"scope":
			return 1.0 if scope_on and _scope_i == index else 0.0
		"intercept":
			return intercept_left
		"camo":
			return net_left
		"purge":
			return purge_left
		"matrix":
			return matrix_left
		"overdrive":
			return overdrive_left
		"rapid":
			return rapid_left
		"periscope":
			return periscope_left
	return 0.0


func is_beaming() -> bool:
	return _beam_on[0] or _beam_on[1]


func weapon_spread_deg(i: int) -> float:
	return _w_spread[i] + _w_bloom[i]


func get_spread_deg() -> float:
	return maxf(weapon_spread_deg(0), weapon_spread_deg(1))


# максимальная дальность из двух пушек
func weapon_range() -> float:
	return maxf(w_range(0), w_range(1))


# дальность пушки с учётом упора
func w_range(i: int) -> float:
	var r: float = weapons[i]["range"]
	if braced:
		r *= 1.0 + stats.get("brace_bonus", 0.0)
	if scope_on:
		r *= 1.0 + ability_param(_scope_i, "boost")
	return r


func is_landing() -> bool:
	return landing_left > 0.0 or _jump_up > 0.0


# сколько секунд осталось до готовности (таймер у курсора, когда жмёшь на перезарядке):
# index ≥ 0 — абилка модуля, -1 — рывок, -5 — телепорт на базу; 0 — ждать нечего (не по времени)
func cooldown_left(index: int) -> float:
	if index >= 0:
		return ability_cd[index] if index < ability_cd.size() else 0.0
	if index == -1:
		return dash_cd if dash_stock < 1.0 else 0.0
	if index == -5:
		return tp_cd
	return 0.0


func is_channeling() -> bool:
	return tp_left > 0.0


# скорость снаряда для упреждения (у лазера упреждение не нужно)
func lead_speed() -> float:
	var best := 0.0
	for w in weapons:
		if w["type"] == "bullet":
			best = maxf(best, w["bullet_speed"])
	return best


func torso_forward() -> Vector3:
	return Vector3(-sin(torso_yaw), 0, -cos(torso_yaw))


# то же для рисования между тиками (прицел на земле): плавно от прошлого тика к текущему
func torso_forward_smooth() -> Vector3:
	var yaw := lerp_angle(_ip_yaw, torso_yaw, Engine.get_physics_interpolation_fraction())
	return Vector3(-sin(yaw), 0, -cos(yaw))


func aim_point_smooth() -> Vector3:
	return _ip_aim.lerp(aim_point, Engine.get_physics_interpolation_fraction())


func aim_ground_smooth() -> Vector3:
	return _ip_ground.lerp(aim_ground, Engine.get_physics_interpolation_fraction())


func spread_smooth(i: int) -> float:
	if i >= 2:
		return weapon_spread_deg(i)
	return lerpf(_ip_spread[i], weapon_spread_deg(i), Engine.get_physics_interpolation_fraction())


func aim_distance() -> float:
	var d := aim_point - global_position
	d.y = 0
	return maxf(d.length(), 4.0)


func ability_index(type: String) -> int:
	for i in abilities.size():
		if abilities[i]["type"] == type:
			return i
	return -1


func ability_param(index: int, key: String) -> float:
	return abilities[index]["params"].get(key, 0.0)


func ability_cooldown_max(index: int) -> float:
	return ability_param(index, "cooldown") * stats.get("cd_mult", 1.0)


func ability_cost(index: int) -> float:
	return ability_param(index, "cost")


func can_cast(index: int) -> bool:
	if index < 0 or index >= abilities.size():
		return false
	var type: String = abilities[index]["type"]
	if (type == "shield" and barrier_on) or (type == "stance" and stance_on) or (type == "siege" and siege_on):
		return not dead and not is_stunned()     # выключить щит и оборону можно всегда
	if type in ["blink", "jump", "dropjump"] and (root_left > 0.0 or stance_on or siege_on):
		return false
	if dead or (is_stunned() and type != "purge") or ability_cd[index] > 0.0 or energy < ability_cost(index):
		return false
	if ability_charges_max(index) > 0.0 and ability_charges[index] < 1.0:
		return false
	if type == "blink" and blink_left > 0.0:
		return false
	return not (type == "rockets" and _salvo_left > 0)


# кнопки, которые "нажимает" бот
func press_dash() -> void:
	_dash_pressed = true


func press_tp() -> void:
	_tp_pressed = true


func can_tp() -> bool:
	return not dead and tp_cd <= 0.0 and tp_left <= 0.0 and not is_landing() and not Battle.pvp     # в PvP базы нет


func press_ability(index: int) -> void:
	if index >= 0 and index < _ability_pressed.size():
		_ability_pressed[index] = true


# ------------------------------------------------------------------
#  Главный цикл
# ------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if dead:
		return
	_ip_yaw = torso_yaw
	_ip_aim = aim_point
	_ip_ground = aim_ground
	for i in mini(weapons.size(), 2):
		_ip_spread[i] = weapon_spread_deg(i)
	# числа деталей поменяли в панели F2: пересчитываемся на лету
	if _parts_version != Parts.version:
		_apply_build()

	if _jump_up > 0.0:
		_update_jump_up(delta)
		return
	if is_landing():
		_update_landing(delta)
		return
	if _ghost:
		_update_ghost()
	stun_left = maxf(stun_left - delta, 0.0)
	shield_left = maxf(shield_left - delta, 0.0)
	slow_left = maxf(slow_left - delta, 0.0)
	root_left = maxf(root_left - delta, 0.0)
	disarm_left = maxf(disarm_left - delta, 0.0)
	purge_left = maxf(purge_left - delta, 0.0)
	overdrive_left = maxf(overdrive_left - delta, 0.0)
	rapid_left = maxf(rapid_left - delta, 0.0)
	relay_left = maxf(relay_left - delta, 0.0)
	matrix_left = maxf(matrix_left - delta, 0.0)
	periscope_left = maxf(periscope_left - delta, 0.0)
	marked_left = maxf(marked_left - delta, 0.0)
	if _matrix_vis != null and _matrix_vis.visible != (matrix_left > 0.0 and visual.visible):
		_matrix_vis.visible = matrix_left > 0.0 and visual.visible
	dock_left = maxf(dock_left - delta, 0.0)
	tp_cd = maxf(tp_cd - delta, 0.0)
	_since_damage += delta
	var blink_vis := shield_left <= 0.0 or fmod(shield_left, 0.2) > 0.08   # мигает, пока неуязвим
	visual.visible = blink_vis and seen
	# самопочинка (Механик): давно не получал урон
	if stats.get("regen_hp", 0.0) > 0.0 and _since_damage >= stats.get("regen_delay", 4.0) and hp < max_hp():
		hp = minf(hp + stats["regen_hp"] * delta, max_hp())

	if brain != null:
		brain.think(delta)
		aim_ground = Vector3(aim_point.x, 0.0, aim_point.z)     # бот бросает гранату под ноги цели
	elif demo != null:
		_read_demo()
	elif is_player:
		_read_player()

	if is_stunned():
		# оглушён: стоит, не стреляет, не кастует, корпус не крутится
		_move = Vector2.ZERO
		_run = false
		_fire = false
		_fire2 = false
		_dash_pressed = false
		for i in _ability_pressed.size():
			if abilities[i]["type"] != "purge":      # перезапуск снимает оглушение — его жать можно
				_ability_pressed[i] = false

	if root_left > 0.0 or stance_on or siege_on:
		# обездвижен, в обороне или в осадном режиме: ноги стоят, корпус крутится, стреляет
		_move = Vector2.ZERO
		_run = false
		_dash_pressed = false
	if disarm_left > 0.0:
		_fire = false
		_fire2 = false

	if blink_left > 0.0:
		# готовится к прыжку: стоит на месте
		_move = Vector2.ZERO
		_run = false
		_dash_pressed = false

	_update_tp(delta)
	_update_move(delta)
	_update_energy(delta)
	if not is_stunned():
		_update_aim(delta)
	_update_spread(delta)
	_update_fire(delta)
	_update_abilities(delta)
	visual.stunned = is_stunned()
	_aim_guns()
	visual.update_visual(delta, global_position, velocity, legs_yaw, torso_yaw, is_dashing())
	if _hit_h <= 0.0:
		_hit_h = _measure_height()
	if _snap_next:
		_snap_next = false
		snap_interpolation(self)
	_update_ability_fx(delta)
	visual.braced = braced or stance_on or siege_on
	if _bar != null:
		_bar.set_ratio(hp / maxf(max_hp(), 1.0))
		var ctl := control_info()
		_bar.set_control(ctl[0], ctl[1])


func _read_demo() -> void:
	_move = demo.get("move", Vector2.ZERO)
	_run = demo.get("run", false)
	_fire = demo.get("fire", false)
	_fire2 = demo.get("fire2", _fire)
	if demo.get("dash", false):
		_dash_pressed = true
		demo["dash"] = false
	if demo.get("tp", false):
		_tp_pressed = true
		demo["tp"] = false
	if demo.get("q", false):
		press_ability(0)
		demo["q"] = false
	if demo.get("e", false):
		press_ability(1)
		demo["e"] = false
	if demo.has("aim"):
		aim_point = demo["aim"]
		aim_ground = Vector3(aim_point.x, 0.0, aim_point.z)


func _read_player() -> void:
	var m := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_A):
		m.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D):
		m.x += 1.0
	if Input.is_physical_key_pressed(KEY_W):
		m.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S):
		m.y += 1.0
	_move = m.normalized() if m.length() > 1.0 else m
	_run = Input.is_physical_key_pressed(KEY_SHIFT)
	_fire = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not Cfg.ui_hover and not Input.is_key_pressed(KEY_ALT) and not Cfg.ping_hold
	_fire2 = Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and not Cfg.ui_hover and not Input.is_key_pressed(KEY_ALT) and not Cfg.ping_hold

	if camera != null and not Cfg.ui_hover:
		var mp := get_viewport().get_mouse_position()
		var o := camera.project_ray_origin(mp)
		var d := camera.project_ray_normal(mp)
		aim_point = aim_from_ray(o, d)
		var g = Plane(Vector3.UP, 0.0).intersects_ray(o, d)
		if g != null:
			aim_ground = g


# куда целится игрок: курсор на видимом враге (мех, крип, постройка) — на высоту середины его
# хитбокса, но туда же, куда показывает курсор (можно брать упреждение); иначе — в точку на земле
# (стрельба вслепую). Гранатомёт всегда бьёт по земле под курсором (aim_ground)
func aim_from_ray(o: Vector3, d: Vector3) -> Vector3:
	var q := PhysicsRayQueryParameters3D.create(o, o + d * 500.0, 4)
	q.collide_with_areas = true
	q.collide_with_bodies = false
	q.exclude = Fx.team_rids(team)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		var u = hit["collider"].get("mech")
		if u != null and is_instance_valid(u) and u.get("seen") != false and u.has_method("get_hit_height"):
			var p = Plane(Vector3.UP, u.global_position.y + u.get_hit_height() * 0.5).intersects_ray(o, d)
			if p != null:
				return p
	var g = Plane(Vector3.UP, 0.0).intersects_ray(o, d)
	return g if g != null else aim_point


# ------------------------------------------------------------------
#  ЗДОРОВЬЕ
# ------------------------------------------------------------------

# kind: "" обычный урон, "explosion" взрыв (режется защитой от взрывов), "beam" луч (каждый кадр понемногу).
# src: кто стрелял (для счёта)
func take_damage(amount: float, pos: Vector3, _dir: Vector3, kind := "", src: Node = null) -> void:
	if dead or amount <= 0.0 or shield_left > 0.0 or is_landing():
		return
	# пассивки стрелка: Ловчий бьёт обездвиженных сильнее, пули Поджигателя поджигают
	if src != null and is_instance_valid(src) and src.get("stats") is Dictionary:
		var sst: Dictionary = src.get("stats")
		if root_left > 0.0 and sst.get("rooted_bonus", 0.0) > 0.0:
			amount *= 1.0 + sst["rooted_bonus"]
		if kind == "" and sst.get("ignite_dps", 0.0) > 0.0 and src.get("team") != team:
			ignite(sst["ignite_dps"], sst.get("ignite_time", 3.0), src)
	if kind == "explosion":
		amount *= 1.0 - stats.get("resist_explosion", 0.0)
	# бронеплиты Бастиона: каждое попадание слабее (лучи не режут), но не меньше 30%
	var plate: float = stats.get("armor_flat", 0.0)
	if plate > 0.0 and kind != "beam":
		amount = maxf(amount - plate, amount * 0.3)
	if stance_on:
		amount *= 1.0 - clampf(ability_param(_stance_i, "reduce"), 0.0, 0.95)
	if matrix_left > 0.0:
		amount *= 1.0 - clampf(_matrix_k, 0.0, 0.95)
	if marked_left > 0.0:
		amount *= 1.0 + _mark_k
	_since_damage = 0.0
	if src != null and is_instance_valid(src) and src != self:
		last_attacker = src
	if barrier_on:
		amount = _barrier_absorb(amount)
		if amount <= 0.0:
			if brain != null:
				brain.on_damaged()
			return
	amount = minf(amount, hp)
	hp -= amount
	damaged.emit(amount)
	Battle.on_damage(src, self, amount, pos)
	if brain != null:
		brain.on_damaged()
	if hp <= 0.0:
		die()


func stun(seconds: float) -> void:
	if dead or shield_left > 0.0 or purge_left > 0.0:
		return
	seconds *= (1.0 - stats.get("resist_stun", 0.0)) * control_k()
	if seconds > stun_left:
		_stun_total = seconds
	stun_left = maxf(stun_left, seconds)
	if seconds > 0.0 and blink_left > 0.0:
		_cancel_blink()     # оглушение сбивает подготовку блинка


func die() -> void:
	if dead:
		return
	dead = true
	hp = 0.0
	visible = false
	_cancel_tp()
	Battle.on_kill(last_attacker, self)
	_col.set_deferred("disabled", true)
	hitbox.set_active(false)
	_salvo_left = 0
	_beam_on = [false, false]
	_reset_ability_states()
	slow_left = 0.0
	death_velocity = Vector3(velocity.x, 0, velocity.z)
	velocity = Vector3.ZERO
	Fx.mech_death(global_position, get_hit_radius())
	Sfx.play_at("boom", global_position, 2.0, 0.08)
	died.emit(self)


# отдать модель обломку (main.gd) и собрать себе новую к возрождению
func detach_visual() -> Node3D:
	var v := visual
	for i in 2:
		v.set_beam(i, false)
	v.set_fade(0.0)       # обломок невидимки видно всем
	v.visible = true
	_fade = 0.0
	visual = null
	_look = {}
	_apply_build()
	return v


# drop: прилететь с неба (как ступень ракеты), иначе просто встать на место
func respawn(pos: Vector3, drop := true) -> void:
	global_position = pos
	_snap_next = true
	velocity = Vector3.ZERO
	hp = max_hp()
	energy = energy_max()
	refill_all()
	no_regen_left = 0.0
	slow_left = 0.0
	run_locked = false
	stun_left = 0.0
	dash_left = 0.0
	dash_cd = 0.0
	dash_stock = stats.get("dash_charges", 1.0)
	_since_damage = 99.0
	last_attacker = null
	_cancel_tp()
	tp_cd = 0.0
	_w_spin = [0.0, 0.0]
	_w_charge = [0.0, 0.0]
	for i in ability_cd.size():
		ability_cd[i] = 0.0
	_reset_ability_states()
	_w_spread = [0.0, 0.0]
	_w_bloom = [0.0, 0.0]
	_w_timer = [0.0, 0.0]
	_beam_on = [false, false]
	_dash_pressed = false
	for i in _ability_pressed.size():
		_ability_pressed[i] = false
	dead = false
	visible = true
	shield_left = Cfg.spawn_shield
	_col.set_deferred("disabled", false)
	hitbox.set_active(true)
	visual.reset()
	if brain != null:
		brain.reset()
	_set_ghost(true)
	if drop:
		start_landing()


# ------------------------------------------------------------------
#  ВЫСАДКА С НЕБА: мех падает быстро, у земли включает тормозные двигатели и мягко садится
# ------------------------------------------------------------------

func start_landing(time := -1.0) -> void:
	if time < 0.0 and Cfg.drop_time <= 0.05:
		return
	_landing_total = Cfg.drop_time if time < 0.0 else maxf(time, 0.1)
	landing_left = _landing_total
	velocity = Vector3.ZERO
	_col.set_deferred("disabled", true)
	hitbox.set_active(false)
	if _landing_marker != null and is_instance_valid(_landing_marker):
		_landing_marker.queue_free()
	var col := Color(0.45, 0.8, 1.0) if team == 0 else Color(1.0, 0.3, 0.25)
	_landing_marker = Fx.ground_marker(global_position, get_hit_radius() + 0.6, col, team, _landing_total + 0.2, false, true)
	_update_landing(0.0)


func _update_landing(delta: float) -> void:
	landing_left = maxf(landing_left - delta, 0.0)
	var u := 1.0 - landing_left / maxf(_landing_total, 0.01)
	# высота: кубическая кривая, быстро падает и плавно подходит к земле
	# после прыжка падает с разгоном и бьёт о землю, при высадке плавно тормозит двигателями
	var h := Cfg.drop_height * ((1.0 - u * u) if _jump_land else pow(1.0 - u, 3.0))
	visual.visible = seen
	visual.airborne = true
	visual.update_visual(delta, global_position + Vector3.UP * h, Vector3.ZERO, legs_yaw, torso_yaw, true)
	if _snap_next:
		_snap_next = false
		snap_interpolation(self)
	# тормозные двигатели работают на последних двух третях спуска
	visual.set_jets(clampf((u - 0.3) / 0.2, 0.0, 1.0) * (1.0 - clampf((u - 0.97) / 0.03, 0.0, 1.0)) if seen and not _jump_land else 0.0)
	if landing_left <= 0.0:
		_finish_landing()


func _finish_landing() -> void:
	landing_left = 0.0
	visual.airborne = false
	visual.set_jets(0.0)
	visual.reset()
	_col.set_deferred("disabled", false)
	hitbox.set_active(true)
	_set_ghost(true)
	if _jump_land:
		_jump_land = false
		_jump_slam()
	else:
		shield_left = Cfg.spawn_shield
	if _landing_marker != null and is_instance_valid(_landing_marker):
		_landing_marker.queue_free()
	_landing_marker = null
	if seen:
		Fx.dust_ring(global_position, get_hit_radius() * 3.0)
	Sfx.play_at("land", global_position, -4.0, 0.06)
	landed.emit()


# ------------------------------------------------------------------
#  ПОЯВЛЕНИЕ В ДРУГОМ МЕХЕ: после высадки, возрождения или телепорта мех мог оказаться внутри
#  другого меха или обломка (пока летел, туда зашли). Физика выталкивает такие тела друг из друга,
#  при совпадении — вверх, и оба улетали в небо. Поэтому только что появившийся мех проходит сквозь
#  мехов и обломки и мягко отходит в сторону, а как разошлись — столкновения возвращаются
# ------------------------------------------------------------------

func _set_ghost(on: bool) -> void:
	_ghost = on
	_ghost_push = Vector3.ZERO
	collision_layer = 0 if on else 2
	collision_mask = (1 | 32) if on else (1 | 2 | 16 | 32)


func _update_ghost() -> void:
	var me := Vector3(global_position.x, 0, global_position.z)
	var push := Vector3.ZERO
	var inside := false
	var others: Array = []
	for m in get_tree().get_nodes_in_group("mechs"):
		if m != self and not m.dead and not m.is_landing():
			others.append([m, 2.5])            # две капсулы ходьбы по 1,25
	for w in get_tree().get_nodes_in_group("wrecks"):
		others.append([w, 1.25 + float(w.get("radius") if w.get("radius") != null else 1.8)])
	for o in others:
		var d := me - Vector3(o[0].global_position.x, 0, o[0].global_position.z)
		var gap: float = o[1] + 0.15
		if d.length() >= gap:
			continue
		inside = true
		if d.length() < 0.05:            # ровно в нём: отходим в свою сторону, у каждого меха своя
			d = Vector3.RIGHT.rotated(Vector3.UP, float(get_instance_id() % 628) * 0.01)
		push += d.normalized() * (gap - d.length())
	if not inside:
		_set_ghost(false)
		return
	_ghost_push = push.limit_length(1.0) * 6.0


# ------------------------------------------------------------------
#  ТЕЛЕПОРТ НА БАЗУ (клавиша T): постоять на месте несколько секунд, движение или выстрел отменяют
# ------------------------------------------------------------------

func _update_tp(delta: float) -> void:
	if _tp_pressed:
		_tp_pressed = false
		if tp_left > 0.0:
			_cancel_tp()
		elif can_tp() and not is_stunned():
			tp_left = Cfg.tp_channel
			_tp_fx = Fx.tp_column(self, team)
			Sfx.play_at("tp", global_position, -6.0, 0.0)
		else:
			ability_denied.emit(-5, "cooldown")
	if tp_left <= 0.0:
		return
	if _move.length() > 0.1 or _fire or _fire2 or _dash_pressed or is_stunned() or _ability_pressed.has(true):
		_cancel_tp()
		return
	tp_left -= delta
	if tp_left <= 0.0:
		var g = get_tree().current_scene
		var dest: Vector3 = g.spawn_point(team) if g != null and g.has_method("spawn_point") else global_position
		if seen:
			Fx.burst(global_position + Vector3.UP * 2.0, Color(0.5, 0.85, 1.0), 4.0)
		global_position = dest
		velocity = Vector3.ZERO
		visual.reset()
		_snap_next = true
		_set_ghost(true)
		Fx.burst(global_position + Vector3.UP * 2.0, Color(0.5, 0.85, 1.0), 4.0)
		Sfx.play_at("dash", global_position, -2.0, 0.05)
		_cancel_tp()
		tp_cd = Cfg.tp_cooldown
		teleported.emit()


func _cancel_tp() -> void:
	tp_left = 0.0
	if _tp_fx != null and is_instance_valid(_tp_fx):
		_tp_fx.queue_free()
	_tp_fx = null


# ------------------------------------------------------------------
#  ЭНЕРГИЯ
# ------------------------------------------------------------------

func spend_energy(amount: float) -> bool:
	if amount <= 0.0:
		return true
	if energy < amount:
		return false
	energy -= amount
	return true


# восстановление идёт всегда, даже пока тратишь: бег 10/с при восстановлении 4/с = минус 6/с.
# Остановить его может только чужая способность (импульс).
func _update_energy(delta: float) -> void:
	var regen: float = stats["energy_regen"] * _game_mult("regen")
	if no_regen_left > 0.0:
		no_regen_left -= delta
		regen = 0.0
	energy = minf(energy + regen * delta, energy_max())
	if barrier_on:
		energy -= ability_param(_barrier_i, "upkeep") * delta
		if energy <= 0.0:
			energy = 0.0
			_set_barrier(false)
	if running:
		energy -= Cfg.run_energy_cost * delta
		if energy <= 0.0:
			energy = 0.0
			run_locked = true
	if run_locked and energy >= minf(Cfg.run_min_energy, energy_max()):
		run_locked = false


# во сколько раз контроль (оглушение, ЭМИ, притяжение, толчок) сильнее обычного: базовая масса / масса меха
# (F2 → «Контроль»). Мех вдвое тяжелее базового — вдвое слабее
func control_k() -> float:
	return clampf(Cfg.control_mass / maxf(stats.get("weight", Cfg.control_mass), 1.0), 0.2, 4.0)


# связка: ноги не ходят (нет ходьбы, рывка, блинка, прыжка), корпус крутится, пушки стреляют
func root(seconds: float) -> void:
	if dead or shield_left > 0.0 or purge_left > 0.0 or is_landing():
		return
	if seconds > root_left:
		_root_total = seconds
	root_left = maxf(root_left, seconds)
	if blink_left > 0.0:
		_cancel_blink()


# глушащий дротик: пушки не стреляют, остальное можно
func disarm(seconds: float) -> void:
	if dead or shield_left > 0.0 or purge_left > 0.0 or is_landing():
		return
	if seconds > disarm_left:
		_disarm_total = seconds
	disarm_left = maxf(disarm_left, seconds)


# ЭМИ-снаряд сжигает энергию (тяжёлому меньше)
func drain_energy(amount: float) -> void:
	if dead or shield_left > 0.0 or purge_left > 0.0 or is_landing():
		return
	energy = maxf(energy - amount * control_k(), 0.0)


# гравитационный якорь тянет: скорость на этот тик (тяжёлого тянет слабее)
func pull(v: Vector3) -> void:
	if dead or is_landing() or shield_left > 0.0 or purge_left > 0.0:
		return
	_pull += v * control_k()


# ударная волна: отлетает на dist (мех базовой массы; тяжелее — ближе) с постоянной скоростью
func shove(dir: Vector3, dist: float) -> void:
	if dead or is_landing() or shield_left > 0.0 or purge_left > 0.0:
		return
	dir.y = 0.0
	_shove_v = dir.normalized() * SHOVE_SPEED
	_shove_t = dist * control_k() / SHOVE_SPEED


# подожгли (пули Поджигателя): горит, теряет здоровье; повторное попадание продлевает
func ignite(dps: float, seconds: float, src: Node) -> void:
	if dead or purge_left > 0.0:
		return
	if burn_left <= 0.0 and seen:
		Fx.smolder(visual, Vector3.UP * get_hit_height() * 0.5, get_hit_radius() * 0.5, seconds)
	burn_left = maxf(burn_left, seconds)
	_burn_dps = dps
	_burn_src = src


# дротик-целеуказатель: все попадания по мне сильнее на k
func mark(seconds: float, k: float) -> void:
	if dead:
		return
	marked_left = maxf(marked_left, seconds)
	_mark_k = maxf(_mark_k if marked_left > seconds else 0.0, k)


# во сколько раз чаще стреляют пушки (форсированная подача)
func fire_mult() -> float:
	return 1.0 + _rapid_k if rapid_left > 0.0 else 1.0


# обзор и омни (перископ увеличивает); vision.gd берёт отсюда
func vision_r() -> float:
	var k := 1.0 + _peri_k if periscope_left > 0.0 else 1.0
	if scope_on:
		k *= 1.0 + ability_param(_scope_i, "boost") * 0.5
	return stats.get("vision", 35.0) * k


func omni_r() -> float:
	return stats.get("omni", 0.0) + (_peri_omni if periscope_left > 0.0 else 0.0)


func block_regen(seconds: float) -> void:
	if dead or shield_left > 0.0 or purge_left > 0.0:
		return
	seconds *= control_k()
	if seconds > no_regen_left:
		_no_regen_total = seconds
	no_regen_left = maxf(no_regen_left, seconds)


# ------------------------------------------------------------------
#  ДВИЖЕНИЕ
# ------------------------------------------------------------------

func _update_move(delta: float) -> void:
	var wish := Vector3(_move.x, 0, _move.y)
	var has_wish := wish.length() > 0.01
	# бежать можно, только если есть энергия (или бег бесплатный)
	var can_run := not run_locked or Cfg.run_energy_cost <= 0.0
	running = _run and has_wish and can_run and dash_left <= 0.0
	var max_speed := run_speed() if running else walk_speed()

	# рывки копятся: один заряд за перезарядку (у большинства мехов заряд один)
	var charges_max: float = maxf(stats.get("dash_charges", 1.0), 1.0)
	if dash_stock < charges_max:
		dash_cd = maxf(dash_cd - delta, 0.0)
		if dash_cd <= 0.0:
			dash_stock += 1.0
			if dash_stock < charges_max:
				dash_cd = stats["dash_cooldown"]
	else:
		dash_cd = 0.0
	if _dash_pressed:
		_dash_pressed = false
		if dash_stock >= 1.0 and dash_left <= 0.0:
			if spend_energy(Cfg.dash_energy_cost):
				dash_dir = wish.normalized() if has_wish else torso_forward()
				# двигатели работают дольше на половину разгона: дальность рывка та же, что без разгона
				dash_left = stats["dash_time"] + stats.get("dash_ramp", 0.0) * 0.5
				if dash_stock >= charges_max:
					dash_cd = stats["dash_cooldown"]
				dash_stock -= 1.0
				_rammed.clear()
				dashed.emit()
			else:
				ability_denied.emit(-1, "energy")
		else:
			ability_denied.emit(-1, "cooldown")

	var hv := Vector3(velocity.x, 0, velocity.z)
	if dash_left > 0.0:
		dash_left -= delta
		# рывок — мощный, но не мгновенный разгон: двигатели доводят скорость до рывковой за «Разгон рывка»
		# (тяжёлый разгоняется дольше), заодно гасят скорость вбок
		var top: Vector3 = dash_dir * stats["dash_speed"]
		var ramp: float = stats.get("dash_ramp", 0.0)
		hv = top if ramp <= 0.001 else hv.move_toward(top, stats["dash_speed"] / ramp * delta)
		if stats.get("ram_damage", 0.0) > 0.0:
			_ram()
	else:
		var target := wish * max_speed
		var rate: float = stats["accel"]
		if hv.length() > run_speed() + 0.5:
			rate = stats["dash_brake"]      # гасим скорость после рывка
		elif not has_wish or hv.length() > max_speed + 0.2:
			rate = stats["decel"]
		hv = hv.move_toward(target, rate * delta)

	var vy := velocity.y
	if is_on_floor():
		vy = -1.0
	else:
		vy -= 30.0 * delta
	var extra := _ghost_push + _pull + (_shove_v if _shove_t > 0.0 else Vector3.ZERO)
	_pull = Vector3.ZERO
	_shove_t = maxf(_shove_t - delta, 0.0)
	velocity = Vector3(hv.x + extra.x, vy, hv.z + extra.z)
	_push_wrecks(wish * max_speed if dash_left <= 0.0 else hv, delta)
	move_and_slide()
	# отход в сторону и притяжение не копятся в скорости. Если упёрлись (притянуло к стене), своя скорость
	# только скользит вдоль преграды — иначе вычитание давало скорость от стены, и мех застывал
	var after := velocity - extra
	if extra.length() > 0.01 and get_slide_collision_count() > 0:
		after = hv
		for k in get_slide_collision_count():
			var nrm := get_slide_collision(k).get_normal()
			nrm.y = 0.0
			if nrm.length() > 0.1 and after.dot(nrm) < 0.0:
				after = after.slide(nrm.normalized())
		after.y = velocity.y
	velocity = after

	# упор: стоит на месте достаточно долго
	var real := Vector3(velocity.x, 0, velocity.z)
	if real.length() < 0.6 and dash_left <= 0.0:
		_still_t += delta
	else:
		_still_t = 0.0
	braced = stats.get("brace_bonus", 0.0) > 0.0 and _still_t >= stats.get("brace_time", 0.6)

	# ноги разворачиваются туда, куда идём
	if real.length() > 0.8:
		var want_yaw := atan2(-real.x, -real.z)
		legs_yaw = rotate_toward(legs_yaw, want_yaw, deg_to_rad(stats["legs_turn_speed"]) * delta)


# таран (рывком врезался во врага): урон, оглушение, отбрасывание. Каждого один раз за рывок
func _ram() -> void:
	var r := get_hit_radius() + 0.6
	for n in get_tree().get_nodes_in_group("damageable"):
		if not (n is Node3D) or n == self or n.get("team") == team or n.get("team") == null or int(n.get("team")) < 0:
			continue
		if not (n.is_in_group("mechs") or n.is_in_group("creeps")):
			continue
		if n.get("dead") or _rammed.has(n.get_instance_id()):
			continue
		var d: Vector3 = n.global_position - global_position
		d.y = 0
		var size: float = n.get_hit_radius() if n.has_method("get_hit_radius") else 1.0
		if d.length() > r + size or d.normalized().dot(dash_dir) < 0.2:
			continue
		_rammed[n.get_instance_id()] = true
		n.take_damage(stats["ram_damage"] * damage_mult(), n.global_position + Vector3.UP * 2.0, dash_dir, "", self)
		if n.has_method("stun"):
			n.stun(stats.get("ram_stun", 0.0))
		if n.has_method("knock"):
			n.knock(dash_dir * 16.0)
		Fx.spark(global_position + dash_dir * r + Vector3.UP * 2.0, -dash_dir, true)
		Fx.shake_at.emit(global_position, Cfg.shake_explosion * 0.6)
		Sfx.play_at("cannon", global_position, -2.0, 0.1)


# толчок со стороны (таран, ударная волна): скорость, которая гаснет сама. Тяжёлого толкает слабее
func knock(v: Vector3) -> void:
	if dead or is_landing() or shield_left > 0.0 or purge_left > 0.0:
		return
	v *= control_k()
	velocity.x += v.x
	velocity.z += v.z


# упираемся в обломок: сначала двигаем его, потом идём сами.
# Чем тяжелее мех относительно обломка, тем быстрее тот едет (тяжёлый толкает почти на полной скорости)
func _push_wrecks(want: Vector3, delta: float) -> void:
	want.y = 0
	var spd := want.length()
	if spd < 0.3:
		return
	# обломков рядом нет — вторая проверка движения за тик не нужна (она дорогая)
	var near := false
	for w in get_tree().get_nodes_in_group("wrecks"):
		if w.global_position.distance_to(global_position) < get_hit_radius() + 8.0 + spd * delta * 1.5:
			near = true
			break
	if not near:
		return
	var motion := want * delta * 1.5
	var col := KinematicCollision3D.new()
	if not test_move(global_transform, motion, col):
		return
	for i in col.get_collision_count():
		var w = col.get_collider(i)
		if w == null or not w.is_in_group("wrecks"):
			continue
		var dir: Vector3 = w.global_position - global_position
		dir.y = 0
		if dir.length() < 0.01 or dir.normalized().dot(want.normalized()) < 0.2:
			continue
		var k := clampf(stats.get("weight", 60.0) / maxf(w.weight, 1.0), 0.1, 1.0) * Cfg.wreck_push
		var want_move := spd * minf(k, 1.0) * delta
		var moved: float = w.shove(dir.normalized() * want_move)
		# обломок упёрся (в стену, постройку): не стоим, а обходим его боком
		if moved < want_move * 0.3:
			continue
		# мех не останавливается об обломок, а идёт с той скоростью, с какой едет обломок
		var keep := minf(k, 1.0)
		velocity.x = want.x * keep
		velocity.z = want.z * keep


func _update_aim(delta: float) -> void:
	var d := aim_point - global_position
	d.y = 0
	if d.length() > 0.8:
		var want_yaw := atan2(-d.x, -d.z)
		torso_yaw = rotate_toward(torso_yaw, want_yaw, deg_to_rad(stats["torso_turn_speed"]) * delta)


# 0 = стоит, 1 = идёт, 2 = бежит, 3 = рывок (плавно между ними)
func _move_level() -> float:
	if is_dashing():
		return 3.0
	var speed := Vector2(velocity.x, velocity.z).length()
	var walk := maxf(walk_speed(), 0.1)
	if speed <= walk:
		return speed / walk
	return 1.0 + clampf((speed - walk) / maxf(run_speed() - walk, 0.1), 0.0, 1.0)


func _update_spread(delta: float) -> void:
	var lvl := _move_level()
	var brace_k := 1.0 - clampf(stats.get("brace_bonus", 0.0) * 2.0, 0.0, 0.7) if braced else 1.0
	for i in weapons.size():
		var w: Dictionary = weapons[i]
		var target: float
		if lvl <= 1.0:
			target = lerpf(w["spread_stand"], w["spread_walk"], lvl)
		elif lvl <= 2.0:
			target = lerpf(w["spread_walk"], w["spread_run"], lvl - 1.0)
		else:
			target = w["spread_dash"]
		target *= brace_k
		var rate: float = w["spread_grow"] if target > _w_spread[i] else w["spread_shrink"]
		_w_spread[i] = move_toward(_w_spread[i], target, rate * delta)
		_w_bloom[i] = move_toward(_w_bloom[i], 0.0, w["spread_shrink"] * 0.5 * delta)


# ------------------------------------------------------------------
#  ОРУЖИЕ (оба подвеса стреляют на ЛКМ)
# ------------------------------------------------------------------

func _update_fire(delta: float) -> void:
	if siege_on:
		_update_siege(delta)      # в осадном режиме пушки молчат, кнопки стрельбы бьют мортирой
		return
	# две одинаковые пушки (настройка «Одинаковые пушки на ЛКМ»): обе стреляют на любую кнопку мыши
	var linked: bool = Cfg.link_guns > 0 and weapons.size() == 2 and weapons[0]["id"] == weapons[1]["id"]
	for i in weapons.size():
		var w: Dictionary = weapons[i]
		var pressed := (_fire or _fire2) if linked else (_fire if i == 0 else _fire2)
		var start: bool = pressed and not _fire_prev[i]
		_fire_prev[i] = pressed
		if start:
			_energy_warned[i] = false
		match w["type"]:
			"beam":
				_update_beam(i, w, delta, pressed)
				continue
			"rail":
				_update_rail(i, w, delta, pressed, start)
				continue
		# Гатлинг раскручивается, пока держишь кнопку, и медленнее замедляется
		var rate: float = w["fire_rate"] * fire_mult()
		if w["spin_up"] > 0.0:
			var spin_to := 1.0 if pressed else 0.0
			var spd: float = 1.0 / maxf(w["spin_up"], 0.05)
			_w_spin[i] = move_toward(_w_spin[i], spin_to, delta * (spd if pressed else spd * 0.7))
			rate *= lerpf(0.2, 1.0, _w_spin[i])
			visual.spin(i, _w_spin[i], delta)
		_w_timer[i] -= delta
		# одинаковые пушки стреляют по очереди (левая, правая), а не залпом; рельсы — залпом (выше, свой расчёт)
		if start and i == 1 and (linked or _fire) and weapons[0]["id"] == w["id"]:
			_w_timer[1] = maxf(_w_timer[1], 0.5 / maxf(rate, 0.1))
		if not pressed or _w_timer[i] > 0.0:
			continue
		if not _can_shoot(i, w, start):
			continue
		_w_timer[i] = 1.0 / maxf(rate, 0.1)
		_pay_shot(i, w)
		if w["type"] == "lob":
			_fire_lob(i, w)
		else:
			_fire_bullet(i, w)


# хватает ли патронов и энергии на выстрел; если нет, щелчок один раз на нажатие
func _can_shoot(i: int, w: Dictionary, start: bool) -> bool:
	if ammo_max(i) > 0.0 and ammo[i] < 1.0:
		if start or not _ammo_warned[i]:
			_ammo_warned[i] = true
			ability_denied.emit(-2 - i, "ammo")
		return false
	_ammo_warned[i] = false
	if w["energy_per_shot"] > 0.0 and energy < w["energy_per_shot"]:
		if not _energy_warned[i]:
			_energy_warned[i] = true
			ability_denied.emit(-2 - i, "energy")
		return false
	return true


func _pay_shot(i: int, w: Dictionary) -> void:
	if ammo_max(i) > 0.0:
		ammo[i] -= 1.0
	if w["energy_per_shot"] > 0.0:
		energy = maxf(energy - w["energy_per_shot"], 0.0)


# Стволы смотрят туда, куда смотрит корпус, на дальность прицела и на его высоту (земля или
# середина хитбокса врага). Доворачиваются в стороны и вверх-вниз только в пределах, сводятся
# не ближе GUN_MIN_DIST: в упор между стволами не стреляем, пули не вылетают поперёк
const GUN_YAW_MAX := 12.0        # градусов в сторону от корпуса
const GUN_PITCH_MIN := -30.0     # градусов вниз
const GUN_PITCH_MAX := 20.0      # градусов вверх
const GUN_MIN_DIST := 8.0        # ближе этого стволы не сводятся


# точка, в которую сводятся стволы (у гранатомёта — на земле под курсором)
func gun_target(lob := false) -> Vector3:
	var p := aim_ground if lob else aim_point
	var flat := Vector3(p.x - global_position.x, 0, p.z - global_position.z)
	var t := global_position + torso_forward() * maxf(flat.length(), GUN_MIN_DIST)
	t.y = p.y
	return t


# дальность до точки на земле под курсором (куда полетит граната)
func aim_ground_distance() -> float:
	return Vector2(aim_ground.x - global_position.x, aim_ground.z - global_position.z).length()


# поворот ствола от корпуса: x — в сторону, y — вверх-вниз (радианы, в пределах)
func _gun_angles(origin: Vector3, target: Vector3) -> Vector2:
	var fwd := torso_forward()
	var v := target - origin
	var flat := Vector3(v.x, 0, v.z)
	var yaw := 0.0
	if flat.length() > 0.01:
		yaw = clampf(fwd.signed_angle_to(flat.normalized(), Vector3.UP), -deg_to_rad(GUN_YAW_MAX), deg_to_rad(GUN_YAW_MAX))
	var pitch := clampf(atan2(v.y, maxf(flat.length(), 0.01)), deg_to_rad(GUN_PITCH_MIN), deg_to_rad(GUN_PITCH_MAX))
	return Vector2(yaw, pitch)


func _dir_from(a: Vector2) -> Vector3:
	var flat := torso_forward().rotated(Vector3.UP, a.x)
	return (flat * cos(a.y) + Vector3.UP * sin(a.y)).normalized()


# направление выстрела из ствола (с разбросом влево-вправо)
func _gun_dir(origin: Vector3, spread_deg: float, random := true) -> Vector3:
	var dir := _dir_from(_gun_angles(origin, gun_target()))
	if random:
		var s := deg_to_rad(spread_deg)
		dir = dir.rotated(Vector3.UP, (randf() + randf() - 1.0) * s)
	return dir


# модель: стволы поворачиваются туда же, куда полетят пули
func _aim_guns() -> void:
	var t := gun_target()
	var tl := gun_target(true)
	for i in mini(visual.gun_pods.size(), weapons.size()):
		var a := _gun_angles(visual.gun_pods[i].global_position, t)
		if weapons[i]["type"] == "lob":
			a = _gun_angles(visual.gun_pods[i].global_position, tl)
			a.y = _lob_pitch(visual.gun_pods[i].global_position, tl, weapons[i])
		visual.gun_yaw[i] = a.x
		visual.gun_pitch[i] = a.y


# если ствол упёрся в стену, выстрел не должен пройти сквозь неё
func _muzzle_blocked(origin: Vector3) -> Dictionary:
	var chest := Vector3(global_position.x, origin.y, global_position.z)
	var q := PhysicsRayQueryParameters3D.create(chest, origin, 1)
	return get_world_3d().direct_space_state.intersect_ray(q)


func _fire_bullet(i: int, w: Dictionary) -> void:
	var origin: Vector3 = visual.get_muzzle(i)
	var blocked := _muzzle_blocked(origin)
	if not blocked.is_empty():
		Fx.spark(blocked["position"], blocked["normal"], false)
	else:
		# дробовик: несколько дробин веером; у остального одна пуля
		var n := int(w["pellets"])
		for k in n:
			var spread: float = weapon_spread_deg(i)
			if n > 1:
				spread += w["pellet_spread"]
			var dir := _gun_dir(origin, spread)
			var p := Projectile.new()
			p.setup(origin, dir * w["bullet_speed"], w["damage"] * damage_mult(), w_range(i), self)
			p.tracer = w["tracer"]
			p.falloff = w["falloff"] if w["falloff"] > 0.0 else 1.0
			p.style = "plasma" if w["look"] == "blaster" else "tracer"
			get_tree().current_scene.add_child(p)
		_eject_casing(i, w, origin)
	_after_shot(i, w)


# гильза из автопушки, Гатлинга и тяжёлого орудия: вылетает наружу от корпуса
func _eject_casing(i: int, w: Dictionary, origin: Vector3) -> void:
	var look: String = w["look"]
	if not seen or Cfg.casings <= 0 or not (look in ["twin", "minigun", "heavy"]):
		return
	var b := Basis(Vector3.UP, torso_yaw)
	var right := b.x
	var side := right if right.dot(origin - global_position) >= 0.0 else -right
	var port := origin + b.z * 1.0          # окно выброса чуть позади дула
	# у Гатлинга звенит не каждая, иначе сплошной звон
	Fx.casing(port, side, look == "heavy", look != "minigun" or randf() < 0.3)


func _after_shot(i: int, w: Dictionary) -> void:
	_break_cloak()
	visual.kick(i, w["recoil"])
	_shot_light(i, w)
	_w_bloom[i] = minf(_w_bloom[i] + w["spread_per_shot"], w["spread_shot_max"])
	fired.emit(i)


# вспышка выстрела подсвечивает землю и мехов вокруг. Только если меха видно: иначе свет выдаст его в тумане
func _shot_light(i: int, w: Dictionary) -> void:
	if not seen and team != Fx.player_team:
		return
	var friend := team == Fx.player_team
	match String(w["look"]):
		"laser", "rail":
			return      # у лазера свет держится, пока он горит; у рельсы своя вспышка
		"blaster":
			Fx.light_flash(visual.get_muzzle(i), Color(0.5, 0.9, 1.0) if friend else Color(1.0, 0.4, 0.85), 8.0, 3.0, 0.08)
		"heavy", "grenade", "shotgun":
			Fx.light_flash(visual.get_muzzle(i), Color(1.0, 0.68, 0.32), 10.0, 4.0, 0.1)
		_:
			Fx.light_flash(visual.get_muzzle(i), Color(1.0, 0.72, 0.38), 7.0, 2.5, 0.07)


# гранатомёт: граната вылетает с постоянной скоростью, ствол сам поднимается или опускается под
# точку прицела (под ноги — вниз, вдаль — чуть вверх), летит по настоящей баллистике и рвётся о то,
# во что врежется: стену, меха, крипа, обломок или землю. Низкую стену может перелететь
func _fire_lob(i: int, w: Dictionary) -> void:
	var origin: Vector3 = visual.get_muzzle(i)
	var t := gun_target(true)
	var flat := Vector3(t.x - global_position.x, 0, t.z - global_position.z)
	if flat.length() > w_range(i):
		t = Vector3(global_position.x, t.y, global_position.z) + flat.normalized() * w_range(i)
	var a := _gun_angles(origin, t)
	a.y = _lob_pitch(origin, t, w)
	var dir := _dir_from(a)
	var s := deg_to_rad(weapon_spread_deg(i))
	dir = dir.rotated(Vector3.UP, (randf() + randf() - 1.0) * s)
	var lob := Lob.new()
	lob.setup_ballistic(origin, dir * w["launch_speed"], self, {
		"kind": "explosive", "damage": w["damage"] * damage_mult(), "radius": w["radius"], "edge_damage": w["edge_damage"]})
	get_tree().current_scene.add_child(lob)
	_after_shot(i, w)


# угол ствола гранатомёта, чтобы граната с его скоростью вылета упала в точку (низкая траектория).
# Не долетает — максимальный угол
func _lob_pitch(origin: Vector3, t: Vector3, w: Dictionary) -> float:
	var v: float = maxf(w["launch_speed"], 1.0)
	var g: float = Cfg.gravity()
	var x := Vector2(t.x - origin.x, t.z - origin.z).length()
	var y := t.y - origin.y
	var disc := v * v * v * v - g * (g * x * x + 2.0 * y * v * v)
	var ang := deg_to_rad(GUN_PITCH_MAX)
	if disc >= 0.0 and x > 0.01:
		ang = atan((v * v - sqrt(disc)) / (g * x))
	return clampf(ang, deg_to_rad(GUN_PITCH_MIN), deg_to_rad(GUN_PITCH_MAX))


# рельсотрон: держишь кнопку, он заряжается и сам стреляет, когда заряд полный.
# Отпустил раньше: заряд быстро спадает. Луч прошивает мехов и крипов насквозь, стены держат
func _update_rail(i: int, w: Dictionary, delta: float, pressed: bool, start: bool) -> void:
	_w_timer[i] -= delta
	var ct: float = maxf(w["charge_time"], 0.05)
	if pressed and _w_timer[i] <= 0.0 and _can_shoot(i, w, start):
		_w_charge[i] = minf(_w_charge[i] + delta / ct, 1.0)
		if _w_charge[i] >= 1.0:
			_w_charge[i] = 0.0
			_w_timer[i] = 1.0 / maxf(w["fire_rate"] * fire_mult(), 0.05)
			_pay_shot(i, w)
			_fire_rail(i, w)
	else:
		_w_charge[i] = move_toward(_w_charge[i], 0.0, delta * 2.0 / ct)
	visual.set_charge(i, _w_charge[i])


# ник над полоской здоровья (Battle.register)
func set_title(t: String) -> void:
	if _bar != null:
		_bar.set_title(t)


func rail_charge(i: int) -> float:
	return _w_charge[i]


func _fire_rail(i: int, w: Dictionary) -> void:
	var origin: Vector3 = visual.get_muzzle(i)
	var dir := _gun_dir(origin, weapon_spread_deg(i))
	var end := origin + dir * w_range(i)
	var blocked := _muzzle_blocked(origin)
	if not blocked.is_empty():
		end = blocked["position"]
	else:
		var space := get_world_3d().direct_space_state
		var ex: Array[RID] = Fx.team_rids(team)
		var from := origin
		var dmg: float = w["damage"] * damage_mult() * (1.0 + ability_param(_scope_i, "boost") if scope_on else 1.0)
		for step in 10:
			var q := PhysicsRayQueryParameters3D.create(from, end, 1 | 4 | 16 | 128)
			q.collide_with_areas = true
			q.exclude = ex
			var hit := space.intersect_ray(q)
			if hit.is_empty():
				break
			var col = hit["collider"]
			if col is Area3D and col.has_meta("prop"):      # мелочь: ломает и летит дальше
				col.get_meta("prop").bullet_hit(dir, self)
				ex.append(hit["rid"])
				continue
			if col != null and col.has_method("take_damage"):
				col.take_damage(dmg, hit["position"], dir, "", self)
			Fx.impact(hit["position"], hit["normal"], "armor" if col is Area3D else ("ground" if hit["normal"].y > 0.6 else "concrete"), dmg)
			# насквозь только через мехов и крипов (хитбоксы); стена или обломок останавливают
			if col is Area3D and w["pierce"] > 0.5:
				ex.append(hit["rid"])
				from = hit["position"]
				continue
			end = hit["position"]
			break
	Fx.rail_beam(origin, end, team)
	_after_shot(i, w)


# лазер: пока зажата ЛКМ и есть энергия, луч бьёт мгновенно и ест энергию
func _update_beam(i: int, w: Dictionary, delta: float, pressed: bool) -> void:
	var on := pressed and energy > 0.5
	_beam_on[i] = on
	if not on:
		visual.set_beam(i, false)
		return
	energy = maxf(energy - w["energy_per_sec"] * delta, 0.0)
	_break_cloak()

	var origin: Vector3 = visual.get_muzzle(i)
	# луч слегка гуляет: на ходу сильнее
	var wobble := deg_to_rad(weapon_spread_deg(i)) * sin(Time.get_ticks_msec() * 0.007 + i * 1.7)
	var dir := _gun_dir(origin, 0.0, false).rotated(Vector3.UP, wobble)
	var end: Vector3 = origin + dir * w_range(i)
	var normal: Vector3 = -dir
	var target = null

	var blocked := _muzzle_blocked(origin)
	if not blocked.is_empty():
		end = blocked["position"]
		normal = blocked["normal"]
	else:
		_beam_ex_t -= delta
		if _beam_ex_t <= 0.0:
			_beam_ex_t = 0.5
			_beam_exclude = Fx.team_rids(team)
		var q := PhysicsRayQueryParameters3D.create(origin, end, 1 | 4 | 16 | 128)
		q.collide_with_areas = true
		var ex_l: Array[RID] = _beam_exclude.duplicate()
		q.exclude = ex_l
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		for _guard in 4:      # мелочь луч режет и идёт дальше
			if hit.is_empty() or not (hit["collider"] is Area3D and hit["collider"].has_meta("prop")):
				break
			hit["collider"].get_meta("prop").bullet_hit(dir, self)
			ex_l.append(hit["rid"])
			q.exclude = ex_l
			hit = get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty():
			end = hit["position"]
			normal = hit["normal"]
			var col = hit["collider"]
			if col != null and col.has_method("take_damage"):
				target = col
				col.take_damage(w["dps"] * damage_mult() * delta, end, dir, "beam", self)

	visual.set_beam(i, true, origin, end)
	# лазер светит на землю вдоль луча и ярче в месте попадания, пока горит
	if seen or team == Fx.player_team:
		var lc := Color(0.45, 0.85, 1.0) if team == Fx.player_team else Color(1.0, 0.35, 0.35)
		var lkey := "lz%d_%d" % [get_instance_id(), i]
		Fx.light_flash(origin.lerp(end, 0.5), lc, origin.distance_to(end) * 0.5 + 4.0, 1.5, 0.12, lkey + "m", true)
		Fx.light_flash(end, lc, 6.0, 3.0, 0.12, lkey + "e", true)
	_beam_fx_t[i] -= delta
	if _beam_fx_t[i] <= 0.0 and end.distance_to(origin) < w_range(i) - 0.1:
		_beam_fx_t[i] = 0.09
		Fx.spark(end, normal, target != null, false)


# ------------------------------------------------------------------
#  АБИЛКИ (из модулей; клавиши по порядку модулей: Q, E, F, C, V, G)
# ------------------------------------------------------------------

func _update_abilities(delta: float) -> void:
	for i in abilities.size():
		ability_cd[i] = maxf(ability_cd[i] - delta, 0.0)
		if _ability_pressed[i]:
			_ability_pressed[i] = false
			_try_ability(i)

	# невидимость, ремонт, блинк: отсчёт времени
	if cloak_left > 0.0:
		cloak_left = maxf(cloak_left - delta, 0.0)
	if repair_left > 0.0:
		repair_left = maxf(repair_left - delta, 0.0)
		hp = minf(hp + _repair_rate * delta, max_hp())
	if blink_left > 0.0:
		blink_left -= delta
		if blink_left <= 0.0:
			_finish_blink()
	# ПРО-перехват: сбивает ближайшую вражескую ракету или гранату рядом, несколько раз в секунду
	if intercept_left > 0.0:
		intercept_left = maxf(intercept_left - delta, 0.0)
		_icpt_t -= delta
		if _icpt_t <= 0.0 and _icpt_i >= 0 and _icpt_i < abilities.size():
			_icpt_t = 1.0 / maxf(ability_param(_icpt_i, "fire_rate"), 0.5)
			_intercept(ability_param(_icpt_i, "radius"))
	# горит: урон раз в полсекунды (вид "fire" — не поджигает заново)
	if burn_left > 0.0:
		burn_left = maxf(burn_left - delta, 0.0)
		_burn_tick += delta
		if _burn_tick >= 0.5:
			_burn_tick = 0.0
			take_damage(_burn_dps * 0.5, global_position + Vector3.UP * 1.0, Vector3.ZERO, "fire", _burn_src if is_instance_valid(_burn_src) else null)
	# маскировочная сеть: невидим, только пока стоит
	net_left = maxf(net_left - delta, 0.0)
	_net_still = Vector2(velocity.x, velocity.z).length() < 0.6

	# залп: ракеты вылетают по одной с паузой
	if _salvo_left > 0:
		_salvo_timer -= delta
		if _salvo_timer <= 0.0:
			_launch_rocket()
			_salvo_left -= 1
			_salvo_timer = _salvo_params.get("salvo_delay", 0.1)


func _try_ability(index: int) -> void:
	var type: String = abilities[index]["type"]
	# щит включается и выключается одной кнопкой; перезарядка начинается после выключения
	if type == "shield" and barrier_on:
		_set_barrier(false)
		return
	if type == "stance" and stance_on:
		_set_stance(false)
		return
	if type == "scope" and scope_on:
		_set_scope(false)
		return
	if type == "siege" and siege_on:
		_set_siege(false)
		return
	if type in ["blink", "jump", "dropjump"] and (root_left > 0.0 or stance_on or siege_on):
		return          # ноги связаны или стоит в обороне
	if ability_cd[index] > 0.0 or (type == "rockets" and _salvo_left > 0) or (type == "blink" and blink_left > 0.0):
		ability_denied.emit(index, "cooldown")
		return
	if ability_charges_max(index) > 0.0 and ability_charges[index] < 1.0:
		ability_denied.emit(index, "charges")
		return
	if type == "burner" and _burner_target(index) == null:
		ability_denied.emit(index, "target")      # выжигателю не за кого зацепиться: энергию не тратим
		return
	if not spend_energy(ability_cost(index)):
		ability_denied.emit(index, "energy")
		return
	if ability_charges_max(index) > 0.0:
		ability_charges[index] -= 1.0
	if type != "cloak":
		_break_cloak()
	if not type in ["shield", "stance", "scope", "siege"]:
		ability_cd[index] = ability_cooldown_max(index)
	var p: Dictionary = abilities[index]["params"]
	match type:
		"rockets":
			_start_salvo(index)
		"emp":
			_cast_emp(index)
		"cloak":
			cloak_left = p["duration"]
			_cloak_break = p.get("break_on_fire", 1.0) > 0.5
			if team == _player_team():     # вспышку видят только свои, иначе она выдаёт невидимку
				Fx.burst(global_position + Vector3.UP * 2.0, Color(0.6, 0.7, 0.9), 3.0)
		"repair":
			repair_left = p["duration"]
			_repair_rate = p["heal_per_sec"]
		"airstrike":
			_cast_airstrike(index)
		"shield":
			_barrier_i = index
			_set_barrier(true)
		"blink":
			_start_blink(index)
		"mine":
			_cast_mine(index)
		"bolas":
			_cast_shot(index, "bolas")
		"jammer":
			_cast_shot(index, "jam")
		"napalm":
			_throw(index, {"kind": "napalm", "radius": p["radius"], "duration": p["duration"],
				"dps": p["dps"] * damage_mult(), "slow": p["slow"]})
		"emp_shell":
			_throw(index, {"kind": "emp", "radius": p["radius"], "stun": p.get("stun_time", 0.0),
				"no_regen": p.get("no_regen_time", 0.0), "burn": p.get("burn", 0.0), "damage": p.get("damage", 0.0) * damage_mult()})
		"probe":
			_throw(index, {"kind": "probe", "params": p})
		"gravity":
			# Гравитон: усиленный якорь — шире, дольше и тянет сильнее
			var gb: float = stats.get("gravity_boost", 0.0)
			_throw(index, {"kind": "gravity", "radius": p["radius"] * (1.0 + gb * 0.5), "duration": p["duration"] * (1.0 + gb * 0.5),
				"push": p["push"] * (1.0 + gb)})
		"barricade":
			_cast_barricade(index)
		"drone":
			_cast_drone(index)
		"jump":
			_start_jump(index)
		"stance":
			_stance_i = index
			_set_stance(true)
		"repulse":
			_cast_repulse(index)
		"dome":
			_cast_dome(index)
		"turret":
			# Инженер ставит две турели за раз — рядом, поперёк броска
			var tc := maxi(int(stats.get("turret_count", 1.0)), 1)
			var side := torso_forward().cross(Vector3.UP).normalized()
			for k in tc:
				_throw(index, {"kind": "turret", "params": p}, side * (k - (tc - 1) * 0.5) * 3.0)
		"roller":
			_cast_roller(index)
		"marker":
			_cast_shot(index, "mark")
		"slug":
			_cast_slug(index)
		"purge":
			_cast_purge(index)
		"matrix":
			matrix_left = p.get("duration", 4.0)
			_matrix_k = p.get("reduce", 0.4)
			_show_matrix()
		"overdrive":
			overdrive_left = p.get("duration", 4.0)
			_overdrive_k = p.get("boost", 0.35)
			if seen:
				Fx.burst(global_position + Vector3.UP * 1.0, Color(1.0, 0.6, 0.25), 2.5)
			Sfx.play_at("dash", global_position, -4.0, 0.1)
		"rapid":
			rapid_left = p.get("duration", 5.0)
			_rapid_k = p.get("boost", 0.5)
			Sfx.play_at("casing", global_position, -2.0, 0.1)
		"periscope":
			periscope_left = p.get("duration", 8.0)
			_peri_k = p.get("boost", 0.6)
			_peri_omni = p.get("omni", 10.0)
			Sfx.play_at("beep", global_position, -6.0, 0.0)
		"trap":
			_throw(index, {"kind": "trap", "params": p})
		"firewall":
			var fd := _ability_point() - global_position
			fd.y = 0.0
			_throw(index, {"kind": "firewall", "params": p, "dps": p.get("dps", 20.0) * damage_mult(),
				"dir": fd if fd.length() > 0.1 else torso_forward()})
		"emp_dart":
			_cast_shot(index, "empd")
		"nanocloud":
			_throw(index, {"kind": "nanocloud", "params": p})
		"relay":
			_throw(index, {"kind": "relay", "params": p})
		"supply":
			_throw(index, {"kind": "supply", "params": p})
		"smoke":
			_throw(index, {"kind": "smoke", "params": p})
		"scope":
			_scope_i = index
			_set_scope(true)
		"camo":
			net_left = p.get("duration", 20.0)
			Sfx.play_at("step", global_position, -10.0, 0.1)
		"burner":
			_cast_burner(index)
		"siege":
			_siege_i = index
			_set_siege(true)
		"intercept":
			_icpt_i = index
			intercept_left = p.get("duration", 5.0)
			_icpt_t = 0.0
			Sfx.play_at("beep", global_position, -6.0, 0.0)
		"dropjump":
			_start_jump(index)
	ability_used.emit(index)


# ракеты: залп по точке под прицелом. Ракеты летят медленно, от них можно уйти.
func _start_salvo(index: int) -> void:
	_salvo_params = abilities[index]["params"]
	var point := aim_point
	if ability_aim_override != null:
		point = ability_aim_override
		ability_aim_override = null
	var to := point - global_position
	to.y = 0
	var dist := clampf(to.length(), 5.0, _salvo_params["range"])
	var dir := to.normalized() if to.length() > 0.1 else torso_forward()
	_salvo_target = global_position + dir * dist
	_salvo_target.y = 0.0
	_salvo_left = int(_salvo_params["count"])
	_salvo_timer = 0.0
	_salvo_index = 0
	# куда прилетит: метку на земле не рисуем (решение Сани, 16.10.2026), но опасная зона остаётся —
	# по ней боты уходят из-под залпа
	var mark_r: float = _salvo_params["radius"] + (_salvo_params["scatter"] if _salvo_left > 1 else 0.0)
	_salvo_marker = Fx.ground_marker(_salvo_target, mark_r, Color.WHITE, team, 6.0, true, true)
	_salvo_marker.visible = false


func _launch_rocket() -> void:
	var port: Vector3 = visual.get_missile_port(_salvo_index % 2)
	var target := _salvo_target
	if _salvo_index > 0 and _salvo_params["scatter"] > 0.0:
		var a := randf() * TAU
		var r := sqrt(randf()) * float(_salvo_params["scatter"])
		target += Vector3(cos(a) * r, 0, sin(a) * r)
	var rk := Rocket.new()
	rk.setup(port, target, self, _salvo_marker if _salvo_left == 1 else null, _salvo_params)
	get_tree().current_scene.add_child(rk)
	visual.kick_missile(_salvo_index % 2)
	Sfx.play_at("launch", global_position, -6.0, 0.08)
	_salvo_index += 1


# импульс: волна вокруг меха. Бьёт врагов в радиусе и оглушает.
func _cast_emp(index: int) -> void:
	var p: Dictionary = abilities[index]["params"]
	var center := global_position
	Fx.pulse(center + Vector3.UP * 1.2, p["radius"])
	Sfx.play_at("emp", global_position, -3.0, 0.04)
	for n in get_tree().get_nodes_in_group("damageable"):
		if n == self or not (n is Node3D) or n.is_in_group("walls"):
			continue
		if n.get("team") == team:
			continue
		var d: Vector3 = n.global_position - center
		d.y = 0
		var size: float = n.get_hit_radius() if n.has_method("get_hit_radius") else 1.0
		if d.length() <= p["radius"] + size:
			if n.has_method("stun"):
				n.stun(p["stun_time"])
			if n.has_method("block_regen") and p.get("no_regen_time", 0.0) > 0.0:
				n.block_regen(p["no_regen_time"])
			if n.has_method("take_damage") and p["damage"] > 0.0:
				n.take_damage(p["damage"] * damage_mult(), n.global_position + Vector3.UP * 2.0, d.normalized(), "", self)


func _on_footstep(pos: Vector3) -> void:
	stepped.emit(pos)
	# пыль от шага: только у видимых мехов и не у невидимок
	if seen and not is_cloaked() and Cfg.step_dust > 0:
		Fx.step_dust(pos, {"light": 0.7, "mid": 1.0, "heavy": 1.4}.get(visual.cls, 1.0))


# ------------------------------------------------------------------
#  Невидимость, ремонт, щит, блинк, авиаудар
# ------------------------------------------------------------------

func _reset_ability_states() -> void:
	cloak_left = 0.0
	repair_left = 0.0
	_set_barrier(false)
	_cancel_blink()
	_set_stance(false)
	root_left = 0.0
	disarm_left = 0.0
	purge_left = 0.0
	overdrive_left = 0.0
	rapid_left = 0.0
	matrix_left = 0.0
	periscope_left = 0.0
	relay_left = 0.0
	_set_scope(false)
	net_left = 0.0
	_set_siege(false)
	intercept_left = 0.0
	burn_left = 0.0
	marked_left = 0.0
	_shove_t = 0.0
	_jump_up = 0.0
	_jump_land = false


func _break_cloak() -> void:
	if cloak_left > 0.0 and _cloak_break:
		cloak_left = 0.0
	net_left = 0.0          # маскировочную сеть снимает выстрел и любая другая абилка


# осадный режим: включил — стоит на упорах, пушки молчат, ЛКМ/ПКМ — снаряд по дуге в точку прицела
func _set_siege(on: bool) -> void:
	if siege_on and not on and _siege_i >= 0 and _siege_i < ability_cd.size():
		ability_cd[_siege_i] = ability_cooldown_max(_siege_i)
	if on != siege_on:
		Sfx.play_at("land", global_position, -6.0 if on else -10.0, 0.1)
	siege_on = on


func _update_siege(delta: float) -> void:
	_siege_cd = maxf(_siege_cd - delta, 0.0)
	if not (_fire or _fire2) or _siege_cd > 0.0 or disarm_left > 0.0 or is_stunned() or _siege_i < 0:
		return
	var p: Dictionary = abilities[_siege_i]["params"]
	var flat := Vector3(aim_point.x - global_position.x, 0.0, aim_point.z - global_position.z)
	var rng: float = p.get("range", 54.0)
	if flat.length() > rng:
		flat = flat.normalized() * rng
	var target := Vector3(global_position.x + flat.x, 0.0, global_position.z + flat.z)
	var from := global_position + Vector3.UP * get_hit_height() + torso_forward() * 0.5
	var lob := Lob.new()
	lob.setup(from, target, 2.0 + flat.length() * 0.15, self, {"kind": "explosive", "damage": p.get("damage", 120.0) * damage_mult(),
		"radius": p.get("radius", 6.0), "edge_damage": p.get("edge_damage", 0.35)})
	get_tree().current_scene.add_child(lob)
	_siege_cd = 1.0 / maxf(p.get("fire_rate", 0.33), 0.05)
	_break_cloak()
	if seen:
		Fx.light_flash(from, Color(1.0, 0.7, 0.35), 10.0, 2.0, 0.12)
	Sfx.play_at("boom", global_position, -4.0, 0.1)
	Fx.shake_at.emit(global_position, Cfg.shake_explosion * 0.3)


# ПРО-перехват: ближайшая вражеская ракета или граната в радиусе гаснет в воздухе (чёрточка-трассер к ней)
func _intercept(r: float) -> void:
	var best: Node3D = null
	var best_d := r
	for g in ["rockets", "lobs"]:
		for n in get_tree().get_nodes_in_group(g):
			if not is_instance_valid(n) or n.is_queued_for_deletion() or n.get("team") == team:
				continue
			var d: float = n.global_position.distance_to(global_position)
			if d < best_d:
				best_d = d
				best = n
	if best == null:
		return
	Fx.rail_beam(global_position + Vector3.UP * get_hit_height(), best.global_position, team)
	best.intercept()


# прицеливание: включил — дальше бьёт и видит, рельса сильнее, ход медленнее; перезарядка — после выключения
func _set_scope(on: bool) -> void:
	if scope_on and not on and _scope_i >= 0 and _scope_i < ability_cd.size():
		ability_cd[_scope_i] = ability_cooldown_max(_scope_i)
	if on != scope_on:
		Sfx.play_at("beep", global_position, -8.0 if on else -12.0, 0.0)
	scope_on = on


# выжигатель: ближайший к прицелу видимый вражеский мех в досягаемости (не дальше ~12 м от точки прицела)
func _burner_target(index: int) -> Node3D:
	var rng: float = abilities[index]["params"].get("range", 26.0)
	var at := _ability_point()
	var g = get_tree().current_scene
	var best: Node3D = null
	var best_d := 8.0
	for m in get_tree().get_nodes_in_group("mechs"):
		if m.dead or m.team == team or (g != null and g.has_method("is_visible_to") and not g.is_visible_to(team, m)):
			continue
		if Vector2(m.global_position.x - global_position.x, m.global_position.z - global_position.z).length() > rng:
			continue
		var d := Vector2(m.global_position.x - at.x, m.global_position.z - at.z).length()
		if d < best_d:
			best_d = d
			best = m
	return best


# выжигатель: луч цепляется к цели и жжёт её энергию, пока цель в досягаемости и стены не мешают
func _cast_burner(index: int) -> void:
	var t := _burner_target(index)
	if t == null:
		return
	var p: Dictionary = abilities[index]["params"]
	var b := BurnerBeam.new()
	b.shooter = self
	b.target = t
	b.life = p.get("duration", 4.0)
	b.burn = p.get("burn", 30.0)
	b.rng = p.get("range", 26.0)
	get_tree().current_scene.add_child(b)
	Sfx.play_at("laser", global_position, -6.0, 0.05)


# щит: сфера вокруг меха (цвет и прозрачность в шейдере ниже), плюс зелёные искры ремонта
func _make_ability_fx() -> void:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, cull_back, depth_draw_never, shadows_disabled;
uniform vec4 col : source_color = vec4(0.35, 0.78, 1.0, 1.0);
uniform float hit = 0.0;
uniform float fade = 1.0;
void fragment() {
	float rim = pow(1.0 - abs(dot(NORMAL, VIEW)), 2.2);
	ALBEDO = mix(col.rgb, vec3(0.85, 0.95, 1.0), hit);
	ALPHA = clamp(0.08 + rim * 0.7 + hit * 0.35, 0.0, 1.0) * fade;
}
"""
	_barrier_mat = ShaderMaterial.new()
	_barrier_mat.shader = sh
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 32
	sm.rings = 16
	_barrier = MeshInstance3D.new()
	_barrier.mesh = sm
	_barrier.material_override = _barrier_mat
	_barrier.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_barrier.visible = false
	add_child(_barrier)

	_repair_fx = CPUParticles3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(0.18, 0.18, 0.18)
	_repair_fx.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gm.albedo_color = Color(0.4, 1.0, 0.5)
	_repair_fx.material_override = gm
	_repair_fx.amount = 24
	_repair_fx.lifetime = 0.8
	_repair_fx.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_repair_fx.emission_sphere_radius = 2.0
	_repair_fx.direction = Vector3.UP
	_repair_fx.spread = 20.0
	_repair_fx.initial_velocity_min = 1.5
	_repair_fx.initial_velocity_max = 3.5
	_repair_fx.gravity = Vector3.ZERO
	_repair_fx.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_repair_fx.position = Vector3(0, 2.5, 0)
	_repair_fx.emitting = false
	add_child(_repair_fx)

	# дым из подбитого меха: тёмные клубы из корпуса, плюс редкие искры (в _update_ability_fx)
	_smoke_fx = CPUParticles3D.new()
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.vertex_color_use_as_albedo = true
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var stex := Art.fx_tex("smoke_07")
	if stex != null:
		var qm := QuadMesh.new()
		qm.size = Vector2(1.6, 1.6)
		_smoke_fx.mesh = qm
		smat.albedo_texture = stex
		smat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		_smoke_fx.angle_max = 360.0
	else:
		var ssm := SphereMesh.new()
		ssm.radius = 0.5
		ssm.height = 1.0
		ssm.radial_segments = 6
		ssm.rings = 3
		_smoke_fx.mesh = ssm
	_smoke_fx.material_override = smat
	var sramp := Gradient.new()
	sramp.set_color(0, Color(0.12, 0.11, 0.1, 0.75))
	sramp.set_color(1, Color(0.25, 0.25, 0.27, 0.0))
	_smoke_fx.color_ramp = sramp
	_smoke_fx.local_coords = false
	_smoke_fx.amount = 18
	_smoke_fx.lifetime = 1.6
	_smoke_fx.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_smoke_fx.emission_sphere_radius = 0.6
	_smoke_fx.direction = Vector3.UP
	_smoke_fx.spread = 15.0
	_smoke_fx.initial_velocity_min = 1.5
	_smoke_fx.initial_velocity_max = 3.0
	_smoke_fx.gravity = Vector3(0.6, 0.8, 0)
	_smoke_fx.scale_amount_min = 0.8
	_smoke_fx.scale_amount_max = 1.8
	_smoke_fx.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_smoke_fx.position = Vector3(0, 3.2, 0.4)
	_smoke_fx.emitting = false
	add_child(_smoke_fx)


func _update_ability_fx(delta: float) -> void:
	# невидимость: свой мех полупрозрачный, чужой почти не виден
	# своя команда видит своего невидимку полупрозрачным; врага видно, только если его раскрыл омни-сенсор
	var want := 0.0
	if is_cloaked():
		want = 0.6 if team == _player_team() else Cfg.cloak_revealed
	if not is_equal_approx(_fade, want):
		_fade = move_toward(_fade, want, delta * 4.0)
		visual.set_fade(_fade)
	_repair_fx.emitting = repair_left > 0.0 and seen
	# мало здоровья: мех дымит и искрит, чтобы было видно, кого добивать
	var hurt := not dead and landing_left <= 0.0 and hp < max_hp() * Cfg.smoke_hp and seen and not is_cloaked()
	_smoke_fx.emitting = hurt
	# оглушение: по корпусу бегают мелкие молнии
	if is_stunned() and seen and not dead and Cfg.stun_zaps > 0:
		var zr: float = {"light": 1.6, "mid": 2.3, "heavy": 2.8}.get(visual.cls, 2.3)
		var zh: float = {"light": 3.4, "mid": 4.4, "heavy": 4.8}.get(visual.cls, 4.4)
		for z in (1 if randf() < 0.6 else 0):
			Fx.zap(global_position, zr, zh)
	if hurt:
		_spark_t -= delta
		if _spark_t <= 0.0:
			_spark_t = randf_range(0.5, 1.3)
			var sp := global_position + Vector3(randf_range(-1.0, 1.0), randf_range(2.2, 3.4), randf_range(-1.0, 1.0))
			Fx.spark(sp, Vector3(randf_range(-0.5, 0.5), 1.0, randf_range(-0.5, 0.5)).normalized(), true, false)
	_barrier.visible = barrier_on and seen
	if _bar != null:
		_bar.visible = seen
	if barrier_on:
		_barrier_hit = maxf(_barrier_hit - delta * 4.0, 0.0)
		_barrier_mat.set_shader_parameter("hit", _barrier_hit)
		_barrier_mat.set_shader_parameter("fade", 1.0 - _fade)
		# щит светит на землю и соседей своим цветом, при попадании ярче (только видимый — иначе выдаст меха)
		if seen:
			Fx.light_flash(global_position + Vector3.UP * 2.0, Color(0.35, 0.78, 1.0), 9.0, (1.5 + _barrier_hit * 3.0) * (1.0 - _fade),
				0.08, "shield_%d" % get_instance_id())


func _player_team() -> int:
	var g = get_tree().current_scene if is_inside_tree() else null
	if g != null and "vision" in g and g.vision != null:
		return g.vision.player_team
	return 0


func _set_barrier(on: bool) -> void:
	if barrier_on and not on and _barrier_i >= 0 and _barrier_i < ability_cd.size():
		ability_cd[_barrier_i] = ability_cooldown_max(_barrier_i)
	barrier_on = on
	if _barrier != null:
		_barrier.visible = on
	if on:
		_barrier_hit = 1.0


# щит принимает урон на себя и платит за него энергией; когда энергия кончилась, щит падает
func _barrier_absorb(amount: float) -> float:
	var take := amount * clampf(ability_param(_barrier_i, "absorb"), 0.0, 1.0)
	var per := ability_param(_barrier_i, "energy_per_damage")
	var cost := take * per
	_barrier_hit = 1.0
	if cost <= energy:
		energy -= cost
		return amount - take
	var can_take := energy / maxf(per, 0.0001)
	energy = 0.0
	_set_barrier(false)
	return amount - can_take


# блинк: выбираем точку, ставим метку, стоим delay секунд, прыгаем
func _start_blink(index: int) -> void:
	var p: Dictionary = abilities[index]["params"]
	var point := _ability_point()
	var to := point - global_position
	to.y = 0
	if to.length() > p["range"]:
		to = to.normalized() * p["range"]
	_blink_dest = _free_spot(global_position + to)
	blink_left = maxf(p["delay"], 0.01)
	_blink_marker = Fx.ground_marker(_blink_dest, get_hit_radius(), Color(0.45, 0.75, 1.0), team, blink_left + 0.5, false, true)
	Fx.burst(global_position + Vector3.UP * 2.0, Color(0.45, 0.75, 1.0), 2.5)


func _finish_blink() -> void:
	blink_left = 0.0
	var dest := _free_spot(_blink_dest)      # пока стоял, туда могли зайти
	if _blink_marker != null and is_instance_valid(_blink_marker):
		_blink_marker.queue_free()
	_blink_marker = null
	Fx.burst(global_position + Vector3.UP * 2.0, Color(0.45, 0.75, 1.0), 3.5)
	global_position = Vector3(dest.x, global_position.y, dest.z)
	_snap_next = true
	velocity = Vector3.ZERO
	Fx.burst(global_position + Vector3.UP * 2.0, Color(0.45, 0.75, 1.0), 3.5)
	Sfx.play_at("dash", global_position, -2.0, 0.05)


func _cancel_blink() -> void:
	blink_left = 0.0
	if _blink_marker != null and is_instance_valid(_blink_marker):
		_blink_marker.queue_free()
	_blink_marker = null


# ближайшая к цели точка на линии от меха, где мех помещается (не в стене и не в другом мехе)
func _free_spot(target: Vector3) -> Vector3:
	var from := Vector3(global_position.x, 0, global_position.z)
	var to := Vector3(target.x, 0, target.z) - from
	var dist := to.length()
	var dir := to / maxf(dist, 0.001)
	var shape := SphereShape3D.new()
	shape.radius = 1.4
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.collision_mask = 1 | 2
	q.exclude = [get_rid()]
	var space := get_world_3d().direct_space_state
	var d := dist
	while d > 0.0:
		var p := from + dir * d
		q.transform = Transform3D(Basis(), p + Vector3.UP * 1.9)
		if space.intersect_shape(q, 1).is_empty():
			return p
		d -= 0.5
	return from


# точка под прицелом (или та, что указал бот)
func _ability_point() -> Vector3:
	var point := aim_point
	if ability_aim_override != null:
		point = ability_aim_override
		ability_aim_override = null
	return point


# мина: ставится под себя
func _cast_mine(index: int) -> void:
	var mn := Mine.new()
	mn.team = team
	mn.owner_mech = self
	mn.p = abilities[index]["params"]
	get_tree().current_scene.add_child(mn)
	mn.global_position = Vector3(global_position.x, 0.0, global_position.z)
	mn.reset_physics_interpolation()
	Sfx.play_at("step", global_position, -4.0, 0.1)


# авиаудар: метка на земле, через delay секунд сверху падает ракета
func _cast_airstrike(index: int) -> void:
	var p: Dictionary = abilities[index]["params"].duplicate()
	var point := _ability_point()
	var to := point - global_position
	to.y = 0
	if to.length() > p["range"]:
		to = to.normalized() * p["range"]
	var target := global_position + to
	target.y = 0.0
	var delay: float = maxf(p["delay"], 0.05)
	var marker := Fx.strike_marker(target, p["radius"], team, delay)      # видна своей команде, метки сходятся к падению
	var fall := minf(0.45, delay)
	p["fall"] = true
	var start := target + Vector3(4.0, 34.0, 3.0)
	p["speed"] = start.distance_to(target) / fall
	var who := self
	get_tree().create_timer(delay - fall, false).timeout.connect(func() -> void:
		if not is_instance_valid(who):
			if is_instance_valid(marker):
				marker.queue_free()
			return
		var rk := Rocket.new()
		rk.setup(start, target, who, marker, p)
		who.get_tree().current_scene.add_child(rk)
		Sfx.play_at("launch", start, -4.0, 0.05))


# ------------------------------------------------------------------
#  Абилки 17.10.2026: связка, дротик, снаряды навесом (напалм, ЭМИ, зонд, якорь), баррикада,
#  ремонтный дрон, прыжок, оборона, ударная волна
# ------------------------------------------------------------------

# связка или глушащий дротик: летит прямо из корпуса в сторону прицела
func _cast_shot(index: int, kind: String) -> void:
	var p: Dictionary = abilities[index]["params"]
	var point := _ability_point()
	var dir := point - global_position
	dir.y = 0
	if dir.length() < 0.1:
		dir = torso_forward()
	var sh := Bolas.new()
	sh.setup(global_position + Vector3.UP * get_hit_height() * 0.55 + dir.normalized() * get_hit_radius(), dir, self, kind, p)
	get_tree().current_scene.add_child(sh)
	Sfx.play_at("launch", global_position, -7.0, 0.1)


# снаряд навесом в точку прицела (не дальше «Дальности»). Зонд — по дуге над стенами точно в точку
func _throw(index: int, payload: Dictionary, offset := Vector3.ZERO) -> void:
	var p: Dictionary = abilities[index]["params"]
	var point := _ability_point()
	var flat := Vector3(point.x - global_position.x, 0, point.z - global_position.z)
	var rng: float = p.get("range", 30.0)
	if flat.length() > rng:
		flat = flat.normalized() * rng
	var target := Vector3(global_position.x + flat.x + offset.x, 0.0, global_position.z + flat.z + offset.z)
	var from := global_position + Vector3.UP * get_hit_height() + torso_forward() * 0.5
	var lob := Lob.new()
	if payload["kind"] == "probe":
		lob.setup(from, target, PROBE_ARC, self, payload)
	else:
		lob.setup_ballistic(from, Lob.aim_velocity(from, target, p.get("speed", 28.0)), self, payload)
	get_tree().current_scene.add_child(lob)
	Sfx.play_at("launch", global_position, -6.0, 0.1)


# баррикада: перед мехом в сторону прицела, развёрнута поперёк
func _cast_barricade(index: int) -> void:
	var p: Dictionary = abilities[index]["params"]
	var dir := _ability_point() - global_position
	dir.y = 0
	if dir.length() < 0.1:
		dir = torso_forward()
	dir = dir.normalized()
	var b := Barricade.new()
	b.team = team
	b.owner_mech = self
	b.hp_max = p.get("hp", 400.0) * (1.0 + stats.get("device_hp", 0.0))
	b.life = p.get("duration", 25.0)
	var pos := global_position + dir * (get_hit_radius() + float(p.get("range", 4.5)))
	b.position = Vector3(pos.x, 0.0, pos.z)
	b.rotation.y = atan2(dir.x, dir.z)
	get_tree().current_scene.add_child(b)
	b.reset_physics_interpolation()


# ремонтный дрон: к союзнику под прицелом (ближе 6 единиц к прицелу и в «Дальности»), иначе к себе
func _cast_drone(index: int) -> void:
	var p: Dictionary = abilities[index]["params"]
	var point := _ability_point()
	var best: Node3D = self
	var bd := 6.0
	for m in get_tree().get_nodes_in_group("mechs"):
		if m == self or m.dead or m.team != team or m.is_landing():
			continue
		var d := Vector2(m.global_position.x - point.x, m.global_position.z - point.z).length()
		if d < bd and m.global_position.distance_to(global_position) <= p.get("range", 30.0):
			best = m
			bd = d
	var dr := RepairDrone.new()
	dr.owner_mech = self
	dr.target = best
	dr.p = p
	get_tree().current_scene.add_child(dr)
	dr.global_position = global_position + Vector3.UP * (get_hit_height() + 0.5)
	dr.reset_physics_interpolation()


# ударная волна: мех бьёт в землю, врагов вокруг отбрасывает на «Дистанцию толчка» (тяжёлых ближе,
# крипов ровно на неё) и чуть ранит
func _cast_repulse(index: int) -> void:
	var p: Dictionary = abilities[index]["params"]
	var c := global_position
	var r: float = p.get("radius", 8.0)
	Fx.dust_ring(c, r)
	Fx.dust_cloud(c, r * 0.35)
	Fx.shake_at.emit(c, Cfg.shake_explosion * 0.5)
	Sfx.play_at("boom", c, -4.0, 0.1)
	var g = get_tree().current_scene
	if g == null or not g.has_method("units"):
		return
	for u in g.units():
		if u[2] == team:
			continue
		var d: Vector3 = u[1] - c
		d.y = 0
		if d.length() > r + float(u[3]):
			continue
		var dir := d.normalized() if d.length() > 0.1 else torso_forward()
		var n = u[0]
		if n.has_method("shove"):
			n.shove(dir, float(p.get("shove", 8.0)))
		if p.get("damage", 0.0) > 0.0:
			n.take_damage(p["damage"] * damage_mult(), n.global_position + Vector3.UP * 1.5, dir, "", self)


# оборона: включается и выключается одной кнопкой; перезарядка — после выключения
func _set_stance(on: bool) -> void:
	if stance_on and not on and _stance_i >= 0 and _stance_i < ability_cd.size():
		ability_cd[_stance_i] = ability_cooldown_max(_stance_i)
	if on != stance_on:
		Sfx.play_at("land", global_position, -8.0 if on else -12.0, 0.1)
	stance_on = on


# прыжок: двигатели уносят меха вверх за кадр (неуязвим), потом он падает на точку, как при высадке,
# и бьёт при приземлении (_jump_slam)
func _start_jump(index: int) -> void:
	var p: Dictionary = abilities[index]["params"]
	var to := _ability_point() - global_position
	to.y = 0
	if to.length() > p.get("range", 26.0):
		to = to.normalized() * p.get("range", 26.0)
	_jump_dest = _free_spot(global_position + to)
	_jump_from = global_position
	_jump_i = index
	_jump_up = JUMP_UP
	_cancel_blink()
	dash_left = 0.0
	velocity = Vector3.ZERO
	_col.set_deferred("disabled", true)
	hitbox.set_active(false)
	if seen:
		Fx.dust_ring(global_position, get_hit_radius() * 2.5)
	Fx.shake_at.emit(global_position, Cfg.shake_explosion * 0.3)
	Sfx.play_at("launch", global_position, -1.0, 0.05)


func _update_jump_up(delta: float) -> void:
	_jump_up = maxf(_jump_up - delta, 0.0)
	var u := 1.0 - _jump_up / JUMP_UP
	visual.visible = seen
	visual.airborne = true
	visual.set_jets(1.0 if seen else 0.0)
	visual.update_visual(delta, global_position + Vector3.UP * Cfg.drop_height * u * u, Vector3.ZERO, legs_yaw, torso_yaw, true)
	if _jump_up <= 0.0:
		global_position = Vector3(_jump_dest.x, global_position.y, _jump_dest.z)
		_snap_next = true
		_jump_land = true
		start_landing(ability_param(_jump_i, "delay") if _jump_i >= 0 and _jump_i < abilities.size() else 1.2)


func _jump_slam() -> void:
	if _jump_i < 0 or _jump_i >= abilities.size():
		return
	var p: Dictionary = abilities[_jump_i]["params"]
	var c := global_position
	Fx.blast(c, p.get("radius", 5.0), p.get("damage", 60.0) * damage_mult(), p.get("edge_damage", 0.4), team, self)
	if seen:
		Fx.dust_cloud(c, p.get("radius", 5.0) * 0.5)
	Fx.shake_at.emit(c, Cfg.shake_explosion * 0.8)
	Sfx.play_at("boom", c, -3.0, 0.1)
	# десантный прыжок: врагов у места приземления отбрасывает туда, откуда прыгнул, — к своим
	if abilities[_jump_i]["type"] == "dropjump":
		for m in get_tree().get_nodes_in_group("mechs"):
			if m.dead or m.team == team:
				continue
			var d: Vector3 = m.global_position - c
			d.y = 0
			if d.length() > p.get("radius", 6.0) + m.get_hit_radius():
				continue
			var home: Vector3 = _jump_from - m.global_position
			home.y = 0
			if home.length() > 0.1:
				m.shove(home.normalized(), p.get("shove", 8.0))


# купольный щит: генератор у ног, купол держит вражеские пули, гранаты и снаряды снаружи
func _cast_dome(index: int) -> void:
	var p: Dictionary = abilities[index]["params"]
	var d := DomeShield.new()
	d.team = team
	d.p = p
	d.position = Vector3(global_position.x, 0.0, global_position.z)
	get_tree().current_scene.add_child(d)
	d.reset_physics_interpolation()


# шар-самоубийца выкатывается из-под меха в сторону прицела
func _cast_roller(index: int) -> void:
	var p: Dictionary = abilities[index]["params"]
	var dir := _ability_point() - global_position
	dir.y = 0
	if dir.length() < 0.1:
		dir = torso_forward()
	dir = dir.normalized()
	var r := Roller.new()
	r.team = team
	r.owner_mech = self
	r.p = p
	r.dir = dir
	r.position = Vector3(global_position.x, 0.0, global_position.z) + dir * (get_hit_radius() + 1.0)
	get_tree().current_scene.add_child(r)
	r.reset_physics_interpolation()
	Sfx.play_at("step", global_position, -4.0, 0.1)


# тяжёлая болванка: орудие наводится «Задержку» секунд (слышно), потом выстрел
func _cast_slug(index: int) -> void:
	var p: Dictionary = abilities[index]["params"]
	var point := _ability_point()
	Sfx.play_at("beep", global_position, -6.0, 0.0)
	var who := self
	get_tree().create_timer(maxf(p.get("delay", 0.4), 0.0), false).timeout.connect(func() -> void:
		if not is_instance_valid(who) or who.dead or who.is_stunned():
			return
		who.ability_aim_override = point
		who._cast_shot(index, "slug")
		Sfx.play_at("cannon", who.global_position, 0.0, 0.05)
		Fx.shake_at.emit(who.global_position, Cfg.shake_explosion * 0.3))


# аварийный перезапуск: снять весь контроль и какое-то время не брать новый
func _cast_purge(index: int) -> void:
	var p: Dictionary = abilities[index]["params"]
	stun_left = 0.0
	root_left = 0.0
	disarm_left = 0.0
	slow_left = 0.0
	no_regen_left = 0.0
	marked_left = 0.0
	_shove_t = 0.0
	purge_left = p.get("duration", 2.5)
	if seen:
		Fx.burst(global_position + Vector3.UP * 2.0, Color(0.9, 0.95, 1.0), 3.0)
		Fx.dust_cloud(global_position + Vector3.UP * 1.5, 1.2)
	Sfx.play_at("emp", global_position, -6.0, 0.1)


# матрица брони: оранжевое поле вокруг меха, пока действует
func _show_matrix() -> void:
	if _matrix_vis == null and _barrier != null:
		_matrix_vis = MeshInstance3D.new()
		_matrix_vis.mesh = _barrier.mesh
		var m: ShaderMaterial = _barrier_mat.duplicate()
		m.set_shader_parameter("col", Color(1.0, 0.55, 0.2, 1.0))
		_matrix_vis.material_override = m
		_matrix_vis.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_matrix_vis.scale = _barrier.scale * 1.05
		_matrix_vis.position = _barrier.position
		add_child(_matrix_vis)
	if _matrix_vis != null:
		_matrix_vis.visible = visual.visible
	Sfx.play_at("wall", global_position, -6.0, 0.1)
