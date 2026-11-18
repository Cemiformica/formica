# Caja logística (B3.7, D-093), versión 3: CÁMARA DE HORMIGUERO de una pieza (César). 1×2.
# Como el almacén del extractor: abajo, una caja metálica rígida de la altura del marco de los puertos
# (0,62 m), sin patas, con base oscura, franja naranja y reborde; encima, el caparazón de hormiga (segmentos
# oscuros abombados con anillos naranjas) y las antenas con las luces de estado. Mirillas hundidas que se
# llenan y el emblema pintado en los costados de la casilla de atrás.
# La caja es la PROPIA cámara (ya no hay túnel): ocupa las dos casillas y queda a ras de los dos puertos.
# Tiene TRES versiones y Godot enseña solo la de la salida elegida con F (los nodos conservan los nombres
# tunnel_straight / tunnel_right / tunnel_left, que ya usa el código): recta (caja entera, a ras del puerto
# norte) y derecha / izquierda (en la casilla de delante, la caja se retira del lado del puerto lateral
# hasta su cara trasera y se alarga hacia el norte hasta cubrirla: «mordisco», elección de César).
# Puertos (los pone Godot): entrada al SUR de la casilla de atrás; salida al NORTE, ESTE u OESTE de la
# casilla de delante. Nada entra en el borde de un puerto (marco: 0,265 m desde el borde).
# Convenciones: sin girar, la salida recta mira al NORTE (+Y en Blender). Origen en el centro de la
# huella, a ras de suelo. Huella: x ∈ [−0,5, 0,5], y ∈ [−1, 1]. Altura declarada 1.
#
# Nodos para Godot: tunnel_straight / tunnel_right / tunnel_left (versiones de la cámara: se enseña una),
# status_light_east / status_light_west (puntas de las antenas: verde con sitio, ámbar llena) y
# store_fill_pivot (lo que guarda en las mirillas de atrás) y store_fill_pivot_straight / _right / _left
# (el de las mirillas de delante de cada versión): Godot los escala en vertical y los pinta del color de lo
# que guarda.
#
# Uso: Editor de texto de Blender → abrir → Alt+P. Si ya existe «logistic_box», lo borra y lo rehace.
# Dónde tocar: las medidas están arriba y en build(); cada pieza dice su color como (fila, columna).

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
ROOT = "logistic_box"
TEXTURE = "//../../assets/textures/palette.png"

WOOD, WOOD_DARK, WOOD_END = (0, 3), (0, 4), (0, 2)
METAL_LIGHT, METAL, METAL_DARK, METAL_DEEP = (5, 2), (5, 3), (5, 4), (5, 5)
GLASS = (7, 6)
ACCENT = (4, 2)
ORE = (3, 5)

HALF_X = 0.4                 # semiancho de la caja (el marco del puerto mide 0,8)
BODY_Z0, BODY_Z1 = 0.07, 0.62  # la caja, sobre su base; arriba, a la altura del marco del puerto
END_Y = 0.735                # cara trasera de los puertos norte y sur (1 − 0,265)
SIDE_X = 0.235               # cara trasera de un puerto lateral (0,5 − 0,265)
SIDE_Y0, SIDE_Y1 = 0.1, 0.9  # lo que ocupa a lo largo un puerto lateral (centro 0,5 ± 0,4)
BEND_Y = 0.5                 # centro de la casilla de delante (pivote de las versiones)
WIN_Y, WIN_Z, WIN_W, WIN_H = -0.38, 0.3, 0.34, 0.14   # mirillas en los costados de la casilla de atrás
FRONT_WIN_Y = 0.38           # y las de la casilla de delante (en cada versión, los costados sin puerto)


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



def arch_segment(x0: float, x1: float, half_y: float, z0: float, rise: float, sides: int = 6) -> bmesh.types.BMesh:
    # Segmento de tapa abombada: medio polígono (arco) en el plano YZ, extruido de x0 a x1.
    bm = bmesh.new()
    rings = []
    for x in (x0, x1):
        ring = []
        for i in range(sides + 1):
            a = math.pi * i / sides
            ring.append(bm.verts.new((x, half_y * math.cos(a), z0 + rise * math.sin(a))))
        rings.append(ring)
    for i in range(sides):
        bm.faces.new((rings[0][i], rings[0][i + 1], rings[1][i + 1], rings[1][i]))
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


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



