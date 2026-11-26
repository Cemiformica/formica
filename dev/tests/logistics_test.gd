extends Node
## Prueba de cintas y conexiones (B2.5a), solo en datos (solo desarrollo).
## Ejecuta con F6 y mira la pestaña Salida: cada comprobación imprime OK o FALLO.
##
## Plano de la prueba (x hacia la derecha = este; las cintas miran al este, giro 1):
##   fila 0:  [A]→[b1]→[b2]→[b3]→ (nada)      [c]→[B]
##             0    1    2    3                  5   6
##   fila 4:  [D][E]   dos trituradoras pegadas, salida de D frente a entrada de E
##
## Cintas en L, T y X (C2b, D-118), más abajo (giro: 0 = mira al norte, 1 = al este, 2 = al sur):
##   fila 12: L        p (0,12)→ entra por el costado oeste de q (1,12)↑
##   filas 14–15:      dos cintas paralelas al este: no se unen
##   filas 17–18: T que divide: t0 (0,18)→ sale recta a t1 (1,18)→ y por su costado norte a t2 (0,17)↑
##   filas 21–22: T que junta: u0 (0,22)→ por detrás y u1 (1,21)↓ por el costado norte de m (1,22)→ m2 → m3 → m4
##   fila 26:  trituradora k (0,26) → costado oeste de v (1,26)↑; cinta w (5,26)↑ → por su costado este → trituradora z (6,26)
##   filas 29–30: T con el cruce mirando a un lado (captura de César): l0 (0,30)↑ entra por el costado de
##             j (0,29)→, que sale por delante a e (1,29)→ y por su trasera a la trasera de wb (−1,29)←

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

	# 2) Máquina → cintas: 60 s = 20 ciclos. Caben `belt_capacity` por cinta (3 desde la sesión 28) en las 3
	#    cintas; el resto espera en la salida de A.
	var full: int = 3 * conveyor.belt_capacity
	a.input.add_item(stone, 20)
	Simulation.advance(60.0)
	var on_belts: int = b1.belt_items.size() + b2.belt_items.size() + b3.belt_items.size()
	_check("cintas llenas: %d ítems" % full, on_belts == full)
	_check("el resto espera en la salida de A (%d)" % (20 - full), a.output.get_total(gravel) == 20 - full)
	_check("el de delante está parado al final", is_equal_approx(b3.belt_progress[0], 1.0))

	# 3) Cinta → máquina: piedra puesta en c entra en B (1 casilla a 0,5/s = 2 s, con margen).
	c.accept(stone)
	Simulation.advance(3.0)
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

	# 8) Cinta → cinta: lo que el ítem se pasa del final en un paso no se pierde; sigue en la siguiente.
	var x: PlacedBuilding = island.place(conveyor, Vector2i(0, 8), 1)
	var y: PlacedBuilding = island.place(conveyor, Vector2i(1, 8), 1)
	x.accept(stone)
	x.belt_progress[0] = 0.95
	Simulation.advance(Simulation.TICK)
	var expected: float = 0.95 + conveyor.belt_speed * Simulation.TICK - 1.0
	_check("unión: el ítem pasa a la siguiente cinta", x.belt_items.is_empty() and y.belt_items.size() == 1)
	_check("unión: sigue donde iba, no en 0", y.belt_items.size() == 1 and is_equal_approx(y.belt_progress[0], expected))

	# 9) L: el frente de p entra por el costado oeste de q (la cinta gira).
	var p: PlacedBuilding = island.place(conveyor, Vector2i(0, 12), 1)
	var q: PlacedBuilding = island.place(conveyor, Vector2i(1, 12), 0)
	_check("L: p conecta con q por el costado", _linked(island, p, q))
	p.accept(stone)
	Simulation.advance(5.0) # dos casillas a 0,5/s = 4 s, con margen
	_check("L: el ítem gira y llega al final de q", q.belt_items.size() == 1 and is_equal_approx(q.belt_progress[0], 1.0))
	_check("L: q sabe que entró por el oeste", q.belt_entries.size() == 1 and q.belt_entries[0] == PortData.PortSide.WEST)

	# 10) Paralelas: dos cintas una al lado de la otra no se unen por los costados.
	var r: PlacedBuilding = island.place(conveyor, Vector2i(0, 14), 1)
	var s: PlacedBuilding = island.place(conveyor, Vector2i(0, 15), 1)
	_check("paralelas: no se unen", not _linked(island, r, s) and not _linked(island, s, r))

	# 11) T que divide: t0 sale recta a t1 y por un costado a t2, por turnos.
	var t0: PlacedBuilding = island.place(conveyor, Vector2i(0, 18), 1)
	var t1: PlacedBuilding = island.place(conveyor, Vector2i(1, 18), 1)
	var t2: PlacedBuilding = island.place(conveyor, Vector2i(0, 17), 0)
	_check("T: t0 tiene dos salidas", island.get_links_from(t0.id).size() == 2 and _linked(island, t0, t1) and _linked(island, t0, t2))
	_feed(t0, stone, 2, conveyor.ports[0])
	_check("T: uno a cada lado", t1.belt_items.size() == 1 and t2.belt_items.size() == 1)
	# t1 llena: el siguiente, aunque le toque a t1, va a t2.
	for _i: int in 200:
		if t1.belt_items.size() >= conveyor.belt_capacity:
			break
		if t1.can_accept(stone, conveyor.ports[0]):
			t1.accept(stone)
		Simulation.advance(Simulation.TICK)
	_feed(t0, stone, 1, conveyor.ports[0])
	_check("T: con una rama llena, va a la otra", t2.belt_items.size() == 2 and t0.belt_items.is_empty())

	# 12) T que junta: piedra por detrás y grava por un costado entran por turnos.
	var u0: PlacedBuilding = island.place(conveyor, Vector2i(0, 22), 1)
	var u1: PlacedBuilding = island.place(conveyor, Vector2i(1, 21), 2)
	var m: PlacedBuilding = island.place(conveyor, Vector2i(1, 22), 1)
	var after: Array[PlacedBuilding] = []
	for x_cell: int in [2, 3, 4]:
		after.append(island.place(conveyor, Vector2i(x_cell, 22), 1))
	_check("junta: m tiene dos entradas", island.get_links_into(m.id).size() == 2)
	for _i: int in 300:
		if u0.can_accept(stone, conveyor.ports[0]):
			u0.accept(stone)
		if u1.can_accept(gravel, conveyor.ports[0]):
			u1.accept(gravel)
		Simulation.advance(Simulation.TICK)
	var stones: int = 0
	var gravels: int = 0
	for belt: PlacedBuilding in after:
		for item: ItemData in belt.belt_items:
			if item == stone:
				stones += 1
			elif item == gravel:
				gravels += 1
	# Las tres cintas de después, llenas (3 × belt_capacity), con piedra y grava alternadas: como mucho uno más.
	_check("junta: por turnos (%d en total, alternados)" % full, stones + gravels == full and absi(stones - gravels) <= 1)

	# 13) Máquina → costado de una cinta, y cinta → máquina por un costado.
	var k: PlacedBuilding = island.place(crusher, Vector2i(0, 26))
	var v: PlacedBuilding = island.place(conveyor, Vector2i(1, 26), 0)
	var w: PlacedBuilding = island.place(conveyor, Vector2i(5, 26), 0)
	var z: PlacedBuilding = island.place(crusher, Vector2i(6, 26))
	_check("costado: la trituradora echa a la cinta", _linked(island, k, v))
	_check("costado: la cinta mete en la trituradora", _linked(island, w, z))
	k.output.add_item(gravel, 1)
	w.accept(stone)
	Simulation.advance(3.0)
	_check("costado: llega la grava a v", v.belt_items.size() == 1 and k.output.get_total(gravel) == 0)
	_check("costado: entra la piedra en z", z.input.get_total(stone) == 1 and w.belt_items.is_empty())

	# 15) T con el cruce mirando a un lado: trasera con trasera, el que recibe le pasa al que no.
	var l0: PlacedBuilding = island.place(conveyor, Vector2i(0, 30), 0)
	var j: PlacedBuilding = island.place(conveyor, Vector2i(0, 29), 1)
	var e2: PlacedBuilding = island.place(conveyor, Vector2i(1, 29), 1)
	var wb: PlacedBuilding = island.place(conveyor, Vector2i(-1, 29), 3)
	_check("cruce de lado: j sale a e y, por la trasera, a wb", _linked(island, j, e2) and _linked(island, j, wb)
			and _linked(island, l0, j) and not _linked(island, wb, j))
	_feed(l0, stone, 2, conveyor.ports[0])
	Simulation.advance(3.0)
	_check("cruce de lado: uno a cada lado", e2.belt_items.size() == 1 and wb.belt_items.size() == 1)

	# 16) Caudal (sesión 28): una línea de 4 cintas siempre alimentada y vaciada al final da belt_speed ×
	#     belt_capacity ítems por segundo (90/min), sin perder un paso en cada unión. 20 s tras 10 de arranque.
	var line: Array[PlacedBuilding] = []
	for x_cell: int in 4:
		line.append(island.place(conveyor, Vector2i(x_cell, 33), 1))
	var delivered: int = 0
	for tick: int in 300:
		if line[0].can_accept(stone, conveyor.ports[0]):
			line[0].accept(stone, line[0].belt_entry_slack())
		Simulation.advance(Simulation.TICK)
		var last: PlacedBuilding = line[line.size() - 1]
		if last.peek_output(conveyor.ports[1]) != null:
			last.take_output(stone)
			if tick >= 100:
				delivered += 1
	var expected_count: int = roundi(conveyor.belt_speed * conveyor.belt_capacity * 20.0)
	_check("caudal: %d ítems en 20 s (esperados %d)" % [delivered, expected_count], absi(delivered - expected_count) <= 1)

	# 14) Guardar y cargar: las uniones por los costados vuelven.
	var reloaded := IslandState.new()
	reloaded.load_data(JSON.parse_string(JSON.stringify(island.to_data())))
	_check("cargada: mismas conexiones con los costados", reloaded.get_links().size() == island.get_links().size())

	WorldState.reset()
	Simulation.running = true
	if _failures == 0:
		print("--- Logística: TODO OK ---")
	else:
		print("--- Logística: %d FALLOS ---" % _failures)


## ¿Hay una conexión de `from` a `to`?
func _linked(island: IslandState, from: PlacedBuilding, to: PlacedBuilding) -> bool:
	for link: Dictionary in island.get_links_from(from.id):
		if link["to"] == to:
			return true
	return false


## Mete `count` ítems en la cinta `belt`, uno cada vez que haya hueco, y espera a que se vacíe (máx. 20 s).
func _feed(belt: PlacedBuilding, item: ItemData, count: int, back: PortData) -> void:
	var fed: int = 0
	for _i: int in 200:
		if fed < count and belt.can_accept(item, back):
			belt.accept(item)
			fed += 1
		Simulation.advance(Simulation.TICK)
		if fed == count and belt.belt_items.is_empty():
			return


func _check(label: String, condition: bool) -> void:
	if condition:
		print("OK    ", label)
	else:
		_failures += 1
		push_error("FALLO " + label)
