# Режет сырую 3D-модель меха из "3d ref" на части под шагающие ноги игры и пишет assets/mechs/<имя>.glb.
# Запуск (без окна):
#   blender -b --python tools/cut_mech.py -- <имя> [папка_для_снимков]
#   имена моделей — ключи MODELS ниже. Без имени — все по очереди.
#
# Что делает:
#   1. поворачивает модель передом в -Y, ставит середину корпуса в x = 0;
#   2. вырезает лишнее (пушки модели, рога, фигурку пилота), при нужде зеркалит ногу;
#   3. делит на части: hull (корпус), pelvis (таз, может не быть), thigh/shin/foot _l/_r (бедро, голень, ступня);
#   4. переводит в метры игры (x вправо, y вверх, z назад) — части остаются в позе модели;
#   5. запекает с исходной (миллионной) модели затенение щелей и углублений и затемняет им окраску:
#      у исходника тёмные линии на корпусе — это тени щелей между деталями, после упрощения их нет;
#      упрощает; окраска и карта рельефа 2048, шероховатость 1024; корпус матовее (глянец отражал небо
#      и заливал окраску серым);
#   5б. (если у модели задан remesh) пересобирает каждую часть по объёму: сплошная оболочка без дыр и щелей
#      (исходник собран из тысяч отдельных кусков, при простом упрощении между ними открывались щели), упрощает,
#      делает одну новую раскладку текстуры на все части и запекает на неё окраску с исходника (старая раскладка
#      из сотен островков рвалась при упрощении). Мелкие тонкие детали пропадают — на экране мех ~200 пикселей;
#   6. добавляет точки (пустые узлы): суставы j_hip/j_knee/j_ankle _l/_r, крепления пушек gun_l/gun_r,
#      модулей mod_0.., двигателей рывка jet_0.., полосы цвета команды accent_0.. (масштаб узла = размер полосы).
# Игра (mech_visual.gd) сама переносит части в кости по суставам.

import bpy, bmesh, sys, os, math
import numpy as np
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TEX = 2048           # окраска и карта рельефа (исходник 4096: в бою мех мелкий, 4096 только съест видеопамять)
TEX_ORM = 1024       # металличность и шероховатость
AO_DIST = 0.18       # затенение щелей: на каком расстоянии (метры игры) деталь затеняет соседнюю
AO_K = 0.7           # насколько щели темнеют (0 — никак, 1 — до чёрного)
ROUGH_MIN, ROUGH_MAX = 0.5, 0.9   # шероховатость сжимается в этот промежуток (исходник почти глянец 0,15)

