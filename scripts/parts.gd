extends Node
## ============================================================
##  ДЕТАЛИ МЕХА
##
##  Мех собирается из: шасси меха (ноги и корпус вместе, 10 видов), ядра,
##  двух пушек (левый и правый подвес) и модулей. Сколько модулей влезает, решает мех.
##  Модуль может давать абилку (ракеты, импульс) или пассивку.
##
##  У каждой детали две цены:
##    масса  - сумма масс не должна превышать грузоподъёмность меха,
##             а чем ближе к пределу, тем медленнее мех (правило в F2, группа "Вес и скорость");
##    резерв энергии - деталь забирает часть запаса ядра, в бою остаётся меньше.
##
##  Числа деталей удобнее всего крутить в игре: F2, вкладка "Детали".
##  Здесь лежат значения по умолчанию.
## ============================================================

const ABILITY_KEYS := [KEY_Q, KEY_E, KEY_R, KEY_F, KEY_C, KEY_V, KEY_G, KEY_X]
const ABILITY_KEY_NAMES := ["Q", "E", "R", "F", "C", "V", "G", "X"]
const SLOT_ORDER := ["mech", "core", "weapon", "module", "structure", "unit"]
const SLOT_NAMES := {"mech": "Мехи", "core": "Ядра", "weapon": "Оружие", "module": "Модули", "structure": "Постройки", "unit": "Крипы"}

