extends Node
## ============================================================
##  ВСЕ ЦИФРЫ ИГРЫ ЛЕЖАТ ЗДЕСЬ.
##
##  Проще всего крутить их прямо в игре: клавиша F2 открывает панель с ползунками.
##  Здесь общие правила. Числа деталей меха (ноги, корпус, оружие, модули) лежат в parts.gd,
##  в панели это вкладка "Детали".
##  Изменения применяются сразу и сохраняются сами в файл tuning.cfg в папке проекта.
##  Кнопка "Сбросить всё" возвращает числа из этого файла.
##
##  Числа в этом файле это значения "по умолчанию".
##  Формат строки:  диапазон ползунка (от, до, шаг)  имя := значение   # Название | пояснение
## ============================================================


@export_group("Вес и скорость")
@export_range(0, 0.95, 0.05) var load_free := 0.4        # Порог груза | с какой доли грузоподъёмности начинается штраф. 0 = любой вес замедляет
@export_range(0.2, 1, 0.05) var load_min_speed := 0.6    # Скорость при полной загрузке | множитель ходьбы и бега, когда масса равна грузоподъёмности
@export_range(0.2, 1, 0.05) var load_accel := 0.5        # Разгон при полной загрузке | множитель разгона и торможения
@export_range(0.2, 1, 0.05) var load_dash := 0.7         # Рывок при полной загрузке | множитель скорости рывка (рывок становится короче)
@export_range(0.2, 1, 0.05) var load_turn := 0.5         # Поворот при полной загрузке | множитель поворота ног и корпуса
@export_range(0, 100, 1) var min_energy_pool := 10.0     # Минимум энергии сборки | сколько энергии должно остаться после резерва деталей

@export_group("Энергия")
@export_range(0, 60, 0.5) var run_energy_cost := 12.0    # Цена бега | единиц энергии в секунду
@export_range(0, 100, 1) var run_min_energy := 15.0      # Порог бега | если энергия кончилась, бежать снова можно только набрав столько
@export_range(0, 100, 1) var dash_energy_cost := 0.0     # Цена рывка | сколько энергии тратит рывок (0 = бесплатно)

@export_group("Твой мех")
@export_range(0.5, 30, 0.5) var respawn_time := 5.0      # Возрождение | секунд после смерти, появляешься на своей базе
@export_range(0, 10, 0.5) var spawn_shield := 2.0        # Защита после возрождения | секунд неуязвимости, мех в это время мигает

@export_group("Контроль")
@export_range(5, 200, 1) var control_mass := 70.0       # Базовая масса контроля | тонн: мех такой массы оглушается, получает ЭМИ, тянется и толкается ровно на число абилки; масса вдвое больше — вдвое слабее, вдвое меньше — вдвое сильнее

@export_group("Высадка и телепорт на базу")
@export_range(0, 6, 0.1) var drop_time := 2.2            # Время высадки | секунд падения с неба при появлении (0 = появляется сразу)
@export_range(10, 150, 1) var drop_height := 60.0        # Высота высадки | метров, откуда падает мех
@export_range(0.5, 10, 0.1) var tp_channel := 3.0        # Телепорт: время | секунд стоять на месте до прыжка на базу (T); движение и выстрел сбивают
@export_range(0, 180, 1) var tp_cooldown := 45.0         # Телепорт: перезарядка | секунд

@export_group("Вижен")
@export_range(0, 1, 0.05) var fog_darkness := 0.5        # Темнота тумана | насколько темнее всё, что твоя команда не видит
@export_range(0, 1, 0.05) var cloak_revealed := 0.55     # Раскрытый невидимка | прозрачность невидимого врага, которого засёк омни-сенсор (1 = не видно)
@export_range(0, 40, 1) var structure_vision := 0.0      # Добавка обзора построек | метров к обзору турелей и штаба (их обзор задаётся в «Постройках»)

@export_group("База и турели")
@export_range(5, 40, 1) var base_radius := 16.0          # Радиус базы | метров вокруг штаба, где мех чинится и пополняется
@export_range(0, 200, 5) var base_heal := 40.0           # Ремонт на базе | здоровья в секунду
@export_range(0, 1, 0.01) var base_refill := 0.2         # Патроны на базе | доля полного боезапаса в секунду
@export_range(0, 20, 0.5) var base_charge_time := 3.0    # Заряды на базе | секунд на один заряд расходника (0 = не пополняются)
@export_range(0, 1, 1) var hq_needs_t3 := 1              # Штаб под защитой | 1 = штаб неуязвим, пока стоит хоть одна турель 3 уровня его команды

