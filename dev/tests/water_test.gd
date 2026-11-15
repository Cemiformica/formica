extends Node
## Prueba del agua (B3.7, D-094), solo en datos (solo desarrollo).
## Ejecuta con F6 y mira la pestaña Salida: cada comprobación imprime OK o FALLO.

var _failures: int = 0


func _ready() -> void:
	var conveyor: BuildingData = Content.find_building(&"conveyor")
	Simulation.running = false
	WorldState.reset()
	var island: IslandState = WorldState.get_island(&"test_water")
	island.add_tree(Vector2i(0, 2))

	# 1) Canal de 5 casillas en x = 0 (y 0..4) que corre al sur; la del árbol se salta.
	var cells: Array[Vector2i] = []
	for y: int in 5:
		cells.append(Vector2i(0, y))
	_check("añade 4 (la del árbol se salta)", island.add_water(cells, Vector2i(0, 1)) == 4)
	_check("agua y dirección", island.is_water(Vector2i(0, 0)) and island.water[Vector2i(0, 4)] == Vector2i(0, 1)
			and not island.is_water(Vector2i(0, 2)))

	# 2) Bloquea construir, plantar y las rocas.
	_check("no se construye encima", island.placement_problem(conveyor, Vector2i(0, 0)) == "BUILD_NO_ROOM")
	_check("sí al lado", island.placement_problem(conveyor, Vector2i(1, 0)) == "")
	_check("no se planta ni salen rocas", not island.add_tree(Vector2i(0, 1)) and not island.add_rock(Vector2i(0, 3)))

	# 3) Rueda hidráulica (2×3): columna oeste sobre agua que corre a lo largo de ella; la otra, tierra.
	var wheel: BuildingData = Content.find_building(&"water_wheel")
	_check("rueda en el catálogo (genera 6)", wheel != null and wheel.power == 6.0 and wheel.size == Vector2i(2, 3))
	var river: Array[Vector2i] = []
	for y: int in range(10, 15):
		river.append(Vector2i(10, y))
	island.add_water(river, Vector2i(0, 1))
	_check("rueda: bien colocada", island.placement_problem(wheel, Vector2i(10, 11)) == "")
	_check("rueda: sobre tierra no", island.placement_problem(wheel, Vector2i(20, 11)) == "BUILD_NEEDS_WATER")
	_check("rueda: con la dinamo en el agua no", island.placement_problem(wheel, Vector2i(9, 11)) == "BUILD_NEEDS_WATER")
	_check("rueda: girada 90° (corriente de lado) no", island.placement_problem(wheel, Vector2i(10, 11), 1) == "BUILD_NEEDS_WATER")
	_check("rueda: girada 180° sí (la corriente sigue a lo largo)", island.placement_problem(wheel, Vector2i(9, 11), 2) == "")
	var lake: Array[Vector2i] = []
	for y: int in range(20, 23):
		lake.append(Vector2i(10, y))
	island.add_water(lake, Vector2i.ZERO)
	_check("rueda: en agua quieta no", island.placement_problem(wheel, Vector2i(10, 20)) == "BUILD_NEEDS_WATER")

	# 4) Guardar y cargar: el agua vuelve con su dirección.
	var restored := IslandState.new()
	restored.load_data(JSON.parse_string(JSON.stringify(island.to_data())))
	_check("cargada: el agua con su dirección", restored.water.size() == island.water.size() and restored.water[Vector2i(0, 3)] == Vector2i(0, 1))

	WorldState.reset()
	Simulation.running = true
	if _failures == 0:
		print("--- Agua: TODO OK ---")
	else:
		print("--- Agua: %d FALLOS ---" % _failures)


func _check(label: String, condition: bool) -> void:
	if condition:
		print("OK    ", label)
	else:
		_failures += 1
		push_error("FALLO " + label)