# Координаты ниже — в повёрнутой модели (перёд -Y, верх Z, x от середины корпуса), в единицах модели.
# Точки с x даются для стороны +X; вторая сторона получается зеркально.
# Правило "torso" и т.п. получает массивы x, y, z (центры граней) и ax = |x|.
MODELS = {
	# тяжёлый: плоский корпус-щит, по бокам на балках вращающиеся пушки (убраны), колено вперёд
	"heavy_26cbe": dict(
		src="26cbe29566d8c5027b8ddae8bf96abbf.glb", rotz=0, x0=0.0, scale=6.3,
		delete=[lambda x, y, z, ax: (ax > 0.2) & (z > 0.445)],
		delete_comp=[lambda x, y, z, ax: (ax > 0.25) & (z > 0.38)],
		torso=lambda x, y, z, ax: z > 0.445,
		pelvis=lambda x, y, z, ax: ax < 0.12,
		thigh=[(-0.32, 0.45), (0.2, 0.45), (0.2, 0.31), (0.0, 0.27), (-0.07, 0.25), (-0.32, 0.19)],
		foot_z=0.125,
		hip=(0.17, 0.025, 0.385), knee=(0.21, -0.09, 0.285), ankle=(0.33, 0.08, 0.09),
		gun=(0.29, -0.06, 0.53),
		mods=[(0.11, 0.17), (-0.11, 0.17), (0.0, 0.26)],
		jets=[(0.09, 0.335, 0.52), (-0.09, 0.335, 0.52)],
		accents=[(0.135, -0.12, 0.012, 0.32)],
		target=dict(hull=9000, pelvis=1200, thigh=3000, shin=3000, foot=2200)),
	# средний: короб-кабина с глазом, зелёные плечевые короба (оставлены как броня), пушки на руках и рога убраны,
	# нога в три звена (среднее звено жёсткое), колено вперёд
	"mid_87e20": dict(
		src="87e20aa1ac01064ea193010a97c693a7.glb", rotz=0, x0=0.0, scale=4.3,
		delete=[lambda x, y, z, ax: (ax > 0.285) & (z > 0.44) & (z < 0.8),
			lambda x, y, z, ax: (ax > 0.2) & (z > 0.6) & (z < 0.8),
			lambda x, y, z, ax: (ax > 0.1) & (ax < 0.21) & (z > 0.72) & (z < 0.84) & (y < -0.12)],
		delete_comp=[lambda x, y, z, ax: (ax > 0.28) & (z > 0.4) & (z < 0.8),
			lambda x, y, z, ax: (ax > 0.19) & (z > 0.58) & (z < 0.8)],
		torso=lambda x, y, z, ax: ((ax < 0.135) & (z > 0.56)) | (z > 0.6),
		pelvis=lambda x, y, z, ax: (ax < 0.135) & (z > 0.4),
		thigh=[(-0.17, 0.45), (-0.17, 0.27), (0.03, 0.27), (0.09, 0.33), (0.16, 0.43), (0.36, 0.43), (0.36, 0.62), (-0.17, 0.62)],
		foot_z=0.1,
		hip=(0.2, 0.2, 0.536), knee=(0.2, -0.018, 0.332), ankle=(0.21, -0.014, 0.1),
		gun=(0.31, -0.02, 0.64),
		mods=[(0.1, 0.24), (-0.1, 0.24)],
		jets=[(0.08, 0.3, 0.6), (-0.08, 0.3, 0.6)],
		accents=[(0.24, -0.05, 0.012, 0.25)],
		target=dict(hull=8000, pelvis=800, thigh=2200, shin=2200, foot=1600)),
	# лёгкий: узкая кабина-киль, плечевая балка с коробами-антеннами, пушки по бокам убраны, колено назад
	"light_046748": dict(
		src="046748ee491dacc70805450925209a16.glb", rotz=0, x0=0.0, scale=3.7,
		delete=[lambda x, y, z, ax: (ax > 0.27) & (z > 0.44),
			lambda x, y, z, ax: (ax > 0.245) & (z > 0.58)],
		delete_comp=[lambda x, y, z, ax: (ax > 0.25) & (z > 0.5)],
		torso=lambda x, y, z, ax: (z > 0.6) | ((ax < 0.07) & (z > 0.25)),
		pelvis=lambda x, y, z, ax: (ax < 0.1) & (z > 0.4),
		thigh=[(-0.3, 0.3), (0.3, 0.3), (0.3, 0.62), (-0.3, 0.62)],
		foot_z=0.135,
		hip=(0.17, 0.064, 0.49), knee=(0.19, 0.096, 0.304), ankle=(0.21, 0.06, 0.14),
		gun=(0.27, -0.03, 0.66),
		mods=[(0.11, 0.0), (-0.11, 0.0)],
		jets=[(0.05, 0.16, 0.55), (-0.05, 0.16, 0.55)],
		accents=[(0.17, -0.02, 0.01, 0.14)],
		target=dict(hull=7500, pelvis=700, thigh=2000, shin=1800, foot=1500)),
	# лёгкий: кабина со стеклом, одна нога (вторую зеркалим), пушки по бокам и фигурка пилота убраны, колено назад
	"light_cc59ad": dict(
		src="cc59ad415fc69c3dd3d1c5577687ad4a.glb", rotz=90, x0=-0.057, scale=3.9,
		delete=[lambda x, y, z, ax: (x < -0.193) & (z > 0.33),
			lambda x, y, z, ax: (x > 0.282) & (z > 0.43),
			lambda x, y, z, ax: (x > 0.192) & (z > 0.53),
			lambda x, y, z, ax: (x < -0.05) & (y < -0.36) & (z < 0.34)],
		delete_comp=[lambda x, y, z, ax: (x < -0.18) & (z > 0.3),
			lambda x, y, z, ax: (ax > 0.3) & (z > 0.38)],
		mirror=lambda x, y, z, ax: (x > 0.175) & (z < 0.52),
		torso=lambda x, y, z, ax: ~((ax > 0.175) & (z < 0.52)),
		pelvis=None,
		thigh=[(-0.12, 0.56), (0.13, 0.56), (0.13, 0.4), (0.11, 0.3), (0.06, 0.29), (-0.12, 0.37)],
		foot_z=0.09,
		hip=(0.227, 0.0, 0.48), knee=(0.227, 0.088, 0.3), ankle=(0.227, -0.05, 0.085),
		gun=(0.28, 0.0, 0.58),
		mods=[(0.08, 0.15), (-0.08, 0.15)],
		jets=[(0.06, 0.26, 0.55), (-0.06, 0.26, 0.55)],
		accents=[(0.07, -0.02, 0.01, 0.16)],
		target=dict(hull=8000, pelvis=0, thigh=1800, shin=2000, foot=1500)),
}

