class_name UiWindow
extends PanelContainer
## Marco de ventana del tema (C2): esquinas cortadas con borde naranja, cabecera oscura con el emblema de la
## colonia, título y subtítulo, botón de cerrar hexagonal, el emblema muy tenue de fondo y dos remaches en las
## esquinas de abajo. Lo de dentro va en `content` (un `VBoxContainer`).
## Uso: `var w := UiWindow.new(tr("TÍTULO"), "2 × 2")`, `w.content.add_child(...)`. El botón de cerrar
## cierra la ventana de `WindowManager`.

const WATERMARK_RADIUS: float = 64.0
const WATERMARK_ALPHA: float = 0.05

## Lo de dentro de la ventana.
var content: VBoxContainer
var _title: Label
var _subtitle: Label


func _init(title: String = "", subtitle: String = "") -> void:
	add_theme_stylebox_override("panel", UiStyle.window_style())
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	add_child(column)
	# Cabecera
	var header := PanelContainer.new()
	var header_style := StyleBoxFlat.new()
	header_style.bg_color = UiStyle.HEADER
	header_style.border_color = UiStyle.BORDER
	header_style.border_width_bottom = 2
	header_style.corner_radius_top_left = UiStyle.CHAMFER - 2
	header_style.corner_radius_top_right = UiStyle.CHAMFER - 2
	header_style.corner_detail = 1
	header_style.anti_aliasing = true
	header_style.content_margin_left = 14
	header_style.content_margin_right = 12
	header_style.content_margin_top = 8
	header_style.content_margin_bottom = 8
	header.add_theme_stylebox_override("panel", header_style)
	column.add_child(header)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	header.add_child(row)
	row.add_child(UiEmblem.new(34.0))
	_title = _make_label(title, 22, UiStyle.TITLE)
	row.add_child(_title)
	_subtitle = _make_label(subtitle, 13, UiStyle.SUBTLE)
	_subtitle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_subtitle)
	row.add_child(_CloseButton.new())
	# Cuerpo
	var body := MarginContainer.new()
	body.add_theme_constant_override("margin_left", 22)
	body.add_theme_constant_override("margin_right", 22)
	body.add_theme_constant_override("margin_top", 16)
	body.add_theme_constant_override("margin_bottom", 20)
	column.add_child(body)
	content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	body.add_child(content)


func set_title(title: String, subtitle: String = "") -> void:
	_title.text = title
	_subtitle.text = subtitle


func _draw() -> void:
	# Emblema tenue de fondo, abajo a la derecha, y remaches en las esquinas cortadas de abajo.
	var mark := Vector2(size.x - WATERMARK_RADIUS - 24.0, size.y - WATERMARK_RADIUS - 24.0)
	UiStyle.draw_emblem(self, mark, WATERMARK_RADIUS, Color(1.0, 0.8, 0.6, WATERMARK_ALPHA), Color(0, 0, 0, WATERMARK_ALPHA * 3.0))
	for corner: Vector2 in [Vector2(9, size.y - 9), Vector2(size.x - 9, size.y - 9)]:
		draw_colored_polygon(UiStyle.hexagon(corner, 3.2, false), UiStyle.BORDER_DARK)


func _make_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED # el texto ya va traducido
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return label


## Botón de cerrar: hexágono con una X; se ilumina al pasar el ratón.
class _CloseButton:
	extends Control

	var _hover: bool = false

	func _init() -> void:
		custom_minimum_size = Vector2(28, 28)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_STOP
		tooltip_text = ""
		mouse_entered.connect(func() -> void:
			_hover = true
			queue_redraw())
		mouse_exited.connect(func() -> void:
			_hover = false
			queue_redraw())

	func _gui_input(event: InputEvent) -> void:
		var click := event as InputEventMouseButton
		if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
			WindowManager.close()
			accept_event()

	func _draw() -> void:
		var center: Vector2 = size * 0.5
		var points: PackedVector2Array = UiStyle.hexagon(center, 13.0)
		draw_colored_polygon(points, Color8(56, 42, 32) if _hover else Color8(40, 31, 25))
		points.append(points[0])
		draw_polyline(points, UiStyle.BORDER if _hover else Color8(96, 72, 56), 1.0, true)
		var color: Color = UiStyle.AMBER if _hover else UiStyle.SUBTLE
		draw_line(center + Vector2(-5, -5), center + Vector2(5, 5), color, 2.0, true)
		draw_line(center + Vector2(5, -5), center + Vector2(-5, 5), color, 2.0, true)
