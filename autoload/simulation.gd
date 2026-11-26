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


## Segundos de juego desde el último paso (0 ≤ x < TICK). Las vistas lo usan para dibujar suave
## lo que entre pasos se movería (p. ej. los ítems de las cintas), sin tocar los datos.
func time_since_step() -> float:
	return _accumulator


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
			elif placed.is_extractor():
				if has_power:
					_step_extractor(placed)
			elif placed.is_belt():
				placed.advance_belt(TICK)
		# 3) Conexiones, recorridas por destino: como mucho un ítem por conexión y paso. Una cinta con
		#    varias entradas (T o X que junta, C2b) toma uno por paso, por turnos entre las que tienen algo.
		#    Solo se recorren los destinos que tienen conexiones (no todas las construcciones).
		for target: PlacedBuilding in island.get_link_targets():
			var incoming: Array = target.links_in
			if target.is_belt() and incoming.size() > 1:
				for k: int in incoming.size():
					var index: int = (target.in_turn + k) % incoming.size()
					if _transfer(incoming[index]):
						target.in_turn = (index + 1) % incoming.size()
						break
			else:
				for link: Dictionary in incoming:
					_transfer(link)
	tick_count += 1


## Una máquina avanza si tiene los ingredientes y si TODO lo que va a producir cabe en la salida.
## Si no, espera sin perder el progreso. Al completar el ciclo consume y produce a la vez.
func _step_machine(placed: PlacedBuilding) -> void:
	var recipe: RecipeData = placed.data.recipe
	if not placed.input.has_items(recipe.inputs) or not placed.output_fits(recipe.outputs):
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
	if not found or not placed.output_fits(_tree_wood()):
		return
	if placed.data.output_capacity > 0:
		for item: ItemData in _tree_wood():
			if placed.output.get_total(item) + _tree_wood()[item] > placed.data.output_capacity:
				return # bandejas llenas (D-092): espera a que la cinta (o E) se lleve la madera
	placed.progress += TICK
	if placed.progress + EPSILON >= placed.data.harvest_time:
		var gained: Dictionary[ItemData, int] = island.chop_tree(target, false)
		for item: ItemData in gained:
			placed.output.add_item(item, gained[item])
		placed.progress = 0.0


## Extractor (B3.7, D-090): si tiene veta debajo y cabe 1 ítem en la salida, avanza; cada
## `extract_time` segundos saca 1 ítem de la veta. Las vetas no se agotan.
func _step_extractor(placed: PlacedBuilding) -> void:
	if placed.vein_item == null or not placed.output_fits(placed.vein_output):
		return
	if placed.data.output_capacity > 0 and placed.output.get_total(placed.vein_item) >= placed.data.output_capacity:
		return # almacén lleno: espera a que la cinta (o E) lo vacíe
	placed.progress += TICK
	if placed.progress + EPSILON >= placed.data.extract_time:
		placed.output.add_item(placed.vein_item, 1)
		placed.progress = 0.0


## Madera que da un árbol talado, preparada una sola vez (B2.9: antes se creaba en cada paso).
var _tree_wood_cache: Dictionary[ItemData, int] = {}


func _tree_wood() -> Dictionary[ItemData, int]:
	if _tree_wood_cache.is_empty():
		_tree_wood_cache[Content.find_item(&"wood")] = IslandState.TREE_WOOD
	return _tree_wood_cache


## Pasa un ítem de una salida a la entrada conectada, si hay algo listo y el destino lo acepta.
## Devuelve si lo pasó. Una cinta con varias salidas (L, T o X que divide, C2b, D-118) reparte por turnos:
## el ítem espera a la salida a la que le toca, salvo que esa no pueda aceptarlo ahora (entonces vale
## cualquier otra, para que una rama llena no pare la cinta).
func _transfer(link: Dictionary) -> bool:
	var from: PlacedBuilding = link["from"]
	var to: PlacedBuilding = link["to"]
	var item: ItemData = from.peek_output(link["out"])
	if item == null or not to.can_accept(item, link["in"]):
		return false
	if from.is_belt():
		var outgoing: Array = from.links_out
		if outgoing.size() > 1:
			var preferred: Dictionary = outgoing[from.out_turn % outgoing.size()]
			if preferred != link and (preferred["to"] as PlacedBuilding).can_accept(item, preferred["in"]):
				return false
			from.out_turn = (outgoing.find(link) + 1) % outgoing.size()
	# Dónde empieza en la cinta de destino: lo que se pasó del final de la anterior o, si esperaba, lo que habría
	# avanzado desde que se abrió el hueco (sesión 28: así la separación es exacta y una cinta llena da 90/min).
	var start: float = 0.0
	if to.is_belt():
		start = from.belt_overflow if from.is_belt() and from.belt_overflow > 0.0 else to.belt_entry_slack()
	from.take_output(item)
	var in_port: PortData = link["in"]
	to.accept(item, start, in_port.side)
	return true
