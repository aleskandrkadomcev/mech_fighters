# Режет сырую 3D-модель среднего меха (3d ref/medium1.glb) на части под шагающие ноги игры,
# упрощает их, запекает затенение в цвет вершин и сохраняет assets/mechs/medium1.glb.
# Запуск (без окна):
#   blender -b --python tools/medium1_cut.py -- "3d ref/medium1.glb" assets/mechs/medium1.glb [папка_для_снимков]
#
# Части в файле (всё уже в метрах игры, вперёд = -Z):
#   hull               корпус, начало координат = поворотный круг (таз + 0.32)
#   pod_l/pod_r        орудийные блоки, начало = точка подвеса (см. POD в печати)
#   barrels_l/_r       стволы автопушки в том же начале, что и блок
#   pelvis             таз, начало = центр таза
#   thigh_*, shin_*    бедро и голень: начало = середина кости, ось Y вдоль кости, длина кости = 1
#                      (в игре вытягивается до нужной длины масштабом по Y)
#   knee_*             колено: начало = сустав, оси как у бедра
#   foot_*             ступня: начало = земля под щиколоткой

import bpy, bmesh, sys, math
import numpy as np
from mathutils import Vector, Matrix

argv = sys.argv[sys.argv.index("--") + 1:]
SRC, DST = argv[0], argv[1]
SHOTS = argv[2] if len(argv) > 2 else ""

# --- суставы в координатах сырой модели (Blender: вперёд -Y, вверх Z), сторона +X ---
HIP = Vector((0.42, 0.10, 0.126))
KNEE = Vector((0.45, 0.29, -0.25))
ANKLE = Vector((0.57, 0.11, -0.49))
GROUND = -0.75
CY = 0.10                         # центр таза по длине
HIP_H = 2.05                      # высота таза в игре
S = HIP_H / (HIP.z - GROUND)      # масштаб в метры игры
WAIST_UP = 0.32

# сколько треугольников оставить
TARGET = {"hull": 5000, "pod": 1500, "barrels": 260, "pelvis": 500, "thigh": 1300,
	"knee": 180, "shin": 1000, "foot": 1100}


def G(p):
	"""точка сырой модели -> координаты игры (x вправо, y вверх, z назад)"""
	return Vector((-p.x * S, (p.z - GROUND) * S, (p.y - CY) * S))


def to_blender(g):
	"""координаты игры -> Blender (после выгрузки в glTF станут снова координатами игры)"""
	return Vector((g.x, -g.z, g.y))


bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
src = [o for o in bpy.data.objects if o.type == 'MESH'][0]
me = src.data

# --- 1. разметка граней по частям (по центру грани) ---
n = len(me.polygons)
c = np.empty(n * 3, dtype=np.float32)
me.polygons.foreach_get('center', c)
c = c.reshape(-1, 3)
x, y, z = c[:, 0], c[:, 1], c[:, 2]
ax = np.abs(x)
right = x < 0            # правая сторона меха (смотрит в -Y, значит правая рука на -X)
upper = ((ax < 0.3) & (z > 0.255)) | ((ax >= 0.3) & (z > 0.29))
pod = upper & (ax >= 0.385)
barrel = pod & (y < -0.45)
pelvis = (~upper) & (ax < 0.3) & (z > -0.1)
leg = (~upper) & (~pelvis)
foot = leg & (z < -0.535)
knee = leg & (~foot) & (np.sqrt((y - KNEE.y) ** 2 + (z - KNEE.z) ** 2) < 0.09) & (ax > 0.28)
thigh = leg & (~foot) & (~knee) & (z > -0.245)
shin = leg & (~foot) & (~knee) & (z <= -0.245)

names = ["hull", "pod_l", "pod_r", "barrels_l", "barrels_r", "pelvis", "thigh_l", "thigh_r",
	"knee_l", "knee_r", "shin_l", "shin_r", "foot_l", "foot_r"]
part = np.zeros(n, dtype=np.int32)
def put(mask, base):
	part[mask & ~right] = names.index(base + "_l")
	part[mask & right] = names.index(base + "_r")
