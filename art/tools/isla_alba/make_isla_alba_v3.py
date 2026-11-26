# Isla Alba, versión 3 (C5.4b, César: las explanadas se veían demasiado grandes y vacías; D-167 a D-169).
# Uso (desde esta carpeta):  python make_isla_alba_v3.py isla_alba_v2.txt ../../../content/islands/isla_alba.txt isla_alba_v3.png
# Lee también terrace_mask.json (forma de la terraza dibujada por César) y paint_v3.json (lomas altas en amarillo y
# tierra pisada en morado y rosa, de sus dibujos). Necesita Pillow para la imagen de comprobación.
# Ojo: si se retoca isla_alba.txt a mano, volver a generar lo machaca. Para pintar a mano está paint_alba.png (paso 13).
# Parte del plano v2 con sendero y añade: bolsas en la explanada baja separadas por lomas con árboles y peñascos,
# una terraza a 3 m (explanada media) con su rampa, y la explanada alta más pequeña y con el borde roto.
import math, sys, random
src, out, png = sys.argv[1], sys.argv[2], sys.argv[3]
lines = open(src, encoding='utf-8').read().split('\n')
head = [l for l in lines if l.startswith('//')]
grid = [list(l) for l in lines if l and not l.startswith('//')]
H = len(grid); W = max(len(r) for r in grid)
for r in grid:
    r.extend('~' * (W - len(r)))
rnd = random.Random(7)

def _fix_cascade():
    # Cascada (C5.4e, César): el lago llega a todo el borde de arriba y las dos últimas filas pasan a ser río, para que
    # el agua caiga directamente en él (antes quedaba un trozo de tierra plano entre la caída y el río).
    cs = [(x, y) for y in range(H) for x in range(W) if grid[y][x] == 'C']
    if not cs:
        return
    x0, x1 = min(c[0] for c in cs), max(c[0] for c in cs)
    y0, y1 = min(c[1] for c in cs), max(c[1] for c in cs)
    for x in range(x0 - 1, x1 + 2):   # una casilla más a cada lado: si no, una esquina del lago quedaba cortada
        grid[y0 - 1][x] = 'O'
    for x in range(x0 - 1, x1 + 2):   # y la primera fila de la caída entera: sin dos salientes de agua a los lados
        grid[y0][x] = 'O'             # y un escalón de tierra entre ellos (César); la caída empieza en el borde
    for x in range(x0, x1 + 1):
        for y in (y1 - 1, y1):
            grid[y][x] = 'v'

def h(x, y, seed):
    n = math.sin(x * 12.9898 + y * 78.233 + seed * 37.719) * 43758.5453
    return n - math.floor(n)

def noise(x, y, seed, scale):
    gx, gy = x / scale, y / scale
    x0, y0 = math.floor(gx), math.floor(gy)
    fx, fy = gx - x0, gy - y0
    fx, fy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
    a, b = h(x0, y0, seed), h(x0 + 1, y0, seed)
    c, d = h(x0, y0 + 1, seed), h(x0 + 1, y0 + 1, seed)
    return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy

def setc(x, y, ch, only=None):
    if 0 <= x < W and 0 <= y < H and (only is None or grid[y][x] in only):
        grid[y][x] = ch

LOWFLAT = '='

_fix_cascade()

# 3) Lomas con árboles y peñascos entre las bolsas de la explanada baja, con pasos anchos (se construye en ellos).
def band_v(y, cx, amp, freq, half, gaps, y0, y1, seed):
    for yy in range(y0, y1 + 1):
        if any(g0 <= yy <= g1 for g0, g1 in gaps):
            continue
        c = cx + amp * math.sin(yy * freq + seed) + (noise(0, yy, seed, 4.0) - 0.5) * 2.0
        w = half + (noise(5, yy, seed + 1, 3.0) - 0.5) * 2.0
        for x in range(int(c - w), int(c + w) + 1):
            setc(x, yy, 'n', '=')
def band_h(cy, amp, freq, half, gaps, x0, x1, seed):
    for xx in range(x0, x1 + 1):
        if any(g0 <= xx <= g1 for g0, g1 in gaps):
            continue
        c = cy + amp * math.sin(xx * freq + seed) + (noise(xx, 0, seed, 4.0) - 0.5) * 2.0
        w = half + (noise(xx, 5, seed + 1, 3.0) - 0.5) * 2.0
        for y in range(int(c - w), int(c + w) + 1):
            setc(xx, y, 'n', '=')
