extends Node3D
## Разрушаемая мелочь на карте (пока кучки ящиков; потом бочки, столбы, техника — ROADMAP, графика п. 8).
## Не мешает ходить, стрелять и видеть: мехи и крипы идут сквозь неё, боты и крипы её не обходят
## (её нет в карте проходимости). Ломается с первого касания меха или крипа и от взрыва:
## куски разлетаются, лежат несколько секунд и уходят в землю (только картинка; будущему серверу
## достаточно знать «предмет N сломан»). Мех, который её проломил, чуть теряет скорость.
## Сломали в тумане войны — игрок видит целую кучку, пока не посмотрит туда сам (иначе выдаст врага).

const Art := preload("res://scripts/art.gd")

var team := -1                 # ничья: взрыв любой команды её ломает
var radius := 1.6              # по земле: насколько близко подойти, чтобы сломать
var broken := false
var _intact: MeshInstance3D
var _boxes: Array = []         # [размер, положение, поворот] коробок кучки — из них куски
var _mat: Material
var _hidden_break := false     # сломана в тумане: показать, когда игрок туда посмотрит
var _check_t := 0.0
var _rng := RandomNumberGenerator.new()


# кучка ящиков из коробок [размер, положение, поворот] одним материалом (одна отрисовка, пока целая)
func setup(boxes: Array, mat: Material, r: float) -> void:
	_boxes = boxes
	_mat = mat
	radius = r
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for b in boxes:
		var bm := BoxMesh.new()
		bm.size = b[0]
		st.append_from(bm, 0, Transform3D(Basis.from_euler(b[2]), b[1]))
	_intact = MeshInstance3D.new()
	_intact.mesh = st.commit()
	_intact.material_override = mat
	add_child(_intact)


func _ready() -> void:
	add_to_group("props")
	add_to_group("damageable")
	_rng.seed = hash(global_position)


func get_hit_radius() -> float:
	return radius


func take_damage(_amount: float, _point: Vector3, dir: Vector3, _kind := "", who: Node = null) -> void:
	smash(dir, who)


func _physics_process(_delta: float) -> void:
	if broken:
		return
	var g = get_tree().current_scene
	if g == null or not g.has_method("units"):
		return
	for u in g.units():
		var d := Vector3(global_position.x - u[1].x, 0, global_position.z - u[1].z)
		if d.length() < radius + float(u[3]) * 0.7:
			var n: Node3D = u[0]
			var push: Vector3 = Vector3(n.velocity.x, 0, n.velocity.z) if "velocity" in n else d
			smash(push if push.length() > 0.5 else d, n)
			if u[4]:
				n.velocity = Vector3(n.velocity.x * 0.75, n.velocity.y, n.velocity.z * 0.75)     # лёгкая заминка
			return


# сломать: кто сломал (если видно игроку) — куски летят в сторону удара
func smash(dir: Vector3, who: Node = null) -> void:
	if broken:
		return
	broken = true
	remove_from_group("damageable")
	var g = get_tree().current_scene
	var seen := true
	if g != null and g.has_method("is_visible_to") and who != null and is_instance_valid(who):
		seen = g.is_visible_to(Fx.player_team, who)
	if not seen:
		_hidden_break = true        # целая на вид, пока игрок сам не посмотрит сюда
		return
	_burst(dir)


func _process(delta: float) -> void:
	if not _hidden_break:
		return
	_check_t -= delta
	if _check_t > 0.0:
		return
	_check_t = 0.3
	var g = get_tree().current_scene
	if g != null and "vision" in g and g.vision != null and g.vision.point_visible(Fx.player_team, global_position, radius):
		_hidden_break = false
		_intact.visible = false     # сломали без нас: обломки уже ушли в землю


func _burst(dir: Vector3) -> void:
	_intact.visible = false
	var scene := get_tree().current_scene
	if scene == null:
		return
	var flat := Vector3(dir.x, 0, dir.z)
	flat = flat.normalized() if flat.length() > 0.01 else Vector3.RIGHT.rotated(Vector3.UP, _rng.randf() * TAU)
	var xf := global_transform
	for b in _boxes:
		var s: Vector3 = b[0]
		var center: Vector3 = xf * b[1]
		# каждый ящик — половинка и несколько досок
		var parts: Array = [Vector3(s.x, s.y * 0.5, s.z)]
		for k in 3:
			parts.append(Vector3(s.x * _rng.randf_range(0.6, 1.0), 0.1, s.z * _rng.randf_range(0.2, 0.35)))
		for ps in parts:
			var mi := MeshInstance3D.new()
			mi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
			mi.mesh = Art.bevel_box(ps, minf(minf(ps.x, ps.y), ps.z) * 0.2)
			mi.material_override = _mat
			scene.add_child(mi)
			mi.global_position = center + Vector3(_rng.randf_range(-0.3, 0.3), _rng.randf_range(-0.2, 0.3), _rng.randf_range(-0.3, 0.3))
			mi.rotation = Vector3(_rng.randf() * TAU, _rng.randf() * TAU, _rng.randf() * TAU)
			var vel := (flat * _rng.randf_range(2.0, 6.0) + Vector3(_rng.randf_range(-1.5, 1.5), 0, _rng.randf_range(-1.5, 1.5))) + Vector3.UP * _rng.randf_range(2.0, 5.0)
			var spin := Vector3(_rng.randf_range(-9, 9), _rng.randf_range(-9, 9), _rng.randf_range(-9, 9))
			_fly(mi, vel, spin, minf(ps.y, minf(ps.x, ps.z)) * 0.5)
	Fx.dust_ring(global_position, radius * 1.4)
	Sfx.play_at("wall", global_position, -6.0, 0.15)


# кусок летит по дуге, подпрыгивает на земле, лежит и уходит в землю (как куски стен)
func _fly(mi: MeshInstance3D, vel: Vector3, spin: Vector3, rest_y: float) -> void:
	var st := {"v": vel, "spin": spin}
	var tw := mi.create_tween()
	tw.tween_method(func(_x: float) -> void:
		var dt := mi.get_process_delta_time()
		var v: Vector3 = st["v"]
		v.y -= 25.0 * dt
		var p := mi.global_position + v * dt
		if p.y < rest_y:
			p.y = rest_y
			v.y = -v.y * 0.3
			v.x *= 0.55
			v.z *= 0.55
			st["spin"] *= 0.45
		st["v"] = v
		mi.global_position = p
		mi.rotation += st["spin"] * dt, 0.0, 1.0, 1.4)
	tw.tween_interval(3.5)
	tw.tween_property(mi, "position:y", -1.0, 1.5).as_relative()
	tw.tween_callback(mi.queue_free)
