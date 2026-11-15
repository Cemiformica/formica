# Naturaleza (B3.7, pieza 10, D-097): árboles por fases con variantes, tocones y rocas.
#   A — «frondoso»: tronco hexagonal con raíces y copa de bolas facetadas en verdes vecinos (el más común).
#   B — «pino de hexágonos»: conos hexagonales apilados y girados (eco del hexágono de la colonia).
# Cada pieza sale de una SEMILLA: cambiarla da otra variante con la misma receta. Cada pieza va en su
# propio vacío raíz; al exportar, cada una se une en una sola malla con su nombre (Godot elige especie y
# variante según la casilla, D-097).
# Convenciones: origen de cada pieza en el centro de su casilla, a ras de suelo; el tronco dentro de la
# casilla (la copa puede salir) y todo por debajo de 3,5 m.
#
# Uso: Editor de texto de Blender → abrir → Alt+P. Borra y rehace todas las piezas de PIECES.
# Exportar: con el .blend guardado, export_nature() une cada pieza en una malla con su nombre (en el origen)
# y escribe assets/models/props/nature.glb (escribe antes su .import si es la primera vez, D-083).
# Dónde tocar: la lista PIECES (qué variantes hay y con qué semilla) y las medidas de cada función.

import bpy
import bmesh
import math
import random
from mathutils import Matrix, Vector

PALETTE = 64
SWATCH = 8
TEXTURE = "//../../assets/textures/palette.png"

BARK, BARK_DARK = (0, 5), (0, 6)
WOOD_END, WOOD_RING = (0, 1), (0, 2)
LEAVES_A = [(2, 2), (2, 3), (2, 4), (2, 5)]
LEAVES_B = [(2, 4), (2, 5), (2, 6)]
SPROUT = (2, 1)
STONE, STONE_DARK, STONE_LIGHT = (1, 4), (1, 5), (1, 3)
MOSS = (2, 4)

# (nombre, función, semilla). El nombre es el que buscará Godot.
PIECES = [
    ("tree_a_mature_0", "tree_a_mature", 7),
    ("tree_a_mature_1", "tree_a_mature", 21),
    ("tree_a_mature_2", "tree_a_mature", 40),
    ("tree_a_young_0", "tree_a_young", 5),
    ("tree_a_young_1", "tree_a_young", 13),
    ("tree_a_sprout_0", "tree_a_sprout", 2),
    ("tree_b_mature_0", "tree_b_mature", 11),
    ("tree_b_mature_1", "tree_b_mature", 30),
    ("tree_b_young_0", "tree_b_young", 4),
    ("tree_b_sprout_0", "tree_b_sprout", 6),
    ("tree_a_stump_0", "stump_a", 3),
    ("tree_b_stump_0", "stump_b", 9),
    ("rock_0", "rock", 5),
    ("rock_1", "rock", 17),
    ("rock_2", "rock", 28),
]


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


def finish(name: str, bm: bmesh.types.BMesh, color, parent, material, bevel: float = 0.0):
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


def prism(sides: int, r_bottom: float, r_top: float, z0: float, z1: float, x=0.0, y=0.0, angle: float = 0.0):
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


def blob(center, radius: float, squash: float, rng: random.Random, jitter: float = 0.08, subdivisions: int = 1):
    # Bola facetada (icosaedro) con los vértices un poco movidos: orgánica, no perfecta.
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=subdivisions, radius=radius)
    bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(rng.uniform(0, math.tau), 3, "Z"))
    for v in bm.verts:
        v.co *= 1.0 + rng.uniform(-jitter, jitter)
        v.co.z *= squash
    bmesh.ops.translate(bm, vec=Vector(center), verts=bm.verts)
    return bm


def bar(p0, p1, r0: float, r1: float, sides: int = 5):
    p0, p1 = Vector(p0), Vector(p1)
    d = p1 - p0
    bm = prism(sides, r0, r1, 0.0, d.length)
    rot = Vector((0.0, 0.0, 1.0)).rotation_difference(d.normalized()).to_matrix().to_4x4()
    bmesh.ops.transform(bm, matrix=Matrix.Translation(p0) @ rot, verts=bm.verts)
    return bm