const DATA := {
	# ---------------- МЕХИ (ноги и корпус вместе) ----------------
	# class: лёгкий/средний/тяжёлый; trait: особенность словами; style: как выглядит корпус (если мех из коробок);
	# model: 3D-модель из assets/mechs (если задана, мех собирается из неё)
	"mech_wasp": {"slot": "mech", "name": "Оса", "class": "Лёгкий", "style": "light", "model": "light_046748",
		"trait": "Два рывка подряд, самый быстрый",
		"weight": 20.0, "capacity": 60.0, "hp": 190.0, "hit_radius": 1.55, "vision": 40.0, "omni": 15.0, "slots": 3,
		"walk_speed": 9.0, "run_speed": 17.5, "accel": 22.0, "decel": 36.0,
		"dash_speed": 50.0, "dash_time": 0.22, "dash_cooldown": 1.6, "dash_brake": 120.0, "dash_charges": 2, "dash_ramp": 0.12,
		"legs_turn_speed": 320.0, "torso_turn_speed": 340.0,
		"stride_walk": 5.0, "stride_run": 6.0, "legs_scale": 0.85, "hull_scale": 0.8},
	"mech_hound": {"slot": "mech", "name": "Гончая", "class": "Лёгкий", "style": "scout", "model": "light_cc59ad",
		"trait": "Разведчик: дальний обзор и сильный омни-сенсор",
		"weight": 22.0, "capacity": 62.0, "hp": 210.0, "hit_radius": 1.6, "vision": 52.0, "omni": 24.0, "slots": 3,
		"walk_speed": 8.6, "run_speed": 16.5, "accel": 20.0, "decel": 34.0,
		"dash_speed": 46.0, "dash_time": 0.24, "dash_cooldown": 1.8, "dash_brake": 115.0, "dash_charges": 1, "dash_ramp": 0.12,
		"legs_turn_speed": 300.0, "torso_turn_speed": 380.0,
		"stride_walk": 5.2, "stride_run": 6.0, "legs_scale": 0.88, "hull_scale": 0.85},
	"mech_ghost": {"slot": "mech", "name": "Призрак", "class": "Лёгкий", "style": "light",
		"trait": "Энергетик: энергия +40% быстрее, абилки на 15% чаще, лишний слот",
		"weight": 22.0, "capacity": 64.0, "hp": 180.0, "hit_radius": 1.55, "vision": 40.0, "omni": 16.0, "slots": 4,
		"walk_speed": 8.4, "run_speed": 16.0, "accel": 20.0, "decel": 34.0,
		"dash_speed": 46.0, "dash_time": 0.24, "dash_cooldown": 1.8, "dash_brake": 115.0, "dash_charges": 1, "dash_ramp": 0.12,
		"legs_turn_speed": 280.0, "torso_turn_speed": 320.0, "energy_regen_mult": 1.4, "cd_mult": 0.85,
		"stride_walk": 5.2, "stride_run": 6.0, "legs_scale": 0.9, "hull_scale": 0.82},
	"mech_ray": {"slot": "mech", "name": "Скат", "class": "Средний", "style": "mid",
		"trait": "Стрелок на ходу: разброс в движении вдвое меньше",
		"weight": 30.0, "capacity": 80.0, "hp": 260.0, "hit_radius": 1.8, "vision": 38.0, "omni": 14.0, "slots": 4,
		"walk_speed": 8.2, "run_speed": 15.5, "accel": 18.0, "decel": 32.0,
		"dash_speed": 46.0, "dash_time": 0.26, "dash_cooldown": 2.0, "dash_brake": 110.0, "dash_charges": 1, "dash_ramp": 0.16,
		"legs_turn_speed": 220.0, "torso_turn_speed": 260.0, "moving_spread": 0.5,
		"stride_walk": 5.5, "stride_run": 6.1, "legs_scale": 1.0, "hull_scale": 0.92},
	"mech_assault": {"slot": "mech", "name": "Штурмовик", "class": "Средний", "style": "mid", "model": "mid_87e20",
		"trait": "Универсал: ровные числа, много слотов",
		"weight": 34.0, "capacity": 90.0, "hp": 300.0, "hit_radius": 1.9, "vision": 36.0, "omni": 14.0, "slots": 5,
		"walk_speed": 7.8, "run_speed": 14.9, "accel": 16.0, "decel": 31.0,
		"dash_speed": 46.5, "dash_time": 0.28, "dash_cooldown": 2.0, "dash_brake": 110.0, "dash_charges": 1, "dash_ramp": 0.16,
		"legs_turn_speed": 190.0, "torso_turn_speed": 220.0,
		"stride_walk": 5.7, "stride_run": 6.2, "legs_scale": 1.0, "hull_scale": 1.0},
	"mech_medic": {"slot": "mech", "name": "Механик", "class": "Средний", "style": "repair",
		"trait": "Самопочинка: вне боя чинится сам",
		"weight": 36.0, "capacity": 92.0, "hp": 320.0, "hit_radius": 1.95, "vision": 36.0, "omni": 14.0, "slots": 5,
		"walk_speed": 7.4, "run_speed": 14.0, "accel": 15.0, "decel": 30.0,
		"dash_speed": 44.0, "dash_time": 0.26, "dash_cooldown": 2.2, "dash_brake": 110.0, "dash_charges": 1, "dash_ramp": 0.16,
		"legs_turn_speed": 190.0, "torso_turn_speed": 220.0, "regen_hp": 10.0, "regen_delay": 4.0,
		"stride_walk": 5.7, "stride_run": 6.2, "legs_scale": 1.02, "hull_scale": 1.02},
	"mech_ram": {"slot": "mech", "name": "Таран", "class": "Средний", "style": "ram",
		"trait": "Рывок-таран: бьёт, отталкивает и оглушает врага",
		"weight": 42.0, "capacity": 100.0, "hp": 360.0, "hit_radius": 2.05, "vision": 34.0, "omni": 13.0, "slots": 4,
		"walk_speed": 7.0, "run_speed": 14.0, "accel": 18.0, "decel": 30.0,
		"dash_speed": 52.0, "dash_time": 0.32, "dash_cooldown": 3.0, "dash_brake": 100.0, "dash_charges": 1, "dash_ramp": 0.16,
		"legs_turn_speed": 180.0, "torso_turn_speed": 200.0, "resist_explosion": 0.15, "ram_damage": 60.0, "ram_stun": 0.6,
		"stride_walk": 5.8, "stride_run": 6.3, "legs_scale": 1.08, "hull_scale": 1.08},
	"mech_mortar": {"slot": "mech", "name": "Мортира", "class": "Тяжёлый", "style": "siege",
		"trait": "Упор: стоя на месте бьёт дальше и точнее",
		"weight": 48.0, "capacity": 115.0, "hp": 380.0, "hit_radius": 2.15, "vision": 34.0, "omni": 12.0, "slots": 6,
		"walk_speed": 5.8, "run_speed": 11.0, "accel": 12.0, "decel": 28.0,
		"dash_speed": 38.0, "dash_time": 0.26, "dash_cooldown": 3.0, "dash_brake": 90.0, "dash_charges": 1, "dash_ramp": 0.2,
		"legs_turn_speed": 160.0, "torso_turn_speed": 190.0, "brace_bonus": 0.25, "brace_time": 0.6,
		"stride_walk": 6.0, "stride_run": 6.4, "legs_scale": 1.12, "hull_scale": 1.12},
	"mech_bastion": {"slot": "mech", "name": "Бастион", "class": "Тяжёлый", "style": "bastion",
		"trait": "Бронеплиты: каждое попадание слабее на 3",
		"weight": 52.0, "capacity": 125.0, "hp": 420.0, "hit_radius": 2.25, "vision": 30.0, "omni": 12.0, "slots": 6,
		"walk_speed": 5.4, "run_speed": 10.4, "accel": 11.0, "decel": 28.0,
		"dash_speed": 36.0, "dash_time": 0.26, "dash_cooldown": 3.2, "dash_brake": 90.0, "dash_charges": 1, "dash_ramp": 0.2,
		"legs_turn_speed": 150.0, "torso_turn_speed": 160.0, "armor_flat": 3.0, "resist_stun": 0.2,
		"stride_walk": 6.0, "stride_run": 6.4, "legs_scale": 1.16, "hull_scale": 1.18},
	"mech_fortress": {"slot": "mech", "name": "Крепость", "class": "Тяжёлый", "style": "heavy", "model": "heavy_26cbe_v2",
		"trait": "Больше всех слотов, защита от взрывов и оглушения",
		"weight": 54.0, "capacity": 135.0, "hp": 460.0, "hit_radius": 2.3, "vision": 30.0, "omni": 12.0, "slots": 7,
		"walk_speed": 5.2, "run_speed": 10.0, "accel": 10.0, "decel": 27.0,
		"dash_speed": 36.0, "dash_time": 0.28, "dash_cooldown": 3.4, "dash_brake": 90.0, "dash_charges": 1, "dash_ramp": 0.2,
		"legs_turn_speed": 150.0, "torso_turn_speed": 170.0, "resist_explosion": 0.25, "resist_stun": 0.3,
		"stride_walk": 6.0, "stride_run": 6.4, "legs_scale": 1.18, "hull_scale": 1.2, "stance": 0.35},

	# ---------------- ЯДРА ----------------
	"core_battery": {"slot": "core", "name": "Ядро-батарея",
		"weight": 6.0, "energy_max": 220.0, "energy_regen": 9.0, "cd_mult": 1.0},
	"core_reactor": {"slot": "core", "name": "Ядро-реактор",
		"weight": 9.0, "energy_max": 140.0, "energy_regen": 24.0, "cd_mult": 1.0},
	"core_combat": {"slot": "core", "name": "Боевое ядро",
		"weight": 7.0, "energy_max": 170.0, "energy_regen": 14.0, "cd_mult": 0.85},

	# ---------------- ОРУЖИЕ ----------------
	# type: bullet (снаряды), beam (луч), lob (навесом), rail (заряд и прострел насквозь)
	"autocannon": {"slot": "weapon", "type": "bullet", "look": "twin", "name": "Автопушка",
		"weight": 5.0, "energy": 5.0, "ammo": 400, "fire_rate": 3.5, "damage": 8.0, "bullet_speed": 70.0, "range": 34.0,
		"spread_stand": 0.5, "spread_walk": 3.0, "spread_run": 8.0, "spread_dash": 12.0,
		"spread_per_shot": 0.35, "spread_shot_max": 2.5, "spread_grow": 30.0, "spread_shrink": 14.0,
		"recoil": 0.22, "tracer": 0.1},
	"heavy_cannon": {"slot": "weapon", "type": "bullet", "look": "heavy", "name": "Тяжёлое орудие",
		"weight": 9.0, "energy": 10.0, "ammo": 60, "fire_rate": 0.7, "damage": 45.0, "bullet_speed": 110.0, "range": 45.0,
		"spread_stand": 0.2, "spread_walk": 5.0, "spread_run": 12.0, "spread_dash": 18.0,
		"spread_per_shot": 3.0, "spread_shot_max": 6.0, "spread_grow": 40.0, "spread_shrink": 10.0,
		"recoil": 0.5, "tracer": 0.22},
	"laser": {"slot": "weapon", "type": "beam", "look": "laser", "name": "Лазер",
		"weight": 6.0, "energy": 15.0, "dps": 30.0, "energy_per_sec": 18.0, "range": 28.0,
		"spread_stand": 0.3, "spread_walk": 2.0, "spread_run": 5.0, "spread_dash": 9.0,
		"spread_grow": 30.0, "spread_shrink": 14.0},
	"blaster": {"slot": "weapon", "type": "bullet", "look": "blaster", "name": "Бластер",
		"weight": 5.0, "energy": 10.0, "ammo": 0, "energy_per_shot": 7.0, "fire_rate": 3.0, "damage": 14.0, "bullet_speed": 60.0, "range": 40.0,
		"spread_stand": 0.6, "spread_walk": 3.0, "spread_run": 7.0, "spread_dash": 10.0,
		"spread_per_shot": 0.5, "spread_shot_max": 3.0, "spread_grow": 30.0, "spread_shrink": 14.0,
		"recoil": 0.18, "tracer": 0.32},
	"grenade_launcher": {"slot": "weapon", "type": "lob", "look": "grenade", "name": "Гранатомёт",
		"weight": 7.0, "energy": 5.0, "ammo": 30, "fire_rate": 0.9, "damage": 45.0, "radius": 4.5, "edge_damage": 0.35,
		"range": 38.0, "launch_speed": 30.0,
		"spread_stand": 1.0, "spread_walk": 3.0, "spread_run": 6.0, "spread_dash": 10.0,
		"spread_per_shot": 1.0, "spread_shot_max": 3.0, "spread_grow": 30.0, "spread_shrink": 12.0,
		"recoil": 0.4},
	"shotgun": {"slot": "weapon", "type": "bullet", "look": "shotgun", "name": "Дробовик",
		"weight": 6.0, "energy": 5.0, "ammo": 50, "fire_rate": 1.1, "damage": 7.0, "pellets": 8, "pellet_spread": 7.0, "falloff": 0.4,
		"bullet_speed": 85.0, "range": 18.0,
		"spread_stand": 1.0, "spread_walk": 2.5, "spread_run": 5.0, "spread_dash": 8.0,
		"spread_per_shot": 1.5, "spread_shot_max": 3.0, "spread_grow": 30.0, "spread_shrink": 14.0,
		"recoil": 0.45, "tracer": 0.07},
	"railgun": {"slot": "weapon", "type": "rail", "look": "rail", "name": "Рельсотрон",
		"weight": 10.0, "energy": 15.0, "ammo": 20, "energy_per_shot": 20.0, "charge_time": 1.0, "fire_rate": 0.5, "damage": 110.0,
		"range": 70.0, "pierce": 1,
		"spread_stand": 0.1, "spread_walk": 3.0, "spread_run": 8.0, "spread_dash": 14.0,
		"spread_grow": 25.0, "spread_shrink": 12.0, "recoil": 0.7},
	"minigun": {"slot": "weapon", "type": "bullet", "look": "minigun", "name": "Гатлинг",
		"weight": 8.0, "energy": 5.0, "ammo": 700, "fire_rate": 14.0, "spin_up": 1.2, "damage": 5.0, "bullet_speed": 80.0, "range": 34.0,
		"spread_stand": 1.2, "spread_walk": 3.5, "spread_run": 9.0, "spread_dash": 14.0,
		"spread_per_shot": 0.12, "spread_shot_max": 2.5, "spread_grow": 30.0, "spread_shrink": 12.0,
		"recoil": 0.08, "tracer": 0.07},

	# ---------------- МОДУЛИ: АБИЛКИ ----------------
	"mod_rockets": {"slot": "module", "ability": "rockets", "name": "Ракетная установка", "short": "Ракеты",
		"weight": 6.0, "energy": 12.0, "cost": 35.0, "cooldown": 6.0, "charges": 5, "count": 3, "salvo_delay": 0.1,
		"speed": 24.0, "range": 30.0, "damage": 22.0, "radius": 4.0, "edge_damage": 0.4, "scatter": 2.0},
	"mod_emp": {"slot": "module", "ability": "emp", "name": "Излучатель импульса", "short": "Импульс",
		"weight": 4.0, "energy": 10.0, "cost": 40.0, "cooldown": 10.0, "radius": 9.0, "damage": 10.0, "stun_time": 2.5, "no_regen_time": 2.5},
	"mod_cloak": {"slot": "module", "ability": "cloak", "name": "Маскировка", "short": "Невидимость",
		"weight": 3.0, "energy": 10.0, "cost": 30.0, "cooldown": 14.0, "duration": 4.0, "break_on_fire": 1},
	"mod_repair": {"slot": "module", "ability": "repair", "name": "Наноремонт", "short": "Ремонт",
		"weight": 4.0, "energy": 10.0, "cost": 30.0, "cooldown": 16.0, "duration": 4.0, "heal_per_sec": 20.0},
	"mod_airstrike": {"slot": "module", "ability": "airstrike", "name": "Маяк авиаудара", "short": "Авиаудар",
		"weight": 3.0, "energy": 10.0, "cost": 40.0, "cooldown": 14.0, "charges": 2, "range": 40.0, "delay": 3.0,
		"damage": 70.0, "radius": 6.0, "edge_damage": 0.3},
	"mod_shield": {"slot": "module", "ability": "shield", "name": "Генератор щита", "short": "Щит",
		"weight": 5.0, "energy": 15.0, "cost": 15.0, "cooldown": 4.0, "upkeep": 6.0, "energy_per_damage": 1.5, "absorb": 1.0},
	"mod_mines": {"slot": "module", "ability": "mine", "name": "Минный укладчик", "short": "Мина",
		"weight": 4.0, "energy": 5.0, "cost": 10.0, "cooldown": 2.0, "charges": 3, "trigger_radius": 3.5, "arm_time": 1.0,
		"delay": 0.5, "damage": 60.0, "radius": 6.0, "edge_damage": 0.5, "slow": 0.3, "slow_time": 4.0},
	"mod_blink": {"slot": "module", "ability": "blink", "name": "Телепорт", "short": "Блинк",
		"weight": 3.0, "energy": 10.0, "cost": 25.0, "cooldown": 9.0, "range": 14.0, "delay": 1.0},
	# абилки 17.10.2026 (разбор с Саней): у каждой есть носитель — снаряд, граната или устройство
	"mod_bolas": {"slot": "module", "ability": "bolas", "name": "Метатель связки", "short": "Связка",
		"weight": 3.0, "energy": 5.0, "cost": 25.0, "cooldown": 12.0, "speed": 34.0, "range": 30.0, "duration": 2.0},
	"mod_jammer": {"slot": "module", "ability": "jammer", "name": "Глушащий дротик", "short": "Глушилка",
		"weight": 3.0, "energy": 5.0, "cost": 25.0, "cooldown": 14.0, "speed": 40.0, "range": 30.0, "duration": 2.0},
	"mod_napalm": {"slot": "module", "ability": "napalm", "name": "Напалм-мортирка", "short": "Напалм",
		"weight": 4.0, "energy": 5.0, "cost": 30.0, "cooldown": 14.0, "speed": 28.0, "range": 32.0, "radius": 4.5,
		"duration": 5.0, "dps": 16.0, "slow": 0.35},
	"mod_emp_shell": {"slot": "module", "ability": "emp_shell", "name": "ЭМИ-мортирка", "short": "ЭМИ-снаряд",
		"weight": 4.0, "energy": 5.0, "cost": 30.0, "cooldown": 12.0, "speed": 30.0, "range": 34.0, "radius": 5.0,
		"burn": 60.0, "no_regen_time": 3.0, "stun_time": 0.0, "damage": 0.0},
	"mod_probe": {"slot": "module", "ability": "probe", "name": "Скан-зонд", "short": "Зонд",
		"weight": 2.0, "energy": 5.0, "cost": 20.0, "cooldown": 8.0, "charges": 2, "speed": 26.0, "range": 30.0,
		"radius": 22.0, "omni": 6.0, "duration": 60.0, "hp": 50.0},
	"mod_barricade": {"slot": "module", "ability": "barricade", "name": "Раскладная баррикада", "short": "Баррикада",
		"weight": 5.0, "energy": 5.0, "cost": 25.0, "cooldown": 16.0, "range": 4.5, "hp": 400.0, "duration": 25.0},
	"mod_drone": {"slot": "module", "ability": "drone", "name": "Ремонтный дрон", "short": "Дрон",
		"weight": 3.0, "energy": 10.0, "cost": 30.0, "cooldown": 18.0, "range": 30.0, "duration": 6.0, "heal_per_sec": 25.0},
	"mod_jump": {"slot": "module", "ability": "jump", "name": "Прыжковые двигатели", "short": "Прыжок",
		"weight": 5.0, "energy": 10.0, "cost": 35.0, "cooldown": 14.0, "range": 26.0, "delay": 1.2,
		"damage": 60.0, "radius": 5.0, "edge_damage": 0.4},
	"mod_stance": {"slot": "module", "ability": "stance", "name": "Оборонительная позиция", "short": "Оборона",
		"weight": 4.0, "energy": 5.0, "cost": 10.0, "cooldown": 3.0, "reduce": 0.6},
	"mod_gravity": {"slot": "module", "ability": "gravity", "name": "Гравитационный якорь", "short": "Гравитация",
		"weight": 4.0, "energy": 10.0, "cost": 35.0, "cooldown": 16.0, "speed": 26.0, "range": 30.0, "radius": 9.0,
		"duration": 2.5, "push": 6.0},
	"mod_repulse": {"slot": "module", "ability": "repulse", "name": "Ударная волна", "short": "Толчок",
		"weight": 4.0, "energy": 10.0, "cost": 30.0, "cooldown": 10.0, "radius": 8.0, "shove": 8.0, "damage": 10.0},
	"mod_dome": {"slot": "module", "ability": "dome", "name": "Купольный щит", "short": "Купол",
		"weight": 6.0, "energy": 10.0, "cost": 40.0, "cooldown": 22.0, "radius": 6.5, "hp": 500.0, "duration": 6.0},
	"mod_turret": {"slot": "module", "ability": "turret", "name": "Мини-турель", "short": "Турель",
		"weight": 5.0, "energy": 10.0, "cost": 35.0, "cooldown": 20.0, "speed": 24.0, "range": 20.0, "radius": 26.0,
		"hp": 150.0, "duration": 15.0, "damage": 6.0, "fire_rate": 4.0},
	"mod_roller": {"slot": "module", "ability": "roller", "name": "Шар-самоубийца", "short": "Шар",
		"weight": 4.0, "energy": 10.0, "cost": 30.0, "cooldown": 14.0, "speed": 12.0, "range": 40.0, "hp": 50.0,
		"damage": 90.0, "radius": 5.0, "edge_damage": 0.4},
	"mod_marker": {"slot": "module", "ability": "marker", "name": "Дротик-целеуказатель", "short": "Метка",
		"weight": 2.0, "energy": 5.0, "cost": 20.0, "cooldown": 12.0, "speed": 45.0, "range": 32.0, "duration": 6.0, "boost": 0.25},
	"mod_slug": {"slot": "module", "ability": "slug", "name": "Тяжёлая болванка", "short": "Болванка",
		"weight": 6.0, "energy": 10.0, "cost": 35.0, "cooldown": 14.0, "speed": 60.0, "range": 40.0, "delay": 0.4,
		"damage": 70.0, "stun_time": 1.2},
	"mod_purge": {"slot": "module", "ability": "purge", "name": "Аварийный перезапуск", "short": "Перезапуск",
		"weight": 3.0, "energy": 10.0, "cost": 30.0, "cooldown": 30.0, "duration": 2.5},
	"mod_matrix": {"slot": "module", "ability": "matrix", "name": "Матрица брони", "short": "Матрица",
		"weight": 4.0, "energy": 10.0, "cost": 30.0, "cooldown": 18.0, "duration": 4.0, "reduce": 0.4},
	"mod_overdrive": {"slot": "module", "ability": "overdrive", "name": "Форсаж", "short": "Форсаж",
		"weight": 3.0, "energy": 10.0, "cost": 25.0, "cooldown": 16.0, "duration": 4.0, "boost": 0.35},
	"mod_rapid": {"slot": "module", "ability": "rapid", "name": "Форсированная подача", "short": "Подача",
		"weight": 3.0, "energy": 10.0, "cost": 30.0, "cooldown": 18.0, "duration": 5.0, "boost": 0.5},
	"mod_periscope": {"slot": "module", "ability": "periscope", "name": "Перископ", "short": "Перископ",
		"weight": 2.0, "energy": 5.0, "cost": 20.0, "cooldown": 20.0, "duration": 8.0, "boost": 0.6, "omni": 10.0},

	# ---------------- ПОСТРОЙКИ (не для ангара: турели и штаб на карте) ----------------
	"turret_t1": {"slot": "structure", "name": "Турель 1 уровня (у центра)",
		"hp": 1200.0, "damage": 25.0, "fire_rate": 1.0, "range": 48.0, "bullet_speed": 95.0, "vision": 50.0, "hit_radius": 2.2},
	"turret_t2": {"slot": "structure", "name": "Турель 2 уровня (ЭМИ-граната)",
		"hp": 1800.0, "damage": 35.0, "fire_rate": 1.2, "range": 52.0, "bullet_speed": 100.0, "vision": 54.0, "hit_radius": 2.4,
		"emp_cooldown": 9.0, "emp_range": 40.0, "emp_radius": 5.0, "emp_stun": 1.2, "emp_damage": 15.0, "emp_speed": 28.0},
	"turret_t3": {"slot": "structure", "name": "Турель 3 уровня (у базы, осадное орудие)",
		"hp": 2600.0, "damage": 45.0, "fire_rate": 1.4, "range": 56.0, "bullet_speed": 105.0, "vision": 58.0, "hit_radius": 2.6,
		"mortar_cooldown": 5.0, "mortar_range": 75.0, "mortar_min_range": 14.0, "mortar_damage": 90.0, "mortar_radius": 6.0,
		"mortar_speed": 36.0},
	"hq": {"slot": "structure", "name": "Штаб",
		"hp": 5000.0, "vision": 30.0, "hit_radius": 6.0, "barrier": 1.0},
	"core": {"slot": "structure", "name": "Ядро штаба (Тесла)",
		"hp": 2200.0, "vision": 34.0, "hit_radius": 2.2, "offset": 12.0, "forward": 3.0,
		"range": 30.0, "cooldown": 3.5, "charge": 0.6, "damage": 30.0, "stun": 0.8},

	# ---------------- КРИПЫ ----------------
	"creep_tank": {"slot": "unit", "name": "Танк-крип",
		"hp": 240.0, "damage": 12.0, "fire_rate": 0.8, "range": 22.0, "bullet_speed": 70.0, "vision": 24.0, "hit_radius": 1.15,
		"move_speed": 5.5},

	# ---------------- МОДУЛИ: ПАССИВКИ ----------------
	"mod_armor": {"slot": "module", "name": "Бронеплиты",
		"weight": 6.0, "energy": 0.0, "add_hp": 80.0},
	"mod_stabilizer": {"slot": "module", "name": "Стабилизатор",
		"weight": 2.0, "energy": 10.0, "mul_spread": 0.7},
	"mod_radiator": {"slot": "module", "name": "Радиатор",
		"weight": 3.0, "energy": 0.0, "mul_energy_regen": 1.35},
	"mod_battery": {"slot": "module", "name": "Аккумулятор",
		"weight": 5.0, "energy": 0.0, "add_energy_max": 60.0},
	"mod_servos": {"slot": "module", "name": "Форсированные приводы",
		"weight": 3.0, "energy": 10.0, "mul_speed": 1.08, "mul_accel": 1.3},
	"mod_dash": {"slot": "module", "name": "Ускоритель рывка",
		"weight": 2.0, "energy": 10.0, "mul_dash_cooldown": 0.65, "mul_dash_speed": 1.15},
	"mod_autoloader": {"slot": "module", "name": "Автозарядчик",
		"weight": 3.0, "energy": 10.0, "mul_fire_rate": 1.2},
	"mod_ap_rounds": {"slot": "module", "name": "Бронебойные снаряды",
		"weight": 2.0, "energy": 5.0, "mul_damage": 1.2},
	"mod_cooldown": {"slot": "module", "name": "Контроллер перезарядки",
		"weight": 1.0, "energy": 15.0, "mul_cd": 0.75},
	"mod_dampers": {"slot": "module", "name": "Демпферы",
		"weight": 4.0, "energy": 5.0, "add_resist_explosion": 0.3, "add_resist_stun": 0.3},
}

