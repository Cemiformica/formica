# Embarcadero en ruinas de Isla Alba (C5.6b, D-186; sesión 29). Por ahora, una pieza que coloca el juego al final del muelle
# (`DockBuilder`): el muelle, sus pilotes y sus bolardos se generan en código, como la pasarela del vado.
#   - dock_beacon: la baliza apagada. Mástil de tronco hexagonal sobre un trípode de hierro, con abrazaderas de hierro
#     remachadas (y una de cobre con verdín), un borne con el cable cortado, una placa solar del Nexo rota en su brazo y,
#     arriba, el farol: jaula de seis barrotes de hierro (uno doblado) con el cristal ámbar apagado y roto, tejadillo
#     hexagonal de cobre con verdín y dos antenas (una partida). Se ve que lleva hierro: se reparará con él (César). Anuncia la baliza de la barca
#     (D-186): con energía, guiará el piloto automático. El casco de la barca se hará con la barca (César).
# Origen de la pieza en el pie del mástil, sobre la tabla. Mismo estilo que el resto (paleta compartida, biseles pequeños,
# sombreado suave a 30°).
#
# Uso: con art/props/dock.blend abierto, Editor de texto → abrir → Alt+P. Borra y rehace el embarcadero.
# Exportar: export_hierarchy("dock", "//../../assets/models/props/dock.glb") (export_glb.py): cada pieza queda unida en una
# malla bajo su vacío (dock_beacon_mesh).

import bpy
import bmesh
import math
from mathutils import Matrix, Vector

PALETTE = 64
SWATCH = 8
TEXTURE = "//../../assets/textures/palette.png"
SURFACE = "//../../assets/textures/palette_surface.png"

# Cuadritos de la paleta (fila, columna), los mismos que items_blockout.py.
PLANK, PLANK_GRAIN, WOOD_END = (0, 2), (0, 4), (0, 1)
BARK, BARK_DARK = (0, 5), (0, 6)
COPPER, COPPER_LIGHT, COPPER_DARK = (3, 2), (3, 1), (3, 3)
VERDIGRIS, VERDIGRIS_DARK = (3, 5), (3, 6)
IRON, IRON_DARK = (5, 3), (5, 5)
AMBER_DULL, AMBER_DEEP = (6, 3), (6, 5)
CELL, CELL_DEEP = (7, 3), (7, 4)

ROOT = "dock"
MAST_RADIUS = 0.095
MAST_TOP = 1.45
LAMP_BOTTOM = 1.45
LAMP_TOP = 1.82
CAGE_RADIUS = 0.17
GLASS_RADIUS = 0.12


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


def lathe(profile, sides, angle=0.0):
    # Sólido de revolución cerrado por abajo y por arriba: anillos de `sides` lados en cada punto del perfil.
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
    # Palito por tramos (antenas): un prisma de `sides` lados entre cada par de puntos, que se va afinando.
    bm = bmesh.new()
    for k, (a, b) in enumerate(zip(points, points[1:])):
        a, b = Vector(a), Vector(b)
        r0 = radius * (1.0 - 0.3 * k)
        r1 = radius * (1.0 - 0.3 * (k + 1))
        piece = prism(sides, r0, r1, 0.0, (b - a).length, math.radians(45))
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


def bar(a, b, radius, sides=4):
    # Barrote recto de `a` a `b` (un prisma), para la jaula y los brazos.
    a, b = Vector(a), Vector(b)
    piece = prism(sides, radius, radius, 0.0, (b - a).length, math.radians(45))
    rot = Vector((0, 0, 1)).rotation_difference((b - a).normalized()).to_matrix().to_4x4()
    bmesh.ops.transform(piece, matrix=Matrix.Translation(a) @ rot, verts=piece.verts)
    return piece


def moved(bm, location=(0, 0, 0), rotation=None):
    m = Matrix.Translation(Vector(location))
    if rotation is not None:
        m = m @ rotation
    bmesh.ops.transform(bm, matrix=m, verts=bm.verts)
    return bm


# --- Piezas ---

