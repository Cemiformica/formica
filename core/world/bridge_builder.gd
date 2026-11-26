class_name BridgeBuilder
extends RefCounted
## Pasarelas reparables del plano (C5.6b, D-187; sesión 29): una por cada vado (`s` en `isla_alba.txt`), de orilla a
## orilla por encima del río, a lo largo de las casillas del vado. Se genera en código, como la escala: dos caballetes
## de maderos sobre piedras planas del fondo, un tablero de tablones de través (el ítem tablón, César) sobre dos largueros
## y un pasamanos de cuerda a cada lado, atado a postes-hormiga como los de la barandilla.
## Tres piezas (costes de César): los caballetes (2 maderos), el tablero (6 tablones) y el pasamanos (2 cuerdas + 2
## maderos). Las piedras del vado son la base: están siempre y chocan (son bajas, se pasa por encima andando por el agua).
## Mientras no esté reparada, la pasarela vieja está deshecha («broken_wreck»: no choca y se quita al completarla): un
## caballete volcado en el río, tablones encallados en las piedras y los tocones de los postes de la orilla oeste.
## Las estructuras se crean al poner el plano y se registran en `Content` por su id («bridge_0»…), para que el guardado
## las encuentre.
## Dónde tocar: las constantes (medidas en metros) y `_model`.

const POST_MODEL: PackedScene = preload("res://assets/models/props/fence.glb")
const PALETTE_MATERIAL: Material = preload("res://assets/materials/palette.tres")
const ID_PREFIX: String = "bridge_"
const PURPOSE: StringName = &"bridge"
const FORD_CHAR: String = "s"
## Lo que entra el tablero en cada orilla, desde el borde del agua (m).
const BANK_REACH: float = 0.9
## Ancho del tablero y lo que sube su cara de arriba sobre la orilla más alta de las dos.
const DECK_HALF: float = 0.5
const DECK_LIFT: float = 0.2
## Por encima de la superficie del agua, como mínimo (m).
const WATER_CLEAR: float = 0.22
## Tablones de través: ancho a lo largo de la pasarela, grueso y hueco entre uno y otro.
const PLANK_WIDTH: float = 0.18
const PLANK_THICK: float = 0.035
const PLANK_GAP: float = 0.02
## Largueros (dos vigas a lo largo, bajo los tablones): a ±BEAM_SIDE del centro, de sección BEAM_HALF × 2.
const BEAM_SIDE: float = 0.33
const BEAM_HALF: float = 0.05
## Caballetes: el cabezal (viga de través bajo los largueros) llega a ±HEAD_HALF; las patas, de sección LEG_HALF × 2,
## bajan abiertas de ±LEG_TOP a ±LEG_FOOT hasta una piedra plana del fondo.
const HEAD_HALF: float = 0.64
const LEG_TOP: float = 0.48
const LEG_FOOT: float = 0.62
const LEG_HALF: float = 0.045
## Piedras del vado: alto sobre el fondo (bajas: se pasa andando por encima) y radio.
const STONE_HEIGHT: float = 0.22
const STONE_RADIUS: float = 0.22
## Durmientes: un bloque de madera en cada orilla que sostiene la punta de los largueros y los postes de los extremos, a
## SLEEPER_IN de cada extremo.
const SLEEPER_IN: float = 0.3
## Postes del pasamanos: a ±POST_SIDE del centro (por fuera del tablero), sobre los durmientes y los cabezales de los
## caballetes; las cuerdas, atadas a POST_TIE sobre su pie (el cuello del poste, a la altura del tronco alto de la
## barandilla) y con ROPE_SAG de comba.
const POST_SIDE: float = 0.58
const POST_TIE: float = 0.71
## Los postes de la barandilla, más pequeños en la pasarela (César: ocho tan juntos tapaban el tablero). La cuerda se ata
## a la misma altura relativa (POST_TIE × POST_SCALE).
const POST_SCALE: float = 0.8
const ROPE_HALF: float = 0.016
const ROPE_SAG: float = 0.06
## Cuadritos de la paleta (fila, columna), como `items_blockout.py`: madera labrada clara y oscura, testa, corteza,
## piedra y esparto.
const PLANK_SWATCHES: Array[Vector2i] = [Vector2i(0, 2), Vector2i(0, 2), Vector2i(0, 1), Vector2i(0, 4)]
const TIMBER_SWATCH := Vector2i(0, 2)
const DARK_SWATCH := Vector2i(0, 4)
const STUMP_SWATCH := Vector2i(0, 6)
const STONE_SWATCHES: Array[Vector2i] = [Vector2i(1, 4), Vector2i(1, 3), Vector2i(1, 6)]
const ROPE_SWATCH := Vector2i(0, 1)


