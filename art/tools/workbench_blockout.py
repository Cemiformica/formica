# Banco de trabajo (B3.7, D-095). 2×1, sin energía: Mira fabrica a mano. Mesa de taller de madera con los
# cantos reforzados con fleje y remaches hexagonales, sobre seis patitas de hormiga (la familia del arcón y la
# caja). Encima, una DEVANADORA DE BOBINAS con manivela (cuenta para qué sirve: lingote → hilo → bobina) y
# un tornillo de banco; al fondo, un panel de herramientas con agujeros hexagonales; abajo, una balda con
# lingotes de cobre. Frente (lo que mira al jugador): el SUR (−Y en Blender).
# Convenciones: origen en el centro de la huella, a ras de suelo. Huella: x ∈ [−1, 1], y ∈ [−0,5, 0,5].
# Altura 2.
#
# Nodos para Godot: work_lamp (bombilla del flexo del Nexo: se enciende mientras fabrica), lamp_light (vacío donde va su foco), crank_pivot (manivela: gira en X mientras fabrica), spool_pivot (carrete: gira en X) y,
# dentro, coil_fill_pivot (el hilo enrollado: se escala en Y y Z según el progreso, «la bobina crece»).
#
# Uso: Editor de texto de Blender → abrir → Alt+P. Si ya existe «workbench», lo borra y lo rehace.
# Dónde tocar: las medidas están en las constantes y en build(); cada pieza dice su color como (fila, columna).

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
ROOT = "workbench"
TEXTURE = "//../../assets/textures/palette.png"

WOOD, WOOD_DARK, WOOD_END = (0, 3), (0, 4), (0, 2)
STONE, STONE_DARK = (1, 3), (1, 5)
COPPER, COPPER_DARK = (3, 1), (3, 2)
METAL_LIGHT, METAL, METAL_DARK, METAL_DEEP = (5, 2), (5, 3), (5, 4), (5, 5)
ACCENT = (4, 2)
GLASS = (7, 6)

TOP_Z = 0.86          # altura del tablero
HALF_X, HALF_Y = 0.9, 0.4
SPOOL_X, SPOOL_Y = 0.25, -0.02   # devanadora
SPOOL_Z = TOP_Z + 0.22


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



