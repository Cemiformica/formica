class_name MusicPlayer
extends Node
## Música del juego (C1.8, César): temas tranquilos que suenan por turnos y al azar: los tres de
## art/tools/make_music.py y seis más hechos con Audio Studio (Stable Audio 3, sesión 24), dos por tema,
## nunca el mismo dos veces seguidas, con un silencio de entre `pause_min` y `pause_max` segundos entre uno
## y otro (como en Minecraft), para que no canse y se oiga la isla. Suena por el bus «Music».
## Uso: `add_child(MusicPlayer.new())` en la escena de juego.

const TRACKS: Array[AudioStream] = [
	preload("res://assets/audio/music_alba.ogg"),
	preload("res://assets/audio/music_galerias.ogg"),
	preload("res://assets/audio/music_engranajes.ogg"),
	# Audio Studio (sesión 24): César los prueba y quitará los que sobren.
	preload("res://assets/audio/music_alba_2.ogg"),
	preload("res://assets/audio/music_alba_3.ogg"),
	preload("res://assets/audio/music_galerias_2.ogg"),
	preload("res://assets/audio/music_galerias_3.ogg"),
	preload("res://assets/audio/music_engranajes_2.ogg"),
	preload("res://assets/audio/music_engranajes_3.ogg"),
]

## Espera antes del primer tema al empezar (segundos).
@export var first_delay: float = 3.0
## Silencio entre temas (segundos).
@export var pause_min: float = 120.0
@export var pause_max: float = 240.0

var _player: AudioStreamPlayer
var _timer: Timer
var _last: int = -1
## Generador propio, sembrado al azar al empezar: así el primer tema cambia de una partida a otra.
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_player = AudioStreamPlayer.new()
	_player.bus = &"Music"
	_player.finished.connect(_on_track_finished)
	add_child(_player)
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.timeout.connect(_play_next)
	add_child(_timer)
	_timer.start(maxf(first_delay, 0.05))


## Elige un tema distinto del último y lo pone.
func _play_next() -> void:
	var index: int = _rng.randi() % TRACKS.size()
	if TRACKS.size() > 1 and index == _last:
		index = (index + 1 + _rng.randi() % (TRACKS.size() - 1)) % TRACKS.size()
	_last = index
	_player.stream = TRACKS[index]
	_player.play()
	print("Música: %s" % TRACKS[index].resource_path.get_file())


func _on_track_finished() -> void:
	_timer.start(_rng.randf_range(pause_min, pause_max))
