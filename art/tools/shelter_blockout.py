# Refugio de Isla Alba (C5.5, `Refugio.md`): un hormiguero hueco levantado al pie del acantilado.
# Paso 1, el cascarón: el montículo por fuera (cono de estratos con la punta inclinada hacia el acantilado y dos
# brazos que abrazan el porche), y por dentro la sala hexagonal con su cúpula, la galería ovalada de la boca y las
# dos alcobas (cama al oeste, fogón al este).
# Paso 2, las cuatro piezas por reparar (`Refugio.md` §4), cada una bajo su vacío «piece_<id>» con el origen en su base
# (lo que busca `RepairSiteView`), y el vacío «spawn_point» delante de la cama:
#   - piece_props: marco de mina (dos postes inclinados, travesaño y cuñas) dentro de la galería;
#   - piece_floor: panal de baldosas hexagonales que cubre la sala;
#   - piece_awning: travesaño en la boca de la galería con la piel enrollada y atada a un lado (este);
#   - piece_bed: camastro de nómadas en la alcoba del oeste (largueros, tablillas, piel, manta y cojín);
#   - piece_hatch: trampilla en la boca del cráter (César), con la tapa colgando del vacío «hatch_hinge» (Godot la gira
#     al abrirla) y una cuerda que baja por el pozo hasta una estaca con tirador junto a la entrada: el vacío
#     «hatch_pull» es donde se apunta para entregarle cosas y, ya reparada, para abrirla o cerrarla con E.
#     Dentro de la trampilla, los vacíos «light_shaft_top» (la boca) y «light_shaft_bottom» (el suelo de la sala):
#     Godot dibuja entre ellos el haz de luz cuando la trampilla está abierta.
# Detalles (no se reparan):
#   - lantern: candil colgado de un soporte en la pared suroeste; su llama «lantern_flame» va aparte y el vacío
#     «lantern_light» es donde Godot pone la luz. Se enciende al completar el refugio y luego con E.
#   - hearth: fogón en la alcoba del este, con llamas «hearth_flame_N», brasas «hearth_embers» y «hearth_light».
#   - ruins: aros de la boca y cacharros (`build_ruins`).
#
# Planta (`Refugio.md` §3): 8 × 7 casillas con el origen en el centro de la huella, a ras de suelo. En Blender el
# norte es +Y (en Godot, -Z) y la boca mira al sur (-Y). Una casilla = 1 m. Regla: las paredes pueden pasar por
# encima de las casillas bloqueadas, nunca de las libres (la sala, la galería y el porche).
#
# Cómo se hace: un montículo cerrado al que se le restan (Boolean exacto) la sala, la galería, las alcobas y el pozo.
# Por fuera lleva el material «terrain_rock», que en Godot es el mismo shader que el terreno (`terrain.gdshader`):
# así tiene exactamente los estratos, los tonos y la hierba de los acantilados (César). Ese material tiene
# `object_mode` activado: no lee el color de vértice ni las UV de la malla (es roca sin agua cerca ni explanada, y la
# altura sale de la posición). Por dentro, la paleta, en tierra.
#
# Exportar: export_hierarchy("shelter", "//../../assets/models/props/shelter.glb")
#
# Uso: con art/props/shelter.blend abierto, Editor de texto → abrir → Alt+P (o exec desde la consola). Borra y
# rehace el refugio.

import bpy
import bmesh
import math
import random
from mathutils import Matrix, Vector

PALETTE = 64
SWATCH = 8
TEXTURE = "//../../assets/textures/palette.png"
SURFACE = "//../../assets/textures/palette_surface.png"

# Cuadritos de la paleta (fila, columna).
EARTH_WALL = (4, 6)    # 7d5c42: paredes de dentro, tierra apisonada
EARTH_FLOOR = (4, 5)   # a07a5a: suelo de dentro
EARTH_DARK = (4, 7)    # 5a412e: lo alto de la cúpula, más oscuro
# Piezas (los mismos cuadritos que la ruina de prueba y los ítems).
PLANK, PLANK_GRAIN, WOOD_END, BARK_DARK = (0, 2), (0, 4), (0, 1), (0, 6)
STONE, STONE_LIGHT, STONE_DARK = (1, 4), (1, 3), (1, 6)
HIDE, HIDE_DARK = (4, 1), (4, 3)     # pieles de los nómadas
BLANKET_STRIPE = (6, 2)              # franja ámbar de la manta
CUSHION = (1, 1)                     # cojín de piel clara

ROOT = "shelter"
OUTSIDE_MATERIAL = "terrain_rock"   # en Godot, `assets/materials/terrain_rock.tres` (el shader del terreno)

# Montículo.
MOUND_HEIGHT = 11.2        # la punta del cono entero; cortado en el cráter queda en unos 8,9 m (el acantilado tiene 6; más
                           # alto que antes para que la boca de arriba sea más estrecha: César)
MOUND_RX = 3.95            # medio ancho de la base (este-oeste), dentro de las 8 casillas
MOUND_RY = 3.45            # medio fondo de la base (norte-sur), dentro de las 7
MOUND_LEAN = 2.0           # lo que la punta se va hacia el norte (hacia el acantilado: así, a la altura del borde, la
                           # espalda ya está dentro de la roca)
# La espalda (norte) se apoya en el acantilado (C5.5, César: sin surco entre el cono y la pared): es más honda que la
# huella, así que entra en la roca, y baja más despacio, así que sigue pegada a la pared al subir. El shader es el
# mismo que el del terreno, así que la costura no se ve: estrato con estrato.
MOUND_RY_BACK = 5.2        # la espalda entra más de 1,5 m en la roca (con 4,3 quedaba una grieta: César)
MOUND_RX_BACK = 8.0        # y más ancha que el frente: sus esquinas se meten en la pared, a los dos lados (solo
                           # se sale de las 8 casillas en la fila pegada a la pared, hasta 1 m por cada lado)
BACK_SHRINK_EXTRA = 1.6
MOUND_SINK = 0.35          # lo que la base se mete bajo el suelo, para que no se vea el borde
MOUND_RINGS = 14
# La punta, cortada en un cráter con su boca de hormiguero (César): el cono se queda en MOUND_TOP_T de su altura, con
# un reborde que sobresale, y de ahí baja un pozo hasta la cúpula de la sala (César): por él entrará el rayo de luz
# cenital de `Refugio.md` §5.
MOUND_TOP_T = 0.78         # un poco más abajo que antes: la boca es más ancha y el reborde no se queda fino
CRATER_LIP = 0.22          # lo que sube el reborde sobre el último anillo
CRATER_LIP_OUT = 1.12      # y lo que se abre hacia fuera
# Por dentro, encima de las paredes de la sala, el techo sube como un cono hueco que sigue la forma de fuera, con las
# paredes del mismo grueso (César): se abre en la boca del cráter, estrecha arriba y ancha abajo. Por ella entra el
# rayo de luz cenital de `Refugio.md` §5.
WALL_THICKNESS = 0.8
MOUTH_R = 0.72             # radio medio de la boca de arriba (unos 1,45 m; César: algo más ancha). La boca no es un
                           # círculo: es la forma de fuera a escala (ovalada y abollada como el cráter; César)
MOUND_SIDES = 28
PORCH_FRONT = -2.5         # el porche (fila 6, columnas 2 a 5) queda libre: el montículo no pasa de aquí
PORCH_HALF = 2.0

# Sala: hexágono con la punta al fondo (norte), que contiene sus 16 casillas libres (un cuadrado de 4 × 4).
ROOM_CENTER = Vector((0.0, 0.5))   # 30 cm más al fondo que la primera versión (César: que quepa más)
ROOM_R = 3.2                       # con 2,95 quedaban 14 casillas libres; así, un cuadrado de 4 × 4 (16)
ROOM_NORTH_CUT = 3.15              # la punta norte se corta en recto aquí: llegaba a 3,7 y el acantilado (desde 3,5)
                                   # asomaba dentro (César); la sala de 2,95 llegaba a 3,15 y no asomaba. No toca el cuadrado de casillas (llega a 2,5).
ROOM_WALL = 1.9            # alto de las facetas antes de la cúpula
FLOOR_Z = 0.03             # suelo de dentro, un pelo por encima del terreno (si no, parpadean)

# Galería de la boca (columnas 3 y 4, fila 5): túnel ovalado. Más ancha y alta que al principio (0,8 y 2,2) para que
# quepa el marco de los puntales dejando paso a Mira (1,8 m).
GALLERY_HALF = 0.95
GALLERY_HEIGHT = 2.5
GALLERY_FROM = -1.6
GALLERY_TO = -3.3

rng = random.Random(11)


def swatch_uv(row: int, col: int) -> Vector:
    return Vector(((col * SWATCH + SWATCH / 2) / PALETTE, 1.0 - (row * SWATCH + SWATCH / 2) / PALETTE))


def get_material(name: str = "palette"):
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
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


def smooth_noise(a: float, z: float, seed: float) -> float:
    # Ruido suave y periódico alrededor del montículo (a en radianes), sin dependencias.
    return (math.sin(a * 3.0 + seed + z * 0.7) * 0.5 + math.sin(a * 5.0 - seed * 1.7 + z * 1.3) * 0.3
            + math.sin(a * 9.0 + seed * 0.4 - z * 2.1) * 0.2)


def to_object(name: str, bm, material, parent=None):
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    mesh.materials.append(material)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.parent = parent
    return obj


# --- Formas cerradas ---

