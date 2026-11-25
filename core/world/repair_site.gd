class_name RepairSite
extends RefCounted
## Una estructura por reparar colocada en una isla (C4, D-115), con lo entregado a cada pieza.
## Se crea y se consulta SIEMPRE a través de `IslandState` (`add_repair_site`, `deliver_repair`), que
## mantiene sus casillas ocupadas y avisa a la vista.

var data: RepairSiteData
## Esquina de su huella (x e y mínimas) y giro (0–3), como las construcciones.
var origin: Vector2i
var rotation: int = 0
## Lo entregado a cada pieza (ítem → cantidad), en el mismo orden que `data.pieces`.
var delivered: Array[Dictionary] = []
## Piezas abiertas (las que se abren y cierran, `RepairPieceData.action` &"toggle"), en el mismo orden.
var opened: Array[bool] = []
## Luces encendidas, en el mismo orden que `data.lights` (C5.5, D-191).
var lit: Array[bool] = []


func _init(p_data: RepairSiteData, p_origin: Vector2i, p_rotation: int = 0) -> void:
	data = p_data
	origin = p_origin
	rotation = posmod(p_rotation, 4)
	for i: int in data.pieces.size():
		delivered.append({})
		opened.append(false)
	for i: int in data.lights.size():
		lit.append(false)


## Casillas que ocupa (con su giro): las de `data.blocked_cells` o, si no hay, todo el rectángulo.
func cells() -> Array[Vector2i]:
	if data.blocked_cells.is_empty():
		return OccupancyGrid.footprint_cells(origin, data.size, rotation)
	var result: Array[Vector2i] = []
	for local: Vector2i in data.blocked_cells:
		if local.x >= 0 and local.y >= 0 and local.x < data.size.x and local.y < data.size.y:
			result.append(OccupancyGrid.local_to_cell(origin, data.size, rotation, local))
	return result


func piece_count() -> int:
	return data.pieces.size()


## Lo que aún falta para la pieza `index` (ítem → cantidad). Vacío si está completa o no existe.
func missing(index: int) -> Dictionary[ItemData, int]:
	var result: Dictionary[ItemData, int] = {}
	if index < 0 or index >= data.pieces.size():
		return result
	var cost: Dictionary[ItemData, int] = data.pieces[index].cost
	for item: ItemData in cost:
		var left: int = cost[item] - int(delivered[index].get(item, 0))
		if left > 0:
			result[item] = left
	return result


## Cuánto se ha entregado de `item` a la pieza `index`.
func delivered_amount(index: int, item: ItemData) -> int:
	if index < 0 or index >= delivered.size():
		return 0
	return int(delivered[index].get(item, 0))


## Parte entregada de la pieza `index`, de 0 a 1 (unidades entregadas / unidades que pide).
func piece_fraction(index: int) -> float:
	if index < 0 or index >= data.pieces.size():
		return 0.0
	var total: int = 0
	var given: int = 0
	var cost: Dictionary[ItemData, int] = data.pieces[index].cost
	for item: ItemData in cost:
		total += cost[item]
		given += mini(int(delivered[index].get(item, 0)), cost[item])
	return 1.0 if total == 0 else float(given) / float(total)


func is_piece_done(index: int) -> bool:
	return index >= 0 and index < data.pieces.size() and missing(index).is_empty()


## Piezas ya completas.
func done_count() -> int:
	var count: int = 0
	for i: int in data.pieces.size():
		if is_piece_done(i):
			count += 1
	return count


func is_complete() -> bool:
	return done_count() == data.pieces.size()


## Entrega a la pieza `index` lo que le falte y haya en `from` (D-115: se puede entregar poco a poco).
## Lo saca de `from`. Devuelve cuántas unidades entregó en total (0 = nada).
func deliver(index: int, from: Inventory) -> int:
	if from == null or index < 0 or index >= data.pieces.size():
		return 0
	var given: int = 0
	var need: Dictionary[ItemData, int] = missing(index)
	for item: ItemData in need:
		var amount: int = mini(need[item], from.get_total(item))
		if amount > 0 and from.remove_item(item, amount):
			delivered[index][item] = int(delivered[index].get(item, 0)) + amount
			given += amount
	return given


## ¿Está abierta la pieza `index`?
func is_open(index: int) -> bool:
	return index >= 0 and index < opened.size() and opened[index]


## ¿Se puede abrir o cerrar la pieza `index`? Solo las de acción &"toggle" y ya completas.
func can_toggle(index: int) -> bool:
	return index >= 0 and index < data.pieces.size() and data.pieces[index].action == &"toggle" and is_piece_done(index)


## ¿Está encendida la luz `index`?
func is_lit(index: int) -> bool:
	return index >= 0 and index < lit.size() and lit[index]


## ¿Se puede encender o apagar la luz `index`? Con la estructura completa.
func can_switch_light(index: int) -> bool:
	return index >= 0 and index < data.lights.size() and is_complete()


## Al completarse: enciende las luces que se encienden solas (el candil).
func light_on_complete() -> void:
	for i: int in data.lights.size():
		if data.lights[i] != null and data.lights[i].lit_on_complete:
			lit[i] = true


## Estado → datos para el guardado.
func to_data() -> Dictionary:
	var progress: Array = []
	for piece_delivered: Dictionary in delivered:
		var entry: Dictionary = {}
		for item: ItemData in piece_delivered:
			entry[String(item.id)] = piece_delivered[item]
		progress.append(entry)
	var open_list: Array = []
	for i: int in opened.size():
		if opened[i]:
			open_list.append(i)
	var lit_list: Array = []
	for i: int in lit.size():
		if lit[i]:
			lit_list.append(i)
	return {"id": String(data.id), "x": origin.x, "y": origin.y, "r": rotation, "d": progress, "o": open_list, "l": lit_list}


## Datos del guardado → estructura, o null si su tipo no existe. Lo entregado de más o de ítems que la
## pieza ya no pide (si cambió el contenido) se ignora.
static func from_data(entry: Dictionary) -> RepairSite:
	var site_data: RepairSiteData = Content.find_repair_site(StringName(str(entry.get("id", ""))))
	if site_data == null:
		return null
	var site := RepairSite.new(site_data, Vector2i(int(entry.get("x", 0)), int(entry.get("y", 0))), int(entry.get("r", 0)))
	var open_list: Variant = entry.get("o", [])   # las partidas de antes no lo tienen: todo cerrado
	if open_list is Array:
		for value: Variant in open_list:
			if (value is int or value is float) and int(value) >= 0 and int(value) < site.opened.size():
				site.opened[int(value)] = true
	var lit_list: Variant = entry.get("l", [])   # las partidas de antes no lo tienen: todo apagado
	if lit_list is Array:
		for value: Variant in lit_list:
			if (value is int or value is float) and int(value) >= 0 and int(value) < site.lit.size():
				site.lit[int(value)] = true
	var progress: Variant = entry.get("d", [])
	if not progress is Array:
		return site
	for i: int in mini(progress.size(), site_data.pieces.size()):
		if not progress[i] is Dictionary:
			continue
		var cost: Dictionary[ItemData, int] = site_data.pieces[i].cost
		for item_id: Variant in progress[i]:
			var value: Variant = progress[i][item_id]
			var item: ItemData = Content.find_item(StringName(str(item_id)))
			if item == null or not cost.has(item) or not (value is int or value is float):
				continue
			var amount: int = clampi(int(value), 0, cost[item])
			if amount > 0:
				site.delivered[i][item] = amount
	return site
