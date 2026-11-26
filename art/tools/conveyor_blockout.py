# Blockout de la cinta transportadora básica (B3.7). Tramo recto de una casilla, a juego con los puertos
# (César: toda la logística comparte aspecto): artesa gris del Nexo con perfil de MEDIO HEXÁGONO (la mitad
# de abajo de la boca de los puertos, D-079), paredes gruesas con larguero naranja y remaches
# hexagonales, dos traviesas con pies y la banda («belt_band», con su propio material para que Godot la
# haga avanzar).
# La banda es una superficie sin grosor (sin cantos) y su parte recta acaba donde empiezan las curvas.
# En cada extremo hay dos piezas que Godot alterna: la «vuelta de banda» (belt_end_front / belt_end_back),
# medio cilindro alrededor de un eje, si ese extremo está SIN conectar (para que se vea girar, César); y un
# tramo recto corto (belt_join_front / belt_join_back) si está conectado, para que la banda siga continua.
# Convenciones de la guía de arte: origen en el centro de la casilla a ras de suelo; la cinta sin girar
# avanza hacia el NORTE (+Y en Blender): entrada al sur, salida al norte. Va de borde a borde.
# Los números del perfil están también en port_blockout.py (lengüeta): si cambian aquí, cambiarlos allí.
#
# Uso: Editor de texto de Blender → abrir → Alt+P. Si ya existe «conveyor», lo borra y lo rehace.
# Exportar: export_hierarchy("conveyor", "//../../assets/models/buildings/conveyor.glb") de export_glb.py.
# Dónde tocar: medidas en las constantes; colores de la paleta como (fila, columna).

import bpy
import bmesh
import math
from mathutils import Matrix, Vector

PALETTE = 64
SWATCH = 8
PALETTE_PATH = "//../../assets/textures/palette.png"
BAND_TEXTURE_PATH = "//../../assets/textures/belt_band.png"
ROOT = "conveyor"

BAND_HALF = 0.19        # banda de 0,38 m (fondo plano de la artesa)
BAND_TOP = 0.125        # superficie de la banda
BAND_THICK = 0.01
# v2 (César: «parece frágil, de plástico»): paredes más gruesas y algo más bajas, con un larguero naranja
# a cada lado, y dos traviesas con pies bajo la artesa en vez de un pie central.
WALL_TOP_X = 0.27       # borde interior de la pared, arriba
WALL_TOP_Z = 0.23
LIP = 0.08              # grosor de la pared (borde superior plano, como un perfil de acero)
SHELL_BOTTOM = (0.29, 0.06)   # media anchura y altura del fondo exterior de la artesa
OUTER_KNEE_Z = 0.13     # altura donde la cara exterior deja de ser vertical y se recoge hacia el fondo
ROLLER_R = 0.06         # radio de la vuelta de banda en los extremos
TEX_PER_M = 2           # repeticiones de la textura de la banda por metro (cada una: nervio + chevrón)

FRAME, RIVET, FOOT = (5, 3), (5, 5), (5, 4)   # los mismos grises que el puerto estándar
ACCENT = (4, 2)         # naranja del horno y del extractor: el acento de toda la maquinaria


def swatch_uv(row, col):
    return Vector(((col * SWATCH + SWATCH / 2) / PALETTE, 1.0 - (row * SWATCH + SWATCH / 2) / PALETTE))


def _image_material(name, path, roughness):
    img = bpy.data.images.load(path, check_existing=True)
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial"); out.location = (300, 0)
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled"); bsdf.location = (0, 0)
    tex = nt.nodes.new("ShaderNodeTexImage"); tex.location = (-350, 0)
    tex.image = img
    tex.interpolation = "Closest"
    bsdf.inputs["Roughness"].default_value = roughness
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    return mat


def palette_material():
    return bpy.data.materials.get("palette") or _image_material("palette", PALETTE_PATH, 0.8)


def band_material():
    return bpy.data.materials.get("belt_band") or _image_material("belt_band", BAND_TEXTURE_PATH, 0.9)


def hex_rivet(center, normal, r: float = 0.017, depth: float = 0.02, bm=None):
    # Remache o tornillo HEXAGONAL (guía de arte: nada de cubitos): prisma de 6 lados con el eje en
    # `normal`, medio hundido en la superficie. Con `bm`, se añade a esa malla y devuelve sus caras.
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


