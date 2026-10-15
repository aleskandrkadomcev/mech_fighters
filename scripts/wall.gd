extends StaticBody3D
## Разрушаемая стена или барьер. Три вида:
##   целая     - как построили;
##   с трещиной - когда здоровье упало ниже порога (F2, «Стены»): по бетону идут трещины, сыплются куски;
##               хитбокс тот же, что у целой;
##   разрушена - стена обваливается (куски разлетаются и падают, пыль), остаётся низкое основание из обломков.
##               Хитбокса больше нет: сквозь неё ходят, стреляют и видят.
## Ломается от любого урона: пуль, лучей, взрывов. Своих и чужих не различает.

signal destroyed(wall: Node3D)

const Art := preload("res://scripts/art.gd")

var c: Array = []               # [x, z, ширина, высота, глубина, вид]
var art: Node                   # map_art.gd: материалы карты
var extra := 30.0               # насколько стена выше для выстрелов, чем на вид (игра плоская)
var team := -1                  # ничья: бьют все
var hp := 100.0
var hp_max := 100.0
var state := 0                  # 0 целая, 1 с трещиной, 2 разрушена
var seen := true
var _intact: Node3D
var _rubble: Node3D
var _cs: CollisionShape3D
var _mat: ShaderMaterial        # свой бетон: у каждой стены свои трещины
var _crack := 0.0
var _crack_target := 0.0
var _flash := 0.0
var _rng := RandomNumberGenerator.new()

static var _chunk_mesh: Mesh


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	add_to_group("walls")
	add_to_group("damageable")
	_rng.seed = int(c[0] * 131.0 + c[1] * 17.0)
	position = Vector3(c[0], 0, c[1])
	reset_physics_interpolation()
	var w: float = c[2]
	var h: float = c[3]
	var d: float = c[4]
	hp_max = maxf(w, d) * Cfg.wall_hp_per_m * (0.6 if kind() == "barrier" else 1.0)
	set_meta("top", h)      # настоящая высота (столкновение для пуль выше): граната её перелетает
	hp = hp_max
	_cs = CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(w, h + extra, d)
	_cs.shape = bs
	_cs.position = Vector3(0, (h + extra) * 0.5, 0)
	add_child(_cs)

	_mat = art.new_mat(Color(0.42, 0.42, 0.42), 0, 0.85, 0.0, Color.BLACK, 0.0,
		"concrete" if kind() == "wall" else "concrete2", 0.22)
	_mat.set_shader_parameter("tex_tint", Color(0.8, 0.8, 0.8))
	_intact = Node3D.new()
	add_child(_intact)
	if kind() == "barrier":
		_build_barrier(_intact, w, h, d)
	else:
		_build_wall(_intact, w, h, d)
	Art.merge_meshes(_intact, [_mat, art.dark_metal()])


func kind() -> String:
	return c[5] if c.size() > 5 else "wall"


func box() -> Array:
	return [c[0], c[1], c[2], c[3], c[4]]


func is_destroyed() -> bool:
	return state == 2


func get_hit_radius() -> float:
	return minf(c[2], c[4]) * 0.5


# расстояние от точки взрыва до стены (до ближайшего края, а не до центра)
func blast_distance(p: Vector3) -> float:
	var dx := maxf(absf(p.x - c[0]) - c[2] * 0.5, 0.0)
	var dz := maxf(absf(p.z - c[1]) - c[4] * 0.5, 0.0)
	return Vector2(dx, dz).length()


func take_damage(amount: float, pos: Vector3, _dir: Vector3, _kind := "", _src: Node = null) -> void:
	if state == 2 or amount <= 0.0:
		return
	hp -= amount
	_flash = 0.05
	if state == 0 and hp <= hp_max * Cfg.wall_crack_at:
		_set_cracked(pos)
	if hp <= 0.0:
		_collapse()


func _process(delta: float) -> void:
	if not is_equal_approx(_crack, _crack_target):
		_crack = move_toward(_crack, _crack_target, delta * 2.0)
		_mat.set_shader_parameter("crack", _crack)
	if _flash > 0.0:
		_flash -= delta


# ------------------------------------------------------------------
#  Трещина и обрушение
# ------------------------------------------------------------------

func _set_cracked(pos: Vector3) -> void:
	state = 1
	_crack_target = 0.55
	# вид с трещиной: сколы, сорванная шапка
	_intact.queue_free()
	_intact = Node3D.new()
	add_child(_intact)
	if kind() == "barrier":
		_build_barrier(_intact, c[2], c[3], c[4], true)
	else:
		_build_wall(_intact, c[2], c[3], c[4], true)
	Art.merge_meshes(_intact, [_mat, art.dark_metal()])
	# с края отваливаются куски
	Sfx.play_at("wall", pos, -2.0, 0.1)
	_debris(6, 0.5, 0.25)


