class_name FirstPersonArm
extends Node3D
## Brazo derecho de Mira en primera persona (C3, D-144). Va dentro de la cámara: el resto de Mira está oculto
## en primera persona, así que lo que lleva en la mano se ve con este brazo, abajo a la derecha.
##
## Usa mira_arm.glb (solo el antebrazo y la mano, con el mismo esqueleto que Mira; export_mira_arm.py) con
## el brazo doblado como en MiraHoldPose, los mismos agarres (MiraHandGrip) y los mismos enganches de la
## mano que Mira (HELD_*, FIST_*). En cada fotograma coloca el modelo para que el centro del puño quede en
## `fist_position`, con lo que lleva apuntando hacia delante. Solo se ve cuando lleva algo con modelo (las
## herramientas): los ítems sueltos aún no tienen modelo y en primera persona no se enseñan (César).
## No proyecta sombra.
## Con la herramienta encendida (set_working, lo llama el jugador mientras se mantiene el clic, haya o no algo
## delante), el brazo se adelanta hacia el centro (`work_position`): la mordedora abre y cierra las mandíbulas
## y empuja con cada mordisco, y la barrena gira la broca y vibra. Cada una tiene su motor en bucle, que
## arranca y frena con la herramienta (la mordedora suena a sierra eléctrica pequeña, César).
## En los modos construir y desmontar (plan_mode, lo pone el jugador) Mira guarda lo que llevaba y saca el
## **plano** (blueprint.glb, tools_blockout.py; D-223, César): una tablilla con la hoja azul que sube desde abajo.
## En el modo desmontar, dos trazos de pintura roja la tachan, uno detrás de otro. Al colocar o desmontar algo,
## el plano da un golpecito (plan_tap). Al salir del modo vuelve lo de la barra.
## Dónde tocar: fist_position, work_position, aim_*, view_scale, plan_* y las constantes BITE_*, DRILL_* y
## PLAN_* (en el Inspector, también con el juego en marcha desde el árbol remoto).

enum PlanMode { NONE, BUILD, DISMANTLE }

const ARM_SCENE: PackedScene = preload("res://assets/models/characters/mira_arm.glb")
const ARM_POSE: Dictionary = {   # la misma postura que MiraHoldPose: el antebrazo, hacia delante
	"RightUpperArm": Vector3(-20.0, 0.0, 0.0),
	"RightLowerArm": Vector3(-70.0, 0.0, 0.0),
}

## Centro del puño en la vista (marco de la cámara: +X a la derecha, +Y arriba, −Z delante), en metros.
@export var fist_position: Vector3 = Vector3(0.24, -0.25, -0.4)
## Dónde va el puño mientras trabaja: más adelante y hacia el centro, hacia lo que muerde o perfora.
@export var work_position: Vector3 = Vector3(0.17, -0.2, -0.49)
@export var work_aim_yaw_degrees: float = 11.0
## Cuánto apunta lo que lleva hacia el centro de la pantalla (grados) y hacia arriba.
@export var aim_yaw_degrees: float = 8.0
@export var aim_pitch_degrees: float = 4.0
## Escala del brazo y lo que lleva solo en la vista (1 = tamaño real). Muchos juegos agrandan un poco las
## herramientas en primera persona para que se lean mejor.
@export var view_scale: float = 1.0
## Dónde va el puño con el plano y cómo se gira: con el yaw negativo la cara mira hacia el centro, y con el
## pitch negativo se inclina hacia arriba, hacia los ojos.
@export var plan_position: Vector3 = Vector3(0.38, -0.05, -0.38)
@export var plan_yaw_degrees: float = -15.0
@export var plan_pitch_degrees: float = -12.0

