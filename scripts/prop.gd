extends Node3D
## Разрушаемая мелочь на карте: кучки ящиков (разлетаются на куски), столбики-фонари (падают целиком),
## мешки с песком (разлетаются), бетонные блоки (сдвигаются и заваливаются), заборы-решётки (падают плашмя),
## брошенные машины (мех сминает; взрыв поджигает — горит и остаётся обгорелым остовом; пули сквозь неё летят).
## Без урона и без влияния на бой — только декор (решение Сани 16.10.2026).
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
var kind := "crates"             # "crates" — разлетается на куски, "post" — столбик падает целиком
var _pivot: Node3D               # столбик: поворачивается у основания
var _lamp: MeshInstance3D        # плафон столбика: гаснет, когда столб упал
var half := Vector2.ZERO         # вытянутая мелочь (ряд мешков, блоки, забор): полуразмеры по своим X и Z
var _parts: Array = []           # детали мешков/блоков/забора: {mesh, xf, mat, group}
var _meshes: Array = []          # целый вид (по одной модели на материал)


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


# столбик: детали [размер, положение, материал] над основанием (основание остаётся на месте, оно в общей
# модели карты). Детали одного материала склеиваются; плафон (материал lamp_mat) — отдельно, чтобы погаснуть
func setup_post(parts: Array, lamp_mat: Material, r: float) -> void:
	kind = "post"
	radius = r
	_pivot = Node3D.new()
	_pivot.position = Vector3(0, 0.3, 0)
	add_child(_pivot)
	var by_mat := {}
	for pt in parts:
		if not by_mat.has(pt[2]):
			var st0 := SurfaceTool.new()
			st0.begin(Mesh.PRIMITIVE_TRIANGLES)
			by_mat[pt[2]] = st0
		var bm := BoxMesh.new()
		bm.size = pt[0]
		by_mat[pt[2]].append_from(bm, 0, Transform3D(Basis(), pt[1] - _pivot.position))
	for m in by_mat:
		var mi := MeshInstance3D.new()
		mi.mesh = by_mat[m].commit()
		mi.material_override = m
		_pivot.add_child(mi)
		if m == lamp_mat:
			_lamp = mi
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


# мешки, блоки, забор: детали {mesh, xf (в осях предмета), mat, group}; одинаковый материал склеивается.
# hx, hz — полуразмеры, по ним считается касание и взрыв
func setup_parts(parts: Array, k: String, hx: float, hz: float) -> void:
	kind = k
	_parts = parts
	half = Vector2(hx, hz)
	radius = maxf(hx, hz)
	_pivot = Node3D.new()
	add_child(_pivot)
	var by_mat := {}
	for pt in parts:
		if not by_mat.has(pt["mat"]):
			var st0 := SurfaceTool.new()
			st0.begin(Mesh.PRIMITIVE_TRIANGLES)
			by_mat[pt["mat"]] = st0
		for si in pt["mesh"].get_surface_count():
			by_mat[pt["mat"]].append_from(pt["mesh"], si, pt["xf"])
	for m in by_mat:
		var mi := MeshInstance3D.new()
		mi.mesh = by_mat[m].commit()
		mi.material_override = m
		_pivot.add_child(mi)
		_meshes.append(mi)


# насколько точка близко (по земле, от края предмета) — для взрывов (Fx.blast)
func blast_distance(pos: Vector3) -> float:
	if half == Vector2.ZERO:
		return maxf(Vector2(pos.x - global_position.x, pos.z - global_position.z).length() - radius, 0.0)
	var lp := global_transform.affine_inverse() * pos
	return Vector2(maxf(absf(lp.x) - half.x, 0.0), maxf(absf(lp.z) - half.y, 0.0)).length()


func _ready() -> void:
	add_to_group("props")
	add_to_group("damageable")
	_rng.seed = hash(global_position)


func get_hit_radius() -> float:
	return radius


var burnt := false                # машина сгорела


func take_damage(_amount: float, _point: Vector3, dir: Vector3, dmg_kind := "", who: Node = null) -> void:
	if kind == "car":
		if dmg_kind == "explosion" and not burnt:
			_ignite()
		return
	smash(dir, who)


# машина загорелась: огонь и дым (Fx.smolder), краска за пару секунд обгорает дочерна
func _ignite() -> void:
	burnt = true
	if broken:
		remove_from_group("damageable")
	Fx.smolder(self, Vector3(0, 0.9, 0), 1.5, 20.0)
	Fx.light_flash(global_position + Vector3.UP, Color(1.0, 0.55, 0.2), 8.0, 3.0, 0.3)
	var m = get_meta("car_mat", null)
	if m != null:
		var tw := create_tween()
		tw.tween_method(func(v: float) -> void: m.set_shader_parameter("burnt", v), 0.0, 1.0, 2.5)


