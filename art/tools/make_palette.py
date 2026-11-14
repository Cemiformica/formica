# Genera la textura paleta de Formica: 64×64 px, 8×8 colores de 8 px.
from PIL import Image, ImageDraw
import sys
ROWS = [
    ("madera",            ["f2d29b","e6b877","d49a55","b97d3f","9a6230","7a4a24","5a3519","3d2410"]),
    ("piedra y arena",    ["f3ead6","e2d5b8","cdbd9b","b4a381","978a6c","7a6f58","5d5545","403b31"]),
    ("verdes",            ["d9f08a","b5e061","8ccb45","66b03a","4a9234","357429","25561f","173a15"]),
    ("cobre | malaquita", ["f6b07a","e88a4e","cf6a32","a94e24","7ee0b0","3fbf8a","1f8f66","11604a"]),
    ("arcilla y tierra",  ["e9a585","d4835f","b8673f","9a5232","7c4128","a07a5a","7d5c42","5a412e"]),
    ("grises del Nexo",   ["e6e6e3","c4c4c0","a1a19d","7f807d","60615f","444543","2c2d2c","1a1a1a"]),
    ("ámbar y fuego",     ["fff2b0","ffd76a","ffb83a","ff9420","f06a12","d94410","a82a0c","6e1808"]),
    ("agua y cristal",    ["d8f4fa","9fe3f0","5cc3dd","2f97c0","1f6c94","b8c8d4","8aa3b8","5c7488"]),
]
img = Image.new("RGB", (64, 64))
d = ImageDraw.Draw(img)
for r, (_, cols) in enumerate(ROWS):
    for c, h in enumerate(cols):
        d.rectangle([c*8, r*8, c*8+7, r*8+7], fill="#"+h)
img.save(sys.argv[1])
# Vista ampliada con etiquetas para revisarla
S = 48
prev = Image.new("RGB", (8*S + 170, 8*S), "white")
pd = ImageDraw.Draw(prev)
prev.paste(img.resize((8*S, 8*S), Image.NEAREST), (0, 0))
for r, (name, _) in enumerate(ROWS):
    pd.text((8*S + 10, r*S + S//2 - 6), f"{r}  {name}", fill="black")
prev.save(sys.argv[2])
