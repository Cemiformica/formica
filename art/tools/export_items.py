# Modelos de los ítems para Godot (sesión 28, César: «que las cintas transporten objetos en lugar de cubos»).
# Exporta todos los ítems de items.blend (items_blockout.py) a un solo assets/models/items/items.glb: cada
# ítem es una malla «item_<id>» con todas sus piezas unidas y el origen en su centro (como en items.blend),
# y todas en el origen. En Godot, ItemModels (core/content/item_models.gd) busca la malla por el id del ítem.
# El .blend NO cambia: se trabaja sobre copias que se borran al terminar.
#
# Uso (en Blender, con art/props/items.blend abierto):
#   exec(open(bpy.path.abspath("//../tools/export_items.py")).read())
# Dónde tocar: SKIP (raíces de items.blend que no son ítems del juego).

import os

import bpy

OUTPUT = "//../../assets/models/items/items.glb"
SKIP = {"item_seed"}   # semilla antigua, anterior a la bellota y la piña (C1.9); no hay ítem con ese id


def export() -> None:
    if bpy.context.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")
    roots = sorted((o for o in bpy.data.objects if o.type == "EMPTY" and o.name.startswith("item_")
                    and o.parent is None and o.name not in SKIP), key=lambda o: o.name)
    made = []
    names = {root: root.name for root in roots}
    try:
        for root in roots:
            root.name = names[root] + "_src"   # libera el nombre para la malla exportada
            parts = [c for c in root.children_recursive if c.type == "MESH"]
            if not parts:
                continue
            # Copias de las piezas, en coordenadas del vacío raíz (así el origen queda en su centro).
            to_root = root.matrix_world.inverted()
            copies = []
            for part in parts:
                copy = part.copy()
                copy.data = part.data.copy()
                copy.parent = None
                copy.matrix_world = to_root @ part.matrix_world
                bpy.context.scene.collection.objects.link(copy)
                copies.append(copy)
            bpy.ops.object.select_all(action="DESELECT")
            for copy in copies:
                copy.select_set(True)
            bpy.context.view_layer.objects.active = copies[0]
            if len(copies) > 1:
                bpy.ops.object.join()
            item = bpy.context.view_layer.objects.active
            bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
            item.name = names[root]
            item.data.name = names[root]
            made.append(item)
        bpy.ops.object.select_all(action="DESELECT")
        for item in made:
            item.select_set(True)
        os.makedirs(os.path.dirname(bpy.path.abspath(OUTPUT)), exist_ok=True)
        options = dict(filepath=bpy.path.abspath(OUTPUT), export_format="GLB", use_selection=True, export_yup=True,
                       export_apply=False, export_cameras=False, export_lights=False, export_animations=False)
        try:
            bpy.ops.export_scene.gltf(export_vertex_color="ACTIVE", **options)
        except TypeError:
            bpy.ops.export_scene.gltf(**options)
        for item in made:
            n = sum(len(p.vertices) - 2 for p in item.data.polygons)
            size = item.dimensions
            print("%-18s %5d triángulos  %.2f × %.2f × %.2f m" % (item.name, n, size.x, size.y, size.z))
    finally:
        for item in made:
            data = item.data
            bpy.data.objects.remove(item, do_unlink=True)
            bpy.data.meshes.remove(data)
        for root, name in names.items():   # después de borrar las copias, que tenían su nombre
            root.name = name
    print("exportado:", OUTPUT, "|", len(made), "ítems")


export()
