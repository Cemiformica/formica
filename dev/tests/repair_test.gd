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
	# El refugio (C5.5): sus cuatro piezas, la cama, y un nodo en el modelo por pieza más el punto de reaparición.
	var shelter: RepairSiteData = Content.find_repair_site(&"shelter")
	_check("refugio en el catálogo, con sus 5 piezas", shelter != null and shelter.pieces.size() == 5
			and shelter.find_piece(&"props") == 0 and shelter.find_piece(&"bed") == 3 and shelter.find_piece(&"hatch") == 4)
	_check("la cama del refugio es la cama", shelter != null and shelter.pieces[3].action == &"bed")
	# La sala deja libre un cuadrado de 4 × 4 casillas (columnas 2–5, filas 1–4) para el banco y los arcones (César).
	var room_free: bool = shelter != null
	for x: int in range(2, 6):
		for y: int in range(1, 5):
			room_free = room_free and not shelter.blocked_cells.has(Vector2i(x, y))
	_check("la sala del refugio deja libre un cuadrado de 4 × 4 casillas", room_free)
	var rope_item: ItemData = Content.find_item(&"rope")
	_check("la trampilla pide 1 madero, 2 cuerdas y 2 de madera, y gira la tapa y la palanca", shelter != null
			and shelter.pieces[4].cost.get(timber, 0) == 1 and shelter.pieces[4].cost.get(rope_item, 0) == 2
			and shelter.pieces[4].toggle_nodes.size() == 2 and shelter.pieces[4].toggle_rotations.size() == 2)
	var make_rope: RecipeData = Content.find_recipe(&"make_rope")
	_check("receta de la cuerda: 3 de fibra → 1 cuerda", make_rope != null
			and make_rope.inputs.get(Content.find_item(&"fiber"), 0) == 3 and make_rope.outputs.get(rope_item, 0) == 1)
	if shelter != null and shelter.scene != null:
		var model: Node = shelter.scene.instantiate()
		var all_nodes: bool = model.find_child("spawn_point", true, false) != null
		for piece: RepairPieceData in shelter.pieces:
			all_nodes = all_nodes and model.find_child(String(piece.node_name), true, false) != null
			if piece.aim_node != &"":
				all_nodes = all_nodes and model.find_child(String(piece.aim_node), true, false) != null
			for node_name: StringName in piece.toggle_nodes:
				all_nodes = all_nodes and model.find_child(String(node_name), true, false) != null
		for n: int in 2:
			all_nodes = all_nodes and model.find_child("rope_a_%d" % n, true, false) != null \
					and model.find_child("rope_b_%d" % n, true, false) != null
		# Haz de luz dentro de la trampilla y candil con su llama (D-180).
		var hatch_node: Node = model.find_child("piece_hatch", true, false)
		var shaft_top: Node = model.find_child("light_shaft_top", true, false)
		var lights_ok: bool = hatch_node != null and shaft_top != null and hatch_node.is_ancestor_of(shaft_top) \
				and model.find_child("light_shaft_bottom", true, false) != null \
				and model.find_child("lantern_light", true, false) != null \
				and model.find_child("lantern_flame", true, false) is MeshInstance3D \
				and model.find_child("hearth_light", true, false) != null \
				and model.find_child("hearth_flame_0", true, false) is MeshInstance3D \
				and model.find_child("hearth_embers", true, false) is MeshInstance3D
		model.free()
		_check("el modelo trae el haz de luz (en la trampilla), el candil y el fogón con sus llamas", lights_ok)
		_check("el modelo del refugio tiene un nodo por pieza (con el tirador, la bisagra, la palanca y las cuerdas) y su spawn_point", all_nodes)
	# La trampilla: no se abre hasta estar completa; después se abre y se cierra, y abierta se guarda.
	if shelter != null:
		var hatch_island: IslandState = IslandState.new()
		var hatch_site: RepairSite = hatch_island.add_repair_site(shelter, Vector2i(40, 40))
		var hatch: int = shelter.find_piece(&"hatch")
		var toggles: Array[int] = []
		hatch_island.repair_toggled.connect(func(_o: Vector2i, index: int) -> void: toggles.append(index))
		_check("la trampilla sin reparar no se abre", hatch_site != null and not hatch_island.toggle_repair_piece(Vector2i(40, 40), hatch))
		var stock := Inventory.new(4)
		stock.add_item(timber, 1)
		stock.add_item(Content.find_item(&"rope"), 2)
		stock.add_item(Content.find_item(&"wood"), 2)
		hatch_island.deliver_repair(Vector2i(40, 40), hatch, stock)
		var opened_ok: bool = hatch_island.toggle_repair_piece(Vector2i(40, 40), hatch) and hatch_site.is_open(hatch)
		_check("reparada, se abre (y avisa)", opened_ok and toggles == [hatch])
		var hatch_restored: RepairSite = RepairSite.from_data(hatch_site.to_data())
		_check("abierta se guarda y se carga abierta", hatch_restored != null and hatch_restored.is_open(hatch)
				and not hatch_restored.is_open(0))
		_check("y se vuelve a cerrar", hatch_island.toggle_repair_piece(Vector2i(40, 40), hatch) and not hatch_site.is_open(hatch))
		_check("la cama no se abre", not hatch_island.toggle_repair_piece(Vector2i(40, 40), shelter.find_piece(&"bed")))
		# Luces (D-191): el candil y el fogón solo se encienden con el refugio completo; el candil, solo la primera vez.
		_check("el refugio tiene el candil (se enciende solo) y el fogón (hoguera)", shelter.lights.size() == 2
				and shelter.lights[0].id == &"lantern" and shelter.lights[0].lit_on_complete
				and shelter.lights[1].id == &"hearth" and shelter.lights[1].fire and not shelter.lights[1].lit_on_complete)
		_check("sin completar el refugio, el fogón no se enciende", not hatch_island.switch_repair_light(Vector2i(40, 40), 1))
		var everything := Inventory.new(10)
		for item_id: StringName in [&"timber", &"stone_tile", &"rope", &"wood"]:
			everything.add_item(Content.find_item(item_id), 20)
		for i: int in shelter.pieces.size():
			hatch_island.deliver_repair(Vector2i(40, 40), i, everything)
		_check("al completarlo, el candil se enciende solo y el fogón no", hatch_site.is_complete()
				and hatch_site.is_lit(0) and not hatch_site.is_lit(1))
		var switched: Array[int] = []
		hatch_island.repair_light_switched.connect(func(_o: Vector2i, index: int) -> void: switched.append(index))
		_check("el fogón se enciende con E (y avisa)", hatch_island.switch_repair_light(Vector2i(40, 40), 1)
				and hatch_site.is_lit(1) and switched == [1])
		_check("y el candil se apaga", hatch_island.switch_repair_light(Vector2i(40, 40), 0) and not hatch_site.is_lit(0))
		var lit_restored: RepairSite = RepairSite.from_data(JSON.parse_string(JSON.stringify(hatch_site.to_data())))
		_check("las luces se guardan como estaban", lit_restored != null and not lit_restored.is_lit(0) and lit_restored.is_lit(1))

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

	# 9) Punto de reaparición (C4): se guarda con la partida, aparte de dónde estaba el jugador (C5.5, César):
	# cargar te deja donde guardaste; la cama solo cuenta al morir.
	WorldState.set_respawn(&"test_repair", Vector3(1.5, 0.05, -2.0), 0.5)
	WorldState.player_position = Vector3(20.0, 0.1, 7.0)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(WorldState.to_data()))
	WorldState.reset()
	_check("reaparición: sin partida, no hay", not WorldState.has_respawn(&"test_repair"))
	WorldState.load_data(saved)
	_check("reaparición: vuelve al cargar", WorldState.has_respawn(&"test_repair") and not WorldState.has_respawn(&"otra")
			and WorldState.respawn_position.is_equal_approx(Vector3(1.5, 0.05, -2.0)) and is_equal_approx(WorldState.respawn_rotation_y, 0.5))
	_check("reaparición: cargar te deja donde guardaste, no en la cama",
			WorldState.player_position.is_equal_approx(Vector3(20.0, 0.1, 7.0)))
	# Dormir en otra cama cambia el punto (como en Minecraft).
	WorldState.set_respawn(&"test_repair", Vector3(9.0, 0.05, 4.0), 1.0)
	_check("reaparición: la última cama manda", WorldState.respawn_position.is_equal_approx(Vector3(9.0, 0.05, 4.0)))

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
