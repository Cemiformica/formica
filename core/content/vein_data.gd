class_name VeinData
extends Resource
## Tipo de veta (B3.7, D-090): un yacimiento inagotable de 3×3 que da un ítem. Es contenido: cada
## material tiene la suya, con su modelo y su color (malaquita verde; más adelante, piedra, hierro…).
## A mano se mina con E a golpes; el extractor (1×2) pone su cabeza en una casilla del borde.
## Para añadir una veta nueva: un .tres con su ítem y su modelo, y añadirlo a `content/catalog.tres`.

## Tamaño de todas las vetas, en casillas (las 8 del borde admiten extractor; la central, no).
const SIZE: int = 3

## Identificador estable (se guarda con la isla).
@export var id: StringName = &""
## Clave de traducción del nombre visible (por ejemplo, "VEIN_MALACHITE").
@export var name_key: String = ""
## Ítem que da, a mano y con el extractor.
@export var item: ItemData
## Modelo de la veta (origen en su centro, a ras de suelo).
@export var scene: PackedScene
## Golpes de E que hacen falta para sacar 1 ítem a mano (César: 3 o 4).
@export_range(1, 10) var hits_per_item: int = 4
## Segundos mínimos entre dos golpes.
@export var hit_cooldown: float = 1.0
## Herramienta necesaria para minarla a mano. Vacío = ninguna (las herramientas llegan en la fase C).
@export var required_tool: StringName = &""