# Что значит каждое число: название, ползунок от, до, шаг, пояснение
const FIELDS := {
	"weight": ["Масса", 0, 80, 0.5, "тонн"],
	"energy": ["Резерв энергии", 0, 100, 1, "сколько энергии деталь забирает из запаса ядра"],
	"capacity": ["Грузоподъёмность", 20, 250, 1, "тонн: сколько всего может весить мех вместе с деталями"],
	"walk_speed": ["Скорость ходьбы", 1, 20, 0.1, "м/с, пока груз ниже порога"],
	"run_speed": ["Скорость бега", 1, 30, 0.1, "м/с, пока груз ниже порога"],
	"accel": ["Разгон", 5, 150, 1, "больше = резче стартует"],
	"decel": ["Торможение", 5, 150, 1, "больше = быстрее встаёт"],
	"dash_speed": ["Скорость рывка", 5, 80, 0.5, "м/с"],
	"dash_time": ["Длительность рывка", 0.05, 0.6, 0.01, "секунд"],
	"dash_ramp": ["Разгон рывка", 0, 0.5, 0.01, "секунд до полной скорости рывка (0 = мгновенно); дальность та же"],
	"dash_cooldown": ["Перезарядка рывка", 0, 10, 0.1, "секунд на один заряд"],
	"dash_brake": ["Торможение после рывка", 20, 300, 5, "меньше = дольше скользит"],
	"dash_charges": ["Зарядов рывка", 1, 4, 1, "сколько рывков подряд"],
	"legs_turn_speed": ["Поворот ног", 60, 2000, 10, "градусов в секунду"],
	"stride_walk": ["Длина шага (ходьба)", 1, 8, 0.1, "только вид"],
	"stride_run": ["Длина шага (бег)", 1, 10, 0.1, "только вид"],
	"legs_scale": ["Размер ног", 0.5, 1.6, 0.01, "только вид"],
	"hull_scale": ["Размер корпуса", 0.5, 1.6, 0.01, "только вид"],
	"stance": ["Ширина постановки ног", 0, 1, 0.05, "только вид, мехи из 3D-моделей: 1 = как в модели, меньше = ступни ближе к бёдрам"],
	"hp": ["Здоровье", 50, 10000, 10, ""],
	"hit_radius": ["Радиус хитбокса", 0.5, 10, 0.05, "метров"],
	"vision": ["Обзор", 5, 80, 1, "метров: сколько видит вокруг себя, укрытия закрывают обзор"],
	"omni": ["Омни-сенсор", 0, 40, 0.5, "метров: тут видно невидимых и мины; укрытия всё равно мешают"],
	"ammo": ["Боезапас", 0, 2000, 5, "выстрелов на весь бой, 0 = бесконечно; пополняется на базе и припасами"],
	"charges": ["Заряды", 0, 20, 1, "сколько раз можно применить до пополнения, 0 = без ограничений"],
	"trigger_radius": ["Радиус срабатывания", 0.5, 10, 0.1, "метров: враг ближе этого взводит мину"],
	"arm_time": ["Взвод", 0, 5, 0.1, "секунд после установки, пока мина не опасна"],
	"slow": ["Замедление", 0, 0.9, 0.05, "доля скорости, которую теряет задетый враг"],
	"slow_time": ["Время замедления", 0, 15, 0.5, "секунд"],
	"torso_turn_speed": ["Поворот корпуса", 60, 2000, 10, "градусов в секунду, как быстро доворачивает за мышкой"],
	"slots": ["Слотов под модули", 0, 8, 1, ""],
	"resist_explosion": ["Защита от взрывов", 0, 0.9, 0.05, "доля урона от взрывов, которая не проходит"],
	"resist_stun": ["Защита от оглушения", 0, 0.9, 0.05, "на какую долю короче оглушение"],
	"armor_flat": ["Бронеплиты", 0, 20, 0.5, "на сколько слабее каждое попадание (лучи не режет; минимум 30% урона проходит)"],
	"regen_hp": ["Самопочинка", 0, 50, 0.5, "здоровья в секунду, когда давно не получал урон"],
	"regen_delay": ["Задержка самопочинки", 0, 15, 0.5, "секунд без урона до начала починки"],
	"moving_spread": ["Разброс на ходу", 0.2, 1.5, 0.05, "множитель разброса в движении: 0.5 = вдвое точнее"],
	"brace_bonus": ["Упор", 0, 1, 0.05, "стоя на месте: дальность больше на эту долю, разброс меньше вдвое этой доли"],
	"brace_time": ["Время до упора", 0, 3, 0.1, "секунд стоять, чтобы включился упор"],
	"ram_damage": ["Урон тарана", 0, 300, 5, "урон врагу, в которого врезался рывком"],
	"ram_stun": ["Оглушение тарана", 0, 3, 0.05, "секунд"],
	"energy_regen_mult": ["× восстановление энергии", 0.5, 3, 0.05, "больше 1 = быстрее"],
	"energy_max": ["Запас энергии", 20, 400, 5, "до вычета резерва деталей"],
	"energy_regen": ["Восстановление энергии", 0, 80, 0.5, "единиц в секунду"],
	"cd_mult": ["Перезарядка абилок", 0.3, 1.5, 0.05, "множитель: 1 = обычная, 0.8 = на 20% быстрее"],
	"fire_rate": ["Скорострельность", 0.1, 30, 0.1, "выстрелов в секунду с одного подвеса"],
	"damage": ["Урон", 0, 300, 0.5, ""],
	"bullet_speed": ["Скорость снаряда", 5, 250, 1, "м/с"],
	"range": ["Дальность", 5, 120, 1, "метров"],
	"launch_speed": ["Скорость гранаты", 10, 150, 1, "м/с при вылете: быстрее — дуга площе и граната быстрее долетает. Ствол сам поднимается под точку прицела"],
	"energy_per_shot": ["Энергия за выстрел", 0, 80, 0.5, "сколько энергии ест один выстрел"],
	"pellets": ["Дробин в выстреле", 1, 20, 1, "штук"],
	"pellet_spread": ["Разлёт дроби", 0, 30, 0.5, "градусов, половина конуса"],
	"falloff": ["Урон на краю дальности", 0, 1, 0.05, "доля урона, которая остаётся на максимальной дистанции"],
	"charge_time": ["Время заряда", 0.1, 4, 0.05, "секунд держать кнопку до выстрела"],
	"pierce": ["Прострел насквозь", 0, 1, 1, "1 = пробивает мехов и крипов, стены всё равно держат"],
	"spin_up": ["Раскрутка", 0, 4, 0.05, "секунд до полной скорострельности"],
	"spread_stand": ["Разброс стоя", 0, 10, 0.05, "градусов, половина конуса"],
	"spread_walk": ["Разброс на ходу", 0, 20, 0.1, "градусов"],
	"spread_run": ["Разброс на бегу", 0, 30, 0.1, "градусов"],
	"spread_dash": ["Разброс в рывке", 0, 40, 0.1, "градусов"],
	"spread_per_shot": ["Добавка за выстрел", 0, 8, 0.05, "градусов за каждый выстрел"],
	"spread_shot_max": ["Потолок добавки", 0, 15, 0.1, "градусов"],
	"spread_grow": ["Рост разброса", 1, 120, 1, "градусов в секунду, когда начал двигаться"],
	"spread_shrink": ["Сжатие разброса", 1, 120, 1, "градусов в секунду, когда остановился"],
	"recoil": ["Откат ствола", 0, 1, 0.01, "только вид"],
	"tracer": ["Толщина трассера", 0.03, 0.5, 0.01, "только вид"],
	"dps": ["Урон в секунду", 0, 200, 1, "пока луч касается цели"],
	"energy_per_sec": ["Энергия в секунду", 0, 100, 0.5, "сколько ест луч, пока светит"],
	"cost": ["Цена", 0, 150, 1, "энергии за применение"],
	"cooldown": ["Перезарядка", 0, 30, 0.1, "секунд"],
	"count": ["Ракет в залпе", 1, 8, 1, "штук"],
	"salvo_delay": ["Пауза между ракетами", 0, 0.5, 0.01, "секунд"],
	"speed": ["Скорость ракеты", 5, 80, 0.5, "м/с, меньше = легче увернуться"],
	"radius": ["Радиус", 1, 30, 0.5, "метров"],
	"edge_damage": ["Урон на краю", 0, 1, 0.05, "доля от урона в центре"],
	"scatter": ["Разлёт ракет", 0, 8, 0.1, "метров вокруг точки"],
	"stun_time": ["Оглушение", 0, 10, 0.1, "секунд"],
	"duration": ["Длительность", 0.5, 20, 0.1, "секунд"],
	"break_on_fire": ["Выстрел снимает", 0, 1, 1, "1 = выстрел или другая абилка снимают невидимость, 0 = нет"],
	"heal_per_sec": ["Лечение в секунду", 0, 200, 1, "здоровья в секунду, пока действует"],
	"delay": ["Задержка", 0, 6, 0.05, "секунд от нажатия до срабатывания"],
	"upkeep": ["Поддержание", 0, 50, 0.5, "энергии в секунду, пока щит включён"],
	"energy_per_damage": ["Энергии за 1 урона", 0, 5, 0.05, "сколько энергии сжигает каждая единица урона, которую принял щит"],
	"absorb": ["Поглощение", 0, 1, 0.05, "доля урона, которую берёт щит; остальное проходит в броню"],
	"no_regen_time": ["Без восстановления энергии", 0, 10, 0.1, "секунд, сколько у задетых врагов не восстанавливается энергия"],
	"burn": ["Сжигает энергию", 0, 300, 1, "энергии у каждого задетого врага (меха базовой массы, см. «Контроль»)"],
	"push": ["Сила", 0, 80, 0.5, "м/с: как быстро тянет или толкает меха базовой массы; тяжелее — слабее"],
	"reduce": ["Снижение урона", 0, 0.95, 0.05, "доля урона, которую режет, пока включено"],
	"shove": ["Дистанция толчка", 0, 40, 0.5, "метров: на сколько отлетает мех базовой массы (F2 → «Контроль»), тяжелее — ближе; крипы — ровно на столько"],
	"boost": ["Усиление", 0, 2, 0.05, "доля: форсаж — к скорости, подача — к скорострельности, перископ — к обзору, метка — к урону по цели"],
	"emp_cooldown": ["ЭМИ-граната: перезарядка", 1, 30, 0.5, "секунд"],
	"emp_range": ["ЭМИ-граната: дальность", 5, 80, 1, "метров"],
	"emp_radius": ["ЭМИ-граната: радиус", 1, 15, 0.5, "метров"],
	"emp_stun": ["ЭМИ-граната: оглушение", 0, 5, 0.1, "секунд"],
	"emp_damage": ["ЭМИ-граната: урон", 0, 100, 1, ""],
	"emp_speed": ["ЭМИ-граната: скорость", 10, 80, 1, "м/с при вылете: быстрее — летит прямее и быстрее. Рвётся о то, во что врежется (стена, мех, крип, земля)"],
	"mortar_cooldown": ["Осадное орудие: перезарядка", 1, 30, 0.5, "секунд"],
	"mortar_range": ["Осадное орудие: дальность", 10, 120, 1, "метров"],
	"mortar_min_range": ["Осадное орудие: мёртвая зона", 0, 40, 1, "метров: ближе не стреляет"],
	"mortar_damage": ["Осадное орудие: урон", 0, 400, 5, "в центре"],
	"mortar_radius": ["Осадное орудие: радиус", 1, 15, 0.5, "метров"],
	"mortar_speed": ["Осадное орудие: скорость", 10, 80, 1, "м/с при вылете: быстрее — летит прямее и быстрее. Рвётся о то, во что врежется (стена, мех, крип, земля)"],
	"charge": ["Тесла: зарядка", 0, 3, 0.05, "секунд от вспышки до удара молнии; можно успеть выйти из радиуса"],
	"stun": ["Тесла: оглушение", 0, 5, 0.1, "секунд"],
	"offset": ["Ядра: отступ вбок", 6, 30, 0.5, "метров от центра штаба (действует со следующего боя)"],
	"forward": ["Ядра: отступ вперёд", -10, 15, 0.5, "метров в сторону врага (действует со следующего боя)"],
	"barrier": ["Барьер от ядер", 0, 1, 1, "1 = пока стоит хоть одно ядро, штаб неуязвим"],
	"move_speed": ["Скорость", 1, 20, 0.1, "м/с"],
	"add_hp": ["+ здоровье", 0, 500, 5, ""],
	"add_energy_max": ["+ запас энергии", 0, 300, 5, ""],
	"mul_energy_regen": ["× восстановление энергии", 0.5, 3, 0.05, "больше 1 = быстрее"],
	"mul_spread": ["× разброс", 0.2, 1.5, 0.05, "меньше 1 = точнее"],
	"mul_speed": ["× скорость", 0.5, 2, 0.01, "ходьба и бег"],
	"mul_accel": ["× разгон", 0.5, 3, 0.05, ""],
	"mul_dash_cooldown": ["× перезарядка рывка", 0.2, 1.5, 0.05, "меньше 1 = чаще"],
	"mul_dash_speed": ["× скорость рывка", 0.5, 2, 0.05, ""],
	"mul_fire_rate": ["× скорострельность", 0.5, 3, 0.05, ""],
	"mul_damage": ["× урон оружия", 0.5, 3, 0.05, ""],
	"mul_cd": ["× перезарядка абилок", 0.3, 1.5, 0.05, "меньше 1 = быстрее"],
	"add_resist_explosion": ["+ защита от взрывов", 0, 0.9, 0.05, ""],
	"add_resist_stun": ["+ защита от оглушения", 0, 0.9, 0.05, ""],
}

