# Puerto estándar de cinta (B3, D-079). Genera en la escena abierta dos objetos, «port_input» y
# «port_output», iguales salvo la flecha: verde y hacia dentro (entrada) o ámbar y hacia fuera (salida).
# Convenciones: el puerto se modela en el lado NORTE (+Y) de una casilla de 1 m. El origen es el centro
# de la casilla, a ras de suelo, así que Godot solo tiene que ponerlo en el centro de la casilla del
# puerto y girarlo según su lado. La cara exterior queda a ras del borde de la casilla (y = 0,5).
#
# Uso: Editor de texto de Blender → abrir → Alt+P. Si los objetos ya existen, los rehace.
# Dónde tocar: las medidas están en las constantes de abajo; los colores, como (fila, columna).

import bpy
import bmesh
import math
from mathutils import Matrix, Vector

PALETTE = 64
SWATCH = 8
TEXTURE = "//../../assets/textures/palette.png"

WIDTH = 0.8            # ancho del marco (X)
DEPTH = 0.25           # fondo del marco (Y): de y = 0,25 a y = 0,5
HEIGHT = 0.6           # alto del marco (Z)
MOUTH_W = 0.31         # media anchura de la boca: 0,62 m de punta a punta (hexágono alargado)
MOUTH_H = 0.19         # media altura de la boca: 0,38 m entre los lados planos de arriba y abajo
# Cinta estándar: banda de unos 0,55 m de ancho, que entra en la boca con holgura.
HEX_Z = 0.30           # centro de la boca: base plana a 0,11 m, sobre la cinta (0,1 m)
OUTER_Y = 0.485        # cara exterior, 1,5 cm dentro del borde: los remaches llegan justo al borde (0,5)

FRAME = (5, 3)         # gris del Nexo
MOUTH = (5, 6)         # interior oscuro
ARROW_IN = (2, 2)      # verde: entra
ARROW_OUT = (6, 2)     # ámbar: sale
RIVET = (5, 5)         # remaches, gris oscuro
BAND_TEXTURE = "//../../assets/textures/belt_band.png"
BAND_TEX_PER_M = 2     # repeticiones de la textura de la banda por metro: el TEX_PER_M de conveyor_blockout.py
TONGUE_SHELL = (5, 3)  # artesa de la lengüeta: el mismo gris que el marco y que la cinta


def swatch_uv(row: int, col: int) -> Vector:
    return Vector(((col * SWATCH + SWATCH / 2) / PALETTE, 1.0 - (row * SWATCH + SWATCH / 2) / PALETTE))


def get_band_material():
    # El mismo material «belt_band» que la cinta (en Godot, el .tres compartido que hace avanzar la banda).
    mat = bpy.data.materials.get("belt_band")
    if mat is not None:
        return mat
    img = bpy.data.images.load(BAND_TEXTURE, check_existing=True)
    mat = bpy.data.materials.new("belt_band")
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial"); out.location = (300, 0)
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled"); bsdf.location = (0, 0)
    tex = nt.nodes.new("ShaderNodeTexImage"); tex.location = (-350, 0)
    tex.image = img
    tex.interpolation = "Closest"
    bsdf.inputs["Roughness"].default_value = 0.9
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    return mat


def get_palette_material():
    mat = bpy.data.materials.get("palette")
    if mat is not None:
        return mat
    img = bpy.data.images.load(TEXTURE, check_existing=True)
    mat = bpy.data.materials.new("palette")
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial"); out.location = (300, 0)
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled"); bsdf.location = (0, 0)
    tex = nt.nodes.new("ShaderNodeTexImage"); tex.location = (-350, 0)
    tex.image = img
    tex.interpolation = "Closest"
    bsdf.inputs["Roughness"].default_value = 0.8
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    return mat


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


def hex_prism(bm, w: float, h: float, y0: float, y1: float, cz: float) -> list:
    # Prisma hexagonal ALARGADO a lo largo de Y: puntas a ±w en X, lados planos arriba y abajo a ±h.
    # Las esquinas de arriba y abajo se retiran h · tan 30° de las puntas, como en un hexágono regular.
    k = w - h * math.tan(math.radians(30))
    outline = [(w, 0.0), (k, h), (-k, h), (-w, 0.0), (-k, -h), (k, -h)]
    front, back = [], []
    for (ox, oz) in outline:
        x, z = ox, cz + oz
        back.append(bm.verts.new((x, y0, z)))
        front.append(bm.verts.new((x, y1, z)))
    faces = [bm.faces.new(back), bm.faces.new(list(reversed(front)))]
    for i in range(6):
        j = (i + 1) % 6
        faces.append(bm.faces.new((back[i], back[j], front[j], front[i])))
    return faces


