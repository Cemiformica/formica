# Poste eléctrico (B3.7). 1×1, admite 4 cables. Se fabrica en la isla, así que va en el estilo
# rudimentario de Isla Alba (guía de arte §2): madera, piedra y arcilla, no los grises del Nexo.
# Forma: base de piedra con dos cuñas que calzan el palo; palo de madera desbastado (6 lados) con dos
# atados de fibra; cruceta corta con dos tornapuntas; arriba, un aislante de arcilla cocida con una
# vuelta de hilo de cobre (el poste cuesta un lingote de cobre, D-089: lo que pagas se ve).
# Convenciones: norte = +Y, este = +X, origen en el centro de la casilla a ras de suelo, todo dentro de
# x, y ∈ [−0,5, 0,5]. Sin puertos.
#
# Nodos para Godot: cable_insulator (aislante y su hilo: se ilumina en verde con cable) y cable_anchor
# (punta del aislante: ahí se juntan todos los cables).
#
# Uso: Editor de texto de Blender → abrir → Alt+P. Si ya existe «power_pole», lo borra y lo rehace.
# Dónde tocar: las medidas están en build(); cada pieza dice su color como (fila, columna).

import bpy
import bmesh
import math
from mathutils import Matrix, Vector

PALETTE = 64
SWATCH = 8
ROOT = "power_pole"
TEXTURE = "//../../assets/textures/palette.png"

# Colores (fila, columna) de palette.png
WOOD, WOOD_DARK, WOOD_END = (0, 3), (0, 4), (0, 2)
STONE, STONE_DARK, STONE_LIGHT = (1, 4), (1, 5), (1, 3)
FIBER, FIBER_DARK = (1, 1), (1, 2)
CLAY = (4, 4)            # arcilla cocida oscura: así destaca el hilo de cobre
COPPER = (3, 1)          # cobre anaranjado brillante

POST_TOP = 2.2           # altura de la punta del palo
INSULATOR_TOP = 2.42     # punta del aislante: ahí se enganchan los cables (por encima de la cabeza: 1,8 m)


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


def paint(bm: bmesh.types.BMesh, color: tuple, faces=None) -> None:
    uv = bm.loops.layers.uv.get("UVMap") or bm.loops.layers.uv.new("UVMap")
    target = swatch_uv(*color)
    for f in (faces if faces is not None else bm.faces):
        for loop in f.loops:
            loop[uv].uv = target


def finish(name: str, bm: bmesh.types.BMesh, color, parent, material, bevel: float = 0.015,
           segments: int = 2, painted: bool = False):
    # Bisel primero, color después (guía). Biseles de hasta 1,2 cm: un solo segmento.
    if bevel <= 0.012:
        segments = 1
    if bevel > 0.0:
        bmesh.ops.bevel(bm, geom=list(bm.edges), offset=bevel, segments=segments, affect="EDGES",
                        profile=0.5, clamp_overlap=True)
    if not painted:
        paint(bm, color)
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


def box(size, center) -> bmesh.types.BMesh:
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
    bmesh.ops.translate(bm, vec=Vector(center), verts=bm.verts)
    return bm


def prism(sides: int, r_bottom: float, r_top: float, z0: float, z1: float, x=0.0, y=0.0,
          angle: float = 0.0, bm: bmesh.types.BMesh = None):
    # Prisma o tronco de n lados entre z0 y z1. Con angle = 0, un vértice apunta a +X. Si se pasa `bm`,
    # se añade a esa malla y devuelve sus caras nuevas (para pintarlas aparte).
    target = bm if bm is not None else bmesh.new()
    bottom, top = [], []
    for i in range(sides):
        a = angle + 2.0 * math.pi * i / sides
        bottom.append(target.verts.new((x + r_bottom * math.cos(a), y + r_bottom * math.sin(a), z0)))
        top.append(target.verts.new((x + r_top * math.cos(a), y + r_top * math.sin(a), z1)))
    faces = [target.faces.new(list(reversed(bottom))), target.faces.new(top)]
    for i in range(sides):
        j = (i + 1) % sides
        faces.append(target.faces.new((bottom[i], bottom[j], top[j], top[i])))
    bmesh.ops.recalc_face_normals(target, faces=faces)
    return faces if bm is not None else target


def strut(p0, p1, thick: float) -> bmesh.types.BMesh:
    # Barra de sección cuadrada de p0 a p1.
    p0, p1 = Vector(p0), Vector(p1)
    d = p1 - p0
    bm = box((thick, thick, d.length), (0.0, 0.0, d.length / 2))
    rot = Vector((0.0, 0.0, 1.0)).rotation_difference(d.normalized()).to_matrix().to_4x4()
    bmesh.ops.transform(bm, matrix=Matrix.Translation(p0) @ rot, verts=bm.verts)
    return bm