# entre la bolsa de la llegada (oeste) y la del río (este), con un paso a media altura
band_v(0, 58, 2.0, 0.35, 3.9, [(63, 68)], 56, 78, 1)
# entre las de arriba y la del suroeste, con el paso de la llegada al suroeste y la rampa a la terraza
band_h(77, 1.6, 0.22, 3.5, [(37, 45)], 23, 60, 2)
# entre la del suroeste y la terraza (la terraza ya tiene su acantilado; aquí, una loma suave al pie)

# Terraza a 3 m con la forma que dibujó César (`terrace_mask.json`, casillas dentro de su trazo). Al oeste y al norte,
# lomas pegadas que hacen de borde; al este (contra el río, que pasa pegado al corte) y al sur, el corte de roca.
# La rampa entra por el hueco de arriba del dibujo, entre las lomas.
import json
import os
mask = json.load(open(os.path.join(os.path.dirname(os.path.abspath(sys.argv[0])), 'terrace_mask.json')))
inside = {(x, y) for y in range(H) for x in range(W) if mask[y][x] and grid[y][x] not in '~vo<>sCO'}
TERRACE_RIM = 4
dist, origin = {}, {}
frontier = []
for (x, y) in inside:
    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        o2 = (x + dx, y + dy)
        if o2 not in inside and (x, y) not in dist:
            dist[(x, y)] = 1
            origin[(x, y)] = o2
            frontier.append((x, y))
qi = 0
while qi < len(frontier):
    cx, cy = frontier[qi]; qi += 1
    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        c = (cx + dx, cy + dy)
        if c in inside and c not in dist:
            dist[c] = dist[(cx, cy)] + 1
            origin[c] = origin[(cx, cy)]
            frontier.append(c)
for (x, y) in inside:
    d = dist[(x, y)]
    ox, oy = origin[(x, y)]
    ddx, ddy = ox - x, oy - y   # hacia dónde queda el borde
    cliff_side = (ddx > 0 and ddx >= abs(ddy)) or (ddy > 0 and ddy > abs(ddx))
    if cliff_side:
        grid[y][x] = '-' if d <= 1 else '+'
    else:
        grid[y][x] = 'n' if d <= TERRACE_RIM + (noise(x, y, 41, 3.0) - 0.5) * 2 else '+'
# Casillas de terraza sueltas entre las lomas del borde (donde cambia el lado): pasan a ser loma.
for _ in range(2):
    for (x, y) in inside:
        if grid[y][x] == '+' and sum(grid[y + dy][x + dx] == '+' for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))) < 2:
            grid[y][x] = 'n'
# Una casilla de terraza no puede tocar (ni en diagonal) la explanada baja: su esquina tendría dos alturas.
for (x, y) in inside:
    if grid[y][x] == '+' and any(grid[y + dy][x + dx] == '=' for dx in (-1, 0, 1) for dy in (-1, 0, 1)):
        grid[y][x] = '-'
# Rampa: 5 de ancho, desde 2 casillas fuera del borde hasta la primera casilla de terraza.
RAMP_X0, RAMP_X1 = 75, 79
top = min(y for y in range(H) for x in range(RAMP_X0, RAMP_X1 + 1) if (x, y) in inside)
first_flat = min(y for y in range(top, H) if all(grid[y][x] == '+' for x in range(RAMP_X0, RAMP_X1 + 1)))
for y in range(top - 4, first_flat):   # más larga, para que suba suave (César)
    for x in range(RAMP_X0, RAMP_X1 + 1):
        grid[y][x] = 'r'
# Talud a los lados de la rampa donde da a la explanada baja: si no, la explanada sujetaba el borde de la rampa abajo
# y la rampa salía abombada de lado a lado («barriga», César). Así sube plana y el talud baja hasta la explanada.
for y in range(top - 4, first_flat):
    for x in (RAMP_X0 - 2, RAMP_X0 - 1, RAMP_X1 + 1, RAMP_X1 + 2):
        if grid[y][x] == '=':
            grid[y][x] = '.'

# una loma suelta en medio de la bolsa del suroeste, la más grande
for y in range(H):
    for x in range(W):
        if (x - 39) ** 2 + ((y - 93) * 1.3) ** 2 <= 16 + (noise(x, y, 4, 2.0) - 0.5) * 10:
            setc(x, y, 'n', '=')

