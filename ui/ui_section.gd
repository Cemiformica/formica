class_name UiSection
extends HBoxContainer
## Cabecera de una sección de ventana (C2): hexágono naranja, título en mayúsculas pequeñas y una línea fina
## hasta el final. «ENTRADA», «MOCHILA · 1 MÓDULO»…

var _label: Label


func _init(p_text: String = "") -> void:
	add_theme_constant_override("separation", 8)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(UiHex.new(UiStyle.BORDER, 11.0))
	_label = Label.new()
	_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED # el texto ya va traducido
	_label.add_theme_font_size_override("font_size", 13)
	_label.add_theme_color_override("font_color", UiStyle.SUBTLE)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)
	var line := HSeparator.new()
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(line)
	set_text(p_text)


func set_text(value: String) -> void:
	_label.text = value.to_upper()
