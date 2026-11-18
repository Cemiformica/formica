class_name Mira
extends Node3D
## Mira en el mundo: su modelo con esqueleto (mira.glb), sus animaciones y el movimiento secundario (B4.5).
##
## Al arrancar monta en el Skeleton3D, por este orden:
## - MiraSkirtFollower: levanta las varillas de la bata siguiendo a los muslos (no atraviesan la tela);
## - MiraHoldPose: levanta el brazo derecho cuando lleva algo en la mano;
## - MiraHandGrip: cierra los dedos de la mano derecha («sujetar» con algo en la mano, «puño» para las
##   herramientas; set_grip);
## y un SpringBoneSimulator3D que añade la inercia encima:
## - la bata: solo las varillas del costado y de detrás (3 y 4 de cada lado) se balancean con inercia;
##   las delanteras (1 y 2) las mueve solo MiraSkirtFollower, porque con muelle el borde delantero
##   se colaba por detrás del muslo al levantarse (D-106);
## - las antenas: base y punta rebotan un poco al moverse;
## - cápsulas en muslos y espinillas que apartan la bata, para que las piernas no la atraviesen.
## Las animaciones las mezcla un AnimationTree: Mira mide sola su velocidad (cuánto se ha movido desde el
## fotograma anterior) y pasa de "idle" a "walk", acelerando o frenando el paso para que no patine.
## En la mano derecha lleva lo que tenga seleccionado (hold_item): un BoneAttachment3D sigue al hueso
## RightHand y de él cuelga el objeto, dentro de los dedos cerrados. Mientras los ítems no tengan modelo,
## es una barrita de su color, atravesada en la mano. Con algo en la mano, MiraHoldPose le levanta el brazo para enseñarlo.
## En primera persona, el jugador pone a Mira en «solo sombras» (set_shadow_only): no se dibuja, pero su
## sombra sí (también la de lo que lleva en la mano).
## La mochila enseña tantos módulos como tenga el inventario (set_backpack_modules; el jugador se lo dice):
## cada módulo es una malla aparte del .glb, backpack_module_0…5, en el orden en que se ganan (C3).
## Dónde tocar: WALK_REFERENCE_SPEED (si los pies patinan), HELD_OFFSET (dónde queda el objeto en la mano),
## las constantes SKIRT_* y ANTENNA_* (rigidez, freno, grosor) y LEG_RADIUS.

const SKIRT_SIDES: Array[String] = ["Left", "Right"]
const SKIRT_SPRING_RIBS: Array[int] = [3, 4]   # varillas con muelle (1 = delante … 4 = detrás)
const SKIRT_STIFFNESS: float = 3.0     # cuánto vuelve la tela a su sitio (más = más rígida)
const SKIRT_DRAG: float = 0.7          # freno del balanceo (más = se calma antes)
const SKIRT_RADIUS: float = 0.015      # grosor de la tela para chocar con las piernas (m)
const ANTENNA_STIFFNESS: float = 1.5
const ANTENNA_DRAG: float = 0.3
const ANTENNA_RADIUS: float = 0.01
const LEG_RADIUS: float = 0.045        # grosor de las cápsulas (m); con la tela, menos que el hueco en reposo (~7 cm)
const LEG_BONES: Dictionary = {        # hueso de la pierna → hueso hijo (marca su longitud)
	"LeftUpperLeg": "LeftLowerLeg", "LeftLowerLeg": "LeftFoot",
	"RightUpperLeg": "RightLowerLeg", "RightLowerLeg": "RightFoot",
}
const WALK_REFERENCE_SPEED: float = 0.75   # m/s a los que "walk" va a su ritmo sin que patinen los pies
const WALK_SCALE_MIN: float = 0.5          # el paso nunca va más lento ni más rápido que esto
const WALK_SCALE_MAX: float = 2.0
const SPEED_SMOOTHING: float = 10.0        # cuánto se suaviza la velocidad medida (más = reacciona antes)
const MAX_MEASURED_SPEED: float = 20.0     # por encima es un salto de sitio (reaparecer, portal): se ignora
const HAND_BONE: String = "RightHand"
# Sitio del objeto en el marco del hueso de la mano: +X va hacia la palma (mira al cuerpo), +Y baja de la
# muñeca a los dedos y −Z va hacia delante. Es el centro del hueco que dejan los dedos en «sujetar» (C3,
# D-146), calculado en Blender: queda a 13 mm de la palma, los dedos y el pulgar. HELD_BASIS atraviesa la
# mano: su Z va a lo largo de la fila de nudillos (del índice al anular).
const HELD_OFFSET: Vector3 = Vector3(0.042, 0.064, -0.0172)
const HELD_BASIS: Basis = Basis(Vector3(0.9999, 0.0041, 0.0156), Vector3(0.0, 0.9662, -0.2577),
		Vector3(-0.0161, 0.2576, 0.9661))