# Árboles y peñascos sobre las lomas (no en su borde, para que el paso quede limpio)
for y in range(H):
    for x in range(W):
        if grid[y][x] != 'n':
            continue
        inner = all(grid[y + dy][x + dx] in 'ntX' for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))
        r = h(x, y, 11)
        if inner and r < 0.2:
            grid[y][x] = 't'
        elif inner and r < 0.24:
            grid[y][x] = 'X'

# 4) Explanada alta más pequeña y con el borde roto: el norte vuelve a ser montaña con árboles, bahías en los
# costados y un bosquecillo con peñascos dentro.
for y in range(H):
    for x in range(W):
        if grid[y][x] != '#':
            continue
        north = y <= 14 + (noise(x, 0, 21, 4.0) - 0.5) * 4
        west_bay = x <= 46 + (noise(0, y, 22, 3.0) - 0.5) * 6 and 16 <= y <= 34
        east_bay = x >= 81 + (noise(0, y, 23, 3.0) - 0.5) * 6 and 15 <= y <= 30
        grove = (x - 62) ** 2 + (y - 24) ** 2 <= 3.2 ** 2 + (noise(x, y, 24, 2.0) - 0.5) * 6
        if north or west_bay or east_bay or grove:
            grid[y][x] = '^'
            r = h(x, y, 25)
            if r < (0.35 if grove else 0.12):
                grid[y][x] = 't'
            elif grove and r < 0.45:
                grid[y][x] = 'X'

# 5) Cumbre a 9 m al noreste (César: lo alto seguía muy abierto), con su explanada y el árbol singular en lo más alto,
# que así se ve desde toda la isla. Rampa desde la explanada alta, con peñascos a los lados.
for y in range(H):
    for x in range(W):
        if grid[y][x] in '~OoCvs<>,':
            continue
        wob = (noise(x, y, 31, 3.0) - 0.5) * 0.35
        ring = ((x - 99) / 11.5) ** 2 + ((y - 20) / 10.0) ** 2
        flat = ((x - 99) / 7.0) ** 2 + ((y - 22.5) / 4.6) ** 2
        if ring <= 1.0 + wob:
            if flat <= 1.0 + wob * 0.6:
                grid[y][x] = '%'
            elif grid[y][x] not in 'GtX':
                grid[y][x] = '*'
for y in range(19, 22):
    for x in range(84, 92):   # hasta la explanada alta (antes quedaba una casilla de montaña en medio)
        grid[y][x] = 'r'
for x in range(85, 92):
    for y in (18, 22):
        if grid[y][x] not in 'G':
            grid[y][x] = 'X'
for y in range(19, 22):   # la boca de arriba de la rampa da a la explanada de la cumbre
    for x in range(92, 94):
        grid[y][x] = '%'

# 6) Del dibujo de César: lomas en lo alto sin explanada (amarillo) y tierra pisada por donde se anda (morado).
paint = json.load(open(os.path.join(os.path.dirname(os.path.abspath(sys.argv[0])), 'paint_v3.json')))
for y in range(min(H, 50)):   # más abajo, lo amarillo del dibujo es el portal
    for x in range(W):
        if paint['yellow'][y][x] and grid[y][x] in '^#':
            grid[y][x] = 'm'
worn = [['x' if paint['purple'][y][x] or paint.get('pink', [[0] * W] * H)[y][x] else '.' for x in range(W)] for y in range(H)]

# 7) Orilla sin construir alrededor del agua quieta (lago y remanso; C5.4d, César: el lago tenía los bordes cuadrados).
# Ahí el terreno se deforma y la orilla sale irregular. En el río no: la explanada llega al agua por la rueda.
NOT_FLAT = {'#': '^', '=': '.', '+': '-', '%': '*'}
shore_cells = [(x, y) for y in range(H) for x in range(W) if grid[y][x] in NOT_FLAT
               and any(0 <= x + dx < W and 0 <= y + dy < H and grid[y + dy][x + dx] in 'Oo'
                       for dx in (-1, 0, 1) for dy in (-1, 0, 1))]
for x, y in shore_cells:
    grid[y][x] = NOT_FLAT[grid[y][x]]

# 8) Más acantilados de juguete en lo alto (César: le gustan tanto que echaba de menos más arriba).
# a) Borde de roca del lago por el lado de la cascada: la cascada sale de entre rocas.
for y in range(44, 50):
    for x in range(80, 108):
        if grid[y][x] != '^':
            continue
        near_lake = any(grid[y + dy][x + dx] == 'O' for dx in range(-2, 3) for dy in range(-2, 3)
                        if 0 <= y + dy < H and 0 <= x + dx < W)
        near_fall = any(grid[y + dy][x + dx] in 'CH' for dx in range(-1, 2) for dy in range(-1, 2)
                        if 0 <= y + dy < H and 0 <= x + dx < W)
        if near_lake and not near_fall:
            grid[y][x] = 'm'