# Крепость, вторая версия: тот же исходник, но пересборка по объёму вместо простого упрощения (23.10.2026)
MODELS["heavy_26cbe_v2"] = dict(MODELS["heavy_26cbe"], remesh=0.03)

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
NAMES = [argv[0]] if argv and argv[0] in MODELS else list(MODELS.keys())
SHOTS = argv[1] if len(argv) > 1 else ""


def tris(o):
	return sum(len(p.vertices) - 2 for p in o.data.polygons)


def in_poly(py, pz, poly):
	"""точки (py, pz) внутри многоугольника poly [(y, z), ...]"""
	inside = np.zeros(len(py), dtype=bool)
	n = len(poly)
	for i in range(n):
		y1, z1 = poly[i]
		y2, z2 = poly[(i + 1) % n]
		cond = (z1 > pz) != (z2 > pz)
		yc = (y2 - y1) * (pz - z1) / ((z2 - z1) if z2 != z1 else 1e-9) + y1
		inside ^= cond & (py < yc)
	return inside


def face_components(me):
	"""номер связного куска для каждой грани"""
	ed = np.empty(len(me.edges) * 2, dtype=np.int64)
	me.edges.foreach_get('vertices', ed)
	ed = ed.reshape(-1, 2)
	lab = np.arange(len(me.vertices))
	while True:
		m = np.minimum(lab[ed[:, 0]], lab[ed[:, 1]])
		new = lab.copy()
		np.minimum.at(new, ed[:, 0], m)
		np.minimum.at(new, ed[:, 1], m)
		new = new[new]
		new = new[new]
		if np.array_equal(new, lab):
			break
		lab = new
	ls = np.empty(len(me.polygons), dtype=np.int64)
	me.polygons.foreach_get('loop_start', ls)
	lv = np.empty(len(me.loops), dtype=np.int64)
	me.loops.foreach_get('vertex_index', lv)
	return lab[lv[ls]]


def face_centers(me):
	c = np.empty(len(me.polygons) * 3, dtype=np.float32)
	me.polygons.foreach_get('center', c)
	c = c.reshape(-1, 3)
	return c[:, 0], c[:, 1], c[:, 2], np.abs(c[:, 0])


