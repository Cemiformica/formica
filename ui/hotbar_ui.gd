class_name HotbarUI
extends CanvasLayer
## Barra de abajo (C1.2, César): siempre en pantalla, con las 10 primeras casillas del inventario del jugador.
## En el modo construcción enseña la barra de construcción en su lugar (nombre de cada construcción), para
## que construir se sienta como un modo aparte. Fuera del modo, 1–0 y la rueda eligen casilla; lo elegido
## es lo que Mira llevará en la mano (C1.6). Con una ventana abierta, sus casillas se manejan con clics.
## En el modo construcción, encima de la barra, una línea de ayuda con las teclas útiles según lo que se
## lleva (C1.8): "[Clic] Colocar · [R] Girar · [F] Reflejar · [B] Salir"…

## Se emite al elegir otra casilla de la barra normal.
signal selection_changed(index: int)

const COLOR_CELL: Color = Color(0.08, 0.08, 0.08, 0.55)
const COLOR_SELECTED: Color = Color(1.0, 0.72, 0.23)

## Casilla elegida de la barra normal.
var selected_slot: int = 0

var _builder: BuildController = null
var _dismantler: DismantleController = null
var _cells: Array[PanelContainer] = []
var _slots: Array[SlotUI] = []
var _build_labels: Array[Label] = []
var _build_icons: Array[TextureRect] = []
## El catálogo (Q) está abierto: se enseña la barra de construcción para soltar en ella (C2.3).
var show_build_bar: bool = false
## «Barra 2/5» y flechas para cambiar de barra con el catálogo abierto.
var _bar_label: Label
var _bar_buttons: Array[Button] = []
var _hint_label: Label


func _ready() -> void:
	layer = 4
	# Todo el ancho de abajo (C2b, César): así la barra queda siempre centrada y con su tamaño, aunque el
	# texto de ayuda de encima cambie de largo (antes la columna se ensanchaba y no volvía a encoger).
	var bottom := MarginContainer.new()
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom.add_theme_constant_override("margin_bottom", 14)
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bottom)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_child(column)
	_hint_label = Label.new()
	_hint_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED # el texto ya va traducido
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.add_theme_font_size_override("font_size", 15)
	_hint_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_hint_label.add_theme_constant_override("outline_size", 5)
	_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_label.visible = false
	column.add_child(_hint_label)
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	row.add_theme_constant_override("separation", 4)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(row)
	# Barra de construcción en uso (C2.3): «2/5» y, con el catálogo abierto, flechas para cambiarla.
	var prev_button := _make_bar_button("<", -1)
	row.add_child(prev_button)
	_bar_label = Label.new()
	_bar_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_bar_label.custom_minimum_size = Vector2(44, 0)
	_bar_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bar_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_bar_label.add_theme_color_override("font_color", COLOR_SELECTED)
	_bar_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_bar_label.add_theme_constant_override("outline_size", 4)
	_bar_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_bar_label)
	for i: int in WorldState.HOTBAR_SLOTS:
		var cell := PanelContainer.new()
		row.add_child(cell)
		var slot := SlotUI.new()
		slot.framed = false # el marco lo pone la celda (tema, C2)
		slot.setup(WorldState.player_inventory, i)
		cell.add_child(slot)
		var build_label := Label.new()
		build_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		build_label.custom_minimum_size = SlotUI.SLOT_SIZE
		build_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		build_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		build_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		build_label.add_theme_font_size_override("font_size", 9)
		build_label.add_theme_color_override("font_outline_color", Color.BLACK)
		build_label.add_theme_constant_override("outline_size", 4)
		build_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var build_icon: TextureRect = SlotUI.make_icon_rect() # icono de la construcción (C2.3)
		build_icon.custom_minimum_size = SlotUI.SLOT_SIZE
		cell.add_child(build_icon)
		_build_icons.append(build_icon)
		cell.add_child(build_label)
		var key := Label.new()
		key.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		key.text = str((i + 1) % 10) # la décima casilla va con el 0
		key.add_theme_font_size_override("font_size", 10)
		key.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		key.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		key.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(key)
		# Con el catálogo abierto: soltar una construcción arrastrada y clic derecho para vaciar (C2.3).
		cell.set_drag_forwarding(Callable(), _can_drop_on_cell.bind(i), _drop_on_cell.bind(i))
		cell.gui_input.connect(_on_cell_input.bind(i))
		_cells.append(cell)
		_slots.append(slot)
		_build_labels.append(build_label)
	var next_button := _make_bar_button(">", 1)
	row.add_child(next_button)
	_refresh()


