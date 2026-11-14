class_name IslandState
extends RefCounted
## Estado de una isla en DATOS: su cuadrícula de ocupación y las construcciones colocadas.
## Existe aunque la isla no esté cargada en pantalla, así que `Simulation` puede hacerla producir.
## Para colocar o quitar se usa SIEMPRE esta clase (no la cuadrícula a mano): mantiene las dos cosas a la par.

## Se emite al colocar una construcción (la vista crea su pieza visible).
signal building_placed(building: PlacedBuilding)
## Se emite al quitar una construcción (la vista borra su pieza visible).
signal building_removed(building: PlacedBuilding)
## Se emite al tender o quitar cables (la vista los vuelve a dibujar).
signal cables_changed
## Se emite cuando cambia lo natural de una casilla: aparece, cambia de fase o desaparece (B2.7).
signal nature_changed(cell: Vector2i)

## Qué casilla ocupa cada construcción. Se reconstruye al cargar a partir de las construcciones.
var grid: OccupancyGrid = OccupancyGrid.new()
## Id → construcción colocada.
var buildings: Dictionary[int, PlacedBuilding] = {}
## Conexiones entre puertos frente a frente (D-066). Cada una es un diccionario
## {"from": PlacedBuilding, "out": PortData, "to": PlacedBuilding, "in": PortData}.
## Se recalculan solo cuando algo cambia (colocar, quitar, cargar), no en cada paso.
var _links: Array[Dictionary] = []
var _links_dirty: bool = true
## Madera y semillas que dan los árboles (B2.7, D-057). Más adelante podrían ir en un Resource por especie.
const TREE_WOOD: int = 4
const STUMP_WOOD: int = 1
## Rocas (B2.8, D-057): piedra que dan, cada cuánto aparece una y cuántas puede haber a la vez.
const ROCK_STONE: int = 2
const ROCK_SPAWN_TIME: float = 45.0
const MAX_ROCKS: int = 12

## Casillas de la isla donde pueden aparecer rocas. Vacío = no aparecen. Es parte de cómo es la isla
## (lo pone su escena), no de la partida, así que no se guarda.
var bounds: Rect2i = Rect2i()
## Generador aleatorio de las rocas. Las pruebas le ponen una semilla fija para repetir el resultado.
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
## Segundos desde la última roca que apareció (se guarda).
var _rock_timer: float = 0.0

## Capa natural (B2.7): casilla → árbol o tocón. Bloquea construir. Se guarda con la isla.
var nature: Dictionary[Vector2i, NatureState] = {}

## Longitud máxima de un cable (m), entre los centros de las dos construcciones.
const MAX_CABLE_LENGTH: float = 12.0

## Cables de energía: pares de ids de construcción, siempre con x < y (D-068).
var cables: Array[Vector2i] = []
## Redes eléctricas: grupos unidos por cables. Se recalculan solo cuando algo cambia.
var _networks: Array[PowerNetwork] = []
var _network_by_id: Dictionary[int, PowerNetwork] = {}
var _networks_dirty: bool = true

## Siguiente id libre. Nunca se reutilizan ids, ni tras quitar ni tras cargar.
var _next_id: int = 1


## ¿Cabe una construcción de este tipo aquí? (casillas libres de construcciones y de naturaleza)
func can_place(data: BuildingData, origin: Vector2i, rotation: int = 0) -> bool:
	if data == null or not grid.can_place(origin, data.size, rotation):
		return false
	for cell: Vector2i in OccupancyGrid.footprint_cells(origin, data.size, rotation):
		if nature.has(cell):
			return false
	return true


## Coloca una construcción. Devuelve la nueva `PlacedBuilding`, o null si no cabe.
func place(data: BuildingData, origin: Vector2i, rotation: int = 0, flipped: bool = false) -> PlacedBuilding:
	if not can_place(data, origin, rotation) or not grid.place(_next_id, origin, data.size, rotation):
		return null
	var placed := PlacedBuilding.new(_next_id, data, origin, rotation, flipped)
	buildings[_next_id] = placed
	_next_id += 1
	_links_dirty = true
	_networks_dirty = true
	building_placed.emit(placed)
	return placed


## Quita una construcción y libera sus casillas. Devuelve la que se quitó (para el reembolso), o null.
func remove(id: int) -> PlacedBuilding:
	if not buildings.has(id):
		return null
	var placed: PlacedBuilding = buildings[id]
	grid.remove(id)
	buildings.erase(id)
	var kept: Array[Vector2i] = []
	for cable: Vector2i in cables:
		if cable.x != id and cable.y != id:
			kept.append(cable)
	var had_cables: bool = kept.size() != cables.size()
	cables = kept
	_links_dirty = true
	_networks_dirty = true
	if had_cables:
		cables_changed.emit()
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
	var cable_list: Array = []
	for cable: Vector2i in cables:
		cable_list.append([cable.x, cable.y])
	var nature_list: Array = []
	for cell: Vector2i in nature:
		nature_list.append(nature[cell].to_data(cell))
	return {"next_id": _next_id, "buildings": list, "cables": cable_list, "nature": nature_list, "rock_timer": _rock_timer}


