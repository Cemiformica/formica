# Esqueleto de Mira (B4.3). Se ejecuta en Blender DESPUÉS de mira_blockout.py.
#
# Mira es una figura articulada de juguete: cada pieza pertenece al 100 % a un hueso,
# sin pintado de pesos. El script:
#   1. crea el armature "mira_rig" con nombres de SkeletonProfileHumanoid de Godot
#      (más antenas, mascarilla, abdomen y mochila), usando los empties del blockout
#      como pivotes;
#   2. une todas las piezas en una sola malla "mira_mesh" con un grupo de vértices por
#      hueso (peso 1). La excepción es el faldón de la bata (vacío "skirt", D-106): se
#      reparte con pesos suaves entre 8 varillas de 2 huesos para que se doble sin rendijas;
#      en Godot las mueve SpringBoneSimulator3D. Lo que va con el pecho (bata, tórax,
#      solapas, botones) también se dobla suave en la cintura, de la cadera al pecho pasando
#      por la columna, para que la costura con el faldón no se abra al inclinarse;
#   3. borra los empties y deja la malla con su modificador Armature.
#
# Uso: exec(open(bpy.path.abspath("//../tools/mira_rig.py")).read())
# Para cambiar la forma de Mira: regenerar con mira_blockout.py y volver a ejecutar este.

import math

import bpy
from mathutils import Vector

RIG_NAME = "mira_rig"
MESH_NAME = "mira_mesh"
MODULE_PREFIX = "backpack_module_"   # piezas de cada módulo de la mochila (mallas aparte, ver build)

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

# Dedos (C3, D-145): tres dedos y el pulgar por mano, dos falanges cada uno. El dedo 2 es el índice
# (el más corto, junto al pulgar), el 1 el corazón y el 0 el anular. Nombres del perfil humanoide.
FINGERS = ((2, "Index"), (1, "Middle"), (0, "Ring"))
for _s, _side in (("l", "Left"), ("r", "Right")):
    for _k, _name in FINGERS:
        EMPTY_TO_BONE["finger_%s_%d" % (_s, _k)] = _side + _name + "Proximal"
        EMPTY_TO_BONE["finger_%s_%d_mid" % (_s, _k)] = _side + _name + "Intermediate"
    EMPTY_TO_BONE["thumb_" + _s] = _side + "ThumbProximal"
    EMPTY_TO_BONE["thumb_%s_mid" % _s] = _side + "ThumbDistal"


SKIRT_EMPTY = "skirt"
SKIRT_SIDES = (("Left", "l"), ("Right", "r"))
SKIRT_BLEND = 0.06       # zona de mezcla (m) entre cintura/cadera y entre los dos huesos de cada varilla


WAIST_LOW = 0.62         # por debajo, lo del pecho va con la cadera (casa con la cintura del faldón)
WAIST_HIGH = 0.80        # por encima, va con el pecho (las asas de la mochila y las mangas empiezan más arriba)


def waist_weights(z: float) -> dict:
    """Pesos de un vértice del pecho en la cintura: cadera → columna → pecho."""
    t = min(1.0, max(0.0, (z - WAIST_LOW) / (WAIST_HIGH - WAIST_LOW)))
    if t < 0.5:
        weights = {"Hips": 1.0 - 2.0 * t, "Spine": 2.0 * t}
    else:
        weights = {"Spine": 2.0 - 2.0 * t, "Chest": 2.0 * t - 1.0}
    return {name: w for name, w in weights.items() if w > 1e-4}


def skirt_bone(side: str, index: int, lower: bool) -> str:
    return "Skirt%s%d%s" % (side, index, "Lower" if lower else "Upper")


def skirt_angle(point: Vector) -> float:
    # Ángulo (°) desde el frente alrededor del faldón, el mismo para los vacíos y para los vértices.
    return math.degrees(math.atan2(abs(point.x), -point.y))


def skirt_ribs() -> list:
    """Varillas del faldón: [(lado, índice, ángulo, cintura, rodilla, bajo)], ordenadas por ángulo."""
    ribs = []
    for side, s in SKIRT_SIDES:
        index = 1
        while ("skirt_%s%d_0" % (s, index)) in bpy.data.objects:
            joints = [pivot("skirt_%s%d_%d" % (s, index, k)) for k in range(3)]
            ribs.append((side, index, skirt_angle(joints[0])) + tuple(joints))
            index += 1
    return sorted(ribs, key=lambda rib: rib[2])