def mound_outline(a: float, t: float, solid_back: bool = True) -> Vector:
    # Punto del contorno del montículo a la altura relativa t (0 abajo, 1 arriba), en el ángulo a.
    # Campana: abajo casi recto (si no, las alcobas atravesaban la pared) y arriba en punta, como la aguja. La espalda,
    # más honda y más llena (ver MOUND_RY_BACK).
    back = smoothstep(0.0, 0.7, math.sin(a))
    # Las esquinas de atrás se ensanchan para hundirse en la pared por los dos lados (César). Delante de la fila pegada
    # a la pared, la huella sigue siendo de 8 casillas (al oeste está el portal).
    corners = smoothstep(0.45, 0.8, math.sin(a))
    # Por encima del acantilado (6 m) ya no hay pared en la que hundirse: los hombros acaban justo por debajo del
    # borde (quedan bajo la roca) y la punta vuelve a ser un cono, con la espalda aún apoyada en el borde.
    above = smoothstep(0.47, 0.57, t)
    corners *= 1.0 - above
    back *= 1.0 - 0.2 * above
    # Y lo más alto, redondo del todo: el cráter queda centrado sobre su pozo (César).
    back *= 1.0 - smoothstep(0.6, 0.76, t)
    if not solid_back:   # el cono «de frente» por todos lados: es lo que sigue el hueco de dentro
        back = 0.0
        corners = 0.0
    shrink = 1.0 - t ** (1.35 + BACK_SHRINK_EXTRA * back)
    wobble = 1.0 + 0.09 * smooth_noise(a, t * 6.0, 1.3) * (1.0 - t * 0.4)
    x = math.cos(a) * (MOUND_RX + (MOUND_RX_BACK - MOUND_RX) * corners) * shrink * wobble
    y = math.sin(a) * (MOUND_RY + (MOUND_RY_BACK - MOUND_RY) * back) * shrink * wobble
    # El porche queda libre: entre los brazos, el frente no baja de PORCH_FRONT (solo cuenta abajo, donde la base es
    # ancha; arriba el cono ya está más atrás).
    if y < PORCH_FRONT:
        inside = 1.0 - smoothstep(PORCH_HALF, PORCH_HALF + 0.7, abs(x))
        y = y + (PORCH_FRONT - y) * inside
    y += MOUND_LEAN * t ** 1.5
    return Vector((x, y))


def smoothstep(e0: float, e1: float, v: float) -> float:
    k = max(0.0, min(1.0, (v - e0) / (e1 - e0)))
    return k * k * (3.0 - 2.0 * k)


def build_mound():
    bm = bmesh.new()
    rings = []
    for k in range(MOUND_RINGS):
        t = MOUND_TOP_T * k / (MOUND_RINGS - 1)
        z = -MOUND_SINK + t * (MOUND_HEIGHT + MOUND_SINK)
        ring = []
        for i in range(MOUND_SIDES):
            a = 2.0 * math.pi * i / MOUND_SIDES - math.pi / 2.0
            p = mound_outline(a, t)
            ring.append(bm.verts.new((p.x, p.y, z + 0.12 * smooth_noise(a, t * 4.0, 4.1) * (t > 0))))
        rings.append(ring)
    # Reborde del cráter: el último anillo, algo más abierto y más alto, como la tierra que sacan las hormigas.
    center = crater_center()
    lip = []
    for v in rings[-1]:
        out = Vector((v.co.x - center.x, v.co.y - center.y)) * CRATER_LIP_OUT
        lip.append(bm.verts.new((center.x + out.x, center.y + out.y, crater_top())))   # plano: si no, el pozo dejaba aristas sueltas
    rings.append(lip)
    bm.faces.new(list(reversed(rings[0])))
    for k in range(len(rings) - 1):
        for i in range(MOUND_SIDES):
            j = (i + 1) % MOUND_SIDES
            bm.faces.new((rings[k][i], rings[k][j], rings[k + 1][j], rings[k + 1][i]))
    bm.faces.new(lip)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def crater_top() -> float:
    return -MOUND_SINK + MOUND_TOP_T * (MOUND_HEIGHT + MOUND_SINK) + CRATER_LIP


def crater_center() -> Vector:
    return Vector((0.0, MOUND_LEAN * MOUND_TOP_T ** 1.5))


def build_cavity():
    # El cono hueco de encima de la sala: empieza en el hexágono de la sala (un pelo por debajo de ROOM_WALL, para que
    # las dos formas se solapen) y sube metido WALL_THICKNESS dentro del cono de fuera hasta salir por el cráter.
    bm = bmesh.new()
    sides = MOUND_SIDES
    rings = []
    # Abajo: el hexágono de la sala, con tantos puntos como lados tiene el cono (el mismo ángulo en cada uno).
    ring = []
    for i in range(sides):
        a = 2.0 * math.pi * i / sides - math.pi / 2.0
        ring.append(bm.verts.new(hexagon_point(a, ROOM_WALL - 0.05)))
    rings.append(ring)
    top_z = crater_top() + 0.5
    t0 = (ROOM_WALL + 0.45 + MOUND_SINK) / (MOUND_HEIGHT + MOUND_SINK)
    t1 = (top_z + MOUND_SINK) / (MOUND_HEIGHT + MOUND_SINK)
    steps = 9
    for k in range(steps + 1):
        t = t0 + (min(t1, MOUND_TOP_T) - t0) * k / steps
        z = -MOUND_SINK + t * (MOUND_HEIGHT + MOUND_SINK)
        if k == steps:
            z = top_z
        center = Vector((0.0, MOUND_LEAN * t ** 1.5))
        outline = []
        for i in range(sides):
            a = 2.0 * math.pi * i / sides - math.pi / 2.0
            outline.append(mound_outline(a, t, solid_back=False) - center)
        mean_len = sum(d.length for d in outline) / sides
        ring = []
        for d in outline:
            # Lo más estrecho que puede ser el hueco: la forma de fuera reducida hasta un radio medio de MOUTH_R.
            r = max(MOUTH_R * d.length / mean_len, d.length - WALL_THICKNESS)
            q = center + d.normalized() * r
            ring.append(bm.verts.new((q.x, q.y, z)))
        rings.append(ring)
    bm.faces.new(list(reversed(rings[0])))
    for k in range(len(rings) - 1):
        for i in range(sides):
            j = (i + 1) % sides
            bm.faces.new((rings[k][i], rings[k][j], rings[k + 1][j], rings[k + 1][i]))
    bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def hexagon_point(a: float, z: float) -> Vector:
    # Punto del contorno del hexágono de la sala (punta al norte, cortada en ROOM_NORTH_CUT) en la dirección a, desde su
    # centro.
    r = ROOM_R * math.cos(math.pi / 6.0) / math.cos(((a - math.pi / 2.0) % (math.pi / 3.0)) - math.pi / 6.0)
    if math.sin(a) > 1e-6:
        r = min(r, (ROOM_NORTH_CUT - ROOM_CENTER.y) / math.sin(a))
    return Vector((ROOM_CENTER.x + math.cos(a) * r, ROOM_CENTER.y + math.sin(a) * r, z))


def build_room():
    # Hexágono con la punta al norte (cortada en ROOM_NORTH_CUT): facetas rectas hasta ROOM_WALL; encima, el cono hueco
    # (build_cavity).
    bm = bmesh.new()
    north = ROOM_NORTH_CUT
    outline = clip_half_plane(room_hexagon(), Vector((1.0, north)), Vector((0.0, north)))
    rings = []
    for z in (FLOOR_Z, ROOM_WALL):
        rings.append([bm.verts.new((p.x, p.y, z)) for p in outline])
    n = len(outline)
    bm.faces.new(list(reversed(rings[0])))
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((rings[0][i], rings[0][j], rings[1][j], rings[1][i]))
    bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def build_gallery():
    # Túnel de sección ovalada con el suelo plano, de GALLERY_FROM (dentro de la sala) a GALLERY_TO (fuera).
    bm = bmesh.new()
    steps = 12
    ends = []
    for y in (GALLERY_FROM, GALLERY_TO):
        ring = [bm.verts.new((GALLERY_HALF, y, FLOOR_Z))]
        for s in range(1, steps):
            t = math.pi * s / steps
            ring.append(bm.verts.new((GALLERY_HALF * math.cos(t), y, FLOOR_Z + (GALLERY_HEIGHT - FLOOR_Z) * math.sin(t))))
        ring.append(bm.verts.new((-GALLERY_HALF, y, FLOOR_Z)))
        ends.append(ring)
    a, b = ends
    bm.faces.new(a)
    bm.faces.new(list(reversed(b)))
    n = len(a)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((a[i], a[j], b[j], b[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def build_alcove(center, radii):
    # Alcoba ovalada: un elipsoide con el fondo aplanado al nivel del suelo.
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=12, v_segments=8, radius=1.0)
    for v in bm.verts:
        v.co = Vector((center[0] + v.co.x * radii[0], center[1] + v.co.y * radii[1], center[2] + v.co.z * radii[2]))
        if v.co.z < FLOOR_Z:
            v.co.z = FLOOR_Z
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.001)
    bmesh.ops.dissolve_degenerate(bm, edges=bm.edges, dist=0.001)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


# --- Pintar ---

def paint(obj, inner_material, outside_material):
    # Dentro (lo que vino de las formas restadas): la paleta, en tierra. Fuera: el material del terreno.
    mesh = obj.data
    inner_index = mesh.materials.find(inner_material.name)
    bm = bmesh.new()
    bm.from_mesh(mesh)
    uv = bm.loops.layers.uv.verify()
    for f in bm.faces:
        c = f.calc_center_median()
        if f.material_index != inner_index:
            for loop in f.loops:
                loop[uv].uv = (0.0, 0.0)
            f.material_index = 1
            f.smooth = True
            continue
        if f.normal.z > 0.7 and c.z < FLOOR_Z + 0.05:
            color = EARTH_FLOOR
        elif c.z > crater_top() - 0.6:
            color = EARTH_DARK             # la boca del pozo, en tierra
        elif c.z > 2.5:
            color = EARTH_DARK
        else:
            color = EARTH_WALL
        for loop in f.loops:
            loop[uv].uv = swatch_uv(*color)
        f.material_index = 0
        f.smooth = True
    bm.to_mesh(mesh)
    bm.free()
    # Huecos: 0 = paleta (dentro), 1 = terreno (fuera), en el sitio del de las formas restadas, que sobra (sin
    # `materials.clear()`: borra los huecos de cada cara).
    mesh.materials[1] = outside_material
    mesh.set_sharp_from_angle(angle=math.radians(35))


def get_outside_material():
    # En Blender, solo para verlo (el color de la roca); en Godot lo sustituye el shader del terreno.
    mat = bpy.data.materials.get(OUTSIDE_MATERIAL) or bpy.data.materials.new(OUTSIDE_MATERIAL)
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial"); out.location = (300, 0)
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled"); bsdf.location = (0, 0)
    bsdf.inputs["Base Color"].default_value = (0.66, 0.44, 0.32, 1.0)
    bsdf.inputs["Roughness"].default_value = 1.0
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    mat.diffuse_color = (0.66, 0.44, 0.32, 1.0)
    return mat


# --- Piezas por reparar ---

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
    for poly in mesh.polygons:
        poly.use_smooth = True
    mesh.set_sharp_from_angle(angle=math.radians(30))
    return obj


def box(size, center=(0, 0, 0)):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=size, verts=bm.verts)
    bmesh.ops.translate(bm, vec=Vector(center), verts=bm.verts)
    return bm


