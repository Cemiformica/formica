# Escala de mano por módulos (C5.6b, D-187; sesión 27). Cada módulo mide 1 casilla de alto (1 m) y se apilan para dar
# la altura que se quiera (César): la escala reparable junto a la cascada son 6 módulos con sus remates, y al repararla
# se desbloquea la escala de mano del modo construcción, con los mismos módulos.
#   - ladder_mid: el módulo de 1 m. Dos largueros hexagonales en X = ±RAIL_X, tres peldaños, dos grapas que se clavan en
#     la pared (+Y) y la cruz de dos lazos de cuerda donde cada peldaño cruza cada larguero. El origen, en
#     el centro del módulo a ras de su base; la pared queda en +Y y el jugador sube desde -Y.
#   - ladder_top: el remate de arriba, que se pone encima del último módulo, ya sobre el borde: los largueros siguen
#     TOP_HEIGHT más como asideros y acaban en la cabeza del poste de la valla (cuello, cabeza, capuchón hexagonal de
#     arcilla y antenas). Lleva un peldaño atado a 0,17 para que el paso siga igual que en los módulos.
#   - ladder_foot: el remate de abajo, bajo el primer módulo: una piedra plana medio enterrada bajo cada larguero y un
#     guijarro. El origen, como en los módulos, en el centro a ras del suelo.
#   - ladder_wreck: la escala vieja caída al pie antes de repararla (decorado): un trozo con dos peldaños aún atados, el
#     otro larguero partido con su punta astillada tirada al lado, peldaños sueltos y un cabo de cuerda deshecho. Tumbada
#     delante de la pared (hacia -Y), con el origen donde irá el pie de la escala.
# Mismo estilo y piezas que la barandilla (fence_blockout.py): troncos hexagonales con biseles pequeños, nudos y cuerda
# de esparto (los cuadritos de ROPE_SWATCHES de FenceBuilder). Sombreado suave a 30°.
#
# Uso: con art/props/ladder.blend abierto, Editor de texto → abrir → Alt+P. Borra y rehace la escala.
# Exportar: export_hierarchy("ladder", "//../../assets/models/props/ladder.glb") (export_glb.py).

import bpy
import bmesh
import math
from mathutils import Matrix, Vector

PALETTE = 64
SWATCH = 8
TEXTURE = "//../../assets/textures/palette.png"
SURFACE = "//../../assets/textures/palette_surface.png"

# Cuadritos de la paleta (fila, columna), los mismos que fence_blockout.py.
PLANK, PLANK_GRAIN, WOOD_END = (0, 2), (0, 4), (0, 1)
BARK, BARK_DARK = (0, 5), (0, 6)
ROPE_A, ROPE_B = (0, 1), (0, 0)   # esparto, como ROPE_SWATCHES de FenceBuilder
CLAY = (4, 2)
STONE, STONE_LIGHT, STONE_DARK = (1, 4), (1, 3), (1, 6)

ROOT = "ladder"
MODULE = 1.0            # alto de un módulo (1 casilla)
RAIL_X = 0.24           # medio ancho entre los ejes de los largueros
RAIL_RADIUS = 0.045
RUNG_RADIUS = 0.03
RUNG_OUT = 0.05         # lo que asoma el peldaño por fuera de cada larguero
RUNG_Z = (0.17, 0.50, 0.83)
CLAMP_Z = 0.58          # altura de las grapas
CLAMP_LENGTH = 0.15     # del larguero a la pared
ROPE_MINOR = 0.012      # grosor de la cuerda, el de FenceBuilder
ROPE_GAP = 0.004
TOP_HEIGHT = 0.80       # lo que siguen los largueros por encima del borde, hasta el cuello
# Cuello y cabeza del poste de la valla a la medida del larguero (radio, altura sobre la base del remate).
TOP_HEAD = [(0.046, TOP_HEIGHT), (0.040, TOP_HEIGHT + 0.03), (0.062, TOP_HEIGHT + 0.08), (0.066, TOP_HEIGHT + 0.15),
            (0.052, TOP_HEIGHT + 0.20)]
TOP_CAP = TOP_HEIGHT + 0.20


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


