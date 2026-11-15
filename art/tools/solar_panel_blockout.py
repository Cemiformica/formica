# Placa solar del Nexo (B3.7). La placa portátil del laboratorio de Mira: la única pieza «del futuro» en
# la isla. Estilo del Nexo (guía de arte §2): grises desaturados, cristal y el ámbar como único acento.
# Forma: un panel de 7 celdas hexagonales en panal (tecnología de hormiga), inclinado 30° hacia el SUR,
# sobre un mástil con rótula; base de módulo hexagonal con 4 patas plegables, como un trípode de campo,
# y un asa en el borde de arriba del panel (Mira la trajo en brazos).
# Convenciones: norte = +Y, este = +X, origen en el centro de la huella (2×2) a ras de suelo, todo dentro
# de x, y ∈ [−1, 1]. Sin puertos.
#
# Nodos para Godot: cable_insulator (se ilumina en verde con cable), cable_anchor (enganche del cable) y
# status_light_south/north (luces de estado: encendida si su red funciona, apagada y parpadeando si salta el fusible).
#
# Uso: Editor de texto de Blender → abrir → Alt+P. Si ya existe «solar_panel», lo borra y lo rehace.
# Dónde tocar: las medidas están en build(); cada pieza dice su color como (fila, columna).

import bpy
import bmesh
import math
from mathutils import Matrix, Vector

PALETTE = 64
SWATCH = 8
ROOT = "solar_panel"
TEXTURE = "//../../assets/textures/palette.png"

# Colores (fila, columna) de palette.png
METAL_LIGHT, METAL, METAL_DARK, METAL_DEEP = (5, 2), (5, 3), (5, 4), (5, 5)
PANEL_BLACK = (5, 7)                 # placa bajo las celdas: negra, la que mejor absorbe el calor (César)
CELL, CELL_EDGE = (7, 4), (7, 7)     # cristal azul oscuro de las celdas; gris azulado del marco de cada celda
AMBER = (6, 2)                       # la luz de estado (único acento)
INSULATOR = (7, 6)                   # aislante del borne, como el del horno

TILT = math.radians(30)              # inclinación del panel hacia el sur
PANEL_CENTER = Vector((0.0, -0.05, 1.05))
CELL_R = 0.24                        # radio de cada celda hexagonal (de vértice a centro)


def swatch_uv(row: int, col: int) -> Vector:
    return Vector(((col * SWATCH + SWATCH / 2) / PALETTE, 1.0 - (row * SWATCH + SWATCH / 2) / PALETTE))


def get_materials():
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
        bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
        tex = next(n for n in nt.nodes if n.type == "TEX_IMAGE")
        nt.links.new(tex.outputs["Color"], bsdf.inputs["Emission Color"])
        bsdf.inputs["Emission Strength"].default_value = 1.5
    return base, glow


def finish(name: str, bm: bmesh.types.BMesh, color: tuple, parent, material, bevel: float = 0.02,
           segments: int = 2, transform: Matrix = None):
    # Bisel primero, color después (guía). Biseles de hasta 1,2 cm: un solo segmento.
    if bevel <= 0.012:
        segments = 1
    if bevel > 0.0:
        bmesh.ops.bevel(bm, geom=list(bm.edges), offset=bevel, segments=segments, affect="EDGES",
                        profile=0.5, clamp_overlap=True)
    if transform is not None:
        bmesh.ops.transform(bm, matrix=transform, verts=bm.verts)
    uv = bm.loops.layers.uv.new("UVMap")
    target = swatch_uv(*color)
    for f in bm.faces:
        for loop in f.loops:
            loop[uv].uv = target
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


def box(size, center) -> bmesh.types.BMesh:
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
    bmesh.ops.translate(bm, vec=Vector(center), verts=bm.verts)
    return bm


def prism(sides: int, r_bottom: float, r_top: float, z0: float, z1: float, x=0.0, y=0.0,
          angle: float = 0.0) -> bmesh.types.BMesh:
    # Prisma o tronco de n lados entre z0 y z1. Con angle = 0, un vértice apunta a +X.
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


