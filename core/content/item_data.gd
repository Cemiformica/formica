class_name ItemData
extends Resource
## Definición de un tipo de ítem (madera, piedra...). Es contenido, no estado de partida:
## el inventario guardará referencias a estos recursos y cantidades, nunca copias.

## Identificador estable y único. Se usará en el guardado, así que no debe cambiar.
@export var id: StringName = &""
## Clave de traducción del nombre visible (por ejemplo, "ITEM_WOOD").
@export var name_key: String = ""
## Cantidad máxima por casilla de inventario.
@export_range(1, 999) var max_stack: int = 50
## Icono. Mientras no haya arte, las casillas usan `color` y el nombre abreviado.
@export var icon: Texture2D
## Color provisional de la casilla (sustituto del icono).
@export var color: Color = Color(0.5, 0.5, 0.5)