def cut(name):
	cfg = MODELS[name]
	bpy.ops.wm.read_factory_settings(use_empty=True)
	bpy.ops.import_scene.gltf(filepath=os.path.join(ROOT, "3d ref", cfg["src"]))
	src = [o for o in bpy.data.objects if o.type == 'MESH'][0]
	me = src.data
	mat0 = me.materials[0]
	# 1. поворот файла впекаем в сетку, разворачиваем передом в -Y, середину корпуса в x = 0
	me.transform(src.matrix_world)
	src.matrix_world = Matrix.Identity(4)
	me.transform(Matrix.Translation((-cfg["x0"], 0, 0)) @ Matrix.Rotation(math.radians(cfg["rotz"]), 4, 'Z'))
	me.update()
	# 2. вырезать лишнее
	x, y, z, ax = face_centers(me)
	kill = np.zeros(len(x), dtype=bool)
	for rule in cfg["delete"]:
		kill |= rule(x, y, z, ax)
	bm = bmesh.new()
	bm.from_mesh(me)
	bm.faces.ensure_lookup_table()
	bmesh.ops.delete(bm, geom=[bm.faces[i] for i in np.nonzero(kill)[0]], context='FACES')
	bm.to_mesh(me)
	bm.free()
	print("DEL %s: убрано граней %d" % (name, int(kill.sum())))
	# обрезки: куски модели (она собрана из множества отдельных деталей), чей центр в зоне удаления
	if cfg.get("delete_comp"):
		me.update()
		lab = face_components(me)
		x, y, z, ax = face_centers(me)
		cnt = np.bincount(lab).astype(np.float64)
		cnt[cnt == 0] = 1
		cx = np.bincount(lab, x) / cnt
		cy = np.bincount(lab, y) / cnt
		cz = np.bincount(lab, z) / cnt
		bad = np.zeros(len(cnt), dtype=bool)
		for rule in cfg["delete_comp"]:
			bad |= rule(cx, cy, cz, np.abs(cx))
		kill = bad[lab]
		bm = bmesh.new()
		bm.from_mesh(me)
		bm.faces.ensure_lookup_table()
		bmesh.ops.delete(bm, geom=[bm.faces[i] for i in np.nonzero(kill)[0]], context='FACES')
		bm.to_mesh(me)
		bm.free()
		print("DEL %s: обрезков %d, граней %d" % (name, int(bad.sum()), int(kill.sum())))
	# зеркальная нога
	if cfg.get("mirror"):
		x, y, z, ax = face_centers(me)
		sel = cfg["mirror"](x, y, z, ax)
		bm = bmesh.new()
		bm.from_mesh(me)
		bm.faces.ensure_lookup_table()
		res = bmesh.ops.duplicate(bm, geom=[bm.faces[i] for i in np.nonzero(sel)[0]])
		verts = [e for e in res["geom"] if isinstance(e, bmesh.types.BMVert)]
		faces = [e for e in res["geom"] if isinstance(e, bmesh.types.BMFace)]
		for v in verts:
			v.co.x = -v.co.x
		bmesh.ops.reverse_faces(bm, faces=faces)
		bm.to_mesh(me)
		bm.free()
		print("MIRROR %s: граней %d" % (name, len(faces)))
	me.update()
	# 3. части
	x, y, z, ax = face_centers(me)
	torso = cfg["torso"](x, y, z, ax)
	pelvis = (~torso) & cfg["pelvis"](x, y, z, ax) if cfg["pelvis"] else np.zeros(len(x), dtype=bool)
	leg = (~torso) & (~pelvis)
	foot = leg & (z < cfg["foot_z"])
	thigh = leg & (~foot) & in_poly(y, z, cfg["thigh"])
	shin = leg & (~foot) & (~thigh)
	names = ["hull", "pelvis", "thigh_l", "thigh_r", "shin_l", "shin_r", "foot_l", "foot_r"]
	part = np.zeros(len(x), dtype=np.int32)
	part[pelvis] = 1
	left = x > 0     # перёд -Y: левая рука меха на +X
	for base, m in (("thigh", thigh), ("shin", shin), ("foot", foot)):
		part[m & left] = names.index(base + "_l")
		part[m & ~left] = names.index(base + "_r")
	me.materials.clear()
	for nm in names:
		me.materials.append(bpy.data.materials.new(nm))
	me.polygons.foreach_set('material_index', part)
	me.update()
	bpy.context.view_layer.objects.active = src
	src.select_set(True)
	bpy.ops.object.mode_set(mode='EDIT')
	bpy.ops.mesh.select_all(action='SELECT')
	bpy.ops.mesh.separate(type='MATERIAL')
	bpy.ops.object.mode_set(mode='OBJECT')
	objs = {}
	for o in list(bpy.data.objects):
		if o.type == 'MESH':
			if len(o.data.polygons) == 0:
				bpy.data.objects.remove(o)
				continue
			nm = o.data.materials[o.data.polygons[0].material_index].name
			o.name = nm
			o.data.name = nm
			o.data.materials.clear()
			o.data.materials.append(mat0)
			objs[nm] = o
	# 4. метры игры: x_игры = -x, y_игры = z, z_игры = y - yc. В Blender храним (x_игры, -z_игры, y_игры)
	S = cfg["scale"]
	yc = (cfg["hip"][1] + cfg["ankle"][1]) * 0.5
	def to_game(p):
		return Vector((-p[0] * S, p[2] * S, (p[1] - yc) * S))
	def to_bl(g):
		return Vector((g.x, -g.z, g.y))
	for o in objs.values():
		co = np.empty(len(o.data.vertices) * 3, dtype=np.float64)
		o.data.vertices.foreach_get('co', co)
		co = co.reshape(-1, 3)
		b = np.stack([-co[:, 0] * S, -(co[:, 1] - yc) * S, co[:, 2] * S], axis=1)
		o.data.vertices.foreach_set('co', b.ravel())
		o.data.update()
	# 5. затенение щелей с исходной модели (до упрощения), потом упрощение
	ao = bake_ao(objs, mat0)
	if cfg.get("remesh"):
		fix_textures(ao)            # затенение щелей впекаем в окраску исходника, с неё потом запекаем
		objs = rebuild(objs, cfg)
	for nm, o in objs.items():
		if cfg.get("remesh"):
			break
		t0 = tris(o)
		target = cfg["target"][nm.split("_")[0]]
		if target > 0 and t0 > target:
			mod = o.modifiers.new("dec", 'DECIMATE')
			mod.decimate_type = 'COLLAPSE'
			mod.ratio = target / t0
			mod.use_collapse_triangulate = True
			bpy.context.view_layer.objects.active = o
			bpy.ops.object.modifier_apply(modifier="dec")
		print("PART %-8s %8d -> %6d" % (nm, t0, tris(o)))
	# поверхность корпуса (для точек модулей и полос: ставим прямо на броню)
	hull = objs["hull"]
	bm = bmesh.new()
	bm.from_mesh(hull.data)
	bvh = BVHTree.FromBMesh(bm)
	def top_at(xn, yn):
		g = to_game(Vector((xn, yn, 0)))
		hit = bvh.ray_cast(to_bl(Vector((g.x, 50.0, g.z))), Vector((0, 0, -1)))
		return hit[0].z if hit[0] is not None else None
	# 6. точки
	empties = []
	def empty(nm, g, size=None):
		e = bpy.data.objects.new(nm, None)
		e.location = to_bl(g)
		if size is not None:
			e.scale = Vector((size.x, size.z, size.y))
		bpy.context.scene.collection.objects.link(e)
		empties.append(e)
	for side, sg in (("l", 1.0), ("r", -1.0)):
		for jn in ("hip", "knee", "ankle"):
			p = cfg[jn]
			empty("j_%s_%s" % (jn, side), to_game((p[0] * sg, p[1], p[2])))
		g = cfg["gun"]
		empty("gun_" + side, to_game((g[0] * sg, g[1], g[2])))
	for i, (mx, my) in enumerate(cfg["mods"]):
		zt = top_at(mx, my)
		gp = to_game((mx, my, 0))
		gp.y = (zt if zt is not None else cfg["hip"][2] * S * 1.6) + 0.02
		empty("mod_%d" % i, gp)
	for i, j in enumerate(cfg["jets"]):
		empty("jet_%d" % i, to_game(j))
	k = 0
	for (axn, ayn, w, ln) in cfg["accents"]:
		for sg in (1.0, -1.0):
			zt = top_at(axn * sg, ayn)
			if zt is None:
				continue
			gp = to_game((axn * sg, ayn, 0))
			gp.y = zt + 0.02
			empty("accent_%d" % k, gp, Vector((w * S, 0.05, ln * S)))
			k += 1
	bm.free()
	# 7. текстуры: окраска с затенением щелей, рельеф, матовость
	if not cfg.get("remesh"):
		fix_textures(ao)
	if SHOTS:
		shots(name, objs, empties)
	# 8. выгрузка
	bpy.ops.object.select_all(action='DESELECT')
	for o in list(objs.values()) + empties:
		o.select_set(True)
	dst = os.path.join(ROOT, "assets", "mechs", name + ".glb")
	bpy.ops.export_scene.gltf(filepath=dst, export_format='GLB', use_selection=True, export_normals=True,
		export_materials='EXPORT', export_yup=True, export_apply=True, export_image_format='JPEG')
	print("TOTAL %s: треугольников %d -> %s" % (name, sum(tris(o) for o in objs.values()), dst))


