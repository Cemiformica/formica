extends Node
## Prueba de rocas (B2.8), solo en datos (solo desarrollo).
## Ejecuta con F6 y mira la pestaña Salida: cada comprobación imprime OK o FALLO.
## El generador aleatorio lleva semilla fija, así que la prueba da siempre lo mismo.

var _failures: int = 0


func _ready() -> void:
	var stone: ItemData = Content.find_item(&"stone")
	var crusher: BuildingData = Content.find_building(&"crusher")
	Simulation.running = false
	WorldState.reset()

	# 1) Picar una roca: 2 de piedra y casilla libre; mientras está, bloquea construir.
	var island: IslandState = WorldState.get_island(&"test_rocks")
	island.add_rock(Vector2i(0, 0))
	_check("la roca bloquea construir", not island.can_place(crusher, Vector2i(0, 0)))
	var gained: Dictionary[ItemData, int] = island.mine_rock(Vector2i(0, 0))
	_check("picar: 2 de piedra y casilla libre", gained.get(stone, 0) == 2 and island.can_place(crusher, Vector2i(0, 0)))

	# 2) Sin límites no aparecen rocas.
	Simulation.advance(100.0)
	_check("sin límites: no aparecen", island.rock_count() == 0)

	# 3) Con límites de 5×5: una cada 45 s, como mucho 12, siempre dentro.
	island.bounds = Rect2i(0, 0, 5, 5)
	island.rng.seed = 12345
	Simulation.advance(44.0)
	_check("antes de 45 s: ninguna", island.rock_count() == 0)
	Simulation.advance(1.0)
	_check("a los 45 s: una", island.rock_count() == 1)
	Simulation.advance(45.0 * 20)
	_check("como mucho 12", island.rock_count() == 12)
	var inside: bool = true
	for cell: Vector2i in island.nature:
		if not island.bounds.has_point(cell):
			inside = false
	_check("todas dentro de los límites", inside)

	# 4) Solo en casillas libres: en un 3×3 con una construcción y un árbol, caben 7 rocas.
	var small: IslandState = WorldState.get_island(&"test_rocks_small")
	small.bounds = Rect2i(0, 0, 3, 3)
	small.rng.seed = 7
	small.place(crusher, Vector2i(1, 1))
	small.add_tree(Vector2i(0, 0))
	Simulation.advance(45.0 * 10)
	_check("solo casillas libres: 7 rocas", small.rock_count() == 7)
	_check("ni sobre la construcción ni sobre el árbol", small.nature[Vector2i(0, 0)].kind == NatureState.Kind.TREE and not small.nature.has(Vector2i(1, 1)))

	# 5) Guardar y cargar: rocas y temporizador.
	Simulation.advance(20.0)
	var restored := IslandState.new()
	restored.load_data(JSON.parse_string(JSON.stringify(small.to_data())))
	_check("cargada: rocas", restored.rock_count() == 7)
	_check("cargada: temporizador", is_equal_approx(restored.to_data()["rock_timer"], small.to_data()["rock_timer"]))

	WorldState.reset()
	Simulation.running = true
	if _failures == 0:
		print("--- Rocas: TODO OK ---")
	else:
		print("--- Rocas: %d FALLOS ---" % _failures)


func _check(label: String, condition: bool) -> void:
	if condition:
		print("OK    ", label)
	else:
		_failures += 1
		push_error("FALLO " + label)
