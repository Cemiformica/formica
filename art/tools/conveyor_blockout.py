# Blockout de la cinta transportadora básica (B3.7). Tramo recto de una casilla, a juego con los puertos
# (César: toda la logística comparte aspecto): artesa gris del Nexo con perfil de MEDIO HEXÁGONO (la mitad
# de abajo de la boca de los puertos, D-079), remaches, un pie metálico y la banda («belt_band», con su
# propio material para que Godot la haga avanzar).
# La banda es una superficie sin grosor (sin cantos) y su parte recta acaba donde empiezan las curvas.
# En cada extremo hay dos piezas que Godot alterna: la «vuelta de banda» (belt_end_front / belt_end_back),
# medio cilindro alrededor de un eje, si ese extremo está SIN conectar (para que se vea girar, César); y un
# tramo recto corto (belt_join_front / belt_join_back) si está conectado, para que la banda siga continua.
# Convenciones de la guía de arte: origen en el centro de la casilla a ras de suelo; la cinta sin girar
# avanza hacia el NORTE (+Y en Blender): entrada al sur, salida al norte. Va de borde a borde.
# Los números del perfil están también en port_blockout.py (lengüeta): si cambian aquí, cambiarlos allí.
#
# Uso: Editor de texto de Blender → abrir → Alt+P. Si ya existe «conveyor», lo borra y lo rehace.
# Dónde tocar: medidas en las constantes; colores de la paleta como (fila, columna).

import bpy
import bmesh
import math
from mathutils import Vector

PALETTE = 64
SWATCH = 8
PALETTE_PATH = "//../../assets/textures/palette.png"
BAND_TEXTURE_PATH = "//../../assets/textures/belt_band.png"
ROOT = "conveyor"

BAND_HALF = 0.19        # banda de 0,38 m (fondo plano de la artesa)
BAND_TOP = 0.125        # superficie de la banda
BAND_THICK = 0.01
WALL_TOP_X = 0.29       # borde interior de la pared, arriba
WALL_TOP_Z = 0.28
LIP = 0.04              # grosor de la pared (borde superior plano)
SHELL_BOTTOM = (0.24, 0.06)   # media anchura y altura del fondo exterior de la artesa
ROLLER_R = 0.06         # radio de la vuelta de banda en los extremos
TEX_PER_M = 2           # repeticiones de la textura de la banda por metro (cada una: nervio + chevrón)

FRAME, RIVET, FOOT = (5, 3), (5, 5), (5, 4)   # los mismos grises que el puerto estándar


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
    # Paredes (perfil de medio hexágono), de borde a borde.
    for side, sx in (("east", 1), ("west", -1)):
        wall = [(sx * (WALL_TOP_X + LIP), WALL_TOP_Z), (sx * WALL_TOP_X, WALL_TOP_Z), (sx * BAND_HALF, floor_z),
                (sx * BAND_HALF, bz), (sx * bx, bz)]
        if sx < 0:
            wall.reverse()
        make("wall_" + side, prism_x_profile(wall, -0.5, 0.5), root, pal, FRAME, 0.008)
        # Dos remaches en el borde de arriba de cada pared, medio hundidos (como los del puerto).
        for i, y in enumerate((-0.25, 0.25)):
            make("rivet_%s_%d" % (side, i), box((0.03, 0.03, 0.03), (sx * (WALL_TOP_X + LIP / 2), y, WALL_TOP_Z)),
                 root, pal, RIVET)
    # Fondo bajo la banda, acortado en los extremos para dejar sitio a las vueltas de banda.
    floor_len = 1.0 - 2 * (2 * ROLLER_R)
    make("floor", box((2 * BAND_HALF, floor_len, floor_z - bz), (0.0, 0.0, (floor_z + bz) / 2)), root, pal, FRAME)
    make("foot", box((2 * bx - 0.06, 0.14, bz), (0.0, 0.0, bz / 2)), root, pal, FOOT, 0.008)
    edge = 0.5 - ROLLER_R   # donde acaba la banda recta y empieza la curva (o el tramo de unión)
    make("belt_band", band_strip(-edge, edge), root, band, uv_mode="band")
    make("belt_join_front", band_strip(edge, 0.5), root, band, uv_mode="band")
    make("belt_join_back", band_strip(-0.5, -edge), root, band, uv_mode="band")
    make("belt_end_front", roller_band(True), root, band, uv_mode="keep")
    make("belt_end_back", roller_band(False), root, band, uv_mode="keep")

    tris = sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in root.children if o.type == "MESH")
    print("piezas:", len(root.children), "triángulos:", tris)


build()