@export_group("PvP (мехи против мехов)")
@export_range(1, 100, 1) var pvp_kills_to_win := 20      # Убийств до победы | PvP: команда, первой набравшая столько убийств, побеждает
@export_range(1, 30, 0.5) var pvp_time := 8.0            # Время боя PvP | минут; когда время вышло, побеждает команда, у которой больше убийств (поровну — ничья)
@export_range(10, 300, 5) var pvp_crate_interval := 30.0 # Ящики в PvP | раз в сколько секунд падает ящик с припасами (баз нет, патроны только из ящиков и обломков)

@export_group("Крипы")
@export_range(0, 1, 1) var creeps_enabled := 1           # Крипы | 1 = идут волнами по линиям, 0 = выключены
@export_range(0, 120, 1) var creep_first := 12.0         # Первая волна | секунд от начала боя
@export_range(5, 120, 1) var creep_interval := 30.0      # Волна каждые | секунд
@export_range(3, 60, 1) var creep_max_lane := 15            # Крипов на линии максимум | у одной команды; больше новые не выезжают
@export_range(1, 8, 1) var creep_per_lane := 3           # Крипов в волне | на каждую линию у каждой команды
@export_range(2, 12, 0.5) var creep_spacing := 5.0       # Расстояние между крипами | метров: держат дистанцию, не сбиваются в кучу
@export_range(0, 1, 0.05) var creep_loot_chance := 0.15  # Припас с крипа | шанс, что из убитого крипа выпадет припас

@export_group("Стены")
@export_range(10, 1000, 10) var wall_hp_per_m := 120.0   # Прочность стены | здоровья на метр длины (стена 20 м = 20 × это число)
@export_range(0.1, 0.9, 0.05) var wall_crack_at := 0.5   # Трещина | при какой доле здоровья стена трескается

@export_group("Обломки и припасы")
@export_range(5, 500, 5) var wreck_hp := 60.0            # Прочность обломка | урона, чтобы разбить
@export_range(1, 60, 0.5) var wreck_friction := 9.0      # Трение обломка | как быстро гаснет скольжение после смерти (тушка трётся о землю), единиц/с за секунду
@export_range(0, 1, 0.01) var wreck_drag := 0.12         # Сопротивление на скорости | чем быстрее тушка едет, тем сильнее пашет землю и кувыркается: убитый в рывке пролетает ~25 м, а не через полкарты
@export_range(0, 3, 0.05) var wreck_push := 1.0         # Толкание обломков | множитель; чем тяжелее мех относительно обломка, тем сильнее толкает
@export_range(1, 5, 1) var loot_max := 2                 # Припасов с обломка | до скольки штук выпадает (от 1)
@export_range(50, 5000, 50) var ruin_hp := 600.0         # Прочность развалины турели | урона, чтобы разбить развалину сломанной турели или ядра; бьют обе команды. Разбили — путь свободен, выпадают припасы
@export_range(0, 10, 1) var ruin_loot := 4               # Припасов с развалины турели | штук
@export_range(0, 300, 5) var loot_energy := 60.0         # Припас «энергия» | сколько энергии даёт
@export_range(0, 1, 0.05) var loot_ammo := 0.35          # Припас «патроны» | доля полного боезапаса обеих пушек
@export_range(0, 5, 1) var loot_charges := 1             # Припас «расходник» | сколько зарядов даёт случайной абилке с зарядами
@export_range(1, 6, 0.1) var pickup_radius := 2.6        # Радиус подбора | метров, наехал и подобрал

