# Vegetación de varios tamaños (C5.6, D-179; sesión 30). Todo es decorado: no se recoge ni choca (César). Cuatro familias:
#   - flowers_N: matita de flores silvestres de 15–40 cm, de SEIS pétalos (como un hexágono, el lenguaje del emblema y del
#     panal), con tallos y dos o tres hojas al pie. Una por color: amarillo, rosa arcilla y crema.
#   - fern_N: helecho de 30–50 cm: una roseta de frondas curvas hechas de foliolos en rombo, a la sombra de rocas y árboles.
#   - bush_N: arbusto redondo de 0,5–1,2 m: bolas facetadas como la copa del frondoso, pero bajo y ancho.
#   - reeds_N: mata de juncos de 0,8–1,3 m para la orilla del río y del lago: hojas finas que se arquean y alguna espiga.
#   - clover_3 / clover_4: matita de tréboles de 6–10 cm (César: especial para él). Se comporta como el césped (lo reparte
#     el mismo sistema, con viento, empuje y sin salir bajo lo construido). En clover_4, uno de los tréboles tiene CUATRO
#     hojas: Godot pone muchas menos matas de esta que de la de tres.
# Godot las mece con el viento según la altura del vértice (cuanto más arriba, más se mueven) y las aparta al pasar Mira.
# Convenciones: origen de cada pieza en el centro de su casilla, a ras de suelo; cada pieza bajo su vacío raíz. Todo con la
# paleta compartida (verdes, madera y, en las flores, ámbar, arcilla y piedra clara).
#
# Uso: con art/props/plants.blend abierto, Editor de texto → abrir → Alt+P (o exec). Borra y rehace todas las piezas.
# Exportar: export_hierarchy("plants", "//../../assets/models/props/plants.glb") (export_glb.py).
# Dónde tocar: PIECES (variantes, semillas y medidas) y las funciones de cada familia.

import bpy
import bmesh
import math
import random
from mathutils import Matrix, Vector

PALETTE = 64
SWATCH = 8
TEXTURE = "//../../assets/textures/palette.png"
SURFACE = "//../../assets/textures/palette_surface.png"

LEAF_LIGHT, LEAF, LEAF_MID, LEAF_DARK, LEAF_DEEP = (2, 1), (2, 2), (2, 3), (2, 4), (2, 5)
STEM = (2, 4)
WOOD_DARK = (0, 5)
SPIKE = (0, 4)
# Flores: (pétalo, centro).
FLOWER_COLORS = {"yellow": ((6, 1), (6, 3)), "pink": ((4, 0), (6, 2)), "cream": ((1, 0), (6, 2))}

ROOT = "plants"
SPACING = 2.5

# (nombre, familia, semilla, medida, extra)
PIECES = [
    ("flowers_0", "flowers", 3, 0.3, "yellow"),
    ("flowers_1", "flowers", 7, 0.25, "pink"),
    ("flowers_2", "flowers", 12, 0.35, "cream"),
    ("fern_0", "fern", 21, 0.4, None),
    ("fern_1", "fern", 26, 0.5, None),
    ("bush_0", "bush", 31, 0.55, None),
    ("bush_1", "bush", 37, 0.85, None),
    ("bush_2", "bush", 44, 1.15, None),
    ("reeds_0", "reeds", 51, 0.9, None),
    ("reeds_1", "reeds", 58, 1.25, None),
    ("clover_3", "clover", 61, 0.08, 3),
    ("clover_4", "clover", 67, 0.08, 4),
]


def swatch_uv(row: int, col: int) -> Vector:
    return Vector(((col * SWATCH + SWATCH / 2) / PALETTE, 1.0 - (row * SWATCH + SWATCH / 2) / PALETTE))


