class_name PortData
extends Resource
## Un puerto de una construcción: por dónde entra o sale una cinta (contenido, B2.2).
## Se define en la huella SIN girar ni reflejar; las funciones de abajo calculan dónde queda
## en la cuadrícula para una construcción concreta.
##
## Convenciones (las mismas que `OccupancyGrid`):
## - Norte = −Z del mundo (y − 1 en la cuadrícula), este = +X, sur = +Z, oeste = −X.
## - `rotation` en cuartos de vuelta, sentido horario visto desde arriba: norte → este → sur → oeste.
## - `flipped` refleja la construcción de norte a sur ANTES de girarla (p. ej., intercambia las
##   dos salidas del horno). No cambia la huella, solo dónde quedan los puertos.

enum Kind { INPUT, OUTPUT }
## El orden importa: sumar 1 = girar un cuarto de vuelta en sentido horario.
enum PortSide { NORTH, EAST, SOUTH, WEST }

## Entrada o salida.
@export var kind: Kind = Kind.INPUT
## Casilla de la huella sin girar; (0, 0) = esquina noroeste.
@export var cell: Vector2i = Vector2i.ZERO
## Lado de esa casilla por el que se conecta.
@export var side: PortSide = PortSide.NORTH
## Ítem que admite o saca este puerto. Vacío = cualquiera (las entradas del horno van vacías).
@export var item_filter: ItemData


## Desplazamiento de una casilla hacia ese lado.
static func side_offset(p_side: PortSide) -> Vector2i:
	match p_side:
		PortSide.NORTH: return Vector2i(0, -1)
		PortSide.EAST: return Vector2i(1, 0)
		PortSide.SOUTH: return Vector2i(0, 1)
		_: return Vector2i(-1, 0)


## Lado tras reflejar (si `flipped`) y girar.
static func transform_side(p_side: PortSide, rotation: int, flipped: bool) -> PortSide:
	var s: int = p_side
	if flipped and (s == PortSide.NORTH or s == PortSide.SOUTH):
		s = (s + 2) % 4 # norte ↔ sur; este y oeste no cambian
	return ((s + posmod(rotation, 4)) % 4) as PortSide


## Casilla de la cuadrícula donde está el puerto, para una construcción colocada.
func get_grid_cell(origin: Vector2i, size: Vector2i, rotation: int, flipped: bool) -> Vector2i:
	var local: Vector2i = cell
	if flipped:
		local.y = size.y - 1 - local.y
	return OccupancyGrid.local_to_cell(origin, size, rotation, local)


## Lado de la cuadrícula hacia el que mira el puerto, para una construcción colocada.
func get_grid_side(rotation: int, flipped: bool) -> PortSide:
	return transform_side(side, rotation, flipped)


## Casilla vecina a la que apunta el puerto: ahí se conectará la cinta (B2.5).
func get_target_cell(origin: Vector2i, size: Vector2i, rotation: int, flipped: bool) -> Vector2i:
	return get_grid_cell(origin, size, rotation, flipped) + side_offset(get_grid_side(rotation, flipped))
