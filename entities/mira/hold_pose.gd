class_name MiraHoldPose
extends SkeletonModifier3D
## Postura de Mira cuando lleva algo en la mano derecha: levanta el brazo y dobla el codo para enseñar el
## objeto delante del cuerpo.
##
## Va después de las animaciones: lleva el brazo de la pose animada hacia la postura de llevar algo, sin
## llegar del todo (STRENGTH), así que al andar el brazo aún se balancea un poco. Entra y sale suave
## (BLEND_SPEED) cuando `holding` cambia.
## Dónde tocar: POSE (cuánto se levanta el brazo y se dobla el codo), STRENGTH y BLEND_SPEED.

# Hueso → giro en grados respecto al reposo (X negativo lleva hacia delante en los huesos que cuelgan).
const POSE: Dictionary = {
	"RightUpperArm": Vector3(-20.0, 0.0, 0.0),
	"RightLowerArm": Vector3(-70.0, 0.0, 0.0),
}
const STRENGTH: float = 0.85     # 1 = el brazo queda fijo en POSE; menos deja pasar el balanceo de la animación
const BLEND_SPEED: float = 4.0   # cuánto tarda en subir o bajar el brazo (1 / segundos)

var holding: bool = false

var _skeleton: Skeleton3D
var _weight: float = 0.0
var _targets: Dictionary = {}    # índice del hueso → rotación de la postura


func _ready() -> void:
	_skeleton = get_skeleton()
	for bone_name: String in POSE:
		var bone: int = _skeleton.find_bone(bone_name)
		var angles: Vector3 = POSE[bone_name]
		var turn := Quaternion.from_euler(Vector3(deg_to_rad(angles.x), deg_to_rad(angles.y), deg_to_rad(angles.z)))
		_targets[bone] = _skeleton.get_bone_rest(bone).basis.get_rotation_quaternion() * turn


func _process_modification() -> void:
	var target_weight: float = 0.0
	if holding:
		target_weight = 1.0
	_weight = move_toward(_weight, target_weight, BLEND_SPEED * get_process_delta_time())
	if _weight <= 0.0:
		return
	var amount: float = _weight * STRENGTH
	for bone: int in _targets:
		var current: Quaternion = _skeleton.get_bone_pose_rotation(bone)
		_skeleton.set_bone_pose_rotation(bone, current.slerp(_targets[bone], amount))