def get_palette():
    mat = bpy.data.materials.get("palette") or bpy.data.materials.new("palette")
    img = bpy.data.images.load(TEXTURE, check_existing=True)
    surface = bpy.data.images.load(SURFACE, check_existing=True)
    surface.colorspace_settings.name = "Non-Color"
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = img
    tex.interpolation = "Closest"
    stex = nt.nodes.new("ShaderNodeTexImage")
    stex.image = surface
    stex.interpolation = "Closest"
    sep = nt.nodes.new("ShaderNodeSeparateColor")
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    nt.links.new(stex.outputs["Color"], sep.inputs["Color"])
    nt.links.new(sep.outputs["Red"], bsdf.inputs["Metallic"])
    nt.links.new(sep.outputs["Green"], bsdf.inputs["Roughness"])
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    return mat


def finish(name, bm, parent, material, color, smooth=True):
    uv = bm.loops.layers.uv.new("UVMap")
    for f in bm.faces:
        for loop in f.loops:
            loop[uv].uv = swatch_uv(*color)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    mesh.materials.append(material)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.parent = parent
    for p in mesh.polygons:
        p.use_smooth = smooth
    mesh.set_sharp_from_angle(angle=math.radians(35))
    return obj


def empty(name, parent=None, location=(0, 0, 0)):
    obj = bpy.data.objects.new(name, None)
    obj.empty_display_size = 0.2
    obj.location = location
    obj.parent = parent
    bpy.context.collection.objects.link(obj)
    return obj


def tube(points, r0, r1, sides=4):
    # Tubo por una lista de puntos, de radio r0 a r1 (tallos, hojas de junco). Cerrado en las puntas.
    bm = bmesh.new()
    rings = []
    n = len(points)
    for i, p in enumerate(points):
        p = Vector(p)
        d = (Vector(points[min(i + 1, n - 1)]) - Vector(points[max(i - 1, 0)])).normalized()
        side = d.cross(Vector((0, 0, 1)))
        if side.length < 1e-4:
            side = Vector((1, 0, 0))
        side.normalize()
        up = side.cross(d).normalized()
        r = r0 + (r1 - r0) * i / (n - 1)
        rings.append([bm.verts.new(p + (side * math.cos(math.tau * k / sides) + up * math.sin(math.tau * k / sides)) * r)
                      for k in range(sides)])
    for a, b in zip(rings, rings[1:]):
        for k in range(sides):
            bm.faces.new((a[k], a[(k + 1) % sides], b[(k + 1) % sides], b[k]))
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])
    return bm


def leaf(base, direction, length, width, lift, thickness=0.012):
    # Hoja en rombo, con un pelo de grosor (se ve por las dos caras sin tocar el material): base, punta y dos lados.
    d = Vector(direction).normalized()
    side = d.cross(Vector((0, 0, 1)))
    if side.length < 1e-4:
        side = Vector((1, 0, 0))
    side.normalize()
    base = Vector(base)
    tip = base + d * length + Vector((0, 0, lift))
    mid = base + d * length * 0.45 + Vector((0, 0, lift * 0.6))
    bm = bmesh.new()
    up = Vector((0, 0, thickness * 0.5))
    pts_top = [bm.verts.new(base + up), bm.verts.new(mid + side * width + up), bm.verts.new(tip + up),
               bm.verts.new(mid - side * width + up)]
    pts_bot = [bm.verts.new(base - up), bm.verts.new(mid + side * width - up), bm.verts.new(tip - up),
               bm.verts.new(mid - side * width - up)]
    bm.faces.new(pts_top)
    bm.faces.new(list(reversed(pts_bot)))
    for k in range(4):
        j = (k + 1) % 4
        bm.faces.new((pts_bot[k], pts_bot[j], pts_top[j], pts_top[k]))
    return bm


def blob(center, radius, squash, rng, jitter=0.1):
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=1, radius=radius)
    for v in bm.verts:
        v.co *= 1.0 + rng.uniform(-jitter, jitter)
    bmesh.ops.scale(bm, vec=(1.0, 1.0, squash), verts=bm.verts)
    bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(rng.uniform(0, math.tau), 3, "Z"))
    bmesh.ops.translate(bm, vec=Vector(center), verts=bm.verts)
    return bm