func _make_bar_button(text: String, step: int) -> Button:
	var button := Button.new()
	button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	button.text = text
	button.custom_minimum_size = Vector2(28, SlotUI.SLOT_SIZE.y)
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(func() -> void:
		if _builder != null:
			_builder.switch_bar(step))
	_bar_buttons.append(button)
	return button


## Enseña u oculta la barra de construcción mientras el catálogo está abierto (lo llama `CatalogWindow`).
func set_show_build_bar(value: bool) -> void:
	show_build_bar = value
	_refresh()


func _can_drop_on_cell(_at: Vector2, data: Variant, _index: int) -> bool:
	return show_build_bar and data is Dictionary and (data as Dictionary).has("catalog_entry")


func _drop_on_cell(_at: Vector2, data: Variant, index: int) -> void:
	if _builder != null:
		_builder.pin(index, (data as Dictionary)["catalog_entry"])


func _on_cell_input(event: InputEvent, index: int) -> void:
	var click := event as InputEventMouseButton
	if show_build_bar and click != null and click.pressed and click.button_index == MOUSE_BUTTON_RIGHT and _builder != null:
		_builder.clear_slot(index)
		_cells[index].accept_event() # la capa no es un control: lo acepta la casilla


## Conecta la barra con el modo desmontar (C2.2), para enseñar su ayuda de teclas.
func set_dismantler(dismantler: DismantleController) -> void:
	_dismantler = dismantler


## Conecta la barra con el modo construcción del jugador.
func set_builder(builder: BuildController) -> void:
	_builder = builder
	builder.mode_changed.connect(_refresh.unbind(1))
	builder.selection_changed.connect(_refresh)
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if WindowManager.is_open() or (_builder != null and _builder.active):
		return # en el modo construcción, las teclas son de su barra (BuildController)
	for i: int in WorldState.HOTBAR_SLOTS:
		if event.is_action_pressed("hotbar_%d" % (i + 1)):
			_select(i)
			return
	if event.is_action_pressed("hotbar_next"):
		_select((selected_slot + 1) % WorldState.HOTBAR_SLOTS)
	elif event.is_action_pressed("hotbar_prev"):
		_select(posmod(selected_slot - 1, WorldState.HOTBAR_SLOTS))


## La ayuda de teclas se rehace cada fotograma: depende de lo que se lleva y de si hay un cable a medias.
func _process(_delta: float) -> void:
	var building: bool = _builder != null and _builder.active and not WindowManager.is_open()
	var dismantling: bool = _dismantler != null and _dismantler.active and not WindowManager.is_open()
	_hint_label.visible = building or dismantling
	if building:
		_hint_label.text = _build_hint()
	elif dismantling:
		_hint_label.text = _dismantle_hint()


## "[Clic] Marcar · [Mayús + Clic] Área · [Clic derecho] Desmontar (3) · [X] Salir"
func _dismantle_hint() -> String:
	var parts: PackedStringArray = [_key_hint(&"build_place", "DISMANTLE_HINT_MARK"),
			"[%s + %s] %s" % [InputLabels.action_text(&"select_area"), InputLabels.action_text(&"build_place"), tr("DISMANTLE_HINT_AREA")]]
	var count: int = _dismantler.get_marked_ids().size()
	if count > 0:
		parts.append("[%s] %s" % [InputLabels.action_text(&"dismantle_confirm"), tr("DISMANTLE_HINT_CONFIRM") % count])
	parts.append(_key_hint(&"toggle_dismantle", "BUILD_HINT_EXIT"))
	return "  ·  ".join(parts)


