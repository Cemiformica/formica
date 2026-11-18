class_name UiModuleHoneycomb
extends Control
## Panal de los módulos de la mochila (C2), como la mochila del modelo de Mira (D-103): el emblema en el centro
## y 6 celdas alrededor, encendidas según los módulos que se tienen. Debajo, «MÓDULOS 1/6».

const MAX_MODULES: int = 6
const CELL: float = 15.0

var modules: int = 1:
	set(value):
		modules = value
		queue_redraw()


func _init() -> void:
	custom_minimum_size = Vector2(110, 130)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var center := Vector2(size.x * 0.5, 50.0)
	for k: int in MAX_MODULES:
		var a: float = deg_to_rad(60.0 * k - 90.0)
		var pos: Vector2 = center + Vector2(cos(a), sin(a)) * CELL * 1.77
		var lit: bool = k < modules
		var points: PackedVector2Array = UiStyle.hexagon(pos, CELL - 1.0)
		draw_colored_polygon(points, UiStyle.AMBER if lit else Color8(36, 27, 20))
		points.append(points[0])
		draw_polyline(points, UiStyle.BORDER_DARK if lit else Color8(80, 60, 46), 1.0, true)
	UiStyle.draw_emblem(self, center, CELL - 1.0)
	var font: Font = get_theme_default_font()
	draw_string(font, Vector2(0, 112), tr("INVENTORY_MODULES") % [modules, MAX_MODULES], HORIZONTAL_ALIGNMENT_CENTER,
			size.x, 11, UiStyle.SUBTLE)
