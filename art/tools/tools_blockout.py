# Herramientas de Mira (C3, D-115): hacha de mandíbula y pico de soldado, de madera y piedra.
# Prehistóricas (no llevan metal) pero con el diseño de hormiga de Mira: la cabeza del hacha es una
# mandíbula tallada en piedra y la del pico, la cabeza de una hormiga soldado con sus mandíbulas en punta.
# Mismo estilo que los ítems (paleta compartida, biseles pequeños, sombreado suave a 30°).
#
# Convenciones: origen en el punto donde las coge la mano (el centro del puño), mango a lo largo de +Z y
# cabeza arriba; la hoja o la punta miran a +X. Mango de 2 cm de grosor: cabe en el hueco del puño de Mira
# (D-146). Cada herramienta cuelga de un vacío raíz «tool_<id>».
# De momento hay varias versiones de cada una para elegir (axe_c y pick_c, tras la primera ronda con
# César); en la escena van en fila.
#
# Uso: con art/props/tools.blend abierto, Editor de texto → abrir → Alt+P. Borra y rehace todas.
# Dónde tocar: las listas de puntos de cada hoja y punta (x hacia delante, z hacia arriba) y TOOLS.

import bpy
import bmesh
import math
from mathutils import Matrix, Vector

PALETTE = 64
SWATCH = 8
TEXTURE = "//../../assets/textures/palette.png"
SURFACE = "//../../assets/textures/palette_surface.png"
SPACING = 0.45

BARK, BARK_DARK = (0, 5), (0, 6)
WOOD, WOOD_LIGHT = (0, 3), (0, 1)
FIBER = (2, 5)            # cordel de fibra vegetal, verde oscuro
STONE, STONE_LIGHT, STONE_DARK = (1, 5), (1, 3), (1, 6)
EYE = (5, 7)
METAL, METAL_LIGHT, METAL_DARK, RUBBER = (5, 3), (5, 2), (5, 5), (5, 6)
COPPER, COPPER_LIGHT = (3, 2), (3, 1)
AMBER = (6, 2)
CELL, CELL_LIGHT = (7, 3), (7, 2)

HANDLE_R = 0.010          # radio del mango (2 cm de grosor)
HANDLE_BOTTOM = -0.08
# Las cabezas se dibujan con sus medidas de partida y se agrandan ×HEAD_SCALE alrededor de HEAD_FROM, que
# baja a HEAD_TO: así se cambia el tamaño de la cabeza y el largo del mango sin rehacer los contornos.
HEAD_SCALE = 1.3
HEAD_FROM, HEAD_TO = 0.41, 0.33
HEAD = Matrix.Translation((0, 0, HEAD_TO)) @ Matrix.Scale(HEAD_SCALE, 4) @ Matrix.Translation((0, 0, -HEAD_FROM))

TOOLS = ["biter", "hand_drill"]
EXPORT = True   # al terminar, exporta los .glb (export())
DEVICE_SCALE = 1.35     # tamaño del aparato respecto al primer boceto (la empuñadura no cambia)
DEVICE_BASE = 0.06      # altura de lo alto de la empuñadura, desde donde se agranda
GRIP_PARTS = ("grip", "grip_pommel", "trigger")


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


def get_emissive(mat):
    # Luces de estado (ámbar) y cristales que se encienden: la misma paleta, con su color como emisión.
    glow = bpy.data.materials.get("palette_emissive") or bpy.data.materials.new("palette_emissive")
    glow.use_nodes = True
    nt = glow.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial"); out.location = (300, 0)
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled"); bsdf.location = (0, 0)
    tex = nt.nodes.new("ShaderNodeTexImage"); tex.location = (-450, 0)
    tex.image = mat.node_tree.nodes["Image Texture"].image if "Image Texture" in mat.node_tree.nodes else None
    tex.interpolation = "Closest"
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Emission Color"])
    bsdf.inputs["Emission Strength"].default_value = 2.0
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    return glow


def finish(name, bm, color, parent, material, bevel: float = 0.0):
    if bevel > 0.0:
        bmesh.ops.bevel(bm, geom=list(bm.edges), offset=bevel, segments=1, affect="EDGES", profile=0.5, clamp_overlap=True)
    bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 4])
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