const PLAN_SCENE: PackedScene = preload("res://assets/models/tools/blueprint.glb")
# Dónde va la tablilla en el marco del hueso de la mano, con el agarre «tablilla» (MiraHandGrip.Grip.PLATE):
# la palma apoyada detrás, los dedos abiertos por detrás hacia arriba y el pulgar que rodea el borde y se
# apoya delante. Calculado en Blender con el brazo de Mira (la mano gira 35° respecto al borde para que el
# antebrazo entre desde abajo a la derecha). El origen de la tablilla está en su borde derecho.
const PLAN_OFFSET: Vector3 = Vector3(0.047, 0.0176, -0.029)
const PLAN_BASIS: Basis = Basis(Vector3(-1.0, 0.0, 0.0), Vector3(0.0, 0.5736, -0.8192), Vector3(0.0, -0.8192, -0.5736))
const PLAN_RAISE_DROP: float = 0.16    # desde cuánto más abajo sube el plano al sacarlo (m)
const PLAN_RAISE_SPEED: float = 5.0    # cuánto tarda en subir (1 / segundos)
const PLAN_CROSS_SPEED: float = 3.5    # cuánto tarda en dibujarse la X entera (1 / segundos)
const PLAN_TAP_PUSH: float = 0.03      # cuánto se adelanta con el golpecito (m)
const PLAN_TAP_TILT: float = 6.0       # cuánto se inclina con el golpecito (grados)
const PLAN_TAP_SPEED: float = 4.0      # cuánto dura el golpecito (1 / segundos)

const WORK_BLEND_SPEED: float = 5.0   # cuánto tarda en adelantarse o volver (1 / segundos)
const BITE_RATE: float = 2.5          # mordiscos por segundo
const BITE_OPEN_DEGREES: float = 24.0 # cuánto se abre cada mandíbula
const BITE_PUSH: float = 0.035        # cuánto empuja el brazo con cada mordisco (m)
const DRILL_SPIN: float = 30.0        # giro de la broca trabajando (rad/s)
const DRILL_SHAKE: float = 0.004      # vibración del brazo con la barrena (m)
## Motores de las herramientas (C3, make_sounds.py), en bucle, y su volumen a tope (los dos iguales, César).
const BITER_SOUND: AudioStreamWAV = preload("res://assets/audio/biter_loop.wav")
const DRILL_SOUND: AudioStreamWAV = preload("res://assets/audio/drill_loop.wav")
const BITER_MAX_DB: float = -4.0
const DRILL_MAX_DB: float = -4.0
const MOTOR_QUIET_DB: float = -40.0
const MOTOR_SPIN_UP: float = 2.0      # cuánto tarda el motor en arrancar o pararse (1 / segundos)

var held_item: ItemData
## En el modo construcción o desmontar, Mira lleva el plano en lugar de lo de la barra; lo pone el jugador.
var plan_mode: PlanMode = PlanMode.NONE:
	set(value):
		if value == plan_mode:
			return
		var was_none: bool = plan_mode == PlanMode.NONE
		plan_mode = value
		if was_none:
			_raise = 0.0   # al sacarlo, sube desde abajo
		_update_plan()

var _model: Node3D
var _skeleton: Skeleton3D
var _hand_bone: int = -1
var _hand_grip: MiraHandGrip
var _held_anchor: Node3D
var _fist_anchor: Node3D
var _working: bool = false
var _work: float = 0.0       # 0 en reposo, 1 adelantado trabajando
var _time: float = 0.0
var _jaws: Array[Node3D] = []   # mandíbulas de la mordedora (izquierda, derecha)
var _bit: Node3D = null         # broca de la barrena
var _bit_speed: float = 0.0
var _motor: float = 0.0          # 0 apagado, 1 a tope
var _motor_max_db: float = 0.0
var _motor_player: AudioStreamPlayer
var _item_grip: MiraHandGrip.Grip = MiraHandGrip.Grip.OPEN   # agarre de lo de la barra
var _plan_anchor: Node3D        # el plano, en el puño (aparte: hold_item no lo borra)
var _cross: Array[Node3D] = []  # los dos trazos de la X
var _cross_rest: Array[Transform3D] = []
var _cross_center: Array[Vector3] = []
var _raise: float = 1.0         # 0 abajo, 1 en su sitio
var _cross_t: float = 0.0       # 0 sin X, 1 dibujada entera
var _tap: float = 0.0           # 1 al empezar el golpecito, baja a 0