def arch_segment_y(y0: float, y1: float, half_x: float, z0: float, rise: float, sides: int = 6) -> bmesh.types.BMesh:
    # Como arch_segment, pero el arco va en el plano XZ y se extruye a lo largo de Y.
    bm = arch_segment(y0, y1, half_x, z0, rise, sides)
    swap = Matrix(((0, 1, 0, 0), (1, 0, 0, 0), (0, 0, 1, 0), (0, 0, 0, 1)))
    bmesh.ops.transform(bm, matrix=swap, verts=bm.verts)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def outline(turn: int):
    # Planta de la caja (antihoraria). turn: 0 = recta; 1 = salida al este (derecha); −1 = al oeste.
    if turn == 0:
        return [(-HALF_X, -END_Y), (HALF_X, -END_Y), (HALF_X, END_Y), (-HALF_X, END_Y)]
    pts = [(-HALF_X, -END_Y), (HALF_X, -END_Y), (HALF_X, SIDE_Y0), (SIDE_X, SIDE_Y0), (SIDE_X, SIDE_Y1),
           (-HALF_X, SIDE_Y1)]
    if turn < 0:
        pts = [(-x, y) for (x, y) in reversed(pts)]
    return pts


def grow(points, d: float):
    # Agranda `d` una planta de lados rectos (ejes X e Y), esquinas entrantes incluidas.
    out = []
    n = len(points)
    for i in range(n):
        a, b, c = Vector(points[i - 1]), Vector(points[i]), Vector(points[(i + 1) % n])
        e0, e1 = (b - a).normalized(), (c - b).normalized()
        n0, n1 = Vector((e0.y, -e0.x)), Vector((e1.y, -e1.x))
        out.append(tuple(b + (n0 + n1) * d))
    return out


def shell(name: str, y0: float, y1: float, x0: float, x1: float, scale: float, root, mat, ring: bool = False):
    # Segmento de caparazón (o anillo naranja) sobre la caja entre x0 y x1.
    cx, half = (x0 + x1) / 2, (x1 - x0) / 2
    z = BODY_Z1 + 0.045
    if ring:
        bm = arch_segment_y(y0, y1, half + 0.035, z, 0.3 * scale + 0.025)
    else:
        bm = arch_segment_y(y0, y1, (half + 0.02) * (0.9 + 0.1 * scale), z, 0.3 * scale)
    bmesh.ops.translate(bm, vec=(cx, 0.0, 0.0), verts=bm.verts)
    return finish(name, bm, ACCENT if ring else METAL_DEEP, root, mat, 0.006 if ring else 0.012)


def window_parts(tag: str, sx: float, y: float, root, mat) -> list:
    # Marco (arriba y abajo), cristal y dos tornillos de una mirilla hundida.
    parts = []
    for k, dz in enumerate((WIN_H / 2 + 0.015, -WIN_H / 2 - 0.015)):
        parts.append(finish("window_frame_%s_%d" % (tag, k), box((0.02, WIN_W + 0.08, 0.03), (sx * (HALF_X + 0.005), y, WIN_Z + dz)),
                            METAL_DARK, root, mat, 0.004))
    parts.append(finish("store_window_" + tag, box((0.01, WIN_W, WIN_H), (sx * (HALF_X - 0.045), y, WIN_Z)), GLASS, root, mat, 0.0))
    for dy in (-0.25, 0.25):
        parts.append(finish("rivet_%s_%d" % (tag, dy > 0), hex_rivet((sx * (HALF_X + 0.004), y + dy, WIN_Z), (sx, 0, 0), r=0.016),
                            METAL_DEEP, root, mat, 0.0))
    return parts


def build_chamber(name: str, turn: int, root, mat):
    objs = []
    pts = outline(turn)
    body = finish(name + "_body", slab(pts, BODY_Z0, BODY_Z1), METAL, root, mat, 0.02)
    objs.append(body)
    # Base, franja y reborde: sobresalen por los lados y se meten un poco en los marcos de los puertos.
    objs.append(finish(name + "_base", slab(grow(pts, 0.02), 0.0, BODY_Z0 + 0.02), METAL_DEEP, root, mat, 0.01))
    objs.append(finish(name + "_band", slab(grow(pts, 0.01), BODY_Z0 + 0.075, BODY_Z0 + 0.125), ACCENT, root, mat, 0.006))
    objs.append(finish(name + "_rim", slab(grow(pts, 0.02), BODY_Z1 - 0.005, BODY_Z1 + 0.045), METAL_DARK, root, mat, 0.01))
    # Mirillas: las de atrás (comunes, fuera de las versiones) y, en la casilla de delante, una más en cada
    # costado largo (César): en las dos en la recta y solo en el costado sin puerto en las laterales.
    front_sides = (1.0, -1.0) if turn == 0 else (-float(turn),)
    for sx in (1.0, -1.0):
        cut_recess(body, (0.1, WIN_W, WIN_H), (sx * HALF_X, WIN_Y, WIN_Z), METAL_DEEP)
    for sx in front_sides:
        cut_recess(body, (0.1, WIN_W, WIN_H), (sx * HALF_X, FRONT_WIN_Y, WIN_Z), METAL_DEEP)
    suffix = name.split("_")[1]
    fill_pos = Vector((0.0, FRONT_WIN_Y, WIN_Z - WIN_H / 2))
    fill = empty("store_fill_pivot_" + suffix, fill_pos, root, "ARROWS", 0.06)
    objs.append(fill)
    for sx in front_sides:
        tag = "%s_%s" % (suffix, "e" if sx > 0 else "w")
        objs.extend(window_parts(tag, sx, FRONT_WIN_Y, root, mat))
        ore = finish("store_ore_" + tag, box((0.012, WIN_W, WIN_H), (sx * (HALF_X - 0.044), FRONT_WIN_Y, WIN_Z)), ORE, root, mat, 0.0)
        hang(ore, fill, fill_pos)
    # Caparazón: los dos segmentos de atrás son iguales en las tres versiones; delante, dos segmentos a todo
    # lo ancho (recta) o uno más estrecho que deja libre el lado del puerto (laterales).
    segs = [(-END_Y - 0.02, -0.37, 0.8), (-0.33, 0.06, 1.0)]
    rings = [(-0.38, -0.32), (0.05, 0.11)]
    x0, x1 = -HALF_X, HALF_X
    if turn == 0:
        segs += [(0.1, 0.42, 1.0), (0.46, END_Y + 0.02, 0.75)]
        rings.append((0.41, 0.47))
    else:
        segs.append((0.1, SIDE_Y1 + 0.02, 0.85))
    for k, (y0, y1, scale) in enumerate(segs):
        if turn != 0 and y0 >= 0.1:
            x0, x1 = (-HALF_X, SIDE_X) if turn > 0 else (-SIDE_X, HALF_X)
        objs.append(shell("%s_shell_%d" % (name, k), y0, y1, x0, x1, scale, root, mat))
    for k, (y0, y1) in enumerate(rings):
        objs.append(shell("%s_ring_%d" % (name, k), y0, y1, -HALF_X, HALF_X, 1.0, root, mat, ring=True))
    return objs


