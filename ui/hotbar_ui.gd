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
var _cells: Array[PanelContainer] = []
var _slots: Array[SlotUI] = []
var _build_labels: Array[Label] = []
var _hint_label: Label


func _ready() -> void:
	layer = 4
	var bottom := MarginContainer.new()
	bottom.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bottom.grow_horizontal = Control.GROW_DIRECTION_BOTH
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
	row.add_theme_constant_override("separation", 4)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(row)
	for i: int in WorldState.HOTBAR_SLOTS:
		var cell := PanelContainer.new()
		row.add_child(cell)
		var slot := SlotUI.new()
		slot.setup(WorldState.player_inventory, i)
		cell.add_child(slot)
		var build_label := Label.new()
		build_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		build_label.custom_minimum_size = SlotUI.SLOT_SIZE
		build_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		build_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		build_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		build_label.add_theme_font_size_override("font_size", 11)
		build_label.add_theme_color_override("font_outline_color", Color.BLACK)
		build_label.add_theme_constant_override("outline_size", 4)
		cell.add_child(build_label)
		var key := Label.new()
		key.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		key.text = str((i + 1) % 10) # la décima casilla va con el 0
		key.add_theme_font_size_override("font_size", 10)
		key.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		key.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		key.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(key)
		_cells.append(cell)
		_slots.append(slot)
		_build_labels.append(build_label)
	_refresh()


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
	_hint_label.visible = building
	if building:
		_hint_label.text = _build_hint()


## "[Clic] Colocar · [R] Girar · [F] Reflejar · [Clic central] Copiar · [B] Salir" (o lo del cable).
func _build_hint() -> String:
	var parts: PackedStringArray = []
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
			parts.append(_key_hint(&"build_rotate", "BUILD_HINT_ROTATE"))
			if held.output_turns:
				parts.append(_key_hint(&"build_flip", "BUILD_HINT_TURN"))
			elif held.can_flip():
				parts.append(_key_hint(&"build_flip", "BUILD_HINT_FLIP"))
	parts.append(_key_hint(&"pick_building", "BUILD_HINT_PICK"))
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
	var building: bool = _builder != null and _builder.active
	var highlight: int = _builder.selected_slot if building else selected_slot
	for i: int in _cells.size():
		_slots[i].visible = not building
		_build_labels[i].visible = building
		if building:
			var entry: Resource = _builder.build_bar[i] if i < _builder.build_bar.size() else null
			_build_labels[i].text = tr(str(entry.get("name_key"))) if entry != null else ""
		var style := StyleBoxFlat.new()
		style.bg_color = COLOR_CELL
		style.set_corner_radius_all(4)
		if i == highlight:
			style.set_border_width_all(3)
			style.border_color = COLOR_SELECTED
		_cells[i].add_theme_stylebox_override("panel", style)