func _ready() -> void:
	_model = ARM_SCENE.instantiate()
	_model.name = "ArmModel"
	add_child(_model)
	_skeleton = _model.find_child("Skeleton3D") as Skeleton3D
	for bone_name: String in ARM_POSE:
		var bone: int = _skeleton.find_bone(bone_name)
		var angles: Vector3 = ARM_POSE[bone_name]
		var turn := Quaternion.from_euler(Vector3(deg_to_rad(angles.x), deg_to_rad(angles.y), deg_to_rad(angles.z)))
		_skeleton.set_bone_pose_rotation(bone, _skeleton.get_bone_rest(bone).basis.get_rotation_quaternion() * turn)
	_hand_bone = _skeleton.find_bone(Mira.HAND_BONE)
	_hand_grip = MiraHandGrip.new()
	_hand_grip.name = "HandGrip"
	_skeleton.add_child(_hand_grip)
	var attachment := BoneAttachment3D.new()
	attachment.name = "RightHandAttachment"
	attachment.bone_name = Mira.HAND_BONE
	_skeleton.add_child(attachment)
	_held_anchor = Node3D.new()
	_held_anchor.transform = Transform3D(Mira.HELD_BASIS, Mira.HELD_OFFSET)
	attachment.add_child(_held_anchor)
	_fist_anchor = Node3D.new()
	_fist_anchor.transform = Transform3D(Mira.FIST_BASIS, Mira.FIST_OFFSET)
	attachment.add_child(_fist_anchor)
	# El plano, en su propio enganche (hold_item no lo borra).
	_plan_anchor = Node3D.new()
	_plan_anchor.name = "PlanAnchor"
	_plan_anchor.transform = Transform3D(PLAN_BASIS, PLAN_OFFSET)
	attachment.add_child(_plan_anchor)
	var plan: Node3D = PLAN_SCENE.instantiate()
	_plan_anchor.add_child(plan)
	for node: Node in plan.find_children("cross_mark*", "Node3D", true, false):
		var stroke := node as Node3D
		_cross.append(stroke)
		_cross_rest.append(stroke.transform)
		# Centro del trazo, para que crezca desde ahí sin moverse.
		var center := Vector3.ZERO
		var mesh_node := stroke as MeshInstance3D
		if mesh_node == null:
			mesh_node = stroke.find_child("*", true, false) as MeshInstance3D
		if mesh_node != null and mesh_node.mesh != null:
			center = mesh_node.mesh.get_aabb().get_center()
		_cross_center.append(center)
	_plan_anchor.visible = false
	_set_no_shadow(_model)
	visible = _should_show()
	# Los bucles se marcan por código. Sobre una variable: la constante no deja cambiar sus propiedades.
	for sound: AudioStreamWAV in [BITER_SOUND, DRILL_SOUND]:
		var stream: AudioStreamWAV = sound
		if stream.loop_mode == AudioStreamWAV.LOOP_DISABLED:
			stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
			stream.loop_begin = 0
			stream.loop_end = int(stream.get_length() * stream.mix_rate)
	_motor_player = AudioStreamPlayer.new()
	_motor_player.bus = &"SFX"
	_motor_player.volume_db = MOTOR_QUIET_DB
	add_child(_motor_player)
	_update_plan()


## Lo llama el jugador en cada paso: si la herramienta está encendida (clic mantenido).
func set_working(working: bool) -> void:
	_working = working


## Golpecito del plano al colocar o desmontar algo (lo llama el jugador).
func plan_tap() -> void:
	if plan_mode != PlanMode.NONE:
		_tap = 1.0


