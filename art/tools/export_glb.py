# Exportación a Godot (B3). Exporta un objeto raíz y su jerarquía a un .glb en assets/, UNIENDO todas
# las piezas fijas en una sola malla («<raíz>_body») para que Godot las dibuje en una sola llamada.
# Se quedan aparte, con su nombre, las piezas que Godot necesita tocar:
#   - las que cuelgan de un vacío intermedio (p. ej. todo lo que cuelga de «bellows_pivot» se une en
#     una sola malla «bellows_pivot_mesh» bajo ese pivote, para animarlo),
#   - las que empiezan por un prefijo de KEEP (brasa, aislante, lengüeta de cinta, luz de estado…),
#   - los vacíos (cable_anchor, smoke_origin, pivotes).
# El .blend NO cambia: se trabaja sobre copias temporales que se borran al terminar.
#
# Uso (en Blender, con el .blend abierto):
#   export_hierarchy("furnace", "//../../assets/models/buildings/furnace.glb")
# Dónde tocar: KEEP, si una máquina nueva tiene otra pieza que Godot deba encender o mover.

import bpy

KEEP = ("ember_window", "cable_insulator", "belt_tongue", "belt_end", "belt_join", "status_light", "work_lamp")


def _is_kept(name: str) -> bool:
    return any(name.startswith(prefix) for prefix in KEEP)


def _join(objects: list, name: str):
    # Une `objects` (copias) en el primero y le pone el nombre.
    bpy.ops.object.select_all(action="DESELECT")
    for o in objects:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    if len(objects) > 1:
        bpy.ops.object.join()
    joined = bpy.context.view_layer.objects.active
    joined.name = name
    joined.data.name = name
    return joined


def export_hierarchy(root_name: str, filepath: str) -> None:
    if bpy.context.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")
    root = bpy.data.objects[root_name]
    temp = bpy.data.collections.new("_export_tmp")
    bpy.context.scene.collection.children.link(temp)

    # 1) Copiar la jerarquía (las mallas se copian también, para poder unirlas sin tocar las originales).
    copies = {}
    for src in [root] + list(root.children_recursive):
        dup = src.copy()
        if src.data is not None:
            dup.data = src.data.copy()
        temp.objects.link(dup)
        copies[src] = dup
    for src, dup in copies.items():
        if src.parent in copies:
            dup.parent = copies[src.parent]
            dup.matrix_parent_inverse = src.matrix_parent_inverse.copy()
    root_copy = copies[root]

    # 2) Agrupar mallas: fijas del cuerpo, por pivote, o aparte.
    body, by_pivot, kept = [], {}, []
    for src, dup in copies.items():
        if dup.type != "MESH" or src is root:
            continue  # la raíz se queda como está (en el puerto, la raíz es la propia malla del marco)
        if _is_kept(src.name):
            kept.append((src.name, dup))
        elif src.parent is root:
            body.append(dup)
        else:
            by_pivot.setdefault(copies[src.parent], []).append(dup)

    # 3) Unir (cada grupo conserva el padre de su primera pieza). Los nombres limpios se ponen en el 4.
    if body:
        _join(body, root_name + "_body")
    for pivot, parts in by_pivot.items():
        _join(parts, pivot.name.split(".")[0] + "_mesh")

    # 4) Exportar solo las copias. Los originales se renombran un momento para que las copias
    #    puedan llevar los nombres limpios que buscará Godot.
    originals = [root] + list(root.children_recursive)
    for o in originals:
        o.name = "_orig_" + o.name
    for o in temp.objects:
        o.name = o.name.split(".")[0]
    bpy.ops.object.select_all(action="DESELECT")
    for o in temp.objects:
        o.select_set(True)
    bpy.context.view_layer.objects.active = root_copy
    bpy.ops.export_scene.gltf(filepath=bpy.path.abspath(filepath), export_format="GLB", use_selection=True,
                              export_yup=True, export_apply=True, export_cameras=False, export_lights=False,
                              export_animations=False)
    meshes = [o for o in temp.objects if o.type == "MESH"]
    print("exportado:", filepath, "| mallas:", sorted(o.name for o in meshes),
          "| vacíos:", sorted(o.name for o in temp.objects if o.type == "EMPTY"))

    # 5) Limpiar: borrar copias y devolver los nombres originales.
    for o in list(temp.objects):
        data = o.data
        bpy.data.objects.remove(o, do_unlink=True)
        if data is not None and data.users == 0:
            bpy.data.meshes.remove(data)
    bpy.data.collections.remove(temp)
    for o in originals:
        o.name = o.name[len("_orig_"):]