## Las pasarelas del plano de `island`, sin poner aún: una lista de {"data": RepairSiteData, "origin": Vector2i}.
## Registra cada `data` en `Content`.
static func build(island: IslandState) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var layout: IslandLayout = island.layout
	if layout == null:
		return result
	var fords: Array[Vector2i] = ford_cells(layout)
	if fords.is_empty():
		return result
	var timber: ItemData = Content.find_item(&"timber")
	var plank: ItemData = Content.find_item(&"plank")
	var rope: ItemData = Content.find_item(&"rope")
	var model: Node3D = POST_MODEL.instantiate() as Node3D
	var post: Node3D = model.find_child("fence_post", true, false) as Node3D
	var all_groups: Array[Array] = LadderBuilder.groups(fords)
	for index: int in all_groups.size():
		var cells: Array[Vector2i] = []
		cells.assign(all_groups[index])
		var spot: Dictionary = measure(layout, cells)
		if spot.is_empty():
			push_warning("BridgeBuilder: el vado de %s no tiene orilla a los dos lados" % cells[0])
			continue
		var covered: Array[Vector2i] = _covered_cells(spot)
		var min_cell: Vector2i = covered[0]
		var max_cell: Vector2i = covered[0]
		for cell: Vector2i in covered:
			min_cell = min_cell.min(cell)
			max_cell = max_cell.max(cell)
		var data := RepairSiteData.new()
		data.id = StringName(ID_PREFIX + str(index))
		data.name_key = "REPAIR_BRIDGE"
		data.size = max_cell - min_cell + Vector2i.ONE
		for cell: Vector2i in covered:
			data.blocked_cells.append(cell - min_cell)
		data.exact_collision = true   # se anda por encima del tablero
		data.footstep_surface = &"wood"
		data.purpose = PURPOSE
		var center: Vector3 = GridMath.footprint_center(min_cell, data.size, 0, island.ground_height(min_cell))
		data.scene = _model(layout, spot, center, post)
		var along_x: bool = absf(Vector2(spot["dir"]).x) > 0.5
		for entry: Array in [["trestles", "REPAIR_PIECE_BRIDGE_TRESTLES", {timber: 2}, Vector3(0.6, 0.7, 1.4)],
				["deck", "REPAIR_PIECE_BRIDGE_DECK", {plank: 6}, Vector3.ZERO],
				["rails", "REPAIR_PIECE_BRIDGE_RAILS", {rope: 2, timber: 2}, Vector3(0.5, 0.8, 1.5)]]:
			var piece := RepairPieceData.new()
			piece.id = StringName("bridge_%s" % entry[0])
			piece.name_key = entry[1]
			piece.node_name = StringName("piece_bridge_%s" % entry[0])
			var cost: Dictionary = entry[2]
			for item: ItemData in cost:
				piece.cost[item] = cost[item]
			# El pasamanos y los caballetes rodean el tablero: se apunta a un trozo de cada uno (los postes de la orilla
			# oeste, el primer caballete) para que sus cajas no tapen la del tablero.
			var aim: Vector3 = entry[3]
			if aim != Vector3.ZERO:
				piece.aim_node = StringName("aim_bridge_%s" % entry[0])
				piece.aim_size = aim if along_x else Vector3(aim.z, aim.y, aim.x)
			data.pieces.append(piece)
		Content.register_repair_site(data)
		result.append({"data": data, "origin": min_cell})
	model.free()
	return result


