class_name CatalogWindow
extends CanvasLayer
## Catálogo de construcciones (C2.3, D-067): Q lo abre y lo cierra, solo en el modo construcción (D-193).
## Rehecho en la sesión 25 con la opción «B» que eligió César, con las piezas comunes de las ventanas:
## - **Categorías** en una columna a la izquierda, cada una con su icono y cuántas construcciones tiene.
## - **Tarjetas** grandes (`UiCard`) de la categoría elegida: apagadas si no te llega para pagarlas, con el
##   número de la casilla de la barra en uso donde están fijadas y «Bloqueada» si aún no se puede (D-115).
## - **Detalle** a la derecha: icono grande, nombre, categoría y tamaño, energía (genera o consume), qué hace y
##   el coste línea a línea en verde o en rojo (`UiCostList`).
## Si las categorías o las tarjetas no caben, su columna se desplaza (César).
## Queda por encima de la barra, que mientras está abierto enseña la barra de construcción en uso (con «<» y «>»,
## o Ctrl + rueda, para cambiar de barra).
## - Clic en una tarjeta: la coge para colocarla (como el cuentagotas) y entra en el modo construcción.
## - Arrastrar una tarjeta a una casilla de la barra: la fija ahí. Clic derecho en una casilla: la vacía.
## - Con el ratón encima, 1–0: la fija en esa casilla.

const CARD_SIZE: Vector2 = Vector2(138, 136)
const CARD_ICON: float = 80.0
const COLUMNS: int = 3
## Filas de tarjetas que se ven sin desplazar.
const VISIBLE_ROWS: int = 2
const CATEGORY_WIDTH: float = 180.0
const CATEGORY_ICON: Vector2 = Vector2(42, 42)
const DETAIL_WIDTH: float = 350.0
const DETAIL_ICON: Vector2 = Vector2(96, 96)
## Hueco que se deja abajo para la barra (que tiene que verse para soltar en ella).
const BOTTOM_SPACE: int = 130
## Energía que consume: naranja claro (la que genera va en ámbar).
const COLOR_CONSUMES: Color = Color8(242, 140, 90)

var _panel: UiWindow
var _categories: Dictionary[StringName, PanelContainer] = {}
var _category_labels: Dictionary[StringName, Label] = {}
var _category: StringName = &""
var _cards_title: UiSection
var _grid: GridContainer
var _builder: BuildController = null
var _hotbar: HotbarUI = null
## Tarjeta bajo el ratón (para fijarla con 1–0) y la que enseña el detalle.
var _hovered: Resource = null
var _cards: Dictionary[Resource, UiCard] = {}
var _detail_entry: Resource = null
var _detail_icon: TextureRect
var _detail_name: Label
var _detail_kind: Label
var _detail_power: Label
var _detail_desc: Label
var _detail_costs: UiCostList
var _detail_status: Label


## Conecta el catálogo con el modo construcción y con la barra de abajo.
func set_builder(builder: BuildController, hotbar: HotbarUI) -> void:
	_builder = builder
	_hotbar = hotbar
	builder.selection_changed.connect(_refresh_cards)


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
	_panel = UiWindow.new(tr("CATALOG_TITLE"), "Q") # marco del tema (C2)
	center.add_child(_panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	_panel.content.add_child(row)
	row.add_child(_make_categories_column())
	row.add_child(VSeparator.new())
	row.add_child(_make_cards_column())
	row.add_child(VSeparator.new())
	row.add_child(_make_detail_column())
	var help := _make_label(tr("CATALOG_HELP"), 13, UiStyle.SUBTLE)
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_panel.content.add_child(help)
	_panel.visible = false
	WindowManager.window_closed.connect(_on_window_closed)
	WorldState.player_inventory.changed.connect(_refresh_cards)
	_show_category(Content.CATALOG_CATEGORIES[0])


# --- Columnas ---

func _make_categories_column() -> VBoxContainer:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	column.add_child(UiSection.new(tr("CATALOG_CATEGORIES")))
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size.x = CATEGORY_WIDTH
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 8)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for category: StringName in Content.CATALOG_CATEGORIES:
		var entries: Array[Resource] = Content.catalog_entries(category)
		if entries.is_empty():
			continue
		list.add_child(_make_category_button(category, entries))
	return column


