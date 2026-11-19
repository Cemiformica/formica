extends Node
## Prueba del plano de las islas (C5.3a, D-155), solo en datos (solo desarrollo).
## Ejecuta con F6 y mira la pestaña Salida: cada comprobación imprime OK o FALLO.

const MAP: String = """// Plano de prueba: arriba, la parte alta con su explanada (#), el lago (O) y la cascada (C); abajo, la explanada
// baja (=) con una veta (M), el río (v), la playa (,) y la ladera (/). La última fila es más corta.
~~~~~~~~~~~~
~^^^####^^~~
~^t^####O^~~
~///##==Cv~~
~/,,====.v.~
~,,,=M==,v,~
~~~~~~~~~~~"""

var _failures: int = 0


func _ready() -> void:
	var layout: IslandLayout = IslandLayout.from_text(MAP)

	# 1) Lectura: tamaño, comentarios fuera, filas cortas rellenas con mar.
	_check("tamaño 12 × 7", layout.size == Vector2i(12, 7))
	_check("la fila corta se rellena con mar", layout.char_at(Vector2i(11, 6)) == "~" and layout.ground(Vector2i(11, 6)) == IslandLayout.Ground.SEA)
	_check("fuera del plano es mar", layout.ground(Vector2i(-1, 3)) == IslandLayout.Ground.SEA and layout.char_at(Vector2i(50, 50)) == "~")

	# 2) Suelo y alturas.
	_check("explanada alta: nivel alto y se construye", layout.level(Vector2i(5, 1)) == IslandLayout.HIGH_LEVEL and layout.is_buildable(Vector2i(5, 1)))
	_check("explanada baja: nivel bajo y se construye", layout.level(Vector2i(6, 4)) == IslandLayout.LOW_LEVEL and layout.is_buildable(Vector2i(6, 4)))
	_check("montaña y playa: se andan, no se construye", layout.is_land(Vector2i(1, 1)) and not layout.is_buildable(Vector2i(1, 1))
			and layout.is_land(Vector2i(2, 4)) and not layout.is_buildable(Vector2i(2, 4)))
	_check("ladera: sin altura fija, se anda, no se construye", layout.level(Vector2i(1, 3)) == IslandLayout.NO_LEVEL
			and layout.is_land(Vector2i(1, 3)) and not layout.is_buildable(Vector2i(1, 3)))
	_check("mar y cascada no son tierra", not layout.is_land(Vector2i(0, 0)) and not layout.is_land(Vector2i(8, 3)))

	# 3) Agua: el río corre hacia el sur; el lago, quieto y arriba; el mar no es agua de la cuadrícula.
	_check("río: corre al sur", layout.water_flow(Vector2i(9, 4)) == Vector2i(0, 1))
	_check("lago: quieto y en lo alto", layout.water_flow(Vector2i(8, 2)) == Vector2i.ZERO and layout.level(Vector2i(8, 2)) == IslandLayout.HIGH_LEVEL)
	_check("el mar no es agua de la cuadrícula", layout.water_flow(Vector2i(0, 0)) == null)

	# 3b) Alturas (C5.3d): la ladera sube entre las dos; bajo el agua, su fondo.
	_check("ladera: entre 0 y 6 m (4 m en esta casilla)", is_equal_approx(layout.height(Vector2i(1, 3)), 4.0))
	_check("fondo del río bajo el nivel de abajo", layout.height(Vector2i(9, 4)) < 0.0)
	_check("fondo del lago bajo el nivel de arriba", layout.height(Vector2i(8, 2)) < IslandLayout.LEVEL_HEIGHT
			and layout.height(Vector2i(8, 2)) > 0.0)

	# 4) Objetos: apuntados, y su suelo es el de alrededor.
	_check("la veta está apuntada", layout.cells_of("M").size() == 1 and layout.cells_of("M")[0] == Vector2i(5, 5))
	_check("la veta está en la explanada baja", layout.ground(Vector2i(5, 5)) == IslandLayout.Ground.LOW_FLAT)
	_check("el árbol está en la montaña", layout.ground(Vector2i(2, 2)) == IslandLayout.Ground.HIGH
			and layout.level(Vector2i(2, 2)) == IslandLayout.HIGH_LEVEL)

	# 5) La isla con el plano: dónde se construye.
	Simulation.running = false
	WorldState.reset()
	var island: IslandState = WorldState.get_island(&"test_layout")
	island.apply_layout(layout)
	var crusher: BuildingData = Content.find_building(&"crusher")
	var furnace: BuildingData = Content.find_building(&"furnace")
	_check("los límites son los del plano", island.bounds == Rect2i(0, 0, 12, 7))
	_check("se construye en la explanada", island.placement_problem(crusher, Vector2i(6, 4)) == "")
	_check("en la playa no", island.placement_problem(crusher, Vector2i(2, 4)) == "BUILD_NOT_BUILDABLE")
	_check("en la ladera no", island.placement_problem(crusher, Vector2i(1, 3)) == "BUILD_NOT_BUILDABLE")
	_check("horno entero arriba, sí", island.placement_problem(furnace, Vector2i(4, 1)) == "")
	_check("horno a caballo entre dos alturas, no", island.placement_problem(furnace, Vector2i(5, 2)) == "BUILD_TWO_LEVELS")
	_check("altura del suelo: 0 abajo, 6 arriba", is_equal_approx(island.ground_height(Vector2i(6, 4)), 0.0)
			and is_equal_approx(island.ground_height(Vector2i(5, 1)), IslandLayout.LEVEL_HEIGHT))

	# 5b) A dos alturas (C5.3b): cada construcción guarda la altura de su suelo; las cintas no se unen de una
	# altura a otra; los cables sí, y miden la diferencia de altura.
	var conveyor: BuildingData = Content.find_building(&"conveyor")
	var pole: BuildingData = Content.find_building(&"power_pole")
	var up_belt: PlacedBuilding = island.place(conveyor, Vector2i(5, 3), 1)    # arriba, mirando al este
	var down_belt: PlacedBuilding = island.place(conveyor, Vector2i(6, 3), 1)  # abajo, justo al lado
	_check("cinta de arriba a 6 m y la de abajo a 0", up_belt != null and down_belt != null
			and is_equal_approx(up_belt.ground_y, IslandLayout.LEVEL_HEIGHT) and is_equal_approx(down_belt.ground_y, 0.0))
	_check("las cintas no se unen de una altura a otra", island.get_links_from(up_belt.id).is_empty())
	var next_belt: PlacedBuilding = island.place(conveyor, Vector2i(7, 3), 1)
	_check("en la misma altura sí", next_belt != null and island.get_links_from(down_belt.id).size() == 1)
	var pole_up: PlacedBuilding = island.place(pole, Vector2i(4, 1))
	var pole_down: PlacedBuilding = island.place(pole, Vector2i(6, 4))
	_check("cable de arriba abajo: se puede", pole_up != null and pole_down != null and island.add_cable(pole_up.id, pole_down.id))
	_check("y mide la diferencia de altura", is_equal_approx(island.cable_length(pole_up.id, pole_down.id), sqrt(4.0 + 9.0 + 36.0)))

	# 6) El agua del plano entra en la cuadrícula; el mar y la cascada no son suelo libre.
	_check("el río está en la cuadrícula", island.is_water(Vector2i(9, 5)) and island.water[Vector2i(9, 5)] == Vector2i(0, 1))
	_check("el lago también, quieto", island.is_water(Vector2i(8, 2)) and island.water[Vector2i(8, 2)] == Vector2i.ZERO)
	_check("no se planta en el mar ni en la cascada", not island.can_plant(Vector2i(0, 0)) and not island.can_plant(Vector2i(8, 3)))
	# (La playa de (2, 4) está pegada a la ladera de este plano diminuto, que sube 6 m en tres casillas: es
	# empinada. En llano, sí.)
	_check("en la playa llana sí", island.can_plant(Vector2i(3, 5)))
	_check("junto a la ladera, empinada: no", not island.can_plant(Vector2i(2, 4)))
	_check("ninguna roca en el agua", not island.add_rock(Vector2i(9, 4)) and not island.add_rock(Vector2i(0, 0)))
	_check("la orilla baja justo bajo el agua", is_equal_approx(layout.corner_height(9, 4), -IslandLayout.SHORE_BELOW_WATER))

	# 7) Las rocas y los palos que aparecen solos caen solo en tierra.
	island.rng.seed = 7
	for i: int in 40:
		island.step_nature(IslandState.ROCK_SPAWN_TIME)
	var all_on_land: bool = true
	for cell: Vector2i in island.nature:
		if not layout.can_spawn(cell):
			all_on_land = false
	_check("rocas y palos solo en tierra", island.rock_count() > 0 and all_on_land)

	# 8) Al cargar una partida, el plano se conserva (no se guarda, como los límites).
	var saved: Dictionary = JSON.parse_string(JSON.stringify(WorldState.to_data()))
	WorldState.load_data(saved)
	var reloaded: IslandState = WorldState.get_island(&"test_layout")
	_check("cargada: el plano sigue ahí", reloaded.layout == layout and reloaded.placement_problem(crusher, Vector2i(2, 4)) == "BUILD_NOT_BUILDABLE")
	_check("cargada: las construcciones de arriba siguen arriba", is_equal_approx(reloaded.get_at(Vector2i(5, 3)).ground_y, IslandLayout.LEVEL_HEIGHT))

	# 9) El plano de verdad de Isla Alba.
	var alba: IslandLayout = IslandLayout.load_file("res://content/islands/isla_alba.txt")
	_check("Isla Alba: se lee", alba != null and alba.size == Vector2i(120, 118))
	if alba != null:
		var flat: int = 0
		for y: int in alba.size.y:
			for x: int in alba.size.x:
				if alba.is_buildable(Vector2i(x, y)):
					flat += 1
		_check("Isla Alba: más de 4.500 casillas para construir", flat > 4500)
		_check("Isla Alba: refugio de 8 × 7, portal y veta de malaquita", alba.cells_of("R").size() == 56
				and alba.cells_of("P").size() == 6 and alba.cells_of("M").size() == 9)
		_check("Isla Alba: la veta de malaquita está en la explanada baja", alba.ground(alba.cells_of("M")[4]) == IslandLayout.Ground.LOW_FLAT)
		# Poblar desde el plano (C5.3c): árboles y la veta, solo en una partida nueva.
		var isle: IslandState = WorldState.get_island(&"test_alba")
		isle.apply_layout(alba)
		var planted: int = isle.populate_from_layout()
		var expected: int = 0
		for cell: Vector2i in alba.cells_of("T") + alba.cells_of("t"):
			if not alba.is_steep(cell):
				expected += 1
		_check("Isla Alba: un árbol por cada T y cada t que no sea empinada", planted == expected and isle.nature.size() == expected)
		_check("Isla Alba: las arboledas, enteras (están en llano)", alba.cells_of("T").all(func(c: Vector2i) -> bool: return not alba.is_steep(c)))
		var m_corner: Vector2i = alba.cells_of("M")[0]
		_check("Isla Alba: una sola veta de malaquita, en su sitio", isle.veins.size() == 1 and isle.veins.has(m_corner)
				and isle.vein_at(m_corner + Vector2i(2, 2)) != null)
		var high_tree: Vector2i = Vector2i(-1, -1)
		# Un árbol de lo alto rodeado de montaña por todos lados (en el borde, el suelo dibujado ya baja un poco).
		for cell: Vector2i in alba.cells_of("t"):
			var surrounded: bool = alba.level(cell) == IslandLayout.HIGH_LEVEL
			for dy: int in range(-1, 2):
				for dx: int in range(-1, 2):
					if alba.level(cell + Vector2i(dx, dy)) != IslandLayout.HIGH_LEVEL:
						surrounded = false
			if surrounded:
				high_tree = cell
				break
		_check("Isla Alba: hay árboles en lo alto, a 6 m", high_tree != Vector2i(-1, -1)
				and is_equal_approx(isle.ground_height(high_tree), IslandLayout.LEVEL_HEIGHT))
		# Todo lo que va sobre el terreno se apoya en el suelo dibujado (C5.3d): ni flota ni queda enterrado.
		var shore_ok: bool = true
		for cell: Vector2i in alba.cells_of("t"):
			if not is_equal_approx(isle.ground_height(cell), alba.surface_height(cell)):
				shore_ok = false
		_check("Isla Alba: los árboles se apoyan en el suelo dibujado", shore_ok)
		# Sendero de la ladera (C5.4a): está dibujado, es ladera y ahí no salen rocas ni palos.
		var path_cells: int = 0
		var path_ok: bool = true
		for y: int in alba.size.y:
			for x: int in alba.size.x:
				var cell := Vector2i(x, y)
				if alba.is_path(cell):
					path_cells += 1
					if alba.ground(cell) != IslandLayout.Ground.SLOPE or alba.can_spawn(cell):
						path_ok = false
		_check("Isla Alba: hay sendero en la ladera y está despejado", path_cells > 50 and path_ok)

	WorldState.reset()
	Simulation.running = true
	if _failures == 0:
		print("--- Plano de las islas: TODO OK ---")
	else:
		print("--- Plano de las islas: %d FALLOS ---" % _failures)


func _check(label: String, condition: bool) -> void:
	if condition:
		print("OK    ", label)
	else:
		_failures += 1
		push_error("FALLO " + label)
