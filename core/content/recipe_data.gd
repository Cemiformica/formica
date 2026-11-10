class_name RecipeData
extends Resource
## Receta de una máquina: qué consume, qué produce y cuánto tarda (contenido, no estado).

## Identificador estable y único (se usará en el guardado).
@export var id: StringName = &""
## Ítems que consume cada ciclo.
@export var inputs: Dictionary[ItemData, int] = {}
## Ítems que produce cada ciclo.
@export var outputs: Dictionary[ItemData, int] = {}
## Duración de un ciclo, en segundos.
@export var duration: float = 3.0