const MECH_STATS := ["capacity", "hp", "hit_radius", "vision", "omni", "torso_turn_speed", "resist_explosion", "resist_stun",
	"walk_speed", "run_speed", "accel", "decel", "dash_speed", "dash_time", "dash_ramp",
	"dash_cooldown", "dash_brake", "dash_charges", "legs_turn_speed", "stride_walk", "stride_run", "legs_scale", "hull_scale", "stance",
	"armor_flat", "regen_hp", "regen_delay", "brace_bonus", "brace_time", "ram_damage", "ram_stun"]
const WEAPON_STATS := ["ammo", "fire_rate", "damage", "bullet_speed", "range", "spread_stand", "spread_walk", "spread_run",
	"spread_dash", "spread_per_shot", "spread_shot_max", "spread_grow", "spread_shrink", "recoil", "tracer",
	"dps", "energy_per_sec", "energy_per_shot", "pellets", "pellet_spread", "falloff", "launch_speed",
	"radius", "edge_damage", "charge_time", "pierce", "spin_up"]
const ABILITY_STATS := ["cost", "cooldown", "count", "salvo_delay", "speed", "range", "damage", "radius",
	"edge_damage", "scatter", "stun_time", "no_regen_time",
	"duration", "break_on_fire", "charges", "trigger_radius", "arm_time", "slow", "slow_time", "heal_per_sec", "delay", "upkeep", "energy_per_damage", "absorb", "dps", "burn", "push", "reduce", "omni", "hp", "shove", "boost", "fire_rate"]
