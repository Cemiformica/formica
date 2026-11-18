class_name UiHex
extends Control
## Hexágono de la interfaz (C2): viñeta de las secciones, número de cada módulo de la mochila…
## Si lleva `text`, lo escribe en el centro.

@export var color: Color = UiStyle.BORDER
@export var outline: Color = Color(0, 0, 0, 0)
@export var text: String = ""
@export var text_color: Color = Color8(40, 28, 16)
@export var font_size: int = 11


func _init(p_color: Color = UiStyle.BORDER, p_size: float = 12.0, p_text: String = "") -> void:
	color = p_color
	text = p_text
	custom_minimum_size = Vector2(p_size, p_size)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_vertical = Control.SIZE_SHRINK_CENTER


func _draw() -> void:
	var radius: float = minf(size.x, size.y) * 0.5
	var points: PackedVector2Array = UiStyle.hexagon(size * 0.5, radius)
	draw_colored_polygon(points, color)
	if outline.a > 0.0:
		points.append(points[0])
		draw_polyline(points, outline, 1.0, true)
	if text != "":
		var font: Font = get_theme_default_font()
		var ascent: float = font.get_ascent(font_size)
		draw_string(font, Vector2(0, size.y * 0.5 + ascent * 0.38), text, HORIZONTAL_ALIGNMENT_CENTER, size.x, font_size, text_color)