def roots(prefix: str, root, mat, r_trunk: float, count: int, rng: random.Random, size: float = 1.0) -> None:
    # Raíces: cuñas cortas que salen del pie del tronco y se hunden en el suelo.
    start = rng.uniform(0, math.tau)
    for k in range(count):
        a = start + 2.0 * math.pi * k / count + rng.uniform(-0.25, 0.25)
        d = Vector((math.cos(a), math.sin(a), -0.45)).normalized()
        p0 = Vector((0.0, 0.0, 0.17 * size))
        p1 = p0 + d * (r_trunk + 0.18 * size)
        finish("%s_root_%d" % (prefix, k), bar(p0, p1, 0.07 * size, 0.03 * size, 4), BARK_DARK, root, mat)


CANOPY_OVERLAP = 0.15  # cuánto baja la bola central por debajo de la punta del tronco (César: sin hueco)


def canopy_center(trunk_top: float, size: float, squash: float) -> float:
    # Altura del centro de la copa para que su bola central abrace la punta del tronco.
    return trunk_top - CANOPY_OVERLAP * size + 0.75 * size * squash * 0.85


def canopy_a(name: str, root, mat, rng: random.Random, top: float, spread: float, count: int, size: float,
             squash: float = 0.85) -> None:
    # Una bola central y `count` alrededor, a alturas y tamaños distintos. `top` es el centro de la central.
    finish(name + "_leaves_c", blob((0, 0, top), 0.75 * size, squash, rng), rng.choice(LEAVES_A[1:3]), root, mat)
    start = rng.uniform(0, math.tau)
    for k in range(count):
        a = start + math.tau * k / count + rng.uniform(-0.35, 0.35)
        r = rng.uniform(0.38, 0.55) * size
        c = (math.cos(a) * spread * size, math.sin(a) * spread * size, top + rng.uniform(-0.35, 0.25) * size)
        finish("%s_leaves_%d" % (name, k), blob(c, r, squash, rng), rng.choice(LEAVES_A), root, mat)
    finish(name + "_leaves_t", blob((rng.uniform(-0.1, 0.1), rng.uniform(-0.1, 0.1), top + 0.48 * size), 0.45 * size, squash, rng),
           LEAVES_A[0], root, mat)


# Tres siluetas de frondoso maduro (César: que se distingan): normal, ancho y bajo, y alto y estrecho.
# (altura del tronco, separación de las bolas, número de bolas, tamaño, aplastado)
A_SHAPES = [((1.4, 1.65), 0.45, 4, 1.0, 0.85), ((1.15, 1.3), 0.66, 5, 1.08, 0.72), ((1.75, 1.9), 0.28, 3, 0.82, 0.95)]


def tree_a_mature(name: str, root, mat, rng: random.Random) -> None:
    (h_min, h_max), spread, count, size, squash = A_SHAPES[int(name[-1]) % len(A_SHAPES)]
    h = rng.uniform(h_min, h_max)
    lean = Vector((rng.uniform(-0.08, 0.08), rng.uniform(-0.08, 0.08), 0.0))
    trunk = prism(6, 0.17, 0.11, 0.0, h)
    for v in trunk.verts:
        v.co += lean * (v.co.z / h)
    finish(name + "_trunk", trunk, BARK, root, mat, 0.01)
    roots(name, root, mat, 0.17, rng.choice((3, 4)), rng)
    a = rng.uniform(0, math.tau)
    branch_from = Vector((0, 0, h * 0.72)) + lean * 0.72
    finish(name + "_branch", bar(branch_from, branch_from + Vector((math.cos(a) * 0.4, math.sin(a) * 0.4, 0.4)), 0.06, 0.035),
           BARK, root, mat)
    canopy_a(name, root, mat, rng, canopy_center(h, size, squash), spread, count, size, squash)
    for obj in root.children:
        if "_leaves" in obj.name:
            obj.location += lean


def tree_a_young(name: str, root, mat, rng: random.Random) -> None:
    # Más bajo y con la copa más llena (César: parecía una piruleta).
    h = rng.uniform(0.5, 0.6)
    finish(name + "_trunk", prism(6, 0.11, 0.08, 0.0, h), BARK, root, mat, 0.006)
    roots(name, root, mat, 0.11, 3, rng, 0.65)
    canopy_a(name, root, mat, rng, canopy_center(h, 0.66, 0.85), 0.3, 4, 0.66)


