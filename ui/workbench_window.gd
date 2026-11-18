class_name WorkbenchWindow
extends CanvasLayer
## Ventana del banco de trabajo (C1.5, D-067; tema y dos columnas en C2). A la izquierda, las recetas y, de
## la elegida, lo que pide (lo que tienes / lo que hace falta, en verde o en rojo), la **cantidad** y el botón
## Fabricar; a la derecha, la mochila. Se fabrica **al instante** con lo del inventario del jugador, y mientras
## está abierta el banco se anima (D-095). E, Esc o el botón de cerrar la cierran.
## Las recetas son las de `BuildingData.crafting_recipes` del banco.

const LEFT_WIDTH: float = 340.0
const NEED_ICON: Vector2 = Vector2(30, 30)

var _window: UiWindow
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
	_window = UiWindow.new()
	center.add_child(_window)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	_window.content.add_child(row)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = LEFT_WIDTH
	left.add_theme_constant_override("separation", 10)
	row.add_child(left)
	left.add_child(UiSection.new(tr("WINDOW_RECIPES")))
	_list = ItemList.new()
	_list.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_list.custom_minimum_size = Vector2(LEFT_WIDTH, 150)
	_list.fixed_icon_size = Vector2i(28, 28)
	_list.item_selected.connect(_on_recipe_selected.unbind(1))
	left.add_child(_list)
	left.add_child(UiSection.new(tr("WINDOW_NEEDS")))
	_needs = VBoxContainer.new()
	_needs.add_theme_constant_override("separation", 4)
	left.add_child(_needs)
	var amount_row := HBoxContainer.new()
	amount_row.add_theme_constant_override("separation", 10)
	amount_row.add_child(_make_label(tr("WINDOW_AMOUNT"), 14, UiStyle.SUBTLE))
	_amount = SpinBox.new()
	_amount.min_value = 1
	_amount.max_value = 99
	_amount.value_changed.connect(_refresh.unbind(1))
	amount_row.add_child(_amount)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	amount_row.add_child(spacer)
	_craft = Button.new()
	_craft.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_craft.text = tr("WINDOW_CRAFT")
	_craft.custom_minimum_size = Vector2(130, 36)
	_craft.pressed.connect(_on_craft)
	amount_row.add_child(_craft)
	left.add_child(amount_row)
	# Mochila a la derecha
	row.add_child(VSeparator.new())
	row.add_child(PlayerInventoryPanel.new())
	_window.visible = false
	WindowManager.window_closed.connect(_on_window_closed)
	WorldState.player_inventory.changed.connect(_refresh)


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
	_list.clear()
	for recipe: RecipeData in _recipes:
		_list.add_item(_recipe_name(recipe), _recipe_icon(recipe))
	if not _recipes.is_empty():
		_list.select(0)
	_amount.value = 1
	_refresh()
	WindowManager.open(_window)
	view.set_window_open(true)


func _unhandled_input(event: InputEvent) -> void:
	if WindowManager.is_showing(_window) and event.is_action_pressed("interact"):
		WindowManager.close()
		get_viewport().set_input_as_handled()


## "Bobina de cobre" (o "Bobina de cobre ×2" si la receta da más de una).
func _recipe_name(recipe: RecipeData) -> String:
	for item: ItemData in recipe.outputs:
		var amount: int = recipe.outputs[item]
		return tr(item.name_key) if amount == 1 else "%s ×%d" % [tr(item.name_key), amount]
	return String(recipe.id)


func _recipe_icon(recipe: RecipeData) -> Texture2D:
	for item: ItemData in recipe.outputs:
		return item.icon
	return null


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
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 8)
		var icon: TextureRect = SlotUI.make_icon_rect()
		icon.custom_minimum_size = NEED_ICON
		icon.texture = item.icon
		line.add_child(icon)
		line.add_child(_make_label(tr(item.name_key), 14, UiStyle.TEXT))
		var count := _make_label("%d / %d" % [have, need], 14, UiStyle.GREEN if have >= need else UiStyle.RED)
		count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		line.add_child(count)
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
	if window == _window:
		if is_instance_valid(_view):
			_view.set_window_open(false)
		_view = null
