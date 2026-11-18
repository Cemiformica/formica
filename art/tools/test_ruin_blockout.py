# Ruina de prueba (C4.3, D-115): estructura por reparar provisional para el sandbox, de 3×1 casillas.
# Base de piedra rota con dos tocones (siempre se ve) y tres piezas que faltan, cada una bajo su vacío
# «piece_<id>» (lo que busca `RepairSiteView`: el `node_name` de cada `RepairPieceData`):
#   - piece_pillar_left, piece_pillar_right: postes de madera sobre los tocones,
#   - piece_lintel: el dintel (un madero) con tres baldosas hexagonales encima,
#   - piece_bed: un camastro de nómada entre los pilares (la cama: reaparición y guardado, C4).
# Y un vacío «spawn_point» delante de la cama: donde reaparece Mira (mirando hacia la ruina).
# El origen de cada vacío está en la base de su pieza, para que crezca desde abajo al completarse.
# Mismo estilo que el resto (paleta compartida, biseles pequeños, sombreado suave a 30°).
#
# Uso: con art/props/test_ruin.blend abierto, Editor de texto → abrir → Alt+P. Borra y rehace la ruina.
# Exportar: export_hierarchy("test_ruin", "//../../assets/models/props/test_ruin.glb") (export_glb.py).

import bpy
import bmesh
import math
import random
from mathutils import Matrix, Vector

PALETTE = 64
SWATCH = 8
TEXTURE = "//../../assets/textures/palette.png"
SURFACE = "//../../assets/textures/palette_surface.png"

# Cuadritos de la paleta (fila, columna), los mismos que items_blockout.py.
PLANK, PLANK_GRAIN, WOOD_END, BARK_DARK = (0, 2), (0, 4), (0, 1), (0, 6)
STONE, STONE_LIGHT, STONE_DARK = (1, 4), (1, 3), (1, 6)
CLAY = (4, 2)

ROOT = "test_ruin"
STUMP_X = 1.1          # centro de los tocones y los pilares, a cada lado
STUMP_TOP = 0.38
PILLAR_HEIGHT = 1.45
LINTEL_Z = STUMP_TOP + PILLAR_HEIGHT


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


def box(size, center=(0, 0, 0)):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=size, verts=bm.verts)
    bmesh.ops.translate(bm, vec=Vector(center), verts=bm.verts)
    return bm


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


def blob(center, radius, squash, rng, jitter=0.15):
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=1, radius=radius)
    for v in bm.verts:
        v.co *= 1.0 + rng.uniform(-jitter, jitter)
        v.co.z *= squash
    bmesh.ops.translate(bm, vec=Vector(center), verts=bm.verts)
    return bm


def place(bm, location=(0, 0, 0), rotation=None):
    m = Matrix.Translation(Vector(location))
    if rotation is not None:
        m = m @ rotation
    bmesh.ops.transform(bm, matrix=m, verts=bm.verts)
    return bm


def empty(name, parent, location):
    obj = bpy.data.objects.new(name, None)
    obj.empty_display_type = "PLAIN_AXES"
    obj.empty_display_size = 0.2
    bpy.context.collection.objects.link(obj)
    obj.parent = parent
    obj.location = location
    return obj


# --- Piezas ---

def base(root, mat, rng):
    # Losa de piedra rota a ras de suelo, con cascotes, y los dos tocones donde van los pilares.
    finish("base_slab", box((3.0, 0.9, 0.12), (0, 0, 0.06)), STONE_DARK, root, mat, 0.02)
    for side in (-1, 1):
        finish("base_stump_%d" % (side + 1), box((0.46, 0.46, STUMP_TOP - 0.12), (side * STUMP_X, 0, 0.12 + (STUMP_TOP - 0.12) / 2)), STONE, root, mat, 0.03)
        finish("base_stump_cap_%d" % (side + 1), box((0.36, 0.36, 0.03), (side * STUMP_X, 0, STUMP_TOP + 0.005)), STONE_LIGHT, root, mat, 0.01)
    for k, (x, y) in enumerate(((-0.35, 0.22), (0.3, -0.25), (0.05, 0.3), (-0.6, -0.2))):
        finish("base_rubble_%d" % k, blob((x, y, 0.15), rng.uniform(0.07, 0.11), 0.7, rng), (STONE, STONE_LIGHT)[k % 2], root, mat)
    # Marca de la colonia en el frente de la losa: aquí había algo de las hormigas.
    mark = place(prism(6, 0.07, 0.07, 0.0, 0.01, math.radians(30)), (0, -0.455, 0.06), Matrix.Rotation(math.radians(90), 4, "X"))
    finish("base_mark", mark, CLAY, root, mat)


