extends Node3D
## Внешний вид карты: скалы, низкие постройки, мачты с проводами, фонари, трава и мелкие камни,
## тёмные пятна-тени под объектами. Разрушаемые стены и барьеры рисует wall.gd (у каждой свой вид).
## Игровую часть (столкновения укрытий) делает main.gd; здесь только вид
## и столкновения низких построек (их не видно сквозь, но через них видно и стреляется).
## Где лежат постройки, мачты и фонари, берётся из файла карты.

const Art := preload("res://scripts/art.gd")
const WorldShader := preload("res://shaders/world.gdshader")
const GrassShader := preload("res://shaders/grass.gdshader")
const Prop := preload("res://scripts/prop.gd")

const DECOR_KINDS := {"container": "Контейнер", "generator": "Генератор", "tank": "Цистерна", "terminal": "Терминал",
	"crates": "Ящики", "antenna": "Антенна", "sandbags": "Мешки с песком", "jersey": "Бетонные блоки", "fence": "Забор",
	"car": "Брошенная машина"}

var vision: Node
var ground_mask: Image           # где дороги и площадки (из main.gd): трава там не растёт
var biome: Image                 # где сухая грязь, грунт и камни (из main.gd): там травы меньше
var puddles: Array = []          # лужи (из main.gd): Vector3(x, радиус, z); в них трава не растёт
var mask_rect := Rect2()
var decor_boxes: Array = []      # [x, z, ширина, высота, глубина] для карты проходимости ботов
var prop_boxes: Array = []       # то же для разрушаемой мелочи (ящики): ботам не мешает, только трава под ней не растёт
var _mats := {}
var _rng := RandomNumberGenerator.new()


func _mat(key: String, col: Color, mode: int, rough := 0.85, metal := 0.0, glow := Color.BLACK, glow_pow := 0.0, tex := "", tex_scale := 0.25, use_normal := true) -> ShaderMaterial:
	if _mats.has(key):
		return _mats[key]
	var m := new_mat(col, mode, rough, metal, glow, glow_pow, tex, tex_scale, use_normal)
	_mats[key] = m
	return m


# новый материал карты (с туманом войны); tex: имя набора текстур из assets/textures
func new_mat(col: Color, mode: int, rough := 0.85, metal := 0.0, glow := Color.BLACK, glow_pow := 0.0, tex := "", tex_scale := 0.25, use_normal := true) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = WorldShader
	m.set_shader_parameter("albedo", col)
	m.set_shader_parameter("mode", mode)
	m.set_shader_parameter("roughness", rough)
	m.set_shader_parameter("metallic", metal)
	m.set_shader_parameter("glow", glow)
	m.set_shader_parameter("glow_power", glow_pow)
	if tex != "":
		var t := Art.textures(tex)
		if not t.is_empty():
			m.set_shader_parameter("use_tex", 1.0)
			m.set_shader_parameter("tex_albedo", t["albedo"])
			if t.has("normal"):
				m.set_shader_parameter("tex_normal", t["normal"])
			if t.has("rough"):
				m.set_shader_parameter("tex_rough", t["rough"])
			m.set_shader_parameter("tex_scale", tex_scale)
			m.set_shader_parameter("use_normal", 1.0 if use_normal else 0.0)
	if vision != null:
		vision.register_material(m)
	return m


func concrete() -> ShaderMaterial:
	return _mat("concrete", Color(0.42, 0.42, 0.42), 0, 0.85, 0.0, Color.BLACK, 0.0, "concrete", 0.22)


func dark_metal() -> ShaderMaterial:
	return _mat("dmetal", Color(0.16, 0.17, 0.19), 2, 0.55, 0.5, Color.BLACK, 0.0, "darkmetal", 0.4)


func metal() -> ShaderMaterial:
	return _mat("metal", Color(0.36, 0.38, 0.41), 2, 0.5, 0.45, Color.BLACK, 0.0, "plates", 0.3)


func rock() -> ShaderMaterial:
	var m := _mat("rock", Color(0.36, 0.34, 0.31), 1, 0.95, 0.0, Color.BLACK, 0.0, "rock2", 0.18, false)
	m.set_shader_parameter("tex_tint", Color(0.88, 0.8, 0.72))    # тёплый серо-бурый, как камни в цели
	m.set_shader_parameter("tex_sat", 0.35)                       # мох на текстуре слишком зелёный
	return m


