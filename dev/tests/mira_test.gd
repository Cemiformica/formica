extends Node3D
## Prueba visual de Mira (B4.5): animaciones, muelles de la bata y las antenas, y choque con las piernas.
##
## En bucle, tres fases: quieta con "idle" (4 s); andando con "walk", 2 s hacia un lado y 2 s de
## vuelta; y agachándose (la pose de prueba hecha por código, con la animación parada) y levantándose.
## La cámara gira despacio a su alrededor. Al arrancar imprime OK si los muelles y las animaciones están.
## Dónde tocar: PHASE_TIME, WALK_SPEED (debe casar con el paso para que no patine) y CROUCH_POSE.

enum Phase { IDLE, WALK, CROUCH }

const PHASE_TIME: float = 4.0
const CROUCH_HOLD: float = 2.5         # dentro de la fase de agacharse: cuánto se queda abajo
const WALK_SPEED: float = 0.5          # m/s
const CROUCH_SPEED: float = 1.5        # cuánto tarda en agacharse (1 / segundos)
const CROUCH_HIPS_DROP: float = 0.2    # cuánto baja la cadera (m)
const CAMERA_RADIUS: float = 2.6
const CAMERA_HEIGHT: float = 1.1
const CAMERA_PERIOD: float = 20.0
const EXPECTED_CHAINS: int = 6         # 4 varillas de la bata con muelle + 2 antenas
const EXPECTED_ANIMATIONS: Array[String] = ["idle", "walk"]
# Pose de agacharse, la misma que probamos en Blender: hueso → (giro en X, giro en Z) en grados.
# Se aplica primero el giro en Z (abrir la pierna) y luego el de X (levantarla).
const CROUCH_POSE: Dictionary = {
	"Hips": Vector2(20.0, 0.0), "Spine": Vector2(5.0, 0.0), "Neck": Vector2(-20.0, 0.0),
	"LeftUpperLeg": Vector2(-75.0, -18.0), "RightUpperLeg": Vector2(-75.0, 18.0),
	"LeftLowerLeg": Vector2(110.0, 0.0), "RightLowerLeg": Vector2(110.0, 0.0),
	"LeftFoot": Vector2(-30.0, 0.0), "RightFoot": Vector2(-30.0, 0.0),
}

var time: float = 0.0
var phase_time: float = 0.0
var phase: Phase = Phase.IDLE
var crouch: float = 0.0                # 0 de pie, 1 agachada

@onready var mira: Mira = $Mira
@onready var camera: Camera3D = $Camera3D


func _ready() -> void:
	var chains: int = mira.springs.setting_count
	var ok: bool = chains == EXPECTED_CHAINS
	for animation_name: String in EXPECTED_ANIMATIONS:
		ok = ok and mira.animations.has_animation(animation_name)
	if ok:
		print("OK: Mira con %d cadenas de muelles y animaciones %s" % [chains, EXPECTED_ANIMATIONS])
	else:
		print("FALLO: cadenas %d (esperaba %d), animaciones %s" % [chains, EXPECTED_CHAINS,
				mira.animations.get_animation_list()])


func _process(delta: float) -> void:
	time += delta
	phase_time += delta
	if phase_time >= PHASE_TIME and crouch == 0.0:
		_next_phase()
	match phase:
		Phase.WALK:
			var direction: float = 1.0
			if phase_time > PHASE_TIME * 0.5:
				direction = -1.0
			mira.position.x += direction * WALK_SPEED * delta
			mira.rotation.y = direction * PI * 0.5   # su frente (+Z) mira hacia donde anda
		Phase.CROUCH:
			var target: float = 0.0
			if phase_time < CROUCH_HOLD:
				target = 1.0
			crouch = move_toward(crouch, target, delta * CROUCH_SPEED)
			_apply_crouch(crouch)
	var angle: float = time * TAU / CAMERA_PERIOD
	camera.position = Vector3(sin(angle) * CAMERA_RADIUS, CAMERA_HEIGHT, cos(angle) * CAMERA_RADIUS)
	camera.look_at(Vector3(mira.position.x, 0.6, 0.0))


func _next_phase() -> void:
	phase_time = 0.0
	phase = ((phase + 1) % Phase.size()) as Phase
	mira.rotation.y = 0.0
	match phase:
		Phase.IDLE:
			mira.play_idle()
		Phase.WALK:
			mira.play_walk()
		Phase.CROUCH:
			# La pose de agacharse se pone a mano: se para la animación y se parte del reposo.
			mira.animations.stop()
			mira.skeleton.reset_bone_poses()


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
