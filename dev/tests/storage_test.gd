extends Node
## Prueba de los almacenes (B3.7, D-093), solo en datos (solo desarrollo).
## Ejecuta con F6 y mira la pestaña Salida: cada comprobación imprime OK o FALLO.
##
## Plano (las cajas logísticas son de 1×2 y miran al norte: cabeza en y = 0, abdomen en y = 1):
##   x 0:  cinta de salida en (0, −1) ← caja recta A (0, 0..1) ← cinta de entrada en (0, 2)
##   x 5:  caja B con la salida a la DERECHA (este) → cinta en (6, 0); la cinta de (5, −1) NO conecta
##   x 10: caja C con la salida a la IZQUIERDA (oeste) → cinta en (9, 0)
##   x 20: arcón de 2×1

var _failures: int = 0


func _ready() -> void:
	var box_data: BuildingData = Content.find_building(&"logistic_box")
	var chest_data: BuildingData = Content.find_building(&"storage_chest")
	var conveyor: BuildingData = Content.find_building(&"conveyor")
	var stone: ItemData = Content.find_item(&"stone")
	var wood: ItemData = Content.find_item(&"wood")
	_check("contenido: caja logística (8 casillas, F gira la salida, no se refleja)", box_data != null
			and box_data.storage_slots == 8 and box_data.output_turns and not box_data.can_flip())
	_check("contenido: arcón (16 casillas, sin puertos)", chest_data != null and chest_data.storage_slots == 16
			and chest_data.ports.is_empty())

	Simulation.running = false
	WorldState.reset()
	var island: IslandState = WorldState.get_island(&"test_storage")
	var a: PlacedBuilding = island.place(box_data, Vector2i(0, 0))
	var feed: PlacedBuilding = island.place(conveyor, Vector2i(0, 2), 0)
	var out_a: PlacedBuilding = island.place(conveyor, Vector2i(0, -1), 0)
	var b: PlacedBuilding = island.place(box_data, Vector2i(5, 0), 0, false, 1)
	var out_b: PlacedBuilding = island.place(conveyor, Vector2i(6, 0), 1)
	var not_b: PlacedBuilding = island.place(conveyor, Vector2i(5, -1), 0)
	var c: PlacedBuilding = island.place(box_data, Vector2i(10, 0), 0, false, 2)
	var out_c: PlacedBuilding = island.place(conveyor, Vector2i(9, 0), 3)

	# 1) Conexiones: cinta → A, A → cinta, B → este, C → oeste. La cinta al norte de B no conecta.
	_check("4 conexiones", island.get_links().size() == 4)
	var b_linked_north: bool = false
	for link: Dictionary in island.get_links():
		if link["from"] == b and link["to"] == not_b:
			b_linked_north = true
	_check("B (derecha) no sale por delante", not b_linked_north)

	# 2) Entra por detrás, guarda y saca por delante: 5 piedras; la cinta de salida no lleva a ningún
	#    sitio, así que se llena (2) y el resto (3) se queda guardado en A.
	for i: int in 5:
		a.accept(stone)
	feed.accept(stone)
	Simulation.advance(10.0)
	_check("la cinta de entrada se vacía en A", feed.belt_items.is_empty())
	_check("salen 2 a la cinta y A guarda 4", out_a.belt_items.size() == 2 and a.output.get_total(stone) == 4)

	# 3) Salidas giradas: B saca por el este y C por el oeste.
	b.output.add_item(wood, 1)
	c.output.add_item(wood, 1)
	Simulation.advance(1.0)
	_check("B saca por la derecha (este)", out_b.belt_items.size() == 1 and b.output.get_total(wood) == 0)
	_check("C saca por la izquierda (oeste)", out_c.belt_items.size() == 1 and c.output.get_total(wood) == 0)

	# 3b) Versiones nuevas (C2b): entrada por un costado de la casilla de atrás.
	#     D (15, 0..1), combinación 3: entrada a la derecha (este) y salida recta. Cinta (16, 1) ← que entra.
	#     G (20, 0..1), combinación 8: entrada y salida a la izquierda (oeste). Cinta (19, 1) → que entra y
	#     cinta (19, 0) ← que sale.
	var d: PlacedBuilding = island.place(box_data, Vector2i(15, 0), 0, false, 3)
	var feed_d: PlacedBuilding = island.place(conveyor, Vector2i(16, 1), 3)
	var out_d: PlacedBuilding = island.place(conveyor, Vector2i(15, -1), 0)
	var g: PlacedBuilding = island.place(box_data, Vector2i(20, 0), 0, false, 8)
	var feed_g: PlacedBuilding = island.place(conveyor, Vector2i(19, 1), 1)
	var out_g: PlacedBuilding = island.place(conveyor, Vector2i(19, 0), 3)
	feed_d.accept(wood)
	feed_g.accept(wood)
	Simulation.advance(6.0)
	_check("entrada a la derecha: entra y sale recta", feed_d.belt_items.is_empty() and out_d.belt_items.size() == 1)
	_check("entrada y salida a la izquierda", feed_g.belt_items.is_empty() and out_g.belt_items.size() == 1)
	_check("cargada: combinación 8", d.output_turn == 3 and g.output_turn == 8)

	# 4) Llena: no acepta más.
	var in_port: PortData = box_data.ports[0]
	a.output.add_item(stone, 99999)
	_check("llena: no acepta más", not a.can_accept(stone, in_port))

	# 5) Guardar y cargar: el lado de la salida y lo guardado vuelven.
	var restored := IslandState.new()
	restored.load_data(JSON.parse_string(JSON.stringify(island.to_data())))
	var rb: PlacedBuilding = restored.buildings.get(b.id)
	var ra: PlacedBuilding = restored.buildings.get(a.id)
	_check("cargada: salida a la derecha", rb != null and rb.output_turn == 1)
	_check("cargada: contenido de A", ra != null and ra.output.get_total(stone) == a.output.get_total(stone))
	_check("cargada: mismas conexiones", restored.get_links().size() == island.get_links().size())

	WorldState.reset()
	Simulation.running = true
	if _failures == 0:
		print("--- Almacenes: TODO OK ---")
	else:
		print("--- Almacenes: %d FALLOS ---" % _failures)


func _check(label: String, condition: bool) -> void:
	if condition:
		print("OK    ", label)
	else:
		_failures += 1
		push_error("FALLO " + label)
