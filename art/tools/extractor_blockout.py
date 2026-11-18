# Extractor (B3.7). 1×2: la CABEZA va sobre una casilla del borde de una veta (3×3) y la COLA queda fuera,
# con la tolva y el puerto de salida al final (diseño de César: hasta 8 extractores por veta).
# Metálico, en los grises del Nexo como la placa solar, la cinta y los puertos (v2, César): bastidor de 4
# pies sobre la veta, carcasa hexagonal con el motor y el borne, taladro a la vista por debajo, conducto
# cerrado hasta un almacén metálico cuya salida es el puerto estándar.
# Convenciones: sin girar, la cabeza está al SUR (casilla y ∈ [−1, 0]) y la cola al NORTE (y ∈ [0, 1]),
# con la salida al norte (la pone Godot: puerto estándar). Origen en el centro de la huella, a ras de suelo.
# Regla de puertos: donde hay puerto, nada pasa de 0,25 m del borde (aquí, y ≤ 0,75); el almacén llega justo
# hasta ahí para que el puerto quede pegado.
# Para ver cómo encaja, se trae una copia de la veta (colección «ref_vein», no se exporta).
#
# Nodos para Godot: status_light_east / status_light_west (puntas de las antenas: verde con sitio, ámbar
# lleno), cable_insulator, cable_anchor, drill_pivot (lo que cuelga de él gira y sube y baja
# mientras trabaja), dust_origin (sale polvo donde excava la broca, César) y store_fill_pivot (el
# mineral de las mirillas: se escala en vertical según lo lleno que esté el almacén).
#
# Uso: Editor de texto de Blender → abrir → Alt+P. Si ya existe «extractor», lo borra y lo rehace.
# Dónde tocar: las medidas están en build(); cada pieza dice su color como (fila, columna).

import bpy
import bmesh
import importlib
import math
import os
import sys
from mathutils import Matrix, Vector

# Emblema de la colonia: pieza común en art/tools/crest.py (sin dejar __pycache__ en el proyecto).
sys.dont_write_bytecode = True
sys.path.insert(0, os.path.normpath(bpy.path.abspath("//../tools")))
import crest
importlib.reload(crest)

PALETTE = 64
SWATCH = 8
ROOT = "extractor"
TEXTURE = "//../../assets/textures/palette.png"
VEIN_BLEND = "//malachite_vein.blend"

WOOD, WOOD_DARK, WOOD_END = (0, 3), (0, 4), (0, 2)
STONE, STONE_DARK = (1, 4), (1, 5)
METAL_LIGHT, METAL, METAL_DARK, METAL_DEEP = (5, 2), (5, 3), (5, 4), (5, 5)
GLASS = (7, 6)
ACCENT = (4, 2)           # naranja oscuro, el del horno: el color propio del extractor (César)
ORE = (3, 5)

HEAD_Y = -0.5            # centro de la casilla de la cabeza
HEAD_Y_DEFAULT = HEAD_Y
VEIN_TOP = 0.15          # altura máxima de la veta en el borde: ahí apoyan los pies
# Centro del almacén a lo largo de Y: va de y = 0,12 hasta 0,75, pegado a la cara interior del puerto
# de salida (0,735) para que no quede hueco entre los dos (César).
STORE_Y = 0.435


def swatch_uv(row: int, col: int) -> Vector:
    return Vector(((col * SWATCH + SWATCH / 2) / PALETTE, 1.0 - (row * SWATCH + SWATCH / 2) / PALETTE))


def get_material():
    mat = bpy.data.materials.get("palette")
    if mat is not None:
        return mat
    img = bpy.data.images.load(TEXTURE, check_existing=True)
    mat = bpy.data.materials.new("palette")
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial"); out.location = (300, 0)
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled"); bsdf.location = (0, 0)
    tex = nt.nodes.new("ShaderNodeTexImage"); tex.location = (-350, 0)
    tex.image = img
    tex.interpolation = "Closest"
    bsdf.inputs["Roughness"].default_value = 0.8
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    return mat