func _collapse() -> void:
	state = 2
	hp = 0.0
	_cs.set_deferred("disabled", true)
	_intact.visible = false
	remove_from_group("damageable")
	var w: float = c[2]
	var h: float = c[3]
	var d: float = c[4]
	_rubble = Node3D.new()
	add_child(_rubble)
	_build_rubble(_rubble, w, h, d)
	Art.merge_meshes(_rubble, [_mat, art.dark_metal()])
	_debris(clampi(int(maxf(w, d) * 1.2), 10, 26), 1.0, 1.0)
	Fx.dust_ring(global_position, maxf(w, d) * 0.6)
	Fx.explosion(global_position + Vector3.UP * h * 0.4, minf(maxf(w, d) * 0.35, 4.0))
	Sfx.play_at("wallbreak", global_position, 2.0, 0.08)
	destroyed.emit(self)


# куски бетона: вылетают из стены, падают, катятся, через несколько секунд уходят в землю
func _debris(count: int, size_k: float, speed_k: float) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var w: float = c[2]
	var h: float = c[3]
	var d: float = c[4]
	var mats := [_mat, art.dark_metal()]
	for i in count:
		var mi := MeshInstance3D.new()
		mi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		var s := Vector3(_rng.randf_range(0.4, 1.3), _rng.randf_range(0.3, 1.0), _rng.randf_range(0.4, 1.2)) * size_k
		mi.mesh = Art.bevel_box(s, minf(minf(s.x, s.y), s.z) * 0.2)
		mi.material_override = mats[0] if _rng.randf() < 0.85 else mats[1]
		scene.add_child(mi)
		var start := global_position + Vector3(_rng.randf_range(-w, w) * 0.45, _rng.randf_range(0.3, h), _rng.randf_range(-d, d) * 0.45)
		mi.global_position = start
		mi.rotation = Vector3(_rng.randf() * TAU, _rng.randf() * TAU, _rng.randf() * TAU)
		var out := Vector3(start.x - global_position.x, 0, start.z - global_position.z)
		if out.length() < 0.1:
			out = Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1))
		var vel := out.normalized() * _rng.randf_range(2.0, 7.0) * speed_k + Vector3.UP * _rng.randf_range(2.0, 7.0) * speed_k
		var spin := Vector3(_rng.randf_range(-8, 8), _rng.randf_range(-8, 8), _rng.randf_range(-8, 8))
		_fly(mi, vel, spin, s.y * 0.5)


# простая физика куска: летит по дуге, подпрыгивает на земле, замирает и уходит в землю
func _fly(mi: MeshInstance3D, vel: Vector3, spin: Vector3, rest_y: float) -> void:
	var state_d := {"v": vel, "life": 0.0, "spin": spin}
	var tw := mi.create_tween()
	tw.tween_method(func(_x: float) -> void:
		var dt := get_process_delta_time()
		state_d["life"] += dt
		var v: Vector3 = state_d["v"]
		v.y -= 25.0 * dt
		var p := mi.global_position + v * dt
		if p.y < rest_y:
			p.y = rest_y
			v.y = -v.y * 0.3
			v.x *= 0.6
			v.z *= 0.6
			state_d["spin"] *= 0.5
		state_d["v"] = v
		mi.global_position = p
		mi.rotation += state_d["spin"] * dt, 0.0, 1.0, 1.6)
	tw.tween_interval(3.0)
	tw.tween_property(mi, "position:y", mi.position.y - 1.5, 1.5).as_relative()
	tw.tween_callback(mi.queue_free)


# ------------------------------------------------------------------
#  Вид
# ------------------------------------------------------------------

func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, rot := Vector3.ZERO, shadow := true) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = Art.bevel_box(size, minf(minf(size.x, size.y), size.z) * 0.08)
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	if not shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