# b) Cerros de roca sueltos por la montaña alrededor de la explanada alta: sitios de montaña con bosque alrededor,
# lejos de las explanadas, del agua, de las lomas altas y entre sí. Siempre los mismos (orden por un ruido fijo).
HILLOCKS = 6
candidates = []
for y in range(6, 60):
    for x in range(20, 112):
        if grid[y][x] != '^':
            continue
        ok = True
        for dy in range(-4, 5):
            for dx in range(-4, 5):
                yy, xx = y + dy, x + dx
                if not (0 <= yy < H and 0 <= xx < W) or grid[yy][xx] not in '^tmX*':
                    ok = False
                    break
                if grid[yy][xx] == 'm' and abs(dx) <= 3 and abs(dy) <= 3:
                    ok = False
                    break
            if not ok:
                break
        if ok:
            candidates.append((h(x, y, 61), x, y))
candidates.sort()
chosen = []
for _, x, y in candidates:
    if all((x - cx) ** 2 + (y - cy) ** 2 >= 12 ** 2 for cx, cy in chosen):
        chosen.append((x, y))
    if len(chosen) >= HILLOCKS:
        break
for cx, cy in chosen:
    rx = 2.5 + h(cx, cy, 62) * 1.5
    ry = 2.5 + h(cx, cy, 63) * 1.5
    for y in range(cy - 5, cy + 6):
        for x in range(cx - 5, cx + 6):
            d = ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2
            if d <= 1.0 + (noise(x, y, 64, 2.0) - 0.5) * 0.8 and grid[y][x] in '^t':
                grid[y][x] = 'm' if grid[y][x] == '^' else 't'
print('cerros', chosen)

# 9) El borde este de la ladera, de lo alto hasta el refugio, como acantilado de juguete (dibujo de César): la parte
# alta pegada a la ladera pasa a ser loma alta con corte. La salida de arriba del sendero (filas de arriba) se deja.
for y in range(32, 56):
    for x in range(30, 40):
        if grid[y][x] != '^':
            continue
        if any(grid[y + dy][x + dx] in '/:' for dx in range(-2, 3) for dy in range(-2, 3)
               if 0 <= y + dy < H and 0 <= x + dx < W):
            grid[y][x] = 'm'

