class_name UiCellProgress
extends Control
## Barra de progreso por celdas hexagonales (C2, detalle del estilo Panal): se encienden en ámbar según
## `value` (0–1).

const CELLS: int = 10

var value: float = 0.0:
	set(v):
		var clamped: float = clampf(v, 0.0, 1.0)
		if not is_equal_approx(clamped, value):
			value = clamped
			queue_redraw()


func _init() -> void:
	custom_minimum_size = Vector2(300, 30)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var step: float = size.x / CELLS
	var lit: int = roundi(value * CELLS)
	for k: int in CELLS:
		var center := Vector2(step * (k + 0.5), size.y * 0.5)
		var points: PackedVector2Array = UiStyle.hexagon(center, minf(step * 0.44, size.y * 0.5))
		var on: bool = k < lit
		draw_colored_polygon(points, UiStyle.AMBER if on else Color8(36, 27, 20))
		points.append(points[0])
		draw_polyline(points, UiStyle.BORDER_DARK if on else Color8(66, 50, 40), 1.0, true)
