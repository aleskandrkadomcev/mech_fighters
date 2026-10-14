extends Area3D
## Хитбокс для попаданий (мех, турель или штаб: всё, у чего есть команда)
## Хитбокс меха для попаданий: высокий цилиндр от пола (игра плоская, важен только радиус).
## Отдельно от узкой капсулы, которой мех упирается в стены.
## Размер задаёт корпус (детали, parts.gd). Клавиша F3 показывает его в игре.

var mech: Node3D
var _shape: CylinderShape3D
var _cs: CollisionShape3D
var _vis: MeshInstance3D
var _mesh: CylinderMesh
var _r := -1.0
var _h := -1.0

var team: int:
	get:
		return mech.team


func _ready() -> void:
	collision_layer = 4      # слой "по этому можно попасть"
	collision_mask = 0
	add_to_group("team_hitbox")
	monitoring = false
	_shape = CylinderShape3D.new()
	_cs = CollisionShape3D.new()
	_cs.shape = _shape
	add_child(_cs)

	# видимый контур для проверки (F3)
	_mesh = CylinderMesh.new()
	_mesh.radial_segments = 32
	_mesh.rings = 1
	_vis = MeshInstance3D.new()
	_vis.mesh = _mesh
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.2, 1.0, 0.4, 0.2)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_vis.material_override = m
	_vis.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_vis.visible = false
	add_child(_vis)
	_apply_size()


func _process(_delta: float) -> void:
	if _r != mech.get_hit_radius() or _h != mech.get_hit_height():
		_apply_size()
	_vis.visible = Cfg.show_hitboxes


func _apply_size() -> void:
	_r = mech.get_hit_radius()
	_h = mech.get_hit_height()
	_shape.radius = _r
	_shape.height = _h
	_mesh.top_radius = _r
	_mesh.bottom_radius = _r
	_mesh.height = _h
	position = Vector3(0, _h * 0.5, 0)


func set_active(on: bool) -> void:
	_cs.set_deferred("disabled", not on)


# попадание в хитбокс это попадание в меха
func take_damage(amount: float, pos: Vector3, dir: Vector3, kind := "", src: Node = null) -> void:
	mech.take_damage(amount, pos, dir, kind, src)


func stun(seconds: float) -> void:
	mech.stun(seconds)


func block_regen(seconds: float) -> void:
	mech.block_regen(seconds)
