extends Node
## Autoload `WindowManager` (C1.1, D-048): abre y cierra las ventanas de la interfaz (inventario, máquinas,
## opciones…). Solo hay una abierta cada vez: abrir otra cierra la anterior. Mientras hay una abierta, el
## ratón queda libre y el jugador no se mueve ni mira (lo consultan con `is_open()`). Esc la cierra.
## Uso: `WindowManager.open(mi_control)`, `WindowManager.close()`, `WindowManager.toggle(mi_control)`.
## La ventana es cualquier `Control`: el gestor solo la enseña, la esconde y avisa con señales.
## También lleva la **pila en la mano** de las ventanas de inventario (C1.2, como en Minecraft): clic para
## coger y clic para soltar; clic derecho coge la mitad o deja una unidad. Al cerrar, lo que quede en la mano
## vuelve a su casilla (o a la primera libre del jugador).

## Se emiten al abrir y al cerrar una ventana (la ventana puede refrescarse o guardar algo al cerrarse).
signal window_opened(window: Control)
signal window_closed(window: Control)

## Ventana abierta ahora (null si ninguna).
var current: Control = null
## Pila que se lleva en la mano dentro de una ventana (null si ninguna) y de dónde salió.
var held: ItemStack = null
var _held_source: Inventory = null
var _held_index: int = -1
## Inventario de la ventana abierta (máquina, arcón…) al que va Mayús + clic desde el del jugador.
var other_inventory: Inventory = null
## Arrastrar (C2.4, César): si se coge una pila con el clic y se suelta el botón lejos, sobre otra casilla,
## se deja ahí, como si se hubiera hecho clic en ella. Así funcionan las dos cosas: clic-clic y arrastrar.
const DRAG_DISTANCE: float = 10.0
var _press_position: Vector2 = Vector2.ZERO
var _picked_by_press: bool = false

var _held_view: Control
var _held_swatch: ColorRect
var _held_icon: TextureRect
var _held_label: Label


func _ready() -> void:
	UiStyle.apply_theme(get_tree().root) # tema común de la interfaz (C2)
	# La pila en la mano se dibuja encima de todo y sigue al ratón.
	var layer := CanvasLayer.new()
	layer.layer = 50
	add_child(layer)
	_held_view = Control.new()
	_held_view.size = SlotUI.SLOT_SIZE * 0.8
	_held_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_held_view.visible = false
	layer.add_child(_held_view)
	# Icono del ítem; el cuadrito de color solo para ítems sin icono.
	_held_swatch = ColorRect.new()
	_held_swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_held_swatch.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_held_view.add_child(_held_swatch)
	_held_icon = SlotUI.make_icon_rect()
	_held_icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_held_view.add_child(_held_icon)
	_held_label = Label.new()
	_held_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_held_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_held_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_held_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_held_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_held_label.add_theme_constant_override("outline_size", 4)
	_held_view.add_child(_held_label)


func _process(_delta: float) -> void:
	if _held_view.visible:
		_held_view.position = get_viewport().get_mouse_position() + Vector2(6, 6)


## ¿Hay alguna ventana abierta? Mientras la haya, el juego no recibe clics ni movimiento.
func is_open() -> bool:
	return current != null and is_instance_valid(current)


## ¿Está abierta precisamente esta ventana?
func is_showing(window: Control) -> bool:
	return is_open() and current == window


## Abre `window`. Si había otra abierta, la cierra antes.
func open(window: Control) -> void:
	if window == null or is_showing(window):
		return
	if is_open():
		close()
	current = window
	window.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	window_opened.emit(window)


## Cierra la ventana abierta (si hay alguna) y vuelve a capturar el ratón para jugar.
func close() -> void:
	if not is_open():
		current = null
		return
	_return_held()
	other_inventory = null
	var window: Control = current
	current = null
	window.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	window_closed.emit(window)


## Abre `window` si no lo estaba; si ya estaba abierta, la cierra.
func toggle(window: Control) -> void:
	if is_showing(window):
		close()
	else:
		open(window)