def build_port(name: str, inward: bool, arrow_color: tuple, mat) -> None:
    for child_name in ("belt_tongue_" + name.split("_")[-1],):
        old_child = bpy.data.objects.get(child_name)
        if old_child is not None:
            child_mesh = old_child.data
            bpy.data.objects.remove(old_child, do_unlink=True)
            if child_mesh is not None and child_mesh.users == 0:
                bpy.data.meshes.remove(child_mesh)
    old = bpy.data.objects.get(name)
    if old is not None:
        old_mesh = old.data
        bpy.data.objects.remove(old, do_unlink=True)
        if old_mesh is not None and old_mesh.users == 0:
            bpy.data.meshes.remove(old_mesh)

    # 1) Marco: caja con un túnel hexagonal (booleana), y después bisel por ángulo.
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=(WIDTH, DEPTH, HEIGHT), verts=bm.verts)
    bmesh.ops.translate(bm, vec=(0.0, OUTER_Y - DEPTH / 2, HEIGHT / 2), verts=bm.verts)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh); bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)

    cutter_bm = bmesh.new()
    hex_prism(cutter_bm, MOUTH_W, MOUTH_H, OUTER_Y - DEPTH - 0.05, OUTER_Y + 0.05, HEX_Z)
    bmesh.ops.recalc_face_normals(cutter_bm, faces=cutter_bm.faces)
    cutter_mesh = bpy.data.meshes.new("port_cutter")
    cutter_bm.to_mesh(cutter_mesh); cutter_bm.free()
    cutter = bpy.data.objects.new("port_cutter", cutter_mesh)
    bpy.context.collection.objects.link(cutter)

    boolean = obj.modifiers.new("hole", "BOOLEAN")
    boolean.operation = "DIFFERENCE"
    boolean.object = cutter
    bevel = obj.modifiers.new("bevel", "BEVEL")
    bevel.width = 0.015
    bevel.segments = 1   # un solo segmento: compensa los remaches (presupuesto de triángulos)
    bevel.limit_method = "ANGLE"
    bevel.angle_limit = math.radians(30)
    deps = bpy.context.evaluated_depsgraph_get()
    evaluated = obj.evaluated_get(deps)
    new_mesh = bpy.data.meshes.new_from_object(evaluated)
    obj.modifiers.clear()
    old_mesh = obj.data
    obj.data = new_mesh
    bpy.data.meshes.remove(old_mesh)
    new_mesh.name = name  # después de borrar la vieja, para que no quede «port_input.001»
    bpy.data.objects.remove(cutter, do_unlink=True)
    bpy.data.meshes.remove(cutter_mesh)

    # 2) Añadidos: tapón oscuro al fondo del túnel (no se ve a través) y flecha encima.
    bm = bmesh.new()
    bm.from_mesh(new_mesh)
    plug = hex_prism(bm, MOUTH_W + 0.01, MOUTH_H + 0.01, OUTER_Y - DEPTH, OUTER_Y - DEPTH + 0.03, HEX_Z)
    # Flecha (vista desde arriba) apuntando a +Y; si es de entrada, se refleja para apuntar a −Y.
    y_mid = OUTER_Y - DEPTH / 2
    outline = [(-0.05, -0.095), (0.05, -0.095), (0.05, 0.0), (0.14, 0.0), (0.0, 0.095), (-0.14, 0.0), (-0.05, 0.0)]
    sign = -1.0 if inward else 1.0
    z0, z1 = HEIGHT, HEIGHT + 0.025
    low = [bm.verts.new((x, y_mid + sign * y, z0)) for x, y in outline]
    high = [bm.verts.new((x, y_mid + sign * y, z1)) for x, y in outline]
    arrow = [bm.faces.new(low), bm.faces.new(high)]
    for i in range(len(outline)):
        j = (i + 1) % len(outline)
        arrow.append(bm.faces.new((low[i], low[j], high[j], high[i])))
    # Remaches: cuatro hexagonales en las esquinas de la cara exterior (el toque de juguete).
    rivets = []
    for rx in (-WIDTH / 2 + 0.06, WIDTH / 2 - 0.06):
        for rz in (0.06, HEIGHT - 0.06):
            rivets.extend(hex_rivet((rx, OUTER_Y, rz), (0, 1, 0), 0.018, 0.03, bm=bm))  # medio hundidos
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)

    # 3) Colores: túnel y tapón oscuros, flecha de su color, el resto del marco gris.
    uv = bm.loops.layers.uv.active or bm.loops.layers.uv.new("UVMap")
    arrow_set, plug_set, rivet_set = set(arrow), set(plug), set(rivets)
    for f in bm.faces:
        color = FRAME
        c = f.calc_center_median()
        in_tunnel = abs(c.x) < MOUTH_W + 0.02 and abs(c.z - HEX_Z) < MOUTH_H + 0.03 and abs(f.normal.y) < 0.5
        if f in plug_set or in_tunnel:
            color = MOUTH
        if f in plug_set and f.normal.y < -0.5:
            # La cara de DETRÁS del tapón va del gris del marco: así, si el cuerpo de la máquina no tapa
            # del todo el fondo del puerto, no asoma un hexágono oscuro por detrás (César, caja logística).
            color = FRAME
        if f in arrow_set:
            color = arrow_color
        if f in rivet_set:
            color = RIVET
        target = swatch_uv(*color)
        for loop in f.loops:
            loop[uv].uv = target
    bm.to_mesh(new_mesh); bm.free()

    new_mesh.materials.clear()
    new_mesh.materials.append(mat)
    for p in new_mesh.polygons:
        p.use_smooth = True
    new_mesh.set_sharp_from_angle(angle=math.radians(30))
    tris = sum(len(p.vertices) - 2 for p in new_mesh.polygons)
    tris += build_tongue(obj, mat)
    print(name, "triángulos (con lengüeta):", tris)