def slab(points, thickness, edge=None):
    # Pieza plana a partir de un contorno en el plano XZ (x hacia delante, z arriba), con su grosor en Y.
    # `edge` = (x, grosor): a partir de esa x hacia delante, la pieza se afila hasta ese grosor (el filo).
    bm = bmesh.new()
    half = thickness / 2.0
    front = [bm.verts.new((x, -half, z)) for x, z in points]
    back = [bm.verts.new((x, half, z)) for x, z in points]
    bm.faces.new(front)
    bm.faces.new(list(reversed(back)))
    n = len(points)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((front[i], back[i], back[j], front[j]))
    if edge is not None:
        x0, thin = edge
        xmax = max(x for x, _ in points)
        for v in bm.verts:
            if v.co.x > x0:
                t = min(1.0, (v.co.x - x0) / max(1e-6, xmax - x0))
                v.co.y *= 1.0 - t * (1.0 - thin / thickness)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def ellipsoid(center, radii, segments=8, rings=5):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segments, v_segments=rings, radius=1.0)
    bmesh.ops.scale(bm, vec=radii, verts=bm.verts)
    bmesh.ops.translate(bm, vec=Vector(center), verts=bm.verts)
    return bm


def place(bm, location=(0, 0, 0), rotation=None):
    m = Matrix.Translation(Vector(location))
    if rotation is not None:
        m = m @ rotation
    bmesh.ops.transform(bm, matrix=m, verts=bm.verts)
    return bm


# --- Piezas comunes ---

def head_z(z):
    # Altura de un punto de la cabeza ya agrandada.
    return HEAD_TO + (z - HEAD_FROM) * HEAD_SCALE


def hfinish(name, bm, color, root, mat, bevel=0.0):
    # Como finish, para las piezas de la cabeza: las agranda y las baja (HEAD) antes.
    return finish(name, place(bm, rotation=HEAD), color, root, mat, bevel)


def handle(root, mat, top):
    # Mango de madera de 8 lados, con la corteza quitada; pomo hexagonal abajo para que no resbale.
    # `top` en medidas de la cabeza (antes de agrandarla).
    finish("handle", prism(8, HANDLE_R, HANDLE_R * 0.9, HANDLE_BOTTOM, head_z(top), math.radians(22.5)), WOOD, root, mat, 0.002)
    finish("pommel", prism(6, HANDLE_R * 1.45, HANDLE_R * 1.3, HANDLE_BOTTOM - 0.022, HANDLE_BOTTOM + 0.004), BARK_DARK, root, mat, 0.003)


def lashing(root, mat, z0, z1, turns=3, radius=HANDLE_R * 1.35):
    # Vueltas de cordel alrededor del mango, bajo la cabeza (medidas de la cabeza).
    for k in range(turns):
        z = z0 + (z1 - z0) * (k + 0.5) / turns
        hfinish("lashing_%d" % k, prism(8, radius / HEAD_SCALE, radius / HEAD_SCALE, z - 0.006, z + 0.006, math.radians(22.5)), FIBER, root, mat, 0.0015)


def bands(root, mat, z0, z1, blade_thickness, reach=0.03, turns=3):
    # Cordel que abraza a la vez el mango y la raíz de la hoja (medidas de la cabeza).
    for k in range(turns):
        z = z0 + (z1 - z0) * (k + 0.5) / turns
        size = (reach + 0.026, blade_thickness + 0.008, 0.011)
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=1.0)
        bmesh.ops.scale(bm, vec=size, verts=bm.verts)
        bmesh.ops.translate(bm, vec=(reach / 2 - 0.003, 0, z), verts=bm.verts)
        hfinish("band_%d" % k, bm, FIBER, root, mat, 0.002)


def hex_inlay(root, mat, name, center, radius=0.012, color=STONE_DARK):
    # Hexágono hundido en la piedra: la marca del taller de Mira (como los remaches de sus máquinas).
    disc = prism(6, radius, radius * 0.85, -0.002, 0.002, math.radians(30))
    hfinish(name, place(disc, center, Matrix.Rotation(math.radians(90), 4, "X")), color, root, mat)


# --- Hachas ---

