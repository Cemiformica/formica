class_name WorkbenchWindow
extends CanvasLayer
## Ventana del banco de trabajo (C1.5, D-067; rehecha en la sesión 25 con el diseño «A» que eligió César: en las
## ventanas manda lo que se hace, no la mochila). Tres columnas:
## - **Recetas:** tarjetas grandes con pestañas (Todo, Componentes, Herramientas). Cada una dice cuántas veces se
##   puede hacer con lo que llevas («×12») o «×0» en rojo si no llega para ninguna, y sale apagada.
## - **Fabricar:** la receta elegida en grande, lo que pide (lo que tienes / lo que hace falta, en verde o en
##   rojo), la cantidad con − / + / Máx, el botón Fabricar y lo que vas a recibir.
## - **Mochila compacta** (`PlayerInventoryPanel` con casillas pequeñas), que se maneja como siempre.
## Se fabrica **al instante** con lo del inventario del jugador, y mientras está abierta el banco se anima (D-095).
## E, Esc o el botón de cerrar la cierran. Las recetas son las de `BuildingData.crafting_recipes` del banco.
## Herramienta = el producto se coge en puño (`ItemData.HeldGrip.FIST`); lo demás, componente.
## Cada pulsación de Fabricar suena una vez (sesión 28, César): un golpe corto que se puede solapar si se pulsa
## muy deprisa, con un poco de variación de tono para que no canse.

const CARD_SIZE: Vector2 = Vector2(132, 124)
const CARD_ICON: float = 64.0
const COLUMNS: int = 3
## Filas de tarjetas a la vista; si hay más, la rejilla se desplaza.
const VISIBLE_ROWS: int = 3
const DETAIL_WIDTH: float = 290.0
const DETAIL_ICON: Vector2 = Vector2(88, 88)
const MAX_AMOUNT: int = 99
const CRAFT_SOUND: AudioStream = preload("res://assets/audio/craft_bench.wav")
const CRAFT_SOUND_DB: float = -4.0
const CRAFT_PITCH_JITTER: float = 0.06   # ± variación de tono en cada golpe
## Pestañas: todo, componentes y herramientas.
enum Tab { ALL, COMPONENTS, TOOLS }

var _window: UiWindow
var _tabs: Array[Button] = []
var _tab: Tab = Tab.ALL
var _grid: GridContainer
var _cards: Array[UiCard] = []
var _detail_icon: TextureRect
var _detail_name: Label
var _detail_kind: Label
var _detail_can: Label
var _costs: UiCostList
var _amount_label: Label
var _craft: Button
var _yield_label: Label
var _view: BuildingView = null
var _recipes: Array[RecipeData] = []
## Recetas de la pestaña, en el orden de las tarjetas.
var _shown: Array[RecipeData] = []
var _selected: RecipeData = null
var _amount: int = 1
var _craft_player: AudioStreamPlayer


func _ready() -> void:
	layer = 5
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_window = UiWindow.new()
	center.add_child(_window)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	_window.content.add_child(row)
	row.add_child(_make_recipes_column())
	row.add_child(VSeparator.new())
	row.add_child(_make_detail_column())
	row.add_child(VSeparator.new())
	row.add_child(PlayerInventoryPanel.new(true))
	_window.visible = false
	_craft_player = AudioStreamPlayer.new()
	_craft_player.stream = CRAFT_SOUND
	_craft_player.bus = &"SFX"
	_craft_player.volume_db = CRAFT_SOUND_DB
	_craft_player.max_polyphony = 4   # pulsando muy deprisa, cada golpe suena entero
	add_child(_craft_player)
	WindowManager.window_closed.connect(_on_window_closed)
	WorldState.player_inventory.changed.connect(_refresh)


func _make_recipes_column() -> VBoxContainer:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	column.add_child(UiSection.new(tr("WINDOW_RECIPES")))
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	column.add_child(tabs)
	for tab: Tab in [Tab.ALL, Tab.COMPONENTS, Tab.TOOLS]:
		var button := UiTabButton.new(tr(["TAB_ALL", "TAB_COMPONENTS", "TAB_TOOLS"][tab]))
		button.pressed.connect(_show_tab.bind(tab))
		tabs.add_child(button)
		_tabs.append(button)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(COLUMNS * (CARD_SIZE.x + 8) + 10, VISIBLE_ROWS * (CARD_SIZE.y + 8))
	column.add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = COLUMNS
	_grid.add_theme_constant_override("h_separation", 8)
	_grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(_grid)
	return column


