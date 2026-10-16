extends Node3D
## Собирает карту и ведёт бой как в мобе.
## Карта берётся из файла (папка maps, выбирается в меню или открывается из редактора).
## Две базы: у каждой штаб и турели (чем ближе к базе, тем сильнее). Сломал вражеский штаб = победа.
## По линиям волнами едут крипы-танки. Стены и барьеры можно разрушить.
## Точки интереса дают бонус команде-владельцу, на карту периодически падают ящики с припасами.
## Убитый мех превращается в обломок: его можно толкать и разбить, тогда выпадут припасы.
## Мехи появляются, прилетая с неба. Клавиша T: телепорт на свою базу.
## Своя команда: ты и союзные боты. Враги: вражеские боты. Количество ботов в настройках (F2, «Боты»).
## Режим PvP (карта с "mode": "pvp"): только мехи, без баз, турелей, штабов и крипов. Команды появляются
## на своих точках, убитый мех возвращается через несколько секунд. Победа: первой набрать нужное число
## убийств или иметь больше убийств, когда вышло время (числа в F2, группа «PvP»).

const Mech := preload("res://scripts/mech.gd")
const BotBrain := preload("res://scripts/bot_brain.gd")
const Nav := preload("res://scripts/nav.gd")
const CameraRig := preload("res://scripts/camera_rig.gd")
const Crosshair := preload("res://scripts/crosshair.gd")
const Hud := preload("res://scripts/hud.gd")
const Hangar := preload("res://scripts/hangar.gd")
const GameMenu := preload("res://scripts/game_menu.gd")
const TargetDummy := preload("res://scripts/target_dummy.gd")
const Structure := preload("res://scripts/structure.gd")
const Wreck := preload("res://scripts/wreck.gd")
const Pickup := preload("res://scripts/pickup.gd")
const Poi := preload("res://scripts/poi.gd")
const Vision := preload("res://scripts/vision.gd")
const Minimap := preload("res://scripts/minimap.gd")
const Wall := preload("res://scripts/wall.gd")
const Creep := preload("res://scripts/creep.gd")
const GroundShader := preload("res://shaders/ground.gdshader")
const Autotest := preload("res://scripts/dev_autotest.gd")
const MapArt := preload("res://scripts/map_art.gd")
const Art := preload("res://scripts/art.gd")

const WALL_EXTRA := 30.0          # насколько стены и укрытия выше для выстрелов, чем на вид
const BOT_NAMES := ["Ржавый", "Гром", "Шершень", "Клык", "Пепел", "Вольт", "Кремень", "Дизель", "Штиль", "Карась"]

var map := {}                     # данные карты из файла
var mech: CharacterBody3D
var cam: Camera3D
var hud: CanvasLayer
var hangar: CanvasLayer
var menu: CanvasLayer
var nav: RefCounted
var vision: Node
var art: Node3D
var puddles: Array = []          # лужи на земле: Vector3(x, радиус, z); трава в них не растёт
var minimap: Control
var bots: Array = []
var kills := 0
var deaths := 0
var winner := -1                  # -1 бой идёт, 0 и 1 победила команда, 2 ничья (PvP по времени)
var pvp := false                  # режим PvP: мехи против мехов, без баз
var team_kills := [0, 0]          # PvP: убийства каждой команды
var covers: Array = []            # все укрытия [x, z, ширина, высота, глубина, вид]
var walls: Array = []             # разрушаемые стены (wall.gd)
var lanes := {}                   # имя линии -> точки от базы команды 0 к базе команды 1
var started := false              # бой начался (нажали «В бой»)
var _player_respawn := 0.0
var _hq := [null, null]
var _crate_t := 0.0
var _crate_warn := 0.0
var _crate_spot = null
var _crate_marker: Node3D
var _base_charge := {}
var _lane_i := 0
var _motes: CPUParticles3D     # пылинки в воздухе вокруг игрока
var _creep_t := 0.0
var _creep_slot := 0
var _spawns := [[], []]           # места появления вокруг штабов
var _static_boxes: Array = []     # постройки и украшения для карты проходимости
var _hit_shake_t := 0.0           # тряска от попаданий не чаще нескольких раз в секунду
var _hit_shake_acc := 0.0
var _name_i := 0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var autotest: Node = null
	if not args.is_empty():
		autotest = Autotest.new()
		autotest.setup(self, args)
	Input.set_default_cursor_shape(Input.CURSOR_CROSS)
	Battle.reset()

	map = Maps.current()
	pvp = Maps.is_pvp(map)
	Battle.pvp = pvp
	covers = map["covers"]
	lanes = Maps.lanes(map)          # в PvP линий нет
	vision = Vision.new()
	vision.map_rect = map_rect()
	Fx.player_team = vision.player_team
	add_child(vision)

	_build_environment()
	_build_ground()
	_build_motes()
	_build_walls()
	_build_structures()
	_build_cables()

	for p in map["pois"]:
		var poi := Poi.new()
		poi.kind = p[2] if p.size() > 2 else "regen"
		poi.title = Maps.POI_NAMES.get(poi.kind, "Точка")
		poi.position = Vector3(float(p[0]), 0, float(p[1]))
		add_child(poi)

	mech = Mech.new()
	mech.team = 0
	mech.is_player = true
	mech.build = Parts.player_build.duplicate(true)
	mech.position = spawn_point(0)
	add_child(mech)
	var face := _face_yaw(0)
	mech.torso_yaw = face
	mech.legs_yaw = face
	mech.died.connect(_on_mech_died)
	Battle.register(mech, Cfg.player_name)
	Battle.set_mech(mech, Parts.pname(mech.build.get("mech", "")))

	cam = CameraRig.new()
	cam.target = mech
	if autotest != null:
		cam.debug_yaw = autotest.debug_yaw
	add_child(cam)
	mech.camera = cam

	var ch := Crosshair.new()
	ch.mech = mech
	add_child(ch)

	hud = Hud.new()
	hud.main = self
	hud.bind(mech)
	add_child(hud)
	minimap = Minimap.new()
	hud.add_minimap(minimap)
	# миникарта вписана в 360 × 260 пикселей (квадратная карта не вылезает за низ экрана)
	var mm_k := minf(360.0 / map_rect().size.x, 260.0 / map_rect().size.y)
	minimap.setup(self, vision, map_rect(), covers, map_rect().size * mm_k)

	hangar = Hangar.new()
	hangar.applied.connect(_on_build_applied)
	add_child(hangar)

	menu = GameMenu.new()
	menu.main = self
	add_child(menu)

	var blockers: Array = []
	for t in map["targets"]:
		var d := TargetDummy.new()
		d.position = Vector3(float(t[0]), 0, float(t[1]))
		add_child(d)
		blockers.append(d.position)
	for w in map["walkers"]:
		var d2 := TargetDummy.new()
		d2.position = Vector3(float(w[0]), 0, float(w[1]))
		d2.patrol_a = Vector3(float(w[0]), 0, float(w[1]))
		d2.patrol_b = Vector3(float(w[2]), 0, float(w[3]))
		d2.patrol_speed = float(w[4]) if w.size() > 4 else 5.0
		add_child(d2)

	_static_boxes = _structure_boxes() + art.decor_boxes
	nav = Nav.new()
	nav.build(map_rect(), _nav_boxes(), blockers)

	mech.fired.connect(_on_fired)
	mech.dashed.connect(_on_dashed)
	mech.stepped.connect(_on_stepped)
	mech.ability_denied.connect(_on_denied)
	mech.damaged.connect(_on_player_damaged)
	mech.landed.connect(_on_player_landed)
	Fx.shake_at.connect(_on_shake_at)
	_crate_t = _crate_every() * 0.5
	_creep_t = Cfg.creep_first

	if autotest != null:
		add_child(autotest)
		start_battle(false)
	else:
		# перед боем: ангар со своим мехом, игра на паузе до кнопки "В бой"
		hangar.open_start.call_deferred(mech.build)


