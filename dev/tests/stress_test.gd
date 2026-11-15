extends Node
## Prueba de estrés de la simulación (B2.9), solo en datos (solo desarrollo).
## Monta por código una isla grande que NO se dibuja (como una isla no cargada) y mide:
##   - milisegundos por paso de `Simulation` (presupuesto: 2 ms; a 10 pasos/s es un 2 % del tiempo);
##   - milisegundos para guardar y cargar la isla (presupuesto: 200 ms);
##   - que todo sigue produciendo.
## Ejecuta con F6 y mira la pestaña Salida. Tarda unos segundos. Los tiempos dependen del equipo:
## anótalos en el Devlog para comparar más adelante (y probar en equipos modestos).
##
## Contenido (ajustable con las constantes):
##   - CHAINS cadenas «trituradora → 2 cintas» (3 construcciones y 2 conexiones cada una);
##   - una red eléctrica grande: POLES postes en fila, cada uno con su placa y un talador con un árbol delante
##     (consumidores del catálogo, para que el guardado los reconozca);
##   - CUTTERS taladores, cada uno con su placa y una arboleda de 3×3 delante.

const CHAINS: int = 250
const POLES: int = 100
const CUTTERS: int = 20
const STEP_BUDGET_MS: float = 2.0
const SAVE_BUDGET_MS: float = 200.0
const MEASURE_STEPS: int = 100

var _failures: int = 0


