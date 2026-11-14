class_name IslandState
extends RefCounted
## Estado de una isla en DATOS: su cuadrícula de ocupación y las construcciones colocadas.
## Existe aunque la isla no esté cargada en pantalla, así que `Simulation` puede hacerla producir.
## Para colocar o quitar se usa SIEMPRE esta clase (no la cuadrícula a mano): mantiene las dos cosas a la par.

## Se emite al colocar una construcción (la vista crea su pieza visible).
signal building_placed(building: PlacedBuilding)
## Se emite al quitar una construcción (la vista borra su pieza visible).
signal building_removed(building: PlacedBuilding)

## Qué casilla ocupa cada construcción. Se reconstruye al cargar a partir de las construcciones.
var grid: OccupancyGrid = OccupancyGrid.new()
## Id → construcción colocada.
var buildings: Dictionary[int, PlacedBuilding] = {}
## Conexiones entre puertos frente a frente (D-066). Cada una es un diccionario
## {"from": PlacedBuilding, "out": PortData, "to": PlacedBuilding, "in": PortData}.
## Se recalculan solo cuando algo cambia (colocar, quitar, cargar), no en cada paso.
var _links: Array[Dictionary] = []
var _links_dirty: bool = true
## Siguiente id libre. Nunca se reutilizan ids, ni tras quitar ni tras cargar.
var _next_id: int = 1


## ¿Cabe una construcción de este tipo aquí?
func can_place(data: BuildingData, origin: Vector2i, rotation: int = 0) -> bool:
	return data != null and grid.can_place(origin, data.size, rotation)


## Coloca una construcción. Devuelve la nueva `PlacedBuilding`, o null si no cabe.
func place(data: BuildingData, origin: Vector2i, rotation: int = 0, flipped: bool = false) -> PlacedBuilding:
	if data == null or not grid.place(_next_id, origin, data.size, rotation):
		return null
	var placed := PlacedBuilding.new(_next_id, data, origin, rotation, flipped)
	buildings[_next_id] = placed
	_next_id += 1
	_links_dirty = true
	building_placed.emit(placed)
	return placed


## Quita una construcción y libera sus casillas. Devuelve la que se quitó (para el reembolso), o null.
func remove(id: int) -> PlacedBuilding:
	if not buildings.has(id):
		return null
	var placed: PlacedBuilding = buildings[id]
	grid.remove(id)
	buildings.erase(id)
	_links_dirty = true
	building_removed.emit(placed)
	return placed


## Construcción que ocupa esa casilla, o null.
func get_at(cell: Vector2i) -> PlacedBuilding:
	return buildings.get(grid.get_occupant(cell), null)


## Estado → datos para el guardado. La cuadrícula no se guarda: se recalcula al cargar.
func to_data() -> Dictionary:
	var list: Array = []
	for id: int in buildings:
		list.append(buildings[id].to_data())
	return {"next_id": _next_id, "buildings": list}


## Datos del guardado → estado. Ignora con aviso lo dañado, lo desconocido y lo que se solape.
func load_data(data: Dictionary) -> void:
	grid = OccupancyGrid.new()
	buildings.clear()
	_links_dirty = true
	var max_id: int = 0
	var list: Variant = data.get("buildings", [])
	if list is Array:
		for entry: Variant in list:
			if not entry is Dictionary:
				push_warning("IslandState: entrada dañada ignorada: %s" % str(entry))
				continue
			var placed: PlacedBuilding = PlacedBuilding.from_data(entry)
			if placed == null:
				continue
			if placed.id <= 0 or not grid.place(placed.id, placed.origin, placed.data.size, placed.rotation):
				push_warning("IslandState: construcción %d no válida o solapada, ignorada" % placed.id)
				continue
			buildings[placed.id] = placed
			max_id = maxi(max_id, placed.id)
	_next_id = maxi(int(data.get("next_id", 1)), max_id + 1)


## Conexiones actuales (las recalcula si algo cambió).
func get_links() -> Array[Dictionary]:
	if _links_dirty:
		_rebuild_links()
	return _links


## Una salida conecta con una entrada si están frente a frente: la salida apunta a la casilla de la
## entrada y la entrada apunta a la casilla de la salida. Vale para máquina, cinta y máquina pegada.
func _rebuild_links() -> void:
	_links.clear()
	for from: PlacedBuilding in buildings.values():
		for out_port: PortData in from.data.ports:
			if out_port.kind != PortData.Kind.OUTPUT:
				continue
			var out_cell: Vector2i = out_port.get_grid_cell(from.origin, from.data.size, from.rotation, from.flipped)
			var target_cell: Vector2i = out_port.get_target_cell(from.origin, from.data.size, from.rotation, from.flipped)
			var to: PlacedBuilding = get_at(target_cell)
			if to == null or to == from:
				continue
			for in_port: PortData in to.data.ports:
				if in_port.kind != PortData.Kind.INPUT:
					continue
				if in_port.get_grid_cell(to.origin, to.data.size, to.rotation, to.flipped) == target_cell \
						and in_port.get_target_cell(to.origin, to.data.size, to.rotation, to.flipped) == out_cell:
					_links.append({"from": from, "out": out_port, "to": to, "in": in_port})
					break
	_links_dirty = false