## Datos del guardado → estado. Ignora con aviso lo dañado, lo desconocido y lo que se solape.
func load_data(data: Dictionary) -> void:
	grid = OccupancyGrid.new()
	buildings.clear()
	_links_dirty = true
	cables.clear()
	nature.clear()
	_rock_timer = clampf(float(data.get("rock_timer", 0.0)), 0.0, ROCK_SPAWN_TIME)
	_networks_dirty = true
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
	var nature_list: Variant = data.get("nature", [])
	if nature_list is Array:
		for entry: Variant in nature_list:
			if not entry is Dictionary or not (entry.get("x") is float or entry.get("x") is int):
				push_warning("IslandState: naturaleza dañada ignorada: %s" % str(entry))
				continue
			var cell := Vector2i(int(entry.get("x", 0)), int(entry.get("y", 0)))
			if int(entry.get("k", NatureState.Kind.TREE)) == NatureState.Kind.ROCK:
				if not add_rock(cell):
					push_warning("IslandState: roca en casilla ocupada ignorada: %s" % str(entry))
				continue
			var stage: int = clampi(int(entry.get("s", NatureState.Stage.MATURE)), 0, NatureState.Stage.MATURE)
			if add_tree(cell, stage as NatureState.Stage):
				nature[cell].timer = clampf(float(entry.get("t", 0.0)), 0.0, NatureState.STAGE_TIME)
			else:
				push_warning("IslandState: árbol en casilla ocupada ignorado: %s" % str(entry))
	var cable_list: Variant = data.get("cables", [])
	if cable_list is Array:
		for entry: Variant in cable_list:
			if not entry is Array or entry.size() != 2 or not add_cable(int(entry[0]), int(entry[1])):
				push_warning("IslandState: cable no válido ignorado: %s" % str(entry))


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


# --- Energía (B2.6a, D-068) ---

## Cables que ya tiene una construcción.
func cable_count(id: int) -> int:
	var count: int = 0
	for cable: Vector2i in cables:
		if cable.x == id or cable.y == id:
			count += 1
	return count


## Distancia entre los centros de dos construcciones (m).
func cable_length(a: int, b: int) -> float:
	var pa: PlacedBuilding = buildings[a]
	var pb: PlacedBuilding = buildings[b]
	return GridMath.footprint_center(pa.origin, pa.data.size, pa.rotation).distance_to(
			GridMath.footprint_center(pb.origin, pb.data.size, pb.rotation))


## ¿Se puede tender un cable entre `a` y `b`? Las dos deben existir, admitir cables, tener una
## conexión libre, no estar ya unidas y estar a `MAX_CABLE_LENGTH` como mucho.
func can_add_cable(a: int, b: int) -> bool:
	if a == b or not buildings.has(a) or not buildings.has(b):
		return false
	if cables.has(_cable_key(a, b)):
		return false
	if cable_count(a) >= buildings[a].data.power_connections or cable_count(b) >= buildings[b].data.power_connections:
		return false
	return cable_length(a, b) <= MAX_CABLE_LENGTH + 0.001


## Clave de traducción del motivo por el que no se puede tender el cable ("" si sí se puede).
func cable_problem(a: int, b: int) -> String:
	if a == b or not buildings.has(a) or not buildings.has(b):
		return "CABLE_INVALID"
	if buildings[a].data.power_connections <= 0 or buildings[b].data.power_connections <= 0:
		return "CABLE_NO_CONNECTOR"
	if cables.has(_cable_key(a, b)):
		return "CABLE_ALREADY"
	if cable_count(a) >= buildings[a].data.power_connections or cable_count(b) >= buildings[b].data.power_connections:
		return "CABLE_FULL"
	if cable_length(a, b) > MAX_CABLE_LENGTH + 0.001:
		return "CABLE_TOO_FAR"
	return ""


## Tiende un cable. Devuelve false (y no toca nada) si no se puede.
func add_cable(a: int, b: int) -> bool:
	if not can_add_cable(a, b):
		return false
	cables.append(_cable_key(a, b))
	_networks_dirty = true
	cables_changed.emit()
	return true


## Quita un cable. Devuelve false si no existía.
func remove_cable(a: int, b: int) -> bool:
	var key: Vector2i = _cable_key(a, b)
	if not cables.has(key):
		return false
	cables.erase(key)
	_networks_dirty = true
	cables_changed.emit()
	return true


## Redes actuales (las recalcula si algo cambió).
func get_networks() -> Array[PowerNetwork]:
	if _networks_dirty:
		_rebuild_networks()
	return _networks


## Red de una construcción, o null si no admite cables.
func get_network(id: int) -> PowerNetwork:
	if _networks_dirty:
		_rebuild_networks()
	return _network_by_id.get(id, null)


## ¿Le llega energía a esta construcción? (está en una red con generadores, sin sobrecarga ni fusible saltado)
func is_powered(id: int) -> bool:
	var network: PowerNetwork = get_network(id)
	return network != null and network.is_powered()


