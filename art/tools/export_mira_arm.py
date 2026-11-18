# Brazo de Mira en primera persona (C3, D-144). Exporta el esqueleto "mira_rig" con una copia de la malla
# que solo conserva el antebrazo y la mano derecha (con los dedos y el guante), sin animaciones. En Godot
# lo coloca FirstPersonArm delante de la cámara; el resto de Mira sigue oculto en primera persona.
# El .blend NO cambia: se trabaja sobre una copia que se borra al terminar.
#
# Uso (en Blender, con mira.blend abierto y Mira en reposo):
#   exec(open(bpy.path.abspath("//../tools/export_mira_arm.py")).read())
# Dónde tocar: ARM_BONES (qué huesos se quedan con su malla).

import bpy
import bmesh

RIG_NAME = "mira_rig"
MESH_NAME = "mira_mesh"
OUTPUT = "//../../assets/models/characters/mira_arm.glb"
ARM_BONES = {"RightLowerArm", "RightHand", "RightThumbProximal", "RightThumbDistal"} | {
    "Right%s%s" % (finger, part) for finger in ("Index", "Middle", "Ring") for part in ("Proximal", "Intermediate")}


def export() -> None:
    if bpy.context.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")
    rig = bpy.data.objects[RIG_NAME]
    for bone in rig.pose.bones:
        if bone.matrix_basis != bone.matrix_basis.Identity(4):
            raise RuntimeError("Mira no está en reposo: hueso " + bone.name)
    source = bpy.data.objects[MESH_NAME]
    arm = source.copy()
    arm.data = source.data.copy()
    arm.name = "mira_arm_mesh"
    arm.data.name = "mira_arm_mesh"
    bpy.context.scene.collection.objects.link(arm)
    keep = {g.index for g in arm.vertex_groups if g.name in ARM_BONES}
    bm = bmesh.new()
    bm.from_mesh(arm.data)
    deform = bm.verts.layers.deform.active
    doomed = [v for v in bm.verts if sum(w for g, w in v[deform].items() if g in keep) < 0.5]
    bmesh.ops.delete(bm, geom=doomed, context="VERTS")
    bm.to_mesh(arm.data)
    bm.free()
    tris = sum(len(p.vertices) - 2 for p in arm.data.polygons)
    try:
        bpy.ops.object.select_all(action="DESELECT")
        rig.select_set(True)
        arm.select_set(True)
        bpy.context.view_layer.objects.active = rig
        options = dict(filepath=bpy.path.abspath(OUTPUT), export_format="GLB", use_selection=True, export_yup=True,
                       export_apply=False, export_cameras=False, export_lights=False, export_skins=True,
                       export_def_bones=False, export_animations=False)
        try:
            bpy.ops.export_scene.gltf(export_vertex_color="ACTIVE", **options)
        except TypeError:
            bpy.ops.export_scene.gltf(**options)
    finally:
        data = arm.data
        bpy.data.objects.remove(arm, do_unlink=True)
        bpy.data.meshes.remove(data)
    print("exportado:", OUTPUT, "| triángulos:", tris)


export()
