class_name UiTabButton
extends Button
## Pestaña de la interfaz (sesión 25, piezas comunes de las ventanas): caja pequeña de esquinas cortadas; la
## activa, con el borde y el texto en ámbar. La usan el banco y el catálogo Q.
## Uso: `var tab := UiTabButton.new(tr("TAB_ALL"))`, `tab.pressed.connect(...)` y `tab.set_active(true)`.

const BG: Color = Color8(22, 17, 14)
const BG_ACTIVE: Color = Color8(44, 34, 27)


func _init(text_value: String = "") -> void:
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED # el texto ya va traducido
	text = text_value
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(0, 32)
	add_theme_font_size_override("font_size", 14)
	set_active(false)


func set_active(value: bool) -> void:
	var edge: Color = UiStyle.AMBER if value else UiStyle.SLOT_EDGE
	var bg: Color = BG_ACTIVE if value else BG
	for state: String in ["normal", "pressed", "focus"]:
		add_theme_stylebox_override(state, UiStyle.chamfered(bg, edge, 1, 6, 0.0))
	add_theme_stylebox_override("hover", UiStyle.chamfered(BG_ACTIVE, UiStyle.TITLE if not value else UiStyle.AMBER, 1, 6, 0.0))
	for state: String in ["font_color", "font_pressed_color", "font_focus_color"]:
		add_theme_color_override(state, UiStyle.AMBER if value else UiStyle.SUBTLE)
	add_theme_color_override("font_hover_color", UiStyle.AMBER if value else UiStyle.TEXT)
	# Margen del texto (los estilos no lo traen).
	for state: String in ["normal", "pressed", "focus", "hover"]:
		var style := get_theme_stylebox(state) as StyleBoxFlat
		if style != null:
			style.content_margin_left = 12.0
			style.content_margin_right = 12.0
