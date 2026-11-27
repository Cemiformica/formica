# Rocas de varios tamaños (C5.6, D-179; sesión 30). Tres familias con papeles distintos (César):
#   - pebbles_N: grupitos de 3 a 6 guijarros de 10–30 cm, de la paleta. Detalle del suelo, sin choque. Godot los dibuja
#     todos juntos (MultiMesh).
#   - rock_m_N: rocas medianas de 0,45–0,9 m de alto que ocupan 1 casilla, más anchas que altas, con choque. Rompen las lomas y las orillas.
#   - boulder_N: peñascos de 1,3–2 m de alto (2 × 2 o 3 × 3 casillas), macizos, con choque. Puntos de referencia que César pinta en el mapa.
#     Dos con historia: uno partido en dos (boulder_split) y otro con un hexágono tallado medio borrado (boulder_carved),
#     que anticipa las ruinas de la colonia antigua (D-159).
# Las medianas y los peñascos son losas apiladas, como las repisas de los acantilados, y llevan el material «terrain_rock»:
# en Godot es el shader del terreno con `object_mode` (D-175), así tienen los mismos estratos y tonos que los acantilados.
# El reborde de guijarros del pie y el hexágono tallado, con la paleta. Sin musgo: el shader del terreno ya pone hierba en las
# caras de arriba de cada losa, como en el borde de los acantilados (César).
# Convenciones: origen de cada pieza en el centro de su huella, a ras de suelo; cada pieza bajo su vacío raíz. Las losas de
# abajo se hunden SINK en el suelo para que no se vea la costura con el terreno.
#
# Uso: con art/props/rocks.blend abierto, Editor de texto → abrir → Alt+P (o exec). Borra y rehace todas las piezas de PIECES.
# Exportar: export_hierarchy("rocks", "//../../assets/models/props/rocks.glb") (export_glb.py).
# Dónde tocar: PIECES (qué variantes hay, con qué semilla y medidas) y las funciones de cada familia.

import bpy
import bmesh
import math
import random
from mathutils import Matrix, Vector

PALETTE = 64
SWATCH = 8
TEXTURE = "//../../assets/textures/palette.png"
SURFACE = "//../../assets/textures/palette_surface.png"
ROCK_MATERIAL = "terrain_rock"   # en Godot, `assets/materials/terrain_rock.tres` (el shader del terreno)

STONE, STONE_DARK, STONE_LIGHT = (1, 4), (1, 5), (1, 3)
CARVE = (1, 6)

ROOT = "rocks"
SINK = 0.12          # lo que se hunden las losas de abajo
SPACING = 5.0        # separación entre piezas en el .blend (solo para verlas)

# (nombre, familia, semilla, medida): la medida es el alto aproximado (m) en medianas y peñascos, y el número de
# guijarros en los grupitos. La huella en casillas va en FOOTPRINT.
PIECES = [
    ("pebbles_0", "pebbles", 3, 3),
    ("pebbles_1", "pebbles", 8, 5),
    ("pebbles_2", "pebbles", 14, 6),
    ("rock_m_0", "medium", 21, 0.45),
    ("rock_m_1", "medium", 34, 0.6),
    ("rock_m_2", "medium", 47, 0.75),
    ("rock_m_3", "medium", 52, 0.9),
    ("boulder_0", "boulder", 61, 1.3),
    ("boulder_1", "boulder", 75, 2.0),
    ("boulder_split", "split", 88, 1.5),
    ("boulder_carved", "carved", 93, 1.5),
]
FOOTPRINT = {"medium": 1.0, "boulder": 3.0, "split": 3.0, "carved": 2.0}
# Los peñascos de 2,4 m caben en 2 × 2.
SMALL_BOULDER = 1.6


def swatch_uv(row: int, col: int) -> Vector:
    return Vector(((col * SWATCH + SWATCH / 2) / PALETTE, 1.0 - (row * SWATCH + SWATCH / 2) / PALETTE))


