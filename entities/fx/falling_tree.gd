class_name FallingTree
extends Node3D
## Árbol que cae al talarlo (C3, César): una copia del modelo del árbol maduro que se vuelca hacia el lado
## contrario a la jugadora, cada vez más deprisa, rebota un poco al llegar al suelo y después se hunde y
## encoge con una nube de virutas hasta desaparecer. Mientras, en su casilla ya está el tocón. Suena
## `tree_fall.wav`, con el golpe a los FALL_TIME segundos.
## Uso: `FallingTree.spawn(padre, visual_del_árbol, posición_de_quien_tala)`.
## Dónde tocar: FALL_TIME, BOUNCE_*, SINK_* y FALL_ANGLE.

const FALL_SOUND: AudioStream = preload("res://assets/audio/tree_fall.wav")
const FALL_TIME: float = 1.05      # lo que tarda en caer (el golpe del sonido va aquí)
const FALL_ANGLE: float = 86.0     # grados: casi tumbado (la copa no se mete del todo en el suelo)
const BOUNCE_TIME: float = 0.3
const BOUNCE_DEGREES: float = 6.0
const LIE_TIME: float = 0.6        # tumbado antes de irse
const SINK_TIME: float = 0.7
const SINK_DEPTH: float = 0.4

var _axis: Vector3 = Vector3.RIGHT
var _time: float = 0.0
var _pivot: Node3D
var _landed: bool = false
var _sank: bool = false


## Copia `visual` (el Node3D con las mallas del árbol) en `parent` y lo hace caer lejos de `from`.
static func spawn(parent: Node, visual: Node3D, from: Vector3) -> void:
	var fall := FallingTree.new()
	parent.add_child(fall)
	fall.global_transform = Transform3D(Basis.IDENTITY, visual.global_position)
	fall._pivot = Node3D.new()
	fall.add_child(fall._pivot)
	var copy: Node3D = visual.duplicate() as Node3D
	fall._pivot.add_child(copy)
	copy.global_transform = visual.global_transform
	var away: Vector3 = visual.global_position - from
	away.y = 0.0
	if away.length() < 0.01:
		away = Vector3.FORWARD
	fall._axis = Vector3.UP.cross(away.normalized()).normalized()   # la copa va hacia `away`
	var sound := AudioStreamPlayer3D.new()
	sound.stream = FALL_SOUND
	sound.bus = &"SFX"
	sound.pitch_scale = randf_range(0.94, 1.06)
	fall.add_child(sound)
	sound.play()


func _process(delta: float) -> void:
	_time += delta
	var angle: float
	if _time < FALL_TIME:
		var t: float = _time / FALL_TIME
		angle = FALL_ANGLE * t * t   # cada vez más deprisa, como al caer de verdad
	elif _time < FALL_TIME + BOUNCE_TIME:
		if not _landed:
			_landed = true
			DustPuff.spawn(get_parent(), global_position + _axis.cross(Vector3.UP) * 2.0, BuildingView.CHIPS_COLOR)
		var b: float = (_time - FALL_TIME) / BOUNCE_TIME
		angle = FALL_ANGLE - BOUNCE_DEGREES * sin(b * PI) * (1.0 - b)
	else:
		angle = FALL_ANGLE
	_pivot.basis = Basis(_axis, deg_to_rad(angle))
	var sink_start: float = FALL_TIME + BOUNCE_TIME + LIE_TIME
	if _time > sink_start:
		if not _sank:
			_sank = true
			DustPuff.spawn(get_parent(), global_position + Vector3.UP * 0.3, BuildingView.CHIPS_COLOR)
		var s: float = minf(1.0, (_time - sink_start) / SINK_TIME)
		_pivot.position.y = -SINK_DEPTH * s
		_pivot.scale = Vector3.ONE * (1.0 - 0.9 * s)
		if s >= 1.0:
			queue_free()
