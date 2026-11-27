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
	_check("ladera: entre 0 y 6 m (4,8 m en esta casilla)", is_equal_approx(layout.height(Vector2i(1, 3)), 4.8))
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
	# Una casilla de playa llana sin roca caída (C5.4c: al pie de la ladera puede haberlas).
	var flat_beach := Vector2i(-1, -1)
	for y: int in layout.size.y:
		for x: int in layout.size.x:
			var c := Vector2i(x, y)
			if flat_beach == Vector2i(-1, -1) and layout.ground(c) == IslandLayout.Ground.BEACH and not layout.is_steep(c) \
					and not layout.has_debris(c):
				flat_beach = c
	_check("en la playa llana sí", flat_beach != Vector2i(-1, -1) and island.can_plant(flat_beach))
	_check("junto a la ladera, empinada: no", not island.can_plant(Vector2i(2, 4)))
	_check("ninguna roca en el agua", not island.add_rock(Vector2i(9, 4)) and not island.add_rock(Vector2i(0, 0)))
	_check("la orilla queda justo sobre el agua", is_equal_approx(layout.corner_height(10, 5), IslandLayout.SHORE_ABOVE_WATER))
	# (no junto a la cascada: su cauce va plano hasta el filo, C5.4e)

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
		# Versión 3 (C5.4b): explanadas partidas en bolsas, terraza a 3 m y explanada alta más pequeña.
		_check("Isla Alba: más de 3.000 casillas para construir", flat > 3000)
		var terrace: Array[Vector2i] = []
		var ramp: Array[Vector2i] = []
		var hill_peak: float = 0.0
		for y: int in alba.size.y:
			for x: int in alba.size.x:
				var cell := Vector2i(x, y)
				match alba.ground(cell):
					IslandLayout.Ground.MID_FLAT:
						if alba.char_at(cell) == "+":   # sin los peñascos de la rampa, que toman el suelo de al lado
							terrace.append(cell)
					IslandLayout.Ground.RAMP:
						if x >= 70 and y >= 70:
							ramp.append(cell)
					IslandLayout.Ground.HILL:
						hill_peak = maxf(hill_peak, alba.relief(x + 0.5, y + 0.5))
		_check("Isla Alba: la terraza está a 3 m y se construye en ella", terrace.size() > 200
				and terrace.all(func(c: Vector2i) -> bool: return alba.is_buildable(c) and is_equal_approx(alba.height(c), IslandLayout.MID_HEIGHT)))
		_check("Isla Alba: la rampa de la terraza sube entre 0 y 3 m", ramp.size() > 10
				and ramp.all(func(c: Vector2i) -> bool: return alba.height(c) > 0.0 and alba.height(c) < IslandLayout.MID_HEIGHT))
		_check("Isla Alba: las lomas suben unos 2 m o más", hill_peak > 2.0)
		var landing_cells: int = 0
		var landing_ok: bool = true
		for y: int in alba.size.y:
			for x: int in alba.size.x:
				if alba.char_at(Vector2i(x, y)) != "_":
					continue
				landing_cells += 1
				if not (alba.is_buildable(Vector2i(x, y)) and is_equal_approx(alba.surface_height(Vector2i(x, y)), IslandLayout.MID_HEIGHT)):
					landing_ok = false
		_check("Isla Alba: el mirador es plano, a 3 m, y se construye en él", landing_cells > 20 and landing_ok)
		# Cumbre a 9 m (C5.4b): su explanada se construye y la rampa sube entre 6 y 9 m.
		var summit: int = 0
		var summit_ok: bool = true
		var summit_ramp_ok: bool = true
		for y: int in alba.size.y:
			for x: int in alba.size.x:
				var cell := Vector2i(x, y)
				if alba.char_at(cell) == "%":
					summit += 1
					if not (alba.is_buildable(cell) and is_equal_approx(alba.height(cell), IslandLayout.TOP_HEIGHT)):
						summit_ok = false
				elif alba.char_at(cell) == "r" and y < 30 and x > 80:
					if alba.height(cell) <= IslandLayout.LEVEL_HEIGHT or alba.height(cell) >= IslandLayout.TOP_HEIGHT:
						summit_ramp_ok = false
		_check("Isla Alba: la cumbre está a 9 m y se construye en su explanada", summit > 80 and summit_ok)
		# Capa de tierra pisada (dibujo de César): se lee y pinta de tierra lo que no es empinado.
		var worn: int = 0
		for y: int in alba.size.y:
			for x: int in alba.size.x:
				if alba.wear(Vector2i(x, y)) >= 1.0 and not alba.is_path(Vector2i(x, y)):
					worn += 1
		_check("Isla Alba: la capa de tierra pisada se lee", worn > 300)
		# Sin charcos de una casilla en la arena (sesión 23, César: se veían como hoyos hundidos con agua).
		var puddles: int = 0
		for y: int in alba.size.y:
			for x: int in alba.size.x:
				var cell := Vector2i(x, y)
				if alba.ground(cell) != IslandLayout.Ground.WATER:
					continue
				var alone: bool = true
				for side: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
					if alba.ground(cell + side) == IslandLayout.Ground.WATER:
						alone = false
				if alone:
					puddles += 1
		_check("Isla Alba: no hay charcos sueltos de una casilla", puddles == 0)
		# Rocas caídas al pie de las paredes (C5.4c): hay bastantes, nunca en el agua, y donde hay una no se construye.
		var debris_ok: bool = alba.debris.size() > 60
		for item: Dictionary in alba.debris:
			var p: Vector3 = item["position"]
			var cell := Vector2i(floori(p.x), floori(p.z))
			if not alba.is_land(cell) or not alba.has_debris(cell):
				debris_ok = false
		_check("Isla Alba: rocas caídas al pie de las paredes, en tierra", debris_ok)
		# Rocas modeladas (C5.6, sesión 30): peñascos de los grupos de X, un solo peñasco del emblema en su K, medianas que
		# bloquean su casilla y guijarros que no chocan; ni unas ni otros en una explanada ni en la arena (César).
		var carved: int = 0
		var mediums: int = 0
		var pebbles: int = 0
		var big: int = 0
		var rocks_ok: bool = true
		for rock: Dictionary in alba.rocks:
			var at: Vector3 = rock["position"]
			var cell := Vector2i(floori(at.x), floori(at.z))
			var piece: String = rock["mesh"]
			if piece == IslandLayout.CARVED_BOULDER:
				carved += 1
			elif piece.begins_with("pebbles"):
				pebbles += 1
				rocks_ok = rocks_ok and not rock["solid"] and not alba.is_buildable(cell) \
						and alba.ground(cell) != IslandLayout.Ground.BEACH
			elif piece.begins_with("boulder"):
				big += 1
			elif alba.char_at(cell) != "X":
				mediums += 1
				rocks_ok = rocks_ok and rock["solid"] and alba.has_debris(cell) and not alba.can_spawn(cell) \
						and not alba.is_buildable(cell) and alba.ground(cell) != IslandLayout.Ground.BEACH
		_check("Isla Alba: un solo peñasco del emblema, en sus 4 casillas K", carved == 1
				and alba.cells_of(IslandLayout.CARVED_CHAR).size() == 4)
		_check("Isla Alba: rocas repartidas (%d peñascos, %d medianas sueltas, %d grupitos de guijarros)" % [big, mediums, pebbles],
				rocks_ok and big >= 3 and mediums >= 10 and pebbles >= 30)
		_check("Isla Alba: la rampa de la cumbre sube entre 6 y 9 m", summit_ramp_ok)
		_check("Isla Alba: refugio de 8 × 7, portal y veta de malaquita", alba.cells_of("R").size() == 56
				and alba.cells_of("P").size() == 6 and alba.cells_of("M").size() == 9)
		# El portal, delante de la boca del refugio (sesión 25): centrado con ella, a unos pasos al sur y con
		# explanada baja libre entre los dos, para que Mira llegue con el refugio de frente.
		var portal_front_ok: bool = not alba.cells_of("P").is_empty()
		if portal_front_ok:
			var shelter_south: int = 0
			for cell: Vector2i in alba.cells_of("R"):
				shelter_south = maxi(shelter_south, cell.y)
			var portal_north: int = 1000
			var portal_x: float = 0.0
			for cell: Vector2i in alba.cells_of("P"):
				portal_north = mini(portal_north, cell.y)
				portal_x += cell.x + 0.5
			portal_x /= alba.cells_of("P").size()
			var gap: int = portal_north - shelter_south - 1
			portal_front_ok = portal_x > 46.0 and portal_x < 50.0 and gap >= 5 and gap <= 9
			for y: int in range(shelter_south + 1, portal_north):
				if alba.ground(Vector2i(floori(portal_x), y)) != IslandLayout.Ground.LOW_FLAT:
					portal_front_ok = false
		_check("Isla Alba: el portal, delante de la boca del refugio y con explanada libre entre los dos", portal_front_ok)
		var shelter_flat: bool = true
		for cell: Vector2i in alba.cells_of("R"):
			if alba.ground(cell) != IslandLayout.Ground.LOW_FLAT or not is_zero_approx(alba.terrain_height(cell.x + 0.5, cell.y + 0.5)):
				shelter_flat = false
		_check("Isla Alba: la zona del refugio es llana y está abajo (el hormiguero va encima)", shelter_flat)
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
		# Con las lomas (C5.4b), a unos 6 m: más o menos lo que mueven las lomas de la montaña.
		_check("Isla Alba: hay árboles en lo alto, a unos 6 m", high_tree != Vector2i(-1, -1)
				and absf(isle.ground_height(high_tree) - IslandLayout.LEVEL_HEIGHT) <= IslandLayout.RELIEF_BY_GROUND[IslandLayout.Ground.HIGH] + IslandLayout.LANDMARK_MOUND
				+ IslandLayout.HIGH_HILL_HEIGHT + 0.01)
		# Lomas (C5.4b): las explanadas siguen planas del todo (también en sus bordes) y la montaña se mueve.
		var flat_ok: bool = true
		var bumpy: int = 0
		for y: int in alba.size.y:
			for x: int in alba.size.x:
				var cell := Vector2i(x, y)
				if alba.is_buildable(cell):
					for f: Vector2 in [Vector2(0.0, 0.0), Vector2(0.5, 0.5), Vector2(1.0, 0.5), Vector2(0.5, 1.0), Vector2(1.0, 1.0)]:
						if not is_equal_approx(alba.terrain_height(x + f.x, y + f.y), alba.height(cell)):
							flat_ok = false
				elif alba.ground(cell) == IslandLayout.Ground.HIGH and absf(alba.relief(x + 0.5, y + 0.5)) > 0.2:
					bumpy += 1
		_check("Isla Alba: las explanadas siguen planas con las lomas", flat_ok)
		_check("Isla Alba: la montaña tiene lomas", bumpy > 200)
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
		# Escala de cuerda de la cascada (C5.6b, sesión 27): una, en tres piezas por reparar, que sube la pared.
		var ladders: int = 0
		var ladder_pieces: int = 0
		for site_origin: Vector2i in isle.repair_sites:
			var site: RepairSite = isle.repair_sites[site_origin]
			if site.data.purpose == LadderBuilder.PURPOSE:
				ladders += 1
				ladder_pieces = site.data.pieces.size()
		_check("Isla Alba: una escala de cuerda reparable, en tres piezas", ladders == 1 and ladder_pieces == 3)
		var ladder_spot: Dictionary = LadderBuilder.measure(alba, alba.ladder_cells)
		var ladder_reaches: bool = not ladder_spot.is_empty() and absf(float(ladder_spot["modules"]) - float(ladder_spot["rise"])) <= 0.5 \
				and absf(float(ladder_spot["rise"]) - IslandLayout.LEVEL_HEIGHT) < 1.0
		_check("Isla Alba: la escala llega al borde de la pared (%s)" % ("sin pared" if ladder_spot.is_empty() else
				"%d módulos, %.2f m" % [ladder_spot["modules"], ladder_spot["rise"]]), ladder_reaches)
		# Pasarela del vado (C5.6b, sesión 29): una, en tres piezas, con el tablero por encima del agua y de las orillas.
		var bridges: int = 0
		var bridge_pieces: int = 0
		for site_origin: Vector2i in isle.repair_sites:
			var site: RepairSite = isle.repair_sites[site_origin]
			if site.data.purpose == BridgeBuilder.PURPOSE:
				bridges += 1
				bridge_pieces = site.data.pieces.size()
		_check("Isla Alba: una pasarela reparable en el vado, en tres piezas", bridges == 1 and bridge_pieces == 3)
		var bridge_spot: Dictionary = BridgeBuilder.measure(alba, BridgeBuilder.ford_cells(alba))
		var bridge_ok: bool = not bridge_spot.is_empty() and float(bridge_spot["length"]) > 4.0 \
				and float(bridge_spot["deck"]) - float(bridge_spot["surface"]) >= BridgeBuilder.WATER_CLEAR - 0.001 \
				and float(bridge_spot["deck"]) - float(bridge_spot["surface"]) < 0.6
		_check("Isla Alba: la pasarela cruza el vado (%s)" % ("sin orillas" if bridge_spot.is_empty() else
				"%.2f m, tablero a %.2f m sobre el agua" % [bridge_spot["length"],
				float(bridge_spot["deck"]) - float(bridge_spot["surface"])]), bridge_ok)
		# Embarcadero en ruinas (sesión 29): uno, solo decorado (sin piezas), que sale de la orilla hacia el agua.
		var docks: int = 0
		var dock_pieces: int = -1
		for site_origin: Vector2i in isle.repair_sites:
			var site: RepairSite = isle.repair_sites[site_origin]
			if site.data.purpose == DockBuilder.PURPOSE:
				docks += 1
				dock_pieces = site.data.pieces.size()
		_check("Isla Alba: un embarcadero en ruinas, solo decorado", docks == 1 and dock_pieces == 0)
		var dock_spot: Dictionary = DockBuilder.measure(alba, alba.cells_of(DockBuilder.DOCK_CHAR))
		var dock_ok: bool = not dock_spot.is_empty() and float(dock_spot["deck"]) - float(dock_spot["surface"]) >= DockBuilder.WATER_CLEAR - 0.001 \
				and float(dock_spot["deck"]) - float(dock_spot["surface"]) < 1.2
		_check("Isla Alba: el embarcadero entra en el agua (%s)" % ("sin agua" if dock_spot.is_empty() else
				"%.2f m, tablero a %.2f m sobre el agua" % [dock_spot["length"],
				float(dock_spot["deck"]) - float(dock_spot["surface"])]), dock_ok)

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