func _physics_process(_delta: float) -> void:
	if broken:
		return
	var g = get_tree().current_scene
	if g == null or not g.has_method("units"):
		return
	var inv := global_transform.affine_inverse() if half != Vector2.ZERO else Transform3D()
	for u in g.units():
		var d := Vector3(global_position.x - u[1].x, 0, global_position.z - u[1].z)
		var touch := false
		if half != Vector2.ZERO:
			var lp: Vector3 = inv * u[1]
			touch = absf(lp.x) < half.x + float(u[3]) * 0.7 and absf(lp.z) < half.y + float(u[3]) * 0.7
		else:
			touch = d.length() < radius + float(u[3]) * 0.7
		if touch:
			var n: Node3D = u[0]
			var push: Vector3 = Vector3(n.velocity.x, 0, n.velocity.z) if "velocity" in n else d
			smash(push if push.length() > 0.5 else d, n)
			if u[4]:
				var k := 0.6 if kind == "jersey" else 0.75        # заминка; бетонные блоки держат сильнее
				n.velocity = Vector3(n.velocity.x * k, n.velocity.y, n.velocity.z * k)
			return


# сломать: кто сломал (если видно игроку) — куски летят в сторону удара
func smash(dir: Vector3, who: Node = null) -> void:
	if broken:
		return
	broken = true
	if kind != "car" or burnt:
		remove_from_group("damageable")      # несгоревшую смятую машину ещё можно поджечь
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
		if kind == "post":
			_fall(Vector3(_pivot.global_basis.x), true)     # сломали без нас: уже лежит
		elif kind == "fence":
			_fence_fall(global_basis.z, true)
		elif kind == "jersey":
			_knock(global_basis.z, true)
		elif kind == "car":
			_crush(global_basis.z, true)
		elif _intact != null:
			_intact.visible = false     # сломали без нас: обломки уже ушли в землю
		else:
			for mi in _meshes:
				mi.visible = false


# столбик падает в сторону удара: сначала медленно, потом быстрее, у земли подпрыгивает; плафон гаснет с искрами.
# Так и лежит до конца боя
func _fall(dir: Vector3, instant := false) -> void:
	var flat := Vector3(dir.x, 0, dir.z)
	flat = flat.normalized() if flat.length() > 0.01 else Vector3.RIGHT.rotated(Vector3.UP, _rng.randf() * TAU)
	var axis := Vector3.UP.cross(flat).normalized()          # ось падения в мире
	var start := _pivot.global_basis
	var lie := Basis(axis, PI * 0.5 - 0.05) * start
	if instant:
		_pivot.global_basis = lie
		if _lamp != null:
			_lamp.visible = false
		return
	var tw := _pivot.create_tween()
	tw.tween_method(func(k: float) -> void: _pivot.global_basis = Basis(axis, (PI * 0.5 - 0.05) * k * k) * start, 0.0, 1.0, 0.7)
	tw.tween_method(func(k: float) -> void: _pivot.global_basis = Basis(axis, PI * 0.5 - 0.05 - sin(k * PI) * 0.06) * start, 0.0, 1.0, 0.25)
	tw.tween_callback(func() -> void:
		var head := global_position + flat * 4.4 + Vector3.UP * 0.3
		Fx.spark(head, Vector3.UP, true, false)
		Fx.spark(head, (Vector3.UP + flat).normalized(), true, false)
		Fx.dust_ring(head, 1.2)
		Sfx.play_at("wall", head, -10.0, 0.2)
		if _lamp != null:
			_lamp.visible = false)


# забор падает плашмя в ту сторону, куда толкнули (поперёк своей линии), у земли пыль; так и лежит
func _fence_fall(dir: Vector3, instant := false) -> void:
	var nz := global_basis.z.normalized()
	var side := 1.0 if Vector3(dir.x, 0, dir.z).dot(nz) >= 0.0 else -1.0
	var axis := global_basis.x.normalized() * side                # ось падения — вдоль забора
	var start := _pivot.global_basis
	if instant:
		_pivot.global_basis = Basis(axis, PI * 0.5 - 0.04) * start
		return
	var tw := _pivot.create_tween()
	tw.tween_method(func(k: float) -> void: _pivot.global_basis = Basis(axis, (PI * 0.5 - 0.04) * k * k) * start, 0.0, 1.0, 0.55)
	tw.tween_method(func(k: float) -> void: _pivot.global_basis = Basis(axis, PI * 0.5 - 0.04 - sin(k * PI) * 0.05) * start, 0.0, 1.0, 0.2)
	tw.tween_callback(func() -> void:
		var mid := global_position + nz * side * 1.2
		Fx.dust_ring(mid, half.x * 0.9)
		Sfx.play_at("wall", mid, -8.0, 0.2))


