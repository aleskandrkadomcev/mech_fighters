class_name Bolas
extends Node3D
## Связка и глушащий дротик: летят прямо (без навеса), бьются о стены, баррикады и первого врага.
## Связка (kind "bolas") — верёвка с двумя грузами, крутится в полёте; попала — обматывает ноги:
## мех обездвижен (корпус крутится, пушки стреляют), крип оглушён.
## Дротик (kind "jam") — втыкается в броню и искрит: мех не стреляет, крип оглушён.
## Целеуказатель (kind "mark") — дротик с красным маячком: по меху все попадания сильнее.
## Болванка (kind "slug") — тяжёлый снаряд: урон и оглушение (тяжёлого — короче).

var team := 0
var shooter: Node
var kind := "bolas"
var p := {}
var _from := Vector3.ZERO
var _vel := Vector3.ZERO
var _left := 30.0
var _exclude: Array[RID] = []
var _spin: Node3D

static var _mats := {}


func setup(from: Vector3, dir: Vector3, who: Node, k: String, params: Dictionary) -> void:
	_from = from
	shooter = who
	kind = k
	p = params
	team = who.team
	_vel = dir.normalized() * float(p.get("speed", 34.0))
	_left = float(p.get("range", 30.0))


static func mat(key: String, c: Color, glow := false) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.8
	if glow:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mats[key] = m
	return m


func _ready() -> void:
	_exclude = Fx.team_rids(team)
	_spin = Node3D.new()
	add_child(_spin)
	if kind == "bolas":
		# два груза на верёвке
		var wm := SphereMesh.new()
		wm.radius = 0.24
		wm.height = 0.48
		wm.radial_segments = 8
		wm.rings = 4
		for sx in [-1.0, 1.0]:
			var w := MeshInstance3D.new()
			w.mesh = wm
			w.material_override = mat("weight", Color(0.22, 0.22, 0.24))
			w.position = Vector3(sx * 0.95, 0, 0)
			_spin.add_child(w)
		var rope := MeshInstance3D.new()
		var rm := BoxMesh.new()
		rm.size = Vector3(1.9, 0.05, 0.05)
		rope.mesh = rm
		rope.material_override = mat("rope", Color(0.45, 0.36, 0.22))
		_spin.add_child(rope)
	elif kind == "slug":
		var sm := SphereMesh.new()
		sm.radius = 0.32
		sm.height = 0.9
		var sl := MeshInstance3D.new()
		sl.mesh = sm
		sl.material_override = mat("slug", Color(1.0, 0.7, 0.35) * 2.2, true)
		sl.rotation.x = PI * 0.5
		_spin.add_child(sl)
	else:
		# дротик с огоньком на хвосте: жёлтым (глушилка) или красным (метка)
		var dm := CylinderMesh.new()
		dm.top_radius = 0.02
		dm.bottom_radius = 0.09
		dm.height = 0.8
		dm.radial_segments = 6
		var d := MeshInstance3D.new()
		d.mesh = dm
		d.material_override = mat("dart", Color(0.3, 0.3, 0.32))
		d.rotation.x = -PI * 0.5
		_spin.add_child(d)
		var gm := SphereMesh.new()
		gm.radius = 0.1
		gm.height = 0.2
		var g := MeshInstance3D.new()
		g.mesh = gm
		g.material_override = _glow()
		g.position = Vector3(0, 0, 0.4)
		_spin.add_child(g)
	global_position = _from
	if _vel.length() > 0.01:
		look_at(_from + _vel, Vector3.UP)
	reset_physics_interpolation()


func _physics_process(delta: float) -> void:
	var from := global_position
	var to := from + _vel * delta
	var q := PhysicsRayQueryParameters3D.create(from, to, 1 | 4 | 16)
	q.collide_with_areas = true
	q.exclude = _exclude
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		_hit(hit)
		return
	global_position = to
	if kind == "bolas":
		_spin.rotate_y(delta * 20.0)
	_left -= _vel.length() * delta
	if _left <= 0.0:
		queue_free()


func _hit(hit: Dictionary) -> void:
	var col = hit["collider"]
	var target = col.get("mech") if col != null and col.get("mech") != null else col
	var pos: Vector3 = hit["position"]
	var t := float(p.get("duration", 2.0))
	if target != null and is_instance_valid(target) and target.get("team") != null and int(target.get("team")) != team \
			and int(target.get("team")) >= 0 and not target.get("dead"):
		if kind == "bolas" and target.has_method("root"):
			target.root(t)
			_wrap(target, t)
		elif kind == "jam" and target.has_method("disarm"):
			target.disarm(t)
			_stick(target, pos, t)
		elif kind == "mark":
			if target.has_method("mark"):
				target.mark(t, float(p.get("boost", 0.25)))
				_stick(target, pos, t)
		elif kind == "slug":
			var k: float = shooter.damage_mult() if is_instance_valid(shooter) else 1.0
			target.take_damage(float(p.get("damage", 70.0)) * k, pos, _vel.normalized(), "", shooter if is_instance_valid(shooter) else null)
			if target.has_method("stun"):
				target.stun(float(p.get("stun_time", 1.2)))
			Fx.impact(pos, -_vel.normalized(), "armor", float(p.get("damage", 70.0)))
		elif target.has_method("stun"):
			target.stun(t)
		Sfx.play_at("hit", pos, -4.0, 0.1)
	else:
		Fx.spark(pos, hit["normal"], false, false)
	queue_free()


# верёвка обмоталась вокруг ног: кольцо на высоте колен, пока действует
func _wrap(target: Node3D, t: float) -> void:
	var holder: Node3D = target.get("visual") if target.get("visual") != null else target
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	var r: float = target.get_hit_radius() if target.has_method("get_hit_radius") else 1.0
	tm.inner_radius = r * 0.55
	tm.outer_radius = r * 0.55 + 0.12
	ring.mesh = tm
	ring.material_override = mat("rope", Color(0.45, 0.36, 0.22))
	ring.position = Vector3(0, 1.0, 0)
	ring.rotation.z = 0.12
	holder.add_child(ring)
	get_tree().create_timer(t, false).timeout.connect(ring.queue_free)


# дротик торчит из брони и искрит, пока действует
func _stick(target: Node3D, pos: Vector3, t: float) -> void:
	var holder: Node3D = target.get("visual") if target.get("visual") != null else target
	var d := MeshInstance3D.new()
	var gm := SphereMesh.new()
	gm.radius = 0.14
	gm.height = 0.28
	d.mesh = gm
	d.material_override = _glow()
	holder.add_child(d)
	d.global_position = pos
	Fx.spark(pos, -_vel.normalized(), true, false)
	get_tree().create_timer(t, false).timeout.connect(d.queue_free)


func _glow() -> StandardMaterial3D:
	if kind == "mark":
		return mat("mark_glow", Color(1.0, 0.2, 0.15) * 2.5, true)
	return mat("dart_glow", Color(1.0, 0.85, 0.3) * 2.5, true)
