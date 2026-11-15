# Emblema de la colonia de Mira (B3.7): hormiga vista desde arriba (abdomen, tórax y cabeza como tres
# hexágonos en fila, seis patas y dos antenas) sobre un hexágono naranja. Pieza común para todos los
# modelos que lo llevan (banco, arcón, horno, talador, rueda hidráulica, extractor). Guía de arte: el
# emblema va solo en máquinas clave, nunca en piezas que se repiten (cinta, poste, puertos).
#
# Dos versiones:
#   - "plate": placa en relieve con marco hexagonal gris del Nexo (banco, horno). `frame_depth` es lo que
#     sobresale el marco de la superficie; puede hundirse hacia atrás con `embed` para fundirse con una barra.
#   - "painted": casi a ras, sin marco, como una marca pintada en la carcasa (arcón, talador, rueda, extractor).
#
# Uso, desde un script de modelo (que ya tiene su propia función finish()):
#   import crest
#   crest.add_crest(finish, root, mat, location=(0, -0.36, 0.4), facing=(0, -1, 0), scale=0.75, style="painted")
# `location` es el centro del emblema SOBRE la superficie donde se monta; `facing`, hacia dónde mira (la
# normal de esa superficie). La cabeza de la hormiga apunta hacia arriba (+Z) en superficies verticales.
# A escala 1 mide 0,32 m de ancho con marco (0,26 m la placa naranja), como en el banco de trabajo.

import bmesh
import math
from mathutils import Matrix, Vector

ACCENT = (4, 2)
METAL_DARK = (5, 4)
METAL_DEEP = (5, 5)

FRAME_R = 0.16
PLATE_R = 0.128
PLATE_DEPTH = 0.02
ANT_DEPTH = 0.015
PAINT_PLATE_DEPTH = 0.008
PAINT_ANT_DEPTH = 0.008
# Tres hexágonos de la hormiga: (desplazamiento vertical, radio) de abdomen, tórax y cabeza.
ANT_SEGMENTS = ((-0.062, 0.04), (0.0, 0.025), (0.056, 0.031))
LEG_ROWS = (-0.018, 0.0, 0.018)
LEG_REACH = 0.088
LEG_THICK = 0.012


def _hex(r: float, y_back: float, y_front: float, angle: float) -> bmesh.types.BMesh:
    # Prisma hexagonal de pie en el plano XZ, de y_back a y_front (el frente mira a −Y).
    bm = bmesh.new()
    back, front = [], []
    for i in range(6):
        a = angle + 2.0 * math.pi * i / 6
        back.append(bm.verts.new((r * math.cos(a), y_back, r * math.sin(a))))
        front.append(bm.verts.new((r * math.cos(a), y_front, r * math.sin(a))))
    bm.faces.new(back)
    bm.faces.new(front)
    for i in range(6):
        j = (i + 1) % 6
        bm.faces.new((back[i], back[j], front[j], front[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def _bar(p0, p1, thick: float) -> bmesh.types.BMesh:
    # Barra de sección cuadrada de p0 a p1.
    p0, p1 = Vector(p0), Vector(p1)
    d = p1 - p0
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=(thick, thick, d.length), verts=bm.verts)
    bmesh.ops.translate(bm, vec=(0.0, 0.0, d.length / 2), verts=bm.verts)
    rot = Vector((0.0, 0.0, 1.0)).rotation_difference(d.normalized()).to_matrix().to_4x4()
    bmesh.ops.transform(bm, matrix=Matrix.Translation(p0) @ rot, verts=bm.verts)
    return bm


def _placement(location, facing, scale: float) -> Matrix:
    # Lleva el emblema hecho «mirando a −Y» hasta `location`, mirando a `facing`.
    # Primero se inclina (en X) y luego se orienta (en Z): así la cabeza nunca queda torcida. En una
    # superficie de arriba (facing hacia +Z), la cabeza apunta al norte (+Y).
    f = Vector(facing).normalized()
    yaw = math.atan2(f.x, -f.y) if abs(f.z) < 0.999 else 0.0
    tilt = -math.asin(max(-1.0, min(1.0, f.z)))
    rot = Matrix.Rotation(yaw, 4, "Z") @ Matrix.Rotation(tilt, 4, "X")
    return Matrix.Translation(Vector(location)) @ rot @ Matrix.Scale(scale, 4)


def add_crest(finish, parent, material, location, facing=(0.0, -1.0, 0.0), scale: float = 1.0,
              style: str = "plate", frame_depth: float = 0.04, embed: float = 0.0, prefix: str = "crest") -> list:
    m = _placement(location, facing, scale)
    pieces = []  # (nombre, bmesh, color, bisel)
    if style == "plate":
        front = -frame_depth
        pieces.append(("frame", _hex(FRAME_R, embed, front, 0.0), METAL_DARK, 0.008))
        plate_back, plate_front = front, front - PLATE_DEPTH
        ant_depth = ANT_DEPTH
        plate_bevel = 0.004
    else:
        plate_back, plate_front = 0.002, -PAINT_PLATE_DEPTH
        ant_depth = PAINT_ANT_DEPTH
        plate_bevel = 0.002
    pieces.append(("plate", _hex(PLATE_R, plate_back, plate_front, 0.0), ACCENT, plate_bevel))
    ant_front = plate_front - ant_depth
    # Las patas, un pelo por detrás de la cara del cuerpo: si asomaran por delante taparían el tórax.
    leg_y = ant_front + LEG_THICK * 0.5 + 0.002
    for k, (dz, r) in enumerate(ANT_SEGMENTS):
        seg = _hex(r, plate_front, ant_front, math.radians(30))
        bmesh.ops.translate(seg, vec=(0.0, 0.0, dz), verts=seg.verts)
        pieces.append(("ant_%d" % k, seg, METAL_DEEP, 0.0))
    for k, dz in enumerate(LEG_ROWS):
        for sx in (-1.0, 1.0):
            # Las patas salen del centro del tórax: así no queda hueco entre pata y cuerpo (César).
            leg = _bar((0.0, leg_y, dz * 0.6), (sx * LEG_REACH, leg_y, dz * 3.2), LEG_THICK)
            pieces.append(("leg_%d_%d" % (k, sx > 0), leg, METAL_DEEP, 0.0))
    for sx in (-1.0, 1.0):
        antenna = _bar((sx * 0.006, leg_y, 0.074), (sx * 0.045, leg_y, 0.105), LEG_THICK * 0.67)
        pieces.append(("antenna_%d" % (sx > 0), antenna, METAL_DEEP, 0.0))
    objects = []
    for name, bm, color, bevel in pieces:
        bmesh.ops.transform(bm, matrix=m, verts=bm.verts)
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        objects.append(finish("%s_%s" % (prefix, name), bm, color, parent, material, bevel * scale))
    return objects