## Botón de categoría: icono de su primera construcción, nombre y cuántas tiene.
func _make_category_button(category: StringName, entries: Array[Resource]) -> PanelContainer:
	var button := PanelContainer.new()
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.custom_minimum_size = Vector2(CATEGORY_WIDTH - 12, 0)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 10)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(line)
	var icon: TextureRect = SlotUI.make_icon_rect()
	icon.custom_minimum_size = CATEGORY_ICON
	icon.texture = entries[0].get("icon")
	line.add_child(icon)
	var texts := VBoxContainer.new()
	texts.add_theme_constant_override("separation", 0)
	texts.alignment = BoxContainer.ALIGNMENT_CENTER
	texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(texts)
	var title: Label = _make_label(tr("CATALOG_" + String(category).to_upper()), 15, UiStyle.TEXT)
	texts.add_child(title)
	_category_labels[category] = title
	var count: String = tr("CATALOG_COUNT_ONE") if entries.size() == 1 else tr("CATALOG_COUNT") % entries.size()
	texts.add_child(_make_label(count, 11, UiStyle.SUBTLE))
	button.gui_input.connect(func(event: InputEvent) -> void:
		var click := event as InputEventMouseButton
		if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
			_show_category(category))
	button.mouse_entered.connect(_style_category.bind(category, true))
	button.mouse_exited.connect(_style_category.bind(category, false))
	_categories[category] = button
	return button


func _make_cards_column() -> VBoxContainer:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	_cards_title = UiSection.new("")
	column.add_child(_cards_title)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(COLUMNS * (CARD_SIZE.x + 8) + 10, VISIBLE_ROWS * (CARD_SIZE.y + 8))
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
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
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(UiSection.new(tr("CATALOG_DETAIL")))
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
	info.add_theme_constant_override("separation", 3)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(info)
	_detail_name = _make_label("", 21, UiStyle.TITLE)
	_detail_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(_detail_name)
	_detail_kind = _make_label("", 13, UiStyle.SUBTLE)
	info.add_child(_detail_kind)
	_detail_power = _make_label("", 14, UiStyle.SUBTLE)
	info.add_child(_detail_power)
	_detail_desc = _make_label("", 13, UiStyle.TEXT)
	_detail_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_desc.custom_minimum_size.x = DETAIL_WIDTH - DETAIL_ICON.x - 30.0
	info.add_child(_detail_desc)
	column.add_child(UiSection.new(tr("CATALOG_COST")))
	_detail_costs = UiCostList.new()
	column.add_child(_detail_costs)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(spacer)
	_detail_status = _make_label("", 14, UiStyle.GREEN)
	column.add_child(_detail_status)
	return column


# --- Abrir, cerrar y teclas ---

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_catalog"):
		if WindowManager.is_showing(_panel):
			WindowManager.close()
		elif not WindowManager.is_open() and _builder != null and _builder.active:   # solo en el modo construcción (César)
			_refresh_cards()
			WindowManager.open(_panel)
			if _hotbar != null:
				_hotbar.set_show_build_bar(true)
		get_viewport().set_input_as_handled()
		return
	if not WindowManager.is_showing(_panel) or _builder == null:
		return
	# Ctrl + rueda: otra barra, también con el catálogo abierto.
	if Input.is_action_pressed("bar_switch") and (event.is_action_pressed("hotbar_next") or event.is_action_pressed("hotbar_prev")):
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
	_hovered = null
	if _hotbar != null:
		_hotbar.set_show_build_bar(false)


# --- Categorías y tarjetas ---

func _show_category(category: StringName) -> void:
	_category = category
	for key: StringName in _categories:
		_style_category(key, false)
	_cards_title.set_text(tr("CATALOG_" + String(category).to_upper()))
	_hovered = null
	for card: UiCard in _cards.values():
		card.queue_free()
	_cards.clear()
	var entries: Array[Resource] = Content.catalog_entries(category)
	for entry: Resource in entries:
		_grid.add_child(_make_card(entry))
	_show_detail(entries[0] if not entries.is_empty() else null)
	_refresh_cards()


## La categoría elegida, con el borde y el nombre en ámbar; las demás se iluminan con el ratón encima.
func _style_category(category: StringName, hover: bool) -> void:
	if not _categories.has(category):
		return
	var active: bool = category == _category
	var lit: bool = active or hover
	_categories[category].add_theme_stylebox_override("panel", UiStyle.chamfered(UiCard.BG_LIT if lit else UiCard.BG,
			UiStyle.AMBER if active else (UiStyle.TITLE if hover else UiStyle.SLOT_EDGE), 2 if active else 1, 8, 7.0))
	_category_labels[category].add_theme_color_override("font_color", UiStyle.AMBER if active else UiStyle.TEXT)


func _make_card(entry: Resource) -> UiCard:
	var card := UiCard.new(CARD_SIZE, CARD_ICON, 14)
	card.set_content(entry.get("icon"), tr(entry.get("name_key")))
	card.hovered.connect(_on_card_hovered.bind(entry))
	card.mouse_exited.connect(func() -> void:
		if _hovered == entry:
			_hovered = null)
	card.pressed.connect(_on_card_pressed.bind(entry))
	card.set_drag_forwarding(_start_drag.bind(entry), Callable(), Callable())
	_cards[entry] = card
	return card


