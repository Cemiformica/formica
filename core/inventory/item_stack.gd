class_name ItemStack
extends RefCounted
## Una casilla ocupada del inventario: qué ítem y cuántos. Es estado de partida, no contenido.

var item: ItemData
var amount: int


func _init(p_item: ItemData, p_amount: int) -> void:
	item = p_item
	amount = p_amount


## Cuántos caben todavía en esta pila.
func space_left() -> int:
	return item.max_stack - amount
