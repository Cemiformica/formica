class_name UiStyle
extends RefCounted
## Tema de la interfaz (C2, César: «estilo Taller con detalles del Panal y el emblema»). Colores, cajas de
## estilo y el `Theme` común que se pone en la ventana raíz (`apply_theme`, lo llama `WindowManager`): botones,
## ayudas flotantes, barras de progreso, separadores, listas y campos de texto. Las piezas que el tema no
## dibuja solo van en sus propios controles: `UiWindow` (marco con cabecera), `UiSection`, `UiHex`,
## `UiEmblem` y `UiModuleHoneycomb`. Dónde tocar: las constantes de color de aquí arriba.

const BACKGROUND: Color = Color8(29, 23, 19, 252)
const HEADER: Color = Color8(17, 13, 11)
const BORDER: Color = Color8(184, 103, 63) # naranja de la arcilla (4,2): el acento de las máquinas
const BORDER_DARK: Color = Color8(120, 66, 38)
const INNER_LINE: Color = Color8(58, 43, 34)
const LINE: Color = Color8(70, 54, 44)
const TITLE: Color = Color8(212, 131, 95)
const TEXT: Color = Color8(232, 222, 208)
const SUBTLE: Color = Color8(176, 158, 140)
const AMBER: Color = Color8(255, 184, 58)
const SLOT_BG: Color = Color8(13, 10, 8)
const SLOT_EDGE: Color = Color8(66, 52, 43)
const SLOT_LIGHT: Color = Color8(56, 44, 36)
const GREEN: Color = Color8(115, 217, 102)
const RED: Color = Color(0.95, 0.35, 0.3)
## Esquinas cortadas de las ventanas (px).
const CHAMFER: int = 14

static var _theme: Theme = null