func light_strip(col: Color) -> ShaderMaterial:
	return _mat("glow_%s" % col.to_html(), col, 3, 0.5, 0.0, col, 2.2)


func hazard() -> ShaderMaterial:
	return _mat("hazard", Color(0.75, 0.55, 0.12), 2, 0.6, 0.2, Color.BLACK, 0.0, "paint_yellow", 0.5)


# Всё неподвижное складывается в общие пачки по материалу и в конце сливается в одну сетку
# на материал: так видеокарте рисовать в сотни раз меньше отдельных предметов.
var _batches := {}     # ключ -> {mat, shadow, st}


func _add(mesh: Mesh, xf: Transform3D, mat: Material, shadow: bool) -> void:
	var key := "%d_%s" % [mat.get_instance_id(), shadow]
	if not _batches.has(key):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_batches[key] = {"mat": mat, "shadow": shadow, "st": st}
	_batches[key]["st"].append_from(mesh, 0, xf)


func _flush() -> void:
	for key in _batches:
		var b: Dictionary = _batches[key]
		var mi := MeshInstance3D.new()
		mi.mesh = b["st"].commit()
		mi.material_override = b["mat"]
		if not b["shadow"]:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
	_batches.clear()


func _box(parent: Transform3D, size: Vector3, pos: Vector3, mat: Material, rot := Vector3.ZERO, shadow := true) -> void:
	var bm := BoxMesh.new()
	bm.size = size
	_add(bm, parent * Transform3D(Basis.from_euler(rot), pos), mat, shadow)


func _cyl(parent: Transform3D, r: float, h: float, pos: Vector3, mat: Material, rot := Vector3.ZERO, segs := 12) -> void:
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = segs
	cm.rings = 1
	_add(cm, parent * Transform3D(Basis.from_euler(rot), pos), mat, true)


# ------------------------------------------------------------------
#  Главная сборка
# ------------------------------------------------------------------

# covers: укрытия [x, z, ширина, высота, глубина, вид]; edges: стены по краю карты [центр, размер];
# map: данные карты (украшения, фонари, мачты)
func build(covers: Array, edges: Array, map_rect: Rect2, no_grass: Array, map: Dictionary) -> void:
	_rng.seed = 1234
	for c in covers:
		var kind: String = c[5] if c.size() > 5 else "wall"
		if kind == "rock":
			_rock_cluster(c)
		_blob(Vector3(c[0], 0, c[1]), Vector2(c[2] + 2.5, c[4] + 2.5), deg_to_rad(Maps.cover_rot(c)))
	for e in edges:
		_edge_wall(e[0], e[1])
	for d in map.get("decor", []):
		_decor(d[0], Vector3(float(d[1]), 0, float(d[2])), deg_to_rad(float(d[3]) if d.size() > 3 else 0.0))
	# большие мачты с проводами убраны (Саня, 16.10.2026: слишком большие и не нужны); провода теперь
	# лежат по земле от базы к турелям (main._build_cables)
	for l in map.get("lamps", []):
		_lamp(Vector3(float(l[0]), 0, float(l[1])))
	_scatter(map_rect, covers, no_grass)
	_flush()


# ------------------------------------------------------------------
#  Укрытия
# ------------------------------------------------------------------

# скала: несколько валунов, заполняющих площадь укрытия
func _rock_cluster(c: Array) -> void:
	var w: float = c[2]
	var h: float = c[3]
	var d: float = c[4]
	var count := clampi(int(w * d / 6.0), 3, 9)
	for i in count:
		var mesh := Art.rock_mesh(_rng.randi_range(0, 5))
		var sx := _rng.randf_range(0.85, 1.05) * maxf(w, d) * 0.95
		var sy := _rng.randf_range(0.85, 1.15) * h * 1.7
		var sz := _rng.randf_range(0.85, 1.05) * minf(w, d) * 1.1
		if i > 0:
			sx *= 0.65
			sy *= _rng.randf_range(0.5, 0.85)
			sz *= 0.65
		# сдвиг валуна внутри скалы — в осях скалы (скалу можно повернуть в редакторе)
		var off := Vector3(_rng.randf_range(-w, w) * 0.3 * float(i > 0), 0.0, _rng.randf_range(-d, d) * 0.3 * float(i > 0))
		var pos := Vector3(c[0], 0.0, c[1]) + off.rotated(Vector3.UP, deg_to_rad(Maps.cover_rot(c)))
		_add(mesh, Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(sx, sy, sz)), pos), rock(), true)


