# Barandilla de troncos por tramos (C5.6b, D-187; sesión 26). Dos piezas que coloca el juego por las casillas de la capa
# [barandilla] del plano:
#   - fence_post: poste de madera torneada con forma de hormiguita (abdomen abajo, cintura, tórax, cuello y cabeza),
#     remate hexagonal de arcilla como la placa del emblema y dos antenas. Los troncos van a la altura de las dos partes
#     estrechas: la cintura (LOW_RAIL_Z) y el cuello (HIGH_RAIL_Z). Las ataduras de esparto las pone el juego en cada
#     tronco, donde toca el poste (`FenceBuilder`, con el mismo perfil POST_PARTS).
#   - fence_log: los dos troncos horizontales de un tramo, de 1 m a lo largo de +X (de 0 a 1), con el origen en el poste
#     de salida a ras de suelo. El juego lo estira en X hasta el poste siguiente y los extremos quedan dentro de los postes.
# Mismo estilo que el resto (paleta compartida, biseles pequeños, sombreado suave a 30°).
#
# Uso: con art/props/fence.blend abierto, Editor de texto → abrir → Alt+P. Borra y rehace la barandilla.
# Exportar: export_hierarchy("fence", "//../../assets/models/props/fence.glb") (export_glb.py): cada pieza queda unida en
# una malla bajo su vacío (fence_post y fence_log).

import bpy
import bmesh
import math
from mathutils import Matrix, Vector

PALETTE = 64
SWATCH = 8
TEXTURE = "//../../assets/textures/palette.png"
SURFACE = "//../../assets/textures/palette_surface.png"

# Cuadritos de la paleta (fila, columna), los mismos que items_blockout.py.
PLANK, PLANK_GRAIN, WOOD_END = (0, 2), (0, 4), (0, 1)
BARK, BARK_DARK = (0, 5), (0, 6)
CLAY = (4, 2)

ROOT = "fence"
POST_SIDES = 8
LOW_RAIL_Z = 0.40      # cintura de la hormiga
HIGH_RAIL_Z = 0.71     # cuello
RAIL_RADIUS = 0.05
# Perfil del poste (radio, altura) de abajo arriba, por partes, cada una de su color como una hormiga: el abdomen
# (con el pie) en madera oscura y el tórax y la cabeza en madera media. Cada parte empieza donde acaba la anterior.
POST_PARTS = [
    ("abdomen", BARK, [(0.105, 0.0), (0.105, 0.05), (0.125, 0.11), (0.135, 0.24), (0.115, 0.33), (0.07, 0.40)]),
    ("thorax", PLANK_GRAIN, [(0.07, 0.40), (0.09, 0.47), (0.095, 0.58), (0.078, 0.66), (0.062, 0.71)]),
    ("head", PLANK_GRAIN, [(0.062, 0.71), (0.085, 0.77), (0.09, 0.85), (0.07, 0.91)]),
]
CAP_Z = 0.91
CAP_HEIGHT = 0.045


def swatch_uv(row: int, col: int) -> Vector:
    return Vector(((col * SWATCH + SWATCH / 2) / PALETTE, 1.0 - (row * SWATCH + SWATCH / 2) / PALETTE))


def get_material():
    mat = bpy.data.materials.get("palette") or bpy.data.materials.new("palette")
    img = bpy.data.images.load(TEXTURE, check_existing=True)
    surface = bpy.data.images.load(SURFACE, check_existing=True)
    surface.colorspace_settings.name = "Non-Color"
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial"); out.location = (300, 0)
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled"); bsdf.location = (0, 0)
    tex = nt.nodes.new("ShaderNodeTexImage"); tex.location = (-450, 150)
    tex.image = img
    tex.interpolation = "Closest"
    stex = nt.nodes.new("ShaderNodeTexImage"); stex.location = (-450, -150)
    stex.image = surface
    stex.interpolation = "Closest"
    sep = nt.nodes.new("ShaderNodeSeparateColor"); sep.location = (-200, -150)
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    nt.links.new(stex.outputs["Color"], sep.inputs["Color"])
    nt.links.new(sep.outputs["Red"], bsdf.inputs["Metallic"])
    nt.links.new(sep.outputs["Green"], bsdf.inputs["Roughness"])
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    return mat


def finish(name, bm, color, parent, material, bevel: float = 0.0):
    if bevel > 0.0:
        bmesh.ops.bevel(bm, geom=list(bm.edges), offset=bevel, segments=1, affect="EDGES", profile=0.5, clamp_overlap=True)
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