func _cable_key(a: int, b: int) -> Vector2i:
	return Vector2i(mini(a, b), maxi(a, b))


## Agrupa en redes las construcciones unidas por cables (búsqueda en anchura).
## Una construcción con conexiones pero sin cables forma una red ella sola.
func _rebuild_networks() -> void:
	_networks.clear()
	_network_by_id.clear()
	var neighbours: Dictionary[int, Array] = {}
	for cable: Vector2i in cables:
		if not neighbours.has(cable.x):
			neighbours[cable.x] = []
		if not neighbours.has(cable.y):
			neighbours[cable.y] = []
		neighbours[cable.x].append(cable.y)
		neighbours[cable.y].append(cable.x)
	for id: int in buildings:
		if buildings[id].data.power_connections <= 0 or _network_by_id.has(id):
			continue
		var network := PowerNetwork.new()
		var pending: Array[int] = [id]
		_network_by_id[id] = network
		while not pending.is_empty():
			var current: int = pending.pop_back()
			network.add(buildings[current])
			for other: int in neighbours.get(current, []):
				if not _network_by_id.has(other):
					_network_by_id[other] = network
					pending.append(other)
		_networks.append(network)
	_networks_dirty = false


# --- Naturaleza (B2.7, D-057, D-069) ---

## Planta un árbol en la fase indicada. Devuelve false si la casilla tiene una construcción o ya hay algo.
func add_tree(cell: Vector2i, stage: NatureState.Stage = NatureState.Stage.MATURE) -> bool:
	if nature.has(cell) or grid.get_occupant(cell) != 0:
		return false
	nature[cell] = NatureState.new(NatureState.Kind.TREE, stage)
	nature_changed.emit(cell)
	return true


## Tala un árbol maduro: queda un tocón (que rebrotará solo). Devuelve lo que da: 4 de madera y,
## a mano, 1 semilla; el talador no da semilla. Diccionario vacío si ahí no hay un árbol maduro.
func chop_tree(cell: Vector2i, with_seed: bool) -> Dictionary[ItemData, int]:
	var result: Dictionary[ItemData, int] = {}
	if not nature.has(cell) or not nature[cell].is_mature_tree():
		return result
	nature[cell].stage = NatureState.Stage.STUMP
	nature[cell].timer = 0.0
	result[Content.find_item(&"wood")] = TREE_WOOD
	if with_seed:
		result[Content.find_item(&"seed")] = 1
	nature_changed.emit(cell)
	return result


## Arranca un tocón: da 1 de madera y libera la casilla. Diccionario vacío si ahí no hay un tocón.
func uproot_stump(cell: Vector2i) -> Dictionary[ItemData, int]:
	var result: Dictionary[ItemData, int] = {}
	if not nature.has(cell) or not nature[cell].is_stump():
		return result
	nature.erase(cell)
	result[Content.find_item(&"wood")] = STUMP_WOOD
	nature_changed.emit(cell)
	return result


## Pone una roca. Devuelve false si la casilla tiene una construcción o ya hay algo.
func add_rock(cell: Vector2i) -> bool:
	if nature.has(cell) or grid.get_occupant(cell) != 0:
		return false
	nature[cell] = NatureState.new(NatureState.Kind.ROCK)
	nature_changed.emit(cell)
	return true


## Pica una roca: da 2 de piedra y libera la casilla. Diccionario vacío si ahí no hay una roca.
func mine_rock(cell: Vector2i) -> Dictionary[ItemData, int]:
	var result: Dictionary[ItemData, int] = {}
	if not nature.has(cell) or not nature[cell].is_rock():
		return result
	nature.erase(cell)
	result[Content.find_item(&"stone")] = ROCK_STONE
	nature_changed.emit(cell)
	return result


## Rocas que hay ahora en la isla.
func rock_count() -> int:
	var count: int = 0
	for state: NatureState in nature.values():
		if state.is_rock():
			count += 1
	return count


## Hace crecer los árboles y rebrotar los tocones `dt` segundos, y cada `ROCK_SPAWN_TIME` hace aparecer
## una roca en una casilla libre al azar dentro de `bounds` (si hay menos de `MAX_ROCKS`). Lo llama `Simulation`.
func step_nature(dt: float) -> void:
	for cell: Vector2i in nature:
		if nature[cell].grow(dt):
			nature_changed.emit(cell)
	if not bounds.has_area():
		return
	_rock_timer += dt
	if _rock_timer + 0.0001 < ROCK_SPAWN_TIME:
		return
	_rock_timer = 0.0
	if rock_count() >= MAX_ROCKS:
		return
	var free_cells: Array[Vector2i] = []
	for x: int in range(bounds.position.x, bounds.end.x):
		for y: int in range(bounds.position.y, bounds.end.y):
			var cell := Vector2i(x, y)
			if not nature.has(cell) and grid.get_occupant(cell) == 0:
				free_cells.append(cell)
	if not free_cells.is_empty():
		add_rock(free_cells[rng.randi_range(0, free_cells.size() - 1)])
