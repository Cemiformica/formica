# Carbonera (B3.7). 3×3. Horno de colmena tradicional: zócalo octogonal de piedra (v2: base y gargantas en
# una sola pieza, con caras planas para los puertos) y cúpula de arcilla con hiladas marcadas, un
# respiradero hueco arriba y tres pequeños alrededor (conductos con el fondo oscuro) (de cada uno sale humo blanco grisáceo, como en
# las carboneras reales), rendijas de brasa anchas al sur y al norte, sillares desiguales y una pila de
# troncos ordenados en el suelo al noroeste. Estilo rudimentario de Isla Alba (piedra, arcilla y madera; nada del Nexo).
# Puertos centrados (César): entrada de madera al oeste y salida de carbón al este, en las casillas
# centrales, pegados a las caras planas del zócalo (x = ±1,25). Los puertos los pone Godot; aquí solo
# hay copias de referencia (colección «ref_ports», no se exporta).
# Convenciones: norte = +Y, este = +X, origen en el centro de la huella a ras de suelo, x, y ∈ [−1,5, 1,5].
#
# Nodos para Godot: ember_window_south / ember_window_north (brasa), smoke_origin_top / smoke_origin_vent_0…2 (humo).
#
# Uso: Editor de texto de Blender → abrir → Alt+P. Si ya existe «charcoal_kiln», lo borra y lo rehace.
# Dónde tocar: las medidas están en build(); cada pieza dice su color como (fila, columna).

import bpy
import bmesh
import math
from mathutils import Matrix, Vector

PALETTE = 64
SWATCH = 8
ROOT = "charcoal_kiln"
BEVEL = 0.02


def swatch_uv(row: int, col: int) -> Vector:
    return Vector(((col * SWATCH + SWATCH / 2) / PALETTE, 1.0 - (row * SWATCH + SWATCH / 2) / PALETTE))


