class_name DomeShield
extends Area3D
## Купольный щит: мех вбивает в землю генератор, из него раскрывается купол. Вражеские пули, лучи,
## гранаты и снаряды абилок снаружи бьются о купол и снимают ему прочность; изнутри всё вылетает
## (луч, начатый внутри шара, его не видит), свои стреляют сквозь (группа team_hitbox — Fx.team_rids).
## Мехи ходят сквозь. Обзор не закрывает. Живёт «Длительность» или пока не кончилась прочность.

var team := 0
var p := {}
var seen := true
var dead := false
var hp := 500.0
var _t := 0.0
var _r := 6.5
var _shell: MeshInstance3D
var _mat: ShaderMaterial
var _hit := 0.0
var _fade := 0.0

static var _shader: Shader


func _ready() -> void:
	add_to_group("gadgets")
	add_to_group("damageable")
	add_to_group("team_hitbox")
	collision_layer = 4
	collision_mask = 0
	monitoring = false
	hp = float(p.get("hp", 500.0))
	_r = float(p.get("radius", 6.5))
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = _r
	cs.shape = sh
	add_child(cs)
	# генератор-тумба
	var metal := Bolas.mat("dome_gen", Color(0.3, 0.32, 0.3))
	var cm := CylinderMesh.new()
	cm.top_radius = 0.3
	cm.bottom_radius = 0.45
	cm.height = 0.9
	cm.radial_segments = 10
	var gen := MeshInstance3D.new()
	gen.mesh = cm
	gen.material_override = metal
	gen.position.y = 0.45
	add_child(gen)
	var lm := SphereMesh.new()
	lm.radius = 0.16
	lm.height = 0.32
	var lamp := MeshInstance3D.new()
	lamp.mesh = lm
	lamp.material_override = Bolas.mat("dome_lamp", Color(0.4, 0.8, 1.0) * 2.5, true)
	lamp.position.y = 1.0
	add_child(lamp)
	# купол
	if _shader == null:
		_shader = Shader.new()
		_shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec4 col : source_color = vec4(0.35, 0.78, 1.0, 1.0);
uniform float hit = 0.0;
uniform float fade = 1.0;
void fragment() {
	float rim = pow(1.0 - abs(dot(NORMAL, VIEW)), 2.5);
	ALBEDO = mix(col.rgb, vec3(0.85, 0.95, 1.0), hit);
	ALPHA = clamp(0.05 + rim * 0.6 + hit * 0.3, 0.0, 1.0) * fade;
}
"""
	_mat = ShaderMaterial.new()
	_mat.shader = _shader
	var sm := SphereMesh.new()
	sm.radius = _r
	sm.height = _r * 2.0
	sm.radial_segments = 40
	sm.rings = 20
	_shell = MeshInstance3D.new()
	_shell.mesh = sm
	_shell.material_override = _mat
	_shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shell.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_shell.scale = Vector3.ONE * 0.05
	add_child(_shell)
	create_tween().tween_property(_shell, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	Sfx.play_at("emp", global_position, -6.0, 0.05)


func get_hit_radius() -> float:
	return _r


func take_damage(amount: float, _pos: Vector3, _dir: Vector3, _kind := "", _src: Node = null) -> void:
	if dead or amount <= 0.0:
		return
	hp -= amount
	_hit = 1.0
	if hp <= 0.0:
		_end()


func _end() -> void:
	if dead:
		return
	dead = true
	collision_layer = 0
	if seen:
		Fx.burst(global_position + Vector3.UP * _r * 0.5, Color(0.5, 0.85, 1.0), _r * 0.6)
	Sfx.play_at("emp", global_position, -4.0, 0.05)


func _physics_process(delta: float) -> void:
	_t += delta
	if not dead and _t >= float(p.get("duration", 6.0)):
		_end()


# вспышка от попадания и угасание — только картинка
func _process(delta: float) -> void:
	visible = seen
	if dead:
		_fade += delta * 3.0
		_mat.set_shader_parameter("fade", maxf(0.0, 1.0 - _fade))
		if _fade >= 1.0:
			queue_free()
		return
	if _hit > 0.0:
		_hit = maxf(_hit - delta * 4.0, 0.0)
		_mat.set_shader_parameter("hit", _hit)
