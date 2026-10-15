extends MeshInstance3D
## Прицел. Кольцо показывает, куда сводятся стволы (на земле или на середине хитбокса врага под
## курсором, не ближе GUN_MIN_DIST), а его размер это текущий разброс. Две линии от меха это края
## конуса. Маленькая точка это курсор (куда корпус ещё доворачивает).

var mech: Node3D
var _im: ImmediateMesh
var _mat: StandardMaterial3D


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_im = ImmediateMesh.new()
	mesh = _im
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.vertex_color_use_as_albedo = true
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.no_depth_test = true
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat.render_priority = 10
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 1000.0


func _process(_delta: float) -> void:
	_im.clear_surfaces()
	if mech == null or mech.dead:
		return
	var y := maxf(mech.aim_point.y, 0.06)
	var origin: Vector3 = mech.get_global_transform_interpolated().origin
	origin.y = y
	var fwd: Vector3 = mech.torso_forward()
	var dist: float = maxf(mech.aim_distance(), mech.GUN_MIN_DIST)
	var center := origin + fwd * dist
	var spread: float = deg_to_rad(mech.get_spread_deg())

	_im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	# по кольцу на каждую пушку: у разных пушек разный разброс
	var col := Color(1, 1, 1, 0.9)
	for i in mech.weapons.size():
		var w: Dictionary = mech.weapons[i]
		var sd: float = mech.weapon_spread_deg(i)
		var radius := maxf(tan(deg_to_rad(sd)) * dist, 0.28)
		# цвет: белый когда точно, оранжевый когда разброс большой
		var k := clampf((sd - w["spread_stand"]) / maxf(w["spread_run"] - w["spread_stand"], 0.1), 0.0, 1.0)
		var c := Color(1, 1, 1, 0.9).lerp(Color(1.0, 0.5, 0.15, 0.9), k)
		if dist > mech.w_range(i):
			c.a = 0.35     # цель дальше, чем бьёт эта пушка
		_ring(center, radius, 0.09, c)
		if i == 0:
			col = c
	_ring(center, 0.07, 0.07, col)
	# заряд рельсотрона: дуга вокруг прицела заполняется
	for i in mech.weapons.size():
		if mech.weapons[i]["type"] == "rail":
			var k: float = mech.rail_charge(i)
			if k > 0.01:
				_arc(center, 1.1 + i * 0.25, 0.12, k, Color(0.5, 0.9, 1.0, 0.95))
		elif mech.weapons[i]["type"] == "lob":
			# гранатомёт: куда на земле полетит граната (не дальше его дальности)
			var dl := minf(maxf(mech.aim_ground_distance(), mech.GUN_MIN_DIST), mech.w_range(i))
			_ring(Vector3(origin.x, 0.06, origin.z) + fwd * dl, 0.5, 0.06, Color(1.0, 0.7, 0.3, 0.6))
	# края конуса разброса
	var faint := Color(col.r, col.g, col.b, 0.22)
	for sgn in [-1.0, 1.0]:
		var d := fwd.rotated(Vector3.UP, spread * sgn)
		_line(origin + d * 3.2, origin + d * dist, 0.05, faint)
	# курсор, если корпус ещё не довернул
	var cur: Vector3 = mech.aim_point
	cur.y = y
	if cur.distance_to(center) > 0.6:
		_ring(cur, 0.16, 0.06, Color(1, 1, 1, 0.6))
	_im.surface_end()


func _ring(c: Vector3, r: float, w: float, col: Color) -> void:
	var n := 40
	var r0 := maxf(r - w * 0.5, 0.0)
	var r1 := r + w * 0.5
	for i in n:
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		_quad(c + d0 * r0, c + d0 * r1, c + d1 * r1, c + d1 * r0, col)


func _line(a: Vector3, b: Vector3, w: float, col: Color) -> void:
	var dir := (b - a)
	dir.y = 0
	if dir.length() < 0.01:
		return
	var side := dir.normalized().cross(Vector3.UP) * w * 0.5
	_quad(a - side, a + side, b + side, b - side, col)


func _quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	for v in [a, b, c, a, c, d]:
		_im.surface_set_color(col)
		_im.surface_add_vertex(v)


func _arc(c: Vector3, r: float, w: float, k: float, col: Color) -> void:
	var n := int(40 * k) + 1
	for i in n:
		var a0 := -PI / 2 + TAU * k * i / n
		var a1 := -PI / 2 + TAU * k * (i + 1) / n
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		_quad(c + d0 * (r - w), c + d0 * (r + w), c + d1 * (r + w), c + d1 * (r - w), col)
