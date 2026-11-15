# Placa solar del Nexo (B3.7). La placa portátil del laboratorio de Mira: la única pieza «del futuro» en
# la isla. Estilo del Nexo (guía de arte §2): grises desaturados, cristal y el ámbar como único acento.
# Forma: un panel de 7 celdas hexagonales en panal (tecnología de hormiga), inclinado 30° hacia el SUR,
# sobre un mástil con rótula. Instalación FIJA (D-089: Mira la monta en la isla con células y hierro del
# Nexo): placa base de hierro atornillada al suelo con 4 pernos y cartelas, mástil, caja de conexiones a
# media altura (borne y luces) y dos tirantes al norte con sus estacas.
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

    # --- Anclaje fijo (D-089): placa base de hierro atornillada al suelo con 4 pernos y cartelas ---
    finish("base_plate", box((0.56, 0.56, 0.04), (0.0, 0.0, 0.02)), METAL_DARK, root, mat, 0.01)
    for i, (sx, sy) in enumerate(((1, 1), (-1, 1), (-1, -1), (1, -1))):
        finish("anchor_bolt_%d" % i, prism(6, 0.03, 0.03, 0.04, 0.075, x=sx * 0.21, y=sy * 0.21), METAL_DEEP, root, mat, 0.0)
    # Cartelas: triángulos de refuerzo entre la placa y el mástil, en los cuatro lados.
    for i, (dx, dy) in enumerate(((1, 0), (0, 1), (-1, 0), (0, -1))):
        bm = bmesh.new()
        prof = [(0.06, 0.04), (0.24, 0.04), (0.06, 0.26)]
        half = 0.012
        verts = []
        for side in (-half, half):
            for (r, z) in prof:
                # r a lo largo de (dx, dy); side, en perpendicular
                verts.append(bm.verts.new((dx * r - dy * side, dy * r + dx * side, z)))
        bm.faces.new(verts[0:3]); bm.faces.new(verts[3:6])
        for a in range(3):
            b = (a + 1) % 3
            bm.faces.new((verts[a], verts[b], verts[b + 3], verts[a + 3]))
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        finish("gusset_%d" % i, bm, METAL, root, mat, 0.0)

    # Mástil de hierro desde la placa base hasta la caja de conexiones.
    finish("post", prism(6, 0.065, 0.06, 0.04, 0.34), METAL, root, mat, 0.01)

    # Caja de conexiones (con el borne y las luces) a media altura, atornillada al mástil.
    finish("base_module", prism(6, 0.24, 0.22, 0.34, 0.6), METAL, root, mat, 0.02)
    finish("base_bottom", prism(6, 0.2, 0.24, 0.3, 0.34), METAL_DARK, root, mat, 0.01)
    finish("base_cap", prism(6, 0.18, 0.16, 0.6, 0.66), METAL_DARK, root, mat, 0.01)
    finish("base_band", ring(6, 0.228, 0.25, 0.46, 0.49), METAL_DEEP, root, mat, 0.0)

    # Tirantes: dos barras del mástil a dos estacas en el suelo, por el lado norte (contra el viento).
    for i, sx in enumerate((-1, 1)):
        stake = (sx * 0.55, 0.62, 0.0)
        finish("brace_%d" % i, strut((sx * 0.03, 0.05, 0.85), (stake[0], stake[1], 0.06), 0.035), METAL_DARK, root, mat, 0.006)
        finish("brace_stake_%d" % i, prism(6, 0.045, 0.04, 0.0, 0.08, x=stake[0], y=stake[1]), METAL_DEEP, root, mat, 0.0)

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

    # --- Borne del cable: en un saliente de la cara este del módulo (lejos del panel) ---
    finish("cable_ledge", box((0.12, 0.14, 0.04), (0.25, 0.0, 0.52)), METAL_DARK, root, mat, 0.008)
    finish("cable_post", box((0.06, 0.06, 0.08), (0.27, 0.0, 0.58)), METAL, root, mat, 0.008)
    finish("cable_insulator", prism(6, 0.065, 0.048, 0.6, 0.69, x=0.27, y=0.0), INSULATOR, root, mat, 0.008)
    empty("cable_anchor", (0.27, 0.0, 0.69), root)

    # --- Luces de estado: en las caras sur y norte del módulo, bajo el panel (César: las dos) ---
    # Godot enciende todo lo que empiece por «status_light_» (los marcos se llaman «status_frame_»).
    apothem = 0.235 * math.cos(math.radians(30))
    for side, sy in (("south", -1.0), ("north", 1.0)):
        finish("status_frame_" + side, box((0.16, 0.03, 0.1), (0.0, sy * (apothem + 0.005), 0.4)), METAL_DEEP, root, mat, 0.006)
        finish("status_light_" + side, box((0.11, 0.02, 0.055), (0.0, sy * (apothem + 0.02), 0.4)), AMBER, root, glow, 0.005)

    tris = 0
    for child in root.children_recursive:
        if child.type == "MESH":
            tris += sum(len(p.vertices) - 2 for p in child.data.polygons)
    print("piezas:", len(root.children), "triángulos:", tris)


build()