# бой начинается: игрок и боты прилетают с неба, пошло время
func start_battle(drop := true) -> void:
	if started:
		return
	started = true
	Battle.running = true
	if drop:
		mech.start_landing()


func map_rect() -> Rect2:
	return Maps.rect(map)


# куда смотреть при появлении: в сторону вражеской базы
func _face_yaw(team: int) -> float:
	var to := base_center(1 - team) - base_center(team)
	return atan2(-to.x, -to.z)


# места появления: кольцо вокруг своего штаба (свободные от стен и построек).
# В PvP кольца теснее: вокруг точки появления команды
func _build_spawns(team: int) -> void:
	var c := base_center(team)
	var to_enemy := (base_center(1 - team) - c).normalized()
	var r := map_rect().grow(-4.0)
	var pts: Array = []
	for ring in ([4.0, 8.0, 12.0] if pvp else [10.0, 14.0, 18.0]):
		for i in 12:
			var a := TAU * i / 12.0
			var p: Vector3 = c + Vector3(cos(a), 0, sin(a)) * ring
			if not r.has_point(Vector2(p.x, p.z)) or not _spot_free(p, 2.0):
				continue
			pts.append(p)
	# ближе к выходу из базы (в сторону врага) удобнее
	pts.sort_custom(func(a, b) -> bool: return (a - c).normalized().dot(to_enemy) > (b - c).normalized().dot(to_enemy))
	if pts.is_empty():
		pts.append(c + to_enemy * 8.0)
	_spawns[team] = pts.slice(0, 8)


func spawn_point(team: int) -> Vector3:
	if _spawns[team].is_empty():
		_build_spawns(team)
	var options: Array = []
	for s in _spawns[team]:
		var p: Vector3 = Vector3(s.x, 0.05, s.z)
		var free := true
		for m in get_tree().get_nodes_in_group("mechs"):
			if not m.dead and m.global_position.distance_to(p) < 5.0:
				free = false
		if free:
			options.append(p)
	if options.is_empty():
		var s0: Vector3 = _spawns[team][0]
		return Vector3(s0.x, 0.05, s0.z)
	return options.pick_random()


# штаб команды; в PvP баз нет — точка появления команды
func base_center(team: int) -> Vector3:
	return Maps.spawn_pos(map, team) if pvp else Maps.hq_pos(map, team)


func is_visible_to(team: int, node: Node) -> bool:
	return vision.is_visible_to(team, node)


# все живые мехи (кроме падающих с неба) и крипы на этом тике одним списком:
# [узел, позиция, команда, радиус, мех ли]. Турели и крипы ищут по нему цели и соседей,
# а не перебирают группы заново каждый раз (так было дорого: десятки турелей и крипов на каждом тике)
var _units: Array = []
var _units_tick := -1


func units() -> Array:
	var t := Engine.get_physics_frames()
	if t != _units_tick:
		_units_tick = t
		_units = []
		for m in get_tree().get_nodes_in_group("mechs"):
			if not m.dead and not m.is_landing():
				_units.append([m, m.global_position, m.team, m.get_hit_radius(), true])
		for c in get_tree().get_nodes_in_group("creeps"):
			if not c.dead:
				_units.append([c, c.global_position, c.team, c.get_hit_radius(), false])
	return _units


# бонусы команды с захваченных точек
func team_mult(team: int, kind: String) -> float:
	var k := 1.0
	for p in get_tree().get_nodes_in_group("pois"):
		if p.owner_team == team and p.kind == kind:
			k += Cfg.poi_regen_bonus if kind == "regen" else Cfg.poi_damage_bonus
	return k


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_ESCAPE and not hangar.is_open():
			menu.toggle_pause()
			get_viewport().set_input_as_handled()
		elif event.physical_keycode == KEY_F3:
			Cfg.show_hitboxes = not Cfg.show_hitboxes
		elif event.physical_keycode == KEY_B and not hangar.is_open() and not menu.is_open() and winner < 0:
			hangar.open(mech.build)
			get_viewport().set_input_as_handled()


func restart() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


func to_menu() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://menu.tscn")


func to_editor() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://editor.tscn")


func _physics_process(delta: float) -> void:
	_update_bots(delta)
	if not pvp:
		_update_base(delta)
	_update_crates(delta)
	_update_creeps(delta)
	_update_pvp()
	_hit_shake_t = maxf(_hit_shake_t - delta, 0.0)
	Sfx.set_laser(mech.is_beaming() and not mech.dead)
	Sfx.set_listener(mech.global_position, cam.global_basis)
	if _motes != null:
		_motes.global_position = Vector3(mech.global_position.x, 3.5, mech.global_position.z)
	if mech.dead:
		_player_respawn -= delta
		if _player_respawn <= 0.0:
			mech.respawn(spawn_point(0))


# ------------------------------------------------------------------
#  БОТЫ
# ------------------------------------------------------------------

func _update_bots(delta: float) -> void:
	if not started:
		return
	for team in 2:
		var want: int = Cfg.bot_allies if team == 0 else Cfg.bot_enemies
		var mine: Array = bots.filter(func(b) -> bool: return b.team == team)
		while mine.size() > maxi(want, 0):
			var extra = mine.pop_back()
			bots.erase(extra)
			extra.queue_free()
		while mine.size() < want:
			mine.append(_spawn_bot(team))
	for b in bots:
		if b.dead:
			var left: float = b.get_meta("respawn", 0.0) - delta
			b.set_meta("respawn", left)
			if left <= 0.0:
				b.set_build(Parts.random_build())    # каждый раз новая случайная сборка
				Battle.set_mech(b, Parts.pname(b.build["mech"]))
				b.respawn(spawn_point(b.team))


func _spawn_bot(team: int) -> Node:
	var b := Mech.new()
	b.team = team
	b.build = Parts.random_build()
	b.position = spawn_point(team)
	var brain := BotBrain.new()
	brain.mech = b
	brain.nav = nav
	brain.main = self
	var names := lanes.keys()
	if not names.is_empty():          # в PvP линий нет
		brain.lane = names[_lane_i % names.size()]
	_lane_i += 1
	b.brain = brain
	add_child(b)
	b.torso_yaw = _face_yaw(team)
	b.legs_yaw = b.torso_yaw
	b.died.connect(_on_mech_died)
	b.fired.connect(_on_bot_fired.bind(b))
	b.stepped.connect(_on_bot_stepped.bind(b))
	bots.append(b)
	Battle.register(b, BOT_NAMES[_name_i % BOT_NAMES.size()])
	Battle.set_mech(b, Parts.pname(b.build["mech"]))
	_name_i += 1
	if Cfg.drop_time > 0.05:
		b.start_landing()
	return b


