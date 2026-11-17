# Animaciones de Mira (B4.5.2). Se ejecuta en Blender DESPUÉS de mira_rig.py, con mira.blend abierto.
#
# Crea dos acciones en el esqueleto "mira_rig", sin desplazamiento (a Mira la mueve el juego):
#   - "idle": 3 s en bucle. Respiración suave, un vistazo a un lado y el abdomen que acompaña.
#   - "walk": 0,93 s en bucle. Paso corto y saltarín (opción A de César): rebote de cadera y brazos en
#     contrapeso. La inclinación es pequeña y repartida entre cadera y columna (3° + 3°): así la bata no
#     se separa del abdomen y los pies quedan bajo el cuerpo (las piernas cuelgan de la cadera, así que
#     su inclinación se descuenta del muslo; con 7° solo en la cadera, Mira parecía caerse hacia delante).
# La bata y las antenas no se animan: las mueven en Godot MiraSkirtFollower y los muelles.
#
# Uso: exec(open(bpy.path.abspath("//../tools/mira_anims.py")).read())
# Dónde tocar: las tablas IDLE y WALK (hueso → canal → valores por fotograma clave).
#
# Ejes (huesos de Mira, rotación XYZ en grados): en los huesos que cuelgan (brazos, piernas), X negativo
# lleva hacia delante; en cadera, columna y pecho, X positivo inclina hacia delante; en los huesos que
# apuntan arriba, Y gira a los lados.

import bpy

RIG_NAME = "mira_rig"
FPS = 30

# Fotogramas clave del paso: contacto izquierdo, paso, contacto derecho, paso, y vuelta al principio.
WALK_FRAMES = (0, 7, 14, 21, 28)
WALK = {
    "Hips": {"loc_y": (-0.03, 0.02, -0.03, 0.02, -0.03), "rot_x": (3, 3, 3, 3, 3), "rot_y": (6, 0, -6, 0, 6)},
    "Spine": {"rot_x": (3, 3, 3, 3, 3), "rot_y": (-4, 0, 4, 0, -4)},
    "Neck": {"rot_x": (-7, -7, -7, -7, -7)},
    "Head": {"rot_x": (2, -1, 2, -1, 2)},
    "LeftUpperLeg": {"rot_x": (-33, -11, 11, -13, -33)},
    "LeftLowerLeg": {"rot_x": (8, 18, 12, 55, 8)},
    "RightUpperLeg": {"rot_x": (11, -13, -33, -11, 11)},
    "RightLowerLeg": {"rot_x": (12, 55, 8, 18, 12)},
    "LeftUpperArm": {"rot_x": (18, 0, -22, 0, 18)},
    "RightUpperArm": {"rot_x": (-22, 0, 18, 0, -22)},
    "LeftLowerArm": {"rot_x": (-20, -20, -20, -20, -20)},
    "RightLowerArm": {"rot_x": (-20, -20, -20, -20, -20)},
    "Abdomen": {"rot_x": (4, -3, 4, -3, 4)},
}

IDLE_FRAMES = (0, 30, 45, 50, 75, 90)
IDLE = {
    "Hips": {"loc_y": (0, -0.004, -0.006, -0.006, -0.002, 0)},
    "Chest": {"rot_x": (0, -1.4, -2, -2, -0.7, 0)},
    "Neck": {"rot_x": (0, -0.7, -1, -1, -0.4, 0)},
    "Head": {"rot_y": (0, 8, 8, 8, 0, 0), "rot_z": (0, 3, 4, 4, 0, 0)},
    "LeftUpperArm": {"rot_x": (0, 1.5, 2, 2, 0.7, 0)},
    "RightUpperArm": {"rot_x": (0, 1.5, 2, 2, 0.7, 0)},
    "Abdomen": {"rot_x": (0, 2, 3, 3, 1, 0)},
}

CHANNELS = {"rot_x": ("rotation_euler", 0, True), "rot_y": ("rotation_euler", 1, True),
            "rot_z": ("rotation_euler", 2, True), "loc_y": ("location", 1, False)}


def reset_pose(rig) -> None:
    for bone in rig.pose.bones:
        bone.rotation_mode = "XYZ"
        bone.rotation_euler = (0.0, 0.0, 0.0)
        bone.rotation_quaternion = (1.0, 0.0, 0.0, 0.0)
        bone.location = (0.0, 0.0, 0.0)
        bone.scale = (1.0, 1.0, 1.0)


def build_action(rig, name: str, frames: tuple, table: dict):
    old = bpy.data.actions.get(name)
    if old is not None:
        bpy.data.actions.remove(old)
    action = bpy.data.actions.new(name)
    action.use_fake_user = True   # que no se pierda al quitarla del esqueleto
    rig.animation_data.action = action
    reset_pose(rig)
    for bone_name, channels in table.items():
        bone = rig.pose.bones[bone_name]
        for channel, values in channels.items():
            prop, axis, degrees = CHANNELS[channel]
            for frame, value in zip(frames, values):
                vector = getattr(bone, prop)
                vector[axis] = value * 0.017453292519943295 if degrees else value
                bone.keyframe_insert(prop, index=axis, frame=frame, group=bone_name)
    action.frame_range = (frames[0], frames[-1])
    return action


def build() -> None:
    if bpy.context.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")
    rig = bpy.data.objects[RIG_NAME]
    rig.animation_data_create()
    bpy.context.scene.render.fps = FPS
    build_action(rig, "idle", IDLE_FRAMES, IDLE)
    build_action(rig, "walk", WALK_FRAMES, WALK)
    # Mira queda en reposo y sin acción puesta: export_mira.py exporta todas las acciones.
    rig.animation_data.action = None
    reset_pose(rig)
    print("Animaciones de Mira:", [a.name for a in bpy.data.actions if a.name in ("idle", "walk")])


build()
