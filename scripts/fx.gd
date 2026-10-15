extends Node
## Эффекты: искры от попаданий, взрыв ракеты, волна импульса, метка на земле,
## пыль высадки, столб телепорта, луч рельсотрона, цифры урона.
## Спрайты вспышек и дыма берутся из assets/fx (если их нет, рисуем простыми фигурами).

const Art := preload("res://scripts/art.gd")

signal shake_at(pos: Vector3, amount: float)   # просьба тряхнуть камеру (слушает main.gd)

# места, куда сейчас летят ракеты: [{pos, radius, team, node, born}]. По ним боты решают, куда не стоять
var danger_zones: Array = []
var player_team := 0            # за какую команду играет игрок (чьи секретные метки показывать)

var _spark_mesh: BoxMesh
var _mat_hit: StandardMaterial3D
var _mat_wall: StandardMaterial3D
var _flash_mesh: SphereMesh
var _ring_mesh: ArrayMesh      # плоское кольцо радиусом 1, лежит на земле
var _smoke_mesh: SphereMesh
var _smoke_ramp: Gradient
var _scorch_mesh: QuadMesh
var _scorch_shader: Shader
var _scorches: Array = []      # следы гари на земле (старые убираются, когда их слишком много)
const SCORCH_MAX := 40
const SCORCH_LIFE := 25.0


func _ready() -> void:
	_spark_mesh = BoxMesh.new()
	_spark_mesh.size = Vector3(0.12, 0.12, 0.12)
	_mat_hit = _unshaded(Color(1.0, 0.85, 0.45) * 2.4)
	_mat_wall = _unshaded(Color(0.85, 0.8, 0.7) * 1.4)
	_flash_mesh = SphereMesh.new()
	_flash_mesh.radius = 0.5
	_flash_mesh.height = 1.0
	_flash_mesh.radial_segments = 12
	_flash_mesh.rings = 6
	_ring_mesh = _make_ring(0.9, 1.0, 48)
	_smoke_mesh = SphereMesh.new()
	_smoke_mesh.radius = 0.5
	_smoke_mesh.height = 1.0
	_smoke_mesh.radial_segments = 6
	_smoke_mesh.rings = 3
	_smoke_ramp = Gradient.new()
	_smoke_ramp.set_color(0, Color(0.35, 0.33, 0.31, 0.6))
	_smoke_ramp.set_color(1, Color(0.3, 0.3, 0.32, 0.0))
	_scorch_mesh = QuadMesh.new()
	_scorch_mesh.size = Vector2(2, 2)
	_scorch_mesh.orientation = PlaneMesh.FACE_Y
	_scorch_shader = Shader.new()
	_scorch_shader.code = """
shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled, shadows_disabled;
uniform float fade = 1.0;
uniform float seed = 0.0;
uniform sampler2D burst : filter_linear_mipmap;
uniform float has_burst = 0.0;
float h(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7)) + seed) * 43758.5453); }
float n(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h(i), h(i + vec2(1, 0)), f.x), mix(h(i + vec2(0, 1)), h(i + vec2(1, 1)), f.x), f.y);
}
void fragment() {
	vec2 c = UV * 2.0 - 1.0;
	float r = length(c);
	float a = atan(c.y, c.x);
	// пятно с рваным краем, поверх — звёздчатые лучи копоти от взрыва (спрайт scorch_02)
	float edge = 0.5 + 0.25 * n(vec2(a * 2.5, seed));
	float m = 1.0 - smoothstep(edge * 0.2, edge, r);
	float rays = texture(burst, UV).a * has_burst;
	m = max(m * (0.6 + 0.4 * n(c * 6.0)), rays * 0.8 * (0.55 + 0.45 * n(c * 9.0)));
	ALBEDO = mix(vec3(0.04, 0.035, 0.03), vec3(0.14, 0.1, 0.07), smoothstep(0.0, 0.9, r));
	ALPHA = clamp(m * 0.72 * fade, 0.0, 1.0);
}
"""