# шаги ботов: тяжёлые громче
func _on_bot_stepped(_pos, bot: Node3D) -> void:
	Sfx.play_at("step", bot.global_position, -14.0 + 3.0 * (bot.stats["legs_scale"] - 1.0) * 4.0, 0.12)


func _on_bot_fired(mount: int, bot: Node3D) -> void:
	var s := _shot_sound(bot.weapons[mount]["look"])
	Sfx.play_at(s[0], bot.global_position, s[1] - 2.0, 0.08)


# звук выстрела по виду оружия: [звук, громкость]
func _shot_sound(look: String) -> Array:
	match look:
		"heavy":
			return ["cannon", -3.0]
		"blaster":
			return ["blaster", -6.0]
		"shotgun":
			return ["shotgun", -3.0]
		"grenade":
			return ["grenade", -4.0]
		"rail":
			return ["rail", -1.0]
		"minigun":
			return ["shot", -9.0]
	return ["shot", -5.0]


# цель для бота: вражеские постройки по порядку его линии, потом турели базы и штаб
func objective_for(team: int, lane: String) -> Node3D:
	var enemy := 1 - team
	var order := [["turret_t1", lane], ["turret_t2", lane], ["turret_t3", ""], ["core", ""], ["hq", ""]]
	for step in order:
		var best: Node3D = null
		var best_d := 1e9
		for s in get_tree().get_nodes_in_group("structures"):
			if s.dead or s.team != enemy or s.id != step[0]:
				continue
			if step[1] != "" and s.get_meta("lane", "") != step[1]:
				continue
			var d: float = s.global_position.distance_to(base_center(team))
			if d < best_d:
				best_d = d
				best = s
		if best != null:
			return best
	return null


# линия глазами команды: точки от своей базы к вражеской
func lane_path(team: int, lane: String) -> PackedVector3Array:
	if lanes.is_empty():
		return PackedVector3Array()
	var p: PackedVector3Array = lanes.get(lane, lanes.values()[0])
	if team == 0:
		return p
	var r := PackedVector3Array()
	for i in range(p.size() - 1, -1, -1):
		r.append(p[i])
	return r


# ближайшая к боту точка его линии впереди (бот сначала выходит на линию, потом идёт по ней)
func lane_waypoint(team: int, lane: String, pos: Vector3) -> Vector3:
	var p := lane_path(team, lane)
	if p.is_empty():
		return pos
	var best_i := 0
	var best_d := 1e9
	for i in p.size():
		var d := p[i].distance_to(pos)
		if d < best_d:
			best_d = d
			best_i = i
	# уже у точки или прошёл её дальше к следующей: идём к следующей
	if best_i < p.size() - 1:
		var nxt := p[best_i + 1]
		if best_d < 10.0 or pos.distance_to(nxt) < p[best_i].distance_to(nxt):
			return nxt
	return p[best_i]


# ------------------------------------------------------------------
#  КРИПЫ: волна на каждую линию у каждой команды
# ------------------------------------------------------------------

func _update_creeps(delta: float) -> void:
	if pvp or not started or winner >= 0 or Cfg.creeps_enabled != 1:
		return
	_creep_t -= delta
	if _creep_t > 0.0:
		return
	_creep_t = Cfg.creep_interval
	for team in 2:
		if _hq[team] == null or _hq[team].dead:
			continue
		for lane in lanes:
			var path := lane_path(team, lane)
			if path.size() < 2:
				continue
			for k in Cfg.creep_per_lane:
				# выезжают по очереди, чтобы не родиться друг в друге
				get_tree().create_timer(0.7 * k, false).timeout.connect(_spawn_creep.bind(team, lane, k))


func _spawn_creep(team: int, lane: String, k: int) -> void:
	if winner >= 0:
		return
	# страховка: если крипы где-то застряли и копятся, новые не выезжают (каждый крип стоит процессору)
	var on_lane := 0
	for c0 in get_tree().get_nodes_in_group("creeps"):
		if c0.team == team and c0.lane == lane and not c0.dead:
			on_lane += 1
	if on_lane >= Cfg.creep_max_lane:
		return
	var path := lane_path(team, lane)
	var c := Creep.new()
	c.team = team
	c.lane = lane
	c.path = path
	c.nav = nav
	c.slot = k
	var start := path[0]
	var dir := (path[1] - path[0])
	dir.y = 0
	dir = dir.normalized()
	start += dir * 9.0
	var perp := Vector3(-dir.z, 0, dir.x)
	start += perp * (float(k % 3) - 1.0) * 2.5
	if not _spot_free(start, 1.2):
		start = path[0] + dir * 12.0
	c.position = Vector3(start.x, 0, start.z)
	add_child(c)


# ------------------------------------------------------------------
#  СМЕРТЬ, ОБЛОМКИ, ПРИПАСЫ
# ------------------------------------------------------------------

func _on_mech_died(who: Node3D) -> void:
	if who == mech:
		deaths += 1
		_player_respawn = Cfg.respawn_time
	else:
		if who.team != mech.team:
			kills += 1
		who.set_meta("respawn", Cfg.bot_respawn)
	# PvP: каждая смерть меха — очко команде противника (счёт смотрит _update_pvp)
	if pvp and winner < 0:
		team_kills[1 - who.team] += 1
	# обломок: забирает модель меха, едет по инерции, оседает и дымит
	var w := Wreck.new()
	w.setup_wreck(who.detach_visual(), who.death_velocity, who.stats.get("weight", 60.0), who.get_hit_radius(), who.get_hit_height() * 0.7)
	add_child(w)
	w.global_position = Vector3(who.global_position.x, 0, who.global_position.z)
	Mech.snap_interpolation(w)
	w.start()


func spawn_loot(pos: Vector3, count: int, from_crate := false) -> void:
	var kinds := ["energy", "ammo", "charge"]
	var first := randi() % kinds.size()
	for i in count:
		var p := Pickup.new()
		p.kind = kinds[(first + i) % kinds.size()] if from_crate else kinds.pick_random()
		var spot := Vector3(pos.x, 0, pos.z)
		if count > 1:
			for attempt in 6:
				var a := randf() * TAU
				var r := randf_range(0.8, 2.5)
				var cand := Vector3(pos.x + cos(a) * r, 0, pos.z + sin(a) * r)
				if _spot_free(cand):
					spot = cand
					break
		add_child(p)
		p.global_position = spot
		p.reset_physics_interpolation()


