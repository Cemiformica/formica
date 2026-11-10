extends Node
## Prueba automática de `Inventory` (solo desarrollo, no se exporta). Ejecuta esta escena con F6
## y mira la pestaña Salida: cada comprobación imprime OK o FALLO.

const WOOD: ItemData = preload("res://content/items/wood.tres")
const STONE: ItemData = preload("res://content/items/stone.tres")

var _failures: int = 0


func _ready() -> void:
	# 1) Pilas: 120 de madera con max_stack 50 ocupan 3 casillas (50 + 50 + 20).
	var inv := Inventory.new(3)
	_check("cabe todo", inv.add_item(WOOD, 120) == 0)
	_check("total 120", inv.get_total(WOOD) == 120)
	# 2) Inventario lleno: lo que no cabe se devuelve.
	_check("sobran 30", inv.add_item(WOOD, 60) == 30)
	_check("no cabe piedra", inv.add_item(STONE, 1) == 1)
	# 3) Quitar: si no hay suficiente, no toca nada.
	_check("no quita de más", not inv.remove_item(WOOD, 500))
	_check("quita 100", inv.remove_item(WOOD, 100))
	_check("quedan 50", inv.get_total(WOOD) == 50)
	# 4) Reglas: una salida de máquina no admite meter cosas.
	var output := Inventory.new(1, [], false)
	_check("salida cerrada", not output.can_insert(0, WOOD))
	# 5) Transferir entre inventarios y señal `changed`.
	var box := Inventory.new(2)
	var emitted: Array[int] = [0]
	box.changed.connect(func() -> void: emitted[0] += 1)
	inv.transfer_to(_first_used_slot(inv), box, 0)
	_check("transferido", box.get_total(WOOD) == 50 and inv.get_total(WOOD) == 0)
	_check("señal emitida", emitted[0] == 1)

	print("--- Inventory: %s ---" % ("TODO OK" if _failures == 0 else "%d FALLOS" % _failures))


func _check(label: String, condition: bool) -> void:
	if condition:
		print("OK    ", label)
	else:
		_failures += 1
		push_error("FALLO " + label)


func _first_used_slot(inv: Inventory) -> int:
	for i: int in inv.get_slot_count():
		if inv.slots[i] != null:
			return i
	return -1