# стена по краю карты
func _edge_wall(center: Vector3, size: Vector3) -> void:
	var root := Transform3D(Basis(), center)
	_box(root, size, Vector3.ZERO, concrete())
	_box(root, Vector3(size.x + 0.3, 0.4, size.z + 0.3), Vector3(0, size.y * 0.5, 0), dark_metal())
	var long_x := size.x > size.z
	var length := size.x if long_x else size.z
	var n := int(length / 6.0)
	for i in n + 1:
		var t := -length * 0.5 + length * float(i) / float(n)
		var pos := Vector3(t, 0, 0) if long_x else Vector3(0, 0, t)
		var sz := Vector3(0.7, size.y + 0.6, size.z + 0.5) if long_x else Vector3(size.x + 0.5, size.y + 0.6, 0.7)
		_box(root, sz, pos + Vector3(0, 0.3, 0), metal())


# мягкое тёмное пятно на земле под объектом (вместе с затенением в углах, SSAO)
func _blob(pos: Vector3, size: Vector2, rot := 0.0) -> void:
	if not _mats.has("blob"):
		var sh := Shader.new()
		sh.code = """shader_type spatial;
render_mode unshaded, depth_draw_never, shadows_disabled, cull_disabled;
uniform float strength = 0.25;
void fragment() {
	vec2 q = abs(UV - 0.5) * 2.0;
	float d = max(q.x, q.y);
	ALBEDO = vec3(0.0);
	ALPHA = (1.0 - smoothstep(0.55, 1.0, d)) * strength;
}
"""
		var m := ShaderMaterial.new()
		m.shader = sh
		_mats["blob"] = m
	var pm := PlaneMesh.new()
	pm.size = size
	_add(pm, Transform3D(Basis(Vector3.UP, rot), pos + Vector3.UP * 0.03), _mats["blob"], false)


# ------------------------------------------------------------------
#  Низкие постройки (сквозь них видно и стреляется, но мехи о них упираются)
# ------------------------------------------------------------------

