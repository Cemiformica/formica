class_name GridMath
extends RefCounted
## Conversión entre casillas de la cuadrícula y posiciones del mundo (1 casilla = 1 m).
## La casilla (x, y) cubre de x a x + 1 en el eje X y de y a y + 1 en el eje Z (ver `OccupancyGrid`).


## Casilla que contiene un punto del mundo.
static func world_to_cell(pos: Vector3) -> Vector2i:
	return Vector2i(floori(pos.x), floori(pos.z))


## Centro de una casilla, a la altura `y`.
static func cell_center(cell: Vector2i, y: float = 0.0) -> Vector3:
	return Vector3(cell.x + 0.5, y, cell.y + 0.5)


## Centro de una huella colocada (ya girada), a la altura `y`.
static func footprint_center(origin: Vector2i, size: Vector2i, rotation: int, y: float = 0.0) -> Vector3:
	var s: Vector2i = OccupancyGrid.rotated_size(size, rotation)
	return Vector3(origin.x + s.x * 0.5, y, origin.y + s.y * 0.5)


## Giro de la cuadrícula (cuartos de vuelta en sentido horario visto desde arriba) → `rotation.y` de Godot,
## que gira en sentido antihorario visto desde arriba. Por eso el signo menos.
static func rotation_to_yaw(rotation: int) -> float:
	return -posmod(rotation, 4) * PI * 0.5


## Gira un desplazamiento de casillas `rotation` cuartos de vuelta en sentido horario visto desde arriba
## (norte → este → sur → oeste). Ejemplo: (0, −1), «una casilla al norte», girado 1 vez = (1, 0), «al este».
static func rotate_offset(offset: Vector2i, rotation: int) -> Vector2i:
	var result: Vector2i = offset
	for _i: int in posmod(rotation, 4):
		result = Vector2i(-result.y, result.x)
	return result
