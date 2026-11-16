# Esqueleto de Mira (B4.3). Se ejecuta en Blender DESPUÉS de mira_blockout.py.
#
# Mira es una figura articulada de juguete: cada pieza pertenece al 100 % a un hueso,
# sin pintado de pesos. El script:
#   1. crea el armature "mira_rig" con nombres de SkeletonProfileHumanoid de Godot
#      (más antenas, mascarilla, abdomen y mochila), usando los empties del blockout
#      como pivotes;
#   2. une todas las piezas en una sola malla "mira_mesh" con un grupo de vértices por
#      hueso (peso 1);
#   3. borra los empties y deja la malla con su modificador Armature.
#
# Uso: exec(open(bpy.path.abspath("//../tools/mira_rig.py")).read())
# Para cambiar la forma de Mira: regenerar con mira_blockout.py y volver a ejecutar este.

import bpy
from mathutils import Vector

RIG_NAME = "mira_rig"
MESH_NAME = "mira_mesh"

# Empty del blockout → hueso que hereda sus piezas
EMPTY_TO_BONE = {
    "hips": "Hips", "chest": "Chest", "neck": "Neck", "head": "Head",
    "mask": "Mask", "backpack": "Backpack", "abdomen": "Abdomen",
    "antenna_l": "AntennaLeft", "antenna_l_tip": "AntennaLeftTip",
    "antenna_r": "AntennaRight", "antenna_r_tip": "AntennaRightTip",
    "upper_arm_l": "LeftUpperArm", "forearm_l": "LeftLowerArm", "hand_l": "LeftHand",
    "upper_arm_r": "RightUpperArm", "forearm_r": "RightLowerArm", "hand_r": "RightHand",
    "thigh_l": "LeftUpperLeg", "shin_l": "LeftLowerLeg", "foot_l": "LeftFoot",
    "thigh_r": "RightUpperLeg", "shin_r": "RightLowerLeg", "foot_r": "RightFoot",
}


def pivot(name: str) -> Vector:
    return bpy.data.objects[name].matrix_world.translation.copy()


def bone_specs() -> list:
    """(nombre, cabeza, cola, padre). Mira mira hacia −Y; su izquierda es +X."""
    hips, chest, neck, head = pivot("hips"), pivot("chest"), pivot("neck"), pivot("head")
    spine = hips.lerp(chest, 0.5)
    specs = [
        ("Root", Vector((0, 0, 0)), Vector((0, -0.15, 0)), None),
        ("Hips", hips, spine, "Root"),
        ("Spine", spine, chest, "Hips"),
        ("Chest", chest, neck, "Spine"),
        ("Neck", neck, head, "Chest"),
        ("Head", head, head + Vector((0, 0, 0.4)), "Neck"),
        ("Mask", pivot("mask"), pivot("mask") + Vector((0, -0.12, 0)), "Neck"),
        ("Backpack", pivot("backpack"), pivot("backpack") + Vector((0, 0, 0.25)), "Chest"),
        ("Abdomen", pivot("abdomen"), pivot("abdomen") + Vector((0, 0.35, -0.05)), "Hips"),
    ]
    for side, s in (("Left", "l"), ("Right", "r")):
        sign = 1.0 if s == "l" else -1.0
        upper, fore, hand = pivot("upper_arm_" + s), pivot("forearm_" + s), pivot("hand_" + s)
        thigh, shin, foot = pivot("thigh_" + s), pivot("shin_" + s), pivot("foot_" + s)
        ant, tip = pivot("antenna_" + s), pivot("antenna_" + s + "_tip")
        side_lower = "Left" if s == "l" else "Right"
        specs += [
            (side + "Shoulder", Vector((sign * 0.04, upper.y, upper.z)), upper, "Chest"),
            (side + "UpperArm", upper, fore, side + "Shoulder"),
            (side + "LowerArm", fore, hand, side + "UpperArm"),
            (side + "Hand", hand, hand + Vector((0, 0, -0.12)), side + "LowerArm"),
            (side + "UpperLeg", thigh, shin, "Hips"),
            (side + "LowerLeg", shin, foot, side + "UpperLeg"),
            (side + "Foot", foot, foot + Vector((0, -0.14, -0.04)), side + "LowerLeg"),
            ("Antenna" + side_lower, ant, tip, "Head"),
            ("Antenna" + side_lower + "Tip", tip, tip + (tip - ant) * 0.6, "Antenna" + side_lower),
        ]
    return specs