func _decor(kind: String, pos: Vector3, rot: float) -> void:
	var root := Transform3D(Basis(Vector3.UP, rot), pos)
	var foot := Vector2(3, 3)
	var height := 2.4
	match kind:
		"container":
			foot = Vector2(2.6, 6.2)
			height = 2.6
			var col: Color = [Color(0.55, 0.22, 0.12), Color(0.18, 0.32, 0.45), Color(0.4, 0.42, 0.2)][_rng.randi_range(0, 2)]
			var body := _mat("cont_%s" % col.to_html(), col, 2, 0.6, 0.3)
			_box(root, Vector3(2.5, 2.5, 6.0), Vector3(0, 1.25, 0), body)
			for i in 7:
				_box(root, Vector3(2.62, 2.3, 0.08), Vector3(0, 1.25, -2.7 + i * 0.9), body)
			_box(root, Vector3(2.6, 0.12, 6.1), Vector3(0, 2.55, 0), dark_metal())
		"generator":
			foot = Vector2(3.4, 2.4)
			height = 2.2
			_box(root, Vector3(3.2, 1.6, 2.2), Vector3(0, 0.8, 0), metal())
			_box(root, Vector3(2.6, 0.6, 1.6), Vector3(0, 1.9, 0), dark_metal())
			for i in 4:
				_box(root, Vector3(0.08, 1.1, 2.24), Vector3(-1.1 + i * 0.35, 0.8, 0), dark_metal())
			_box(root, Vector3(0.5, 0.12, 0.12), Vector3(1.0, 1.65, 1.12), light_strip(Color(0.3, 1.0, 0.45)), Vector3.ZERO, false)
			_cyl(root, 0.18, 1.4, Vector3(-1.2, 2.3, 0.6), dark_metal())
		"tank":
			foot = Vector2(3.6, 3.6)
			height = 2.8
			_cyl(root, 1.7, 2.6, Vector3(0, 1.3, 0), metal(), Vector3.ZERO, 20)
			_cyl(root, 1.8, 0.2, Vector3(0, 0.5, 0), dark_metal(), Vector3.ZERO, 20)
			_cyl(root, 1.8, 0.2, Vector3(0, 2.2, 0), dark_metal(), Vector3.ZERO, 20)
			_box(root, Vector3(0.6, 0.15, 0.6), Vector3(0, 2.65, 0), hazard())
		"terminal":
			foot = Vector2(1.6, 1.2)
			height = 1.8
			_box(root, Vector3(1.4, 1.2, 0.9), Vector3(0, 0.6, 0), metal())
			_box(root, Vector3(1.2, 0.7, 0.2), Vector3(0, 1.4, -0.2), dark_metal(), Vector3(-0.4, 0, 0))
			_box(root, Vector3(0.9, 0.45, 0.04), Vector3(0, 1.42, -0.32), light_strip(Color(0.3, 0.85, 1.0)), Vector3(-0.4, 0, 0), false)
		"crates":
			# разрушаемая мелочь: не мешает ходить, ломается от касания и взрыва (prop.gd)
			# деревянные ящики: доски (ambientCG Planks021) по самому ящику, по две поперечные планки
			var cm := _mat("crate", Color(0.36, 0.33, 0.22), 2, 0.8, 0.1, Color.BLACK, 0.0, "wood", 0.6)
			cm.set_shader_parameter("obj_space", 1.0)
			cm.set_shader_parameter("tex_tint", Color(0.5, 0.42, 0.32))     # старое потёртое дерево, не жёлтая сосна
			cm.set_shader_parameter("tex_sat", 0.65)
			var pr := Prop.new()
			pr.position = pos
			pr.rotation.y = rot
			var boxes: Array = []
			for b in [[Vector3(1.4, 1.2, 1.2), Vector3(-0.7, 0.6, 0), Vector3(0, 0.2, 0)],
					[Vector3(1.2, 1.0, 1.2), Vector3(0.8, 0.5, 0.3), Vector3(0, -0.3, 0)],
					[Vector3(1.0, 0.8, 1.0), Vector3(-0.5, 1.6, 0.1), Vector3(0, 0.6, 0)]]:
				boxes.append(b)
				var s: Vector3 = b[0]
				for k in [-0.3, 0.3]:      # планки вокруг ящика, чуть толще его
					var off: Vector3 = Basis.from_euler(b[2]) * Vector3(s.x * k, 0, 0)
					boxes.append([Vector3(0.12, s.y + 0.04, s.z + 0.04), b[1] + off, b[2]])
			pr.setup(boxes, cm, 1.6)
			add_child(pr)
			var wide := absf(sin(rot)) < 0.5
			_blob(pos, Vector2(5.0, 4.4) if wide else Vector2(4.4, 5.0))
			prop_boxes.append([pos.x, pos.z, 3.2 if wide else 2.6, 2.0, 2.6 if wide else 3.2])
			return
		"sandbags", "jersey", "fence":
			_small_stuff(kind, pos, rot)
			return
		"car":
			_car(pos, rot)
			return
		"antenna":
			foot = Vector2(2.2, 2.2)
			height = 2.0
			_box(root, Vector3(2.0, 1.0, 2.0), Vector3(0, 0.5, 0), metal())
			_cyl(root, 0.08, 6.0, Vector3(0, 4.0, 0), dark_metal(), Vector3.ZERO, 6)
			_box(root, Vector3(1.4, 0.06, 0.06), Vector3(0, 6.0, 0), dark_metal())
			_box(root, Vector3(0.18, 0.18, 0.18), Vector3(0, 7.05, 0), light_strip(Color(1.0, 0.2, 0.15)), Vector3.ZERO, false)
	# столкновение: мехи упираются, вижен и выстрелы проходят (слой построек)
	var body2 := StaticBody3D.new()
	body2.collision_layer = 32
	body2.collision_mask = 0
	body2.position = pos
	body2.rotation.y = rot
	add_child(body2)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(foot.x, height, foot.y)
	cs.shape = bs
	cs.position = Vector3(0, height * 0.5, 0)
	body2.add_child(cs)
	var fx: float = foot.x if absf(sin(rot)) < 0.5 else foot.y
	var fz: float = foot.y if absf(sin(rot)) < 0.5 else foot.x
	_blob(pos, Vector2(fx + 1.8, fz + 1.8))
	decor_boxes.append([pos.x, pos.z, fx, height, fz])


# ------------------------------------------------------------------
#  Фонари (маленькие столбики, падают — prop.gd)
# ------------------------------------------------------------------

