class_name UiCostList
extends VBoxContainer
## Lo que pide algo, línea a línea (sesión 25, piezas comunes de las ventanas): icono, nombre y «lo que tienes /
## lo que hace falta» en verde si llega o en rojo si no. La usan el banco y el catálogo Q.
## Uso: `list.show_costs(coste, inventario, veces)`; se rehace en cada llamada.

const ICON_SIZE: Vector2 = Vector2(32, 32)


func _init() -> void:
	add_theme_constant_override("separation", 6)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## `costs`: ítem → cantidad por vez; `times`: cuántas veces (la cantidad elegida en el banco).
func show_costs(costs: Dictionary, inventory: Inventory, times: int = 1) -> void:
	for child: Node in get_children():
		child.queue_free()
	for item: ItemData in costs:
		var need: int = int(costs[item]) * times
		var have: int = inventory.get_total(item) if inventory != null else 0
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 10)
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var icon: TextureRect = SlotUI.make_icon_rect()
		icon.custom_minimum_size = ICON_SIZE
		icon.texture = item.icon
		line.add_child(icon)
		line.add_child(_label(tr(item.name_key), UiStyle.TEXT, false))
		line.add_child(_label("%d / %d" % [have, need], UiStyle.GREEN if have >= need else UiStyle.RED, true))
		add_child(line)


func _label(text: String, color: Color, right: bool) -> Label:
	var label := Label.new()
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED # el texto ya va traducido
	label.text = text
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if right:
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return label