def rebuild(objs, cfg):
	"""пересборка по объёму, упрощение, одна раскладка на все части, окраска запекается с исходника"""
	vox = cfg["remesh"]
	lows = {}
	for nm, hi in objs.items():
		lo = hi.copy()
		lo.data = hi.data.copy()
		lo.name = nm + "_lo"
		bpy.context.scene.collection.objects.link(lo)
		bpy.ops.object.select_all(action='DESELECT')
		bpy.context.view_layer.objects.active = lo
		lo.select_set(True)
		# исходник — тонкие открытые листы: сначала толщина, иначе пересборка по объёму их теряет
		sol = lo.modifiers.new("sol", 'SOLIDIFY')
		sol.thickness = vox * 2.0
		sol.offset = 0.0
		bpy.ops.object.modifier_apply(modifier="sol")
		m = lo.modifiers.new("vox", 'REMESH')
		m.mode = 'VOXEL'
		m.voxel_size = vox
		bpy.ops.object.modifier_apply(modifier="vox")
		t0 = tris(lo)
		target = cfg["target"][nm.split("_")[0]]
		if target > 0 and t0 > target:
			d = lo.modifiers.new("dec", 'DECIMATE')
			d.decimate_type = 'COLLAPSE'
			d.ratio = target / t0
			d.use_collapse_triangulate = True
			bpy.ops.object.modifier_apply(modifier="dec")
		bpy.ops.object.shade_smooth_by_angle(angle=math.radians(35))
		if not lo.data.uv_layers:
			lo.data.uv_layers.new(name="UVMap")
		print("REMESH %-8s исходник %8d -> оболочка %7d -> %6d" % (nm, tris(hi), t0, tris(lo)))
		lows[nm] = lo
	# одна раскладка на все части
	bpy.ops.object.select_all(action='DESELECT')
	for lo in lows.values():
		lo.select_set(True)
	bpy.context.view_layer.objects.active = next(iter(lows.values()))
	bpy.ops.object.mode_set(mode='EDIT')
	bpy.ops.mesh.select_all(action='SELECT')
	bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.003)
	bpy.ops.object.mode_set(mode='OBJECT')
	# новый материал с одной текстурой
	img = bpy.data.images.new("mech_color", TEX, TEX, alpha=False)
	mat = bpy.data.materials.new("mech")
	mat.use_nodes = True
	nt = mat.node_tree
	bsdf = nt.nodes["Principled BSDF"]
	bsdf.inputs["Roughness"].default_value = 0.75
	bsdf.inputs["Metallic"].default_value = 0.35
	node = nt.nodes.new('ShaderNodeTexImage')
	node.image = img
	nt.links.new(node.outputs["Color"], bsdf.inputs["Base Color"])
	nt.nodes.active = node
	for lo in lows.values():
		lo.data.materials.clear()
		lo.data.materials.append(mat)
	# запекание окраски с исходника (только цвет, без света)
	sc = bpy.context.scene
	sc.cycles.samples = 4
	bk = sc.render.bake
	bk.use_selected_to_active = True
	bk.cage_extrusion = vox * 3.0
	bk.max_ray_distance = vox * 10.0
	bk.margin = 8
	bk.use_pass_direct = False
	bk.use_pass_indirect = False
	bk.use_pass_color = True
	first = True
	for nm, lo in lows.items():
		bpy.ops.object.select_all(action='DESELECT')
		objs[nm].select_set(True)
		lo.select_set(True)
		bpy.context.view_layer.objects.active = lo
		bk.use_clear = first
		bpy.ops.object.bake(type='DIFFUSE', pass_filter={'COLOR'}, use_selected_to_active=True,
			cage_extrusion=vox * 3.0, max_ray_distance=vox * 10.0, margin=8, use_clear=first)
		first = False
	img.pack()
	# исходник больше не нужен
	for nm in list(objs.keys()):
		bpy.data.objects.remove(objs[nm])
		lows[nm].name = nm
		lows[nm].data.name = nm
	return lows