# сайфай-стена: бетон, металлическая шапка, колонны, светящаяся полоса.
# damaged: стена с трещиной — сколы сверху, часть шапки сорвана, остальное перекошено
func _build_wall(root: Node3D, w: float, h: float, d: float, damaged := false) -> void:
	var long_x := w >= d
	var length := w if long_x else d
	var thick := d if long_x else w
	var hb := h - 0.35
	# тело стены кусками по ~2 м: у повреждённой стены у части кусков сколот верх
	var n := maxi(int(length / 2.0), 1)
	var seg := length / n
	for i in n:
		var t := -length * 0.5 + (i + 0.5) * seg
		var hh := hb
		if damaged and _rng.randf() < 0.45:
			hh = hb - _rng.randf_range(0.4, minf(1.4, hb * 0.5))
		var size := Vector3(seg + 0.02, hh, thick) if long_x else Vector3(thick, hh, seg + 0.02)
		var pos := Vector3(t, hh * 0.5, 0) if long_x else Vector3(0, hh * 0.5, t)
		_box(root, size, pos, _mat)
		# металлическая шапка над куском: у повреждённой часть сорвана, часть перекошена
		if hh >= hb - 0.01:
			var rot := Vector3.ZERO
			if damaged:
				if _rng.randf() < 0.35:
					continue
				rot = Vector3(_rng.randf_range(-0.12, 0.12), _rng.randf_range(-0.1, 0.1), _rng.randf_range(-0.12, 0.12))
			var csize := Vector3(seg + 0.02, 0.35, thick + 0.2) if long_x else Vector3(thick + 0.2, 0.35, seg + 0.02)
			_box(root, csize, Vector3(pos.x, h - 0.17, pos.z), art.dark_metal(), rot)
	_box(root, Vector3(w + 0.3, 0.4, d + 0.3), Vector3(0, 0.2, 0), art.dark_metal())
	var nc := maxi(int(length / 4.0), 1)
	for i in nc + 1:
		if damaged and _rng.randf() < 0.3:
			continue
		var t := -length * 0.5 + length * float(i) / float(nc)
		var cpos := Vector3(t, h * 0.5, 0) if long_x else Vector3(0, h * 0.5, t)
		var size2 := Vector3(0.5, h + 0.1, thick + 0.35) if long_x else Vector3(thick + 0.35, h + 0.1, 0.5)
		_box(root, size2, cpos, art.metal(), Vector3(_rng.randf_range(-0.06, 0.06), 0, _rng.randf_range(-0.06, 0.06)) if damaged else Vector3.ZERO)
	if damaged:
		return
	var strip_col := Color(1.0, 0.62, 0.2)
	for s in [-1.0, 1.0]:
		var pos2 := Vector3(0, h - 0.55, (thick * 0.5 + 0.04) * s) if long_x else Vector3((thick * 0.5 + 0.04) * s, h - 0.55, 0)
		var size3 := Vector3(length * 0.9, 0.08, 0.04) if long_x else Vector3(0.04, 0.08, length * 0.9)
		_box(root, size3, pos2, art.light_strip(strip_col), Vector3.ZERO, false)


# невысокий барьер: бетонный блок с наклонной гранью и жёлто-чёрной полосой
func _build_barrier(root: Node3D, w: float, h: float, d: float, damaged := false) -> void:
	_box(root, Vector3(w, h * 0.75, d), Vector3(0, h * 0.375, 0), _mat)
	_box(root, Vector3(w + 0.1, 0.22, d + 0.1), Vector3(0, h * 0.75 - 0.3, 0), art.hazard())
	if not damaged:
		_box(root, Vector3(w * 0.86, h * 0.25, d * 0.8), Vector3(0, h * 0.875, 0), _mat)
		_box(root, Vector3(w * 0.3, 0.1, 0.1), Vector3(0, h + 0.02, 0), art.light_strip(Color(0.3, 0.85, 1.0)), Vector3.ZERO, false)
		return
	# скол: верхний блок сдвинут и наклонён, кусок отвалился
	_box(root, Vector3(w * 0.5, h * 0.22, d * 0.75), Vector3(-w * 0.2, h * 0.86, 0), _mat, Vector3(0.1, 0.2, -0.15))


# разрушенное основание: цоколь, неровные остатки стены, торчащая арматура, куски вокруг
func _build_rubble(root: Node3D, w: float, h: float, d: float) -> void:
	var long_x := w >= d
	var length := w if long_x else d
	var thick := d if long_x else w
	_box(root, Vector3(w + 0.3, 0.4, d + 0.3), Vector3(0, 0.2, 0), art.dark_metal())
	var n := maxi(int(length / 1.6), 2)
	for i in n:
		var t := -length * 0.5 + (i + 0.5) * length / n
		var hh := _rng.randf_range(0.25, 0.95)
		var size := Vector3(length / n * 1.05, hh, thick * _rng.randf_range(0.8, 1.05))
		if not long_x:
			size = Vector3(size.z, size.y, size.x)
		var pos := Vector3(t, hh * 0.5 + 0.2, 0) if long_x else Vector3(0, hh * 0.5 + 0.2, t)
		_box(root, size, pos, _mat, Vector3(_rng.randf_range(-0.1, 0.1), 0, _rng.randf_range(-0.12, 0.12)))
	# арматура
	for i in maxi(int(length / 3.0), 1):
		var t2 := _rng.randf_range(-length * 0.45, length * 0.45)
		var pos2 := Vector3(t2, 0.9, 0) if long_x else Vector3(0, 0.9, t2)
		_box(root, Vector3(0.08, _rng.randf_range(0.8, 1.8), 0.08), pos2, art.dark_metal(), Vector3(_rng.randf_range(-0.5, 0.5), 0, _rng.randf_range(-0.5, 0.5)))
	# куски вокруг основания
	for i in int(length * 0.8):
		var s := Vector3(_rng.randf_range(0.3, 0.9), _rng.randf_range(0.2, 0.5), _rng.randf_range(0.3, 0.8))
		var off := Vector3(_rng.randf_range(-w * 0.5 - 1.2, w * 0.5 + 1.2), s.y * 0.5, _rng.randf_range(-d * 0.5 - 1.2, d * 0.5 + 1.2))
		_box(root, s, off, _mat, Vector3(0, _rng.randf() * TAU, _rng.randf_range(-0.3, 0.3)))
	_mat.set_shader_parameter("crack", 0.6)
	_mat.set_shader_parameter("tex_tint", Color(0.62, 0.6, 0.57))
	_crack_target = 0.6
	_crack = 0.6
