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
	return placed


static func _as_array(value: Variant) -> Array:
	if value is Array:
		return value
	return []