def bake_ao(objs, mat):
	"""затенение щелей и углублений с исходной модели в раскладку текстуры -> массив TEX×TEX (0..1)"""
	sc = bpy.context.scene
	sc.render.engine = 'CYCLES'
	try:
		prefs = bpy.context.preferences.addons['cycles'].preferences
		for dt in ('OPTIX', 'CUDA'):
			try:
				prefs.compute_device_type = dt
				prefs.get_devices()
				if any(d.type == dt for d in prefs.devices):
					for d in prefs.devices:
						d.use = d.type == dt
					sc.cycles.device = 'GPU'
					print("AO: видеокарта (%s)" % dt)
					break
			except Exception:
				pass
	except Exception:
		pass
	sc.cycles.samples = 48
	w = bpy.data.worlds.new("ao")
	sc.world = w
	w.light_settings.distance = AO_DIST
	img = bpy.data.images.new("ao_bake", TEX, TEX, alpha=False)
	img.colorspace_settings.name = 'Non-Color'
	nt = mat.node_tree
	node = nt.nodes.new('ShaderNodeTexImage')
	node.image = img
	nt.nodes.active = node
	bpy.ops.object.select_all(action='DESELECT')
	for o in objs.values():
		o.select_set(True)
	bpy.context.view_layer.objects.active = next(iter(objs.values()))
	sc.render.bake.margin = 6
	sc.render.bake.use_clear = True
	bpy.ops.object.bake(type='AO')
	buf = np.empty(TEX * TEX * 4, dtype=np.float32)
	img.pixels.foreach_get(buf)
	nt.nodes.remove(node)
	bpy.data.images.remove(img)
	ao = buf.reshape(TEX, TEX, 4)[:, :, 0]
	print("AO: средняя %.2f, тёмных (<0.5) %.1f%%" % (float(ao.mean()), float((ao < 0.5).mean() * 100)))
	return ao