# свободно ли место (не в стене и не в постройке)
func _spot_free(p: Vector3, r := 0.7) -> bool:
	var q := PhysicsShapeQueryParameters3D.new()
	var sh := SphereShape3D.new()
	sh.radius = r
	q.shape = sh
	q.transform = Transform3D(Basis(), p + Vector3.UP * maxf(r, 1.0))
	q.collision_mask = 1 | 32
	return get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()


# ящики с припасами: сначала метка, потом падает ящик
func _update_crates(delta: float) -> void:
	if winner >= 0 or map["crates"].is_empty() or not started:
		return
	if _crate_spot != null:
		_crate_warn -= delta
		if _crate_warn <= 0.0:
			var c := Wreck.new()
			c.setup_crate()
			add_child(c)
			c.global_position = _crate_spot
			c.reset_physics_interpolation()
			c.start()
			_crate_spot = null
		return
	_crate_t -= delta
	if _crate_t > 0.0:
		return
	_crate_t = _crate_every()
	var spot: Array = map["crates"].pick_random()
	_crate_spot = Vector3(float(spot[0]), 0, float(spot[1]))
	_crate_warn = Cfg.crate_warning
	_crate_marker = Fx.ground_marker(_crate_spot, 3.0, Color(1.0, 0.8, 0.25), -1, Cfg.crate_warning + 0.3, false)


func crate_warning_pos():
	return _crate_spot


# как часто падают ящики: в PvP чаще (баз нет, патроны пополнять негде)
func _crate_every() -> float:
	return Cfg.pvp_crate_interval if pvp else Cfg.crate_interval


# на своей базе мех чинится и пополняет патроны и заряды
func _update_base(delta: float) -> void:
	for m in get_tree().get_nodes_in_group("mechs"):
		if m.dead:
			continue
		var d: Vector3 = m.global_position - base_center(m.team)
		d.y = 0
		if d.length() > Cfg.base_radius:
			_base_charge.erase(m.get_instance_id())
			continue
		m.heal(Cfg.base_heal * delta)
		m.add_ammo(Cfg.base_refill * delta)
		if Cfg.base_charge_time > 0.0:
			var id: int = m.get_instance_id()
			var t: float = _base_charge.get(id, 0.0) + delta
			if t >= Cfg.base_charge_time:
				t = 0.0
				m.add_charge(1)
			_base_charge[id] = t


# ------------------------------------------------------------------
#  ПОСТРОЙКИ И ПОБЕДА
# ------------------------------------------------------------------

func _build_structures() -> void:
	if pvp:
		return       # в PvP нет турелей, штабов и ядер
	for s in map["structures"]:
		var team := int(s[1])
		var st := Structure.new()
		st.id = s[0]
		st.team = team
		st.tier = 0 if s[0] == "hq" else int(String(s[0]).right(1))
		st.set_meta("lane", s[4] if s.size() > 4 else "mid")
		st.position = Vector3(float(s[2]), 0, float(s[3]))
		add_child(st)
		# смотрит в сторону врага
		st.rotation.y = _face_yaw(team)
		st.destroyed.connect(_on_structure_destroyed)
		st.ruin_cleared.connect(_on_ruin_cleared)
		if s[0] == "hq":
			_hq[team] = st
			_build_cores(st)


# ------------------------------------------------------------------
#  ПРОВОДА ПО ЗЕМЛЕ (Саня, 16.10.2026): от штаба к каждой турели своей команды. Идут вдоль линии сбоку
#  от дороги, чуть виляют, местами уходят под землю (как присыпало). Тёмный кабель с тонкой жилой
#  цвета команды, по ней от базы к турели медленно бегут огоньки. Одна модель на команду; темнеет в тумане
# ------------------------------------------------------------------

const CABLE_SHADER := """shader_type spatial;
render_mode cull_disabled;
uniform vec4 glow : source_color = vec4(1.0, 0.55, 0.15, 1.0);
uniform sampler2D fog_tex : filter_linear, repeat_disable;
uniform vec4 fog_rect = vec4(-120.0, -70.0, 240.0, 140.0);
uniform float fog_dark = 0.0;
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	float across = abs(UV.y - 0.5) * 2.0;                    // 0 — гребень кабеля, 1 — край
	float core = 1.0 - smoothstep(0.08, 0.3, across);
	float run = pow(0.5 + 0.5 * sin(UV.x * 0.35 - TIME * 2.2), 8.0);   // огоньки бегут от базы к турели
	float vis = texture(fog_tex, (wpos.xz - fog_rect.xy) / fog_rect.zw).r;
	float dark = 1.0 - fog_dark * (1.0 - vis);
	ALBEDO = vec3(0.045, 0.042, 0.04) * dark;
	ROUGHNESS = 0.55;
	EMISSION = glow.rgb * core * (0.35 + 1.2 * run) * dark;
}
"""


func _build_cables() -> void:
	if pvp:
		return
	var sh := Shader.new()
	sh.code = CABLE_SHADER
	for team in 2:
		var hq = _hq[team]
		if hq == null:
			continue
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var n := 0
		for s in get_tree().get_nodes_in_group("structures"):
			if s.team != team or s.id == "hq" or s.id == "core":
				continue
			_cable_strip(st, _cable_route(hq.position, s.position, String(s.get_meta("lane", "")), team, n), n)
			n += 1
		if n == 0:
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		var m := ShaderMaterial.new()
		m.shader = sh
		var c: Color = Cfg.player_color if team == 0 else Cfg.enemy_color
		m.set_shader_parameter("glow", c)
		vision.register_material(m)
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)


# путь провода: от края штаба вдоль своей линии (сбоку от дороги) до турели; к турелям у базы — напрямую
func _cable_route(from: Vector3, to: Vector3, lane: String, team: int, k: int) -> PackedVector3Array:
	var pts := PackedVector3Array()
	var path := lane_path(team, lane) if lanes.has(lane) else PackedVector3Array()
	pts.append(from)
	if path.size() >= 2:
		# точки линии, пока не дошли до турели
		var best := 0
		for i in path.size():
			if path[i].distance_to(to) < path[best].distance_to(to):
				best = i
		var side := 4.2 + 0.4 * k
		for i in range(1, best):
			var a := path[maxi(i - 1, 0)]
			var b := path[mini(i + 1, path.size() - 1)]
			var dir := (b - a).normalized()
			pts.append(path[i] + Vector3(-dir.z, 0, dir.x) * side)
	pts.append(to)
	# с края штаба и до основания турели, а не из середины
	var out := PackedVector3Array()
	var start := from + (pts[1] - from).normalized() * 7.5
	var end := to + (pts[pts.size() - 2] - to).normalized() * 2.6
	pts[0] = start
	pts[pts.size() - 1] = end
	# ровный шаг 0,5 м и лёгкое виляние
	var d := 0.0
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var seg := Vector3(b.x - a.x, 0, b.z - a.z)
		var seg_len := seg.length()
		if seg_len < 0.01:
			continue
		var dir := seg / seg_len
		var perp := Vector3(-dir.z, 0, dir.x)
		var m := int(seg_len / 0.5) + 1
		for j in m:
			var t := float(j) / m
			var wig := sin((d + seg_len * t) * 0.17 + k * 1.3) * 0.5
			out.append(a.lerp(b, t) + perp * wig)
		d += seg_len
	out.append(end)
	return out


