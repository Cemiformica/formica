class_name UiRateRow
extends HBoxContainer
## Ritmo por minuto de una construcción (sesión 25, César: cada máquina debe decir cuánto pide y cuánto da):
## «[icono] 30/min + [icono] 15/min  →  [icono] 15/min». Una cinta dice lo que cabe que pase («Hasta 90/min»)
## y el talador lleva «~» delante, porque depende de los árboles que tenga en su área. Es el ritmo trabajando sin
## parar, sin contar esperas (falta de entrada, salida llena o sin energía).
## Lo usan el letrero de arriba (`FocusPanel`) y la ventana de la máquina (`MachineWindow`).
## Uso: `var row := UiRateRow.new(tamaño_icono, tamaño_letra)` y, cada vez que haga falta, `row.show_for(placed,
## island)`, que se rehace solo si algo ha cambiado.

var _icon_size: Vector2
var _font_size: int
## Lo que enseña ahora (para rehacerla solo si cambia).
var _key: String = "-"


func _init(p_icon_size: Vector2 = Vector2(24, 24), p_font_size: int = 14) -> void:
	_icon_size = p_icon_size
	_font_size = p_font_size
	alignment = BoxContainer.ALIGNMENT_CENTER
	add_theme_constant_override("separation", 4)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## «20/min», «7,5/min» (coma decimal en español y catalán).
static func rate_text(per_minute: float) -> String:
	var text: String
	if absf(per_minute - roundf(per_minute)) < 0.05:
		text = str(roundi(per_minute))
	else:
		text = String.num(per_minute, 1)
		var locale: String = TranslationServer.get_locale()
		if locale.begins_with("es") or locale.begins_with("ca"):
			text = text.replace(".", ",")
	return text + "/min"


## Enseña el ritmo de `placed` (null = nada). Se oculta si no hay nada que enseñar (almacenes, postes…).
## Devuelve si se ve.
func show_for(placed: PlacedBuilding, island: IslandState) -> bool:
	var rates: Dictionary = {}
	var belt: float = 0.0
	if placed != null:
		if placed.is_belt():
			belt = placed.belt_rate_per_minute()
		else:
			rates = placed.rates_per_minute(island)
	var inputs: Dictionary = rates.get("in", {})
	var outputs: Dictionary = rates.get("out", {})
	var approx: bool = rates.get("approx", false)
	var key: String = "belt:%s" % rate_text(belt) if belt > 0.0 else ""
	for side: Dictionary in [inputs, outputs]:
		for item: ItemData in side:
			key += "%s=%s;" % [item.id, rate_text(side[item])]
		key += "|"
	visible = belt > 0.0 or not inputs.is_empty() or not outputs.is_empty()
	if key == _key:
		return visible
	_key = key
	for child: Node in get_children():
		child.queue_free()
	if not visible:
		return false
	if belt > 0.0:
		add_child(_label(tr("RATE_BELT_MAX") % rate_text(belt), UiStyle.TEXT))
		return true
	_add_side(inputs, false)
	if not inputs.is_empty() and not outputs.is_empty():
		add_child(_label("  →  ", UiStyle.TITLE))
	_add_side(outputs, approx)
	return true


func _add_side(items: Dictionary, approx: bool) -> void:
	var first: bool = true
	for item: ItemData in items:
		if not first:
			add_child(_label(" + ", UiStyle.SUBTLE))
		first = false
		var icon: TextureRect = SlotUI.make_icon_rect()
		icon.custom_minimum_size = _icon_size
		icon.texture = item.icon
		icon.tooltip_text = tr(item.name_key)
		icon.mouse_filter = Control.MOUSE_FILTER_PASS
		add_child(icon)
		add_child(_label(("~" if approx else "") + rate_text(items[item]), UiStyle.TEXT))


func _label(text: String, color: Color) -> Label:
	var label := Label.new()
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED # el texto ya va traducido
	label.text = text
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", _font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