def build_tongue(port_obj, mat) -> int:
    # Lengüeta de cinta dentro de la boca: el mismo perfil de MEDIO HEXÁGONO que la cinta (artesa gris)
    # y su misma banda animada (material «belt_band»), para que la cinta parezca seguir dentro de la máquina. Godot la
    # muestra SOLO si el puerto está conectado. Se llama «belt_tongue_input» o «belt_tongue_output».
    # Los números del perfil son los de conveyor_blockout.py: si cambian allí, cambiarlos aquí.
    band_half, band_top, wall_x, wall_z, lip, bottom = 0.19, 0.125, 0.27, 0.23, 0.06, (0.28, 0.06)
    name = "belt_tongue_" + port_obj.name.split("_")[-1]
    y0, y1 = OUTER_Y - DEPTH + 0.03, OUTER_Y + 0.015   # del tapón del fondo al borde de la casilla
    profile = [(-wall_x - lip, wall_z), (-wall_x, wall_z), (-band_half, band_top - 0.01), (band_half, band_top - 0.01),
               (wall_x, wall_z), (wall_x + lip, wall_z), (bottom[0], bottom[1]), (-bottom[0], bottom[1])]
    bm = bmesh.new()
    back = [bm.verts.new((x, y0, z)) for x, z in profile]
    front = [bm.verts.new((x, y1, z)) for x, z in profile]
    shell = [bm.faces.new(back), bm.faces.new(list(reversed(front)))]
    for i in range(len(profile)):
        j = (i + 1) % len(profile)
        shell.append(bm.faces.new((back[i], back[j], front[j], front[i])))
    shell = set(shell)
    bmesh.ops.recalc_face_normals(bm, faces=list(shell))
    # Banda: una sola cara hacia arriba con el material «belt_band» de la cinta, para que avance con ella.
    band = bm.faces.new([bm.verts.new((-band_half, y0, band_top)), bm.verts.new((band_half, y0, band_top)),
                         bm.verts.new((band_half, y1, band_top)), bm.verts.new((-band_half, y1, band_top))])
    band.normal_update()
    if band.normal.z < 0.0:
        band.normal_flip()
    band.material_index = 1
    is_input = name.endswith("input")
    uv = bm.loops.layers.uv.new("UVMap")
    for f in bm.faces:
        if f is band:
            # Igual que la banda de la cinta: u a lo ancho, v a lo largo en el sentido de avance, 2 por metro,
            # con v entero en el borde de la casilla (y = 0,5) para que los chevrones casen con la cinta.
            # Entrada: los ítems van hacia dentro (−Y); salida: hacia fuera (+Y).
            for loop in f.loops:
                co = loop.vert.co
                if is_input:
                    loop[uv].uv = Vector(((band_half - co.x) / (2 * band_half), (0.5 - co.y) * BAND_TEX_PER_M))
                else:
                    loop[uv].uv = Vector(((co.x + band_half) / (2 * band_half), (co.y - 0.5) * BAND_TEX_PER_M))
            continue
        target = swatch_uv(*TONGUE_SHELL)
        for loop in f.loops:
            loop[uv].uv = target
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    mesh.materials.append(mat)
    mesh.materials.append(get_band_material())
    tongue = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(tongue)
    tongue.parent = port_obj
    for p in mesh.polygons:
        p.use_smooth = True
    mesh.set_sharp_from_angle(angle=math.radians(30))
    return sum(len(p.vertices) - 2 for p in mesh.polygons)


def build() -> None:
    cube = bpy.data.objects.get("Cube")
    if cube is not None:
        bpy.data.objects.remove(cube, do_unlink=True)
    mat = get_palette_material()
    build_port("port_input", True, ARROW_IN, mat)
    build_port("port_output", False, ARROW_OUT, mat)


build()
