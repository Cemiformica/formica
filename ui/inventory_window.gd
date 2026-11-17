class_name InventoryWindow
extends CanvasLayer
## Ventana del inventario del jugador (C1.2): se abre y cierra con Tab (`toggle_inventory`) como ventana de
## `WindowManager`. Dentro, la mochila y la barra (`PlayerInventoryPanel`).

var _panel: PanelContainer


func _ready() -> void:
	layer = 5
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_panel = PanelContainer.new()
	center.add_child(_panel)
	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	_panel.add_child(margin)
	margin.add_child(PlayerInventoryPanel.new())
	_panel.visible = false


## En `_input` y no en `_unhandled_input`: si una casilla tiene el foco, la interfaz usaría Tab para saltar
## de un control a otro y la ventana no se cerraría.
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_inventory"):
		WindowManager.toggle(_panel)
		get_viewport().set_input_as_handled()