func _ready() -> void:
	var crusher: BuildingData = Content.find_building(&"crusher")
	var conveyor: BuildingData = Content.find_building(&"conveyor")
	var pole_data: BuildingData = Content.find_building(&"power_pole")
	var solar_data: BuildingData = Content.find_building(&"solar_panel")
	var cutter_data: BuildingData = Content.find_building(&"tree_cutter")
	var stone: ItemData = Content.find_item(&"stone")
	var gravel: ItemData = Content.find_item(&"gravel")
	var wood: ItemData = Content.find_item(&"wood")

	Simulation.running = false
	WorldState.reset()
	var island: IslandState = WorldState.get_island(&"stress_far")
	var build_start: int = Time.get_ticks_usec()

	# 1) Cadenas: trituradora en (x, y) y dos cintas al este mirando al este (giro 1).
	var crushers: Array[PlacedBuilding] = []
	for i: int in CHAINS:
		var x: int = int(i / 50.0) * 5
		var y: int = (i % 50) * 2
		var c: PlacedBuilding = island.place(crusher, Vector2i(x, y))
		island.place(conveyor, Vector2i(x + 1, y), 1)
		island.place(conveyor, Vector2i(x + 2, y), 1)
		c.input.add_item(stone, 50)
		crushers.append(c)

	# 2) Red grande: postes cada 3 casillas en x = 300; placa al este y, al oeste, un talador de 3×1
	#    (x 296..298) mirando al norte con un árbol maduro justo delante.
	var electric: Array[PlacedBuilding] = []
	var previous_pole: PlacedBuilding = null
	for k: int in POLES:
		var y: int = k * 3
		var pole: PlacedBuilding = island.place(pole_data, Vector2i(300, y))
		var solar: PlacedBuilding = island.place(solar_data, Vector2i(302, y))
		var consumer: PlacedBuilding = island.place(cutter_data, Vector2i(296, y))
		island.add_tree(Vector2i(297, y - 1))
		island.add_cable(pole.id, solar.id)
		island.add_cable(pole.id, consumer.id)
		if previous_pole != null:
			island.add_cable(previous_pole.id, pole.id)
		previous_pole = pole
		electric.append(consumer)

	# 3) Taladores de 3×1: en x − 1..x + 1 (x = 500 + 6j) mirando al norte, arboleda madura delante y placa al este.
	var cutters: Array[PlacedBuilding] = []
	for j: int in CUTTERS:
		var x: int = 500 + j * 6
		for dx: int in range(-1, 2):
			for dy: int in range(-3, 0):
				island.add_tree(Vector2i(x + dx, dy))
		var cutter: PlacedBuilding = island.place(cutter_data, Vector2i(x - 1, 0))
		var solar: PlacedBuilding = island.place(solar_data, Vector2i(x + 2, 0))
		island.add_cable(cutter.id, solar.id)
		cutters.append(cutter)

	var build_ms: float = (Time.get_ticks_usec() - build_start) / 1000.0
	print("Isla de estrés: %d construcciones, %d conexiones, %d redes, %d árboles (montada en %.1f ms)" % [
		island.buildings.size(), island.get_links().size(), island.get_networks().size(), island.nature.size(), build_ms])
	_check("todo colocado", island.buildings.size() == CHAINS * 3 + POLES * 3 + CUTTERS * 2)
	_check("la red grande funciona", island.is_powered(electric[0].id) and island.get_network(electric[0].id).members.size() == POLES * 3)

	# 4) Tiempo por paso (la primera tanda calienta; se mide la segunda).
	Simulation.advance(1.0)
	var start: int = Time.get_ticks_usec()
	for _i: int in MEASURE_STEPS:
		Simulation.advance(Simulation.TICK)
	var step_ms: float = (Time.get_ticks_usec() - start) / 1000.0 / MEASURE_STEPS
	print("Tiempo por paso: %.3f ms (presupuesto %.1f ms)" % [step_ms, STEP_BUDGET_MS])
	# El presupuesto es un OBJETIVO para islas grandes (D-073), no un requisito: si se pasa, aviso amarillo
	# en lugar de FALLO, para que un FALLO rojo siga queriendo decir que algo está roto.
	if step_ms <= STEP_BUDGET_MS:
		print("OK    paso dentro del objetivo")
	else:
		push_warning("Paso por encima del objetivo de %.1f ms (%.3f ms): ver D-073" % [STEP_BUDGET_MS, step_ms])

	# 5) Sigue produciendo: 60 s más de juego.
	Simulation.advance(60.0)
	var gravel_total: int = 0
	var slow_chain: int = 999
	for c: PlacedBuilding in crushers:
		gravel_total += c.output.get_total(gravel)
		slow_chain = mini(slow_chain, c.output.get_total(gravel))
	var electric_min: int = 999
	for e: PlacedBuilding in electric:
		electric_min = mini(electric_min, e.output.get_total(wood))
	var cutter_wood: int = 0
	for cutter: PlacedBuilding in cutters:
		cutter_wood += cutter.output.get_total(wood)
	print("Tras ~71 s: grava en salidas de cadenas %d · mínima por talador de la red grande %d · madera de taladores %d" % [gravel_total, electric_min, cutter_wood])
	_check("las cadenas producen", slow_chain > 0)
	_check("la red grande produce", electric_min > 0)
	_check("los taladores talan", cutter_wood == CUTTERS * 9 * IslandState.TREE_WOOD)

	# 6) Guardar y cargar la isla entera (datos → JSON → datos).
	start = Time.get_ticks_usec()
	var json_text: String = JSON.stringify(island.to_data())
	var restored := IslandState.new()
	restored.load_data(JSON.parse_string(json_text))
	var save_ms: float = (Time.get_ticks_usec() - start) / 1000.0
	print("Guardar + cargar: %.1f ms · %d KB de JSON" % [save_ms, int(json_text.length() / 1024.0)])
	_check("guardar + cargar dentro del presupuesto", save_ms <= SAVE_BUDGET_MS)
	_check("cargada: mismas construcciones", restored.buildings.size() == island.buildings.size())

	WorldState.reset()
	Simulation.running = true
	if _failures == 0:
		print("--- Estrés: TODO OK ---")
	else:
		print("--- Estrés: %d FALLOS ---" % _failures)


func _check(label: String, condition: bool) -> void:
	if condition:
		print("OK    ", label)
	else:
		_failures += 1
		push_error("FALLO " + label)
