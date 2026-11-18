class_name DismantleWindow
extends CanvasLayer
## Ventana de confirmar el desmontaje (C2.2). La abre el clic derecho en el modo desmontar (`DismantleController`):
## cuántas construcciones, lo que se recupera (coste y contenido) con icono y cantidad, y Desmontar /
## Cancelar. Si el reembolso no cabe en el inventario, avisa y el botón queda desactivado. El juego no se
## pausa (César): lo que se recupera se recalcula mientras está abierta. Otro clic derecho confirma; Esc cierra.

const COLUMNS: int = 8
const CELL_SIZE: Vector2 = Vector2(48, 48)
const COLOR_CELL: Color = Color(1.0, 1.0, 1.0, 0.07)
const COLOR_WARNING: Color = Color(0.95, 0.35, 0.3)

var _panel: UiWindow
var _grid: GridContainer
var _warning: Label
var _confirm: Button
var _controller: DismantleController = null


func _ready() -> void:
	layer = 5
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_panel = UiWindow.new() # marco del tema (C2)
	center.add_child(_panel)
	var column: VBoxContainer = _panel.content
	column.add_child(UiSection.new(tr("DISMANTLE_REFUND")))
	_grid = GridContainer.new()
	_grid.columns = COLUMNS
	_grid.add_theme_constant_override("h_separation", 4)
	_grid.add_theme_constant_override("v_separation", 4)
	column.add_child(_grid)
	_warning = _make_label(tr("DISMANTLE_NO_SPACE"))
	_warning.add_theme_color_override("font_color", COLOR_WARNING)
	column.add_child(_warning)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 16)
	column.add_child(buttons)
	_confirm = _make_button(tr("DISMANTLE_CONFIRM"))
	_confirm.pressed.connect(_on_confirm)
	buttons.add_child(_confirm)
	var cancel: Button = _make_button(tr("DISMANTLE_CANCEL"))
	cancel.pressed.connect(WindowManager.close)
	buttons.add_child(cancel)
	_panel.visible = false


## Abre la ventana para lo marcado en `controller`.
func open_for(controller: DismantleController) -> void:
	_controller = controller
	WindowManager.open(_panel)
	_refresh()


func _input(event: InputEvent) -> void:
	if WindowManager.is_showing(_panel) and event.is_action_pressed("dismantle_confirm"):
		_on_confirm()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if WindowManager.is_showing(_panel):
		_refresh()


func _refresh() -> void:
	var ids: Array[int] = _controller.get_marked_ids()
	if ids.is_empty():
		WindowManager.close() # ya no queda nada marcado (desmontado o borrado)
		return
	_panel.set_title(tr("DISMANTLE_TITLE") % ids.size())
	var refund: Dictionary[ItemData, int] = _controller.get_refund()
	var items: Array[ItemData] = []
	items.assign(refund.keys())
	while _grid.get_child_count() < items.size():
		_grid.add_child(_make_cell())
	for i: int in _grid.get_child_count():
		var cell := _grid.get_child(i) as ColorRect
		cell.visible = i < items.size()
		if not cell.visible:
			continue
		var item: ItemData = items[i]
		(cell.get_child(0) as TextureRect).texture = item.icon
		cell.color = item.color if item.icon == null else COLOR_CELL
		(cell.get_child(1) as Label).text = str(refund[item])
		cell.tooltip_text = tr(item.name_key)
	var fits: bool = WorldState.player_inventory.can_add_all(refund)
	_warning.visible = not fits
	_confirm.disabled = not fits


func _on_confirm() -> void:
	if _controller != null and _controller.confirm():
		WindowManager.close()


func _make_cell() -> ColorRect:
	var cell := ColorRect.new()
	cell.custom_minimum_size = CELL_SIZE
	var icon: TextureRect = SlotUI.make_icon_rect()
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cell.add_child(icon)
	var amount := _make_label("")
	amount.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	amount.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	amount.add_theme_color_override("font_outline_color", Color.BLACK)
	amount.add_theme_constant_override("outline_size", 4)
	amount.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(amount)
	return cell


func _make_label(text: String) -> Label:
	var label := Label.new()
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED # el texto ya va traducido
	label.text = text
	return label


func _make_button(text: String) -> Button:
	var button := Button.new()
	button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	button.text = text
	button.custom_minimum_size = Vector2(140, 36)
	return button