# кабель лентой с гребнем (три вершины поперёк); UV.x — метры от штаба (для бегущих огоньков).
# Местами (по плавному шуму) опускается под землю и снова выходит
func _cable_strip(st: SurfaceTool, pts: PackedVector3Array, k: int) -> void:
	var w := 0.12
	var d := 0.0
	var rows: Array = []
	for i in pts.size():
		var a := pts[maxi(i - 1, 0)]
		var b := pts[mini(i + 1, pts.size() - 1)]
		var dir := Vector3(b.x - a.x, 0, b.z - a.z).normalized()
		var perp := Vector3(-dir.z, 0, dir.x)
		if i > 0:
			d += pts[i].distance_to(pts[i - 1])
		var h := sin(d * 0.09 + k * 2.1) * 0.6 + sin(d * 0.23 + k * 0.7) * 0.4
		var y := lerpf(0.04, -0.25, smoothstep(0.45, 0.7, h))      # под землёй, где шум высокий
		if i < 4 or i > pts.size() - 5:
			y = 0.04                                           # у штаба и у турели кабель всегда виден
		var c := Vector3(pts[i].x, y, pts[i].z)
		rows.append([c - perp * w, c + Vector3(0, 0.09, 0), c + perp * w, d])
	for i in rows.size() - 1:
		var r0: Array = rows[i]
		var r1: Array = rows[i + 1]
		for side in 2:
			var quad := [[r0[side], 0.5 * side], [r0[side + 1], 0.5 * side + 0.5], [r1[side + 1], 0.5 * side + 0.5], [r1[side], 0.5 * side]]
			var dists := [r0[3], r0[3], r1[3], r1[3]]
			var nrm: Vector3 = (quad[1][0] - quad[0][0]).cross(quad[3][0] - quad[0][0]).normalized()
			if nrm.y < 0.0:
				nrm = -nrm
			for idx in [0, 1, 2, 0, 2, 3]:
				st.set_normal(nrm)
				st.set_uv(Vector2(dists[idx], quad[idx][1]))
				st.add_vertex(quad[idx][0])


# ядра штаба: по бокам от главного здания (поперёк направления на врага), чуть вперёд.
# Пока стоит хоть одно ядро, на штабе защитный барьер
func _build_cores(hq: Node3D) -> void:
	var team: int = hq.team
	var fwd := (base_center(1 - team) - base_center(team))
	fwd.y = 0
	fwd = fwd.normalized()
	var side := Vector3(-fwd.z, 0, fwd.x)
	for k in [-1.0, 1.0]:
		var c := Structure.new()
		c.id = "core"
		c.team = team
		c.tier = 4
		c.set_meta("lane", "base")
		c.position = _core_spot(hq.position, fwd, side * k)
		add_child(c)
		c.rotation.y = _face_yaw(team)
		c.destroyed.connect(_on_structure_destroyed)
		c.ruin_cleared.connect(_on_ruin_cleared)


# место для ядра: сбоку от штаба, но не на линии (иначе крипы упираются в ядро и копятся у базы).
# Начинаем с точки из настроек и поворачиваем вокруг штаба, пока линии и постройки не окажутся далеко
func _core_spot(hq_pos: Vector3, fwd: Vector3, side: Vector3) -> Vector3:
	var off := Parts.v("core", "offset")
	var want := side * off + fwd * Parts.v("core", "forward")
	var base_ang := atan2(want.z, want.x)
	var r := want.length()
	var turn := 1.0 if side.cross(fwd).y < 0.0 else -1.0     # сначала крутим назад, от врага
	var rect := map_rect().grow(-4.0)
	var best := hq_pos + want
	var best_score := -1e9
	for step in 13:
		for dir in ([1.0] if step == 0 else [turn, -turn]):
			var a: float = base_ang + dir * deg_to_rad(15.0) * step
			var p := hq_pos + Vector3(cos(a), 0, sin(a)) * r
			if not rect.has_point(Vector2(p.x, p.z)):
				continue
			var clear := _lane_clearance(p)
			for st in get_tree().get_nodes_in_group("structures"):
				clear = minf(clear, st.position.distance_to(p) - (8.0 if st.id == "hq" else 6.0))
			if clear >= 7.0:
				return p
			if clear > best_score:
				best_score = clear
				best = p
	return best


