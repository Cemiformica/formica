class_name TreeView
extends Interactable
## Árbol, tocón o roca visible (B2.7b, B2.8). El nombre de la clase es de antes de las rocas. Solo MUESTRA su `NatureState` (D-046): la crea, actualiza y borra
## `IslandView` cuando la isla avisa con `nature_changed`. La forma cambia con la fase:
## tocón bajo, brote pequeño, árbol joven y árbol maduro. Formas provisionales hasta B3.
## Se trabaja con el clic izquierdo (`use`, C1.8; César: la E queda para abrir y accionar). En C3 talar pedirá
## el hacha y picar el pico en la mano; de momento se hace a mano.
## Talar exige la mordedora en la mano y arrancar un tocón, la barrena (C3, César; get_required_tool). Las
## rocas se recogen con la E (C3, César: la E recoge e interactúa; el clic, solo para las herramientas). El avance de los golpes sale en el letrero («2/4», get_progress_text).
## Clic sobre un árbol maduro: un golpe; a los `NatureState.CHOP_HITS` golpes (uno por segundo como mucho;
## manteniendo el clic, va golpeando) se tala (4 de madera + 1 semilla, queda un tocón) (D-090). Cada golpe
## levanta polvo y lo agita. Clic sobre un tocón: arrancarlo (1 de madera, libera la casilla). Brotes y
## jóvenes no se tocan. Clic sobre una roca: recogerla de una vez (1 de piedra, libera la casilla).
## Modelos (B3.7, D-097): `nature.glb` trae cada pieza en una malla con su nombre («tree_a_mature_1»,
## «rock_2»…). Se cargan una vez y todas las vistas comparten esas mallas. La especie (roble o pino) la
## guarda el estado del árbol (C1.9); la variante, el giro y el tamaño los elige la casilla, siempre los
## mismos: al rebrotar sale el mismo árbol. Dónde tocar: SCALE_MIN/MAX, PHASE_SCALE (ancho y alto de cada
## fase), las listas de variantes de MODELS y NatureState.PINE_EVERY (cuántos pinos salvajes).

const NATURE_SCENE: PackedScene = preload("res://assets/models/props/nature.glb")
## Modelos de cada especie en `nature.glb` (a = frondoso: el roble; b = pino de hexágonos).
const MODEL_PREFIX: Dictionary[StringName, String] = {NatureState.OAK: "a", NatureState.PINE: "b"}
## Nombre visible por especie y fase.
const NAME_KEYS: Dictionary = {
	NatureState.OAK: {"mature": "PROP_OAK", "young": "PROP_OAK_YOUNG", "sprout": "PROP_OAK_SPROUT", "stump": "PROP_OAK_STUMP"},
	NatureState.PINE: {"mature": "PROP_PINE", "young": "PROP_PINE_YOUNG", "sprout": "PROP_PINE_SPROUT", "stump": "PROP_PINE_STUMP"},
}
const SCALE_MIN: float = 0.9
const SCALE_MAX: float = 1.1
## Tamaño de cada fase sobre el modelo de `nature.glb`: ancho (x) y alto (y). César: árboles adultos más
## altos, pero sin ensancharlos tanto, para que las copas de casillas vecinas no se solapen. El tocón crece
## con el tronco del árbol talado; el brote y las rocas se quedan como están.
const PHASE_SCALE: Dictionary = {
	"a": {"mature": Vector2(1.25, 1.6), "young": Vector2(1.15, 1.3), "sprout": Vector2.ONE, "stump": Vector2(1.5, 1.5)},
	"b": {"mature": Vector2(1.0, 1.75), "young": Vector2(1.0, 1.4), "sprout": Vector2.ONE, "stump": Vector2(1.5, 1.5)},
}
## Choque de cada fase con su tamaño ya aplicado: alto y radio, en metros.
const COLLISION: Dictionary = {
	"mature": Vector2(4.5, 0.3), "young": Vector2(1.8, 0.27), "sprout": Vector2(0.4, 0.25), "stump": Vector2(0.4, 0.32),
}
## Variantes por especie y fase (sufijo _0, _1…). Las rocas no tienen especie.
const MODELS: Dictionary = {
	"a": {"mature": 3, "young": 2, "sprout": 1, "stump": 1},
	"b": {"mature": 2, "young": 1, "sprout": 1, "stump": 1},
}
const ROCK_VARIANTS: int = 3
const STICKS_VARIANTS: int = 3   # palos caídos (C3)
## Golpes de barrena para arrancar un tocón (C3).
const UPROOT_HITS: int = 2
const TOOL_CHOP: StringName = &"biter"         # mordedora
const TOOL_UPROOT: StringName = &"hand_drill"  # barrena
## Cada cuánto salen virutas mientras una herramienta trabaja (ms).
const TOOL_FX_MS: int = 180
## Madera mordida, en bucle mientras la mordedora trabaja (C3).
const SAW_SOUND: AudioStreamWAV = preload("res://assets/audio/wood_saw_loop.wav")