func _unshaded(c: Color, alpha := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	if alpha:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _make_ring(r0: float, r1: float, segments: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in segments:
		var a0 := TAU * i / segments
		var a1 := TAU * (i + 1) / segments
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		for v in [d0 * r0, d0 * r1, d1 * r1, d0 * r0, d1 * r1, d1 * r0]:
			st.add_vertex(v)
	return st.commit()


func _mesh_node(mesh: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	get_tree().current_scene.add_child(mi)
	mi.global_position = pos
	return mi


# ------------------------------------------------------------------
#  Искры от попадания снаряда
# ------------------------------------------------------------------

func spark(pos: Vector3, normal: Vector3, on_target: bool, sound := true) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	if on_target:
		# броня: веер оранжевых искр и короткая вспышка
		_streaks(pos, normal, 9, Color(1.0, 0.62, 0.22), 6.0, 15.0, 0.28, 60.0, 0.75)
		_flare(pos, "circle_05", 1.6, Color(1.0, 0.55, 0.2, 1.0), 0.09)
	else:
		# земля или стена: пара искр и облачко пыли (бурой с земли, серой со стены)
		var ground := normal.y > 0.6
		_streaks(pos, normal, 4, Color(1.0, 0.7, 0.35), 4.0, 10.0, 0.2, 55.0, 0.5)
		_emit(pos + normal * 0.2, _quad(), _sprite_mat("smoke_07"), 3, 0.8, {"dir": normal, "spread": 40.0,
			"v0": 0.8, "v1": 2.2, "damp": 1.5, "g": Vector3(0, -0.4 if ground else 0.3, 0), "s0": 0.6, "s1": 1.1,
			"grow": [0.5, 1.6], "spin": 40.0, "ramp": _dust_ramp(Color(0.42, 0.34, 0.25) if ground else Color(0.55, 0.53, 0.5))})
		_flare(pos, "circle_05", 0.7, Color(1.0, 0.6, 0.3, 1.0), 0.06)
	if sound:
		Sfx.play_at("hit" if on_target else "wall", pos, -6.0 if on_target else -14.0, 0.12)


# ------------------------------------------------------------------
#  Взрыв ракеты
# ------------------------------------------------------------------

func explosion(pos: Vector3, radius: float) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var r := radius
	# вспышка
	_flare(pos + Vector3.UP * 0.9, "star_09", r * 3.0, Color(1.0, 0.85, 0.6, 1.0), 0.12)
	_flare(pos + Vector3.UP * 0.7, "circle_05", r * 3.4, Color(1.0, 0.5, 0.15, 1.0), 0.25)
	# огненный шар: плотные клубы раздуваются, темнеют и уходят в копоть
	_emit(pos + Vector3.UP * 0.6, _quad(), _sprite_mat("smoke_07"), 14, 0.75, {"sphere": r * 0.25, "v0": r * 0.6, "v1": r * 1.4,
		"damp": r * 2.0, "g": Vector3(0, 3.0, 0), "s0": r * 0.5, "s1": r * 0.85, "grow": [0.7, 1.6], "spin": 60.0, "ramp": _fire_ramp()})
	# раскалённое ядро шара светится поверх клубов и быстро гаснет
	_emit(pos + Vector3.UP * 0.7, _quad(), _sprite_mat("smoke_07", true), 8, 0.35, {"sphere": r * 0.2, "v0": r * 0.4, "v1": r * 1.0,
		"damp": r * 2.0, "s0": r * 0.45, "s1": r * 0.75, "grow": [0.8, 1.4], "spin": 60.0, "ramp": _hot_ramp()})
	# языки пламени
	_emit(pos + Vector3.UP * 0.6, _quad(), _sprite_mat("fire_01", true), 8, 0.5, {"sphere": r * 0.3, "v0": r * 0.8, "v1": r * 1.6,
		"damp": r * 2.0, "g": Vector3(0, 4.0, 0), "s0": r * 0.4, "s1": r * 0.7, "grow": [0.6, 1.2], "spin": 90.0, "ramp": _hot_ramp()})
	# столб тёмного дыма
	_emit(pos + Vector3.UP * 0.9, _quad(), _sprite_mat("smoke_04"), 10, 2.4, {"burst": 0.75, "sphere": r * 0.35, "spread": 45.0,
		"v0": 1.0, "v1": 3.2, "damp": 0.6, "g": Vector3(0.4, 1.2, 0.2), "s0": r * 0.7, "s1": r * 1.2, "grow": [0.7, 2.2],
		"spin": 25.0, "ramp": _smoke_ramp2()})
	# обломки разлетаются и падают
	_emit(pos + Vector3.UP * 0.4, _chunk(), _chunk_material(), 10, 1.1, {"spread": 70.0, "v0": 7.0, "v1": 15.0,
		"g": Vector3(0, -24, 0), "s0": 0.5, "s1": 1.4, "spin": 400.0})
	# искры и угли
	_streaks(pos + Vector3.UP * 0.6, Vector3.UP, 18, Color(1.0, 0.55, 0.15), 9.0, 20.0, 0.7, 80.0, 0.9)

	# ударная волна по земле: показывает реальный радиус урона
	var ring_mat := _unshaded(Color(1.0, 0.6, 0.25, 0.5), true)
	var ground := Vector3(pos.x, 0.12, pos.z)
	var ring := _mesh_node(_ring_mesh, ring_mat, ground)
	ring.scale = Vector3(r * 0.2, 1, r * 0.2)
	var tw2 := ring.create_tween()
	tw2.tween_property(ring, "scale", Vector3(r, 1, r), 0.22).set_ease(Tween.EASE_OUT)
	tw2.parallel().tween_property(ring_mat, "albedo_color:a", 0.0, 0.4)
	tw2.tween_callback(ring.queue_free)

	_flash_light(pos + Vector3.UP * 1.5, Color(1.0, 0.6, 0.25), r * 3.0, 0.35)
	shake_at.emit(pos, Cfg.shake_explosion)
	if pos.y < 3.5:
		scorch(Vector3(pos.x, 0, pos.z), r * 0.8)


# тёмное пятно гари на земле после взрыва, медленно выцветает
func scorch(pos: Vector3, radius: float) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	if _scorches.size() >= SCORCH_MAX:
		var old = _scorches.pop_front()
		if is_instance_valid(old):
			old.queue_free()
	var mat := ShaderMaterial.new()
	mat.shader = _scorch_shader
	mat.set_shader_parameter("seed", randf() * 100.0)
	var bt := Art.fx_tex("scorch_02")
	if bt != null:
		mat.set_shader_parameter("burst", bt)
		mat.set_shader_parameter("has_burst", 1.0)
	var mi := MeshInstance3D.new()
	mi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	mi.mesh = _scorch_mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = pos + Vector3.UP * (0.03 + randf() * 0.02)
	mi.rotation.y = randf() * TAU
	mi.scale = Vector3.ONE * radius * 1.35
	scene.add_child(mi)
	_scorches.append(mi)
	var tw := mi.create_tween()
	tw.tween_interval(SCORCH_LIFE * 0.6)
	tw.tween_method(func(v: float): mat.set_shader_parameter("fade", v), 1.0, 0.0, SCORCH_LIFE * 0.4)
	tw.tween_callback(func():
		_scorches.erase(mi)
		mi.queue_free())


# короткая вспышка настоящего света (освещает землю и стены вокруг взрыва).
# Одновременно не больше нескольких, чтобы не тормозило: на высокой графике 6, на средней 3, на низкой нет
var _lights := 0


func _flash_light(pos: Vector3, col: Color, rng: float, time: float) -> void:
	if _lights >= Cfg.gfx(0, 3, 6) or get_tree().current_scene == null:
		return
	_lights += 1
	var l := OmniLight3D.new()
	l.tree_exiting.connect(func() -> void: _lights -= 1)     # и когда бой закрыли посреди вспышки
	l.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	l.light_color = col
	l.light_energy = 5.0
	l.omni_range = rng
	l.shadow_enabled = false
	get_tree().current_scene.add_child(l)
	l.global_position = pos
	var tw := l.create_tween()
	tw.tween_property(l, "light_energy", 0.0, time).set_ease(Tween.EASE_OUT)
	tw.tween_callback(l.queue_free)


# ------------------------------------------------------------------
#  Волна импульса вокруг меха
# ------------------------------------------------------------------

func pulse(pos: Vector3, radius: float) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var ground := Vector3(pos.x, 0.15, pos.z)
	# две волны по земле, вторая с небольшой задержкой
	for i in 2:
		var ring_mat := _unshaded(Color(0.45, 0.8, 1.0, 0.95 if i == 0 else 0.6), true)
		var ring := _mesh_node(_ring_mesh, ring_mat, ground)
		ring.scale = Vector3(1.0, 1, 1.0)
		var tw := ring.create_tween()
		if i == 1:
			tw.tween_interval(0.07)
		tw.tween_property(ring, "scale", Vector3(radius, 1, radius), 0.28).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(ring_mat, "albedo_color:a", 0.0, 0.5)
		tw.tween_callback(ring.queue_free)
	# прозрачный купол
	var dome_mat := _unshaded(Color(0.5, 0.82, 1.0, 0.35), true)
	var dome := _mesh_node(_flash_mesh, dome_mat, pos)
	dome.scale = Vector3.ONE * 2.0
	var tw2 := dome.create_tween()
	tw2.tween_property(dome, "scale", Vector3(radius * 2.0, radius * 0.9, radius * 2.0), 0.25).set_ease(Tween.EASE_OUT)
	tw2.parallel().tween_property(dome_mat, "albedo_color:a", 0.0, 0.32)
	tw2.tween_callback(dome.queue_free)

	shake_at.emit(pos, Cfg.shake_explosion * 0.5)


# ------------------------------------------------------------------
#  Короткая вспышка: блинк, включение невидимости
# ------------------------------------------------------------------

func burst(pos: Vector3, color: Color, radius: float) -> void:
	if get_tree().current_scene == null:
		return
	var mat := _unshaded(Color(color.r, color.g, color.b, 0.6), true)
	var ball := _mesh_node(_flash_mesh, mat, pos)
	ball.scale = Vector3.ONE * radius * 0.4
	var tw := ball.create_tween()
	tw.tween_property(ball, "scale", Vector3(radius * 2.0, radius * 1.4, radius * 2.0), 0.2).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(mat, "albedo_color:a", 0.0, 0.25)
	tw.tween_callback(ball.queue_free)
	var ring_mat := _unshaded(Color(color.r, color.g, color.b, 0.9), true)
	var ring := _mesh_node(_ring_mesh, ring_mat, Vector3(pos.x, 0.12, pos.z))
	ring.scale = Vector3(0.5, 1, 0.5)
	var tw2 := ring.create_tween()
	tw2.tween_property(ring, "scale", Vector3(radius, 1, radius), 0.22).set_ease(Tween.EASE_OUT)
	tw2.parallel().tween_property(ring_mat, "albedo_color:a", 0.0, 0.3)
	tw2.tween_callback(ring.queue_free)


# ------------------------------------------------------------------
#  Метка на земле: сюда прилетит залп
# ------------------------------------------------------------------

# life: через сколько секунд метка уберётся сама; danger: боты стараются из неё выйти;
# secret: метку видит только своя команда (враг не знает, куда прилетит)
func ground_marker(pos: Vector3, radius: float, color: Color, team := 0, life := 6.0, danger := true, secret := false) -> Node3D:
	var mat := _unshaded(Color(color.r, color.g, color.b, 0.85), true)
	mat.no_depth_test = true
	mat.render_priority = 5
	var ring := _mesh_node(_ring_mesh, mat, Vector3(pos.x, 0.1, pos.z))
	ring.scale = Vector3(radius, 1, radius)
	# точка в центре
	var dot_mat := _unshaded(Color(color.r, color.g, color.b, 0.5), true)
	dot_mat.no_depth_test = true
	var dot := MeshInstance3D.new()
	dot.mesh = _ring_mesh
	dot.material_override = dot_mat
	dot.scale = Vector3(0.12, 1, 0.12)
	dot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.add_child(dot)
	# мигает, чтобы привлекать внимание
	var tw := ring.create_tween().set_loops()
	tw.tween_property(mat, "albedo_color:a", 0.35, 0.18)
	tw.tween_property(mat, "albedo_color:a", 0.9, 0.18)
	# страховка: если ракеты куда-то делись, метка уберётся сама
	var kill := ring.create_tween()
	kill.tween_interval(life)
	kill.tween_callback(ring.queue_free)
	if secret and team >= 0 and team != player_team:
		ring.visible = false
	if danger:
		danger_zones.append({"pos": Vector3(pos.x, 0, pos.z), "radius": radius, "team": team, "node": ring,
			"born": Time.get_ticks_msec(), "secret": secret})
	return ring


# хитбоксы команды (мехи, турели, штаб): свои снаряды сквозь них пролетают
func team_rids(team: int) -> Array[RID]:
	var out: Array[RID] = []
	for n in get_tree().get_nodes_in_group("team_hitbox"):
		if n.team == team:
			out.append(n.get_rid())
	return out


func _physics_process(_delta: float) -> void:
	# метка исчезла (ракеты взорвались) -> зона больше не опасна
	for i in range(danger_zones.size() - 1, -1, -1):
		if not is_instance_valid(danger_zones[i]["node"]):
			danger_zones.remove_at(i)


# ------------------------------------------------------------------
#  Спрайт-вспышка: плоская картинка лицом к камере, светится и гаснет
# ------------------------------------------------------------------

var _flare_mats := {}
var _flare_quad: QuadMesh


func _flare(pos: Vector3, tex_name: String, size: float, col: Color, life: float) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var tex := Art.fx_tex(tex_name)
	if tex == null:
		return
	if _flare_quad == null:
		_flare_quad = QuadMesh.new()
		_flare_quad.size = Vector2.ONE
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_texture = tex
	m.albedo_color = col
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.no_depth_test = false
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mi := _mesh_node(_flare_quad, m, pos)
	mi.scale = Vector3.ONE * size
	mi.rotation.z = randf() * TAU
	var tw := mi.create_tween()
	tw.tween_property(m, "albedo_color:a", 0.0, life).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(mi, "scale", Vector3.ONE * size * 1.3, life)
	tw.tween_callback(mi.queue_free)


# ------------------------------------------------------------------
#  Урон по площади: всем врагам (и стенам, обломкам) в радиусе, к краю слабее.
#  Возвращает список задетых
# ------------------------------------------------------------------

func blast(pos: Vector3, radius: float, dmg: float, edge: float, team: int, src: Node = null, kind := "explosion") -> Array:
	var out: Array = []
	for n in get_tree().get_nodes_in_group("damageable"):
		if not (n is Node3D) or not n.has_method("take_damage"):
			continue
		if n.get("team") == team:     # своих (и себя) взрыв не задевает
			continue
		var dist: float
		if n.has_method("blast_distance"):
			dist = n.blast_distance(pos)
		else:
			var d: Vector3 = n.global_position - pos
			d.y = 0
			# расстояние считаем до края хитбокса, а не до центра цели
			var size: float = n.get_hit_radius() if n.has_method("get_hit_radius") else 1.0
			dist = maxf(d.length() - size, 0.0)
		if dist > radius:
			continue
		var k := dist / maxf(radius, 0.01)
		var dir: Vector3 = n.global_position - pos
		dir.y = 0
		n.take_damage(lerpf(dmg, dmg * edge, k), n.global_position + Vector3.UP * 2.0, dir.normalized(), kind, src)
		out.append(n)
	return out


# попадание сгустка плазмы: голубая (у врага розовая) вспышка
func plasma_hit(pos: Vector3, friend: bool) -> void:
	var c := Color(0.45, 0.9, 1.0) if friend else Color(1.0, 0.35, 0.8)
	_flare(pos, "circle_05", 2.4, Color(c.r, c.g, c.b, 1.0), 0.15)
	_flare(pos, "star_07", 1.8, Color(c.r, c.g, c.b, 1.0), 0.1)
	Sfx.play_at("hit", pos, -10.0, 0.2)


# луч рельсотрона: яркая полоса, быстро тает
func rail_beam(from: Vector3, to: Vector3, team: int) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var friend := team == player_team
	var c := Color(0.5, 0.9, 1.0) if friend else Color(1.0, 0.4, 0.4)
	var d := to - from
	var len := maxf(d.length(), 0.1)
	var dir := d / len
	# ящик растягиваем по его собственным осям (умножение справа). Basis.scaled() тянет по осям МИРА:
	# выстрел вдоль X рисовался полосой длиной во весь выстрел поперёк, по Z, «через всю карту»
	# широкое свечение и тонкое белое ядро, оба мягкие по краям и гаснут
	for layer in 2:
		var mat := beam_material(c if layer == 0 else Color(0.92, 0.97, 1.0), 3.5 if layer == 0 else 4.0, 1.4 if layer == 0 else 1.0, 0.35)
		var mi := _mesh_node(_unit_quad(), mat, from + d * 0.5)
		place_beam(mi, from, to, 1.8 if layer == 0 else 0.45)
		var tw := mi.create_tween()
		tw.tween_method(func(v: float): mat.set_shader_parameter("fade", v), 1.0, 0.0, 0.4).set_ease(Tween.EASE_IN)
		tw.tween_callback(mi.queue_free)
	_streaks(to, -dir, 8, c, 5.0, 12.0, 0.3, 70.0, 0.8)
	_flare(from, "flare_01", 4.0, Color(c.r, c.g, c.b, 1.0), 0.15)
	_flare(to, "star_09", 3.0, Color(c.r, c.g, c.b, 1.0), 0.2)
	_flash_light(from, c, 10.0, 0.15)
	shake_at.emit(from, shake_rail)


var shake_rail := 0.12


# пыль по земле: кольцо при приземлении меха
func dust_ring(pos: Vector3, radius: float) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var p := CPUParticles3D.new()
	var mat := _unshaded(Color(1, 1, 1, 1), true)
	mat.vertex_color_use_as_albedo = true
	var stex := Art.fx_tex("smoke_07")
	if stex != null:
		var qm := QuadMesh.new()
		qm.size = Vector2(2, 2)
		p.mesh = qm
		mat.albedo_texture = stex
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		p.angle_max = 360.0
	else:
		p.mesh = _smoke_mesh
	p.material_override = mat
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.55, 0.5, 0.42, 0.55))
	ramp.set_color(1, Color(0.5, 0.48, 0.45, 0.0))
	p.color_ramp = ramp
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = 18
	p.lifetime = 1.1
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	p.emission_ring_axis = Vector3.UP
	p.emission_ring_radius = 1.0
	p.emission_ring_inner_radius = 0.5
	p.emission_ring_height = 0.1
	p.direction = Vector3(1, 0.15, 0)
	p.spread = 180.0
	p.flatness = 0.9
	p.initial_velocity_min = radius * 1.2
	p.initial_velocity_max = radius * 2.2
	p.damping_min = radius * 1.5
	p.damping_max = radius * 2.2
	p.gravity = Vector3(0, 0.5, 0)
	p.scale_amount_min = 1.0
	p.scale_amount_max = 2.2
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.position = pos + Vector3.UP * 0.4
	scene.add_child(p)
	p.emitting = true
	get_tree().create_timer(1.6).timeout.connect(p.queue_free)
	shake_at.emit(pos, shake_explosion_land)


var shake_explosion_land := 0.25


# столб света вокруг меха, пока он телепортируется на базу; удаляется, когда телепорт закончен или сбит
func tp_column(owner_node: Node3D, team: int) -> Node3D:
	var root := Node3D.new()
	owner_node.add_child(root)
	var c := Color(0.45, 0.85, 1.0) if team == player_team else Color(1.0, 0.35, 0.3)
	var mat := _unshaded(Color(c.r * 1.5, c.g * 1.5, c.b * 1.5, 0.35), true)
	var cm := CylinderMesh.new()
	cm.top_radius = 1.6
	cm.bottom_radius = 2.2
	cm.height = 14.0
	cm.radial_segments = 24
	cm.rings = 1
	cm.cap_top = false
	cm.cap_bottom = false
	var col := MeshInstance3D.new()
	col.mesh = cm
	col.material_override = mat
	col.position.y = 7.0
	col.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(col)
	var ring := MeshInstance3D.new()
	ring.mesh = _ring_mesh
	ring.material_override = _unshaded(Color(c.r * 2.0, c.g * 2.0, c.b * 2.0, 0.9), true)
	ring.scale = Vector3(2.6, 1, 2.6)
	ring.position.y = 0.12
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ring)
	var tw := root.create_tween().set_loops()
	tw.tween_property(mat, "albedo_color:a", 0.6, 0.35)
	tw.tween_property(mat, "albedo_color:a", 0.25, 0.35)
	var tw2 := root.create_tween().set_loops()
	tw2.tween_property(col, "rotation:y", TAU, 1.2).from(0.0)
	return root


