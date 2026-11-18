class_name FocusPanel
extends CanvasLayer
## Letrero de arriba (C1.8, César; como el mod Jade de Minecraft): nombre de lo que miras, su estado de
## energía si es una construcción, la primera fila de lo que guarda si es un almacén, y qué hacen la E y el
## clic. Sustituye a los textos flotantes de las construcciones. Se oculta en el modo construcción y con una
## ventana abierta. Uso: `add_child(FocusPanel.new())` y `set_player(player)`.

const COLOR_BACKGROUND: Color = Color(0.11, 0.09, 0.08, 0.92)
## Naranja de la arcilla (4,2), el acento de las máquinas (Guía de arte), y uno más claro (4,1) para leerse bien.
const COLOR_BORDER: Color = Color8(184, 103, 63)
const COLOR_NAME: Color = Color8(212, 131, 95)
const COLOR_HINT: Color = Color(0.62, 0.6, 0.56)
const COLOR_POWER_ON: Color = Color(0.45, 0.85, 0.4)
const COLOR_POWER_OFF: Color = Color(0.95, 0.35, 0.3)
const COLOR_POWER_MAKES: Color = Color8(255, 184, 58) # ámbar (6,2)
const COLOR_POWER_NONE: Color = Color(0.7, 0.68, 0.64)
const COLOR_PREVIEW_CELL: Color = Color(1.0, 1.0, 1.0, 0.07)
## Casillas de la primera fila de un almacén (las mismas que una fila de su ventana).
const STORAGE_PREVIEW: int = 8
const PREVIEW_SLOT: Vector2 = Vector2(36, 36)
## Lo que pide una estructura por reparar (C4): icono y «entregado/necesario» por material.
const NEED_ICON: Vector2 = Vector2(28, 28)
const COLOR_NEED_DONE: Color = Color(0.45, 0.85, 0.4)
const COLOR_NEED_LEFT: Color = Color(0.91, 0.87, 0.82)

var _player: Player = null
var _top: MarginContainer
var _name_label: Label
var _status_label: Label
var _storage_row: HBoxContainer
var _preview_cells: Array[ColorRect] = []
var _preview_icons: Array[TextureRect] = []
var _preview_amounts: Array[Label] = []
var _hint_label: Label
var _needs_row: HBoxContainer
## Lo que enseña ahora la fila de lo que pide (para rehacerla solo si cambia).
var _needs_key: String = ""


## Jugador del que se lee qué se está mirando.
func set_player(player: Player) -> void:
	_player = player


func _ready() -> void:
	layer = 5
	# Franja de todo el ancho de arriba que centra el letrero, sea cual sea su tamaño.
	_top = MarginContainer.new()
	_top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_top.add_theme_constant_override("margin_top", 12)
	_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_top.visible = false
	add_child(_top)
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_top.add_child(center)
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_BACKGROUND
	style.border_color = COLOR_BORDER
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.content_margin_left = 18.0
	style.content_margin_right = 18.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	panel.add_theme_stylebox_override("panel", style)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 3)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(column)
	_name_label = _make_label(column, 22, COLOR_NAME) # destaca por tamaño y color (sin engrosar: César)
	_status_label = _make_label(column, 15, COLOR_POWER_NONE)
	_storage_row = HBoxContainer.new()
	_storage_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_storage_row.add_theme_constant_override("separation", 3)
	_storage_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_storage_row)
	for i: int in STORAGE_PREVIEW:
		var cell := ColorRect.new()
		cell.custom_minimum_size = PREVIEW_SLOT
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_storage_row.add_child(cell)
		var icon: TextureRect = SlotUI.make_icon_rect()
		icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		cell.add_child(icon)
		var amount := Label.new()
		amount.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		amount.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		amount.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		amount.add_theme_font_size_override("font_size", 12)
		amount.add_theme_color_override("font_outline_color", Color.BLACK)
		amount.add_theme_constant_override("outline_size", 4)
		amount.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(amount)
		_preview_cells.append(cell)
		_preview_icons.append(icon)
		_preview_amounts.append(amount)
	_needs_row = HBoxContainer.new()
	_needs_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_needs_row.add_theme_constant_override("separation", 12)
	_needs_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_needs_row)
	_hint_label = _make_label(column, 13, COLOR_HINT)


