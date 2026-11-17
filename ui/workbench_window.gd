class_name WorkbenchWindow
extends CanvasLayer
## Ventana del banco de trabajo (C1.5, D-067): recetas a la izquierda; a la derecha, lo que pide la elegida
## (lo que tienes / lo que hace falta), la **cantidad** y el botón Fabricar. Se fabrica **al instante** con
## lo del inventario del jugador, y mientras está abierta el banco se anima (D-095). E o Esc la cierran.
## Las recetas son las de `BuildingData.crafting_recipes` del banco.

const COLOR_OK: Color = Color(0.75, 0.95, 0.6)
const COLOR_MISSING: Color = Color(1.0, 0.5, 0.4)

var _panel: PanelContainer
var _title: Label
var _list: ItemList
var _needs: VBoxContainer
var _amount: SpinBox
var _craft: Button
var _view: BuildingView = null
var _recipes: Array[RecipeData] = []


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
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	column.add_child(row)
	_list = ItemList.new()
	_list.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_list.custom_minimum_size = Vector2(220, 180)
	_list.item_selected.connect(_on_recipe_selected.unbind(1))
	row.add_child(_list)
	var detail := VBoxContainer.new()
	detail.custom_minimum_size.x = 260
	detail.add_theme_constant_override("separation", 8)
	row.add_child(detail)
	detail.add_child(_make_label(tr("WINDOW_NEEDS")))
	_needs = VBoxContainer.new()
	detail.add_child(_needs)
	var amount_row := HBoxContainer.new()
	amount_row.add_child(_make_label(tr("WINDOW_AMOUNT")))
	_amount = SpinBox.new()
	_amount.min_value = 1
	_amount.max_value = 99
	_amount.value_changed.connect(_refresh.unbind(1))
	amount_row.add_child(_amount)
	detail.add_child(amount_row)
	_craft = Button.new()
	_craft.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_craft.text = tr("WINDOW_CRAFT")
	_craft.pressed.connect(_on_craft)
	detail.add_child(_craft)
	column.add_child(HSeparator.new())
	column.add_child(PlayerInventoryPanel.new())
	_panel.visible = false
	WindowManager.window_closed.connect(_on_window_closed)
	WorldState.player_inventory.changed.connect(_refresh)


func _make_label(text: String) -> Label:
	var label := Label.new()
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED # el texto ya va traducido
	label.text = text
	return label


## Abre la ventana del banco que muestra `view`.
func open_for(view: BuildingView) -> void:
	_view = view
	_title.text = tr(view.placed.data.name_key)
	_recipes = view.placed.data.crafting_recipes
	_list.clear()
	for recipe: RecipeData in _recipes:
		_list.add_item(_recipe_name(recipe))
	if not _recipes.is_empty():
		_list.select(0)
	_amount.value = 1
	_refresh()
	WindowManager.open(_panel)
	view.set_window_open(true)


func _unhandled_input(event: InputEvent) -> void:
	if WindowManager.is_showing(_panel) and event.is_action_pressed("interact"):
		WindowManager.close()
		get_viewport().set_input_as_handled()


## "Bobina de cobre" (o "Bobina de cobre ×2" si la receta da más de una).
func _recipe_name(recipe: RecipeData) -> String:
	for item: ItemData in recipe.outputs:
		var amount: int = recipe.outputs[item]
		return tr(item.name_key) if amount == 1 else "%s ×%d" % [tr(item.name_key), amount]
	return String(recipe.id)


func _selected() -> RecipeData:
	var picked: PackedInt32Array = _list.get_selected_items()
	if picked.is_empty() or picked[0] >= _recipes.size():
		return null
	return _recipes[picked[0]]


func _on_recipe_selected() -> void:
	_amount.value = 1
	_refresh()


## Cuántas veces se puede fabricar la receta con lo que lleva el jugador.
func _craftable(recipe: RecipeData) -> int:
	var inventory: Inventory = WorldState.player_inventory
	var times: int = 999
	for item: ItemData in recipe.inputs:
		times = mini(times, inventory.get_total(item) / recipe.inputs[item])
	return times


## Lo que pide la receta elegida para la cantidad elegida (verde si lo tienes, rojo si no) y el botón.
func _refresh() -> void:
	if not is_instance_valid(_needs):
		return
	for child: Node in _needs.get_children():
		child.queue_free()
	var recipe: RecipeData = _selected()
	if recipe == null:
		_craft.disabled = true
		return
	var amount: int = int(_amount.value)
	var inventory: Inventory = WorldState.player_inventory
	for item: ItemData in recipe.inputs:
		var need: int = recipe.inputs[item] * amount
		var have: int = inventory.get_total(item)
		var line := _make_label("%s  %d / %d" % [tr(item.name_key), have, need])
		line.add_theme_color_override("font_color", COLOR_OK if have >= need else COLOR_MISSING)
		_needs.add_child(line)
	var outputs: Dictionary[ItemData, int] = {}
	for item: ItemData in recipe.outputs:
		outputs[item] = recipe.outputs[item] * amount
	_craft.disabled = _craftable(recipe) < amount or not inventory.can_add_all(outputs)


## Fabrica al instante: quita los ingredientes y da los productos, tantas veces como diga la cantidad.
func _on_craft() -> void:
	var recipe: RecipeData = _selected()
	if recipe == null:
		return
	var amount: int = int(_amount.value)
	if _craftable(recipe) < amount:
		return
	var inventory: Inventory = WorldState.player_inventory
	for item: ItemData in recipe.inputs:
		inventory.remove_item(item, recipe.inputs[item] * amount)
	for item: ItemData in recipe.outputs:
		var left: int = inventory.add_item(item, recipe.outputs[item] * amount)
		if left > 0:
			push_warning("WorkbenchWindow: no cabían %d de %s" % [left, item.id])
	_refresh()


func _on_window_closed(window: Control) -> void:
	if window == _panel:
		if is_instance_valid(_view):
			_view.set_window_open(false)
		_view = null
