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
PLANK, PLANK_GRAIN = (0, 2), (0, 4)   # madera labrada del madero (C4.2)
STRAW, STRAW_LIGHT, STRAW_DARK = (0, 1), (0, 0), (0, 3)   # esparto seco (C5.5): fibra y cuerda
ROPE_STRAND = (0, 2)                                     # franjas del trenzado
ESPARTO_GREEN = (2, 4)

ITEMS = ["wood", "stone", "acorn", "copper_ore", "charcoal", "copper_ingot", "slag", "copper_coil",
        "iron_ingot", "solar_cell", "gravel", "pine_cone", "timber", "stone_tile", "fiber", "rope", "esparto_seed"]


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


def pine_cone(root, mat, rng):
    # Piña del pino (C1.9): eje oscuro y escamas en pisos de 6, giradas medio paso en cada piso, más anchas
    # en el centro; las puntas, más claras. Un poco inclinada, para que se lea en el icono.
    tilt = Matrix.Rotation(math.radians(15), 4, "Y")
    finish("cone_core", place(blob((0, 0, 0.005), 0.026, 2.0, rng, 0.03), rotation=tilt), BARK_DARK, root, mat)
    floors = 6
    for k in range(floors):
        t = k / (floors - 1)
        z = -0.045 + t * 0.095
        radius = 0.012 + 0.03 * math.sin(math.pi * (0.15 + 0.75 * t))
        length = 0.014 + 0.012 * math.sin(math.pi * (0.15 + 0.75 * t))
        for j in range(6):
            a = math.radians(60 * j + (30 if k % 2 else 0) + rng.uniform(-6, 6))
            rot = Matrix.Rotation(a, 4, "Z") @ Matrix.Rotation(math.radians(62), 4, "Y")
            scale = prism(4, 0.011, 0.006, 0.0, length, math.radians(45))
            center = Vector((radius * 0.55 * math.cos(a), radius * 0.55 * math.sin(a), z))
            finish("cone_scale_%d_%d" % (k, j), place(scale, tilt @ center, tilt @ rot), BARK if (j + k) % 3 else WOOD_RING, root, mat)
    stem = place(prism(5, 0.006, 0.005, -0.065, -0.045), rotation=tilt)
    finish("cone_stem", stem, BARK_DARK, root, mat)


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


def acorn(root, mat, rng):
    # Bellota del roble (C1.9; antes «semilla») con su caperuza y un brote.
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
    # Grava (C1.9, César): un montoncito de piedrecitas pequeñas sobre una base, para que se lea como
    # gravilla y no como unas piedras sueltas.
    finish("gravel_base", blob((0, 0, -0.012), 0.06, 0.35, rng, 0.05), STONE_DARK, root, mat)
    radius, height = 0.065, 0.045
    for k in range(30):
        r = radius * rng.uniform(0.0, 1.0) ** 0.6
        a = rng.uniform(0.0, math.tau)
        z = -0.012 + height * (1.0 - r / radius) * rng.uniform(0.75, 1.0)
        color = (STONE, STONE_LIGHT, STONE_DARK, STONE)[k % 4]
        finish("gravel_%d" % k, blob((r * math.cos(a), r * math.sin(a), z), rng.uniform(0.009, 0.014), 0.8, rng, 0.2), color, root, mat)

def timber(root, mat, rng):
    # Madero (C4.2, D-115; antes «viga», D-150): madero escuadrado y tumbado en X, con los cantos achaflanados, testas claras con su
    # anillo, vetas oscuras a lo largo y el hexágono de la colonia marcado a fuego en la cara de arriba.
    lying = Matrix.Rotation(math.radians(90), 4, "Y")
    half_len, r = 0.13, 0.05
    top = r * math.cos(math.radians(45))   # media anchura de la sección cuadrada
    finish("timber_body", place(prism(4, r, r, -half_len, half_len, math.radians(45)), rotation=lying), PLANK, root, mat, 0.008)
    for side in (-1, 1):
        turn = Matrix.Rotation(math.radians(90 * side), 4, "Y")
        cap = place(prism(4, r * 0.84, r * 0.84, 0.0, 0.005, math.radians(45)), (side * half_len, 0, 0), turn)
        finish("timber_end_%d" % (side + 1), cap, WOOD_END, root, mat)
        ring = place(prism(6, 0.016, 0.016, 0.0, 0.007), (side * half_len, 0, 0), turn)
        finish("timber_ring_%d" % (side + 1), ring, WOOD_RING, root, mat)
    # Vetas: listones finísimos encima y en el costado de delante, de largos distintos.
    for k, (x, y, length) in enumerate(((0.0, -0.012, 0.2), (0.03, 0.014, 0.12), (-0.06, 0.004, 0.08))):
        finish("timber_grain_top_%d" % k, box((length, 0.003, 0.002), (x, y, top + 0.0005)), PLANK_GRAIN, root, mat)
    for k, (x, z, length) in enumerate(((-0.02, 0.01, 0.17), (0.05, -0.014, 0.1))):
        finish("timber_grain_side_%d" % k, box((length, 0.002, 0.003), (x, -top - 0.0005, z)), PLANK_GRAIN, root, mat)
    finish("timber_mark", prism(6, 0.013, 0.013, top - 0.0005, top + 0.0015, math.radians(30)), BARK_DARK, root, mat)