@export_group("Точки интереса")
@export_range(3, 25, 0.5) var poi_radius := 9.0          # Радиус точки | метров
@export_range(1, 30, 0.5) var poi_capture_time := 6.0    # Время захвата | секунд стоять на точке без врагов
@export_range(0, 1, 0.05) var poi_regen_bonus := 0.3     # Бонус «Реактор» | доля к восстановлению энергии всей команды-владельца
@export_range(0, 1, 0.05) var poi_damage_bonus := 0.1    # Бонус «Арсенал» | доля к урону всей команды-владельца
@export_range(0, 40, 1) var poi_vision := 12.0           # Обзор с точки | метров вижена у команды-владельца
@export_range(0.5, 15, 0.5) var poi_radar_capture := 2.0   # Радар: время захвата | секунд стоять у вышки без врагов (быстрее других точек)
@export_range(10, 90, 1) var poi_radar_range := 40.0     # Радар: обзор | метров вокруг вышки, пока у неё стоит мех команды-владельца; видно сквозь стены
@export_range(0.1, 5, 0.1) var poi_radar_grow := 0.8     # Радар: раскрытие обзора | секунд от нуля до полного круга
@export_range(0.1, 5, 0.1) var poi_radar_shrink := 0.5   # Радар: сворачивание обзора | секунд: круг сужается до нуля, когда своих у вышки нет
@export_range(0, 1, 1) var poi_radar_cloak := 1          # Радар видит невидимок | 1 = невидимки в круге радара видны, 0 = нет
@export_range(0, 100, 1) var poi_dock_heal := 25.0       # Ремонтный док: ремонт | здоровья в секунду своим мехам в круге точки
@export_range(0, 1, 0.01) var poi_dock_refill := 0.1     # Ремонтный док: патроны | доля полного боезапаса в секунду своим мехам в круге
@export_range(10, 300, 5) var crate_interval := 60.0     # Дроп припасов | раз в сколько секунд падает ящик
@export_range(0, 30, 1) var crate_warning := 8.0         # Предупреждение о дропе | секунд метка на земле до падения
@export_range(10, 1000, 10) var crate_hp := 150.0        # Прочность ящика |
@export_range(1, 10, 1) var crate_loot := 4              # Припасов в ящике | штук

@export_group("Боты")
@export_range(0, 4, 1) var bot_allies := 2               # Союзных ботов | в твоей команде
@export_range(0, 5, 1) var bot_enemies := 3              # Вражеских ботов |
@export_range(0, 1, 0.05) var bot_retreat_hp := 0.3      # Отход на базу | при какой доле здоровья бот уходит чиниться
@export_range(0.5, 30, 0.5) var bot_respawn := 5.0       # Возрождение бота | секунд после смерти
@export_range(0, 3, 0.05) var bot_damage := 0.5          # Урон ботов | множитель к урону пушек и абилок, 1 = как у тебя
@export_range(0.3, 1.5, 0.05) var bot_speed := 0.9       # Скорость ботов | множитель, 1 = как у тебя
@export_range(0, 15, 0.25) var bot_aim_error := 3.5      # Ошибка прицела | градусов, насколько бот мажет. 0 = снайпер
@export_range(0.05, 1.5, 0.05) var bot_reaction := 0.35  # Реакция бота | секунд, с каким запозданием он следит за тобой
@export_range(3, 30, 1) var bot_range_min := 10.0        # Ближняя дистанция | ближе этого бот отходит назад
@export_range(8, 40, 1) var bot_range_max := 22.0        # Дальняя дистанция | дальше этого бот идёт на сближение
@export_range(0.1, 5, 0.1) var bot_burst_time := 1.0     # Длина очереди | секунд бот стреляет
@export_range(0, 5, 0.1) var bot_burst_pause := 1.0      # Пауза между очередями | секунд бот молчит
@export_range(0, 1, 0.05) var bot_plant_chance := 0.3    # Шанс встать и целиться | как часто бот останавливается ради точности
@export_range(0, 1, 0.05) var bot_dodge_chance := 0.35   # Шанс уворота | рывок в сторону при попадании и уход из-под ракет
@export_range(0, 1, 1) var bot_use_abilities := 1        # Боты используют абилки | 1 = да, 0 = нет
@export_range(0, 15, 0.5) var bot_ability_delay := 3.0   # Пауза между абилками бота | секунд

@export_group("Камера")
@export_range(30, 90, 1) var cam_pitch := 60.0           # Наклон камеры | градусов, 90 = строго сверху
@export_range(20, 90, 1) var cam_distance := 50.0        # Высота камеры | расстояние до меха, колесо мыши меняет это же число
@export_range(15, 80, 1) var cam_fov := 35.0             # Угол обзора | меньше = более плоская картинка
@export_range(1, 40, 0.5) var cam_follow := 10.0         # Жёсткость слежения | больше = камера плотнее держится за мехом
@export_range(0, 0.6, 0.01) var cam_lookahead := 0.18    # Смещение к прицелу | 0 = камера не смещается за мышкой
@export_range(0, 20, 0.5) var cam_lookahead_max := 6.0   # Предел смещения | метров

