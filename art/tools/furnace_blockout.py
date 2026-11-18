# Blockout del horno de fundición (B3), versión 2 con puertos estándar (D-079). Genera en la escena
# abierta un horno de 2×2 con piezas simples, cada una de un color de la paleta, colgadas de un vacío
# «furnace» en el origen. Convenciones de la guía de arte: norte = +Y, este = +X, origen en el centro de
# la huella a ras de suelo, todo dentro de x, y ∈ [−1, 1] y por debajo de 3,5 m.
# Puertos (PortData): entradas al oeste (−X) en las dos casillas; salidas al este (+X): lingote en la
# casilla norte (y > 0) y escoria en la sur (y < 0). Los puertos NO forman parte del horno: los pone
# Godot. Aquí solo se colocan copias de referencia (colección «ref_ports», no se exporta) para ver cómo
# encajan. Regla: donde hay un puerto, el cuerpo llega con una pared plana hasta 0,25 m del borde.
#
# Nodos para Godot: ember_window_east_0…2 / west_0…2 (brasas, cada grupo a su ritmo), cable_insulator (se ilumina con cable), cable_anchor,
# smoke_origin (humo) y bellows_pivot (fuelle animado).
#
# Uso: Editor de texto de Blender → abrir → Alt+P. Si ya existe «furnace», lo borra y lo rehace.
# Dónde tocar: las medidas están en build(); cada pieza dice su color como (fila, columna).

import bpy
import bmesh
import importlib
import math
import os
import sys
from mathutils import Matrix, Vector

# Emblema de la colonia: pieza común en art/tools/crest.py (sin dejar __pycache__ en el proyecto).
sys.dont_write_bytecode = True
sys.path.insert(0, os.path.normpath(bpy.path.abspath("//../tools")))
import crest
importlib.reload(crest)

PALETTE = 64
SWATCH = 8
ROOT = "furnace"
BEVEL = 0.02


def swatch_uv(row: int, col: int) -> Vector:
    return Vector(((col * SWATCH + SWATCH / 2) / PALETTE, 1.0 - (row * SWATCH + SWATCH / 2) / PALETTE))


def get_materials():
    base = bpy.data.materials["palette"]
    glow = bpy.data.materials.get("palette_emissive")
    if glow is None:
        glow = base.copy()
        glow.name = "palette_emissive"
        nt = glow.node_tree
        bsdf = nt.nodes["Principled BSDF"]
        tex = next(n for n in nt.nodes if n.type == "TEX_IMAGE")
        nt.links.new(tex.outputs["Color"], bsdf.inputs["Emission Color"])
    # Intensidad del brillo: se fija siempre, para que cambiarla aquí afecte también al material ya creado.
    glow.node_tree.nodes["Principled BSDF"].inputs["Emission Strength"].default_value = 1.5
    return base, glow


def finish(name: str, bm: bmesh.types.BMesh, color: tuple, parent, material, bevel: float = BEVEL,
           segments: int = 2):
    # Bisel primero, color después (regla de la guía). Los biseles pequeños (≤ 1,2 cm) llevan un solo
    # segmento: no se nota la diferencia y ahorra muchos triángulos (presupuesto, guía de arte §4).
    if bevel <= 0.012:
        segments = 1
    if bevel > 0.0:
        bmesh.ops.bevel(bm, geom=list(bm.edges), offset=bevel, segments=segments, affect="EDGES",
                        profile=0.5, clamp_overlap=True)
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


def cut_recess(obj, size, center, color) -> None:
    # Hunde una caja en `obj`.
    cut_with(obj, box(size, center), color)