def join(bms):
    out = bmesh.new()
    for bm in bms:
        tmp = bpy.data.meshes.new("tmp")
        bm.to_mesh(tmp)
        bm.free()
        out.from_mesh(tmp)
        bpy.data.meshes.remove(tmp)
    return out


# --- Familias ---

def flower_head(center, radius, tilt_dir, petal_color, rng):
    # Flor de seis pétalos alrededor de un centro hexagonal, un poco inclinada hacia fuera.
    petals = []
    normal = (Vector((0, 0, 1)) + Vector(tilt_dir) * 0.35).normalized()
    side = normal.cross(Vector((0, 1, 0)))
    if side.length < 1e-4:
        side = Vector((1, 0, 0))
    side.normalize()
    fwd = normal.cross(side).normalized()
    start = rng.uniform(0, math.tau)
    for k in range(6):
        a = start + math.tau * k / 6
        d = side * math.cos(a) + fwd * math.sin(a)
        petals.append(leaf(Vector(center) + d * radius * 0.25, d, radius, radius * 0.38, radius * 0.15, 0.008))
    return join(petals)


def flowers(name, root, mat, rng, height, color):
    petal, middle = FLOWER_COLORS[color]
    count = rng.randint(5, 7)
    stems, heads, centers, leaves = [], [], [], []
    for i in range(count):
        a = rng.uniform(0, math.tau)
        d = rng.uniform(0.0, 0.14)
        foot = Vector((math.cos(a) * d, math.sin(a) * d, 0.0))
        h = height * rng.uniform(0.6, 1.0)
        out = Vector((math.cos(a), math.sin(a), 0.0)) * rng.uniform(0.03, 0.08)
        top = foot + out + Vector((0, 0, h))
        bend = foot + out * 0.3 + Vector((0, 0, h * 0.55))
        stems.append(tube([foot, bend, top], 0.008, 0.006, 4))
        r = rng.uniform(0.07, 0.1)
        heads.append(flower_head(top, r, (math.cos(a), math.sin(a), 0.0), petal, rng))
        c = bmesh.new()
        bmesh.ops.create_cone(c, cap_ends=True, segments=6, radius1=r * 0.32, radius2=r * 0.25, depth=r * 0.25)
        bmesh.ops.translate(c, vec=top + Vector((0, 0, r * 0.12)), verts=c.verts)
        centers.append(c)
    for i in range(rng.randint(4, 5)):
        a = rng.uniform(0, math.tau)
        leaves.append(leaf((0, 0, 0.01), (math.cos(a), math.sin(a), 0), rng.uniform(0.14, 0.2), 0.045, 0.06))
    finish(name + "_stems", join(stems), root, mat, STEM)
    finish(name + "_leaves", join(leaves), root, mat, LEAF_MID)
    finish(name + "_petals", join(heads), root, mat, petal, smooth=False)
    finish(name + "_centers", join(centers), root, mat, middle, smooth=False)


def frond(direction, length, width, height, lobes, rng):
    # Fronda de una pieza: contorno dentado (lóbulos a cada lado, cada vez más pequeños hacia la punta), con un pelo de
    # grosor, que sale del centro, sube y cae hacia fuera.
    d = Vector(direction).normalized()
    side = d.cross(Vector((0, 0, 1))).normalized()

    def spine(t):
        return d * length * t + Vector((0, 0, height * math.sin(t * math.pi * 0.8)))

    left, right = [], []
    for k in range(lobes * 2 + 1):
        t = k / (lobes * 2)
        w = width * (1.0 - t) ** 0.8 * (1.0 if k % 2 == 1 else 0.45)   # lóbulo y entrante, alternos
        p = spine(t)
        left.append(p + side * w)
        right.append(p - side * w)
    outline = [spine(0.0)] + left[1:-1] + [spine(1.0)] + list(reversed(right[1:-1]))
    bm = bmesh.new()
    up = Vector((0, 0, 0.006))
    top = [bm.verts.new(p + up) for p in outline]
    bot = [bm.verts.new(p - up) for p in outline]
    bm.faces.new(top)
    bm.faces.new(list(reversed(bot)))
    n = len(outline)
    for k in range(n):
        j = (k + 1) % n
        bm.faces.new((bot[k], bot[j], top[j], top[k]))
    bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 4])
    return bm