def fix_textures(ao):
	"""окраска 2048 с затенением щелей, рельеф 2048, шероховатость 1024 и матовее"""
	for img in list(bpy.data.images):
		nm = img.name.lower()
		if img.size[0] == 0:
			continue
		if "roughness" in nm:
			if img.size[0] != TEX_ORM:
				img.scale(TEX_ORM, TEX_ORM)
			px = np.empty(TEX_ORM * TEX_ORM * 4, dtype=np.float32)
			img.pixels.foreach_get(px)
			px = px.reshape(-1, 4)
			px[:, 1] = ROUGH_MIN + (ROUGH_MAX - ROUGH_MIN) * px[:, 1]
			img.pixels.foreach_set(px.ravel())
			img.update()
		elif "normal" in nm:
			if img.size[0] != TEX:
				img.scale(TEX, TEX)
		else:
			if img.size[0] != TEX:
				img.scale(TEX, TEX)
			px = np.empty(TEX * TEX * 4, dtype=np.float32)
			img.pixels.foreach_get(px)
			px = px.reshape(TEX, TEX, 4)
			k = (1.0 - AO_K) + AO_K * ao
			px[:, :, :3] *= k[:, :, None]
			img.pixels.foreach_set(px.ravel())
			img.update()
		print("TEX %-60s %d" % (img.name, img.size[0]))


