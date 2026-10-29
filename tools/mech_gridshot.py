# Снимки сырой модели с сеткой координат (единицы модели) для настройки нарезки.
# Модель: поворот файла впечён, середина по X в 0 (сдвиг печатается), низ в z = 0.
# Виды: front (смотрим с -Y: вправо +X, вверх +Z), side (смотрим с +X: вправо +Y, вверх +Z),
# top (сверху: вправо +X, вверх +Y). Сетка через 0.05, подписи через 0.1.
import bpy, sys, os, math, subprocess
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
SRC, OUT = argv[0], argv[1]
names = argv[2:]
R = 1000
for nm in names:
	bpy.ops.wm.read_factory_settings(use_empty=True)
	bpy.ops.import_scene.gltf(filepath=os.path.join(SRC, nm + ".glb"))
	o = [o for o in bpy.data.objects if o.type == 'MESH'][0]
	o.data.transform(o.matrix_world)
	o.matrix_world = o.matrix_world.Identity(4)
	xs = [v.co.x for v in o.data.vertices]
	ys = [v.co.y for v in o.data.vertices]
	zs = [v.co.z for v in o.data.vertices]
	print("GRID %s: x %.3f..%.3f y %.3f..%.3f z %.3f..%.3f" % (nm, min(xs), max(xs), min(ys), max(ys), min(zs), max(zs)))
	sc = bpy.context.scene
	sc.render.engine = 'BLENDER_WORKBENCH'
	sc.display.shading.light = 'STUDIO'
	sc.display.shading.color_type = 'TEXTURE'
	sc.render.resolution_x = R
	sc.render.resolution_y = R
	cam = bpy.data.objects.new("c", bpy.data.cameras.new("c"))
	cam.data.type = 'ORTHO'
	sc.collection.objects.link(cam)
	sc.camera = cam
	lo = Vector((min(xs), min(ys), min(zs)))
	hi = Vector((max(xs), max(ys), max(zs)))
	ctr = (lo + hi) * 0.5
	S = max(hi - lo) * 1.08
	cam.data.ortho_scale = S
	for vn, d, h, v in [("front", (0, -1, 0), 0, 2), ("side", (1, 0, 0), 1, 2), ("top", (0, 0, 1), 0, 1)]:
		vec = Vector(d)
		cam.location = ctr + vec * S * 3
		cam.rotation_euler = (0, 0, 0) if vn == "top" else (-vec).to_track_quat('-Z', 'Y').to_euler()
		p = os.path.join(OUT, "%s_%s.png" % (nm, vn))
		sc.render.filepath = p
		bpy.ops.render.render(write_still=True)
		# сетку рисует питон снаружи (PIL): передаём, где центр и масштаб
		with open(p + ".txt", "w") as f:
			f.write("%f %f %f %d" % (ctr[h], ctr[v], S, R))