@export_group("Тряска и отдача")
@export_range(0, 3, 0.05) var shake := 1.0               # Тряска камеры (общая) | множитель, 0 = выключить всю тряску
@export_range(0, 0.3, 0.005) var shake_shot := 0.035     # Тряска от выстрела |
@export_range(0, 0.2, 0.005) var shake_step := 0.02      # Тряска от шага |
@export_range(0, 1, 0.01) var shake_dash := 0.18         # Тряска от рывка |
@export_range(0, 2, 0.05) var shake_explosion := 0.45    # Тряска от взрыва |
@export_range(0, 1, 0.01) var shake_hit := 0.06          # Тряска от попадания по тебе |
@export_range(0, 3, 0.05) var recoil_kick := 1.0         # Откат стволов | множитель к откату каждого оружия

@export_group("Шаги (как выглядит ходьба)")
@export_range(0, 1.5, 0.05) var step_lift := 0.45        # Подъём ноги | метров
@export_range(0, 20, 0.5) var lean_deg := 6.0            # Наклон корпуса | градусов в сторону движения

@export_group("Мишени")
@export_range(10, 1000, 10) var target_hp := 100.0       # Здоровье мишени |
@export_range(0.5, 20, 0.5) var target_respawn := 3.0    # Возрождение мишени | секунд
@export_range(0, 3, 0.05) var walker_speed := 1.0        # Скорость ходячих мишеней | множитель, 0 = стоят

@export_group("Вид выстрелов")
@export_range(0, 3, 0.05) var shot_glow := 1.0          # Свечение пуль | множитель размера и яркости свечения трассеров (пули, дробь). Толщина трассера у каждой пушки — во вкладке «Детали»
@export_range(0.05, 3, 0.05) var rail_width := 0.5       # Рельса: толщина следа | метров, ширина свечения выстрела рельсотрона
@export_range(0, 3, 0.05) var rail_glow := 1.0           # Рельса: яркость следа | множитель
@export_range(0.05, 2, 0.05) var rail_fade := 0.25       # Рельса: сколько держится след | секунд
@export_range(1, 15, 0.5) var boom_size_max := 5.0       # Взрыв: размер не больше | метров огня и гари. Урон бьёт по настоящему радиусу; при большом радиусе вместо одного раздутого облака — несколько обычных взрывов по кругу

@export_group("Прочее")
@export_range(0, 1, 0.05) var sound_volume := 0.7        # Громкость звуков | от 0 до 1
@export_range(0.3, 1.2, 0.02) var mech_model_bright := 0.72  # Яркость окраски мехов из моделей | 1 = как в текстуре модели; светлый корпус на солнце уходит в белое и теряет линии, поэтому темнее. Применяется к новым мехам
@export_range(0, 3, 0.05) var flash_light := 1.0         # Свет от вспышек | множитель: насколько выстрелы, лучи, попадания и взрывы подсвечивают землю и мехов вокруг; 0 = нет. Сколько источников разом — по графике (низкие 0, средние 4, высокие 8)
@export_range(0, 1, 1) var damage_numbers := 1           # Цифры урона | 1 = показывать над целью, 0 = нет
@export_range(0, 1, 1) var link_guns := 1                # Одинаковые пушки на ЛКМ | 1 = две одинаковые пушки стреляют обе на ЛКМ по очереди (рельсы залпом), 0 = ЛКМ левая, ПКМ правая
@export_range(0, 1, 1) var step_dust := 1                # Пыль от шагов | 1 = есть, 0 = нет
@export_range(0, 1, 1) var casings := 1                  # Гильзы | 1 = автопушка, Гатлинг и тяжёлое орудие выбрасывают гильзы, 0 = нет
@export_range(0, 0.6, 0.05) var smoke_hp := 0.3          # Дым подбитого меха | ниже какой доли здоровья мех дымит и искрит
@export_range(0, 1, 1) var stun_zaps := 1                # Молнии при оглушении | 1 = оглушённый мех или крип искрит молниями, 0 = нет
@export_range(0, 50, 1) var sound_near := 10.0           # Звук: ближняя дистанция | метров от твоего меха, где звуки на полной громкости
@export_range(20, 250, 5) var sound_range := 100.0       # Звук: дальняя дистанция | метров, дальше звуков не слышно

