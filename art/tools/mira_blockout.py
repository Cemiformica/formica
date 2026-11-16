# Mira (B4, D-099 y D-100): blockout de la protagonista, por partes.
# Figura articulada de juguete: cada pieza es rígida y colgará de un solo hueso (sin pintado de pesos).
# Hoja de diseño: claude/Mira.md del proyecto (proporciones, colores y presupuesto).
#
# Convenciones:
#   - 1 unidad = 1 m. Origen entre los pies, a ras de suelo. Mira mide 1,8 m (sin antenas).
#   - Mira MIRA A −Y (vista frontal de Blender, tecla 1 del teclado numérico): al exportar a glTF queda
#     mirando a +Z en Godot, que es el frente de modelo estándar (Vector3.MODEL_FRONT).
#   - Su derecha es −X (la izquierda de quien la mira de frente). La antena doblada es la derecha.
#   - Cada parte cuelga de un vacío con el nombre del hueso que la moverá (head, antenna_r…); el
#     esqueleto se añadirá en un paso posterior.
#   - Mira es un escalón más fina que las máquinas (César, B4.2): superficies redondas con sombreado suave,
#     y la quitina, los ojos y el cristal con el material brillante `palette_gloss`, que además oscurece
#     las piezas hacia abajo con un degradado (atributo de color «shade»).
#
# Uso: Editor de texto de Blender → abrir → Alt+P. Borra y rehace las partes de PARTS.
# Dónde tocar: las constantes de medidas de cada parte y los colores (fila, columna de palette.png).

import bpy
import bmesh
import math
import os
import sys
from mathutils import Matrix, Vector

PALETTE = 64
SWATCH = 8
TEXTURE = "//../../assets/textures/palette.png"
SURFACE = "//../../assets/textures/palette_surface.png"   # R = metálico, G = rugosidad por color (D-105)
# Ropa de Mira: va con `palette_cloth` (mate, sin el mapa de superficie) aunque use los grises del Nexo,
# para que la tela no parezca metal. Se reconoce por el principio del nombre de la pieza.
CLOTH_PREFIXES = ("coat", "sleeve", "glove", "goggles_strap", "mask_strap", "backpack_strap", "head_shine")

# Colores (fila, columna) de palette.png
SKIN = (3, 2)          # naranja intenso de la quitina
SKIN_DARK = (3, 3)     # antenas, cuello, segmentos
SKIN_DEEP = (4, 3)     # mandíbulas
EYE_RIM = (7, 4)       # globo del ojo: azul oscuro (asoma como media luna)
PUPIL = (5, 7)         # pupila grande, casi negra
MOUTH = (0, 7)         # boca y orificios de la nariz (marrón casi negro)
STRAP = (7, 7)         # cinta de tela de las gafas (gris azulado)
SHINE = (5, 0)         # brillos del ojo
LENS = (7, 3)          # fondo de la lente
LENS_CELLS = [(7, 1), (7, 2), (7, 0)]  # nido de abeja: el centro más claro
COPPER = (3, 0)        # aros de cobre de las gafas
AMBER = (6, 2)         # luces (emisivo)
METAL = (5, 4)         # grises del Nexo
METAL_DARK = (5, 5)
METAL_LIGHT = (5, 2)
COAT = (5, 0)          # bata: blanco gastado
COAT_SHADE = (5, 1)    # cuello, tapeta y puños
COAT_PATCH = (5, 2)    # remiendo de otro gris
DUST = (1, 2)          # bajo de la bata manchado de polvo
SHIRT = (5, 5)         # camiseta gris oscuro, bajo la bata
GLOVE = (5, 5)         # guante sin dedos de la mano derecha (gris oscuro)
STITCH = (5, 6)        # costuras del remiendo
LAPEL = (5, 2)         # solapas y cuello de la bata: un gris más oscuro que la tela
BOOT = (5, 3)          # botas
BOOT_SOLE = (5, 6)     # suela

# Proporciones de la referencia de César (B4.2): cabeza grande (casi 1/3 de la altura), hombros estrechos
# y caídos, bata larga y abierta, piernas cortas y finas y abdomen grande detrás.
HEAD_SCALE = 1.45      # la cabeza se modela a tamaño «1» y se agranda al final alrededor del cuello
HAND_SCALE = 1.35     # manos y pies, grandes respecto a brazos y piernas
FOOT_SCALE = 1.35
HEAD_DROP = 0.151      # y se baja para que la coronilla siga a 1,80 m (ojos a ~1,6 m)

PARTS = ["head", "body", "arms", "legs", "abdomen", "backpack"]  # se irán añadiendo: "body", "arms", "legs", "abdomen", "backpack"

# --- Cabeza (hoja §3: 1,38–1,80 m; 0,46 m de ancho; ojos a 1,58 m) ---
HEAD_CENTER = Vector((0.0, 0.0, 1.59))
HEAD_RX, HEAD_RY, HEAD_RZ = 0.24, 0.21, 0.205   # más ancha que alta (1,2:1), como la referencia
HEAD_JAW_TAPER = 0.3    # cuánto se estrecha hacia la barbilla
HEAD_TOP_FLAT = 0.92    # aplasta un poco la coronilla
HEAD_Z = (1.385, 1.78)  # altura de la cabeza: para que párpados y cráneo compartan el degradado
# Rasgos medidos sobre la referencia de César (B4.2), en la esfera unidad (x a los lados, z arriba):
EYE_U = (0.58, 0.14)     # centro de cada ojo: muy separados y algo por encima del centro
EYE_A, EYE_B, EYE_D = 0.085, 0.075, 0.056   # semiejes del ojo: ancho, alto y fondo (m)
RIDGE_TOP = 0.6         # donde nace la cuña central, en la frente
SNOUT = 0.21            # cuánto sobresale la punta del morro (la cuña crece de la frente a la nariz)
SNOUT_Z = -0.28         # altura de la nariz: justo bajo los ojos
MUZZLE = 0.11           # la parte baja de la cara (boca) también avanza un poco
CHEEK = 0.045           # pómulos, bajo los ojos
LIP = 0.03              # labio inferior
MOUTH_Z = -0.56         # centro de la boca
MOUTH_W = 0.45          # media anchura de la sonrisa
MOUTH_CURVE = 0.2       # cuánto suben las comisuras
SHADE_BOTTOM = 0.72     # degradado: la parte de abajo de cada pieza brillante, a este % de su color


# ---------------------------------------------------------------- utilidades

def swatch_uv(row: int, col: int) -> Vector:
    return Vector(((col * SWATCH + SWATCH / 2) / PALETTE, 1.0 - (row * SWATCH + SWATCH / 2) / PALETTE))


def get_materials() -> dict:
    # palette (mate), palette_emissive (luces) y palette_gloss (brillante, con el degradado «shade»).
    base = bpy.data.materials.get("palette")
    if base is None:
        img = bpy.data.images.load(TEXTURE, check_existing=True)
        base = bpy.data.materials.new("palette")
        base.use_nodes = True
        nt = base.node_tree
        nt.nodes.clear()
        out = nt.nodes.new("ShaderNodeOutputMaterial"); out.location = (300, 0)
        bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled"); bsdf.location = (0, 0)
        tex = nt.nodes.new("ShaderNodeTexImage"); tex.location = (-350, 0)
        tex.image = img
        tex.interpolation = "Closest"
        bsdf.inputs["Roughness"].default_value = 0.8
        nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
        nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    glow = bpy.data.materials.get("palette_emissive")
    if glow is None:
        glow = base.copy()
        glow.name = "palette_emissive"
        nt = glow.node_tree
        tex = next(n for n in nt.nodes if n.type == "TEX_IMAGE")
        nt.links.new(tex.outputs["Color"], nt.nodes["Principled BSDF"].inputs["Emission Color"])
    glow.node_tree.nodes["Principled BSDF"].inputs["Emission Strength"].default_value = 1.5
    gloss = bpy.data.materials.get("palette_gloss")
    if gloss is None:
        gloss = base.copy()
        gloss.name = "palette_gloss"
        nt = gloss.node_tree
        bsdf = nt.nodes["Principled BSDF"]
        tex = next(n for n in nt.nodes if n.type == "TEX_IMAGE")
        attr = nt.nodes.new("ShaderNodeVertexColor"); attr.location = (-350, -280)
        attr.layer_name = "shade"
        mix = nt.nodes.new("ShaderNodeMix"); mix.location = (-120, -60)
        mix.data_type = "RGBA"
        mix.blend_type = "MULTIPLY"
        mix.inputs["Factor"].default_value = 1.0
        nt.links.new(tex.outputs["Color"], mix.inputs[6])
        nt.links.new(attr.outputs["Color"], mix.inputs[7])
        nt.links.new(mix.outputs[2], bsdf.inputs["Base Color"])
    # Brillo: quitina pulida, como la de una hormiga de verdad. Se fija siempre para poder ajustarlo aquí.
    gloss.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.3
    cloth = bpy.data.materials.get("palette_cloth")
    if cloth is None:
        cloth = base.copy()
        cloth.name = "palette_cloth"
        strip_surface(cloth)
        cloth.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.85
    add_surface(base)   # al final: las copias de arriba no deben llevar el mapa
    return {"base": base, "glow": glow, "gloss": gloss, "cloth": cloth}