# расстояние от точки до ближайшей линии (по которым едут крипы)
func _lane_clearance(p: Vector3) -> float:
	var best := 1e9
	for ln in lanes.values():
		for i in ln.size() - 1:
			var a: Vector3 = ln[i]
			var b: Vector3 = ln[i + 1]
			var ab := Vector3(b.x - a.x, 0, b.z - a.z)
			var ap := Vector3(p.x - a.x, 0, p.z - a.z)
			var t := clampf(ap.dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
			best = minf(best, (ap - ab * t).length())
	return best


func _structure_boxes() -> Array:
	var out: Array = []
	for s in get_tree().get_nodes_in_group("structures"):
		if s.cleared:
			continue
		var size := 8.0 if s.id == "hq" else 3.2
		out.append([s.position.x, s.position.z, size, 6.0, size])
	return out


# препятствия для ботов: укрытия (кроме разрушенных стен), постройки, украшения
func _nav_boxes() -> Array:
	var out: Array = []
	for c in covers:
		var kind: String = c[5] if c.size() > 5 else "wall"
		if kind != "rock":
			continue
		out.append(c)
	for w in walls:
		if not w.is_destroyed():
			out.append(w.box())
	for b in get_tree().get_nodes_in_group("barricades"):
		out.append(b.box())
	return out + _static_boxes


# баррикаду поставили или сломали: пересчитать проходимость вокруг неё
func obstacle_changed(area: Rect2) -> void:
	if nav != null:
		nav.refresh(area, _nav_boxes())


func structures_left(team: int) -> int:
	var n := 0
	for s in get_tree().get_nodes_in_group("structures"):
		if s.team == team and not s.dead and s.id != "hq" and s.id != "core":
			n += 1
	return n


# развалину турели разбили: убрать её из препятствий для ботов
func _on_ruin_cleared(s: Node3D) -> void:
	_static_boxes = _structure_boxes() + art.decor_boxes
	nav.refresh(Rect2(s.position.x - 3.0, s.position.z - 3.0, 6.0, 6.0), _nav_boxes())
	if minimap != null:
		minimap.redraw(self)


func _on_structure_destroyed(s: Node3D) -> void:
	if s.id == "hq" and winner < 0:
		_finish(1 - s.team)


# конец боя: надпись, через пару секунд пауза и таблица. w: команда-победитель или 2 (ничья)
func _finish(w: int) -> void:
	winner = w
	Battle.running = false
	var draw := w == 2
	hud.show_game_over(winner == mech.team, draw)
	get_tree().create_timer(2.5, false).timeout.connect(func() -> void:
		get_tree().paused = true
		menu.show_results(winner == mech.team, draw))


# PvP: победа, когда команда набрала нужное число убийств; когда вышло время — у кого больше
func _update_pvp() -> void:
	if not pvp or not started or winner >= 0:
		return
	for team in 2:
		if team_kills[team] >= Cfg.pvp_kills_to_win:
			_finish(team)
			return
	if time_left() <= 0.0:
		var a: int = team_kills[0]
		var b: int = team_kills[1]
		_finish(0 if a > b else (1 if b > a else 2))


# PvP: сколько секунд осталось до конца боя
func time_left() -> float:
	return maxf(Cfg.pvp_time * 60.0 - Battle.time, 0.0)


# стену сломали: боты могут ходить сквозь, туман и миникарта обновляются
func _on_wall_destroyed(w: Node3D) -> void:
	var b: Array = w.box()
	nav.refresh(Rect2(b[0] - b[2] * 0.5, b[1] - b[4] * 0.5, b[2], b[4]), _nav_boxes())
	vision.invalidate_static()
	if minimap != null:
		minimap.redraw(self)


# ------------------------------------------------------------------
#  ИГРОК: звуки, тряска
# ------------------------------------------------------------------

func _on_fired(mount: int) -> void:
	var look: String = mech.weapons[mount]["look"]
	var s := _shot_sound(look)
	Sfx.play_at(s[0], mech.global_position, s[1], 0.06)
	var k := 1.0
	match look:
		"heavy", "rail":
			k = 4.0
		"shotgun", "grenade":
			k = 2.5
		"minigun":
			k = 0.4
	cam.shake(Cfg.shake_shot * k)


# сборка из ангара: мех пересобирается на месте с полным здоровьем и боезапасом
func _on_build_applied(b: Dictionary) -> void:
	Parts.set_player_build(b)
	mech.set_build(b)
	Battle.set_mech(mech, Parts.pname(b.get("mech", "")))
	if not started:
		start_battle(autotest_running() == false)
		return
	if not mech.dead and not mech.is_landing():
		mech.respawn(mech.global_position, false)


func autotest_running() -> bool:
	return not OS.get_cmdline_user_args().is_empty()


func _on_dashed() -> void:
	Sfx.play_at("dash", mech.global_position, -3.0, 0.05)
	cam.shake(Cfg.shake_dash)


func _on_stepped(_pos: Vector3) -> void:
	var speed := Vector2(mech.velocity.x, mech.velocity.z).length()
	var k := clampf(speed / maxf(mech.run_speed(), 0.1), 0.0, 1.0)
	Sfx.play_at("step", mech.global_position, -13.0 + 5.0 * k + 3.0 * (mech.stats["legs_scale"] - 1.0) * 4.0, 0.1)
	cam.shake(Cfg.shake_step * (0.5 + k) * mech.stats["legs_scale"])


func _on_player_landed() -> void:
	cam.shake(Cfg.shake_explosion * 0.8)


func _on_denied(_index: int, reason: String) -> void:
	if reason == "ammo":
		Sfx.play("click", -4.0, 0.05)
	else:
		Sfx.play("deny", -8.0, 0.0)


# по тебе попали: тряска по силе урона, но не чаще нескольких раз в секунду
# (лазер бьёт каждый кадр понемногу, раньше это трясло камеру без остановки)
func _on_player_damaged(amount: float) -> void:
	_hit_shake_acc += amount
	if _hit_shake_t > 0.0:
		return
	var k := clampf(_hit_shake_acc / maxf(mech.max_hp() * 0.08, 1.0), 0.25, 1.5)
	cam.shake(Cfg.shake_hit * k)
	_hit_shake_acc = 0.0
	_hit_shake_t = 0.15


func respawn_left() -> float:
	return maxf(_player_respawn, 0.0) if mech.dead else 0.0


# взрыв трясёт камеру тем слабее, чем дальше он от меха
func _on_shake_at(pos: Vector3, amount: float) -> void:
	var d := pos.distance_to(mech.global_position)
	cam.shake(amount * clampf(1.0 - d / 45.0, 0.15, 1.0))


# ------------------------------------------------------------------
#  КАРТА
# ------------------------------------------------------------------

func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.06, 0.07)
	# мягкий рассеянный свет: сверху холодный, как от неба (тени холодные, солнце тёплое)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.52, 0.54, 0.6)    # солнце сзади: стороны к камере освещает небо, не слишком синее
	env.ambient_light_energy = 1.6     # киношная цветопередача сильно давит тёмное: без этого тени чёрные
	# затенение в углах и под предметами: всё «стоит» на земле (только на высокой графике)
	env.ssao_enabled = Cfg.graphics == 2
	env.ssao_radius = 1.6
	env.ssao_intensity = 1.2
	env.ssao_power = 1.4
	# киношная цветопередача и свечение ярких огней (полосы, трассеры, взрывы)
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.15
	env.tonemap_white = 6.0
	env.glow_enabled = Cfg.graphics >= 1     # на низкой графике свечения нет
	env.glow_intensity = 0.7
	env.glow_strength = 1.0
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 0.9
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.08
	env.adjustment_saturation = 1.25
	# дымки нет: лоу-поли картинка должна быть чистой на любой высоте камеры
	env.fog_enabled = false
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	# солнце: тёплое, низкое (вечер), с дальней стороны карты (контровой свет, как в цели docs/targets):
	# тени ложатся к камере, лужи и влажная земля ловят блик
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-34, 150, 0)
	sun.light_energy = 1.75
	sun.light_color = Color(1.0, 0.9, 0.76)
	sun.shadow_enabled = true
	sun.shadow_blur = 1.5
	sun.shadow_opacity = 0.78     # тень не чёрная: в ней видно землю и траву
	sun.directional_shadow_max_distance = 160.0
	# средняя графика: 2 слоя теней до 120 м, низкая: 1 слой до 100 м (высокая — 4 слоя и 160 м, как решил Саня)
	if Cfg.graphics == 1:
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		sun.directional_shadow_split_1 = 0.5
		sun.directional_shadow_max_distance = 120.0
	elif Cfg.graphics == 0:
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
		sun.directional_shadow_max_distance = 100.0
	add_child(sun)
	# слабая подсветка с противоположной стороны, чтобы тени не были чёрными
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-35, -30, 0)
	fill.light_energy = 0.4
	fill.light_color = Color(0.72, 0.7, 0.68)
	add_child(fill)


# мелкая пыль, медленно плывущая в воздухе: добавляет глубины картинке
func _build_motes() -> void:
	_motes = CPUParticles3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.08
	sm.height = 0.16
	sm.radial_segments = 4
	sm.rings = 2
	_motes.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	_motes.material_override = mat
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.95, 0.8, 0.0))
	ramp.add_point(0.3, Color(1.0, 0.95, 0.8, 0.45))
	ramp.add_point(0.7, Color(1.0, 0.95, 0.8, 0.45))
	ramp.set_color(ramp.get_point_count() - 1, Color(1.0, 0.95, 0.8, 0.0))
	_motes.color_ramp = ramp
	_motes.amount = 160
	_motes.lifetime = 7.0
	_motes.preprocess = 7.0
	_motes.local_coords = false
	_motes.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_motes.emission_box_extents = Vector3(45, 3, 30)
	_motes.direction = Vector3(1, 0.2, 0.3)
	_motes.spread = 40.0
	_motes.gravity = Vector3.ZERO
	_motes.initial_velocity_min = 0.3
	_motes.initial_velocity_max = 1.0
	_motes.scale_amount_min = 0.6
	_motes.scale_amount_max = 1.6
	_motes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_motes)
	_motes.emitting = true      # облако ездит за игроком на высоте 3.5 м (см. _process)