## Casillas de vado del plano (`s`). No sale con `IslandLayout.cells_of`, que solo guarda los objetos del plano: el vado
## es suelo (agua del río), así que se busca casilla a casilla.
static func ford_cells(layout: IslandLayout) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for y: int in layout.size.y:
		for x: int in layout.size.x:
			if layout.char_at(Vector2i(x, y)) == FORD_CHAR:
				result.append(Vector2i(x, y))
	return result


## Dónde va la pasarela de estas casillas de vado: {"origin": punto del mundo en el centro del ancho, al principio del
## tablero (a la altura del agua), "dir": a lo largo (eje de la cuadrícula), "length": del principio al final (m),
## "water": dónde empieza y acaba el agua a lo largo (m desde el origen), "deck": altura de la cara de arriba del tablero
## (m del mundo), "surface": la del agua}. Vacío si a algún lado no hay tierra.
## El vado va de orilla a orilla: la pasarela sigue la fila de casillas del vado (si es una sola, de través al río).
static func measure(layout: IslandLayout, cells: Array[Vector2i]) -> Dictionary:
	if cells.is_empty():
		return {}
	var min_cell: Vector2i = cells[0]
	var max_cell: Vector2i = cells[0]
	for cell: Vector2i in cells:
		min_cell = min_cell.min(cell)
		max_cell = max_cell.max(cell)
	var span: Vector2i = max_cell - min_cell
	var dir := Vector2.RIGHT
	if span.y > span.x:
		dir = Vector2.DOWN
	elif span == Vector2i.ZERO:
		var flow: Variant = layout.water_flow(cells[0])
		if flow is Vector2i and (flow as Vector2i).x != 0:
			dir = Vector2.DOWN   # el río corre de lado: se cruza de norte a sur
	var side := Vector2(-dir.y, dir.x)
	var middle: Vector2 = (Vector2(min_cell) + Vector2(max_cell) + Vector2.ONE) * 0.5
	var first: float = Vector2(min_cell).dot(dir)            # dónde empieza el agua, a lo largo
	var last: float = Vector2(max_cell).dot(dir) + 1.0       # dónde acaba
	# Tierra a los dos lados: la casilla de antes del vado y la de después.
	var before := Vector2i((Vector2(min_cell) - dir).floor())
	var after := Vector2i((Vector2(max_cell) + dir).floor())
	if not layout.is_land(before) or not layout.is_land(after):
		return {}
	var start: float = first - BANK_REACH
	var length: float = last - first + 2.0 * BANK_REACH
	var at: Vector2 = side * middle.dot(side) + dir * start
	var surface: float = IslandLayout.level_height(layout.level(cells[0]))
	var bank_a: float = LadderBuilder._drawn_height(layout, at.x + dir.x * SLEEPER_IN, at.y + dir.y * SLEEPER_IN)
	var end: Vector2 = at + dir * (length - SLEEPER_IN)
	var bank_b: float = LadderBuilder._drawn_height(layout, end.x, end.y)
	var deck: float = maxf(maxf(bank_a, bank_b) + DECK_LIFT, surface + WATER_CLEAR)
	return {"origin": Vector3(at.x, surface, at.y), "dir": dir, "length": length,
			"water": Vector2(first - start, last - start), "deck": deck, "surface": surface}


## Casillas que ocupa (bloquean construir, plantar, rocas, palos y césped): el tablero y los postes de los lados.
static func _covered_cells(spot: Dictionary) -> Array[Vector2i]:
	var origin: Vector3 = spot["origin"]
	var dir: Vector2 = spot["dir"]
	var side := Vector2(-dir.y, dir.x)
	var cells: Array[Vector2i] = []
	var along: float = 0.05
	while along <= float(spot["length"]) - 0.05:
		var across: float = -(POST_SIDE + 0.1)
		while across <= POST_SIDE + 0.1 + 0.001:
			var p: Vector2 = Vector2(origin.x, origin.z) + dir * along + side * across
			var cell := Vector2i(floori(p.x), floori(p.y))
			if not cells.has(cell):
				cells.append(cell)
			across += 0.2
		along += 0.2
	return cells


