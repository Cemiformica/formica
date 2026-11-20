class_name PlayerInventoryPanel
extends VBoxContainer
## La mochila del jugador en pantalla (C1.2; tema en C2): las casillas que van después de la barra, **una fila
## de 10 por módulo** con su número en un hexágono a la izquierda (César). La barra no está aquí: se queda
## siempre abajo en la pantalla (`HotbarUI`). Va en la ventana de Tab y a la derecha de las ventanas de
## máquina, de arcón y del banco.

var _inventory: Inventory
var _section: UiSection
var _rows: VBoxContainer


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	_inventory = WorldState.player_inventory
	_section = UiSection.new()
	add_child(_section)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 9)
	add_child(_rows)
	rebuild()


## Módulos de la mochila que se tienen ahora.
func module_count() -> int:
	@warning_ignore("integer_division")
	return (_inventory.get_slot_count() - WorldState.HOTBAR_SLOTS) / WorldState.BACKPACK_MODULE_SLOTS


## Rehace las filas (p. ej., si la mochila gana un módulo).
func rebuild() -> void:
	for child: Node in _rows.get_children():
		child.queue_free()
	var modules: int = module_count()
	_section.set_text(tr("INVENTORY_BACKPACK_ONE") if modules == 1 else tr("INVENTORY_BACKPACK_MANY") % modules)
	for m: int in modules:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.add_child(UiHex.new(UiStyle.AMBER, 24.0, str(m + 1)))
		var grid := InventoryGrid.new()
		row.add_child(grid)
		grid.setup(_inventory, WorldState.HOTBAR_SLOTS + m * WorldState.BACKPACK_MODULE_SLOTS,
				WorldState.BACKPACK_MODULE_SLOTS, WorldState.BACKPACK_MODULE_SLOTS)
		_rows.add_child(row)
