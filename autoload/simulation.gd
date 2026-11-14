extends Node
## Autoload `Simulation`: hace avanzar el mundo a pasos fijos (D-046): energía, árboles, máquinas,
## taladores, cintas y conexiones. Recorre TODAS las islas de
## `WorldState`, estén o no cargadas en pantalla, así que una fábrica lejana sigue produciendo.
## Los nodos no hacen trabajar a las máquinas: solo muestran lo que hay en los datos.
## Se pausa con el árbol (`get_tree().paused`), como el resto del juego.

## Duración de un paso, en segundos de juego (10 pasos por segundo).
const TICK: float = 0.1
## Tope de pasos por fotograma: si el juego se atasca, la simulación no intenta recuperar todo de golpe.
const MAX_STEPS_PER_FRAME: int = 10
## Margen para comparar tiempos (0,1 × 30 no da exactamente 3,0 con decimales).
const EPSILON: float = 0.0001

## Si es false, la simulación no avanza sola (las pruebas usan `advance()` a mano).
var running: bool = true
## Pasos dados desde que arrancó el juego (para depurar y medir).
var tick_count: int = 0

var _accumulator: float = 0.0


func _process(delta: float) -> void:
	if not running:
		return
	_accumulator += delta
	var steps: int = 0
	while _accumulator >= TICK and steps < MAX_STEPS_PER_FRAME:
		_step()
		_accumulator -= TICK
		steps += 1
	if steps == MAX_STEPS_PER_FRAME:
		_accumulator = 0.0 # se descarta el retraso en vez de acumularlo


## Avanza `seconds` de golpe, sin esperar (pruebas, y más adelante el tiempo pasado fuera de una isla).
func advance(seconds: float) -> void:
	for _i: int in roundi(seconds / TICK):
		_step()


## Un paso de simulación para todo el mundo.
func _step() -> void:
	for island: IslandState in WorldState.islands.values():
		# 0) Energía: si una red con generadores pide más de lo que da, salta su fusible (D-068).
		for network: PowerNetwork in island.get_networks():
			if network.supply > 0.0 and network.is_overloaded() and not network.is_tripped():
				network.trip()
		# 1) Los árboles crecen y los tocones rebrotan (B2.7).
		island.step_nature(TICK)
		# 2) Máquinas y taladores trabajan (los eléctricos, solo con energía) y las cintas mueven sus ítems.
		for placed: PlacedBuilding in island.buildings.values():
			var has_power: bool = placed.data.power >= 0.0 or island.is_powered(placed.id)
			if placed.is_machine():
				if has_power:
					_step_machine(placed)
			elif placed.is_harvester():
				if has_power:
					_step_harvester(island, placed)
			elif placed.is_belt():
				placed.advance_belt(TICK)
		# 3) Por cada conexión, pasa como mucho un ítem por paso.
		for link: Dictionary in island.get_links():
			_transfer(link)
	tick_count += 1


## Una máquina avanza si tiene los ingredientes y si TODO lo que va a producir cabe en la salida.
## Si no, espera sin perder el progreso. Al completar el ciclo consume y produce a la vez.
func _step_machine(placed: PlacedBuilding) -> void:
	var recipe: RecipeData = placed.data.recipe
	if not placed.input.has_items(recipe.inputs) or not placed.output.can_add_all(recipe.outputs):
		return
	placed.progress += TICK
	if placed.progress + EPSILON >= recipe.duration:
		for item: ItemData in recipe.inputs:
			placed.input.remove_item(item, recipe.inputs[item])
		for item: ItemData in recipe.outputs:
			placed.output.add_item(item, recipe.outputs[item])
		placed.progress = 0.0


## Talador (B2.7, D-069): si en su área hay un árbol maduro y cabe la madera, avanza; al completar
## `harvest_time` tala el primero que encuentra (sin semilla) y deja la madera en su salida.
## El tocón rebrota solo, así que no hace falta replantar.
func _step_harvester(island: IslandState, placed: PlacedBuilding) -> void:
	var target: Vector2i = Vector2i.ZERO
	var found: bool = false
	for cell: Vector2i in placed.get_harvest_cells():
		if island.nature.has(cell) and island.nature[cell].is_mature_tree():
			target = cell
			found = true
			break
	var wood: Dictionary[ItemData, int] = {Content.find_item(&"wood"): IslandState.TREE_WOOD}
	if not found or not placed.output.can_add_all(wood):
		return
	placed.progress += TICK
	if placed.progress + EPSILON >= placed.data.harvest_time:
		var gained: Dictionary[ItemData, int] = island.chop_tree(target, false)
		for item: ItemData in gained:
			placed.output.add_item(item, gained[item])
		placed.progress = 0.0


## Pasa un ítem de una salida a la entrada conectada, si hay algo listo y el destino lo acepta.
func _transfer(link: Dictionary) -> void:
	var from: PlacedBuilding = link["from"]
	var to: PlacedBuilding = link["to"]
	var item: ItemData = from.peek_output(link["out"])
	if item != null and to.can_accept(item, link["in"]):
		from.take_output(item)
		to.accept(item)
