extends Node
## Звуки. Файлы лежат в папке sounds. Громкость общая, в settings.gd.
## play_at: звук в точке мира. Чем дальше от твоего меха, тем тише, и слышно, слева он или справа.
## play: звук интерфейса (щелчки, подбор), всегда одинаковой громкости.

const NAMES := ["shot", "hit", "wall", "step", "dash", "launch", "boom", "emp", "deny", "cannon", "laser", "pickup", "beep", "click",
	"blaster", "shotgun", "grenade", "rail", "mortar", "wallbreak", "tp", "land", "casing", "ping", "tesla"]
const POOL := 16
const POOL_3D := 32

var _streams := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _loop: AudioStreamPlayer      # гул лазера, играет по кругу, пока луч светит
var _players3d: Array[AudioStreamPlayer3D] = []
var _next3d := 0
var _listener: AudioListener3D
var listener_pos := Vector3.ZERO


func _ready() -> void:
	for n in NAMES:
		var path := "res://sounds/%s.wav" % n
		if ResourceLoader.exists(path):
			_streams[n] = load(path)
	for i in POOL:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	for i in POOL_3D:
		var p3 := AudioStreamPlayer3D.new()
		p3.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED   # громкость считаем сами
		p3.max_distance = 0.0
		p3.panning_strength = 0.8
		add_child(p3)
		_players3d.append(p3)
	_listener = AudioListener3D.new()
	add_child(_listener)
	_loop = AudioStreamPlayer.new()
	add_child(_loop)
	if _streams.has("laser"):
		var w: AudioStream = _streams["laser"]
		if w is AudioStreamWAV:
			w.loop_mode = AudioStreamWAV.LOOP_FORWARD
			w.loop_begin = 0
			w.loop_end = int(w.get_length() * w.mix_rate)
		_loop.stream = w


# включить или выключить гул лазера
func set_laser(on: bool) -> void:
	if _loop.stream == null:
		return
	if on and not _loop.playing:
		_loop.volume_db = -10.0 + linear_to_db(clampf(Cfg.sound_volume, 0.001, 1.0))
		_loop.play()
	elif not on and _loop.playing:
		_loop.stop()


func play(sound: String, volume_db := 0.0, pitch_random := 0.0) -> void:
	if not _streams.has(sound) or Cfg.sound_volume <= 0.001:
		return
	var p := _players[_next]
	_next = (_next + 1) % POOL
	p.stream = _streams[sound]
	p.volume_db = volume_db + linear_to_db(clampf(Cfg.sound_volume, 0.001, 1.0))
	p.pitch_scale = 1.0 + randf_range(-pitch_random, pitch_random)
	p.play()


# слушатель стоит у твоего меха и смотрит как камера (лево/право как на экране)
func set_listener(pos: Vector3, basis: Basis) -> void:
	listener_pos = pos
	_listener.global_transform = Transform3D(basis, pos + Vector3.UP * 2.0)
	if not _listener.is_current():
		_listener.make_current()


# звук в точке мира: до "ближней" дистанции на полную, дальше плавно тише, за "дальней" не слышно
func play_at(sound: String, pos: Vector3, volume_db := 0.0, pitch_random := 0.0) -> void:
	if not _streams.has(sound) or Cfg.sound_volume <= 0.001:
		return
	var d := Vector2(pos.x - listener_pos.x, pos.z - listener_pos.z).length()
	var k := 1.0 - clampf((d - Cfg.sound_near) / maxf(Cfg.sound_range - Cfg.sound_near, 1.0), 0.0, 1.0)
	if k <= 0.01:
		return
	k = k * k
	var p := _players3d[_next3d]
	_next3d = (_next3d + 1) % POOL_3D
	p.stream = _streams[sound]
	p.global_position = Vector3(pos.x, 2.0, pos.z)
	p.volume_db = volume_db + linear_to_db(k) + linear_to_db(clampf(Cfg.sound_volume, 0.001, 1.0))
	p.pitch_scale = 1.0 + randf_range(-pitch_random, pitch_random)
	p.play()
