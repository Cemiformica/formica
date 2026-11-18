extends Node
## Prueba del desmontaje (C2.1, D-089, D-033), solo en datos (solo desarrollo).
## Ejecuta con F6 y mira la pestaña Salida: cada comprobación imprime OK o FALLO.
##
## Plano: horno 2×2 en (0,0) con contenido; arcón 2×1 en (5,0) con piedra; cinta en (10,0) con un ítem;
## placa solar 2×2 en (0,5) unida al horno con un cable.

var _failures: int = 0


func _ready() -> void:
	var furnace_data: BuildingData = Content.find_building(&"furnace")
	var chest_data: BuildingData = Content.find_building(&"storage_chest")
	var conveyor: BuildingData = Content.find_building(&"conveyor")
	var solar_data: BuildingData = Content.find_building(&"solar_panel")
	var stone: ItemData = Content.find_item(&"stone")
	var wood: ItemData = Content.find_item(&"wood")
	var ore: ItemData = Content.find_item(&"copper_ore")
	var ingot: ItemData = Content.find_item(&"copper_ingot")

	Simulation.running = false
	WorldState.reset()
	var island: IslandState = WorldState.get_island(&"test_dismantle")

	# 1) Reembolso de una construcción: coste + contenido.
	var furnace: PlacedBuilding = island.place(furnace_data, Vector2i(0, 0))
	furnace.input.add_item(ore, 5)
	furnace.output.add_item(ingot, 2)
	var refund: Dictionary[ItemData, int] = furnace.get_refund()
	_check("horno: devuelve su coste de piedra", refund.get(stone, 0) == furnace_data.cost.get(stone, 0))
	_check("horno: y lo que tiene dentro (5 mineral, 2 lingotes)", refund.get(ore, 0) == 5 and refund.get(ingot, 0) == 2)

	var chest: PlacedBuilding = island.place(chest_data, Vector2i(5, 0))
	chest.output.add_item(stone, 30)
	_check("arcón: coste de madera + 30 de piedra guardada", chest.get_refund().get(stone, 0) == 30
			and chest.get_refund().get(wood, 0) == chest_data.cost.get(wood, 0))

	var belt: PlacedBuilding = island.place(conveyor, Vector2i(10, 0))
	belt.accept(ingot)
	_check("cinta: devuelve también el ítem que lleva", belt.get_refund().get(ingot, 0) == 1)

	# 2) Reembolso de varias a la vez.
	var all_ids: Array[int] = [furnace.id, chest.id, belt.id]
	var total: Dictionary[ItemData, int] = island.refund_for(all_ids)
	_check("varias: suma los reembolsos", total.get(ingot, 0) == 3 and total.get(ore, 0) == 5
			and total.get(stone, 0) == 30 + furnace_data.cost.get(stone, 0) + conveyor.cost.get(stone, 0))

	# 3) Todo o nada: si no cabe, no se quita ninguna.
	var small := Inventory.new(1)
	_check("no cabe: devuelve false", not island.dismantle(all_ids, small))
	_check("no cabe: siguen las tres", island.buildings.has(furnace.id) and island.buildings.has(chest.id)
			and island.buildings.has(belt.id))
	_check("no cabe: el inventario sigue vacío", small.get_total(stone) == 0 and small.get_total(ingot) == 0)

	# 4) Desmontar con sitio: quita, libera las casillas, mete el reembolso y quita los cables.
	var solar: PlacedBuilding = island.place(solar_data, Vector2i(0, 5))
	island.add_cable(solar.id, furnace.id)
	var big := Inventory.new(30)
	_check("con sitio: desmonta", island.dismantle(all_ids, big))
	_check("con sitio: ya no están y sus casillas quedan libres", not island.buildings.has(furnace.id)
			and island.get_at(Vector2i(0, 0)) == null and island.get_at(Vector2i(6, 0)) == null)
	_check("con sitio: el reembolso está en el inventario", big.get_total(ingot) == 3 and big.get_total(ore) == 5
			and big.get_total(stone) == total.get(stone, 0))
	_check("con sitio: el cable del horno se ha quitado", island.cable_count(solar.id) == 0)
	_check("con sitio: la placa sigue", island.buildings.has(solar.id))

	# 5) Mover (C2.5): quitar y volver a poner la MISMA construcción, con su contenido y su id.
	var chest2: PlacedBuilding = island.place(chest_data, Vector2i(20, 0))
	chest2.output.add_item(stone, 12)
	var furnace2: PlacedBuilding = island.place(furnace_data, Vector2i(3, 5)) # a 3 m de la placa: cable de sobra
	island.add_cable(solar.id, furnace2.id)
	var furnace_cables: Array[Vector2i] = island.cables_of(furnace2.id)
	_check("mover: el horno tiene su cable antes de moverlo", furnace_cables.size() == 1)
	var lifted: PlacedBuilding = island.remove(chest2.id)
	_check("mover: al quitarla deja libres sus casillas", island.get_at(Vector2i(20, 0)) == null)
	_check("mover: se vuelve a poner en otro sitio", island.drop(lifted, Vector2i(24, 0), 1))
	_check("mover: misma construcción, mismo id y con su contenido", island.buildings.get(chest2.id) == chest2
			and chest2.output.get_total(stone) == 12 and chest2.origin == Vector2i(24, 0) and chest2.rotation == 1)
	_check("mover: no se pone encima de otra", not island.drop(island.remove(furnace2.id), Vector2i(24, 0)))
	_check("mover: tras el intento fallido, se puede devolver a su sitio", island.drop(furnace2, Vector2i(3, 5)))
	for cable: Vector2i in furnace_cables:
		island.add_cable(cable.x, cable.y)
	_check("mover: los cables se pueden volver a tender", island.cable_count(furnace2.id) == 1)

	WorldState.reset()
	Simulation.running = true
	if _failures == 0:
		print("--- Desmontar: TODO OK ---")
	else:
		print("--- Desmontar: %d FALLOS ---" % _failures)


func _check(label: String, condition: bool) -> void:
	if condition:
		print("OK    ", label)
	else:
		_failures += 1
		push_error("FALLO " + label)
