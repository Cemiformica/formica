class_name RepairPieceTarget
extends Interactable
## Una pieza de una estructura por reparar, para mirarla y entregarle cosas (C4.3, D-115). La crea
## `RepairSiteView`, una por pieza, con la caja de su modelo.
## Mientras falta, no choca (se atraviesa) y solo la encuentra el rayo de interactuar, por una zona en la
## capa de trabajo de las vetas; el letrero dice qué pide y con E se le entrega lo que lleves.
## Completa, choca como el resto de la estructura y ya no pide nada. Si es la cama (`action` &"bed"),
## con E se descansa: ahí reaparecerás y se guarda la partida (C4, César).
## En las estructuras con `exact_collision` (el refugio, C5.5), la pieza completa choca con su forma real (`exact_body`,
## lo crea `RepairSiteView`): la caja de un arco o de un toldo taparía la entrada. La caja queda solo para apuntarle.

var _view: RepairSiteView
var _index: int = 0
var _area: Area3D
var _done: bool = false
## Choque con la forma real de la pieza (solo en estructuras con `exact_collision`), o null.
var exact_body: StaticBody3D = null


## Prepara la pieza `index` de `view` con su caja (en el espacio de la vista). Se llama ANTES de añadirla.
func setup(view: RepairSiteView, index: int, box: AABB) -> void:
	_view = view
	_index = index
	name = "Piece_%d" % index
	display_name_key = view.site.data.pieces[index].name_key
	position = box.get_center()
	var shape := BoxShape3D.new()
	shape.size = box.size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	add_child(collision)
	_area = Area3D.new()
	_area.name = "WorkArea"
	_area.collision_mask = 0
	_area.monitoring = false
	var area_collision := CollisionShape3D.new()
	area_collision.shape = shape
	_area.add_child(area_collision)
	add_child(_area)


## Completa: choca (capa 1) y deja de pedir. Falta: se atraviesa y solo la ve el rayo de interactuar.
func set_done(done: bool) -> void:
	_done = done
	if exact_body != null:
		# Choca su forma real; la caja no choca nunca. Sigue a tiro del rayo de interactuar mientras falta o si tiene algo
		# que hacer completa (descansar en la cama, abrir la trampilla). Si no, se quita de en medio: la caja del arco
		# envolvía el toldo, que va detrás, y no dejaba entregarle nada (César).
		exact_body.collision_layer = 1 if done else 0
		collision_layer = 0
		_area.collision_layer = VeinView.WORK_AREA_LAYER if not done or _action() != &"" else 0
	else:
		collision_layer = 1 if done else 0
		_area.collision_layer = 0 if done else VeinView.WORK_AREA_LAYER
	# Completa, se llama como la estructura («Ruina de prueba»), no como la pieza; la cama sigue siendo la cama y la
	# trampilla, la trampilla.
	display_name_key = _view.site.data.name_key if done and _action() == &"" else _view.site.data.pieces[_index].name_key


## E: entrega a la pieza lo que le falte y lleves. Si no llevas nada de lo que pide, no pasa nada (el
## letrero ya dice qué necesitas).
func interact(by: Node) -> void:
	if _done:
		if _is_bed() and by.has_method("rest_at"):
			by.rest_at(_view.spawn_transform())
		elif _action() == &"toggle":
			_view.island.toggle_repair_piece(_view.site.origin, _index)
		return
	_view.island.deliver_repair(_view.site.origin, _index, WorldState.player_inventory)


func get_interact_hint_key() -> String:
	if _done:
		if _action() == &"toggle":
			return "HINT_CLOSE" if _view.site.is_open(_index) else "HINT_OPEN"
		return "HINT_REST" if _is_bed() else ""
	return "HINT_DELIVER" if _carries_something() else ""


## Si no llevas nada de lo que falta: «Necesitas: Madero, Baldosa».
func get_note_text() -> String:
	if _done or _carries_something():
		return ""
	var names: PackedStringArray = []
	for item: ItemData in _view.site.missing(_index):
		names.append(tr(item.name_key))
	return tr("HINT_NEEDS_TOOL") % ", ".join(names)


## Lo que pide, con lo entregado (para la fila de iconos del letrero).
func get_needs() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if _done:
		return result
	var cost: Dictionary[ItemData, int] = _view.site.data.pieces[_index].cost
	for item: ItemData in cost:
		result.append({"item": item, "done": _view.site.delivered_amount(_index, item), "need": cost[item]})
	return result


## ¿Llevas algo de lo que aún falta?
func _carries_something() -> bool:
	var inventory: Inventory = WorldState.player_inventory
	for item: ItemData in _view.site.missing(_index):
		if inventory.get_total(item) > 0:
			return true
	return false


func _is_bed() -> bool:
	return _action() == &"bed"


func _action() -> StringName:
	return _view.site.data.pieces[_index].action
