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
float h(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7)) + seed) * 43758.5453); }
float n(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h(i), h(i + vec2(1, 0)), f.x), mix(h(i + vec2(0, 1)), h(i + vec2(1, 1)), f.x), f.y);
}
void fragment() {
	vec2 c = UV * 2.0 - 1.0;
	float r = length(c);
	float a = atan(c.y, c.x);
	// рваный край: радиус гуляет по углу
	float edge = 0.62 + 0.3 * n(vec2(a * 2.5, seed));
	float m = 1.0 - smoothstep(edge * 0.55, edge, r);
	m *= 0.75 + 0.25 * n(c * 6.0);
	ALBEDO = mix(vec3(0.05, 0.04, 0.035), vec3(0.16, 0.1, 0.06), smoothstep(0.0, edge, r));
	ALPHA = m * 0.8 * fade;
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
	var mat := _mat_hit if on_target else _mat_wall

	var fl := _mesh_node(_flash_mesh, mat, pos)
	fl.scale = Vector3.ONE * (0.9 if on_target else 0.5)
	var tw := fl.create_tween()
	tw.tween_property(fl, "scale", Vector3.ONE * 0.05, 0.09)
	tw.tween_callback(fl.queue_free)

	var p := CPUParticles3D.new()
	p.mesh = _spark_mesh
	p.material_override = mat
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = 10 if on_target else 5
	p.lifetime = 0.28
	p.direction = normal
	p.spread = 50.0
	p.initial_velocity_min = 5.0
	p.initial_velocity_max = 12.0
	p.gravity = Vector3(0, -22, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.2
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.position = pos          # место задаём до добавления в сцену, иначе частицы рисуются в центре карты
	scene.add_child(p)
	p.emitting = true
	get_tree().create_timer(0.6).timeout.connect(p.queue_free)

	if on_target:
		_flare(pos, "star_07", 2.2, Color(1.0, 0.8, 0.45, 1.0), 0.1)
	if sound:
		Sfx.play_at("hit" if on_target else "wall", pos, -6.0 if on_target else -14.0, 0.12)


# ------------------------------------------------------------------
#  Взрыв ракеты
# ------------------------------------------------------------------

func explosion(pos: Vector3, radius: float) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return

	# огненный шар: быстро раздувается и гаснет
	var ball_mat := _unshaded(Color(2.4, 1.6, 0.6, 0.95), true)
	var ball := _mesh_node(_flash_mesh, ball_mat, pos + Vector3.UP * 0.4)
	ball.scale = Vector3.ONE * radius * 0.5
	var tw := ball.create_tween()
	tw.tween_property(ball, "scale", Vector3.ONE * radius * 1.5, 0.12).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(ball_mat, "albedo_color", Color(1.5, 0.5, 0.1, 0.0), 0.3)
	tw.tween_callback(ball.queue_free)

	# ударная волна по земле: показывает реальный радиус урона
	var ring_mat := _unshaded(Color(1.0, 0.6, 0.25, 0.9), true)
	var ground := Vector3(pos.x, 0.12, pos.z)
	var ring := _mesh_node(_ring_mesh, ring_mat, ground)
	ring.scale = Vector3(radius * 0.2, 1, radius * 0.2)
	var tw2 := ring.create_tween()
	tw2.tween_property(ring, "scale", Vector3(radius, 1, radius), 0.22).set_ease(Tween.EASE_OUT)
	tw2.parallel().tween_property(ring_mat, "albedo_color:a", 0.0, 0.4)
	tw2.tween_callback(ring.queue_free)

	# осколки
	var p := CPUParticles3D.new()
	p.mesh = _spark_mesh
	p.material_override = _mat_hit
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = 22
	p.lifetime = 0.55
	p.direction = Vector3.UP
	p.spread = 75.0
	p.initial_velocity_min = 8.0
	p.initial_velocity_max = 20.0
	p.gravity = Vector3(0, -30, 0)
	p.scale_amount_min = 0.8
	p.scale_amount_max = 2.0
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.position = pos + Vector3.UP * 0.3
	scene.add_child(p)
	p.emitting = true
	get_tree().create_timer(1.0).timeout.connect(p.queue_free)

	# языки огня и дым: спрайты, если есть
	_flare(pos + Vector3.UP * 0.6, "fire_01", radius * 2.2, Color(1.0, 0.65, 0.3, 1.0), 0.28)
	_flare(pos + Vector3.UP * 0.8, "flare_01", radius * 3.5, Color(1.0, 0.8, 0.5, 1.0), 0.12)
	var smoke_mat := _unshaded(Color(1, 1, 1, 1), true)
	smoke_mat.vertex_color_use_as_albedo = true
	var s := CPUParticles3D.new()
	var stex := Art.fx_tex("smoke_04")
	if stex != null:
		var qm := QuadMesh.new()
		qm.size = Vector2(2, 2)
		s.mesh = qm
		smoke_mat.albedo_texture = stex
		smoke_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		s.angle_max = 360.0
	else:
		s.mesh = _smoke_mesh
	s.material_override = smoke_mat
	s.one_shot = true
	s.explosiveness = 0.9
	s.amount = 9
	s.lifetime = 1.1
	s.direction = Vector3.UP
	s.spread = 60.0
	s.initial_velocity_min = 1.5
	s.initial_velocity_max = 4.5
	s.gravity = Vector3(0, 1.5, 0)
	s.scale_amount_min = radius * 0.3
	s.scale_amount_max = radius * 0.55
	s.color_ramp = _smoke_ramp
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	s.position = pos + Vector3.UP * 0.5
	scene.add_child(s)
	s.emitting = true
	get_tree().create_timer(1.6).timeout.connect(s.queue_free)

	_flash_light(pos + Vector3.UP * 1.5, Color(1.0, 0.6, 0.25), radius * 3.0, 0.35)
	shake_at.emit(pos, Cfg.shake_explosion)
	if pos.y < 3.5:
		scorch(Vector3(pos.x, 0, pos.z), radius * 0.8)


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
	var mi := MeshInstance3D.new()
	mi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	mi.mesh = _scorch_mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = pos + Vector3.UP * (0.03 + randf() * 0.02)
	mi.rotation.y = randf() * TAU
	mi.scale = Vector3.ONE * radius
	scene.add_child(mi)
	_scorches.append(mi)
	var tw := mi.create_tween()
	tw.tween_interval(SCORCH_LIFE * 0.6)
	tw.tween_method(func(v: float): mat.set_shader_parameter("fade", v), 1.0, 0.0, SCORCH_LIFE * 0.4)
	tw.tween_callback(func():
		_scorches.erase(mi)
		mi.queue_free())


# короткая вспышка настоящего света (освещает землю и стены вокруг взрыва).
# Одновременно не больше нескольких, чтобы не тормозило
var _lights := 0


func _flash_light(pos: Vector3, col: Color, rng: float, time: float) -> void:
	if _lights >= 6 or get_tree().current_scene == null:
		return
	_lights += 1
	var l := OmniLight3D.new()
	l.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	l.light_color = col
	l.light_energy = 5.0
	l.omni_range = rng
	l.shadow_enabled = false
	get_tree().current_scene.add_child(l)
	l.global_position = pos
	var tw := l.create_tween()
	tw.tween_property(l, "light_energy", 0.0, time).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func() -> void:
		_lights -= 1
		l.queue_free())


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
	var look := Basis.looking_at(dir, Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT)
	for layer in 2:
		var mat := _unshaded(Color(c.r * 3.0, c.g * 3.0, c.b * 3.0, 0.9) if layer == 0 else Color(1, 1, 1, 0.95), true)
		var bm := BoxMesh.new()
		bm.size = Vector3(1, 1, 1)
		var mi := _mesh_node(bm, mat, from + d * 0.5)
		var w := 0.32 if layer == 0 else 0.1
		mi.global_transform = Transform3D(look * Basis.from_scale(Vector3(w, w, len)), from + d * 0.5)
		var tw := mi.create_tween()
		tw.tween_property(mat, "albedo_color:a", 0.0, 0.35).set_ease(Tween.EASE_IN)
		tw.tween_callback(mi.queue_free)
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

var _zap_core: StandardMaterial3D
var _zap_glow: StandardMaterial3D


func _zap_mats() -> void:
	if _zap_core == null:
		_zap_core = _unshaded(Color(0.75, 0.9, 1.0) * 1.8, true)
		_zap_core.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_zap_glow = _unshaded(Color(0.25, 0.5, 1.0, 0.25), true)
		_zap_glow.blend_mode = BaseMaterial3D.BLEND_MODE_ADD


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
		var w := 0.06 if pass_i == 0 else 0.24
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
		im.surface_add_vertex(a - side)
		im.surface_add_vertex(a + side)
		im.surface_add_vertex(b + side)
		im.surface_add_vertex(a - side)
		im.surface_add_vertex(b + side)
		im.surface_add_vertex(b - side)


# ------------------------------------------------------------------
#  Молния Теслы (ядро штаба): толстая ломаная от шара до цели, мигает 3 раза за четверть секунды
# ------------------------------------------------------------------

func tesla_bolt(from: Vector3, to: Vector3) -> void:
	for i in 3:
		get_tree().create_timer(i * 0.07, false).timeout.connect(_bolt.bind(from, to, 1.0 - i * 0.2))
	_flare(to, "star_07", 3.5, Color(0.6, 0.85, 1.0, 1.0), 0.15)
	_flare(from, "circle_05", 3.0, Color(0.5, 0.8, 1.0, 1.0), 0.2)
	_flash_light(to, Color(0.5, 0.75, 1.0), 12.0, 0.18)
	shake_at.emit(to, 0.15)


func _bolt(from: Vector3, to: Vector3, k: float) -> void:
	var scene := get_tree().current_scene
	var cam := get_viewport().get_camera_3d()
	if scene == null or cam == null:
		return
	_zap_mats()
	var span := from.distance_to(to)
	var n := clampi(int(span / 1.6), 6, 24)
	var pts: Array[Vector3] = [from]
	for i in range(1, n):
		var t := float(i) / n
		var amp := span * 0.06 * sin(t * PI)
		pts.append(from.lerp(to, t) + Vector3(randf_range(-1, 1), randf_range(-0.6, 0.6), randf_range(-1, 1)) * amp)
	pts.append(to)
	var im := ImmediateMesh.new()
	var view := cam.global_position
	for pass_i in 2:
		var w := (0.16 if pass_i == 0 else 0.7) * k
		im.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _zap_core if pass_i == 0 else _zap_glow)
		_ribbon(im, pts, w, view)
		# пара отростков
		for b in 2:
			var j := randi_range(2, n - 2)
			var p0 := pts[j]
			var br: Array[Vector3] = [p0, p0 + Vector3(randf_range(-1, 1), randf_range(-0.8, 0.3), randf_range(-1, 1)) * span * 0.12]
			_ribbon(im, br, w * 0.6, view)
		im.surface_end()
	var mi := _mesh_node(im, null, Vector3.ZERO)
	var tw := mi.create_tween()
	tw.tween_interval(0.07)
	tw.tween_callback(mi.queue_free)
