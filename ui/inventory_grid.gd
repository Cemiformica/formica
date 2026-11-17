class_name InventoryGrid
extends GridContainer
## Cuadrícula de casillas (`SlotUI`) de una parte de un inventario: de la casilla `start`, `count` casillas
## (C1.2). La usan la mochila y las ventanas de máquina y de arcón.

var inventory: Inventory
var start: int = 0
var count: int = 0


## Crea (o rehace) las casillas. `p_count` < 0 = hasta el final del inventario.
func setup(p_inventory: Inventory, p_start: int = 0, p_count: int = -1, p_columns: int = 10) -> void:
	inventory = p_inventory
	start = p_start
	count = p_inventory.get_slot_count() - p_start if p_count < 0 else p_count
	columns = p_columns
	add_theme_constant_override("h_separation", 4)
	add_theme_constant_override("v_separation", 4)
	for child: Node in get_children():
		child.queue_free()
	for i: int in count:
		var slot := SlotUI.new()
		slot.setup(inventory, start + i)
		add_child(slot)