# цифра урона над целью: всплывает и тает
func damage_number(pos: Vector3, amount: float, col: Color) -> void:
	var scene := get_tree().current_scene
	if scene == null or amount < 0.5:
		return
	var l := Label3D.new()
	l.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	l.text = str(int(round(amount)))
	l.font_size = 56
	l.pixel_size = 0.012
	l.outline_size = 14
	l.modulate = col
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.fixed_size = false
	scene.add_child(l)
	l.global_position = pos + Vector3(randf_range(-0.6, 0.6), 3.0, randf_range(-0.4, 0.4))
	var tw := l.create_tween()
	tw.tween_property(l, "global_position:y", l.global_position.y + 2.2, 0.7).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.7).set_delay(0.3)
	tw.tween_callback(l.queue_free)


# ------------------------------------------------------------------
#  Пыль от шага: маленькое облачко у ступни. size: 0.7 лёгкий, 1 средний, 1.4 тяжёлый
# ------------------------------------------------------------------

var _step_mat: StandardMaterial3D
var _step_mesh: Mesh
var _step_ramp: Gradient


func step_dust(pos: Vector3, size: float) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	if _step_mat == null:
		_step_mat = _unshaded(Color(1, 1, 1, 1), true)
		_step_mat.vertex_color_use_as_albedo = true
		var stex := Art.fx_tex("smoke_07")
		if stex != null:
			var qm := QuadMesh.new()
			qm.size = Vector2(1.4, 1.4)
			_step_mesh = qm
			_step_mat.albedo_texture = stex
			_step_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		else:
			_step_mesh = _smoke_mesh
		_step_ramp = Gradient.new()
		_step_ramp.set_color(0, Color(0.55, 0.5, 0.42, 0.4))
		_step_ramp.set_color(1, Color(0.5, 0.48, 0.45, 0.0))
	var p := CPUParticles3D.new()
	p.mesh = _step_mesh
	p.material_override = _step_mat
	p.color_ramp = _step_ramp
	p.angle_max = 360.0
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = 6
	p.lifetime = 0.7
	p.direction = Vector3(1, 0.2, 0)
	p.spread = 180.0
	p.flatness = 0.85
	p.initial_velocity_min = 1.0 * size
	p.initial_velocity_max = 2.4 * size
	p.damping_min = 3.0
	p.damping_max = 4.0
	p.gravity = Vector3(0, 0.4, 0)
	p.scale_amount_min = 0.6 * size
	p.scale_amount_max = 1.2 * size
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.position = Vector3(pos.x, 0.2, pos.z)
	scene.add_child(p)
	p.emitting = true
	get_tree().create_timer(1.0).timeout.connect(p.queue_free)


