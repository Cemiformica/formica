class_name SlotUI
extends PanelContainer
## Casilla visual de un inventario (C1.2; del prototipo, D-036): del jugador, de una máquina o de un arcón.
## Muestra el ítem y la cantidad. Se maneja con clics, como en Minecraft (César): ver `_gui_input`.
## Muestra el icono del ítem (C1.7); si un ítem no lo tiene, su color y su nombre abreviado.

const SLOT_SIZE: Vector2 = Vector2(60, 60)

var inventory: Inventory ## Inventario al que pertenece la casilla.
var index: int = 0 ## Posición dentro de ese inventario.

var _swatch: ColorRect
var _icon: TextureRect
var _name_label: Label
var _amount_label: Label


## Prepara la casilla. Se puede llamar antes o después de añadirla a la escena.
func setup(p_inventory: Inventory, p_index: int) -> void:
	# Si la casilla ya mostraba otro inventario (p. ej., otra máquina), deja de escucharlo.
	if inventory != null and inventory != p_inventory and inventory.changed.is_connected(refresh):
		inventory.changed.disconnect(refresh)
	inventory = p_inventory
	index = p_index
	if is_inside_tree():
		_connect_and_refresh()


func _ready() -> void:
	custom_minimum_size = SLOT_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	_swatch = ColorRect.new()
	_swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_swatch)
	_icon = make_icon_rect()
	add_child(_icon)
	_name_label = _make_label(HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_CENTER)
	_amount_label = _make_label(HORIZONTAL_ALIGNMENT_RIGHT, VERTICAL_ALIGNMENT_BOTTOM)
	if inventory != null:
		_connect_and_refresh()


func _exit_tree() -> void:
	if inventory != null and inventory.changed.is_connected(refresh):
		inventory.changed.disconnect(refresh)


func _make_label(horizontal: HorizontalAlignment, vertical: VerticalAlignment) -> Label:
	var label := Label.new()
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED # el texto ya va traducido
	label.horizontal_alignment = horizontal
	label.vertical_alignment = vertical
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	add_child(label)
	return label


func _connect_and_refresh() -> void:
	if not inventory.changed.is_connected(refresh):
		inventory.changed.connect(refresh)
	refresh()


## Redibuja la casilla según su contenido.
func refresh() -> void:
	if _swatch == null:
		return
	var stack: ItemStack = null
	if inventory != null and index < inventory.slots.size():
		stack = inventory.slots[index]
	if stack == null:
		_swatch.color = Color(0, 0, 0, 0)
		_icon.texture = null
		_name_label.text = ""
		_amount_label.text = ""
		tooltip_text = ""
		return
	var icon: Texture2D = stack.item.icon
	_icon.texture = icon
	_swatch.color = Color(0, 0, 0, 0) if icon != null else stack.item.color
	_name_label.text = "" if icon != null else short_name(stack.item)
	_amount_label.text = str(stack.amount)
	tooltip_text = tr(stack.item.name_key)


## Rectángulo que pinta un icono de ítem ocupando su hueco sin deformarse (casillas y pila en la mano).
static func make_icon_rect() -> TextureRect:
	var rect := TextureRect.new()
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


## Nombre abreviado (3 letras), de reserva para ítems sin icono.
static func short_name(item: ItemData) -> String:
	return TranslationServer.translate(item.name_key).substr(0, 3).to_upper()


## Clics (solo con una ventana abierta, para no tocar el inventario jugando): clic coge o deja, clic derecho
## coge la mitad o deja una unidad, Mayús + clic mueve rápido. Todo lo resuelve `WindowManager`.
func _gui_input(event: InputEvent) -> void:
	if not WindowManager.is_open() or inventory == null:
		return
	if event.is_action_pressed("inventory_split"):
		WindowManager.slot_right_click(inventory, index)
		accept_event()
	elif event is InputEventMouseButton and event.pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		if Input.is_action_pressed("inventory_quick_move"):
			WindowManager.quick_move(inventory, index)
		else:
			WindowManager.slot_left_click(inventory, index)
		accept_event()
