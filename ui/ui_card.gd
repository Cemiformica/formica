class_name UiCard
extends PanelContainer
## Tarjeta de la interfaz (sesión 25, César: el estilo del banco «A» para todas las ventanas): icono grande, el
## nombre debajo (hasta dos líneas) y, arriba a la derecha, una marca: un texto («×12» en verde, «×0» en rojo) o
## el número de la casilla de la barra en un hexágono. Sale apagada si no se puede hacer o pagar, y con el borde
## ámbar si está elegida o con el ratón encima. La usan el banco (recetas) y el catálogo Q (construcciones).
## Señales: `pressed` al soltar el clic izquierdo sin haber arrastrado; `hovered` al entrar el ratón.

signal pressed
signal hovered

const CHAMFER: int = 8
const BG: Color = Color8(22, 17, 14)
const BG_LIT: Color = Color8(44, 34, 27)
## Icono de lo que no se puede hacer o pagar: apagado.
const DIMMED: Color = Color(1.0, 1.0, 1.0, 0.38)

var _icon: TextureRect
var _name: Label
var _badge: Label
var _slot_hex: UiHex
var _selected: bool = false
var _hover: bool = false
var _dimmed: bool = false
var _font_size: int


func _init(p_size: Vector2 = Vector2(132, 124), p_icon_size: float = 64.0, p_font_size: int = 13) -> void:
	_font_size = p_font_size
	custom_minimum_size = p_size
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(column)
	_icon = SlotUI.make_icon_rect()
	_icon.custom_minimum_size = Vector2(p_icon_size, p_icon_size)
	_icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(_icon)
	_name = Label.new()
	_name.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED # el texto ya va traducido
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_name.max_lines_visible = 2
	_name.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_name.add_theme_font_size_override("font_size", p_font_size)
	_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_name)
	# Encima, sin ocupar sitio: la marca de la esquina.
	var overlay := Control.new()
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)
	_badge = Label.new()
	_badge.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_badge.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_badge.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_badge.position.y = -4.0
	_badge.add_theme_font_size_override("font_size", 12)
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(_badge)
	_slot_hex = UiHex.new(UiStyle.BORDER_DARK, 18.0)
	_slot_hex.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_slot_hex.offset_left = -16.0
	_slot_hex.offset_right = 2.0
	_slot_hex.offset_top = -2.0
	_slot_hex.offset_bottom = 16.0
	_slot_hex.visible = false
	overlay.add_child(_slot_hex)
	mouse_entered.connect(_set_hover.bind(true))
	mouse_exited.connect(_set_hover.bind(false))
	_apply_style()


## Icono y nombre de la tarjeta.
func set_content(icon: Texture2D, title: String) -> void:
	_icon.texture = icon
	_name.text = title


## Texto de la esquina («×12», «—»…); vacío lo quita.
func set_badge(text: String, color: Color = UiStyle.GREEN) -> void:
	_badge.text = text
	_badge.add_theme_color_override("font_color", color)


## Número de la casilla de la barra donde está fijada (1–9, 0 para la décima); -1 lo quita.
func set_slot_number(number: int) -> void:
	_slot_hex.visible = number >= 0
	_slot_hex.text = str(number) if number >= 0 else ""
	_slot_hex.queue_redraw()


## Apagada: no se puede hacer o pagar.
func set_dimmed(value: bool) -> void:
	_dimmed = value
	_apply_style()


## Elegida: borde ámbar aunque no tenga el ratón encima.
func set_selected(value: bool) -> void:
	_selected = value
	_apply_style()


func _set_hover(value: bool) -> void:
	_hover = value
	_apply_style()
	if value:
		hovered.emit()


func _apply_style() -> void:
	var lit: bool = _selected or _hover
	var style: StyleBoxFlat = UiStyle.chamfered(BG_LIT if lit else BG, UiStyle.AMBER if lit else UiStyle.SLOT_EDGE,
			2 if lit else 1, CHAMFER, 6.0)
	add_theme_stylebox_override("panel", style)
	_icon.modulate = DIMMED if _dimmed else Color.WHITE
	_name.add_theme_color_override("font_color", UiStyle.SUBTLE if _dimmed else UiStyle.TEXT)
	_slot_hex.color = UiStyle.AMBER if lit else UiStyle.BORDER_DARK
	_slot_hex.queue_redraw()


## Clic: al soltar el botón sin haber arrastrado (si se arrastra, el soltar le llega a donde se suelta).
func _gui_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null and button.button_index == MOUSE_BUTTON_LEFT and not button.pressed:
		pressed.emit()
		accept_event()
