extends RefCounted
## Карта проходимости для ботов. Карта разбита на клетки по 2 метра,
## клетки рядом со стенами и укрытиями помечены как непроходимые.
## По этой сетке бот находит путь в обход препятствий.

const CELL := 2.0
const MARGIN := 1.9      # запас от стены, чтобы мех не цеплялся боками

var _grid := AStarGrid2D.new()
var _rect := Rect2(-48, -48, 96, 96)
var _nx := 0
var _nz := 0
var _points: Array = []


# rect: границы карты (x, z, ширина, глубина); boxes: укрытия и постройки [x, z, ширина, высота, глубина, (поворот°)];
# points: точки, которые надо обходить (мишени)
func build(rect: Rect2, boxes: Array, points: Array) -> void:
	_rect = rect
	_nx = int(rect.size.x / CELL)
	_nz = int(rect.size.y / CELL)
	_grid.region = Rect2i(0, 0, _nx, _nz)
	_grid.cell_size = Vector2(CELL, CELL)
	_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_grid.update()
	_points = points
	for y in _nz:
		for x in _nx:
			_eval(Vector2i(x, y), boxes)


func _eval(cell: Vector2i, boxes: Array) -> void:
	var p := cell_center(cell)
	var rect := _rect
	var solid := p.x < rect.position.x + 3.5 or p.x > rect.end.x - 3.5 or p.z < rect.position.y + 3.5 or p.z > rect.end.y - 3.5
	if not solid:
		for b in boxes:
			# 6-е поле (если есть и это число) — поворот укрытия в градусах
			var rot: float = float(b[5]) if b.size() > 5 and (b[5] is float or b[5] is int) else 0.0
			if rot == 0.0:
				if absf(p.x - b[0]) < b[2] * 0.5 + MARGIN and absf(p.z - b[1]) < b[4] * 0.5 + MARGIN:
					solid = true
					break
			elif Maps.in_box(p.x, p.z, b[0], b[1], b[2], b[4], rot, MARGIN):
				solid = true
				break
	if not solid:
		for e in _points:
			if Vector2(p.x - e.x, p.z - e.z).length() < 3.2:
				solid = true
				break
	_grid.set_point_solid(cell, solid)


# стену сломали: пересчитать клетки вокруг неё (boxes: все препятствия, которые остались)
func refresh(area: Rect2, boxes: Array) -> void:
	var a := cell_of(Vector3(area.position.x - 4.0, 0, area.position.y - 4.0))
	var b := cell_of(Vector3(area.end.x + 4.0, 0, area.end.y + 4.0))
	for y in range(a.y, b.y + 1):
		for x in range(a.x, b.x + 1):
			_eval(Vector2i(x, y), boxes)


func cell_of(pos: Vector3) -> Vector2i:
	var x := int(floor((pos.x - _rect.position.x) / CELL))
	var y := int(floor((pos.z - _rect.position.y) / CELL))
	return Vector2i(clampi(x, 0, _nx - 1), clampi(y, 0, _nz - 1))


func cell_center(c: Vector2i) -> Vector3:
	return Vector3(_rect.position.x + (c.x + 0.5) * CELL, 0, _rect.position.y + (c.y + 0.5) * CELL)


func is_free(pos: Vector3) -> bool:
	if not _rect.has_point(Vector2(pos.x, pos.z)):
		return false
	return not _grid.is_point_solid(cell_of(pos))


# ближайшая проходимая клетка (если точка оказалась внутри запретной зоны)
func nearest_free(c: Vector2i) -> Vector2i:
	if not _grid.is_point_solid(c):
		return c
	for r in range(1, 8):
		var best := Vector2i(-1, -1)
		var best_d := 1e9
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var q := Vector2i(c.x + dx, c.y + dy)
				if q.x < 0 or q.y < 0 or q.x >= _nx or q.y >= _nz:
					continue
				if _grid.is_point_solid(q):
					continue
				var d := float(dx * dx + dy * dy)
				if d < best_d:
					best_d = d
					best = q
		if best.x >= 0:
			return best
	return c


func find_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	var out := PackedVector3Array()
	var a := nearest_free(cell_of(from))
	var b := nearest_free(cell_of(to))
	for id in _grid.get_id_path(a, b):
		out.append(cell_center(id))
	return out