const PLACEHOLDER_SIZE: Vector3 = Vector3(0.024, 0.024, 0.12)   # barrita provisional (m), atravesada en el puño
# Herramientas (C3): el centro del hueco del puño y su eje, calculados en Blender como HELD_OFFSET. La
# empuñadura (+Y de la herramienta) va a lo largo de los nudillos con el aparato por el lado del índice, y la
# herramienta apunta (+X) de la muñeca hacia los nudillos, como una pistola.
const FIST_OFFSET: Vector3 = Vector3(0.0394, 0.0577, -0.015)
const FIST_BASIS: Basis = Basis(Vector3(0.0043, 0.9662, -0.2577), Vector3(0.0161, -0.2576, -0.9661),
		Vector3(-0.9998, 0.0, -0.0167))
const BACKPACK_MODULE_PREFIX: String = "backpack_module_"   # mallas de los módulos en el .glb (mira_rig.py)
const MAX_BACKPACK_MODULES: int = 6

var skeleton: Skeleton3D
var springs: SpringBoneSimulator3D
var animations: AnimationPlayer        # las del .glb: "idle" y "walk" (mira_anims.py), en bucle
var animation_tree: AnimationTree
var move_speed: float = 0.0            # velocidad horizontal medida y suavizada (m/s)
var held_anchor: Node3D                # de aquí cuelga lo que lleva en la mano derecha
var fist_anchor: Node3D                # y de aquí, las herramientas que coge en puño
var hold_pose: MiraHoldPose            # levanta el brazo derecho cuando lleva algo
var hand_grip: MiraHandGrip            # cierra los dedos de la mano derecha
var held_item: ItemData
## Módulos que se ven en la mochila (1 al empezar, D-117).
var backpack_modules: int = 1
## true: Mira no se dibuja, solo proyecta su sombra (primera persona).
var shadow_only: bool = false

var _last_position: Vector3


func _ready() -> void:
	skeleton = find_child("Skeleton3D") as Skeleton3D
	var follower := MiraSkirtFollower.new()
	follower.name = "SkirtFollower"
	skeleton.add_child(follower)
	hold_pose = MiraHoldPose.new()
	hold_pose.name = "HoldPose"
	skeleton.add_child(hold_pose)
	hand_grip = MiraHandGrip.new()
	hand_grip.name = "HandGrip"
	skeleton.add_child(hand_grip)
	springs = SpringBoneSimulator3D.new()
	springs.name = "Springs"
	skeleton.add_child(springs)
	_add_leg_colliders()
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
	animations = find_child("AnimationPlayer") as AnimationPlayer
	_setup_animation_tree()
	_setup_hand()
	set_shadow_only(shadow_only)
	set_backpack_modules(backpack_modules)
	_last_position = get_global_transform_interpolated().origin


func _process(delta: float) -> void:
	if delta <= 0.0:
		return
	# Posición suavizada: si Mira va dentro de un cuerpo con física (el jugador), la física avanza a 60 pasos
	# por segundo y la pantalla a más; con la posición sin suavizar, la velocidad medida daría saltos.
	var position_now: Vector3 = get_global_transform_interpolated().origin
	var step: Vector3 = position_now - _last_position
	_last_position = position_now
	var measured: float = Vector2(step.x, step.z).length() / delta
	if measured > MAX_MEASURED_SPEED:
		measured = move_speed
	move_speed = lerpf(move_speed, measured, 1.0 - exp(-SPEED_SMOOTHING * delta))
	var ratio: float = move_speed / WALK_REFERENCE_SPEED
	animation_tree.set("parameters/move/blend_amount", clampf(ratio, 0.0, 1.0))
	animation_tree.set("parameters/walk_speed/scale", clampf(ratio, WALK_SCALE_MIN, WALK_SCALE_MAX))