func _process(delta: float) -> void:
	if not visible:
		if _motor_player != null and _motor_player.playing:
			_motor_player.stop()
		return
	_time += delta
	if plan_mode != PlanMode.NONE:
		_process_plan(delta)
		return
	_work = move_toward(_work, 1.0 if _working else 0.0, WORK_BLEND_SPEED * delta)
	var eased: float = _work * _work * (3.0 - 2.0 * _work)
	var position_now: Vector3 = fist_position.lerp(work_position, eased)
	var yaw: float = lerpf(aim_yaw_degrees, work_aim_yaw_degrees, eased)
	# Mordedora: se abre y se cierra de golpe; al cerrar, el brazo empuja un poco hacia delante.
	var bite: float = 0.0
	if not _jaws.is_empty():
		var phase: float = fmod(_time * BITE_RATE, 1.0)
		bite = (1.0 - absf(1.0 - 2.0 * phase)) * eased   # 0 cerrada → 1 abierta → 0
		_jaws[0].rotation.y = deg_to_rad(BITE_OPEN_DEGREES) * bite
		if _jaws.size() > 1:
			_jaws[1].rotation.y = -deg_to_rad(BITE_OPEN_DEGREES) * bite
		position_now.z -= BITE_PUSH * (1.0 - bite) * eased
	# Barrena: la broca gira (arranca y frena suave) y el brazo vibra.
	if _bit != null:
		_bit_speed = move_toward(_bit_speed, DRILL_SPIN * eased, DRILL_SPIN * 2.0 * delta)
		_bit.rotation.x += _bit_speed * delta
		position_now += Vector3(sin(_time * 71.0), sin(_time * 83.0), 0.0) * DRILL_SHAKE * eased
	# Motor: arranca y frena suave; el volumen y el tono suben con él.
	if _motor_player.stream != null:
		_motor = move_toward(_motor, 1.0 if _working else 0.0, MOTOR_SPIN_UP * delta)
		if _motor > 0.01 and not _motor_player.playing:
			_motor_player.play()
		elif _motor <= 0.01 and _motor_player.playing:
			_motor_player.stop()
		_motor_player.volume_db = lerpf(MOTOR_QUIET_DB, _motor_max_db, sqrt(_motor))
		_motor_player.pitch_scale = lerpf(0.6, 1.0, _motor)
	_place_fist(position_now, yaw, aim_pitch_degrees, Transform3D(Mira.FIST_BASIS, Mira.FIST_OFFSET))


## El plano: sube desde abajo al sacarlo, la X se dibuja trazo a trazo y da un golpecito al colocar o desmontar.
func _process_plan(delta: float) -> void:
	if _motor_player.playing:
		_motor_player.stop()
	_raise = move_toward(_raise, 1.0, PLAN_RAISE_SPEED * delta)
	_tap = move_toward(_tap, 0.0, PLAN_TAP_SPEED * delta)
	_cross_t = move_toward(_cross_t, 1.0 if plan_mode == PlanMode.DISMANTLE else 0.0, PLAN_CROSS_SPEED * delta)
	for i: int in _cross.size():
		# El primer trazo en la primera mitad y el segundo en la otra; crecen con un pequeño rebote.
		var t: float = clampf(_cross_t * _cross.size() - i, 0.0, 1.0)
		var grow: float = 0.0 if t <= 0.0 else ease(t, -2.0) * (1.0 + 0.12 * sin(t * PI))
		var c: Vector3 = _cross_center[i]
		_cross[i].visible = grow > 0.001
		_cross[i].transform = _cross_rest[i] * Transform3D(Basis.from_scale(Vector3.ONE * maxf(grow, 0.001)), c - c * grow)
	var raise: float = ease(_raise, -2.0)
	var push: float = sin(_tap * PI)
	var position_now: Vector3 = plan_position + Vector3(0.0, -PLAN_RAISE_DROP * (1.0 - raise), -PLAN_TAP_PUSH * push)
	_place_fist(position_now, plan_yaw_degrees, plan_pitch_degrees - PLAN_TAP_TILT * push, _plan_anchor.transform)