def build_armature() -> bpy.types.Object:
    arm = bpy.data.armatures.new(RIG_NAME)
    arm.display_type = "STICK"
    rig = bpy.data.objects.new(RIG_NAME, arm)
    bpy.context.scene.collection.objects.link(rig)
    rig.show_in_front = True
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="EDIT")
    for name, head, tail, parent in bone_specs():
        bone = arm.edit_bones.new(name)
        bone.head, bone.tail, bone.roll = head, tail, 0.0
        if parent:
            bone.parent = arm.edit_bones[parent]
            # Unidos solo si la cabeza coincide con la cola del padre
            bone.use_connect = (bone.parent.tail - head).length < 1e-4
    bpy.ops.object.mode_set(mode="OBJECT")
    return rig


def owner_bone(obj: bpy.types.Object) -> str:
    """Hueso de la pieza: el del empty más cercano hacia arriba."""
    node = obj.parent
    while node is not None and node.name not in EMPTY_TO_BONE:
        node = node.parent
    if node is None:
        raise RuntimeError("Pieza sin empty de hueso: " + obj.name)
    return EMPTY_TO_BONE[node.name]


def prepare_piece(obj: bpy.types.Object) -> None:
    """Hornea la transformación, asigna su hueso y asegura el atributo 'shade'."""
    bone = owner_bone(obj)
    world = obj.matrix_world.copy()
    obj.parent = None
    obj.data.transform(world)
    obj.matrix_world.identity()
    group = obj.vertex_groups.new(name=bone)
    group.add(range(len(obj.data.vertices)), 1.0, "REPLACE")
    # Al unir, las piezas sin 'shade' quedarían negras: se rellenan de blanco (sin sombreado)
    if "shade" not in obj.data.color_attributes:
        shade = obj.data.color_attributes.new("shade", "BYTE_COLOR", "CORNER")
        for value in shade.data:
            value.color = (1.0, 1.0, 1.0, 1.0)


def join_pieces(pieces: list) -> bpy.types.Object:
    bpy.ops.object.select_all(action="DESELECT")
    for piece in pieces:
        piece.select_set(True)
    bpy.context.view_layer.objects.active = pieces[0]
    bpy.ops.object.join()
    mesh = bpy.context.view_layer.objects.active
    mesh.name = MESH_NAME
    mesh.data.name = MESH_NAME
    return mesh


def build() -> None:
    if bpy.context.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")
    if RIG_NAME in bpy.data.objects or "mira" not in bpy.data.objects:
        raise RuntimeError("Ejecuta antes mira_blockout.py: este script trabaja sobre las piezas sueltas.")
    rig = build_armature()
    pieces = [o for o in bpy.data.objects if o.type == "MESH"]
    for piece in pieces:
        prepare_piece(piece)
    mesh = join_pieces(pieces)
    mesh.parent = rig
    modifier = mesh.modifiers.new("Armature", "ARMATURE")
    modifier.object = rig
    for obj in [o for o in bpy.data.objects if o.type == "EMPTY"]:
        bpy.data.objects.remove(obj)
    groups = {g.name for g in mesh.vertex_groups}
    unused = [b.name for b in rig.data.bones if b.name not in groups]
    print("Rig listo:", len(rig.data.bones), "huesos,", len(mesh.data.polygons), "caras,",
          len(mesh.material_slots), "materiales. Huesos sin piezas:", unused)


build()
