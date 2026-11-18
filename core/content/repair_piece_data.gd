class_name RepairPieceData
extends Resource
## Una pieza de una estructura por reparar (C4, D-115): un trozo que falta (una viga, una losa…) y lo
## que hay que entregar para ponerlo. Va dentro de un `RepairSiteData`.

## Identificador estable dentro de su estructura.
@export var id: StringName = &""
## Clave de traducción del nombre visible (por ejemplo, "REPAIR_PIECE_PILLAR").
@export var name_key: String = ""
## Nodo del modelo de la estructura que es esta pieza: la vista lo enseña como fantasma hasta completarla.
@export var node_name: StringName = &""
## Lo que pide (ítem → cantidad). Se puede entregar poco a poco.
@export var cost: Dictionary[ItemData, int] = {}
## Qué hace la pieza cuando ya está completa (C4). Vacío = nada. &"bed": la cama del refugio; con E se
## descansa: marca ahí el punto de reaparición y guarda la partida (César).
@export var action: StringName = &""
