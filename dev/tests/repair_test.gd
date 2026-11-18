extends Node
## Prueba de las estructuras por reparar (C4.1, D-115), solo en datos (solo desarrollo).
## Ejecuta con F6 y mira la pestaña Salida: cada comprobación imprime OK o FALLO.
## Usa la ruina de prueba (`content/repair_sites/test_ruin.tres`): 3×1, dos pilares de 2 maderos, un
## dintel de 1 madero y 3 baldosas (C4.2) y un camastro de 2 maderos (la cama, C4).

var _failures: int = 0
var _changed: int = 0
var _completed: int = 0


func _ready() -> void:
	var ruin: RepairSiteData = Content.find_repair_site(&"test_ruin")
	var timber: ItemData = Content.find_item(&"timber")
	var tile: ItemData = Content.find_item(&"stone_tile")
	var crusher: BuildingData = Content.find_building(&"crusher")
	var malachite: VeinData = Content.find_vein(&"malachite_vein")
	_check("ruina en el catálogo, con sus 4 piezas", ruin != null and ruin.pieces.size() == 4
			and ruin.find_piece(&"lintel") == 2 and ruin.find_piece(&"no_existe") == -1)
	_check("la cama es la cama", ruin != null and ruin.pieces[3].action == &"bed")

	Simulation.running = false
	WorldState.reset()
	var island: IslandState = WorldState.get_island(&"test_repair")
	island.repair_changed.connect(func(_origin: Vector2i, _index: int) -> void: _changed += 1)
	island.repair_completed.connect(func(_origin: Vector2i) -> void: _completed += 1)
	var origin := Vector2i(10, 10)

	# 1) Ponerla y que ocupe sus casillas.
	var site: RepairSite = island.add_repair_site(ruin, origin)
	_check("poner la ruina", site != null and site.done_count() == 0 and not site.is_complete())
	_check("ocupa sus 3 casillas", island.repair_site_at(origin) == site and island.repair_site_at(origin + Vector2i(2, 0)) == site
			and island.repair_site_at(origin + Vector2i(3, 0)) == null)
	_check("lo que falta al principio es todo el coste", _same(site.missing(2), {timber: 1, tile: 3}))

	# 2) Bloquea construir, plantar, rocas, palos, vetas, agua y otra estructura encima.
	_check("no se construye encima", island.placement_problem(crusher, origin + Vector2i(1, 0)) == "BUILD_NO_ROOM")
	_check("al lado sí", island.can_place(crusher, origin + Vector2i(0, 1)))
	_check("no se planta encima", not island.can_plant(origin) and not island.add_tree(origin))
	_check("ni rocas ni palos encima", not island.add_rock(origin + Vector2i(1, 0)) and not island.add_sticks(origin + Vector2i(2, 0)))
	_check("ni una veta encima", not island.add_vein(malachite, origin + Vector2i(-1, -1)))
	var water_cells: Array[Vector2i] = [origin]
	_check("ni agua encima", island.add_water(water_cells, Vector2i(0, 1)) == 0)
	_check("ni otra estructura encima", island.add_repair_site(ruin, origin + Vector2i(2, 0)) == null)
	island.bounds = Rect2i(origin, Vector2i(3, 1))
	island.step_nature(IslandState.ROCK_SPAWN_TIME)
	_check("las rocas que aparecen solas no caen en ella", island.rock_count() == 0 and island.sticks_count() == 0)
	island.bounds = Rect2i()

	# 3) Girada: 3×1 pasa a 1×3.
	var turned: RepairSite = island.add_repair_site(ruin, Vector2i(20, 10), 1)
	_check("girada ocupa 1×3", turned != null and island.repair_site_at(Vector2i(20, 12)) == turned
			and island.repair_site_at(Vector2i(21, 10)) == null)

	# 4) Entregar poco a poco (D-115).
	var bag := Inventory.new(10)
	bag.add_item(timber, 1)
	_check("entrega parcial: 1 de 2", island.deliver_repair(origin, 0, bag) == 1 and bag.get_total(timber) == 0
			and _same(site.missing(0), {timber: 1}) and not site.is_piece_done(0))
	_check("sin nada en la mochila no entrega", island.deliver_repair(origin, 0, bag) == 0)
	bag.add_item(timber, 10)
	_check("entrega solo lo que falta", island.deliver_repair(origin + Vector2i(1, 0), 0, bag) == 1 and bag.get_total(timber) == 9
			and site.is_piece_done(0))
	_check("a una pieza completa no se entrega más", island.deliver_repair(origin, 0, bag) == 0 and bag.get_total(timber) == 9)
	_check("pieza que no existe: nada", island.deliver_repair(origin, 7, bag) == 0 and island.deliver_repair(origin, -1, bag) == 0)
	_check("fuera de la estructura: nada", island.deliver_repair(origin + Vector2i(5, 5), 1, bag) == 0)
	# Dintel con maderos pero sin baldosas: entrega el madero y espera las baldosas.
	_check("dintel: entrega el madero sin las baldosas", island.deliver_repair(origin, 2, bag) == 1
			and _same(site.missing(2), {tile: 3}))
	bag.add_item(tile, 2)
	island.deliver_repair(origin, 2, bag)
	_check("dintel: 2 de 3 baldosas", site.delivered_amount(2, tile) == 2 and not site.is_piece_done(2))
	_check("aún no está completa", site.done_count() == 1 and _completed == 0)

	# 5) Guardar y cargar a medias: vuelve con lo entregado y sigue ocupando sus casillas.
	var restored := IslandState.new()
	restored.load_data(JSON.parse_string(JSON.stringify(island.to_data())))
	var restored_site: RepairSite = restored.repair_site_at(origin + Vector2i(2, 0))
	_check("cargada: vuelven las dos estructuras", restored.repair_sites.size() == 2
			and restored.repair_site_at(Vector2i(20, 12)) != null and restored.repair_site_at(Vector2i(20, 12)).rotation == 1)
	_check("cargada: con lo entregado", restored_site != null and restored_site.is_piece_done(0)
			and restored_site.delivered_amount(0, timber) == 2 and _same(restored_site.missing(2), {tile: 1}))
	_check("cargada: sigue bloqueando", not restored.can_place(crusher, origin))

	# 6) Completar: aviso una sola vez.
	_changed = 0
	bag.add_item(tile, 5)
	island.deliver_repair(origin, 2, bag)
	island.deliver_repair(origin, 1, bag)
	_check("con la cama sin hacer, aún no está completa", not site.is_complete() and _completed == 0)
	island.deliver_repair(origin, 3, bag)
	_check("completa", site.is_complete() and site.done_count() == 4)
	_check("aviso de completa una sola vez, y uno por entrega", _completed == 1 and _changed == 3)
	_check("completa: no acepta más", island.deliver_repair(origin, 1, bag) == 0 and _completed == 1)

	# 7) Datos dañados o desconocidos se ignoran sin romper la carga; lo de más se recorta.
	var damaged := IslandState.new()
	damaged.load_data({"repair_sites": [
		{"id": "no_existe", "x": 0, "y": 0},
		42,
		{"id": "test_ruin", "x": 0, "y": 0, "r": 0, "d": [{"timber": 99, "stone_tile": 5, "no_existe": 1}, "basura", {"timber": "x"}]},
		{"id": "test_ruin", "x": 1, "y": 0},   # se solapa con la anterior
	]})
	var kept: RepairSite = damaged.repair_site_at(Vector2i(0, 0))
	_check("dañados: queda solo la válida", damaged.repair_sites.size() == 1 and kept != null)
	_check("dañados: lo de más se recorta y lo que no pide se ignora", kept != null and kept.delivered_amount(0, timber) == 2
			and kept.delivered_amount(0, tile) == 0 and kept.delivered_amount(2, timber) == 0)

	# 8) Casillas bloqueadas (C4): una estructura de 3×3 que solo ocupa su borde deja libre el centro.
	var ring := RepairSiteData.new()
	ring.id = &"test_ring"
	ring.size = Vector2i(3, 3)
	ring.blocked_cells = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, 1), Vector2i(2, 1),
			Vector2i(0, 2), Vector2i(2, 2)]   # la (1, 2), abajo en el centro, es la entrada
	var ring_site: RepairSite = island.add_repair_site(ring, Vector2i(30, 30))
	_check("bloqueadas: se pone", ring_site != null and ring_site.cells().size() == 7)
	_check("bloqueadas: la pared, ocupada", island.repair_site_at(Vector2i(30, 30)) == ring_site
			and not island.can_plant(Vector2i(32, 32)))
	_check("bloqueadas: el centro y la entrada, libres", island.repair_site_at(Vector2i(31, 31)) == null
			and island.can_place(crusher, Vector2i(31, 31)) and island.can_plant(Vector2i(31, 32)))
	var turned_ring: RepairSite = island.add_repair_site(ring, Vector2i(40, 30), 1)
	_check("bloqueadas: girada, la entrada pasa al oeste", turned_ring != null
			and island.repair_site_at(Vector2i(40, 31)) == null and island.repair_site_at(Vector2i(42, 31)) == turned_ring)

	# 9) Punto de reaparición (C4): se guarda con la partida.
	WorldState.set_respawn(&"test_repair", Vector3(1.5, 0.05, -2.0), 0.5)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(WorldState.to_data()))
	WorldState.reset()
	_check("reaparición: sin partida, no hay", not WorldState.has_respawn(&"test_repair"))
	WorldState.load_data(saved)
	_check("reaparición: vuelve al cargar", WorldState.has_respawn(&"test_repair") and not WorldState.has_respawn(&"otra")
			and WorldState.respawn_position.is_equal_approx(Vector3(1.5, 0.05, -2.0)) and is_equal_approx(WorldState.respawn_rotation_y, 0.5))

	WorldState.reset()
	Simulation.running = true
	if _failures == 0:
		print("--- Estructuras por reparar: TODO OK ---")
	else:
		print("--- Estructuras por reparar: %d FALLOS ---" % _failures)


## ¿Mismo contenido? (compara ítem a ítem: un diccionario tipado y uno sin tipo no siempre dan == entre sí)
func _same(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for key: Variant in b:
		if not a.has(key) or int(a[key]) != int(b[key]):
			return false
	return true


func _check(label: String, condition: bool) -> void:
	if condition:
		print("OK    ", label)
	else:
		_failures += 1
		push_error("FALLO " + label)