# разрушаемая мелочь рядами (prop.gd): мешки с песком полукругом (выпуклостью по +X, как стоят перед
# турелью к врагу), бетонные блоки «джерси» в ряд, забор-решётка из трёх пролётов. Без урона — только декор
func _small_stuff(kind: String, pos: Vector3, rot: float) -> void:
	var pr := Prop.new()
	pr.position = pos
	pr.rotation.y = rot
	var parts: Array = []
	var hx := 1.0
	var hz := 1.0
	match kind:
		"sandbags":
			var bag := _mat("sandbag", Color(0.6, 0.53, 0.38), 0, 0.95, 0.0, Color.BLACK, 0.0, "canvas", 1.2)
			bag.set_shader_parameter("obj_space", 1.0)
			bag.set_shader_parameter("tex_tint", Color(0.62, 0.54, 0.4))
			var R := 4.4
			for row in 2:
				var n := 6 - row
				for i in n:
					var a := deg_to_rad(-55.0 + 110.0 * (float(i) + 0.5 * row) / float(6 - 1)) if n > 1 else 0.0
					var p := Vector3(cos(a) * R, 0.17 + row * 0.3, sin(a) * R)
					var b := Basis(Vector3.UP, -a + PI * 0.5 + _rng.randf_range(-0.12, 0.12)) * Basis(Vector3.RIGHT, _rng.randf_range(-0.06, 0.06))
					parts.append({"mesh": Art.bevel_box(Vector3(0.95, 0.32, 0.5), 0.13), "xf": Transform3D(b, p), "mat": bag, "group": i})
			hx = R + 0.4
			hz = R * 0.85
		"jersey":
			var conc := _mat("jersey", Color(0.55, 0.55, 0.53), 0, 0.85, 0.0, Color.BLACK, 0.0, "concrete", 0.35)
			conc.set_shader_parameter("obj_space", 1.0)
			conc.set_shader_parameter("tex_tint", Color(0.72, 0.7, 0.66))     # не белые: старый грязный бетон
			var strip := hazard()
			for i in 3:
				var x := (float(i) - 1.0) * 2.15
				var b := Basis(Vector3.UP, _rng.randf_range(-0.05, 0.05))
				parts.append({"mesh": Art.bevel_box(Vector3(2.0, 0.32, 0.78), 0.05), "xf": Transform3D(b, Vector3(x, 0.16, 0)), "mat": conc, "group": i})
				parts.append({"mesh": Art.bevel_box(Vector3(2.0, 0.6, 0.36), 0.06), "xf": Transform3D(b, Vector3(x, 0.6, 0)), "mat": conc, "group": i})
				parts.append({"mesh": Art.bevel_box(Vector3(0.5, 0.12, 0.37), 0.02), "xf": Transform3D(b, Vector3(x - 0.55, 0.72, 0)), "mat": strip, "group": i})
			hx = 3.3
			hz = 0.5
		"fence":
			var post := dark_metal()
			var grid := _fence_mat()
			for i in 4:
				var x := (float(i) - 1.5) * 3.0
				parts.append({"mesh": Art.bevel_box(Vector3(0.12, 2.3, 0.12), 0.02), "xf": Transform3D(Basis(), Vector3(x, 1.15, 0)), "mat": post, "group": 0})
			for i in 3:
				var qm := QuadMesh.new()
				qm.size = Vector2(3.0, 2.0)
				qm.center_offset = Vector3(0, 0, 0)
				parts.append({"mesh": qm, "xf": Transform3D(Basis(), Vector3((float(i) - 1.0) * 3.0, 1.15, 0)), "mat": grid, "group": 0})
				parts.append({"mesh": Art.bevel_box(Vector3(3.0, 0.06, 0.06), 0.01), "xf": Transform3D(Basis(), Vector3((float(i) - 1.0) * 3.0, 2.17, 0)), "mat": post, "group": 0})
			hx = 4.7
			hz = 0.35
	pr.setup_parts(parts, kind, hx, hz)
	add_child(pr)
	var wide := absf(sin(rot)) < 0.5
	prop_boxes.append([pos.x, pos.z, hx * 2.0 if wide else hz * 2.0, 1.0, hz * 2.0 if wide else hx * 2.0])


