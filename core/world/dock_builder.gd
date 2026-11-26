class_name DockBuilder
extends RefCounted
## Embarcadero en ruinas del plano (C5.6b, D-186; sesión 29): uno por cada grupo de casillas `E` de `isla_alba.txt`. Sale de
## la orilla hacia el agua por el lado donde más agua hay. Se genera en código, como la pasarela del vado: pilotes, cabezales,
## largueros y tablones (el ítem tablón), con dos bolardos-hormiga (los postes de la barandilla, más bajos) con cuerda podrida
## y la **baliza apagada** (`dock.glb`, `art/tools/dock_blockout.py`) donde el muelle se rompe.
## El primer tramo está entero y se pisa; el resto se hundió: pilotes partidos que asoman del agua, un larguero que cae al
## agua, tablones colgando del borde roto y alguno a la deriva entre los pilotes.
## En el vertical slice es **solo decorado** (D-186): una estructura por reparar **sin piezas** (completa desde el principio,
## así que no se le apunta ni pide nada) para que, cuando llegue la barca, se le añadan las piezas (con componentes del nivel
## de la barca) y repararlo enseñe su plano. Se registra en `Content` por su id («dock_0»…), para que el guardado lo encuentre.
## Dónde tocar: las constantes (medidas en metros) y `_model`.

const BEACON_MODEL: PackedScene = preload("res://assets/models/props/dock.glb")
const POST_MODEL: PackedScene = preload("res://assets/models/props/fence.glb")
const PALETTE_MATERIAL: Material = preload("res://assets/materials/palette.tres")
const ID_PREFIX: String = "dock_"
const PURPOSE: StringName = &"dock"
const DOCK_CHAR: String = "E"
## Cuánto entra en el agua desde la orilla, y qué parte de eso sigue entera (el resto se hundió).
const REACH: float = 5.0
const INTACT_OVER_WATER: float = 1.9
## Desde dónde empieza, dentro de las casillas del embarcadero (desde su borde de tierra): el muelle queda algo metido
## en la playa (César).
const START_IN: float = 0.5
## Medio ancho del tablero; su cara de arriba, sobre lo más alto de la tierra que pisa y, como mínimo, sobre el agua.
const DECK_HALF: float = 0.7
const DECK_LIFT: float = 0.22
## Peldaños de la playa al tablero: altura máxima de cada uno y fondo.
const STEP_RISE: float = 0.17
const STEP_DEPTH: float = 0.34
const WATER_CLEAR: float = 0.38
## Tablones de través (como la pasarela), largueros y cabezales.
const PLANK_WIDTH: float = 0.2
const PLANK_THICK: float = 0.04
const PLANK_GAP: float = 0.025
const BEAM_SIDE: float = 0.45
const BEAM_HALF: float = 0.055
const HEAD_HALF: float = 0.78
## Pilotes: por parejas a ±PILE_SIDE, cada PILE_STEP a lo largo, desde PILE_START.
const PILE_SIDE: float = 0.66
const PILE_STEP: float = 1.4
const PILE_START: float = 0.45
## Bolardos: los postes de la barandilla a esta escala, en las esquinas del final del tramo entero, a ±BOLLARD_SIDE.
const BOLLARD_SCALE: float = 0.7
const BOLLARD_SIDE: float = 0.55
## Baliza: a BEACON_BACK del borde roto, a este lado (negativo = a la izquierda mirando al agua).
const BEACON_BACK: float = 0.55
const BEACON_SIDE: float = -0.38
const ROPE_HALF: float = 0.016
## Cuadritos de la paleta (fila, columna), como `items_blockout.py`.
const PLANK_SWATCHES: Array[Vector2i] = [Vector2i(0, 2), Vector2i(0, 4), Vector2i(0, 2), Vector2i(0, 5)]
const TIMBER_SWATCH := Vector2i(0, 4)
const WET_SWATCH := Vector2i(0, 6)
const ROPE_SWATCH := Vector2i(0, 3)   # esparto oscuro: cuerda vieja


