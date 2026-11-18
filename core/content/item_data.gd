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
## Icono de las casillas: foto del modelo, sacada en Blender (art/tools/render_item_icons.py, C1.7).
## Si falta, las casillas usan `color` y el nombre abreviado.
@export var icon: Texture2D
## Color de reserva de la casilla si el ítem no tiene icono.
@export var color: Color = Color(0.5, 0.5, 0.5)
## Semillas (C1.9): especie de árbol que planta (`NatureState.OAK`, `NatureState.PINE`); vacío si no planta.
@export var plants_tree: StringName = &""

## Cómo lo coge Mira (C3): HOLD, con los dedos alrededor (ítems sueltos); FIST, en puño por la empuñadura
## (herramientas).
enum HeldGrip { HOLD, FIST }
## Modelo que lleva en la mano (C3). Para FIST, su origen es el centro del puño, la empuñadura va por +Y y
## el aparato apunta a +X. Si falta, Mira lleva una barrita del color del ítem.
@export var held_model: PackedScene
@export var held_grip: HeldGrip = HeldGrip.HOLD
