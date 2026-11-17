# Ítems (C1.7, César): un modelo low-poly por ítem, para la mano de Mira (D-109) y para sacar su icono.
# Mismo estilo que el resto (paleta compartida, biseles pequeños, sombreado suave a 30°). Cada ítem cabe en
# unos 25 cm y cuelga de un vacío raíz «item_<id>» con el origen en su centro, para sujetarlo en la mano.
# En la escena van en fila, separados ITEM_SPACING, solo para verlos; las fotos y la exportación los
# llevan al origen uno a uno.
#
# Uso: con art/props/items.blend abierto, Editor de texto → abrir → Alt+P. Borra y rehace todos los ítems.
# Dónde tocar: la lista ITEMS (qué ítems y en qué orden) y la función de cada uno.

import bpy
import bmesh
import math
import random
from mathutils import Matrix, Vector

PALETTE = 64
SWATCH = 8
TEXTURE = "//../../assets/textures/palette.png"
# Mapa de superficie (D-105): metálico en R y rugosidad en G por cuadrito. Así el cobre, el hierro y los
# cristales brillan aquí igual que en Godot (las fotos de los iconos salen de Blender).
SURFACE = "//../../assets/textures/palette_surface.png"
ITEM_SPACING = 0.4

# Cuadritos de la paleta (fila, columna): 0 madera, 1 piedra, 2 verdes, 3 cobre | malaquita,
# 4 arcilla, 5 grises del Nexo, 6 ámbar y fuego, 7 agua | cristal.
BARK, BARK_DARK = (0, 5), (0, 6)
WOOD_END, WOOD_RING = (0, 1), (0, 3)
STONE, STONE_LIGHT, STONE_DARK = (1, 4), (1, 3), (1, 6)
LEAF = (2, 3)
COPPER, COPPER_LIGHT, COPPER_DARK = (3, 2), (3, 1), (3, 3)
MALACHITE, MALACHITE_LIGHT, MALACHITE_DARK = (3, 5), (3, 4), (3, 6)
CLAY_DARK, CLAY_DEEP = (4, 6), (4, 7)
IRON, IRON_LIGHT, IRON_DARK = (5, 3), (5, 2), (5, 5)
CHARCOAL, CHARCOAL_LIGHT = (5, 7), (5, 6)
CELL, CELL_LIGHT, CELL_DEEP = (7, 3), (7, 2), (7, 4)
SEED, SEED_CAP = (0, 4), (0, 6)

ITEMS = ["wood", "stone", "seed", "copper_ore", "charcoal", "copper_ingot", "slag", "copper_coil",
        "iron_ingot", "solar_cell", "gravel"]


def swatch_uv(row: int, col: int) -> Vector:
    return Vector(((col * SWATCH + SWATCH / 2) / PALETTE, 1.0 - (row * SWATCH + SWATCH / 2) / PALETTE))


def get_material():
    # Paleta con su mapa de superficie (brillo por familia de color, D-105). Se rehace siempre los nodos.
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


def box(size, center=(0, 0, 0), top_scale=1.0):
    # Caja; con top_scale < 1 la cara de arriba es más pequeña (forma de lingote).
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        if v.co.z > 0 and top_scale != 1.0:
            v.co.x *= top_scale
            v.co.y *= top_scale
    bmesh.ops.scale(bm, vec=size, verts=bm.verts)
    bmesh.ops.translate(bm, vec=Vector(center), verts=bm.verts)
    return bm


def blob(center, radius, squash, rng, jitter=0.12, subdivisions=1):
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=subdivisions, radius=radius)
    bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(rng.uniform(0, math.tau), 3, "Z"))
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


# --- Ítems ---

def wood(root, mat, rng):
    # Tronquito hexagonal tumbado: corteza, cortes claros con un anillo y una ramita cortada.
    lying = Matrix.Rotation(math.radians(90), 4, "Y")
    finish("wood_bark", place(prism(6, 0.055, 0.052, -0.12, 0.12), rotation=lying), BARK, root, mat, 0.006)
    for side in (-1, 1):
        cap = place(prism(6, 0.046, 0.046, 0.0, 0.006), (side * 0.12, 0, 0), Matrix.Rotation(math.radians(90 * side), 4, "Y"))
        finish("wood_end_%d" % (side + 1), cap, WOOD_END, root, mat)
        ring = place(prism(6, 0.022, 0.022, 0.0, 0.008), (side * 0.12, 0, 0), Matrix.Rotation(math.radians(90 * side), 4, "Y"))
        finish("wood_ring_%d" % (side + 1), ring, WOOD_RING, root, mat)
    twig = place(prism(5, 0.014, 0.01, 0.0, 0.05), (0.03, 0, 0.045), Matrix.Rotation(math.radians(-35), 4, "Y"))
    finish("wood_twig", twig, BARK_DARK, root, mat)


def stone(root, mat, rng):
    finish("stone_big", blob((0, 0, 0), 0.075, 0.75, rng), STONE, root, mat)
    finish("stone_chip", blob((0.06, 0.03, -0.025), 0.035, 0.7, rng), STONE_LIGHT, root, mat)