## Los embarcaderos del plano de `island`, sin poner aún: una lista de {"data": RepairSiteData, "origin": Vector2i}.
## Registra cada `data` en `Content`.
static func build(island: IslandState) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var layout: IslandLayout = island.layout
	if layout == null:
		return result
	var cells_all: Array[Vector2i] = layout.cells_of(DOCK_CHAR)
	if cells_all.is_empty():
		return result
	var beacon_root: Node3D = BEACON_MODEL.instantiate() as Node3D
	var beacon: Node3D = beacon_root.find_child("dock_beacon", true, false) as Node3D
	var post_root: Node3D = POST_MODEL.instantiate() as Node3D
	var post: Node3D = post_root.find_child("fence_post", true, false) as Node3D
	var all_groups: Array[Array] = LadderBuilder.groups(cells_all)
	for index: int in all_groups.size():
		var cells: Array[Vector2i] = []
		cells.assign(all_groups[index])
		var spot: Dictionary = measure(layout, cells)
		if spot.is_empty():
			push_warning("DockBuilder: el embarcadero de %s no da al agua" % cells[0])
			continue
		var covered: Array[Vector2i] = _covered_cells(spot)
		var min_cell: Vector2i = covered[0]
		var max_cell: Vector2i = covered[0]
		for cell: Vector2i in covered:
			min_cell = min_cell.min(cell)
			max_cell = max_cell.max(cell)
		var data := RepairSiteData.new()
		data.id = StringName(ID_PREFIX + str(index))
		data.name_key = "REPAIR_DOCK"
		data.size = max_cell - min_cell + Vector2i.ONE
		for cell: Vector2i in covered:
			data.blocked_cells.append(cell - min_cell)
		data.exact_collision = true   # se pisa el tramo entero
		data.footstep_surface = &"wood"
		data.purpose = PURPOSE
		var center: Vector3 = GridMath.footprint_center(min_cell, data.size, 0, island.ground_height(min_cell))
		data.scene = _model(layout, spot, center, beacon, post)
		Content.register_repair_site(data)
		result.append({"data": data, "origin": min_cell})
	beacon_root.free()
	post_root.free()
	return result


## Dónde va el embarcadero de estas casillas: {"origin": punto del mundo en el centro del ancho, al principio del tablero (a
## la altura del agua), "dir": hacia el agua (eje de la cuadrícula), "water": dónde empieza el agua a lo largo (m desde el
## origen), "length": hasta la punta (m), "deck": altura de la cara de arriba del tablero (m del mundo), "surface": la del
## agua}. Vacío si a ningún lado hay agua.
static func measure(layout: IslandLayout, cells: Array[Vector2i]) -> Dictionary:
	if cells.is_empty():
		return {}
	var min_cell: Vector2i = cells[0]
	var max_cell: Vector2i = cells[0]
	for cell: Vector2i in cells:
		min_cell = min_cell.min(cell)
		max_cell = max_cell.max(cell)
	# Hacia donde más agua toca el grupo (río, lago o mar).
	var best := Vector2i.ZERO
	var best_count: int = 0
	for step: Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
		var count: int = 0
		for cell: Vector2i in cells:
			var next: Vector2i = cell + step
			if not cells.has(next) and _is_water(layout, next):
				count += 1
		if count > best_count:
			best_count = count
			best = step
	if best_count == 0:
		return {}
	var dir := Vector2(best)
	var side := Vector2(-dir.y, dir.x)
	var middle: Vector2 = (Vector2(min_cell) + Vector2(max_cell) + Vector2.ONE) * 0.5
	# A lo largo: el borde de tierra del grupo (por detrás) y el del agua (por delante).
	var back: float = minf(Vector2(min_cell).dot(dir), (Vector2(max_cell) + Vector2.ONE).dot(dir))
	var front: float = maxf(Vector2(min_cell).dot(dir), (Vector2(max_cell) + Vector2.ONE).dot(dir))
	var start: float = back + START_IN
	var at: Vector2 = side * middle.dot(side) + dir * start
	var surface: float = 0.0
	var water_cell := Vector2i((middle + dir * (front - middle.dot(dir) + 0.5)).floor())
	if layout.ground(water_cell) == IslandLayout.Ground.WATER:
		surface = IslandLayout.level_height(layout.level(water_cell))
	var highest: float = -INF
	var along: float = 0.0
	while along <= front - start:
		for across: float in [-DECK_HALF, 0.0, DECK_HALF]:
			var p: Vector2 = at + dir * along + side * across
			highest = maxf(highest, LadderBuilder._drawn_height(layout, p.x, p.y))
		along += 0.25
	var deck: float = maxf(highest + DECK_LIFT, surface + WATER_CLEAR)
	return {"origin": Vector3(at.x, surface, at.y), "dir": dir, "water": front - start,
			"length": front - start + REACH, "deck": deck, "surface": surface}


