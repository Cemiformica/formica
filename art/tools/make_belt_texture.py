# Genera la textura de la banda de las cintas (B3.7; C2b: más fina). 16×32 px por repetición, que la banda
# repite 2 veces por metro y Godot desplaza para que la cinta «avance» (hacia arriba en la imagen = hacia delante).
# Fondo casi negro (paleta 5,6) y, cada 16 px (25 cm), un nervio gris fino (5,3) y un chevrón pequeño que apunta
# hacia delante: la punta naranja (6,2, como la flecha de salida de los puertos) y la cola verde (2,2, como la de
# entrada). Dos por repetición (César, C2b): así los tramos cortos de los cruces también enseñan su chevrón.
# Dónde tocar: colores abajo; forma del chevrón en el bucle.
from PIL import Image
import sys
W, H = 16, 32
PERIOD = 16
DARK = (0x2c, 0x2d, 0x2c)
RIB = (0x7f, 0x80, 0x7d)
GREEN = (0x8c, 0xcb, 0x45)
ORANGE = (0xff, 0xb8, 0x3a)
img = Image.new("RGB", (W, H), DARK)
for start in range(0, H, PERIOD):
    for x in range(W):
        img.putpixel((x, start + PERIOD - 1), RIB)   # nervio fino (1 px)
    # Chevrón «^» pequeño: punta arriba (hacia delante), 4 filas, brazos de 2 px.
    tip_row = start + 5
    for i in range(4):
        row = tip_row + i
        color = ORANGE if i < 2 else GREEN
        for x in (7 - i, 8 + i):
            img.putpixel((x, row), color)
            img.putpixel((x, row + 1), color)
img.save(sys.argv[1])