# ------------------------------------------------------------------
#  Гильза: вылетает вбок из пушки, падает, звякает, лежит пару секунд и пропадает
# ------------------------------------------------------------------

var _casing_mesh := {}
var _casing_mat: StandardMaterial3D
var _casings: Array = []
const CASING_MAX := 60


func casing(pos: Vector3, side: Vector3, big := false, sound := true) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	if _casing_mat == null:
		_casing_mat = StandardMaterial3D.new()
		_casing_mat.albedo_color = Color(0.85, 0.62, 0.25)
		_casing_mat.metallic = 0.9
		_casing_mat.roughness = 0.3
	if not _casing_mesh.has(big):
		var cm := CylinderMesh.new()
		cm.top_radius = 0.11 if big else 0.06
		cm.bottom_radius = cm.top_radius
		cm.height = 0.42 if big else 0.22
		cm.radial_segments = 6
		cm.rings = 1
		_casing_mesh[big] = cm
	var mi := _mesh_node(_casing_mesh[big], _casing_mat, pos)
	# старые гильзы убираем, чтобы при Гатлинге их не было сотни
	_casings.append(mi)
	while _casings.size() > CASING_MAX:
		var old = _casings.pop_front()
		if is_instance_valid(old):
			old.queue_free()
	var out := (side + Vector3(randf_range(-0.3, 0.3), 0, randf_range(-0.3, 0.3))).normalized()
	var land := Vector3(pos.x, 0.07, pos.z) + out * randf_range(1.2, 2.4)
	var start := pos
	var h := randf_range(0.6, 1.2)
	var spin := Vector3(randf_range(8, 14), randf_range(-4, 4), randf_range(6, 12))
	var fall := 0.35 + pos.y * 0.04
	var tw := mi.create_tween()
	tw.tween_method(func(k: float):
		if not is_instance_valid(mi):
			return
		var p := start.lerp(land, k)
		p.y = lerpf(start.y, land.y, k * k) + 4.0 * h * k * (1.0 - k)
		mi.global_position = p
		mi.rotation = spin * k, 0.0, 1.0, fall)
	tw.tween_callback(func():
		mi.rotation = Vector3(PI / 2, randf() * TAU, 0)
		if sound:
			Sfx.play_at("casing", land, -16.0, 0.15))
	tw.tween_interval(2.5)
	tw.tween_property(mi, "scale", Vector3.ONE * 0.01, 0.4)
	tw.tween_callback(func():
		_casings.erase(mi)
		mi.queue_free())