# бетонные блоки: каждый сдвигается в сторону удара и заваливается, пылит. Так и лежат
func _knock(dir: Vector3, instant := false) -> void:
	var flat := Vector3(dir.x, 0, dir.z)
	flat = flat.normalized() if flat.length() > 0.01 else global_basis.z
	for mi in _meshes:
		mi.visible = false
	var groups := {}
	for pt in _parts:
		if not groups.has(pt["group"]):
			groups[pt["group"]] = []
		groups[pt["group"]].append(pt)
	for gi in groups:
		var holder := Node3D.new()
		add_child(holder)
		var center := Vector3.ZERO
		for pt in groups[gi]:
			center += pt["xf"].origin
		center /= float(groups[gi].size())
		center.y = 0.0
		holder.position = center
		for pt in groups[gi]:
			var mi := MeshInstance3D.new()
			mi.mesh = pt["mesh"]
			mi.material_override = pt["mat"]
			mi.transform = Transform3D(pt["xf"].basis, pt["xf"].origin - center)
			holder.add_child(mi)
		var shift := flat * _rng.randf_range(0.6, 1.8)
		var axis := Vector3.UP.cross(flat).normalized()
		var tilt := _rng.randf_range(0.25, 1.1)
		var gstart := holder.global_transform
		var gend := Transform3D(Basis(axis, tilt).rotated(Vector3.UP, _rng.randf_range(-0.4, 0.4)) * gstart.basis, gstart.origin + shift + Vector3.UP * 0.12 * tilt)
		if instant:
			holder.global_transform = gend
			continue
		var tw := holder.create_tween()
		tw.tween_method(func(k: float) -> void: holder.global_transform = gstart.interpolate_with(gend, 1.0 - (1.0 - k) * (1.0 - k)), 0.0, 1.0, 0.35)
		Fx.dust_ring(holder.global_position, 1.4)
	if not instant:
		Sfx.play_at("wall", global_position, -4.0, 0.15)


# мешки с песком: каждый мешок летит в сторону удара, кувыркается, лежит и уходит в землю
func _bags(dir: Vector3) -> void:
	var scene := get_tree().current_scene
	for mi in _meshes:
		mi.visible = false
	if scene == null:
		return
	var flat := Vector3(dir.x, 0, dir.z)
	flat = flat.normalized() if flat.length() > 0.01 else global_basis.z
	for pt in _parts:
		var mi := MeshInstance3D.new()
		mi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		mi.mesh = pt["mesh"]
		mi.material_override = pt["mat"]
		scene.add_child(mi)
		mi.global_transform = global_transform * pt["xf"]
		var out := Vector3(mi.global_position.x - global_position.x, 0, mi.global_position.z - global_position.z).normalized()
		var vel := flat * _rng.randf_range(1.5, 4.5) + out * _rng.randf_range(0.5, 2.0) + Vector3.UP * _rng.randf_range(1.5, 3.5)
		var spin := Vector3(_rng.randf_range(-6, 6), _rng.randf_range(-4, 4), _rng.randf_range(-6, 6))
		_fly(mi, vel, spin, 0.16)
	Fx.dust_ring(global_position, half.x)
	Sfx.play_at("step", global_position, -4.0, 0.2)


# машину смял мех: корпус проседает и чуть кренится, хруст и пыль, стёкла искрами; так и стоит
func _crush(dir: Vector3, instant := false) -> void:
	var flat := Vector3(dir.x, 0, dir.z)
	flat = flat.normalized() if flat.length() > 0.01 else global_basis.z
	var axis := Vector3.UP.cross(flat).normalized()
	var end := Basis(axis, _rng.randf_range(0.05, 0.16)) * _pivot.basis * Basis.from_scale(Vector3(1.06, 0.55, 1.04))
	if instant:
		_pivot.basis = end
		return
	var start := _pivot.basis
	var tw := _pivot.create_tween()
	tw.tween_method(func(k: float) -> void: _pivot.basis = start.slerp(end.orthonormalized(), k) * Basis.from_scale(Vector3.ONE.lerp(Vector3(1.06, 0.55, 1.04), k)), 0.0, 1.0, 0.18)
	Fx.dust_ring(global_position, 2.0)
	Fx.spark(global_position + Vector3.UP * 1.0, Vector3.UP, true, false)
	Fx.spark(global_position + Vector3.UP * 0.8 + flat, (Vector3.UP + flat).normalized(), true, false)
	Sfx.play_at("wall", global_position, -5.0, 0.2)
	Sfx.play_at("casing", global_position, -4.0, 0.3)


func _burst(dir: Vector3) -> void:
	if kind == "car":
		_crush(dir)
		return
	if kind == "post":
		_fall(dir)
		return
	if kind == "fence":
		_fence_fall(dir)
		return
	if kind == "jersey":
		_knock(dir)
		return
	if kind == "sandbags":
		_bags(dir)
		return
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