def axe_a(root, mat):
    # Mandíbula en media luna: hoja ancha de piedra con tres dientes en el filo, atada al mango.
    handle(root, mat, top=0.47)
    blade = [(-0.012, 0.455), (0.05, 0.47), (0.10, 0.495), (0.135, 0.48), (0.142, 0.452), (0.128, 0.438),
             (0.146, 0.412), (0.132, 0.395), (0.143, 0.366), (0.122, 0.335), (0.085, 0.315), (0.05, 0.338),
             (-0.012, 0.352)]
    hfinish("blade", slab(blade, 0.026, edge=(0.09, 0.006)), STONE, root, mat, 0.003)
    hfinish("back", place(prism(6, 0.018, 0.014, 0.0, 0.035, math.radians(30)), (-0.012, 0, 0.403),
                         Matrix.Rotation(math.radians(-90), 4, "Y")), STONE_DARK, root, mat, 0.003)
    bands(root, mat, 0.36, 0.46, 0.026)
    hex_inlay(root, mat, "inlay", (0.055, -0.0135, 0.405))


def axe_b(root, mat):
    # Mandíbula en gancho, como la de una hormiga: larga, curvada hacia abajo, con dientes por dentro.
    handle(root, mat, top=0.475)
    blade = [(-0.012, 0.462), (0.05, 0.485), (0.11, 0.482), (0.158, 0.455), (0.188, 0.405), (0.196, 0.352),
             (0.172, 0.374), (0.162, 0.392), (0.148, 0.378), (0.135, 0.405), (0.118, 0.393), (0.1, 0.418),
             (0.06, 0.41), (-0.012, 0.38)]
    hfinish("blade", slab(blade, 0.024, edge=(0.11, 0.006)), STONE, root, mat, 0.003)
    bands(root, mat, 0.385, 0.465, 0.024, turns=2)
    lashing(root, mat, 0.35, 0.375, turns=2)
    hex_inlay(root, mat, "inlay", (0.045, -0.0125, 0.44), radius=0.011)


# --- Picos ---

def soldier_head(root, mat, center):
    # Cabeza de hormiga soldado: grande y algo cuadrada, de piedra, con dos ojillos oscuros.
    hfinish("head", ellipsoid(center, (0.046, 0.036, 0.04), 8, 5), STONE, root, mat)
    for side in (-1, 1):
        eye = ellipsoid(Vector(center) + Vector((0.03, side * 0.026, 0.013)), (0.0065, 0.0065, 0.0065), 6, 4)
        hfinish("eye_%d" % (side + 1), eye, EYE, root, mat)


def mandible(points, thickness, side, base, bulge, tip=0.003):
    # Mandíbula de pinza vista desde arriba: nace a `base` del centro, se abre `bulge` a media longitud y
    # se cierra hasta casi tocar la otra en la punta, dejando un hueco entre las dos (como una hormiga).
    bm = slab(points, thickness)
    x0 = min(x for x, _ in points)
    xmax = max(x for x, _ in points)
    for v in bm.verts:
        t = max(0.0, min(1.0, (v.co.x - x0) / (xmax - x0)))
        offset = base * (1.0 - t) + tip * t + bulge * math.sin(math.pi * t) * (1.0 - t * 0.5)
        v.co.y += side * (offset + thickness / 2.0)
    return bm


def pick_a(root, mat):
    # Cabeza de soldado sobre el mango, con sus dos mandíbulas juntas por delante como el pico y un
    # remate corto por detrás.
    handle(root, mat, top=0.43)
    head = (0.0, 0.0, 0.43)
    soldier_head(root, mat, head)
    jaw = [(0.025, 0.448), (0.075, 0.452), (0.12, 0.44), (0.155, 0.412), (0.165, 0.39), (0.14, 0.402),
           (0.105, 0.416), (0.065, 0.42), (0.025, 0.414)]
    for side in (-1, 1):
        hfinish("mandible_%d" % (side + 1), mandible(jaw, 0.016, side, 0.006, 0.014), STONE_LIGHT, root, mat, 0.002)
    back = place(prism(6, 0.016, 0.003, 0.0, 0.06, math.radians(30)), (-0.03, 0, 0.43),
                 Matrix.Rotation(math.radians(-90), 4, "Y"))
    hfinish("back_spike", back, STONE_DARK, root, mat, 0.002)
    lashing(root, mat, 0.36, 0.4, turns=2)