def add_surface(mat) -> None:
    # Conecta el mapa de superficie al material: metálico (rojo) y rugosidad (verde) según el color
    # de la paleta, como palette.tres en Godot. No hace nada si ya está conectado.
    nt = mat.node_tree
    if nt.nodes.get("surface") is not None:
        return
    img = bpy.data.images.load(SURFACE, check_existing=True)
    img.colorspace_settings.name = "Non-Color"
    tex = nt.nodes.new("ShaderNodeTexImage"); tex.name = "surface"; tex.location = (-350, -300)
    tex.image = img
    tex.interpolation = "Closest"
    sep = nt.nodes.new("ShaderNodeSeparateColor"); sep.name = "surface_split"; sep.location = (-150, -300)
    bsdf = nt.nodes["Principled BSDF"]
    nt.links.new(tex.outputs["Color"], sep.inputs["Color"])
    nt.links.new(sep.outputs["Red"], bsdf.inputs["Metallic"])
    nt.links.new(sep.outputs["Green"], bsdf.inputs["Roughness"])


def strip_surface(mat) -> None:
    for name in ("surface", "surface_split"):
        node = mat.node_tree.nodes.get(name)
        if node is not None:
            mat.node_tree.nodes.remove(node)


def dress_cloth(root, mats) -> None:
    # La ropa pasa al material mate de tela (ver CLOTH_PREFIXES).
    for obj in root.children_recursive:
        if obj.type == "MESH" and obj.name.startswith(CLOTH_PREFIXES):
            for slot in obj.material_slots:
                if slot.material is mats["base"]:
                    slot.material = mats["cloth"]


def finish(name: str, bm: bmesh.types.BMesh, color, parent, material, bevel: float = 0.0, smooth: bool = False,
           shade=(SHADE_BOTTOM, 1.0, 0.5), sharp_angle: float = 30.0, zrange=None):
    # zrange = (z0, z1): alturas entre las que se reparte el degradado (por defecto, las de la pieza).
    # shade = (abajo, arriba, curva): cuánto se multiplica el color abajo y arriba de la pieza (solo con
    # palette_gloss). Por defecto, un poco más oscura abajo; los ojos lo usan al revés (oscuros arriba).
    # smooth=True: sombreado suave en toda la pieza (formas orgánicas); si no, suavizado por ángulo (30°).
    if bevel > 0.0:
        bmesh.ops.bevel(bm, geom=list(bm.edges), offset=bevel, segments=1, affect="EDGES", profile=0.5, clamp_overlap=True)
    uv = bm.loops.layers.uv.new("UVMap")
    for f in bm.faces:
        for loop in f.loops:
            loop[uv].uv = swatch_uv(*color)
    if material.name == "palette_gloss":
        # Degradado «shade»: blanco arriba y SHADE_BOTTOM abajo, multiplicado por el color de la paleta.
        layer = bm.loops.layers.color.new("shade")
        zs = [v.co.z for v in bm.verts]
        z0, z1 = zrange if zrange is not None else (min(zs), max(zs))
        for f in bm.faces:
            for loop in f.loops:
                t = (loop.vert.co.z - z0) / (z1 - z0) if z1 > z0 else 1.0
                k = shade[0] + (shade[1] - shade[0]) * max(0.0, min(1.0, t)) ** shade[2]
                loop[layer] = (k, k, k, 1.0)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    mesh.materials.append(material)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    attach(obj, parent)
    for p in mesh.polygons:
        p.use_smooth = True
    if not smooth:
        mesh.set_sharp_from_angle(angle=math.radians(sharp_angle))
    return obj


def attach(obj, parent):
    # Cuelga `obj` de `parent` sin moverlo: las piezas se modelan en coordenadas del mundo. Como todos los
    # vacíos se cuelgan así y solo se desplazan, la `location` de un vacío es ya su posición en el mundo.
    obj.parent = parent
    if parent is not None:
        obj.matrix_parent_inverse = Matrix.Translation(-Vector(parent.location))


def empty(name: str, location, parent=None):
    # Vacío en el pivote de una parte (donde irá la articulación de su hueso).
    obj = bpy.data.objects.new(name, None)
    obj.empty_display_size = 0.08
    obj.location = location
    bpy.context.collection.objects.link(obj)
    attach(obj, parent)
    return obj


def merge(*parts) -> bmesh.types.BMesh:
    # Junta varios bmesh en uno (una sola pieza al exportar).
    out = bmesh.new()
    for part in parts:
        mesh = bpy.data.meshes.new("tmp")
        part.to_mesh(mesh)
        part.free()
        out.from_mesh(mesh)
        bpy.data.meshes.remove(mesh)
    return out


def prism(sides: int, r_bottom: float, r_top: float, z0: float, z1: float, angle: float = 0.0):
    bm = bmesh.new()
    bottom, top = [], []
    for i in range(sides):
        a = angle + 2.0 * math.pi * i / sides
        bottom.append(bm.verts.new((r_bottom * math.cos(a), r_bottom * math.sin(a), z0)))
        top.append(bm.verts.new((r_top * math.cos(a), r_top * math.sin(a), z1)))
    bm.faces.new(list(reversed(bottom)))
    bm.faces.new(top)
    for i in range(sides):
        j = (i + 1) % sides
        bm.faces.new((bottom[i], bottom[j], top[j], top[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def bar(p0, p1, r0: float, r1: float, sides: int = 6):
    # Barra de sección poligonal de p0 a p1 (brazos, antenas…).
    p0, p1 = Vector(p0), Vector(p1)
    d = p1 - p0
    bm = prism(sides, r0, r1, 0.0, d.length)
    rot = Vector((0.0, 0.0, 1.0)).rotation_difference(d.normalized()).to_matrix().to_4x4()
    bmesh.ops.transform(bm, matrix=Matrix.Translation(p0) @ rot, verts=bm.verts)
    return bm


def ball(center, radius: float, subdivisions: int = 1, scale=(1.0, 1.0, 1.0)):
    # Bola facetada (icosaedro): para piezas pequeñas.
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=subdivisions, radius=radius)
    bmesh.ops.scale(bm, vec=scale, verts=bm.verts)
    bmesh.ops.translate(bm, vec=Vector(center), verts=bm.verts)
    return bm


def sphere(center, radii, segments: int = 16, rings: int = 10):
    # Esfera redonda (UV) con radios por eje: para formas orgánicas con sombreado suave.
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segments, v_segments=rings, radius=1.0)
    bmesh.ops.scale(bm, vec=radii, verts=bm.verts)
    bmesh.ops.translate(bm, vec=Vector(center), verts=bm.verts)
    return bm


def place_facing(bm, location, normal):
    # Lleva una pieza hecha «mirando a −Y» (cara delantera hacia −Y) hasta `location`, mirando a `normal`.
    rot = Vector((0.0, -1.0, 0.0)).rotation_difference(Vector(normal).normalized()).to_matrix().to_4x4()
    bmesh.ops.transform(bm, matrix=Matrix.Translation(Vector(location)) @ rot, verts=bm.verts)
    return bm


def disc(radius: float, depth: float, sides: int = 6, angle: float = math.radians(30), r_front: float = None):
    # Disco poligonal «mirando a −Y»: su cara trasera en y = 0 y la delantera en y = −depth.
    bm = prism(sides, radius, radius if r_front is None else r_front, 0.0, depth, angle)
    bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(math.radians(90), 3, "X"))
    return bm


def ring(r_out: float, r_in: float, depth: float, sides: int = 6, angle: float = math.radians(30)):
    # Aro poligonal «mirando a −Y» (marco con hueco), de y = 0 a y = −depth.
    bm = bmesh.new()
    rings = []
    for y in (0.0, -depth):
        outer = [bm.verts.new((r_out * math.cos(angle + 2 * math.pi * i / sides), y,
                               r_out * math.sin(angle + 2 * math.pi * i / sides))) for i in range(sides)]
        inner = [bm.verts.new((r_in * math.cos(angle + 2 * math.pi * i / sides), y,
                               r_in * math.sin(angle + 2 * math.pi * i / sides))) for i in range(sides)]
        rings.append((outer, inner))
    (ob, ib), (of, if_) = rings
    for i in range(sides):
        j = (i + 1) % sides
        bm.faces.new((of[i], of[j], if_[j], if_[i]))   # cara delantera
        bm.faces.new((ob[j], ob[i], ib[i], ib[j]))     # cara trasera
        bm.faces.new((ob[i], ob[j], of[j], of[i]))     # canto exterior
        bm.faces.new((ib[j], ib[i], if_[i], if_[j]))   # canto interior
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def _bump(d2: float) -> float:
    return math.exp(-d2)