def seed(root, mat, rng):
    # Semilla tipo bellota con su caperuza y un brote.
    finish("seed_body", blob((0, 0, -0.01), 0.04, 1.25, rng, 0.04), SEED, root, mat)
    finish("seed_cap", place(prism(6, 0.042, 0.03, 0.0, 0.025), (0, 0, 0.025)), SEED_CAP, root, mat, 0.004)
    leaf = place(prism(4, 0.005, 0.016, 0.0, 0.04), (0.0, 0.0, 0.05), Matrix.Rotation(math.radians(25), 4, "X"))
    finish("seed_sprout", leaf, LEAF, root, mat)


def copper_ore(root, mat, rng):
    # Malaquita: verde con bandas de varios verdes y algún resto de roca (César), y cristales que asoman.
    finish("ore_body", blob((0, 0, -0.005), 0.07, 0.8, rng), MALACHITE, root, mat)
    for k, (c, r, color) in enumerate(((( 0.04, 0.02, 0.02), 0.035, MALACHITE_DARK), ((-0.035, -0.03, 0.01), 0.03, MALACHITE_LIGHT),
            ((0.0, 0.045, -0.02), 0.028, MALACHITE_DARK))):
        finish("ore_band_%d" % k, blob(c, r, 0.7, rng), color, root, mat)
    for k, (c, r) in enumerate((((-0.05, 0.03, -0.025), 0.025), ((0.05, -0.035, -0.03), 0.02))):
        finish("ore_rock_%d" % k, blob(c, r, 0.7, rng), STONE_DARK, root, mat)
    for k, (a, tilt, length) in enumerate(((20, 30, 0.07), (140, 40, 0.06), (260, 25, 0.075))):
        r = Matrix.Rotation(math.radians(a), 4, "Z") @ Matrix.Rotation(math.radians(tilt), 4, "Y")
        crystal = place(prism(6, 0.014, 0.005, 0.0, length), (0, 0, 0.02), r)
        finish("ore_crystal_%d" % k, crystal, (MALACHITE_LIGHT, MALACHITE, MALACHITE_LIGHT)[k], root, mat)


def charcoal(root, mat, rng):
    # Trozos de carbón: rocas negras e irregulares, con el leve brillo del carbón (César).
    for k, (c, r) in enumerate((((0, 0, 0), 0.055), ((0.06, 0.035, -0.015), 0.035), ((-0.05, 0.04, -0.02), 0.03))):
        finish("charcoal_%d" % k, blob(c, r, 0.75, rng, 0.22), (CHARCOAL, CHARCOAL_LIGHT, CHARCOAL)[k], root, mat)


def _ingot(name, root, mat, color, light, dark):
    # Lingote con la cara de arriba más clara y un hexágono de la colonia estampado en ella.
    finish(name + "_body", box((0.17, 0.07, 0.045), (0, 0, 0), 0.82), color, root, mat, 0.006)
    finish(name + "_top", box((0.12, 0.04, 0.004), (0, 0, 0.0235)), light, root, mat)
    finish(name + "_mark", prism(6, 0.012, 0.012, 0.0255, 0.0275, math.radians(30)), dark, root, mat)


def copper_ingot(root, mat, rng):
    _ingot("copper_ingot", root, mat, COPPER, COPPER_LIGHT, COPPER_DARK)


def iron_ingot(root, mat, rng):
    _ingot("iron_ingot", root, mat, IRON, IRON_LIGHT, IRON_DARK)


def slag(root, mat, rng):
    # Escoria: un puñado de piedrecitas oscuras y rugosas, alguna con brillo de vidrio (César).
    pieces = (((0, 0, 0), 0.03, CLAY_DARK), ((0.045, 0.02, -0.005), 0.024, CLAY_DEEP), ((-0.04, 0.025, -0.008), 0.026, STONE_DARK),
            ((0.01, -0.045, -0.008), 0.022, CLAY_DEEP), ((-0.03, -0.03, -0.01), 0.02, IRON_DARK))
    for k, (c, r, color) in enumerate(pieces):
        finish("slag_%d" % k, blob(c, r, 0.75, rng, 0.25), color, root, mat)


