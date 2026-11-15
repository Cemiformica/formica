class_name BuildingData
extends Resource
## Definición de un tipo de construcción (contenido). Las construcciones colocadas son estado aparte.

## Identificador estable y único (se usará en el guardado).
@export var id: StringName = &""
## Clave de traducción del nombre visible.
@export var name_key: String = ""
## Escena que se instancia al construir. Su origen debe estar en el centro de la base.
@export var scene: PackedScene
## Tamaño en casillas de la cuadrícula (X, Z).
@export var size: Vector2i = Vector2i.ONE
## Altura en metros enteros (colisión y enganche del cable por defecto; guía de arte §7: 1, 2 o 3).
## 0 = altura provisional de la pieza sin modelo (caja de 1 m, poste de 2 m, losa de 0,5 m).
@export_range(0, 3) var height: int = 0
## Coste: qué ítems y cuántos de cada uno.
@export var cost: Dictionary[ItemData, int] = {}
## Receta fija si es una máquina (vacío = no es máquina: caja, cinta, generador…).
@export var recipe: RecipeData
## Solo cintas: velocidad en casillas por segundo. 0 = no es una cinta.
@export var belt_speed: float = 0.0
## Solo cintas: ítems que caben a la vez en una casilla.
@export_range(1, 8) var belt_capacity: int = 2
## Solo taladores: tamaño del área que tala, justo DELANTE de la construcción (ancho × fondo,
## sin girar). (0, 0) = no tala. El talador del vertical slice usa 3×3 (D-057, D-069).
@export var harvest_area: Vector2i = Vector2i.ZERO
## Solo taladores: segundos que tarda en talar un árbol maduro.
@export var harvest_time: float = 2.0
## Solo extractores (B3.7, D-090): segundos que tarda en sacar 1 ítem de la veta. 0 = no es extractor.
@export var extract_time: float = 0.0
## Solo extractores: casilla LOCAL (sin girar; 0,0 = noroeste) de la cabeza, que debe ir sobre una
## casilla del BORDE de una veta. El resto de la huella (la cola) queda fuera de la veta.
@export var vein_cell: Vector2i = Vector2i.ZERO
## Solo extractores: cuántos ítems caben en su almacén (se para al llenarse). 0 = lo que quepa en la
## salida (una pila entera). El extractor del vertical slice guarda 10 (César: «no demasiado alto»).
@export_range(0, 999) var output_capacity: int = 0
## Energía en puntos: positivo = genera, negativo = consume, 0 = no eléctrica (D-068).
## Lo que consume cuenta entero mientras esté conectado, trabaje o no.
@export var power: float = 0.0
## Cables de energía que admite: máquinas y generadores, 1; poste, 4. 0 = no se conecta.
@export_range(0, 8) var power_connections: int = 0
## Puertos de entrada y salida (cintas). Se definen sin girar; giran y se reflejan con la construcción.
@export var ports: Array[PortData] = []


## ¿Cambia algo al reflejarla (tecla F)? Solo si algún puerto queda distinto: otra casilla, otro lado
## u otro filtro (p. ej., las dos salidas del horno). Si reflejar no cambia nada, F no hace nada.
func can_flip() -> bool:
	if extract_time > 0.0:
		return false # reflejar cambiaría la cabeza de lado: el giro con R basta
	var normal: Array[String] = []
	var mirrored: Array[String] = []
	for port: PortData in ports:
		normal.append(_port_key(port, false))
		mirrored.append(_port_key(port, true))
	normal.sort()
	mirrored.sort()
	return normal != mirrored


## Descripción de un puerto colocado en el origen sin girar, para comparar.
func _port_key(port: PortData, flipped: bool) -> String:
	var filter_id: String = ""
	if port.item_filter != null:
		filter_id = String(port.item_filter.id)
	return "%s|%d|%d|%s" % [port.get_grid_cell(Vector2i.ZERO, size, 0, flipped), port.get_grid_side(0, flipped), port.kind, filter_id]
