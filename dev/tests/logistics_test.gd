extends Node
## Prueba de cintas y conexiones (B2.5a), solo en datos (solo desarrollo).
## Ejecuta con F6 y mira la pestaña Salida: cada comprobación imprime OK o FALLO.
##
## Plano de la prueba (x hacia la derecha = este; las cintas miran al este, giro 1):
##   fila 0:  [A]→[b1]→[b2]→[b3]→ (nada)      [c]→[B]
##             0    1    2    3                  5   6
##   fila 4:  [D][E]   dos trituradoras pegadas, salida de D frente a entrada de E

var _failures: int = 0


func _ready() -> void:
	var crusher: BuildingData = Content.find_building(&"crusher")
	var conveyor: BuildingData = Content.find_building(&"conveyor")
	var stone: ItemData = Content.find_item(&"stone")
	var gravel: ItemData = Content.find_item(&"gravel")
	_check("cinta en el catálogo", conveyor != null and conveyor.belt_speed > 0.0)

	Simulation.running = false
	WorldState.reset()
	var island: IslandState = WorldState.get_island(&"test_logistics")
	var a: PlacedBuilding = island.place(crusher, Vector2i(0, 0))
	var b1: PlacedBuilding = island.place(conveyor, Vector2i(1, 0), 1)
	var b2: PlacedBuilding = island.place(conveyor, Vector2i(2, 0), 1)
	var b3: PlacedBuilding = island.place(conveyor, Vector2i(3, 0), 1)
	var c: PlacedBuilding = island.place(conveyor, Vector2i(5, 0), 1)
	var b: PlacedBuilding = island.place(crusher, Vector2i(6, 0))
	var d: PlacedBuilding = island.place(crusher, Vector2i(0, 4))
	var e: PlacedBuilding = island.place(crusher, Vector2i(1, 4))

	# 1) Conexiones: A→b1, b1→b2, b2→b3, c→B y D→E (máquinas pegadas). b3 no conecta con nada.
	_check("5 conexiones", island.get_links().size() == 5)

	# 2) Máquina → cintas: 60 s = 20 ciclos. Caben 6 en las 3 cintas; el resto espera en la salida de A.
	a.input.add_item(stone, 20)
	Simulation.advance(60.0)
	var on_belts: int = b1.belt_items.size() + b2.belt_items.size() + b3.belt_items.size()
	_check("cintas llenas: 6 ítems", on_belts == 6)
	_check("el resto espera en la salida de A (14)", a.output.get_total(gravel) == 14)
	_check("el de delante está parado al final", is_equal_approx(b3.belt_progress[0], 1.0))

	# 3) Cinta → máquina: piedra puesta en c entra en B (1 casilla a 1,5/s ≈ 0,7 s).
	c.accept(stone)
	Simulation.advance(1.0)
	_check("la piedra entra en B", b.input.get_total(stone) == 1 and c.belt_items.is_empty())

	# 4) Lo que la máquina no acepta se queda esperando en la cinta.
	c.accept(gravel)
	Simulation.advance(2.0)
	_check("la grava no entra en B", c.belt_items.size() == 1 and b.input.get_total(gravel) == 0)

	# 5) Máquinas pegadas: conectadas, pero E solo acepta piedra, así que la grava de D se queda.
	d.output.add_item(gravel, 2)
	Simulation.advance(1.0)
	_check("pegadas: la grava no pasa a E", d.output.get_total(gravel) == 2 and e.input.get_total(gravel) == 0)

	# 6) Guardar y cargar: los ítems de las cintas y las conexiones vuelven.
	var restored := IslandState.new()
	restored.load_data(JSON.parse_string(JSON.stringify(island.to_data())))
	var r3: PlacedBuilding = restored.get_at(Vector2i(3, 0))
	_check("cargada: ítems de la cinta", r3 != null and r3.belt_items.size() == b3.belt_items.size() and r3.belt_items[0] == gravel)
	_check("cargada: avance de la cinta", r3 != null and is_equal_approx(r3.belt_progress[0], b3.belt_progress[0]))
	_check("cargada: 5 conexiones", restored.get_links().size() == 5)

	# 7) Quitar una cinta corta la cadena.
	island.remove(b2.id)
	_check("sin b2: 3 conexiones", island.get_links().size() == 3)

	WorldState.reset()
	Simulation.running = true
	if _failures == 0:
		print("--- Logística: TODO OK ---")
	else:
		print("--- Logística: %d FALLOS ---" % _failures)


func _check(label: String, condition: bool) -> void:
	if condition:
		print("OK    ", label)
	else:
		_failures += 1
		push_error("FALLO " + label)