def pillar(name, x, root, mat):
    pivot = empty(name, root, (x, 0, STUMP_TOP))
    finish(name + "_post", box((0.26, 0.26, PILLAR_HEIGHT), (0, 0, PILLAR_HEIGHT / 2)), PLANK, pivot, mat, 0.02)
    finish(name + "_grain", box((0.004, 0.2, PILLAR_HEIGHT * 0.8), (0.131, 0, PILLAR_HEIGHT * 0.5)), PLANK_GRAIN, pivot, mat)
    finish(name + "_foot", box((0.3, 0.3, 0.06), (0, 0, 0.03)), BARK_DARK, pivot, mat, 0.01)


def lintel(root, mat):
    pivot = empty("piece_lintel", root, (0, 0, LINTEL_Z))
    lying = Matrix.Rotation(math.radians(90), 4, "Y")
    finish("piece_lintel_beam", place(prism(4, 0.2, 0.2, -1.5, 1.5, math.radians(45)), (0, 0, 0.142), lying), PLANK, pivot, mat, 0.02)
    for side in (-1, 1):
        cap = place(prism(4, 0.17, 0.17, 0.0, 0.006, math.radians(45)), (side * 1.5, 0, 0.142), Matrix.Rotation(math.radians(90 * side), 4, "Y"))
        finish("piece_lintel_end_%d" % (side + 1), cap, WOOD_END, pivot, mat)
    for k, x in enumerate((-0.85, 0.0, 0.85)):
        finish("piece_lintel_tile_%d" % k, prism(6, 0.24, 0.24, 0.284, 0.334, math.radians(30)), (STONE_LIGHT, STONE, STONE_LIGHT)[k], pivot, mat, 0.012)
        bpy.data.objects["piece_lintel_tile_%d" % k].location.x = x


def bed(root, mat):
    # Camastro: dos largueros de madero sobre patas cortas, tablas atravesadas y una piel encima.
    pivot = empty("piece_bed", root, (0, 0.05, 0.12))
    for side in (-1, 1):
        finish("piece_bed_rail_%d" % (side + 1), box((1.2, 0.09, 0.09), (0, side * 0.24, 0.16)), PLANK, pivot, mat, 0.01)
        for end in (-1, 1):
            finish("piece_bed_leg_%d_%d" % (side + 1, end + 1), box((0.08, 0.08, 0.12), (end * 0.52, side * 0.24, 0.06)), BARK_DARK, pivot, mat)
    for k in range(5):
        finish("piece_bed_slat_%d" % k, box((0.16, 0.56, 0.03), (-0.48 + k * 0.24, 0, 0.215)), PLANK_GRAIN if k % 2 else PLANK, pivot, mat, 0.006)
    finish("piece_bed_fur", box((0.95, 0.44, 0.05), (0.05, 0, 0.255)), CLAY, pivot, mat, 0.015)


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
    rng = random.Random(41)
    root = bpy.data.objects.new(ROOT, None)
    root.empty_display_type = "PLAIN_AXES"
    bpy.context.collection.objects.link(root)
    base(root, mat, rng)
    pillar("piece_pillar_left", -STUMP_X, root, mat)
    pillar("piece_pillar_right", STUMP_X, root, mat)
    lintel(root, mat)
    bed(root, mat)
    # Sin girar: en Godot mira a −Z, que es +Y de Blender, hacia la ruina.
    empty("spawn_point", root, (0, -1.1, 0))
    tris = sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in root.children_recursive if o.type == "MESH")
    print("ruina de prueba:", tris, "triángulos")


build()
