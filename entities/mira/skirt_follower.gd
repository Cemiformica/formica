class_name MiraSkirtFollower
extends SkeletonModifier3D
## Levanta las varillas de la bata de Mira siguiendo a los muslos (D-106).
##
## En cada fotograma mide cuánto ha subido cada muslo hacia delante (o hacia atrás) respecto a la
## cadera y gira las varillas de su lado en proporción: así la tela se aparta antes de que la pierna
## llegue, con cualquier animación. Va antes del SpringBoneSimulator3D, que añade la inercia encima.
## La tela sube a la vez que la pierna pero baja con retraso (RELEASE_SPEED): así, al levantarse, la
## pierna se retira antes de que la tela caiga y el muelle no la empuja contra el muslo.
## Dónde tocar: FRONT_FOLLOW y BACK_FOLLOW (cuánto sigue cada varilla, de delante a detrás) y
## RELEASE_SPEED (lo rápido que vuelve a caer).

const SIDES: Array[String] = ["Left", "Right"]
# Cuánto sigue cada varilla (1 = delante … 4 = detrás) al muslo cuando va hacia delante o hacia atrás.
# Salen de la pose que probamos en Blender: con el muslo a 75°, las varillas a 85°, 70°, 40° y 5°.
const FRONT_FOLLOW: Array[float] = [1.1, 0.9, 0.5, 0.05]
const BACK_FOLLOW: Array[float] = [0.0, 0.2, 0.5, 0.8]
const RELEASE_SPEED: float = 2.0     # velocidad máxima a la que baja la tela (radianes por segundo)
const LIFT_AXIS: Vector3 = Vector3(-1.0, 0.0, 0.0)   # girar sobre él lleva «abajo» hacia el frente (+Z)

var _skeleton: Skeleton3D
var _hips: int
var _thighs: Dictionary = {}          # lado → índice del muslo
var _ribs: Dictionary = {}            # lado → índices de los huesos de arriba de cada varilla
var _lifts: Dictionary = {}           # lado → giro que lleva ahora la tela (radianes, + hacia delante)


func _ready() -> void:
	_skeleton = get_skeleton()
	_hips = _skeleton.find_bone("Hips")
	for side: String in SIDES:
		_thighs[side] = _skeleton.find_bone(side + "UpperLeg")
		var ribs: Array[int] = []
		for rib: int in range(1, FRONT_FOLLOW.size() + 1):
			ribs.append(_skeleton.find_bone("Skirt%s%dUpper" % [side, rib]))
		_ribs[side] = ribs
		_lifts[side] = 0.0


func _process_modification() -> void:
	var hips_rest: Basis = _skeleton.get_bone_global_rest(_hips).basis
	# Pasa una dirección del esqueleto «tal como está» al marco de la cadera en reposo: así la medida no
	# cambia si toda la cadera se inclina, solo si el muslo se mueve respecto a ella.
	var to_hips_rest: Basis = hips_rest * _skeleton.get_bone_global_pose(_hips).basis.inverse()
	for side: String in SIDES:
		var thigh: int = _thighs[side]
		var now: Vector3 = to_hips_rest * _skeleton.get_bone_global_pose(thigh).basis.y
		var rest: Vector3 = _skeleton.get_bone_global_rest(thigh).basis.y
		var lift: float = _follow(side, _forward_angle(now) - _forward_angle(rest))
		var follow: Array[float] = FRONT_FOLLOW
		if lift < 0.0:
			follow = BACK_FOLLOW
		var ribs: Array[int] = _ribs[side]
		for i: int in ribs.size():
			var rib: int = ribs[i]
			var turned: Basis = Basis(LIFT_AXIS, lift * follow[i]) * _skeleton.get_bone_global_rest(rib).basis
			# La varilla cuelga de la cadera: su pose local es el giro visto desde la cadera en reposo.
			_skeleton.set_bone_pose_rotation(rib, (hips_rest.inverse() * turned).get_rotation_quaternion())


## Sube a la vez que el muslo y baja, como mucho, a RELEASE_SPEED.
func _follow(side: String, target: float) -> float:
	var current: float = _lifts[side]
	var rising: bool = signf(target) == signf(current) and absf(target) > absf(current)
	if rising or is_zero_approx(current):
		current = target
	else:
		current = move_toward(current, target, RELEASE_SPEED * get_process_delta_time())
	_lifts[side] = current
	return current


## Ángulo de una dirección hacia delante (+Z) desde «abajo», mirando de lado (radianes).
func _forward_angle(direction: Vector3) -> float:
	return atan2(direction.z, -direction.y)
