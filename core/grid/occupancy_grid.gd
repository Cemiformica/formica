class_name OccupancyGrid
extends RefCounted
## Cuadrícula de ocupación de una isla, como DATOS (D-047): qué construcción ocupa cada casilla.
## No sabe nada de nodos ni de escenas: la usan la construcción, `Simulation`, el talador, las rocas…
##
## Convenciones:
## - Una casilla mide 1 m. `Vector2i(x, y)` → x = eje X del mundo, y = eje Z del mundo.
## - `origin` es la casilla de la esquina con x e y más pequeñas de la huella YA girada.
## - `rotation` va en cuartos de vuelta (0–3), en sentido horario visto desde arriba (como en el prototipo).
##   A 90° y 270° se intercambian ancho y fondo.
## - Cada construcción colocada se identifica con un `occupant_id` entero mayor que 0, que asigna quien
##   la coloca (más adelante, `WorldState`). La cuadrícula solo lo apunta.

## Casilla → id del ocupante. Solo están las casillas ocupadas.
var _cells: Dictionary[Vector2i, int] = {}
## Id del ocupante → su colocación: {"origin": Vector2i, "size": Vector2i, "rotation": int}.
var _placements: Dictionary[int, Dictionary] = {}


## Tamaño de la huella tras girarla.
static func rotated_size(size: Vector2i, rotation: int) -> Vector2i:
	if posmod(rotation, 2) == 1:
		return Vector2i(size.y, size.x)
	return size


## Pasa una casilla LOCAL de la huella sin girar (0,0 = esquina noroeste) a casilla de la cuadrícula.
## Es lo que harán los puertos (B2.2): se definen en local y giran con la construcción.
static func local_to_cell(origin: Vector2i, size: Vector2i, rotation: int, local: Vector2i) -> Vector2i:
	var w: int = size.x
	var h: int = size.y
	var rotated: Vector2i
	match posmod(rotation, 4):
		0: rotated = local
		1: rotated = Vector2i(h - 1 - local.y, local.x)
		2: rotated = Vector2i(w - 1 - local.x, h - 1 - local.y)
		_: rotated = Vector2i(local.y, w - 1 - local.x)
	return origin + rotated


## Todas las casillas que cubre una huella.
static func footprint_cells(origin: Vector2i, size: Vector2i, rotation: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var s: Vector2i = rotated_size(size, rotation)
	for x: int in s.x:
		for y: int in s.y:
			cells.append(origin + Vector2i(x, y))
	return cells


## ¿Están libres todas las casillas de la huella?
func can_place(origin: Vector2i, size: Vector2i, rotation: int) -> bool:
	if size.x < 1 or size.y < 1:
		return false
	for cell: Vector2i in footprint_cells(origin, size, rotation):
		if _cells.has(cell):
			return false
	return true


## Ocupa la huella con `occupant_id`. Devuelve false (y no toca nada) si no cabe o el id no vale.
func place(occupant_id: int, origin: Vector2i, size: Vector2i, rotation: int) -> bool:
	if occupant_id <= 0 or _placements.has(occupant_id):
		return false
	if not can_place(origin, size, rotation):
		return false
	for cell: Vector2i in footprint_cells(origin, size, rotation):
		_cells[cell] = occupant_id
	_placements[occupant_id] = {"origin": origin, "size": size, "rotation": posmod(rotation, 4)}
	return true


## Libera todas las casillas de `occupant_id`. Devuelve false si no estaba.
func remove(occupant_id: int) -> bool:
	if not _placements.has(occupant_id):
		return false
	var p: Dictionary = _placements[occupant_id]
	for cell: Vector2i in footprint_cells(p["origin"], p["size"], p["rotation"]):
		_cells.erase(cell)
	_placements.erase(occupant_id)
	return true


## Id de quien ocupa la casilla, o 0 si está libre.
func get_occupant(cell: Vector2i) -> int:
	return _cells.get(cell, 0)


## Número de construcciones colocadas.
func get_occupant_count() -> int:
	return _placements.size()


## Datos para el guardado (aptos para JSON). Se guardan las colocaciones, no las casillas:
## las casillas se recalculan al cargar.
func to_data() -> Array:
	var data: Array = []
	for id: int in _placements:
		var p: Dictionary = _placements[id]
		var origin: Vector2i = p["origin"]
		var size: Vector2i = p["size"]
		data.append({"id": id, "x": origin.x, "y": origin.y, "w": size.x, "h": size.y, "r": p["rotation"]})
	return data


## Reconstruye la cuadrícula desde `to_data()`. Ignora con aviso las entradas dañadas o que se solapan.
func load_data(data: Array) -> void:
	_cells.clear()
	_placements.clear()
	for entry: Variant in data:
		if not entry is Dictionary or not _has_keys(entry, ["id", "x", "y", "w", "h", "r"]):
			push_warning("OccupancyGrid: entrada dañada ignorada: %s" % str(entry))
			continue
		# JSON devuelve los números como float: se pasan a int.
		var ok: bool = place(int(entry["id"]), Vector2i(int(entry["x"]), int(entry["y"])),
				Vector2i(int(entry["w"]), int(entry["h"])), int(entry["r"]))
		if not ok:
			push_warning("OccupancyGrid: colocación no válida o solapada ignorada: %s" % str(entry))


func _has_keys(entry: Dictionary, keys: Array) -> bool:
	for key: String in keys:
		if not entry.has(key) or not (entry[key] is float or entry[key] is int):
			return false
	return true