def head_point(u) -> Vector:
    # Deforma un punto de la esfera unidad (u) en la superficie de la cabeza. Solo relieves suaves y
    # amplios (los ojos y sus párpados son piezas aparte, para que la piel no se arrugue):
    #   - cuña central que crece desde la frente hasta la punta del morro y se corta bajo la nariz;
    #   - parte baja de la cara adelantada, pómulos y labio inferior.
    x, y, z = u
    k = 1.0
    front = max(0.0, min(1.0, -y * 1.4))
    if front > 0.0:
        t = max(0.0, min(1.0, (RIDGE_TOP - z) / (RIDGE_TOP - SNOUT_Z)))
        if z >= SNOUT_Z:
            amp = SNOUT * t ** 1.3
        else:
            amp = SNOUT * _bump(((z - SNOUT_Z) / 0.1) ** 2)
        w = 0.12 + 0.1 * (1.0 - t)
        k += amp * _bump((x / w) ** 4) * front
        k += MUZZLE * _bump((x / 0.5) ** 2 + ((z + 0.5) / 0.3) ** 2) * front
        for sx in (1.0, -1.0):
            k += CHEEK * _bump(((x - sx * 0.5) / 0.22) ** 2 + ((z + 0.32) / 0.2) ** 2) * front
        k += LIP * _bump((x / 0.2) ** 2 + ((z + 0.7) / 0.07) ** 2) * front
    taper = 1.0 - HEAD_JAW_TAPER * max(0.0, -z)
    X = x * HEAD_RX * taper * k
    Y = y * HEAD_RY * k
    Z = z * HEAD_RZ * (HEAD_TOP_FLAT if z > 0.0 else 1.0) * k
    return HEAD_CENTER + Vector((X, Y, Z))


def decimate(bm: bmesh.types.BMesh, ratio: float) -> bmesh.types.BMesh:
    # Simplifica una malla con el modificador Decimate (menos triángulos con la misma forma), con
    # simetría para que la cara quede igual a los dos lados.
    mesh = bpy.data.meshes.new("tmp_decimate")
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new("tmp_decimate", mesh)
    bpy.context.collection.objects.link(obj)
    mod = obj.modifiers.new("decimate", "DECIMATE")
    mod.ratio = ratio
    mod.use_symmetry = True
    mod.symmetry_axis = "X"
    deps = bpy.context.evaluated_depsgraph_get()
    ev = obj.evaluated_get(deps)
    out = bmesh.new()
    out.from_mesh(ev.to_mesh())
    ev.to_mesh_clear()
    bpy.data.objects.remove(obj, do_unlink=True)
    bpy.data.meshes.remove(mesh)
    return out


def tube(points, radius, normals, sides: int = 6, closed: bool = False) -> bmesh.types.BMesh:
    # Tubo que sigue una lista de puntos sobre una superficie (boca, párpados). `radius` puede ser un
    # número o una lista (un radio por punto); `normals`, la normal de la superficie en cada punto
    # (evita que el tubo se retuerza). closed=True une el final con el principio.
    bm = bmesh.new()
    pts = [Vector(p) for p in points]
    n = len(pts)
    radii = radius if isinstance(radius, (list, tuple)) else [radius] * n
    rings = []
    for i, p in enumerate(pts):
        if closed:
            t = (pts[(i + 1) % n] - pts[i - 1]).normalized()
        else:
            t = (pts[min(i + 1, n - 1)] - pts[max(i - 1, 0)]).normalized()
        a = Vector(normals[i])
        a = (a - t * a.dot(t)).normalized()
        b = t.cross(a).normalized()
        rings.append([bm.verts.new(p + (a * math.cos(2 * math.pi * j / sides) + b * math.sin(2 * math.pi * j / sides)) * radii[i])
                      for j in range(sides)])
    for i in range(n if closed else n - 1):
        i2 = (i + 1) % n
        for j in range(sides):
            k = (j + 1) % sides
            bm.faces.new((rings[i][j], rings[i][k], rings[i2][k], rings[i2][j]))
    if not closed:
        bm.faces.new(list(reversed(rings[0])))
        bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def orient(bm, center, front, up_hint=(0.0, 0.0, 1.0)):
    # Lleva una pieza hecha «mirando a −Y» hasta `center`, mirando a `front` y con su Z hacia arriba.
    # Devuelve (eje_x, arriba): los ejes de la pieza en el mundo, para colocar cosas sobre ella.
    front = Vector(front).normalized()
    up = Vector(up_hint)
    up = (up - front * up.dot(front)).normalized()
    x_axis = (-front).cross(up).normalized()
    m = Matrix((x_axis, -front, up)).transposed().to_4x4()
    bmesh.ops.transform(bm, matrix=Matrix.Translation(Vector(center)) @ m, verts=bm.verts)
    return x_axis, up


def head_surface(direction):
    # Punto de la superficie de la cabeza en una dirección, y su normal (calculada con dos puntos vecinos).
    d = Vector(direction).normalized()
    t1 = d.cross(Vector((0.0, 0.0, 1.0)))
    if t1.length < 1e-4:
        t1 = Vector((1.0, 0.0, 0.0))
    t1.normalize()
    t2 = d.cross(t1).normalized()
    e = 0.01
    p = head_point(d)
    a = head_point((d + t1 * e).normalized()) - head_point((d - t1 * e).normalized())
    b = head_point((d + t2 * e).normalized()) - head_point((d - t2 * e).normalized())
    n = a.cross(b).normalized()
    if n.dot(p - HEAD_CENTER) < 0.0:
        n = -n
    return p, n


def frame_axes(n):
    # Ejes «derecha» y «arriba» de una superficie que mira a `n` (para colocar cosas sobre ella).
    right = n.cross(Vector((0.0, 0.0, 1.0))).normalized()
    up = right.cross(n).normalized()
    return right, up


# ---------------------------------------------------------------- cabeza

def build_head(root, mats):
    gloss = mats["gloss"]
    head = empty("head", (0.0, 0.0, 1.40), bpy.data.objects.get("neck") or root)  # pivote del cuello

    # Cráneo: esfera fina deformada con los rasgos (head_point), aligerada y con sombreado suave.
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=4, radius=1.0)
    for v in bm.verts:
        v.co = head_point(v.co.normalized())
    bm = decimate(bm, 0.28)
    finish("head_skull", bm, SKIN, head, gloss, smooth=True, zrange=HEAD_Z)

    build_eyes(head, mats)

    # Boca: sonrisa ancha y oscura bajo el morro; nariz: dos orificios cerca de la punta.
    pts, nrm = [], []
    steps = 18
    for i in range(steps + 1):
        t = -1.0 + 2.0 * i / steps
        p, n = head_surface((t * MOUTH_W, -0.8, MOUTH_Z + MOUTH_CURVE * t * t))
        pts.append(p + n * 0.0015)
        nrm.append(n)
    radii = [0.0085 * (0.45 + 0.55 * math.sqrt(max(0.0, 1.0 - (-1.0 + 2.0 * i / steps) ** 2))) for i in range(steps + 1)]
    finish("head_mouth", tube(pts, radii, nrm, 6), MOUTH, head, mats["base"], smooth=True)
    for side, sx in (("l", 1.0), ("r", -1.0)):
        p, n = head_surface((sx * 0.05, -1.0, SNOUT_Z + 0.035))
        finish("head_nostril_" + side, sphere(p + n * 0.001, (0.007, 0.0055, 0.006), 8, 6), MOUTH, head,
               mats["base"], smooth=True)

    build_antennae(head, mats)
    build_goggles(head, mats)