put(pod & ~barrel, "pod")
put(barrel, "barrels")
part[pelvis] = names.index("pelvis")
put(thigh, "thigh")
put(knee, "knee")
put(shin, "shin")
put(foot, "foot")

for nm in names:
	me.materials.append(bpy.data.materials.new(nm))
me.polygons.foreach_set('material_index', part)
me.update()

# --- 2. разделить на объекты ---
bpy.context.view_layer.objects.active = src
src.select_set(True)
bpy.ops.object.mode_set(mode='EDIT')
bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.mesh.separate(type='MATERIAL')
bpy.ops.object.mode_set(mode='OBJECT')
objs = {}
for o in bpy.data.objects:
	if o.type == 'MESH' and len(o.data.polygons) > 0:
		nm = o.data.materials[o.data.polygons[0].material_index].name
		o.name = nm
		o.data.name = nm
		objs[nm] = o

# --- 3. перевод в метры игры (поза как в сырой модели) ---
for nm, o in objs.items():
	co = np.empty(len(o.data.vertices) * 3, dtype=np.float64)
	o.data.vertices.foreach_get('co', co)
	co = co.reshape(-1, 3)
	g = np.stack([-co[:, 0] * S, (co[:, 2] - GROUND) * S, (co[:, 1] - CY) * S], axis=1)
	b = np.stack([g[:, 0], -g[:, 2], g[:, 1]], axis=1)
	o.data.vertices.foreach_set('co', b.ravel())
	o.data.update()
	# у разреза все грани одного материала; материалы ниже назначим заново
	o.data.materials.clear()

# --- 3б. мелкие обрезки: разрез отделяет от соседней части крошечные кусочки, они висят в воздухе ---
for nm, o in objs.items():
	bm = bmesh.new()
	bm.from_mesh(o.data)
	bm.faces.ensure_lookup_table()
	seen = set()
	comps = []
	for f in bm.faces:
		if f.index in seen:
			continue
		stack = [f]
		seen.add(f.index)
		comp = []
		while stack:
			g = stack.pop()
			comp.append(g)
			for e in g.edges:
				for h in e.link_faces:
					if h.index not in seen:
						seen.add(h.index)
						stack.append(h)
		comps.append(comp)
	biggest = max(len(cp) for cp in comps)
	drop = [f for cp in comps if len(cp) < biggest * 0.01 for f in cp]
	bmesh.ops.delete(bm, geom=drop, context='FACES')
	bm.to_mesh(o.data)
	bm.free()
	print("CLEAN %-10s %d кусков, убрано граней %d" % (nm, len(comps), len(drop)))

# --- 4. упрощение ---
for nm, o in objs.items():
	base = nm.split("_")[0]
	tris = sum(len(p.vertices) - 2 for p in o.data.polygons)
	ratio = min(1.0, TARGET[base] / max(tris, 1))
	mod = o.modifiers.new("dec", 'DECIMATE')
	mod.decimate_type = 'COLLAPSE'
	mod.ratio = ratio
	mod.use_collapse_triangulate = True
	bpy.context.view_layer.objects.active = o
	bpy.ops.object.modifier_apply(modifier="dec")
	print("PART %-10s %7d -> %5d tris" % (nm, tris, sum(len(p.vertices) - 2 for p in o.data.polygons)))

# --- 5. материалы: какая часть каким цветом брони ---
MATS = {}
for mn, col in [("armor", (0.55, 0.56, 0.57, 1)), ("armor2", (0.33, 0.34, 0.36, 1)), ("dark", (0.2, 0.2, 0.21, 1))]:
	m = bpy.data.materials.new(mn)
	m.diffuse_color = col
	m.use_nodes = True
	MATS[mn] = m
PART_MAT = {"hull": "armor", "pod": "armor", "barrels": "dark", "pelvis": "armor2", "thigh": "armor",
	"knee": "dark", "shin": "armor2", "foot": "armor2"}
for nm, o in objs.items():
	o.data.materials.append(MATS[PART_MAT[nm.split("_")[0]]])

