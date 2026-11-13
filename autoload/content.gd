extends Node
## Autoload `Content`: el catálogo del juego, de solo lectura (D-048).
## Traduce los `id` guardados en disco ("wood", "crush_stone") a sus Resources.
## Uso: `Content.find_item(&"wood")`. Devuelve null si el id no existe.
## Para añadir contenido nuevo no se toca este script: se añade el .tres a `content/catalog.tres`.

const CATALOG: Catalog = preload("res://content/catalog.tres")

var _items_by_id: Dictionary[StringName, ItemData] = {}
var _recipes_by_id: Dictionary[StringName, RecipeData] = {}
var _buildings_by_id: Dictionary[StringName, BuildingData] = {}


func _ready() -> void:
	for item: ItemData in CATALOG.items:
		_register(_items_by_id, item, item.id, "ítem")
	for recipe: RecipeData in CATALOG.recipes:
		_register(_recipes_by_id, recipe, recipe.id, "receta")
	for building: BuildingData in CATALOG.buildings:
		_register(_buildings_by_id, building, building.id, "edificio")


## Ítem con ese id (null si no existe).
func find_item(id: StringName) -> ItemData:
	return _items_by_id.get(id, null)


## Receta con ese id (null si no existe).
func find_recipe(id: StringName) -> RecipeData:
	return _recipes_by_id.get(id, null)


## Edificio con ese id (null si no existe).
func find_building(id: StringName) -> BuildingData:
	return _buildings_by_id.get(id, null)


## Añade `resource` a `index` con su id. Avisa (y lo salta) si el id está vacío o repetido.
func _register(index: Dictionary, resource: Resource, id: StringName, kind: String) -> void:
	if resource == null:
		push_warning("Catálogo: hay una casilla vacía en la lista de %s" % kind)
		return
	if id == &"" or index.has(id):
		push_warning("Catálogo: id de %s vacío o repetido: '%s' (%s)" % [kind, id, resource.resource_path])
		return
	index[id] = resource
