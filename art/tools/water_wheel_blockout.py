# Rueda hidráulica con dinamo (B3.7, D-094). 2×3 (César): sirve en cualquier orilla, no solo en canales de 1.
# Columna oeste (x −1…0) sobre AGUA QUE CORRE a lo largo de Y: la rueda, en voladizo. Columna este (x 0…1) en
# TIERRA: la DINAMO, con sus bobinas de cobre a la vista tras dos mirillas (lo que pagas es lo que ves) y la
# carcasa segmentada como un abdomen de hormiga, con los anillos naranjas de los almacenes, y un cojinete en
# la orilla. La rueda de paletas de madera, con aros de hierro, se moja abajo. El eje asoma por el lado del
# agua con una BRIDA DE ACOPLE: más adelante se le podrán añadir ruedas de extensión (idea de César,
# aparcada para después del vertical slice).
# Medidas del agua (TerrainView): superficie a −0,08 m; fondo a −0,4 m en el centro del canal, con rampas.
# Convenciones: origen en el centro de la huella, a ras de suelo. Huella: x ∈ [−1, 1], y ∈ [−1,5, 1,5].
# Altura 3.
#
# Nodos para Godot: wheel_pivot (lo que cuelga gira en X: la rueda, su eje y la brida), status_light_north /
# status_light_south (luces de estado sobre la dinamo), cable_insulator y cable_anchor (borne), y
# splash_origin (donde las paletas salen del agua: salpicaduras).
#
# Uso: Editor de texto de Blender → abrir → Alt+P. Si ya existe «water_wheel», lo borra y lo rehace.
# Dónde tocar: las medidas están en las constantes y en build(); cada pieza dice su color como (fila, columna).

import bpy
import bmesh
import math
from mathutils import Matrix, Vector

PALETTE = 64
SWATCH = 8
ROOT = "water_wheel"
TEXTURE = "//../../assets/textures/palette.png"

WOOD, WOOD_DARK, WOOD_END = (0, 3), (0, 4), (0, 2)
STONE, STONE_DARK = (1, 3), (1, 5)
COPPER = (3, 1)
METAL_LIGHT, METAL, METAL_DARK, METAL_DEEP = (5, 2), (5, 3), (5, 4), (5, 5)
GLASS = (7, 6)
ACCENT = (4, 2)