# значения, если у меха такого числа нет
const MECH_DEFAULTS := {"dash_charges": 1.0, "moving_spread": 1.0, "energy_regen_mult": 1.0, "cd_mult": 1.0, "brace_time": 0.6,
	"regen_delay": 4.0, "legs_scale": 1.0, "hull_scale": 1.0, "stance": 1.0}

const DEFAULT_BUILD := {
	"mech": "mech_assault", "core": "core_combat",
	"weapons": ["autocannon", "autocannon"],
	"modules": ["mod_rockets", "mod_emp", "mod_armor", "mod_radiator"],
}

# старые сборки (ноги + корпус) переводим на мехов по корпусу
const OLD_HULL_TO_MECH := {"hull_scout": "mech_hound", "hull_assault": "mech_assault", "hull_fortress": "mech_fortress"}

var version := 0              # растёт при каждом изменении чисел, мехи по нему понимают, что пора пересчитаться
var player_build := {}
var saved_builds := {}        # твои сохранённые сборки: имя -> сборка
var _over := {}               # твои изменения чисел деталей: id -> {поле: значение}
var _mech_models := {}        # 3D-модели мехов (assets/mechs): имя -> сцена, грузятся один раз при запуске


func _ready() -> void:
	player_build = DEFAULT_BUILD.duplicate(true)
	_load()
	_load_builds()
	# модели мехов сразу в память: иначе первое появление такого меха в бою подтормаживает
	for id in DATA:
		if DATA[id].has("model"):
			mech_model(DATA[id]["model"])