def get_materials():
    base = bpy.data.materials.get("palette")
    if base is None:
        img = bpy.data.images.load("//../../assets/textures/palette.png", check_existing=True)
        base = bpy.data.materials.new("palette")
        base.use_nodes = True
        nt = base.node_tree
        nt.nodes.clear()
        out = nt.nodes.new("ShaderNodeOutputMaterial"); out.location = (300, 0)
        bsdf_new = nt.nodes.new("ShaderNodeBsdfPrincipled"); bsdf_new.location = (0, 0)
        tex_new = nt.nodes.new("ShaderNodeTexImage"); tex_new.location = (-350, 0)
        tex_new.image = img
        tex_new.interpolation = "Closest"
        bsdf_new.inputs["Roughness"].default_value = 0.8
        nt.links.new(tex_new.outputs["Color"], bsdf_new.inputs["Base Color"])
        nt.links.new(bsdf_new.outputs["BSDF"], out.inputs["Surface"])
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
           segments: int = 2, painted: bool = False):
    # Bisel primero, color después (regla de la guía). Los biseles pequeños (≤ 1,2 cm) llevan un solo
    # segmento: no se nota la diferencia y ahorra muchos triángulos (presupuesto, guía de arte §4).
    if bevel <= 0.012:
        segments = 1
    if bevel > 0.0:
        bmesh.ops.bevel(bm, geom=list(bm.edges), offset=bevel, segments=segments, affect="EDGES",
                        profile=0.5, clamp_overlap=True)
    if not painted:
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
# Puertos de la carbonera (centrados, regla de César: 1 entrada y 1 salida → ancho impar): madera por la
# casilla central oeste y carbón por la central este. (objeto, centro de la casilla, giro en Z).
PORTS = [
    ("port_input", (-1.0, 0.0), 90.0),
    ("port_output", (1.0, 0.0), -90.0),
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


def empty(name: str, location, parent, size: float = 0.05):
    obj = bpy.data.objects.new(name, None)
    obj.empty_display_type = "SPHERE"
    obj.empty_display_size = size
    obj.location = location
    obj.parent = parent
    bpy.context.collection.objects.link(obj)
    return obj


def log_bm(length: float, r: float, center, bark, bark_dark, sapwood, ring_color, heart) -> bmesh.types.BMesh:
    # Tronco tumbado a lo largo de X: corteza de 8 caras en dos tonos (vetas pintadas) y, en cada corte,
    # tres anillos concéntricos (albura clara, anillo y corazón).
    bm = prism(8, r, r, -length / 2, length / 2, angle=math.radians(11))
    uv = bm.loops.layers.uv.new("UVMap")
    caps = [f for f in bm.faces if len(f.verts) == 8]
    sides = [f for f in bm.faces if f not in caps]
    for i, f in enumerate(sides):
        for loop in f.loops:
            loop[uv].uv = swatch_uv(*(bark if i % 3 else bark_dark))
    for cap in caps:
        for loop in cap.loops:
            loop[uv].uv = swatch_uv(*sapwood)
        ring_faces = bmesh.ops.inset_individual(bm, faces=[cap], thickness=r * 0.22, depth=-0.004)["faces"]
        for f in ring_faces:
            for loop in f.loops:
                loop[uv].uv = swatch_uv(*sapwood)
        inner = bmesh.ops.inset_individual(bm, faces=[cap], thickness=r * 0.3, depth=-0.003)["faces"]
        for f in inner:
            for loop in f.loops:
                loop[uv].uv = swatch_uv(*ring_color)
        for loop in cap.loops:
            loop[uv].uv = swatch_uv(*heart)
    bmesh.ops.rotate(bm, cent=(0, 0, 0), matrix=Matrix.Rotation(math.radians(90), 3, "Y"), verts=bm.verts)
    bmesh.ops.translate(bm, vec=Vector(center), verts=bm.verts)
    return bm


def build() -> None:
    clear_previous()
    mat, glow = get_materials()
    root = bpy.data.objects.new(ROOT, None)
    root.empty_display_type = "PLAIN_AXES"
    bpy.context.collection.objects.link(root)

    STONE, STONE_DARK, STONE_DEEP = (1, 2), (1, 4), (1, 5)
    STONE_A, STONE_B = (1, 3), (1, 5)
    CLAY, CLAY_DARK, CLAY_DEEP = (4, 2), (4, 3), (4, 4)
    WOOD, WOOD_DARK, WOOD_END = (0, 3), (0, 5), (0, 2)
    METAL_DARK = (5, 4)
    EMBER = (6, 3)
    SIDES = 12

    MOUTH = (5, 6)          # interior oscuro de los conductos (como la boca de los puertos)
    BARK, BARK_DARK = (0, 5), (0, 6)
    SAPWOOD, HEART_RING, HEART = (0, 1), (0, 2), (0, 3)
    BASE_H = 0.72           # alto del zócalo: más que los puertos (0,6 m), para darles una cara plana
    APOTHEM = 1.25          # caras planas a x, y = ±1,25: ahí se pega la cara de dentro de cada puerto
    LIFT = 0.3              # la cúpula sube lo que ha crecido el zócalo

    # --- Zócalo de piedra octogonal (base y «gargantas» en una sola pieza, César) ---
    oct_r = APOTHEM / math.cos(math.radians(22.5))
    finish("base", prism(8, oct_r, oct_r, 0.0, BASE_H, angle=math.radians(22.5)), STONE, root, mat, 0.03)
    finish("base_cap", prism(8, oct_r - 0.02, oct_r - 0.06, BASE_H, BASE_H + 0.06, angle=math.radians(22.5)), STONE_DEEP,
           root, mat, 0.012)
    # Sillares que sobresalen, de tamaños, alturas y tonos distintos, para que la base se vea desigual
    # (César). Van en las caras sur, norte y diagonales; las este y oeste llevan los puertos.
    # (ángulo de la cara, desplazamiento a lo largo de la cara, z, ancho, alto, cuánto sobresale)
    stones = [
        (-90, -0.38, 0.16, 0.26, 0.18, 0.03), (-90, 0.36, 0.22, 0.3, 0.2, 0.02), (-90, 0.02, 0.3, 0.18, 0.12, 0.025),
        (90, -0.34, 0.24, 0.28, 0.22, 0.025), (90, 0.3, 0.14, 0.34, 0.16, 0.03), (90, 0.02, 0.36, 0.16, 0.1, 0.02),
        (45, -0.25, 0.18, 0.4, 0.2, 0.03), (45, 0.22, 0.48, 0.3, 0.18, 0.02), (45, 0.3, 0.14, 0.2, 0.14, 0.025),
        (135, 0.2, 0.2, 0.36, 0.22, 0.025), (135, -0.28, 0.5, 0.26, 0.16, 0.03), (135, -0.1, 0.12, 0.16, 0.1, 0.02),
        (225, -0.18, 0.22, 0.38, 0.2, 0.03), (225, 0.26, 0.46, 0.28, 0.2, 0.02), (225, 0.3, 0.16, 0.18, 0.12, 0.025),
        (315, 0.22, 0.17, 0.34, 0.2, 0.025), (315, -0.24, 0.47, 0.3, 0.18, 0.03), (315, -0.3, 0.14, 0.16, 0.12, 0.02),
    ]
    tones = [STONE_A, STONE_B, STONE_DARK]
    for i, (deg, along, z, w, h, out) in enumerate(stones):
        a = math.radians(deg)
        n = Vector((math.cos(a), math.sin(a), 0.0))
        t = Vector((-math.sin(a), math.cos(a), 0.0))
        block = box((w, 0.04 + out, h), (0.0, 0.0, 0.0))
        bmesh.ops.rotate(block, cent=(0, 0, 0), matrix=Matrix.Rotation(a + math.pi / 2, 3, "Z"), verts=block.verts)
        pos = n * (APOTHEM + out / 2 - 0.01) + t * along
        bmesh.ops.translate(block, vec=(pos.x, pos.y, z), verts=block.verts)
        finish("stone_block_%d" % i, block, tones[i % 3], root, mat, 0.01, 1)

    # --- Cúpula de arcilla: troncos de cono apilados, con hiladas marcadas ---
    profile = [(1.1, 0.48), (1.06, 0.85), (0.94, 1.2), (0.74, 1.5), (0.48, 1.74), (0.24, 1.86)]
    profile = [(r, z + LIFT) for r, z in profile]
    for k in range(len(profile) - 1):
        (r0, z0), (r1, z1) = profile[k], profile[k + 1]
        finish("dome_%d" % k, prism(SIDES, r0, r1, z0, z1), CLAY if k % 2 == 0 else CLAY_DARK, root, mat, 0.0)
        finish("course_%d" % k, ring(SIDES, r1 - 0.01, r1 + 0.025, z1 - 0.02, z1 + 0.02), CLAY_DEEP, root, mat, 0.0)
    # Respiradero de arriba: un conducto hueco con el fondo oscuro (César), como la boca de los puertos.
    top = profile[-1][1]
    finish("top_vent", ring(SIDES, 0.13, 0.21, top, top + 0.18), CLAY_DARK, root, mat, 0.0)
    finish("top_vent_hole", prism(SIDES, 0.135, 0.135, top - 0.02, top + 0.06), MOUTH, root, mat, 0.0)
    empty("smoke_origin_top", (0.0, 0.0, top + 0.2), root)
    # Tres respiraderos pequeños alrededor: tubitos huecos de arcilla con el fondo oscuro.
    for i, deg in enumerate((60, 180, 300)):
        a = math.radians(deg)
        r, z = 0.84, 1.36 + LIFT
        tilt = Matrix.Rotation(a, 4, "Z") @ Matrix.Rotation(math.radians(40), 4, "Y")
        place = Matrix.Translation((r * math.cos(a), r * math.sin(a), z)) @ tilt
        tube = ring(8, 0.045, 0.08, 0.0, 0.17)
        bmesh.ops.transform(tube, matrix=place, verts=tube.verts)
        finish("vent_%d" % i, tube, CLAY_DEEP, root, mat, 0.0)
        # Raíz maciza del tubo, metida en la cúpula: cierra el hueco que quedaba por debajo (César).
        root_bm = prism(8, 0.08, 0.08, -0.16, 0.002)
        bmesh.ops.transform(root_bm, matrix=place, verts=root_bm.verts)
        finish("vent_root_%d" % i, root_bm, CLAY_DEEP, root, mat, 0.0)
        hole = prism(8, 0.05, 0.05, -0.05, 0.11)
        bmesh.ops.transform(hole, matrix=place, verts=hole.verts)
        finish("vent_hole_%d" % i, hole, MOUTH, root, mat, 0.0)
        tip = place @ Vector((0.0, 0.0, 0.2))
        empty("smoke_origin_vent_%d" % i, tuple(tip), root, 0.03)

    # --- Rendijas de brasa anchas y hundidas en las caras sur y norte del zócalo (César) ---
    for side, sy in (("south", -1.0), ("north", 1.0)):
        cut_recess(bpy.data.objects["base"], (0.62, 0.1, 0.09), (0.0, sy * APOTHEM, 0.6), STONE_DEEP)
        finish("ember_window_" + side, box((0.6, 0.01, 0.09), (0.0, sy * (APOTHEM - 0.035), 0.6)), EMBER, root, glow, 0.0)

    # --- Pila de troncos al noroeste: corteza con vetas pintadas y anillos en los cortes (César) ---
    # Leñero ordenado en el suelo de la esquina noroeste (César), paralelo a la cara diagonal del zócalo:
    # dos capas de troncos bien alineados (3 abajo, 2 arriba), con largos y grosores algo distintos para
    # que no parezcan copias.
    out = Vector((-1.0, 1.0, 0.0)).normalized()     # hacia la esquina
    along = Vector((1.0, 1.0, 0.0)).normalized()    # paralelo a la cara diagonal
    yaw = math.atan2(along.y, along.x)              # los troncos se modelan a lo largo de X
    center = out * 1.55
    # (desplazamiento hacia fuera, capa, largo, radio)
    logs = [(-0.15, 0, 0.56, 0.075), (0.0, 0, 0.52, 0.072), (0.15, 0, 0.55, 0.075),
            (-0.075, 1, 0.5, 0.07), (0.075, 1, 0.54, 0.072)]
    for i, (off, layer, length, r) in enumerate(logs):
        z = 0.075 + layer * 0.13
        pos = center + out * off
        bm = log_bm(length, r, (0.0, 0.0, 0.0), BARK, BARK_DARK, SAPWOOD, HEART_RING, HEART)
        bmesh.ops.rotate(bm, cent=(0, 0, 0), matrix=Matrix.Rotation(yaw, 3, "Z"), verts=bm.verts)
        bmesh.ops.translate(bm, vec=(pos.x, pos.y, z), verts=bm.verts)
        finish("log_%d" % i, bm, None, root, mat, 0.0, painted=True)

    tris = 0
    for child in root.children_recursive:
        if child.type == "MESH":
            tris += sum(len(p.vertices) - 2 for p in child.data.polygons)
    print("carbonera: piezas:", len(root.children), "triángulos:", tris)
    place_reference_ports()


build()
