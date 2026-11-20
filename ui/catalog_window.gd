class_name CatalogWindow
extends CanvasLayer
## Catálogo de construcciones (C2.3, D-067): Q lo abre y lo cierra. Pestañas por categoría a la izquierda y
## las construcciones en tarjetas (icono y nombre; el icono sale apagado si no te llega para pagarla). A la
## derecha, el detalle de la tarjeta que miras: icono grande, nombre, tamaño y el coste línea a línea, con lo
## que tienes y lo que hace falta en verde o en rojo, como en el banco (C4). Lo bloqueado (la caja logística, D-115) sale con
## candado y no se puede coger. Queda por encima de la barra, que mientras está abierto enseña la barra de
## construcción en uso (con «<» y «>», o Mayús + rueda, para cambiar de barra).
## - Clic en una tarjeta: la coge para colocarla (como el cuentagotas) y entra en el modo construcción.
## - Arrastrar una tarjeta a una casilla de la barra: la fija ahí. Clic derecho en una casilla: la vacía.
## - Con el ratón encima, 1–0: la fija en esa casilla.

const CARD_SIZE: Vector2 = Vector2(118, 128)
const ICON_SIZE: Vector2 = Vector2(64, 64)
const DETAIL_WIDTH: float = 250.0
const DETAIL_ICON: Vector2 = Vector2(80, 80)
const NEED_ICON: Vector2 = Vector2(30, 30)
const NEED_SEPARATION: int = 4
## Alto reservado para el nombre (dos líneas) y para el aviso de abajo: así la ventana no cambia de tamaño
## al pasar de una tarjeta a otra.
const DETAIL_NAME_HEIGHT: float = 46.0
const DETAIL_STATUS_HEIGHT: float = 20.0
## Icono de una construcción que no puedes pagar: apagado.
const COLOR_UNAFFORDABLE: Color = Color(0.55, 0.55, 0.55, 0.55)
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
var _card_icons: Dictionary[Resource, TextureRect] = {}
## Panel de detalle (C4): lo que enseña ahora y sus piezas.
var _detail_entry: Resource = null
var _detail_icon: TextureRect
var _detail_name: Label
var _detail_size: Label
var _detail_status: Label
var _detail_needs: VBoxContainer


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
	row.add_child(VSeparator.new())
	row.add_child(_make_detail_panel())
	var help := _make_label(tr("CATALOG_HELP"), 13)
	help.modulate = Color(1, 1, 1, 0.7)
	column.add_child(help)
	_panel.visible = false
	WindowManager.window_closed.connect(_on_window_closed)
	WorldState.player_inventory.changed.connect(_refresh_costs)
	_show_category(Content.CATALOG_CATEGORIES[0])


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_catalog"):
		if WindowManager.is_showing(_panel):
			WindowManager.close()
		elif not WindowManager.is_open():
			_refresh_bar_labels()
			_refresh_costs()
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
	_card_icons.clear()
	var entries: Array[Resource] = Content.catalog_entries(category)
	for entry: Resource in entries:
		_grid.add_child(_make_card(entry))
	_refresh_bar_labels()
	_show_detail(entries[0] if not entries.is_empty() else null)


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
	icon.modulate = Color.WHITE if _can_afford(entry) else COLOR_UNAFFORDABLE
	box.add_child(icon)
	_card_icons[entry] = icon
	var name_label := _make_label(tr(entry.get("name_key")), 13)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(name_label)
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
		_show_detail(_hovered) # al salir de la tarjeta, el detalle se queda con la última


## «Barra 3» en las tarjetas de lo que ya está en la barra en uso.
func _refresh_bar_labels() -> void:
	if _builder == null:
		return
	for entry: Resource in _bar_labels:
		var index: int = _builder.build_bar.find(entry)
		_bar_labels[entry].text = tr("CATALOG_IN_BAR") % str((index + 1) % 10) if index >= 0 else ""


# --- Detalle (C4) ---

