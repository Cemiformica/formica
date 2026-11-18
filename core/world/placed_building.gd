class_name PlacedBuilding
extends RefCounted
## Una construcción concreta colocada en una isla (ESTADO, D-046). Su tipo es un `BuildingData`
## (contenido); aquí solo va lo que cambia en la partida: dónde está, cómo está girada y, si es
## máquina, qué tiene dentro y cuánto lleva del ciclo. El nodo que la muestra en pantalla vendrá en B2.4.

## Id único dentro de su isla (> 0). Es el mismo que usa la cuadrícula de ocupación.
var id: int
## Tipo de construcción.
var data: BuildingData
## Casilla de origen de la huella girada (ver `OccupancyGrid`).
var origin: Vector2i
## Cuartos de vuelta (0–3), sentido horario visto desde arriba.
var rotation: int
## Reflejada de norte a sur (tecla F en el modo construcción; ver `PortData`).
var flipped: bool
## Solo cajas logísticas (D-093): lado de la salida. 0 = recta, 1 = derecha, 2 = izquierda (tecla F).
var output_turn: int = 0
## Solo máquinas: entrada (admite los ingredientes de la receta) y salida (solo se saca).
## Almacenes: todo lo que guardan está en `output` (se mete y se saca de ahí).
var input: Inventory = null
var output: Inventory = null
## Solo máquinas: segundos que lleva el ciclo actual. Lo hace avanzar `Simulation` (B2.3b).
var progress: float = 0.0
## Solo cintas: ítems encima, del más adelantado (índice 0) al último, y su avance en la casilla
## (0 = acaba de entrar por detrás, 1 = listo para salir por delante). Los mueve `Simulation`.
var belt_items: Array[ItemData] = []
var belt_progress: Array[float] = []
## Lo que el ítem de delante se pasó del final en el último paso (en fracción de casilla). Al pasar a
## otra cinta empieza ahí, no en 0, para no perder ese trocito de tiempo en cada unión. No se guarda.
var belt_overflow: float = 0.0
## Solo taladores: casillas del área, calculadas una vez (la construcción no se mueve; B2.9).
var _harvest_cells: Array[Vector2i] = []

## Solo extractores: ítem de la veta que tiene debajo la cabeza (lo pone `IslandState` al colocar o
## cargar; no se guarda) y el diccionario {ítem: 1} preparado una vez para no crearlo en cada paso.
var vein_item: ItemData = null
var vein_output: Dictionary[ItemData, int] = {}

## Solo generadores: fusible saltado. Una red está cortada si alguno de sus generadores lo tiene (D-068).
var fuse_tripped: bool = false


func _init(p_id: int, p_data: BuildingData, p_origin: Vector2i, p_rotation: int = 0, p_flipped: bool = false,
		p_turn: int = 0) -> void:
	id = p_id
	data = p_data
	origin = p_origin
	rotation = posmod(p_rotation, 4)
	flipped = p_flipped
	if data.output_turns:
		output_turn = posmod(p_turn, 3)
	if data.recipe != null:
		# Una casilla por ingrediente y otra por producto.
		var accepted: Array[ItemData] = []
		accepted.assign(data.recipe.inputs.keys())
		var any_item: Array[ItemData] = []
		input = Inventory.new(maxi(accepted.size(), 1), accepted)
		output = Inventory.new(maxi(data.recipe.outputs.size(), 1), any_item, false)
	elif is_harvester() or is_extractor():
		# Talador y extractor solo tienen salida: ahí dejan lo que sacan hasta que la cinta se lo lleva.
		var any_item: Array[ItemData] = []
		output = Inventory.new(1, any_item, false)
	elif is_storage():
		# Almacén (arcón o caja logística): admite cualquier ítem.
		var any_item: Array[ItemData] = []
		output = Inventory.new(data.storage_slots, any_item, true)


## Se ha movido a otro sitio (C2.5): olvida lo que dependía de dónde estaba.
func moved() -> void:
	_harvest_cells.clear()


## Todo lo que lleva dentro: entrada, salida o almacén, e ítems encima si es una cinta (C2.1).
func get_contents() -> Dictionary[ItemData, int]:
	var result: Dictionary[ItemData, int] = {}
	for inventory: Inventory in [input, output]:
		if inventory == null:
			continue
		for stack: ItemStack in inventory.slots:
			if stack != null:
				result[stack.item] = result.get(stack.item, 0) + stack.amount
	for item: ItemData in belt_items:
		if item != null:
			result[item] = result.get(item, 0) + 1
	return result


## Lo que devuelve al desmontarla (C2.1, D-089): su coste entero más lo que lleva dentro.
func get_refund() -> Dictionary[ItemData, int]:
	var result: Dictionary[ItemData, int] = get_contents()
	for item: ItemData in data.cost:
		result[item] = result.get(item, 0) + data.cost[item]
	return result


## Puertos de esta construcción, con la salida girada si es una caja logística (usar siempre esto en
## lugar de `data.ports`).
func get_ports() -> Array[PortData]:
	return data.ports_for(output_turn)


## ¿Es un almacén? (arcón o caja logística, D-093)
func is_storage() -> bool:
	return data.storage_slots > 0


