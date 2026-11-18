class_name PickupFeed
extends CanvasLayer
## Avisos de lo que se acaba de recoger (C3, César: si no miras la barra, no te enteras). Arriba a la
## izquierda (César): una línea por ítem con su icono y «+1 Mineral de cobre». Si llega más del mismo ítem mientras su
## línea sigue a la vista, la suma («+3») y la vuelve a resaltar. Cada línea se va apagando a los SHOW_TIME
## segundos; como mucho MAX_LINES.
## Uso: `add_child(PickupFeed.new())` una vez (el sandbox); desde cualquier sitio, `PickupFeed.notify(ítem, n)`.

const SHOW_TIME: float = 2.5
const FADE_TIME: float = 0.5
const MAX_LINES: int = 5
const ICON_SIZE: Vector2 = Vector2(30, 30)

static var _instance: PickupFeed = null

var _column: VBoxContainer
var _lines: Dictionary = {}   # ítem → {"box", "label", "amount", "time"}


## Avisa de que la jugadora ha recogido `amount` de `item` (no hace nada si no hay avisos en pantalla).
static func notify(item: ItemData, amount: int) -> void:
	if _instance != null and is_instance_valid(_instance) and item != null and amount > 0:
		_instance._add(item, amount)


func _ready() -> void:
	layer = 4
	_instance = self
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_TOP_LEFT)
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 24)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)
	_column = VBoxContainer.new()
	_column.alignment = BoxContainer.ALIGNMENT_BEGIN
	_column.add_theme_constant_override("separation", 4)
	_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(_column)


func _exit_tree() -> void:
	if _instance == self:
		_instance = null


func _add(item: ItemData, amount: int) -> void:
	if _lines.has(item):
		var line: Dictionary = _lines[item]
		line["amount"] += amount
		line["time"] = 0.0
		(line["label"] as Label).text = _text(item, line["amount"])
		(line["box"] as Control).modulate.a = 1.0
		_pop(line["box"] as Control)
		return
	var box := PanelContainer.new()
	var style: StyleBoxFlat = UiStyle.chamfered(Color(UiStyle.BACKGROUND, 0.85), UiStyle.BORDER_DARK, 1, 6, 4.0)
	style.content_margin_left = 6.0
	style.content_margin_right = 10.0
	box.add_theme_stylebox_override("panel", style)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	var icon := TextureRect.new()
	icon.texture = item.icon
	icon.custom_minimum_size = ICON_SIZE
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(icon)
	var label := Label.new()
	label.text = _text(item, amount)
	label.add_theme_color_override("font_color", UiStyle.TEXT)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("outline_size", 4)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	_column.add_child(box)
	_lines[item] = {"box": box, "label": label, "amount": amount, "time": 0.0}
	_pop(box)
	while _lines.size() > MAX_LINES:
		_remove(_lines.keys()[0])


func _process(delta: float) -> void:
	for item: ItemData in _lines.keys():
		var line: Dictionary = _lines[item]
		line["time"] += delta
		var box: Control = line["box"]
		if line["time"] > SHOW_TIME:
			box.modulate.a = 1.0 - (line["time"] - SHOW_TIME) / FADE_TIME
			if line["time"] >= SHOW_TIME + FADE_TIME:
				_remove(item)


func _remove(item: ItemData) -> void:
	var line: Dictionary = _lines[item]
	(line["box"] as Control).queue_free()
	_lines.erase(item)


## Rebote corto al aparecer o al sumar, para que se note.
func _pop(box: Control) -> void:
	box.pivot_offset = box.size * 0.5
	var tween := box.create_tween()
	box.scale = Vector2.ONE * 1.15
	tween.tween_property(box, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _text(item: ItemData, amount: int) -> String:
	return "+%d  %s" % [amount, tr(item.name_key)]