def stone_tile(root, mat, rng):
    # Baldosa (C4.2, D-115; antes «losa», D-150): baldosa hexagonal de piedra labrada, como una celda del panal. Cara de arriba más
    # clara con un surco hexagonal y un par de desconchones oscuros en el canto.
    finish("tile_body", prism(6, 0.1, 0.1, -0.018, 0.018, math.radians(30)), STONE, root, mat, 0.006)
    finish("tile_top", prism(6, 0.088, 0.088, 0.018, 0.021, math.radians(30)), STONE_LIGHT, root, mat, 0.002)
    finish("tile_groove", prism(6, 0.062, 0.062, 0.021, 0.0222, math.radians(30)), STONE_DARK, root, mat)
    finish("tile_inner", prism(6, 0.054, 0.054, 0.021, 0.0226, math.radians(30)), STONE_LIGHT, root, mat)
    for k, a in enumerate((50, 215)):
        c = (0.088 * math.cos(math.radians(a)), 0.088 * math.sin(math.radians(a)), 0.012)
        finish("tile_chip_%d" % k, blob(c, 0.014, 0.6, rng, 0.2), STONE_DARK, root, mat)


# --- Construir ---

def tube(points, radius, sides=6, radius_at=None):
    # Tubo que sigue `points` (lista de Vector), con `sides` lados; `radius_at(k)` da el radio en el punto k (o
    # `radius`). Devuelve (bmesh, [(tramo, lado) de cada cara, en orden]) para pintar cada cara por su sitio.
    bm = bmesh.new()
    rings = []
    up_ref = Vector((0.0, 0.0, 1.0))
    for k, p in enumerate(points):
        a = points[max(k - 1, 0)]
        b = points[min(k + 1, len(points) - 1)]
        t = (b - a).normalized()
        ref = up_ref if abs(t.dot(up_ref)) < 0.95 else Vector((1.0, 0.0, 0.0))
        side = t.cross(ref).normalized()
        up = side.cross(t).normalized()
        r = radius_at(k) if radius_at is not None else radius
        ring = []
        for j in range(sides):
            ang = 2.0 * math.pi * j / sides
            ring.append(bm.verts.new(p + (side * math.cos(ang) + up * math.sin(ang)) * r))
        rings.append(ring)
    where = []
    for k in range(len(rings) - 1):
        for j in range(sides):
            jj = (j + 1) % sides
            bm.faces.new((rings[k][j], rings[k][jj], rings[k + 1][jj], rings[k + 1][j]))
            where.append((k, j))
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])
    where += [(-1, 0), (len(rings) - 1, 0)]
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm, where


def finish_colored(name, bm, colors, parent, material):
    # Como `finish`, pero con un color por cara (en el orden de `bm.faces`).
    uv = bm.loops.layers.uv.new("UVMap")
    bm.faces.ensure_lookup_table()
    for f, color in zip(bm.faces, colors):
        for loop in f.loops:
            loop[uv].uv = swatch_uv(*color)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    mesh.materials.append(material)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.parent = parent
    for poly in mesh.polygons:
        poly.use_smooth = True
    mesh.set_sharp_from_angle(angle=math.radians(50))
    return obj


def twisted(where, base, strand, period=3):
    # Colores de una cuerda trenzada: franjas en diagonal (el tramo y el lado avanzan a la vez).
    return [strand if (k + j) % period == 0 else base for k, j in where]


