extends RefCounted
## Заготовки для графики, которые делаются один раз и потом переиспользуются:
## фактура брони (панели, болты, потёртости), сетки камней и пучков травы.
## Всё генерируется кодом, внешних картинок и моделей нет.

static var _panel_tex: ImageTexture
static var _panel_norm: ImageTexture
static var _rocks: Array = []
static var _grass: ArrayMesh


# фактура брони: светлые панели, тёмные швы, болты по углам, лёгкая грязь.
# Белая основа, цвет даёт материал (умножается).
static func panel_texture() -> ImageTexture:
	if _panel_tex != null:
		return _panel_tex
	var size := 256
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.seed = 7
	noise.frequency = 0.035
	var fine := FastNoiseLite.new()
	fine.seed = 11
	fine.frequency = 0.3
	# панели разного размера: делим квадрат на прямоугольники
	var cuts_x := [0, 64, 112, 176, 256]
	var cuts_y := [0, 48, 128, 160, 224, 256]
	for y in size:
		for x in size:
			var v := 0.86 + noise.get_noise_2d(x, y) * 0.08 + fine.get_noise_2d(x, y) * 0.04
			# швы между панелями
			var seam := false
			for cx in cuts_x:
				if absi(x - cx) <= 1:
					seam = true
			for cy in cuts_y:
				if absi(y - cy) <= 1:
					seam = true
			if seam:
				v *= 0.68
			# светлая фаска вдоль шва
			for cx in cuts_x:
				if x - cx == 2:
					v *= 1.08
			for cy in cuts_y:
				if y - cy == 2:
					v *= 1.08
			img.set_pixel(x, y, Color(v, v, v))
	# болты в углах панелей
	for cx in cuts_x:
		for cy in cuts_y:
			for dx in [5, -6]:
				for dy in [5, -6]:
					var bx: int = cx + dx
					var by: int = cy + dy
					if bx < 1 or by < 1 or bx > size - 2 or by > size - 2:
						continue
					for oy in range(-1, 2):
						for ox in range(-1, 2):
							var c := img.get_pixel(bx + ox, by + oy)
							img.set_pixel(bx + ox, by + oy, c * (0.6 if (ox == 0 and oy == 0) else 0.8))
	img.generate_mipmaps()
	_panel_tex = ImageTexture.create_from_image(img)
	return _panel_tex


# применить фактуру к материалу брони (развёртка по осям объекта, без UV).
# Если в assets/textures лежат текстуры брони, берём их (цвет, рельеф, шероховатость), иначе рисуем сами
static func apply_panels(m: StandardMaterial3D, scale := 1.2, kind := "armor") -> void:
	var t := textures(kind)
	m.uv1_triplanar = true
	m.uv1_triplanar_sharpness = 4.0
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if t.is_empty():
		m.albedo_texture = panel_texture()
		m.uv1_scale = Vector3.ONE * scale
		return
	m.albedo_texture = t["albedo"]
	m.uv1_scale = Vector3.ONE * scale * 0.35
	if t.has("normal"):
		m.normal_enabled = true
		m.normal_texture = t["normal"]
		m.normal_scale = 0.9
	if t.has("rough"):
		m.roughness_texture = t["rough"]
		m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED


static var _tex_cache := {}


# текстуры из assets/textures: {albedo, normal, rough} или пусто, если файлов нет
static func textures(kind: String) -> Dictionary:
	if _tex_cache.has(kind):
		return _tex_cache[kind]
	var out := {}
	for part in ["albedo", "normal", "rough"]:
		var path := "res://assets/textures/%s_%s.jpg" % [kind, part]
		if ResourceLoader.exists(path):
			out[part] = load(path)
	if not out.has("albedo"):
		out = {}
	_tex_cache[kind] = out
	return out


# спрайт эффекта из assets/fx (белый на прозрачном) или null
static func fx_tex(name: String) -> Texture2D:
	var key := "fx_" + name
	if _tex_cache.has(key):
		return _tex_cache[key]
	var path := "res://assets/fx/%s.png" % name
	var t: Texture2D = load(path) if ResourceLoader.exists(path) else null
	_tex_cache[key] = t
	return t


static var _bevels := {}