func _make_label(parent: Control, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED # el texto ya va traducido
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


## Se rehace cada fotograma: el estado de una máquina o lo que guarda un almacén cambian mientras lo miras.
func _process(_delta: float) -> void:
	var target: Interactable = null
	if _player != null and not WindowManager.is_open() and not _player.build_controller.active \
			and is_instance_valid(_player.focused_interactable):
		target = _player.focused_interactable
	_top.visible = target != null
	if target == null:
		return
	_name_label.text = tr(target.display_name_key) if target.display_name_key != "" else String(target.name)
	var view := target as BuildingView
	if view != null and view.placed == null:
		view = null
	_update_status(view)
	_update_storage(view)
	_update_needs(target)
	_update_hint(target)


## Energía de una construcción: gasta (con o sin energía), genera, o no la necesita.
func _update_status(view: BuildingView) -> void:
	_status_label.visible = view != null
	if view == null:
		return
	var power: float = view.placed.data.power
	var key: String = "POWER_NOT_NEEDED"
	var color: Color = COLOR_POWER_NONE
	if power < 0.0:
		var powered: bool = view.island != null and view.island.is_powered(view.placed.id)
		key = "POWER_ON" if powered else "POWER_NO_POWER"
		color = COLOR_POWER_ON if powered else COLOR_POWER_OFF
	elif power > 0.0:
		key = "POWER_GENERATES"
		color = COLOR_POWER_MAKES
	_status_label.text = ("• " if power != 0.0 else "") + tr(key) # «●» no está en la fuente
	_status_label.add_theme_color_override("font_color", color)


## Primera fila de lo que guarda un almacén (icono y cantidad).
func _update_storage(view: BuildingView) -> void:
	var storage: Inventory = null
	if view != null and view.placed.is_storage():
		storage = view.placed.output
	_storage_row.visible = storage != null
	if storage == null:
		return
	for i: int in STORAGE_PREVIEW:
		var exists: bool = i < storage.slots.size()
		_preview_cells[i].visible = exists
		var stack: ItemStack = storage.slots[i] if exists else null
		var icon: Texture2D = stack.item.icon if stack != null else null
		_preview_icons[i].texture = icon
		_preview_cells[i].color = stack.item.color if stack != null and icon == null else COLOR_PREVIEW_CELL
		_preview_amounts[i].text = str(stack.amount) if stack != null else ""


## Lo que pide una estructura por reparar (C4): «[icono] 1/2   [icono] 0/3». Se rehace solo si cambia.
func _update_needs(target: Interactable) -> void:
	var needs: Array[Dictionary] = target.get_needs()
	var key: String = ""
	for need: Dictionary in needs:
		key += "%s:%d/%d;" % [(need["item"] as ItemData).id, need["done"], need["need"]]
	_needs_row.visible = not needs.is_empty()
	if key == _needs_key:
		return
	_needs_key = key
	for child: Node in _needs_row.get_children():
		child.queue_free()
	for need: Dictionary in needs:
		var item: ItemData = need["item"]
		var pair := HBoxContainer.new()
		pair.add_theme_constant_override("separation", 4)
		pair.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var icon: TextureRect = SlotUI.make_icon_rect()
		icon.custom_minimum_size = NEED_ICON
		icon.texture = item.icon
		pair.add_child(icon)
		var amount: Label = _make_label(pair, 15, COLOR_NEED_DONE if int(need["done"]) >= int(need["need"]) else COLOR_NEED_LEFT)
		amount.text = "%d/%d" % [need["done"], need["need"]]
		_needs_row.add_child(pair)


## "[E] Abrir", "[Clic] Talar"…: qué hacen la E y el clic sobre lo que miras.
func _update_hint(target: Interactable) -> void:
	var parts: PackedStringArray = []
	var interact_key: String = target.get_interact_hint_key()
	if interact_key != "":
		parts.append("[%s] %s" % [InputLabels.action_text(&"interact"), tr(interact_key)])
	var use_key: String = target.get_use_hint_key()
	if use_key != "":
		# Si pide una herramienta que no se lleva, se dice cuál en lugar del clic (C3).
		var required: StringName = target.get_required_tool()
		if required != &"" and _player != null and not _player.can_use_on(target):
			var needed: ItemData = Content.find_item(required)
			parts.append(tr("HINT_NEEDS_TOOL") % (tr(needed.name_key) if needed != null else String(required)))
		else:
			var text: String = "[%s] %s" % [InputLabels.action_text(&"use_tool"), tr(use_key)]
			var progress: String = target.get_progress_text()
			if progress != "":
				text += "  " + progress
			parts.append(text)
	var note: String = target.get_note_text()
	if note != "":
		parts.append(note)
	_hint_label.text = "    ".join(parts)
	_hint_label.visible = not parts.is_empty()