# брошенная техника (модели Kenney Car Kit, CC0): краска выцвела, ржавчина пятнами, грязь снизу; пропорции
# чуть приплюснуты (у Kenney игрушечные). Мех сминает (prop.gd, вид «car»), взрыв поджигает — горит остовом
const CAR_MODELS := ["sedan", "suv", "delivery", "truck-flat", "hatchback-sports"]
const CAR_SHADER := """shader_type spatial;
uniform sampler2D atlas : source_color, filter_linear_mipmap;
uniform float burnt = 0.0;
uniform sampler2D fog_tex : filter_linear, repeat_disable;
uniform vec4 fog_rect = vec4(-120.0, -70.0, 240.0, 140.0);
uniform float fog_dark = 0.0;
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
float h3(vec3 p) { p = fract(p * 0.3183099 + 0.1); p *= 17.0; return fract(p.x * p.y * p.z * (p.x + p.y + p.z)); }
float n3(vec3 x) {
	vec3 i = floor(x); vec3 f = fract(x); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(h3(i), h3(i + vec3(1, 0, 0)), f.x), mix(h3(i + vec3(0, 1, 0)), h3(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(h3(i + vec3(0, 0, 1)), h3(i + vec3(1, 0, 1)), f.x), mix(h3(i + vec3(0, 1, 1)), h3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}
void fragment() {
	vec3 c = texture(atlas, UV).rgb;
	float l = dot(c, vec3(0.3, 0.59, 0.11));
	c = mix(vec3(l), c, 0.3) * 0.36;                                   // краска выцвела и потемнела
	float n = n3(wpos * 2.3);
	float rust = smoothstep(0.38, 0.68, n3(wpos * 0.8 + 5.0) * 0.7 + n * 0.3);
	c = mix(c, vec3(0.28, 0.14, 0.06) * (0.6 + 0.7 * n), rust * 0.85);  // ржавчина пятнами
	c = mix(c, vec3(0.2, 0.16, 0.11), smoothstep(0.55, 0.8, n3(wpos * 1.6 + 11.0)) * 0.5);   // пыль и грязь
	c *= mix(0.55, 1.0, clamp(wpos.y / 1.3, 0.0, 1.0));                // грязь снизу
	c = mix(c, vec3(0.035, 0.03, 0.028) * (0.7 + 0.6 * n), burnt);     // обгорел
	float vis = texture(fog_tex, (wpos.xz - fog_rect.xy) / fog_rect.zw).r;
	c *= 1.0 - fog_dark * (1.0 - vis);
	ALBEDO = c;
	ROUGHNESS = mix(0.7, 0.95, max(rust, burnt));
	METALLIC = 0.25 * (1.0 - max(rust, burnt));
}
"""
static var _car_shader: Shader


func _car(pos: Vector3, rot: float) -> void:
	var pick: String = CAR_MODELS[absi(int(pos.x * 7.0 + pos.z * 13.0)) % CAR_MODELS.size()]
	var path := "res://assets/props/cars/%s.glb" % pick
	if not ResourceLoader.exists(path):
		return
	if _car_shader == null:
		_car_shader = Shader.new()
		_car_shader.code = CAR_SHADER
	var scene: Node3D = (load(path) as PackedScene).instantiate()
	var mat := ShaderMaterial.new()
	mat.shader = _car_shader
	if vision != null:
		vision.register_material(mat)
	var k := 1.2
	var squash := Basis.from_scale(Vector3(k, k * 0.82, k))
	var parts: Array = []
	for mi in scene.find_children("*", "MeshInstance3D", true, false):
		var m: Mesh = mi.mesh
		var src = m.surface_get_material(0)
		if src != null and src.get("albedo_texture") != null and mat.get_shader_parameter("atlas") == null:
			mat.set_shader_parameter("atlas", src.albedo_texture)
		var xf: Transform3D = Transform3D(squash, Vector3.ZERO) * (scene.global_transform.affine_inverse() * mi.global_transform if mi.is_inside_tree() else _rel_xf(scene, mi))
		parts.append({"mesh": m, "xf": xf, "mat": mat, "group": 0})
	scene.free()
	var pr := Prop.new()
	pr.position = pos
	pr.rotation.y = rot
	pr.setup_parts(parts, "car", 0.95 * k, 1.35 * k)
	pr.set_meta("car_mat", mat)
	add_child(pr)
	_blob(pos, Vector2(2.4, 3.6) * k if absf(sin(rot)) < 0.5 else Vector2(3.6, 2.4) * k)
	prop_boxes.append([pos.x, pos.z, 2.0 * k, 1.0, 2.8 * k] if absf(sin(rot)) < 0.5 else [pos.x, pos.z, 2.8 * k, 1.0, 2.0 * k])


# положение детали модели относительно корня (модель ещё не в сцене — считаем по цепочке родителей)
func _rel_xf(root: Node3D, n: Node3D) -> Transform3D:
	var xf := Transform3D()
	var cur: Node = n
	while cur != null and cur != root:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf


