# Exportación de Mira a Godot (B4.4). Exporta el esqueleto "mira_rig" y su malla con pesos "mira_mesh"
# a un .glb, con todas las acciones del esqueleto como animaciones (idle, walk… de mira_anims.py).
# A diferencia de export_glb.py, no une piezas: mira_rig.py ya lo dejó todo en una malla.
#
# Uso (en Blender, con mira.blend abierto y Mira en reposo):
#   exec(open(bpy.path.abspath("//../tools/export_mira.py")).read())
#
# En Godot, el .glb.import usa los materiales externos de assets/materials/: palette, palette_emissive,
# palette_gloss (color de vértice «shade» × paleta) y palette_cloth (ropa mate).

import bpy

RIG_NAME = "mira_rig"
MESH_NAME = "mira_mesh"
OUTPUT = "//../../assets/models/characters/mira.glb"
MAX_INFLUENCES = 4       # Godot usa 4 huesos por vértice; el faldón no pasa de 4


def check_ready() -> None:
    rig = bpy.data.objects[RIG_NAME]
    if rig.animation_data is not None and rig.animation_data.action is not None:
        raise RuntimeError("Quita la acción puesta en el esqueleto antes de exportar")
    for bone in rig.pose.bones:
        if bone.matrix_basis != bone.matrix_basis.Identity(4):
            raise RuntimeError("Mira no está en reposo: hueso " + bone.name)
    mesh = bpy.data.objects[MESH_NAME]
    for vertex in mesh.data.vertices:
        if len(vertex.groups) > MAX_INFLUENCES:
            raise RuntimeError("Vértice con más de %d huesos: %d" % (MAX_INFLUENCES, vertex.index))


def export() -> None:
    if bpy.context.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")
    check_ready()
    bpy.ops.object.select_all(action="DESELECT")
    for name in (RIG_NAME, MESH_NAME):
        bpy.data.objects[name].select_set(True)
    bpy.context.view_layer.objects.active = bpy.data.objects[RIG_NAME]
    options = dict(filepath=bpy.path.abspath(OUTPUT), export_format="GLB", use_selection=True, export_yup=True,
                   export_apply=False, export_cameras=False, export_lights=False, export_skins=True, export_def_bones=False,
                   export_animations=True, export_animation_mode="ACTIONS", export_force_sampling=True,
                   export_anim_slide_to_zero=True)
    try:
        # El color de vértice «shade» lo usa palette_gloss: hay que exportarlo siempre.
        bpy.ops.export_scene.gltf(export_vertex_color="ACTIVE", **options)
    except TypeError:
        bpy.ops.export_scene.gltf(**options)
    print("exportado:", OUTPUT)


export()
