# Fotos de las construcciones para el catálogo (C2.3), como los iconos de los ítems (render_item_icons.py).
# Uso: con cualquier .blend abierto y guardado (no lo toca: trabaja en una escena temporal y al acabar la
# borra). Importa cada assets/models/buildings/<id>.glb, le pone la paleta con su mapa de superficie (brillo
# como en Godot) y escribe assets/textures/icons/buildings/<id>.png (128 px, fondo transparente, 3/4).
# El cable no tiene modelo: se dibuja aquí uno pequeño (dos bornes y un cable colgando).
import math
import os
import bpy
import bmesh
from mathutils import Vector

SIZE = 128
MARGIN = 1.08
VIEW_DIR = Vector((0.55, -1.0, 0.75)).normalized()
PROJECT = os.path.normpath(os.path.join(os.path.dirname(bpy.data.filepath), "..", ".."))
MODELS = os.path.join(PROJECT, "assets", "models", "buildings")
OUT_DIR = os.path.join(PROJECT, "assets", "textures", "icons", "buildings")
PALETTE = os.path.join(PROJECT, "assets", "textures", "palette.png")
SURFACE = os.path.join(PROJECT, "assets", "textures", "palette_surface.png")
## Piezas que Godot enseña solo en algunos casos y que no salen en el icono: los tramos de unión de la cinta
## (se ve la vuelta de banda) y los túneles girados de la caja logística (se ve el recto).
HIDDEN = ("belt_join_", "tunnel_left", "tunnel_right")
BUILDINGS = ["workbench", "water_wheel", "solar_panel", "power_pole", "conveyor", "tree_cutter",
        "charcoal_kiln", "furnace", "extractor", "storage_chest", "logistic_box"]


def palette_material():
    mat = bpy.data.materials.new("icon_palette")
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(PALETTE, check_existing=True)
    tex.interpolation = "Closest"
    stex = nt.nodes.new("ShaderNodeTexImage")
    stex.image = bpy.data.images.load(SURFACE, check_existing=True)
    stex.image.colorspace_settings.name = "Non-Color"
    stex.interpolation = "Closest"
    sep = nt.nodes.new("ShaderNodeSeparateColor")
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    nt.links.new(stex.outputs["Color"], sep.inputs["Color"])
    nt.links.new(sep.outputs["Red"], bsdf.inputs["Metallic"])
    nt.links.new(sep.outputs["Green"], bsdf.inputs["Roughness"])
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    return mat


def cable_icon_model(scene, mat):
    # Dos bornes de arcilla con hilo de cobre y un cable negro que cuelga entre ellos.
    def uv_to(bm, col, row):
        uv = bm.loops.layers.uv.new("UVMap")
        for f in bm.faces:
            for loop in f.loops:
                loop[uv].uv = ((col * 8 + 4) / 64, 1.0 - (row * 8 + 4) / 64)
    def add(name, bm, col, row):
        uv_to(bm, col, row)
        me = bpy.data.meshes.new(name)
        bm.to_mesh(me)
        bm.free()
        me.materials.append(mat)
        ob = bpy.data.objects.new(name, me)
        scene.collection.objects.link(ob)
    for side in (-1, 1):
        bm = bmesh.new()
        bmesh.ops.create_cone(bm, cap_ends=True, segments=6, radius1=0.06, radius2=0.05, depth=0.12)
        bmesh.ops.translate(bm, vec=Vector((side * 0.35, 0, 0.06)), verts=bm.verts)
        add("cable_post_%d" % side, bm, 2, 4)
        bm = bmesh.new()
        bmesh.ops.create_cone(bm, cap_ends=True, segments=6, radius1=0.025, radius2=0.025, depth=0.05)
        bmesh.ops.translate(bm, vec=Vector((side * 0.35, 0, 0.145)), verts=bm.verts)
        add("cable_tip_%d" % side, bm, 1, 3)
    bm = bmesh.new()
    prev = None
    steps = 16
    for i in range(steps + 1):
        t = i / steps
        x = -0.35 + 0.7 * t
        z = 0.16 - 0.12 * math.sin(math.pi * t)
        ring = []
        for k in range(6):
            a = math.tau * k / 6
            ring.append(bm.verts.new((x, 0.018 * math.cos(a), z + 0.018 * math.sin(a))))
        if prev is not None:
            for k in range(6):
                bm.faces.new((prev[k], prev[(k + 1) % 6], ring[(k + 1) % 6], ring[k]))
        prev = ring
    add("cable_wire", bm, 7, 5)


def frame_and_render(scene, cam, objects, path):
    points = []
    for ob in objects:
        if ob.type == "MESH":
            points += [ob.matrix_world @ Vector(c) for c in ob.bound_box]
    rot = cam.rotation_euler.to_matrix()
    right, up = rot @ Vector((1, 0, 0)), rot @ Vector((0, 1, 0))
    xs, ys = [p.dot(right) for p in points], [p.dot(up) for p in points]
    center = sum(points, Vector()) / len(points)
    cx, cy = (max(xs) + min(xs)) / 2, (max(ys) + min(ys)) / 2
    center = center - right * (center.dot(right) - cx) - up * (center.dot(up) - cy)
    cam.location = center + VIEW_DIR * 20.0
    cam.data.ortho_scale = max(max(xs) - min(xs), max(ys) - min(ys)) * MARGIN
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True, scene=scene.name)


def render_all():
    os.makedirs(OUT_DIR, exist_ok=True)
    previous = bpy.context.window.scene
    scene = bpy.data.scenes.new("building_icons")
    bpy.context.window.scene = scene
    scene.render.engine = previous.render.engine
    scene.render.resolution_x = scene.render.resolution_y = SIZE
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    world = bpy.data.worlds.new("icon_world")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.45, 0.5, 0.58, 1)
    scene.world = world
    sun = bpy.data.objects.new("icon_sun", bpy.data.lights.new("icon_sun", "SUN"))
    sun.data.energy = 3.0
    sun.rotation_euler = (0.8, 0.2, 0.6)
    scene.collection.objects.link(sun)
    cam = bpy.data.objects.new("icon_cam", bpy.data.cameras.new("icon_cam"))
    cam.data.type = "ORTHO"
    cam.data.clip_end = 100.0
    cam.rotation_euler = (-VIEW_DIR).to_track_quat("-Z", "Y").to_euler()
    scene.collection.objects.link(cam)
    scene.camera = cam
    mat = palette_material()
    try:
        for name in BUILDINGS:
            before = set(bpy.data.objects)
            bpy.ops.import_scene.gltf(filepath=os.path.join(MODELS, name + ".glb"))
            new = [o for o in bpy.data.objects if o not in before]
            for ob in new:
                if ob.type == "MESH":
                    for slot in ob.material_slots:
                        # La banda de la cinta y lo emisivo llevan su propio material.
                        if slot.material is not None and not slot.material.name.startswith(("palette_emissive", "belt_band")):
                            slot.material = mat
            for ob in new:
                if ob.name.startswith(HIDDEN):
                    ob.hide_render = True
            frame_and_render(scene, cam, new, os.path.join(OUT_DIR, name + ".png"))
            for ob in new:
                bpy.data.objects.remove(ob, do_unlink=True)
            print("icono", name)
        before = set(bpy.data.objects)
        cable_icon_model(scene, mat)
        new = [o for o in bpy.data.objects if o not in before]
        frame_and_render(scene, cam, new, os.path.join(OUT_DIR, "cable.png"))
        print("icono cable")
    finally:
        bpy.context.window.scene = previous
        bpy.data.scenes.remove(scene)


if __name__ == "__main__":
    render_all()