## Pone en la mano derecha el ítem seleccionado (null = mano vacía).
func hold_item(item: ItemData) -> void:
	for anchor: Node3D in [held_anchor, fist_anchor]:
		for child: Node in anchor.get_children():
			child.queue_free()
	held_item = item
	hold_pose.holding = item != null
	if item == null:
		set_grip(MiraHandGrip.Grip.OPEN)
		return
	if item.held_model != null:
		var fist: bool = item.held_grip == ItemData.HeldGrip.FIST
		set_grip(MiraHandGrip.Grip.TOOL if fist else MiraHandGrip.Grip.HOLD)   # el índice, en el gatillo
		var model: Node3D = item.held_model.instantiate()
		model.name = "HeldItem"
		(fist_anchor if fist else held_anchor).add_child(model)
		for geometry: Node in model.find_children("*", "GeometryInstance3D", true, false):
			(geometry as GeometryInstance3D).cast_shadow = _shadow_setting()
		return
	set_grip(MiraHandGrip.Grip.HOLD)
	var box := BoxMesh.new()
	box.size = PLACEHOLDER_SIZE
	var material := StandardMaterial3D.new()
	material.albedo_color = item.color
	material.roughness = 0.6
	var mesh := MeshInstance3D.new()
	mesh.name = "HeldItem"
	mesh.mesh = box
	mesh.material_override = material
	mesh.cast_shadow = _shadow_setting()
	held_anchor.add_child(mesh)


## Cambia el agarre de la mano derecha (abierta, sujetar o puño). hold_item ya pone «sujetar» o abierta;
## las herramientas pondrán «puño» (C3).
func set_grip(grip: MiraHandGrip.Grip) -> void:
	hand_grip.grip = grip


## Enseña en la mochila los `count` primeros módulos y esconde los demás.
func set_backpack_modules(count: int) -> void:
	backpack_modules = clampi(count, 0, MAX_BACKPACK_MODULES)
	if not is_node_ready():
		return
	for index: int in MAX_BACKPACK_MODULES:
		var module := find_child(BACKPACK_MODULE_PREFIX + str(index), true, false) as Node3D
		if module != null:
			module.visible = index < backpack_modules


## Con `enabled`, todo lo que se ve de Mira (también lo que coja después) solo proyecta sombra.
func set_shadow_only(enabled: bool) -> void:
	shadow_only = enabled
	if not is_node_ready():
		return
	for geometry: Node in find_children("*", "GeometryInstance3D", true, false):
		(geometry as GeometryInstance3D).cast_shadow = _shadow_setting()


func _shadow_setting() -> GeometryInstance3D.ShadowCastingSetting:
	if shadow_only:
		return GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	return GeometryInstance3D.SHADOW_CASTING_SETTING_ON


## Enciende o apaga las animaciones (apagadas, se puede posar el esqueleto a mano).
func set_animated(enabled: bool) -> void:
	animation_tree.active = enabled


## Árbol: "idle" y "walk" (con su velocidad ajustable) mezcladas según move_speed.
func _setup_animation_tree() -> void:
	var idle := AnimationNodeAnimation.new()
	idle.animation = &"idle"
	var walk := AnimationNodeAnimation.new()
	walk.animation = &"walk"
	var blend_tree := AnimationNodeBlendTree.new()
	blend_tree.add_node(&"idle", idle, Vector2(0.0, 0.0))
	blend_tree.add_node(&"walk", walk, Vector2(0.0, 160.0))
	blend_tree.add_node(&"walk_speed", AnimationNodeTimeScale.new(), Vector2(200.0, 160.0))
	blend_tree.add_node(&"move", AnimationNodeBlend2.new(), Vector2(400.0, 80.0))
	blend_tree.connect_node(&"walk_speed", 0, &"walk")
	blend_tree.connect_node(&"move", 0, &"idle")
	blend_tree.connect_node(&"move", 1, &"walk_speed")
	blend_tree.connect_node(&"output", 0, &"move")
	animation_tree = AnimationTree.new()
	animation_tree.name = "AnimationTree"
	animation_tree.tree_root = blend_tree
	# Junto al AnimationPlayer del .glb, para que las pistas encuentren el esqueleto igual que él.
	animations.get_parent().add_child(animation_tree)
	animation_tree.anim_player = animation_tree.get_path_to(animations)
	animation_tree.active = true


## Enganche de la mano derecha: sigue al hueso con la pose ya animada y con los muelles aplicados.
func _setup_hand() -> void:
	var attachment := BoneAttachment3D.new()
	attachment.name = "RightHandAttachment"
	attachment.bone_name = HAND_BONE
	skeleton.add_child(attachment)
	held_anchor = Node3D.new()
	held_anchor.name = "HeldAnchor"
	held_anchor.transform = Transform3D(HELD_BASIS, HELD_OFFSET)
	attachment.add_child(held_anchor)
	fist_anchor = Node3D.new()
	fist_anchor.name = "FistAnchor"
	fist_anchor.transform = Transform3D(FIST_BASIS, FIST_OFFSET)
	attachment.add_child(fist_anchor)


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
