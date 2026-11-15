# Caja logística (B3.7, D-093), versión 2: GALERÍA DE HORMIGUERO (César). 1×2.
# Atrás, la CÁMARA de almacén (el abdomen: ancho, con caparazón y anillos naranjas, mirillas que se llenan y
# antenas con las luces de estado). Delante, un TÚNEL de sección hexagonal con anillos naranjas, como los
# segmentos de una hormiga, que sale de la cámara y llega a la salida. El túnel tiene TRES versiones, y
# Godot enseña solo la de la salida elegida con F: recta (sigue al norte), derecha (codo al este) e
# izquierda (codo al oeste). Cada una acaba en un collarín que se abre justo hasta el marco de su puerto.
# Puertos (los pone Godot): entrada al SUR de la casilla de atrás; salida al NORTE, ESTE u OESTE de la
# casilla de delante. Como en cada modo solo hay UN puerto de salida, cada versión del túnel puede usar
# los bordes de los otros dos lados; nunca entra en el borde de su propio puerto (marco: 0,25 m).
# Convenciones: sin girar, la salida recta mira al NORTE (+Y en Blender). Origen en el centro de la
# huella, a ras de suelo. Huella: x ∈ [−0,5, 0,5], y ∈ [−1, 1]. Altura declarada 1.
#
# Nodos para Godot: tunnel_straight / tunnel_right / tunnel_left (versiones del túnel: se enseña una),
# status_light_east / status_light_west (puntas de las antenas: verde con sitio, ámbar llena) y
# store_fill_pivot (lo que guarda en las mirillas: se escala en vertical y se pinta del color de lo que
# guarda).
#
# Uso: Editor de texto de Blender → abrir → Alt+P. Si ya existe «logistic_box», lo borra y lo rehace.
# Dónde tocar: las medidas están en build(); cada pieza dice su color como (fila, columna).

import bpy
import bmesh
import math
from mathutils import Matrix, Vector

PALETTE = 64
SWATCH = 8
ROOT = "logistic_box"
TEXTURE = "//../../assets/textures/palette.png"

WOOD, WOOD_DARK, WOOD_END = (0, 3), (0, 4), (0, 2)
METAL_LIGHT, METAL, METAL_DARK, METAL_DEEP = (5, 2), (5, 3), (5, 4), (5, 5)
GLASS = (7, 6)
ACCENT = (4, 2)
ORE = (3, 5)

ABD_Y0, ABD_Y1 = -0.75, -0.02   # abdomen (casilla de atrás y un poco de la de delante)
ABD_HALF_X = 0.42
ABD_Z0, ABD_Z1 = 0.07, 0.62    # el abdomen baja por debajo de la boca del puerto de entrada (0,11 m)
# Túnel: hexágono alargado como la boca de los puertos, pero más grande (ancho y alto) y centrado a la
# altura del marco del puerto (0,6 m de alto). El collarín se abre hasta el marco (0,8 × 0,6 m).
TUNNEL_W, TUNNEL_H, TUNNEL_Z = 0.48, 0.44, 0.3   # 0,48: en la casilla de delante cabe sin tocar los bordes
FRAME_W, FRAME_H = 0.8, 0.6
BEND_Y = 0.5          # centro de la casilla de delante: ahí gira el túnel
PORT_PLANE = 0.25     # distancia del borde a la que empieza el marco del puerto
COLLAR = 0.1          # largo del collarín


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


def tunnel_section(scale_w: float = 1.0, scale_h: float = 1.0):
    # Hexágono alargado (u = lateral, v = alto), en el mismo orden para el túnel y para el collarín.
    w, h = TUNNEL_W * scale_w / 2, TUNNEL_H * scale_h / 2
    return [(-w, 0.0), (-w / 2, -h), (w / 2, -h), (w, 0.0), (w / 2, h), (-w / 2, h)]


def frame_section():
    # El mismo orden de 6 puntos, pero sobre el rectángulo del marco del puerto (los del medio quedan en
    # los lados): así el collarín pasa del hexágono del túnel al marco sin retorcerse.
    w, h = FRAME_W / 2, FRAME_H / 2
    return [(-w, 0.0), (-w, -h), (w, -h), (w, 0.0), (w, h), (-w, h)]