def build_eyes(head, mats):
    # Ojos de la referencia: grandes, ovalados y muy separados, casi negros y brillantes, con una media
    # luna azul oscuro en el borde de fuera y dos brillos blancos. Cada ojo son dos cúpulas (globo azul
    # y gran pupila negra) y un párpado naranja aparte que sigue la piel, más grueso arriba (ceja).
    gloss = mats["gloss"]
    for side, sx in (("l", 1.0), ("r", -1.0)):
        pos, n = head_surface((sx * EYE_U[0], -0.77, EYE_U[1]))
        look = (n + Vector((0.0, -0.5, 0.0))).normalized()
        center = pos - look * 0.036
        globe = sphere((0, 0, 0), (EYE_A, EYE_D, EYE_B), 14, 8)
        x_axis, up = orient(globe, center, look)
        finish("head_eye_" + side, globe, EYE_RIM, head, gloss, smooth=True, shade=(0.4, 0.55, 1.0))
        # Pupila: un poco hacia la nariz y hacia abajo, para que el azul asome por fuera y por arriba.
        pa, pb, pd = EYE_A * 0.94, EYE_B * 0.94, EYE_D + 0.003
        pc = center + x_axis * (-sx * 0.006) - up * 0.004 + look * 0.003
        pupil = sphere((0, 0, 0), (pa, pd, pb), 14, 8)
        orient(pupil, pc, look)
        finish("head_pupil_" + side, pupil, PUPIL, head, gloss, smooth=True, shade=(1.0, 1.0, 1.0))
        for k, (du, dv, ra, rb) in enumerate(((-sx * 0.018, 0.022, 0.017, 0.012), (sx * 0.03, -0.016, 0.007, 0.007))):
            depth = pd * math.sqrt(max(0.0, 1.0 - (du / pa) ** 2 - (dv / pb) ** 2))
            shine = sphere((0, 0, 0), (ra, 0.0012, rb), 8, 4)   # casi plano: no sobresale del ojo
            orient(shine, pc + x_axis * du + up * dv + look * (depth - 0.0012), look)
            finish("head_shine_%s_%d" % (side, k), shine, SHINE, head, mats["base"], smooth=True)
        # Párpado: tubo cerrado sobre la piel, justo en la línea donde el ojo sale de la cabeza (se busca
        # en cada dirección el punto de la piel en que el ojo deja de asomar), para que lo tape siempre.
        def inside(p) -> bool:
            for c, ra, rb, rd in ((center, EYE_A, EYE_B, EYE_D), (pc, pa, pb, pd)):
                d = p - c
                if (d.dot(x_axis) / ra) ** 2 + (d.dot(up) / rb) ** 2 + (d.dot(look) / rd) ** 2 < 1.0:
                    return True
            return False

        pts, nrm, radii = [], [], []
        steps = 20
        for i in range(steps):
            a = 2.0 * math.pi * i / steps
            ray = x_axis * (math.cos(a) * EYE_A) + up * (math.sin(a) * EYE_B)
            lo, hi = 0.3, 1.6
            for _ in range(18):
                mid = 0.5 * (lo + hi)
                p, pn = head_surface(pos + ray * mid - HEAD_CENTER)
                if inside(p):
                    lo = mid
                else:
                    hi = mid
            p, pn = head_surface(pos + ray * hi - HEAD_CENTER)
            r = 0.0055 + 0.011 * max(0.0, math.sin(a + 0.25 * sx)) ** 0.8
            pts.append(p + pn * (r * 0.35))
            nrm.append(pn)
            radii.append(r)
        finish("head_eyelid_" + side, tube(pts, radii, nrm, 5, closed=True), SKIN, head, gloss, smooth=True,
               zrange=HEAD_Z)


def build_antennae(head, mats):
    # Antenas acodadas con punta de bola. La derecha (−X) está doblada y lleva un aro de reparación.
    gloss = mats["gloss"]
    specs = {
        "l": [(0.105, 0.0, 1.75), (0.155, 0.02, 1.97), (0.215, -0.08, 2.12)],
        "r": [(-0.105, 0.0, 1.75), (-0.155, 0.02, 1.97), (-0.2, -0.05, 2.07), (-0.27, -0.1, 2.03)],
    }
    for side, pts in specs.items():
        pts = [Vector(p) for p in pts]
        base = empty("antenna_" + side, pts[0], head)
        tip = empty("antenna_" + side + "_tip", pts[1], base)
        finish("antenna_%s_scape" % side, merge(bar(pts[0], pts[1], 0.02, 0.016, 8), ball(pts[0], 0.022, 1)),
               SKIN_DARK, base, gloss, smooth=True)
        parts = [bar(pts[k], pts[k + 1], 0.016, 0.013, 8) for k in range(1, len(pts) - 1)]
        parts += [ball(pts[k], 0.019, 1) for k in range(1, len(pts) - 1)]  # rótulas en los codos
        finish("antenna_%s_flagellum" % side, merge(*parts), SKIN_DARK, tip, gloss, smooth=True)
        finish("antenna_%s_bulb" % side, sphere(pts[-1], (0.036, 0.036, 0.036), 10, 6), SKIN, tip, gloss, smooth=True)
        if side == "r":
            d = (pts[2] - pts[1]).normalized()
            mid = pts[1].lerp(pts[2], 0.55)
            finish("antenna_r_ring", bar(mid - d * 0.016, mid + d * 0.016, 0.024, 0.024, 6), METAL_LIGHT, tip,
                   mats["base"], bevel=0.003)


def build_goggles(head, mats):
    # Gafas de ojo compuesto en la frente: cinta con hebilla, montura gris con aro de cobre y tornillos,
    # lente con nido de abeja en tres tonos, sensores con luz ámbar y una lupa abatible a la derecha
    # (la científica que mira de cerca).
    base, gloss, glow = mats["base"], mats["gloss"], mats["glow"]
    # Cinta de tela: tira fina pegada a la cabeza, alta en la frente y más baja en la nuca, como unas
    # gafas de verdad; hebilla de cobre detrás.
    segs = 36
    rows = []
    for i in range(segs):
        th = 2.0 * math.pi * i / segs                     # 0 = frente, pi = nuca
        zc = 0.55 + 0.2 * math.cos(th)                     # 0,75 delante, 0,35 detrás
        ring_pts = []
        for dzu in (-0.065, 0.065):
            zu = zc + dzu
            r = math.sqrt(max(0.0, 1.0 - zu * zu))
            p, n = head_surface((r * math.sin(th), -r * math.cos(th), zu))
            ring_pts.append((p + n * 0.0015, p + n * 0.0055))
        rows.append(ring_pts)
    band = bmesh.new()
    vs = [[(band.verts.new(bi), band.verts.new(bo)), (band.verts.new(ti), band.verts.new(to))]
          for (bi, bo), (ti, to) in rows]
    for i in range(segs):
        j = (i + 1) % segs
        (bi0, bo0), (ti0, to0) = vs[i]
        (bi1, bo1), (ti1, to1) = vs[j]
        band.faces.new((bo0, bo1, to1, to0))   # cara de fuera
        band.faces.new((ti0, ti1, bi1, bi0))   # cara de dentro
        band.faces.new((to0, to1, ti1, ti0))   # canto de arriba
        band.faces.new((bi0, bi1, bo1, bo0))   # canto de abajo
    bmesh.ops.recalc_face_normals(band, faces=band.faces)
    finish("goggles_strap", band, STRAP, head, base, smooth=True)
    bp, bn = head_surface((0.0, 0.94, 0.35))
    finish("goggles_buckle", place_facing(ring(0.026, 0.014, 0.006, 4, math.radians(45)), bp + bn * 0.004, bn),
           COPPER, head, base)

    for side, sx in (("l", 1.0), ("r", -1.0)):
        pos, n = head_surface((sx * 0.3, -0.6, 0.75))
        n = (n + Vector((0.0, -0.6, 0.0))).normalized()
        right, up = frame_axes(n)
        finish("goggles_frame_" + side, place_facing(disc(0.062, 0.035, r_front=0.056), pos + n * 0.008, n),
               METAL_LIGHT, head, base, bevel=0.005)
        lens_front = pos + n * 0.043
        finish("goggles_rim_" + side, place_facing(ring(0.054, 0.045, 0.008), lens_front + n * 0.002, n),
               COPPER, head, gloss)
        finish("goggles_lens_" + side, place_facing(disc(0.046, 0.01), lens_front, n), LENS, head, gloss)
        # Nido de abeja: 7 celdas en relieve, la del centro más clara.
        cells = [(0.0, 0.0)] + [(0.025 * math.cos(math.radians(30 + 60 * i)), 0.025 * math.sin(math.radians(30 + 60 * i)))
                                for i in range(6)]
        for i, (cx, cy) in enumerate(cells):
            c = lens_front + n * 0.009 + right * cx + up * cy
            color = LENS_CELLS[0] if i == 0 else LENS_CELLS[1 + i % 2]
            finish("goggles_cell_%s_%d" % (side, i), place_facing(disc(0.0115, 0.004, r_front=0.0095), c, n),
                   color, head, gloss)
        # Tres tornillos hexagonales en la montura.
        for j, a in enumerate((90, 210, 330)):
            off = right * (0.052 * math.cos(math.radians(a))) + up * (0.052 * math.sin(math.radians(a)))
            finish("goggles_screw_%s_%d" % (side, j), place_facing(disc(0.006, 0.006), pos + n * 0.044 + off, n),
                   METAL_DARK, head, base)
        # Bisagra donde la montura se une a la cinta.
        hinge_c, hn = head_surface((sx * 0.56, -0.4, 0.72))
        finish("goggles_hinge_" + side, place_facing(disc(0.016, 0.03, 8), hinge_c + hn * 0.005, hn),
               METAL, head, base)
        # Sensor: antenita a un lado de la montura con una luz ámbar en la punta.
        s0, _ = head_surface((sx * 0.9, -0.05, 0.55))
        s1 = s0 + Vector((sx * 0.03, 0.03, 0.075))
        finish("goggles_sensor_" + side, bar(s0, s1, 0.009, 0.007), METAL, head, base)
        finish("goggles_sensor_light_" + side, ball(s1, 0.013, 1), AMBER, head, glow)

    # Lupa abatible a la derecha (−X): brazo desde la bisagra y lente pequeña levantada sobre la frente.
    h, hn = head_surface((-0.56, -0.4, 0.72))
    a0 = h + hn * 0.02
    a1 = a0 + Vector((-0.012, -0.03, 0.06))
    finish("goggles_loupe_arm", merge(bar(a0, a1, 0.006, 0.006, 6), ball(a1, 0.009, 1)), METAL, head, base)
    ln = Vector((-0.35, -0.6, 0.72)).normalized()
    lc = a1 + ln * 0.004 + Vector((0.02, -0.01, 0.02))
    finish("goggles_loupe_frame", place_facing(ring(0.026, 0.018, 0.008), lc, ln), COPPER, head, gloss)
    finish("goggles_loupe_lens", place_facing(disc(0.019, 0.004), lc - ln * 0.002, ln), LENS_CELLS[0], head, gloss)


