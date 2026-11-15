# Arcón manual (B3.7, D-093). 2×1, sin puertos: solo se abre a mano (ventana de almacén).
# Con forma de ABDOMEN DE HORMIGA (César aprobó la idea): caja de madera con flejes y remaches
# hexagonales sobre seis patitas metálicas cortas, y una tapa abombada partida en segmentos con franjas
# naranjas, como los anillos del abdomen. Cerradura hexagonal delante, como emblema de la colonia.
# Convenciones: sin girar, el frente (cerradura) mira al SUR (−Y en Blender), que es la cara que el fantasma
# pone hacia el jugador. Origen en el centro de la huella, a ras de suelo. Huella: x ∈ [−1, 1], y ∈ [−0,5, 0,5].
# Altura declarada 1 (todo por debajo de 1 m).
#
# Nodos para Godot: lid_pivot (bisagra de la tapa: lo que cuelga se abre girando en X al abrir la ventana).
#
# Uso: Editor de texto de Blender → abrir → Alt+P. Si ya existe «storage_chest», lo borra y lo rehace.
# Dónde tocar: las medidas están en build(); cada pieza dice su color como (fila, columna).

import bpy
import bmesh
import math
from mathutils import Matrix, Vector

PALETTE = 64
SWATCH = 8
ROOT = "storage_chest"
TEXTURE = "//../../assets/textures/palette.png"

WOOD, WOOD_DARK, WOOD_END = (0, 3), (0, 4), (0, 2)
METAL_LIGHT, METAL, METAL_DARK, METAL_DEEP = (5, 2), (5, 3), (5, 4), (5, 5)
ACCENT = (4, 2)           # naranja oscuro de las máquinas: aquí, las franjas del abdomen

HALF_X, HALF_Y = 0.86, 0.36   # medio largo y medio fondo de la caja
BODY_Z0, BODY_Z1 = 0.16, 0.56  # la caja va sobre las patitas
LID_RISE = 0.3                 # cuánto sube la tapa abombada sobre la caja


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