# маска земли (1 пиксель = 1 метр): красный - дороги по линиям, зелёный - площадки баз, синий - площадки точек
func _ground_mask() -> Image:
	var r := map_rect()
	var w := int(r.size.x)
	var h := int(r.size.y)
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	img.fill(Color.BLACK)
	var stamp := func(p: Vector3, radius: float, ch: int) -> void:
		var cx := p.x - r.position.x
		var cz := p.z - r.position.y
		for y in range(maxi(int(cz - radius) - 1, 0), mini(int(cz + radius) + 2, h)):
			for x in range(maxi(int(cx - radius) - 1, 0), mini(int(cx + radius) + 2, w)):
				var d := Vector2(x + 0.5 - cx, y + 0.5 - cz).length()
				if d <= radius:
					var c := img.get_pixel(x, y)
					c[ch] = 1.0
					img.set_pixel(x, y, c)
	for lane in lanes:
		var path: PackedVector3Array = lanes[lane]
		for i in path.size() - 1:
			var a := path[i]
			var b := path[i + 1]
			var n := int(a.distance_to(b) / 1.5) + 1
			for k in n + 1:
				stamp.call(a.lerp(b, float(k) / n), 5.0, 0)
	for team in 2:
		stamp.call(base_center(team), 12.0 if pvp else 23.0, 1)     # в PvP — площадка у точки появления
	for p in map["pois"]:
		stamp.call(Vector3(float(p[0]), 0, float(p[1])), 10.5, 2)
	# лёгкое размытие: края мягче (уменьшить и растянуть обратно)
	img.resize(maxi(w / 3, 1), maxi(h / 3, 1), Image.INTERPOLATE_BILINEAR)
	img.resize(w, h, Image.INTERPOLATE_BILINEAR)
	return img


# где на земле сухая грязь, грунт и камни (1 пиксель = 1 метр; красный, зелёный, синий; остальное трава).
# По ней шейдер земли смешивает текстуры, а пучки травы растут только на траве
func _ground_biome() -> Image:
	var r := map_rect()
	var w := int(r.size.x)
	var h := int(r.size.y)
	var noise: Array[Image] = []
	for k in 3:
		var n := FastNoiseLite.new()
		n.seed = 11 + k * 17
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		n.frequency = [0.03, 0.06, 0.045][k]
		n.fractal_octaves = 3
		noise.append(n.get_image(w, h))
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	for y in h:
		for x in w:
			img.set_pixel(x, y, Color(smoothstep(0.6, 0.7, noise[0].get_pixel(x, y).r),
				smoothstep(0.6, 0.7, noise[1].get_pixel(x, y).r),
				smoothstep(0.74, 0.8, noise[2].get_pixel(x, y).r)))
	return img


# лужи (4 пикселя на единицу карты): раскладываются вдоль дорог через 9–18 м и немного на сухой
# грязи; каждая из 2–4 кругов. Список луж [x, z, радиус] — в puddles: по нему трава в лужах не растёт
func _ground_wet(mask: Image, biome: Image) -> Image:
	var r := map_rect()
	var k := 4.0
	var w := int(r.size.x * k)
	var h := int(r.size.y * k)
	var img := Image.create(w, h, false, Image.FORMAT_R8)
	var put := func(x: int, y: int, ch: int, v: float) -> void:
		if x < 0 or y < 0 or x >= w or y >= h:
			return
		var c := img.get_pixel(x, y)
		if v > c[ch]:
			c[ch] = v
			img.set_pixel(x, y, c)
	var on_pad := func(p: Vector3) -> bool:
		var c := mask.get_pixel(clampi(int(p.x - r.position.x), 0, mask.get_width() - 1), clampi(int(p.z - r.position.y), 0, mask.get_height() - 1))
		return c.g > 0.15 or c.b > 0.15
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	var spots: Array = []
	for lane in lanes:
		var path: PackedVector3Array = lanes[lane]
		var dist := 0.0
		var next_puddle := rng.randf_range(4.0, 12.0)
		for i in path.size() - 1:
			var a := path[i]
			var b := path[i + 1]
			var seg := a.distance_to(b)
			var side := Vector3(-(b.z - a.z), 0, b.x - a.x) / maxf(seg, 0.001)
			var n := int(seg / 0.25) + 1
			for s in n:
				var d := dist + seg * s / n
				var c0 := a.lerp(b, float(s) / n)
				if d >= next_puddle:
					next_puddle = d + rng.randf_range(9.0, 18.0)
					var at: Vector3 = c0 + side * rng.randf_range(-2.2, 2.2)
					if not on_pad.call(at):
						spots.append([at, rng.randf_range(0.9, 1.9)])
			dist += seg
	for i in 60:
		var at := Vector3(rng.randf_range(r.position.x + 4, r.end.x - 4), 0, rng.randf_range(r.position.y + 4, r.end.y - 4))
		var bc := biome.get_pixel(clampi(int(at.x - r.position.x), 0, biome.get_width() - 1), clampi(int(at.z - r.position.y), 0, biome.get_height() - 1))
		if bc.r > 0.7 and not on_pad.call(at):
			spots.append([at, rng.randf_range(0.6, 1.3)])
	puddles = []
	for sp in spots:
		var center: Vector3 = sp[0]
		var size: float = sp[1]
		for q in rng.randi_range(2, 4):
			var cc := center + Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)) * size * 0.7
			var rad := size * rng.randf_range(0.55, 1.0)
			puddles.append(Vector3(cc.x, rad, cc.z))
			var cx := (cc.x - r.position.x) * k
			var cz := (cc.z - r.position.y) * k
			var rp := rad * k
			for y in range(int(cz - rp) - 1, int(cz + rp) + 2):
				for x in range(int(cx - rp) - 1, int(cx + rp) + 2):
					var dd := Vector2(x + 0.5 - cx, y + 0.5 - cz).length() / rp
					if dd < 1.0:
						put.call(x, y, 0, 1.0 - smoothstep(0.45, 1.0, dd))
	return img


