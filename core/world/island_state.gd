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
## Se emite al añadir una veta (la vista crea su pieza visible). Las vetas nunca se quitan.
signal vein_added(origin: Vector2i)
## Cambió el agua de la isla (B3.7, D-094).
signal water_changed
## Estructuras por reparar (C4, D-115): se añadió una, se entregó algo a una pieza o se completó entera.
signal repair_site_added(origin: Vector2i)
signal repair_changed(origin: Vector2i, piece_index: int)
signal repair_completed(origin: Vector2i)

## Qué casilla ocupa cada construcción. Se reconstruye al cargar a partir de las construcciones.
var grid: OccupancyGrid = OccupancyGrid.new()
## Id → construcción colocada.
var buildings: Dictionary[int, PlacedBuilding] = {}
## Conexiones entre puertos frente a frente (D-066). Cada una es un diccionario
## {"from": PlacedBuilding, "out": PortData, "to": PlacedBuilding, "in": PortData}.
## Se recalculan solo cuando algo cambia (colocar, quitar, cargar), no en cada paso.
var _links: Array[Dictionary] = []
## Construcciones a las que entra alguna conexión, en orden (las recorre `Simulation`, C2b).
## Cada construcción guarda además sus conexiones en `links_out` y `links_in`.
var _link_targets: Array[PlacedBuilding] = []
var _links_dirty: bool = true
var _dropping: bool = false
## Madera que dan los árboles (B2.7, D-057); la semilla depende de la especie (NatureState.SEED_ITEMS).
const TREE_WOOD: int = 4
const STUMP_WOOD: int = 1
## Rocas (B2.8, D-057): piedra que dan, cada cuánto aparece una y cuántas puede haber a la vez.
## Se recogen de una sola E y dan 1 de piedra (César, D-090); por eso aparecen más a menudo y caben
## más a la vez que antes (antes: 2 de piedra, cada 45 s, como mucho 12).
const ROCK_STONE: int = 1
const ROCK_SPAWN_TIME: float = 20.0
const MAX_ROCKS: int = 16
## Palos caídos (C3, César): se recogen con la E, como las rocas, y dan madera; así se puede empezar sin
## herramientas. Aparecen solos con su propio ritmo.
const STICKS_WOOD: int = 1   # como las rocas, 1 de piedra (César)
const STICKS_SPAWN_TIME: float = 30.0
const MAX_STICKS: int = 10

## Casillas de la isla donde pueden aparecer rocas. Vacío = no aparecen. Es parte de cómo es la isla
## (lo pone su escena), no de la partida, así que no se guarda.
var bounds: Rect2i = Rect2i()
## Generador aleatorio de las rocas. Las pruebas le ponen una semilla fija para repetir el resultado.
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
## Segundos desde la última roca que apareció (se guarda).
var _rock_timer: float = 0.0
## Segundos desde los últimos palos que aparecieron (se guarda). `spawn_sticks` = false los apaga (pruebas).
var _sticks_timer: float = 0.0
var spawn_sticks: bool = true

## Capa natural (B2.7): casilla → árbol o tocón. Bloquea construir. Se guarda con la isla.
var nature: Dictionary[Vector2i, NatureState] = {}
## Vetas (B3.7, D-090): esquina (x e y mínimas) → tipo. Ocupan 3×3 y nunca se agotan ni se quitan.
## Se guardan con la isla, porque al cargar se crea una isla nueva a partir de los datos.
var veins: Dictionary[Vector2i, VeinData] = {}
## Agua (canales y ríos, D-094): casilla → dirección en la que corre (un paso de la cuadrícula). Es
## terreno: bloquea construir (salvo lo que la necesita, como la rueda hidráulica), plantar y las rocas.
## Se puede vadear andando. Se guarda con la isla, como las vetas.
var water: Dictionary[Vector2i, Vector2i] = {}
## Casilla → esquina de la veta que la cubre (para preguntar rápido «¿hay veta aquí?»).
var _vein_cells: Dictionary[Vector2i, Vector2i] = {}
## Estructuras por reparar (C4, D-115): esquina → estructura. Ocupan sus casillas como el terreno (no se
## desmontan ni se mueven) y se guardan con la isla, con lo entregado a cada pieza.
var repair_sites: Dictionary[Vector2i, RepairSite] = {}
## Casilla → esquina de la estructura que la ocupa.
var _repair_cells: Dictionary[Vector2i, Vector2i] = {}

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


