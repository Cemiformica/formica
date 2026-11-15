# Veta de malaquita (B3.7). 3×3, inagotable. Las 8 casillas del borde admiten la CABEZA de un extractor
# (1×2); la central lleva un grupo de cristales grandes que se reconoce de lejos y sirve para minar a mano.
# Forma (v2, César): redondeada, con el contorno irregular y a 0 m para fundirse con el suelo (tierra y
# hierba en el borde); muy poco abombada y suave (sin facetas de diamante); vetas verdes hacia el centro.
# Convenciones: origen en el centro de la veta a ras de suelo; ocupa x, y ∈ [−1,5, 1,5].
# Las vetas son genéricas en el juego (cada una dice qué ítem da); esta es la de malaquita.
#
# Uso: Editor de texto de Blender → abrir → Alt+P. Si ya existe «malachite_vein», lo borra y lo rehace.
# Dónde tocar: las medidas y los colores (fila, columna) están en las constantes.

import bpy
import bmesh
import math
from mathutils import Matrix, Vector

PALETTE = 64
SWATCH = 8
ROOT = "malachite_vein"
TEXTURE = "//../../assets/textures/palette.png"

RADIUS = 1.42             # radio de la veta (redondeada, dentro de las 3×3 casillas)
SECTORS = 20              # sectores de la malla radial
ROCK = [(1, 5), (1, 4)]                  # grises pardos de la roca
EDGE = [(2, 3), (2, 4)]                  # contorno: verdes de hierba, para fundirse con el suelo
MALACHITE = [(3, 5), (3, 6), (3, 4)]     # verdes de la malaquita (claro, medio, oscuro)
CRYSTAL = [(3, 4), (3, 5), (3, 6)]


def swatch_uv(row: int, col: int) -> Vector:
    return Vector(((col * SWATCH + SWATCH / 2) / PALETTE, 1.0 - (row * SWATCH + SWATCH / 2) / PALETTE))


def noise(x: float, y: float, seed: int = 0) -> float:
    # Ruido determinista de 0 a 1 (siempre sale la misma veta).
    v = math.sin(x * 12.9898 + y * 78.233 + seed * 37.719) * 43758.5453
    return v - math.floor(v)


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


def to_object(name: str, bm: bmesh.types.BMesh, parent, material, smooth: bool = True):
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    mesh.materials.append(material)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.parent = parent
    for p in mesh.polygons:
        p.use_smooth = smooth
    mesh.set_sharp_from_angle(angle=math.radians(30))
    return obj


def streak(x: float, y: float) -> float:
    # Patrón suave y continuo (0–1) para pintar vetas alargadas en vez de casillas sueltas.
    v = math.sin(x * 2.1 + y * 0.9) + math.sin(y * 2.7 - x * 1.3 + 1.7) * 0.7
    return (v + 1.7) / 3.4


def height_at(r: float, a: float) -> float:
    # Suave y baja: sube un poco hacia el centro y baja a 0 en el contorno, para que se funda con el suelo.
    t = min(r / RADIUS, 1.0)
    return 0.13 * (1.0 - t * t) ** 1.5 + 0.02 * (noise(math.cos(a) * r, math.sin(a) * r, 1) - 0.5) * (1.0 - t)


def build_slab(parent, mat):
    # Malla radial (anillos y sectores) con el contorno irregular: redondeada, no cuadrada.
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new("UVMap")
    rings = [0.0, 0.35, 0.7, 1.0, 1.25, 1.42]
    contour = [1.0 + 0.06 * math.sin(3 * a + 0.7) + 0.04 * math.sin(5 * a + 2.1)
               for a in [2 * math.pi * k / SECTORS for k in range(SECTORS)]]
    grid = []
    for ri, r in enumerate(rings):
        row = []
        for k in range(SECTORS):
            a = 2 * math.pi * k / SECTORS
            rr = r * contour[k] if ri > 0 else 0.0
            row.append(bm.verts.new((rr * math.cos(a), rr * math.sin(a), height_at(rr, a))))
            if ri == 0:
                break
        grid.append(row)
    for ri in range(1, len(rings)):
        for k in range(SECTORS):
            k2 = (k + 1) % SECTORS
            if ri == 1:
                f = bm.faces.new((grid[0][0], grid[1][k], grid[1][k2]))
            else:
                f = bm.faces.new((grid[ri - 1][k], grid[ri][k], grid[ri][k2], grid[ri - 1][k2]))
            c = f.calc_center_median()
            if ri == len(rings) - 1:
                color = EDGE[0] if noise(k, ri, 9) < 0.6 else EDGE[1]           # contorno: hierba, para fundirse
            elif streak(c.x, c.y) > 0.78 - 0.04 * ri:
                color = MALACHITE[0] if streak(c.x + 3.0, c.y) > 0.5 else MALACHITE[1]   # vetas verdes continuas
            else:
                color = ROCK[0] if streak(c.y + 5.0, c.x) > 0.35 else ROCK[1]
            for loop in f.loops:
                loop[uv].uv = swatch_uv(*color)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    for f in bm.faces:
        if f.normal.z < 0:
            f.normal_flip()
    return to_object("vein_slab", bm, parent, mat, smooth=True)