# коробка со скошенными рёбрами: на рёбрах ловится блик, детали перестают выглядеть "картонными"
static func bevel_box(size: Vector3, bevel := -1.0) -> ArrayMesh:
	if bevel < 0.0:
		bevel = minf(minf(size.x, size.y), size.z) * 0.12
	bevel = clampf(bevel, 0.0, minf(minf(size.x, size.y), size.z) * 0.45)
	var key := "%s_%.3f" % [size, bevel]
	if _bevels.has(key):
		return _bevels[key]
	var h := size * 0.5
	var c := bevel
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# 6 основных граней (уменьшены на фаску)
	var faces := [
		[Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)],
		[Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, -1)],
		[Vector3(0, 1, 0), Vector3(0, 0, 1), Vector3(1, 0, 0)],
		[Vector3(0, -1, 0), Vector3(0, 0, -1), Vector3(1, 0, 0)],
		[Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0)],
		[Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(0, 1, 0)],
	]
	for f in faces:
		var n: Vector3 = f[0]
		var u: Vector3 = f[1]
		var w: Vector3 = f[2]
		var center := n * (h * n.abs()).length()
		var hu := (h * u.abs()).length() - c
		var hw := (h * w.abs()).length() - c
		_quad(st, center - u * hu - w * hw, center + u * hu - w * hw, center + u * hu + w * hw, center - u * hu + w * hw, n)
	# 12 рёбер-фасок
	var axes := [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
	for ai in 3:
		var a: Vector3 = axes[ai]
		var b: Vector3 = axes[(ai + 1) % 3]
		var d: Vector3 = axes[(ai + 2) % 3]
		var ha := (h * a).length() - c
		for sb in [-1.0, 1.0]:
			for sd in [-1.0, 1.0]:
				var hb := (h * b).length()
				var hd := (h * d).length()
				var p1: Vector3 = b * sb * hb + d * sd * (hd - c)
				var p2: Vector3 = b * sb * (hb - c) + d * sd * hd
				var n2: Vector3 = (b * sb + d * sd).normalized()
				_quad(st, p1 - a * ha, p1 + a * ha, p2 + a * ha, p2 - a * ha, n2)
	# 8 уголков
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				var px: Vector3 = Vector3(sx * h.x, sy * (h.y - c), sz * (h.z - c))
				var py: Vector3 = Vector3(sx * (h.x - c), sy * h.y, sz * (h.z - c))
				var pz: Vector3 = Vector3(sx * (h.x - c), sy * (h.y - c), sz * h.z)
				var n3: Vector3 = Vector3(sx, sy, sz).normalized()
				_tri(st, px, py, pz, n3)
	st.generate_tangents()
	var mesh := st.commit()
	_bevels[key] = mesh
	return mesh


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3) -> void:
	_tri(st, a, b, c, n)
	_tri(st, a, c, d, n)


# треугольник, развёрнутый лицом наружу (по нормали)
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, n: Vector3) -> void:
	if (b - a).cross(c - a).dot(n) > 0.0:
		var t := b
		b = c
		c = t
	for p in [a, b, c]:
		st.set_normal(n)
		st.set_uv(Vector2(p.x + p.z, p.y))
		st.add_vertex(p)


# неровный камень: сфера, продавленная шумом, с гранёными гранями
static func rock_mesh(variant: int) -> ArrayMesh:
	while _rocks.size() <= variant:
		_rocks.append(null)
	if _rocks[variant] != null:
		return _rocks[variant]
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	sm.radial_segments = 10
	sm.rings = 6
	var arrays := sm.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var noise := FastNoiseLite.new()
	noise.seed = 100 + variant * 17
	noise.frequency = 1.6
	var squash := Vector3(1.0 + (variant % 3) * 0.15, 0.6 + (variant % 2) * 0.15, 1.0 - (variant % 3) * 0.1)
	for i in verts.size():
		var v := verts[i]
		var k := 1.0 + noise.get_noise_3dv(v * 2.0) * 0.45
		v = v * k * squash
		if v.y < -0.1:
			v.y = -0.1 - (v.y + 0.1) * 0.2      # плоское дно
		verts[i] = v
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in idx:
		st.add_vertex(verts[i])
	st.generate_normals()
	_rocks[variant] = st.commit()
	return _rocks[variant]


# пучок травы: несколько узких травинок веером
static func grass_mesh() -> ArrayMesh:
	if _grass != null:
		return _grass
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for b in 5:
		var a := TAU * b / 5.0 + rng.randf_range(-0.3, 0.3)
		var dir := Vector3(cos(a), 0, sin(a))
		var side := Vector3(-dir.z, 0, dir.x)
		var h := rng.randf_range(0.35, 0.65)
		var lean := dir * rng.randf_range(0.15, 0.35)
		var w := 0.09
		var p0 := dir * 0.05 - side * w
		var p1 := dir * 0.05 + side * w
		var p2 := dir * 0.05 + lean + Vector3.UP * h
		st.set_normal(Vector3.UP)
		st.add_vertex(p0)
		st.add_vertex(p1)
		st.add_vertex(p2)
	_grass = st.commit()
	return _grass


# Склейка деталей: все неподвижные детали внутри одного узла с одинаковым материалом
# становятся одной моделью. Рисуется одним вызовом вместо десятков — главный выигрыш в кадрах.
# Склеиваются только «листья» (детали без своих детей) с материалом из списка mats.
# Узлы-контейнеры (бёдра, подвесы пушек, радар) остаются и двигаются как раньше.
# keep: детали, которые нельзя трогать (на них ссылается код: вспышки, лучи, кольца)
static func merge_meshes(root: Node, mats: Array, keep: Array = []) -> void:
	var groups := {}
	for c in root.get_children():
		if c is MeshInstance3D:
			var mi: MeshInstance3D = c
			if mi.get_child_count() > 0 or not mi.visible or keep.has(mi) or mi.mesh == null:
				continue
			var mat: Material = mi.material_override
			if mat == null or not mats.has(mat):
				continue
			var key := "%d_%d" % [mat.get_instance_id(), mi.cast_shadow]
			if not groups.has(key):
				groups[key] = []
			groups[key].append(mi)
	for key in groups:
		var list: Array = groups[key]
		if list.size() >= 2:
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			for mi in list:
				for s in mi.mesh.get_surface_count():
					st.append_from(mi.mesh, s, mi.transform)
			var am := st.commit()
			var out := MeshInstance3D.new()
			out.mesh = am
			out.material_override = list[0].material_override
			out.cast_shadow = list[0].cast_shadow
			root.add_child(out)
			for mi in list:
				root.remove_child(mi)
				mi.free()
	# дальше вглубь: контейнеры со своими деталями
	for c in root.get_children():
		if c.get_child_count() > 0 and not keep.has(c):
			merge_meshes(c, mats, keep)