## ¿Es una máquina (tiene receta)?
func is_machine() -> bool:
	return data.recipe != null


## ¿Es un banco de trabajo? (fabrica a mano desde su ventana, C1.5)
func is_workbench() -> bool:
	return not data.crafting_recipes.is_empty()


## ¿Es una cinta?
func is_belt() -> bool:
	return data.belt_speed > 0.0


## ¿Es un extractor? (saca el ítem de la veta que tiene debajo, B3.7)
func is_extractor() -> bool:
	return data.extract_time > 0.0


## Solo extractores: fija el ítem de la veta de debajo (null = sin veta: no trabaja).
func set_vein_item(item: ItemData) -> void:
	vein_item = item
	vein_output.clear()
	if item != null:
		vein_output[item] = 1


## Casilla de la cuadrícula donde queda la cabeza de un extractor colocado así.
static func head_cell_for(p_data: BuildingData, p_origin: Vector2i, p_rotation: int) -> Vector2i:
	return OccupancyGrid.local_to_cell(p_origin, p_data.size, p_rotation, p_data.vein_cell)


## ¿Es un talador?
func is_harvester() -> bool:
	return data.harvest_area.x > 0 and data.harvest_area.y > 0


## Solo taladores: casillas del área que tala, delante de la construcción según su giro.
func get_harvest_cells() -> Array[Vector2i]:
	if _harvest_cells.is_empty():
		_harvest_cells = harvest_cells_for(data, origin, rotation)
	return _harvest_cells