def get_palette():
    mat = bpy.data.materials.get("palette") or bpy.data.materials.new("palette")
    img = bpy.data.images.load(TEXTURE, check_existing=True)
    surface = bpy.data.images.load(SURFACE, check_existing=True)
    surface.colorspace_settings.name = "Non-Color"
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = img
    tex.interpolation = "Closest"
    stex = nt.nodes.new("ShaderNodeTexImage")
    stex.image = surface
    stex.interpolation = "Closest"
    sep = nt.nodes.new("ShaderNodeSeparateColor")
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    nt.links.new(stex.outputs["Color"], sep.inputs["Color"])
    nt.links.new(sep.outputs["Red"], bsdf.inputs["Metallic"])
    nt.links.new(sep.outputs["Green"], bsdf.inputs["Roughness"])
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    return mat


def get_rock_material():
    # En Blender, solo para verlo: estratos de 1,1 m en tres tonos rojizos con el borde ondulado, como `terrain.gdshader`.
    # En Godot lo sustituye el shader del terreno.
    mat = bpy.data.materials.get(ROCK_MATERIAL) or bpy.data.materials.new(ROCK_MATERIAL)
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Roughness"].default_value = 0.9
    coord = nt.nodes.new("ShaderNodeNewGeometry")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    noise = nt.nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 1.3
    wobble = nt.nodes.new("ShaderNodeMath"); wobble.operation = "MULTIPLY_ADD"
    wobble.inputs[1].default_value = 0.25
    wobble.inputs[2].default_value = -0.12
    add = nt.nodes.new("ShaderNodeMath"); add.operation = "ADD"
    div = nt.nodes.new("ShaderNodeMath"); div.operation = "DIVIDE"; div.inputs[1].default_value = 1.1
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.interpolation = "CONSTANT"
    els = ramp.color_ramp.elements
    els[0].position = 0.0; els[0].color = (0.42, 0.17, 0.10, 1)
    els[1].position = 0.33; els[1].color = (0.55, 0.25, 0.14, 1)
    e = els.new(0.66); e.color = (0.35, 0.14, 0.09, 1)
    e = els.new(0.97); e.color = (0.18, 0.07, 0.05, 1)   # línea oscura entre capas
    frac = nt.nodes.new("ShaderNodeMath"); frac.operation = "FRACT"
    nt.links.new(coord.outputs["Position"], sep.inputs["Vector"])
    nt.links.new(coord.outputs["Position"], noise.inputs["Vector"])
    nt.links.new(noise.outputs["Fac"], wobble.inputs[0])
    nt.links.new(sep.outputs["Z"], add.inputs[0])
    nt.links.new(wobble.outputs[0], add.inputs[1])
    nt.links.new(add.outputs[0], div.inputs[0])
    nt.links.new(div.outputs[0], frac.inputs[0])
    nt.links.new(frac.outputs[0], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    return mat


def finish(name, bm, parent, material, color=None):
    if color is not None:
        uv = bm.loops.layers.uv.new("UVMap")
        for f in bm.faces:
            for loop in f.loops:
                loop[uv].uv = swatch_uv(*color)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
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


def empty(name, parent=None, location=(0, 0, 0)):
    obj = bpy.data.objects.new(name, None)
    obj.empty_display_size = 0.3
    obj.location = location
    obj.parent = parent
    bpy.context.collection.objects.link(obj)
    return obj


def hull(points):
    bm = bmesh.new()
    for p in points:
        bm.verts.new(p)
    bmesh.ops.convex_hull(bm, input=list(bm.verts))
    # Lo que no quedó en el casco (puntos de dentro) sobra.
    loose = [v for v in bm.verts if not v.link_faces]
    if loose:
        bmesh.ops.delete(bm, geom=loose, context="VERTS")
    return bm


def slab(center, rx, ry, z0, z1, rng, sides=None, taper=0.9, lean=(0.0, 0.0)):
    # Losa de roca: un polígono irregular abajo y otro más pequeño arriba, unidos por su casco. Cara de arriba casi plana
    # (un pelo inclinada), como las repisas de los acantilados.
    sides = sides or rng.randint(7, 9)
    cx, cy = center
    start = rng.uniform(0, math.tau)
    points = []
    tilt = (rng.uniform(-0.06, 0.06), rng.uniform(-0.06, 0.06))
    for i in range(sides):
        a = start + math.tau * i / sides + rng.uniform(-0.25, 0.25)
        k = rng.uniform(0.78, 1.08)
        x, y = math.cos(a) * rx * k, math.sin(a) * ry * k
        points.append((cx + x, cy + y, z0))
        kt = taper * rng.uniform(0.85, 1.05)
        top_z = z1 + x * tilt[0] + y * tilt[1] + rng.uniform(-0.03, 0.03) * (z1 - z0)
        points.append((cx + x * kt + lean[0], cy + y * kt + lean[1], top_z))
    return hull(points)


def pebble(center, radius, rng):
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=1, radius=radius)
    for v in bm.verts:
        v.co *= rng.uniform(0.82, 1.12)
    bmesh.ops.scale(bm, vec=(rng.uniform(1.0, 1.35), rng.uniform(0.8, 1.0), rng.uniform(0.45, 0.7)), verts=bm.verts)
    bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(rng.uniform(0, math.tau), 3, "Z"))
    bmesh.ops.translate(bm, vec=Vector(center) + Vector((0, 0, radius * 0.25)), verts=bm.verts)
    return bm