def prism(sides, r0, r1, z0, z1, angle=0.0):
    bm = bmesh.new()
    bottom, top = [], []
    for i in range(sides):
        a = angle + 2.0 * math.pi * i / sides
        bottom.append(bm.verts.new((r0 * math.cos(a), r0 * math.sin(a), z0)))
        top.append(bm.verts.new((r1 * math.cos(a), r1 * math.sin(a), z1)))
    bm.faces.new(list(reversed(bottom)))
    bm.faces.new(top)
    for i in range(sides):
        j = (i + 1) % sides
        bm.faces.new((bottom[i], bottom[j], top[j], top[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def lathe(profile, sides, angle=0.0):
    # Sólido de revolución cerrado por abajo y por arriba: anillos de `sides` lados en cada punto del perfil.
    bm = bmesh.new()
    rings = []
    for r, z in profile:
        rings.append([bm.verts.new((r * math.cos(angle + 2.0 * math.pi * i / sides),
                                    r * math.sin(angle + 2.0 * math.pi * i / sides), z)) for i in range(sides)])
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])
    for a, b in zip(rings, rings[1:]):
        for i in range(sides):
            j = (i + 1) % sides
            bm.faces.new((a[i], a[j], b[j], b[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def stick(points, radius, sides=4):
    # Palito por tramos (antenas): un prisma de `sides` lados entre cada par de puntos, que se va afinando.
    bm = bmesh.new()
    for k, (a, b) in enumerate(zip(points, points[1:])):
        a, b = Vector(a), Vector(b)
        r0 = radius * (1.0 - 0.3 * k)
        r1 = radius * (1.0 - 0.3 * (k + 1))
        piece = prism(sides, r0, r1, 0.0, (b - a).length, math.radians(45))
        rot = Vector((0, 0, 1)).rotation_difference((b - a).normalized()).to_matrix().to_4x4()
        bmesh.ops.transform(piece, matrix=Matrix.Translation(a) @ rot, verts=piece.verts)
        tmp = bpy.data.meshes.new("tmp")
        piece.to_mesh(tmp)
        piece.free()
        bm.from_mesh(tmp)
        bpy.data.meshes.remove(tmp)
    return bm


def empty(name, parent, location=(0, 0, 0)):
    obj = bpy.data.objects.new(name, None)
    obj.empty_display_type = "PLAIN_AXES"
    obj.empty_display_size = 0.2
    bpy.context.collection.objects.link(obj)
    obj.parent = parent
    obj.location = location
    return obj


# --- Piezas ---

def post(root, mat):
    pivot = empty("fence_post", root)
    for part, color, profile in POST_PARTS:
        finish("fence_post_" + part, lathe(profile, POST_SIDES, math.radians(22.5)), color, pivot, mat)
    # Remate hexagonal de arcilla, como la placa del emblema: la firma de la colonia, en pequeño.
    finish("fence_post_cap", prism(6, 0.072, 0.066, CAP_Z - 0.005, CAP_Z + CAP_HEIGHT, math.radians(30)), CLAY, pivot, mat, 0.006)
    # Antenas: dos palitos que salen de la cabeza y se abren hacia los lados, con la punta algo caída.
    for side in (-1, 1):
        pts = [(side * 0.035, 0.0, CAP_Z + 0.02), (side * 0.08, 0.0, CAP_Z + 0.13), (side * 0.15, 0.0, CAP_Z + 0.17)]
        finish("fence_post_antenna_%d" % (side + 1), stick(pts, 0.014), BARK_DARK, pivot, mat)
    # Las ataduras de esparto ya no van en el poste (los troncos las cortaban, César): las pone el juego en cada tronco,
    # justo donde toca el poste (`FenceBuilder`).


def logs(root, mat):
    pivot = empty("fence_log", root)
    lying = Matrix.Rotation(math.radians(90), 4, "Y")   # el prisma, de +Z a +X
    for k, z in enumerate((LOW_RAIL_Z, HIGH_RAIL_Z)):
        bm = prism(6, RAIL_RADIUS, RAIL_RADIUS * 0.92, 0.0, 1.0, math.radians(30 + 17 * k))
        bmesh.ops.transform(bm, matrix=Matrix.Translation((0.0, 0.0, z)) @ lying, verts=bm.verts)
        finish("fence_log_%d" % k, bm, BARK if k == 0 else PLANK_GRAIN, pivot, mat, 0.008)
        # Un nudo en cada tronco, en sitios distintos, para que no parezcan dos copias.
        knot = prism(5, RAIL_RADIUS * 0.45, RAIL_RADIUS * 0.3, 0.0, 0.02, 0.0)
        place = Matrix.Translation((0.35 + 0.3 * k, 0.0, z + RAIL_RADIUS * 0.85))
        bmesh.ops.transform(knot, matrix=place, verts=knot.verts)
        finish("fence_log_knot_%d" % k, knot, BARK_DARK, pivot, mat)


# --- Construir ---

def clear_previous():
    root = bpy.data.objects.get(ROOT)
    if root is None:
        return
    for obj in list(root.children_recursive) + [root]:
        data = obj.data
        bpy.data.objects.remove(obj, do_unlink=True)
        if data is not None and data.users == 0:
            bpy.data.meshes.remove(data)


def build():
    clear_previous()
    mat = get_material()
    root = bpy.data.objects.new(ROOT, None)
    root.empty_display_type = "PLAIN_AXES"
    bpy.context.collection.objects.link(root)
    post(root, mat)
    logs(root, mat)
    for name in ("fence_post", "fence_log"):
        pivot = bpy.data.objects[name]
        tris = sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in pivot.children_recursive if o.type == "MESH")
        print(name, tris, "triángulos")


build()
