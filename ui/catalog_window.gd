class_name CatalogWindow
extends CanvasLayer
## Catálogo de construcciones (C2.3, D-067): Q lo abre y lo cierra. Pestañas por categoría a la izquierda y
## las construcciones en tarjetas (icono, nombre y coste). Lo bloqueado (la caja logística, D-115) sale con
## candado y no se puede coger. Queda por encima de la barra, que mientras está abierto enseña la barra de
## construcción en uso (con «<» y «>», o Mayús + rueda, para cambiar de barra).
## - Clic en una tarjeta: la coge para colocarla (como el cuentagotas) y entra en el modo construcción.
## - Arrastrar una tarjeta a una casilla de la barra: la fija ahí. Clic derecho en una casilla: la vacía.
## - Con el ratón encima, 1–0: la fija en esa casilla.

const CARD_SIZE: Vector2 = Vector2(118, 128)
const ICON_SIZE: Vector2 = Vector2(64, 64)
const COST_ICON: Vector2 = Vector2(20, 20)
const COLUMNS: int = 5
## Hueco que se deja abajo para la barra (que tiene que verse para soltar en ella).
const BOTTOM_SPACE: int = 130
const COLOR_CARD: Color = Color(1.0, 1.0, 1.0, 0.06)
const COLOR_HOVER: Color = Color(1.0, 0.72, 0.23, 0.22)
const COLOR_LOCKED: Color = Color(1.0, 1.0, 1.0, 0.35)

var _panel: UiWindow
var _grid: GridContainer
var _tabs: Array[Button] = []
var _category: StringName = &""
var _builder: BuildController = null
var _hotbar: HotbarUI = null
## Tarjeta bajo el ratón y lo que representa.
var _hovered: Resource = null
var _cards: Dictionary[Resource, ColorRect] = {}
var _bar_labels: Dictionary[Resource, Label] = {}


## Conecta el catálogo con el modo construcción y con la barra de abajo.
func set_builder(builder: BuildController, hotbar: HotbarUI) -> void:
	_builder = builder
	_hotbar = hotbar
	builder.selection_changed.connect(_refresh_bar_labels)


func _ready() -> void:
	layer = 5
	var area := MarginContainer.new()
	area.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	area.add_theme_constant_override("margin_top", 20)
	area.add_theme_constant_override("margin_bottom", BOTTOM_SPACE)
	area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(area)
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	area.add_child(center)
	_panel = UiWindow.new(tr("CATALOG_TITLE")) # marco del tema (C2)
	center.add_child(_panel)
	var column: VBoxContainer = _panel.content
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	column.add_child(row)
	var tabs := VBoxContainer.new()
	tabs.add_theme_constant_override("separation", 4)
	row.add_child(tabs)
	for category: StringName in Content.CATALOG_CATEGORIES:
		if Content.catalog_entries(category).is_empty():
			continue
		var tab := Button.new()
		tab.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		tab.text = tr("CATALOG_" + String(category).to_upper())
		tab.toggle_mode = true
		tab.focus_mode = Control.FOCUS_NONE
		tab.custom_minimum_size = Vector2(130, 36)
		tab.pressed.connect(_show_category.bind(category))
		tab.set_meta(&"category", category)
		tabs.add_child(tab)
		_tabs.append(tab)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(COLUMNS * (CARD_SIZE.x + 6), 2 * (CARD_SIZE.y + 6))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	row.add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = COLUMNS
	_grid.add_theme_constant_override("h_separation", 6)
	_grid.add_theme_constant_override("v_separation", 6)
	scroll.add_child(_grid)
	var help := _make_label(tr("CATALOG_HELP"), 13)
	help.modulate = Color(1, 1, 1, 0.7)
	column.add_child(help)
	_panel.visible = false
	WindowManager.window_closed.connect(_on_window_closed)
	_show_category(Content.CATALOG_CATEGORIES[0])


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_catalog"):
		if WindowManager.is_showing(_panel):
			WindowManager.close()
		elif not WindowManager.is_open():
			_refresh_bar_labels()
			WindowManager.open(_panel)
			if _hotbar != null:
				_hotbar.set_show_build_bar(true)
		get_viewport().set_input_as_handled()
		return
	if not WindowManager.is_showing(_panel) or _builder == null:
		return
	# Mayús + rueda: otra barra, también con el catálogo abierto.
	if Input.is_action_pressed("select_area") and (event.is_action_pressed("hotbar_next") or event.is_action_pressed("hotbar_prev")):
		_builder.switch_bar(1 if event.is_action_pressed("hotbar_next") else -1)
		get_viewport().set_input_as_handled()
		return
	if _hovered == null or _is_locked(_hovered):
		return
	for i: int in BuildController.BAR_SIZE:
		if event.is_action_pressed("hotbar_%d" % (i + 1)):
			_builder.pin(i, _hovered)
			get_viewport().set_input_as_handled()
			return


