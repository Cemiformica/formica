class_name LoopSound
extends AudioStreamPlayer3D
## Sonido que se repite mientras algo se trabaja (C3): la veta perforada, el árbol mordido. Quien lo usa
## llama a `keep()` en cada paso mientras dura; si deja de llamarlo, se apaga suave en FADE_TIME.
## El bucle del .wav se marca por código (como la música, D-114). Va en el bus de efectos.

const FADE_TIME: float = 0.15
const QUIET_DB: float = -40.0

var _last_keep_ms: int = -100000
var _max_db: float = 0.0


## Crea el sonido dentro de `parent` (en su origen) con el .wav `sound_stream`, que se repite, a `peak_db` como mucho.
static func create(parent: Node3D, sound_stream: AudioStreamWAV, peak_db: float = 0.0) -> LoopSound:
	if sound_stream.loop_mode == AudioStreamWAV.LOOP_DISABLED:
		sound_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		sound_stream.loop_begin = 0
		sound_stream.loop_end = int(sound_stream.get_length() * sound_stream.mix_rate)
	var sound := LoopSound.new()
	sound.stream = sound_stream
	sound.bus = &"SFX"
	sound.volume_db = QUIET_DB
	sound._max_db = peak_db
	parent.add_child(sound)
	return sound


## Lo llama quien trabaja, en cada paso: el sonido suena (o sigue sonando).
func keep() -> void:
	_last_keep_ms = Time.get_ticks_msec()
	if not playing:
		play()


func _process(delta: float) -> void:
	if not playing:
		return
	var active: bool = Time.get_ticks_msec() - _last_keep_ms < 150
	var step: float = (_max_db - QUIET_DB) * delta / FADE_TIME
	volume_db = move_toward(volume_db, _max_db if active else QUIET_DB, step)
	if not active and volume_db <= QUIET_DB:
		stop()