# 10) Más acantilado en la curva del sendero, entre el camino y el refugio (dibujo de César): así el camino sube recto
# entre la ladera y la pared.
for y in range(45, 56):
    for x in range(22, 34):
        if grid[y][x] == '/' and not any(grid[y + dy][x + dx] == ':' for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
            # al este del camino (a su derecha bajando): el lado del refugio
            if any(grid[y][xx] == ':' for xx in range(x - 6, x)):
                grid[y][x] = 'm'

# 11) El refugio es un hormiguero que se levanta en la explanada (C5.5, César). Donde estaba la zona del refugio en
# el plano v2 se escribe el suelo que el juego le deducía (la misma regla que `_infer_ground()` de
# `island_layout.gd`), para que el sendero y la loma alta de al lado queden igual. Ninguna casilla del sendero cambia.
SHELTER_AT = (44, 56)      # esquina noroeste de sus 8 × 7 casillas: de espaldas al acantilado (César)
SHELTER_SIZE = (8, 7)
_GROUND = {'~': 'SEA', ',': 'BEACH', '.': 'LOW', '=': 'LOW_FLAT', '^': 'HIGH', '#': 'HIGH_FLAT', '-': 'MID',
           '+': 'MID_FLAT', 'n': 'HILL', '*': 'TOP', '%': 'TOP_FLAT', 'r': 'RAMP', 'm': 'HIGH_HILL', '/': 'SLOPE',
           ':': 'SLOPE', '_': 'LANDING', 'O': 'WATER', 'o': 'WATER', 'v': 'WATER', '<': 'WATER', '>': 'WATER',
           's': 'WATER', 'C': 'FALL'}
_CHAR = {'BEACH': ',', 'LOW': '.', 'LOW_FLAT': '=', 'HIGH': '^', 'HIGH_FLAT': '#', 'MID': '-', 'MID_FLAT': '+',
         'HILL': 'n', 'TOP': '*', 'TOP_FLAT': '%', 'RAMP': 'r', 'HIGH_HILL': 'm', 'SLOPE': '/', 'LANDING': '_'}
_FEATURES = 'RPMSTtXAGHQE'

def _inferred(x, y):
    counts = {}
    for dy in range(-2, 3):
        for dx in range(-2, 3):
            ox, oy = x + dx, y + dy
            if not (0 <= ox < W and 0 <= oy < H) or grid[oy][ox] in _FEATURES:
                continue
            g = _GROUND.get(grid[oy][ox], 'SEA')
            if g in ('SEA', 'WATER', 'FALL'):
                continue
            counts[g] = counts.get(g, 0) + 1
    best, best_count = 'LOW', -1
    for g, c in counts.items():   # el primero que se encuentra gana en un empate, como en Godot
        if c > best_count:
            best, best_count = g, c
    return _CHAR[best]

_shelter = [(x, y) for y in range(H) for x in range(W) if grid[y][x] == 'R']
if _shelter:
    _path_before = [(x, y) for y in range(H) for x in range(W) if grid[y][x] == ':']
    _fill = {(x, y): _inferred(x, y) for x, y in _shelter}
    for (x, y), c in _fill.items():
        grid[y][x] = c
    sx, sy = SHELTER_AT
    for y in range(sy, sy + SHELTER_SIZE[1]):
        for x in range(sx, sx + SHELTER_SIZE[0]):
            assert grid[y][x] != ':', 'el refugio pisaría el sendero en %d, %d' % (x, y)
            grid[y][x] = 'R'
    assert _path_before == [(x, y) for y in range(H) for x in range(W) if grid[y][x] == ':']

# 12) El portal, delante de la boca del refugio (César, sesión 25): Mira llega de espaldas al portal y con el refugio
# de frente, a unos 7 m. Donde estaba (al oeste del refugio, de cara al acantilado) se escribe el suelo deducido,
# como en el paso 11. El portal ocupa 3 × 2 casillas de explanada baja.
PORTAL_AT = (47, 70)       # esquina noroeste de sus 3 × 2 casillas: centrado con la boca del refugio (x 47–48), con una fila libre antes de la loma del sur
PORTAL_SIZE = (3, 2)
_portal = [(x, y) for y in range(H) for x in range(W) if grid[y][x] == 'P']
if _portal:
    _fill = {(x, y): _inferred(x, y) for x, y in _portal}
    for (x, y), c in _fill.items():
        grid[y][x] = c
    px0, py0 = PORTAL_AT
    for y in range(py0, py0 + PORTAL_SIZE[1]):
        for x in range(px0, px0 + PORTAL_SIZE[0]):
            assert grid[y][x] == '=', 'el portal no cae en explanada baja en %d, %d' % (x, y)
            grid[y][x] = 'P'

# 12b) El embarcadero en ruinas, en la playa oeste, al pie del sendero (César, sesión 29): sale de la playa hacia el mar
# (en la desembocadura salía hacia el río y no quedaba bien). Donde estaba se escribe el suelo deducido, como en el
# paso 11. Ocupa 3 × 2 casillas de playa; el muelle lo genera el juego (`DockBuilder`) hacia el lado del mar.
DOCK_AT = (6, 60)          # esquina noroeste de sus 3 × 2 casillas: el mar empieza justo al oeste (x 5)
DOCK_SIZE = (3, 2)
_dock = [(x, y) for y in range(H) for x in range(W) if grid[y][x] == 'E']
if _dock:
    _fill = {(x, y): _inferred(x, y) for x, y in _dock}
    for (x, y), c in _fill.items():
        grid[y][x] = c
    dx0, dy0 = DOCK_AT
    for y in range(dy0, dy0 + DOCK_SIZE[1]):
        for x in range(dx0, dx0 + DOCK_SIZE[0]):
            assert grid[y][x] == ',', 'el embarcadero no cae en la playa en %d, %d' % (x, y)
            grid[y][x] = 'E'
        assert grid[y][dx0 - 1] == '~', 'al oeste del embarcadero no hay mar en la fila %d' % y

# 13) La pintura de César (`paint_alba.png`, sesión 26): tierra pisada, árboles salvajes, arboledas, barandilla, césped
# (hierba aunque haya sendero o rellano) y escala, pintados en Paint sobre el plano (8 píxeles por casilla; los colores,
# en la columna de la derecha; el amarillo y el azul, los de Paint que eligió César). Si la imagen no existe, se crea con
# lo que hay ahora; si existe, manda ella en todo eso (lo que no esté pintado de su color, no lo lleva).
# Una casilla lleva una cosa si tiene al menos PAINT_MIN píxeles de su color (con tolerancia; PAINT_MIN_THIN para las
# líneas finas), así no hace falta pintar con cuidado; la tierra pisada se puede combinar con un árbol o con la barandilla. El resto de colores no cuenta.
from PIL import Image, ImageDraw, ImageFont
PAINT_FILE = os.path.join(os.path.dirname(os.path.abspath(sys.argv[0])), 'paint_alba.png')
CELL_PX = 8
PAINT_MIN = 12
# Lo que se pinta con líneas finas (barandilla, escala y la franja de césped a su lado): con unos pocos píxeles basta.
PAINT_MIN_THIN = {'fence': 3, 'ladder': 3, 'grass': 4}
PAINT_TOLERANCE = 70
PAINT_MARGIN = 330
PAINT_COLORS = {'worn': (170, 0, 210), 'tree': (0, 80, 0), 'grove': (0, 210, 80), 'fence': (255, 0, 0),
                'grass': (255, 242, 0), 'ladder': (0, 162, 232)}
PAINT_LABELS = {'worn': 'Tierra pisada', 'tree': 'Árbol salvaje (t)', 'grove': 'Arboleda (T, mejor 3 × 3)',
                'fence': 'Barandilla', 'grass': 'Césped (sin tierra)', 'ladder': 'Escala'}
GROUND_COLORS = {"~": (143, 208, 236), ",": (238, 217, 166), ".": (169, 214, 126), "=": (188, 224, 143), "^": (94, 158, 78),
                 "#": (123, 180, 99), "/": (150, 160, 88), ":": (190, 150, 100), "_": (196, 176, 118), "O": (63, 169, 216),
                 "o": (90, 185, 225), "v": (40, 140, 205), "<": (40, 140, 205), ">": (40, 140, 205), "C": (233, 246, 252),
                 "s": (150, 140, 125), "R": (200, 85, 61), "P": (242, 177, 58), "M": (46, 158, 126), "S": (142, 138, 128),
                 "X": (120, 112, 100), "A": (90, 84, 76), "G": (120, 60, 30), "H": (200, 120, 70), "Q": (40, 35, 30),
                 "E": (140, 100, 60), "n": (130, 175, 95), "-": (170, 190, 120), "+": (215, 228, 160), "r": (160, 150, 90),
                 "m": (80, 140, 70), "*": (70, 128, 60), "%": (150, 200, 110)}
fence = [['.'] * W for _ in range(H)]
lawn = [['.'] * W for _ in range(H)]
ladder = [['.'] * W for _ in range(H)]

def _ground_char(x, y):
    # Lo que hay debajo de un árbol, para el fondo de la imagen.
    return _inferred(x, y) if grid[y][x] in 'tT' else grid[y][x]

def _write_paint_image():
    img = Image.new('RGB', (W * CELL_PX + PAINT_MARGIN, H * CELL_PX), (255, 255, 255))
    draw = ImageDraw.Draw(img)
    for y in range(H):
        for x in range(W):
            # El plano, apagado (mezclado con blanco) para que no se confunda con los colores de pintar.
            col = GROUND_COLORS.get(_ground_char(x, y), (255, 0, 255))
            # (el sendero y el rellano, menos apagados: por ahí va la barandilla).
            fade = 0.3 if _ground_char(x, y) in ':_' else 0.55
            col = tuple(int(c * (1.0 - fade) + 255 * fade) for c in col)
            x0, y0 = x * CELL_PX, y * CELL_PX
            draw.rectangle([x0, y0, x0 + CELL_PX - 1, y0 + CELL_PX - 1], fill=col)
            line = tuple(int(c * 0.8) for c in col)   # cuadrícula cada 10 casillas, de 1 píxel, para orientarse
            if x % 10 == 0:
                draw.line([x0, y0, x0, y0 + CELL_PX - 1], fill=line)
            if y % 10 == 0:
                draw.line([x0, y0, x0 + CELL_PX - 1, y0], fill=line)
            if worn[y][x] == 'x':
                draw.rectangle([x0, y0, x0 + CELL_PX - 1, y0 + CELL_PX - 1], fill=PAINT_COLORS['worn'])
            elif lawn[y][x] == 'g':
                draw.rectangle([x0, y0, x0 + CELL_PX - 1, y0 + CELL_PX - 1], fill=PAINT_COLORS['grass'])
            mark = ('tree' if grid[y][x] == 't' else 'grove' if grid[y][x] == 'T' else 'fence' if fence[y][x] == 'b'
                    else 'ladder' if ladder[y][x] == 'e' else '')
            if mark:   # un cuadrado en el centro, para que se vea la tierra pisada de debajo
                draw.rectangle([x0 + 2, y0 + 2, x0 + CELL_PX - 3, y0 + CELL_PX - 3], fill=PAINT_COLORS[mark])
    font = None
    for name in ('arial.ttf', 'DejaVuSans.ttf', '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'):   # con tildes
        try:
            font = ImageFont.truetype(name, 16)
            break
        except OSError:
            pass
    if font is None:
        font = ImageFont.load_default()
    left = W * CELL_PX + 16
    draw.text((left, 12), 'Colores para pintar', fill=(0, 0, 0), font=font)
    draw.text((left, 32), '(cógelos con el cuentagotas)', fill=(90, 90, 90), font=font)
    for i, key in enumerate(PAINT_COLORS):
        top = 66 + i * 52
        draw.rectangle([left, top, left + 40, top + 40], fill=PAINT_COLORS[key])
        draw.text((left + 50, top + 10), PAINT_LABELS[key], fill=(0, 0, 0), font=font)
    top = 66 + len(PAINT_COLORS) * 52 + 10
    for line in ['Borrar: pinta de blanco', '(o de cualquier otro color).', '', '1 casilla = 8 × 8 píxeles.',
                 'Cuadrícula cada 10 casillas.', 'Casilla = píxel / 8 (la posición', 'del ratón sale abajo en Paint).',
                 '', 'El sendero y el resto del plano', 'no se pintan aquí: son el fondo.']:
        draw.text((left, top), line, fill=(60, 60, 60), font=font)
        top += 22
    img.save(PAINT_FILE)

def _read_paint_image():
    img = Image.open(PAINT_FILE).convert('RGB')
    assert img.width >= W * CELL_PX and img.height >= H * CELL_PX, 'paint_alba.png es más pequeña que el plano'
    px = img.load()
    painted = {key: [[False] * W for _ in range(H)] for key in PAINT_COLORS}
    for y in range(H):
        for x in range(W):
            counts = dict.fromkeys(PAINT_COLORS, 0)
            for b in range(CELL_PX):
                for a in range(CELL_PX):
                    c = px[x * CELL_PX + a, y * CELL_PX + b]
                    for key, ref in PAINT_COLORS.items():
                        if sum((c[k] - ref[k]) ** 2 for k in range(3)) <= PAINT_TOLERANCE ** 2:
                            counts[key] += 1
            for key in PAINT_COLORS:
                painted[key][y][x] = counts[key] >= PAINT_MIN_THIN.get(key, PAINT_MIN)
    return painted

if not os.path.exists(PAINT_FILE):
    _write_paint_image()
    print('paint_alba.png creada con lo que hay ahora en el plano')
painted = _read_paint_image()
_NO_TREE = 'RPMSXAGHQE~OovC<>s'   # objetos, mar y agua: ahí no se pone un árbol ni la barandilla
skipped = {'tree': 0, 'fence': 0, 'ladder': 0}
# Primero se quitan los árboles que ya no están pintados (su suelo, el de alrededor, como en el paso 11)...
_fill = {(x, y): _inferred(x, y) for y in range(H) for x in range(W)
         if (grid[y][x] == 't' and not painted['tree'][y][x]) or (grid[y][x] == 'T' and not painted['grove'][y][x])}
for (x, y), c in _fill.items():
    grid[y][x] = c
# ...y después se ponen los pintados.
for y in range(H):
    for x in range(W):
        # El césped manda sobre la tierra pisada.
        lawn[y][x] = 'g' if painted['grass'][y][x] and grid[y][x] not in _NO_TREE else '.'
        worn[y][x] = 'x' if painted['worn'][y][x] and lawn[y][x] != 'g' else '.'
        for key, ch in (('tree', 't'), ('grove', 'T')):
            if painted[key][y][x] and grid[y][x] not in 'tT':
                if grid[y][x] in _NO_TREE:
                    skipped['tree'] += 1
                else:
                    grid[y][x] = ch
        for key, layer, ch in (('fence', fence, 'b'), ('ladder', ladder, 'e')):
            if painted[key][y][x]:
                if grid[y][x] in _NO_TREE:
                    skipped[key] += 1
                else:
                    layer[y][x] = ch
if any(skipped.values()):
    print('pintura sobre agua u objetos, sin poner: %d árboles, %d de barandilla, %d de escala' % (
        skipped['tree'], skipped['fence'], skipped['ladder']))
print('pintura: %d casillas de tierra pisada, %d árboles salvajes, %d de arboleda, %d de barandilla, %d de césped, '
      '%d de escala' % (sum(r.count('x') for r in worn), sum(r.count('t') for r in grid), sum(r.count('T') for r in grid),
                        sum(r.count('b') for r in fence), sum(r.count('g') for r in lawn), sum(r.count('e') for r in ladder)))

legend_add = [
    '//  -  parte media (terraza a 3 m; se anda, no se construye)      +  explanada media (plana; se construye)  nivel 2 (3 m)',
    '//  *  cumbre (se anda, no se construye)       %  explanada de la cumbre (plana; se construye)   nivel 3 (9 m)',
    '//  r  rampa (sube recta y lisa entre dos alturas; se anda, no se construye)',
    '//  m  loma alta (parte alta; se anda, no se construye; sube unos 3,5 m sobre lo alto)',
    '//  n  loma (parte baja; se anda, no se construye; sube hasta unos 2,5 m y tapa la vista entre las bolsas)',
]
head = [l.replace('rellano de la cuesta (mirador a media altura)', 'rellano de la cuesta (mirador plano a 3 m; se construye, para decorarlo)') for l in head]
at = [i for i, l in enumerate(head) if l.startswith('//  #')][0]
for k, l in enumerate(legend_add):
    head.insert(at + 1 + k, l)
head.append('//')
head.append('// Al final, la capa [tierra pisada]: el mismo tamaño que el plano; x = tierra pisada (se pinta como el sendero,')
head.append('// sin cambiar dónde se construye). Se puede dibujar a mano.')
head.append('// Después, las capas de la sesión 26: [barandilla] (b = casilla con un tramo, C5.6b), [césped] (g = hierba aunque')
head.append('// sea sendero, rellano o tierra pisada) y [escala] (e = casilla de la escala reparable, C5.6b).')
head.append('// Las capas y los árboles salen de art/tools/isla_alba/paint_alba.png (paso 13 del generador).')
open(out, 'w', encoding='utf-8', newline='\n').write('\n'.join(head) + '\n' + '\n'.join(''.join(r) for r in grid) + '\n'
        + '[tierra pisada]\n' + '\n'.join(''.join(r) for r in worn) + '\n'
        + '[barandilla]\n' + '\n'.join(''.join(r) for r in fence) + '\n'
        + '[césped]\n' + '\n'.join(''.join(r) for r in lawn) + '\n'
        + '[escala]\n' + '\n'.join(''.join(r) for r in ladder) + '\n')

COLORS = {"~": (143, 208, 236), ",": (238, 217, 166), ".": (169, 214, 126), "=": (188, 224, 143), "^": (94, 158, 78),
          "#": (123, 180, 99), "/": (150, 160, 88), ":": (190, 150, 100), "_": (196, 176, 118), "O": (63, 169, 216), "o": (90, 185, 225),
          "v": (40, 140, 205), "<": (40, 140, 205), ">": (40, 140, 205), "C": (233, 246, 252), "s": (150, 140, 125),
          "R": (200, 85, 61), "P": (242, 177, 58), "M": (46, 158, 126), "S": (142, 138, 128), "T": (47, 107, 42), "t": (47, 107, 42),
          "X": (120, 112, 100), "A": (90, 84, 76), "G": (120, 60, 30), "H": (200, 120, 70), "Q": (40, 35, 30), "E": (140, 100, 60),
          "n": (130, 175, 95), "-": (170, 190, 120), "+": (215, 228, 160), "r": (160, 150, 90), "m": (80, 140, 70), "*": (70, 128, 60), "%": (150, 200, 110)}
S = 5
img = Image.new("RGB", (W * S, H * S))
px = img.load()
for y in range(H):
    for x in range(W):
        col = COLORS.get(grid[y][x], (255, 0, 255))
        for a in range(S):
            for b in range(S):
                px[x * S + a, y * S + b] = col
img = img.resize((W * S * 2 // 2, H * S * 2 // 2))
img.save(png)
count = lambda chs: sum(r.count(c) for r in grid for c in chs)
print('construible baja', count('='), 'media', count('+'), 'alta', count('#'), 'cumbre', count('%'), 'total', count('=+#%_'))