def wire_turn(radius, thickness, x, segments=12):
    # Una vuelta de hilo: anillo de sección cuadrada girada (rombo), eje en X. Los rombos juntos hacen
    # surcos entre vuelta y vuelta, y la luz los marca (que la bobina no se vea plana).
    bm = bmesh.new()
    rings = []
    for i in range(segments):
        a = 2.0 * math.pi * i / segments
        ring = []
        for dr, dx in ((thickness, 0.0), (0.0, thickness), (-thickness, 0.0), (0.0, -thickness)):
            r = radius + dr
            ring.append(bm.verts.new((x + dx, r * math.cos(a), r * math.sin(a))))
        rings.append(ring)
    for i in range(segments):
        a, b = rings[i], rings[(i + 1) % segments]
        for k in range(4):
            bm.faces.new((a[k], a[(k + 1) % 4], b[(k + 1) % 4], b[k]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def copper_coil(root, mat, rng):
    # Carrete del Nexo (gris, como las máquinas) con vueltas de hilo de cobre que se ven una a una
    # (César: que no se vea plana ni se confunda el cobre con el carrete). Eje en X (tumbado).
    lying = Matrix.Rotation(math.radians(90), 4, "Y")
    finish("coil_core", place(prism(8, 0.022, 0.022, -0.075, 0.075), rotation=lying), IRON_DARK, root, mat)
    finish("coil_fill", place(prism(12, 0.046, 0.046, -0.054, 0.054), rotation=lying), COPPER_DARK, root, mat)
    turns, thick = 8, 0.0068
    for k in range(turns):
        x = -0.054 + thick + k * (0.108 - 2 * thick) / (turns - 1)
        finish("coil_turn_%d" % k, wire_turn(0.05, thick, x), COPPER if k % 2 == 0 else COPPER_LIGHT, root, mat)
    # Cabo suelto del hilo: sale de lo alto de la última vuelta y asoma por encima del carrete, recortado
    # contra el fondo, para que se vea también en el icono (César).
    tail_dir = Vector((0.15, 0.35, 0.92)).normalized()
    tail_rot = tail_dir.to_track_quat("Z", "X").to_matrix().to_4x4()
    tail = place(prism(4, 0.006, 0.006, 0.0, 0.055, math.radians(45)), (0.04, 0.0, 0.048), tail_rot)
    finish("coil_tail", tail, COPPER_LIGHT, root, mat)
    for side in (-1, 1):
        flange = place(prism(8, 0.07, 0.07, -0.008, 0.008, math.radians(22.5)), (side * 0.064, 0, 0), lying)
        finish("coil_flange_%d" % (side + 1), flange, IRON, root, mat, 0.003)
        hub = place(prism(8, 0.026, 0.026, -0.003, 0.003, math.radians(22.5)), (side * 0.074, 0, 0), lying)
        finish("coil_hub_%d" % (side + 1), hub, IRON_DARK, root, mat)

def solar_cell(root, mat, rng):
    # Célula hexagonal del Nexo: marco gris, lámina negra y celda azul con nervios.
    finish("cell_frame", prism(6, 0.1, 0.1, -0.008, 0.008, math.radians(30)), IRON, root, mat, 0.003)
    finish("cell_back", prism(6, 0.088, 0.088, 0.008, 0.011, math.radians(30)), CHARCOAL, root, mat)
    finish("cell_face", prism(6, 0.078, 0.078, 0.011, 0.014, math.radians(30)), CELL_DEEP, root, mat)
    # Nervios en cruz que acaban justo en el borde de la celda (contra la lámina negra): el horizontal
    # llega a los lados planos del hexágono y el vertical a sus puntas, con las esquinas tocando las aristas.
    face_r, rib_w = 0.078, 0.004
    rib_x = 2.0 * face_r * math.cos(math.radians(30))
    rib_y = 2.0 * (face_r - rib_w / 2.0 * math.tan(math.radians(30)))
    for k, size in enumerate(((rib_x, rib_w, 0.002), (rib_w, rib_y, 0.002))):
        finish("cell_rib_%d" % k, box(size, (0, 0, 0.0145)), CELL, root, mat)


def gravel(root, mat, rng):
    for k in range(5):
        a = k * 1.3
        c = (math.cos(a) * 0.045 * (k > 0), math.sin(a) * 0.045 * (k > 0), 0.0)
        finish("gravel_%d" % k, blob(c, rng.uniform(0.022, 0.03), 0.75, rng), (STONE, STONE_LIGHT, STONE_DARK)[k % 3], root, mat)


# --- Construir ---

def clear_previous():
    for item_id in ITEMS:
        root = bpy.data.objects.get("item_" + item_id)
        if root is None:
            continue
        for obj in list(root.children_recursive) + [root]:
            data = obj.data
            bpy.data.objects.remove(obj, do_unlink=True)
            if data is not None and data.users == 0:
                bpy.data.meshes.remove(data)


def build():
    clear_previous()
    mat = get_material()
    for i, item_id in enumerate(ITEMS):
        root = bpy.data.objects.new("item_" + item_id, None)
        root.empty_display_type = "PLAIN_AXES"
        root.empty_display_size = 0.05
        bpy.context.collection.objects.link(root)
        root.location = (i * ITEM_SPACING, 0.0, 0.0)
        globals()[item_id](root, mat, random.Random(17 + i))
    tris = 0
    for item_id in ITEMS:
        root = bpy.data.objects["item_" + item_id]
        n = sum(sum(len(p.vertices) - 2 for p in c.data.polygons) for c in root.children if c.type == "MESH")
        tris += n
        print("%-14s %4d triángulos" % (item_id, n))
    print("total", tris)


build()