AXLE_Z = 1.1          # altura del eje
WHEEL_R = 1.2         # radio hasta la punta de las paletas (abajo se moja: −0,1 m)
RIM_R = 1.0           # radio de los aros
WHEEL_HALF = 0.3      # medio ancho de la rueda (en X); el canal mide 1 m
SPOKES = 6
PADDLES = 12
WHEEL_X = -0.5        # centro de la columna de agua
DYN_X = 0.53          # centro de la dinamo (columna de tierra)


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

    # --- Rueda (gira con wheel_pivot alrededor del eje X) ---
    pivot_pos = Vector((WHEEL_X, 0.0, AXLE_Z))
    pivot = empty("wheel_pivot", pivot_pos, root, "ARROWS", 0.3)
    parts = []
    for k, sx in enumerate((-1.0, 1.0)):
        x0 = WHEEL_X + sx * WHEEL_HALF
        x1 = WHEEL_X + sx * (WHEEL_HALF - 0.07)
        parts.append(finish("rim_%d" % k, ring_x(min(x0, x1), max(x0, x1), RIM_R, RIM_R - 0.1, PADDLES, AXLE_Z), WOOD_DARK, root, mat, 0.0))
        parts.append(finish("hoop_%d" % k, ring_x(WHEEL_X + sx * (WHEEL_HALF + 0.005) - 0.015, WHEEL_X + sx * (WHEEL_HALF + 0.005) + 0.015,
                                                  RIM_R + 0.012, RIM_R - 0.03, PADDLES, AXLE_Z), METAL_DARK, root, mat, 0.0))
        # Radios: de la maza al aro, en cada cara.
        for s in range(SPOKES):
            a = 2 * math.pi * s / SPOKES
            xs = WHEEL_X + sx * (WHEEL_HALF - 0.04)
            p0 = Vector((xs, 0.12 * math.cos(a), AXLE_Z + 0.12 * math.sin(a)))
            p1 = Vector((xs, (RIM_R - 0.06) * math.cos(a), AXLE_Z + (RIM_R - 0.06) * math.sin(a)))
            parts.append(finish("spoke_%d_%d" % (k, s), strut(p0, p1, 0.06), WOOD, root, mat, 0.0))
    # Paletas entre los dos aros, de punta un poco más larga que el aro.
    for s in range(PADDLES):
        a = 2 * math.pi * (s + 0.5) / PADDLES
        r_mid = (RIM_R - 0.05 + WHEEL_R) / 2
        center = Vector((WHEEL_X, r_mid * math.cos(a), AXLE_Z + r_mid * math.sin(a)))
        paddle = box((2 * WHEEL_HALF - 0.02, 0.045, WHEEL_R - RIM_R + 0.1), (0.0, 0.0, 0.0))
        rot = Matrix.Rotation(a - math.pi / 2, 4, "X")
        bmesh.ops.transform(paddle, matrix=Matrix.Translation(center) @ rot, verts=paddle.verts)
        parts.append(finish("paddle_%d" % s, paddle, WOOD, root, mat, 0.0))
    # Maza y eje.
    parts.append(finish("hub", cylinder_x(WHEEL_X - WHEEL_HALF - 0.02, WHEEL_X + WHEEL_HALF + 0.02, 0.16, 8, 0.0, AXLE_Z), METAL, root, mat, 0.0))
    parts.append(finish("axle", cylinder_x(-0.93, DYN_X, 0.06, 8, 0.0, AXLE_Z), METAL_DARK, root, mat, 0.0))
    for k, sx in enumerate((-1.0, 1.0)):
        parts.append(finish("hub_cap_%d" % k, hex_rivet((WHEEL_X + sx * (WHEEL_HALF + 0.03), 0.0, AXLE_Z), (sx, 0, 0), r=0.1, depth=0.03), ACCENT, root, mat, 0.0))
    # Brida de acople en la punta del eje, del lado del agua (para las futuras ruedas de extensión).
    parts.append(finish("coupling", cylinder_x(-0.97, -0.92, 0.13, 6, 0.0, AXLE_Z), ACCENT, root, mat, 0.0))
    for b in range(6):
        a = 2 * math.pi * (b + 0.5) / 6
        parts.append(finish("coupling_bolt_%d" % b, hex_rivet((-0.975, 0.09 * math.cos(a), AXLE_Z + 0.09 * math.sin(a)), (-1, 0, 0), r=0.016),
                            METAL_DEEP, root, mat, 0.0))
    for obj in parts:
        hang(obj, pivot, pivot_pos)

    # --- Cojinete en la orilla, entre la rueda y la dinamo (hierro sobre un dado de piedra) ---
    finish("bearing_block", box((0.22, 0.5, AXLE_Z - 0.16), (0.12, 0.0, (AXLE_Z - 0.16) / 2)), STONE, root, mat, 0.015)
    finish("bearing_block_joint", box((0.23, 0.51, 0.02), (0.12, 0.0, 0.45)), STONE_DARK, root, mat, 0.0)
    finish("bearing", box((0.2, 0.26, 0.2), (0.12, 0.0, AXLE_Z - 0.06)), METAL, root, mat, 0.015)
    finish("bearing_cap", cylinder_x(0.02, 0.22, 0.1, 8, 0.0, AXLE_Z + 0.02), METAL_DARK, root, mat, 0.0)
    for dy in (-0.09, 0.09):
        finish("bearing_bolt_%d" % (dy > 0), hex_rivet((0.12, dy, AXLE_Z + 0.105), (0, 0, 1), r=0.022), METAL_DEEP, root, mat, 0.0)

    # --- Dinamo al este: carcasa segmentada (abdomen) con mirillas de bobinas de cobre ---
    finish("dynamo_base", box((0.84, 1.3, 0.14), (DYN_X + 0.02, 0.0, 0.07)), STONE, root, mat, 0.015)
    body = finish("dynamo_body", box((0.66, 0.96, 0.9), (DYN_X, 0.0, 0.14 + 0.45)), METAL, root, mat, 0.02)
    # Anillos naranjas y tapa abombada segmentada.
    for k, z in enumerate((0.36, 0.84)):
        finish("dynamo_ring_%d" % k, box((0.69, 0.99, 0.05), (DYN_X, 0.0, z)), ACCENT, root, mat, 0.006)
    cap = prism(8, 0.46, 0.3, 1.04, 1.24, x=DYN_X, y=0.0, angle=math.radians(22.5))
    bmesh.ops.scale(cap, vec=(0.75, 1.0, 1.0), space=Matrix.Translation((-DYN_X, 0.0, 0.0)), verts=cap.verts)
    finish("dynamo_cap", cap, METAL_DEEP, root, mat, 0.01)
    # Mirillas al norte y al sur, con las bobinas (anillos de cobre) dentro.
    for side, sy in (("north", 1.0), ("south", -1.0)):
        cut_recess(body, (0.42, 0.1, 0.32), (DYN_X, sy * 0.48, 0.6), METAL_DEEP)
        # Mirilla abierta (sin cristal): dentro del hueco, tres bobinas de cobre de cara a ella.
        for c, cx in enumerate((DYN_X - 0.13, DYN_X, DYN_X + 0.13)):
            coil = ring_x(-0.02, 0.02, 0.07, 0.03, 8, 0.0)
            bmesh.ops.transform(coil, matrix=Matrix.Translation((cx, sy * 0.455, 0.6)) @ Matrix.Rotation(math.radians(90), 4, "Z"),
                                verts=coil.verts)
            finish("coil_%s_%d" % (side, c), coil, COPPER, root, mat, 0.0)
            finish("coil_core_%s_%d" % (side, c), cylinder_x(-0.03, 0.03, 0.03, 6, 0.0, 0.0), METAL_DARK, root, mat, 0.0)
            core = bpy.data.objects["coil_core_%s_%d" % (side, c)]
            core.data.transform(Matrix.Translation((cx, sy * 0.45, 0.6)) @ Matrix.Rotation(math.radians(90), 4, "Z"))
        finish("window_frame_%s" % side, box((0.48, 0.02, 0.04), (DYN_X, sy * 0.485, 0.78)), METAL_DARK, root, mat, 0.0)
        finish("window_frame_low_%s" % side, box((0.48, 0.02, 0.04), (DYN_X, sy * 0.485, 0.42)), METAL_DARK, root, mat, 0.0)
        # Luces de estado arriba, una a cada lado.
        finish("status_light_" + side, prism(6, 0.05, 0.035, 1.22, 1.3, x=DYN_X, y=sy * 0.3), GLASS, root, mat, 0.006)
    # Donde entra el eje: un collarín.
    finish("dynamo_collar", cylinder_x(DYN_X - 0.37, DYN_X - 0.31, 0.12, 8, 0.0, AXLE_Z), METAL_DARK, root, mat, 0.0)
    for dy in (-0.36, 0.36):
        for dz in (0.25, 0.95):
            finish("dynamo_rivet_%d_%d" % (dy > 0, int(dz * 100)), hex_rivet((DYN_X - 0.335, dy, dz), (-1, 0, 0), r=0.018), METAL_DEEP, root, mat, 0.0)
    # Borne del cable, arriba al este.
    finish("cable_post", box((0.07, 0.07, 0.1), (0.9, 0.0, 1.0)), METAL, root, mat, 0.008)
    finish("cable_insulator", prism(6, 0.06, 0.045, 1.05, 1.14, x=0.9, y=0.0), GLASS, root, mat, 0.008)
    empty("cable_anchor", (0.9, 0.0, 1.14), root)
    # Salpicaduras: donde las paletas suben del agua (la corriente va hacia −Y en Blender, el sur).
    empty("splash_origin", (WHEEL_X, -0.9, -0.02), root, "SPHERE", 0.06)

    tris = 0
    for child in root.children_recursive:
        if child.type == "MESH":
            tris += sum(len(p.vertices) - 2 for p in child.data.polygons)
    print("rueda: piezas:", len(root.children_recursive), "triángulos:", tris)


build()