# Цвета полосок на мехах (в панели их нет, меняются только здесь)
var player_color := Color(1.0, 0.55, 0.15)
var enemy_color := Color(1.0, 0.15, 0.12)
var mech_accent := Color(0.72, 0.7, 0.65)    # полосы и огни на мехах: у всех одинаковые, сероватые
var player_name := "Lenkin"                  # ник игрока над мехом и в таблице после боя (поля для ника в ангаре пока нет)
# масштаб мира: танк-крип длиной 2,7 единицы = 4 м, значит 1 единица игры = 1,48 м.
# Игра считает в единицах; в F2 и в ангаре расстояния и скорости показываются в метрах (× это число)
const METERS_PER_UNIT := 1.48

# полоска здоровья и ник над мехом: свой мех, союзники, враги
var bar_self := Color(0.2, 0.45, 1.0)
var bar_ally := Color(0.4, 0.9, 0.4)
var bar_enemy := Color(0.95, 0.25, 0.2)

# Графика: 0 низкие, 1 средние, 2 высокие (как задумано). Выбирается в меню «Настройки»,
# хранится отдельно от tuning.cfg (в graphics.cfg в папке игры у пользователя),
# применяется при старте боя: трава (map_art), земля, свет и тени (main), вспышки (fx)
const GFX_NAMES := ["Низкие", "Средние", "Высокие"]
const GFX_PATH := "user://graphics.cfg"
var graphics := 2

# ограничение кадров в секунду (меню «Настройки», хранится там же, в graphics.cfg; 0 — без ограничения):
# меньше кадров — меньше работы и нагрева видеокарты. Применяется сразу
const FPS_LIMITS := [60, 90, 120, 144, 0]
var fps_limit := 0


# ============================================================
#  Дальше служебный код: он собирает список чисел для панели F2
#  и сохраняет твои изменения. Трогать не нужно.
# ============================================================

var ping_hold := false  # зажата Alt+ЛКМ для метки (круговое меню): мех не стреляет, даже если Alt уже отпустили
var ui_hover := false   # мышь над панелью настроек (чтобы не стрелять сквозь неё)
var show_hitboxes := false   # показывать хитбоксы (переключается клавишей F3)

var _items: Array = []
var _defaults := {}
var _dirty := false
var _save_in := 0.0
var _persist := true


var panel: CanvasLayer        # панель F2: живёт здесь, поэтому открывается везде — в меню, в ангаре, в бою и на паузе


func _ready() -> void:
	_collect_items()
	call_deferred("_make_panel")     # после остальных глобальных (панели нужны числа деталей из Parts)
	# во время автопроверки сохранённые настройки не трогаем
	var args := OS.get_cmdline_user_args()
	_persist = args.is_empty() or args.has("--tuning-test")
	if _persist:
		_load_tuning()
		_load_graphics()
	apply_fps_limit()
	# проверки и замеры: --gfx=low|mid|high
	for a in args:
		if a.begins_with("--gfx="):
			graphics = maxi(["low", "mid", "high"].find(a.trim_prefix("--gfx=")), 0)


func persist_enabled() -> bool:
	return _persist


func tuning_path() -> String:
	return _tuning_path()


# кто-то поменял числа (панель, колесо мыши, детали): сохранить чуть позже
func mark_dirty() -> void:
	_dirty = true
	_save_in = 0.4


func _process(delta: float) -> void:
	if _dirty:
		_save_in -= delta
		if _save_in <= 0.0:
			_save_tuning()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		if _dirty:
			_save_tuning()


func get_items() -> Array:
	return _items


func get_default(key: String):
	return _defaults.get(key)


func is_changed(key: String) -> bool:
	return not is_equal_approx(float(get(key)), float(_defaults[key]))


func set_value(key: String, value: float) -> void:
	if not _defaults.has(key):
		return
	if typeof(_defaults[key]) == TYPE_INT:
		set(key, int(round(value)))
	else:
		set(key, value)
	_dirty = true
	_save_in = 0.4


func reset_value(key: String) -> void:
	if _defaults.has(key):
		set(key, _defaults[key])
		_dirty = true
		_save_in = 0.4


func reset_all() -> void:
	for key in _defaults:
		set(key, _defaults[key])
	_dirty = true
	_save_in = 0.0


