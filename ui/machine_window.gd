class_name MachineWindow
extends CanvasLayer
## Ventana de una construcción (C1.3; tema y dos columnas en C2), con E. Sustituye al intercambio rápido.
## A la izquierda, la construcción; a la derecha, la mochila (César: así cabe toda aunque crezca; la barra se
## queda abajo en la pantalla).
## - Máquina (horno, carbonera…): entrada, progreso por celdas, salida y la receta con iconos.
## - Extractor y talador: progreso y lo que guardan.
## - Almacén (arcón, caja logística): su contenido.
## - Generador y poste: la red y, en los generadores, el botón para rearmar el fusible.
## Se maneja con clics, como el inventario. Mayús + clic manda lo del jugador a la entrada (o al almacén).
## E, Esc o el botón de cerrar la cierran.

const LEFT_WIDTH: float = 340.0
const RECIPE_ICON: Vector2 = Vector2(28, 28)

var _window: UiWindow
var _input_box: VBoxContainer
var _input_grid: InventoryGrid
var _progress_box: VBoxContainer
var _progress: UiCellProgress
var _progress_label: Label
var _output_section: UiSection
var _output_box: VBoxContainer
var _output_grid: InventoryGrid
var _recipe_box: VBoxContainer
var _recipe_row: HBoxContainer
var _status_row: HBoxContainer
var _status_hex: UiHex
var _status: Label
var _fuse_button: Button
## Construcción que se está viendo.
var _view: BuildingView = null


func _ready() -> void:
	layer = 5
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_window = UiWindow.new()
	center.add_child(_window)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	_window.content.add_child(row)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = LEFT_WIDTH
	left.add_theme_constant_override("separation", 10)
	row.add_child(left)
	# Entrada
	_input_box = VBoxContainer.new()
	_input_box.add_theme_constant_override("separation", 8)
	_input_box.add_child(UiSection.new(tr("WINDOW_INPUT")))
	_input_grid = InventoryGrid.new()
	_input_grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_input_box.add_child(_input_grid)
	left.add_child(_input_box)
	# Progreso
	_progress_box = VBoxContainer.new()
	_progress = UiCellProgress.new()
	_progress.custom_minimum_size = Vector2(LEFT_WIDTH, 30)
	_progress_box.add_child(_progress)
	_progress_label = _make_label("", 12, UiStyle.SUBTLE)
	_progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_progress_box.add_child(_progress_label)
	left.add_child(_progress_box)
	# Salida o almacén
	_output_box = VBoxContainer.new()
	_output_box.add_theme_constant_override("separation", 8)
	_output_section = UiSection.new(tr("WINDOW_OUTPUT"))
	_output_box.add_child(_output_section)
	_output_grid = InventoryGrid.new()
	_output_grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_output_box.add_child(_output_grid)
	left.add_child(_output_box)
	# Receta
	_recipe_box = VBoxContainer.new()
	_recipe_box.add_theme_constant_override("separation", 8)
	_recipe_box.add_child(UiSection.new(tr("WINDOW_RECIPE")))
	_recipe_row = HBoxContainer.new()
	_recipe_row.add_theme_constant_override("separation", 4)
	_recipe_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_recipe_box.add_child(_recipe_row)
	left.add_child(_recipe_box)
	# Estado
	_status_row = HBoxContainer.new()
	_status_row.add_theme_constant_override("separation", 8)
	_status_hex = UiHex.new(UiStyle.GREEN, 12.0)
	_status_row.add_child(_status_hex)
	_status = _make_label("", 14, UiStyle.GREEN)
	_status_row.add_child(_status)
	left.add_child(_status_row)
	_fuse_button = Button.new()
	_fuse_button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_fuse_button.text = tr("WINDOW_RESET_FUSE")
	_fuse_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_fuse_button.pressed.connect(_on_reset_fuse)
	left.add_child(_fuse_button)
	# Mochila a la derecha
	row.add_child(VSeparator.new())
	row.add_child(PlayerInventoryPanel.new())
	_window.visible = false
	WindowManager.window_closed.connect(_on_window_closed)


func _make_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED # el texto ya va traducido
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