def moss_cap(center, radius, rng):
    # Media bola aplastada (el punto del centro del grabado).
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=1, radius=radius)
    bmesh.ops.scale(bm, vec=(1.0, rng.uniform(0.7, 0.9), 0.32), verts=bm.verts)
    for v in bm.verts:
        v.co *= rng.uniform(0.9, 1.1)
    bmesh.ops.translate(bm, vec=Vector(center), verts=bm.verts)
    return bm


def top_of(bm):
    return max(v.co.z for v in bm.verts)


def north_point(bm, z_min):
    # El vértice más al norte (+Y) por encima de `z_min`: ahí se pega el musgo.
    best = None
    for v in bm.verts:
        if v.co.z >= z_min and (best is None or v.co.y > best.y):
            best = v.co.copy()
    return best


# --- Familias ---

def stack(name, root, rock, palette, rng, height, half):
    # Losas apiladas de abajo arriba, cada una más pequeña y un poco desplazada. Devuelve las losas (bmesh) para el musgo.
    # Pocas losas y anchas (la primera prueba salían torres, César aún no las había visto): 2 en las medianas, 2–3 en los
    # peñascos; cada una apenas más pequeña que la de abajo.
    layers = 2 if height < 1.6 else 3
    z = -SINK
    rx, ry = half * rng.uniform(0.85, 1.0), half * rng.uniform(0.7, 0.9)
    off = Vector((0.0, 0.0))
    made = []
    for i in range(layers):
        h = (height + SINK) / layers * rng.uniform(0.85, 1.15)
        if i == layers - 1:
            h = height - z
        bm = slab((off.x, off.y), rx, ry, z, z + h, rng, lean=(rng.uniform(-0.05, 0.05) * h, rng.uniform(-0.05, 0.05) * h))
        made.append(bm.copy())
        finish("%s_layer_%d" % (name, i), bm, root, rock)
        z += h * rng.uniform(0.92, 0.98)   # un poco solapadas: sin rendijas
        rx *= rng.uniform(0.8, 0.92)
        ry *= rng.uniform(0.8, 0.92)
        off += Vector((rng.uniform(-0.1, 0.1), rng.uniform(-0.1, 0.1))) * half
    return made


def free_layers(layers):
    # Las copias de las losas ya no hacen falta (antes se usaban para el musgo, que se quitó: la hierba que pone el shader
    # del terreno en las caras de arriba ya hace ese papel, César).
    for bm in layers:
        bm.free()


def add_skirt(name, root, palette, rng, half, count):
    # Reborde de guijarros al pie: para que la roca no parezca posada encima.
    for i in range(count):
        a = rng.uniform(0, math.tau)
        d = half * rng.uniform(0.95, 1.2)
        finish("%s_skirt_%d" % (name, i), pebble((math.cos(a) * d, math.sin(a) * d, -0.03), rng.uniform(0.06, 0.13), rng),
               root, palette, rng.choice((STONE, STONE_DARK, STONE_LIGHT)))


def pebbles(name, root, palette, rock, rng, count):
    for i in range(int(count)):
        a = rng.uniform(0, math.tau)
        d = rng.uniform(0.0, 0.35)
        finish("%s_%d" % (name, i), pebble((math.cos(a) * d, math.sin(a) * d, -0.02), rng.uniform(0.05, 0.15), rng),
               root, palette, rng.choice((STONE, STONE_DARK, STONE_LIGHT)))


def medium(name, root, palette, rock, rng, height):
    half = 0.47
    layers = stack(name, root, rock, palette, rng, height, half)
    free_layers(layers)
    add_skirt(name, root, palette, rng, half, rng.randint(2, 4))