def box(size, center):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
    bmesh.ops.translate(bm, vec=Vector(center), verts=bm.verts)
    return bm


def prism_x_profile(profile, y0, y1):
    # Extruye un perfil (puntos X, Z) a lo largo de Y, de y0 a y1, con tapas.
    bm = bmesh.new()
    back = [bm.verts.new((x, y0, z)) for x, z in profile]
    front = [bm.verts.new((x, y1, z)) for x, z in profile]
    bm.faces.new(back)
    bm.faces.new(list(reversed(front)))
    for i in range(len(profile)):
        j = (i + 1) % len(profile)
        bm.faces.new((back[i], back[j], front[j], front[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def prism_y_profile(profile, x0, x1):
    # Como prism_x_profile, pero el perfil son puntos (Y, Z) y se extruye a lo largo de X (garganta).
    bm = bmesh.new()
    back = [bm.verts.new((x0, y, z)) for y, z in profile]
    front = [bm.verts.new((x1, y, z)) for y, z in profile]
    bm.faces.new(back)
    bm.faces.new(list(reversed(front)))
    for i in range(len(profile)):
        j = (i + 1) % len(profile)
        bm.faces.new((back[i], back[j], front[j], front[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def band_strip_x(x0, x1):
    # Banda recta a lo ancho (a lo largo de X), de x0 a x1: la de la garganta.
    bm = bmesh.new()
    v = [bm.verts.new((x0, -BAND_HALF, BAND_TOP)), bm.verts.new((x1, -BAND_HALF, BAND_TOP)),
         bm.verts.new((x1, BAND_HALF, BAND_TOP)), bm.verts.new((x0, BAND_HALF, BAND_TOP))]
    face = bm.faces.new(v)
    face.normal_update()
    if face.normal.z < 0.0:
        face.normal_flip()
    return bm


def join_parts(name, objects, parent, material):
    # Une varias piezas (de colores distintos de la paleta) en una sola malla: Godot la enseña o la
    # esconde entera y la dibuja en una sola llamada.
    bm = bmesh.new()
    for obj in objects:
        bm.from_mesh(obj.data)
    for obj in objects:
        mesh = obj.data
        bpy.data.objects.remove(obj, do_unlink=True)
        bpy.data.meshes.remove(mesh)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    mesh.materials.append(material)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.parent = parent
    for poly in mesh.polygons:
        poly.use_smooth = True
    mesh.set_sharp_from_angle(angle=math.radians(30))
    return obj


# --- Curvas en L (C2b): la cinta recta doblada un cuarto de vuelta ---
# Una cinta con una sola entrada y una sola salida que no están en línea se dibuja como una curva (César:
# como en Alchemy Factory). Se modelan dos, con la entrada por detrás (sur) y la salida a la izquierda
# (oeste, «left») o a la derecha (este, «right»); Godot las gira para los demás casos. Se construyen las
# piezas rectas con cortes a lo largo y luego se doblan: el eje de la cinta pasa a ser un arco de radio
# 0,5 alrededor de la esquina de la casilla, y lo que estaba a la derecha queda por fuera.
CORNER_SEGMENTS = 6     # cortes del cuarto de vuelta (15° cada uno: por debajo de los 30° del suavizado)


def seg_prism(profile, y0, y1, n):
    # Perfil (X, Z) extruido a lo largo de Y con n tramos (para poder doblarlo).
    bm = bmesh.new()
    rings = []
    for k in range(n + 1):
        y = y0 + (y1 - y0) * k / n
        rings.append([bm.verts.new((x, y, z)) for x, z in profile])
    bm.faces.new(rings[0])
    bm.faces.new(list(reversed(rings[-1])))
    for k in range(n):
        a, b = rings[k], rings[k + 1]
        for i in range(len(profile)):
            j = (i + 1) % len(profile)
            bm.faces.new((a[i], a[j], b[j], b[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def rect_profile(cx, cz, w, h):
    return [(cx - w / 2, cz - h / 2), (cx + w / 2, cz - h / 2), (cx + w / 2, cz + h / 2), (cx - w / 2, cz + h / 2)]


def bevel_sharp(bm, offset):
    # Bisel solo en las aristas vivas (no en los cortes planos que se añaden para doblar).
    edges = [e for e in bm.edges if len(e.link_faces) == 2 and e.calc_face_angle(0.0) > math.radians(10)]
    bmesh.ops.bevel(bm, geom=edges, offset=offset, segments=1, affect="EDGES", profile=0.5, clamp_overlap=True)
    return bm


def bend(bm, turn):
    # Dobla la cinta recta (de y = −0,5 a 0,5) un cuarto de vuelta: turn = 1 gira a la izquierda (sale
    # por el oeste), −1 a la derecha (sale por el este). La entrada sigue en el borde sur.
    for v in bm.verts:
        x, y, z = v.co
        angle = (y + 0.5) * math.pi / 2
        if turn > 0:
            r = 0.5 + x
            v.co = Vector((-0.5 + r * math.cos(angle), -0.5 + r * math.sin(angle), z))
        else:
            r = 0.5 - x
            v.co = Vector((0.5 - r * math.cos(angle), -0.5 + r * math.sin(angle), z))
    bm.normal_update()
    return bm


def add_band_uv(bm):
    # UV de la banda ANTES de doblarla: u a lo ancho, v a lo largo (por casilla, como la recta, para que
    # la banda vaya al paso de los ítems).
    uv = bm.loops.layers.uv.new("UVMap")
    for f in bm.faces:
        for loop in f.loops:
            co = loop.vert.co
            loop[uv].uv = Vector(((co.x + BAND_HALF) / (2 * BAND_HALF), (co.y + 0.5) * TEX_PER_M))
    return bm


def band_strip_segments(y0, y1, n):
    bm = bmesh.new()
    rows = [[bm.verts.new((-BAND_HALF, y0 + (y1 - y0) * k / n, BAND_TOP)),
             bm.verts.new((BAND_HALF, y0 + (y1 - y0) * k / n, BAND_TOP))] for k in range(n + 1)]
    for k in range(n):
        bm.faces.new((rows[k][0], rows[k][1], rows[k + 1][1], rows[k + 1][0]))
    bm.normal_update()
    for face in bm.faces:
        if face.normal.z < 0.0:
            face.normal_flip()
    return bm


def build_corner(root, pal, band, turn, wall_profiles):
    # Curva completa: cuerpo (paredes, largueros, remaches, fondo y traviesa en una malla), banda (de la
    # entrada hasta donde empieza el extremo de salida) y, en la salida, la vuelta de banda o el tramo de
    # unión. La entrada siempre está conectada (por eso es una L), así que no tiene vuelta de banda.
    name = "belt_corner_" + ("left" if turn > 0 else "right")
    n = CORNER_SEGMENTS
    bx, bz = SHELL_BOTTOM
    floor_z = BAND_TOP - BAND_THICK
    xo = WALL_TOP_X + LIP
    parts = []
    for sx, wall in wall_profiles:
        parts.append(make("tmp_corner_wall", bend(bevel_sharp(seg_prism(wall, -0.5, 0.5, n), 0.008), turn), root, pal, FRAME))
        # Larguero sin bisel y sin remaches: en la curva apenas se ven y ahorran ~300 triángulos.
        rail = seg_prism(rect_profile(sx * (xo + 0.012), 0.175, 0.03, 0.055), -0.5, 0.5, n)
        parts.append(make("tmp_corner_rail", bend(rail, turn), root, pal, ACCENT))
    floor = seg_prism(rect_profile(0.0, (floor_z + bz) / 2, 2 * BAND_HALF, floor_z - bz), -0.5, 0.5 - 2 * ROLLER_R, n)
    parts.append(make("tmp_corner_floor", bend(floor, turn), root, pal, FRAME))
    # Una traviesa en el centro de la curva, con sus pies.
    sleeper = seg_prism(rect_profile(0.0, (bz + 0.02) / 2, 2 * xo + 0.1, bz + 0.02), -0.05, 0.05, 1)
    parts.append(make("tmp_corner_sleeper", bend(bevel_sharp(sleeper, 0.008), turn), root, pal, FOOT))
    for sx in (-1, 1):
        parts.append(make("tmp_corner_foot", bend(hex_rivet((sx * (xo + 0.035), 0.0, (bz + 0.02) + 0.012), (0, 0, 1), 0.03, 0.025), turn),
                          root, pal, RIVET))
    body = join_parts(name, parts, root, pal)
    edge = 0.5 - ROLLER_R
    pieces = [body,
              make(name + "_band", bend(add_band_uv(band_strip_segments(-0.5, edge, n)), turn), root, band, uv_mode="keep"),
              make(name + "_join", bend(add_band_uv(band_strip(edge, 0.5)), turn), root, band, uv_mode="keep"),
              make(name + "_end", bend(roller_band(True), turn), root, band, uv_mode="keep")]
    # En Blender se esconden para que no tapen la cinta recta (Godot elige qué enseñar).
    for piece in pieces:
        piece.hide_set(True)
    return pieces


def hub_post(sx, sy):
    # Poste de la esquina (sx, sy) del cruce: lo que comparten la pared que va a lo largo de Y (perfil de medio
    # hexágono en X) y la que va a lo largo de X (el mismo perfil en Y). Los dos perfiles son convexos, así que
    # el poste es el casco convexo de los puntos donde se cortan tres de sus planos y que caen dentro de todos.
    bx, bz = SHELL_BOTTOM
    floor_z = BAND_TOP - BAND_THICK
    xo = WALL_TOP_X + LIP
    profile = [(xo, WALL_TOP_Z), (WALL_TOP_X, WALL_TOP_Z), (BAND_HALF, floor_z), (BAND_HALF, bz), (bx, bz), (xo, OUTER_KNEE_Z)]
    cx = sum(a for a, _ in profile) / len(profile)
    cz = sum(b for _, b in profile) / len(profile)
    lines = []   # (normal hacia fuera en (u, z), d): u * nu + z * nz <= d
    for i in range(len(profile)):
        (u0, z0), (u1, z1) = profile[i], profile[(i + 1) % len(profile)]
        nu, nz = z1 - z0, -(u1 - u0)
        if nu * (cx - u0) + nz * (cz - z0) > 0.0:
            nu, nz = -nu, -nz
        lines.append((nu, nz, nu * u0 + nz * z0))
    planes = [Vector((sx * nu, 0.0, nz)).to_4d() for nu, nz, _ in lines]
    planes += [Vector((0.0, sy * nu, nz)).to_4d() for nu, nz, _ in lines]
    for k, (_, _, d) in enumerate(lines + lines):
        planes[k].w = d
    points = []
    for a in range(len(planes)):
        for b in range(a + 1, len(planes)):
            for c in range(b + 1, len(planes)):
                m = Matrix((planes[a].xyz, planes[b].xyz, planes[c].xyz))
                if abs(m.determinant()) < 1e-9:
                    continue
                p = m.inverted() @ Vector((planes[a].w, planes[b].w, planes[c].w))
                if all(q.xyz.dot(p) <= q.w + 1e-7 for q in planes) and all((p - o).length > 1e-6 for o in points):
                    points.append(p)
    bm = bmesh.new()
    verts = [bm.verts.new(p) for p in points]
    hull = bmesh.ops.convex_hull(bm, input=verts)
    bmesh.ops.delete(bm, geom=[g for g in hull["geom_interior"] + hull["geom_unused"] if isinstance(g, bmesh.types.BMVert)], context="VERTS")
    bmesh.ops.dissolve_limit(bm, angle_limit=math.radians(1), verts=bm.verts, edges=bm.edges)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


# --- Cruce (C2b): la cinta de una T o una X, como en Alchemy Factory ---
# Estructura del cruce: centro con su base y, en cada lado, una boca abierta o una pared. Las piezas de los
# lados se modelan solo para el lado NORTE (+Y); Godot las copia y las gira para los otros tres. La banda
# del cruce NO está aquí: la crea Godot según el camino (dividida en zonas que avanzan cada una hacia su
# lado, dibujo de César), con el mismo material «belt_band».
def build_hub(root, pal, band, wall_profiles):
    bx, bz = SHELL_BOTTOM
    floor_z = BAND_TOP - BAND_THICK
    xo = WALL_TOP_X + LIP
    pieces = []
    # Centro: fondo bajo la banda y una base con cuatro pies.
    base = [make("tmp_hub_floor", box((2 * BAND_HALF, 2 * BAND_HALF, floor_z - bz), (0.0, 0.0, (floor_z + bz) / 2)), root, pal, FRAME),
            make("tmp_hub_base", box((2 * xo - 0.08, 2 * xo - 0.08, bz + 0.02), (0.0, 0.0, (bz + 0.02) / 2)), root, pal, FOOT, 0.008)]
    for sx in (-1, 1):
        for sy in (-1, 1):
            base.append(make("tmp_hub_foot", hex_rivet((sx * (xo - 0.06), sy * (xo - 0.06), (bz + 0.02) + 0.012), (0, 0, 1), 0.03, 0.025),
                             root, pal, RIVET))
    pieces.append(join_parts("belt_hub", base, root, pal))
    # Postes de la esquina NORESTE (sesión 28, César): llenan el cuadrado entre los lados norte y este, del borde
    # de la banda a la cara de fuera. Antes, las paredes de dos brazos abiertos se pisaban ahí (bulto con una V) y
    # la pared cerrada se montaba sobre la abierta (una cruz). Godot copia y gira las piezas para las otras tres
    # esquinas y enseña, según qué lados estén abiertos:
    #   - los dos abiertos: «miter», el perfil de medio hexágono en las dos direcciones (esquina de un marco);
    #   - norte cerrado: «a», la pared cerrada sigue recta hasta la boca del este (a lo largo de X);
    #   - este cerrado: «b», lo mismo a lo largo de Y. Con los dos cerrados, las dos a la vez.
    top = (WALL_TOP_X + xo) / 2
    miter = [make("tmp_post_miter", hub_post(1, 1), root, pal, FRAME, 0.008),
             make("tmp_post_rivet", hex_rivet((top, top, WALL_TOP_Z), (0, 0, 1), 0.022, 0.012), root, pal, RIVET)]
    pieces.append(join_parts("belt_hub_post_miter", miter, root, pal))
    profile = [(xo, WALL_TOP_Z), (WALL_TOP_X, WALL_TOP_Z), (BAND_HALF, floor_z), (BAND_HALF, bz), (bx, bz), (xo, OUTER_KNEE_Z)]
    pieces.append(join_parts("belt_hub_post_a", [make("tmp_post_a", prism_y_profile(profile, BAND_HALF, xo), root, pal, FRAME, 0.008)],
                             root, pal))
    pieces.append(join_parts("belt_hub_post_b", [make("tmp_post_b", prism_x_profile(profile, BAND_HALF, xo), root, pal, FRAME, 0.008)],
                             root, pal))
    # Boca abierta al norte: dos paredes (el perfil de la cinta) desde el borde del centro hasta el borde de
    # la casilla, sus largueros donde se ven y el fondo bajo la banda.
    arm = []
    for sx, wall in wall_profiles:
        arm.append(make("tmp_arm_wall", prism_x_profile(wall, xo, 0.5), root, pal, FRAME, 0.008))   # desde el poste
        arm.append(make("tmp_arm_rail", box((0.03, 0.5 - xo, 0.055), (sx * (xo + 0.012), (xo + 0.5) / 2, 0.175)), root, pal, ACCENT, 0.006))
    arm.append(make("tmp_arm_floor", box((2 * BAND_HALF, 0.5 - BAND_HALF, floor_z - bz), (0.0, (BAND_HALF + 0.5) / 2, (floor_z + bz) / 2)),
                    root, pal, FRAME))
    pieces.append(join_parts("belt_hub_arm_open", arm, root, pal))
    # Lado cerrado al norte: pared a lo ancho, con su larguero por fuera.
    profile = [(xo, WALL_TOP_Z), (WALL_TOP_X, WALL_TOP_Z), (BAND_HALF, floor_z), (BAND_HALF, bz), (bx, bz), (xo, OUTER_KNEE_Z)]
    closed = [make("tmp_closed_wall", prism_y_profile(profile, -BAND_HALF, BAND_HALF), root, pal, FRAME, 0.008),   # entre los postes
              make("tmp_closed_rail", box((2 * xo, 0.03, 0.055), (0.0, xo + 0.012, 0.175)), root, pal, ACCENT, 0.006)]
    pieces.append(join_parts("belt_hub_arm_closed", closed, root, pal))
    for piece in pieces:
        piece.hide_set(True)
    return pieces


def band_strip(y0, y1):
    # Banda recta: una sola cara hacia arriba (sin grosor, así no tiene cantos), de y0 a y1.
    bm = bmesh.new()
    v = [bm.verts.new((-BAND_HALF, y0, BAND_TOP)), bm.verts.new((BAND_HALF, y0, BAND_TOP)),
         bm.verts.new((BAND_HALF, y1, BAND_TOP)), bm.verts.new((-BAND_HALF, y1, BAND_TOP))]
    face = bm.faces.new(v)
    face.normal_update()
    if face.normal.z < 0.0:
        face.normal_flip()
    return bm


def roller_band(front: bool):
    # Media vuelta de banda alrededor de un eje en X, en el extremo delantero (+Y) o trasero (−Y).
    # Lleva UV de la banda (v sigue la dirección de avance), así sus nervios se mueven con el resto.
    sign = 1.0 if front else -1.0
    cy = sign * (0.5 - ROLLER_R)
    cz = BAND_TOP - ROLLER_R
    steps = 6
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new("UVMap")
    rows = []
    arc = math.pi * ROLLER_R
    for k in range(steps + 1):
        t = k / steps
        a = math.pi / 2 - math.pi * t          # de arriba (90°) a abajo (−90°), pasando por el extremo
        y = cy + sign * ROLLER_R * math.cos(a)
        z = cz + ROLLER_R * math.sin(a)
        # Delante la banda baja (avanza de arriba a abajo); detrás sube (de abajo a arriba).
        if front:
            v = ((0.5 - ROLLER_R) + 0.5 + arc * t) * TEX_PER_M
        else:
            v = ((-0.5 + ROLLER_R) + 0.5 - arc * t) * TEX_PER_M
        rows.append(([bm.verts.new((-BAND_HALF, y, z)), bm.verts.new((BAND_HALF, y, z))], v))
    for k in range(steps):
        (a0, b0), v0 = rows[k]
        (a1, b1), v1 = rows[k + 1]
        face = bm.faces.new((a0, b0, b1, a1))
        for loop in face.loops:
            u = 0.0 if loop.vert in (a0, a1) else 1.0
            loop[uv].uv = Vector((u, v0 if loop.vert in (a0, b0) else v1))
    # Normales hacia fuera del eje.
    bm.normal_update()
    center = Vector((0.0, cy, cz))
    for face in bm.faces:
        if face.normal.dot(face.calc_center_median() - center) < 0.0:
            face.normal_flip()
    return bm


def make(name, bm, parent, material, color=None, bevel=0.0, uv_mode="palette"):
    if bevel > 0.0:
        bmesh.ops.bevel(bm, geom=list(bm.edges), offset=bevel, segments=1, affect="EDGES",
                        profile=0.5, clamp_overlap=True)
    if uv_mode != "keep":
        uv = bm.loops.layers.uv.new("UVMap")
        for f in bm.faces:
            for loop in f.loops:
                if uv_mode == "band":
                    # u: a lo ancho (0–1); v: a lo largo, TEX_PER_M repeticiones por metro.
                    co = loop.vert.co
                    loop[uv].uv = Vector(((co.x + BAND_HALF) / (2 * BAND_HALF), (co.y + 0.5) * TEX_PER_M))
                elif isinstance(uv_mode, tuple):
                    # ("dir", dx, dy): banda que avanza hacia (dx, dy). u crece hacia la derecha del avance
                    # y v hacia el avance, como en la banda principal (derecha = +X, avance = +Y).
                    _, dx, dy = uv_mode
                    co = loop.vert.co
                    along = co.x * dx + co.y * dy
                    across = co.x * dy - co.y * dx
                    loop[uv].uv = Vector(((across + BAND_HALF) / (2 * BAND_HALF), (along + 0.5) * TEX_PER_M))
                else:
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


def build():
    old = bpy.data.objects.get(ROOT)
    if old is not None:
        for child in list(old.children_recursive):
            bpy.data.objects.remove(child, do_unlink=True)
        bpy.data.objects.remove(old, do_unlink=True)
    for leftover in ("Cube",):
        obj = bpy.data.objects.get(leftover)
        if obj is not None:
            bpy.data.objects.remove(obj, do_unlink=True)
    pal = palette_material()
    band = band_material()
    root = bpy.data.objects.new(ROOT, None)
    root.empty_display_type = "PLAIN_AXES"
    bpy.context.collection.objects.link(root)

    bx, bz = SHELL_BOTTOM
    floor_z = BAND_TOP - BAND_THICK
    xo = WALL_TOP_X + LIP   # cara exterior de la pared
    wall_profiles = []      # (lado, perfil) de cada pared, para las curvas
    # Paredes gruesas (perfil de medio hexágono por dentro, cara exterior vertical), de borde a borde. Una
    # cinta recta nunca tiene uniones por los costados: si las tiene, Godot la dibuja como curva o cruce.
    for side, sx in (("east", 1), ("west", -1)):
        wall = [(sx * xo, WALL_TOP_Z), (sx * WALL_TOP_X, WALL_TOP_Z), (sx * BAND_HALF, floor_z),
                (sx * BAND_HALF, bz), (sx * bx, bz), (sx * xo, OUTER_KNEE_Z)]
        if sx < 0:
            wall.reverse()
        wall_profiles.append((sx, wall))
        make("wall_" + side, prism_x_profile(wall, -0.5, 0.5), root, pal, FRAME, 0.008)
        # Larguero naranja a lo largo de la cara exterior, con dos remaches hexagonales grandes.
        make("rail_" + side, box((0.03, 1.0, 0.055), (sx * (xo + 0.012), 0.0, 0.175)), root, pal, ACCENT, 0.006)
        for i, y in enumerate((-0.25, 0.25)):
            make("rivet_%s_%d" % (side, i), hex_rivet((sx * (xo + 0.027), y, 0.175), (sx, 0, 0), 0.02, 0.02),
                 root, pal, RIVET)
    # Fondo bajo la banda, acortado en los extremos para dejar sitio a las vueltas de banda.
    floor_len = 1.0 - 2 * (2 * ROLLER_R)
    make("floor", box((2 * BAND_HALF, floor_len, floor_z - bz), (0.0, 0.0, (floor_z + bz) / 2)), root, pal, FRAME)
    # Dos traviesas bajo la artesa, cerca de los extremos, que asoman a los lados con un pie hexagonal:
    # en una fila de cintas forman un ritmo de apoyos que da peso.
    for i, y in enumerate((-0.36, 0.36)):
        make("sleeper_%d" % i, box((2 * xo + 0.1, 0.1, bz + 0.02), (0.0, y, (bz + 0.02) / 2)), root, pal, FOOT, 0.008)
        for sx in (-1, 1):
            make("sleeper_foot_%d_%d" % (i, sx > 0), hex_rivet((sx * (xo + 0.035), y, (bz + 0.02) + 0.012), (0, 0, 1), 0.03, 0.025),
                 root, pal, RIVET)
    edge = 0.5 - ROLLER_R   # donde acaba la banda recta y empieza la curva (o el tramo de unión)
    make("belt_band", band_strip(-edge, edge), root, band, uv_mode="band")
    make("belt_join_front", band_strip(edge, 0.5), root, band, uv_mode="band")
    make("belt_join_back", band_strip(-0.5, -edge), root, band, uv_mode="band")
    make("belt_end_front", roller_band(True), root, band, uv_mode="keep")
    make("belt_end_back", roller_band(False), root, band, uv_mode="keep")
    # Curvas en L (C2b).
    for turn in (1, -1):
        build_corner(root, pal, band, turn, wall_profiles)
    # Cruce (C2b).
    build_hub(root, pal, band, wall_profiles)

    tris = sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in root.children if o.type == "MESH")
    print("piezas:", len(root.children), "triángulos:", tris)


if __name__ == "__main__":   # con Alt+P; desde fuera se puede llamar build() a mano
    build()
