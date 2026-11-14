class_name IslandView
extends Node3D
## Dibuja una isla de `WorldState` (B2.4c): una `BuildingView` por construcción colocada.
## Solo muestra (D-046): los datos los cambian el modo construcción y `Simulation`.
## Escucha a su `IslandState` para crear y borrar piezas, y lo rehace todo si se carga una partida.
## También dibuja los cables de energía como líneas finas entre sus dos construcciones (B2.6b)
## y la naturaleza: un `TreeView` por árbol o tocón (B2.7b).

const CABLE_COLOR: Color = Color(0.1, 0.1, 0.1)
const CABLE_THICKNESS: float = 0.04

## Isla de `WorldState` que dibuja.
@export var island_id: StringName = &"dev_sandbox"

var _island: IslandState = null
## Id de la construcción → su vista.
var _views: Dictionary[int, BuildingView] = {}
## Casilla → vista de su árbol o tocón.
var _tree_views: Dictionary[Vector2i, TreeView] = {}
## Líneas de los cables dibujados.
var _cable_meshes: Array[MeshInstance3D] = []
var _cable_material: StandardMaterial3D


func _ready() -> void:
	_cable_material = StandardMaterial3D.new()
	_cable_material.albedo_color = CABLE_COLOR
	WorldState.state_replaced.connect(_rebuild)
	_rebuild()


## Borra todas las vistas y las vuelve a crear desde los datos (al empezar o al cargar una partida).
func _rebuild() -> void:
	if _island != null and _island.building_placed.is_connected(_on_building_placed):
		_island.building_placed.disconnect(_on_building_placed)
		_island.building_removed.disconnect(_on_building_removed)
		_island.cables_changed.disconnect(_redraw_cables)
		_island.nature_changed.disconnect(_on_nature_changed)
	for view: BuildingView in _views.values():
		view.queue_free()
	_views.clear()
	for tree: TreeView in _tree_views.values():
		tree.queue_free()
	_tree_views.clear()

	_island = WorldState.get_island(island_id)
	_island.building_placed.connect(_on_building_placed)
	_island.building_removed.connect(_on_building_removed)
	_island.cables_changed.connect(_redraw_cables)
	_island.nature_changed.connect(_on_nature_changed)
	for placed: PlacedBuilding in _island.buildings.values():
		_on_building_placed(placed)
	_redraw_cables()
	for cell: Vector2i in _island.nature:
		_on_nature_changed(cell)


func _on_building_placed(placed: PlacedBuilding) -> void:
	var view := BuildingView.new()
	view.setup(placed, _island)
	add_child(view)
	_views[placed.id] = view


func _on_building_removed(placed: PlacedBuilding) -> void:
	if _views.has(placed.id):
		_views[placed.id].queue_free()
		_views.erase(placed.id)


## Algo natural cambió en `cell`: crea, actualiza o borra su vista.
func _on_nature_changed(cell: Vector2i) -> void:
	if not _island.nature.has(cell):
		if _tree_views.has(cell):
			_tree_views[cell].queue_free()
			_tree_views.erase(cell)
		return
	if not _tree_views.has(cell):
		var view := TreeView.new()
		view.setup(cell, _island)
		add_child(view)
		_tree_views[cell] = view
	_tree_views[cell].refresh()


## Borra las líneas y las vuelve a crear desde `IslandState.cables` (son pocas: no merece la pena más).
func _redraw_cables() -> void:
	for mesh: MeshInstance3D in _cable_meshes:
		mesh.queue_free()
	_cable_meshes.clear()
	for cable: Vector2i in _island.cables:
		if not _island.buildings.has(cable.x) or not _island.buildings.has(cable.y):
			continue
		var line := MeshInstance3D.new()
		add_child(line)
		place_line(line, BuildingView.cable_anchor(_island.buildings[cable.x]), BuildingView.cable_anchor(_island.buildings[cable.y]), CABLE_THICKNESS)
		line.material_override = _cable_material
		_cable_meshes.append(line)


## Convierte `line` en una barra fina de `from` a `to` (también la usa el cable provisional del modo construcción).
static func place_line(line: MeshInstance3D, from: Vector3, to: Vector3, thickness: float) -> void:
	var length: float = from.distance_to(to)
	var box := line.mesh as BoxMesh
	if box == null:
		box = BoxMesh.new()
		line.mesh = box
	box.size = Vector3(thickness, thickness, maxf(length, 0.01))
	line.global_position = (from + to) * 0.5
	if length > 0.001:
		var up: Vector3 = Vector3.UP
		if absf((to - from).normalized().dot(Vector3.UP)) > 0.99:
			up = Vector3.FORWARD # casi vertical: otro «arriba» para que look_at no falle
		line.look_at(to, up)