def tree_a_sprout(name: str, root, mat, rng: random.Random) -> None:
    finish(name + "_stem", prism(5, 0.025, 0.018, 0.0, 0.32), SPROUT, root, mat)
    for k in range(3):
        a = math.tau * k / 3 + rng.uniform(-0.3, 0.3)
        c = (math.cos(a) * 0.09, math.sin(a) * 0.09, 0.26 + 0.06 * k)
        finish("%s_leaf_%d" % (name, k), blob(c, 0.09, 0.45, rng, 0.05), LEAVES_A[k % 2], root, mat)


def cones_b(name: str, root, mat, rng: random.Random, tiers: list, z_base: float) -> None:
    turn = rng.uniform(0, 60)
    for k, (r, z0, z1) in enumerate(tiers):
        cone = prism(6, r, 0.05, z_base + z0, z_base + z1, angle=math.radians(turn + rng.uniform(10, 20) * k))
        # Falda del cono un poco caída por fuera, como ramas que cuelgan.
        for v in cone.verts:
            if abs(v.co.z - (z_base + z0)) < 1e-6:
                v.co.z -= 0.08 * r
        finish("%s_tier_%d" % (name, k), cone, LEAVES_B[(k + rng.randint(0, 1)) % 2 + 1], root, mat, 0.012)


def tree_b_mature(name: str, root, mat, rng: random.Random) -> None:
    finish(name + "_trunk", prism(6, 0.15, 0.1, 0.0, 0.9), BARK, root, mat, 0.01)
    roots(name, root, mat, 0.15, 3, rng)
    n = rng.choice((4, 5))
    top = rng.uniform(2.9, 3.25)
    tiers = []
    for k in range(n):
        t = k / n
        r = 0.88 - 0.6 * t + rng.uniform(-0.05, 0.05)
        z0 = 0.55 + (top - 0.95) * t
        tiers.append((r, z0, z0 + 0.95 - 0.25 * t))
    cones_b(name, root, mat, rng, tiers, 0.0)


def tree_b_young(name: str, root, mat, rng: random.Random) -> None:
    finish(name + "_trunk", prism(6, 0.08, 0.06, 0.0, 0.45), BARK, root, mat, 0.006)
    cones_b(name, root, mat, rng, [(0.45, 0.25, 0.85), (0.33, 0.6, 1.15), (0.2, 0.92, 1.4)], 0.0)


def tree_b_sprout(name: str, root, mat, rng: random.Random) -> None:
    finish(name + "_stem", prism(5, 0.022, 0.016, 0.0, 0.14), SPROUT, root, mat)
    cones_b(name, root, mat, rng, [(0.13, 0.1, 0.32), (0.08, 0.24, 0.42)], 0.0)


def stump(name: str, root, mat, rng: random.Random, r: float, h: float) -> None:
    finish(name + "_bark", prism(6, r, r * 0.85, 0.0, h), BARK, root, mat, 0.01)
    finish(name + "_cut", prism(6, r * 0.78, r * 0.78, h - 0.005, h + 0.012), WOOD_END, root, mat)
    finish(name + "_ring", prism(6, r * 0.4, r * 0.4, h + 0.01, h + 0.017), WOOD_RING, root, mat)
    roots(name, root, mat, r, rng.choice((3, 4)), rng)


def stump_a(name: str, root, mat, rng: random.Random) -> None:
    stump(name, root, mat, rng, 0.19, 0.26)


def stump_b(name: str, root, mat, rng: random.Random) -> None:
    stump(name, root, mat, rng, 0.16, 0.2)


def rock(name: str, root, mat, rng: random.Random) -> None:
    # Más pequeña que la primera prueba (César): visible, sin cargar el terreno. Unos 0,4–0,55 m.
    w = rng.uniform(0.2, 0.27)
    big = blob((0.0, 0.0, w * 0.4), w, rng.uniform(0.55, 0.75), rng, 0.15)
    bmesh.ops.scale(big, vec=(rng.uniform(1.0, 1.2), rng.uniform(0.8, 0.95), 1.0), verts=big.verts)
    finish(name + "_big", big, rng.choice((STONE, STONE_LIGHT)), root, mat)
    if rng.random() < 0.7:
        a = rng.uniform(0, math.tau)
        c = (math.cos(a) * w * 0.95, math.sin(a) * w * 0.95, 0.04)
        finish(name + "_small", blob(c, w * 0.42, 0.65, rng, 0.15), STONE_DARK, root, mat)
    if rng.random() < 0.6:
        finish(name + "_moss", blob((rng.uniform(-0.05, 0.05), rng.uniform(-0.05, 0.05), w * 0.85), w * 0.55, 0.25, rng, 0.1),
               MOSS, root, mat)


