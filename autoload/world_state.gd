extends Node
## Autoload `WorldState`: el ESTADO de la partida en datos (D-046). Todo lo que se guarda vive aquí;
## los nodos de las escenas solo lo muestran. Nunca contiene contenido (eso es `Content`).
## Contiene el inventario y la posición del jugador y el estado de cada isla (`IslandState`:
## cuadrícula y construcciones), esté o no cargada en pantalla. `Simulation` lo hace avanzar.

## Se emite después de cargar una partida o empezar una nueva: quien muestre el estado debe releerlo.
signal state_replaced
## Se emite al aprender un plano nuevo reparando algo (sesión 30): el aviso «Plano aprendido» escucha aquí. No se
## emite al cargar una partida.
signal blueprint_learned(building_id: StringName)

## Casillas de la barra (las 10 primeras del inventario del jugador) y de cada módulo de la mochila, que va
## después (C1, César): se empieza con 1 módulo; cada mejora añade otro. Módulos de 8 desde la sesión 25 (César:
## con 10, los 6 módulos daban 60 casillas, demasiadas; ahora 48 más la barra).
const HOTBAR_SLOTS: int = 10
const BACKPACK_MODULE_SLOTS: int = 8
const START_BACKPACK_MODULES: int = 1

## Inventario del jugador: casillas 0–9, la barra; desde la 10, la mochila. Al cargar se rellena el MISMO
## objeto, así que las referencias siguen valiendo.
var player_inventory: Inventory = Inventory.new(HOTBAR_SLOTS + START_BACKPACK_MODULES * BACKPACK_MODULE_SLOTS)
## Isla (o zona) donde está el jugador. Vacío = todavía ninguna.
var current_island: StringName = &""
## Posición y giro horizontal del jugador dentro de esa isla.
var player_position: Vector3 = Vector3.ZERO
var player_rotation_y: float = 0.0
## Punto de reaparición (C4, la cama del refugio): isla, posición y giro. Sin isla = no hay; el jugador
## vuelve entonces al sitio donde empezó la escena.
var respawn_island: StringName = &""
var respawn_position: Vector3 = Vector3.ZERO
var respawn_rotation_y: float = 0.0
## Barras de construcción elegidas por el jugador (C2.3): una lista de ids por barra ("" = casilla vacía).
## Vacía del todo = las barras de serie del jugador. Y cuál se está usando.
var build_bars_ids: Array = []
var build_bar_index: int = 0
## Estado de cada isla: id de isla → `IslandState`. Usa `get_island()` para no tener que comprobar si existe.
var islands: Dictionary[StringName, IslandState] = {}
## Planos aprendidos al reparar (sesión 30, D-186): ids de `BuildingData`. Son de la partida y no de un jugador,
## para no atar el código a un jugador único (D-252): lo que aprende uno lo sabe todo el grupo.
var blueprints: Array[StringName] = []


## Estado de la isla `id`. Si aún no existe, la crea vacía.
func get_island(id: StringName) -> IslandState:
	if not islands.has(id):
		var island := IslandState.new()
		_watch_island(island, id)
		islands[id] = island
	return islands[id]


# --- Planos (sesión 30, D-186) ---

## Aprende el plano `building_id`. Devuelve false si ya se sabía. Con `quiet`, sin aviso (al cargar).
func learn_blueprint(building_id: StringName, quiet: bool = false) -> bool:
	if building_id == &"" or blueprints.has(building_id):
		return false
	blueprints.append(building_id)
	if not quiet:
		blueprint_learned.emit(building_id)
	return true


## ¿Se sabe ya el plano `building_id`?
func knows_blueprint(building_id: StringName) -> bool:
	return blueprints.has(building_id)


## ¿Está bloqueada en el catálogo? Por la progresión (`locked`, D-115) o porque aún no se ha aprendido su plano.
func is_building_locked(data: BuildingData) -> bool:
	return data != null and (data.locked or (data.needs_blueprint and not knows_blueprint(data.id)))


## Escucha las reparaciones de una isla para aprender sus planos. Se ata el id y no la isla: atar la isla haría
## que se sujetara a sí misma por su propia señal y no se liberaría nunca.
func _watch_island(island: IslandState, island_id: StringName) -> void:
	island.repair_completed.connect(_on_repair_completed.bind(island_id))


func _on_repair_completed(origin: Vector2i, island_id: StringName) -> void:
	if not islands.has(island_id):
		return
	var site: RepairSite = islands[island_id].repair_sites.get(origin)
	if site == null:
		return
	for building_id: StringName in site.data.unlocks:
		learn_blueprint(building_id)