## Mallas de `nature.glb` por nombre, compartidas por todas las vistas.
static var _meshes: Dictionary[String, Mesh] = {}

## Casilla que ocupa.
var cell: Vector2i
## Isla a la que pertenece.
var island: IslandState

var _shape: CylinderShape3D
var _visual: Node3D = null
## Golpes dados al árbol y momento del último (no se guardan: si te vas, se pierden).
var _hits: int = 0
var _last_hit_ms: int = -100000
var _shake: float = 0.0
## Temblor fino mientras una herramienta trabaja el árbol (C3), en lugar de la sacudida del golpe a mano.
var _tremble: float = 0.0
var _fx_ms: int = -100000
var _saw_sound: LoopSound = null


## Radio (m) de la base que tiene que quedar dentro del suelo en una cuesta (tronco y raíces de los árboles).
const BASE_RADIUS: float = 0.45


## Prepara la vista. Se llama ANTES de añadirla al árbol.
func setup(p_cell: Vector2i, p_island: IslandState) -> void:
	cell = p_cell
	island = p_island
	name = "tree_%d_%d" % [cell.x, cell.y]
	position = GridMath.cell_center(cell, island.ground_height(cell))   # a la altura de su suelo (C5.3b)
	if island.layout != null and not island.layout.is_buildable(cell):
		# En cuesta, apoyado en lo más bajo bajo su base: si no, el pie y las raíces asomaban por el lado de abajo.
		position.y = island.layout.lowest_around(position.x, position.z, BASE_RADIUS)
	_shape = CylinderShape3D.new()
	var collision := CollisionShape3D.new()
	collision.shape = _shape
	add_child(collision)


## Vuelve a dibujar según la fase actual (la llama `IslandView` cuando cambia).
func refresh() -> void:
	var state: NatureState = island.nature.get(cell, null)
	if state == null:
		return
	if _visual != null:
		_visual.queue_free()
	_visual = Node3D.new()
	add_child(_visual)
	# Giro y tamaño fijos de esta casilla: el mismo árbol (o roca) cada vez que se dibuja.
	var seed_value: int = NatureState.cell_hash(cell)
	_visual.rotation.y = deg_to_rad(float(seed_value % 360))
	var size: float = lerpf(SCALE_MIN, SCALE_MAX, float((seed_value >> 9) % 101) / 100.0)
	_visual.scale = Vector3.ONE * size
	if state.is_rock():
		display_name_key = "PROP_ROCK"
		_add_model("rock_%d" % ((seed_value >> 4) % ROCK_VARIANTS))
		_shape.radius = 0.3
		_shape.height = 0.4
		(get_child(0) as CollisionShape3D).position.y = 0.2
		return
	if state.is_sticks():
		display_name_key = "PROP_STICKS"
		_add_model("sticks_%d" % ((seed_value >> 4) % STICKS_VARIANTS))
		_shape.radius = 0.35
		_shape.height = 0.15
		(get_child(0) as CollisionShape3D).position.y = 0.075
		return
	var species: String = MODEL_PREFIX.get(state.species, "a")
	var phase: String = "mature"
	match state.stage:
		NatureState.Stage.STUMP:
			phase = "stump"
		NatureState.Stage.SPROUT:
			phase = "sprout"
		NatureState.Stage.YOUNG:
			phase = "young"
	display_name_key = NAME_KEYS.get(state.species, NAME_KEYS[NatureState.OAK])[phase]
	var phase_scale: Vector2 = PHASE_SCALE[species][phase]
	_visual.scale = Vector3(phase_scale.x, phase_scale.y, phase_scale.x) * size
	var variants: int = MODELS[species][phase]
	_add_model("tree_%s_%s_%d" % [species, phase, (seed_value >> 5) % variants])
	var collision: Vector2 = COLLISION[phase]
	_shape.radius = collision.y
	_shape.height = collision.x
	(get_child(0) as CollisionShape3D).position.y = collision.x * 0.5