func _on_window_closed(_window: Control) -> void:
	_set_hovered(null)
	if _hotbar != null:
		_hotbar.set_show_build_bar(false)


func _show_category(category: StringName) -> void:
	_category = category
	for tab: Button in _tabs:
		tab.button_pressed = tab.get_meta(&"category") == category
	_set_hovered(null)
	for child: Node in _grid.get_children():
		child.queue_free()
	_cards.clear()
	_bar_labels.clear()
	for entry: Resource in Content.catalog_entries(category):
		_grid.add_child(_make_card(entry))
	_refresh_bar_labels()


func _make_card(entry: Resource) -> ColorRect:
	var card := ColorRect.new()
	card.color = COLOR_CARD
	card.custom_minimum_size = CARD_SIZE
	card.tooltip_text = tr(entry.get("name_key"))
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(box)
	var icon: TextureRect = SlotUI.make_icon_rect()
	icon.custom_minimum_size = ICON_SIZE
	icon.texture = entry.get("icon")
	box.add_child(icon)
	var name_label := _make_label(tr(entry.get("name_key")), 12)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(name_label)
	var cost_row := HBoxContainer.new()
	cost_row.alignment = BoxContainer.ALIGNMENT_CENTER
	cost_row.add_theme_constant_override("separation", 3)
	cost_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(cost_row)
	if entry is BuildingData:
		var cost: Dictionary[ItemData, int] = (entry as BuildingData).cost
		for item: ItemData in cost:
			var item_icon: TextureRect = SlotUI.make_icon_rect()
			item_icon.custom_minimum_size = COST_ICON
			item_icon.texture = item.icon
			cost_row.add_child(item_icon)
			cost_row.add_child(_make_label(str(cost[item]), 11))
	var bar_label := _make_label("", 11)
	bar_label.modulate = Color(1.0, 0.72, 0.23)
	bar_label.position = Vector2(CARD_SIZE.x - 54, 4)
	bar_label.size = Vector2(50, 16)
	bar_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	card.add_child(bar_label)
	_bar_labels[entry] = bar_label
	if _is_locked(entry):
		box.modulate = COLOR_LOCKED
		var locked := _make_label(tr("CATALOG_LOCKED"), 11)
		locked.position = Vector2(6, 4)
		card.add_child(locked)
	card.mouse_entered.connect(_set_hovered.bind(entry))
	card.mouse_exited.connect(func() -> void:
		if _hovered == entry:
			_set_hovered(null))
	card.gui_input.connect(_on_card_input.bind(entry))
	card.set_drag_forwarding(_start_drag.bind(entry), Callable(), Callable())
	_cards[entry] = card
	return card


## Arrastrar una tarjeta: se lleva su icono bajo el ratón; se suelta en una casilla de la barra.
func _start_drag(_at: Vector2, entry: Resource) -> Variant:
	if _is_locked(entry):
		return null
	var preview: TextureRect = SlotUI.make_icon_rect()
	preview.texture = entry.get("icon")
	preview.size = ICON_SIZE
	preview.position = -ICON_SIZE * 0.5
	var holder := Control.new()
	holder.add_child(preview)
	_cards[entry].set_drag_preview(holder)
	return {"catalog_entry": entry}


## Clic (al soltar el botón, para que arrastrar no lo cuente como clic): coger la construcción.
func _on_card_input(event: InputEvent, entry: Resource) -> void:
	var click := event as InputEventMouseButton
	if click == null or click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
		return
	if _builder == null or _is_locked(entry) or get_viewport().gui_is_dragging():
		return
	WindowManager.close()
	_builder.pick(entry)


func _set_hovered(entry: Resource) -> void:
	if _hovered != null and _cards.has(_hovered):
		_cards[_hovered].color = COLOR_CARD
	_hovered = entry
	if _hovered != null and _cards.has(_hovered):
		_cards[_hovered].color = COLOR_HOVER


## «Barra 3» en las tarjetas de lo que ya está en la barra en uso.
func _refresh_bar_labels() -> void:
	if _builder == null:
		return
	for entry: Resource in _bar_labels:
		var index: int = _builder.build_bar.find(entry)
		_bar_labels[entry].text = tr("CATALOG_IN_BAR") % str((index + 1) % 10) if index >= 0 else ""


func _is_locked(entry: Resource) -> bool:
	return bool(entry.get("locked"))


func _make_label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED # el texto ya va traducido
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