# 3D-модель меха по имени (или null, если файла нет)
func mech_model(name: String) -> PackedScene:
	if not _mech_models.has(name):
		var path := "res://assets/mechs/%s.glb" % name
		_mech_models[name] = load(path) if ResourceLoader.exists(path) else null
	return _mech_models[name]


# ------------------------------------------------------------------
#  Числа деталей с учётом твоих изменений
# ------------------------------------------------------------------

func ids_for(slot: String) -> Array:
	var out: Array = []
	for id in DATA:
		if DATA[id]["slot"] == slot:
			out.append(id)
	return out


func pname(id: String) -> String:
	return DATA[id]["name"] if DATA.has(id) else "— пусто —"


func v(id: String, field: String) -> float:
	if _over.has(id) and _over[id].has(field):
		return float(_over[id][field])
	if DATA.has(id) and DATA[id].has(field):
		return float(DATA[id][field])
	return float(MECH_DEFAULTS.get(field, 0.0)) if id.begins_with("mech_") else 0.0


func text(id: String, field: String) -> String:
	return str(DATA[id].get(field, "")) if DATA.has(id) else ""


func numeric_fields(id: String) -> Array:
	var out: Array = []
	for f in DATA[id]:
		if FIELDS.has(f):
			out.append(f)
	return out


func set_value(id: String, field: String, value: float) -> void:
	if not _over.has(id):
		_over[id] = {}
	_over[id][field] = value
	version += 1
	Cfg.mark_dirty()


func is_changed(id: String, field: String) -> bool:
	return _over.has(id) and _over[id].has(field) and not is_equal_approx(float(_over[id][field]), float(DATA[id][field]))


func reset_value(id: String, field: String) -> void:
	if _over.has(id):
		_over[id].erase(field)
	version += 1
	Cfg.mark_dirty()


func reset_all() -> void:
	_over.clear()
	version += 1
	Cfg.mark_dirty()


# ------------------------------------------------------------------
#  Описание детали: собирается из текущих чисел, поэтому всегда точное
# ------------------------------------------------------------------

const BONUS_TEXT := {
	"add_hp": "здоровья",
	"add_energy_max": "запаса энергии",
	"mul_energy_regen": "восстановления энергии",
	"mul_spread": "разброса оружия",
	"mul_speed": "скорости",
	"mul_accel": "разгона",
	"mul_dash_cooldown": "перезарядки рывка",
	"mul_dash_speed": "скорости рывка",
	"mul_fire_rate": "скорострельности",
	"mul_damage": "урона оружия",
	"mul_cd": "перезарядки абилок",
	"add_resist_explosion": "урона от взрывов",
	"add_resist_stun": "длительности оглушения",
}


# расстояние или скорость в настоящих метрах (игра считает в единицах, 1 единица = Cfg.METERS_PER_UNIT м)
func _m(x: float) -> String:
	return _n(snappedf(x * Cfg.METERS_PER_UNIT, 0.1))


func _n(x: float) -> String:
	if is_equal_approx(x, round(x)):
		return str(int(round(x)))
	return str(snappedf(x, 0.01))


func _pct(x: float) -> String:
	var p := int(round(x * 100.0))
	return ("+%d%%" % p) if p > 0 else ("−%d%%" % -p)


# урон в секунду с одного подвеса (для ангара)
func weapon_dps(id: String) -> float:
	match DATA[id].get("type", "bullet"):
		"beam":
			return v(id, "dps")
		"rail":
			return v(id, "damage") / maxf(v(id, "charge_time") + 1.0 / maxf(v(id, "fire_rate"), 0.05), 0.05)
	return v(id, "damage") * maxf(v(id, "pellets"), 1.0) * v(id, "fire_rate")


# коротко: главное о детали в одну строку (для плитки в ангаре)
func short_line(id: String) -> String:
	if not DATA.has(id):
		return "пусто"
	var d: Dictionary = DATA[id]
	match d["slot"]:
		"mech":
			return "%s HP · %s м/с · слотов %d" % [_n(v(id, "hp")), _m(v(id, "run_speed")), int(v(id, "slots"))]
		"core":
			return "энергия %s · +%s/с" % [_n(v(id, "energy_max")), _n(v(id, "energy_regen"))]
		"weapon":
			var ammo := "∞" if v(id, "ammo") <= 0.0 else _n(v(id, "ammo"))
			if v(id, "energy_per_shot") > 0.0 and v(id, "ammo") <= 0.0:
				ammo = "энергия"
			if d.get("type", "") == "beam":
				ammo = "энергия"
			return "%s урона/с · %s м · %s" % [_n(snappedf(weapon_dps(id), 1.0)), _m(v(id, "range")), ammo]
		"module":
			var s := describe(id)
			return s.split(" · ")[0] if s != "" else ""
	return ""