def build() -> None:
    clear_previous()
    mat = get_material()
    root = empty(ROOT, (0, 0, 0), None, "PLAIN_AXES", 0.3)

    # --- Seis patitas de hormiga: un muslo que sale de la caja y una pata que baja, con pie hexagonal ---
    for i, x in enumerate((-0.62, 0.0, 0.62)):
        for side, sy in (("s", -1.0), ("n", 1.0)):
            hip = Vector((x, sy * (HALF_Y - 0.06), BODY_Z0 + 0.04))
            # El muslo sube hacia fuera hasta la rodilla y la pata baja al suelo, como en una hormiga.
            knee = Vector((x + 0.05 * (1 if x >= 0 else -1), sy * 0.465, BODY_Z0 + 0.13))
            foot = Vector((knee.x + 0.04 * (1 if x >= 0 else -1), sy * 0.465, 0.03))
            finish("leg_thigh_%d_%s" % (i, side), strut(hip, knee, 0.055, 6), METAL_DARK, root, mat, 0.0)
            finish("leg_shin_%d_%s" % (i, side), strut(knee, foot, 0.05, 6), METAL_DARK, root, mat, 0.0)
            finish("leg_knee_%d_%s" % (i, side), prism(6, 0.04, 0.04, knee.z - 0.03, knee.z + 0.03, x=knee.x, y=knee.y), ACCENT, root, mat, 0.0)
            finish("leg_foot_%d_%s" % (i, side), prism(6, 0.04, 0.035, 0.0, 0.035, x=foot.x, y=foot.y), METAL_DEEP, root, mat, 0.0)

    # --- Caja de madera: tablas, marco de abajo, cantoneras y flejes de hierro con remaches ---
    body_h = BODY_Z1 - BODY_Z0
    finish("body", box((2 * HALF_X, 2 * HALF_Y, body_h), (0.0, 0.0, (BODY_Z0 + BODY_Z1) / 2)), WOOD, root, mat, 0.015)
    finish("bottom_frame", box((2 * HALF_X + 0.04, 2 * HALF_Y + 0.04, 0.05), (0.0, 0.0, BODY_Z0 + 0.025)), WOOD_DARK, root, mat, 0.01)
    # Juntas entre tablas (largas, delante y detrás).
    for k, z in enumerate((BODY_Z0 + 0.15, BODY_Z0 + 0.27)):
        for side, sy in (("s", -1.0), ("n", 1.0)):
            finish("plank_line_%s_%d" % (side, k), box((2 * HALF_X - 0.04, 0.012, 0.018), (0.0, sy * (HALF_Y + 0.002), z)),
                   WOOD_DARK, root, mat, 0.0)
    # Cantoneras metálicas en las cuatro esquinas.
    for i, (sx, sy) in enumerate(((1, 1), (-1, 1), (-1, -1), (1, -1))):
        finish("corner_%d" % i, box((0.08, 0.08, body_h + 0.02), (sx * (HALF_X - 0.025), sy * (HALF_Y - 0.025), (BODY_Z0 + BODY_Z1) / 2)),
               METAL_DARK, root, mat, 0.01)
    # Dos flejes verticales que abrazan la caja, con remaches hexagonales.
    for k, x in enumerate((-0.42, 0.42)):
        finish("strap_%d" % k, box((0.07, 2 * HALF_Y + 0.025, body_h + 0.01), (x, 0.0, (BODY_Z0 + BODY_Z1) / 2)), METAL_DARK, root, mat, 0.006)
        for side, sy in (("s", -1.0), ("n", 1.0)):
            for z in (BODY_Z0 + 0.08, BODY_Z1 - 0.08):
                finish("strap_rivet_%d_%s_%d" % (k, side, int(z * 100)), hex_rivet((x, sy * (HALF_Y + 0.013), z), (0, sy, 0), r=0.016),
                       METAL_DEEP, root, mat, 0.0)
    # Asas en los dos extremos.
    for side, sx in (("e", 1.0), ("w", -1.0)):
        finish("handle_%s" % side, box((0.03, 0.26, 0.035), (sx * (HALF_X + 0.06), 0.0, BODY_Z1 - 0.14)), METAL, root, mat, 0.008)
        for dy in (-0.12, 0.12):
            finish("handle_post_%s_%d" % (side, dy > 0), box((0.06, 0.03, 0.03), (sx * (HALF_X + 0.03), dy, BODY_Z1 - 0.14)), METAL_DARK, root, mat, 0.0)

    # --- Tapa: abdomen de hormiga en 4 segmentos con franjas naranjas; cuelga de la bisagra de atrás ---
    hinge = Vector((0.0, HALF_Y + 0.01, BODY_Z1 + 0.01))
    lid = empty("lid_pivot", hinge, root, "ARROWS", 0.12)
    parts = []
    lid_half_y = HALF_Y + 0.025
    finish_rim = box((2 * HALF_X + 0.05, 2 * lid_half_y, 0.05), (0.0, 0.0, BODY_Z1 + 0.025))
    parts.append(finish("lid_rim", finish_rim, WOOD_DARK, root, mat, 0.01))
    # Segmentos: más altos en el centro y más bajos hacia los extremos, como un abdomen.
    edges = [-HALF_X - 0.02, -0.5, -0.02, 0.02, 0.5, HALF_X + 0.02]
    # Más bajos hacia los extremos y de metal oscuro, como el caparazón del abdomen; cada anillo naranja
    # sobresale (César eligió el metal para que el abdomen destaque sobre la madera).
    segments = [(-HALF_X - 0.02, -0.46, 0.6), (-0.44, -0.03, 1.0), (0.03, 0.44, 1.0), (0.46, HALF_X + 0.02, 0.6)]
    for k, (x0, x1, scale) in enumerate(segments):
        seg = arch_segment(x0, x1, lid_half_y * (0.9 + 0.1 * scale), BODY_Z1 + 0.05, LID_RISE * scale)
        parts.append(finish("lid_segment_%d" % k, seg, METAL_DEEP, root, mat, 0.012))
    # Anillos naranjas entre segmentos, más anchos y por encima de los dos vecinos.
    for k, (x0, x1, scale) in enumerate(((-0.48, -0.42, 1.0), (-0.035, 0.035, 1.0), (0.42, 0.48, 1.0))):
        band = arch_segment(x0, x1, lid_half_y + 0.018, BODY_Z1 + 0.05, LID_RISE * scale + 0.025)
        parts.append(finish("lid_band_%d" % k, band, ACCENT, root, mat, 0.006))
    # Cierre delantero de la tapa (el pestillo baja hasta la cerradura).
    parts.append(finish("lid_hasp", box((0.1, 0.03, 0.14), (0.0, -lid_half_y - 0.005, BODY_Z1 + 0.02)), METAL_DARK, root, mat, 0.006))
    for obj in parts:
        hang(obj, lid, hinge)
    # Bisagras detrás (fijas).
    for k, x in enumerate((-0.5, 0.5)):
        hb = prism(6, 0.03, 0.03, -0.08, 0.08)
        bmesh.ops.transform(hb, matrix=Matrix.Translation((x, hinge.y + 0.01, hinge.z)) @ Matrix.Rotation(math.radians(90), 4, "Y"), verts=hb.verts)
        finish("hinge_%d" % k, hb, METAL, root, mat, 0.0)

    # --- Cerradura hexagonal delante: el emblema de la colonia ---
    # Placa gris y hexágono naranja con la MISMA orientación (dos vértices arriba y abajo) y el naranja
    # claramente por delante de la placa, para que no se solapen al moverte alrededor (César).
    lock_z = BODY_Z1 - 0.12

    def front_hex(r: float, y_back: float, y_front: float):
        # Prisma hexagonal tumbado hacia el sur, con dos vértices arriba y abajo, de y_back a y_front.
        bm = bmesh.new()
        back, front = [], []
        for i in range(6):
            a = math.radians(90 + 60 * i)
            back.append(bm.verts.new((r * math.cos(a), y_back, lock_z + r * math.sin(a))))
            front.append(bm.verts.new((r * math.cos(a), y_front, lock_z + r * math.sin(a))))
        bm.faces.new(back)
        bm.faces.new(front)
        for i in range(6):
            j = (i + 1) % 6
            bm.faces.new((back[i], back[j], front[j], front[i]))
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        return bm

    finish("lock_plate", front_hex(0.095, -HALF_Y + 0.004, -HALF_Y - 0.022), METAL, root, mat, 0.006)
    finish("lock_ring", front_hex(0.058, -HALF_Y - 0.02, -HALF_Y - 0.034), ACCENT, root, mat, 0.004)
    finish("lock_hole", box((0.022, 0.012, 0.05), (0.0, -HALF_Y - 0.036, lock_z - 0.006)), METAL_DEEP, root, mat, 0.0)

    tris = 0
    for child in root.children_recursive:
        if child.type == "MESH":
            tris += sum(len(p.vertices) - 2 for p in child.data.polygons)
    print("arcón: piezas:", len(root.children_recursive), "triángulos:", tris)


build()