def clear_previous() -> None:
    for name, _func, _seed in PIECES:
        root = bpy.data.objects.get(name)
        if root is None:
            continue
        for obj in list(root.children_recursive) + [root]:
            data = obj.data
            bpy.data.objects.remove(obj, do_unlink=True)
            if data is not None and data.users == 0:
                bpy.data.meshes.remove(data)
    for name in ("tree_a_mature", "tree_b_mature", "tree_stump", "rock"):  # piezas de la primera prueba
        root = bpy.data.objects.get(name)
        if root is not None:
            for obj in list(root.children_recursive) + [root]:
                bpy.data.objects.remove(obj, do_unlink=True)


def build() -> None:
    clear_previous()
    mat = get_material()
    funcs = globals()
    # Vista previa ordenada: una fila por especie (A, B) y otra para tocones y rocas.
    rows = {"tree_a": 0.0, "tree_b": -2.5}
    col = {}
    for name, func, seed in PIECES:
        key = "tree_a" if name.startswith("tree_a") and "stump" not in name else "tree_b" if name.startswith("tree_b") and "stump" not in name else "misc"
        y = rows.get(key, -5.0)
        x = col.get(key, 0.0)
        col[key] = x + 2.0
        root = bpy.data.objects.new(name, None)
        root.empty_display_type = "PLAIN_AXES"
        root.empty_display_size = 0.3
        root.location = (x, y, 0.0)
        bpy.context.collection.objects.link(root)
        bpy.context.view_layer.update()
        funcs[func](name, root, mat, random.Random(seed))
        tris = sum(sum(len(p.vertices) - 2 for p in c.data.polygons) for c in root.children_recursive if c.type == "MESH")
        print(name, "triángulos:", tris)



def export_nature(filepath: str = "//../../assets/models/props/nature.glb") -> None:
    # Copias temporales: cada pieza unida en una malla con su nombre y llevada al origen. El .blend no cambia.
    names = sorted(name for name, _func, _seed in PIECES)
    temp = bpy.data.collections.new("_export_tmp")
    bpy.context.scene.collection.children.link(temp)
    win = bpy.context.window_manager.windows[0]
    area = next(a for a in win.screen.areas if a.type == "VIEW_3D")
    region = next(r for r in area.regions if r.type == "WINDOW")
    joined = []
    with bpy.context.temp_override(window=win, area=area, region=region):
        for name in names:
            root = bpy.data.objects[name]
            inv = root.matrix_world.inverted()
            copies = []
            for child in root.children_recursive:
                if child.type != "MESH":
                    continue
                dup = child.copy()
                dup.data = child.data.copy()
                dup.parent = None
                temp.objects.link(dup)
                dup.matrix_world = inv @ child.matrix_world
                copies.append(dup)
            bpy.ops.object.select_all(action="DESELECT")
            for dup in copies:
                dup.select_set(True)
            bpy.context.view_layer.objects.active = copies[0]
            bpy.ops.object.join()
            piece = bpy.context.view_layer.objects.active
            bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
            joined.append((name, piece))
        originals = [bpy.data.objects[name] for name in names]
        for obj in originals:
            obj.name = "_orig_" + obj.name
        for name, piece in joined:
            piece.name = name
            piece.data.name = name
        bpy.ops.object.select_all(action="DESELECT")
        for _name, piece in joined:
            piece.select_set(True)
        bpy.ops.export_scene.gltf(filepath=bpy.path.abspath(filepath), export_format="GLB", use_selection=True,
                                  export_yup=True, export_apply=True, export_cameras=False, export_lights=False,
                                  export_animations=False)
        for _name, piece in joined:
            mesh = piece.data
            bpy.data.objects.remove(piece, do_unlink=True)
            bpy.data.meshes.remove(mesh)
        bpy.data.collections.remove(temp)
        for obj in originals:
            obj.name = obj.name[len("_orig_"):]
    print("exportado:", filepath, "| piezas:", names)


build()
