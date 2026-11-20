class_name SettingsPanel
extends CanvasLayer
## Panel provisional de opciones gráficas y volúmenes (B5.3, B5.4). Se abre y cierra con F10 (`toggle_settings`) o se cierra
## con Esc, como ventana de `WindowManager` (C1.1). Cada cambio se aplica y se guarda al momento (autoload `Settings`). En la fase C irá dentro del
## menú de pausa. Para añadir una opción: una línea en `_build()` con `_add_row()`.

var _panel: UiWindow
## Desplegable de cada opción: nombre de la opción → OptionButton.
var _buttons: Dictionary[StringName, OptionButton] = {}


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_panel.visible = false
	WindowManager.window_opened.connect(_on_window_opened)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_settings"):
		WindowManager.toggle(_panel)
		get_viewport().set_input_as_handled()


func _on_window_opened(window: Control) -> void:
	if window == _panel:
		_refresh()


func _build() -> void:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_panel = UiWindow.new(tr("SETTINGS_TITLE")) # marco del tema (C2)
	center.add_child(_panel)
	var column: VBoxContainer = _panel.content
	column.add_theme_constant_override("separation", 12)
	column.add_child(UiSection.new(tr("SETTINGS_GRAPHICS")))
	var grid: GridContainer = _make_grid()
	column.add_child(grid)
	_add_row(grid, &"fullscreen", "SETTINGS_WINDOW_MODE", [tr("SETTINGS_WINDOWED"), tr("SETTINGS_FULLSCREEN")])
	_add_row(grid, &"vsync", "SETTINGS_VSYNC", [tr("SETTINGS_OFF"), tr("SETTINGS_ON")])
	_add_row(grid, &"msaa", "SETTINGS_MSAA", [tr("SETTINGS_OFF"), "2x", "4x", "8x"])
	_add_row(grid, &"smaa", "SETTINGS_SMAA", [tr("SETTINGS_OFF"), tr("SETTINGS_ON")])
	_add_row(grid, &"shadow_quality", "SETTINGS_SHADOWS", [tr("SETTINGS_LOW"), tr("SETTINGS_MEDIUM"), tr("SETTINGS_HIGH")])
	_add_row(grid, &"render_scale", "SETTINGS_RENDER_SCALE", ["50 %", "75 %", "100 %"])
	column.add_child(UiSection.new(tr("SETTINGS_AUDIO")))
	grid = _make_grid()
	column.add_child(grid)
	var volumes: Array = []
	for step: int in Settings.VOLUME_STEPS + 1:
		volumes.append("%d %%" % (step * 10))
	_add_row(grid, &"music_volume", "SETTINGS_MUSIC_VOLUME", volumes)
	_add_row(grid, &"sfx_volume", "SETTINGS_SFX_VOLUME", volumes)
	var hint := _make_label("SETTINGS_CLOSE_HINT")
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.modulate = Color(1.0, 1.0, 1.0, 0.6)
	column.add_child(hint)


func _make_grid() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 32)
	grid.add_theme_constant_override("v_separation", 8)
	return grid


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
	# Las opciones de sí o no guardan un bool; las demás, el número de la lista.
	var value: Variant = index
	if current is bool:
		value = bool(index)
	Settings.set_option(option, value)
