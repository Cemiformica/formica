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
## Solo máquinas: entrada (admite los ingredientes de la receta) y salida (solo se saca).
var input: Inventory = null
var output: Inventory = null
## Solo máquinas: segundos que lleva el ciclo actual. Lo hace avanzar `Simulation` (B2.3b).
var progress: float = 0.0
## Solo cintas: ítems encima, del más adelantado (índice 0) al último, y su avance en la casilla
## (0 = acaba de entrar por detrás, 1 = listo para salir por delante). Los mueve `Simulation`.
var belt_items: Array[ItemData] = []
var belt_progress: Array[float] = []


func _init(p_id: int, p_data: BuildingData, p_origin: Vector2i, p_rotation: int = 0, p_flipped: bool = false) -> void:
	id = p_id
	data = p_data
	origin = p_origin
	rotation = posmod(p_rotation, 4)
	flipped = p_flipped
	if data.recipe != null:
		# Una casilla por ingrediente y otra por producto.
		var accepted: Array[ItemData] = []
		accepted.assign(data.recipe.inputs.keys())
		var any_item: Array[ItemData] = []
		input = Inventory.new(maxi(accepted.size(), 1), accepted)
		output = Inventory.new(maxi(data.recipe.outputs.size(), 1), any_item, false)


## ¿Es una máquina (tiene receta)?
func is_machine() -> bool:
	return data.recipe != null


## ¿Es una cinta?
func is_belt() -> bool:
	return data.belt_speed > 0.0


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
	return false


## Recibe una unidad de `item`. Llamar solo si `can_accept()` dio true.
func accept(item: ItemData) -> void:
	if is_belt():
		belt_items.append(item)
		belt_progress.append(0.0)
	elif is_machine():
		input.add_item(item, 1)


## Ítem que puede salir ahora por el puerto de salida `port`, o null si ninguno.
## Máquina: el primero de la salida que pase el filtro del puerto. Cinta: el de delante, si ha llegado al final.
func peek_output(port: PortData) -> ItemData:
	if is_belt():
		if not belt_items.is_empty() and belt_progress[0] >= 1.0:
			return belt_items[0]
		return null
	if is_machine():
		for stack: ItemStack in output.slots:
			if stack != null and (port.item_filter == null or stack.item == port.item_filter):
				return stack.item
	return null


## Entrega una unidad de `item` (la que dio `peek_output()`).
func take_output(item: ItemData) -> void:
	if is_belt():
		belt_items.remove_at(0)
		belt_progress.remove_at(0)
	elif is_machine():
		output.remove_item(item, 1)


## Avanza los ítems de la cinta `dt` segundos. Ninguno adelanta al de delante (separación mínima)
## ni pasa del final (1,0): si el destino está lleno, la cinta se para y se llena hacia atrás.
func advance_belt(dt: float) -> void:
	var limit: float = 1.0
	for i: int in belt_items.size():
		var current: float = belt_progress[i]
		var target: float = minf(current + data.belt_speed * dt, limit)
		if target > current:
			belt_progress[i] = target
		limit = belt_progress[i] - _belt_spacing()


## Distancia mínima entre dos ítems de la cinta (en fracción de casilla).
func _belt_spacing() -> float:
	return 1.0 / data.belt_capacity


## Intercambio rápido con E (PROVISIONAL, B2.4c, hasta la ventana de máquina de la fase C):
## recoge la salida en `other` y mete en la entrada todo lo que la máquina acepta de `other`.
## Lo que no quepa se queda donde estaba.
func quick_exchange(other: Inventory) -> void:
	if not is_machine():
		return
	for item: ItemData in data.recipe.outputs:
		var amount: int = output.get_total(item)
		var moved: int = amount - other.add_item(item, amount)
		if moved > 0:
			output.remove_item(item, moved)
	for item: ItemData in data.recipe.inputs:
		var amount: int = other.get_total(item)
		var moved: int = amount - input.add_item(item, amount)
		if moved > 0:
			other.remove_item(item, moved)


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
	if is_machine():
		result["in"] = input.to_data()
		result["out"] = output.to_data()
		result["progress"] = progress
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
			Vector2i(int(entry["x"]), int(entry["y"])), int(entry.get("r", 0)), entry.get("flip", false) == true)
	if placed.is_machine():
		placed.input.load_data(_as_array(entry.get("in")))
		placed.output.load_data(_as_array(entry.get("out")))
		placed.progress = clampf(float(entry.get("progress", 0.0)), 0.0, building_data.recipe.duration)
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