# ------------------------------------------------------------------
#  Метка игрока (Alt+клик): кольцо на земле и звук
# ------------------------------------------------------------------

signal pinged(pos: Vector3, team: int)


func ping(pos: Vector3, team: int) -> void:
	var col := Color(0.4, 1.0, 0.6)
	var r := ground_marker(pos, 1.6, col, team, 3.0, false)
	var tw := r.create_tween()
	r.scale = Vector3(4.0, 1, 4.0)
	tw.tween_property(r, "scale", Vector3(1.6, 1, 1.6), 0.25).set_ease(Tween.EASE_OUT)
	_flare(pos + Vector3.UP * 0.5, "circle_05", 3.0, Color(0.4, 1.0, 0.6, 0.8), 0.5)
	Sfx.play("ping", -4.0)
	pinged.emit(pos, team)


# ------------------------------------------------------------------
#  Электризация (оглушение): короткие ломаные молнии, пляшут по корпусу.
#  center: точка у земли под юнитом, radius: насколько широко, height: до какой высоты
# ------------------------------------------------------------------

var _zap_core: Material
var _zap_glow: Material
var _zap_haze: Material


func _zap_mats() -> void:
	if _zap_core == null:
		# ленты уже повёрнуты к камере, мягкие края по UV.x
		_zap_core = beam_material(Color(0.85, 0.93, 1.0), 4.0, 0.8, 0.5, false)
		_zap_glow = beam_material(Color(0.3, 0.55, 1.0), 2.2, 1.8, 0.0, false)
		_zap_haze = beam_material(Color(0.25, 0.45, 1.0), 0.6, 2.5, 0.0, false)


