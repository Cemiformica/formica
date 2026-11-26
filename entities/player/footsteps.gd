class_name Footsteps
extends Node
## Pisadas de Mira (sesión 28, César). Un paso cada cierta distancia recorrida, que cambia al andar, correr o ir
## agachada, para que vaya al compás de las piernas; un golpe más fuerte al aterrizar de un salto, y un crujido de cuerda
## por cada peldaño al trepar. Suena distinto según lo que pisa: lo pregunta con un rayo hacia abajo al nodo que lo
## sabe (`get_footstep_surface()` en `TerrainView`, `BuildingView` y `RepairSiteView`, o en uno de sus padres).
## Los sonidos están en assets/audio/steps/<superficie>_<n>.wav (Audio Studio: pisadas sueltas recortadas de tandas
## de pasos) y en cada paso sale uno al azar, sin repetir el anterior, con un poco de variación de tono y volumen.
## Lo llama el jugador en cada paso de la física (`walk`, `land`, `climb`).
## Dónde tocar: *_STRIDE (ritmo), *_DB (volumen) y SURFACE_DB (una superficie más alta o más baja que las demás).

## Superficies y cuántas pisadas hay de cada una.
const SURFACES: Dictionary[StringName, int] = {
	&"grass": 5, &"dirt": 4, &"stone": 4, &"wood": 5, &"metal": 4, &"rope": 5, &"water": 4,
}
const SURFACE_DB: Dictionary[StringName, float] = {
	&"grass": 0.0, &"dirt": 0.0, &"stone": 0.0, &"wood": 0.0, &"metal": -2.0, &"rope": 0.0, &"water": 0.0,
}
## Lo que suena si el rayo no da con nada que sepa de qué es (rocas sueltas, tocones…).
const DEFAULT_SURFACE: StringName = &"stone"
## Metros entre pisada y pisada: andando (4,5 m/s) sale una cada 0,4 s, corriendo (7 m/s) cada 0,31 s y agachada
## (2,5 m/s) cada 0,52 s.
const WALK_STRIDE: float = 1.8
const RUN_STRIDE: float = 2.2
const CROUCH_STRIDE: float = 1.3
## Metros de escala entre crujido y crujido (los peldaños van cada 0,33 m; uno de cada dos).
const RUNG_EVERY: float = 0.66
## Por debajo de esta velocidad (m/s) no se dan pasos; por encima de RUN_MIN_SPEED, con Mayús, son de correr.
const MIN_SPEED: float = 0.6
const RUN_MIN_SPEED: float = 5.0
const WALK_DB: float = -8.0
const RUN_DB: float = -5.0
const CROUCH_DB: float = -15.0
const CLIMB_DB: float = -8.0
## Al aterrizar: desde qué velocidad de caída (m/s) suena, y cuánto más fuerte y grave que un paso.
const LAND_MIN_FALL: float = 3.0
const LAND_DB: float = -2.0
const LAND_PITCH: float = 0.85
const PITCH_RANDOM: float = 1.08          # variación de tono de cada pisada (×/÷)
const VOLUME_RANDOM_DB: float = 2.0       # variación de volumen de cada pisada (± dB)
## Rayo hacia abajo desde los pies: cuánto sale por encima y hasta dónde baja.
const PROBE_UP: float = 0.2
const PROBE_DOWN: float = 0.5

var player: CharacterBody3D

## Un reproductor por superficie (cambiar el sonido de un reproductor corta lo que suena).
var _players: Dictionary[StringName, AudioStreamPlayer] = {}
var _walked: float = 0.0
var _climbed: float = 0.0


func _ready() -> void:
	for surface: StringName in SURFACES:
		var randomizer := AudioStreamRandomizer.new()
		randomizer.playback_mode = AudioStreamRandomizer.PLAYBACK_RANDOM_NO_REPEATS
		randomizer.random_pitch = PITCH_RANDOM
		randomizer.random_volume_offset_db = VOLUME_RANDOM_DB
		for i: int in SURFACES[surface]:
			var stream := load("res://assets/audio/steps/%s_%d.wav" % [surface, i + 1]) as AudioStream
			if stream != null:
				randomizer.add_stream(-1, stream)
		var audio := AudioStreamPlayer.new()
		audio.stream = randomizer
		audio.bus = &"SFX"
		audio.max_polyphony = 3
		add_child(audio)
		_players[surface] = audio


## Andar, correr o ir agachada: suma lo recorrido por el suelo y da un paso cada `*_STRIDE`. Al pararse, el siguiente
## paso queda a medio camino, para que al arrancar suene enseguida.
func walk(delta: float, on_floor: bool, speed: float, sprinting: bool, crouching: bool) -> void:
	var running: bool = sprinting and speed > RUN_MIN_SPEED
	var stride: float = CROUCH_STRIDE if crouching else (RUN_STRIDE if running else WALK_STRIDE)
	if not on_floor or speed < MIN_SPEED:
		_walked = stride * 0.6
		return
	_walked += speed * delta
	if _walked >= stride:
		_walked = fmod(_walked, stride)
		var volume: float = CROUCH_DB if crouching else (RUN_DB if running else WALK_DB)
		_play(_surface(), volume, 1.0)


## Al tocar el suelo tras una caída de `fall_speed` m/s: un golpe más fuerte y grave.
func land(fall_speed: float) -> void:
	_walked = 0.0
	if fall_speed >= LAND_MIN_FALL:
		_play(_surface(), LAND_DB, LAND_PITCH)


## Trepando: `distance` es lo que ha subido o bajado por la escala en este paso.
func climb(distance: float) -> void:
	_climbed += distance
	if _climbed >= RUNG_EVERY:
		_climbed = fmod(_climbed, RUNG_EVERY)
		_play(&"rope", CLIMB_DB, 1.0)


## Al agarrarse a una escala: el primer crujido llega a medio peldaño.
func start_climb() -> void:
	_climbed = RUNG_EVERY * 0.5


func _play(surface: StringName, volume_db: float, pitch: float) -> void:
	var audio: AudioStreamPlayer = _players.get(surface, _players.get(DEFAULT_SURFACE)) as AudioStreamPlayer
	if audio == null:
		return
	audio.volume_db = volume_db + SURFACE_DB.get(surface, 0.0)
	audio.pitch_scale = pitch
	audio.play()


## Qué pisa Mira: un rayo hacia abajo desde sus pies y el primer nodo (el que choca o uno de sus padres) que lo sabe.
func _surface() -> StringName:
	if player == null:
		return DEFAULT_SURFACE
	var from: Vector3 = player.global_position + Vector3.UP * PROBE_UP
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * (PROBE_UP + PROBE_DOWN),
			player.collision_mask, [player.get_rid()])
	var hit: Dictionary = player.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return DEFAULT_SURFACE
	var node: Node = hit["collider"] as Node
	while node != null:
		if node.has_method(&"get_footstep_surface"):
			return node.call(&"get_footstep_surface", hit["position"], hit["collider"])
		node = node.get_parent()
	return DEFAULT_SURFACE
