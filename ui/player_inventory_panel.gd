class_name PlayerInventoryPanel
extends VBoxContainer
## La mochila del jugador en pantalla (C1.2): las casillas que van después de la barra. La barra no está aquí:
## se queda siempre abajo en la pantalla (`HotbarUI`, César). Va en la ventana de Tab y, más adelante, debajo
## de las ventanas de máquina y de arcón.

var _inventory: Inventory
var _backpack: InventoryGrid


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	_inventory = WorldState.player_inventory
	var label := Label.new()
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.text = tr("INVENTORY_BACKPACK")
	add_child(label)
	_backpack = InventoryGrid.new()
	add_child(_backpack)
	rebuild()


## Rehace las casillas (p. ej., si la mochila gana un módulo).
func rebuild() -> void:
	var hotbar: int = WorldState.HOTBAR_SLOTS
	_backpack.setup(_inventory, hotbar, _inventory.get_slot_count() - hotbar)