## El modelo: un marco con +X a lo largo de la pasarela y +Z a un lado, con las piedras del vado («ford_stones», la base),
## las tres piezas («piece_bridge_trestles», «…_deck», «…_rails»), sus zonas de apuntar («aim_bridge_…») y la pasarela
## vieja («broken_wreck»).
static func _model(layout: IslandLayout, spot: Dictionary, center: Vector3, post: Node3D) -> PackedScene:
	var root := Node3D.new()
	root.name = "bridge"
	var frame := Node3D.new()
	frame.name = "bridge_frame"
	var dir: Vector2 = spot["dir"]
	var origin: Vector3 = spot["origin"]
	frame.position = origin - center
	frame.rotation.y = atan2(-dir.y, dir.x)   # el +X del marco, a lo largo de la pasarela
	root.add_child(frame)
	var basis: Basis = frame.basis
	var length: float = spot["length"]
	var water: Vector2 = spot["water"]
	var deck_top: float = float(spot["deck"]) - origin.y
	var beam_top: float = deck_top - PLANK_THICK
	var head_top: float = beam_top - 2.0 * BEAM_HALF
	# Caballetes a un tercio y a dos tercios del agua.
	var trestles: Array[float] = [lerpf(water.x, water.y, 1.0 / 3.0), lerpf(water.x, water.y, 2.0 / 3.0)]
	var ground := func(at_along: float, at_across: float) -> float:
		return LadderBuilder._local_ground(layout, origin, basis, Vector3(at_along, 0.0, at_across))

	# --- Base: piedras planas del vado, bajo cada pata y unas cuantas más sueltas ---
	var stones := MeshInstance3D.new()
	stones.name = "ford_stones"
	var tool := LadderBuilder._begin()
	var stone_spots: Array[Vector2] = []
	for t: float in trestles:
		stone_spots.append(Vector2(t, -LEG_FOOT))
		stone_spots.append(Vector2(t, LEG_FOOT))
	stone_spots.append_array([Vector2(water.x + 0.35, 0.15), Vector2(lerpf(water.x, water.y, 0.5), -0.1),
			Vector2(water.y - 0.4, 0.2)])
	for k: int in stone_spots.size():
		var s: Vector2 = stone_spots[k]
		var bed: float = float(ground.call(s.x, s.y))
		_add_slab(tool, Vector3(s.x, bed, s.y), STONE_RADIUS * (0.85 + 0.1 * (k % 3)), STONE_HEIGHT, 0.4 * k,
				STONE_SWATCHES[k % STONE_SWATCHES.size()])
	stones.mesh = LadderBuilder._commit(tool)
	frame.add_child(stones)

	# --- Caballetes, largueros y durmientes ---
	var trestle_node := MeshInstance3D.new()
	trestle_node.name = "piece_bridge_trestles"
	tool = LadderBuilder._begin()
	for t: float in trestles:
		_add_box(tool, Vector3(t, head_top - BEAM_HALF, 0.0), Vector3(BEAM_HALF * 1.2, BEAM_HALF, HEAD_HALF), TIMBER_SWATCH)
		var feet: Array[Vector3] = []
		for sz: float in [-1.0, 1.0]:
			var foot_z: float = sz * LEG_FOOT
			var foot := Vector3(t, float(ground.call(t, foot_z)) + STONE_HEIGHT, foot_z)
			feet.append(foot)
			LadderBuilder._add_tube(tool, PackedVector3Array([Vector3(t, head_top - 2.0 * BEAM_HALF + 0.02, sz * LEG_TOP), foot]),
					LEG_HALF, Vector3.RIGHT, TIMBER_SWATCH)
		# Riostra en aspa entre las dos patas, un poco por debajo del cabezal.
		var high: float = head_top - 0.25
		var low: float = maxf(minf(feet[0].y, feet[1].y) + 0.15, float(spot["surface"]) - origin.y - 0.25)
		if high - low > 0.15:
			LadderBuilder._add_tube(tool, PackedVector3Array([Vector3(t + 0.06, high, -LEG_TOP - 0.03), Vector3(t + 0.06, low, LEG_FOOT - 0.06)]),
					0.025, Vector3.RIGHT, DARK_SWATCH)
	for sz: float in [-BEAM_SIDE, BEAM_SIDE]:
		_add_box(tool, Vector3(length * 0.5, beam_top - BEAM_HALF, sz), Vector3(length * 0.5 - 0.05, BEAM_HALF, BEAM_HALF), TIMBER_SWATCH)
	for along: float in [SLEEPER_IN, length - SLEEPER_IN]:
		var low_ground: float = minf(float(ground.call(along, -HEAD_HALF)), float(ground.call(along, HEAD_HALF)))
		var bottom: float = low_ground - 0.06
		var top: float = beam_top - 2.0 * BEAM_HALF
		if top - bottom > 0.02:
			_add_box(tool, Vector3(along, (top + bottom) * 0.5, 0.0), Vector3(0.11, (top - bottom) * 0.5, HEAD_HALF), DARK_SWATCH)
	trestle_node.mesh = LadderBuilder._commit(tool)
	frame.add_child(trestle_node)

	# --- Tablero: tablones de través, cada uno algo distinto ---
	var deck := MeshInstance3D.new()
	deck.name = "piece_bridge_deck"
	tool = LadderBuilder._begin()
	var rng := RandomNumberGenerator.new()
	rng.seed = 29
	var count: int = int((length - 0.04) / (PLANK_WIDTH + PLANK_GAP))
	var pitch: float = (length - 0.04) / count
	for i: int in count:
		var along: float = 0.02 + pitch * (i + 0.5)
		var half_across: float = DECK_HALF - rng.randf_range(0.0, 0.05)
		var shift: float = rng.randf_range(-0.03, 0.03)
		var turn := Basis(Vector3.UP, rng.randf_range(-0.035, 0.035))
		_add_box(tool, Vector3(along, deck_top - PLANK_THICK * 0.5 + rng.randf_range(-0.004, 0.004), shift),
				Vector3(PLANK_WIDTH * 0.5, PLANK_THICK * 0.5, half_across), PLANK_SWATCHES[rng.randi() % PLANK_SWATCHES.size()], turn)
	deck.mesh = LadderBuilder._commit(tool)
	frame.add_child(deck)

	# --- Pasamanos: postes-hormiga a los lados y una cuerda con su comba entre poste y poste ---
	var rails := Node3D.new()
	rails.name = "piece_bridge_rails"
	frame.add_child(rails)
	var post_alongs: Array[float] = [SLEEPER_IN, trestles[0], trestles[1], length - SLEEPER_IN]
	var rope_tool := LadderBuilder._begin()
	for sz: float in [-POST_SIDE, POST_SIDE]:
		var ties: Array[Vector3] = []
		for along: float in post_alongs:
			var foot := Vector3(along, head_top, sz)   # sobre el cabezal o el durmiente
			var stake: Node3D = post.duplicate() as Node3D
			stake.transform = Transform3D(Basis(Vector3.UP, 0.0 if sz < 0.0 else PI).scaled(Vector3.ONE * POST_SCALE), foot)   # de cara al tablero
			for mesh: MeshInstance3D in LadderBuilder._meshes_of(stake):
				mesh.material_override = PALETTE_MATERIAL
			rails.add_child(stake)
			ties.append(foot + Vector3(0.0, POST_TIE * POST_SCALE, 0.0))
		var line := PackedVector3Array()
		for k: int in ties.size() - 1:
			for s: int in 8:
				var f: float = s / 8.0
				var point: Vector3 = ties[k].lerp(ties[k + 1], f)
				point.y -= ROPE_SAG * 4.0 * f * (1.0 - f)
				line.append(point)
		line.append(ties[ties.size() - 1])
		LadderBuilder._add_tube(rope_tool, line, ROPE_HALF, Vector3.UP, ROPE_SWATCH)
	var ropes := MeshInstance3D.new()
	ropes.name = "bridge_rail_ropes"
	ropes.mesh = LadderBuilder._commit(rope_tool)
	rails.add_child(ropes)

	# --- Zonas de apuntar: el primer caballete y los postes de la orilla de partida ---
	for entry: Array in [["aim_bridge_trestles", Vector3(trestles[0], head_top - 0.3, 0.0)],
			["aim_bridge_rails", Vector3(SLEEPER_IN, head_top + 0.6, 0.0)]]:
		var aim := Node3D.new()
		aim.name = entry[0]
		aim.position = entry[1]
		frame.add_child(aim)

	frame.add_child(_wreck(spot, trestles, post_alongs, ground))
	LadderBuilder._set_owner(root, root)
	var scene := PackedScene.new()
	scene.pack(root)
	root.free()
	return scene


