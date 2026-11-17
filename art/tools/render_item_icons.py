# Fotos de los ítems para los iconos del inventario (C1, paso 7).
# Uso: abrir art/props/items.blend y ejecutar este script. Escribe assets/textures/icons/<id>.png
# (128 px, fondo transparente, cámara ortográfica en 3/4). Deja la escena como estaba.
import math
import os
import bpy
from mathutils import Vector

SIZE = 128
MARGIN = 1.12  # aire alrededor del objeto dentro del icono
VIEW_DIR = Vector((0.55, -1.0, 0.75)).normalized()  # del objeto hacia la cámara
OUT_DIR = bpy.path.abspath("//../../assets/textures/icons/")
ITEMS = ["wood", "stone", "seed", "copper_ore", "charcoal", "copper_ingot", "slag", "copper_coil",
        "iron_ingot", "solar_cell", "gravel"]


def _mesh_points(root: bpy.types.Object) -> list:
    points = []
    for obj in [root] + list(root.children_recursive):
        if obj.type == "MESH":
            points += [obj.matrix_world @ Vector(c) for c in obj.bound_box]
    return points


def _setup_camera() -> bpy.types.Object:
    cam_data = bpy.data.cameras.new("icon_camera")
    cam_data.type = "ORTHO"
    cam = bpy.data.objects.new("icon_camera", cam_data)
    bpy.context.collection.objects.link(cam)
    cam.rotation_euler = (-VIEW_DIR).to_track_quat("-Z", "Y").to_euler()
    return cam


def _frame(cam: bpy.types.Object, points: list) -> None:
    rot = cam.rotation_euler.to_matrix()
    right, up = rot @ Vector((1, 0, 0)), rot @ Vector((0, 1, 0))
    xs, ys = [p.dot(right) for p in points], [p.dot(up) for p in points]
    center = sum(points, Vector()) / len(points)
    # Centra el rectángulo proyectado, no la media de puntos
    cx, cy = (max(xs) + min(xs)) / 2, (max(ys) + min(ys)) / 2
    center = center - right * (center.dot(right) - cx) - up * (center.dot(up) - cy)
    cam.location = center + VIEW_DIR * 5.0
    cam.data.ortho_scale = max(max(xs) - min(xs), max(ys) - min(ys)) * MARGIN


def render_all() -> None:
    scene = bpy.context.scene
    os.makedirs(OUT_DIR, exist_ok=True)
    saved = (scene.camera, scene.render.resolution_x, scene.render.resolution_y,
            scene.render.resolution_percentage, scene.render.film_transparent, scene.render.filepath)
    roots = [bpy.data.objects["item_" + i] for i in ITEMS]
    hidden = {o.name: o.hide_render for o in bpy.data.objects}
    cam = _setup_camera()
    scene.camera = cam
    scene.render.resolution_x = scene.render.resolution_y = SIZE
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    try:
        for item, root in zip(ITEMS, roots):
            keep = {root} | set(root.children_recursive)
            for o in bpy.data.objects:
                if o.type == "MESH":
                    o.hide_render = o not in keep
            _frame(cam, _mesh_points(root))
            scene.render.filepath = os.path.join(OUT_DIR, item + ".png")
            bpy.ops.render.render(write_still=True)
            print("icono", item)
    finally:
        for name, h in hidden.items():
            if name in bpy.data.objects:
                bpy.data.objects[name].hide_render = h
        (scene.camera, scene.render.resolution_x, scene.render.resolution_y,
            scene.render.resolution_percentage, scene.render.film_transparent, scene.render.filepath) = saved
        cam_data = cam.data
        bpy.data.objects.remove(cam)
        bpy.data.cameras.remove(cam_data)


if __name__ == "__main__":
    render_all()