# --- 6. затенение (ambient occlusion) в цвет вершин, по всей сборке сразу ---
sc = bpy.context.scene
sc.render.engine = 'CYCLES'
sc.cycles.device = 'CPU'
sc.cycles.samples = 64
if sc.world is None:
	sc.world = bpy.data.worlds.new("w")
sc.world.light_settings.distance = 0.9
for o in objs.values():
	o.data.color_attributes.new("Color", 'FLOAT_COLOR', 'POINT')
	o.data.color_attributes.active_color = o.data.color_attributes["Color"]
bpy.ops.object.select_all(action='DESELECT')
for o in objs.values():
	o.select_set(True)
bpy.context.view_layer.objects.active = objs["hull"]
bpy.ops.object.bake(type='AO', target='VERTEX_COLORS')
for o in objs.values():
	ca = o.data.color_attributes["Color"]
	v = np.empty(len(ca.data) * 4, dtype=np.float32)
	ca.data.foreach_get('color', v)
	v = v.reshape(-1, 4)
	ao = np.clip(v[:, 0], 0, 1)
	k = 0.3 + 0.7 * ao ** 1.2
	v[:, 0] = k; v[:, 1] = k; v[:, 2] = k; v[:, 3] = 1.0
	ca.data.foreach_set('color', v.ravel())

# --- снимки собранного меха (для проверки глазами) ---
def shots(prefix):
	if not SHOTS:
		return
	sc.render.engine = 'BLENDER_WORKBENCH'
	sc.display.shading.light = 'STUDIO'
	sc.display.shading.color_type = 'VERTEX'
	sc.render.resolution_x = 900
	sc.render.resolution_y = 900
	cam = bpy.data.cameras.new("cam")
	cam.type = 'ORTHO'
	cam.ortho_scale = 6.0
	co = bpy.data.objects.new("cam", cam)
	sc.collection.objects.link(co)
	sc.camera = co
	sc.render.resolution_x = 1200
	sc.render.resolution_y = 1200
	# Blender: перёд меха = +Y. Сетка: тонкая через 0.1 м, синяя через 0.5 м, красная через 1 м
	# (на виде сбоку и спереди красная линия снизу = земля, по центру высота 2 м)
	for nm, d, ctr in [("iso", (0.9, 1.0, 0.8), (0, 0, 2.0)), ("side", (1, 0, 0), (0, 0, 2.0)),
			("front", (0, 1, 0), (0, 0, 2.0)), ("top", (0, 0, 1), (0, 0, 2.0))]:
		v = Vector(d).normalized()
		co.location = Vector(ctr) + v * 12
		co.rotation_euler = (0, 0, 0) if nm == "top" else (-v).to_track_quat('-Z', 'Y').to_euler()
		path = "%s/%s_%s.png" % (SHOTS, prefix, nm)
		sc.render.filepath = path
		bpy.ops.render.render(write_still=True)
		if nm == "iso":
			continue
		img = bpy.data.images.load(path)
		R = img.size[0]
		px = np.array(img.pixels[:], dtype=np.float32).reshape(R, R, 4)
		step = 0.1 / 6.0 * R
		for k in range(-30, 31):
			c = int(round(R / 2 + k * step))
			if 0 <= c < R:
				col = (0.8, 0, 0, 1) if k % 10 == 0 else ((0, 0, 0.9, 1) if k % 5 == 0 else (0, 0.45, 0, 1))
				px[:, c] = col
				px[c, :] = col
		img.pixels = px.ravel()
		img.save()
	bpy.data.objects.remove(co)
shots("model")

# --- 7. перенос каждой части в её собственные координаты ---
def bone_frame(top, bottom):
	yv = (top - bottom).normalized()
	zv = Vector((1, 0, 0)).cross(yv).normalized()
	xv = yv.cross(zv).normalized()
	return Matrix((xv, yv, zv)).transposed(), (top + bottom) * 0.5, (top - bottom).length