## ¿Cabe una construcción de este tipo aquí? (casillas libres de construcciones, naturaleza y vetas)
## Extractores (D-090): la cabeza debe ir sobre una casilla del BORDE de una veta; el resto, fuera.
func can_place(data: BuildingData, origin: Vector2i, rotation: int = 0) -> bool:
	return placement_problem(data, origin, rotation) == ""


## Por qué no cabe aquí (clave de traducción), o "" si cabe. Lo usa el modo construcción para avisar.
func placement_problem(data: BuildingData, origin: Vector2i, rotation: int = 0) -> String:
	if data == null or not grid.can_place(origin, data.size, rotation):
		return "BUILD_NO_ROOM"
	var head := Vector2i(2147483647, 2147483647) # ninguna casilla
	if data.extract_time > 0.0:
		head = PlacedBuilding.head_cell_for(data, origin, rotation)
		if not is_vein_edge(head):
			return "BUILD_NEEDS_VEIN"
	# Rueda hidráulica (D-094): sus casillas de agua tienen que ser agua que corre a lo largo de su eje.
	var wet: Dictionary[Vector2i, bool] = {}
	if not data.water_cells.is_empty():
		var axis: Vector2i = GridMath.rotate_offset(Vector2i(0, 1), rotation)
		for local: Vector2i in data.water_cells:
			var cell: Vector2i = OccupancyGrid.local_to_cell(origin, data.size, rotation, local)
			var flow: Vector2i = water.get(cell, Vector2i.ZERO)
			if flow == Vector2i.ZERO or (flow != axis and flow != -axis):
				return "BUILD_NEEDS_WATER"
			wet[cell] = true
	for cell: Vector2i in OccupancyGrid.footprint_cells(origin, data.size, rotation):
		if nature.has(cell) or (_vein_cells.has(cell) and cell != head) or (water.has(cell) and not wet.has(cell)) \
				or _repair_cells.has(cell):
			return "BUILD_NO_ROOM"
	return ""


## Coloca una construcción. Devuelve la nueva `PlacedBuilding`, o null si no cabe.
## `turn`: solo cajas logísticas, lado de la salida (0 = recta, 1 = derecha, 2 = izquierda).
func place(data: BuildingData, origin: Vector2i, rotation: int = 0, flipped: bool = false, turn: int = 0) -> PlacedBuilding:
	if not can_place(data, origin, rotation) or not grid.place(_next_id, origin, data.size, rotation):
		return null
	var placed := PlacedBuilding.new(_next_id, data, origin, rotation, flipped, turn)
	if placed.is_extractor():
		placed.set_vein_item(vein_at(PlacedBuilding.head_cell_for(data, origin, rotation)).item)
	buildings[_next_id] = placed
	_next_id += 1
	_links_dirty = true
	_networks_dirty = true
	building_placed.emit(placed)
	return placed


## Solo para vistas previas (C2b: el fantasma de un tramo de cintas, en una isla de prueba que no se ve):
## pone una construcción SIN comprobar si cabe ni buscar su veta, y sin avisar a ninguna vista.
func add_for_preview(data: BuildingData, origin: Vector2i, rotation: int = 0, flipped: bool = false, turn: int = 0) -> PlacedBuilding:
	var placed := PlacedBuilding.new(_next_id, data, origin, rotation, flipped, turn)
	grid.place(_next_id, origin, data.size, rotation)
	buildings[_next_id] = placed
	_next_id += 1
	_links_dirty = true
	return placed


