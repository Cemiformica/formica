class_name SettingsPanel
extends CanvasLayer
## Panel provisional de opciones gráficas (B5.3). Se abre y cierra con F10 (`toggle_settings`) o se cierra
## con Esc. Cada cambio se aplica y se guarda al momento (autoload `Settings`). En la fase C irá dentro del
## menú de pausa. Para añadir una opción: una línea en `_build()` con `_add_row()`.

var _panel: PanelContainer
## Desplegable de cada opción: nombre de la opción → OptionButton.
var _buttons: Dictionary[StringName, OptionButton] = {}


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_panel.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_settings"):
		_set_open(not _panel.visible)
		get_viewport().set_input_as_handled()
	elif _panel.visible and event.is_action_pressed("ui_cancel"):
		_set_open(false)
		get_viewport().set_input_as_handled()


func _set_open(open: bool) -> void:
	# Otra ventana (provisional) ya abierta: no abrimos encima.
	if open and Aim.ui_open:
		return
	_panel.visible = open
	Aim.ui_open = open
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if open else Input.MOUSE_MODE_CAPTURED
	if open:
		_refresh()


func _build() -> void:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_panel = PanelContainer.new()
	center.add_child(_panel)
	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	_panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	margin.add_child(column)
	var title := _make_label("SETTINGS_TITLE")
	title.add_theme_font_size_override("font_size", 24)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 8)
	column.add_child(grid)
	_add_row(grid, &"fullscreen", "SETTINGS_WINDOW_MODE", [tr("SETTINGS_WINDOWED"), tr("SETTINGS_FULLSCREEN")])
	_add_row(grid, &"vsync", "SETTINGS_VSYNC", [tr("SETTINGS_OFF"), tr("SETTINGS_ON")])
	_add_row(grid, &"msaa", "SETTINGS_MSAA", [tr("SETTINGS_OFF"), "2x", "4x", "8x"])
	_add_row(grid, &"smaa", "SETTINGS_SMAA", [tr("SETTINGS_OFF"), tr("SETTINGS_ON")])
	_add_row(grid, &"shadow_quality", "SETTINGS_SHADOWS", [tr("SETTINGS_LOW"), tr("SETTINGS_MEDIUM"), tr("SETTINGS_HIGH")])
	_add_row(grid, &"render_scale", "SETTINGS_RENDER_SCALE", ["50 %", "75 %", "100 %"])
	var hint := _make_label("SETTINGS_CLOSE_HINT")
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.modulate = Color(1.0, 1.0, 1.0, 0.6)
	column.add_child(hint)


## Una fila: nombre traducido y desplegable. Las opciones de sí/no usan el índice 0 = no, 1 = sí.
func _add_row(grid: GridContainer, option: StringName, label_key: String, choices: Array) -> void:
	grid.add_child(_make_label(label_key))
	var button := OptionButton.new()
	button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED # los textos ya van traducidos
	button.custom_minimum_size.x = 180.0
	for choice: Variant in choices:
		button.add_item(str(choice))
	button.item_selected.connect(_on_item_selected.bind(option))
	grid.add_child(button)
	_buttons[option] = button


func _make_label(key: String) -> Label:
	var label := Label.new()
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.text = tr(key)
	return label


## Pone cada desplegable en el valor actual de `Settings`.
func _refresh() -> void:
	for option: StringName in _buttons:
		var value: Variant = Settings.get(option)
		_buttons[option].select(int(value))


func _on_item_selected(index: int, option: StringName) -> void:
	var current: Variant = Settings.get(option)
	Settings.set_option(option, bool(index) if current is bool else index)
