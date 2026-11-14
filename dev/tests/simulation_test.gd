extends Node
## Prueba de `Simulation` con dos trituradoras solo en datos (solo desarrollo).
## Ejecuta con F6 y mira la pestaña Salida: cada comprobación imprime OK o FALLO.
## La isla de prueba nunca se carga en pantalla: las máquinas producen igual.
## Tarda 1 segundo en terminar (el bloque 4 espera en tiempo real).

var _failures: int = 0


func _ready() -> void:
	var crusher: BuildingData = Content.find_building(&"crusher")
	var stone: ItemData = Content.find_item(&"stone")
	var gravel: ItemData = Content.find_item(&"gravel")

	Simulation.running = false # aquí mandamos nosotros con advance()
	WorldState.reset()
	var island: IslandState = WorldState.get_island(&"test_island")
	var m1: PlacedBuilding = island.place(crusher, Vector2i(0, 0))
	var m2: PlacedBuilding = island.place(crusher, Vector2i(2, 0))
	m1.input.add_item(stone, 20)
	m2.input.add_item(stone, 5)

	# 1) 30 s a 3 s por ciclo = 10 ciclos. m2 se queda sin piedra a los 5.
	Simulation.advance(30.0)
	_check("m1: 10 de grava", m1.output.get_total(gravel) == 10)
	_check("m1: quedan 10 de piedra", m1.input.get_total(stone) == 10)
	_check("m2: 5 de grava y sin piedra", m2.output.get_total(gravel) == 5 and m2.input.get_total(stone) == 0)
	_check("m2: parada sin progreso", m2.progress == 0.0)

	# 2) Medio ciclo: el progreso se queda a medias y aún no hay grava nueva.
	Simulation.advance(1.5)
	_check("m1: progreso 1,5 s", is_equal_approx(m1.progress, 1.5))
	_check("m1: sigue con 10 de grava", m1.output.get_total(gravel) == 10)

	# 3) Salida llena: la máquina se para y no gasta piedra.
	var m3: PlacedBuilding = island.place(crusher, Vector2i(4, 0))
	m3.output.add_item(gravel, gravel.max_stack)
	m3.input.add_item(stone, 5)
	Simulation.advance(10.0)
	_check("salida llena: no gasta piedra", m3.input.get_total(stone) == 5)
	_check("salida llena: no avanza", m3.progress == 0.0)
	m3.output.remove_item(gravel, 1) # hueco para 1
	Simulation.advance(3.0)
	_check("con hueco: produce 1", m3.output.get_total(gravel) == gravel.max_stack and m3.input.get_total(stone) == 4)

	# 4) En tiempo real: en 1 s da unos 10 pasos sola.
	var before: int = Simulation.tick_count
	Simulation.running = true
	await get_tree().create_timer(1.0).timeout
	var steps: int = Simulation.tick_count - before
	_check("tiempo real: ~10 pasos en 1 s (%d)" % steps, steps >= 8 and steps <= 12)

	WorldState.reset()
	if _failures == 0:
		print("--- Simulation: TODO OK ---")
	else:
		print("--- Simulation: %d FALLOS ---" % _failures)


func _check(label: String, condition: bool) -> void:
	if condition:
		print("OK    ", label)
	else:
		_failures += 1
		push_error("FALLO " + label)