def build() -> None:
    clear_previous()
    mat = get_material()
    root = empty(ROOT, (0, 0, 0), None, "PLAIN_AXES", 0.3)

    # --- Cámara: tres versiones (recta, derecha, izquierda); Godot enseña la de la salida elegida ---
    for name, turn in (("tunnel_straight", 0), ("tunnel_right", 1), ("tunnel_left", -1)):
        pivot_pos = Vector((0.0, BEND_Y, 0.0))
        pivot = empty(name, pivot_pos, root, "PLAIN_AXES", 0.1)
        for obj in build_chamber(name, turn, root, mat):
            hang(obj, pivot, pivot_pos)

    # --- Mirillas hundidas en los costados de la casilla de atrás, con lo que guarda dentro ---
    for side, sx in (("east", 1.0), ("west", -1.0)):
        window_parts(side, sx, WIN_Y, root, mat)
    fill_pos = Vector((0.0, WIN_Y, WIN_Z - WIN_H / 2))
    fill = empty("store_fill_pivot", fill_pos, root, "ARROWS", 0.08)
    for side, sx in (("east", 1.0), ("west", -1.0)):
        ore = finish("store_ore_" + side, box((0.012, WIN_W, WIN_H), (sx * (HALF_X - 0.044), WIN_Y, WIN_Z)), ORE, root, mat, 0.0)
        hang(ore, fill, fill_pos)

    # --- Emblema de la colonia pintado, entre la mirilla y el reborde (como en el extractor) ---
    for side, sx in (("east", 1.0), ("west", -1.0)):
        crest.add_crest(finish, root, mat, (sx * HALF_X, WIN_Y, 0.5), (sx, 0.0, 0.0), scale=0.5, style="painted",
                        prefix="crest_" + side)

    # --- Antenas sobre el segmento grande del caparazón, con la luz de estado en la punta ---
    for side, sx in (("east", 1.0), ("west", -1.0)):
        p0 = Vector((sx * 0.12, -0.15, 0.98))
        p1 = Vector((sx * 0.2, -0.05, 1.12))
        p2 = Vector((sx * 0.3, 0.07, 1.18))
        finish("antenna_%s_socket" % side, prism(6, 0.04, 0.032, p0.z - 0.05, p0.z + 0.01, x=p0.x, y=p0.y), METAL_DEEP, root, mat, 0.0)
        finish("antenna_%s_0" % side, strut(p0, p1, 0.03, 6), METAL_DARK, root, mat, 0.0)
        finish("antenna_%s_1" % side, strut(p1, p2, 0.026, 6), METAL_DARK, root, mat, 0.0)
        finish("antenna_%s_joint" % side, prism(6, 0.026, 0.026, p1.z - 0.02, p1.z + 0.02, x=p1.x, y=p1.y), ACCENT, root, mat, 0.0)
        finish("status_light_" + side, prism(6, 0.04, 0.028, p2.z - 0.015, p2.z + 0.05, x=p2.x, y=p2.y), GLASS, root, mat, 0.006)

    tris = 0
    for child in root.children_recursive:
        if child.type == "MESH":
            tris += sum(len(p.vertices) - 2 for p in child.data.polygons)
    print("caja logística: piezas:", len(root.children_recursive), "triángulos:", tris)


build()
