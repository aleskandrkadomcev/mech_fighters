# Листы кадров огня и дыма для взрывов (Blender, без окна):
#   blender -b --python tools/render_flipbook.py -- <explosion|smoke> <папка_вывода> [preview]
# Симуляция Mantaflow (огонь и дым из шара, коротким выбросом), рендер Cycles на видеокарте с прозрачным
# фоном: огненный шар 32 кадра, дым 64, по 256×256. Кадры складываются в лист скриптом tools/pack_flipbook.py.
import bpy, sys, os, math

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
kind = argv[0] if argv else "explosion"
out = os.path.abspath(argv[1] if len(argv) > 1 else "flip_out")
os.makedirs(out, exist_ok=True)

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
FRAMES = 32 if kind == "explosion" else 64      # огненный шар — 32 кадра (лист 8×4), дым — 64 (8×8)

# источник: шар, коротко выбрасывает топливо и дым наружу
bpy.ops.mesh.primitive_uv_sphere_add(radius=0.42 if kind == "explosion" else 0.5, location=(0, 0, 0))
emitter = bpy.context.active_object
bpy.ops.object.quick_smoke(style='BOTH' if kind == "explosion" else 'SMOKE')
domain = [o for o in scene.objects if o.modifiers and o.modifiers[0].type == 'FLUID' and o.modifiers[0].fluid_type == 'DOMAIN'][0]
dom = domain.modifiers[0].domain_settings
# область по размеру облака (куб ±1, растянутый масштабом): шар внизу, облако растёт вверх и вширь
domain.scale = (1.7, 1.7, 1.9) if kind == "explosion" else (1.4, 1.4, 2.0)
domain.location = (0, 0, 1.15 if kind == "explosion" else 1.55)
dom.resolution_max = 128
dom.cache_frame_start = 1
dom.cache_frame_end = FRAMES + 8
dom.cache_type = 'ALL'
dom.cache_directory = os.path.join(out, "cache")
dom.use_noise = True      # доп. детализация огня и клубов
if kind == "smoke":
    dom.use_dissolve_smoke = True      # клуб сам рассеивается к концу
    dom.dissolve_speed = 45
dom.noise_scale = 2
dom.noise_strength = 1.4 if kind == "explosion" else 1.0
dom.vorticity = 0.8 if kind == "explosion" else 0.3
dom.alpha = 0.0 if kind == "explosion" else 0.4        # плотность дыма: тянет вниз/вверх
dom.beta = 0.7 if kind == "explosion" else 0.6          # жар поднимает (мало — шар, а не гриб)
if kind == "explosion":
    dom.burning_rate = 0.45
    dom.flame_smoke = 1.0
    dom.flame_vorticity = 1.0
    dom.flame_max_temp = 2.5

flow = emitter.modifiers[0].flow_settings
flow.use_initial_velocity = True
flow.velocity_normal = 7.5 if kind == "explosion" else 3.0
flow.velocity_coord = (0, 0, 1.0)
flow.surface_distance = 0.6
if kind == "explosion":
    flow.fuel_amount = 3.0
    flow.temperature = 2.0
else:
    flow.temperature = 0.8
    flow.smoke_color = (0.3, 0.29, 0.28)
    flow.density = 2.0
# выброс только первые кадры, потом источник уходит из области (иначе тянется тонкая «ножка» огня)
emitter.location = (0, 0, 0)
emitter.keyframe_insert("location", frame=1)
emitter.keyframe_insert("location", frame=6 if kind == "explosion" else 8)
emitter.location = (0, 0, -30)
emitter.keyframe_insert("location", frame=7 if kind == "explosion" else 9)
for fc in emitter.animation_data.action.fcurves if emitter.animation_data and emitter.animation_data.action and hasattr(emitter.animation_data.action, "fcurves") else []:
    for kp in fc.keyframe_points:
        kp.interpolation = 'CONSTANT'
emitter.hide_render = True

