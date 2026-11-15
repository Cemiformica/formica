# Talador (B3.7). 3×1 (César): tan ancho como el bloque de 3×3 de arboleda que tala delante.
# Es una «cabeza de hormiga» metálica del Nexo: una MANDÍBULA CORTADORA de dos hojas naranjas dentadas
# (nuestra «hacha», César) que muerde hacia la arboleda, dos antenas con las luces de estado en la punta y,
# a los lados, dos bandejas con troncos a la vista que se llenan según la madera que guarda.
# Convenciones: sin girar, la arboleda está al NORTE (+Y en Blender) y la salida al SUR, en la casilla
# central (puerto estándar, lo pone Godot). Origen en el centro de la huella, a ras de suelo.
# Huella: x ∈ [−1,5, 1,5], y ∈ [−0,5, 0,5]. Regla de puertos: en la casilla central, nada pasa de y = −0,25.
#
# Nodos para Godot: cable_insulator, cable_anchor, status_light_east / status_light_west (puntas de las
# antenas, que cuelgan de antenna_pivot_east / antenna_pivot_west: Godot las balancea al trabajar), jaw_pivot_east / jaw_pivot_west (lo que cuelga gira en Z: la hoja se cierra hacia delante al
# talar), chips_origin (sale serrín donde muerde la mandíbula) y store_log_0 … store_log_9 (troncos de las
# bandejas: Godot enciende tantos como diga lo lleno que esté el almacén).
#
# Uso: Editor de texto de Blender → abrir → Alt+P. Si ya existe «tree_cutter», lo borra y lo rehace.
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
ROOT = "tree_cutter"
TEXTURE = "//../../assets/textures/palette.png"

WOOD, WOOD_DARK, WOOD_END = (0, 3), (0, 4), (0, 2)
METAL_LIGHT, METAL, METAL_DARK, METAL_DEEP = (5, 2), (5, 3), (5, 4), (5, 5)
GLASS = (7, 6)
ACCENT = (4, 2)           # naranja oscuro, el de las máquinas del vertical slice

BODY_Y0, BODY_Y1 = -0.25, 0.22   # fondo del cuerpo: por detrás, a ras de la cara del puerto
BODY_TOP = 0.49
JAW_Z = 0.7                      # altura de las hojas de la mandíbula
JAW_PIVOT = (0.26, 0.32)         # bisagra de la hoja este (la oeste, reflejada)


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


def hang(obj, pivot, pivot_pos) -> None:
    # Cuelga `obj` de un vacío sin moverlo de sitio.
    obj.parent = pivot
    obj.matrix_parent_inverse = Matrix.Translation(Vector(pivot_pos)).inverted()


def hex_rivet(center, normal, r: float = 0.017, depth: float = 0.02, bm=None):
    # Remache o tornillo HEXAGONAL (guía de arte), orientado según la cara.
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


def strut(p0, p1, thick: float, sides: int = 0) -> bmesh.types.BMesh:
    # Barra recta de p0 a p1 (caja, o prisma de `sides` lados).
    p0, p1 = Vector(p0), Vector(p1)
    d = p1 - p0
    if sides:
        bm = prism(sides, thick / 2, thick / 2, 0.0, d.length)
    else:
        bm = box((thick, thick, d.length), (0.0, 0.0, d.length / 2))
    rot = Vector((0.0, 0.0, 1.0)).rotation_difference(d.normalized()).to_matrix().to_4x4()
    bmesh.ops.transform(bm, matrix=Matrix.Translation(p0) @ rot, verts=bm.verts)
    return bm