def beacon(root, mat):
    pivot = empty("dock_beacon", root)
    # Mástil: tronco hexagonal que se afina un poco, con la testa de arriba tapada por la base del farol.
    finish("dock_beacon_mast", prism(6, MAST_RADIUS, MAST_RADIUS * 0.85, 0.0, MAST_TOP, math.radians(30)), BARK, pivot, mat, 0.008)
    # Pie: collar de cobre con remaches, clavado a la tabla.
    finish("dock_beacon_collar", prism(6, MAST_RADIUS + 0.03, MAST_RADIUS + 0.025, 0.0, 0.07, math.radians(30)), COPPER_DARK, pivot, mat, 0.005)
    for i in range(6):
        a = math.radians(30 + 60 * i)
        r = MAST_RADIUS + 0.032
        finish("dock_beacon_rivet_%d" % i, moved(prism(6, 0.011, 0.011, 0.0, 0.008), (r * math.cos(a), r * math.sin(a), 0.035),
               Matrix.Rotation(a, 4, "Z") @ Matrix.Rotation(math.radians(90), 4, "Y")), IRON_DARK, pivot, mat)
    # Abrazaderas: de hierro, remachadas (César: que se vea el hierro, con el que se reparará), y una de cobre con verdín
    # (lleva años junto al mar).
    for k, (z, color) in enumerate(((0.32, IRON_DARK), (0.62, VERDIGRIS), (0.95, IRON_DARK), (1.25, IRON_DARK))):
        r = MAST_RADIUS * (1.0 - 0.15 * z / MAST_TOP) + 0.012
        finish("dock_beacon_band_%d" % k, prism(6, r, r, z, z + 0.05, math.radians(30)), color, pivot, mat, 0.004)
        if color == IRON_DARK:
            for i in range(3):
                a = math.radians(30 + 120 * i + 40 * k)
                finish("dock_beacon_band_rivet_%d_%d" % (k, i), moved(prism(6, 0.009, 0.009, 0.0, 0.007),
                       ((r + 0.001) * math.cos(a), (r + 0.001) * math.sin(a), z + 0.025),
                       Matrix.Rotation(a, 4, "Z") @ Matrix.Rotation(math.radians(90), 4, "Y")), IRON, pivot, mat)
    # Trípode de hierro: tres tornapuntas del mástil a la tabla, con su pie atornillado. Una, suelta y doblada.
    for i in range(3):
        a = math.radians(90 + 120 * i)
        top = (MAST_RADIUS * 0.9 * math.cos(a), MAST_RADIUS * 0.9 * math.sin(a), 0.42)
        foot = (0.34 * math.cos(a), 0.34 * math.sin(a), 0.02)
        if i == 2:
            foot = (0.3 * math.cos(a + 0.35), 0.3 * math.sin(a + 0.35), 0.03)
            knee = (0.22 * math.cos(a + 0.2), 0.22 * math.sin(a + 0.2), 0.12)
            finish("dock_beacon_strut_%d" % i, stick([top, knee, foot], 0.016), IRON, pivot, mat)
        else:
            finish("dock_beacon_strut_%d" % i, bar(top, foot, 0.015), IRON, pivot, mat)
        finish("dock_beacon_foot_%d" % i, moved(prism(6, 0.045, 0.04, 0.0, 0.018, math.radians(30)), (foot[0], foot[1], 0.0)),
               IRON_DARK, pivot, mat, 0.003)
    # Borne con el cable cortado: una cajita de cobre y un trozo de cable que cuelga y se riza (la baliza necesita energía).
    finish("dock_beacon_terminal", moved(box_bm((0.06, 0.05, 0.08)), (0.0, -MAST_RADIUS - 0.02, 0.4)), COPPER, pivot, mat, 0.006)
    cable = [(0.0, -MAST_RADIUS - 0.05, 0.4), (0.03, -MAST_RADIUS - 0.09, 0.33), (0.0, -MAST_RADIUS - 0.11, 0.25),
             (-0.04, -MAST_RADIUS - 0.08, 0.2), (-0.02, -MAST_RADIUS - 0.05, 0.16)]
    finish("dock_beacon_cable", stick(cable, 0.012), COPPER_DARK, pivot, mat)
    # Brazo con la placa solar del Nexo, rota: un hexágono de celda azul con una esquina partida y la mitad oscura.
    arm_from, arm_to = (MAST_RADIUS * 0.8, 0.0, 1.22), (0.32, 0.0, 1.3)
    finish("dock_beacon_arm", bar(arm_from, arm_to, 0.016), IRON_DARK, pivot, mat)
    tilt = Matrix.Rotation(math.radians(-35), 4, "Y")
    finish("dock_beacon_panel_frame", moved(prism(6, 0.13, 0.13, -0.012, 0.0, math.radians(30)), (0.38, 0.0, 1.32), tilt), IRON, pivot, mat, 0.004)
    cell = bmesh.new()
    pts = [(0.11 * math.cos(math.radians(30 + 60 * i)), 0.11 * math.sin(math.radians(30 + 60 * i))) for i in range(6)]
    pts[1] = (pts[1][0] * 0.45, pts[1][1] * 0.45)   # la esquina que se partió
    verts = [cell.verts.new((x, y, 0.004)) for x, y in pts]
    cell.faces.new(verts)
    finish("dock_beacon_panel_cell", moved(cell, (0.38, 0.0, 1.32), tilt), CELL, pivot, mat)
    shard = bmesh.new()
    sv = [shard.verts.new(p) for p in ((-0.09, -0.05, 0.006), (0.02, -0.1, 0.006), (-0.03, 0.04, 0.006))]
    shard.faces.new(sv)
    finish("dock_beacon_panel_dead", moved(shard, (0.38, 0.0, 1.32), tilt), CELL_DEEP, pivot, mat)
    # Farol: base de hierro, cristal ámbar apagado al que le falta un panel, seis barrotes de hierro (uno doblado hacia
    # fuera) con su aro, tejadillo de cobre con verdín y su remate.
    finish("dock_beacon_lamp_base", prism(6, CAGE_RADIUS + 0.02, CAGE_RADIUS, LAMP_BOTTOM - 0.02, LAMP_BOTTOM + 0.04, math.radians(30)),
           IRON_DARK, pivot, mat, 0.006)
    glass = bmesh.new()
    bottom = [glass.verts.new((GLASS_RADIUS * math.cos(math.radians(30 + 60 * i)), GLASS_RADIUS * math.sin(math.radians(30 + 60 * i)),
                               LAMP_BOTTOM + 0.04)) for i in range(6)]
    top = [glass.verts.new((v.co.x * 0.92, v.co.y * 0.92, LAMP_TOP - 0.06)) for v in bottom]
    for i in range(6):
        j = (i + 1) % 6
        if i == 4:
            continue   # el panel roto: se ve el hueco
        glass.faces.new((bottom[i], bottom[j], top[j], top[i]))
    glass.faces.new(top)
    a4, a5 = bottom[4].co.copy(), bottom[5].co.copy()   # antes de `finish`, que libera el bmesh
    finish("dock_beacon_glass", glass, AMBER_DULL, pivot, mat)
    # Lo que queda del panel roto: un triángulo de cristal abajo.
    piece = bmesh.new()
    pv = [piece.verts.new(p) for p in (a4, a5, a4.lerp(a5, 0.35) + Vector((0, 0, 0.12)))]
    piece.faces.new(pv)
    finish("dock_beacon_glass_shard", piece, AMBER_DEEP, pivot, mat)
    # Mecha apagada dentro: un cilindrito oscuro.
    finish("dock_beacon_wick", prism(6, 0.025, 0.02, LAMP_BOTTOM + 0.04, LAMP_BOTTOM + 0.14), IRON_DARK, pivot, mat)
    for i in range(6):
        a = math.radians(60 * i)
        lo = (CAGE_RADIUS * math.cos(a), CAGE_RADIUS * math.sin(a), LAMP_BOTTOM + 0.03)
        hi = (CAGE_RADIUS * 0.9 * math.cos(a), CAGE_RADIUS * 0.9 * math.sin(a), LAMP_TOP)
        if i == 2:   # el doblado: sale hacia fuera por la mitad
            mid = (CAGE_RADIUS * 1.45 * math.cos(a), CAGE_RADIUS * 1.45 * math.sin(a), (LAMP_BOTTOM + LAMP_TOP) * 0.5)
            finish("dock_beacon_bar_%d" % i, stick([lo, mid, hi], 0.012), IRON, pivot, mat)
        else:
            finish("dock_beacon_bar_%d" % i, bar(lo, hi, 0.011), IRON, pivot, mat)
    # Aro de hierro que cierra la jaula por arriba, bajo el tejadillo.
    ring = prism(6, CAGE_RADIUS * 0.95, CAGE_RADIUS * 0.95, LAMP_TOP - 0.03, LAMP_TOP + 0.005, math.radians(30))
    finish("dock_beacon_cage_ring", ring, IRON_DARK, pivot, mat, 0.004)
    finish("dock_beacon_roof", prism(6, CAGE_RADIUS + 0.05, 0.03, LAMP_TOP, LAMP_TOP + 0.13, math.radians(30)), COPPER_DARK, pivot, mat, 0.006)
    finish("dock_beacon_roof_rust", prism(6, CAGE_RADIUS * 0.55, 0.035, LAMP_TOP + 0.075, LAMP_TOP + 0.125, math.radians(30)), VERDIGRIS_DARK, pivot, mat)
    finish("dock_beacon_finial", prism(6, 0.028, 0.012, LAMP_TOP + 0.12, LAMP_TOP + 0.19, math.radians(30)), COPPER, pivot, mat)
    # Antenas: la de la izquierda entera, la de la derecha partida a media altura (las máquinas que trabajan solas, D-143).
    for side, length in ((-1, 1.0), (1, 0.45)):
        pts = [(side * 0.03, 0.0, LAMP_TOP + 0.16), (side * 0.09, 0.0, LAMP_TOP + 0.16 + 0.12 * length),
               (side * (0.09 + 0.08 * length), 0.0, LAMP_TOP + 0.16 + 0.17 * length)]
        finish("dock_beacon_antenna_%d" % (side + 1), stick(pts, 0.012), IRON_DARK, pivot, mat)
    # Vacío para la luz cuando se encienda (más adelante, con la barca).
    empty("beacon_light", pivot, (0.0, 0.0, LAMP_BOTTOM + 0.18))


def box_bm(size):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=size, verts=bm.verts)
    return bm


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
    beacon(root, mat)
    for name in ("dock_beacon",):
        pivot = bpy.data.objects[name]
        tris = sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in pivot.children_recursive if o.type == "MESH")
        print(name, tris, "triángulos")


build()