scene.frame_start = 1
scene.frame_end = FRAMES + 8
with bpy.context.temp_override(object=domain, active_object=domain, selected_objects=[domain]):
    bpy.ops.fluid.bake_all()

# материал дыма: плотнее и мягче; у взрыва огонь светится сам
mat = domain.active_material
nodes = mat.node_tree.nodes
pv = [n for n in nodes if n.type == 'PRINCIPLED_VOLUME'][0]
pv.inputs["Density"].default_value = 6.0 if kind == "explosion" else 10.0
if kind == "explosion":
    # огонь светится сам по силе пламени: белое ядро, жёлтое, оранжевое, тёмно-красные края
    pv.inputs["Blackbody Intensity"].default_value = 0.0
    pv.inputs["Color"].default_value = (0.06, 0.055, 0.05, 1.0)
    links = mat.node_tree.links
    fl = nodes.new("ShaderNodeAttribute")
    fl.attribute_name = "flame"
    ramp = nodes.new("ShaderNodeValToRGB")
    cr = ramp.color_ramp
    cr.elements[0].position = 0.0
    cr.elements[0].color = (0.0, 0.0, 0.0, 1.0)
    cr.elements[1].position = 1.0
    cr.elements[1].color = (1.0, 0.95, 0.85, 1.0)
    for pos, col in [(0.08, (0.35, 0.03, 0.0, 1.0)), (0.3, (1.0, 0.25, 0.02, 1.0)), (0.6, (1.0, 0.65, 0.15, 1.0))]:
        e = cr.elements.new(pos)
        e.color = col
    links.new(fl.outputs["Fac"], ramp.inputs["Fac"])
    links.new(ramp.outputs["Color"], pv.inputs["Emission Color"])
    mul = nodes.new("ShaderNodeMath")
    mul.operation = 'MULTIPLY'
    mul.inputs[1].default_value = 40.0
    links.new(fl.outputs["Fac"], mul.inputs[0])
    links.new(mul.outputs["Value"], pv.inputs["Emission Strength"])
else:
    pv.inputs["Color"].default_value = (0.32, 0.3, 0.28, 1.0)

# свет: солнце сверху-сбоку, слабое небо
bpy.ops.object.light_add(type='SUN', location=(4, -4, 8))
sun = bpy.context.active_object
sun.data.energy = 4.0
sun.rotation_euler = (math.radians(40), 0, math.radians(35))
scene.world = bpy.data.worlds.new("w")
scene.world.use_nodes = True
scene.world.node_tree.nodes["Background"].inputs[1].default_value = 0.6

# камера сбоку, ортографическая, кадр вокруг облака
cz = 0.65 if kind == "explosion" else 1.15
bpy.ops.object.camera_add(location=(0, -10, cz), rotation=(math.radians(90), 0, 0))
cam = bpy.context.active_object
cam.data.type = 'ORTHO'
cam.data.ortho_scale = 2.5 if kind == "explosion" else 3.3
scene.camera = cam

scene.render.engine = 'CYCLES'
scene.cycles.device = 'GPU'
prefs = bpy.context.preferences.addons["cycles"].preferences
for ct in ("OPTIX", "CUDA"):
    try:
        prefs.compute_device_type = ct
        prefs.get_devices()
        for d in prefs.devices:
            d.use = True
        break
    except Exception:
        pass
scene.cycles.samples = 48
scene.cycles.volume_bounces = 1
scene.cycles.use_denoising = True
scene.render.film_transparent = True
scene.render.resolution_x = 256
scene.render.resolution_y = 256
scene.render.image_settings.file_format = 'PNG'
scene.render.image_settings.color_mode = 'RGBA'
scene.view_settings.view_transform = 'Standard'

preview = len(argv) > 2 and argv[2] == "preview"      # проба: каждый 8-й кадр
for i in (range(0, FRAMES, 8) if preview else range(FRAMES)):
    scene.frame_set(3 + i)
    scene.render.filepath = os.path.join(out, "f%03d.png" % i)
    bpy.ops.render.render(write_still=True)
print("FLIPBOOK DONE", kind, out)