# сетка забора: картинка с прозрачностью (ambientCG Fence007A), отсекается по альфе, видна с обеих сторон
func _fence_mat() -> Material:
	if _mats.has("fence"):
		return _mats["fence"]
	var m := StandardMaterial3D.new()
	var t = load("res://assets/textures/fence_albedo.png") if ResourceLoader.exists("res://assets/textures/fence_albedo.png") else null
	if t != null:
		m.albedo_texture = t
	m.albedo_color = Color(0.62, 0.62, 0.6)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.5
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.metallic = 0.6
	m.roughness = 0.5
	m.uv1_scale = Vector3(3.0, 2.0, 1.0)
	_mats["fence"] = m
	return m


# фонарь — маленький столбик: бетонное основание в общей модели карты, сам столб с плафоном — разрушаемая
# мелочь (prop.gd): падает от касания меха или крипа и от взрыва, плафон гаснет
func _lamp(pos: Vector3) -> void:
	var root := Transform3D(Basis(), pos)
	_box(root, Vector3(0.6, 0.3, 0.6), Vector3(0, 0.15, 0), concrete())
	var lamp_mat := light_strip(Color(1.0, 0.85, 0.55))
	var pr := Prop.new()
	pr.position = pos
	pr.rotation.y = 0.0     # как раньше: плечо фонаря смотрит по +X (общий _rng не трогаем — от него раскладка травы)
	pr.setup_post([[Vector3(0.18, 4.5, 0.18), Vector3(0, 2.4, 0), dark_metal()],
		[Vector3(1.0, 0.14, 0.3), Vector3(0.35, 4.6, 0), dark_metal()],
		[Vector3(0.6, 0.06, 0.24), Vector3(0.5, 4.52, 0), lamp_mat]], lamp_mat, 0.6)
	add_child(pr)


# ------------------------------------------------------------------
#  Трава и мелкие камни
# ------------------------------------------------------------------

# на дороге, площадке или в укрытии траву не сажаем (по той же картинке, что и шейдер земли)
const GRASS_CHUNK := 16          # трава режется на куски 16×16 м: рисуются только куски в кадре
const GRASS_PER_M2 := 5.0        # кустов на квадратный метр там, где трава гуще всего (высокая графика)