## Clic: talar si está maduro, arrancar si es un tocón, recoger si es una roca. Lo obtenido va al
## inventario del jugador; si no cabe entero, no se hace nada (para no perder materiales).
func use(_by: Node) -> void:
	var state: NatureState = island.nature.get(cell, null)
	if state == null:
		return
	if state.is_rock() or state.is_sticks():
		return # las rocas y los palos se recogen con la E (interact)
	var inventory: Inventory = WorldState.player_inventory
	var preview: Dictionary[ItemData, int] = {}
	if state.is_mature_tree():
		preview = {Content.find_item(&"wood"): IslandState.TREE_WOOD,
				Content.find_item(NatureState.SEED_ITEMS[state.species]): 1}
	elif state.is_stump():
		preview = {Content.find_item(&"wood"): IslandState.STUMP_WOOD}
	if preview.is_empty() or not inventory.can_add_all(preview):
		return
	if state.is_stump():
		# Con la barrena, unos golpes para soltar las raíces (C3, César).
		var now: int = Time.get_ticks_msec()
		var at: Vector3 = _by.work_point() if _by.has_method("work_point") else global_position + Vector3(0.0, 0.2, 0.0)
		_tremble = 1.0
		if now - _fx_ms >= TOOL_FX_MS:
			_fx_ms = now
			DustPuff.spawn(self, at, BuildingView.CHIPS_COLOR, true)
		if now - _last_hit_ms < int(NatureState.HIT_COOLDOWN * 1000.0):
			return
		_last_hit_ms = now
		_hits += 1
		_shake = 0.5
		if _hits < UPROOT_HITS:
			return
		_hits = 0
	if state.is_mature_tree():
		var now: int = Time.get_ticks_msec()
		var with_tool: bool = _by.has_method("holding_tool") and _by.holding_tool()
		var at: Vector3 = _by.work_point() if _by.has_method("work_point") else global_position + Vector3(0.0, 0.6, 0.0)
		if with_tool:
			# La mordedora va mordiendo: virutas seguidas donde muerde, el árbol tiembla y cruje (C3).
			_tremble = 1.0
			if _saw_sound == null:
				_saw_sound = LoopSound.create(self, SAW_SOUND)
			_saw_sound.global_position = at
			_saw_sound.keep()
			if now - _fx_ms >= TOOL_FX_MS:
				_fx_ms = now
				DustPuff.spawn(self, at, BuildingView.CHIPS_COLOR, true)
		if now - _last_hit_ms < int(NatureState.HIT_COOLDOWN * 1000.0):
			return
		_last_hit_ms = now
		_hits += 1
		if with_tool:
			_shake = 0.5
		else:
			_shake = 1.0
			DustPuff.spawn(self, at)
		if _hits < NatureState.CHOP_HITS:
			return
		_hits = 0
	var gained: Dictionary[ItemData, int] = {}
	if state.is_mature_tree():
		# Antes de que la casilla pase a tocón, una copia del árbol cae hacia el otro lado (C3, César).
		if _visual != null and get_parent() != null:
			FallingTree.spawn(get_parent(), _visual, (_by as Node3D).global_position if _by is Node3D else global_position)
		gained = island.chop_tree(cell, true)
	else:
		gained = island.uproot_stump(cell)
	_give(gained, _by)


## E sobre una roca o unos palos: recogerlos de una vez (si cabe en el inventario).
func interact(by: Node) -> void:
	var state: NatureState = island.nature.get(cell, null)
	if state == null:
		return
	if state.is_rock():
		var stone: Dictionary[ItemData, int] = {Content.find_item(&"stone"): IslandState.ROCK_STONE}
		if WorldState.player_inventory.can_add_all(stone):
			_give(island.mine_rock(cell), by)
	elif state.is_sticks():
		var wood: Dictionary[ItemData, int] = {Content.find_item(&"wood"): IslandState.STICKS_WOOD}
		if WorldState.player_inventory.can_add_all(wood):
			_give(island.pick_sticks(cell), by)