# ---------------------------------------------------------------- cuerpo

def loft(rings, sides: int = 12) -> bmesh.types.BMesh:
    # Pieza «a rodajas»: cada rodaja es (z, radio_x, radio_y) o (z, radio_x, radio_y, y).
    bm = bmesh.new()
    loops = []
    for ring_def in rings:
        z, rx, ry = ring_def[:3]
        y0 = ring_def[3] if len(ring_def) > 3 else 0.0
        loops.append([bm.verts.new((rx * math.cos(2 * math.pi * (j + 0.5) / sides),
                                    y0 + ry * math.sin(2 * math.pi * (j + 0.5) / sides), z)) for j in range(sides)])
    for a, b in zip(loops, loops[1:]):
        for j in range(sides):
            k = (j + 1) % sides
            bm.faces.new((a[j], a[k], b[k], b[j]))
    bm.faces.new(list(reversed(loops[0])))
    bm.faces.new(loops[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def open_shell(rings, steps: int = 8, thickness: float = 0.012) -> bmesh.types.BMesh:
    # Prenda abierta «a rodajas»: cada rodaja es (z, radio_x, radio_y, hueco_delante°, hueco_detrás°).
    # El hueco de delante es la abertura de la bata; el de detrás, la raja por donde sale el abdomen
    # (0 = cerrado). Se hace una lámina y se le da grosor.
    bm = bmesh.new()
    for sgn in (1.0, -1.0):
        grid = []
        for z, rx, ry, gf, gb in rings:
            row = []
            for j in range(steps + 1):
                th = math.radians(gf + (180.0 - gb - gf) * j / steps)
                row.append(bm.verts.new((sgn * rx * math.sin(th), -ry * math.cos(th), z)))
            grid.append(row)
        for r0, r1 in zip(grid, grid[1:]):
            for j in range(steps):
                bm.faces.new((r0[j], r0[j + 1], r1[j + 1], r1[j]))
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.0005)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bmesh.ops.solidify(bm, geom=list(bm.faces), thickness=thickness)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


# Abdomen: centro y radios. La raja de la bata se calcula a partir de él.
ABD_C = Vector((0.0, 0.37, 0.62))
ABD_R = (0.22, 0.26, 0.21)
ABD_PIVOT = Vector((0.0, 0.08, 0.62))   # donde se une a la cadera (pecíolo)
ABD_TILT = 16.0                          # caída del abdomen hacia atrás (°): postura natural

# Bata: perfil (z, radio_x, radio_y, hueco delante°). Larga hasta media pierna, acampanada y con los
# hombros caídos.
COAT_PROFILE = [(0.34, 0.25, 0.19, 40), (0.48, 0.235, 0.175, 38), (0.64, 0.21, 0.155, 35), (0.78, 0.195, 0.14, 32),
                (0.88, 0.19, 0.135, 31), (0.98, 0.19, 0.132, 36), (1.06, 0.178, 0.126, 44), (1.13, 0.145, 0.11, 54),
                (1.185, 0.095, 0.08, 66), (1.207, 0.066, 0.058, 78)]   # escote en V y ceñida al cuello

# La abertura baja RECTA (César): misma media anchura en metros a todas las alturas, salvo arriba, donde
# la bata se cierra ceñida al cuello.
COAT_OPEN = 0.085
COAT_PROFILE = [(z, rx, ry, g if z > 1.15 else math.degrees(math.asin(COAT_OPEN / rx))) for z, rx, ry, g in COAT_PROFILE]


def coat_dims(z: float):
    # Radios y hueco delantero de la bata a una altura (interpolados del perfil).
    for (z0, rx0, ry0, g0), (z1, rx1, ry1, g1) in zip(COAT_PROFILE, COAT_PROFILE[1:]):
        if z0 <= z <= z1:
            t = (z - z0) / (z1 - z0)
            return rx0 + (rx1 - rx0) * t, ry0 + (ry1 - ry0) * t, g0 + (g1 - g0) * t
    raise ValueError("altura fuera de la bata")


def abdomen_half_width(z: float) -> float:
    # Media anchura del abdomen (ya inclinado) donde atraviesa la espalda de la bata, a una altura.
    rx, ry, _ = coat_dims(z)
    inv = Matrix.Rotation(math.radians(ABD_TILT), 3, "X")

    def inside(x: float) -> bool:
        q = inv @ (Vector((x, ry, z)) - ABD_PIVOT) + ABD_PIVOT - ABD_C
        return (q.x / ABD_R[0]) ** 2 + (q.y / ABD_R[1]) ** 2 + (q.z / ABD_R[2]) ** 2 < 1.0

    if not inside(0.0):
        return 0.0
    lo, hi = 0.0, rx * 0.95
    for _ in range(16):
        mid = 0.5 * (lo + hi)
        if inside(mid):
            lo = mid
        else:
            hi = mid
    return lo


def coat_slit(z: float) -> float:
    # Hueco de detrás (°) a una altura: la raja nace justo donde el abdomen atraviesa la bata, sigue su
    # contorno hasta su parte más ancha y desde ahí cae recta a los lados (César). Algo más estrecha que
    # el abdomen, para que la tela lo toque y no se vea nada por debajo.
    rx, _, _ = coat_dims(z)
    half, zz = 0.0, z
    while zz <= COAT_PROFILE[-1][0]:
        half = max(half, abdomen_half_width(zz))
        zz += 0.01
    return math.degrees(math.asin(min(0.95, half * 0.76 / rx))) if half > 0.0 else 0.0


def coat_rings():
    top = COAT_PROFILE[-1][0]
    while top > COAT_PROFILE[0][0] and abdomen_half_width(top) <= 0.0:
        top -= 0.002
    zs = sorted(set([p[0] for p in COAT_PROFILE] + [top - 0.18, top - 0.13, top - 0.09, top - 0.055, top - 0.025,
                                                    top - 0.008, top + 0.004]))
    return [(z,) + coat_dims(z) + (coat_slit(z),) for z in zs]


def coat_point(z: float, angle_deg: float):
    # Punto de la bata (y su normal) a una altura y un ángulo desde el frente (+ = su izquierda).
    rx, ry, _ = coat_dims(z)
    th = math.radians(angle_deg)
    p = Vector((rx * math.sin(th), -ry * math.cos(th), z))
    n = Vector((p.x / rx ** 2, p.y / ry ** 2, 0.0)).normalized()
    return p, n


def build_body(root, mats):
    # Tronco bajo y rechoncho, como la referencia: camisa y pelvis de quitina bajo una bata larga y
    # ABIERTA, con una raja detrás para el abdomen; cuello, emblema, remiendo, bajo manchado y mascarilla.
    base, gloss = mats["base"], mats["gloss"]
    hips = empty("hips", (0.0, 0.0, 0.54), root)
    chest = empty("chest", (0.0, 0.0, 0.86), hips)
    neck = empty("neck", (0.0, 0.0, 1.17), chest)

    finish("neck_skin", bar((0, 0, 1.14), (0, 0, 1.27), 0.046, 0.042, 8), SKIN_DARK, neck, gloss, smooth=True)
    # Tórax de quitina (sin nada debajo de la bata, César): cintura fina, pecho ancho y un surco.
    finish("thorax", loft([(0.6, 0.1, 0.085), (0.72, 0.115, 0.092), (0.88, 0.145, 0.106), (1.02, 0.15, 0.108),
                           (1.11, 0.122, 0.095), (1.17, 0.07, 0.06)], 14), SKIN, chest, gloss, smooth=True)
    groove = [(0.127 * math.cos(a), 0.098 * math.sin(a), 0.79) for a in (2.0 * math.pi * i / 14 for i in range(14))]
    finish("thorax_groove", tube(groove, 0.006, [(x, y, 0.0) for x, y, _ in groove], 4, closed=True), SKIN_DARK,
           chest, gloss, smooth=True)
    finish("pelvis", sphere((0.0, 0.0, 0.565), (0.15, 0.112, 0.09), 12, 8), SKIN, hips, gloss, smooth=True)
    rings = coat_rings()
    finish("coat", open_shell(rings), COAT, chest, base)
    # Cuello y solapas en UNA sola pieza, como un chaleco (César): la bata se abre en V y lo que se ve es
    # la tela doblada hacia fuera. La solapa nace en punta a media altura, se ensancha siguiendo la V
    # hasta el hombro y continúa como cuello plano, tumbado sobre los hombros, rodeando la nuca.
    top = COAT_PROFILE[-1][0]

    def cloth(z, a):
        q, qn = coat_point(z, a)
        return q + qn * 0.009

    collar = bmesh.new()

    # Solapas y cuello en una sola pieza, según el retoque a mano de César: la solapa de abajo nace en
    # punta y se ensancha hasta un pico; ahí mismo, tras una muesca en el borde de fuera, sigue la de
    # arriba con su propio pico, que se estrecha hacia el hombro y da la vuelta a la nuca como un cuello
    # estrecho. El borde de dentro sigue siempre el borde de la bata.
    z_join = 1.15
    ring_step = (360.0 - 2.0 * (coat_dims(z_join)[2] + 0.4)) / 22
    LAPEL_ROWS = ((0.72, 0.004), (0.79, 0.024), (0.86, 0.044), (0.93, 0.062), (0.985, 0.076), (1.0, 0.046),
                  (1.03, 0.07), (1.08, 0.054), (1.12, 0.042), (z_join, None))
    for sgn in (1.0, -1.0):
        grid = []
        for z, w in LAPEL_ROWS:
            rx_z, _, g = coat_dims(z)
            wd = ring_step if w is None else math.degrees(w / rx_z)   # arriba casa con el cuello
            grid.append([collar.verts.new(cloth(z, sgn * (g + 0.4 + wd * j / 3))) for j in range(4)])
        for r0, r1 in zip(grid, grid[1:]):
            for j in range(3):
                collar.faces.new((r0[j], r0[j + 1], r1[j + 1], r1[j]))
    # Cuello: la misma tira sigue alrededor de la nuca. Su borde de abajo arranca donde acaba la solapa
    # y sube poco a poco hasta dejar un cuello de 3 cm por detrás, sin escalón (César).
    z_back = top - 0.03
    grid = [[], [], []]
    for j in range(23):
        k = min(j, 22 - j)                                   # columnas desde el frente
        f = max(0.0, min(1.0, (k - 1) / 4.0))
        z_low = z_join + (z_back - z_join) * (f * f * (3.0 - 2.0 * f))
        for r, t in enumerate((0.0, 0.5, 1.0)):
            z = z_low + (top - z_low) * t
            g = coat_dims(z)[2] + 0.4
            grid[r].append(collar.verts.new(cloth(z, g + (360.0 - 2.0 * g) * j / 22)))
    for r0, r1 in zip(grid, grid[1:]):
        for j in range(22):
            collar.faces.new((r0[j], r0[j + 1], r1[j + 1], r1[j]))
    bmesh.ops.remove_doubles(collar, verts=collar.verts, dist=0.001)
    bmesh.ops.recalc_face_normals(collar, faces=collar.faces)
    bmesh.ops.solidify(collar, geom=list(collar.faces), thickness=0.009)
    bmesh.ops.recalc_face_normals(collar, faces=collar.faces)
    finish("coat_collar", collar, LAPEL, chest, base)
    z0, rx, ry, gf, gb = rings[0]
    hem = [(z0, rx + 0.006, ry + 0.006, gf, gb + 1.0), (z0 + 0.04,) + tuple(v + 0.0055 for v in coat_dims(z0 + 0.04)[:2])
           + (gf, coat_slit(z0 + 0.04) + 1.0)]
    finish("coat_hem", open_shell(hem, thickness=0.014), DUST, hips, base)
    # Remiendo grande en el faldón (su derecha): un trozo de tela que sigue la curva de la bata, cosido
    # con puntadas. Es parte de la ropa, no una pieza encima.
    pw, ph, pz, pa = 0.115, 0.105, 0.52, -60.0
    prx = coat_dims(pz)[0]
    ct, st_ = math.cos(math.radians(8)), math.sin(math.radians(8))

    def cloth(u, v, off):
        q, qn = coat_point(pz + u * st_ + v * ct, pa + math.degrees((u * ct - v * st_) / prx))
        return q + qn * off

    patch = bmesh.new()
    grid = [[patch.verts.new(cloth(-pw / 2 + pw * i / 4, -ph / 2 + ph * j / 2, 0.0035)) for i in range(5)]
            for j in range(3)]
    for j in range(2):
        for i in range(4):
            patch.faces.new((grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i]))
    bmesh.ops.recalc_face_normals(patch, faces=patch.faces)
    bmesh.ops.solidify(patch, geom=list(patch.faces), thickness=0.003)
    bmesh.ops.recalc_face_normals(patch, faces=patch.faces)
    finish("coat_patch", patch, COAT_PATCH, hips, base)
    stitches = []
    for i in range(4):
        t = -0.5 + (i + 0.5) / 4
        for (u0, v0), (u1, v1) in ((((t * pw), ph / 2 - 0.01), ((t * pw), ph / 2 + 0.011)),
                                   (((t * pw), -ph / 2 + 0.01), ((t * pw), -ph / 2 - 0.011)),
                                   ((pw / 2 - 0.01, t * ph), (pw / 2 + 0.011, t * ph)),
                                   ((-pw / 2 + 0.01, t * ph), (-pw / 2 - 0.011, t * ph))):
            stitches.append(bar(cloth(u0, v0, 0.005), cloth(u1, v1, 0.0035), 0.0028, 0.0028, 4))
    finish("coat_patch_stitches", merge(*stitches), STITCH, hips, base)
    # Botones hexagonales de cobre en el borde de la bata (su derecha).
    for i, z in enumerate((0.44, 0.53, 0.62, 0.71)):
        bp, bn = coat_point(z, -(coat_dims(z)[2] + 7.0))
        button = disc(0.015, 0.007)
        orient(button, bp + bn * 0.006, bn)
        finish("coat_button_%d" % i, button, COPPER, chest, gloss)
    tools = os.path.dirname(os.path.abspath(__file__))
    if tools not in sys.path:
        sys.path.append(tools)
    sys.dont_write_bytecode = True
    import crest
    # Emblema bordado, pequeño y a ras de la tela.
    p, n = coat_point(0.86, 62)
    crest.add_crest(finish, chest, base, location=p + n * 0.0015, facing=n, scale=0.25, style="painted",
                    prefix="coat_crest")
    build_mask(neck, mats)
    rescale(bpy.data.objects["mask"], 1.3, (0.0, -0.1, 1.1), (0.0, -0.004, -0.03))
    # Goma del respirador: una sola correa que sale de un lado de la copa, sube por el hombro, rodea la
    # nuca por encima del cuello de la bata y baja al otro lado. De ella cuelga el respirador.
    half = [(0.062, -0.128, 1.092), (0.098, -0.07, 1.185), (0.08, -0.015, 1.226), (0.064, 0.04, 1.228),
            (0.032, 0.066, 1.228)]
    pts = [Vector(p) for p in half] + [Vector((0.0, 0.073, 1.228))] + [Vector((-x, y, z)) for x, y, z in reversed(half)]
    finish("mask_strap", tube(pts, 0.0075, [(0.0, 0.0, 1.0)] * len(pts), 4), STRAP, bpy.data.objects["mask"], base,
           smooth=True)


