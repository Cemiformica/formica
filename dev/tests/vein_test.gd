extends Node
## Prueba de vetas (B3.7, D-090), solo en datos (solo desarrollo).
## Ejecuta con F6 y mira la pestaña Salida: cada comprobación imprime OK o FALLO.
## Minar a golpes es de la vista (`VeinView`), así que aquí no se prueba: se prueba en el sandbox.

var _failures: int = 0


func _ready() -> void:
	var malachite: VeinData = Content.find_vein(&"malachite_vein")
	var crusher: BuildingData = Content.find_building(&"crusher")
	_check("veta en el catálogo, con su ítem y su modelo",
			malachite != null and malachite.item == Content.find_item(&"copper_ore") and malachite.scene != null)

	Simulation.running = false
	WorldState.reset()
	var island: IslandState = WorldState.get_island(&"test_veins")
	var origin := Vector2i(10, 10)

	# 1) Poner una veta y consultar sus casillas.
	_check("poner una veta", island.add_vein(malachite, origin))
	_check("la veta cubre sus 9 casillas", island.vein_at(origin) == malachite and island.vein_at(origin + Vector2i(2, 2)) == malachite)
	_check("fuera de la veta no hay veta", island.vein_at(origin + Vector2i(3, 0)) == null)
	_check("borde sí, centro no", island.is_vein_edge(origin) and island.is_vein_edge(origin + Vector2i(2, 1))
			and not island.is_vein_edge(origin + Vector2i(1, 1)))

	# 2) Bloquea construir, árboles, rocas y otra veta encima.
	_check("no se construye encima", not island.can_place(crusher, origin + Vector2i(1, 1)))
	_check("al lado sí", island.can_place(crusher, origin + Vector2i(3, 0)))
	_check("no se planta encima", not island.add_tree(origin + Vector2i(0, 2)))
	_check("no aparece una roca encima", not island.add_rock(origin + Vector2i(2, 0)))
	_check("no se solapa otra veta", not island.add_vein(malachite, origin + Vector2i(2, 2)))

	# 3) Las rocas que aparecen solas no caen en la veta: límites de solo 3×3 = la propia veta.
	island.bounds = Rect2i(origin, Vector2i(3, 3))
	island.step_nature(IslandState.ROCK_SPAWN_TIME)
	_check("las rocas no aparecen en la veta", island.rock_count() == 0)
	island.bounds = Rect2i()

	# 4) Extractor (1×2): la cabeza sobre el BORDE de la veta y la cola fuera (D-090).
	var extractor: BuildingData = Content.find_building(&"extractor")
	var solar: BuildingData = Content.find_building(&"solar_panel")
	# Sin girar, la cabeza es la casilla de abajo (sur) y la cola la de arriba (norte, con la salida).
	# Cabeza en el borde norte de la veta (10, 10) → cola en (10, 9), fuera.
	_check("extractor: cabeza en el borde, cola fuera", island.can_place(extractor, Vector2i(10, 9)))
	_check("extractor: cabeza fuera de la veta, no", island.placement_problem(extractor, Vector2i(10, 7)) == "BUILD_NEEDS_VEIN")
	_check("extractor: cabeza en el centro, no", island.placement_problem(extractor, Vector2i(11, 11), 2) == "BUILD_NEEDS_VEIN")
	_check("extractor: cola dentro de la veta, no", not island.can_place(extractor, Vector2i(10, 10)))
	_check("extractor: girado, por el borde este", island.can_place(extractor, Vector2i(12, 11), 1))
	var ex: PlacedBuilding = island.place(extractor, Vector2i(10, 9))
	_check("extractor: sabe qué saca", ex != null and ex.vein_item == malachite.item)
	_check("extractor: no se puede reflejar", not extractor.can_flip())
	# Con energía (placa solar cableada), 1 mineral cada 4 s.
	var panel: PlacedBuilding = island.place(solar, Vector2i(4, 4))
	island.add_cable(panel.id, ex.id)
	Simulation.advance(extractor.extract_time * 3)
	_check("extractor: 3 minerales en 12 s", ex.output.get_total(malachite.item) == 3)
	var unpowered: PlacedBuilding = island.place(extractor, Vector2i(10, 12), 2)
	Simulation.advance(extractor.extract_time * 2)
	_check("extractor: sin energía no saca", unpowered != null and unpowered.output.get_total(malachite.item) == 0)

	# 5) Guardar y cargar: la veta vuelve, con su tipo y su sitio, y el extractor sigue sabiendo qué saca.
	var restored := IslandState.new()
	restored.load_data(JSON.parse_string(JSON.stringify(island.to_data())))
	_check("cargada: la veta vuelve", restored.vein_at(origin + Vector2i(1, 1)) == malachite and restored.veins.size() == 1)
	var restored_ex: PlacedBuilding = restored.get_at(Vector2i(10, 9))
	_check("cargada: el extractor sabe qué saca", restored_ex != null and restored_ex.vein_item == malachite.item
			and restored_ex.output.get_total(malachite.item) == ex.output.get_total(malachite.item))

	# 6) Datos dañados o desconocidos se ignoran sin romper la carga.
	var damaged := IslandState.new()
	damaged.load_data({"veins": [{"id": "no_existe", "x": 0, "y": 0}, 42]})
	_check("dañados: se ignoran", damaged.veins.is_empty())

	WorldState.reset()
	Simulation.running = true
	if _failures == 0:
		print("--- Vetas: TODO OK ---")
	else:
		print("--- Vetas: %d FALLOS ---" % _failures)


func _check(label: String, condition: bool) -> void:
	if condition:
		print("OK    ", label)
	else:
		_failures += 1
		push_error("FALLO " + label)