def boulder(name, root, palette, rock, rng, height):
    foot = 2.0 if height < SMALL_BOULDER else 3.0
    half = foot * 0.47
    layers = stack(name, root, rock, palette, rng, height, half)
    free_layers(layers)
    add_skirt(name, root, palette, rng, half, rng.randint(5, 8))


def split(name, root, palette, rock, rng, height):
    # Peñasco partido en dos: un bloque redondo y bajo con una grieta de norte a sur. Se hace el bloque entero y cada mitad
    # se queda con su lado (los vértices que pasan del plano de la grieta se aplastan contra él); la mitad del este está un
    # poco caída hacia fuera. En la grieta, Godot puede poner un arbolito o una mata.
    half = 1.35
    gap = 0.18
    lean = math.radians(7)
    for side, sx in (("w", -1.0), ("e", 1.0)):
        layer_rng = random.Random(77)   # las dos mitades salen del MISMO bloque: misma semilla
        z = -SINK
        rx, ry = half, half * 0.82
        made = []
        for i in range(2):
            h = (height + SINK) / 2 if i == 0 else height - z
            bm = slab((0.0, 0.0), rx, ry, z, z + h, layer_rng)
            for v in bm.verts:
                if v.co.x * sx < gap:
                    v.co.x = gap * sx
            if sx > 0:   # la mitad del este, caída hacia fuera girando sobre su borde de abajo
                pivot = Vector((half, 0.0, -SINK))
                bmesh.ops.rotate(bm, verts=bm.verts, cent=pivot, matrix=Matrix.Rotation(-lean, 3, "Y"))
            made.append(bm.copy())
            finish("%s_%s_layer_%d" % (name, side, i), bm, root, rock)
            z += h * 0.95
            rx *= 0.88
            ry *= 0.88
        free_layers(made)
    add_skirt(name, root, palette, rng, half, 7)
    # Guijarros caídos dentro de la grieta.
    for i in range(3):
        finish("%s_gap_%d" % (name, i), pebble((rng.uniform(0.0, 0.12), rng.uniform(-0.8, 0.8), 0.0), rng.uniform(0.07, 0.1), rng),
               root, palette, STONE_DARK)