func _make_detail_column() -> VBoxContainer:
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = DETAIL_WIDTH
	column.add_theme_constant_override("separation", 12)
	column.add_child(UiSection.new(tr("WINDOW_CRAFT")))
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	column.add_child(head)
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", UiStyle.chamfered(UiStyle.SLOT_BG, UiStyle.SLOT_EDGE, 1, 8, 8.0))
	head.add_child(frame)
	_detail_icon = SlotUI.make_icon_rect()
	_detail_icon.custom_minimum_size = DETAIL_ICON
	frame.add_child(_detail_icon)
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 2)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(info)
	_detail_name = _make_label("", 22, UiStyle.TITLE)
	_detail_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(_detail_name)
	_detail_kind = _make_label("", 13, UiStyle.SUBTLE)
	info.add_child(_detail_kind)
	_detail_can = _make_label("", 13, UiStyle.GREEN)
	info.add_child(_detail_can)
	_costs = UiCostList.new()
	column.add_child(_costs)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(spacer)
	# Cantidad: − / número / + / Máx
	var amount_row := HBoxContainer.new()
	amount_row.add_theme_constant_override("separation", 6)
	column.add_child(amount_row)
	var amount_text: Label = _make_label(tr("WINDOW_AMOUNT"), 14, UiStyle.SUBTLE)
	amount_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	amount_row.add_child(amount_text)
	amount_row.add_child(_small_button("-", _change_amount.bind(-1)))
	_amount_label = _make_label("1", 17, UiStyle.TEXT)
	_amount_label.custom_minimum_size = Vector2(40, 34)
	_amount_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_amount_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	amount_row.add_child(_amount_label)
	amount_row.add_child(_small_button("+", _change_amount.bind(1)))
	amount_row.add_child(_small_button(tr("WINDOW_MAX"), _set_max_amount))
	_craft = Button.new()
	_craft.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_craft.text = tr("WINDOW_CRAFT").to_upper()
	_craft.focus_mode = Control.FOCUS_NONE
	_craft.custom_minimum_size = Vector2(DETAIL_WIDTH, 48)
	_craft.add_theme_font_size_override("font_size", 20)
	_craft.add_theme_stylebox_override("normal", UiStyle.chamfered(Color8(110, 60, 34), UiStyle.AMBER, 2, 8))
	_craft.add_theme_stylebox_override("hover", UiStyle.chamfered(Color8(134, 74, 42), UiStyle.AMBER, 2, 8))
	_craft.add_theme_stylebox_override("pressed", UiStyle.chamfered(Color8(90, 49, 28), UiStyle.AMBER, 2, 8))
	_craft.add_theme_stylebox_override("disabled", UiStyle.chamfered(Color8(40, 31, 25), UiStyle.SLOT_EDGE, 1, 8))
	_craft.pressed.connect(_on_craft)
	column.add_child(_craft)
	_yield_label = _make_label("", 13, UiStyle.SUBTLE)
	_yield_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_yield_label)
	return column


func _small_button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(38, 34)
	button.pressed.connect(action)
	return button


func _make_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED # el texto ya va traducido
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


## Abre la ventana del banco que muestra `view`.
func open_for(view: BuildingView) -> void:
	_view = view
	_window.set_title(tr(view.placed.data.name_key), "%d × %d" % [view.placed.data.size.x, view.placed.data.size.y])
	_recipes = view.placed.data.crafting_recipes
	_selected = null
	_show_tab(_tab)
	WindowManager.open(_window)
	view.set_window_open(true)


func _unhandled_input(event: InputEvent) -> void:
	if WindowManager.is_showing(_window) and event.is_action_pressed("interact"):
		WindowManager.close()
		get_viewport().set_input_as_handled()


## Rehace las tarjetas de la pestaña `tab` y elige la primera si la elegida no está en ella.
func _show_tab(tab: Tab) -> void:
	_tab = tab
	for i: int in _tabs.size():
		_tabs[i].set_active(i == tab)
	_shown.clear()
	for recipe: RecipeData in _recipes:
		if tab == Tab.ALL or (tab == Tab.TOOLS) == _is_tool(recipe):
			_shown.append(recipe)
	for card: UiCard in _cards:
		card.queue_free()
	_cards.clear()
	for recipe: RecipeData in _shown:
		var card := UiCard.new(CARD_SIZE, CARD_ICON)
		card.set_content(_product(recipe).icon if _product(recipe) != null else null, _recipe_name(recipe))
		card.pressed.connect(_select.bind(recipe))
		_grid.add_child(card)
		_cards.append(card)
	if not _shown.has(_selected):
		_selected = _shown[0] if not _shown.is_empty() else null
		_amount = 1
	_refresh()


