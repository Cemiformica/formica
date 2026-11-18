class_name ItemPop
extends Sprite3D
## Icono del ítem recogido que salta de donde sale y vuela hacia abajo de la pantalla, hacia la barra (C3,
## César: que se note lo que consigues). Siempre mira a la cámara y se ve por encima de todo. Primero sube y
## rebota (POP_TIME) y después vuela hacia la parte de abajo de la vista mientras encoge (FLY_TIME).
## Uso: `ItemPop.spawn(padre, ítem, posición_global)`. Si el ítem no tiene icono, no hace nada.

const POP_TIME: float = 0.3
const FLY_TIME: float = 0.4
const POP_HEIGHT: float = 0.35
const SIZE: float = 0.28              # metros que mide el icono
## Adonde vuela, en el marco de la cámara (abajo, hacia la barra).
const TARGET_IN_VIEW: Vector3 = Vector3(0.0, -0.45, -0.9)

var _start: Vector3
var _time: float = 0.0


static func spawn(parent: Node, item: ItemData, at: Vector3) -> void:
	if item == null or item.icon == null or parent == null:
		return
	var pop := ItemPop.new()
	pop.texture = item.icon
	pop.pixel_size = SIZE / maxf(1.0, float(item.icon.get_width()))
	pop.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	pop.no_depth_test = true
	pop.shaded = false
	pop.render_priority = 10
	pop.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pop.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	parent.add_child(pop)
	pop.global_position = at
	pop._start = at


func _process(delta: float) -> void:
	_time += delta
	if _time < POP_TIME:
		var rise: float = _time / POP_TIME
		global_position = _start + Vector3.UP * POP_HEIGHT * sin(rise * PI * 0.5)
		scale = Vector3.ONE * (0.4 + 0.8 * sin(rise * PI * 0.5) - 0.2 * sin(rise * PI))
		return
	var camera: Camera3D = get_viewport().get_camera_3d()
	var t: float = minf(1.0, (_time - POP_TIME) / FLY_TIME)
	var from: Vector3 = _start + Vector3.UP * POP_HEIGHT
	var to: Vector3 = camera.global_transform * TARGET_IN_VIEW if camera != null else from
	global_position = from.lerp(to, t * t)
	scale = Vector3.ONE * lerpf(1.0, 0.35, t)
	modulate.a = 1.0 - t * t
	if t >= 1.0:
		queue_free()