## Vuelve a poner una construcción que se había quitado para moverla (C2.5), la MISMA, con su id y todo lo
## que lleva dentro, en otro sitio y con otro giro. Devuelve false si ahí no cabe (y no la pone).
func drop(placed: PlacedBuilding, origin: Vector2i, rotation: int = 0, flipped: bool = false, turn: int = 0) -> bool:
	if placed == null or buildings.has(placed.id) or not can_place(placed.data, origin, rotation):
		return false
	if not grid.place(placed.id, origin, placed.data.size, rotation):
		return false
	placed.origin = origin
	placed.rotation = posmod(rotation, 4)
	placed.flipped = flipped and placed.data.can_flip()
	if placed.data.output_turns:
		placed.output_turn = posmod(turn, BuildingData.TURN_COUNT)
	placed.moved()
	if placed.is_extractor():
		placed.set_vein_item(vein_at(PlacedBuilding.head_cell_for(placed.data, origin, rotation)).item)
	buildings[placed.id] = placed
	_links_dirty = true
	_networks_dirty = true
	# La vista distingue soltar de construir (C2b): al soltar no hay efecto de construir.
	_dropping = true
	building_placed.emit(placed)
	_dropping = false
	return true


## ¿Se está avisando de una construcción que se SUELTA tras moverla (no de una nueva)? Solo es true
## mientras se emite `building_placed` desde `drop()`.
func is_dropping() -> bool:
	return _dropping