## Abre la ventana de la construcción que muestra `view`. Las cintas no tienen ventana.
func open_for(view: BuildingView) -> void:
	var placed: PlacedBuilding = view.placed
	if placed == null or placed.is_belt():
		return
	_view = view
	_window.set_title(tr(placed.data.name_key), "%d × %d" % [placed.data.size.x, placed.data.size.y])
	var has_input: bool = placed.is_machine()
	var has_output: bool = placed.output != null
	_input_box.visible = has_input
	if has_input:
		_input_grid.setup(placed.input, 0, -1, mini(placed.input.get_slot_count(), 4))
	_output_box.visible = has_output
	if has_output:
		_output_section.set_text(tr("WINDOW_STORAGE") if placed.is_storage() else tr("WINDOW_OUTPUT"))
		# Almacenes en filas de 4 (arcón 4 × 4, caja logística 4 × 2); salidas de máquina, en una fila.
		_output_grid.setup(placed.output, 0, -1, 4 if placed.is_storage() else mini(placed.output.get_slot_count(), 5))
	_progress_box.visible = placed.is_machine() or placed.is_extractor() or placed.is_harvester()
	_fuse_button.visible = placed.data.power > 0.0
	_build_recipe(placed.data.recipe if placed.is_machine() else null)
	_refresh()
	WindowManager.open(_window)
	view.set_window_open(true)
	# Mayús + clic desde el inventario del jugador va a la entrada (o al almacén).
	if has_input:
		WindowManager.other_inventory = placed.input
	elif placed.is_storage():
		WindowManager.other_inventory = placed.output


## «2 [mineral] + 1 [carbón] → 1 [lingote] + 1 [escoria]» con los iconos de los ítems.
func _build_recipe(recipe: RecipeData) -> void:
	for child: Node in _recipe_row.get_children():
		child.queue_free()
	_recipe_box.visible = recipe != null
	if recipe == null:
		return
	_add_recipe_side(recipe.inputs)
	_recipe_row.add_child(_make_label("  →  ", 15, UiStyle.TITLE))
	_add_recipe_side(recipe.outputs)


func _add_recipe_side(items: Dictionary) -> void:
	var first: bool = true
	for item: ItemData in items:
		if not first:
			_recipe_row.add_child(_make_label(" + ", 14, UiStyle.SUBTLE))
		first = false
		_recipe_row.add_child(_make_label(str(items[item]), 14, UiStyle.TEXT))
		var icon: TextureRect = SlotUI.make_icon_rect()
		icon.custom_minimum_size = RECIPE_ICON
		icon.texture = item.icon
		icon.tooltip_text = tr(item.name_key)
		icon.mouse_filter = Control.MOUSE_FILTER_PASS
		_recipe_row.add_child(icon)


func _process(_delta: float) -> void:
	if WindowManager.is_showing(_window):
		if not is_instance_valid(_view) or _view.placed == null:
			WindowManager.close() # la construcción ya no existe
			return
		_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if WindowManager.is_showing(_window) and event.is_action_pressed("interact"):
		WindowManager.close()
		get_viewport().set_input_as_handled()


## Progreso y estado (energía, veta, red).
func _refresh() -> void:
	var placed: PlacedBuilding = _view.placed
	var island: IslandState = _view.island
	var duration: float = 0.0
	if placed.is_machine():
		duration = placed.data.recipe.duration
	elif placed.is_extractor():
		duration = placed.data.extract_time
	elif placed.is_harvester():
		duration = placed.data.harvest_time
	var fraction: float = clampf(placed.progress / duration, 0.0, 1.0) if duration > 0.0 else 0.0
	_progress.value = fraction
	_progress_label.text = "%d %%  ·  %s s" % [roundi(fraction * 100.0), str(snappedf(duration, 0.1))]
	var lines: PackedStringArray = []
	var ok: bool = true
	if placed.is_extractor() and placed.vein_item == null:
		lines.append(tr("BUILD_NEEDS_VEIN"))
		ok = false
	if island != null and (placed.data.power != 0.0 or placed.data.power_connections > 0):
		var network: PowerNetwork = island.get_network(placed.id)
		if network != null:
			lines.append(tr("WINDOW_NETWORK") % [int(network.supply), int(network.demand)])
			if network.is_tripped():
				lines.append(tr("WINDOW_FUSE_TRIPPED"))
				ok = false
		if placed.data.power < 0.0 and not island.is_powered(placed.id) and (network == null or not network.is_tripped()):
			lines.append(tr("POWER_NO_POWER"))
			ok = false
	_status.text = "\n".join(lines)
	_status_row.visible = not lines.is_empty()
	var color: Color = UiStyle.GREEN if ok else UiStyle.RED
	_status.add_theme_color_override("font_color", color)
	_status_hex.color = color
	_status_hex.queue_redraw()


func _on_reset_fuse() -> void:
	if _view == null or _view.island == null:
		return
	var network: PowerNetwork = _view.island.get_network(_view.placed.id)
	if network != null:
		network.reset_fuse() # si sigue sobrecargada, volverá a saltar en el siguiente paso


func _on_window_closed(window: Control) -> void:
	if window == _window:
		if is_instance_valid(_view):
			_view.set_window_open(false)
		_view = null