## Mete lo obtenido en el inventario, con el icono que vuela a la barra y el aviso de arriba.
func _give(gained: Dictionary[ItemData, int], by: Node) -> void:
	var inventory: Inventory = WorldState.player_inventory
	var pop_at: Vector3 = global_position + Vector3(0.0, 0.8, 0.0)
	if by.has_method("work_point"):
		pop_at = by.work_point()
	for item: ItemData in gained:
		inventory.add_item(item, gained[item])
		ItemPop.spawn(get_parent(), item, pop_at)   # lo recogido salta hacia la barra (C3)
		PickupFeed.notify(item, gained[item])


## Talar pide la mordedora y arrancar un tocón, la barrena (C3, César). Las rocas, con la E.
func get_required_tool() -> StringName:
	var state: NatureState = island.nature.get(cell, null) if island != null else null
	if state == null:
		return &""
	if state.is_mature_tree():
		return TOOL_CHOP
	if state.is_stump():
		return TOOL_UPROOT
	return &""


## «2/4» mientras se tala o se arranca.
func get_progress_text() -> String:
	var state: NatureState = island.nature.get(cell, null) if island != null else null
	if state == null or _hits <= 0:
		return ""
	if state.is_mature_tree():
		return "%d/%d" % [_hits, NatureState.CHOP_HITS]
	if state.is_stump():
		return "%d/%d" % [_hits, UPROOT_HITS]
	return ""


## Qué hace el clic aquí, para el letrero de arriba. Brotes y jóvenes no se tocan.
func get_use_hint_key() -> String:
	var state: NatureState = island.nature.get(cell, null) if island != null else null
	if state == null:
		return ""
	if state.is_mature_tree():
		return "HINT_CHOP"
	if state.is_stump():
		return "HINT_UPROOT"
	return ""


## Qué hace la E aquí: recoger las rocas (C3).
func get_interact_hint_key() -> String:
	var state: NatureState = island.nature.get(cell, null) if island != null else null
	return "HINT_PICK_UP" if state != null and (state.is_rock() or state.is_sticks()) else ""


## Sacudida corta del árbol tras un golpe.
func _process(delta: float) -> void:
	if (_shake <= 0.0 and _tremble <= 0.0) or _visual == null:
		return
	_shake = maxf(_shake - delta * 5.0, 0.0)
	_tremble = maxf(_tremble - delta * 4.0, 0.0)
	var jitter: float = 0.008 * sin(Time.get_ticks_msec() * 0.09) * _tremble
	_visual.rotation.z = 0.06 * sin(_shake * PI * 3.0) * _shake + jitter


## Pone la malla `model_name` de `nature.glb` (si no existe, avisa y no dibuja nada).
func _add_model(model_name: String) -> void:
	if _meshes.is_empty():
		_load_meshes()
	var mesh: Mesh = _meshes.get(model_name, null)
	if mesh == null:
		push_warning("TreeView: no hay modelo «%s» en nature.glb" % model_name)
		return
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	_visual.add_child(instance)


## Malla de `nature.glb` por su nombre (p. ej., «rock_1»), para quien la use fuera de los árboles (las rocas caídas del
## terreno, C5.4c). Null si no existe.
static func named_mesh(model_name: String) -> Mesh:
	if _meshes.is_empty():
		_load_meshes()
	return _meshes.get(model_name, null)


## Malla del modelo de una especie y fase (p. ej., el brote de roble), para el fantasma de plantar (C1.9).
static func get_model_mesh(species: StringName, phase: String, variant: int = 0) -> Mesh:
	if _meshes.is_empty():
		_load_meshes()
	return _meshes.get("tree_%s_%s_%d" % [MODEL_PREFIX.get(species, "a"), phase, variant], null)


## Saca una vez las mallas de `nature.glb` y las guarda por nombre.
static func _load_meshes() -> void:
	var scene := NATURE_SCENE.instantiate()
	for node: Node in scene.find_children("*", "MeshInstance3D", true, false):
		_meshes[String(node.name)] = (node as MeshInstance3D).mesh
	scene.free()
