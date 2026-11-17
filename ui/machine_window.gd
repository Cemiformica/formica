class_name MachineWindow
extends CanvasLayer
## Ventana de una construcción (C1.3), con E. Sustituye al intercambio rápido (D-062).
## - Máquina (horno, carbonera…): entrada, barra de progreso y salida.
## - Extractor y talador: progreso y lo que guardan.
## - Almacén (arcón, caja logística): su contenido.
## - Generador y poste: la red (cuánto genera y cuánto consume) y, en los generadores, un botón para rearmar
##   el fusible.
## Debajo va la mochila; la barra sigue abajo en la pantalla. Se maneja con clics, como el inventario.
## Mayús + clic manda lo del jugador a la entrada de la máquina (o al almacén). E o Esc la cierran.

var _panel: PanelContainer
var _title: Label
var _status: Label
var _input_box: VBoxContainer
var _input_grid: InventoryGrid
var _progress: ProgressBar
var _output_box: VBoxContainer
var _output_label: Label
var _output_grid: InventoryGrid
var _fuse_button: Button
## Construcción que se está viendo.
var _view: BuildingView = null


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
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)
	_title = _make_label("")
	_title.add_theme_font_size_override("font_size", 22)
	column.add_child(_title)
	# Entrada · progreso · salida
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(row)
	_input_box = VBoxContainer.new()
	_input_box.add_child(_make_label(tr("WINDOW_INPUT")))
	_input_grid = InventoryGrid.new()
	_input_box.add_child(_input_grid)
	row.add_child(_input_box)
	_progress = ProgressBar.new()
	_progress.custom_minimum_size = Vector2(140, 22)
	_progress.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_progress.max_value = 1.0
	_progress.show_percentage = false
	row.add_child(_progress)
	_output_box = VBoxContainer.new()
	_output_label = _make_label(tr("WINDOW_OUTPUT"))
	_output_box.add_child(_output_label)
	_output_grid = InventoryGrid.new()
	_output_box.add_child(_output_grid)
	row.add_child(_output_box)
	_status = _make_label("")
	column.add_child(_status)
	_fuse_button = Button.new()
	_fuse_button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_fuse_button.text = tr("WINDOW_RESET_FUSE")
	_fuse_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_fuse_button.pressed.connect(_on_reset_fuse)
	column.add_child(_fuse_button)
	column.add_child(HSeparator.new())
	column.add_child(PlayerInventoryPanel.new())
	_panel.visible = false
	WindowManager.window_closed.connect(_on_window_closed)


func _make_label(text: String) -> Label:
	var label := Label.new()
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED # el texto ya va traducido
	label.text = text
	return label


## Abre la ventana de la construcción que muestra `view`. Las cintas no tienen ventana.
func open_for(view: BuildingView) -> void:
	var placed: PlacedBuilding = view.placed
	if placed == null or placed.is_belt():
		return
	_view = view
	_title.text = tr(placed.data.name_key)
	var has_input: bool = placed.is_machine()
	var has_output: bool = placed.output != null
	_input_box.visible = has_input
	if has_input:
		_input_grid.setup(placed.input, 0, -1, mini(placed.input.get_slot_count(), 4))
	_output_box.visible = has_output
	if has_output:
		_output_label.text = tr("WINDOW_STORAGE") if placed.is_storage() else tr("WINDOW_OUTPUT")
		_output_grid.setup(placed.output, 0, -1, mini(placed.output.get_slot_count(), 8))
	_progress.visible = placed.is_machine() or placed.is_extractor() or placed.is_harvester()
	_fuse_button.visible = placed.data.power > 0.0
	_refresh()
	WindowManager.open(_panel)
	view.set_window_open(true)
	# Mayús + clic desde el inventario del jugador va a la entrada (o al almacén).
	if has_input:
		WindowManager.other_inventory = placed.input
	elif placed.is_storage():
		WindowManager.other_inventory = placed.output


func _process(_delta: float) -> void:
	if WindowManager.is_showing(_panel):
		if not is_instance_valid(_view) or _view.placed == null:
			WindowManager.close() # la construcción ya no existe
			return
		_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if WindowManager.is_showing(_panel) and event.is_action_pressed("interact"):
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
	_progress.value = clampf(placed.progress / duration, 0.0, 1.0) if duration > 0.0 else 0.0
	var lines: PackedStringArray = []
	if placed.is_extractor() and placed.vein_item == null:
		lines.append(tr("BUILD_NEEDS_VEIN"))
	if island != null and (placed.data.power != 0.0 or placed.data.power_connections > 0):
		var network: PowerNetwork = island.get_network(placed.id)
		if network != null:
			lines.append(tr("WINDOW_NETWORK") % [int(network.supply), int(network.demand)])
			if network.is_tripped():
				lines.append(tr("WINDOW_FUSE_TRIPPED"))
		elif placed.data.power < 0.0:
			lines.append(tr("POWER_NO_POWER"))
		if placed.data.power < 0.0 and network != null and not island.is_powered(placed.id) and not network.is_tripped():
			lines.append(tr("POWER_NO_POWER"))
	_status.text = "\n".join(lines)
	_status.visible = not lines.is_empty()


func _on_reset_fuse() -> void:
	if _view == null or _view.island == null:
		return
	var network: PowerNetwork = _view.island.get_network(_view.placed.id)
	if network != null:
		network.reset_fuse() # si sigue sobrecargada, volverá a saltar en el siguiente paso


func _on_window_closed(window: Control) -> void:
	if window == _panel:
		if is_instance_valid(_view):
			_view.set_window_open(false)
		_view = null
