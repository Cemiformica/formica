class_name Catalog
extends Resource
## Catálogo del contenido del juego: todos los ítems, recetas, edificios, vetas y estructuras por reparar. Sirve para traducir
## los `id` guardados en disco ("wood", "crush_stone") a sus Resources.
## Al crear contenido nuevo, añádelo aquí: lo que no está en el catálogo no se puede cargar.

@export var items: Array[ItemData] = []
@export var recipes: Array[RecipeData] = []
@export var buildings: Array[BuildingData] = []
@export var veins: Array[VeinData] = []
## Estructuras por reparar (C4, D-115): refugio, Umbral, estabilizador…
@export var repair_sites: Array[RepairSiteData] = []