def set_local(o, fn):
	co = np.empty(len(o.data.vertices) * 3, dtype=np.float64)
	o.data.vertices.foreach_get('co', co)
	co = co.reshape(-1, 3)
	out = []
	for b in co:
		g = Vector((b[0], b[2], -b[1]))
		l = fn(g)
		out.extend((l.x, -l.z, l.y))
	o.data.vertices.foreach_set('co', out)
	o.data.update()

torso0 = Vector((0, HIP_H + WAIST_UP, 0))
set_local(objs["hull"], lambda g: g - torso0)
set_local(objs["pelvis"], lambda g: g - Vector((0, HIP_H, 0)))
info = {}
for side, sgn in [("l", 1.0), ("r", -1.0)]:
	m = Vector((sgn, 1, 1))
	hip = G(Vector((HIP.x * sgn, HIP.y, HIP.z)))
	kn = G(Vector((KNEE.x * sgn, KNEE.y, KNEE.z)))
	an = G(Vector((ANKLE.x * sgn, ANKLE.y, ANKLE.z)))
	# блок пушки: центр по ширине и высоте, подвес на z = -0.1 (так его держит игра)
	po = objs["pod_" + side]
	vs = [Vector((v.co.x, v.co.z, -v.co.y)) for v in po.data.vertices]
	cx = (min(v.x for v in vs) + max(v.x for v in vs)) * 0.5
	cy = (min(v.y for v in vs) + max(v.y for v in vs)) * 0.5
	pod0 = Vector((cx, cy, -0.1))
	set_local(po, lambda g: g - pod0)
	bo = objs["barrels_" + side]
	bvs = [Vector((v.co.x, v.co.z, -v.co.y)) - pod0 for v in bo.data.vertices]
	muzzle = Vector(((min(v.x for v in bvs) + max(v.x for v in bvs)) * 0.5,
		(min(v.y for v in bvs) + max(v.y for v in bvs)) * 0.5, min(v.z for v in bvs)))
	set_local(bo, lambda g: g - pod0)
	B, mid, ln = bone_frame(hip, kn)
	Bi = B.transposed()
	set_local(objs["thigh_" + side], lambda g: (lambda l: Vector((l.x, l.y / ln, l.z)))(Bi @ (g - mid)))
	set_local(objs["knee_" + side], lambda g: Bi @ (g - kn))
	B2, mid2, ln2 = bone_frame(kn, an)
	B2i = B2.transposed()
	set_local(objs["shin_" + side], lambda g: (lambda l: Vector((l.x, l.y / ln2, l.z)))(B2i @ (g - mid2)))
	foot0 = Vector((an.x, 0, an.z))
	set_local(objs["foot_" + side], lambda g: g - foot0)
	info[side] = dict(pod=pod0 - torso0, muzzle=muzzle, hip=hip, knee=kn, ankle=an, thigh_len=ln, shin_len=ln2)

for side in ("l", "r"):
	d = info[side]
	print("SIDE", side)
	for k, v in d.items():
		print("  %-9s %s" % (k, ("(%.3f, %.3f, %.3f)" % tuple(v)) if isinstance(v, Vector) else "%.3f" % v))
print("ANKLE_H %.3f  HIP_X %.3f  FOOT_X %.3f" % (info["l"]["ankle"].y, abs(info["l"]["hip"].x), abs(info["l"]["ankle"].x)))

# --- 8. сглаживание по углу: острые грани остаются острыми ---
for o in objs.values():
	bpy.ops.object.select_all(action='DESELECT')
	o.select_set(True)
	bpy.context.view_layer.objects.active = o
	bpy.ops.object.shade_smooth_by_angle(angle=math.radians(40))
	for m in list(o.modifiers):
		bpy.ops.object.modifier_apply(modifier=m.name)

# --- 9. выгрузка ---
bpy.ops.object.select_all(action='DESELECT')
for o in objs.values():
	o.select_set(True)
total = sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in objs.values())
print("TOTAL TRIS", total)
bpy.ops.export_scene.gltf(filepath=DST, export_format='GLB', use_selection=True, export_vertex_color='ACTIVE',
	export_normals=True, export_materials='EXPORT', export_yup=True, export_apply=True)
print("SAVED", DST)
