class_name RepairPieceData
extends Resource
## Una pieza de una estructura por reparar (C4, D-115): un trozo que falta (una viga, una losa…) y lo
## que hay que entregar para ponerlo. Va dentro de un `RepairSiteData`.

## Identificador estable dentro de su estructura.
@export var id: StringName = &""
## Clave de traducción del nombre visible (por ejemplo, "REPAIR_PIECE_PILLAR").
@export var name_key: String = ""
## Nodo del modelo de la estructura que es esta pieza: la vista lo enseña como fantasma hasta completarla.
@export var node_name: StringName = &""
## Lo que pide (ítem → cantidad). Se puede entregar poco a poco.
@export var cost: Dictionary[ItemData, int] = {}
## Qué hace la pieza cuando ya está completa (C4). Vacío = nada. &"bed": la cama del refugio; con E se
## descansa: marca ahí el punto de reaparición y guarda la partida (César). &"toggle": con E se abre o se
## cierra, girando `toggle_nodes` (la trampilla del refugio y su palanca, C5.5, César). &"climb": con la estructura
## entera completa, con E se agarra uno a ella y sube por `RepairSiteData.climb_path` (la escala de cuerda, C5.6b).
@export var action: StringName = &""
## Nodo del modelo donde se apunta para entregarle cosas y accionarla. Vacío = el de la propia pieza. Sirve para
## piezas que quedan fuera de alcance, como la trampilla del cráter, que se acciona desde un tirador abajo.
@export var aim_node: StringName = &""
## Tamaño de la zona a la que se apunta (m), centrada en `aim_node`. Cero = la caja de sus mallas (o un cubito si es
## un vacío). Sirve para piezas que se mueven, como la palanca de la trampilla: la zona cubre todo su recorrido.
@export var aim_size: Vector3 = Vector3.ZERO
## Con `action` &"toggle": los nodos que giran al abrirla (dentro de la pieza) y cuánto gira cada uno, en grados
## (en el mismo orden).
@export var toggle_nodes: Array[StringName] = []
@export var toggle_rotations: Array[Vector3] = []