def finish(name: str, bm: bmesh.types.BMesh, color, parent, material, bevel: float = 0.012, segments: int = 2):
    if bevel <= 0.012:
        segments = 1
    if bevel > 0.0:
        bmesh.ops.bevel(bm, geom=list(bm.edges), offset=bevel, segments=segments, affect="EDGES",
                        profile=0.5, clamp_overlap=True)
    uv = bm.loops.layers.uv.new("UVMap")
    for f in bm.faces:
        for loop in f.loops:
            loop[uv].uv = swatch_uv(*color)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    mesh.materials.append(material)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.parent = parent
    for p in mesh.polygons:
        p.use_smooth = True
    mesh.set_sharp_from_angle(angle=math.radians(30))
    return obj


def cut_recess(obj, size, center, color) -> None:
    # Hunde una caja en `obj` (booleana aplicada); las caras del hueco toman el color `color`.
    bm = box(size, center)
    uv = bm.loops.layers.uv.new("UVMap")
    for f in bm.faces:
        for loop in f.loops:
            loop[uv].uv = swatch_uv(*color)
    cutter_mesh = bpy.data.meshes.new("recess_cutter")
    bm.to_mesh(cutter_mesh)
    bm.free()
    cutter = bpy.data.objects.new("recess_cutter", cutter_mesh)
    bpy.context.collection.objects.link(cutter)
    mod = obj.modifiers.new("recess", "BOOLEAN")
    mod.operation = "DIFFERENCE"
    mod.object = cutter
    deps = bpy.context.evaluated_depsgraph_get()
    new_mesh = bpy.data.meshes.new_from_object(obj.evaluated_get(deps))
    obj.modifiers.clear()
    old_mesh = obj.data
    obj.data = new_mesh
    bpy.data.meshes.remove(old_mesh)
    new_mesh.name = obj.name
    bpy.data.objects.remove(cutter, do_unlink=True)
    bpy.data.meshes.remove(cutter_mesh)
    for p in new_mesh.polygons:
        p.use_smooth = True
    new_mesh.set_sharp_from_angle(angle=math.radians(30))


def hex_rivet(center, normal, r: float = 0.017, depth: float = 0.02, bm=None):
    # Remache o tornillo HEXAGONAL (guía de arte: nada de cubitos): prisma de 6 lados con el eje en
    # `normal`, medio hundido en la superficie. Con `bm`, se añade a esa malla y devuelve sus caras.
    target = bm if bm is not None else bmesh.new()
    n = Vector(normal).normalized()
    rot = Vector((0.0, 0.0, 1.0)).rotation_difference(n).to_matrix()
    c = Vector(center)
    low, high = [], []
    for i in range(6):
        a = 2.0 * math.pi * i / 6
        p = Vector((r * math.cos(a), r * math.sin(a), 0.0))
        low.append(target.verts.new(c + rot @ (p + Vector((0.0, 0.0, -depth / 2)))))
        high.append(target.verts.new(c + rot @ (p + Vector((0.0, 0.0, depth / 2)))))
    faces = [target.faces.new(list(reversed(low))), target.faces.new(high)]
    for i in range(6):
        j = (i + 1) % 6
        faces.append(target.faces.new((low[i], low[j], high[j], high[i])))
    bmesh.ops.recalc_face_normals(target, faces=faces)
    return faces if bm is not None else target


def box(size, center) -> bmesh.types.BMesh:
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
    bmesh.ops.translate(bm, vec=Vector(center), verts=bm.verts)
    return bm


