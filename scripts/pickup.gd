extends Node3D
## Припас на земле. Наехал и подобрал (если он тебе нужен: полному мех не берёт).
## Виды: энергия, патроны, расходник (заряд случайной абилке с зарядами).

const KINDS := {
	"energy": {"color": Color(1.0, 0.85, 0.25), "name": "энергия"},
	"ammo": {"color": Color(1.0, 0.5, 0.2), "name": "патроны"},
	"charge": {"color": Color(0.4, 0.85, 1.0), "name": "расходник"},
	"supply": {"color": Color(0.45, 1.0, 0.5), "name": "снабжение"},
}

var kind := "ammo"
var seen := true
var team := -1                  # чей ящик: -1 — берёт любой; ящик снабжения Командира — только своя команда
var life := -1.0                # сколько лежит (секунды); -1 — пока не подберут
var supply := {}                # ящик снабжения: числа абилки (hp — ремонт, give_energy, give_ammo — доля патронов)
var _age := 0.0
var _box: Node3D
var _t := 0.0


func _ready() -> void:
	add_to_group("pickups")
	var col: Color = KINDS[kind]["color"]
	_box = Node3D.new()      # корень модели (крутится и покачивается)
	_box.scale = Vector3.ONE * 1.5
	add_child(_box)
	match kind:
		"energy":
			_build_battery(col)
		"ammo", "supply":
			_build_ammo(col)
		_:
			_build_missile(col)
	# светящееся кольцо на земле
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.85
	tm.outer_radius = 1.0
	tm.rings = 32
	ring.mesh = tm
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.albedo_color = col * 1.6
	ring.material_override = rm
	ring.scale = Vector3(1.0, 0.1, 1.0)
	ring.position.y = 0.05
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	_t = randf() * TAU


func _m(c: Color, metal := 0.3, rough := 0.5) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metal
	m.roughness = rough
	return m


func _glow_m(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = 2.5
	return m


func _part(mesh: Mesh, mat: Material, pos: Vector3, rot := Vector3.ZERO) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	_box.add_child(mi)


func _cyl(r: float, h: float, segs := 12, r2 := -1.0) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r if r2 < 0.0 else r2
	c.height = h
	c.radial_segments = segs
	c.rings = 1
	return c


func _bx(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


# энергия: батарея с жёлтыми светящимися кольцами
func _build_battery(col: Color) -> void:
	var body := _m(Color(0.16, 0.17, 0.19), 0.6, 0.35)
	_part(_cyl(0.32, 1.0), body, Vector3.ZERO)
	_part(_cyl(0.34, 0.1), _glow_m(col), Vector3(0, 0.28, 0))
	_part(_cyl(0.34, 0.1), _glow_m(col), Vector3(0, -0.28, 0))
	_part(_cyl(0.15, 0.16), _m(Color(0.7, 0.7, 0.72), 0.8, 0.3), Vector3(0, 0.58, 0))
	_part(_bx(Vector3(0.08, 0.3, 0.02)), _glow_m(col), Vector3(0, 0, 0.33))


# патроны: зелёный ящик с оранжевой полосой и гильзами сверху
func _build_ammo(col: Color) -> void:
	var box := _m(Color(0.27, 0.32, 0.18), 0.1, 0.7)
	_part(_bx(Vector3(1.0, 0.5, 0.65)), box, Vector3.ZERO)
	_part(_bx(Vector3(1.04, 0.08, 0.69)), _glow_m(col), Vector3(0, 0.05, 0))
	var brass := _m(Color(0.85, 0.62, 0.25), 0.9, 0.3)
	for i in 3:
		var x := -0.28 + i * 0.28
		_part(_cyl(0.08, 0.38, 8), brass, Vector3(x, 0.42, 0))
		_part(_cyl(0.0, 0.14, 8, 0.08), _m(Color(0.6, 0.45, 0.25), 0.8, 0.35), Vector3(x, 0.68, 0))


# расходник: голубая ракета на подставке
func _build_missile(col: Color) -> void:
	var white := _m(Color(0.85, 0.87, 0.9), 0.3, 0.4)
	_part(_cyl(0.16, 0.9, 10), white, Vector3(0, 0.05, 0))
	_part(_cyl(0.0, 0.32, 10, 0.16), _glow_m(col), Vector3(0, 0.66, 0))
	for i in 4:
		var a := TAU * i / 4.0
		_part(_bx(Vector3(0.04, 0.26, 0.2)), _m(Color(0.25, 0.27, 0.3)), Vector3(cos(a) * 0.17, -0.3, sin(a) * 0.17), Vector3(0, -a, 0))
	_part(_cyl(0.18, 0.06, 10), _glow_m(col), Vector3(0, 0.2, 0))


func _physics_process(delta: float) -> void:
	_t += delta
	_age += delta
	if life > 0.0 and _age > life:
		queue_free()
		return
	_box.position.y = 1.1 + sin(_t * 3.0) * 0.15
	_box.rotation.y = _t * 1.4
	visible = seen
	for m in get_tree().get_nodes_in_group("mechs"):
		if m.dead or (team >= 0 and m.team != team):
			continue
		var d: Vector3 = m.global_position - global_position
		d.y = 0
		if d.length() <= Cfg.pickup_radius + m.get_hit_radius() * 0.5 and _apply(m):
			if not (m.is_cloaked() and m.team != Fx.player_team):   # невидимку не выдаём
				Fx.burst(global_position + Vector3.UP, KINDS[kind]["color"], 2.0)
			if m.is_player:
				Sfx.play("pickup", -6.0, 0.05)
			queue_free()
			return


func _apply(m) -> bool:
	match kind:
		"energy":
			return m.add_energy(Cfg.loot_energy)
		"ammo":
			return m.add_ammo(Cfg.loot_ammo)
		"charge":
			return m.add_charge(Cfg.loot_charges)
		"supply":
			# ящик снабжения: всё сразу — патроны, энергия, ремонт (берёт, если хоть что-то нужно)
			var need: bool = m.needs_ammo() or m.energy < m.energy_max() - 1.0 or m.hp < m.max_hp() - 1.0
			if not need:
				return false
			m.add_ammo(float(supply.get("give_ammo", 0.5)))
			m.add_energy(float(supply.get("give_energy", 40.0)))
			m.heal(float(supply.get("hp", 60.0)))
			return true
	return false


# нужен ли этот припас меху (боты по этому решают, идти ли за ним)
func useful_for(m) -> bool:
	match kind:
		"energy":
			return m.energy < m.energy_max() * 0.7
		"ammo":
			return m.needs_ammo()
		"charge":
			return m.needs_charges()
		"supply":
			return (team < 0 or m.team == team) and (m.needs_ammo() or m.hp < m.max_hp() * 0.7)
	return false