func describe(id: String) -> String:
	if not DATA.has(id):
		return ""
	var d: Dictionary = DATA[id]
	var out := PackedStringArray()
	match d["slot"]:
		"mech":
			out.append("%s, %s т, груз до %s т" % [d.get("class", ""), _n(v(id, "weight")), _n(v(id, "capacity"))])
			out.append("%s HP" % _n(v(id, "hp")))
			out.append("ход %s / бег %s м/с" % [_m(v(id, "walk_speed")), _m(v(id, "run_speed"))])
			out.append("рывок %s м, кд %s с%s" % [_m(v(id, "dash_speed") * v(id, "dash_time")), _n(v(id, "dash_cooldown")),
				(", зарядов %d" % int(v(id, "dash_charges"))) if v(id, "dash_charges") > 1.0 else ""])
			out.append("модулей: %d" % int(v(id, "slots")))
			out.append("хитбокс %s м" % _m(v(id, "hit_radius")))
			out.append("обзор %s м, омни %s м" % [_m(v(id, "vision")), _m(v(id, "omni"))])
			if v(id, "resist_explosion") > 0.0:
				out.append("%s урона от взрывов" % _pct(-v(id, "resist_explosion")))
			if v(id, "resist_stun") > 0.0:
				out.append("%s оглушения" % _pct(-v(id, "resist_stun")))
		"core":
			out.append("энергия %s" % _n(v(id, "energy_max")))
			out.append("+%s/с" % _n(v(id, "energy_regen")))
			if not is_equal_approx(v(id, "cd_mult"), 1.0):
				out.append("%s перезарядки абилок" % _pct(v(id, "cd_mult") - 1.0))
		"weapon":
			match d.get("type", "bullet"):
				"beam":
					out.append("%s урона/с" % _n(v(id, "dps")))
					out.append("ест %s эн./с" % _n(v(id, "energy_per_sec")))
				"lob":
					out.append("граната %s урона, радиус %s м, по дуге, рвётся о преграду" % [_n(v(id, "damage")), _m(v(id, "radius"))])
					out.append("%s выстр./с" % _n(v(id, "fire_rate")))
				"rail":
					out.append("%s урона, заряд %s с%s" % [_n(v(id, "damage")), _n(v(id, "charge_time")), ", насквозь" if v(id, "pierce") > 0.5 else ""])
				_:
					if v(id, "pellets") > 1.0:
						out.append("%d дробин × %s урона, %s выстр./с" % [int(v(id, "pellets")), _n(v(id, "damage")), _n(v(id, "fire_rate"))])
					else:
						out.append("%s урона × %s/с = %s/с" % [_n(v(id, "damage")), _n(v(id, "fire_rate")), _n(v(id, "damage") * v(id, "fire_rate"))])
					if v(id, "spin_up") > 0.0:
						out.append("раскрутка %s с" % _n(v(id, "spin_up")))
			out.append("%s м" % _m(v(id, "range")))
			if v(id, "ammo") > 0.0:
				out.append("%s патронов" % _n(v(id, "ammo")))
			if v(id, "energy_per_shot") > 0.0:
				out.append("%s эн. за выстрел" % _n(v(id, "energy_per_shot")))
			out.append("разброс %s°/%s°/%s° (стоя/шаг/бег)" % [_n(v(id, "spread_stand")), _n(v(id, "spread_walk")), _n(v(id, "spread_run"))])
		"structure", "unit":
			out.append("%s HP" % _n(v(id, "hp")))
			if v(id, "damage") > 0.0:
				out.append("%s урона × %s/с" % [_n(v(id, "damage")), _n(v(id, "fire_rate"))])
				out.append("дальность %s м" % _m(v(id, "range")))
			out.append("обзор %s м" % _m(v(id, "vision")))
			if v(id, "emp_cooldown") > 0.0:
				out.append("ЭМИ-граната: оглушение %s с раз в %s с" % [_n(v(id, "emp_stun")), _n(v(id, "emp_cooldown"))])
			if v(id, "mortar_cooldown") > 0.0:
				out.append("осадное орудие: %s урона раз в %s с, до %s м" % [_n(v(id, "mortar_damage")), _n(v(id, "mortar_cooldown")), _m(v(id, "mortar_range"))])
		"module":
			match d.get("ability", ""):
				"rockets":
					out.append("%d×%s урона" % [int(v(id, "count")), _n(v(id, "damage"))])
					out.append("радиус %s м (край %s)" % [_m(v(id, "radius")), _pct(v(id, "edge_damage")).trim_prefix("+")])
					out.append("до %s м" % _m(v(id, "range")))
				"emp":
					out.append("%s урона + оглушение %s с" % [_n(v(id, "damage")), _n(v(id, "stun_time"))])
					if v(id, "no_regen_time") > 0.0:
						out.append("энергия врага не растёт %s с" % _n(v(id, "no_regen_time")))
					out.append("радиус %s м" % _m(v(id, "radius")))
				"cloak":
					out.append("невидимость %s с" % _n(v(id, "duration")))
					if v(id, "break_on_fire") > 0.5:
						out.append("выстрел снимает")
				"repair":
					out.append("+%s HP за %s с (%s/с)" % [_n(v(id, "heal_per_sec") * v(id, "duration")), _n(v(id, "duration")), _n(v(id, "heal_per_sec"))])
				"airstrike":
					out.append("%s урона через %s с" % [_n(v(id, "damage")), _n(v(id, "delay"))])
					out.append("радиус %s м (край %s)" % [_m(v(id, "radius")), _pct(v(id, "edge_damage")).trim_prefix("+")])
					out.append("до %s м" % _m(v(id, "range")))
				"shield":
					out.append("берёт %s урона" % _pct(v(id, "absorb")).trim_prefix("+"))
					out.append("%s эн. за 1 урона" % _n(v(id, "energy_per_damage")))
					out.append("держать %s эн./с" % _n(v(id, "upkeep")))
				"mine":
					out.append("%s урона, радиус %s м, замедление %s на %s с" % [_n(v(id, "damage")), _m(v(id, "radius")), _pct(v(id, "slow")).trim_prefix("+"), _n(v(id, "slow_time"))])
				"blink":
					out.append("прыжок до %s м через %s с (стоишь)" % [_m(v(id, "range")), _n(v(id, "delay"))])
				"bolas":
					out.append("связка: обездвиживает %s с, до %s м" % [_n(v(id, "duration")), _m(v(id, "range"))])
				"jammer":
					out.append("дротик: не стреляет %s с, до %s м" % [_n(v(id, "duration")), _m(v(id, "range"))])
				"napalm":
					out.append("огонь %s урона/с %s с, замедление %s, радиус %s м" % [_n(v(id, "dps")), _n(v(id, "duration")), _pct(v(id, "slow")).trim_prefix("+"), _m(v(id, "radius"))])
				"emp_shell":
					out.append("сжигает %s эн., энергия не растёт %s с, радиус %s м" % [_n(v(id, "burn")), _n(v(id, "no_regen_time")), _m(v(id, "radius"))])
				"probe":
					out.append("обзор %s м на %s с, врагу виден вблизи" % [_m(v(id, "radius")), _n(v(id, "duration"))])
				"barricade":
					out.append("стенка %s HP на %s с" % [_n(v(id, "hp")), _n(v(id, "duration"))])
				"drone":
					out.append("чинит союзника +%s HP за %s с" % [_n(v(id, "heal_per_sec") * v(id, "duration")), _n(v(id, "duration"))])
				"jump":
					out.append("прыжок до %s м, удар %s урона, радиус %s м" % [_m(v(id, "range")), _n(v(id, "damage")), _m(v(id, "radius"))])
				"stance":
					out.append("стоит и стреляет, урон %s" % _pct(-v(id, "reduce")))
				"gravity":
					out.append("тянет врагов %s с, радиус %s м" % [_n(v(id, "duration")), _m(v(id, "radius"))])
				"repulse":
					out.append("отбрасывает врагов на %s м, радиус %s м" % [_m(v(id, "shove")), _m(v(id, "radius"))])
				"dome":
					out.append("купол %s м, %s HP на %s с" % [_m(v(id, "radius")), _n(v(id, "hp")), _n(v(id, "duration"))])
				"turret":
					out.append("турель %s урона × %s/с на %s с" % [_n(v(id, "damage")), _n(v(id, "fire_rate")), _n(v(id, "duration"))])
				"roller":
					out.append("катится к врагам, взрыв %s урона" % _n(v(id, "damage")))
				"marker":
					out.append("цель получает %s урона %s с" % [_pct(v(id, "boost")), _n(v(id, "duration"))])
				"slug":
					out.append("%s урона + оглушение %s с" % [_n(v(id, "damage")), _n(v(id, "stun_time"))])
				"purge":
					out.append("снимает контроль, %s с не берёт новый" % _n(v(id, "duration")))
				"matrix":
					out.append("урон %s на %s с" % [_pct(-v(id, "reduce")), _n(v(id, "duration"))])
				"overdrive":
					out.append("скорость %s на %s с" % [_pct(v(id, "boost")), _n(v(id, "duration"))])
				"rapid":
					out.append("скорострельность %s на %s с" % [_pct(v(id, "boost")), _n(v(id, "duration"))])
				"periscope":
					out.append("обзор %s, омни +%s м на %s с" % [_pct(v(id, "boost")), _m(v(id, "omni")), _n(v(id, "duration"))])
			if d.get("ability", "") in ["shield", "stance"]:
				out.append("вкл. %s эн., кд %s с после выкл." % [_n(v(id, "cost")), _n(v(id, "cooldown"))])
			elif d.has("ability"):
				out.append("%s эн., кд %s с" % [_n(v(id, "cost")), _n(v(id, "cooldown"))])
			if v(id, "charges") > 0.0:
				out.append("зарядов: %s" % _n(v(id, "charges")))
			for f in d:
				if not BONUS_TEXT.has(f):
					continue
				var val := v(id, f)
				if f.begins_with("add_resist"):
					out.append("%s %s" % [_pct(-val), BONUS_TEXT[f]])
				elif f.begins_with("add_"):
					out.append("+%s %s" % [_n(val), BONUS_TEXT[f]])
				else:
					out.append("%s %s" % [_pct(val - 1.0), BONUS_TEXT[f]])
	return " · ".join(out)


func set_player_build(b: Dictionary) -> void:
	player_build = b.duplicate(true)
	Cfg.mark_dirty()


# ------------------------------------------------------------------
#  Подсчёт итоговых чисел сборки
# ------------------------------------------------------------------

