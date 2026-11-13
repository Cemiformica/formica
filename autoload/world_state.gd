extends Node
## Autoload `WorldState`: el ESTADO de la partida en datos (D-046). Todo lo que se guarda vive aquí;
## los nodos de las escenas solo lo muestran. Nunca contiene contenido (eso es `Content`).
## Empieza pequeño: inventario y posición del jugador, y un hueco por isla que se llenará en B2
## (construcciones, máquinas, cuadrícula de ocupación).

## Se emite después de cargar una partida o empezar una nueva: quien muestre el estado debe releerlo.
signal state_replaced

## Inventario del jugador. Al cargar se rellena el MISMO objeto, así que las referencias siguen valiendo.
var player_inventory: Inventory = Inventory.new(12)
## Isla (o zona) donde está el jugador. Vacío = todavía ninguna.
var current_island: StringName = &""
## Posición y giro horizontal del jugador dentro de esa isla.
var player_position: Vector3 = Vector3.ZERO
var player_rotation_y: float = 0.0
## Estado de cada isla: id de isla → datos (por ahora, un diccionario libre que se guarda tal cual).
var islands: Dictionary[StringName, Dictionary] = {}


## Partida nueva: todo vacío.
func reset() -> void:
	player_inventory.load_data([])
	current_island = &""
	player_position = Vector3.ZERO
	player_rotation_y = 0.0
	islands.clear()
	state_replaced.emit()


## Estado → datos simples para el guardado (JSON).
func to_data() -> Dictionary:
	var islands_data: Dictionary = {}
	for id: StringName in islands:
		islands_data[String(id)] = islands[id]
	return {
		"island": String(current_island),
		"player": {
			"pos": [player_position.x, player_position.y, player_position.z],
			"rot_y": player_rotation_y,
			"inventory": player_inventory.to_data(),
		},
		"islands": islands_data,
	}


## Datos del guardado → estado. Tolerante: lo que falte o no se entienda queda con su valor por defecto.
func load_data(data: Dictionary) -> void:
	current_island = StringName(str(data.get("island", "")))
	var player: Dictionary = data.get("player", {}) if data.get("player") is Dictionary else {}
	var pos: Variant = player.get("pos", [])
	if pos is Array and pos.size() == 3:
		player_position = Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
	else:
		player_position = Vector3.ZERO
	player_rotation_y = float(player.get("rot_y", 0.0))
	var inventory_data: Variant = player.get("inventory", [])
	player_inventory.load_data(inventory_data if inventory_data is Array else [])
	islands.clear()
	var islands_data: Variant = data.get("islands", {})
	if islands_data is Dictionary:
		for id: Variant in islands_data:
			if islands_data[id] is Dictionary:
				islands[StringName(str(id))] = islands_data[id]
	state_replaced.emit()