func _tuning_path() -> String:
	return "res://tuning.cfg" if OS.has_feature("editor") else "user://tuning.cfg"


# земная гравитация в единицах игры (м/с² ÷ масштаб): для гранат и снарядов навесом
func gravity() -> float:
	return 9.81 / METERS_PER_UNIT


# число по пресету графики: gfx(низкие, средние, высокие)
func gfx(low, mid, high):
	return [low, mid, high][clampi(graphics, 0, 2)]


func set_graphics(q: int) -> void:
	graphics = clampi(q, 0, 2)
	_save_graphics()


func set_fps_limit(fps: int) -> void:
	fps_limit = maxi(fps, 0)
	apply_fps_limit()
	_save_graphics()


# с синхронизацией кадров (она включена) выше частоты монитора игра и так не выдаёт: такой предел
# не ставим, иначе два ограничителя спорят и кадры могут дёргаться
func apply_fps_limit() -> void:
	var hz := DisplayServer.screen_get_refresh_rate()
	var vsync := DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED
	if fps_limit <= 0 or (vsync and hz > 0.0 and fps_limit >= roundi(hz) - 1):
		Engine.max_fps = 0
	else:
		Engine.max_fps = fps_limit


func _save_graphics() -> void:
	if not _persist:
		return
	var cf := ConfigFile.new()
	cf.set_value("graphics", "preset", graphics)
	cf.set_value("graphics", "fps_limit", fps_limit)
	cf.save(GFX_PATH)


func _load_graphics() -> void:
	var cf := ConfigFile.new()
	if cf.load(GFX_PATH) == OK:
		graphics = clampi(int(cf.get_value("graphics", "preset", 2)), 0, 2)
		fps_limit = maxi(int(cf.get_value("graphics", "fps_limit", 0)), 0)


func _collect_items() -> void:
	var labels := _read_labels()
	var group := ""
	for p in get_script().get_script_property_list():
		if p["usage"] & PROPERTY_USAGE_GROUP:
			group = p["name"]
			continue
		if p["hint"] != PROPERTY_HINT_RANGE:
			continue
		var key: String = p["name"]
		var parts: PackedStringArray = p["hint_string"].split(",")
		var lab: Array = labels.get(key, [key, ""])
		_items.append({
			"name": key,
			"group": group,
			"min": float(parts[0]),
			"max": float(parts[1]),
			"step": float(parts[2]) if parts.size() > 2 else 0.01,
			"label": lab[0],
			"hint": lab[1],
			"is_int": p["type"] == TYPE_INT,
		})
		_defaults[key] = get(key)


# Русские названия берутся из пояснений после значка # в этом же файле
func _read_labels() -> Dictionary:
	var out := {}
	var src: String = get_script().source_code
	if src.is_empty():
		return out
	var re := RegEx.new()
	re.compile("^@export_range\\(.*?\\)\\s+var\\s+(\\w+)\\s*:=[^#]*#\\s*(.*)$")
	for line in src.split("\n"):
		var m := re.search(line.strip_edges())
		if m == null:
			continue
		var text := m.get_string(2)
		var bar := text.find("|")
		if bar >= 0:
			out[m.get_string(1)] = [text.substr(0, bar).strip_edges(), text.substr(bar + 1).strip_edges()]
		else:
			out[m.get_string(1)] = [text.strip_edges(), ""]
	return out


func _make_panel() -> void:
	panel = load("res://scripts/tuning_panel.gd").new()
	panel.process_mode = Node.PROCESS_MODE_ALWAYS      # работает и на паузе
	add_child(panel)


func _load_tuning() -> void:
	var cf := ConfigFile.new()
	if cf.load(_tuning_path()) != OK:
		return
	if not cf.has_section("tuning"):
		return
	for key in cf.get_section_keys("tuning"):
		if _defaults.has(key):
			var v = cf.get_value("tuning", key)
			if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
				if typeof(_defaults[key]) == TYPE_INT:
					set(key, int(v))
				else:
					set(key, float(v))


func _save_tuning() -> void:
	_dirty = false
	if not _persist:
		return
	var cf := ConfigFile.new()
	for key in _defaults:
		if is_changed(key):
			cf.set_value("tuning", key, get(key))
	var parts := get_node_or_null("/root/Parts")
	if parts != null:
		parts.write_config(cf)
	cf.save(_tuning_path())