def build_mask(neck, mats):
    # Respirador antipolvo del Nexo, colgando sobre el pecho de sus correas (un hueso lo subirá a la cara):
    # copa hexagonal que cubre el morro, dos filtros redondos con aro de cobre y rejilla, y una válvula.
    base, gloss = mats["base"], mats["gloss"]
    mask = empty("mask", (0.0, 0.0, 1.25), neck)
    c = Vector((0.0, -0.128, 1.07))
    face = Vector((0.0, -1.0, 0.35)).normalized()
    cup = disc(0.068, 0.05, 6, math.radians(0), r_front=0.04)
    x_axis, up = orient(cup, c, face)
    finish("mask_cup", cup, METAL_LIGHT, mask, base, bevel=0.004)
    rim = ring(0.072, 0.058, 0.012, 6, math.radians(0))
    orient(rim, c + face * 0.002, face)
    finish("mask_rim", rim, STRAP, mask, base)
    valve = disc(0.014, 0.012, 6)
    orient(valve, c + face * 0.05, face)
    finish("mask_valve", valve, METAL_DARK, mask, base)
    for side, sx in (("l", 1.0), ("r", -1.0)):
        fdir = (face + x_axis * (sx * 1.1) - up * 0.25).normalized()
        fc = c + face * 0.022 + x_axis * (sx * 0.05) - up * 0.012
        can = disc(0.03, 0.032, 10)
        orient(can, fc, fdir)
        finish("mask_filter_" + side, can, METAL, mask, base, bevel=0.003)
        cap = ring(0.031, 0.022, 0.006, 10)
        orient(cap, fc + fdir * 0.032, fdir)
        finish("mask_filter_ring_" + side, cap, COPPER, mask, gloss)
        grille = disc(0.022, 0.003, 6)
        orient(grille, fc + fdir * 0.033, fdir)
        finish("mask_filter_grille_" + side, grille, METAL_DARK, mask, base)