def pick_b(root, mat):
    # Pico de dos brazos curvados hacia abajo: por delante las dos mandíbulas en punta y por detrás un
    # cincel plano. En el centro, una cabeza de soldado pequeña atada al mango.
    handle(root, mat, top=0.45)
    head = (0.0, 0.0, 0.445)
    hfinish("head", ellipsoid(head, (0.03, 0.024, 0.03), 8, 5), STONE, root, mat)
    for side in (-1, 1):
        eye = ellipsoid((0.019, side * 0.017, 0.455), (0.005, 0.005, 0.005), 6, 4)
        hfinish("eye_%d" % (side + 1), eye, EYE, root, mat)
    jaw = [(0.015, 0.462), (0.07, 0.462), (0.12, 0.447), (0.16, 0.415), (0.172, 0.39), (0.148, 0.403),
           (0.11, 0.425), (0.06, 0.435), (0.015, 0.432)]
    for side in (-1, 1):
        hfinish("mandible_%d" % (side + 1), mandible(jaw, 0.014, side, 0.004, 0.012), STONE_LIGHT, root, mat, 0.002)
    chisel = [(-0.015, 0.462), (-0.08, 0.458), (-0.13, 0.435), (-0.16, 0.4), (-0.175, 0.402), (-0.14, 0.445),
              (-0.08, 0.432), (-0.015, 0.43)]
    hfinish("chisel", slab(list(reversed(chisel)), 0.024), STONE_DARK, root, mat, 0.003)
    lashing(root, mat, 0.37, 0.415, turns=2)


def rod(p0, p1, r0, r1, sides=6):
    # Barra de p0 a p1 (radio r0 al principio y r1 al final).
    p0, p1 = Vector(p0), Vector(p1)
    d = p1 - p0
    bm = prism(sides, r0, r1, 0.0, d.length, math.radians(30))
    rot = d.normalized().to_track_quat("Z", "Y").to_matrix().to_4x4()
    return place(bm, p0, rot)


def axe_c(root, mat):
    # Mezcla de A y B (César): silueta de hacha, con el filo casi recto y vertical, pero la punta de abajo
    # se curva hacia atrás en gancho como una mandíbula, con dos dientes justo encima.
    handle(root, mat, top=0.478)
    blade = [(-0.012, 0.472), (0.04, 0.48), (0.09, 0.482), (0.125, 0.474), (0.138, 0.462), (0.143, 0.435),
             (0.142, 0.405), (0.136, 0.38), (0.124, 0.372), (0.133, 0.357), (0.12, 0.35), (0.126, 0.333),
             (0.112, 0.305), (0.098, 0.33), (0.075, 0.362), (0.048, 0.385), (0.02, 0.398), (-0.012, 0.402)]
    hfinish("blade", slab(blade, 0.026, edge=(0.085, 0.006)), STONE, root, mat, 0.003)
    hfinish("poll", rod((-0.012, 0, 0.44), (-0.045, 0, 0.44), 0.016, 0.013), STONE_DARK, root, mat, 0.003)
    bands(root, mat, 0.41, 0.47, 0.026, turns=3)
    hex_inlay(root, mat, "inlay", (0.06, -0.0135, 0.435))


