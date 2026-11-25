class_name ItemPop
extends Control
## Icono del ítem recogido que salta y vuela a su casilla de la barra (C3, César: que se note lo que consigues).
## Desde la sesión 25 vive en la interfaz y no en el mundo (César: si dejabas de mirarlo, se quedaba en el suelo
## desvaneciéndose). Sale del punto de la pantalla donde se ha conseguido (o de debajo de la mira, si ese punto
## no se ve), da un saltito y vuela hasta la casilla de la barra donde ha caído el ítem, que rebota al llegar.
## Si el ítem no está en la barra (ha ido a la mochila), vuela al centro de la barra.
## Va sobre una placa hexagonal oscura con borde ámbar, como las casillas, para que no se confunda con el polvo
## ni las virutas (César: el mineral verde se perdía en el polvo verde de la barrena).
## Uso: `ItemPop.spawn(cualquier_nodo, ítem, posición_global)`. Si el ítem no tiene icono, no hace nada.

const POP_TIME: float = 0.28
const FLY_TIME: float = 0.42
## Lo que sube (px) en el saltito.
const POP_RISE: float = 36.0
## Tamaño (px) del icono y de la placa de detrás.
const ICON_SIZE: float = 44.0
const PLATE_SIZE: float = 62.0
const PLATE_PIXELS: int = 64
## Tamaño al llegar a la casilla, respecto al del salto.
const END_SCALE: float = 0.7
## Si el punto donde se consigue no se ve, sale de aquí: un poco por debajo de la mira (px).
const FALLBACK_BELOW_CENTER: float = 70.0
## Margen (px) con los bordes de la pantalla para el punto de salida.
const SCREEN_MARGIN: float = 40.0
## Capa de la interfaz: por encima de la barra (4) y de los avisos.
const LAYER: int = 5

## Placa hexagonal compartida por todos (se dibuja una vez).
static var _plate_texture: ImageTexture = null
## Capa compartida donde se dibujan todos (se crea la primera vez, en la escena actual).
static var _layer: CanvasLayer = null

var _item: ItemData = null
var _start: Vector2
var _time: float = 0.0


static func spawn(from_node: Node, item: ItemData, at: Vector3) -> void:
	if item == null or item.icon == null or from_node == null or not from_node.is_inside_tree():
		return
	var viewport: Viewport = from_node.get_viewport()
	var layer: CanvasLayer = _get_layer(from_node)
	if layer == null:
		return
	var pop := ItemPop.new()
	pop._item = item
	pop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pop.size = Vector2(PLATE_SIZE, PLATE_SIZE)
	pop.pivot_offset = pop.size * 0.5
	var plate := TextureRect.new()
	plate.texture = _plate()
	plate.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	plate.size = Vector2(PLATE_SIZE, PLATE_SIZE)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pop.add_child(plate)
	var icon := TextureRect.new()
	icon.texture = item.icon
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size = Vector2(ICON_SIZE, ICON_SIZE)
	icon.position = Vector2(PLATE_SIZE - ICON_SIZE, PLATE_SIZE - ICON_SIZE) * 0.5
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pop.add_child(icon)
	pop._start = _screen_start(viewport, at)
	pop.position = pop._start - pop.size * 0.5
	pop.scale = Vector2.ONE * 0.4
	layer.add_child(pop)


## Punto de salida en la pantalla: donde se ve `at`; si queda detrás de la cámara o fuera de la pantalla,
## debajo de la mira (como si saliera de las manos de Mira).
static func _screen_start(viewport: Viewport, at: Vector3) -> Vector2:
	var rect: Rect2 = viewport.get_visible_rect()
	var fallback: Vector2 = rect.size * 0.5 + Vector2(0.0, FALLBACK_BELOW_CENTER)
	var camera: Camera3D = viewport.get_camera_3d()
	if camera == null or camera.is_position_behind(at):
		return fallback
	var point: Vector2 = camera.unproject_position(at)
	if not rect.grow(-SCREEN_MARGIN).has_point(point):
		return fallback
	return point


static func _get_layer(from_node: Node) -> CanvasLayer:
	if _layer != null and is_instance_valid(_layer) and _layer.is_inside_tree():
		return _layer
	var tree: SceneTree = from_node.get_tree()
	var host: Node = tree.current_scene if tree.current_scene != null else tree.root
	_layer = CanvasLayer.new()
	_layer.layer = LAYER
	_layer.name = "ItemPops"
	host.add_child(_layer)
	return _layer


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
		# Saltito: sube y crece con un pequeño rebote.
		var rise: float = _time / POP_TIME
		var lift: float = sin(rise * PI * 0.5)
		position = _start + Vector2(0.0, -POP_RISE * lift) - size * 0.5
		scale = Vector2.ONE * (0.4 + 0.8 * lift - 0.2 * sin(rise * PI))
		return
	# Vuelo a la casilla: se busca en cada fotograma, por si la barra cambia mientras vuela.
	var t: float = minf(1.0, (_time - POP_TIME) / FLY_TIME)
	var eased: float = t * t * (3.0 - 2.0 * t)
	var from: Vector2 = _start + Vector2(0.0, -POP_RISE)
	var to: Vector2 = HotbarUI.item_target(_item)
	if to.x < 0.0:
		to = from   # sin barra en pantalla: se apaga donde está
	# Un poco de arco hacia arriba, para que no vaya en línea recta.
	var arc: float = -60.0 * sin(t * PI)
	position = from.lerp(to, eased) + Vector2(0.0, arc) - size * 0.5
	scale = Vector2.ONE * lerpf(1.0, END_SCALE, eased)
	modulate.a = 1.0 - smoothstep(0.75, 1.0, t)
	if t >= 1.0:
		HotbarUI.pulse_item(_item)
		queue_free()