def cut_with(obj, bm: bmesh.types.BMesh, color) -> None:
    # Resta la malla `bm` de `obj` (booleana aplicada). Las caras nuevas del hueco salen del cortador,
    # así que heredan su color de la paleta.
    uv = bm.loops.layers.uv.new("UVMap")
    target = swatch_uv(*color)
    for f in bm.faces:
        for loop in f.loops:
            loop[uv].uv = target
    cutter_mesh = bpy.data.meshes.new("recess_cutter")
    bm.to_mesh(cutter_mesh)
    bm.free()
    cutter = bpy.data.objects.new("recess_cutter", cutter_mesh)
    bpy.context.collection.objects.link(cutter)
    mod = obj.modifiers.new("recess", "BOOLEAN")
    mod.operation = "DIFFERENCE"
    mod.object = cutter
    deps = bpy.context.evaluated_depsgraph_get()
    new_mesh = bpy.data.meshes.new_from_object(obj.evaluated_get(deps))
    obj.modifiers.clear()
    old_mesh = obj.data
    obj.data = new_mesh
    bpy.data.meshes.remove(old_mesh)
    new_mesh.name = obj.name
    bpy.data.objects.remove(cutter, do_unlink=True)
    bpy.data.meshes.remove(cutter_mesh)
    for p in new_mesh.polygons:
        p.use_smooth = True
    new_mesh.set_sharp_from_angle(angle=math.radians(30))


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


def box(size, center) -> bmesh.types.BMesh:
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
    bmesh.ops.translate(bm, vec=Vector(center), verts=bm.verts)
    return bm


def coal_group(pieces, seed: int) -> bmesh.types.BMesh:
    # Brasas de juguete (César: la ventana entera brillando parecía una pantalla o lava): piedrecitas
    # facetadas, como el humo y el carbón, juntas en una malla que Godot enciende a su ritmo.
    import random
    rng = random.Random(seed)
    bm = bmesh.new()
    for center, radius in pieces:
        verts = bmesh.ops.create_icosphere(bm, subdivisions=1, radius=radius)["verts"]
        for v in verts:
            v.co *= 1.0 + rng.uniform(-0.18, 0.18)
            v.co.z *= 0.8
        bmesh.ops.rotate(bm, verts=verts, cent=(0, 0, 0), matrix=Matrix.Rotation(rng.uniform(0, math.tau), 3, "Z"))
        bmesh.ops.translate(bm, vec=Vector(center), verts=verts)
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
    # Aro de n lados (cerrado, para booleanas y para los flejes): radio interior y exterior.
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


def sloped_slab(x0, x1, y_half, y, z_start, z_end, thickness) -> bmesh.types.BMesh:
    # Losa inclinada a lo largo de X (canales y rampas): baja de z_start (en x0) a z_end (en x1).
    bm = bmesh.new()
    pts = []
    for (x, z) in ((x0, z_start), (x1, z_end)):
        for dy in (-y_half, y_half):
            pts.append((x, y + dy, z))
    v = [bm.verts.new((p[0], p[1], p[2] - thickness)) for p in pts] + [bm.verts.new(p) for p in pts]
    for f in ((0, 2, 3, 1), (4, 5, 7, 6), (0, 1, 5, 4), (2, 6, 7, 3), (0, 4, 6, 2), (1, 3, 7, 5)):
        bm.faces.new([v[i] for i in f])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def wedge(x, y_back, y_front, z_mid, half_open, half_closed, width) -> bmesh.types.BMesh:
    # Fuelle: cuña centrada en `x`, abierta atrás (y_back) y cerrada delante (y_front), de `width` de ancho.
    bm = bmesh.new()
    hx = width / 2
    back = [(-hx, y_back, z_mid - half_open), (hx, y_back, z_mid - half_open),
            (hx, y_back, z_mid + half_open), (-hx, y_back, z_mid + half_open)]
    front = [(-hx, y_front, z_mid - half_closed), (hx, y_front, z_mid - half_closed),
             (hx, y_front, z_mid + half_closed), (-hx, y_front, z_mid + half_closed)]
    v = [bm.verts.new((p[0] + x, p[1], p[2])) for p in back + front]
    for f in ((0, 1, 2, 3), (4, 7, 6, 5), (0, 4, 5, 1), (3, 2, 6, 7), (0, 3, 7, 4), (1, 5, 6, 2)):
        bm.faces.new([v[i] for i in f])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


