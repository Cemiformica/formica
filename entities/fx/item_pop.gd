class_name ItemPop
extends Sprite3D
## Icono del ítem recogido que salta de donde sale y vuela hacia abajo de la pantalla, hacia la barra (C3,
## César: que se note lo que consigues). Siempre mira a la cámara y se ve por encima de todo. Va sobre una
## placa hexagonal oscura con borde ámbar, como las casillas de la interfaz, para que no se confunda con el
## polvo ni las virutas (César: el mineral verde se perdía en el polvo verde de la barrena). Primero sube y
## rebota (POP_TIME) y después vuela hacia la parte de abajo de la vista mientras encoge (FLY_TIME).
## Uso: `ItemPop.spawn(padre, ítem, posición_global)`. Si el ítem no tiene icono, no hace nada.

const POP_TIME: float = 0.3
const FLY_TIME: float = 0.4
const POP_HEIGHT: float = 0.35
const SIZE: float = 0.34              # metros que mide el icono
const PLATE_SIZE: float = 0.48        # y la placa de detrás
const PLATE_PIXELS: int = 64

## Placa hexagonal compartida por todos (se dibuja una vez).
static var _plate_texture: ImageTexture = null
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
	var plate := Sprite3D.new()
	plate.texture = _plate()
	plate.pixel_size = PLATE_SIZE / float(PLATE_PIXELS)
	plate.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	plate.no_depth_test = true
	plate.shaded = false
	plate.render_priority = 9   # detrás del icono
	plate.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pop.add_child(plate)
	parent.add_child(pop)
	pop.global_position = at
	pop._start = at


## Hexágono oscuro medio transparente con borde ámbar (los colores de la interfaz, UiStyle).
static func _plate() -> ImageTexture:
	if _plate_texture != null:
		return _plate_texture
	var image := Image.create(PLATE_PIXELS, PLATE_PIXELS, false, Image.FORMAT_RGBA8)
	var center := Vector2(PLATE_PIXELS, PLATE_PIXELS) * 0.5
	var radius: float = PLATE_PIXELS * 0.48
	for y: int in PLATE_PIXELS:
		for x: int in PLATE_PIXELS:
			var p := Vector2(x + 0.5, y + 0.5) - center
			# Distancia «hexagonal» (punta arriba): 1 en el borde.
			var q := Vector2(absf(p.x), absf(p.y))
			var d: float = maxf(q.x * 0.866 + q.y * 0.5, q.y) / radius
			if d > 1.0:
				image.set_pixel(x, y, Color(0, 0, 0, 0))
			elif d > 0.86:
				image.set_pixel(x, y, Color(UiStyle.AMBER, 0.95))
			else:
				image.set_pixel(x, y, Color(UiStyle.BACKGROUND, 0.8))
	_plate_texture = ImageTexture.create_from_image(image)
	return _plate_texture


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
	for child: Node in get_children():   # la placa se apaga con el icono
		(child as Sprite3D).modulate.a = modulate.a
	if t >= 1.0:
		queue_free()
