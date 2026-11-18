class_name UiEmblem
extends Control
## Emblema de la colonia en la interfaz (C2, D-096): cabecera de las ventanas, marca de agua y centro del
## panal de módulos. Se dibuja con vectores, así que sirve a cualquier tamaño.

@export var background: Color = UiStyle.BORDER
@export var ant: Color = Color8(28, 22, 18)


func _init(p_size: float = 34.0) -> void:
	custom_minimum_size = Vector2(p_size, p_size)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_vertical = Control.SIZE_SHRINK_CENTER


func _draw() -> void:
	UiStyle.draw_emblem(self, size * 0.5, minf(size.x, size.y) * 0.5, background, ant)