PORT_BLEND = "//port.blend"
# Puertos del horno: (objeto, centro de la casilla, giro en Z). El puerto se modela mirando al norte
# (+Y); +90° lo pone mirando al oeste y −90° al este.
PORTS = [
    ("port_input", (-0.5, 0.5), 90.0),
    ("port_input", (-0.5, -0.5), 90.0),
    ("port_output", (0.5, 0.5), -90.0),
    ("port_output", (0.5, -0.5), -90.0),
]


def clear_previous() -> None:
    old = bpy.data.objects.get(ROOT)
    if old is not None:
        for child in list(old.children_recursive):
            bpy.data.objects.remove(child, do_unlink=True)
        bpy.data.objects.remove(old, do_unlink=True)
    refs = bpy.data.collections.get("ref_ports")
    if refs is not None:
        for obj in list(refs.objects):
            bpy.data.objects.remove(obj, do_unlink=True)


def place_reference_ports() -> None:
    # Copias de referencia de los puertos de port.blend (malla enlazada: si cambia el puerto, cambia aquí).
    refs = bpy.data.collections.get("ref_ports")
    if refs is None:
        refs = bpy.data.collections.new("ref_ports")
        bpy.context.scene.collection.children.link(refs)
    # Se enlazan los OBJETOS por su nombre y se usa su malla (el nombre de la malla puede variar).
    linked = {}
    for name in ("port_input", "port_output"):
        found = next((o for o in bpy.data.objects if o.name == name and o.library is not None), None)
        if found is not None:
            linked[name] = found
    missing = [n for n in ("port_input", "port_output") if n not in linked]
    if missing:
        with bpy.data.libraries.load(PORT_BLEND, link=True) as (src, dst):
            dst.objects = missing
        for obj in dst.objects:
            linked[obj.name] = obj
    for i, (port_name, (x, y), angle) in enumerate(PORTS):
        obj = bpy.data.objects.new("ref_%s_%d" % (port_name, i), linked[port_name].data)
        obj.location = (x, y, 0.0)
        obj.rotation_euler = (0.0, 0.0, math.radians(angle))
        refs.objects.link(obj)


