extends Node
## Autoload `Simulation`: hace avanzar el mundo a pasos fijos (D-046). Recorre TODAS las islas de
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
		for placed: PlacedBuilding in island.buildings.values():
			if placed.is_machine():
				_step_machine(placed)
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