def limb(points, radii, ref=(0.0, -1.0, 0.0), sides: int = 10) -> bmesh.types.BMesh:
    # Miembro orgánico: tubo redondo que sigue una curva, con los dos extremos redondeados. Las piezas
    # vecinas (muslo y espinilla) se solapan en la articulación sin bola ni borde a la vista.
    pts = [Vector(p) for p in points]
    radii = list(radii)
    t0 = (pts[0] - pts[1]).normalized()
    t1 = (pts[-1] - pts[-2]).normalized()
    r0, r1 = radii[0], radii[-1]
    pts = [pts[0] + t0 * r0 * 0.85, pts[0] + t0 * r0 * 0.5] + pts + [pts[-1] + t1 * r1 * 0.5, pts[-1] + t1 * r1 * 0.85]
    radii = [r0 * 0.45, r0 * 0.85] + radii + [r1 * 0.85, r1 * 0.45]
    return tube(pts, radii, [ref] * len(pts), sides)


def build_arms(root, mats):
    # Brazos en reposo: hombro caído (la manga nace dentro del torso y baja en curva), manga remangada y
    # ceñida hasta el codo, antebrazo redondo y algo curvado de quitina y mano con tres dedos y pulgar.
    base, gloss = mats["base"], mats["gloss"]
    chest = bpy.data.objects.get("chest") or root
    for side, sx in (("l", 1.0), ("r", -1.0)):
        sh = Vector((sx * 0.16, 0.0, 1.085))
        el = Vector((sx * 0.25, 0.0, 0.843))
        wr = Vector((sx * 0.266, -0.065, 0.6))
        upper = empty("upper_arm_" + side, sh, chest)
        fore = empty("forearm_" + side, el, upper)
        hand = empty("hand_" + side, wr, fore)
        # El brazo está entero bajo la manga, para poder cambiarle la ropa más adelante.
        finish("upper_arm_skin_" + side, limb([sh, el], [0.034, 0.028]), SKIN_DARK, upper, gloss, smooth=True)
        path = [(sx * 0.085, 0.0, 1.105), (sx * 0.14, 0.0, 1.095), (sx * 0.19, 0.0, 1.04), (sx * 0.22, 0.0, 0.96),
                (sx * 0.24, 0.0, 0.89), (sx * 0.249, -0.002, 0.842)]
        radii = [0.045, 0.054, 0.054, 0.048, 0.045, 0.043]
        finish("sleeve_" + side, tube(path, radii, [(0, -1, 0)] * len(path), 10), COAT, upper, base, smooth=True)
        finish("sleeve_cuff_" + side, tube([(sx * 0.245, -0.001, 0.866), (sx * 0.25, -0.003, 0.832)], 0.047,
                                             [(0, -1, 0)] * 2, 10), COAT_SHADE, upper, base)
        # Antebrazo recto (el único pliegue del brazo es el codo), algo más grueso en el centro.
        finish("forearm_skin_" + side, limb([el, el.lerp(wr, 0.4), wr], [0.027, 0.029, 0.021]), SKIN_DARK, fore, gloss, smooth=True)
        # Mano: palma plana mirando al cuerpo, tres dedos gruesos hacia abajo y pulgar hacia delante.
        d = (wr - el).normalized()
        inward = Vector((-sx, 0.0, 0.0))
        fwd = Vector((0.0, -1.0, 0.0))
        palm = wr + d * 0.04
        gloved = side == "r"   # guante gris oscuro sin dedos en su mano derecha (César)
        if gloved:
            finish("glove_palm", sphere(palm, (0.028, 0.049, 0.054), 10, 6), GLOVE, hand, mats["base"], smooth=True)
            finish("glove_cuff", bar(wr - d * 0.022, wr + d * 0.012, 0.031, 0.033, 8), GLOVE, hand, mats["base"])
        else:
            finish("hand_palm_" + side, sphere(palm, (0.024, 0.044, 0.05), 10, 6), SKIN, hand, gloss, smooth=True)
        for k, off in enumerate((-0.027, 0.0, 0.027)):
            f0 = palm + d * 0.01 + fwd * off
            fl = 0.84 if k == 2 else 1.0   # el índice (junto al pulgar), algo más corto
            f1 = f0 + (d + inward * 0.2).normalized() * 0.062 * fl
            f2 = f1 + (d + inward * 0.75).normalized() * 0.032 * fl
            finish("hand_finger_%s_%d" % (side, k), tube([f0, f1, f2], [0.0125, 0.012, 0.0095], [inward] * 3, 6),
                   SKIN_DARK, hand, gloss)
            if gloved:   # el guante cubre el arranque de cada dedo
                fd = (f1 - f0).normalized()
                finish("glove_finger_%d" % k, bar(f0 - fd * 0.004, f0 + fd * 0.047, 0.0158, 0.0148, 6), GLOVE, hand,
                       mats["base"])
            finish("hand_fingertip_%s_%d" % (side, k), sphere(f2, (0.0098, 0.0098, 0.0098), 6, 4), SKIN_DARK, hand,
                   gloss, smooth=True)
        t0 = palm + fwd * 0.02 - d * 0.032   # nace cerca de la muñeca
        tm = t0 + (fwd + d * 0.35 + inward * 0.2).normalized() * 0.037
        t1 = tm + (fwd * 0.3 + d + inward * 0.6).normalized() * 0.03   # la punta se curva hacia los dedos
        finish("hand_thumb_" + side, tube([t0, tm, t1], [0.0165, 0.0155, 0.013], [inward] * 3, 6), SKIN_DARK, hand,
               gloss, smooth=True)
        if gloved:
            td = (tm - t0).normalized()
            # La funda nace dentro de la palma del guante y una bola tapa la base: sin huecos (César).
            finish("glove_thumb", merge(bar(t0 - td * 0.006, t0 + td * 0.03, 0.02, 0.0185, 6),
                                        sphere(t0, (0.021, 0.021, 0.021), 8, 5)), GLOVE, hand, mats["base"], smooth=True)
        finish("hand_thumbtip_" + side, sphere(t1, (0.0134, 0.0134, 0.0134), 6, 4), SKIN_DARK, hand, gloss, smooth=True)
        rescale(hand, HAND_SCALE, wr, (0.0, 0.0, 0.0))   # manos grandes respecto al brazo (César)


def build_legs(root, mats):
    # Muslo y espinilla son rectos: la pierna solo se dobla en la rodilla (César).
    # Piernas de hormiga, como la referencia: finas, redondas, abiertas y arqueadas (la rodilla hacia
    # fuera), sin bola en la rodilla; descalza, con los pies largos apuntando un poco hacia fuera.
    gloss = mats["gloss"]
    hips = bpy.data.objects.get("hips") or root
    for side, sx in (("l", 1.0), ("r", -1.0)):
        hip = Vector((sx * 0.095, 0.0, 0.54))
        knee = Vector((sx * 0.18, -0.025, 0.3))   # a media altura entre cadera y tobillo
        ankle = Vector((sx * 0.158, 0.012, 0.062))
        thigh = empty("thigh_" + side, hip, hips)
        shin = empty("shin_" + side, knee, thigh)
        foot = empty("foot_" + side, ankle, shin)
        # La rodilla se rellena con una esfera del mismo grosor que muslo y espinilla: no se ve como bola,
        # solo tapa la muesca del pliegue.
        finish("thigh_skin_" + side, merge(limb([hip, hip.lerp(knee, 0.5), knee], [0.041, 0.036, 0.03]),
                                           sphere(knee, (0.0305, 0.0305, 0.0305), 10, 6)),
               SKIN_DARK, thigh, gloss, smooth=True)
        finish("shin_skin_" + side, limb([knee, knee.lerp(ankle, 0.4), ankle],
                                          [0.03, 0.03, 0.021]), SKIN_DARK, shin, gloss, smooth=True)
        # Pie sin dedos pero con forma: talón, puente más estrecho, planta ancha y punta; planta plana.
        sole = limb([(0.0, 0.03, 0.03), (0.0, -0.025, 0.027), (0.0, -0.085, 0.03), (0.0, -0.13, 0.022)],
                    [0.031, 0.025, 0.04, 0.024], ref=(0.0, 0.0, 1.0), sides=10)
        for v in sole.verts:
            v.co.z = max(v.co.z * 0.85, 0.0)
        bmesh.ops.scale(sole, vec=(FOOT_SCALE, FOOT_SCALE, FOOT_SCALE * 0.9), verts=sole.verts)   # pies grandes
        bmesh.ops.rotate(sole, verts=sole.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(sx * math.radians(22), 3, "Z"))
        bmesh.ops.translate(sole, vec=(ankle.x, ankle.y, 0.0), verts=sole.verts)
        finish("foot_skin_" + side, sole, SKIN, foot, gloss, smooth=True)