## Esc cierra la ventana abierta. Los autoloads reciben la entrada después de la escena, así que el
## jugador ya ha visto la tecla y la ha ignorado (comprueba `is_open()`).
func _unhandled_input(event: InputEvent) -> void:
	if is_open() and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


# --- Pila en la mano (C1.2) ---

## Clic en una casilla: coger la pila entera o dejar lo que se lleva (junta o intercambia).
func slot_left_click(inventory: Inventory, index: int) -> void:
	if held == null:
		_set_held(inventory.take_stack(index), inventory, index)
		_picked_by_press = held != null
		_press_position = get_viewport().get_mouse_position()
	else:
		_picked_by_press = false
		_set_held(inventory.put_stack(index, held), inventory, index)


## Al soltar el botón tras arrastrar una pila recién cogida, se deja en la casilla que haya debajo.
func _input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click == null or click.pressed or click.button_index != MOUSE_BUTTON_LEFT or not _picked_by_press:
		return
	_picked_by_press = false
	if held == null or not is_open() or click.position.distance_to(_press_position) < DRAG_DISTANCE:
		return # fue un clic: la pila se queda en la mano hasta el siguiente
	# Mientras se mantiene el botón, Godot no cambia el control «bajo el ratón»: se busca la casilla a mano.
	for node: Node in get_tree().get_nodes_in_group(&"inventory_slots"):
		var slot := node as SlotUI
		if slot.is_visible_in_tree() and slot.inventory != null and slot.get_global_rect().has_point(click.position):
			slot_left_click(slot.inventory, slot.index)
			return


## Clic derecho: con la mano vacía coge la mitad; con algo en la mano deja una unidad.
func slot_right_click(inventory: Inventory, index: int) -> void:
	if held == null:
		_set_held(inventory.take_stack(index, true), inventory, index)
	else:
		_set_held(inventory.put_stack(index, held, 1), _held_source, _held_index)


## Mayús + clic: mover rápido la pila (solo con la mano vacía). Del jugador a la ventana abierta si tiene
## inventario; si no, de la barra a la mochila y al revés. De una máquina o un arcón, al jugador.
func quick_move(inventory: Inventory, index: int) -> void:
	if held != null:
		return
	var player: Inventory = WorldState.player_inventory
	var hotbar: int = WorldState.HOTBAR_SLOTS
	if inventory != player:
		inventory.quick_move(index, player, hotbar) # primero a la mochila…
		inventory.quick_move(index, player, 0, hotbar) # …y lo que no quepa, a la barra
	elif other_inventory != null:
		player.quick_move(index, other_inventory)
	elif index < hotbar:
		player.quick_move(index, player, hotbar)
	else:
		player.quick_move(index, player, 0, hotbar)


func _set_held(stack: ItemStack, source: Inventory, index: int) -> void:
	if stack != null and held == null:
		_held_source = source
		_held_index = index
	held = stack
	_held_view.visible = held != null
	if held != null:
		var icon: Texture2D = held.item.icon
		_held_icon.texture = icon
		_held_swatch.visible = icon == null
		_held_swatch.color = held.item.color
		if icon != null:
			_held_label.text = str(held.amount)
		else:
			_held_label.text = "%s %d" % [SlotUI.short_name(held.item), held.amount]


## Devuelve lo que haya en la mano: a su casilla de origen si cabe, y si no, al inventario del jugador.
func _return_held() -> void:
	if held == null:
		return
	var rest: ItemStack = held
	if _held_source != null and _held_index >= 0:
		rest = _held_source.put_stack(_held_index, rest, -1, false)
	if rest != null:
		var left: int = WorldState.player_inventory.add_item(rest.item, rest.amount)
		if left > 0 and _held_source != null:
			left = _held_source.add_item(rest.item, left)
		if left > 0:
			push_warning("WindowManager: no cabían %d de %s al cerrar la ventana" % [left, rest.item.id])
	_set_held(null, null, -1)