def ring_x(x0: float, x1: float, r_out: float, r_in: float, sides: int, z: float) -> bmesh.types.BMesh:
    # Aro poligonal en el plano YZ (centrado en el eje), de x0 a x1.
    bm = bmesh.new()
    loops = []
    for x in (x0, x1):
        outer = [bm.verts.new((x, r_out * math.cos(2 * math.pi * i / sides), z + r_out * math.sin(2 * math.pi * i / sides))) for i in range(sides)]
        inner = [bm.verts.new((x, r_in * math.cos(2 * math.pi * i / sides), z + r_in * math.sin(2 * math.pi * i / sides))) for i in range(sides)]
        loops.append((outer, inner))
    (o0, i0), (o1, i1) = loops
    for k in range(sides):
        j = (k + 1) % sides
        bm.faces.new((o0[k], o0[j], o1[j], o1[k]))
        bm.faces.new((i0[k], i1[k], i1[j], i0[j]))
        bm.faces.new((o0[k], i0[k], i0[j], o0[j]))
        bm.faces.new((o1[k], o1[j], i1[j], i1[k]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def cylinder_x(x0: float, x1: float, r: float, sides: int, y: float, z: float) -> bmesh.types.BMesh:
    bm = prism(sides, r, r, x0, x1)
    rot = Matrix.Rotation(math.radians(90), 4, "Y")
    # prism va de x0 a x1 en Z; girado 90° en Y, ese Z pasa a +X.
    bmesh.ops.transform(bm, matrix=Matrix.Translation((0.0, y, z)) @ rot, verts=bm.verts)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm



def build() -> None:
    clear_previous()
    mat = get_material()
    root = empty(ROOT, (0, 0, 0), None, "PLAIN_AXES", 0.3)

    # --- Seis patitas de hormiga (como el arcón) ---
    leg_top = TOP_Z - 0.1
    for i, x in enumerate((-0.72, 0.0, 0.72)):
        for side, sy in (("s", -1.0), ("n", 1.0)):
            hip = Vector((x, sy * (HALF_Y - 0.08), leg_top))
            knee = Vector((x + 0.05 * (1 if x >= 0 else -1), sy * 0.46, 0.5))
            foot = Vector((knee.x + 0.03 * (1 if x >= 0 else -1), sy * 0.44, 0.03))
            finish("leg_thigh_%d_%s" % (i, side), strut(hip, knee, 0.06, 6), METAL_DARK, root, mat, 0.0)
            finish("leg_shin_%d_%s" % (i, side), strut(knee, foot, 0.055, 6), METAL_DARK, root, mat, 0.0)
            finish("leg_knee_%d_%s" % (i, side), prism(6, 0.045, 0.045, knee.z - 0.035, knee.z + 0.035, x=knee.x, y=knee.y), ACCENT, root, mat, 0.0)
            finish("leg_foot_%d_%s" % (i, side), prism(6, 0.045, 0.04, 0.0, 0.04, x=foot.x, y=foot.y), METAL_DEEP, root, mat, 0.0)

    # --- Armazón, balda y tablero ---
    finish("apron", box((2 * HALF_X - 0.08, 2 * HALF_Y - 0.08, 0.12), (0.0, 0.0, TOP_Z - 0.1)), WOOD_DARK, root, mat, 0.012)
    finish("shelf", box((2 * HALF_X - 0.2, 2 * HALF_Y - 0.14, 0.04), (0.0, 0.0, 0.3)), WOOD_DARK, root, mat, 0.008)
    for k, x in enumerate((-0.82, 0.82)):
        finish("shelf_rail_%d" % k, box((0.05, 2 * HALF_Y - 0.12, 0.05), (x, 0.0, 0.3)), METAL_DARK, root, mat, 0.0)
    # Travesaños de la balda a cada pata (César: la balda parecía flotar), con un tornillo en la pata.
    for i, x in enumerate((-0.72, 0.0, 0.72)):
        for side, sy in (("s", -1.0), ("n", 1.0)):
            knee = Vector((x + 0.05 * (1 if x >= 0 else -1), sy * 0.46, 0.5))
            foot = Vector((knee.x + 0.03 * (1 if x >= 0 else -1), sy * 0.44, 0.03))
            t = (knee.z - 0.3) / (knee.z - foot.z)
            on_leg = knee.lerp(foot, t)
            finish("shelf_brace_%d_%s" % (i, side), strut((on_leg.x, sy * (HALF_Y - 0.08), 0.3), (on_leg.x, on_leg.y, 0.3), 0.04, 6),
                   METAL_DARK, root, mat, 0.0)
            finish("shelf_bolt_%d_%s" % (i, side), hex_rivet((on_leg.x, on_leg.y + sy * 0.03, 0.3), (0, sy, 0), r=0.02, depth=0.025),
                   ACCENT, root, mat, 0.0)
    # Travesaños a lo largo de los lados largos de la balda (norte y sur), de pata a pata.
    for side, sy in (("s", -1.0), ("n", 1.0)):
        finish("shelf_long_rail_%s" % side, box((2 * HALF_X - 0.2, 0.04, 0.05), (0.0, sy * (HALF_Y - 0.06), 0.3)), METAL_DARK, root, mat, 0.0)
        for x in (-0.4, 0.4):
            finish("shelf_long_rivet_%s_%d" % (side, int((x + 1) * 100)), hex_rivet((x, sy * (HALF_Y - 0.04), 0.3), (0, sy, 0), r=0.013),
                   METAL_DEEP, root, mat, 0.0)
    # Lingotes de cobre en la balda (decoración: de ahí sale el hilo).
    for k, (x, y) in enumerate(((-0.4, -0.08), (-0.22, -0.08), (-0.31, 0.1))):
        ingot = prism(4, 0.09, 0.07, 0.32, 0.37, x=x, y=y, angle=math.radians(45))
        bmesh.ops.scale(ingot, vec=(1.0, 0.55, 1.0), space=Matrix.Translation((-x, -y, 0.0)), verts=ingot.verts)
        finish("ingot_%d" % k, ingot, COPPER, root, mat, 0.0)
    finish("top", box((2 * HALF_X, 2 * HALF_Y, 0.08), (0.0, 0.0, TOP_Z - 0.04)), WOOD, root, mat, 0.012)
    for k, y in enumerate((-0.13, 0.13)):
        finish("top_joint_%d" % k, box((2 * HALF_X - 0.02, 0.012, 0.012), (0.0, y, TOP_Z + 0.001)), WOOD_DARK, root, mat, 0.0)
    # Cantos reforzados con fleje y remaches.
    for side, sy in (("s", -1.0), ("n", 1.0)):
        finish("edge_strap_%s" % side, box((2 * HALF_X + 0.01, 0.025, 0.06), (0.0, sy * (HALF_Y + 0.008), TOP_Z - 0.04)), METAL_DARK, root, mat, 0.006)
        for x in (-0.75, -0.25, 0.25, 0.75):
            finish("edge_rivet_%s_%d" % (side, int((x + 1) * 100)), hex_rivet((x, sy * (HALF_Y + 0.022), TOP_Z - 0.04), (0, sy, 0), r=0.014),
                   METAL_DEEP, root, mat, 0.0)
    for side, sx in (("e", 1.0), ("w", -1.0)):
        finish("edge_cap_%s" % side, box((0.025, 2 * HALF_Y + 0.04, 0.06), (sx * (HALF_X + 0.008), 0.0, TOP_Z - 0.04)), METAL_DARK, root, mat, 0.006)

    # --- Panel de herramientas al fondo (norte), con agujeros hexagonales y dos herramientas ---
    for k, x in enumerate((-0.82, 0.82)):
        finish("board_post_%d" % k, box((0.06, 0.06, 0.92), (x, HALF_Y - 0.05, TOP_Z + 0.46)), WOOD_DARK, root, mat, 0.008)
    finish("pegboard", box((1.58, 0.04, 0.62), (0.0, HALF_Y - 0.05, TOP_Z + 0.5)), WOOD, root, mat, 0.008)
    finish("pegboard_cap", box((1.72, 0.08, 0.05), (0.0, HALF_Y - 0.05, TOP_Z + 0.94)), METAL_DARK, root, mat, 0.008)
    for x in (-0.7, -0.4, 0.4, 0.7):
        finish("cap_rivet_%d" % int((x + 1) * 100), hex_rivet((x, HALF_Y - 0.09, TOP_Z + 0.94), (0, -1, 0), r=0.014), METAL_DEEP, root, mat, 0.0)
    # Emblema de la colonia INTEGRADO en el remate (César: que forme parte de la barra y tenga protagonismo):
    # versión «placa» de la pieza común crest.py, con el marco hundido en la barra.
    crest.add_crest(finish, root, mat, (0.0, HALF_Y - 0.05, TOP_Z + 0.94), (0.0, -1.0, 0.0), scale=1.0,
                    style="plate", frame_depth=0.06, embed=0.04)
    for r_i, z in enumerate((TOP_Z + 0.3, TOP_Z + 0.5, TOP_Z + 0.7)):
        for c_i, x in enumerate((-0.6, -0.36, 0.36, 0.6)):
            hole = prism(6, 0.025, 0.025, 0.0, 0.012, angle=math.radians(30))
            bmesh.ops.transform(hole, matrix=Matrix.Translation((x, HALF_Y - 0.075, z)) @ Matrix.Rotation(math.radians(90), 4, "X"), verts=hole.verts)
            finish("peg_hole_%d_%d" % (r_i, c_i), hole, METAL_DEEP, root, mat, 0.0)
    # Martillo (mango y cabeza hexagonal) y llave colgados en el centro.
    finish("hammer_handle", box((0.03, 0.025, 0.34), (-0.12, HALF_Y - 0.09, TOP_Z + 0.48)), WOOD_DARK, root, mat, 0.0)
    head = prism(6, 0.035, 0.035, -0.08, 0.08, angle=math.radians(30))
    bmesh.ops.transform(head, matrix=Matrix.Translation((-0.12, HALF_Y - 0.1, TOP_Z + 0.66)) @ Matrix.Rotation(math.radians(90), 4, "Y"), verts=head.verts)
    finish("hammer_head", head, METAL, root, mat, 0.0)
    finish("wrench_bar", box((0.035, 0.02, 0.3), (0.1, HALF_Y - 0.09, TOP_Z + 0.5)), METAL_LIGHT, root, mat, 0.0)
    jaw = ring_x(-0.01, 0.01, 0.05, 0.025, 6, 0.0)
    bmesh.ops.transform(jaw, matrix=Matrix.Translation((0.1, HALF_Y - 0.09, TOP_Z + 0.68)) @ Matrix.Rotation(math.radians(90), 4, "Z"), verts=jaw.verts)
    finish("wrench_ring", jaw, METAL_LIGHT, root, mat, 0.0)

    # --- Tornillo de banco en la esquina suroeste ---
    vx, vy = -0.65, -HALF_Y + 0.08
    finish("vise_base", box((0.2, 0.16, 0.06), (vx, vy + 0.04, TOP_Z + 0.03)), METAL_DARK, root, mat, 0.008)
    finish("vise_jaw_back", box((0.2, 0.05, 0.12), (vx, vy + 0.1, TOP_Z + 0.12)), METAL, root, mat, 0.008)
    finish("vise_jaw_front", box((0.2, 0.05, 0.12), (vx, vy - 0.02, TOP_Z + 0.12)), METAL, root, mat, 0.008)
    finish("vise_screw", strut((vx, vy - 0.04, TOP_Z + 0.1), (vx, vy - 0.18, TOP_Z + 0.1), 0.025, 6), METAL_LIGHT, root, mat, 0.0)
    finish("vise_handle", strut((vx - 0.09, vy - 0.18, TOP_Z + 0.1), (vx + 0.09, vy - 0.18, TOP_Z + 0.1), 0.02, 6), ACCENT, root, mat, 0.0)

    # --- Devanadora de bobinas con manivela ---
    for k, dx in enumerate((-0.16, 0.16)):
        finish("winder_post_%d" % k, box((0.04, 0.1, 0.26), (SPOOL_X + dx, SPOOL_Y, TOP_Z + 0.13)), METAL_DARK, root, mat, 0.006)
    finish("winder_base", box((0.42, 0.16, 0.04), (SPOOL_X, SPOOL_Y, TOP_Z + 0.02)), METAL, root, mat, 0.006)
    spool_pos = Vector((SPOOL_X, SPOOL_Y, SPOOL_Z))
    spool = empty("spool_pivot", spool_pos, root, "ARROWS", 0.12)
    parts = [finish("spool_axle", cylinder_x(SPOOL_X - 0.2, SPOOL_X + 0.2, 0.018, 6, SPOOL_Y, SPOOL_Z), METAL_LIGHT, root, mat, 0.0)]
    for k, dx in enumerate((-0.1, 0.1)):
        parts.append(finish("spool_flange_%d" % k, cylinder_x(SPOOL_X + dx - 0.012, SPOOL_X + dx + 0.012, 0.11, 6, SPOOL_Y, SPOOL_Z), ACCENT, root, mat, 0.0))
    parts.append(finish("spool_core", cylinder_x(SPOOL_X - 0.09, SPOOL_X + 0.09, 0.04, 6, SPOOL_Y, SPOOL_Z), WOOD_DARK, root, mat, 0.0))
    for obj in parts:
        hang(obj, spool, spool_pos)
    fill = empty("coil_fill_pivot", spool_pos, spool, "SPHERE", 0.05)
    fill.matrix_parent_inverse = Matrix.Translation(spool_pos).inverted()
    hang(finish("coil_fill", cylinder_x(SPOOL_X - 0.088, SPOOL_X + 0.088, 0.09, 8, SPOOL_Y, SPOOL_Z), COPPER, root, mat, 0.0), fill, spool_pos)
    # Manivela al este, con su puño.
    crank_pos = Vector((SPOOL_X + 0.2, SPOOL_Y, SPOOL_Z))
    crank = empty("crank_pivot", crank_pos, root, "ARROWS", 0.08)
    for obj in (
        finish("crank_arm", box((0.025, 0.03, 0.16), (SPOOL_X + 0.21, SPOOL_Y, SPOOL_Z - 0.07)), METAL, root, mat, 0.0),
        finish("crank_grip", cylinder_x(SPOOL_X + 0.22, SPOOL_X + 0.3, 0.02, 6, SPOOL_Y, SPOOL_Z - 0.14), ACCENT, root, mat, 0.0),
    ):
        hang(obj, crank, crank_pos)
    # Flexo del Nexo sobre la devanadora: brazo articulado desde el poste del este y pantalla hexagonal.
    lamp = Vector((SPOOL_X + 0.05, SPOOL_Y + 0.04, TOP_Z + 0.62))
    elbow = Vector((0.62, HALF_Y - 0.12, TOP_Z + 0.88))
    finish("lamp_arm_0", strut((0.79, HALF_Y - 0.05, TOP_Z + 0.82), elbow, 0.025, 6), METAL_DARK, root, mat, 0.0)
    finish("lamp_arm_1", strut(elbow, lamp + Vector((0.0, 0.0, 0.1)), 0.022, 6), METAL_DARK, root, mat, 0.0)
    finish("lamp_joint", prism(6, 0.03, 0.03, elbow.z - 0.025, elbow.z + 0.025, x=elbow.x, y=elbow.y), ACCENT, root, mat, 0.0)
    finish("lamp_shade", prism(6, 0.1, 0.045, lamp.z, lamp.z + 0.1, x=lamp.x, y=lamp.y, angle=math.radians(30)), METAL, root, mat, 0.006)
    finish("work_lamp", prism(6, 0.05, 0.05, lamp.z - 0.02, lamp.z + 0.01, x=lamp.x, y=lamp.y, angle=math.radians(30)), GLASS, root, mat, 0.0)
    # Luz propia del flexo: Godot pone aquí un foco cálido que apunta hacia abajo (−Z) mientras fabrica.
    empty("lamp_light", (lamp.x, lamp.y, lamp.z - 0.03), root, "SINGLE_ARROW", 0.15).rotation_euler = (math.radians(180), 0.0, 0.0)

    # Hilo de cobre que llega desde una bobina de alimentación (fija) en la mesa.
    finish("feed_reel", cylinder_x(-0.15, -0.05, 0.07, 8, SPOOL_Y + 0.12, TOP_Z + 0.07), COPPER_DARK, root, mat, 0.0)
    finish("feed_wire", strut((-0.05, SPOOL_Y + 0.12, TOP_Z + 0.1), (SPOOL_X - 0.05, SPOOL_Y, SPOOL_Z + 0.08), 0.01, 4), COPPER, root, mat, 0.0)

    tris = 0
    for child in root.children_recursive:
        if child.type == "MESH":
            tris += sum(len(p.vertices) - 2 for p in child.data.polygons)
    print("banco: piezas:", len(root.children_recursive), "triángulos:", tris)


build()