## La pasarela vieja: los tocones de los postes de la orilla de partida, un caballete volcado en el río, tablones
## encallados en las piedras o tirados en la orilla y un cabo de cuerda que cuelga hacia el agua. `ground` da el suelo
## dibujado en el espacio del marco.
static func _wreck(spot: Dictionary, trestles: Array[float], post_alongs: Array[float], ground: Callable) -> Node3D:
	var wreck := MeshInstance3D.new()
	wreck.name = "broken_wreck"
	var tool := LadderBuilder._begin()
	var length: float = spot["length"]
	var surface: float = float(spot["surface"]) - Vector3(spot["origin"]).y
	for k: int in 2:
		var sz: float = -POST_SIDE if k == 0 else POST_SIDE
		var along: float = post_alongs[0]
		LadderBuilder._add_stump(tool, Vector3(along, float(ground.call(along, sz)), sz), 0.25 + 0.1 * k, STUMP_SWATCH)
	var far: float = post_alongs[post_alongs.size() - 1]
	LadderBuilder._add_stump(tool, Vector3(far, float(ground.call(far, POST_SIDE)), POST_SIDE), 0.18, STUMP_SWATCH)
	# Caballete volcado río abajo del segundo: cabezal y dos patas tumbadas en el fondo.
	var t: float = trestles[1] + 0.25
	var bed_a: float = float(ground.call(t, 0.6)) + 0.06
	var bed_b: float = float(ground.call(t + 0.5, -0.5)) + 0.06
	LadderBuilder._add_tube(tool, PackedVector3Array([Vector3(t, bed_a, 0.9), Vector3(t + 0.55, bed_b, -0.35)]), LEG_HALF,
			Vector3.UP, TIMBER_SWATCH)
	LadderBuilder._add_tube(tool, PackedVector3Array([Vector3(t - 0.3, bed_a + 0.02, 0.6), Vector3(t + 0.2, bed_b + 0.04, -0.6)]),
			LEG_HALF, Vector3.UP, TIMBER_SWATCH)
	_add_box(tool, Vector3(t + 0.15, maxf(bed_a, bed_b) + 0.08, 0.15), Vector3(BEAM_HALF, BEAM_HALF, HEAD_HALF * 0.8),
			DARK_SWATCH, Basis(Vector3.UP, 0.6) * Basis(Vector3.RIGHT, 0.25))
	# Tablones: dos encallados contra las piedras del primer caballete (inclinados, asomando del agua), uno tirado en la
	# orilla de partida y otro en la de llegada.
	var pieces: Array = [
		[Vector3(trestles[0] - 0.1, surface - 0.05, -0.45), Basis(Vector3.UP, 0.3) * Basis(Vector3.RIGHT, 0.35)],
		[Vector3(trestles[0] + 0.2, surface - 0.12, 0.5), Basis(Vector3.UP, -0.5) * Basis(Vector3.FORWARD, 0.2)],
		[Vector3(0.45, float(ground.call(0.45, 0.25)) + PLANK_THICK * 0.5, 0.25), Basis(Vector3.UP, 1.1)],
		[Vector3(length - 0.5, float(ground.call(length - 0.5, -0.2)) + PLANK_THICK * 0.5, -0.2), Basis(Vector3.UP, 0.4)],
	]
	for k: int in pieces.size():
		_add_box(tool, pieces[k][0], Vector3(PLANK_WIDTH * 0.5, PLANK_THICK * 0.5, DECK_HALF * 0.9),
				PLANK_SWATCHES[k % PLANK_SWATCHES.size()], pieces[k][1])
	# Cabo de cuerda que sale del tocón del lado de río arriba y baja hasta el agua.
	var tie := Vector3(post_alongs[0], float(ground.call(post_alongs[0], -POST_SIDE)) + 0.2, -POST_SIDE)
	var line := PackedVector3Array()
	for k: int in 7:
		var f: float = k / 6.0
		var along: float = tie.x + f * 0.9
		var y: float = lerpf(tie.y, surface - 0.03, smoothstep(0.0, 1.0, f))
		line.append(Vector3(along, maxf(y, float(ground.call(along, -POST_SIDE - 0.05 * k)) + ROPE_HALF), -POST_SIDE - 0.05 * k))
	LadderBuilder._add_tube(tool, line, ROPE_HALF, Vector3.UP, ROPE_SWATCH)
	wreck.mesh = LadderBuilder._commit(tool)
	return wreck


