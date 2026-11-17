class_name Mira
extends Node3D
## Mira en el mundo: su modelo con esqueleto (mira.glb) y el movimiento secundario (B4.5).
##
## Al arrancar monta en el Skeleton3D, por este orden:
## - MiraSkirtFollower: levanta las varillas de la bata siguiendo a los muslos (no atraviesan la tela);
## y un SpringBoneSimulator3D que añade la inercia encima:
## - la bata: solo las varillas del costado y de detrás (3 y 4 de cada lado) se balancean con inercia;
##   las delanteras (1 y 2) las mueve solo MiraSkirtFollower, porque con muelle el borde delantero
##   se colaba por detrás del muslo al levantarse (D-106);
## - las antenas: base y punta rebotan un poco al moverse;
## - cápsulas en muslos y espinillas que apartan la bata, para que las piernas no la atraviesen.
## Dónde tocar: las constantes SKIRT_* y ANTENNA_* (rigidez, freno, grosor) y LEG_RADIUS.

const SKIRT_SIDES: Array[String] = ["Left", "Right"]
const SKIRT_SPRING_RIBS: Array[int] = [3, 4]   # varillas con muelle (1 = delante … 4 = detrás)
const SKIRT_STIFFNESS: float = 3.0     # cuánto vuelve la tela a su sitio (más = más rígida)
const SKIRT_DRAG: float = 0.7          # freno del balanceo (más = se calma antes)
const SKIRT_RADIUS: float = 0.015      # grosor de la tela para chocar con las piernas (m)
const ANTENNA_STIFFNESS: float = 1.5
const ANTENNA_DRAG: float = 0.3
const ANTENNA_RADIUS: float = 0.01
const LEG_RADIUS: float = 0.045        # grosor de las cápsulas (m); con la tela, menos que el hueco en reposo (~7 cm)
const ANIMATION_BLEND: float = 0.2     # segundos de mezcla al cambiar de animación
const LEG_BONES: Dictionary = {        # hueso de la pierna → hueso hijo (marca su longitud)
	"LeftUpperLeg": "LeftLowerLeg", "LeftLowerLeg": "LeftFoot",
	"RightUpperLeg": "RightLowerLeg", "RightLowerLeg": "RightFoot",
}

var skeleton: Skeleton3D
var springs: SpringBoneSimulator3D
var animations: AnimationPlayer        # las del .glb: "idle" y "walk" (mira_anims.py), en bucle


func _ready() -> void:
	skeleton = find_child("Skeleton3D") as Skeleton3D
	var follower := MiraSkirtFollower.new()
	follower.name = "SkirtFollower"
	skeleton.add_child(follower)
	springs = SpringBoneSimulator3D.new()
	springs.name = "Springs"
	skeleton.add_child(springs)
	_add_leg_colliders()
	animations = find_child("AnimationPlayer") as AnimationPlayer
	# Cadenas: [hueso raíz, hueso final, rigidez, freno, grosor, choca con las piernas]
	var chains: Array = []
	for side: String in SKIRT_SIDES:
		for rib: int in SKIRT_SPRING_RIBS:
			chains.append(["Skirt%s%dUpper" % [side, rib], "Skirt%s%dLower" % [side, rib],
					SKIRT_STIFFNESS, SKIRT_DRAG, SKIRT_RADIUS, true])
	for side: String in SKIRT_SIDES:
		chains.append(["Antenna" + side, "Antenna" + side + "Tip",
				ANTENNA_STIFFNESS, ANTENNA_DRAG, ANTENNA_RADIUS, false])
	springs.setting_count = chains.size()
	for index: int in chains.size():
		_setup_chain(index, chains[index])
	play_idle()


func play_idle() -> void:
	animations.play("idle", ANIMATION_BLEND)


func play_walk() -> void:
	animations.play("walk", ANIMATION_BLEND)


func _setup_chain(index: int, chain: Array) -> void:
	var end_bone: String = chain[1]
	springs.set_root_bone_name(index, chain[0])
	springs.set_end_bone_name(index, end_bone)
	# El último hueso también se mueve: se alarga en la dirección del anterior. Godot no recibe la
	# longitud de los huesos finales, así que se usa la del anterior (en Mira miden parecido).
	springs.set_extend_end_bone(index, true)
	springs.set_end_bone_direction(index, SpringBoneSimulator3D.BONE_DIRECTION_FROM_PARENT)
	springs.set_end_bone_length(index, _length_from_parent(end_bone))
	springs.set_stiffness(index, chain[2])
	springs.set_drag(index, chain[3])
	springs.set_gravity(index, 0.0)
	springs.set_radius(index, chain[4])
	springs.set_enable_all_child_collisions(index, chain[5])


func _add_leg_colliders() -> void:
	for bone_name: String in LEG_BONES:
		var length: float = _length_from_parent(LEG_BONES[bone_name])
		var capsule := SpringBoneCollisionCapsule3D.new()
		capsule.name = bone_name + "Collider"
		capsule.bone_name = bone_name
		capsule.radius = LEG_RADIUS
		capsule.height = length + 2.0 * LEG_RADIUS
		capsule.position_offset = Vector3(0.0, length * 0.5, 0.0)   # el hueso apunta por su eje Y
		springs.add_child(capsule)


## Distancia de un hueso a su padre (la longitud del padre, porque el hijo nace en su cola).
func _length_from_parent(bone_name: String) -> float:
	return skeleton.get_bone_rest(skeleton.find_bone(bone_name)).origin.length()