func zap(center: Vector3, radius: float, height: float) -> void:
	var scene := get_tree().current_scene
	var cam := get_viewport().get_camera_3d()
	if scene == null or cam == null:
		return
	_zap_mats()
	# два конца на поверхности юнита, недалеко друг от друга
	var a0 := randf() * TAU
	var a1 := a0 + randf_range(0.6, 1.8) * (1.0 if randf() < 0.5 else -1.0)
	var r0 := radius * randf_range(0.85, 1.15)
	var r1 := radius * randf_range(0.85, 1.15)
	var p0 := center + Vector3(cos(a0) * r0, randf_range(0.3, height), sin(a0) * r0)
	var p1 := center + Vector3(cos(a1) * r1, randf_range(0.3, height), sin(a1) * r1)
	# ломаная: середина зигзагом, плюс иногда отросток
	var pts: Array[Vector3] = [p0]
	var n := 6
	var span := p0.distance_to(p1)
	for i in range(1, n):
		var k := float(i) / n
		var j := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * span * 0.18
		pts.append(p0.lerp(p1, k) + j)
	pts.append(p1)
	var branch: Array[Vector3] = []
	if randf() < 0.5:
		var from := pts[randi_range(2, n - 2)]
		branch = [from, from + Vector3(randf_range(-1, 1), randf_range(-0.6, 0.4), randf_range(-1, 1)) * span * 0.4]
	var im := ImmediateMesh.new()
	var view := cam.global_position
	for pass_i in 2:
		var w := 0.1 if pass_i == 0 else 0.45
		im.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _zap_core if pass_i == 0 else _zap_glow)
		_ribbon(im, pts, w, view)
		if not branch.is_empty():
			_ribbon(im, branch, w * 0.7, view)
		im.surface_end()
	var mi := _mesh_node(im, null, Vector3.ZERO)
	var tw := mi.create_tween()
	tw.tween_interval(randf_range(0.05, 0.1))
	tw.tween_callback(mi.queue_free)
	if randf() < 0.25:
		_flare(pts[randi_range(1, n - 1)], "spark_01", 0.9, Color(0.6, 0.85, 1.0, 1.0), 0.08)


# полоска из квадов вдоль ломаной, повёрнутая к камере
func _ribbon(im: ImmediateMesh, pts: Array[Vector3], w: float, view: Vector3) -> void:
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var side := (b - a).cross(view - a).normalized() * w * 0.5
		# UV.x поперёк ленты: шейдер делает мягкие края и яркое ядро
		for v in [[a - side, 0.0], [a + side, 1.0], [b + side, 1.0], [a - side, 0.0], [b + side, 1.0], [b - side, 0.0]]:
			im.surface_set_uv(Vector2(v[1], 0.5))
			im.surface_add_vertex(v[0])


# ------------------------------------------------------------------
#  Молния Теслы (ядро штаба): толстая ломаная от шара до цели, мигает 3 раза за четверть секунды
# ------------------------------------------------------------------

func tesla_bolt(from: Vector3, to: Vector3) -> void:
	for i in 3:
		get_tree().create_timer(i * 0.07, false).timeout.connect(_bolt.bind(from, to, 1.0 - i * 0.2))
	_flare(to, "star_07", 4.5, Color(0.6, 0.85, 1.0, 1.0), 0.18)
	_flare(to, "circle_05", 5.0, Color(0.35, 0.6, 1.0, 1.0), 0.25)
	_flare(from, "circle_05", 4.0, Color(0.5, 0.8, 1.0, 1.0), 0.22)
	_streaks(to, Vector3.UP, 12, Color(0.65, 0.85, 1.0), 5.0, 13.0, 0.35, 90.0, 0.8)
	_flash_light(to, Color(0.5, 0.75, 1.0), 12.0, 0.18)
	shake_at.emit(to, 0.15)