## Cables de una construcción (pares de ids), p. ej. para recuperarlos después de moverla.
func cables_of(id: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for cable: Vector2i in cables:
		if cable.x == id or cable.y == id:
			result.append(cable)
	return result


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


## Reembolso total de varias construcciones (C2.1): coste y contenido de todas. Ids que no existan, ignorados.
func refund_for(ids: Array[int]) -> Dictionary[ItemData, int]:
	var result: Dictionary[ItemData, int] = {}
	for id: int in ids:
		var placed: PlacedBuilding = buildings.get(id, null)
		if placed == null:
			continue
		var refund: Dictionary[ItemData, int] = placed.get_refund()
		for item: ItemData in refund:
			result[item] = result.get(item, 0) + refund[item]
	return result


## Desmonta varias construcciones de una vez y mete el reembolso en `into` (D-089, D-033). Todo o nada:
## si el reembolso no cabe entero, no quita ninguna y devuelve false. Los cables se quitan con ellas.
func dismantle(ids: Array[int], into: Inventory) -> bool:
	var refund: Dictionary[ItemData, int] = refund_for(ids)
	if not into.can_add_all(refund):
		return false
	for id: int in ids:
		remove(id)
	for item: ItemData in refund:
		into.add_item(item, refund[item])
	return true


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
	var vein_list: Array = []
	for vein_origin: Vector2i in veins:
		vein_list.append({"id": String(veins[vein_origin].id), "x": vein_origin.x, "y": vein_origin.y})
	var water_list: Array = []
	for cell: Vector2i in water:
		water_list.append([cell.x, cell.y, water[cell].x, water[cell].y])
	var repair_list: Array = []
	for site_origin: Vector2i in repair_sites:
		repair_list.append(repair_sites[site_origin].to_data())
	return {"next_id": _next_id, "buildings": list, "cables": cable_list, "nature": nature_list, "veins": vein_list,
			"water": water_list, "repair_sites": repair_list, "rock_timer": _rock_timer, "sticks_timer": _sticks_timer}


## Datos del guardado → estado. Ignora con aviso lo dañado, lo desconocido y lo que se solape.
func load_data(data: Dictionary) -> void:
	grid = OccupancyGrid.new()
	buildings.clear()
	_links_dirty = true
	cables.clear()
	nature.clear()
	veins.clear()
	_vein_cells.clear()
	repair_sites.clear()
	_repair_cells.clear()
	water.clear()
	# El agua y las vetas primero: son parte del terreno.
	var water_list: Variant = data.get("water", [])
	if water_list is Array:
		for entry: Variant in water_list:
			if entry is Array and entry.size() == 4:
				water[Vector2i(int(entry[0]), int(entry[1]))] = Vector2i(int(entry[2]), int(entry[3]))
			else:
				push_warning("IslandState: agua dañada ignorada: %s" % str(entry))
	water_changed.emit()
	# Las vetas primero: son parte del terreno, y las cabezas de los extractores van encima.
	var vein_list: Variant = data.get("veins", [])
	if vein_list is Array:
		for entry: Variant in vein_list:
			if not entry is Dictionary:
				push_warning("IslandState: veta dañada ignorada: %s" % str(entry))
				continue
			var vein_data: VeinData = Content.find_vein(StringName(str(entry.get("id", ""))))
			if vein_data == null or not add_vein(vein_data, Vector2i(int(entry.get("x", 0)), int(entry.get("y", 0)))):
				push_warning("IslandState: veta desconocida o solapada ignorada: %s" % str(entry))
	# Las estructuras por reparar, también antes que las construcciones (C4).
	var repair_list: Variant = data.get("repair_sites", [])
	if repair_list is Array:
		for entry: Variant in repair_list:
			var site: RepairSite = RepairSite.from_data(entry) if entry is Dictionary else null
			if site == null or not _add_repair_site(site):
				push_warning("IslandState: estructura por reparar desconocida o solapada ignorada: %s" % str(entry))
	_rock_timer = clampf(float(data.get("rock_timer", 0.0)), 0.0, ROCK_SPAWN_TIME)
	_sticks_timer = clampf(float(data.get("sticks_timer", 0.0)), 0.0, STICKS_SPAWN_TIME)
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
			if placed.is_extractor():
				var vein: VeinData = vein_at(PlacedBuilding.head_cell_for(placed.data, placed.origin, placed.rotation))
				placed.set_vein_item(vein.item if vein != null else null) # sin veta debajo: no trabaja
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
			if int(entry.get("k", NatureState.Kind.TREE)) == NatureState.Kind.STICKS:
				if not add_sticks(cell):
					push_warning("IslandState: palos en casilla ocupada ignorados: %s" % str(entry))
				continue
			var stage: int = clampi(int(entry.get("s", NatureState.Stage.MATURE)), 0, NatureState.Stage.MATURE)
			# Especie (C1.9); las partidas de antes no la guardaban y salen con la regla de los salvajes.
			var species := StringName(str(entry.get("sp", "")))
			if not NatureState.SEED_ITEMS.has(species):
				species = &""
			if add_tree(cell, stage as NatureState.Stage, species):
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


## Lista vacía compartida (solo lectura) para un id que no existe.
const _NO_LINKS: Array = []


## Conexiones que salen de la construcción `id` (vacío si ninguna). No modificar la lista devuelta.
func get_links_from(id: int) -> Array:
	if _links_dirty:
		_rebuild_links()
	var placed: PlacedBuilding = buildings.get(id)
	return placed.links_out if placed != null else _NO_LINKS


## Conexiones que entran en la construcción `id` (vacío si ninguna). No modificar la lista devuelta.
func get_links_into(id: int) -> Array:
	if _links_dirty:
		_rebuild_links()
	var placed: PlacedBuilding = buildings.get(id)
	return placed.links_in if placed != null else _NO_LINKS


## Construcciones a las que entra alguna conexión. Lo recorre `Simulation` en cada paso. No modificar.
func get_link_targets() -> Array[PlacedBuilding]:
	if _links_dirty:
		_rebuild_links()
	return _link_targets


## Una salida conecta con una entrada si están frente a frente: la salida apunta a la casilla de la
## entrada y la entrada apunta a la casilla de la salida. Vale para máquina, cinta y máquina pegada.
## Cintas en L, T y X (C2b, D-118): los costados de una cinta son puertos flexibles que se conectan con
## un puerto FIJO de enfrente (salida fija → costado como entrada; costado como salida → entrada fija).
## Un costado nunca se conecta con otro costado: las cintas paralelas no se mezclan.
func _rebuild_links() -> void:
	_links.clear()
	_link_targets.clear()
	for placed: PlacedBuilding in buildings.values():
		placed.links_out = []
		placed.links_in = []
	for from: PlacedBuilding in buildings.values():
		for out_port: PortData in from.get_ports():
			if out_port.kind == PortData.Kind.OUTPUT:
				_try_link(from, out_port, true)
		for out_port: PortData in from.get_flexible_ports():
			if out_port.kind == PortData.Kind.OUTPUT:
				_try_link(from, out_port, false)
	_link_back_to_back()
	_links_dirty = false


## Traseras enfrentadas (C2b, como en Alchemy Factory: da igual hacia dónde mire la cinta de un cruce).
## Si una cinta recibe algo y su trasera da a la trasera de otra cinta que no recibe nada, le pasa los
## ítems por ahí. Si las dos reciben, o ninguna, no se unen.
func _link_back_to_back() -> void:
	for from: PlacedBuilding in buildings.values():
		if not from.is_belt() or from.links_in.is_empty() or _belt_back_used(from):
			continue
		var to: PlacedBuilding = get_at(_belt_back_cell(from))
		if to == null or to == from or not to.is_belt() or not to.links_in.is_empty() or _belt_back_used(to):
			continue
		if _belt_back_cell(to) != from.origin:
			continue
		for in_port: PortData in to.get_ports():
			if in_port.kind == PortData.Kind.INPUT:
				_add_link(from, PlacedBuilding.belt_back_output_port(), to, in_port)
				break


## Casilla que queda detrás de una cinta (las cintas son de 1×1).
func _belt_back_cell(belt: PlacedBuilding) -> Vector2i:
	return belt.origin + PortData.side_offset(PortData.transform_side(PortData.PortSide.SOUTH, belt.rotation, false))


## ¿Tiene ya la cinta alguna conexión por su trasera?
func _belt_back_used(belt: PlacedBuilding) -> bool:
	for link: Dictionary in belt.links_in:
		if (link["in"] as PortData).side == PortData.PortSide.SOUTH:
			return true
	for link: Dictionary in belt.links_out:
		if (link["out"] as PortData).side == PortData.PortSide.SOUTH:
			return true
	return false


## Busca enfrente de `out_port` una entrada que lo mire. Si la salida es fija, también vale un costado
## de cinta (`allow_flexible`); si la salida es un costado, solo una entrada fija.
func _try_link(from: PlacedBuilding, out_port: PortData, allow_flexible: bool) -> void:
	var out_cell: Vector2i = out_port.get_grid_cell(from.origin, from.data.size, from.rotation, from.flipped)
	var target_cell: Vector2i = out_port.get_target_cell(from.origin, from.data.size, from.rotation, from.flipped)
	var to: PlacedBuilding = get_at(target_cell)
	if to == null or to == from:
		return
	var candidates: Array[PortData] = []
	candidates.append_array(to.get_ports())
	if allow_flexible:
		candidates.append_array(to.get_flexible_ports())
	for in_port: PortData in candidates:
		if in_port.kind != PortData.Kind.INPUT:
			continue
		if in_port.get_grid_cell(to.origin, to.data.size, to.rotation, to.flipped) == target_cell \
				and in_port.get_target_cell(to.origin, to.data.size, to.rotation, to.flipped) == out_cell:
			_add_link(from, out_port, to, in_port)
			return


func _add_link(from: PlacedBuilding, out_port: PortData, to: PlacedBuilding, in_port: PortData) -> void:
	var link: Dictionary = {"from": from, "out": out_port, "to": to, "in": in_port}
	_links.append(link)
	from.links_out.append(link)
	if to.links_in.is_empty():
		_link_targets.append(to)
	to.links_in.append(link)


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

## ¿Se puede plantar aquí? (no hay construcción, ni naturaleza, ni veta, ni agua)
func can_plant(cell: Vector2i) -> bool:
	return _is_free_ground(cell)


## Planta un árbol en la fase indicada. `species` vacía = árbol salvaje (la especie la decide su casilla).
## Devuelve false si la casilla tiene una construcción o ya hay algo.
func add_tree(cell: Vector2i, stage: NatureState.Stage = NatureState.Stage.MATURE, species: StringName = &"") -> bool:
	if not can_plant(cell):
		return false
	if species == &"":
		species = NatureState.wild_species(cell)
	nature[cell] = NatureState.new(NatureState.Kind.TREE, stage, species)
	nature_changed.emit(cell)
	return true


## Tala un árbol maduro: queda un tocón (que rebrotará solo). Devuelve lo que da: 4 de madera y,
## a mano, 1 semilla de su especie (bellota o piña, C1.9); el talador no da semilla. Diccionario vacío si
## ahí no hay un árbol maduro.
func chop_tree(cell: Vector2i, with_seed: bool) -> Dictionary[ItemData, int]:
	var result: Dictionary[ItemData, int] = {}
	if not nature.has(cell) or not nature[cell].is_mature_tree():
		return result
	nature[cell].stage = NatureState.Stage.STUMP
	nature[cell].timer = 0.0
	result[Content.find_item(&"wood")] = TREE_WOOD
	if with_seed:
		var seed_item: ItemData = Content.find_item(NatureState.SEED_ITEMS[nature[cell].species])
		if seed_item != null:
			result[seed_item] = 1
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
	if not _is_free_ground(cell):
		return false
	nature[cell] = NatureState.new(NatureState.Kind.ROCK)
	nature_changed.emit(cell)
	return true


## Recoge una roca: da `ROCK_STONE` de piedra y libera la casilla. Diccionario vacío si ahí no hay una roca.
func mine_rock(cell: Vector2i) -> Dictionary[ItemData, int]:
	var result: Dictionary[ItemData, int] = {}
	if not nature.has(cell) or not nature[cell].is_rock():
		return result
	nature.erase(cell)
	result[Content.find_item(&"stone")] = ROCK_STONE
	nature_changed.emit(cell)
	return result


## Pone unos palos caídos. Devuelve false si la casilla tiene una construcción o ya hay algo.
func add_sticks(cell: Vector2i) -> bool:
	if not _is_free_ground(cell):
		return false
	nature[cell] = NatureState.new(NatureState.Kind.STICKS)
	nature_changed.emit(cell)
	return true


## Recoge unos palos: da `STICKS_WOOD` de madera y libera la casilla. Vacío si ahí no hay palos.
func pick_sticks(cell: Vector2i) -> Dictionary[ItemData, int]:
	var result: Dictionary[ItemData, int] = {}
	if not nature.has(cell) or not nature[cell].is_sticks():
		return result
	nature.erase(cell)
	result[Content.find_item(&"wood")] = STICKS_WOOD
	nature_changed.emit(cell)
	return result


## Palos que hay ahora en la isla.
func sticks_count() -> int:
	var count: int = 0
	for state: NatureState in nature.values():
		if state.is_sticks():
			count += 1
	return count


## ¿Casilla de suelo libre (sin naturaleza, construcción, veta ni agua)?
func _is_free_ground(cell: Vector2i) -> bool:
	return not nature.has(cell) and grid.get_occupant(cell) == 0 and not _vein_cells.has(cell) and not water.has(cell) \
			and not _repair_cells.has(cell)


## Una casilla libre al azar dentro de `bounds`, o (-1, -1) si no queda ninguna.
func _random_free_cell() -> Vector2i:
	var free_cells: Array[Vector2i] = []
	for x: int in range(bounds.position.x, bounds.end.x):
		for y: int in range(bounds.position.y, bounds.end.y):
			if _is_free_ground(Vector2i(x, y)):
				free_cells.append(Vector2i(x, y))
	if free_cells.is_empty():
		return Vector2i(-1, -1)
	return free_cells[rng.randi_range(0, free_cells.size() - 1)]


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
	if spawn_sticks:
		_sticks_timer += dt
		if _sticks_timer + 0.0001 >= STICKS_SPAWN_TIME:
			_sticks_timer = 0.0
			if sticks_count() < MAX_STICKS:
				var stick_cell: Vector2i = _random_free_cell()
				if stick_cell != Vector2i(-1, -1):
					add_sticks(stick_cell)
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
			if _is_free_ground(cell):
				free_cells.append(cell)
	if not free_cells.is_empty():
		add_rock(free_cells[rng.randi_range(0, free_cells.size() - 1)])


# --- Vetas (B3.7, D-090) ---

## Pone una veta de 3×3 con su esquina en `origin`. Devuelve false si alguna casilla tiene una
## construcción, algo natural u otra veta.
func add_vein(data: VeinData, origin: Vector2i) -> bool:
	if data == null:
		return false
	var cells: Array[Vector2i] = vein_cells(origin)
	for cell: Vector2i in cells:
		if not _is_free_ground(cell):
			return false
	veins[origin] = data
	for cell: Vector2i in cells:
		_vein_cells[cell] = origin
	vein_added.emit(origin)
	return true


# --- Agua (B3.7, D-094) ---

## Añade agua que corre hacia `flow` (p. ej. Vector2i(0, 1): hacia el sur) en las casillas libres de
## `cells` (las ocupadas por construcciones, naturaleza o vetas se saltan). Devuelve cuántas añadió.
func add_water(cells: Array[Vector2i], flow: Vector2i) -> int:
	var added: int = 0
	for cell: Vector2i in cells:
		if not _is_free_ground(cell):
			continue
		water[cell] = flow
		added += 1
	if added > 0:
		water_changed.emit()
	return added


## ¿Hay agua en esa casilla?
func is_water(cell: Vector2i) -> bool:
	return water.has(cell)


## Veta que cubre esa casilla, o null.
func vein_at(cell: Vector2i) -> VeinData:
	if not _vein_cells.has(cell):
		return null
	return veins[_vein_cells[cell]]


## ¿Es esa casilla del BORDE de una veta? (las 8 que admiten la cabeza de un extractor; la central, no)
func is_vein_edge(cell: Vector2i) -> bool:
	if not _vein_cells.has(cell):
		return false
	return cell - _vein_cells[cell] != Vector2i(1, 1)


## Las 9 casillas de una veta con esquina en `origin`.
static func vein_cells(origin: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for x: int in VeinData.SIZE:
		for y: int in VeinData.SIZE:
			cells.append(origin + Vector2i(x, y))
	return cells


# --- Estructuras por reparar (C4, D-115) ---

## Pone una estructura por reparar, sin nada entregado. Devuelve la estructura, o null si alguna de sus
## casillas no está libre (construcción, naturaleza, veta, agua u otra estructura).
func add_repair_site(data: RepairSiteData, origin: Vector2i, rotation: int = 0) -> RepairSite:
	if data == null:
		return null
	var site := RepairSite.new(data, origin, rotation)
	return site if _add_repair_site(site) else null


func _add_repair_site(site: RepairSite) -> bool:
	if repair_sites.has(site.origin):
		return false
	var cells: Array[Vector2i] = site.cells()
	for cell: Vector2i in cells:
		if not _is_free_ground(cell):
			return false
	repair_sites[site.origin] = site
	for cell: Vector2i in cells:
		_repair_cells[cell] = site.origin
	repair_site_added.emit(site.origin)
	return true


## Estructura por reparar que ocupa esa casilla, o null.
func repair_site_at(cell: Vector2i) -> RepairSite:
	if not _repair_cells.has(cell):
		return null
	return repair_sites[_repair_cells[cell]]


## Entrega a la pieza `piece_index` de la estructura que ocupa `cell` lo que le falte y haya en `from`.
## Devuelve cuántas unidades entregó (0 = nada). Avisa con `repair_changed` y, si con esto queda
## completa, con `repair_completed` (una sola vez).
func deliver_repair(cell: Vector2i, piece_index: int, from: Inventory) -> int:
	var site: RepairSite = repair_site_at(cell)
	if site == null or site.is_complete():
		return 0
	var given: int = site.deliver(piece_index, from)
	if given > 0:
		repair_changed.emit(site.origin, piece_index)
		if site.is_complete():
			repair_completed.emit(site.origin)
	return given
