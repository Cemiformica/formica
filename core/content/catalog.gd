class_name Catalog
extends Resource
## Catálogo del contenido del juego: todos los ítems, recetas y edificios. Sirve para traducir
## los `id` guardados en disco ("wood", "crush_stone") a sus Resources.
## Al crear contenido nuevo, añádelo aquí: lo que no está en el catálogo no se puede cargar.

@export var items: Array[ItemData] = []
@export var recipes: Array[RecipeData] = []
@export var buildings: Array[BuildingData] = []