def pick_c(root, mat):
    # Pico de hormiga (César: el A, de lado, parecía un ave). Cabeza ancha y aplastada, con los ojos a los
    # lados y dos antenas acodadas encima, que es lo que más se lee como hormiga; las mandíbulas en pinza
    # se curvan hacia abajo como un pico de minero y tienen un diente por dentro. Detrás, una cara plana
    # para golpear en lugar del pincho.
    handle(root, mat, top=0.43)
    head = Vector((0.0, 0.0, 0.43))
    hfinish("head", ellipsoid(head, (0.05, 0.046, 0.036), 8, 5), STONE, root, mat)
    for side in (-1, 1):
        hfinish("eye_%d" % (side + 1), ellipsoid(head + Vector((0.016, side * 0.042, 0.01)), (0.008, 0.005, 0.007), 6, 4),
                EYE, root, mat)
        base = head + Vector((0.026, side * 0.018, 0.028))
        elbow = head + Vector((0.0, side * 0.034, 0.072))
        tip = head + Vector((0.05, side * 0.05, 0.086))
        hfinish("antenna_%d" % (side + 1), rod(base, elbow, 0.0065, 0.0055), STONE_DARK, root, mat)
        hfinish("antenna_tip_%d" % (side + 1), rod(elbow, tip, 0.0055, 0.0055), STONE_DARK, root, mat)
        hfinish("antenna_ball_%d" % (side + 1), ellipsoid(tip, (0.0085, 0.0085, 0.0085), 6, 4), STONE_DARK, root, mat)
    jaw = [(0.035, 0.452), (0.08, 0.452), (0.118, 0.436), (0.145, 0.405), (0.158, 0.37), (0.138, 0.385),
           (0.128, 0.397), (0.115, 0.398), (0.1, 0.413), (0.07, 0.42), (0.035, 0.416)]
    for side in (-1, 1):
        hfinish("mandible_%d" % (side + 1), mandible(jaw, 0.02, side, 0.008, 0.011), STONE_LIGHT, root, mat, 0.002)
    hfinish("hammer", rod((-0.035, 0, 0.43), (-0.072, 0, 0.43), 0.021, 0.019), STONE_DARK, root, mat, 0.003)
    lashing(root, mat, 0.36, 0.4, turns=2)


# --- Herramientas del Nexo (camino 2, César): versiones de mano de las máquinas de Mira ---
# Empuñadura de pistola: el origen es el centro del puño, la empuñadura sube por +Z y el aparato va encima
# de la mano, hacia delante (+X). Metal del Nexo, cobre y una célula hexagonal azul a la vista (la energía).

def box(size, center):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=size, verts=bm.verts)
    bmesh.ops.translate(bm, vec=Vector(center), verts=bm.verts)
    return bm


def flat(points, thickness, z):
    # Pieza plana a partir de un contorno visto desde arriba (x, y), con su grosor en Z.
    bm = slab([(x, y) for x, y in points], thickness)
    bmesh.ops.transform(bm, matrix=Matrix.Rotation(math.radians(90), 4, "X"), verts=bm.verts)
    bmesh.ops.translate(bm, vec=(0, 0, z), verts=bm.verts)
    return bm


def pistol_grip(root, mat):
    # Empuñadura hexagonal de goma con su pomo y el gatillo de cobre delante.
    finish("grip", prism(6, 0.011, 0.012, -0.055, 0.06), RUBBER, root, mat, 0.002)
    finish("grip_pommel", prism(6, 0.016, 0.014, -0.068, -0.052), METAL_DARK, root, mat, 0.002)
    finish("trigger", box((0.01, 0.008, 0.026), (0.019, 0, 0.032)), COPPER, root, mat, 0.002)


def cell(root, mat, start, end):
    # Célula hexagonal azul (la batería) con su tapa: lo que da energía al aparato.
    finish("cell", rod(start, end, 0.019, 0.019), CELL, root, mat, 0.002)
    tip = Vector(end) + (Vector(end) - Vector(start)).normalized() * 0.006
    finish("cell_cap", rod(end, tip, 0.014, 0.012), METAL_DARK, root, mat, 0.002)


def antennae(root, mat, base, spread, height, reach):
    # Dos antenitas acodadas con la punta ámbar (luces de estado): cortas y finas, para no tapar la vista.
    glow = get_emissive(mat)
    for side in (-1, 1):
        b = Vector(base) + Vector((0, side * spread, 0))
        elbow = b + Vector((-reach * 0.3, side * spread * 0.4, height))
        tip = elbow + Vector((reach, side * spread * 0.3, height * 0.25))
        finish("antenna_%d" % (side + 1), rod(b, elbow, 0.0028, 0.0024, 5), METAL_DARK, root, mat)
        finish("antenna_tip_%d" % (side + 1), rod(elbow, tip, 0.0024, 0.0022, 5), METAL_DARK, root, mat)
        finish("antenna_light_%d" % (side + 1), ellipsoid(tip, (0.0045, 0.0045, 0.0045), 6, 3), AMBER, root, glow)


