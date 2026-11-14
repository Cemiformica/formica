class_name BuildingData
extends Resource
## Definición de un tipo de construcción (contenido). Las construcciones colocadas son estado aparte.

## Identificador estable y único (se usará en el guardado).
@export var id: StringName = &""
## Clave de traducción del nombre visible.
@export var name_key: String = ""
## Escena que se instancia al construir. Su origen debe estar en el centro de la base.
@export var scene: PackedScene
## Tamaño en casillas de la cuadrícula (X, Z).
@export var size: Vector2i = Vector2i.ONE
## Coste: qué ítems y cuántos de cada uno.
@export var cost: Dictionary[ItemData, int] = {}
## Receta fija si es una máquina (vacío = no es máquina: caja, cinta, generador…).
@export var recipe: RecipeData
## Puertos de entrada y salida (cintas). Se definen sin girar; giran y se reflejan con la construcción.
@export var ports: Array[PortData] = []