## Caja con esquinas cortadas en diagonal (radio con un solo segmento).
static func chamfered(bg: Color, border: Color, border_width: int, chamfer: int, margin: float = 0.0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(chamfer)
	style.corner_detail = 1
	style.anti_aliasing = true
	style.set_content_margin_all(margin)
	return style


## Fondo de ventana: marrón muy oscuro, borde naranja, esquinas cortadas y sombra.
static func window_style() -> StyleBoxFlat:
	var style: StyleBoxFlat = chamfered(BACKGROUND, BORDER, 2, CHAMFER)
	style.shadow_color = Color(0, 0, 0, 0.45)
	style.shadow_size = 12
	style.shadow_offset = Vector2(3, 5)
	return style


## Pone el fondo de ventana a un `PanelContainer` (lo usan las ventanas que aún no son `UiWindow`).
static func window(panel: PanelContainer) -> void:
	panel.add_theme_stylebox_override("panel", window_style())


## Casilla hundida (la sombra de arriba y la luz de abajo las dibuja `SlotUI`).
static func slot_style(edge: Color = SLOT_EDGE, width: int = 1) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = SLOT_BG
	style.border_color = edge
	style.set_border_width_all(width)
	style.set_corner_radius_all(5)
	return style


## Hexágono de radio `radius` con centro `center` (canto plano arriba si `flat`).
static func hexagon(center: Vector2, radius: float, flat: bool = true) -> PackedVector2Array:
	var points := PackedVector2Array()
	var start: float = 0.0 if flat else 30.0
	for k: int in 6:
		var a: float = deg_to_rad(start + 60.0 * k)
		points.append(center + Vector2(cos(a), sin(a)) * radius)
	return points


## Emblema de la colonia (D-096): hormiga vista desde arriba sobre un hexágono naranja.
static func draw_emblem(canvas: CanvasItem, center: Vector2, radius: float, bg: Color = BORDER,
		ant: Color = Color8(28, 22, 18)) -> void:
	canvas.draw_colored_polygon(hexagon(center, radius), bg)
	var s: float = radius / 20.0
	for part: Vector2 in [Vector2(-8.5, 3.6), Vector2(0.0, 3.2), Vector2(9.5, 5.2)]: # cabeza, tórax, abdomen
		canvas.draw_colored_polygon(hexagon(center + Vector2(0, part.x * s), part.y * s), ant)
	var width: float = maxf(1.0, 1.3 * s)
	for side: float in [-1.0, 1.0]:
		for leg: Vector3 in [Vector3(-1.5, 7.0, -5.0), Vector3(0.0, 8.0, 0.5), Vector3(1.5, 7.0, 6.0)]:
			canvas.draw_line(center + Vector2(0, leg.x * s), center + Vector2(side * leg.y * s, (leg.x + leg.z) * s), ant, width, true)
		canvas.draw_line(center + Vector2(side * 1.2 * s, -11.0 * s), center + Vector2(side * 4.5 * s, -15.5 * s), ant, width, true)


## Pone el tema común en la ventana raíz: todos los controles lo heredan.
static func apply_theme(root: Window) -> void:
	if _theme == null:
		_theme = _make_theme()
	root.theme = _theme


static func _make_theme() -> Theme:
	var theme := Theme.new()
	# Botones (y los desplegables de las opciones)
	for type: String in ["Button", "OptionButton"]:
		theme.set_stylebox("normal", type, chamfered(Color8(40, 31, 25), LINE, 1, 6, 8.0))
		theme.set_stylebox("hover", type, chamfered(Color8(56, 42, 32), BORDER, 1, 6, 8.0))
		theme.set_stylebox("pressed", type, chamfered(Color8(70, 44, 28), AMBER, 1, 6, 8.0))
		theme.set_stylebox("hover_pressed", type, chamfered(Color8(70, 44, 28), AMBER, 1, 6, 8.0))
		theme.set_stylebox("disabled", type, chamfered(Color8(30, 24, 20), Color8(48, 38, 32), 1, 6, 8.0))
		theme.set_stylebox("focus", type, StyleBoxEmpty.new())
		theme.set_color("font_color", type, TEXT)
		theme.set_color("font_hover_color", type, AMBER)
		theme.set_color("font_pressed_color", type, AMBER)
		theme.set_color("font_hover_pressed_color", type, AMBER)
		theme.set_color("font_disabled_color", type, Color8(110, 98, 88))
	# Ayudas flotantes
	theme.set_stylebox("panel", "TooltipPanel", chamfered(Color8(12, 9, 7, 245), BORDER, 1, 6, 8.0))
	theme.set_color("font_color", "TooltipLabel", TITLE)
	# Barras de progreso, separadores, listas, campos y menús
	theme.set_stylebox("background", "ProgressBar", chamfered(SLOT_BG, SLOT_EDGE, 1, 4))
	theme.set_stylebox("fill", "ProgressBar", chamfered(AMBER, AMBER, 0, 4))
	var line := StyleBoxLine.new()
	line.color = LINE
	line.thickness = 1
	theme.set_stylebox("separator", "HSeparator", line)
	var vline := StyleBoxLine.new()
	vline.color = LINE
	vline.thickness = 1
	vline.vertical = true
	theme.set_stylebox("separator", "VSeparator", vline)
	theme.set_stylebox("panel", "ItemList", chamfered(SLOT_BG, SLOT_EDGE, 1, 6, 6.0))
	theme.set_stylebox("selected", "ItemList", chamfered(Color8(70, 44, 28), BORDER, 1, 4))
	theme.set_stylebox("selected_focus", "ItemList", chamfered(Color8(70, 44, 28), AMBER, 1, 4))
	theme.set_stylebox("hovered", "ItemList", chamfered(Color8(40, 31, 25), LINE, 0, 4))
	theme.set_stylebox("focus", "ItemList", StyleBoxEmpty.new())
	theme.set_color("font_color", "ItemList", TEXT)
	theme.set_color("font_selected_color", "ItemList", AMBER)
	theme.set_stylebox("normal", "LineEdit", chamfered(SLOT_BG, SLOT_EDGE, 1, 4, 6.0))
	theme.set_stylebox("focus", "LineEdit", chamfered(SLOT_BG, BORDER, 1, 4, 6.0))
	theme.set_stylebox("panel", "PopupMenu", chamfered(BACKGROUND, BORDER, 1, 6, 6.0))
	theme.set_stylebox("hover", "PopupMenu", chamfered(Color8(70, 44, 28), BORDER, 0, 4))
	theme.set_color("font_color", "Label", TEXT)
	return theme