def fern(name, root, mat, rng, height, _extra):
    fronds = []
    count = rng.randint(7, 9)
    start = rng.uniform(0, math.tau)
    for i in range(count):
        a = start + math.tau * i / count + rng.uniform(-0.2, 0.2)
        length = height * rng.uniform(1.1, 1.5)
        fronds.append(frond((math.cos(a), math.sin(a), 0.0), length, length * 0.22, height * rng.uniform(0.7, 1.0), 4, rng))
    # Un par de frondas jóvenes en el centro, más cortas y derechas.
    for i in range(2):
        a = rng.uniform(0, math.tau)
        fronds.append(frond((math.cos(a), math.sin(a), 0.0), height * 0.5, height * 0.1, height * 1.1, 3, rng))
    finish(name + "_fronds", join(fronds), root, mat, rng.choice((LEAF_MID, LEAF_DARK)))


def bush(name, root, mat, rng, height, _extra):
    width = height * rng.uniform(1.1, 1.35)
    parts = []
    # Base ancha y oscura, y bolas encima, más claras arriba.
    parts.append((blob((0, 0, height * 0.32), width * 0.5, 0.72, rng), LEAF_DEEP))
    for i in range(rng.randint(3, 5)):
        a = rng.uniform(0, math.tau)
        d = rng.uniform(0.15, 0.35) * width
        r = width * rng.uniform(0.28, 0.38)
        z = height * rng.uniform(0.45, 0.75)
        parts.append((blob((math.cos(a) * d, math.sin(a) * d, z), r, 0.85, rng), rng.choice((LEAF_MID, LEAF_DARK))))
    parts.append((blob((0, 0, height * 0.82), width * 0.3, 0.8, rng), rng.choice((LEAF, LEAF_MID))))
    for i, (bm, color) in enumerate(parts):
        finish("%s_ball_%d" % (name, i), bm, root, mat, color, smooth=False)


def reeds(name, root, mat, rng, height, _extra):
    blades, spikes, stalks = [], [], []
    count = rng.randint(13, 17)
    for i in range(count):
        a = rng.uniform(0, math.tau)
        d = rng.uniform(0.0, 0.2)
        foot = Vector((math.cos(a) * d, math.sin(a) * d, 0.0))
        out = Vector((math.cos(a), math.sin(a), 0.0))
        h = height * rng.uniform(0.55, 1.0)
        arch = rng.uniform(0.05, 0.25) * h
        points = [foot + out * arch * (t * t) + Vector((0, 0, h * t)) for t in (0.0, 0.35, 0.7, 1.0)]
        blades.append(tube(points, 0.018, 0.002, 3))
    for i in range(rng.randint(1, 2)):
        a = rng.uniform(0, math.tau)
        foot = Vector((math.cos(a) * 0.05, math.sin(a) * 0.05, 0.0))
        top = foot + Vector((0, 0, height * 1.05))
        stalks.append(tube([foot, top], 0.007, 0.005, 4))
        s = bmesh.new()
        bmesh.ops.create_cone(s, cap_ends=True, segments=6, radius1=0.022, radius2=0.022, depth=0.14)
        bmesh.ops.translate(s, vec=top - Vector((0, 0, 0.09)), verts=s.verts)
        spikes.append(s)
    finish(name + "_blades", join(blades), root, mat, rng.choice((LEAF_MID, LEAF_DARK)))
    finish(name + "_stalks", join(stalks), root, mat, STEM)
    finish(name + "_spikes", join(spikes), root, mat, WOOD_DARK, smooth=False)