def ring(sides: int, r_in: float, r_out: float, z0: float, z1: float, angle: float = 0.0) -> bmesh.types.BMesh:
    # Aro de n lados: radio interior y exterior.
    bm = bmesh.new()
    rings = []
    for (r, z) in ((r_out, z0), (r_out, z1), (r_in, z1), (r_in, z0)):
        rings.append([bm.verts.new((r * math.cos(angle + 2 * math.pi * i / sides),
                                    r * math.sin(angle + 2 * math.pi * i / sides), z)) for i in range(sides)])
    for k in range(4):
        a_ring, b_ring = rings[k], rings[(k + 1) % 4]
        for i in range(sides):
            j = (i + 1) % sides
            bm.faces.new((a_ring[i], a_ring[j], b_ring[j], b_ring[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def strut(p0, p1, thick: float) -> bmesh.types.BMesh:
    # Barra de sección cuadrada de p0 a p1 (patas, asa).
    p0, p1 = Vector(p0), Vector(p1)
    d = p1 - p0
    bm = box((thick, thick, d.length), (0.0, 0.0, d.length / 2))
    rot = Vector((0.0, 0.0, 1.0)).rotation_difference(d.normalized()).to_matrix().to_4x4()
    bmesh.ops.transform(bm, matrix=Matrix.Translation(p0) @ rot, verts=bm.verts)
    return bm


def clear_previous() -> None:
    root = bpy.data.objects.get(ROOT)
    if root is None:
        return
    for obj in list(root.children_recursive) + [root]:
        data = obj.data
        bpy.data.objects.remove(obj, do_unlink=True)
        if data is not None and data.users == 0:
            bpy.data.meshes.remove(data)


def empty(name: str, location, parent, kind: str = "SPHERE", size: float = 0.03):
    obj = bpy.data.objects.new(name, None)
    obj.empty_display_type = kind
    obj.empty_display_size = size
    obj.location = location
    obj.parent = parent
    bpy.context.collection.objects.link(obj)
    return obj


def build() -> None:
    clear_previous()
    mat, glow = get_materials()
    root = empty(ROOT, (0, 0, 0), None, "PLAIN_AXES", 0.3)

    # --- Base: módulo hexagonal (caras planas al norte y al sur) sobre 4 patas plegables ---
    finish("base_module", prism(6, 0.30, 0.27, 0.34, 0.62), METAL, root, mat, 0.02)
    finish("base_bottom", prism(6, 0.26, 0.30, 0.28, 0.34), METAL_DARK, root, mat, 0.01)
    finish("base_cap", prism(6, 0.22, 0.20, 0.62, 0.66), METAL_DARK, root, mat, 0.01)
    # Franja saliente en el módulo: se lee como una pieza ensamblada.
    finish("base_band", ring(6, 0.285, 0.31, 0.46, 0.49), METAL_DEEP, root, mat, 0.0)

    # Patas: de las esquinas de abajo del módulo a unos pies cerca de las esquinas de la huella, con
    # una bisagra (articulación) arriba y un pie hexagonal abajo.
    for i, (sx, sy) in enumerate(((1, 1), (-1, 1), (-1, -1), (1, -1))):
        top = (sx * 0.17, sy * 0.17, 0.33)
        foot = (sx * 0.72, sy * 0.72, 0.05)
        finish("leg_%d" % i, strut(top, foot, 0.05), METAL_DARK, root, mat, 0.008)
        finish("leg_hinge_%d" % i, box((0.09, 0.09, 0.07), (sx * 0.17, sy * 0.17, 0.32)), METAL_DEEP, root, mat, 0.01)
        finish("leg_foot_%d" % i, prism(6, 0.07, 0.06, 0.0, 0.05, x=foot[0], y=foot[1]), METAL_DEEP, root, mat, 0.0)

    # Mástil y rótula hasta la parte de atrás del panel.
    finish("mast", prism(6, 0.06, 0.05, 0.66, 0.98), METAL_LIGHT, root, mat, 0.01)
    knuckle = prism(8, 0.07, 0.07, -0.09, 0.09)
    bmesh.ops.rotate(knuckle, cent=(0, 0, 0), matrix=Matrix.Rotation(math.radians(90), 3, "Y"), verts=knuckle.verts)
    bmesh.ops.translate(knuckle, vec=(0.0, 0.0, 0.99), verts=knuckle.verts)
    finish("knuckle", knuckle, METAL_DEEP, root, mat, 0.01)

    # --- Panel: se construye plano (normal +Z) y se inclina 30° hacia el sur ---
    to_panel = Matrix.Translation(PANEL_CENTER) @ Matrix.Rotation(TILT, 4, "X")
    spacing = math.sqrt(3.0) * CELL_R
    centers = [(0.0, 0.0)] + [(spacing * math.cos(math.radians(30 + 60 * k)),
                                spacing * math.sin(math.radians(30 + 60 * k))) for k in range(6)]
    frame_r = 3.0 * CELL_R * 1.03
    # Placa de fondo hexagonal (gris metálica, como la carcasa), una lámina negra encima bajo las celdas
    # y el marco elevado.
    finish("panel_back", prism(6, frame_r, frame_r, -0.05, 0.0), METAL, root, mat, 0.015, transform=to_panel)
    finish("panel_black", prism(6, frame_r - 0.04, frame_r - 0.04, 0.0, 0.006), PANEL_BLACK, root, mat, 0.0,
           transform=to_panel)
    finish("panel_rim", ring(6, frame_r - 0.05, frame_r, 0.0, 0.035), METAL_DARK, root, mat, 0.0, transform=to_panel)
    # Celdas: marco gris azulado y cristal azul oscuro un poco hundido dentro. Los aros finos van sin
    # bisel: con él, cada uno pasaba de 48 a 192 triángulos y no se nota a la distancia de juego.
    for i, (cx, cy) in enumerate(centers):
        finish("cell_frame_%d" % i, ring(6, CELL_R * 0.80, CELL_R * 0.94, 0.0, 0.03), CELL_EDGE, root, mat, 0.0,
               transform=to_panel @ Matrix.Translation((cx, cy, 0.0)))
        finish("cell_glass_%d" % i, prism(6, CELL_R * 0.80, CELL_R * 0.80, 0.0, 0.02), CELL, root, mat, 0.0,
               transform=to_panel @ Matrix.Translation((cx, cy, 0.0)))
    # Soporte del panel: une la rótula con la placa de fondo.
    finish("panel_mount", box((0.16, 0.12, 0.07), (0.0, 0.0, -0.085)), METAL_DEEP, root, mat, 0.01, transform=to_panel)

    # Asa en el borde de arriba (norte) del panel: dos patas y una barra, para llevarla en brazos.
    y_edge = frame_r * math.cos(math.radians(30)) - 0.04
    for sx in (-1, 1):
        finish("handle_post_%d" % (sx > 0), box((0.035, 0.035, 0.12), (sx * 0.16, y_edge, 0.06)), METAL_DARK, root, mat, 0.006,
               transform=to_panel)
    finish("handle_bar", box((0.36, 0.035, 0.035), (0.0, y_edge, 0.12)), METAL_LIGHT, root, mat, 0.008, transform=to_panel)

    # --- Borne del cable: en un saliente de la cara este del módulo (lejos del panel) ---
    finish("cable_ledge", box((0.12, 0.14, 0.04), (0.31, 0.0, 0.52)), METAL_DARK, root, mat, 0.008)
    finish("cable_post", box((0.06, 0.06, 0.08), (0.33, 0.0, 0.58)), METAL, root, mat, 0.008)
    finish("cable_insulator", prism(6, 0.065, 0.048, 0.6, 0.69, x=0.33, y=0.0), INSULATOR, root, mat, 0.008)
    empty("cable_anchor", (0.33, 0.0, 0.69), root)

    # --- Luces de estado: en las caras sur y norte del módulo, bajo el panel (César: las dos) ---
    # Godot enciende todo lo que empiece por «status_light_» (los marcos se llaman «status_frame_»).
    apothem = 0.30 * math.cos(math.radians(30))
    for side, sy in (("south", -1.0), ("north", 1.0)):
        finish("status_frame_" + side, box((0.16, 0.03, 0.1), (0.0, sy * (apothem + 0.005), 0.4)), METAL_DEEP, root, mat, 0.006)
        finish("status_light_" + side, box((0.11, 0.02, 0.055), (0.0, sy * (apothem + 0.02), 0.4)), AMBER, root, glow, 0.005)

    tris = 0
    for child in root.children_recursive:
        if child.type == "MESH":
            tris += sum(len(p.vertices) - 2 for p in child.data.polygons)
    print("piezas:", len(root.children), "triángulos:", tris)


build()