def ring(major, minor, segments=8, section=4, angle=0.0):
    # Vuelta de cuerda alrededor del eje Z: un toro low-poly (segments × section caras), como _rope_ring de FenceBuilder.
    bm = bmesh.new()
    loops = []
    for i in range(segments):
        a = angle + 2.0 * math.pi * i / segments
        center = Vector((major * math.cos(a), major * math.sin(a), 0.0))
        out = Vector((math.cos(a), math.sin(a), 0.0))
        loop = []
        for k in range(section):
            b = 2.0 * math.pi * k / section + math.pi / section
            loop.append(bm.verts.new(center + out * (minor * math.cos(b)) + Vector((0, 0, minor * math.sin(b)))))
        loops.append(loop)
    for i in range(segments):
        a, b = loops[i], loops[(i + 1) % segments]
        for k in range(section):
            m = (k + 1) % section
            bm.faces.new((a[k], b[k], b[m], a[m]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def lash(minor, along, across, diagonal, segments=8, section=4):
    # Lazo cerrado de cuerda en elipse, en el plano de la diagonal `diagonal` (radio `along`) y del eje Y (radio
    # `across`): pasa por delante y por detrás del cruce de dos troncos. Dos, con las diagonales cruzadas, hacen la cruz
    # de la barandilla (D-214).
    d = Vector(diagonal).normalized()
    y = Vector((0.0, 1.0, 0.0))
    n = d.cross(y)
    bm = bmesh.new()
    loops = []
    for i in range(segments):
        a = 2.0 * math.pi * i / segments
        center = d * (along * math.cos(a)) + y * (across * math.sin(a))
        out = (d * (math.cos(a) / along) + y * (math.sin(a) / across)).normalized()
        loop = []
        for k in range(section):
            b = 2.0 * math.pi * k / section + math.pi / section
            loop.append(bm.verts.new(center + out * (minor * math.cos(b)) + n * (minor * math.sin(b))))
        loops.append(loop)
    for i in range(segments):
        a, b = loops[i], loops[(i + 1) % segments]
        for k in range(section):
            m = (k + 1) % section
            bm.faces.new((a[k], b[k], b[m], a[m]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def lathe(profile, sides, angle=0.0):
    # Sólido de revolución cerrado por abajo y por arriba, como en fence_blockout.py.
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
    # Palito por tramos (antenas), como en fence_blockout.py.
    bm = bmesh.new()
    for k, (a, b) in enumerate(zip(points, points[1:])):
        a, b = Vector(a), Vector(b)
        piece = prism(sides, radius * (1.0 - 0.3 * k), radius * (1.0 - 0.3 * (k + 1)), 0.0, (b - a).length, math.radians(45))
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


def moved(bm, matrix):
    bmesh.ops.transform(bm, matrix=matrix, verts=bm.verts)
    return bm


# --- Piezas ---

def module(root, mat):
    pivot = empty("ladder_mid", root)
    lying = Matrix.Rotation(math.radians(90), 4, "Y")   # el prisma, de +Z a +X
    # Largueros: de 0 a 1 m justos, para que al apilar los módulos se lean como un solo tronco. Un nudo en cada uno,
    # a alturas distintas, para que no parezcan dos copias.
    for k, side in enumerate((-1, 1)):
        bm = moved(prism(6, RAIL_RADIUS, RAIL_RADIUS, 0.0, MODULE, math.radians(30 + 13 * k)),
                   Matrix.Translation((side * RAIL_X, 0.0, 0.0)))
        finish("ladder_mid_rail_%d" % k, bm, BARK, pivot, mat, 0.006)
        knot = prism(5, RAIL_RADIUS * 0.45, RAIL_RADIUS * 0.3, 0.0, 0.02, 0.0)
        face = Matrix.Rotation(math.radians(90 if k == 0 else -90), 4, "X")   # sale hacia el jugador o hacia la pared
        knot = moved(knot, Matrix.Translation((side * RAIL_X, (-1 if k == 0 else 1) * RAIL_RADIUS * 0.85, 0.36 + 0.3 * k)) @ face)
        finish("ladder_mid_knot_%d" % k, knot, BARK_DARK, pivot, mat)
    # Peldaños: atraviesan los largueros y asoman un poco por fuera, cada uno girado distinto.
    half = RAIL_X + RAIL_RADIUS + RUNG_OUT
    for k, z in enumerate(RUNG_Z):
        bm = prism(6, RUNG_RADIUS, RUNG_RADIUS * 0.94, -half, half, math.radians(11 * k))
        bm = moved(bm, Matrix.Translation((0.0, 0.0, z)) @ lying)
        finish("ladder_mid_rung_%d" % k, bm, PLANK_GRAIN, pivot, mat, 0.005)
    # Grapas: una cuña de madera por larguero, del larguero a la pared, algo inclinada hacia abajo como una estaca.
    for k, side in enumerate((-1, 1)):
        bm = prism(4, 0.022, 0.015, 0.0, CLAMP_LENGTH + RAIL_RADIUS, math.radians(45))
        tilt = Matrix.Rotation(math.radians(-90 - 12), 4, "X")   # de +Z a +Y, con la punta un poco más baja
        bm = moved(bm, Matrix.Translation((side * RAIL_X, 0.0, CLAMP_Z)) @ tilt)
        finish("ladder_mid_clamp_%d" % k, bm, PLANK, pivot, mat, 0.004)
    # Cuerda: la cruz de dos lazos cerrados de la barandilla (D-214) donde cada peldaño cruza cada larguero (César: en
    # todos los peldaños). Los lazos van apretados: por delante y por detrás rozan el larguero y
    # en las puntas de la diagonal se meten un poco en la madera, como una cuerda que muerde (igual que en la valla).
    rail_r = RAIL_RADIUS / math.cos(math.pi / 6)
    along = rail_r * 1.1 + ROPE_MINOR
    across = rail_r + ROPE_MINOR + 0.002
    for r, z in enumerate(RUNG_Z):
        for k, side in enumerate((-1, 1)):
            for turn, diagonal in enumerate(((1.0, 0.0, 1.0), (1.0, 0.0, -1.0))):
                bm = moved(lash(ROPE_MINOR, along, across, diagonal), Matrix.Translation((side * RAIL_X, 0.0, z)))
                finish("ladder_mid_rope_%d_%d_%d" % (r, k, turn), bm, ROPE_A if turn == 0 else ROPE_B, pivot, mat)


def rope_cross(pivot, mat, prefix, z):
    # La cruz de dos lazos en los dos largueros a la altura z (la de los peldaños de ladder_mid).
    rail_r = RAIL_RADIUS / math.cos(math.pi / 6)
    along = rail_r * 1.1 + ROPE_MINOR
    across = rail_r + ROPE_MINOR + 0.002
    for k, side in enumerate((-1, 1)):
        for turn, diagonal in enumerate(((1.0, 0.0, 1.0), (1.0, 0.0, -1.0))):
            bm = moved(lash(ROPE_MINOR, along, across, diagonal), Matrix.Translation((side * RAIL_X, 0.0, z)))
            finish("%s_rope_%d_%d" % (prefix, k, turn), bm, ROPE_A if turn == 0 else ROPE_B, pivot, mat)


def top(root, mat):
    pivot = empty("ladder_top", root)
    lying = Matrix.Rotation(math.radians(90), 4, "Y")
    for k, side in enumerate((-1, 1)):
        at = Matrix.Translation((side * RAIL_X, 0.0, 0.0))
        bm = moved(prism(6, RAIL_RADIUS, RAIL_RADIUS * 0.95, 0.0, TOP_HEIGHT, math.radians(30 + 13 * k)), at)
        finish("ladder_top_rail_%d" % k, bm, BARK, pivot, mat, 0.006)
        # Cabeza del poste de la valla: así los asideros son de la misma familia que la barandilla.
        finish("ladder_top_head_%d" % k, moved(lathe(TOP_HEAD, 8, math.radians(22.5)), at), PLANK_GRAIN, pivot, mat)
        cap = prism(6, 0.054, 0.049, TOP_CAP - 0.005, TOP_CAP + 0.035, math.radians(30))
        finish("ladder_top_cap_%d" % k, moved(cap, at), CLAY, pivot, mat, 0.005)
        # Antenas: dos por cabeza, como en el poste de la valla, que se abren a los lados con la punta algo caída.
        for a, lean in enumerate((-1, 1)):
            pts = [(lean * 0.025, 0.0, TOP_CAP + 0.015), (lean * 0.07, -0.01, TOP_CAP + 0.13), (lean * 0.14, -0.02, TOP_CAP + 0.17)]
            finish("ladder_top_antenna_%d_%d" % (k, a), moved(stick(pts, 0.015), at), BARK_DARK, pivot, mat)
    bm = prism(6, RUNG_RADIUS, RUNG_RADIUS * 0.94, -(RAIL_X + RAIL_RADIUS + RUNG_OUT), RAIL_X + RAIL_RADIUS + RUNG_OUT)
    finish("ladder_top_rung", moved(bm, Matrix.Translation((0.0, 0.0, RUNG_Z[0])) @ lying), PLANK_GRAIN, pivot, mat, 0.005)
    rope_cross(pivot, mat, "ladder_top", RUNG_Z[0])


def foot(root, mat):
    pivot = empty("ladder_foot", root)
    # Una piedra plana bajo cada larguero, medio enterrada y cada una de su tono y su giro, y un guijarro al lado.
    # Bajas y del tono de las rocas de la isla (las claras parecían bases de cemento).
    stones = [((-RAIL_X, 0.01), 0.12, 0.10, 7, 10, STONE), ((RAIL_X + 0.01, -0.01), 0.115, 0.095, 6, 37, STONE_DARK),
              ((-RAIL_X - 0.13, -0.08), 0.05, 0.04, 5, 20, STONE_LIGHT)]
    for k, ((x, y), rx, ry, sides, turn, color) in enumerate(stones):
        top_z = 0.018 if k < 2 else 0.022
        bm = prism(sides, 1.0, 0.82, -0.05, top_z, math.radians(turn))
        bmesh.ops.scale(bm, vec=(rx, ry, 1.0), verts=bm.verts)
        bm = moved(bm, Matrix.Translation((x, y, 0.0)) @ Matrix.Rotation(math.radians(turn * 1.7), 4, "Z"))
        finish("ladder_foot_stone_%d" % k, bm, color, pivot, mat, 0.01)


def splintered(sides, radius, length, angle, seed):
    # Tronco de +Z partido en la punta: los vértices de arriba a alturas distintas, como una astilla.
    bm = prism(sides, radius, radius * 0.95, 0.0, length, angle)
    tops = sorted([v for v in bm.verts if v.co.z > length * 0.5], key=lambda v: math.atan2(v.co.y, v.co.x))
    cuts = (0.0, -0.09, -0.03, -0.12, -0.05, 0.02)
    for i, v in enumerate(tops):
        v.co.z += cuts[(i + seed) % len(cuts)]
    return bm


def wreck(root, mat):
    pivot = empty("ladder_wreck", root)
    lying = Matrix.Rotation(math.radians(90), 4, "Y")              # prisma de +Z a +X
    across = Matrix.Rotation(math.radians(-90), 4, "X")            # prisma de +Z a +Y
    # El trozo grande: dos largueros a lo largo de X (uno partido) con dos peldaños aún atados. Se gira entero.
    frag = Matrix.Translation((0.05, -0.75, 0.0)) @ Matrix.Rotation(math.radians(14), 4, "Z")
    lie = RAIL_RADIUS * 0.85                                       # medio hundido en la hierba
    rails = [(-0.24, 1.55, False), (0.24, 0.95, True)]             # (y, largo, partido)
    for k, (y, length, broken) in enumerate(rails):
        bm = splintered(6, RAIL_RADIUS, length, math.radians(30 + 13 * k), k) if broken else \
            prism(6, RAIL_RADIUS, RAIL_RADIUS * 0.95, 0.0, length, math.radians(30 + 13 * k))
        bm = moved(bm, frag @ Matrix.Translation((-0.8, y, lie)) @ lying)
        finish("ladder_wreck_rail_%d" % k, bm, BARK_DARK, pivot, mat, 0.006)
    half = RAIL_X + RAIL_RADIUS + RUNG_OUT
    swap = Matrix(((0, 0, 1, 0), (1, 0, 0, 0), (0, 1, 0, 0), (0, 0, 0, 1)))   # cruz: larguero Z→X, peldaño X→Y, Y→Z
    rail_r = RAIL_RADIUS / math.cos(math.pi / 6)
    for r, x in enumerate((-0.62, -0.28)):
        bm = prism(6, RUNG_RADIUS, RUNG_RADIUS * 0.94, -half, half, math.radians(11 * r))
        bm = moved(bm, frag @ Matrix.Translation((x, 0.0, lie)) @ across)
        finish("ladder_wreck_rung_%d" % r, bm, PLANK, pivot, mat, 0.005)
    # Una sola cruz entera (en el primer peldaño, larguero de -Y); las demás se deshicieron.
    for turn, diagonal in enumerate(((1.0, 0.0, 1.0), (1.0, 0.0, -1.0))):
        bm = lash(ROPE_MINOR, rail_r * 1.1 + ROPE_MINOR, rail_r + ROPE_MINOR + 0.002, diagonal)
        bm = moved(bm, frag @ Matrix.Translation((-0.62, -0.24, lie)) @ swap)
        finish("ladder_wreck_rope_%d" % turn, bm, ROPE_A if turn == 0 else ROPE_B, pivot, mat)
    # La punta del larguero partido, tirada más allá con la astilla hacia el trozo grande.
    bm = splintered(6, RAIL_RADIUS, 0.5, math.radians(40), 3)
    bm = moved(bm, Matrix.Translation((0.95, -1.15, lie)) @ Matrix.Rotation(math.radians(200), 4, "Z") @ lying)
    finish("ladder_wreck_tip", bm, BARK_DARK, pivot, mat, 0.006)
    # Peldaños sueltos por la hierba, cada uno con su giro.
    for r, (x, y, turn) in enumerate(((0.55, -0.35, 72), (0.85, -0.72, 118), (-0.45, -1.35, 31))):
        bm = prism(6, RUNG_RADIUS, RUNG_RADIUS * 0.94, -half, half, math.radians(7 * r))
        bm = moved(bm, Matrix.Translation((x, y, RUNG_RADIUS * 0.8)) @ Matrix.Rotation(math.radians(turn), 4, "Z") @ lying)
        finish("ladder_wreck_loose_%d" % r, bm, PLANK if r != 1 else PLANK_GRAIN, pivot, mat, 0.005)
    # Un cabo de cuerda deshecho, culebreando entre los peldaños sueltos.
    path = [Vector((0.25, -0.15, 0.01)), Vector((0.4, -0.28, 0.012)), Vector((0.5, -0.5, 0.01)), Vector((0.68, -0.55, 0.014)),
            Vector((0.78, -0.42, 0.01))]
    bm = bmesh.new()
    for a, b in zip(path, path[1:]):
        piece = prism(4, ROPE_MINOR, ROPE_MINOR, 0.0, (b - a).length + ROPE_MINOR, math.radians(45))
        rot = Vector((0, 0, 1)).rotation_difference((b - a).normalized()).to_matrix().to_4x4()
        bmesh.ops.transform(piece, matrix=Matrix.Translation(a + Vector((0, 0, ROPE_MINOR))) @ rot, verts=piece.verts)
        tmp = bpy.data.meshes.new("tmp")
        piece.to_mesh(tmp)
        piece.free()
        bm.from_mesh(tmp)
        bpy.data.meshes.remove(tmp)
    finish("ladder_wreck_rope_loose", bm, ROPE_A, pivot, mat)


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
    module(root, mat)
    top(root, mat)
    foot(root, mat)
    wreck(root, mat)
    for name in ("ladder_mid", "ladder_top", "ladder_foot", "ladder_wreck"):
        pivot = bpy.data.objects[name]
        tris = sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in pivot.children_recursive if o.type == "MESH")
        print(name, tris, "triángulos")


build()