## Caja de medio tamaño `half` centrada en `at`, girada `turn` (por las dos caras, como todo lo de `LadderBuilder`).
static func _add_box(tool: SurfaceTool, at: Vector3, half: Vector3, swatch: Vector2i, turn: Basis = Basis.IDENTITY) -> void:
	var c: Array[Vector3] = []
	for k: int in 8:
		var corner := Vector3(half.x if (k & 1) != 0 else -half.x, half.y if (k & 2) != 0 else -half.y, half.z if (k & 4) != 0 else -half.z)
		c.append(at + turn * corner)
	# Esquina k: bit 0 = x, bit 1 = y, bit 2 = z (0 = lado negativo).
	LadderBuilder._add_quad(tool, c[0], c[1], c[5], c[4], swatch)   # abajo
	LadderBuilder._add_quad(tool, c[2], c[3], c[7], c[6], swatch)   # arriba
	LadderBuilder._add_quad(tool, c[0], c[1], c[3], c[2], swatch)   # -z
	LadderBuilder._add_quad(tool, c[4], c[5], c[7], c[6], swatch)   # +z
	LadderBuilder._add_quad(tool, c[0], c[2], c[6], c[4], swatch)   # -x
	LadderBuilder._add_quad(tool, c[1], c[3], c[7], c[5], swatch)   # +x


## Piedra plana del vado: un prisma hexagonal algo irregular que apoya en el fondo (`foot`), de `height` de alto.
static func _add_slab(tool: SurfaceTool, foot: Vector3, radius: float, height: float, turn: float, swatch: Vector2i) -> void:
	var bottom := PackedVector3Array()
	var top := PackedVector3Array()
	var wobble: Array[float] = [1.0, 0.86, 1.08, 0.92, 1.04, 0.88]
	for i: int in 6:
		var a: float = TAU * i / 6.0 + turn
		var r: float = radius * wobble[i]
		bottom.append(foot + Vector3(cos(a) * r, -0.1, sin(a) * r))
		top.append(foot + Vector3(cos(a) * r * 0.82, height + 0.015 * (i % 2), sin(a) * r * 0.82))
	LadderBuilder._add_band(tool, bottom, top, swatch)
	LadderBuilder._add_cap(tool, top, swatch)