def build() -> None:
    clear_previous()
    mat, glow = get_materials()
    root = bpy.data.objects.new(ROOT, None)
    root.empty_display_type = "PLAIN_AXES"
    bpy.context.collection.objects.link(root)

    # Colores (fila, columna) de palette.png
    STONE, STONE_DARK, STONE_DEEP = (1, 2), (1, 4), (1, 5)
    CLAY, CLAY_DARK = (4, 2), (4, 4)
    WOOD, WOOD_DARK = (0, 3), (0, 5)
    FIBER, FIBER_DARK = (1, 1), (1, 3)
    METAL, GLASS = (5, 3), (7, 6)
    EMBER = (6, 3)
    HEX = math.radians(30)  # vértices al norte y al sur; caras planas al este y al oeste

    # Zócalo: llega con paredes planas a x = ±0,75, donde se apoyan los cuatro puertos (0,6 m de alto).
    finish("plinth", box((1.5, 1.84, 0.8), (0, 0, 0.4)), STONE_DARK, root, mat, 0.03)
    finish("plinth_cap", box((1.56, 1.9, 0.08), (0, 0, 0.84)), STONE_DEEP, root, mat, 0.02)

    # Cuba más baja y ancha: piedra abajo, arcilla arriba, aro y chimenea (2,8 m en total).
    body_stone = finish("body_stone", prism(6, 0.75, 0.71, 0.88, 1.4, angle=HEX), STONE, root, mat, 0.03)
    finish("body_clay", prism(6, 0.71, 0.58, 1.4, 1.95, angle=HEX), CLAY, root, mat, 0.03)
    finish("rim", prism(6, 0.64, 0.64, 1.95, 2.06, angle=HEX), STONE_DEEP, root, mat)
    finish("chimney", prism(6, 0.25, 0.2, 2.06, 2.8, angle=HEX), CLAY_DARK, root, mat)

    # Ventanitas de brasa: centradas en las caras este y oeste (planas, |x| ≈ 0,63 a esa altura) y hundidas.
    # Dentro, un montón de brasas de juguete en tres grupos (Godot enciende cada «ember_window…» a su ritmo)
    # tras una rejilla de barrotes de hierro; el fondo queda oscuro (César: antes parecía una pantalla).
    GRATE = (5, 5)
    for side, sx in (("east", 1.0), ("west", -1.0)):
        cut_recess(body_stone, (0.2, 0.32, 0.24), (sx * 0.69, 0.0, 1.14), STONE_DEEP)
        finish("ember_back_" + side, box((0.01, 0.32, 0.24), (sx * 0.597, 0.0, 1.14)), (5, 6), root, mat, 0.0) # fondo oscuro
        for g in range(3):
            pieces = []
            for k in range(4):  # cuatro brasas por grupo (con cinco se pasaba del presupuesto)
                y = -0.12 + g * 0.085 + (k % 3) * 0.028
                z = 1.05 + (0.045 if k >= 3 else 0.0) + (0.01 if g == 1 else 0.0)
                x = sx * (0.605 + (0.012 if k % 2 else 0.0))
                pieces.append(((x, y, z), 0.032 + 0.006 * ((k + g) % 3)))
            finish("ember_window_%s_%d" % (side, g), coal_group(pieces, 7 + g + (10 if sx > 0 else 0)), EMBER, root, glow, 0.0)
        for y in (-0.08, 0.0, 0.08):
            finish("ember_grate_%s_%d" % (side, int((y + 1) * 100)), box((0.018, 0.02, 0.24), (sx * 0.632, y, 1.14)), GRATE, root, mat, 0.0)
        finish("ember_grate_%s_bar" % side, box((0.018, 0.3, 0.02), (sx * 0.632, 0.0, 1.2)), GRATE, root, mat, 0.0)

    # Fuelle sobre el zócalo, en la esquina suroeste, soplando hacia la cuba (al norte). César: «que no parezca
    # de plástico»: cuero oscuro en pliegues que sobresalen y se meten alternos, tablas de madera con flejes
    # de hierro, boquilla de cobre con su aro y una orejeta en la tabla de arriba donde engancha la biela.
    y_back, y_front, z_mid = -0.93, -0.62, 1.0
    LEATHER, LEATHER_DARK = (4, 6), (4, 7)
    COPPER, COPPER_DARK = (3, 1), (3, 2)
    IRON = (5, 4)
    moving = []
    folds = 7
    for k in range(folds):
        t0, t1 = k / folds, (k + 1) / folds
        ya, yb = y_back + (y_front - y_back) * t0, y_back + (y_front - y_back) * t1
        ha, hb = 0.085 + (0.03 - 0.085) * t0, 0.085 + (0.03 - 0.085) * t1
        out = 0.012 if k % 2 == 0 else 0.0
        name = "bellows_fold_%d" % k
        finish(name, wedge(-0.48, ya, yb, z_mid, ha + out, hb + out, 0.3 + 2 * out), LEATHER if k % 2 == 0 else LEATHER_DARK, root, mat, 0.0)
        moving.append(name)
    for name, z in (("bellows_board_top", z_mid + 0.1), ("bellows_board_bottom", z_mid - 0.1)):
        finish(name, box((0.36, 0.34, 0.03), (-0.48, -0.775, z)), WOOD, root, mat, 0.0)
        for k, y in enumerate((-0.86, -0.69)):
            strap = name + "_strap_%d" % k
            finish(strap, box((0.38, 0.03, 0.036), (-0.48, y, z)), IRON, root, mat, 0.0)
            if name.endswith("top"):
                moving.append(strap)
    moving.append("bellows_board_top")
    nozzle = prism(6, 0.034, 0.024, 0.0, 0.13, angle=math.radians(30))
    bmesh.ops.transform(nozzle, matrix=Matrix.Translation((-0.48, y_front - 0.01, z_mid)) @ Matrix.Rotation(math.radians(-90), 4, "X"), verts=nozzle.verts)
    finish("bellows_nozzle", nozzle, COPPER, root, mat, 0.004)
    collar = prism(6, 0.042, 0.042, 0.0, 0.025, angle=math.radians(30))
    bmesh.ops.transform(collar, matrix=Matrix.Translation((-0.48, y_front - 0.005, z_mid)) @ Matrix.Rotation(math.radians(-90), 4, "X"), verts=collar.verts)
    finish("bellows_nozzle_collar", collar, COPPER_DARK, root, mat, 0.0)
    moving += ["bellows_nozzle", "bellows_nozzle_collar"]
    # Orejeta en el canto este de la tabla de arriba y la biela que baja a la manivela del eje (se mueve con
    # la tabla: así el fuelle se ve empujado por el motor).
    finish("bellows_lug", box((0.03, 0.05, 0.06), (-0.315, -0.85, z_mid + 0.11)), IRON, root, mat, 0.004)
    finish("bellows_rod", box((0.022, 0.022, 0.09), (-0.29, -0.85, z_mid + 0.08)), METAL, root, mat, 0.0)
    moving += ["bellows_lug", "bellows_rod"]

    # Pivote del fuelle: en la tabla de abajo, del lado de la boquilla. Godot escala el pivote en
    # vertical (aplasta y estira) mientras el horno trabaja. La tabla de abajo no se mueve; la boquilla
    # sí (cuelga del pivote), para que siga al fuelle y no asome al aplastarse (César).
    pivot_pos = Vector((-0.48, y_front, z_mid - 0.1))
    pivot = bpy.data.objects.new("bellows_pivot", None)
    pivot.empty_display_type = "ARROWS"
    pivot.empty_display_size = 0.1
    pivot.location = pivot_pos
    pivot.parent = root
    bpy.context.collection.objects.link(pivot)
    for moving_name in moving:
        obj = bpy.data.objects[moving_name]
        obj.parent = pivot
        obj.matrix_parent_inverse = Matrix.Translation(pivot_pos).inverted()

    # Motor eléctrico del fuelle (gris del Nexo y cristal), en la esquina sureste del zócalo.
    finish("motor", box((0.28, 0.26, 0.24), (0.42, -0.74, 1.0)), METAL, root, mat)
    finish("motor_glass", box((0.14, 0.16, 0.04), (0.37, -0.74, 1.13)), GLASS, root, mat, 0.01)
    # Detalles del motor (César): aletas de refrigeración en la cara sur, una tapa hexagonal al este con
    # tornillos y un anillo naranja.
    for k in range(5):
        finish("motor_fin_%d" % k, box((0.018, 0.03, 0.18), (0.32 + k * 0.05, -0.885, 1.0)), (5, 4), root, mat, 0.0)
    cap = prism(6, 0.1, 0.085, 0.0, 0.04, angle=math.radians(30))
    bmesh.ops.transform(cap, matrix=Matrix.Translation((0.56, -0.74, 1.0)) @ Matrix.Rotation(math.radians(90), 4, "Y"), verts=cap.verts)
    finish("motor_endcap", cap, (5, 4), root, mat, 0.004)
    finish("motor_band", box((0.03, 0.27, 0.25), (0.5, -0.74, 1.0)), (4, 2), root, mat, 0.004)

    # Borne del cable en el motor: poste y aislante hexagonal. El vacío «cable_anchor», en su punta,
    # le dice a Godot dónde se engancha exactamente el cable.
    finish("cable_post", box((0.07, 0.07, 0.1), (0.5, -0.74, 1.16)), METAL, root, mat, 0.01)
    finish("cable_insulator", prism(6, 0.075, 0.055, 1.19, 1.29, x=0.5, y=-0.74), GLASS, root, mat, 0.01)
    anchor = bpy.data.objects.new("cable_anchor", None)
    anchor.empty_display_type = "SPHERE"
    anchor.empty_display_size = 0.03
    anchor.location = (0.5, -0.74, 1.29)
    anchor.parent = root
    bpy.context.collection.objects.link(anchor)

    # Punto de salida del humo: en la boca de la chimenea, bajo la tapa (Godot pone ahí las partículas).
    smoke = bpy.data.objects.new("smoke_origin", None)
    smoke.empty_display_type = "SPHERE"
    smoke.empty_display_size = 0.05
    smoke.location = (0.0, 0.0, 2.83)
    smoke.parent = root
    bpy.context.collection.objects.link(smoke)
    # Eje del fuelle: del costado oeste del motor (x = 0,28) al fuelle (x = −0,33), por fuera de la
    # esquina sur de la cuba (que está en y = −0,75).
    # Transmisión (César: la barra lisa parecía de plástico): eje hexagonal, polea naranja en el motor,
    # cojinete sobre un soporte a mitad de camino y una manivela al final, donde engancha la biela del fuelle.
    shaft = prism(6, 0.026, 0.026, -0.3, 0.28, angle=math.radians(30))
    bmesh.ops.transform(shaft, matrix=Matrix.Translation((0.0, -0.85, 1.0)) @ Matrix.Rotation(math.radians(90), 4, "Y"), verts=shaft.verts)
    finish("drive_shaft", shaft, (5, 2), root, mat, 0.0)
    # Polea, manivela y tornillos del cojinete en cobre (herrajes: brillan, D-105; César).
    for name, x, r, w, color in (("drive_pulley", 0.255, 0.075, 0.03, (3, 2)), ("drive_crank", -0.285, 0.06, 0.025, (3, 2))):
        disc = prism(8, r, r, -w / 2, w / 2)
        bmesh.ops.transform(disc, matrix=Matrix.Translation((x, -0.85, 1.0)) @ Matrix.Rotation(math.radians(90), 4, "Y"), verts=disc.verts)
        finish(name, disc, color, root, mat, 0.0)
        hub = prism(6, 0.03, 0.03, -w, w, angle=math.radians(30))
        bmesh.ops.transform(hub, matrix=Matrix.Translation((x, -0.85, 1.0)) @ Matrix.Rotation(math.radians(90), 4, "Y"), verts=hub.verts)
        finish(name + "_hub", hub, (5, 5), root, mat, 0.0)
    finish("drive_crank_pin", box((0.03, 0.022, 0.022), (-0.285, -0.85, 1.04)), (5, 5), root, mat, 0.0)
    finish("drive_bearing", box((0.08, 0.09, 0.08), (-0.01, -0.85, 1.0)), (5, 4), root, mat, 0.006)
    finish("drive_bearing_post", box((0.05, 0.05, 0.1), (-0.01, -0.85, 0.91)), (5, 5), root, mat, 0.0)
    for x in (-0.04, 0.02):
        finish("drive_bearing_bolt_%d" % int((x + 1) * 100), hex_rivet((x, -0.85, 1.04), (0, 0, 1), r=0.012, depth=0.012), (3, 1), root, mat, 0.0)

    add_details(root, mat, body_stone)

    tris = 0
    for child in root.children_recursive:
        if child.type == "MESH":
            tris += sum(len(p.vertices) - 2 for p in child.data.polygons)
    print("piezas:", len(root.children), "triángulos:", tris)
    place_reference_ports()