func _on_card_hovered(entry: Resource) -> void:
	_hovered = entry
	_show_detail(entry) # al salir de la tarjeta, el detalle se queda con la última
	_refresh_cards()


## Clic (al soltar el botón, para que arrastrar no lo cuente como clic): coger la construcción.
func _on_card_pressed(entry: Resource) -> void:
	if _builder == null or _is_locked(entry) or get_viewport().gui_is_dragging():
		return
	WindowManager.close()
	_builder.pick(entry)


## Arrastrar una tarjeta: se lleva su icono bajo el ratón; se suelta en una casilla de la barra.
func _start_drag(_at: Vector2, entry: Resource) -> Variant:
	if _is_locked(entry):
		return null
	var preview: TextureRect = SlotUI.make_icon_rect()
	preview.texture = entry.get("icon")
	preview.size = Vector2(CARD_ICON, CARD_ICON)
	preview.position = -preview.size * 0.5
	var holder := Control.new()
	holder.add_child(preview)
	_cards[entry].set_drag_preview(holder)
	return {"catalog_entry": entry}


## Tarjetas al día: apagadas si no te llega o están bloqueadas, número de la barra y la del detalle resaltada.
## También el detalle (el coste depende de lo que llevas).
func _refresh_cards() -> void:
	for entry: Resource in _cards:
		var card: UiCard = _cards[entry]
		var locked: bool = _is_locked(entry)
		card.set_dimmed(locked or not _can_afford(entry))
		card.set_badge(tr("CATALOG_LOCKED") if locked else "", UiStyle.RED)
		var index: int = _builder.build_bar.find(entry) if _builder != null else -1
		card.set_slot_number((index + 1) % 10 if index >= 0 and not locked else -1)
		card.set_selected(entry == _detail_entry)
	if _panel != null and _panel.visible:
		_show_detail(_detail_entry)


# --- Detalle ---

## Enseña en la columna de la derecha la construcción `entry` (null = vacío).
func _show_detail(entry: Resource) -> void:
	_detail_entry = entry
	_detail_icon.texture = entry.get("icon") if entry != null else null
	_detail_name.text = tr(entry.get("name_key")) if entry != null else ""
	_detail_kind.text = ""
	_detail_power.text = ""
	_detail_desc.text = ""
	_detail_status.text = ""
	if entry == null:
		_detail_costs.show_costs({}, null)
		return
	var category: String = tr("CATALOG_" + String(entry.get("category")).to_upper())
	var desc_key: String = String(entry.get("name_key")) + "_DESC"
	_detail_desc.text = tr(desc_key) if tr(desc_key) != desc_key else ""
	if entry is BuildingData:
		var data := entry as BuildingData
		_detail_kind.text = tr("CATALOG_KIND") % [category, data.size.x, data.size.y]
		if data.power > 0.0:
			_detail_power.text = tr("CATALOG_POWER_MAKES") % roundi(data.power)
			_detail_power.add_theme_color_override("font_color", UiStyle.AMBER)
		elif data.power < 0.0:
			_detail_power.text = tr("CATALOG_POWER_USES") % roundi(-data.power)
			_detail_power.add_theme_color_override("font_color", COLOR_CONSUMES)
		else:
			_detail_power.text = tr("POWER_NOT_NEEDED")
			_detail_power.add_theme_color_override("font_color", UiStyle.SUBTLE)
		_detail_costs.show_costs(data.cost, WorldState.player_inventory)
	else:
		_detail_kind.text = category
		_detail_costs.show_costs({}, null)
	if _is_locked(entry):
		_detail_status.text = tr("CATALOG_LOCKED")
		_detail_status.add_theme_color_override("font_color", UiStyle.RED)
	elif not (entry is BuildingData) or (entry as BuildingData).cost.is_empty():
		_detail_status.text = tr("CATALOG_NO_COST")
		_detail_status.add_theme_color_override("font_color", UiStyle.SUBTLE)
	elif _can_afford(entry):
		_detail_status.text = tr("CATALOG_CAN_BUILD")
		_detail_status.add_theme_color_override("font_color", UiStyle.GREEN)
	else:
		_detail_status.text = tr("CATALOG_MISSING")
		_detail_status.add_theme_color_override("font_color", UiStyle.RED)


## ¿Lleva el jugador lo que cuesta? (lo que no tiene coste, como el cable, siempre).
func _can_afford(entry: Resource) -> bool:
	if not entry is BuildingData:
		return true
	return WorldState.player_inventory.has_items((entry as BuildingData).cost)


func _is_locked(entry: Resource) -> bool:
	return bool(entry.get("locked"))


func _make_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED # el texto ya va traducido
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