func compute(b: Dictionary) -> Dictionary:
	b = upgrade_build(b)
	var mech: String = b.get("mech", "mech_assault")
	var core: String = b.get("core", "core_combat")
	var wlist: Array = b.get("weapons", ["autocannon", "autocannon"])
	var slots := int(v(mech, "slots"))
	var mods: Array = []
	for i in mini(slots, b.get("modules", []).size()):
		var m: String = b["modules"][i]
		if DATA.has(m):
			mods.append(m)

	var st := {}
	for f in MECH_STATS:
		st[f] = v(mech, f)
	st["mech"] = mech
	st["style"] = text(mech, "style")
	st["model"] = text(mech, "model")
	st["slots"] = slots
	st["energy_total"] = v(core, "energy_max")
	st["energy_regen"] = v(core, "energy_regen") * v(mech, "energy_regen_mult")
	st["cd_mult"] = v(core, "cd_mult") * v(mech, "cd_mult")

	# масса и резерв энергии
	var weight := v(mech, "weight") + v(core, "weight")
	var reserved := 0.0
	for w in wlist:
		weight += v(w, "weight")
		reserved += v(w, "energy")
	for m in mods:
		weight += v(m, "weight")
		reserved += v(m, "energy")

	# пассивки модулей: сначала прибавки, потом множители
	var add := {}
	var mul := {}
	for m in mods:
		for f in DATA[m]:
			if f.begins_with("add_"):
				var k: String = f.substr(4)
				add[k] = add.get(k, 0.0) + v(m, f)
			elif f.begins_with("mul_"):
				var k2: String = f.substr(4)
				mul[k2] = mul.get(k2, 1.0) * v(m, f)
	for k in add:
		var key: String = "energy_total" if k == "energy_max" else k
		if st.has(key):
			st[key] += add[k]
	for k in mul:
		match k:
			"speed":
				st["walk_speed"] *= mul[k]
				st["run_speed"] *= mul[k]
			"cd":
				st["cd_mult"] *= mul[k]
			"accel":
				st["accel"] *= mul[k]
			_:
				if st.has(k):
					st[k] *= mul[k]
	st["resist_explosion"] = clampf(st["resist_explosion"], 0.0, 0.9)
	st["resist_stun"] = clampf(st["resist_stun"], 0.0, 0.9)

	# оружие на подвесах
	var move_k := v(mech, "moving_spread")
	var weapons: Array = []
	for w in wlist:
		var ws := {"id": w, "name": pname(w), "type": DATA[w].get("type", "bullet"), "look": DATA[w].get("look", "twin")}
		for f in WEAPON_STATS:
			ws[f] = v(w, f)
		ws["pellets"] = maxf(ws["pellets"], 1.0)
		for f in ["spread_walk", "spread_run", "spread_dash"]:
			ws[f] = lerpf(ws["spread_stand"], ws[f], move_k)
		if mul.has("spread"):
			for f in ["spread_stand", "spread_walk", "spread_run", "spread_dash", "spread_per_shot", "pellet_spread"]:
				ws[f] *= mul["spread"]
		if mul.has("fire_rate"):
			ws["fire_rate"] *= mul["fire_rate"]
		if mul.has("damage"):
			ws["damage"] *= mul["damage"]
			ws["dps"] *= mul["damage"]
		weapons.append(ws)

	# груз: чем ближе масса к грузоподъёмности, тем мех медленнее, неповоротливее и короче рывок.
	# Штраф растёт линейно от порога до полной загрузки (все множители в F2, группа "Вес и скорость")
	var cap := maxf(st["capacity"], 1.0)
	var load_k := weight / cap
	var lt := clampf((load_k - Cfg.load_free) / maxf(1.0 - Cfg.load_free, 0.01), 0.0, 1.0)
	var factor := lerpf(1.0, Cfg.load_min_speed, lt)
	var k_accel := lerpf(1.0, Cfg.load_accel, lt)
	var k_dash := lerpf(1.0, Cfg.load_dash, lt)
	var k_turn := lerpf(1.0, Cfg.load_turn, lt)
	st["walk_speed"] *= factor
	st["run_speed"] *= factor
	st["accel"] *= k_accel
	st["decel"] *= k_accel
	st["dash_speed"] *= k_dash
	st["legs_turn_speed"] *= k_turn
	st["torso_turn_speed"] *= k_turn
	st["weight"] = weight
	st["load"] = load_k
	st["speed_factor"] = factor
	st["energy_reserved"] = reserved
	st["energy_max"] = maxf(st["energy_total"] - reserved, 1.0)

	# абилки из модулей
	var abilities: Array = []
	var seen := {}
	var problems: Array = []
	for m in mods:
		if DATA[m].has("ability"):
			var t: String = DATA[m]["ability"]
			if seen.has(t):
				problems.append("Две одинаковые абилки: %s" % pname(m))
				continue
			seen[t] = true
			var p := {}
			for f in ABILITY_STATS:
				if DATA[m].has(f):
					p[f] = v(m, f)
			abilities.append({"type": t, "name": pname(m), "short": DATA[m].get("short", pname(m)), "id": m, "params": p})

	if weight > cap + 0.001:
		problems.append("Перегруз: %.1f из %.0f т" % [weight, cap])
	if st["energy_total"] - reserved < Cfg.min_energy_pool:
		problems.append("Мало энергии: детали забирают %.0f из %.0f" % [reserved, st["energy_total"]])

	return {"stats": st, "weapons": weapons, "abilities": abilities, "ok": problems.is_empty(), "problems": problems}


# старый формат (ноги + корпус) -> мех; неизвестные детали -> стандартные
func upgrade_build(b: Dictionary) -> Dictionary:
	if b.has("mech") and DATA.has(b["mech"]):
		return b
	var out := b.duplicate(true)
	out["mech"] = OLD_HULL_TO_MECH.get(b.get("hull", ""), "mech_assault")
	out.erase("legs")
	out.erase("hull")
	if not DATA.has(out.get("core", "")):
		out["core"] = "core_combat"
	return out


# случайная рабочая сборка (для ботов)
func random_build() -> Dictionary:
	var mods_all := ids_for("module")
	for attempt in 60:
		var b := {
			"mech": ids_for("mech").pick_random(),
			"core": ids_for("core").pick_random(),
			"weapons": [],
			"modules": [],
		}
		var wpn: String = ids_for("weapon").pick_random()
		# чаще одинаковое оружие на оба подвеса, иногда разное
		b["weapons"] = [wpn, wpn] if randf() < 0.6 else [wpn, ids_for("weapon").pick_random()]
		if not compute(b)["ok"]:
			continue
		var slots := int(v(b["mech"], "slots"))
		var pool := mods_all.duplicate()
		pool.shuffle()
		for m in pool:
			if b["modules"].size() >= slots:
				break
			b["modules"].append(m)
			if not compute(b)["ok"]:
				b["modules"].pop_back()
		return b
	return DEFAULT_BUILD.duplicate(true)


# ------------------------------------------------------------------
#  Сохранение чисел (в тот же файл tuning.cfg, что и общие настройки)
# ------------------------------------------------------------------

func write_config(cf: ConfigFile) -> void:
	for id in _over:
		for f in _over[id]:
			if is_changed(id, f):
				cf.set_value("parts", "%s/%s" % [id, f], _over[id][f])
	cf.set_value("build", "player", player_build)


func _load() -> void:
	if not Cfg.persist_enabled():
		return
	var cf := ConfigFile.new()
	if cf.load(Cfg.tuning_path()) != OK:
		return
	if cf.has_section("parts"):
		for key in cf.get_section_keys("parts"):
			var parts := key.split("/")
			if parts.size() == 2 and DATA.has(parts[0]) and DATA[parts[0]].has(parts[1]):
				if not _over.has(parts[0]):
					_over[parts[0]] = {}
				_over[parts[0]][parts[1]] = float(cf.get_value("parts", key))
	if cf.has_section_key("build", "player"):
		var b = cf.get_value("build", "player")
		if b is Dictionary:
			b = upgrade_build(b)
			if _valid_ids(b):
				player_build = b


func _valid_ids(b: Dictionary) -> bool:
	for k in ["mech", "core"]:
		if not DATA.has(b.get(k, "")):
			return false
	for w in b.get("weapons", []):
		if not DATA.has(w):
			return false
	for m in b.get("modules", []):
		if m != "" and not DATA.has(m):
			return false
	return b.get("weapons", []).size() == 2


# ------------------------------------------------------------------
#  Сохранённые сборки (отдельный файл builds.cfg рядом с настройками)
# ------------------------------------------------------------------

func builds_path() -> String:
	return "res://builds.cfg" if OS.has_feature("editor") else "user://builds.cfg"


func _load_builds() -> void:
	if not Cfg.persist_enabled():
		return
	var cf := ConfigFile.new()
	if cf.load(builds_path()) != OK:
		return
	for key in cf.get_section_keys("builds") if cf.has_section("builds") else []:
		var b = cf.get_value("builds", key)
		if b is Dictionary:
			b = upgrade_build(b)
			if _valid_ids(b):
				saved_builds[key] = b


func save_build(title: String, b: Dictionary) -> void:
	title = title.strip_edges()
	if title == "":
		return
	saved_builds[title] = b.duplicate(true)
	_write_builds()


func delete_build(title: String) -> void:
	saved_builds.erase(title)
	_write_builds()


func _write_builds() -> void:
	if not Cfg.persist_enabled():
		return
	var cf := ConfigFile.new()
	for k in saved_builds:
		cf.set_value("builds", k, saved_builds[k])
	cf.save(builds_path())