def add_details(root, mat, body_stone) -> None:
    # Textura «de juguete» con geometría y dos tonos vecinos de la paleta (guía de arte §2).
    STONE_A, STONE_B = (1, 3), (1, 5)
    METAL_DARK, MOUTH, METAL = (5, 4), (5, 6), (5, 3)
    HEX = math.radians(30)
    D = 0.015  # lo que sobresale un sillar o un bloque

    # Sillares en las cuatro esquinas del zócalo (1,5 × 1,84 × 0,8 m): dos por esquina, alternando
    # tamaño y tono, como las piedras trabadas de una esquina real.
    for sx in (-1, 1):
        for sy in (-1, 1):
            for k, (z0, z1) in enumerate(((0.0, 0.4), (0.4, 0.8))):
                wx, wy = (0.3, 0.14) if k == 0 else (0.16, 0.26)
                cx = sx * (0.75 - wx / 2 + D)
                cy = sy * (0.92 - wy / 2 + D)
                color = STONE_A if (k + (sx > 0) + (sy > 0)) % 2 == 0 else STONE_B
                finish("quoin_%d_%d_%d" % (sx + 1, sy + 1, k), box((wx, wy, z1 - z0 - 0.02), (cx, cy, (z0 + z1) / 2)),
                       color, root, mat, 0.01, 1)

    # Bloques sueltos en las caras norte y sur del zócalo.
    loose = [((-0.3, 0.92), (0.34, 0.16), 0.25, STONE_A), ((0.25, 0.92), (0.26, 0.14), 0.58, STONE_B),
             ((0.15, -0.92), (0.32, 0.16), 0.3, STONE_B)]
    for i, ((x, y), (w, h), z, color) in enumerate(loose):
        sign = 1 if y > 0 else -1
        finish("stone_block_%d" % i, box((w, 2 * D + 0.02, h), (x, y + sign * D / 2, z)), color, root, mat, 0.01, 1)

    # Dos juntas hundidas alrededor de la piedra de la cuba (sin cruzar la ventanita: 1,02–1,26 m).
    for z in (0.98, 1.31):
        r_here = 0.75 - 0.04 * (z - 0.88) / 0.52
        cut_with(body_stone, ring(6, r_here - 0.018, r_here + 0.1, z - 0.012, z + 0.012, HEX), STONE_B)

    # Dos flejes de metal alrededor de la arcilla (radio en ese punto + 2 cm).
    for i, z in enumerate((1.5, 1.8)):
        r_here = 0.71 - 0.13 * (z - 1.4) / 0.55
        finish("hoop_%d" % i, ring(6, r_here - 0.01, r_here + 0.025, z - 0.03, z + 0.03, HEX), METAL_DARK, root, mat, 0.008, 1)

    # Remaches del motor (caja de 0,28 × 0,26 × 0,24 en (0,42, −0,74, 1,0)): cara sur y cara este.
    for dx in (-0.1, 0.1):
        for dz in (-0.08, 0.08):
            finish("rivet_s_%d_%d" % (dx > 0, dz > 0), hex_rivet((0.42 + dx, -0.87, 1.0 + dz), (0, -1, 0)), METAL_DARK, root, mat, 0.0)
    for dy in (-0.09, 0.09):
        for dz in (-0.08, 0.08):
            finish("rivet_e_%d_%d" % (dy > 0, dz > 0), hex_rivet((0.56, -0.74 + dy, 1.0 + dz), (1, 0, 0)), METAL_DARK, root, mat, 0.0)

    # Chimenea (termina en 2,8 m, radio 0,2): boca oscura, tres patas y tapa de metal.
    finish("chimney_mouth", prism(6, 0.16, 0.16, 2.79, 2.805, angle=HEX), MOUTH, root, mat, 0.0)
    for i in range(3):
        a = HEX + 2 * math.pi * i / 3
        finish("cap_leg_%d" % i, box((0.025, 0.025, 0.11), (0.15 * math.cos(a), 0.15 * math.sin(a), 2.855)), METAL, root, mat, 0.0)
    finish("chimney_cap", prism(6, 0.26, 0.22, 2.9, 2.94, angle=HEX), METAL_DARK, root, mat, 0.008, 1)

    # Emblema de la colonia en placa (crest.py) en las dos caras de las ventanas de brasa (este y oeste),
    # sobre la arcilla, entre los dos flejes (César los quiere ahí aunque el naranja se parezca: el marco
    # gris los separa). La cara se inclina hacia dentro al subir: el emblema se inclina con ella.
    z = 1.65
    slope = 0.13 / 0.55
    apothem = (0.71 - slope * (z - 1.4)) * math.cos(math.radians(30))
    for side, sx in (("east", 1.0), ("west", -1.0)):
        horizontal = Vector((sx, 0.0, 0.0))
        normal = (horizontal + Vector((0.0, 0.0, slope * math.cos(math.radians(30))))).normalized()
        crest.add_crest(finish, root, mat, horizontal * apothem + Vector((0.0, 0.0, z)), normal, scale=0.7,
                        style="plate", frame_depth=0.03, embed=0.02, prefix="crest_" + side)


build()