def prism(sides: int, r_bottom: float, r_top: float, z0: float, z1: float, x=0.0, y=0.0,
          angle: float = 0.0) -> bmesh.types.BMesh:
    bm = bmesh.new()
    bottom, top = [], []
    for i in range(sides):
        a = angle + 2.0 * math.pi * i / sides
        bottom.append(bm.verts.new((x + r_bottom * math.cos(a), y + r_bottom * math.sin(a), z0)))
        top.append(bm.verts.new((x + r_top * math.cos(a), y + r_top * math.sin(a), z1)))
    bm.faces.new(list(reversed(bottom)))
    bm.faces.new(top)
    for i in range(sides):
        j = (i + 1) % sides
        bm.faces.new((bottom[i], bottom[j], top[j], top[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def strut(p0, p1, thick: float) -> bmesh.types.BMesh:
    p0, p1 = Vector(p0), Vector(p1)
    d = p1 - p0
    bm = box((thick, thick, d.length), (0.0, 0.0, d.length / 2))
    rot = Vector((0.0, 0.0, 1.0)).rotation_difference(d.normalized()).to_matrix().to_4x4()
    bmesh.ops.transform(bm, matrix=Matrix.Translation(p0) @ rot, verts=bm.verts)
    return bm


def ring_bm(r_in: float, r_out: float, z0: float, z1: float, x=0.0, y=HEAD_Y_DEFAULT) -> bmesh.types.BMesh:
    # Aro hexagonal (bastidor, flejes).
    bm = bmesh.new()
    rings = []
    for (r, z) in ((r_out, z0), (r_out, z1), (r_in, z1), (r_in, z0)):
        rings.append([bm.verts.new((x + r * math.cos(2 * math.pi * i / 6), y + r * math.sin(2 * math.pi * i / 6), z))
                      for i in range(6)])
    for k in range(4):
        a_ring, b_ring = rings[k], rings[(k + 1) % 4]
        for i in range(6):
            j = (i + 1) % 6
            bm.faces.new((a_ring[i], a_ring[j], b_ring[j], b_ring[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def empty(name: str, location, parent, kind: str = "SPHERE", size: float = 0.03):
    obj = bpy.data.objects.new(name, None)
    obj.empty_display_type = kind
    obj.empty_display_size = size
    obj.location = location
    obj.parent = parent
    bpy.context.collection.objects.link(obj)
    return obj


def clear_previous() -> None:
    for name in (ROOT,):
        root = bpy.data.objects.get(name)
        if root is None:
            continue
        for obj in list(root.children_recursive) + [root]:
            data = obj.data
            bpy.data.objects.remove(obj, do_unlink=True)
            if data is not None and data.users == 0:
                bpy.data.meshes.remove(data)


def place_reference_vein() -> None:
    # Copia de la veta con la casilla norte-centro bajo la cabeza: centro de la veta en (0, −1,5).
    ref = bpy.data.collections.get("ref_vein")
    if ref is not None:
        for obj in list(ref.objects):
            bpy.data.objects.remove(obj, do_unlink=True)
        bpy.data.collections.remove(ref)
    ref = bpy.data.collections.new("ref_vein")
    bpy.context.scene.collection.children.link(ref)
    path = bpy.path.abspath(VEIN_BLEND)
    with bpy.data.libraries.load(path, link=False) as (src, dst):
        dst.objects = [n for n in src.objects if n.startswith("malachite_vein") or n.startswith("vein_")]
    for obj in dst.objects:
        ref.objects.link(obj)
        obj.name = "ref_" + obj.name
        if obj.parent is None:
            obj.location = (0.0, -1.5, 0.0)
        obj.hide_select = True


def place_reference_port() -> None:
    # Copia de referencia del puerto de salida de port.blend al norte (malla enlazada; no se exporta).
    refs = bpy.data.collections.get("ref_ports")
    if refs is None:
        refs = bpy.data.collections.new("ref_ports")
        bpy.context.scene.collection.children.link(refs)
    for obj in list(refs.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    found = next((o for o in bpy.data.objects if o.name == "port_output" and o.library is not None), None)
    if found is None:
        with bpy.data.libraries.load("//port.blend", link=True) as (src, dst):
            dst.objects = ["port_output"]
        found = dst.objects[0]
    obj = bpy.data.objects.new("ref_port_output", found.data)
    obj.location = (0.0, 0.5, 0.0)
    refs.objects.link(obj)


def arch_segment_y(y0: float, y1: float, half_x: float, z0: float, rise: float, sides: int = 6) -> bmesh.types.BMesh:
    # Segmento de tapa abombada (como en la caja logística): medio polígono en el plano XZ, de y0 a y1.
    bm = bmesh.new()
    rings = []
    for y in (y0, y1):
        ring = []
        for i in range(sides + 1):
            a = math.pi * i / sides
            ring.append(bm.verts.new((half_x * math.cos(a), y, z0 + rise * math.sin(a))))
        rings.append(ring)
    for i in range(sides):
        bm.faces.new((rings[0][i], rings[0][i + 1], rings[1][i + 1], rings[1][i]))
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def hex_box(r: float, z0: float, z1: float, x=0.0, y=0.0) -> bmesh.types.BMesh:
    # Prisma hexagonal con caras planas al norte y al sur (como el módulo de la placa solar).
    return prism(6, r, r, z0, z1, x, y)


def build() -> None:
    clear_previous()
    mat = get_material()
    root = empty(ROOT, (0, 0, 0), None, "PLAIN_AXES", 0.3)
    hy = HEAD_Y

    # --- Cabeza (sobre la veta): bastidor metálico de 4 pies, con el taladro a la vista por debajo ---
    for i, (sx, sy) in enumerate(((1, 1), (-1, 1), (-1, -1), (1, -1))):
        fx, fy = sx * 0.3, hy + sy * 0.3
        finish("foot_%d" % i, prism(6, 0.075, 0.065, 0.0, VEIN_TOP + 0.04, x=fx, y=fy), METAL_DEEP, root, mat, 0.0)
        finish("leg_%d" % i, strut((fx, fy, VEIN_TOP + 0.03), (sx * 0.2, hy + sy * 0.2, 0.62), 0.06), METAL_DARK, root, mat, 0.008)
    # Aro hexagonal del bastidor y carcasa del motor encima (grises del Nexo, como la placa y los puertos).
    finish("frame_ring", ring_bm(0.27, 0.33, 0.58, 0.66), METAL_DARK, root, mat)
    finish("housing", hex_box(0.3, 0.66, 1.08, y=hy), METAL, root, mat, 0.02)
    finish("housing_band", ring_bm(0.3, 0.325, 0.82, 0.9), ACCENT, root, mat)
    finish("housing_cap", prism(6, 0.27, 0.2, 1.08, 1.16, y=hy), METAL_DARK, root, mat, 0.01)
    finish("housing_glass", box((0.18, 0.02, 0.08), (0.0, hy - 0.262, 0.97)), GLASS, root, mat, 0.0)
    # Remaches hexagonales en las caras rectas sur y norte de la carcasa, a los lados (César).
    apothem = 0.3 * math.cos(math.radians(30))
    for side, sy in (("s", -1.0), ("n", 1.0)):
        for dx in (-0.12, 0.12):
            for dz in (0.74, 1.02):
                finish("rivet_%s_%d_%d" % (side, dx > 0, dz > 0.9), hex_rivet((dx, hy + sy * apothem, dz), (0, sy, 0)),
                       METAL_DEEP, root, mat, 0.0)
    # Antenas de hormiga en la cabeza (como las de la caja logística, César), inclinadas hacia la veta, con
    # la luz de estado en la punta: verde si al almacén le cabe algo más, ámbar si está lleno.
    for side, sx in (("east", 1.0), ("west", -1.0)):
        p0 = Vector((sx * 0.13, hy - 0.08, 1.15))
        p1 = Vector((sx * 0.21, hy - 0.2, 1.3))
        p2 = Vector((sx * 0.31, hy - 0.33, 1.35))
        finish("antenna_%s_socket" % side, prism(6, 0.04, 0.032, p0.z - 0.05, p0.z + 0.01, x=p0.x, y=p0.y), METAL_DEEP, root, mat, 0.0)
        finish("antenna_%s_0" % side, strut(p0, p1, 0.03), METAL_DARK, root, mat, 0.0)
        finish("antenna_%s_1" % side, strut(p1, p2, 0.026), METAL_DARK, root, mat, 0.0)
        finish("antenna_%s_joint" % side, prism(6, 0.026, 0.026, p1.z - 0.02, p1.z + 0.02, x=p1.x, y=p1.y), ACCENT, root, mat, 0.0)
        finish("status_light_" + side, prism(6, 0.04, 0.028, p2.z - 0.015, p2.z + 0.05, x=p2.x, y=p2.y), GLASS, root, mat, 0.006)
    # Borne del cable encima, como el del horno.
    finish("cable_post", box((0.06, 0.06, 0.08), (0.0, hy, 1.2)), METAL, root, mat, 0.008)
    finish("cable_insulator", prism(6, 0.065, 0.048, 1.22, 1.31, y=hy), GLASS, root, mat, 0.008)
    empty("cable_anchor", (0.0, hy, 1.31), root)

    # --- Taladro: eje, espiras y broca de hierro bajo la carcasa. Godot lo gira y lo sube y baja ---
    pivot_pos = Vector((0.0, hy, 0.66))
    pivot = empty("drill_pivot", pivot_pos, root, "ARROWS", 0.12)
    parts = [
        finish("drill_shaft", prism(6, 0.045, 0.045, VEIN_TOP + 0.2, 0.66, y=hy), METAL_LIGHT, root, mat, 0.0),
        finish("drill_bit", prism(6, 0.1, 0.02, VEIN_TOP + 0.2, VEIN_TOP - 0.03, y=hy, angle=math.radians(30)), METAL_DEEP, root, mat, 0.0),
    ]
    for i, z in enumerate((0.36, 0.5)):
        parts.append(finish("drill_flight_%d" % i, prism(6, 0.09, 0.09, z, z + 0.025, y=hy, angle=math.radians(20 * i)),
                            METAL, root, mat, 0.0))
    for obj in parts:
        obj.parent = pivot
        obj.matrix_parent_inverse = Matrix.Translation(pivot_pos).inverted()
    # Punto de la broca donde sale la nube de polvo mientras trabaja (fijo: no cuelga del pivote).
    empty("dust_origin", (0.0, hy, VEIN_TOP), root, "SPHERE", 0.05)

    # --- Conducto cerrado: de la carcasa al almacén (el mineral pasa por dentro) ---
    finish("duct", box((0.18, 0.5, 0.16), (0.0, -0.08, 0.78)), METAL_DARK, root, mat, 0.012)
    for i, y in enumerate((-0.2, 0.06)):
        finish("duct_band_%d" % i, box((0.21, 0.035, 0.19), (0.0, y, 0.78)), ACCENT, root, mat, 0.0)

    # --- Cola: cámara de almacén como la de la caja logística (César) ---
    # Abajo, una caja metálica de la misma altura que el marco del puerto (0,62 m), plana por detrás y a ras
    # de él: el puerto encaja como en la caja logística. Encima, la tapa de caparazón de hormiga: tres
    # segmentos oscuros abombados (más bajo el de atrás, junto al puerto) con dos anillos naranjas. El
    # conducto de la cabeza entra por el segmento de delante.
    # La caja llega justo a la trasera del puerto (y = 0,735); base, franja y reborde 2,5 cm más allá, por
    # dentro del marco: sin hueco (César).
    store_y0, store_y1 = 0.12, 0.735
    trim_y0, trim_y1 = 0.1, 0.76
    trim_len, trim_mid = trim_y1 - trim_y0, (trim_y0 + trim_y1) / 2
    half_x, z0, z1 = 0.4, 0.07, 0.62
    store = finish("store", box((2 * half_x, store_y1 - store_y0, z1 - z0), (0.0, STORE_Y, (z0 + z1) / 2)), METAL, root, mat, 0.02)
    finish("store_base", box((2 * half_x + 0.04, trim_len, z0 + 0.02), (0.0, trim_mid, (z0 + 0.02) / 2)), METAL_DEEP, root, mat, 0.01)
    finish("store_band", box((2 * half_x + 0.02, trim_len, 0.05), (0.0, trim_mid, z0 + 0.1)), ACCENT, root, mat, 0.006)
    finish("store_rim", box((2 * half_x + 0.04, trim_len, 0.05), (0.0, trim_mid, z1 + 0.02)), METAL_DARK, root, mat, 0.01)
    # Caparazón: 3 segmentos con 2 anillos naranjas (como la caja logística y la tapa del arcón).
    shell_z = z1 + 0.045
    segs = [(trim_y0, 0.3, 0.85), (0.34, 0.52, 1.0), (0.56, trim_y1, 0.7)]
    for k, (y0, y1, scale) in enumerate(segs):
        finish("shell_%d" % k, arch_segment_y(y0, y1, (half_x + 0.02) * (0.9 + 0.1 * scale), shell_z, 0.3 * scale),
               METAL_DEEP, root, mat, 0.012)
    for k, (y0, y1) in enumerate(((0.29, 0.35), (0.51, 0.57))):
        finish("shell_ring_%d" % k, arch_segment_y(y0, y1, half_x + 0.035, shell_z, 0.3 + 0.025), ACCENT, root, mat, 0.006)

    # Mirillas HUNDIDAS en los costados este y oeste (César), con un marco arriba y abajo y el mineral dentro.
    win_z, win_h, win_w = 0.3, 0.14, 0.32
    for side, sx in (("east", 1.0), ("west", -1.0)):
        cut_recess(store, (0.1, win_w, win_h), (sx * half_x, STORE_Y, win_z), METAL_DEEP)
        for k, dz in enumerate((win_h / 2 + 0.015, -win_h / 2 - 0.015)):
            finish("store_window_frame_%s_%d" % (side, k), box((0.02, win_w + 0.08, 0.03), (sx * (half_x + 0.005), STORE_Y, win_z + dz)),
                   METAL_DARK, root, mat, 0.004)
        finish("store_window_" + side, box((0.01, win_w, win_h), (sx * (half_x - 0.045), STORE_Y, win_z)), GLASS, root, mat, 0.0)
        for dy in (-0.25, 0.25):
            finish("store_rivet_%s_%d" % (side[0], dy > 0), hex_rivet((sx * (half_x + 0.004), STORE_Y + dy, win_z), (sx, 0, 0), r=0.016),
                   METAL_DEEP, root, mat, 0.0)
    # Mineral visible en las dos mirillas: cuelga de «store_fill_pivot», en el fondo de la ventana. Godot lo
    # escala en vertical según lo lleno que esté el almacén (vacío = no se ve; lleno = llega arriba) y lo
    # pinta del color del ítem que saca (cada veta, el suyo; César).
    fill_pos = Vector((0.0, STORE_Y, win_z - win_h / 2))
    fill = empty("store_fill_pivot", fill_pos, root, "ARROWS", 0.08)
    for side, sx in (("east", 1.0), ("west", -1.0)):
        # En el mismo plano que el cristal (apenas 1 mm por delante): parece que el cristal se llena.
        ore = finish("store_ore_" + side, box((0.012, win_w, win_h), (sx * (half_x - 0.044), STORE_Y, win_z)), ORE, root, mat, 0.0)
        ore.parent = fill
        ore.matrix_parent_inverse = Matrix.Translation(fill_pos).inverted()

    # Emblema de la colonia pintado (crest.py) en los dos costados, entre la mirilla y el reborde.
    for side, sx in (("east", 1.0), ("west", -1.0)):
        crest.add_crest(finish, root, mat, (sx * half_x, STORE_Y, 0.5), (sx, 0.0, 0.0), scale=0.5, style="painted",
                        prefix="crest_" + side)

    tris = 0
    for child in root.children_recursive:
        if child.type == "MESH":
            tris += sum(len(p.vertices) - 2 for p in child.data.polygons)
    print("extractor: piezas:", len(root.children_recursive), "triángulos:", tris)
    place_reference_vein()
    place_reference_port()


build()
