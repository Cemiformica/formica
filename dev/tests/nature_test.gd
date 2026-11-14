extends Node
## Prueba de árboles y talador (B2.7a), solo en datos (solo desarrollo).
## Ejecuta con F6 y mira la pestaña Salida: cada comprobación imprime OK o FALLO.
##
## Plano: talador en (0,0) mirando al norte (giro 0) → tala la arboleda de 3×3 en x −1..1, y −3..−1.
## Placa solar 2×2 en (4,0) unida al talador con un cable. Árbol suelto para talar a mano en (8,8).

var _failures: int = 0


func _ready() -> void:
	var cutter_data: BuildingData = Content.find_building(&"tree_cutter")
	var solar_data: BuildingData = Content.find_building(&"solar_panel")
	var crusher: BuildingData = Content.find_building(&"crusher")
	var wood: ItemData = Content.find_item(&"wood")
	var seed_item: ItemData = Content.find_item(&"seed")
	_check("contenido: talador 3×3 y semilla", cutter_data != null and cutter_data.harvest_area == Vector2i(3, 3) and seed_item != null)

	Simulation.running = false
	WorldState.reset()
	var island: IslandState = WorldState.get_island(&"test_nature")

	# 1) Talar a mano: 4 de madera + 1 semilla, queda un tocón; arrancarlo da 1 y libera la casilla.
	island.add_tree(Vector2i(8, 8))
	_check("no se construye sobre un árbol", not island.can_place(crusher, Vector2i(8, 8)))
	var gained: Dictionary[ItemData, int] = island.chop_tree(Vector2i(8, 8), true)
	_check("a mano: 4 de madera y 1 semilla", gained.get(wood, 0) == 4 and gained.get(seed_item, 0) == 1)
	_check("queda un tocón que bloquea", island.nature[Vector2i(8, 8)].is_stump() and not island.can_place(crusher, Vector2i(8, 8)))
	var root: Dictionary[ItemData, int] = island.uproot_stump(Vector2i(8, 8))
	_check("arrancar: 1 de madera y casilla libre", root.get(wood, 0) == 1 and island.can_place(crusher, Vector2i(8, 8)))

	# 2) Rebrote: el tocón pasa a brote a los 30 s y a maduro a los 90 s.
	island.add_tree(Vector2i(10, 10), NatureState.Stage.STUMP)
	Simulation.advance(30.0)
	_check("30 s: brote", island.nature[Vector2i(10, 10)].stage == NatureState.Stage.SPROUT)
	Simulation.advance(60.0)
	_check("90 s: maduro", island.nature[Vector2i(10, 10)].is_mature_tree())

	# 3) El área del talador depende de su giro.
	var cutter: PlacedBuilding = island.place(cutter_data, Vector2i(0, 0))
	var cells: Array[Vector2i] = cutter.get_harvest_cells()
	_check("área sin girar: delante (norte)", cells.size() == 9 and cells.has(Vector2i(-1, -3)) and cells.has(Vector2i(1, -1)) and not cells.has(Vector2i(0, 1)))
	var turned := PlacedBuilding.new(99, cutter_data, Vector2i(20, 0), 1)
	var turned_cells: Array[Vector2i] = turned.get_harvest_cells()
	_check("área girada 90°: al este", turned_cells.has(Vector2i(23, -1)) and turned_cells.has(Vector2i(21, 1)) and not turned_cells.has(Vector2i(20, -2)))

	# 4) Arboleda de 9 árboles maduros delante del talador.
	for x: int in range(-1, 2):
		for y: int in range(-3, 0):
			island.add_tree(Vector2i(x, y))
	Simulation.advance(4.0)
	_check("sin energía: no tala", cutter.output.get_total(wood) == 0)

	var solar: PlacedBuilding = island.place(solar_data, Vector2i(4, 0))
	island.add_cable(solar.id, cutter.id)
	Simulation.advance(2.0)
	_check("con energía: tala uno en 2 s (4 de madera)", cutter.output.get_total(wood) == 4)
	Simulation.advance(16.0)
	_check("en 18 s, los 9 (36 de madera, sin semillas)", cutter.output.get_total(wood) == 36 and cutter.output.get_total(seed_item) == 0)
	var stumps: int = 0
	for cell: Vector2i in cells:
		if island.nature[cell].is_stump():
			stumps += 1
	_check("deja 9 tocones (no replanta: rebrotan solos)", stumps == 9)
	Simulation.advance(10.0)
	_check("sin maduros: espera", cutter.output.get_total(wood) == 36)

	# 5) Guardar y cargar la naturaleza: fase y tiempo.
	var restored := IslandState.new()
	restored.load_data(JSON.parse_string(JSON.stringify(island.to_data())))
	var original: NatureState = island.nature[Vector2i(0, -2)]
	var copy: NatureState = restored.nature.get(Vector2i(0, -2), null)
	_check("cargada: fase y tiempo del árbol", copy != null and copy.stage == original.stage and is_equal_approx(copy.timer, original.timer))

	WorldState.reset()
	Simulation.running = true
	if _failures == 0:
		print("--- Naturaleza y talador: TODO OK ---")
	else:
		print("--- Naturaleza y talador: %d FALLOS ---" % _failures)


func _check(label: String, condition: bool) -> void:
	if condition:
		print("OK    ", label)
	else:
		_failures += 1
		push_error("FALLO " + label)