def fiber(root, mat, rng):
    # Fibra de esparto (C5.5, César): un manojo de hojas finas y secas, tumbado en X, apretado por el medio, donde lo
    # rodea una atadura de cuerda de dos vueltas, y abierto hacia las puntas; cada hoja se curva un poco a su manera.
    half = 0.115
    pinch = 0.011            # radio del manojo en la atadura
    flare = 0.03             # radio en las puntas
    for n in range(16):
        a0 = 2.0 * math.pi * n / 16 + rng.uniform(-0.25, 0.25)
        depth = rng.uniform(0.35, 1.0)                     # unas hojas por dentro y otras por fuera del manojo
        bend = rng.uniform(-0.25, 0.25)
        length = half * rng.uniform(0.85, 1.05)
        pts = []
        for k in range(9):
            x = -length + 2.0 * length * k / 8
            u = abs(x) / half
            r = (pinch + (flare - pinch) * u ** 1.6) * depth
            a = a0 + bend * (x / half) + rng.uniform(-0.04, 0.04)
            pts.append(Vector((x, r * math.cos(a), r * math.sin(a))))
        bm, where = tube(pts, 0.0034, 4, lambda k: 0.0038 * (1.0 - 0.5 * abs(k - 4) / 4))
        finish_colored("fiber_blade_%d" % n, bm, [rng.choice((STRAW, STRAW, STRAW_LIGHT))] * len(bm.faces), root, mat)
    # Atadura: dos vueltas apretadas de cuerda alrededor de la parte estrecha.
    pts = []
    turns, steps = 2, 28
    for k in range(steps + 1):
        a = 2.0 * math.pi * turns * k / steps
        x = -0.007 + 0.014 * k / steps
        pts.append(Vector((x, (pinch + 0.004) * math.cos(a), (pinch + 0.004) * math.sin(a))))
    bm, where = tube(pts, 0.0035, 5)
    finish_colored("fiber_tie", bm, twisted(where, STRAW_DARK, ROPE_STRAND, 2), root, mat)


def rope(root, mat, rng):
    # Cuerda (C5.5, César: componente del banco, 3 fibras → 1): una madeja, como se recoge y se guarda una cuerda. Tres
    # lazos alargados en abanico, lisos y en dos tonos de paja, apretados por el medio con una atadura de varias vueltas
    # más oscura. Sin cabos sueltos (se leían raros). Antes fue un rollo de vueltas apiladas: de cerca bien, pero en el
    # inventario parecía un nudo (César).
    half_len, half_w = 0.11, 0.055
    rope_r = 0.0085
    pinch = 0.26                # ancho de cada lazo en la atadura, respecto al de los extremos
    steps = 28
    # Tumbados (poca inclinación) y algo abiertos en abanico sobre el plano: así se ve el hueco de cada lazo.
    for n, (tilt, fan) in enumerate(((-16.0, -9.0), (2.0, 0.0), (18.0, 9.0))):
        turn = Matrix.Rotation(math.radians(fan), 3, "Z") @ Matrix.Rotation(math.radians(tilt), 3, "X")
        length = half_len * (1.0 - 0.06 * (n % 2))
        pts = []
        for k in range(steps):
            a = 2.0 * math.pi * k / steps
            x = length * math.cos(a)
            u = abs(x) / half_len
            w = half_w * (pinch + (1.0 - pinch) * u ** 0.8)
            pts.append(turn @ Vector((x, w * math.sin(a), 0.0)))
        pts.append(pts[0])
        bm, where = tube(pts, rope_r, 6)
        finish_colored("rope_loop_%d" % n, bm, [(STRAW, STRAW_LIGHT)[n % 2]] * len(bm.faces), root, mat)
    # Atadura: vueltas apretadas alrededor del medio de la madeja.
    bind_r = half_w * pinch + rope_r * 1.6
    pts = []
    turns, per_turn = 3, 12
    for k in range(turns * per_turn + 1):
        a = 2.0 * math.pi * k / per_turn
        x = -0.018 + 0.036 * k / (turns * per_turn)
        pts.append(Vector((x, bind_r * math.cos(a), bind_r * math.sin(a))))
    bm, where = tube(pts, rope_r * 0.85, 5)
    finish_colored("rope_bind", bm, [STRAW_DARK] * len(bm.faces), root, mat)


def esparto_seed(root, mat, rng):
    # Semilla de esparto (C5.5): una espiga corta con sus granos alargados en dos filas y un par de hojitas verdes en la
    # base, para que se lea como «semilla de una mata» y no como un fruto.
    finish("seed_stem", prism(4, 0.004, 0.003, -0.09, 0.07), STRAW_DARK, root, mat)
    for k in range(7):
        z = -0.04 + k * 0.018
        for side in (-1, 1):
            grain = place(prism(6, 0.009, 0.004, 0.0, 0.028), (0.0, side * 0.004, z),
                          Matrix.Rotation(math.radians(28 * side), 4, "X") @ Matrix.Rotation(math.radians(k * 25), 4, "Z"))
            finish("seed_grain_%d_%d" % (k, side + 1), grain, STRAW_LIGHT if (k + side) % 2 else STRAW, root, mat)
    for k, angle in enumerate((-35, 30)):
        leaf = place(prism(3, 0.006, 0.001, 0.0, 0.09), (0.0, 0.0, -0.085), Matrix.Rotation(math.radians(angle), 4, "Y"))
        finish("seed_leaf_%d" % k, leaf, ESPARTO_GREEN, root, mat)


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