def crystal(bm, uv, base: Vector, tilt_x: float, tilt_y: float, r: float, h: float, color) -> None:
    # Prisma hexagonal con punta, inclinado.
    m = Matrix.Translation(base) @ Matrix.Rotation(tilt_y, 4, "Y") @ Matrix.Rotation(tilt_x, 4, "X")
    ring_b = [bm.verts.new(m @ Vector((r * math.cos(a), r * math.sin(a), -0.1))) for a in
              [math.radians(60 * k) for k in range(6)]]
    ring_t = [bm.verts.new(m @ Vector((r * math.cos(a), r * math.sin(a), h * 0.75))) for a in
              [math.radians(60 * k) for k in range(6)]]
    tip = bm.verts.new(m @ Vector((0.0, 0.0, h)))
    faces = []
    for i in range(6):
        j = (i + 1) % 6
        faces.append(bm.faces.new((ring_b[i], ring_b[j], ring_t[j], ring_t[i])))
        faces.append(bm.faces.new((ring_t[i], ring_t[j], tip)))
    faces.append(bm.faces.new(list(reversed(ring_b))))
    bmesh.ops.recalc_face_normals(bm, faces=faces)
    for f in faces:
        for loop in f.loops:
            loop[uv].uv = swatch_uv(*color)


def build_crystals(parent, mat):
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new("UVMap")
    top = height_at(0.0, 0.0)
    # Más bajos y más anchos que en la primera versión (César).
    # (x, y, inclinación x, inclinación y, radio, alto, color): el grande en el centro y otros alrededor.
    specs = [
        (0.0, 0.0, 0.0, 0.0, 0.17, 0.65, CRYSTAL[0]),
        (0.22, 0.1, -0.15, 0.5, 0.12, 0.45, CRYSTAL[1]),
        (-0.2, 0.16, -0.45, -0.35, 0.13, 0.5, CRYSTAL[2]),
        (-0.12, -0.22, 0.5, -0.15, 0.1, 0.38, CRYSTAL[1]),
        (0.18, -0.18, 0.4, 0.4, 0.09, 0.32, CRYSTAL[0]),
        (0.36, -0.02, 0.0, 0.8, 0.08, 0.24, CRYSTAL[2]),
        (-0.36, -0.04, 0.1, -0.8, 0.08, 0.26, CRYSTAL[0]),
    ]
    for x, y, tx, ty, r, h, color in specs:
        crystal(bm, uv, Vector((x, y, top - 0.02)), tx, ty, r, h, color)
    return to_object("vein_crystals", bm, parent, mat, smooth=False)


def clear_previous() -> None:
    root = bpy.data.objects.get(ROOT)
    if root is None:
        return
    for obj in list(root.children_recursive) + [root]:
        data = obj.data
        bpy.data.objects.remove(obj, do_unlink=True)
        if data is not None and data.users == 0:
            bpy.data.meshes.remove(data)


def build() -> None:
    clear_previous()
    mat = get_material()
    root = bpy.data.objects.new(ROOT, None)
    root.empty_display_type = "PLAIN_AXES"
    root.empty_display_size = 0.5
    bpy.context.collection.objects.link(root)
    build_slab(root, mat)
    build_crystals(root, mat)
    tris = sum(sum(len(p.vertices) - 2 for p in c.data.polygons) for c in root.children if c.type == "MESH")
    print("veta: triángulos:", tris)


build()
