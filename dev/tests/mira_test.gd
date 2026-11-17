extends Node3D
## Prueba visual de Mira (B4.5, paso 1): muelles de la bata y las antenas, y choque con las piernas.
##
## En bucle: Mira va y viene de lado durante 4 s (la bata y las antenas deben balancearse) y luego se
## agacha 4 s (las cápsulas de las piernas deben apartar la bata). La cámara gira despacio a su
## alrededor. Al arrancar imprime OK si los muelles están montados.
## Dónde tocar: CYCLE (duración de cada fase), WALK_DISTANCE y CROUCH_POSE (la pose de agacharse).

const CYCLE: float = 4.0
const WALK_DISTANCE: float = 0.6
const CROUCH_SPEED: float = 1.5        # cuánto tarda en agacharse (1 / segundos)
const CROUCH_HIPS_DROP: float = 0.2    # cuánto baja la cadera (m)
const CAMERA_RADIUS: float = 2.6
const CAMERA_HEIGHT: float = 1.1
const CAMERA_PERIOD: float = 20.0
const EXPECTED_CHAINS: int = 6         # 4 varillas de la bata con muelle + 2 antenas
# Pose de agacharse, la misma que probamos en Blender: hueso → (giro en X, giro en Z) en grados.
# Se aplica primero el giro en Z (abrir la pierna) y luego el de X (levantarla).
const CROUCH_POSE: Dictionary = {
	"Hips": Vector2(20.0, 0.0), "Spine": Vector2(5.0, 0.0), "Neck": Vector2(-20.0, 0.0),
	"LeftUpperLeg": Vector2(-75.0, -18.0), "RightUpperLeg": Vector2(-75.0, 18.0),
	"LeftLowerLeg": Vector2(110.0, 0.0), "RightLowerLeg": Vector2(110.0, 0.0),
	"LeftFoot": Vector2(-30.0, 0.0), "RightFoot": Vector2(-30.0, 0.0),
}

var time: float = 0.0
var crouch: float = 0.0                # 0 de pie, 1 agachada

@onready var mira: Mira = $Mira
@onready var camera: Camera3D = $Camera3D


func _ready() -> void:
	var chains: int = mira.springs.setting_count
	if chains == EXPECTED_CHAINS:
		print("OK: muelles de Mira montados (%d cadenas)" % chains)
	else:
		print("FALLO: se esperaban %d cadenas y hay %d" % [EXPECTED_CHAINS, chains])


func _process(delta: float) -> void:
	time += delta
	var crouching: bool = int(time / CYCLE) % 2 == 1
	var target: float = 0.0
	if crouching:
		target = 1.0
	else:
		mira.position.x = sin(time * TAU / CYCLE) * WALK_DISTANCE
	crouch = move_toward(crouch, target, delta * CROUCH_SPEED)
	_apply_crouch(crouch)
	var angle: float = time * TAU / CAMERA_PERIOD
	camera.position = Vector3(sin(angle) * CAMERA_RADIUS, CAMERA_HEIGHT, cos(angle) * CAMERA_RADIUS)
	camera.look_at(Vector3(mira.position.x, 0.6, 0.0))


func _apply_crouch(amount: float) -> void:
	var skeleton: Skeleton3D = mira.skeleton
	for bone_name: String in CROUCH_POSE:
		var bone: int = skeleton.find_bone(bone_name)
		var angles: Vector2 = CROUCH_POSE[bone_name] * amount
		var turn: Quaternion = Quaternion(Vector3.RIGHT, deg_to_rad(angles.x)) \
				* Quaternion(Vector3.BACK, deg_to_rad(angles.y))
		skeleton.set_bone_pose_rotation(bone, skeleton.get_bone_rest(bone).basis.get_rotation_quaternion() * turn)
	var hips: int = skeleton.find_bone("Hips")
	var rest: Transform3D = skeleton.get_bone_rest(hips)
	skeleton.set_bone_pose_position(hips, rest.origin + rest.basis * Vector3(0.0, -CROUCH_HIPS_DROP * amount, 0.0))