# густая трава кустами (Art.grass_bush_mesh). Где расти нельзя (дороги, площадки, укрытия, постройки),
# считается один раз сеткой 1×1 м; густота — по карте земли (на грязи и камнях мало) и шуму кочек
func _grass(rect: Rect2, covers: Array, no_grass: Array) -> void:
	var w := int(rect.size.x)
	var h := int(rect.size.y)
	var ok := PackedByteArray()
	ok.resize(w * h)
	ok.fill(1)
	if ground_mask != null and ground_mask.get_width() == w and ground_mask.get_height() == h:
		for y in h:
			for x in w:
				var c := ground_mask.get_pixel(x, y)
				if c.r > 0.25 or c.g > 0.2 or c.b > 0.2:
					ok[y * w + x] = 0
	var block := func(cx: float, cz: float, hx: float, hz: float) -> void:
		for y in range(maxi(int(cz - hz - rect.position.y), 0), mini(int(cz + hz - rect.position.y) + 1, h)):
			for x in range(maxi(int(cx - hx - rect.position.x), 0), mini(int(cx + hx - rect.position.x) + 1, w)):
				ok[y * w + x] = 0
	for c in covers:
		var rot := Maps.cover_rot(c)
		if rot == 0.0:
			block.call(c[0], c[1], c[2] * 0.5 + 0.6, c[4] * 0.5 + 0.6)
			continue
		# повёрнутое укрытие: проверяем каждую клетку его описанного прямоугольника
		var br := Maps.box_rect(c[0], c[1], c[2] + 1.2, c[4] + 1.2, rot)
		for y in range(maxi(int(br.position.y - rect.position.y), 0), mini(int(br.end.y - rect.position.y) + 1, h)):
			for x in range(maxi(int(br.position.x - rect.position.x), 0), mini(int(br.end.x - rect.position.x) + 1, w)):
				if Maps.in_box(rect.position.x + x + 0.5, rect.position.y + y + 0.5, c[0], c[1], c[2], c[4], rot, 0.6 + 0.71):
					ok[y * w + x] = 0
	for b in decor_boxes + prop_boxes:
		block.call(b[0], b[1], b[2] * 0.5 + 0.4, b[4] * 0.5 + 0.4)
	for p in no_grass:
		block.call(p.x, p.z, 4.0, 4.0)
	for pd in puddles:
		var rr: float = pd.y + 0.35
		for y in range(maxi(int(pd.z - rr - rect.position.y), 0), mini(int(pd.z + rr - rect.position.y) + 1, h)):
			for x in range(maxi(int(pd.x - rr - rect.position.x), 0), mini(int(pd.x + rr - rect.position.x) + 1, w)):
				if Vector2(rect.position.x + x + 0.5 - pd.x, rect.position.y + y + 0.5 - pd.z).length() < rr:
					ok[y * w + x] = 0

	var clump := FastNoiseLite.new()
	clump.seed = 5
	clump.frequency = 0.15
	# густота и травинок в кусте по графике (Cfg.graphics): низкие, средние, высокие
	var per_m2: float = Cfg.gfx(1.5, 3.0, GRASS_PER_M2)
	var bush := Art.grass_bush_mesh(Cfg.gfx(10, 16, 24))
	var chunks := {}
	for y in range(1, h - 1):
		for x in range(1, w - 1):
			if ok[y * w + x] == 0:
				continue
			var wx := rect.position.x + x
			var wz := rect.position.y + y
			var dens := _grass_density(wx + 0.5, wz + 0.5) * (0.2 + 0.8 * smoothstep(-0.3, 0.3, clump.get_noise_2d(wx, wz)))
			var n := int(per_m2 * dens + _rng.randf())
			if n == 0:
				continue
			var key := Vector2i(int(x / GRASS_CHUNK), int(y / GRASS_CHUNK))
			if not chunks.has(key):
				chunks[key] = []
			for k in n:
				var s := _rng.randf_range(0.65, 1.3) * (0.6 + 0.4 * dens)
				var tr := Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(s, s * _rng.randf_range(0.8, 1.2), s)),
					Vector3(wx + _rng.randf(), 0, wz + _rng.randf()))
				# оттенок куста: солома, олива или тёмная сухая трава
				var tint := Color(1.0, 0.96, 0.86).lerp(Color(0.86, 0.94, 0.7), _rng.randf()).lerp(Color(0.7, 0.68, 0.6), _rng.randf() * 0.5)
				chunks[key].append([tr, tint])
	var gm := ShaderMaterial.new()
	gm.shader = GrassShader
	vision.register_material(gm)
	for key in chunks:
		var list: Array = chunks[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = bush
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i][0])
			mm.set_instance_color(i, list[i][1])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = gm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)


# сколько травы в точке: 1 на траве, меньше на сухой грязи, грунте и камнях
func _grass_density(x: float, z: float) -> float:
	if biome == null:
		return 1.0
	var px := clampi(int(x - mask_rect.position.x), 0, biome.get_width() - 1)
	var pz := clampi(int(z - mask_rect.position.y), 0, biome.get_height() - 1)
	var c := biome.get_pixel(px, pz)
	return 1.0 - maxf(maxf(c.r * 0.85, c.g * 0.45), c.b * 0.9)


func _scatter(rect: Rect2, covers: Array, no_grass: Array) -> void:
	_grass(rect, covers, no_grass)

	# мелкие камни по траве и обочинам
	for v in 3:
		var rx: Array = []
		for i in 120:
			var x2 := _rng.randf_range(rect.position.x + 3.0, rect.end.x - 3.0)
			var z2 := _rng.randf_range(rect.position.y + 3.0, rect.end.y - 3.0)
			var ok := true
			for c in covers:
				if Maps.in_box(x2, z2, c[0], c[1], c[2], c[4], Maps.cover_rot(c), 1.0):
					ok = false
			if not ok:
				continue
			var s := _rng.randf_range(0.25, 0.8)
			var b2 := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(s * 1.3, s * 0.8, s))
			rx.append(Transform3D(b2, Vector3(x2, 0, z2)))
		var mm2 := MultiMesh.new()
		mm2.transform_format = MultiMesh.TRANSFORM_3D
		mm2.mesh = Art.rock_mesh(v)
		mm2.instance_count = rx.size()
		for i in rx.size():
			mm2.set_instance_transform(i, rx[i])
		var mmi2 := MultiMeshInstance3D.new()
		mmi2.multimesh = mm2
		mmi2.material_override = rock()
		add_child(mmi2)