# колеи вдоль линий (пара полос от колёс посередине и пара слабее по краям, чуть виляют).
# По ним шейдер земли считает рельеф, поэтому маска гладкая: полосы рисуются вдвое мельче
# (16 пикселей на единицу карты), потом уменьшаются с усреднением и размываются; итог — 8 пикселей
# на единицу. Квадрат-штамп подбирается под направление линии, чтобы косая полоса была не шире прямой
func _ground_ruts() -> Image:
	var r := map_rect()
	var k := 8.0
	while r.size.x * r.size.y * k * k * 4.0 > 4.0e7 and k > 2.0:      # огромная карта — маска грубее
		k *= 0.5
	var kk := k * 2.0
	var w := int(r.size.x * kk)
	var h := int(r.size.y * kk)
	var img := Image.create(w, h, false, Image.FORMAT_R8)
	# сначала слабые крайние полосы всех линий, потом сильные средние: где линии сходятся, средние главнее
	for pass_i in 2:
		var ruts: Array = [[-2.7, 1.7, 0.55], [2.7, 1.7, 0.55]] if pass_i == 0 else [[-1.3, 0.0, 1.0], [1.3, 0.0, 1.0]]
		for lane in lanes:
			var path: PackedVector3Array = lanes[lane]
			var dist := 0.0
			for i in path.size() - 1:
				var a := path[i]
				var b := path[i + 1]
				var seg := a.distance_to(b)
				var dir := (b - a) / maxf(seg, 0.001)
				var side := Vector3(-dir.z, 0, dir.x)
				var px_side := 0.42 * kk / (absf(side.x) + absf(side.z))      # ширина полосы 0,42 единицы
				var n := int(seg / 0.08) + 1
				for s in n:
					var d := dist + seg * s / n
					var c0 := a.lerp(b, float(s) / n)
					for t in ruts:
						var p: Vector3 = c0 + side * (float(t[0]) + sin(d * 0.12 + float(t[1])) * 0.35)
						var cx := (p.x - r.position.x) * kk
						var cz := (p.z - r.position.y) * kk
						img.fill_rect(Rect2i(roundi(cx - px_side * 0.5), roundi(cz - px_side * 0.5), roundi(px_side), roundi(px_side)), Color(t[2], 0, 0))
				dist += seg
	# вдвое меньше с усреднением (сглаживает ступеньки), ещё вдвое меньше и обратно — мягкий край полосы
	img.resize(w / 2, h / 2, Image.INTERPOLATE_TRILINEAR)
	img.resize(w / 4, h / 4, Image.INTERPOLATE_TRILINEAR)
	img.resize(w / 2, h / 2, Image.INTERPOLATE_CUBIC)
	return img


func _build_ground() -> void:
	var r := map_rect()
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(r.size.x + 60.0, 2.0, r.size.y + 60.0)
	cs.shape = bs
	cs.position = Vector3(r.get_center().x, -1.0, r.get_center().y)
	body.add_child(cs)

	var mask := _ground_mask()
	set_meta("ground_mask", mask)
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(r.size.x + 400.0, r.size.y + 400.0)     # земля уходит далеко за край, чтобы не было видно пустоты
	mi.mesh = pm
	mi.position = Vector3(r.get_center().x, 0, r.get_center().y)
	var sm := ShaderMaterial.new()
	sm.shader = _ground_shader()
	sm.set_shader_parameter("ground_tex", ImageTexture.create_from_image(mask))
	var biome := _ground_biome()
	set_meta("ground_biome", biome)
	sm.set_shader_parameter("biome_tex", ImageTexture.create_from_image(biome))
	sm.set_shader_parameter("ruts_tex", ImageTexture.create_from_image(_ground_ruts()))
	sm.set_shader_parameter("puddle_tex", ImageTexture.create_from_image(_ground_wet(mask, biome)))
	var layers := Art.ground_arrays()
	if not layers.is_empty():
		sm.set_shader_parameter("tex_albedo", layers[0])
		sm.set_shader_parameter("tex_normal", layers[1])
		sm.set_shader_parameter("use_tex", 1.0)
	vision.register_material(sm)
	mi.material_override = sm
	body.add_child(mi)

	# круги баз на земле (в PvP баз нет)
	for team in (0 if pvp else 2):
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.97
		tm.outer_radius = 1.0
		tm.rings = 64
		ring.mesh = tm
		var rm := StandardMaterial3D.new()
		rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		var c := Cfg.player_color if team == 0 else Cfg.enemy_color
		rm.albedo_color = Color(c.r, c.g, c.b, 0.35)
		ring.material_override = rm
		ring.position = base_center(team) + Vector3.UP * 0.06
		ring.scale = Vector3(Cfg.base_radius, 0.2, Cfg.base_radius)
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(ring)


# шейдер земли под графику: на средней и низкой он проще (см. начало ground.gdshader).
# Варианты собираются один раз за запуск игры
static var _ground_shaders := {}


func _ground_shader() -> Shader:
	var define: String = Cfg.gfx("GFX_LOW", "GFX_MID", "")
	if define == "":
		return GroundShader
	if not _ground_shaders.has(define):
		var sh := Shader.new()
		sh.code = GroundShader.code.insert(GroundShader.code.find("\n") + 1, "#define %s\n" % define)
		_ground_shaders[define] = sh
	return _ground_shaders[define]


# столкновения стен и укрытий; как они выглядят, строят map_art.gd (скалы, края) и wall.gd (стены)
func _build_walls() -> void:
	var r := map_rect()
	var c0 := r.get_center()
	var hw := r.size.x * 0.5
	var hd := r.size.y * 0.5
	var edges := [
		[Vector3(c0.x, 2.5, c0.y - hd), Vector3(r.size.x + 4, 5, 2)], [Vector3(c0.x, 2.5, c0.y + hd), Vector3(r.size.x + 4, 5, 2)],
		[Vector3(c0.x - hw, 2.5, c0.y), Vector3(2, 5, r.size.y + 4)], [Vector3(c0.x + hw, 2.5, c0.y), Vector3(2, 5, r.size.y + 4)],
	]
	for e in edges:
		_block(e[0], e[1])
	art = MapArt.new()
	art.vision = vision
	art.ground_mask = get_meta("ground_mask")
	art.biome = get_meta("ground_biome")
	art.puddles = puddles
	art.mask_rect = r
	add_child(art)
	for c in covers:
		var kind: String = c[5] if c.size() > 5 else "wall"
		if kind == "rock":
			_block(Vector3(c[0], c[3] * 0.5, c[1]), Vector3(c[2], c[3], c[4]))
		else:
			var w := Wall.new()
			w.c = c
			w.art = art
			w.extra = WALL_EXTRA
			add_child(w)
			w.destroyed.connect(_on_wall_destroyed)
			walls.append(w)
	# внешний вид карты: скалы, постройки, провода, трава
	var no_grass: Array = []
	for s in map["structures"]:
		no_grass.append(Vector3(float(s[2]), 0, float(s[3])))
	for t in map["targets"]:
		no_grass.append(Vector3(float(t[0]), 0, float(t[1])))
	art.build(covers, edges, r, no_grass, map)


func _block(pos: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = pos
	body.set_meta("top", pos.y + size.y * 0.5)     # настоящая высота: граната её перелетает
	body.add_to_group("solid_tops")
	add_child(body)
	# стена для выстрелов выше, чем на вид: игра плоская, перестрелять через укрытие сверху нельзя
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(size.x, size.y + WALL_EXTRA, size.z)
	cs.shape = bs
	cs.position = Vector3(0, WALL_EXTRA * 0.5, 0)
	body.add_child(cs)
