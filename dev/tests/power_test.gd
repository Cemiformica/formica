extends Node
## Prueba de energía (B2.6a): cables, redes y fusible, solo en datos (solo desarrollo).
## Ejecuta con F6 y mira la pestaña Salida: cada comprobación imprime OK o FALLO.
## El consumidor (2 puntos, receta de triturar) se crea aquí: la trituradora del catálogo no es eléctrica.
##
## Plano: placa solar 2×2 en (0,0) · poste en (5,0) · consumidores m1 (8,0), m2 (8,2), m3 (8,4).

var _failures: int = 0


func _ready() -> void:
	var solar_data: BuildingData = Content.find_building(&"solar_panel")
	var pole_data: BuildingData = Content.find_building(&"power_pole")
	var stone: ItemData = Content.find_item(&"stone")
	var gravel: ItemData = Content.find_item(&"gravel")
	var consumer := BuildingData.new()
	consumer.id = &"test_consumer"
	consumer.recipe = Content.find_recipe(&"crush_stone")
	consumer.power = -2.0
	consumer.power_connections = 1
	_check("contenido: placa 4 y poste de 4 conexiones", solar_data.power == 4.0 and pole_data.power_connections == 4)

	Simulation.running = false
	WorldState.reset()
	var island: IslandState = WorldState.get_island(&"test_power")
	var solar: PlacedBuilding = island.place(solar_data, Vector2i(0, 0))
	var pole: PlacedBuilding = island.place(pole_data, Vector2i(5, 0))
	var m1: PlacedBuilding = island.place(consumer, Vector2i(8, 0))
	var m2: PlacedBuilding = island.place(consumer, Vector2i(8, 2))
	var m3: PlacedBuilding = island.place(consumer, Vector2i(8, 4))
	for m: PlacedBuilding in [m1, m2, m3]:
		m.input.add_item(stone, 20)

	# 1) Sin cables, una máquina eléctrica no trabaja.
	Simulation.advance(6.0)
	_check("sin red: no trabaja", m1.output.get_total(gravel) == 0)

	# 2) Placa → poste → m1: 4 de 2. Trabaja.
	_check("tiende cables", island.add_cable(solar.id, pole.id) and island.add_cable(pole.id, m1.id))
	Simulation.advance(6.0)
	_check("con red: trabaja", m1.output.get_total(gravel) == 2)

	# 3) Con m2, justo al límite (4 de 4): sigue funcionando.
	island.add_cable(pole.id, m2.id)
	Simulation.advance(6.0)
	_check("al límite: funciona", m2.output.get_total(gravel) == 2 and island.is_powered(m1.id))

	# 4) Con m3 (6 de 4): salta el fusible y nada de la red trabaja.
	island.add_cable(pole.id, m3.id)
	Simulation.advance(0.1)
	_check("sobrecarga: salta el fusible", island.get_network(solar.id).is_tripped())
	var before: int = m1.output.get_total(gravel)
	Simulation.advance(6.0)
	_check("fusible saltado: nada trabaja", m1.output.get_total(gravel) == before and m3.output.get_total(gravel) == 0)

	# 5) Rearmar sin quitar carga: vuelve a saltar.
	island.get_network(solar.id).reset_fuse()
	Simulation.advance(0.1)
	_check("rearmar sin quitar carga: vuelve a saltar", island.get_network(solar.id).is_tripped())

	# 6) Quitar carga y rearmar: vuelve a funcionar.
	island.remove_cable(pole.id, m3.id)
	island.get_network(solar.id).reset_fuse()
	Simulation.advance(3.0)
	_check("quitar carga y rearmar: funciona", m1.output.get_total(gravel) == before + 1)

	# 7) Límites: conexiones ocupadas y distancia.
	var far_pole: PlacedBuilding = island.place(pole_data, Vector2i(30, 0))
	_check("sin conexiones libres: no", not island.can_add_cable(m1.id, solar.id))
	_check("demasiado lejos: no", not island.can_add_cable(pole.id, far_pole.id))

	# 8) Quitar el poste quita sus cables y corta la energía.
	island.remove(pole.id)
	_check("sin poste: sin cables ni energía", island.cables.is_empty() and not island.is_powered(m1.id))

	# 9) Guardar y cargar: cables y fusible vuelven (aquí solo hay contenido del catálogo).
	var saved := IslandState.new()
	var s: PlacedBuilding = saved.place(solar_data, Vector2i(0, 0))
	var p: PlacedBuilding = saved.place(pole_data, Vector2i(4, 0))
	saved.add_cable(s.id, p.id)
	s.fuse_tripped = true
	var restored := IslandState.new()
	restored.load_data(JSON.parse_string(JSON.stringify(saved.to_data())))
	_check("cargada: cable y fusible", restored.cables.size() == 1 and restored.get_network(s.id).is_tripped())

	WorldState.reset()
	Simulation.running = true
	if _failures == 0:
		print("--- Energía: TODO OK ---")
	else:
		print("--- Energía: %d FALLOS ---" % _failures)


func _check(label: String, condition: bool) -> void:
	if condition:
		print("OK    ", label)
	else:
		_failures += 1
		push_error("FALLO " + label)
