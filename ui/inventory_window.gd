class_name InventoryWindow
extends CanvasLayer
## Ventana del inventario del jugador (C1.2; tema en C2): se abre y cierra con Tab (`toggle_inventory`) como
## ventana de `WindowManager`. Dentro, la mochila en filas de 10 por módulo (`PlayerInventoryPanel`) y, a la
## derecha, el panal de módulos (`UiModuleHoneycomb`), como en la mochila de Mira.

var _window: UiWindow
var _backpack: PlayerInventoryPanel
var _honeycomb: UiModuleHoneycomb


func _ready() -> void:
	layer = 5
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_window = UiWindow.new(tr("INVENTORY_TITLE"))
	center.add_child(_window)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	_window.content.add_child(row)
	_backpack = PlayerInventoryPanel.new()
	row.add_child(_backpack)
	_honeycomb = UiModuleHoneycomb.new()
	row.add_child(_honeycomb)
	_window.visible = false
	WindowManager.window_opened.connect(_on_window_opened)


func _on_window_opened(window: Control) -> void:
	if window == _window:
		_honeycomb.modules = _backpack.module_count()


## En `_input` y no en `_unhandled_input`: si una casilla tiene el foco, la interfaz usaría Tab para saltar
## de un control a otro y la ventana no se cerraría.
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_inventory"):
		WindowManager.toggle(_window)
		get_viewport().set_input_as_handled()