func _bolt(from: Vector3, to: Vector3, k: float) -> void:
	var scene := get_tree().current_scene
	var cam := get_viewport().get_camera_3d()
	if scene == null or cam == null:
		return
	_zap_mats()
	var span := from.distance_to(to)
	var n := clampi(int(span / 1.2), 8, 30)
	var pts: Array[Vector3] = [from]
	for i in range(1, n):
		var t := float(i) / n
		var amp := span * 0.07 * sin(t * PI)
		pts.append(from.lerp(to, t) + Vector3(randf_range(-1, 1), randf_range(-0.6, 0.6), randf_range(-1, 1)) * amp)
	pts.append(to)
	# отростки: короткие ломаные от случайных точек основной молнии
	var branches: Array = []
	for b in 3:
		var j := randi_range(2, n - 2)
		var br: Array[Vector3] = [pts[j]]
		var dir := Vector3(randf_range(-1, 1), randf_range(-0.8, 0.2), randf_range(-1, 1)).normalized()
		for q in 3:
			br.append(br[-1] + (dir + Vector3(randf_range(-0.5, 0.5), randf_range(-0.4, 0.4), randf_range(-0.5, 0.5))) * span * 0.05)
		branches.append(br)
	var im := ImmediateMesh.new()
	var view := cam.global_position
	for pass_i in 3:
		var w: float = [0.32, 1.5, 3.6][pass_i] * k
		im.surface_begin(Mesh.PRIMITIVE_TRIANGLES, [_zap_core, _zap_glow, _zap_haze][pass_i])
		_ribbon(im, pts, w, view)
		for br in branches:
			_ribbon(im, br, w * 0.55, view)
		im.surface_end()
	var mi := _mesh_node(im, null, Vector3.ZERO)
	var tw := mi.create_tween()
	tw.tween_interval(0.07)
	tw.tween_callback(mi.queue_free)


# ------------------------------------------------------------------
#  Кирпичики эффектов: светящийся луч с мягкими краями, облачка и искры частицами
# ------------------------------------------------------------------

const BEAM_SHADER := """shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec3 col = vec3(1.0, 0.5, 0.2);
uniform float energy = 3.0;
uniform float soft = 1.6;
uniform float core = 0.3;
uniform float fade = 1.0;
uniform bool billboard = true;
uniform float tip = 0.0;
void vertex() {
	// плоскость вдоль своей оси Y, развёрнута к камере (длина — ось Y узла, ширина — ось X)
	if (billboard) {
		vec3 axis = MODEL_MATRIX[1].xyz;
		vec3 c = MODEL_MATRIX[3].xyz;
		vec3 side = cross(axis, INV_VIEW_MATRIX[3].xyz - c);
		float sl = length(side);
		side = sl > 0.00001 ? side / sl : vec3(1.0, 0.0, 0.0);
		side *= length(MODEL_MATRIX[0].xyz);
		vec3 nrm = normalize(cross(side, axis) + vec3(0.0, 0.00001, 0.0));
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(vec4(side, 0.0), vec4(axis, 0.0), vec4(nrm, 0.0), vec4(c, 1.0));
	}
}
void fragment() {
	float e = 1.0 - abs(UV.x * 2.0 - 1.0);
	float ends = 1.0;
	if (tip > 0.0) {
		ends = smoothstep(0.0, tip, UV.y) * smoothstep(0.0, tip, 1.0 - UV.y);
	}
	float glow = pow(e, soft) * ends;
	float hot = smoothstep(1.0 - core, 1.0, e) * ends;
	ALBEDO = col * energy + vec3(hot * energy * 0.7);
	ALPHA = clamp(glow * fade, 0.0, 1.0);
}
"""

var _beam_shader: Shader
var _sprite_mats := {}
var _ramps := {}
var _unit_q: QuadMesh
var _part_quad: QuadMesh
var _streak_quad: QuadMesh
var _chunk_box: BoxMesh
var _chunk_mat: StandardMaterial3D


# светящийся луч: яркое ядро, к краям мягко гаснет. billboard — плоскость сама повёрнута к камере
# (лазер, рельса, трассер, искра); без него края задаёт UV.x (ленты молнии)
func beam_material(col: Color, energy := 3.0, soft := 1.6, core := 0.3, billboard := true, tip := 0.0) -> ShaderMaterial:
	if _beam_shader == null:
		_beam_shader = Shader.new()
		_beam_shader.code = BEAM_SHADER
	var m := ShaderMaterial.new()
	m.shader = _beam_shader
	m.set_shader_parameter("col", Vector3(col.r, col.g, col.b))
	m.set_shader_parameter("energy", energy)
	m.set_shader_parameter("soft", soft)
	m.set_shader_parameter("core", core)
	m.set_shader_parameter("billboard", billboard)
	m.set_shader_parameter("tip", tip)
	return m


# поставить луч (плоскость 1×1 с beam_material) от from до to шириной width
func place_beam(mi: Node3D, from: Vector3, to: Vector3, width: float) -> void:
	var d := to - from
	if d.length() < 0.001:
		d = Vector3(0, 0, -0.001)
	var perp := d.cross(Vector3.UP)
	if perp.length() < 0.0001:
		perp = d.cross(Vector3.RIGHT)
	perp = perp.normalized() * width
	mi.global_transform = Transform3D(Basis(perp, d, perp.cross(d).normalized()), from + d * 0.5)


func _unit_quad() -> QuadMesh:
	if _unit_q == null:
		_unit_q = QuadMesh.new()
		_unit_q.size = Vector2.ONE
	return _unit_q


func _quad() -> QuadMesh:
	if _part_quad == null:
		_part_quad = QuadMesh.new()
		_part_quad.size = Vector2.ONE
	return _part_quad


func _chunk() -> BoxMesh:
	if _chunk_box == null:
		_chunk_box = BoxMesh.new()
		_chunk_box.size = Vector3(0.22, 0.16, 0.2)
	return _chunk_box