def biter(root, mat):
    # Mordedora (en lugar del hacha): la cabeza del talador en pequeño. Cuerpo con caparazón y anillos de
    # cobre, cabeza con ojos de cristal y luz de estado, y dos mandíbulas dentadas que se cierran (vistas
    # desde arriba, como una pinza) sobre pernos de cobre.
    pistol_grip(root, mat)
    finish("body", box((0.12, 0.05, 0.05), (0.02, 0, 0.085)), METAL, root, mat, 0.006)
    finish("shell", ellipsoid((0.015, 0, 0.11), (0.062, 0.03, 0.02), 6, 4), METAL_DARK, root, mat)
    for k, x in enumerate((-0.015, 0.03)):
        finish("ring_%d" % k, box((0.008, 0.056, 0.058), (x, 0, 0.087)), COPPER, root, mat, 0.002)
    cell(root, mat, (-0.04, 0, 0.085), (-0.068, 0, 0.085))
    finish("head", ellipsoid((0.095, 0, 0.085), (0.032, 0.036, 0.03), 6, 4), METAL_DARK, root, mat)
    glow = get_emissive(mat)
    for side in (-1, 1):
        finish("eye_%d" % (side + 1), ellipsoid((0.112, side * 0.025, 0.097), (0.008, 0.008, 0.008), 6, 3), CELL_LIGHT, root, glow)
        finish("pin_%d" % (side + 1), rod((0.12, side * 0.021, 0.066), (0.12, side * 0.021, 0.1), 0.006, 0.006), COPPER, root, mat)
    antennae(root, mat, (0.098, 0, 0.11), 0.01, 0.018, 0.02)
    jaw = [(0.112, 0.016), (0.13, 0.033), (0.16, 0.042), (0.19, 0.036), (0.21, 0.02), (0.217, 0.005), (0.2, 0.01),
           (0.192, 0.017), (0.182, 0.01), (0.172, 0.018), (0.162, 0.011), (0.15, 0.019), (0.135, 0.013), (0.118, 0.012)]
    for side in (-1, 1):
        points = [(x, side * y) for x, y in jaw]
        if side < 0:
            points.reverse()
        bm = flat(points, 0.02, 0.083)
        for v in bm.verts:
            # Más finas y algo caídas hacia la punta, como una mandíbula de verdad.
            t = max(0.0, (v.co.x - 0.112) / 0.105)
            v.co.z = 0.083 + (v.co.z - 0.083) * (1.0 - 0.55 * t) - 0.008 * t * t
        pivot = bpy.data.objects.new("jaw_pivot_%s" % ("l" if side > 0 else "r"), None)
        pivot.empty_display_size = 0.02
        bpy.context.collection.objects.link(pivot)
        pivot.parent = root
        pivot.location = (0.12, side * 0.021, 0.083)
        jaw_obj = finish("jaw_%d" % (side + 1), bm, METAL_LIGHT, root, mat, 0.002)
        jaw_obj.parent = pivot
        jaw_obj.matrix_parent_inverse = Matrix.Translation(-pivot.location)