## Aprende sin aviso los planos de lo que ya está reparado. Sirve para las partidas guardadas antes de que existieran
## los planos y por si una estructura gana planos nuevos con una actualización. Lo que no tiene piezas (el embarcadero
## decorativo) no cuenta como reparado.
func _learn_from_repaired_sites() -> void:
	for island: IslandState in islands.values():
		for site: RepairSite in island.repair_sites.values():
			if not site.data.pieces.is_empty() and site.is_complete():
				for building_id: StringName in site.data.unlocks:
					learn_blueprint(building_id, true)


## Partida nueva: todo vacío.
func reset() -> void:
	player_inventory.load_data([])
	current_island = &""
	player_position = Vector3.ZERO
	player_rotation_y = 0.0
	respawn_island = &""
	respawn_position = Vector3.ZERO
	respawn_rotation_y = 0.0
	build_bars_ids.clear()
	build_bar_index = 0
	islands.clear()
	blueprints.clear()
	state_replaced.emit()


## Estado → datos simples para el guardado (JSON).
func to_data() -> Dictionary:
	var islands_data: Dictionary = {}
	for id: StringName in islands:
		islands_data[String(id)] = islands[id].to_data()
	return {
		"island": String(current_island),
		"player": {
			"pos": [player_position.x, player_position.y, player_position.z],
			"rot_y": player_rotation_y,
			"inventory": player_inventory.to_data(),
			"build_bars": build_bars_ids,
			"build_bar_index": build_bar_index,
			"respawn": {"island": String(respawn_island), "pos": [respawn_position.x, respawn_position.y, respawn_position.z],
					"rot_y": respawn_rotation_y},
		},
		"islands": islands_data,
		"blueprints": blueprints.map(func(id: StringName) -> String: return String(id)),
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
	build_bars_ids.clear()
	var bars_data: Variant = player.get("build_bars", [])
	if bars_data is Array:
		for bar: Variant in bars_data:
			var ids: Array[String] = []
			if bar is Array:
				for entry: Variant in bar:
					ids.append(str(entry))
			build_bars_ids.append(ids)
	build_bar_index = int(player.get("build_bar_index", 0))
	# Punto de reaparición (C4); las partidas de antes no lo tenían.
	var respawn: Dictionary = player.get("respawn", {}) if player.get("respawn") is Dictionary else {}
	var respawn_pos: Variant = respawn.get("pos", [])
	respawn_island = StringName(str(respawn.get("island", "")))
	if respawn_pos is Array and respawn_pos.size() == 3:
		respawn_position = Vector3(float(respawn_pos[0]), float(respawn_pos[1]), float(respawn_pos[2]))
	else:
		respawn_island = &""
		respawn_position = Vector3.ZERO
	respawn_rotation_y = float(respawn.get("rot_y", 0.0))
	# Los límites de cada isla son parte de cómo es la isla (los pone su escena), no de la partida, y no se
	# guardan (D-070): se conservan al cargar. Sin ellos no habría suelo ni aparecerían rocas (B5.2).
	var old_bounds: Dictionary[StringName, Rect2i] = {}
	var old_layouts: Dictionary[StringName, IslandLayout] = {}   # el plano tampoco se guarda (C5.3)
	for id: StringName in islands:
		old_bounds[id] = islands[id].bounds
		old_layouts[id] = islands[id].layout
	islands.clear()
	var islands_data: Variant = data.get("islands", {})
	if islands_data is Dictionary:
		for id: Variant in islands_data:
			if islands_data[id] is Dictionary:
				var island := IslandState.new()
				island.bounds = old_bounds.get(StringName(str(id)), Rect2i())
				island.layout = old_layouts.get(StringName(str(id)), null)   # antes de cargar: da las alturas
				island.load_data(islands_data[id])
				_watch_island(island, StringName(str(id)))
				islands[StringName(str(id))] = island
	# Planos (sesión 30); las partidas de antes no los tenían.
	blueprints.clear()
	var blueprints_data: Variant = data.get("blueprints", [])
	if blueprints_data is Array:
		for entry: Variant in blueprints_data:
			learn_blueprint(StringName(str(entry)), true)
	_learn_from_repaired_sites()
	state_replaced.emit()


## Marca el punto de reaparición (C4: al descansar en la cama).
func set_respawn(island: StringName, position: Vector3, rotation_y: float) -> void:
	respawn_island = island
	respawn_position = position
	respawn_rotation_y = rotation_y


## ¿Hay punto de reaparición en esa isla?
func has_respawn(island: StringName) -> bool:
	return respawn_island != &"" and respawn_island == island