def skirt_weights(co: Vector, ribs: list, z_cut: float, z_knee: float) -> dict:
    """Pesos de un vértice del faldón: mezcla entre las dos varillas vecinas (por ángulo) y entre la
    cadera, el hueso de arriba y el de abajo (por altura)."""
    side = "Left" if co.x >= 0.0 else "Right"
    own = [rib for rib in ribs if rib[0] == side]
    angle = skirt_angle(co)
    if angle <= own[0][2]:
        around = [(own[0][1], 1.0)]
    elif angle >= own[-1][2]:
        around = [(own[-1][1], 1.0)]
    else:
        i = next(i for i in range(len(own) - 1) if own[i][2] <= angle <= own[i + 1][2])
        t = (angle - own[i][2]) / (own[i + 1][2] - own[i][2])
        around = [(own[i][1], 1.0 - t), (own[i + 1][1], t)]
    hips = min(1.0, max(0.0, (co.z - (z_cut - SKIRT_BLEND)) / SKIRT_BLEND))
    low = min(1.0, max(0.0, (z_knee + SKIRT_BLEND / 2 - co.z) / SKIRT_BLEND))
    low = low * low * (3.0 - 2.0 * low)
    weights = {"Hips": hips} if hips > 0.0 else {}
    for index, w in around:
        for lower, share in ((False, 1.0 - low), (True, low)):
            value = (1.0 - hips) * w * share
            if value > 1e-4:
                name = skirt_bone(side, index, lower)
                weights[name] = weights.get(name, 0.0) + value
    return weights


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
    for side, index, _, waist, knee, hem in skirt_ribs():
        upper = skirt_bone(side, index, False)
        specs += [(upper, waist, knee, "Hips"), (skirt_bone(side, index, True), knee, hem, upper)]
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
        for k, name in FINGERS:
            base = "finger_%s_%d" % (s, k)
            specs += [
                (side + name + "Proximal", pivot(base), pivot(base + "_mid"), side + "Hand"),
                (side + name + "Intermediate", pivot(base + "_mid"), pivot(base + "_end"), side + name + "Proximal"),
            ]
        specs += [
            (side + "ThumbProximal", pivot("thumb_" + s), pivot("thumb_%s_mid" % s), side + "Hand"),
            (side + "ThumbDistal", pivot("thumb_%s_mid" % s), pivot("thumb_%s_end" % s), side + "ThumbProximal"),
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


def in_skirt(obj: bpy.types.Object) -> bool:
    node = obj.parent
    while node is not None:
        if node.name == SKIRT_EMPTY:
            return True
        node = node.parent
    return False


def owner_bone(obj: bpy.types.Object) -> str:
    """Hueso de la pieza: el del empty más cercano hacia arriba."""
    node = obj.parent
    while node is not None and node.name not in EMPTY_TO_BONE:
        node = node.parent
    if node is None:
        raise RuntimeError("Pieza sin empty de hueso: " + obj.name)
    return EMPTY_TO_BONE[node.name]


def prepare_piece(obj: bpy.types.Object, skirt: tuple) -> None:
    """Hornea la transformación, asigna sus pesos y asegura el atributo 'shade'."""
    soft = in_skirt(obj)
    bone = None if soft else owner_bone(obj)
    world = obj.matrix_world.copy()
    obj.parent = None
    obj.data.transform(world)
    obj.matrix_world.identity()
    if soft or bone == "Chest":
        for vertex in obj.data.vertices:
            weights = skirt_weights(vertex.co, *skirt) if soft else waist_weights(vertex.co.z)
            for name, weight in weights.items():
                group = obj.vertex_groups.get(name) or obj.vertex_groups.new(name=name)
                group.add([vertex.index], weight, "REPLACE")
    else:
        group = obj.vertex_groups.new(name=bone)
        group.add(range(len(obj.data.vertices)), 1.0, "REPLACE")
    # Al unir, las piezas sin 'shade' quedarían negras: se rellenan de blanco (sin sombreado)
    if "shade" not in obj.data.color_attributes:
        shade = obj.data.color_attributes.new("shade", "BYTE_COLOR", "CORNER")
        for value in shade.data:
            value.color = (1.0, 1.0, 1.0, 1.0)


def join_pieces(pieces: list, name: str = MESH_NAME) -> bpy.types.Object:
    bpy.ops.object.select_all(action="DESELECT")
    for piece in pieces:
        piece.select_set(True)
    bpy.context.view_layer.objects.active = pieces[0]
    if len(pieces) > 1:
        bpy.ops.object.join()
    mesh = bpy.context.view_layer.objects.active
    mesh.name = name
    mesh.data.name = name
    return mesh


def module_index(obj: bpy.types.Object) -> int:
    """Número del módulo de la mochila al que pertenece la pieza (−1 si no es de un módulo)."""
    if not obj.name.startswith(MODULE_PREFIX):
        return -1
    return int(obj.name.rsplit("_", 1)[1])


def build() -> None:
    if bpy.context.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")
    if RIG_NAME in bpy.data.objects or "mira" not in bpy.data.objects:
        raise RuntimeError("Ejecuta antes mira_blockout.py: este script trabaja sobre las piezas sueltas.")
    rig = build_armature()
    ribs = skirt_ribs()
    skirt = (ribs, pivot(SKIRT_EMPTY).z, ribs[0][4].z)
    pieces = [o for o in bpy.data.objects if o.type == "MESH"]
    for piece in pieces:
        prepare_piece(piece, skirt)
    # Los módulos de la mochila quedan como mallas aparte (una por módulo, con su ventanilla) para que Godot
    # enseñe solo los que tiene el inventario (C3); todo lo demás va en una sola malla.
    modules = {}
    for piece in pieces:
        if module_index(piece) >= 0:
            modules.setdefault(module_index(piece), []).append(piece)
    meshes = [join_pieces([p for p in pieces if module_index(p) < 0])]
    for index in sorted(modules):
        meshes.append(join_pieces(modules[index], MODULE_PREFIX + str(index)))
    for part in meshes:
        part.parent = rig
        modifier = part.modifiers.new("Armature", "ARMATURE")
        modifier.object = rig
    mesh = meshes[0]
    for obj in [o for o in bpy.data.objects if o.type == "EMPTY"]:
        bpy.data.objects.remove(obj)
    groups = {g.name for g in mesh.vertex_groups}
    unused = [b.name for b in rig.data.bones if b.name not in groups]
    print("Rig listo:", len(rig.data.bones), "huesos,", len(mesh.data.polygons), "caras,",
          len(mesh.material_slots), "materiales. Huesos sin piezas:", unused)


build()