def slab(points, z0: float, z1: float) -> bmesh.types.BMesh:
    # Extruye en Z un polígono (lista de (x, y) en sentido antihorario).
    bm = bmesh.new()
    bottom = [bm.verts.new((x, y, z0)) for (x, y) in points]
    top = [bm.verts.new((x, y, z1)) for (x, y) in points]
    bm.faces.new(list(reversed(bottom)))
    bm.faces.new(top)
    n = len(points)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((bottom[i], bottom[j], top[j], top[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def log_along_x(x0: float, x1: float, y: float, z: float, r: float, parent, mat, name: str):
    # Tronco tumbado a lo largo de X, ligero: prisma de 6 lados con la corteza oscura, las dos caras de
    # madera clara y un anillo (una sola cara) un pelo por fuera de cada una, como en la carbonera.
    pos = Vector(((x0 + x1) / 2, y, z))
    pivot = empty(name, pos, parent, "PLAIN_AXES", 0.05)
    half = (x1 - x0) / 2
    bm = bmesh.new()
    rings = []
    for sx in (-1.0, 1.0):
        rings.append([bm.verts.new((pos.x + sx * half, pos.y + r * math.cos(a), pos.z + r * math.sin(a)))
                      for a in (math.radians(30 + 60 * i) for i in range(6))])
    ends = [bm.faces.new(list(reversed(rings[0]))), bm.faces.new(rings[1])]
    for i in range(6):
        j = (i + 1) % 6
        bm.faces.new((rings[0][i], rings[0][j], rings[1][j], rings[1][i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    for k, sx in enumerate((-1.0, 1.0)):
        ring = [bm.verts.new((pos.x + sx * (half + 0.003), pos.y + r * 0.45 * math.cos(a), pos.z + r * 0.45 * math.sin(a)))
                for a in (math.radians(60 * i) for i in range(6))]
        face = bm.faces.new(ring)
        if (face.normal.x > 0) != (sx > 0):
            face.normal_flip()
        ends.append(face)
    obj = finish(name + "_wood", bm, WOOD_DARK, parent, mat, 0.0)
    # Caras de los extremos en madera clara (anillos en madera media): se repintan sus UV.
    uv = obj.data.uv_layers[0].data
    for poly in obj.data.polygons:
        if abs(poly.normal.x) > 0.9:
            color = WOOD if len(poly.vertices) == 6 and abs(obj.data.vertices[poly.vertices[0]].co.x - pos.x) > half + 0.001 else WOOD_END
            for li in poly.loop_indices:
                uv[li].uv = swatch_uv(*color)
    hang(obj, pivot, pos)
    return pivot


def empty(name: str, location, parent, kind: str = "SPHERE", size: float = 0.03):
    obj = bpy.data.objects.new(name, None)
    obj.empty_display_type = kind
    obj.empty_display_size = size
    obj.location = location
    obj.parent = parent
    bpy.context.collection.objects.link(obj)
    return obj


def clear_previous() -> None:
    root = bpy.data.objects.get(ROOT)
    if root is None:
        return
    for obj in list(root.children_recursive) + [root]:
        data = obj.data
        bpy.data.objects.remove(obj, do_unlink=True)
        if data is not None and data.users == 0:
            bpy.data.meshes.remove(data)


def jaw_outline(sx: float):
    # Hoja de mandíbula de hormiga vista desde arriba, con la bisagra en el origen. Abierta, se extiende
    # hacia fuera (eje X) y la punta se curva hacia delante y hacia dentro, como una mandíbula de verdad.
    # Borde de atrás (liso) y borde de delante (con dientes); en sentido antihorario para la hoja este.
    back = [(-0.06, -0.07), (0.25, -0.1), (0.6, -0.09), (0.9, -0.04), (1.08, 0.04), (1.16, 0.15)]
    tip = [(1.12, 0.2)]
    front = [(1.0, 0.13), (0.86, 0.12), (0.8, 0.17), (0.7, 0.1), (0.62, 0.15), (0.52, 0.09),
             (0.44, 0.13), (0.34, 0.08), (0.26, 0.11), (0.1, 0.07), (-0.06, 0.07)]
    pts = back + tip + front
    if sx < 0:
        pts = [(-x, y) for (x, y) in reversed(pts)]
    return pts


def jaw_rib_outline(sx: float):
    # Nervio naranja que sigue el borde de atrás de la hoja, por dentro, y se afila hacia la punta.
    back = [(0.1, -0.075), (0.25, -0.1), (0.42, -0.105), (0.6, -0.09), (0.76, -0.07), (0.9, -0.04),
            (1.0, 0.0), (1.08, 0.04), (1.13, 0.11)]
    outer, inner = [], []
    for i, p in enumerate(back):
        a = Vector(back[max(i - 1, 0)]); b = Vector(back[min(i + 1, len(back) - 1)])
        d = (b - a).normalized()
        n = Vector((-d.y, d.x))               # hacia dentro de la hoja (a la izquierda del borde)
        t = i / (len(back) - 1)
        width = 0.06 * (1.0 - t) + 0.018 * t
        outer.append(Vector(p) + n * 0.022)
        inner.append(Vector(p) + n * (0.022 + width))
    pts = [(v.x, v.y) for v in outer] + [(v.x, v.y) for v in reversed(inner)]
    if sx < 0:
        pts = [(-x, y) for (x, y) in reversed(pts)]
    return pts


def build() -> None:
    clear_previous()
    mat = get_material()
    root = empty(ROOT, (0, 0, 0), None, "PLAIN_AXES", 0.3)

    # --- Patas y chasis: un cuerpo bajo y largo, como el tórax de la hormiga ---
    for i, (fx, fy) in enumerate(((1.3, 0.1), (-1.3, 0.1), (1.3, -0.15), (-1.3, -0.15), (0.6, -0.15), (-0.6, -0.15))):
        finish("foot_%d" % i, prism(6, 0.075, 0.065, 0.0, 0.1, x=fx, y=fy), METAL_DEEP, root, mat, 0.0)
    depth, mid_y = BODY_Y1 - BODY_Y0, (BODY_Y0 + BODY_Y1) / 2
    finish("chassis", box((2.84, depth, 0.36), (0.0, mid_y, 0.27)), METAL, root, mat, 0.02)
    finish("chassis_skirt", box((2.9, depth + 0.04, 0.06), (0.0, mid_y, 0.11)), METAL_DARK, root, mat, 0.01)
    finish("chassis_band", box((2.88, depth + 0.03, 0.06), (0.0, mid_y, 0.36)), ACCENT, root, mat, 0.006)
    finish("chassis_top", box((2.88, depth + 0.04, 0.05), (0.0, mid_y, BODY_TOP - 0.025)), METAL_DARK, root, mat, 0.01)
    # Remaches en la cara de delante y en la de detrás (detrás, fuera del hueco del puerto).
    for side, sy in (("n", 1.0), ("s", -1.0)):
        y = BODY_Y1 if sy > 0 else BODY_Y0
        for x in (-1.3, -0.8, 0.8, 1.3) if sy < 0 else (-1.3, -0.7, 0.7, 1.3):
            for z in (0.24,):
                finish("rivet_%s_%d_%d" % (side, int((x + 2) * 100), int(z * 100)),
                       hex_rivet((x, y + sy * 0.004, z), (0, sy, 0)), METAL_DEEP, root, mat, 0.0)
    for sx in (-1.0, 1.0):
        for z in (0.24,):
            finish("rivet_side_%d_%d" % (sx > 0, int(z * 100)),
                   hex_rivet((sx * 1.424, mid_y, z), (sx, 0, 0)), METAL_DEEP, root, mat, 0.0)

    # --- Cabeza de hormiga, en el centro, mirando a la arboleda ---
    finish("neck", prism(6, 0.24, 0.22, 0.47, 0.57, y=0.02), METAL_DARK, root, mat, 0.01)
    head = prism(6, 0.3, 0.34, 0.55, 0.98, y=0.06)
    finish("head", head, METAL, root, mat, 0.02)
    finish("head_band", prism(6, 0.345, 0.345, 0.78, 0.83, y=0.06), ACCENT, root, mat, 0.006)
    finish("head_cap", prism(6, 0.31, 0.19, 0.98, 1.08, y=0.06), METAL_DARK, root, mat, 0.01)
    # Ojos: dos cúpulas hexagonales oscuras a los lados de la cara.
    for side, sx in (("east", 1.0), ("west", -1.0)):
        eye = prism(6, 0.075, 0.05, 0.0, 0.05)
        rot = Vector((0, 0, 1)).rotation_difference(Vector((sx * 0.75, 0.66, 0)).normalized()).to_matrix().to_4x4()
        bmesh.ops.transform(eye, matrix=Matrix.Translation((sx * 0.21, 0.27, 0.9)) @ rot, verts=eye.verts)
        finish("eye_" + side, eye, METAL_DEEP, root, mat, 0.0)

    # Emblema de la colonia pintado (crest.py) en la nuca: la cara plana de la cabeza que mira al sur (al
    # jugador, sobre el puerto de salida), entre el cuello y la franja naranja. La cabeza se ensancha al
    # subir, así que esa cara mira un poco hacia abajo: el emblema la sigue.
    crest_z = 0.67
    slope = 0.04 / 0.43
    apothem = (0.3 + slope * (crest_z - 0.55)) * math.cos(math.radians(30))
    crest.add_crest(finish, root, mat, (0.0, 0.06 - apothem, crest_z),
                    Vector((0.0, -1.0, -slope * math.cos(math.radians(30)))), scale=0.65, style="painted")

    # Antenas con las luces de estado en la punta (ámbar sin cable, verde con cable, rojo con el fusible).
    for side, sx in (("east", 1.0), ("west", -1.0)):
        p0 = Vector((sx * 0.09, 0.08, 1.06))
        p1 = Vector((sx * 0.24, 0.02, 1.44))
        p2 = Vector((sx * 0.42, 0.16, 1.7))
        # Godot balancea «antenna_pivot_…» mientras trabaja, como una hormiga tanteando (César);
        # la luz de estado cuelga de él y se mueve con la antena.
        pivot = empty("antenna_pivot_" + side, p0, root, "ARROWS", 0.08)
        finish("antenna_%s_socket" % side, prism(6, 0.05, 0.04, p0.z - 0.03, p0.z + 0.02, x=p0.x, y=p0.y), METAL_DEEP, root, mat, 0.0)
        for obj in (
            finish("antenna_%s_0" % side, strut(p0, p1, 0.035, 6), METAL_DARK, root, mat, 0.0),
            finish("antenna_%s_1" % side, strut(p1, p2, 0.03, 6), METAL_DARK, root, mat, 0.0),
            finish("antenna_%s_joint" % side, prism(6, 0.03, 0.03, p1.z - 0.025, p1.z + 0.025, x=p1.x, y=p1.y), ACCENT, root, mat, 0.0),
            finish("status_light_" + side, prism(6, 0.05, 0.035, p2.z - 0.02, p2.z + 0.06, x=p2.x, y=p2.y), GLASS, root, mat, 0.006),
        ):
            hang(obj, pivot, p0)

    # --- Mandíbula: dos hojas naranjas dentadas con su bisagra; Godot las cierra hacia delante al talar ---
    for side, sx in (("east", 1.0), ("west", -1.0)):
        pivot_pos = Vector((sx * JAW_PIVOT[0], JAW_PIVOT[1], JAW_Z))
        pivot = empty("jaw_pivot_" + side, pivot_pos, root, "ARROWS", 0.12)
        pts = [(pivot_pos.x + x, pivot_pos.y + y) for (x, y) in jaw_outline(sx)]
        blade = finish("jaw_" + side, slab(pts, JAW_Z - 0.06, JAW_Z + 0.06), METAL_DARK, root, mat, 0.008)
        hang(blade, pivot, pivot_pos)
        # Filo metálico en el borde de dentro de la punta y nervio por encima.
        rib_pts = [(pivot_pos.x + x, pivot_pos.y + y) for (x, y) in jaw_rib_outline(sx)]
        rib = slab(rib_pts, JAW_Z + 0.055, JAW_Z + 0.08)
        hang(finish("jaw_rib_" + side, rib, ACCENT, root, mat, 0.0), pivot, pivot_pos)
        hinge = prism(6, 0.075, 0.075, JAW_Z - 0.08, JAW_Z + 0.08, x=pivot_pos.x, y=pivot_pos.y)
        finish("jaw_hinge_" + side, hinge, METAL_DARK, root, mat, 0.008)
        finish("jaw_bolt_" + side, hex_rivet((pivot_pos.x, pivot_pos.y, JAW_Z + 0.09), (0, 0, 1), r=0.04, depth=0.03),
               METAL_DEEP, root, mat, 0.0)
        # Brazo que une la bisagra a la cabeza.
        finish("jaw_arm_" + side, strut((sx * 0.08, 0.1, JAW_Z), (pivot_pos.x, pivot_pos.y - 0.02, JAW_Z), 0.09),
               METAL_DARK, root, mat, 0.008)
    # Donde muerde la mandíbula sale el serrín (fijo).
    empty("chips_origin", (0.0, 0.48, JAW_Z), root, "SPHERE", 0.05)

    # --- Bandejas a los lados con los troncos a la vista (se llenan con la madera que guarda) ---
    log_r = 0.075
    slots = [(-0.15, 0), (0.0, 0), (0.15, 0), (-0.075, 1), (0.075, 1)]   # (y, fila): tres abajo y dos encima
    index = 0
    for side, sx in (("east", 1.0), ("west", -1.0)):
        x_in, x_out = sx * 0.5, sx * 1.36
        lo, hi = min(x_in, x_out), max(x_in, x_out)
        # Cunas metálicas en V que sujetan los troncos.
        for k, cx in enumerate((lo + 0.12, hi - 0.12)):
            # Perfil en U (ancho en Y, alto en Z) dibujado en XY y puesto de canto: X→Y, Y→Z, extrusión en X.
            profile = [(-0.27, 0.0), (0.27, 0.0), (0.27, 0.18), (0.24, 0.18), (0.24, 0.04), (-0.24, 0.04),
                       (-0.24, 0.18), (-0.27, 0.18)]
            cradle = slab(profile, -0.025, 0.025)
            to_yz = Matrix(((0, 0, 1, 0), (1, 0, 0, 0), (0, 1, 0, 0), (0, 0, 0, 1)))
            bmesh.ops.transform(cradle, matrix=Matrix.Translation((cx, mid_y, BODY_TOP - 0.005)) @ to_yz, verts=cradle.verts)
            bmesh.ops.recalc_face_normals(cradle, faces=cradle.faces)
            finish("cradle_%s_%d" % (side, k), cradle, METAL_DARK, root, mat, 0.006)
        for (ly, row) in slots:
            z = BODY_TOP + 0.035 + log_r + row * (log_r * 1.73)
            log_along_x(lo + 0.03, hi - 0.03, mid_y + ly, z, log_r, root, mat, "store_log_%d" % index)
            index += 1

    # --- Borne del cable: en una ménsula detrás del ala este, por debajo de la bandeja (César) ---
    bx, by = 1.1, -0.37
    finish("cable_bracket", box((0.14, 0.16, 0.05), (bx, -0.325, 0.3)), METAL_DARK, root, mat, 0.008)
    for dx in (-0.045, 0.045):
        finish("cable_bracket_bolt_%d" % (dx > 0), hex_rivet((bx + dx, -0.255, 0.27), (0, -1, 0), r=0.014),
               METAL_DEEP, root, mat, 0.0)
    finish("cable_post", box((0.06, 0.06, 0.08), (bx, by, 0.365)), METAL, root, mat, 0.008)
    finish("cable_insulator", prism(6, 0.055, 0.042, 0.4, 0.48, x=bx, y=by), GLASS, root, mat, 0.008)
    empty("cable_anchor", (bx, by, 0.48), root)

    tris = 0
    for child in root.children_recursive:
        if child.type == "MESH":
            tris += sum(len(p.vertices) - 2 for p in child.data.polygons)
    print("talador: piezas:", len(root.children_recursive), "triángulos:", tris)


build()
