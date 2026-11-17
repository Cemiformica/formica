class_name TreeView
extends Interactable
## Árbol, tocón o roca visible (B2.7b, B2.8). El nombre de la clase es de antes de las rocas. Solo MUESTRA su `NatureState` (D-046): la crea, actualiza y borra
## `IslandView` cuando la isla avisa con `nature_changed`. La forma cambia con la fase:
## tocón bajo, brote pequeño, árbol joven y árbol maduro. Formas provisionales hasta B3.
## Se trabaja con el clic izquierdo (`use`, C1.8; César: la E queda para abrir y accionar). En C3 talar pedirá
## el hacha y picar el pico en la mano; de momento se hace a mano.
## Clic sobre un árbol maduro: un golpe; a los `NatureState.CHOP_HITS` golpes (uno por segundo como mucho;
## manteniendo el clic, va golpeando) se tala (4 de madera + 1 semilla, queda un tocón) (D-090). Cada golpe
## levanta polvo y lo agita. Clic sobre un tocón: arrancarlo (1 de madera, libera la casilla). Brotes y
## jóvenes no se tocan. Clic sobre una roca: recogerla de una vez (1 de piedra, libera la casilla).
## Modelos (B3.7, D-097): `nature.glb` trae cada pieza en una malla con su nombre («tree_a_mature_1»,
## «rock_2»…). Se cargan una vez y todas las vistas comparten esas mallas. Cada casilla elige siempre la
## misma especie (3 frondosos por cada pino), variante, giro y tamaño: al rebrotar sale el mismo árbol.
## Dónde tocar: PINE_EVERY (cuántos pinos), SCALE_MIN/MAX, PHASE_SCALE (ancho y alto de cada fase)
## y las listas de variantes de MODELS.

const NATURE_SCENE: PackedScene = preload("res://assets/models/props/nature.glb")
## Uno de cada PINE_EVERY árboles es un pino (especie B); el resto, frondosos (A).
const PINE_EVERY: int = 4
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


## Prepara la vista. Se llama ANTES de añadirla al árbol.
func setup(p_cell: Vector2i, p_island: IslandState) -> void:
	cell = p_cell
	island = p_island
	name = "tree_%d_%d" % [cell.x, cell.y]
	position = GridMath.cell_center(cell)
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
	var seed_value: int = _cell_hash()
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
	var species: String = "b" if (seed_value >> 3) % PINE_EVERY == 0 else "a"
	var phase: String = "mature"
	match state.stage:
		NatureState.Stage.STUMP:
			display_name_key = "PROP_STUMP"
			phase = "stump"
		NatureState.Stage.SPROUT:
			display_name_key = "PROP_SPROUT"
			phase = "sprout"
		NatureState.Stage.YOUNG:
			display_name_key = "PROP_YOUNG_TREE"
			phase = "young"
		_:
			display_name_key = "PROP_TREE"
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
	var inventory: Inventory = WorldState.player_inventory
	var preview: Dictionary[ItemData, int] = {}
	if state.is_rock():
		preview = {Content.find_item(&"stone"): IslandState.ROCK_STONE}
	elif state.is_mature_tree():
		preview = {Content.find_item(&"wood"): IslandState.TREE_WOOD, Content.find_item(&"seed"): 1}
	elif state.is_stump():
		preview = {Content.find_item(&"wood"): IslandState.STUMP_WOOD}
	if preview.is_empty() or not inventory.can_add_all(preview):
		return
	if state.is_mature_tree():
		var now: int = Time.get_ticks_msec()
		if now - _last_hit_ms < int(NatureState.HIT_COOLDOWN * 1000.0):
			return
		_last_hit_ms = now
		_hits += 1
		_shake = 1.0
		DustPuff.spawn(self, global_position + Vector3(0.0, 0.6, 0.0))
		if _hits < NatureState.CHOP_HITS:
			return
		_hits = 0
	var gained: Dictionary[ItemData, int] = {}
	if state.is_rock():
		gained = island.mine_rock(cell)
	elif state.is_mature_tree():
		gained = island.chop_tree(cell, true)
	else:
		gained = island.uproot_stump(cell)
	for item: ItemData in gained:
		inventory.add_item(item, gained[item])


## Qué hace el clic aquí, para el letrero de arriba. Brotes y jóvenes no se tocan.
func get_use_hint_key() -> String:
	var state: NatureState = island.nature.get(cell, null) if island != null else null
	if state == null:
		return ""
	if state.is_rock():
		return "HINT_PICK_UP"
	if state.is_mature_tree():
		return "HINT_CHOP"
	if state.is_stump():
		return "HINT_UPROOT"
	return ""


## Sacudida corta del árbol tras un golpe.
func _process(delta: float) -> void:
	if _shake <= 0.0 or _visual == null:
		return
	_shake = maxf(_shake - delta * 5.0, 0.0)
	_visual.rotation.z = 0.06 * sin(_shake * PI * 3.0) * _shake


## Número fijo y bien repartido para esta casilla (no cambia entre partidas ni al recargar).
func _cell_hash() -> int:
	var h: int = (cell.x * 73856093) ^ (cell.y * 19349663)
	h = (h ^ (h >> 13)) * 1274126177
	return (h ^ (h >> 16)) & 0x7fffffff


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


## Saca una vez las mallas de `nature.glb` y las guarda por nombre.
static func _load_meshes() -> void:
	var scene := NATURE_SCENE.instantiate()
	for node: Node in scene.find_children("*", "MeshInstance3D", true, false):
		_meshes[String(node.name)] = (node as MeshInstance3D).mesh
	scene.free()
