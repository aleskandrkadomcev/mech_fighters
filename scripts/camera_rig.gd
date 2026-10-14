extends Camera3D
## Камера под углом, как в доте. Следит за мехом и чуть смещается к прицелу.
## Колесо мыши приближает и отдаляет.

var target: Node3D
var distance := 42.0
var debug_yaw := 0.0   # только для автопроверки
var _focus := Vector3.ZERO
var _shake := 0.0
var _started := false


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	distance = Cfg.cam_distance
	fov = Cfg.cam_fov
	far = 400.0
	current = true


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			Cfg.set_value("cam_distance", maxf(Cfg.cam_distance - 3.0, 20.0))
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			Cfg.set_value("cam_distance", minf(Cfg.cam_distance + 3.0, 90.0))


func shake(amount: float) -> void:
	_shake = minf(_shake + amount * Cfg.shake, 0.6)


func _process(delta: float) -> void:
	if target == null:
		return
	# игра считается тиками (30 в секунду), а камера рисуется каждый кадр: берём сглаженное положение меха
	var want: Vector3 = target.get_global_transform_interpolated().origin
	if "aim_point" in target:
		var off: Vector3 = (target.aim_point - want) * Cfg.cam_lookahead
		off.y = 0
		want += off.limit_length(Cfg.cam_lookahead_max)
	want.y = 0
	if not _started:
		_started = true
		_focus = want
	_focus = _focus.lerp(want, 1.0 - exp(-Cfg.cam_follow * delta))

	distance = Cfg.cam_distance
	fov = Cfg.cam_fov
	var pitch := deg_to_rad(Cfg.cam_pitch)
	var pos := _focus + Vector3(0, sin(pitch), cos(pitch)).rotated(Vector3.UP, debug_yaw) * distance
	_shake = maxf(_shake - delta * 2.2, 0.0)
	if _shake > 0.001:
		pos += Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * _shake
	global_position = pos
	rotation = Vector3(-pitch, debug_yaw, 0)