func _chunk_material() -> StandardMaterial3D:
	if _chunk_mat == null:
		_chunk_mat = StandardMaterial3D.new()
		_chunk_mat.albedo_color = Color(0.08, 0.072, 0.065)
		_chunk_mat.roughness = 0.9
	return _chunk_mat


# спрайт из assets/fx для частиц: всегда лицом к камере, цвет и прозрачность из частицы
func _sprite_mat(tex: String, add := false) -> StandardMaterial3D:
	var key := tex + ("+" if add else "")
	if _sprite_mats.has(key):
		return _sprite_mats[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if add:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_texture = Art.fx_tex(tex)
	_sprite_mats[key] = m
	return m


func _ramp(key: String, stops: Array) -> Gradient:
	if _ramps.has(key):
		return _ramps[key]
	var g := Gradient.new()
	var offs := PackedFloat32Array()
	var cols := PackedColorArray()
	for st in stops:
		offs.append(st[0])
		cols.append(st[1])
	g.offsets = offs
	g.colors = cols
	_ramps[key] = g
	return g


# огонь: бело-жёлтый, оранжевый, тёмно-красный и в копоть (ярче 1 — светится)
func _fire_ramp() -> Gradient:
	return _ramp("fire", [[0.0, Color(1.6, 1.3, 0.85, 1.0)], [0.18, Color(1.5, 0.75, 0.22, 1.0)], [0.45, Color(0.7, 0.22, 0.06, 0.9)],
		[0.75, Color(0.18, 0.1, 0.07, 0.6)], [1.0, Color(0.08, 0.07, 0.06, 0.0)]])


# свечение огня (для сложения цветов): жёлто-белое, оранжевое, гаснет
func _hot_ramp() -> Gradient:
	return _ramp("hot", [[0.0, Color(1.0, 0.85, 0.5, 1.0)], [0.3, Color(1.0, 0.5, 0.15, 0.8)], [1.0, Color(0.6, 0.15, 0.03, 0.0)]])


func _smoke_ramp2() -> Gradient:
	return _ramp("smoke", [[0.0, Color(0.14, 0.12, 0.1, 0.0)], [0.12, Color(0.16, 0.14, 0.12, 0.8)], [0.5, Color(0.24, 0.22, 0.2, 0.55)],
		[1.0, Color(0.32, 0.3, 0.28, 0.0)]])


func _dust_ramp(c: Color) -> Gradient:
	return _ramp("dust_" + c.to_html(), [[0.0, Color(c.r, c.g, c.b, 0.0)], [0.15, Color(c.r, c.g, c.b, 0.6)], [1.0, Color(c.r * 1.1, c.g * 1.1, c.b * 1.1, 0.0)]])


# на низкой и средней графике частиц меньше
func _gfx_k() -> float:
	return Cfg.gfx(0.5, 0.75, 1.0)


# одноразовый выброс частиц. cfg: dir, spread, v0, v1, g, damp, s0, s1, grow [от, до], spin (градусов/с),
# sphere (радиус облака вылета), burst (0..1, одновременность), ramp (цвет по жизни), align (вытянуть вдоль скорости)
func _emit(pos: Vector3, mesh: Mesh, mat: Material, amount: int, life: float, cfg := {}) -> CPUParticles3D:
	var scene := get_tree().current_scene
	var p := CPUParticles3D.new()
	p.mesh = mesh
	p.material_override = mat
	p.one_shot = true
	p.explosiveness = cfg.get("burst", 1.0)
	p.amount = maxi(int(round(amount * _gfx_k())), 1)
	p.lifetime = life
	p.direction = cfg.get("dir", Vector3.UP)
	p.spread = cfg.get("spread", 180.0)
	p.initial_velocity_min = cfg.get("v0", 1.0)
	p.initial_velocity_max = cfg.get("v1", 2.0)
	p.gravity = cfg.get("g", Vector3.ZERO)
	p.damping_min = cfg.get("damp", 0.0)
	p.damping_max = cfg.get("damp", 0.0)
	p.scale_amount_min = cfg.get("s0", 1.0)
	p.scale_amount_max = cfg.get("s1", 1.0)
	if cfg.has("grow"):
		var c := Curve.new()
		c.max_value = 4.0
		c.add_point(Vector2(0.0, cfg["grow"][0]))
		c.add_point(Vector2(1.0, cfg["grow"][1]))
		p.scale_amount_curve = c
	if cfg.has("ramp"):
		p.color_ramp = cfg["ramp"]
	if cfg.get("spin", 0.0) > 0.0:
		p.angle_min = 0.0
		p.angle_max = 360.0
		p.angular_velocity_min = -cfg["spin"]
		p.angular_velocity_max = cfg["spin"]
	if cfg.get("sphere", 0.0) > 0.0:
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		p.emission_sphere_radius = cfg["sphere"]
	p.particle_flag_align_y = cfg.get("align", false)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	p.position = pos
	scene.add_child(p)
	p.emitting = true
	get_tree().create_timer(life * 1.3 + 0.2).timeout.connect(p.queue_free)
	return p


# искры: светящиеся чёрточки, вытянутые вдоль полёта, падают
func _streaks(pos: Vector3, dir: Vector3, n: int, col: Color, v0: float, v1: float, life: float, spread := 55.0, size := 0.7) -> void:
	if get_tree().current_scene == null:
		return
	if _streak_quad == null:
		_streak_quad = QuadMesh.new()
		_streak_quad.size = Vector2(0.09, 1.0)
	var key := "streak_" + col.to_html()
	if not _sprite_mats.has(key):
		_sprite_mats[key] = beam_material(col, 4.0, 1.2, 0.5, true, 0.35)
	_emit(pos, _streak_quad, _sprite_mats[key], n, life, {"dir": dir, "spread": spread, "v0": v0, "v1": v1,
		"g": Vector3(0, -18, 0), "s0": size * 0.6, "s1": size, "align": true, "grow": [1.0, 0.3]})