## Coloca el brazo para que el enganche `anchor` de la mano (el centro del puño o el borde de la tablilla) quede
## en `at` (vista), girado `yaw` y `pitch` grados.
func _place_fist(at: Vector3, yaw: float, pitch: float, anchor: Transform3D) -> void:
	# Dónde está el enganche dentro del modelo (con la postura del brazo ya puesta)...
	var in_model: Transform3D = _model.global_transform.affine_inverse() * _skeleton.global_transform \
			* _skeleton.get_bone_global_pose(_hand_bone) * anchor
	# ...y dónde lo queremos en la vista: lo que lleva (+X) hacia delante (−Z) y su eje (+Y) arriba.
	var forward := Basis(Vector3(0.0, 0.0, -1.0), Vector3.UP, Vector3.RIGHT)
	var aim := Basis(Vector3.UP, deg_to_rad(yaw)) * Basis(Vector3.RIGHT, deg_to_rad(pitch))
	var target := Transform3D(aim * forward, at).scaled_local(Vector3.ONE * view_scale)
	_model.transform = target * in_model.affine_inverse()


## Pone en la mano lo que lleva Mira (null = nada: el brazo se esconde). Con el plano fuera, se guarda para
## cuando se salga del modo.
func hold_item(item: ItemData) -> void:
	held_item = item
	if not is_node_ready():
		visible = _should_show()
		return
	_set_item(item)
	_update_plan()


func _set_item(item: ItemData) -> void:
	for anchor: Node3D in [_held_anchor, _fist_anchor]:
		for child: Node in anchor.get_children():
			child.queue_free()
	_jaws.clear()
	_bit = null
	_bit_speed = 0.0
	_motor = 0.0
	if _motor_player != null:
		_motor_player.stop()
		_motor_player.stream = null
	if item == null:
		_item_grip = MiraHandGrip.Grip.OPEN
		return
	if item.held_model != null:
		var fist: bool = item.held_grip == ItemData.HeldGrip.FIST
		_item_grip = MiraHandGrip.Grip.TOOL if fist else MiraHandGrip.Grip.HOLD
		var model: Node3D = item.held_model.instantiate()
		(_fist_anchor if fist else _held_anchor).add_child(model)
		_set_no_shadow(model)
		# Piezas que se mueven al trabajar (tools_blockout.py las deja aparte bajo su pivote).
		for jaw_name: String in ["jaw_pivot_l", "jaw_pivot_r"]:
			var jaw := model.find_child(jaw_name, true, false) as Node3D
			if jaw != null:
				_jaws.append(jaw)
		_bit = model.find_child("bit_pivot", true, false) as Node3D
		if not _jaws.is_empty():
			_motor_player.stream = BITER_SOUND
			_motor_max_db = BITER_MAX_DB
		elif _bit != null:
			_motor_player.stream = DRILL_SOUND
			_motor_max_db = DRILL_MAX_DB
		return
	_item_grip = MiraHandGrip.Grip.HOLD
	var box := BoxMesh.new()
	box.size = Mira.PLACEHOLDER_SIZE
	var material := StandardMaterial3D.new()
	material.albedo_color = item.color
	material.roughness = 0.6
	var mesh := MeshInstance3D.new()
	mesh.mesh = box
	mesh.material_override = material
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_held_anchor.add_child(mesh)


func _should_show() -> bool:
	if plan_mode != PlanMode.NONE:
		return true
	return held_item != null and held_item.held_model != null


## Enseña el plano o lo de la barra, con su agarre.
func _update_plan() -> void:
	visible = _should_show()
	if not is_node_ready():
		return
	var planning: bool = plan_mode != PlanMode.NONE
	_plan_anchor.visible = planning
	_held_anchor.visible = not planning
	_fist_anchor.visible = not planning
	# La tablilla: pulgar por delante y dedos abiertos por detrás (César).
	_hand_grip.grip = MiraHandGrip.Grip.PLATE if planning else _item_grip
	if not planning:
		_cross_t = 0.0
		_tap = 0.0


func _set_no_shadow(node: Node) -> void:
	for geometry: Node in node.find_children("*", "GeometryInstance3D", true, false):
		(geometry as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