def hand_drill(root, mat):
    # Barrena de mano (en lugar del pico): el taladro del extractor en pequeño. Motor con bobinas de cobre a
    # la vista y aletas, célula detrás, portabrocas hexagonal de cobre y una broca en espiral.
    pistol_grip(root, mat)
    finish("motor", rod((-0.05, 0, 0.09), (0.07, 0, 0.09), 0.031, 0.029, 6), METAL, root, mat, 0.003)
    for k, x in enumerate((-0.025, -0.002, 0.021)):
        finish("coil_%d" % k, rod((x, 0, 0.09), (x + 0.012, 0, 0.09), 0.034, 0.034, 6), COPPER, root, mat, 0.002)
    for k, x in enumerate((-0.03, -0.01, 0.01, 0.03)):
        finish("fin_%d" % k, box((0.006, 0.026, 0.014), (x, 0, 0.124)), METAL_DARK, root, mat, 0.001)
    cell(root, mat, (-0.05, 0, 0.09), (-0.078, 0, 0.09))
    antennae(root, mat, (-0.058, 0, 0.108), 0.01, 0.016, -0.014)   # detrás de las aletas, hacia atrás
    finish("chuck", rod((0.07, 0, 0.09), (0.1, 0, 0.09), 0.022, 0.015), COPPER, root, mat, 0.002)
    # Broca: tramos de 4 lados, cada uno girado un poco más, que se afinan hacia la punta (parece una espiral).
    bit_pivot = bpy.data.objects.new("bit_pivot", None)
    bit_pivot.empty_display_size = 0.02
    bpy.context.collection.objects.link(bit_pivot)
    bit_pivot.parent = root
    bit_pivot.location = (0.1, 0, 0.09)
    inverse = Matrix.Translation(-bit_pivot.location)
    segments, x0, x1 = 6, 0.1, 0.205
    for k in range(segments):
        a = x0 + (x1 - x0) * k / segments
        b = x0 + (x1 - x0) * (k + 1) / segments
        r0 = 0.009 - 0.004 * k / segments
        r1 = 0.009 - 0.004 * (k + 1) / segments
        bm = prism(4, r0, r1, 0.0, b - a, math.radians(25 * k))
        piece = finish("bit_%d" % k, place(bm, (a, 0, 0.09), Matrix.Rotation(math.radians(90), 4, "Y")), METAL_LIGHT, root, mat)
        piece.parent, piece.matrix_parent_inverse = bit_pivot, inverse
    tip = finish("bit_tip", place(prism(4, 0.005, 0.0005, 0.0, 0.02, math.radians(150)), (x1, 0, 0.09),
                                  Matrix.Rotation(math.radians(90), 4, "Y")), METAL_LIGHT, root, mat)
    tip.parent, tip.matrix_parent_inverse = bit_pivot, inverse


# --- Construir ---

def clear_previous():
    for tool_id in TOOLS:
        root = bpy.data.objects.get("tool_" + tool_id)
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
    for i, tool_id in enumerate(TOOLS):
        root = bpy.data.objects.new("tool_" + tool_id, None)
        root.empty_display_type = "PLAIN_AXES"
        root.empty_display_size = 0.05
        bpy.context.collection.objects.link(root)
        root.location = (i * SPACING, 0.0, 0.0)
        globals()[tool_id](root, mat)
        if tool_id in ("biter", "hand_drill"):
            enlarge(root)
    for tool_id in TOOLS:
        root = bpy.data.objects["tool_" + tool_id]
        n = sum(sum(len(p.vertices) - 2 for p in c.data.polygons) for c in root.children if c.type == "MESH")
        print("%-8s %4d triángulos" % (tool_id, n))


def enlarge(root) -> None:
    # Agranda el aparato ×DEVICE_SCALE desde lo alto de la empuñadura (César: en la mano se veían pequeñas),
    # sin tocar la empuñadura, el pomo ni el gatillo, para que sigan encajando en el puño y bajo el índice.
    pivot = Vector((0.0, 0.0, DEVICE_BASE))
    m = Matrix.Translation(pivot) @ Matrix.Scale(DEVICE_SCALE, 4) @ Matrix.Translation(-pivot)
    for obj in root.children_recursive:
        if obj.type == "EMPTY":
            obj.location = m @ obj.location
            for child in obj.children:
                child.matrix_parent_inverse = Matrix.Translation(-obj.location)
        elif obj.name.split(".")[0] not in GRIP_PARTS:
            obj.data.transform(m)


def export() -> None:
    # Cada herramienta a su .glb (assets/models/tools/), con las piezas fijas unidas y las que se mueven
    # aparte bajo su pivote: «jaw_pivot_l/r_mesh» (mandíbulas) y «bit_pivot_mesh» (broca). Ver export_glb.py.
    import os
    import sys
    tools = os.path.dirname(bpy.path.abspath("//../tools/"))
    if tools not in sys.path:
        sys.path.append(tools)
    sys.dont_write_bytecode = True
    import importlib
    import export_glb
    importlib.reload(export_glb)
    for tool_id in TOOLS:
        root = bpy.data.objects["tool_" + tool_id]
        shown_at = root.location.copy()
        root.location = (0.0, 0.0, 0.0)   # en el .glb, el origen es el centro del puño
        bpy.context.view_layer.update()
        export_glb.export_hierarchy(root.name, "//../../assets/models/tools/%s.glb" % tool_id)
        root.location = shown_at


build()
if EXPORT:
    export()