func _make_detail_panel() -> VBoxContainer:
	var panel := VBoxContainer.new()
	panel.custom_minimum_size.x = DETAIL_WIDTH
	panel.add_theme_constant_override("separation", 8)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_detail_icon = SlotUI.make_icon_rect()
	_detail_icon.custom_minimum_size = DETAIL_ICON
	panel.add_child(_detail_icon)
	_detail_name = _make_label("", 17)
	_detail_name.add_theme_color_override("font_color", UiStyle.TEXT)
	_detail_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_name.custom_minimum_size.y = DETAIL_NAME_HEIGHT
	_detail_name.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	panel.add_child(_detail_name)
	_detail_size = _make_label("", 13)
	_detail_size.add_theme_color_override("font_color", UiStyle.SUBTLE)
	panel.add_child(_detail_size)
	panel.add_child(UiSection.new(tr("WINDOW_NEEDS")))
	_detail_needs = VBoxContainer.new()
	_detail_needs.add_theme_constant_override("separation", NEED_SEPARATION)
	# Sitio para tantas líneas como pida la construcción más cara de todo el catálogo.
	var lines: int = _max_cost_lines()
	_detail_needs.custom_minimum_size.y = lines * NEED_ICON.y + (lines - 1) * NEED_SEPARATION
	_detail_needs.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(_detail_needs)
	_detail_status = _make_label("", 13)
	_detail_status.custom_minimum_size.y = DETAIL_STATUS_HEIGHT
	panel.add_child(_detail_status)
	return panel


## Materiales que pide la construcción que más pide (al menos 1, por el «Sin coste»).
func _max_cost_lines() -> int:
	var most: int = 1
	for category: StringName in Content.CATALOG_CATEGORIES:
		for entry: Resource in Content.catalog_entries(category):
			if entry is BuildingData:
				most = maxi(most, (entry as BuildingData).cost.size())
	return most


## Enseña en el panel de la derecha la construcción `entry` (null = vacío).
func _show_detail(entry: Resource) -> void:
	_detail_entry = entry
	for child: Node in _detail_needs.get_children():
		child.queue_free()
	_detail_icon.texture = entry.get("icon") if entry != null else null
	_detail_name.text = tr(entry.get("name_key")) if entry != null else ""
	_detail_size.text = ""
	_detail_status.text = ""
	if entry == null:
		return
	var lines: int = 0
	if entry is BuildingData:
		var data := entry as BuildingData
		_detail_size.text = "%d × %d" % [data.size.x, data.size.y]
		var inventory: Inventory = WorldState.player_inventory
		for item: ItemData in data.cost:
			var need: int = data.cost[item]
			var have: int = inventory.get_total(item)
			var line := HBoxContainer.new()
			line.add_theme_constant_override("separation", 8)
			line.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var icon: TextureRect = SlotUI.make_icon_rect()
			icon.custom_minimum_size = NEED_ICON
			icon.texture = item.icon
			line.add_child(icon)
			var item_name := _make_label(tr(item.name_key), 14)
			item_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			item_name.add_theme_color_override("font_color", UiStyle.TEXT)
			line.add_child(item_name)
			var count := _make_label("%d / %d" % [have, need], 14)
			count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			count.add_theme_color_override("font_color", UiStyle.GREEN if have >= need else UiStyle.RED)
			line.add_child(count)
			_detail_needs.add_child(line)
			lines += 1
	if lines == 0:
		var free := _make_label(tr("CATALOG_NO_COST"), 14)
		free.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		free.add_theme_color_override("font_color", UiStyle.SUBTLE)
		_detail_needs.add_child(free)
	if _is_locked(entry):
		_detail_status.text = tr("CATALOG_LOCKED")
		_detail_status.add_theme_color_override("font_color", UiStyle.RED)


## Al cambiar el inventario: iconos apagados o no y el detalle al día.
func _refresh_costs() -> void:
	for entry: Resource in _card_icons:
		_card_icons[entry].modulate = Color.WHITE if _can_afford(entry) else COLOR_UNAFFORDABLE
	if _panel != null and _panel.visible:
		_show_detail(_detail_entry)


## ¿Lleva el jugador lo que cuesta? (lo que no tiene coste, como el cable, siempre).
func _can_afford(entry: Resource) -> bool:
	if not entry is BuildingData:
		return true
	return WorldState.player_inventory.has_items((entry as BuildingData).cost)


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
