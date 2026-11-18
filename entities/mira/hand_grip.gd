class_name MiraHandGrip
extends SkeletonModifier3D
## Agarre de la mano derecha de Mira (C3, D-146): abierta, «sujetar», «puño» o «herramienta».
##
## Va después de las animaciones y de MiraHoldPose: dobla las dos falanges de cada dedo y del pulgar hacia la
## palma, cada una sobre su propio eje. El eje se calcula al arrancar con el reposo del esqueleto (dirección
## del hueso × hacia la palma), igual que en las pruebas de Blender, así que sirve aunque cambie la mano.
## Cambia suave (BLEND_SPEED) cuando cambia `grip`.
## - SUJETAR: los dedos rodean una barra de unos 2,6 cm (lo que se lleva en la mano).
## - PUÑO: cerrado sobre un mango de unos 2 cm.
## - HERRAMIENTA: el puño, pero con el índice adelantado sobre el gatillo (César): la primera falange casi
##   recta y la segunda doblada por delante del gatillo, a unos 2 mm (calculado en Blender con la mordedora).
## Dónde tocar: GRIP_ANGLES (grados por hueso) y BLEND_SPEED.

enum Grip { OPEN, HOLD, FIST, TOOL }

const SIDE: String = "Right"
# Hacia la palma en el espacio del esqueleto: la mano derecha mira hacia +X (su izquierda, hacia el cuerpo).
const PALM_DIRECTION: Vector3 = Vector3(1.0, 0.0, 0.0)
const FINGERS: Array[String] = ["Index", "Middle", "Ring"]
const GRIP_ANGLES: Dictionary = {
	Grip.HOLD: {"Proximal": 60.0, "Intermediate": 75.0, "ThumbProximal": 25.0, "ThumbDistal": 45.0},
	Grip.FIST: {"Proximal": 80.0, "Intermediate": 95.0, "ThumbProximal": 25.0, "ThumbDistal": 45.0},
	Grip.TOOL: {"Proximal": 80.0, "Intermediate": 95.0, "ThumbProximal": 25.0, "ThumbDistal": 45.0,
			"IndexProximal": 30.0, "IndexIntermediate": 80.0},
}
const BLEND_SPEED: float = 6.0   # cuánto tarda en cerrarse o abrirse (1 / segundos)

var grip: Grip = Grip.OPEN

var _skeleton: Skeleton3D
var _axes: Dictionary = {}       # índice del hueso → eje de doblez en el marco del propio hueso
var _rests: Dictionary = {}      # índice del hueso → rotación de reposo
var _angles: Dictionary = {}     # índice del hueso → ángulo actual (grados), para cambiar suave


func _ready() -> void:
	_skeleton = get_skeleton()
	for bone_name: String in _bone_names():
		var bone: int = _skeleton.find_bone(SIDE + bone_name)
		if bone < 0:
			push_warning("MiraHandGrip: falta el hueso " + SIDE + bone_name)
			continue
		var rest: Basis = _skeleton.get_bone_global_rest(bone).basis.orthonormalized()
		var axis: Vector3 = rest.y.cross(PALM_DIRECTION).normalized()
		_axes[bone] = (rest.inverse() * axis).normalized()
		_rests[bone] = _skeleton.get_bone_rest(bone).basis.get_rotation_quaternion()
		_angles[bone] = 0.0


func _process_modification() -> void:
	var step: float = BLEND_SPEED * 90.0 * get_process_delta_time()
	for bone: int in _axes:
		var target: float = _target_angle(_skeleton.get_bone_name(bone))
		_angles[bone] = move_toward(_angles[bone], target, step)
		if is_zero_approx(_angles[bone]):
			continue
		var turn := Quaternion(_axes[bone], deg_to_rad(_angles[bone]))
		_skeleton.set_bone_pose_rotation(bone, _rests[bone] * turn)


func _target_angle(bone_name: String) -> float:
	if grip == Grip.OPEN:
		return 0.0
	var angles: Dictionary = GRIP_ANGLES[grip]
	var part: String = bone_name.trim_prefix(SIDE)
	if part.begins_with("Thumb"):
		return angles[part]
	if angles.has(part):   # un dedo con su propio ángulo (el índice en el gatillo)
		return angles[part]
	for finger: String in FINGERS:
		if part.begins_with(finger):
			return angles[part.trim_prefix(finger)]
	return 0.0


func _bone_names() -> Array[String]:
	var names: Array[String] = ["ThumbProximal", "ThumbDistal"]
	for finger: String in FINGERS:
		names.append(finger + "Proximal")
		names.append(finger + "Intermediate")
	return names