func _select(recipe: RecipeData) -> void:
	if recipe != _selected:
		_selected = recipe
		_amount = 1
	_refresh()


func _change_amount(step: int) -> void:
	_amount = clampi(_amount + step, 1, MAX_AMOUNT)
	_refresh()


## Máx: todas las que se pueden hacer con lo que llevas (al menos 1).
func _set_max_amount() -> void:
	if _selected != null:
		_amount = clampi(_craftable(_selected), 1, MAX_AMOUNT)
	_refresh()


## Primer producto de la receta (el que le da nombre e icono).
func _product(recipe: RecipeData) -> ItemData:
	for item: ItemData in recipe.outputs:
		return item
	return null


func _is_tool(recipe: RecipeData) -> bool:
	var item: ItemData = _product(recipe)
	return item != null and item.held_grip == ItemData.HeldGrip.FIST


## "Bobina de cobre" (o "Bobina de cobre ×2" si la receta da más de una).
func _recipe_name(recipe: RecipeData) -> String:
	for item: ItemData in recipe.outputs:
		var amount: int = recipe.outputs[item]
		return tr(item.name_key) if amount == 1 else "%s ×%d" % [tr(item.name_key), amount]
	return String(recipe.id)


## Cuántas veces se puede fabricar la receta con lo que lleva el jugador.
func _craftable(recipe: RecipeData) -> int:
	var inventory: Inventory = WorldState.player_inventory
	var times: int = 999
	for item: ItemData in recipe.inputs:
		@warning_ignore("integer_division")
		times = mini(times, inventory.get_total(item) / recipe.inputs[item])
	return times


## Tarjetas (cuántas se pueden hacer), detalle de la elegida, cantidad y botón.
func _refresh() -> void:
	if not is_instance_valid(_costs):
		return
	for i: int in _cards.size():
		var can: int = _craftable(_shown[i])
		_cards[i].set_badge("×%d" % can, UiStyle.GREEN if can > 0 else UiStyle.RED)
		_cards[i].set_dimmed(can == 0)
		_cards[i].set_selected(_shown[i] == _selected)
	var recipe: RecipeData = _selected
	if recipe == null:
		_detail_icon.texture = null
		_detail_name.text = ""
		_detail_kind.text = ""
		_detail_can.text = ""
		_costs.show_costs({}, null)
		_craft.disabled = true
		_yield_label.text = ""
		return
	var product: ItemData = _product(recipe)
	var can_make: int = _craftable(recipe)
	_detail_icon.texture = product.icon if product != null else null
	_detail_name.text = _recipe_name(recipe)
	_detail_kind.text = tr("TAB_TOOLS_ONE") if _is_tool(recipe) else tr("TAB_COMPONENTS_ONE")
	_detail_can.text = tr("CRAFT_CAN_MAKE") % can_make if can_make > 0 else tr("CRAFT_CANNOT_MAKE")
	_detail_can.add_theme_color_override("font_color", UiStyle.GREEN if can_make > 0 else UiStyle.RED)
	_costs.show_costs(recipe.inputs, WorldState.player_inventory, _amount)
	_amount_label.text = str(_amount)
	var outputs: Dictionary[ItemData, int] = {}
	for item: ItemData in recipe.outputs:
		outputs[item] = recipe.outputs[item] * _amount
	_craft.disabled = can_make < _amount or not WorldState.player_inventory.can_add_all(outputs)
	if product != null:
		_yield_label.text = tr("CRAFT_YIELD") % [recipe.outputs[product] * _amount, tr(product.name_key)]


## Fabrica al instante: quita los ingredientes y da los productos, tantas veces como diga la cantidad.
func _on_craft() -> void:
	var recipe: RecipeData = _selected
	if recipe == null or _craftable(recipe) < _amount:
		return
	var inventory: Inventory = WorldState.player_inventory
	for item: ItemData in recipe.inputs:
		inventory.remove_item(item, recipe.inputs[item] * _amount)
	for item: ItemData in recipe.outputs:
		var left: int = inventory.add_item(item, recipe.outputs[item] * _amount)
		if left > 0:
			push_warning("WorkbenchWindow: no cabían %d de %s" % [left, item.id])
	_craft_player.pitch_scale = randf_range(1.0 - CRAFT_PITCH_JITTER, 1.0 + CRAFT_PITCH_JITTER)
	_craft_player.play()
	_refresh()


func _on_window_closed(window: Control) -> void:
	if window == _window:
		if is_instance_valid(_view):
			_view.set_window_open(false)
		_view = null