def loft(rings, cap_first: bool = False, cap_last: bool = False) -> bmesh.types.BMesh:
    # Une anillos de puntos 3D (mismo número de vértices) con caras; tapa los extremos si se pide.
    bm = bmesh.new()
    verts = [[bm.verts.new(p) for p in ring] for ring in rings]
    n = len(rings[0])
    for a, b in zip(verts, verts[1:]):
        for i in range(n):
            j = (i + 1) % n
            bm.faces.new((a[i], a[j], b[j], b[i]))
    if cap_first:
        bm.faces.new(verts[0])
    if cap_last:
        bm.faces.new(verts[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def build_tunnel(name: str, turn: int, root, mat):
    # turn: 0 = sigue al norte; 1 = codo al este (derecha); −1 = codo al oeste (izquierda).
    # El tramo que sale de la cámara va hacia el norte. Si gira, se aparta hacia el lado contrario al giro
    # (ese borde está libre en ese modo) para que el codo, con inglete a 45°, quepa sin entrar en el borde
    # del puerto; luego un tramo corto hacia el puerto y el collarín hasta el marco.
    objs = []
    y_start = ABD_Y1 - 0.06
    sec = tunnel_section()
    z = TUNNEL_Z
    s_ = float(turn)
    cx = -s_ * 0.2                     # eje del tramo norte (0 si es recta)
    if turn == 0:
        end = 1.0 - PORT_PLANE - COLLAR
        rings = [[(u, y_start, z + v) for (u, v) in sec], [(u, end, z + v) for (u, v) in sec]]
        collar = [[(u, end, z + v) for (u, v) in sec],
                  [(u, 1.0 - PORT_PLANE, z + v) for (u, v) in frame_section()]]
    else:
        end = 0.5 - PORT_PLANE - COLLAR    # distancia al centro donde acaba el tramo lateral
        # Lateral u del tramo norte (x = cx + u) → lateral del tramo hacia el puerto (y = BEND_Y − s·u).
        rings = [[(cx + u, y_start, z + v) for (u, v) in sec],
                 [(cx + u, BEND_Y - s_ * u, z + v) for (u, v) in sec],
                 [(s_ * end, BEND_Y - s_ * u, z + v) for (u, v) in sec]]
        collar = [[(s_ * end, BEND_Y - s_ * u, z + v) for (u, v) in sec],
                  [(s_ * (0.5 - PORT_PLANE), BEND_Y - s_ * u, z + v) for (u, v) in frame_section()]]
    objs.append(finish(name + "_tube", loft(rings, cap_first=True), METAL, root, mat, 0.0))
    objs.append(finish(name + "_collar", loft(collar), METAL_DARK, root, mat, 0.0))
    # Anillos naranjas (los segmentos de la hormiga): un poco más grandes que el túnel.
    big = tunnel_section(1.08, 1.12)
    spots = [(cx, 0.14)]
    if turn == 0:
        spots.append((0.0, end - 0.04))
    for k, (x0, at) in enumerate(spots):
        ring = [[(x0 + u, at - 0.025, z + v) for (u, v) in big], [(x0 + u, at + 0.025, z + v) for (u, v) in big]]
        objs.append(finish("%s_ring_%d" % (name, k), loft(ring, True, True), ACCENT, root, mat, 0.0))
    if turn != 0:
        at = s_ * (end - 0.04)
        ring = [[(at - 0.025, BEND_Y - s_ * u, z + v) for (u, v) in big],
                [(at + 0.025, BEND_Y - s_ * u, z + v) for (u, v) in big]]
        objs.append(finish("%s_ring_1" % name, loft(ring, True, True), ACCENT, root, mat, 0.0))
    return objs


def build() -> None:
    clear_previous()
    mat = get_material()
    root = empty(ROOT, (0, 0, 0), None, "PLAIN_AXES", 0.3)

    # --- Seis patitas, todas bajo el abdomen (lejos de los puertos de la cabeza) ---
    for i, y in enumerate((-0.6, -0.35, -0.1)):
        for side, sx in (("e", 1.0), ("w", -1.0)):
            hip = Vector((sx * (ABD_HALF_X - 0.06), y, ABD_Z0 + 0.04))
            knee = Vector((sx * 0.465, y + 0.04 * (i - 1), ABD_Z0 + 0.12))
            foot = Vector((sx * 0.465, knee.y + 0.04 * (i - 1), 0.03))
            finish("leg_thigh_%d_%s" % (i, side), strut(hip, knee, 0.05, 6), METAL_DARK, root, mat, 0.0)
            finish("leg_shin_%d_%s" % (i, side), strut(knee, foot, 0.045, 6), METAL_DARK, root, mat, 0.0)
            finish("leg_knee_%d_%s" % (i, side), prism(6, 0.038, 0.038, knee.z - 0.028, knee.z + 0.028, x=knee.x, y=knee.y), ACCENT, root, mat, 0.0)
            finish("leg_foot_%d_%s" % (i, side), prism(6, 0.038, 0.034, 0.0, 0.035, x=foot.x, y=foot.y), METAL_DEEP, root, mat, 0.0)

    # --- Abdomen: caja metálica con franja naranja, mirillas y tapa de caparazón con anillos ---
    abd_mid, abd_len = (ABD_Y0 + ABD_Y1) / 2, ABD_Y1 - ABD_Y0
    store = finish("abdomen", box((2 * ABD_HALF_X, abd_len, ABD_Z1 - ABD_Z0), (0.0, abd_mid, (ABD_Z0 + ABD_Z1) / 2)), METAL, root, mat, 0.02)
    finish("abdomen_base", box((2 * ABD_HALF_X + 0.03, abd_len + 0.02, 0.05), (0.0, abd_mid, ABD_Z0 + 0.025)), METAL_DARK, root, mat, 0.01)
    finish("abdomen_band", box((2 * ABD_HALF_X + 0.02, abd_len + 0.015, 0.05), (0.0, abd_mid, ABD_Z0 + 0.12)), ACCENT, root, mat, 0.006)
    finish("abdomen_rim", box((2 * ABD_HALF_X + 0.04, abd_len + 0.03, 0.05), (0.0, abd_mid, ABD_Z1 + 0.02)), METAL_DARK, root, mat, 0.01)
    # Caparazón: 3 segmentos (más bajo el de atrás) con 2 anillos naranjas, como la tapa del arcón.
    segs = [(ABD_Y0 - 0.01, -0.5, 0.6), (-0.46, -0.27, 1.0), (-0.23, ABD_Y1 + 0.01, 0.8)]
    for k, (y0, y1, scale) in enumerate(segs):
        finish("shell_%d" % k, arch_segment_y(y0, y1, (ABD_HALF_X + 0.02) * (0.9 + 0.1 * scale), ABD_Z1 + 0.045, 0.24 * scale),
               METAL_DEEP, root, mat, 0.012)
    for k, (y0, y1, scale) in enumerate(((-0.51, -0.45, 1.0), (-0.28, -0.22, 1.0))):
        finish("shell_ring_%d" % k, arch_segment_y(y0, y1, ABD_HALF_X + 0.035, ABD_Z1 + 0.045, 0.24 * scale + 0.025),
               ACCENT, root, mat, 0.006)
    # Mirillas hundidas en los dos costados, con lo que guarda dentro (lo escala y pinta Godot).
    win_y, win_z = -0.38, 0.4
    for side, sx in (("east", 1.0), ("west", -1.0)):
        cut_recess(store, (0.1, 0.34, 0.16), (sx * ABD_HALF_X, win_y, win_z), METAL_DEEP)
        # Marco hexagonal alargado alrededor de la mirilla.
        finish("window_frame_%s" % side, box((0.02, 0.42, 0.03), (sx * (ABD_HALF_X + 0.005), win_y, win_z + 0.095)), METAL_DARK, root, mat, 0.004)
        finish("window_frame_low_%s" % side, box((0.02, 0.42, 0.03), (sx * (ABD_HALF_X + 0.005), win_y, win_z - 0.095)), METAL_DARK, root, mat, 0.004)
        finish("store_window_" + side, box((0.01, 0.34, 0.16), (sx * (ABD_HALF_X - 0.045), win_y, win_z)), GLASS, root, mat, 0.0)
    fill_pos = Vector((0.0, win_y, win_z - 0.08))
    fill = empty("store_fill_pivot", fill_pos, root, "ARROWS", 0.08)
    for side, sx in (("east", 1.0), ("west", -1.0)):
        ore = finish("store_ore_" + side, box((0.012, 0.34, 0.16), (sx * (ABD_HALF_X - 0.044), win_y, win_z)), ORE, root, mat, 0.0)
        ore.parent = fill
        ore.matrix_parent_inverse = Matrix.Translation(fill_pos).inverted()
    for side, sx in (("e", 1.0), ("w", -1.0)):
        for dy in (-0.62, -0.14):
            finish("rivet_%s_%d" % (side, dy > -0.3), hex_rivet((sx * (ABD_HALF_X + 0.004), dy, win_z), (sx, 0, 0), r=0.016),
                   METAL_DEEP, root, mat, 0.0)

    # --- Antenas sobre la parte de delante de la cámara, con la luz de estado en la punta ---
    for side, sx in (("east", 1.0), ("west", -1.0)):
        p0 = Vector((sx * 0.12, -0.12, ABD_Z1 + 0.2))
        p1 = Vector((sx * 0.2, -0.02, 0.88))
        p2 = Vector((sx * 0.3, 0.1, 0.94))
        finish("antenna_%s_socket" % side, prism(6, 0.04, 0.032, p0.z - 0.05, p0.z + 0.01, x=p0.x, y=p0.y), METAL_DEEP, root, mat, 0.0)
        finish("antenna_%s_0" % side, strut(p0, p1, 0.03, 6), METAL_DARK, root, mat, 0.0)
        finish("antenna_%s_1" % side, strut(p1, p2, 0.026, 6), METAL_DARK, root, mat, 0.0)
        finish("antenna_%s_joint" % side, prism(6, 0.026, 0.026, p1.z - 0.02, p1.z + 0.02, x=p1.x, y=p1.y), ACCENT, root, mat, 0.0)
        finish("status_light_" + side, prism(6, 0.04, 0.028, p2.z - 0.015, p2.z + 0.05, x=p2.x, y=p2.y), GLASS, root, mat, 0.006)

    # --- Túnel: tres versiones (recta, derecha, izquierda); Godot enseña la de la salida elegida ---
    for name, turn in (("tunnel_straight", 0), ("tunnel_right", 1), ("tunnel_left", -1)):
        pivot_pos = Vector((0.0, BEND_Y, 0.0))
        pivot = empty(name, pivot_pos, root, "PLAIN_AXES", 0.1)
        for obj in build_tunnel(name, turn, root, mat):
            hang(obj, pivot, pivot_pos)

    tris = 0
    for child in root.children_recursive:
        if child.type == "MESH":
            tris += sum(len(p.vertices) - 2 for p in child.data.polygons)
    print("caja logística: piezas:", len(root.children_recursive), "triángulos:", tris)


build()
