class_name Aim
extends RefCounted
## Utilidades de apuntado compartidas por construir, desmontar e interactuar.
## El rayo sale de la cámara activa por un punto de la pantalla: el centro, o el cursor con cámara libre.
## Traído del prototipo tal cual (D-054). En B2 solo se usa la primera persona; el modo cursor queda
## listo para cuando vuelva la cámara libre (D-064). `ui_open` se sustituirá por un gestor de ventanas (D-048).


## Hay una ventana de interfaz abierta (inventario, máquina...): el juego no recibe clics ni movimiento.
static var ui_open: bool = false
## Modo cursor (cámara libre): el rayo sale del cursor en vez del centro de la pantalla.
static var cursor_mode: bool = false
## Mientras se gira la cámara libre, el cursor queda fijo en esta posición.
static var cursor_frozen: bool = false
static var frozen_position: Vector2 = Vector2.ZERO


## Punto de la pantalla desde el que se apunta: el centro, o el cursor en modo cursor.
static func aim_screen_point(viewport: Viewport) -> Vector2:
	if cursor_mode:
		return frozen_position if cursor_frozen else viewport.get_mouse_position()
	return viewport.get_visible_rect().size / 2.0


## ¿Se pueden usar los clics para construir o desmontar? (ratón capturado, o cámara libre).
static func pointer_ready() -> bool:
	if ui_open:
		return false
	return cursor_mode or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED


## Lanza un rayo desde el punto de apuntado actual (centro o cursor).
static func from_aim(viewport: Viewport, max_distance: float, exclude: Array[RID] = []) -> Dictionary:
	return from_screen_point(viewport, aim_screen_point(viewport), max_distance, exclude)


## Lanza un rayo desde un punto concreto de la pantalla.
static func from_screen_point(viewport: Viewport, screen_point: Vector2, max_distance: float, exclude: Array[RID] = []) -> Dictionary:
	var camera: Camera3D = viewport.get_camera_3d()
	if camera == null:
		return {}
	var from: Vector3 = camera.project_ray_origin(screen_point)
	var to: Vector3 = from + camera.project_ray_normal(screen_point) * max_distance
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = exclude
	return viewport.get_world_3d().direct_space_state.intersect_ray(query)


## Lanza un rayo desde el centro de la pantalla. Devuelve el resultado de intersect_ray ({} si no toca nada).
static func from_screen_center(viewport: Viewport, max_distance: float, exclude: Array[RID] = []) -> Dictionary:
	var camera: Camera3D = viewport.get_camera_3d()
	if camera == null:
		return {}
	var screen_point: Vector2 = viewport.get_visible_rect().size / 2.0
	var from: Vector3 = camera.project_ray_origin(screen_point)
	var to: Vector3 = from + camera.project_ray_normal(screen_point) * max_distance
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = exclude
	return viewport.get_world_3d().direct_space_state.intersect_ray(query)


## Sube por los padres de `node` hasta encontrar una construcción (grupo "buildings"). Devuelve null si no hay.
static func find_building(node: Node) -> Node3D:
	while node != null:
		if node.is_in_group(&"buildings"):
			return node as Node3D
		node = node.get_parent()
	return null