def clear_previous() -> None:
    root = bpy.data.objects.get(ROOT)
    if root is None:
        return
    for obj in list(root.children_recursive) + [root]:
        data = obj.data
        bpy.data.objects.remove(obj, do_unlink=True)
        if data is not None and data.users == 0:
            bpy.data.meshes.remove(data)


def empty(name: str, location, parent, kind: str = "SPHERE", size: float = 0.03):
    obj = bpy.data.objects.new(name, None)
    obj.empty_display_type = kind
    obj.empty_display_size = size
    obj.location = location
    obj.parent = parent
    bpy.context.collection.objects.link(obj)
    return obj


def build() -> None:
    clear_previous()
    mat = get_material()
    root = empty(ROOT, (0, 0, 0), None, "PLAIN_AXES", 0.3)
    HEX = math.radians(30)

    # --- Base de piedra: bloque bajo con una losa encima y dos cuñas calzando el palo ---
    finish("base_stone", prism(6, 0.3, 0.26, 0.0, 0.28, angle=HEX), STONE, root, mat, 0.012)
    finish("base_cap", prism(6, 0.22, 0.2, 0.28, 0.34, angle=HEX), STONE_DARK, root, mat, 0.01)
    for i, a in enumerate((0.4, 0.4 + math.pi)):
        cx, cy = 0.13 * math.cos(a), 0.13 * math.sin(a)
        wedge = box((0.09, 0.07, 0.14), (0.0, 0.0, 0.0))
        bmesh.ops.rotate(wedge, cent=(0, 0, 0), matrix=Matrix.Rotation(math.radians(-18), 3, "Y"), verts=wedge.verts)
        bmesh.ops.rotate(wedge, cent=(0, 0, 0), matrix=Matrix.Rotation(a, 3, "Z"), verts=wedge.verts)
        bmesh.ops.translate(wedge, vec=(cx, cy, 0.4), verts=wedge.verts)
        finish("wedge_%d" % i, wedge, STONE_LIGHT, root, mat, 0.01)

    # --- Palo de madera desbastado (6 lados), un poco más fino arriba ---
    finish("post", prism(6, 0.085, 0.07, 0.28, POST_TOP), WOOD, root, mat, 0.012)
    finish("post_top", prism(6, 0.075, 0.06, POST_TOP, POST_TOP + 0.03), WOOD_END, root, mat, 0.008)
    # Atados de fibra (dos tonos), como refuerzo del palo.
    for i, (z, color) in enumerate(((0.62, FIBER), (1.55, FIBER_DARK))):
        finish("lashing_%d" % i, prism(6, 0.095, 0.095, z - 0.04, z + 0.04), color, root, mat, 0.008)

    # --- Cruceta corta (este-oeste) con dos tornapuntas ---
    arm_z = 1.98
    finish("crossarm", box((0.62, 0.08, 0.08), (0.0, 0.0, arm_z)), WOOD_DARK, root, mat, 0.012)
    for i, sx in enumerate((-1, 1)):
        finish("arm_brace_%d" % i, strut((sx * 0.06, 0.0, arm_z - 0.36), (sx * 0.24, 0.0, arm_z - 0.04), 0.04),
               WOOD_DARK, root, mat, 0.008)
        # Clavija de madera en cada punta de la cruceta (silueta de poste de telégrafo).
        finish("arm_peg_%d" % i, prism(6, 0.025, 0.02, arm_z + 0.04, arm_z + 0.12, x=sx * 0.26), WOOD_END, root, mat, 0.0)

    # --- Aislante de arcilla cocida con una vuelta de hilo de cobre (una sola malla: se ilumina entera) ---
    bm = bmesh.new()
    z0 = POST_TOP + 0.03
    clay = []
    clay += prism(8, 0.05, 0.05, z0, z0 + 0.05, bm=bm)                    # cuello sobre el palo
    clay += prism(8, 0.11, 0.07, z0 + 0.05, z0 + 0.09, bm=bm)             # campana de abajo
    clay += prism(8, 0.06, 0.06, z0 + 0.09, z0 + 0.12, bm=bm)
    clay += prism(8, 0.09, 0.055, z0 + 0.12, z0 + 0.15, bm=bm)            # campana de arriba
    clay += prism(8, 0.045, 0.04, z0 + 0.15, INSULATOR_TOP, bm=bm)        # punta
    wire = prism(8, 0.075, 0.075, z0 + 0.093, z0 + 0.117, bm=bm)          # vuelta de hilo de cobre
    paint(bm, CLAY, clay)
    paint(bm, COPPER, wire)
    finish("cable_insulator", bm, None, root, mat, 0.0, painted=True)
    empty("cable_anchor", (0.0, 0.0, INSULATOR_TOP), root)

    tris = 0
    for child in root.children_recursive:
        if child.type == "MESH":
            tris += sum(len(p.vertices) - 2 for p in child.data.polygons)
    print("piezas:", len(root.children), "triángulos:", tris)


build()