## "[Clic] Colocar · [R] Girar · [F] Reflejar · [Clic central] Copiar · [B] Salir" (o lo del cable).
func _build_hint() -> String:
	var parts: PackedStringArray = []
	if _builder.is_carrying():
		# Moviendo una construcción (C2.5): soltar, girar, reflejar y devolver.
		var carried: BuildingData = _builder.get_held()
		parts.append(tr("BUILD_HINT_CARRYING") % tr(carried.name_key))
		parts.append(_key_hint(&"build_place", "BUILD_HINT_DROP"))
		parts.append(_key_hint(&"build_rotate", "BUILD_HINT_ROTATE"))
		if carried.output_turns:
			parts.append(_key_hint(&"build_flip", "BUILD_HINT_TURN"))
		elif carried.can_flip():
			parts.append(_key_hint(&"build_flip", "BUILD_HINT_FLIP"))
		parts.append(_key_hint(&"build_move", "BUILD_HINT_RETURN"))
		return "  ·  ".join(parts)
	if _builder.is_dragging():
		# Tramo de cintas (C2b): soltar construye y clic derecho cancela.
		parts.append(tr("BUILD_HINT_BELT_RELEASE") % _builder.drag_count())
		parts.append(_key_hint(&"build_move", "BUILD_HINT_CANCEL"))
		return "  ·  ".join(parts)
	if _builder.holding_cable():
		if _builder.cable_started():
			parts.append(_key_hint(&"build_place", "BUILD_HINT_CABLE_END"))
			parts.append(_key_hint(&"ui_cancel", "BUILD_HINT_CANCEL"))
		else:
			parts.append(_key_hint(&"build_place", "BUILD_HINT_CABLE_START"))
	else:
		var held: BuildingData = _builder.get_held()
		if held != null:
			if _builder.is_held_picked():
				parts.append(tr("BUILD_HINT_HELD") % tr(held.name_key))
			parts.append(_key_hint(&"build_place", "BUILD_HINT_PLACE"))
			if held.belt_speed > 0.0:
				parts.append("[%s + %s] %s" % [InputLabels.action_text(&"build_place"), tr("INPUT_DRAG"), tr("BUILD_HINT_BELT_LINE")])
			parts.append(_key_hint(&"build_rotate", "BUILD_HINT_ROTATE"))
			if held.output_turns:
				parts.append(_key_hint(&"build_flip", "BUILD_HINT_TURN"))
			elif held.can_flip():
				parts.append(_key_hint(&"build_flip", "BUILD_HINT_FLIP"))
	parts.append(_key_hint(&"pick_building", "BUILD_HINT_PICK"))
	parts.append(_key_hint(&"build_move", "BUILD_HINT_MOVE"))
	parts.append(_key_hint(&"toggle_catalog", "BUILD_HINT_CATALOG"))
	parts.append(_key_hint(&"toggle_build", "BUILD_HINT_EXIT"))
	return "  ·  ".join(parts)


func _key_hint(action: StringName, text_key: String) -> String:
	return "[%s] %s" % [InputLabels.action_text(action), tr(text_key)]


func _select(index: int) -> void:
	selected_slot = index
	_refresh()
	selection_changed.emit(index)


## Enseña la barra normal o la de construcción y resalta la casilla elegida.
func _refresh() -> void:
	var building: bool = _builder != null and (_builder.active or show_build_bar)
	var highlight: int = _builder.selected_slot if building else selected_slot
	# Se ocultan sin quitarlos del sitio, para que la barra no se desplace al entrar en el modo.
	_bar_label.text = "%d/%d" % [_builder.bar_index + 1, BuildController.BAR_COUNT] if building else ""
	for button: Button in _bar_buttons:
		button.modulate.a = 1.0 if show_build_bar else 0.0
		button.disabled = not show_build_bar
		button.mouse_filter = Control.MOUSE_FILTER_STOP if show_build_bar else Control.MOUSE_FILTER_IGNORE
	for i: int in _cells.size():
		_slots[i].visible = not building
		_build_labels[i].visible = building
		_build_icons[i].visible = building
		if building:
			var entry: Resource = _builder.build_bar[i] if i < _builder.build_bar.size() else null
			_build_labels[i].text = tr(str(entry.get("name_key"))) if entry != null else ""
			_build_icons[i].texture = entry.get("icon") if entry != null else null
		var style: StyleBoxFlat = UiStyle.slot_style(UiStyle.AMBER if i == highlight else UiStyle.SLOT_EDGE, 2 if i == highlight else 1)
		style.bg_color = Color(UiStyle.SLOT_BG, 0.85)
		_cells[i].add_theme_stylebox_override("panel", style)
