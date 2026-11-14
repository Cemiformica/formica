class_name IslandView
extends Node3D
## Dibuja una isla de `WorldState` (B2.4c): una `BuildingView` por construcción colocada.
## Solo muestra (D-046): los datos los cambian el modo construcción y `Simulation`.
## Escucha a su `IslandState` para crear y borrar piezas, y lo rehace todo si se carga una partida.

## Isla de `WorldState` que dibuja.
@export var island_id: StringName = &"dev_sandbox"

var _island: IslandState = null
## Id de la construcción → su vista.
var _views: Dictionary[int, BuildingView] = {}


func _ready() -> void:
	WorldState.state_replaced.connect(_rebuild)
	_rebuild()


## Borra todas las vistas y las vuelve a crear desde los datos (al empezar o al cargar una partida).
func _rebuild() -> void:
	if _island != null and _island.building_placed.is_connected(_on_building_placed):
		_island.building_placed.disconnect(_on_building_placed)
		_island.building_removed.disconnect(_on_building_removed)
	for view: BuildingView in _views.values():
		view.queue_free()
	_views.clear()

	_island = WorldState.get_island(island_id)
	_island.building_placed.connect(_on_building_placed)
	_island.building_removed.connect(_on_building_removed)
	for placed: PlacedBuilding in _island.buildings.values():
		_on_building_placed(placed)


func _on_building_placed(placed: PlacedBuilding) -> void:
	var view := BuildingView.new()
	view.setup(placed)
	add_child(view)
	_views[placed.id] = view


func _on_building_removed(placed: PlacedBuilding) -> void:
	if _views.has(placed.id):
		_views[placed.id].queue_free()
		_views.erase(placed.id)