def shots(name, objs, empties):
	sc = bpy.context.scene
	sc.render.engine = 'BLENDER_EEVEE'
	w = bpy.data.worlds.new("w")
	sc.world = w
	w.use_nodes = True
	bg = w.node_tree.nodes.get("Background")
	bg.inputs[0].default_value = (0.45, 0.47, 0.5, 1)
	sun = bpy.data.lights.new("sun", 'SUN')
	sun.energy = 3.0
	so = bpy.data.objects.new("sun", sun)
	sc.collection.objects.link(so)
	so.rotation_euler = (math.radians(35), math.radians(10), math.radians(30))
	# точки показываем шариками: пушки красные, модули зелёные, двигатели синие, полосы оранжевые
	marks = []
	cols = {"gun": (1, 0, 0, 1), "mod": (0, 1, 0, 1), "jet": (0, 0.4, 1, 1), "accent": (1, 0.5, 0, 1), "j": (1, 1, 0, 1)}
	for e in empties:
		key = e.name.split("_")[0]
		bpy.ops.mesh.primitive_uv_sphere_add(radius=0.12, location=e.location)
		s = bpy.context.active_object
		m = bpy.data.materials.new("mk")
		m.use_nodes = True
		m.node_tree.nodes["Principled BSDF"].inputs[0].default_value = cols.get(key, (1, 1, 1, 1))
		m.node_tree.nodes["Principled BSDF"].inputs["Emission Color"].default_value = cols.get(key, (1, 1, 1, 1))
		m.node_tree.nodes["Principled BSDF"].inputs["Emission Strength"].default_value = 2.0
		s.data.materials.append(m)
		marks.append(s)
	R = 700
	sc.render.resolution_x = R
	sc.render.resolution_y = R
	cam = bpy.data.cameras.new("c")
	cam.type = 'ORTHO'
	co = bpy.data.objects.new("c", cam)
	sc.collection.objects.link(co)
	sc.camera = co
	hgt = max(v.co.z for o in objs.values() for v in o.data.vertices)
	cam.ortho_scale = hgt * 1.6
	ctr = Vector((0, 0, hgt * 0.5))
	files = []
	for vn, d in [("front", (0, 1, 0.05)), ("side", (1, 0, 0)), ("top", (0, 0, 1)), ("iso", (0.8, 1.0, 0.7))]:
		v = Vector(d).normalized()
		co.location = ctr + v * 30
		co.rotation_euler = (0, 0, 0) if vn == "top" else (-v).to_track_quat('-Z', 'Y').to_euler()
		p = "%s/%s_%s.png" % (SHOTS, name, vn)
		sc.render.filepath = p
		bpy.ops.render.render(write_still=True)
		files.append(p)
	imgs = [bpy.data.images.load(f) for f in files]
	buf = np.zeros((R, R * 4, 4), dtype=np.float32)
	for i, im in enumerate(imgs):
		buf[:, i * R:(i + 1) * R] = np.array(im.pixels[:], dtype=np.float32).reshape(R, R, 4)
	res = bpy.data.images.new("o", R * 4, R)
	res.pixels = buf.ravel()
	res.filepath_raw = "%s/%s_cut.png" % (SHOTS, name)
	res.file_format = 'PNG'
	res.save()
	for s in marks:
		bpy.data.objects.remove(s)
	bpy.data.objects.remove(co)
	bpy.data.objects.remove(so)


for nm in NAMES:
	cut(nm)
