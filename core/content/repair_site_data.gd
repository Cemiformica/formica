class_name RepairSiteData
extends Resource
## Tipo de estructura por reparar (C4, D-115): el refugio, el Umbral, el estabilizador… Es contenido: su
## modelo, su huella en la cuadrícula y la lista de piezas que faltan. Su avance vive en `RepairSite`.
## Para añadir una nueva: un .tres con sus piezas y su modelo, y añadirlo a `content/catalog.tres`.

## Identificador estable (se guarda con la isla).
@export var id: StringName = &""
## Clave de traducción del nombre visible (por ejemplo, "REPAIR_SHELTER").
@export var name_key: String = ""
## Modelo de la estructura (origen en el centro de su huella, a ras de suelo), con un nodo por pieza.
@export var scene: PackedScene
## Casillas que ocupa, sin girar. Bloquea construir, plantar y que aparezcan rocas o palos.
@export var size: Vector2i = Vector2i.ONE
## Casillas que ocupa de verdad, en local y sin girar (0,0 = esquina noroeste), como los puertos (C4). Vacío =
## todo el rectángulo. Sirve para que el refugio bloquee sus paredes y su loma y deje libre la sala de
## dentro y la entrada, donde se puede construir el banco o el arcón.
@export var blocked_cells: Array[Vector2i] = []
## Choque con la forma real del modelo (C5.5): sí para lo que se recorre por dentro, como el refugio (sus paredes,
## su galería y su sala); no = una caja que envuelve la base, que basta para una ruina.
@export var exact_collision: bool = false
## Piezas que faltan, en el orden en que se enseñan.
@export var pieces: Array[RepairPieceData] = []
## Para qué sirve al completarse (&"shelter", &"threshold", &"stabilizer"…). Lo usa quien escucha
## `IslandState.repair_completed`; aquí es solo una etiqueta.
@export var purpose: StringName = &""


## Índice de la pieza con ese id, o -1.
func find_piece(piece_id: StringName) -> int:
	for i: int in pieces.size():
		if pieces[i] != null and pieces[i].id == piece_id:
			return i
	return -1
