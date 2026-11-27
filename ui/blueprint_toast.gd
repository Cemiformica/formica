class_name BlueprintToast
extends CanvasLayer
## Aviso «Plano aprendido» (sesión 30, D-186): al reparar algo que enseña a construir, baja una tarjeta arriba en el
## centro con una tablilla de plano (la misma hoja azul del plano en la mano, D-226) con el icono de la construcción
## encima, el nombre de lo aprendido y dónde encontrarlo (o que llegará más adelante, si aún no se puede construir). Escucha `WorldState.blueprint_learned`; si llegan varios a la vez, salen de uno en uno.
## Uso: `add_child(BlueprintToast.new())` una vez (lo monta `GameHud`).

const SHOW_TIME: float = 3.5
const IN_TIME: float = 0.35
const OUT_TIME: float = 0.5
## Cuánto baja al aparecer (px).
const DROP: float = 28.0
const TOP: float = 84.0
const BLUEPRINT_SIZE: Vector2 = Vector2(56, 64)
## Iconos de las construcciones (`render_building_icons.py`; también los de lo que aún no existe, como la escalera de mano).
const ICON_DIR: String = "res://assets/textures/icons/buildings/"

var _queue: Array[StringName] = []
var _showing: bool = false
var _holder: CenterContainer   # ancho de pantalla: centra la tarjeta sola
var _card: PanelContainer
var _name_label: Label
var _where_label: Label
var _sheet: BlueprintSheet


func _ready() -> void:
	layer = 5
	_build()
	WorldState.blueprint_learned.connect(_on_learned)


func _exit_tree() -> void:
	if WorldState.blueprint_learned.is_connected(_on_learned):
		WorldState.blueprint_learned.disconnect(_on_learned)


func _on_learned(building_id: StringName) -> void:
	_queue.append(building_id)
	if not _showing:
		_show_next()


func _show_next() -> void:
	if _queue.is_empty():
		_showing = false
		return
	_showing = true
	var building_id: StringName = _queue.pop_front()
	var data: BuildingData = Content.find_building(building_id)
	_name_label.text = _building_name(building_id, data)
	# Lo que aún no existe como construcción (la escalera de mano espera a las paredes) se podrá construir más adelante.
	_where_label.text = tr("BLUEPRINT_WHERE" if data != null else "BLUEPRINT_LATER")
	_sheet.icon = _icon(building_id, data)
	_sheet.queue_redraw()
	_holder.offset_top = TOP - DROP
	_holder.offset_bottom = TOP - DROP
	_holder.modulate.a = 0.0
	_holder.show()
	var tween := _holder.create_tween()
	tween.set_parallel(true)
	tween.tween_property(_holder, "modulate:a", 1.0, IN_TIME)
	tween.tween_property(_holder, "offset_top", TOP, IN_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_holder, "offset_bottom", TOP, IN_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.chain().tween_interval(SHOW_TIME)
	tween.chain().tween_property(_holder, "modulate:a", 0.0, OUT_TIME)
	tween.chain().tween_callback(_holder.hide)
	tween.chain().tween_callback(_show_next)


## Nombre traducido de la construcción. Si aún no existe en el contenido, la clave `BUILDING_<ID>`.
func _building_name(building_id: StringName, data: BuildingData) -> String:
	if data != null and data.name_key != "":
		return tr(data.name_key)
	return tr("BUILDING_%s" % String(building_id).to_upper())


## Icono de la construcción, o el de su archivo si aún no existe en el contenido. Null = la tablilla sola.
func _icon(building_id: StringName, data: BuildingData) -> Texture2D:
	if data != null and data.icon != null:
		return data.icon
	var path: String = ICON_DIR + String(building_id) + ".png"
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


func _build() -> void:
	_holder = CenterContainer.new()
	_holder.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_holder.grow_vertical = Control.GROW_DIRECTION_END
	_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_holder.hide()
	add_child(_holder)
	_card = PanelContainer.new()
	var style: StyleBoxFlat = UiStyle.chamfered(Color(UiStyle.BACKGROUND, 0.92), UiStyle.AMBER, 2, 10, 10.0)
	style.content_margin_left = 12.0
	style.content_margin_right = 18.0
	_card.add_theme_stylebox_override("panel", style)
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_holder.add_child(_card)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(row)
	_sheet = BlueprintSheet.new()
	_sheet.custom_minimum_size = BLUEPRINT_SIZE
	row.add_child(_sheet)
	var texts := VBoxContainer.new()
	texts.alignment = BoxContainer.ALIGNMENT_CENTER
	texts.add_theme_constant_override("separation", 0)
	texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(texts)
	texts.add_child(_label(tr("BLUEPRINT_LEARNED"), 13, UiStyle.AMBER))
	_name_label = _label("", 22, UiStyle.TEXT)
	texts.add_child(_name_label)
	_where_label = _label("", 12, UiStyle.SUBTLE)
	texts.add_child(_where_label)


func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("outline_size", 4)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


## Tablilla de plano dibujada: marco de madera, hoja azul con cuadrícula y, encima, el icono de la construcción.
class BlueprintSheet:
	extends Control

	const WOOD: Color = Color8(150, 98, 58)
	const PAPER: Color = Color8(38, 74, 128)
	const GRID: Color = Color8(70, 110, 165)

	var icon: Texture2D = null

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), WOOD)
		var paper := Rect2(Vector2(4, 4), size - Vector2(8, 8))
		draw_rect(paper, PAPER)
		var step: float = 6.0
		var x: float = paper.position.x + step
		while x < paper.end.x:
			draw_line(Vector2(x, paper.position.y), Vector2(x, paper.end.y), GRID, 1.0)
			x += step
		var y: float = paper.position.y + step
		while y < paper.end.y:
			draw_line(Vector2(paper.position.x, y), Vector2(paper.end.x, y), GRID, 1.0)
			y += step
		if icon != null:
			var side: float = minf(paper.size.x, paper.size.y) + 4.0   # cuadrado, sin deformar el icono
			draw_texture_rect(icon, Rect2(paper.get_center() - Vector2(side, side) * 0.5, Vector2(side, side)), false)