def prism(sides, r0, r1, z0, z1, angle=0.0, bottom_face=True):
    bm = bmesh.new()
    bottom, top = [], []
    for i in range(sides):
        a = angle + 2.0 * math.pi * i / sides
        bottom.append(bm.verts.new((r0 * math.cos(a), r0 * math.sin(a), z0)))
        top.append(bm.verts.new((r1 * math.cos(a), r1 * math.sin(a), z1)))
    if bottom_face:
        bm.faces.new(list(reversed(bottom)))
    bm.faces.new(top)
    for i in range(sides):
        j = (i + 1) % sides
        bm.faces.new((bottom[i], bottom[j], top[j], top[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def place(bm, location=(0, 0, 0), rotation=None):
    m = Matrix.Translation(Vector(location))
    if rotation is not None:
        m = m @ rotation
    bmesh.ops.transform(bm, matrix=m, verts=bm.verts)
    return bm


def beam(p0, p1, width, depth=None):
    # Madero de sección cuadrada de p0 a p1 (centros de sus extremos).
    p0, p1 = Vector(p0), Vector(p1)
    d = p1 - p0
    bm = box((width, width if depth is None else depth, d.length), (0, 0, d.length / 2))
    rot = d.normalized().to_track_quat("Z", "Y").to_matrix().to_4x4()
    return place(bm, p0, rot)


def empty(name, parent, location, rotation_z: float = 0.0):
    obj = bpy.data.objects.new(name, None)
    obj.empty_display_type = "PLAIN_AXES"
    obj.empty_display_size = 0.25
    bpy.context.collection.objects.link(obj)
    obj.parent = parent
    obj.location = location
    obj.rotation_euler = (0.0, 0.0, rotation_z)
    return obj


def gallery_wall_x(z: float) -> float:
    # Medio ancho de la galería a la altura z (su sección es media elipse).
    k = max(0.0, min(1.0, (z - FLOOR_Z) / (GALLERY_HEIGHT - FLOOR_Z)))
    return GALLERY_HALF * math.sqrt(max(0.0, 1.0 - k * k))


# Puntales: arco de madera en el borde exacto de la boca (César: define la entrada, y en él se apoyará más adelante la
# «pared de la puerta»), con la cara de fuera enrasada con la fachada e inclinado como ella. Recorre todo el borde de la
# galería: cada lado son tramos que siguen su curva desde el suelo hasta lo más alto, con el canto de fuera metido
# PROPS_EMBED en la tierra (sin rendijas), y arriba se juntan en una clave.
MOUTH_Y = -2.48            # la fachada en la boca, a ras de suelo (medido en la malla)
MOUTH_LEAN = 0.075         # y lo que se va hacia atrás por metro de alto (a 2 m está en −2,33)
PROPS_POST = 0.22          # ancho del madero visto de frente (César: más gruesos)
PROPS_DEPTH = 0.34         # y su fondo: más que la pared, para que asome por delante de la fachada
PROPS_STICK_OUT = 0.08     # lo que asoma la cara de fuera por delante de la fachada
PROPS_EMBED = 0.07
PROPS_Y = MOUTH_Y + PROPS_DEPTH / 2 - PROPS_STICK_OUT
PROPS_ANGLES = (0.0, 24.0, 46.0, 66.0, 90.0)   # grados sobre la media elipse de la galería donde se unen los tramos
KEYSTONE = (0.34, PROPS_DEPTH + 0.05, 0.28)    # ancho, fondo y alto de la clave


def arch_point(angle_deg: float, side: int) -> Vector:
    # Centro del madero en ese punto del arco: sobre la pared de la galería, metido hacia dentro medio madero menos lo
    # que entra en la tierra (relativo al suelo de dentro).
    t = math.radians(angle_deg)
    height = GALLERY_HEIGHT - FLOOR_Z
    wall = Vector((side * GALLERY_HALF * math.cos(t), 0.0, height * math.sin(t)))
    normal = Vector((side * math.cos(t) / GALLERY_HALF, 0.0, math.sin(t) / height)).normalized()
    return wall - normal * (PROPS_POST / 2 - PROPS_EMBED)


def build_props(root, mat):
    pivot = empty("piece_props", root, (0.0, PROPS_Y, FLOOR_Z))
    pivot.rotation_euler.x = -math.atan(MOUTH_LEAN)   # se inclina hacia atrás con la fachada
    for side in (-1, 1):
        points = [arch_point(a, side) for a in PROPS_ANGLES]
        points[0].z = 0.0
        for k in range(len(points) - 1):
            d = (points[k + 1] - points[k]).normalized()
            # Cada tramo se alarga un poco por los dos lados para que las uniones no dejen rendija.
            a = points[k] - d * (0.0 if k == 0 else 0.05)
            b = points[k + 1] + d * (0.05 if k < len(points) - 2 else 0.0)
            finish("piece_props_post_%d_%d" % (side + 1, k), beam(a, b, PROPS_POST, PROPS_DEPTH), PLANK, pivot, mat, 0.015)
            if 0 < k:
                # Abrazadera de cuero en cada unión.
                band = beam(points[k] - d * 0.05, points[k] + d * 0.05, PROPS_POST + 0.025, PROPS_DEPTH + 0.025)
                finish("piece_props_band_%d_%d" % (side + 1, k), band, BARK_DARK, pivot, mat)
        finish("piece_props_shim_%d" % (side + 1), box((0.28, PROPS_DEPTH + 0.04, 0.05), (points[0].x, 0.0, 0.025)), STONE_DARK, pivot, mat, 0.012)
    # Clave: el bloque donde se juntan los dos lados, arriba del todo.
    top = arch_point(90.0, 1)
    finish("piece_props_keystone", box(KEYSTONE, (0.0, 0.0, top.z - 0.02)), PLANK_GRAIN, pivot, mat, 0.02)
    finish("piece_props_keystone_band", box((KEYSTONE[0] + 0.02, KEYSTONE[1] + 0.02, 0.05), (0.0, 0.0, top.z - 0.02)), BARK_DARK, pivot, mat)
    # Hierbas secas colgadas del arco (detalle de `Refugio.md` §5): un manojo atado.
    herbs_at = arch_point(62.0, 1)
    finish("piece_props_herbs", place(prism(5, 0.02, 0.07, -0.32, 0.0), (herbs_at.x - 0.05, 0.0, herbs_at.z - PROPS_POST / 2)), (0, 0), pivot, mat)   # paja seca


# Suelo: panal de baldosas de pared a pared (César), también en las alcobas y en toda la galería hasta la boca. Las del
# borde se recortan con la forma de la pared y debajo va una lechada que tapa la tierra entre ellas.
# El suelo se reparte en zonas convexas que no se solapan (la sala, los dos trozos de galería que quedan fuera del
# hexágono y las dos alcobas); cada baldosa se recorta por cada zona que toca, con su misma altura y color, así que un
# corte entre zonas no se nota.
TILE_R = 0.42
TILE_GAP = 0.04
TILE_THICK = 0.035
GROUT = (1, 5)            # 7a6f58: lechada
GROUT_TOP = 0.012
TILE_COLORS = ((1, 4), (1, 4), (1, 3), (1, 2), (1, 6))
TILE_MIN_AREA = 0.015     # trocitos de borde más pequeños que esto se dejan en lechada
BED_ALCOVE = ((-2.72, 0.5, 0.35), (0.72, 1.2, 1.05))      # centro y radios (los de `build()`)
HEARTH_ALCOVE = ((-BED_ALCOVE[0][0], BED_ALCOVE[0][1], BED_ALCOVE[0][2]), BED_ALCOVE[1])   # el espejo exacto de la de la cama (César)


def clip_polygon(poly: list, clip: list) -> list:
    # Sutherland-Hodgman: `poly` recortado por el polígono convexo `clip` (los dos en sentido antihorario).
    out = poly
    for i in range(len(clip)):
        out = clip_half_plane(out, clip[i], clip[(i + 1) % len(clip)])
        if not out:
            break
    return out


def clip_half_plane(poly: list, a: Vector, b: Vector) -> list:
    # Lo de `poly` que queda a la izquierda de la recta a → b.
    edge = b - a

    def inside(p):
        return edge.x * (p.y - a.y) - edge.y * (p.x - a.x) >= 0.0
    out = []
    for j in range(len(poly)):
        cur, prev = poly[j], poly[j - 1]
        if inside(cur):
            if not inside(prev):
                out.append(intersect(prev, cur, a, b))
            out.append(cur)
        elif inside(prev):
            out.append(intersect(prev, cur, a, b))
    return out


def intersect(p, q, a, b):
    r, s = q - p, b - a
    t = ((a - p).x * s.y - (a - p).y * s.x) / (r.x * s.y - r.y * s.x)
    return p + r * t


def polygon_area(poly: list) -> float:
    return abs(sum(poly[i].x * poly[i - 1].y - poly[i - 1].x * poly[i].y for i in range(len(poly)))) / 2.0


def room_hexagon(grow: float = 0.0) -> list:
    # Hexágono de la sala (punta al norte, antihorario) en coordenadas de Blender, agrandado `grow` metros.
    r = ROOM_R + grow / math.cos(math.pi / 6.0)
    return [ROOM_CENTER + Vector((math.cos(math.pi / 2 + k * math.pi / 3), math.sin(math.pi / 2 + k * math.pi / 3))) * r
            for k in range(6)]


def rect(x0, y0, x1, y1) -> list:
    return [Vector((x0, y0)), Vector((x1, y0)), Vector((x1, y1)), Vector((x0, y1))]


def alcove_floor(alcove, grow: float) -> list:
    # Suelo de una alcoba: el corte del elipsoide a ras de suelo (sus puntos de debajo se aplanaron ahí), antihorario.
    (cx, cy, cz), (rx, ry, rz) = alcove
    k = math.sqrt(max(0.0, 1.0 - ((FLOOR_Z - cz) / rz) ** 2))
    return [Vector((cx + math.cos(a) * (rx * k + grow), cy + math.sin(a) * (ry * k + grow)))
            for a in (2.0 * math.pi * i / 24 for i in range(24))]


def floor_zones(grow: float) -> list:
    # Zonas del suelo, convexas y sin solaparse (con `grow` > 0, para la lechada, entran un poco en las paredes).
    hexagon = room_hexagon(grow)
    mouth = MOUTH_Y + 0.01
    room = clip_half_plane(hexagon, Vector((0.0, mouth)), Vector((1.0, mouth)))
    north = ROOM_NORTH_CUT + grow
    room = clip_half_plane(room, Vector((1.0, north)), Vector((0.0, north)))   # la punta norte, cortada
    zones = [room]
    # Galería: lo que queda fuera del hexágono a cada lado, entre la boca y la sala.
    south, south_west, south_east = hexagon[3], hexagon[2], hexagon[4]
    half = GALLERY_HALF + grow
    left = clip_half_plane(rect(-half, mouth, 0.0, GALLERY_FROM), south, south_west)   # fuera del lado suroeste
    right = clip_half_plane(rect(0.0, mouth, half, GALLERY_FROM), south_east, south)   # fuera del lado sureste
    zones += [left, right]
    # Alcobas: lo que queda fuera de los lados oeste y este del hexágono.
    west, east = hexagon[1].x, hexagon[5].x
    zones.append(clip_half_plane(alcove_floor(BED_ALCOVE, grow), Vector((west, 0.0)), Vector((west, 1.0))))     # x ≤ oeste
    zones.append(clip_half_plane(alcove_floor(HEARTH_ALCOVE, grow), Vector((east, 1.0)), Vector((east, 0.0))))   # x ≥ este
    return [z for z in zones if len(z) >= 3]


def slab(poly: list, z0: float, z1: float, top_scale: float, around: Vector = None):
    # Losa con la forma de `poly` (antihorario), sin cara de abajo; la de arriba, encogida hacia `around` (bisel de
    # juguete; 1 = sin bisel).
    bm = bmesh.new()
    c = around if around is not None else sum(poly, Vector((0.0, 0.0))) / len(poly)
    bottom = [bm.verts.new((p.x, p.y, z0)) for p in poly]
    top = [bm.verts.new((c.x + (p.x - c.x) * top_scale, c.y + (p.y - c.y) * top_scale, z1)) for p in poly]
    bm.faces.new(top)
    for i in range(len(poly)):
        j = (i + 1) % len(poly)
        bm.faces.new((bottom[i], bottom[j], top[j], top[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def build_floor(root, mat, rng):
    pivot = empty("piece_floor", root, (ROOM_CENTER.x, ROOM_CENTER.y, FLOOR_Z))
    origin = Vector((ROOM_CENTER.x, ROOM_CENTER.y))
    # Lechada: las mismas zonas, metidas unos centímetros bajo las paredes para que no quede rendija.
    for k, zone in enumerate(floor_zones(0.06)):
        grout = bmesh.new()
        grout.faces.new([grout.verts.new((p.x - origin.x, p.y - origin.y, GROUT_TOP)) for p in zone])
        finish("piece_floor_grout_%d" % k, grout, GROUT, pivot, mat)
    zones = floor_zones(0.0)
    step_x = math.sqrt(3.0) * TILE_R
    step_y = 1.5 * TILE_R
    r = TILE_R - TILE_GAP / 2
    count = 0
    for row in range(-8, 8):
        for col in range(-8, 8):
            center = origin + Vector((col * step_x + (step_x / 2 if row % 2 else 0.0), row * step_y))
            hexagon = [center + Vector((math.cos(math.pi / 2 + k * math.pi / 3), math.sin(math.pi / 2 + k * math.pi / 3))) * r
                       for k in range(6)]
            pieces = [clip_polygon(hexagon, zone) for zone in zones]
            pieces = [p for p in pieces if len(p) >= 3 and polygon_area(p) >= TILE_MIN_AREA]
            if not pieces:
                continue
            top = TILE_THICK + rng.uniform(-0.007, 0.007)
            color = rng.choice(TILE_COLORS)
            whole = len(pieces) == 1 and polygon_area(pieces[0]) > polygon_area(hexagon) * 0.99
            for piece in pieces:
                local = [p - origin for p in piece]
                finish("piece_floor_tile_%d" % count, slab(local, 0.0, top, 0.965 if whole else 1.0, center - origin), color, pivot, mat)
                count += 1
    return count


# Toldo: travesaño justo detrás del marco de los puntales, dentro de la galería, y la piel enrollada al este.
AWNING_Y = PROPS_Y + 0.27
AWNING_Z = 2.05            # centro del travesaño (por debajo, 2,0 m)


def build_awning(root, mat):
    pivot = empty("piece_awning", root, (0.0, AWNING_Y, AWNING_Z))
    half = gallery_wall_x(AWNING_Z) + 0.12                               # sus puntas se clavan en la tierra
    lying = Matrix.Rotation(math.radians(90), 4, "Y")
    finish("piece_awning_pole", place(prism(6, 0.045, 0.045, -half, half), (0, 0, 0), lying), PLANK, pivot, mat)
    # Piel enrollada: un rollo colgando del travesaño, atado con dos cuerdas, y la punta de la piel que asoma abajo.
    roll_x = gallery_wall_x(1.2) - 0.2
    roll = place(prism(7, 0.12, 0.1, -1.05, -0.04), (roll_x, -0.02, 0.0))
    finish("piece_awning_roll", roll, HIDE, pivot, mat, 0.01)
    for k, z in enumerate((-0.3, -0.8)):
        finish("piece_awning_tie_%d" % k, place(prism(7, 0.128, 0.128, z - 0.02, z + 0.02), (roll_x, -0.02, 0.0)), BARK_DARK, pivot, mat)
    # La punta de la piel que cuelga del rollo: un faldón con el borde de abajo algo torcido.
    flap = bmesh.new()
    corners = [(roll_x - 0.1, -0.09, -1.0), (roll_x + 0.1, -0.09, -1.0), (roll_x + 0.09, -0.07, -1.26), (roll_x - 0.11, -0.1, -1.3)]
    flap.faces.new([flap.verts.new(c) for c in corners])
    bmesh.ops.solidify(flap, geom=flap.faces[:], thickness=0.025)
    finish("piece_awning_flap", flap, HIDE_DARK, pivot, mat)
    # Lado oeste: la otra punta de la piel, bien recogida contra la pared.
    finish("piece_awning_knot", place(prism(6, 0.06, 0.05, -0.16, 0.0), (-gallery_wall_x(AWNING_Z) + 0.12, -0.02, 0.0)), HIDE_DARK, pivot, mat)


# Camastro: en la alcoba del oeste (columna 1, filas 2 y 3), a lo largo del eje norte-sur.
BED_CENTER = (-2.5, 0.5)
BED_LENGTH = 1.6
BED_WIDTH = 0.66


def build_bed(root, mat):
    pivot = empty("piece_bed", root, (BED_CENTER[0], BED_CENTER[1], FLOOR_Z + TILE_THICK))   # sobre las baldosas
    half_l = BED_LENGTH / 2
    half_w = BED_WIDTH / 2
    for side in (-1, 1):
        finish("piece_bed_rail_%d" % (side + 1), box((0.09, BED_LENGTH, 0.09), (side * half_w, 0, 0.2)), PLANK, pivot, mat, 0.01)
        for end in (-1, 1):
            finish("piece_bed_leg_%d_%d" % (side + 1, end + 1), box((0.08, 0.08, 0.16), (side * half_w, end * (half_l - 0.08), 0.08)),
                   BARK_DARK, pivot, mat)
    slats = 7
    for k in range(slats):
        y = -half_l + 0.12 + k * (BED_LENGTH - 0.24) / (slats - 1)
        finish("piece_bed_slat_%d" % k, box((BED_WIDTH + 0.06, 0.15, 0.03), (0, y, 0.26)), PLANK_GRAIN if k % 2 else PLANK, pivot, mat, 0.006)
    finish("piece_bed_fur", box((BED_WIDTH - 0.06, BED_LENGTH - 0.2, 0.06), (0, 0.04, 0.305)), HIDE, pivot, mat, 0.02)
    # Manta doblada a los pies (sur, hacia la sala) con su franja, y cojín de piel en la cabecera (norte).
    finish("piece_bed_blanket", box((BED_WIDTH - 0.02, 0.32, 0.09), (0, -half_l + 0.3, 0.37)), HIDE_DARK, pivot, mat, 0.025)
    finish("piece_bed_blanket_stripe", box((BED_WIDTH, 0.06, 0.092), (0, -half_l + 0.3, 0.37)), BLANKET_STRIPE, pivot, mat, 0.01)
    finish("piece_bed_cushion", box((0.42, 0.26, 0.1), (0, half_l - 0.25, 0.38)), CUSHION, pivot, mat, 0.04)


# Trampilla del cráter: tapa hexagonal con la bisagra al norte, que tapa el hueco (radio 0,60–0,82 m) y se apoya en el
# reborde (desde 1,08 m), y la cuerda que baja hasta el tirador.
HATCH_R = 0.98             # radio de la tapa (a sus esquinas)
HATCH_STICK = 0.075
ROPE_ANGLE = math.radians(-60.0)   # por dónde baja la cuerda (desde el centro de la sala): la pared sureste
ROPE_R = 0.025            # cuerda de 5 cm (César: más gruesa)
PULL_Z = 1.1               # altura del pasador de la palanca (a la altura de la mano)
PULLEY_Z = 1.75            # altura de la polea de la pared: por debajo de donde la pared se curva hacia la cúpula (más
                           # arriba, la cuerda atravesaba esa esquina; César)
RIM_PULLEY_IN = 0.35       # la polea de la boca: hacia dentro del cráter desde su centro (al norte) y por debajo del borde
RIM_PULLEY_DOWN = 0.25
LEVER_LENGTH = 0.45
LEVER_UP = 35.0            # grados sobre la horizontal con la trampilla cerrada (Godot la baja 70 al abrir)


def cavity_wall_point(a: float, t: float, inset: float) -> Vector:
    # Punto de la pared del pozo (`build_cavity`) en la dirección a y a la altura relativa t, metido `inset` hacia dentro.
    center = Vector((0.0, MOUND_LEAN * t ** 1.5))
    outline = []
    for i in range(MOUND_SIDES):
        b = 2.0 * math.pi * i / MOUND_SIDES - math.pi / 2.0
        outline.append(mound_outline(b, t, solid_back=False) - center)
    mean_len = sum(d.length for d in outline) / MOUND_SIDES
    d = mound_outline(a, t, solid_back=False) - center
    r = max(MOUTH_R * d.length / mean_len, d.length - WALL_THICKNESS) - inset
    q = center + d.normalized() * r
    return Vector((q.x, q.y, -MOUND_SINK + t * (MOUND_HEIGHT + MOUND_SINK)))


def rope(name, points, parent, mat):
    # Cuerda: un tramo fino por cada par de puntos seguidos, algo solapados.
    for k in range(len(points) - 1):
        a, b = Vector(points[k]), Vector(points[k + 1])
        d = (b - a).normalized()
        bm = prism(6, ROPE_R, ROPE_R, 0.0, (b - a).length + 0.02)
        place(bm, a - d * 0.01, d.to_track_quat("Z", "Y").to_matrix().to_4x4())
        finish("%s_%d" % (name, k), bm, BARK_DARK, parent, mat)


_shell_tree = None


def shell_surface_z(x, y, from_z):
    # Altura de la superficie de fuera del montículo bajo (x, y), mirando desde `from_z` hacia abajo; None si no hay.
    global _shell_tree
    if _shell_tree is None:
        from mathutils.bvhtree import BVHTree
        shell = bpy.data.objects["shelter_shell"]
        bm = bmesh.new()
        bm.from_object(shell, bpy.context.evaluated_depsgraph_get())
        bm.transform(shell.matrix_world)
        _shell_tree = BVHTree.FromBMesh(bm)
        bm.free()
    hit = _shell_tree.ray_cast(Vector((x, y, from_z)), Vector((0.0, 0.0, -1.0)), 20.0)
    return hit[0].z if hit[0] is not None else None


def build_hatch(root, mat):
    top = crater_top()
    center = crater_center()
    pivot = empty("piece_hatch", root, (center.x, center.y, top))
    apothem = HATCH_R * math.cos(math.pi / 6.0)
    hinge = empty("hatch_hinge", pivot, (0.0, apothem, 0.0))
    lid_center = Vector((0.0, -apothem, 0.0))   # en el espacio de la bisagra
    corners = [lid_center + Vector((math.cos(k * math.pi / 3), math.sin(k * math.pi / 3), 0.0)) * HATCH_R for k in range(6)]
    # Piel tensada (hexágono fino) y el marco de palos por encima, con dos travesaños.
    hide = place(prism(6, HATCH_R - 0.05, HATCH_R - 0.07, 0.015, 0.045), lid_center)
    finish("piece_hatch_hide", hide, HIDE, hinge, mat)
    for k in range(6):
        a, b = corners[k], corners[(k + 1) % 6]
        d = (b - a).normalized()
        finish("piece_hatch_frame_%d" % k, beam(a - d * 0.04 + Vector((0, 0, 0.03)), b + d * 0.04 + Vector((0, 0, 0.03)), HATCH_STICK), PLANK, hinge, mat, 0.01)
    for k, x in enumerate((-0.32, 0.32)):
        finish("piece_hatch_bar_%d" % k, beam(lid_center + Vector((x, -apothem + 0.05, 0.075)), lid_center + Vector((x, apothem - 0.05, 0.075)),
               HATCH_STICK * 0.85), PLANK_GRAIN, hinge, mat, 0.008)
    # Asa del lado libre (sur) y correas de cuero en la bisagra.
    finish("piece_hatch_handle", beam(lid_center + Vector((-0.14, -apothem - 0.02, 0.1)), lid_center + Vector((0.14, -apothem - 0.02, 0.1)), 0.04),
           BARK_DARK, hinge, mat)
    for x in (-0.3, 0.3):
        finish("piece_hatch_strap_%d" % int(x > 0), box((0.1, 0.14, 0.03), (x, 0.0, 0.035)), BARK_DARK, hinge, mat)
    # Fijo en el reborde: las dos estacas de la bisagra.
    for x in (-0.42, 0.42):
        finish("piece_hatch_stake_%d" % int(x > 0), place(prism(5, 0.05, 0.035, -0.15, 0.12), (x, apothem + 0.06, 0.0)), BARK_DARK, pivot, mat)
    origin = Vector((center.x, center.y, top))
    # Caballete al norte del cráter (César: la cuerda baja recta, con poleas): dos patas cruzadas con una polea arriba.
    # Abierta, la tapa queda apoyada en él. Del asa de la tapa sube una cuerda a esa polea (la dibuja Godot entre
    # «rope_a_0», en la tapa, y «rope_b_0», en la polea: se acorta al abrir).
    apex = Vector((0.0, center.y + 1.75, top + 2.0))
    for side in (-1, 1):
        # Cada pata baja hasta la superficie del montículo y se clava en ella (César: quedaban en el aire, porque por
        # detrás del cráter el montículo baja).
        foot_xy = (side * 0.62, center.y + 1.15)
        ground = shell_surface_z(foot_xy[0], foot_xy[1], top + 1.0)
        foot = Vector((foot_xy[0], foot_xy[1], (ground if ground is not None else top - 0.12) - 0.08))
        top_end = apex + Vector((-side * 0.12, 0.05, 0.12))
        finish("piece_hatch_trestle_%d" % int(side > 0), beam(foot - origin, top_end - origin, 0.08), PLANK, pivot, mat, 0.01)
    finish("piece_hatch_trestle_tie", beam(apex - origin + Vector((-0.12, 0.0, -0.06)), apex - origin + Vector((0.12, 0.0, -0.06)), 0.1),
           BARK_DARK, pivot, mat)
    pulley(pivot, mat, "piece_hatch_pulley_top", apex - origin + Vector((0.0, -0.06, 0.0)), Vector((1.0, 0.0, 0.0)))
    empty("rope_a_0", hinge, tuple(lid_center + Vector((0.0, -apothem - 0.02, 0.1))))   # en el asa
    empty("rope_b_0", pivot, tuple(apex - origin + Vector((0.0, -0.13, 0.0))))
    # Polea de abajo: en lo alto de la pared sureste de la sala, con su soporte clavado en la tierra.
    wall_top = hexagon_point(ROPE_ANGLE, ROOM_WALL - 0.05)
    room_dir = (Vector((wall_top.x, wall_top.y)) - ROOM_CENTER).normalized()
    inward = Vector((-room_dir.x, -room_dir.y, 0.0))
    side_dir = Vector((-inward.y, inward.x, 0.0))
    wall = Vector((wall_top.x, wall_top.y, 0.0))
    reach = LEVER_LENGTH * math.cos(math.radians(LEVER_UP))   # la polea queda justo encima de la punta de la palanca
    low = wall + inward * reach + Vector((0.0, 0.0, PULLEY_Z))
    finish("piece_hatch_bracket", beam(wall + Vector((0, 0, PULLEY_Z + 0.12)) - inward * 0.12 - origin,
           low + Vector((0, 0, 0.12)) - origin, 0.07), PLANK, pivot, mat, 0.008)
    finish("piece_hatch_bracket_strut", beam(wall + Vector((0, 0, PULLEY_Z - 0.3)) - inward * 0.1 - origin,
           low + Vector((0, 0, 0.1)) - inward * 0.12 - origin, 0.05), PLANK_GRAIN, pivot, mat, 0.006)
    pulley(pivot, mat, "piece_hatch_pulley_low", low - origin, side_dir)
    # Polea de la boca: colgada de una estaca justo dentro del cráter, al norte. La cuerda baja del caballete hasta ella
    # sin rozar el borde y, desde ella, recta por el centro del pozo hasta la polea de la pared.
    rim = Vector((center.x, center.y + RIM_PULLEY_IN, top - RIM_PULLEY_DOWN))
    finish("piece_hatch_rim_stake", beam(Vector((0.0, 0.72, 0.03)), rim - origin + Vector((0.0, 0.0, 0.08)), 0.05), PLANK, pivot, mat, 0.006)
    pulley(pivot, mat, "piece_hatch_pulley_rim", rim - origin, Vector((1.0, 0.0, 0.0)))
    # Cuerdas fijas: del caballete a la boca y de la boca a la pared, rectas.
    rope("piece_hatch_rope", [apex - origin + Vector((0.0, -0.06, -0.08)), rim - origin + Vector((0.0, 0.07, 0.0)),
         rim - origin + Vector((0.0, -0.07, 0.0)), low - origin + Vector((0.0, 0.0, 0.08))], pivot, mat)
    # Palanca (César: al tirar, la manivela baja): gira con «hatch_lever» alrededor de un eje a lo largo de la pared.
    # Cerrada apunta LEVER_UP grados hacia arriba; Godot la baja al abrir. De su punta sube la otra cuerda que se mueve
    # («rope_a_1» en la palanca, «rope_b_1» bajo la polea).
    pin = wall + inward * 0.06 + Vector((0.0, 0.0, PULL_Z))
    lever = empty("hatch_lever", pivot, tuple(pin - origin))
    lever.rotation_euler.z = math.atan2(-inward.x, inward.y)    # su Y local apunta hacia la sala; su X, a lo largo de la pared
    up = math.radians(LEVER_UP)
    tip = Vector((0.0, math.cos(up), math.sin(up))) * LEVER_LENGTH
    finish("piece_hatch_lever_arm", beam((0.0, -0.05, 0.0), tip, 0.05), PLANK, lever, mat, 0.008)
    finish("piece_hatch_lever_knob", place(prism(6, 0.035, 0.035, -0.07, 0.07), tip + Vector((0.0, 0.03, 0.0)),
           Matrix.Rotation(math.radians(90), 4, "Y")), BARK_DARK, lever, mat)
    empty("rope_a_1", lever, tuple(tip + Vector((0.0, 0.0, 0.03))))
    empty("rope_b_1", pivot, tuple(low - origin + Vector((0.0, 0.0, -0.08))))
    # Soporte de la palanca: estaca en la pared con el pasador.
    finish("piece_hatch_cleat", beam(pin - inward * 0.12 - origin, pin + inward * 0.03 - origin, 0.08), PLANK, pivot, mat, 0.01)
    finish("piece_hatch_pin", beam(pin - side_dir * 0.06 - origin, pin + side_dir * 0.06 - origin, 0.025), BARK_DARK, pivot, mat)
    # Donde se apunta (para entregar y para abrir o cerrar): en el centro del recorrido de la palanca, a la altura del
    # pasador. La zona tiene el tamaño `aim_size` de la pieza en `shelter.tres` (César: costaba encontrarla con la
    # palanca abajo).
    empty("hatch_pull", pivot, tuple(pin + inward * 0.22 - origin))
    # Haz de luz (Godot lo dibuja con la trampilla abierta): de la boca del cráter, algo por debajo del borde, al
    # centro del suelo de la sala. Baja un poco inclinado porque la boca queda al norte del centro de la sala.
    empty("light_shaft_top", pivot, (0.0, 0.0, -0.15))
    empty("light_shaft_bottom", pivot, tuple(Vector((ROOM_CENTER.x, ROOM_CENTER.y, FLOOR_Z + TILE_THICK)) - origin))
    # Comprobación: la cuerda entre poleas tiene que ir por dentro del pozo.
    a, b = rim + Vector((0.0, -0.07, 0.0)), low + Vector((0.0, 0.0, 0.08))
    worst = 99.0
    for k in range(1, 40):
        q = a.lerp(b, k / 40)
        if q.z < ROOM_WALL + 0.5 or q.z > top - 0.05:
            continue
        t = (q.z + MOUND_SINK) / (MOUND_HEIGHT + MOUND_SINK)
        c = Vector((0.0, MOUND_LEAN * t ** 1.5))
        d = Vector((q.x, q.y)) - c
        ang = math.atan2(d.y, d.x)
        wall_p = cavity_wall_point(ang, t, 0.0)
        worst = min(worst, (Vector((wall_p.x, wall_p.y)) - c).length - d.length)
    print("refugio: la cuerda del pozo queda a %.2f m de la pared como mínimo" % worst)


def pulley(parent, mat, name, at: Vector, axis: Vector):
    # Polea: rueda de ocho lados con su eje, girada para que el eje vaya en `axis`.
    rot = axis.normalized().to_track_quat("Z", "Y").to_matrix().to_4x4()
    wheel = place(prism(8, 0.075, 0.075, -0.022, 0.022), at, rot)
    finish(name, wheel, PLANK_GRAIN, parent, mat, 0.006)
    hub = place(prism(6, 0.02, 0.02, -0.045, 0.045), at, rot)
    finish(name + "_axle", hub, BARK_DARK, parent, mat)


# Candil de los nómadas (detalle, no se repara): farol hexagonal de madera colgado de un cordel, en un soporte clavado en
# la pared suroeste de la sala (entre la galería y la alcoba de la cama). Godot lo enciende al completar el refugio.
LANTERN_ANGLE = math.radians(240.0)   # centro de la faceta suroeste del hexágono
LANTERN_BRACKET_Z = 1.78              # altura del soporte (la pared recta llega a ROOM_WALL)
LANTERN_REACH = 0.36                  # lo que sale el soporte de la pared
LANTERN_HANG = 0.2                    # cordel desde el soporte hasta el asa
LANTERN_R = 0.085                     # radio (a las esquinas) de la base y la tapa
LANTERN_H = 0.2                       # alto del farol, de la base a la tapa
FLAME = (6, 2)                        # ámbar (el color de la llama apagada; Godot la hace brillar)
CLAY = (4, 5)                         # cazoleta de barro


def build_lantern(root, mat):
    wall = hexagon_point(LANTERN_ANGLE, 0.0)
    wall = Vector((wall.x, wall.y, 0.0))
    inward = (Vector((ROOM_CENTER.x, ROOM_CENTER.y, 0.0)) - wall).normalized()
    tip = wall + inward * LANTERN_REACH + Vector((0.0, 0.0, LANTERN_BRACKET_Z))
    top = tip - Vector((0.0, 0.0, LANTERN_HANG))           # asa del farol
    cap_z = top.z - 0.035                                   # arriba de la tapa
    base_z = cap_z - LANTERN_H                              # abajo de la base
    pivot = empty("lantern", root, (top.x, top.y, base_z))
    o = Vector((top.x, top.y, base_z))
    # Soporte: madero clavado en la pared con su tornapunta, y una cuña en la punta para el cordel.
    finish("lantern_bracket", beam(wall - inward * 0.12 + Vector((0, 0, LANTERN_BRACKET_Z)) - o, tip + inward * 0.04 - o, 0.06),
           PLANK, pivot, mat, 0.008)
    finish("lantern_strut", beam(wall - inward * 0.08 + Vector((0, 0, LANTERN_BRACKET_Z - 0.32)) - o,
           tip - inward * 0.12 + Vector((0, 0, -0.01)) - o, 0.04), PLANK_GRAIN, pivot, mat, 0.006)
    finish("lantern_peg", place(prism(5, 0.02, 0.02, -0.05, 0.05), tip - o, Matrix.Rotation(math.radians(90), 4, "X")),
           BARK_DARK, pivot, mat)
    # Cordel y asa.
    finish("lantern_cord", place(prism(6, 0.009, 0.009, 0.0, LANTERN_HANG + 0.02), top - o - Vector((0, 0, 0.01))), BARK_DARK, pivot, mat)
    finish("lantern_handle", place(prism(6, 0.03, 0.03, -0.004, 0.004), top - o + Vector((0, 0, 0.022)),
           Matrix.Rotation(math.radians(90), 4, "X")),
           BARK_DARK, pivot, mat)
    # Farol: base y tapa hexagonales de madera, tres varillas y la cazoleta de barro con la llama dentro.
    finish("lantern_base", prism(6, LANTERN_R, LANTERN_R * 0.92, 0.0, 0.03), PLANK, pivot, mat, 0.006)
    finish("lantern_cap", prism(6, LANTERN_R, LANTERN_R * 0.35, LANTERN_H - 0.03, LANTERN_H + 0.035), PLANK, pivot, mat, 0.006)
    for k in range(3):
        a = k * 2.0 * math.pi / 3.0
        p = Vector((math.cos(a), math.sin(a), 0.0)) * (LANTERN_R * 0.78)
        finish("lantern_rod_%d" % k, place(prism(5, 0.008, 0.008, 0.02, LANTERN_H - 0.02), p), BARK_DARK, pivot, mat)
    finish("lantern_bowl", prism(8, 0.035, 0.05, 0.03, 0.065), CLAY, pivot, mat, 0.005)
    # Llama: una gota de seis lados (punta arriba), aparte para que Godot la haga brillar.
    flame = prism(6, 0.017, 0.0, 0.0, 0.075)
    bmesh.ops.remove_doubles(flame, verts=flame.verts, dist=0.0005)
    finish("lantern_flame", place(flame, (0.0, 0.0, 0.058)), FLAME, pivot, mat)
    empty("lantern_light", pivot, (0.0, 0.0, 0.1))
    n = sum(sum(len(p.vertices) - 2 for p in c.data.polygons) for c in pivot.children_recursive if c.type == "MESH")
    print("refugio: candil %d triángulos, a %.2f m del suelo" % (n, base_z))


# Fogón de los nómadas (detalle, no se repara; D-191): en la alcoba del este, un anillo de piedras sobre la ceniza, tres
# troncos cruzados con sus brasas, cuatro llamas y un trébede con una olla negra (donde se cocinará cuando haya hambre
# y agricultura). Las llamas («hearth_flame_N») y las brasas («hearth_embers») van aparte: Godot las hace brillar, las
# llamas bailan desde su base (su origen) y se esconden al apagarlo. «hearth_light» es donde Godot pone la luz.
HEARTH_CENTER = (2.75, 0.5)       # centrado en su alcoba, a la misma altura que la cama (filas 2 y 3)
HEARTH_SCALE = 1.35               # todo el fogón, más grande (César): se escala su vacío
POT_WALL = 0.014                  # grosor de la olla, que es hueca
POT_SCALE = 1.3                   # la olla, más grande que el resto del fogón
POT_IRON = (5, 7)                 # olla negra (César), del gris más oscuro del Nexo: brilla un poco, como hierro colado
HEARTH_RING_R = 0.3
TRIVET_Z = 0.34


def merged(parts):
    # Une varias bmesh en una sola.
    bm = bmesh.new()
    for part in parts:
        mesh = bpy.data.meshes.new("_tmp")
        part.to_mesh(mesh)
        part.free()
        bm.from_mesh(mesh)
        bpy.data.meshes.remove(mesh)
    return bm


def lathe(profile, sides, bottom=True):
    # Sólido de revolución: `profile` es una lista de (radio, altura) de abajo arriba.
    bm = bmesh.new()
    rings = []
    for r, z in profile:
        rings.append([bm.verts.new((r * math.cos(2 * math.pi * k / sides), r * math.sin(2 * math.pi * k / sides), z)) for k in range(sides)])
    if bottom:
        bm.faces.new(list(reversed(rings[0])))
    for a, b in zip(rings, rings[1:]):
        for k in range(sides):
            j = (k + 1) % sides
            bm.faces.new((a[k], a[j], b[j], b[k]))
    bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def pot_shell(profile, sides, wall):
    # Olla hueca: la pared de fuera (de abajo arriba), el borde y la de dentro (de arriba abajo) hasta su fondo. Cerrada,
    # así que las normales salen bien.
    bm = bmesh.new()
    inner = [(max(r - wall, 0.01), z) for r, z in profile[1:]]
    inner[-1] = (inner[-1][0], profile[-1][1])
    inner_bottom = profile[0][1] + wall * 1.5
    inner = [(inner[0][0] * 0.85, inner_bottom)] + inner[1:]
    path = profile + list(reversed(inner))
    rings = [[bm.verts.new((r * math.cos(2 * math.pi * k / sides), r * math.sin(2 * math.pi * k / sides), z)) for k in range(sides)]
             for r, z in path]
    bm.faces.new(list(reversed(rings[0])))
    for a, b in zip(rings, rings[1:]):
        for k in range(sides):
            j = (k + 1) % sides
            bm.faces.new((a[k], a[j], b[j], b[k]))
    bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def build_hearth(root, mat):
    rng = random.Random(41)
    base = FLOOR_Z + TILE_THICK
    pivot = empty("hearth", root, (HEARTH_CENTER[0], HEARTH_CENTER[1], base))
    pivot.scale = (HEARTH_SCALE, HEARTH_SCALE, HEARTH_SCALE)
    # Ceniza y anillo de piedras, cada una con su tamaño, su giro y su tono.
    finish("hearth_ash", prism(10, 0.25, 0.23, 0.0, 0.018), STONE_DARK, pivot, mat)
    stone_colors = (STONE, STONE_LIGHT, STONE_DARK, STONE)
    # 16 piedras que se tocan y cierran el círculo (César: con 10 quedaban huecos), unas grandes y otras pequeñas,
    # alargadas a lo largo del anillo.
    count = 16
    sizes = [0.085 if k % 3 == 0 else (0.06 if k % 3 == 1 else 0.07) for k in range(count)]
    for k in range(count):
        a = 2 * math.pi * k / count + rng.uniform(-0.05, 0.05)
        r = sizes[k] * rng.uniform(0.92, 1.08)
        h = r * rng.uniform(1.0, 1.35)
        stone = prism(6, r, r * 0.72, 0.0, h, rng.uniform(0, math.pi))
        bmesh.ops.scale(stone, vec=(rng.uniform(0.75, 0.9), rng.uniform(1.05, 1.25), 1.0), verts=stone.verts)
        place(stone, (math.cos(a) * HEARTH_RING_R, math.sin(a) * HEARTH_RING_R, -0.01), Matrix.Rotation(a, 4, "Z"))
        finish("hearth_stone_%d" % k, stone, stone_colors[k % 4], pivot, mat, 0.008)
    # Tres troncos que se cruzan en el centro, con las puntas quemadas hacia dentro.
    for k in range(3):
        a = 2 * math.pi * k / 3 + 0.4
        out = Vector((math.cos(a) * 0.27, math.sin(a) * 0.27, 0.03))
        inner = Vector((math.cos(a) * 0.03, math.sin(a) * 0.03, 0.1))
        finish("hearth_log_%d" % k, beam(out, inner.lerp(out, 0.35), 0.055), PLANK, pivot, mat, 0.01)
        finish("hearth_log_end_%d" % k, beam(inner.lerp(out, 0.35), inner, 0.05), BARK_DARK, pivot, mat, 0.008)
    # Brasas: trocitos chatos sobre la ceniza, en una sola malla.
    parts = []
    for k in range(9):
        a = rng.uniform(0, 2 * math.pi)
        d = rng.uniform(0.02, 0.15)
        r = rng.uniform(0.025, 0.04)
        parts.append(place(prism(5, r, r * 0.6, 0.0, rng.uniform(0.015, 0.03), rng.uniform(0, 3)), (math.cos(a) * d, math.sin(a) * d, 0.012)))
    finish("hearth_embers", merged(parts), BARK_DARK, pivot, mat)
    # Llamas: gotas de seis lados, la más alta en el centro. Cada una con su origen en su base.
    for k, (dx, dy, r, h) in enumerate(((0.0, 0.0, 0.055, 0.26), (0.06, 0.035, 0.045, 0.19), (-0.05, 0.04, 0.042, 0.17),
                                       (0.01, -0.06, 0.04, 0.15))):
        flame = prism(6, r, 0.0, 0.0, h, k * 0.5)
        bmesh.ops.remove_doubles(flame, verts=flame.verts, dist=0.0005)
        obj = finish("hearth_flame_%d" % k, flame, FLAME, pivot, mat)
        obj.location = (dx, dy, 0.07)
    # Trébede: aro de hierro de seis tramos y tres patas abiertas.
    ring = [Vector((math.cos(2 * math.pi * k / 6) * 0.17, math.sin(2 * math.pi * k / 6) * 0.17, TRIVET_Z)) for k in range(6)]
    for k in range(6):
        a, b = ring[k], ring[(k + 1) % 6]
        d = (b - a).normalized()
        finish("hearth_trivet_ring_%d" % k, beam(a - d * 0.012, b + d * 0.012, 0.022), BARK_DARK, pivot, mat)
    for k in range(3):
        a = 2 * math.pi * k / 3 + math.pi / 6
        top = Vector((math.cos(a) * 0.17, math.sin(a) * 0.17, TRIVET_Z))
        foot = Vector((math.cos(a) * 0.26, math.sin(a) * 0.26, 0.0))
        finish("hearth_trivet_leg_%d" % k, beam(foot, top, 0.022), BARK_DARK, pivot, mat)
    # Olla de barro sobre el trébede, con el borde vuelto y el fondo oscuro por dentro.
    k = POT_SCALE   # olla más grande (César); su barriga sigue apoyada en el aro del trébede
    pot = pot_shell([(0.07 * k, TRIVET_Z - 0.04 * k), (0.12 * k, TRIVET_Z), (0.15 * k, TRIVET_Z + 0.08 * k),
                     (0.14 * k, TRIVET_Z + 0.16 * k), (0.11 * k, TRIVET_Z + 0.21 * k), (0.125 * k, TRIVET_Z + 0.235 * k)],
                    12, POT_WALL)
    finish("hearth_pot", pot, POT_IRON, pivot, mat)
    empty("hearth_light", pivot, (0.0, 0.0, 0.22))
    n = sum(sum(len(p.vertices) - 2 for p in c.data.polygons) for c in pivot.children_recursive if c.type == "MESH")
    print("refugio: fogón %d triángulos" % n)


# Detalles de fuera y cacharros de los nómadas (no se reparan; `Refugio.md` §5, D-192):
#   - dos aros de tierra en relieve alrededor de la boca, siguiendo el arco (los «anillos de la galería»: dentro ya no
#     caben, porque la sala de 16 casillas llega casi hasta la boca);
#   - tres cacharros de barro: una tinaja en la alcoba de la cama, un cántaro junto al fogón y una vasija rota bajo el
#     candil.
# El emblema gastado y las columnas de la colonia antigua se probaron aquí y se quitaron (César): los restos de la
# colonia irán sueltos por la isla (`H` en el plano).
MOUTH_RINGS = (0.22, 0.46)                                         # lo que se separa cada aro del borde de la boca
MOUTH_RING_R = 0.055
POTS = {
    "jar": ((-2.75, 1.45), [(0.05, 0.0), (0.1, 0.04), (0.13, 0.14), (0.11, 0.26), (0.06, 0.32), (0.075, 0.36)], (4, 2)),
    "jug": ((2.98, -0.38), [(0.045, 0.0), (0.085, 0.05), (0.095, 0.12), (0.06, 0.2), (0.045, 0.25), (0.055, 0.28)], (4, 1)),
}
BROKEN_POT_AT = (-1.12, -1.72)


def surface_hit(tree, x, z, depth=-7.0):
    # Punto y normal de la cara de fuera del montículo en (x, z), mirando desde el sur.
    hit = tree.ray_cast(Vector((x, depth, z)), Vector((0.0, 1.0, 0.0)), 12.0)
    return hit[0], hit[1]


def build_ruins(root, shell):
    mat = get_material()
    outside = get_outside_material()
    from mathutils.bvhtree import BVHTree
    dg = bpy.context.evaluated_depsgraph_get()
    bm = bmesh.new()
    bm.from_object(shell, dg)
    bm.transform(shell.matrix_world)
    tree = BVHTree.FromBMesh(bm)
    bm.free()
    pivot = empty("ruins", root, (0.0, 0.0, 0.0))
    # Aros alrededor de la boca: siguen el arco a la distancia dada, pegados a la fachada.
    for k, off in enumerate(MOUTH_RINGS):
        pts = []
        for i in range(17):
            t = math.pi * i / 16
            x = (GALLERY_HALF + off) * math.cos(t)
            z = (GALLERY_HEIGHT + off) * math.sin(t)
            hit, nrm = surface_hit(tree, x, max(z, 0.05))
            if hit is not None:
                pts.append(hit - Vector(nrm) * MOUTH_RING_R * 0.35)
        for i in range(len(pts) - 1):
            a, b = pts[i], pts[i + 1]
            d = (b - a).normalized()
            seg = prism(6, MOUTH_RING_R, MOUTH_RING_R, 0.0, (b - a).length + 0.03)
            place(seg, a - d * 0.015, d.to_track_quat("Z", "Y").to_matrix().to_4x4())
            finish("ruins_ring_%d_%d" % (k, i), seg, EARTH_WALL, pivot, outside)
    # Cacharros de barro (huecos, como la olla).
    base = FLOOR_Z + TILE_THICK
    for name, ((px, py), profile, color) in POTS.items():
        pot = pot_shell(profile, 10, 0.012)
        place(pot, (px, py, base))
        finish("ruins_%s" % name, pot, color, pivot, mat)
    # Vasija rota bajo el candil: la mitad de abajo y tres cascos por el suelo.
    half = pot_shell([(0.05, 0.0), (0.1, 0.04), (0.12, 0.12), (0.115, 0.16)], 10, 0.012)
    place(half, (BROKEN_POT_AT[0], BROKEN_POT_AT[1], base), Matrix.Rotation(math.radians(14), 4, "X"))
    finish("ruins_broken_pot", half, (4, 2), pivot, mat)
    rng = random.Random(7)
    for k in range(3):
        a = rng.uniform(0, 2 * math.pi)
        shard = prism(3, 0.06, 0.05, 0.0, 0.012, rng.uniform(0, 3))
        place(shard, (BROKEN_POT_AT[0] + math.cos(a) * 0.22, BROKEN_POT_AT[1] + math.sin(a) * 0.22, base),
              Matrix.Rotation(rng.uniform(-0.3, 0.3), 4, "X"))
        finish("ruins_shard_%d" % k, shard, (4, 2), pivot, mat)
    n = sum(sum(len(p.vertices) - 2 for p in c.data.polygons) for c in pivot.children_recursive if c.type == "MESH")
    print("refugio: restos y cacharros %d triángulos" % n)


def build_pieces(root):
    mat = get_material()
    rng = random.Random(23)
    build_props(root, mat)
    tiles = build_floor(root, mat, rng)
    build_awning(root, mat)
    build_bed(root, mat)
    build_hatch(root, mat)
    build_lantern(root, mat)   # detalles: no son piezas
    build_hearth(root, mat)
    # Donde reaparece Mira al descansar: en la sala, delante de la cama, mirando al este (hacia la sala). Sin girar, en
    # Godot mira a −Z (+Y de Blender); −90° en Z la pone mirando a +X.
    empty("spawn_point", root, (BED_CENTER[0] + 1.05, BED_CENTER[1], 0.0), math.radians(-90.0))
    print("refugio: %d baldosas" % tiles)


# --- Montar ---

def clear():
    old = bpy.data.objects.get(ROOT)
    if old is not None:
        for o in [old] + list(old.children_recursive):
            bpy.data.objects.remove(o, do_unlink=True)
    for name in ("_shelter_cutters",):
        col = bpy.data.collections.get(name)
        if col is not None:
            for o in list(col.objects):
                bpy.data.objects.remove(o, do_unlink=True)
            bpy.data.collections.remove(col)
    for mesh in list(bpy.data.meshes):
        if mesh.users == 0:
            bpy.data.meshes.remove(mesh)


def build():
    if bpy.context.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")
    clear()
    mat = get_material()
    inner = bpy.data.materials.get("_shelter_inner") or bpy.data.materials.new("_shelter_inner")

    root = bpy.data.objects.new(ROOT, None)
    root.empty_display_type = "PLAIN_AXES"
    bpy.context.collection.objects.link(root)

    # Por dentro, su propio material (en Godot, `shelter_inner.tres`: tierra de hormiguero con capas, motas y surcos);
    # las piezas, la paleta normal.
    shell = to_object("shelter_shell", build_mound(), get_material("shelter_inner"), root)
    shell.data.materials.append(inner)

    cutters = bpy.data.collections.new("_shelter_cutters")
    bpy.context.scene.collection.children.link(cutters)
    shapes = {
        "cut_room": build_room(),
        "cut_gallery": build_gallery(),
        "cut_cavity": build_cavity(),
        # Cama: alcoba de 1 × 2 en la pared oeste (columna 1, filas 2 y 3).
        "cut_bed": build_alcove(*BED_ALCOVE),
        # Fogón: alcoba pequeña en la pared este (columna 6, fila 3).
        "cut_hearth": build_alcove(*HEARTH_ALCOVE),
    }
    for name, bm in shapes.items():
        o = to_object(name, bm, inner)
        bpy.context.collection.objects.unlink(o)
        cutters.objects.link(o)

    mod = shell.modifiers.new("cut", "BOOLEAN")
    mod.operation = "DIFFERENCE"
    mod.operand_type = "COLLECTION"
    mod.collection = cutters
    mod.solver = "EXACT"
    bpy.context.view_layer.objects.active = shell
    bpy.ops.object.modifier_apply(modifier=mod.name)

    for o in list(cutters.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    bpy.data.collections.remove(cutters)

    paint(shell, inner, get_outside_material())
    if inner.users == 0:
        bpy.data.materials.remove(inner)

    tris = sum(len(p.vertices) - 2 for p in shell.data.polygons)
    print("refugio: cascarón", tris, "triángulos")
    global _shell_tree
    _shell_tree = None   # el cascarón es nuevo: se vuelve a medir
    build_pieces(root)
    build_ruins(root, shell)
    for name in ("piece_props", "piece_floor", "piece_awning", "piece_bed", "piece_hatch"):
        pivot = bpy.data.objects[name]
        n = sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in pivot.children_recursive if o.type == "MESH")
        print("  %s: %d triángulos" % (name, n))
    return root


build()
