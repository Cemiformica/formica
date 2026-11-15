# Genera la textura de la banda de las cintas (B3.7): 16×32 px por repetición, que la banda repite
# 2 veces por metro y Godot desplaza para que la cinta «avance» (hacia arriba en la imagen = hacia delante).
# Fondo casi negro (paleta 5,6), un nervio gris fino (5,3) y un chevrón que apunta hacia delante: la cola
# verde (2,2, como la flecha de entrada de los puertos) y la punta naranja (6,2, como la de salida).
# Dónde tocar: colores abajo; forma del chevrón en `chevron`.
from PIL import Image
import sys
W, H = 16, 32
DARK = (0x2c, 0x2d, 0x2c)
RIB = (0x7f, 0x80, 0x7d)
GREEN = (0x8c, 0xcb, 0x45)
ORANGE = (0xff, 0xb8, 0x3a)
img = Image.new("RGB", (W, H), DARK)
for x in range(W):
    img.putpixel((x, H - 1), RIB)          # nervio fino (1 px)
# Chevrón «^»: punta arriba (hacia delante), brazos de 2 px hacia abajo.
tip_row = 10
for i in range(6):
    row = tip_row + i
    color = ORANGE if i < 3 else GREEN
    for x in (7 - i, 8 + i):
        img.putpixel((x, row), color)
        if row + 1 < H:
            img.putpixel((x, row + 1), color)
img.save(sys.argv[1])