def carved(name, root, palette, rock, rng, height):
    # Peñasco con el emblema de la colonia antigua GRABADO en la cara que más mira al sur (la que se ve al llegar): un
    # hexágono hundido 3 cm en la roca, con el fondo y las paredes del surco en piedra oscura, un trozo de un lado borrado,
    # una grieta que lo cruza y un punto en el centro. Se hace restando (Boolean exacto) un molde a la losa de abajo; el molde
    # lleva la paleta oscura y el Boolean pasa ese material a las caras del surco.
    boulder(name, root, palette, rock, rng, height)
    obj = bpy.data.objects["%s_layer_0" % name]
    # Cara sur plana para grabar: se corta la losa con un plano vertical, se quita lo de delante y se tapa el hueco. Así el
    # grabado va sobre una cara grande y plana y no dobla ninguna esquina.
    mesh = obj.data
    front = min(v.co.y for v in mesh.vertices) + 0.25
    bm = bmesh.new()
    bm.from_mesh(mesh)
    cut = bmesh.ops.bisect_plane(bm, geom=list(bm.verts) + list(bm.edges) + list(bm.faces), dist=1e-5,
                                 plane_co=(0.0, front, 0.0), plane_no=(0.0, -1.0, 0.0), clear_outer=True)
    bmesh.ops.holes_fill(bm, edges=[e for e in bm.edges if e.is_boundary], sides=0)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()
    mesh.update()
    normal = Vector((0.0, -1.0, 0.0))
    up = Vector((0.0, 0.0, 1.0))
    side = Vector((1.0, 0.0, 0.0))
    on_face = [v.co for v in mesh.vertices if abs(v.co.y - front) < 1e-3]
    xs = [v.x for v in on_face]
    zs = [v.z for v in on_face]
    width = min(max(xs) - min(xs), (max(zs) - max(min(zs), 0.0)) * 1.2)
    center = Vector(((max(xs) + min(xs)) * 0.5, front, (max(zs) + max(min(zs), 0.0)) * 0.5))
    outer = min(0.3, width * 0.32)
    inner = outer * 0.7
    depth, out = 0.03, 0.2

    def at(r, a, d):
        return center + side * (math.cos(a) * r) + up * (math.sin(a) * r) + normal * d

    def prism(face_points):
        # Prisma a lo largo de la normal: de `depth` dentro de la roca a `out` fuera.
        bm = bmesh.new()
        back = [bm.verts.new(p - normal * depth) for p in face_points]
        front = [bm.verts.new(p + normal * out) for p in face_points]
        n = len(face_points)
        bm.faces.new(back)
        bm.faces.new(list(reversed(front)))
        for i in range(n):
            j = (i + 1) % n
            bm.faces.new((back[i], back[j], front[j], front[i]))
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        return bm

    cutter = bmesh.new()
    pieces = []
    for i in range(6):
        a0 = math.radians(60 * i + 30)
        a1 = math.radians(60 * (i + 1) + 30)
        t1 = 0.4 if i == 3 else 1.0   # medio lado borrado
        a_end = a0 + (a1 - a0) * t1
        # Trapecio del lado (con un pelo de más para que se solapen en las esquinas).
        pts = [at(outer, a0, 0) - (at(outer, a_end, 0) - at(outer, a0, 0)).normalized() * 0.005, at(outer, a_end, 0),
               at(inner, a_end, 0), at(inner, a0, 0)]
        pieces.append(prism(pts))
    # Grieta que cruza el hexágono en diagonal, en zigzag.
    crack = [(-0.36, 0.30), (-0.12, 0.10), (-0.04, 0.14), (0.14, -0.08), (0.38, -0.26)]
    for (x0, y0), (x1, y1) in zip(crack, crack[1:]):
        k = outer / 0.27   # la grieta, a la medida del hexágono
        p0 = center + (side * x0 + up * y0) * k
        p1 = center + (side * x1 + up * y1) * k
        along = (p1 - p0).normalized()
        across = normal.cross(along).normalized() * 0.012
        pieces.append(prism([p0 - across - along * 0.01, p1 - across + along * 0.01, p1 + across + along * 0.01,
                             p0 + across - along * 0.01]))
    # Punto del centro: un hexágono pequeño.
    pieces.append(prism([at(outer * 0.19, math.radians(60 * k + 30), 0) for k in range(6)]))
    for bm in pieces:
        tmp = bpy.data.meshes.new("tmp")
        bm.to_mesh(tmp)
        bm.free()
        cutter.from_mesh(tmp)
        bpy.data.meshes.remove(tmp)
    cutter_obj = finish("%s_carve_cutter" % name, cutter, root, palette, CARVE)
    mod = obj.modifiers.new("carve", "BOOLEAN")
    mod.operation = "DIFFERENCE"
    mod.solver = "EXACT"
    mod.use_self = True
    mod.material_mode = "TRANSFER"
    mod.object = cutter_obj
    bpy.context.view_layer.objects.active = obj
    with bpy.context.temp_override(object=obj, active_object=obj):
        bpy.ops.object.modifier_apply(modifier=mod.name)
    bpy.data.objects.remove(cutter_obj, do_unlink=True)
    obj.data.set_sharp_from_angle(angle=math.radians(30))


BUILDERS = {"pebbles": pebbles, "medium": medium, "boulder": boulder, "split": split, "carved": carved}


def clear_previous():
    old = bpy.data.objects.get(ROOT)
    if old is not None:
        for obj in [old] + list(old.children_recursive):
            bpy.data.objects.remove(obj, do_unlink=True)
    for mesh in [m for m in bpy.data.meshes if m.users == 0]:
        bpy.data.meshes.remove(mesh)


def build():
    clear_previous()
    palette = get_palette()
    rock = get_rock_material()
    root = empty(ROOT)
    for index, (name, family, seed, size) in enumerate(PIECES):
        pivot = empty(name, root, ((index % 4) * SPACING, (index // 4) * SPACING, 0.0))
        BUILDERS[family](name, pivot, palette, rock, random.Random(seed), size)
    for name, _family, _seed, _size in PIECES:
        pivot = bpy.data.objects[name]
        tris = sum(len(p.vertices) - 2 for c in pivot.children_recursive if c.type == "MESH" for p in c.data.polygons)
        print(name, tris, "triángulos")


if __name__ == "__main__":
    build()