static func _is_water(layout: IslandLayout, cell: Vector2i) -> bool:
	var g: IslandLayout.Ground = layout.ground(cell)
	return g == IslandLayout.Ground.WATER or g == IslandLayout.Ground.SEA


## Casillas que ocupa (bloquean construir, plantar, rocas, palos y césped): el tablero y los pilotes.
static func _covered_cells(spot: Dictionary) -> Array[Vector2i]:
	var origin: Vector3 = spot["origin"]
	var dir: Vector2 = spot["dir"]
	var side := Vector2(-dir.y, dir.x)
	var cells: Array[Vector2i] = []
	var along: float = 0.05
	while along <= float(spot["length"]) - 0.05:
		var across: float = -(PILE_SIDE + 0.1)
		while across <= PILE_SIDE + 0.1 + 0.001:
			var p: Vector2 = Vector2(origin.x, origin.z) + dir * along + side * across
			var cell := Vector2i(floori(p.x), floori(p.y))
			if not cells.has(cell):
				cells.append(cell)
			across += 0.2
		along += 0.2
	return cells


## El modelo: un marco con +X hacia el agua y +Z a un lado. Todo es base (no hay piezas en el vertical slice): pilotes,
## tablero, lo hundido, bolardos y la baliza.
static func _model(layout: IslandLayout, spot: Dictionary, center: Vector3, beacon: Node3D, post: Node3D) -> PackedScene:
	var root := Node3D.new()
	root.name = "dock"
	var frame := Node3D.new()
	frame.name = "dock_frame"
	var dir: Vector2 = spot["dir"]
	var origin: Vector3 = spot["origin"]
	frame.position = origin - center
	frame.rotation.y = atan2(-dir.y, dir.x)   # el +X del marco, hacia el agua
	root.add_child(frame)
	var basis: Basis = frame.basis
	var length: float = spot["length"]
	var deck_top: float = float(spot["deck"]) - origin.y
	var beam_top: float = deck_top - PLANK_THICK
	var head_top: float = beam_top - 2.0 * BEAM_HALF
	var broken_at: float = float(spot["water"]) + INTACT_OVER_WATER   # donde se rompe
	var ground := func(at_along: float, at_across: float) -> float:
		return LadderBuilder._local_ground(layout, origin, basis, Vector3(at_along, 0.0, at_across))
	var rng := RandomNumberGenerator.new()
	rng.seed = 86

	var wood := MeshInstance3D.new()
	wood.name = "dock_wood"
	var tool := LadderBuilder._begin()
	# Pilotes por parejas: enteros bajo el tramo que sigue en pie, partidos a alturas distintas en lo hundido.
	var pile_alongs: Array[float] = []
	var along: float = PILE_START
	while along <= length - 0.2:
		pile_alongs.append(along)
		along += PILE_STEP
	for a: float in pile_alongs:
		var intact: bool = a <= broken_at
		for sz: float in [-PILE_SIDE, PILE_SIDE]:
			var bed: float = float(ground.call(a, sz))
			var top: float = head_top if intact else rng.randf_range(-0.15, deck_top + 0.15)
			if top - bed > 0.05:
				LadderBuilder._add_stump(tool, Vector3(a, bed, sz), top - bed, WET_SWATCH)
		if intact:
			BridgeBuilder._add_box(tool, Vector3(a, head_top - BEAM_HALF, 0.0), Vector3(BEAM_HALF * 1.2, BEAM_HALF, HEAD_HALF),
					TIMBER_SWATCH)
	# Largueros: enteros hasta el borde roto; el de la izquierda sigue un poco y cae al agua.
	for sz: float in [-BEAM_SIDE, BEAM_SIDE]:
		BridgeBuilder._add_box(tool, Vector3(broken_at * 0.5, beam_top - BEAM_HALF, sz), Vector3(broken_at * 0.5, BEAM_HALF, BEAM_HALF),
				TIMBER_SWATCH)
	LadderBuilder._add_tube(tool, PackedVector3Array([Vector3(broken_at, beam_top - BEAM_HALF, -BEAM_SIDE),
			Vector3(broken_at + 1.1, beam_top - 0.25, -BEAM_SIDE - 0.05), Vector3(broken_at + 1.9, -0.35, -BEAM_SIDE - 0.15)]),
			BEAM_HALF, Vector3.UP, TIMBER_SWATCH)
	# Tablones del tramo entero, cada uno algo distinto; cerca del borde roto faltan algunos.
	var count: int = int((broken_at - 0.02) / (PLANK_WIDTH + PLANK_GAP))
	var pitch: float = (broken_at - 0.02) / count
	for i: int in count:
		var a: float = 0.01 + pitch * (i + 0.5)
		if a > broken_at - 0.9 and i % 3 == 1:
			continue   # un hueco
		var half_across: float = DECK_HALF - rng.randf_range(0.0, 0.06)
		if a > broken_at - 0.5:
			half_across *= rng.randf_range(0.45, 0.8)   # partidos
		var turn := Basis(Vector3.UP, rng.randf_range(-0.04, 0.04))
		BridgeBuilder._add_box(tool, Vector3(a, deck_top - PLANK_THICK * 0.5 + rng.randf_range(-0.005, 0.005),
				rng.randf_range(-0.04, 0.04)), Vector3(PLANK_WIDTH * 0.5, PLANK_THICK * 0.5, half_across),
				PLANK_SWATCHES[rng.randi() % PLANK_SWATCHES.size()], turn)
	# Peldaños en la punta de tierra (César: el escalón de la playa al tablero era alto): los que hagan falta para que
	# ninguno pase de STEP_RISE, cada uno un tablón ancho sobre su taco, hacia la playa.
	var shore: float = minf(float(ground.call(-0.3, -DECK_HALF * 0.6)), float(ground.call(-0.3, DECK_HALF * 0.6)))
	var steps: int = ceili((deck_top - shore) / STEP_RISE) - 1
	for k: int in steps:
		var step_top: float = deck_top - (deck_top - shore) * float(k + 1) / float(steps + 1)
		var step_along: float = -STEP_DEPTH * (k + 0.5) - 0.02
		BridgeBuilder._add_box(tool, Vector3(step_along, step_top - PLANK_THICK * 0.5, 0.0),
				Vector3(STEP_DEPTH * 0.5, PLANK_THICK * 0.5, DECK_HALF - 0.12), PLANK_SWATCHES[(k + 2) % PLANK_SWATCHES.size()])
		var block_bottom: float = minf(shore, float(ground.call(step_along, 0.0))) - 0.06
		var block_top: float = step_top - PLANK_THICK
		if block_top - block_bottom > 0.02:
			for sz: float in [-(DECK_HALF - 0.25), DECK_HALF - 0.25]:
				BridgeBuilder._add_box(tool, Vector3(step_along, (block_top + block_bottom) * 0.5, sz),
						Vector3(STEP_DEPTH * 0.35, (block_top - block_bottom) * 0.5, 0.09), WET_SWATCH)
	# Lo hundido: tablones que cuelgan del borde roto hacia el agua y otros a la deriva entre los pilotes.
	for k: int in 3:
		var sz: float = -0.4 + 0.4 * k
		var tilt := Basis(Vector3.FORWARD, 0.9 + 0.15 * k) * Basis(Vector3.UP, 0.1 * (k - 1))   # la punta de fuera, al agua
		var hang_center := Vector3(broken_at + 0.28, deck_top - 0.32 - 0.05 * k, sz)
		BridgeBuilder._add_box(tool, hang_center, Vector3(0.38, PLANK_THICK * 0.5, PLANK_WIDTH * 0.5),
				PLANK_SWATCHES[k % PLANK_SWATCHES.size()], tilt)
	for k: int in 3:
		var drift := Vector3(broken_at + 1.3 + 1.0 * k, -0.02, -0.5 + 0.55 * k)
		BridgeBuilder._add_box(tool, drift, Vector3(PLANK_WIDTH * 0.5, PLANK_THICK * 0.5, DECK_HALF * 0.75),
				PLANK_SWATCHES[(k + 1) % PLANK_SWATCHES.size()], Basis(Vector3.UP, 0.5 + 0.7 * k) * Basis(Vector3.RIGHT, 0.1))
	wood.mesh = LadderBuilder._commit(tool)
	frame.add_child(wood)

	# Bolardos-hormiga en las esquinas del tramo entero, mirando al agua, con cuerda podrida.
	var ropes_tool := LadderBuilder._begin()
	for sz: float in [-BOLLARD_SIDE, BOLLARD_SIDE]:
		var foot := Vector3(broken_at - 1.2, deck_top, sz)
		var bollard: Node3D = post.duplicate() as Node3D
		bollard.transform = Transform3D(Basis(Vector3.UP, PI * 0.5).scaled(Vector3(1.25, 1.0, 1.25) * BOLLARD_SCALE), foot)
		for mesh: MeshInstance3D in LadderBuilder._meshes_of(bollard):
			mesh.material_override = PALETTE_MATERIAL
		frame.add_child(bollard)
		# Una vuelta de cuerda a la cintura y un cabo que cae por el borde hasta el agua.
		var waist: float = deck_top + 0.4 * BOLLARD_SCALE
		var loop := PackedVector3Array()
		for s: int in 9:
			var ang: float = TAU * s / 8.0
			loop.append(foot + Vector3(cos(ang) * 0.085, waist - deck_top + 0.01 * sin(ang * 2.0), sin(ang) * 0.085))
		LadderBuilder._add_tube(ropes_tool, loop, ROPE_HALF, Vector3.UP, ROPE_SWATCH)
		var out: float = signf(sz)
		var strand := PackedVector3Array([foot + Vector3(0.0, waist - deck_top, 0.085 * out),
				Vector3(foot.x + 0.15, deck_top + 0.02, sz + 0.25 * out), Vector3(foot.x + 0.3, deck_top - 0.2, DECK_HALF * out + 0.05 * out),
				Vector3(foot.x + 0.4, float(spot["surface"]) - origin.y - 0.05, DECK_HALF * out + 0.15 * out)])
		LadderBuilder._add_tube(ropes_tool, strand, ROPE_HALF, Vector3.UP, ROPE_SWATCH)
	var ropes := MeshInstance3D.new()
	ropes.name = "dock_ropes"
	ropes.mesh = LadderBuilder._commit(ropes_tool)
	frame.add_child(ropes)

	# La baliza apagada, junto al borde roto.
	if beacon != null:
		var lamp: Node3D = beacon.duplicate() as Node3D
		lamp.transform = Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(broken_at - BEACON_BACK, deck_top, BEACON_SIDE))
		for mesh: MeshInstance3D in LadderBuilder._meshes_of(lamp):
			mesh.material_override = PALETTE_MATERIAL
		frame.add_child(lamp)
	LadderBuilder._set_owner(root, root)
	var scene := PackedScene.new()
	scene.pack(root)
	root.free()
	return scene