## Casillas del área de tala de un tipo de construcción colocado en `p_origin` con `p_rotation`
## (también la usa el fantasma del modo construcción). El área queda centrada a lo ancho de la huella y
## pegada por delante (sin girar, "delante" es el norte: filas locales negativas). Vale para el talador de
## 3×1 (área justo delante de sus tres casillas) y para uno de 1×1 (área centrada). Gira igual que los
## puertos, con `OccupancyGrid.local_to_cell()`.
static func harvest_cells_for(p_data: BuildingData, p_origin: Vector2i, p_rotation: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var w: int = p_data.harvest_area.x
	var h: int = p_data.harvest_area.y
	var left: int = floori((p_data.size.x - w) / 2.0)
	for dx: int in w:
		for dy: int in h:
			var local: Vector2i = Vector2i(left + dx, -1 - dy)
			cells.append(OccupancyGrid.local_to_cell(p_origin, p_data.size, p_rotation, local))
	return cells


## ¿Cabe en la salida todo esto? Camino rápido para un solo tipo de ítem (lo normal), sin copias:
## suma el hueco de las pilas de ese ítem y de las casillas vacías. Con varios tipos usa
## `Inventory.can_add_all()`, que simula sobre una copia y es exacto (B2.9).
func output_fits(items: Dictionary[ItemData, int]) -> bool:
	if items.size() != 1:
		return output.can_add_all(items)
	var item: ItemData = items.keys()[0]
	var needed: int = items[item]
	for stack: ItemStack in output.slots:
		if stack == null:
			needed -= item.max_stack
		elif stack.item == item:
			needed -= stack.space_left()
		if needed <= 0:
			return true
	return needed <= 0


# --- Logística (B2.5): lo usa `Simulation` con las conexiones de `IslandState` ---

## ¿Puede recibir ahora `item` por su puerto de entrada `port`?
## Máquina: lo acepta su receta y cabe. Cinta: hay hueco a la entrada.
func can_accept(item: ItemData, port: PortData) -> bool:
	if port.item_filter != null and port.item_filter != item:
		return false
	if is_belt():
		if belt_items.size() >= data.belt_capacity:
			return false
		return belt_items.is_empty() or belt_progress[belt_progress.size() - 1] >= _belt_spacing()
	if is_machine():
		if not input.accepted_items.is_empty() and not input.accepted_items.has(item):
			return false
		var one: Dictionary[ItemData, int] = {item: 1}
		return input.can_add_all(one)
	if is_storage():
		var unit: Dictionary[ItemData, int] = {item: 1}
		return output.can_add_all(unit)
	return false


## Recibe una unidad de `item`. Llamar solo si `can_accept()` dio true.
## Cinta: el ítem entra en `start` (lo que se pasó en la cinta anterior), sin acercarse al de delante.
func accept(item: ItemData, start: float = 0.0) -> void:
	if is_belt():
		var max_start: float = 1.0
		if not belt_progress.is_empty():
			max_start = belt_progress[belt_progress.size() - 1] - _belt_spacing()
		belt_items.append(item)
		belt_progress.append(clampf(start, 0.0, maxf(max_start, 0.0)))
	elif is_machine():
		input.add_item(item, 1)
	elif is_storage():
		output.add_item(item, 1)


## Ítem que puede salir ahora por el puerto de salida `port`, o null si ninguno.
## Máquina: el primero de la salida que pase el filtro del puerto. Cinta: el de delante, si ha llegado al final.
func peek_output(port: PortData) -> ItemData:
	if is_belt():
		if not belt_items.is_empty() and belt_progress[0] >= 1.0:
			return belt_items[0]
		return null
	if output != null:
		for stack: ItemStack in output.slots:
			if stack != null and (port.item_filter == null or stack.item == port.item_filter):
				return stack.item
	return null


## Entrega una unidad de `item` (la que dio `peek_output()`).
func take_output(item: ItemData) -> void:
	if is_belt():
		belt_items.remove_at(0)
		belt_progress.remove_at(0)
		belt_overflow = 0.0
	elif output != null:
		output.remove_item(item, 1)


## Avanza los ítems de la cinta `dt` segundos. Ninguno adelanta al de delante (separación mínima)
## ni pasa del final (1,0): si el destino está lleno, la cinta se para y se llena hacia atrás.
func advance_belt(dt: float) -> void:
	belt_overflow = 0.0
	# Solo cuenta si el de delante llega al final en este paso (si ya estaba parado allí, no se pasa).
	if not belt_progress.is_empty() and belt_progress[0] < 1.0:
		belt_overflow = maxf(0.0, belt_progress[0] + data.belt_speed * dt - 1.0)
	belt_progress = predict_belt_progress(dt)


## Avance que tendrían los ítems de la cinta dentro de `dt` segundos, con las mismas reglas que
## `advance_belt`, pero SIN cambiar los datos. La vista lo usa para dibujarlos suaves entre pasos.
## `front_limit`: hasta dónde puede llegar el de delante (la vista deja que asome por la salida).
func predict_belt_progress(dt: float, front_limit: float = 1.0) -> Array[float]:
	var result: Array[float] = []
	var limit: float = front_limit
	for i: int in belt_items.size():
		var current: float = belt_progress[i]
		var value: float = maxf(current, minf(current + data.belt_speed * dt, limit))
		result.append(value)
		limit = value - _belt_spacing()
	return result


## Distancia mínima entre dos ítems de la cinta (en fracción de casilla).
func _belt_spacing() -> float:
	return 1.0 / data.belt_capacity


## Estado → datos simples para el guardado (JSON). El tipo se guarda por id ("crusher").
func to_data() -> Dictionary:
	var result: Dictionary = {
		"id": id,
		"type": String(data.id),
		"x": origin.x,
		"y": origin.y,
		"r": rotation,
		"flip": flipped,
	}
	if data.output_turns:
		result["turn"] = output_turn
	if is_machine():
		result["in"] = input.to_data()
	if output != null:
		result["out"] = output.to_data()
		result["progress"] = progress
	if data.power > 0.0:
		result["fuse"] = fuse_tripped
	if is_belt():
		var items: Array = []
		for i: int in belt_items.size():
			items.append({"id": String(belt_items[i].id), "p": belt_progress[i]})
		result["belt"] = items
	return result


## Datos del guardado → construcción nueva. Devuelve null (con aviso) si el tipo no existe o faltan datos.
static func from_data(entry: Dictionary) -> PlacedBuilding:
	for key: String in ["id", "x", "y"]:
		if not (entry.get(key) is float or entry.get(key) is int):
			push_warning("PlacedBuilding: falta '%s' en el guardado: %s" % [key, str(entry)])
			return null
	var building_data: BuildingData = Content.find_building(StringName(str(entry.get("type", ""))))
	if building_data == null:
		push_warning("PlacedBuilding: tipo de construcción desconocido: '%s'" % entry.get("type", ""))
		return null
	var placed := PlacedBuilding.new(int(entry["id"]), building_data,
			Vector2i(int(entry["x"]), int(entry["y"])), int(entry.get("r", 0)), entry.get("flip", false) == true,
			int(entry.get("turn", 0)))
	if placed.is_machine():
		placed.input.load_data(_as_array(entry.get("in")))
		placed.output.load_data(_as_array(entry.get("out")))
		placed.progress = clampf(float(entry.get("progress", 0.0)), 0.0, building_data.recipe.duration)
	elif placed.is_harvester():
		placed.output.load_data(_as_array(entry.get("out")))
		placed.progress = clampf(float(entry.get("progress", 0.0)), 0.0, building_data.harvest_time)
	elif placed.is_extractor():
		placed.output.load_data(_as_array(entry.get("out")))
		placed.progress = clampf(float(entry.get("progress", 0.0)), 0.0, building_data.extract_time)
	elif placed.is_storage():
		placed.output.load_data(_as_array(entry.get("out")))
	placed.fuse_tripped = entry.get("fuse", false) == true
	if placed.is_belt():
		for belt_entry: Variant in _as_array(entry.get("belt")):
			if not belt_entry is Dictionary or placed.belt_items.size() >= building_data.belt_capacity:
				continue
			var item: ItemData = Content.find_item(StringName(str(belt_entry.get("id", ""))))
			if item == null:
				push_warning("PlacedBuilding: ítem desconocido en una cinta: '%s'" % belt_entry.get("id", ""))
				continue
			placed.belt_items.append(item)
			placed.belt_progress.append(clampf(float(belt_entry.get("p", 0.0)), 0.0, 1.0))
	return placed


static func _as_array(value: Variant) -> Array:
	if value is Array:
		return value
	return []