def heart(center, direction, size, lift):
    # Hoja de trébol: un corazón plano (dos lóbulos y la punta hacia el centro), con la cara de arriba y la de abajo
    # separadas un pelo (se ve por las dos caras sin tocar el material). Pocos vértices: va a salir muchas veces.
    d = Vector(direction).normalized()
    side = d.cross(Vector((0, 0, 1))).normalized()
    c = Vector(center)
    # Contorno: punta (junto al tallo), lóbulo redondo, muesca honda en el borde de fuera y el otro lóbulo.
    shape = [(0.0, 0.0), (0.4, 0.42), (0.8, 0.5), (1.0, 0.28), (0.52, 0.0), (1.0, -0.28), (0.8, -0.5), (0.4, -0.42)]
    outline = [c + d * size * f + side * size * w for f, w in shape]
    outline = [p + Vector((0, 0, lift * (p - c).length / size)) for p in outline]
    bm = bmesh.new()
    up = Vector((0, 0, 0.0005))
    top = [bm.verts.new(p + up) for p in outline]
    bot = [bm.verts.new(p - up) for p in outline]
    bm.faces.new(top)
    bm.faces.new(list(reversed(bot)))
    bmesh.ops.triangulate(bm, faces=list(bm.faces))
    return bm


def clover(name, root, mat, rng, height, leaves):
    stems, tops, lucky = [], [], []
    count = rng.randint(6, 8)
    for i in range(count):
        a = rng.uniform(0, math.tau)
        d = rng.uniform(0.0, 0.09)
        foot = Vector((math.cos(a) * d, math.sin(a) * d, 0.0))
        h = height * rng.uniform(0.6, 1.0)
        top = foot + Vector((math.cos(a), math.sin(a), 0.0)) * 0.01 + Vector((0, 0, h))
        stems.append(tube([foot, top], 0.003, 0.002, 3))
        n = leaves if i == 0 else 3   # el primero es el de cuatro hojas en clover_4
        size = rng.uniform(0.022, 0.03)
        start = rng.uniform(0, math.tau)
        hearts = [heart(top, (math.cos(start + math.tau * k / n), math.sin(start + math.tau * k / n), 0.0), size, size * 0.25)
                  for k in range(n)]
        (lucky if n == 4 else tops).extend(hearts)
    finish(name + "_stems", join(stems), root, mat, STEM)
    finish(name + "_leaves", join(tops), root, mat, LEAF_MID, smooth=False)
    if lucky:   # el de cuatro hojas, un pelo más claro: se distingue si te fijas
        finish(name + "_lucky", join(lucky), root, mat, LEAF, smooth=False)


BUILDERS = {"flowers": flowers, "fern": fern, "bush": bush, "reeds": reeds, "clover": clover}


def clear_previous():
    old = bpy.data.objects.get(ROOT)
    if old is not None:
        for obj in [old] + list(old.children_recursive):
            bpy.data.objects.remove(obj, do_unlink=True)
    for mesh in [m for m in bpy.data.meshes if m.users == 0]:
        bpy.data.meshes.remove(mesh)


def build():
    clear_previous()
    mat = get_palette()
    root = empty(ROOT)
    for index, (name, family, seed, size, extra) in enumerate(PIECES):
        pivot = empty(name, root, ((index % 5) * SPACING, (index // 5) * SPACING, 0.0))
        BUILDERS[family](name, pivot, mat, random.Random(seed), size, extra)
    for name, *_ in PIECES:
        pivot = bpy.data.objects[name]
        tris = sum(len(p.vertices) - 2 for c in pivot.children_recursive if c.type == "MESH" for p in c.data.polygons)
        print(name, tris, "triángulos")


if __name__ == "__main__":
    build()