def build_abdomen(root, mats):
    # Abdomen grande y centrado detrás de la cadera, con una caída hacia atrás (ABD_TILT); sale por la
    # raja de la bata. Pecíolo y dos surcos.
    gloss = mats["gloss"]
    hips = bpy.data.objects.get("hips") or root
    c = ABD_C
    rx, ry, rz = ABD_R
    rot = Matrix.Rotation(-math.radians(ABD_TILT), 3, "X")
    pivot = empty("abdomen", ABD_PIVOT, hips)

    def tilted(bm):
        bmesh.ops.rotate(bm, verts=bm.verts, cent=ABD_PIVOT, matrix=rot)
        return bm

    finish("abdomen_petiole", tilted(bar((0.0, 0.04, 0.6), (0.0, 0.17, 0.62), 0.05, 0.07, 8)), SKIN_DARK, pivot,
           gloss, smooth=True)
    finish("abdomen_gaster", tilted(sphere(c, (rx, ry, rz), 16, 10)), SKIN, pivot, gloss, smooth=True)
    for k, yk in enumerate((0.05, 0.45)):
        f = math.sqrt(1.0 - yk * yk)
        pts = [c + Vector((rx * f * math.cos(a), ry * yk, rz * f * math.sin(a)))
               for a in (2.0 * math.pi * i / 16 for i in range(16))]
        nrm = [(p - c - Vector((0, ry * yk, 0))).normalized() for p in pts]
        finish("abdomen_ring_%d" % k, tilted(tube(pts, 0.007, nrm, 4, closed=True)), SKIN_DARK, pivot, gloss,
               smooth=True)


def build_backpack(root, mats):
    # Mochila de panal (D-099): armazón hexagonal grande en la espalda, por encima del abdomen, con un
    # panal de 7 celdas: el emblema de la colonia en el centro, 2 módulos puestos (el inventario inicial)
    # y 4 huecos vacíos; cada ampliación añadirá un módulo visible (`backpack_module_<n>`). Luz de estado
    # ámbar, dos antenitas y dos asas que van POR ENCIMA de la ropa, ceñidas a la bata y a las solapas.
    base, gloss, glow = mats["base"], mats["gloss"], mats["glow"]
    chest = bpy.data.objects.get("chest") or root
    c = Vector((0.0, 0.135, 1.0))
    back = Vector((0.0, 1.0, 0.0))
    depth, R, r = 0.1, 0.158, 0.046
    pack = empty("backpack", c, chest)
    frame = disc(R, depth, 6, 0.0, r_front=R - 0.016)
    orient(frame, c, back)
    finish("backpack_frame", frame, METAL, pack, base, bevel=0.006)
    face = c + back * depth
    step = math.sqrt(3.0) * r + 0.004
    for k in range(6):
        a = math.radians(60 * k)
        p = face + Vector((-step * math.cos(a), 0.0, step * math.sin(a)))
        if k in (1, 2):   # las dos celdas de arriba: módulos puestos
            module = disc(r, 0.03, 6, r_front=r - 0.007)
            orient(module, p, back)
            finish("backpack_module_%d" % (k - 1), module, METAL_LIGHT, pack, base)
            window = disc(r - 0.019, 0.005, 6)
            orient(window, p + back * 0.03, back)
            finish("backpack_module_window_%d" % (k - 1), window, LENS, pack, gloss)
        else:              # huecos vacíos: fondo oscuro
            slot = disc(r - 0.004, 0.003, 6)
            orient(slot, p, back)
            finish("backpack_slot_%d" % k, slot, METAL_DARK, pack, base)
    tools = os.path.dirname(os.path.abspath(__file__))
    if tools not in sys.path:
        sys.path.append(tools)
    sys.dont_write_bytecode = True
    import crest
    crest.add_crest(finish, pack, base, location=face + back * 0.001, facing=back, scale=0.33, style="painted",
                    prefix="backpack_crest")
    light = disc(0.012, 0.008, 6)
    orient(light, face + Vector((0.0, 0.0, 0.113)), back)
    finish("backpack_light", light, AMBER, pack, glow)
    for side, sx in (("l", 1.0), ("r", -1.0)):
        # Antenita en la esquina de arriba del armazón, con la punta ámbar.
        a0 = c + Vector((sx * R * 0.5, depth * 0.55, R * 0.866 - 0.01))
        a1 = a0 + Vector((sx * 0.035, 0.02, 0.1))
        finish("backpack_antenna_" + side, bar(a0, a1, 0.008, 0.006, 5), METAL_DARK, pack, base)
        finish("backpack_antenna_tip_" + side, ball(a1, 0.012, 1), AMBER, pack, glow)
        # Asa: sale de lo alto de la mochila, pasa sobre el cuello de la bata y el hombro, baja por el pecho
        # encima de la solapa y vuelve por debajo del brazo. Sigue la superficie de la bata, levantada lo
        # justo para ir por encima de las solapas (que sobresalen 1,8 cm).
        lift = 0.026
        pts, nrm = [Vector((sx * 0.085, c.y + 0.02, 1.1))], [Vector((0.0, 0.3, 1.0)).normalized()]
        # Bajo el brazo el asa se hunde entre la bata del torso y la manga (hundimiento en metros), para
        # no atravesar el brazo (César).
        for z, th, sink in ((1.17, 150.0, 0.0), (1.19, 115.0, 0.0), (1.19, 85.0, 0.0), (1.165, 66.0, 0.0),
                            (1.13, 55.0, 0.0), (1.08, 49.0, 0.0), (1.03, 47.0, 0.0), (0.985, 50.0, 0.0),
                            (0.955, 58.0, 0.006), (0.94, 68.0, 0.026), (0.935, 90.0, 0.05), (0.94, 112.0, 0.026),
                            (0.94, 126.0, 0.0)):
            q, qn = coat_point(z, sx * th)
            pts.append(q + qn * (lift - sink))
            nrm.append(qn)
        pts.append(Vector((sx * 0.125, c.y + 0.02, 0.94)))
        nrm.append(Vector((sx, 0.3, 0.0)).normalized())
        finish("backpack_strap_" + side, tube(pts, 0.011, nrm, 4), METAL_DARK, pack, base)


def rescale(part, factor: float, pivot, shift) -> None:
    # Agranda una parte ya construida (mallas y vacíos que cuelgan de `part`) alrededor de `pivot` y la
    # desplaza `shift`. Las piezas se modelan en coordenadas del mundo, así que basta con mover los datos.
    m = Matrix.Translation(Vector(pivot) + Vector(shift)) @ Matrix.Scale(factor, 4) @ Matrix.Translation(-Vector(pivot))
    objs = [part] + list(part.children_recursive)
    for o in objs:
        if o.type == "MESH":
            o.data.transform(m)
        else:
            o.location = m @ Vector(o.location)
    for o in objs:
        if o.parent is not None:
            attach(o, o.parent)


# ---------------------------------------------------------------- montaje

def clear_previous():
    root = bpy.data.objects.get("mira")
    if root is None:
        return
    for obj in [root] + list(root.children_recursive):
        mesh = obj.data if obj.type == "MESH" else None
        bpy.data.objects.remove(obj, do_unlink=True)
        if mesh is not None and mesh.users == 0:
            bpy.data.meshes.remove(mesh)


def build():
    clear_previous()
    mats = get_materials()
    root = empty("mira", (0.0, 0.0, 0.0))
    root.empty_display_size = 0.3
    if "body" in PARTS:
        build_body(root, mats)
    if "arms" in PARTS:
        build_arms(root, mats)
    if "legs" in PARTS:
        build_legs(root, mats)
    if "abdomen" in PARTS:
        build_abdomen(root, mats)
    if "backpack" in PARTS:
        build_backpack(root, mats)
    if "head" in PARTS:
        build_head(root, mats)
        rescale(bpy.data.objects["head"], HEAD_SCALE, (0.0, 0.0, 1.40), (0.0, 0.0, -HEAD_DROP))
    dress_cloth(root, mats)
    tris = sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in root.children_recursive if o.type == "MESH")
    print("Mira: %d triángulos" % tris)


if __name__ == "__main__":
    build()
