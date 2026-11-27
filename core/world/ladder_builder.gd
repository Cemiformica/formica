class_name LadderBuilder
extends RefCounted
## Escalas reparables del plano (C5.6b, D-187; sesión 27): lee la capa [escala] de `IslandLayout` y hace una estructura
## por reparar por cada grupo de casillas pintadas, entre la parte baja y la alta. Es una **escala de cuerda** (César,
## opción A): dos estacas arriba (el poste-hormiga de la barandilla), dos cuerdas que pasan por el borde y bajan apoyadas
## en el acantilado tal como es, siguiendo sus repisas, y peldaños de madera. El terreno no se toca: el mapa de alturas no
## hace paredes verticales y una escala rígida necesitaba un saliente postizo que se notaba (cinco intentos, César). La
## escala de madera por módulos (`art/tools/ladder_blockout.py`) queda para el modo construcción, contra paredes y pisos.
## Mientras no esté reparada, la escala vieja está deshecha: dos tocones de las estacas y, al pie, cuerda suelta y
## peldaños tirados (nodo «broken_wreck»: no choca y se quita al completarla, `RepairSiteView`).
## Tres piezas (costes de César): las estacas (2 maderos), las cuerdas (2 cuerdas + 2 de madera) y los peldaños (2 cuerdas +
## 2 de madera). Completa, con E en las cuerdas o en los peldaños uno se agarra y sube (`climb_path`, `Player.start_climb`).
## Las estructuras se crean al poner el plano y se registran en `Content` por su id («ladder_0»…), para que el guardado
## las encuentre.

const POST_MODEL: PackedScene = preload("res://assets/models/props/fence.glb")
const PALETTE_MATERIAL: Material = preload("res://assets/materials/palette.tres")
const ID_PREFIX: String = "ladder_"
const PURPOSE: StringName = &"ladder"
## Plano que enseña al repararla (sesión 30): la escalera de mano modular del modo construcción.
const BLUEPRINT: StringName = &"hand_ladder"
## Distancia del eje de la escala a su pie, en la medida (`measure`): el pie de la pared queda a esto delante del origen.
const STANDOFF: float = 0.19
## Búsqueda del pie y del borde de la pared, a lo largo de la escala: desde SEARCH_OUT m por fuera de las casillas de
## abajo hasta SEARCH_BEYOND m más allá de las de arriba, cada SEARCH_STEP.
const SEARCH_OUT: float = 2.5
const SEARCH_BEYOND: float = 2.5
const SEARCH_STEP: float = 0.05
## Pendiente mínima (m de subida por m) de lo más empinado para que haya pared.
const WALL_SLOPE: float = 1.5
## El pie es lo último, antes de lo más empinado, que sigue a EDGE_MARGIN de lo más bajo de abajo, y el borde, lo
## primero, después, que llega a EDGE_MARGIN de lo más alto de arriba (con las repisas del acantilado por medio).
const EDGE_MARGIN: float = 0.15
## Perfil de la pared por donde baja la escala: cada PROFILE_STEP a lo largo, lo que más sobresale entre el centro y
## ±PROFILE_HALF a los lados; se suaviza PROFILE_SMOOTH muestras a cada lado (las cuerdas no hacen esquinas) sin quedar
## nunca por dentro de la roca, y la escala va ROPE_GAP por encima. Abajo sobran FOOT_SLACK m tendidos en el suelo.
const PROFILE_STEP: float = 0.1
const PROFILE_HALF: float = 0.35
## El terreno se dibuja con triángulos cada MESH_STEP (`TerrainView`): entre sus puntos, lo dibujado puede quedar algo
## por encima de `terrain_height`, y la cuerda se metía en el suelo al pie (César). Se mide como lo dibujado.
const MESH_STEP: float = 0.5
const PROFILE_SMOOTH: int = 3
const ROPE_GAP: float = 0.05
const FOOT_SLACK: float = 0.6
## Estacas: a STAKE_BACK del borde, a ±STAKE_HALF; las cuerdas salen de su cintura (STAKE_TIE, la de la barandilla).
const STAKE_BACK: float = 0.5
const STAKE_HALF: float = 0.35
const STAKE_TIE: float = 0.40
## Cuerdas a ±RAIL_HALF del centro, de sección cuadrada de 2 × ROPE_HALF; peldaños cada RUNG_SPACING, de RUNG_LENGTH de
## largo y RUNG_RADIUS de radio, empezando a RUNG_START del pie.
const RAIL_HALF: float = 0.27
const ROPE_HALF: float = 0.016
const RUNG_SPACING: float = 0.33
const RUNG_LENGTH: float = 0.66
const RUNG_RADIUS: float = 0.026
const RUNG_START: float = 0.25
## Al subir, los pies de Mira van CLIMB_OUT por fuera de la escala (hacia el jugador) y, arriba, sale CLIMB_EXIT detrás
## del borde (pasadas las estacas).
const CLIMB_OUT: float = 0.25   # César: a 0,45 parecía que ibas demasiado lejos de la escala
const CLIMB_EXIT: float = 1.0   # César: a 1,3 te dejaba lejos de la escala
## Cuadritos de la paleta (fila, columna), como `items_blockout.py`: esparto, madera labrada y corteza.
const ROPE_SWATCH := Vector2i(0, 1)
const RUNG_SWATCH := Vector2i(0, 4)
const STUMP_SWATCH := Vector2i(0, 6)


## Las escalas del plano de `island`, sin poner aún: una lista de {"data": RepairSiteData, "origin": Vector2i}.
## Registra cada `data` en `Content`.
static func build(island: IslandState) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var layout: IslandLayout = island.layout
	if layout == null or layout.ladder_cells.is_empty():
		return result
	var timber: ItemData = Content.find_item(&"timber")
	var rope: ItemData = Content.find_item(&"rope")
	var wood: ItemData = Content.find_item(&"wood")
	var model: Node3D = POST_MODEL.instantiate() as Node3D
	var post: Node3D = model.find_child("fence_post", true, false) as Node3D
	var all_groups: Array[Array] = groups(layout.ladder_cells)
	for index: int in all_groups.size():
		var cells: Array[Vector2i] = []
		cells.assign(all_groups[index])
		var spot: Dictionary = measure(layout, cells)
		if spot.is_empty():
			push_warning("LadderBuilder: la escala de %s no está entre dos alturas" % cells[0])
			continue
		var covered: Array[Vector2i] = _covered_cells(spot)
		var min_cell: Vector2i = covered[0]
		var max_cell: Vector2i = covered[0]
		for cell: Vector2i in covered:
			min_cell = min_cell.min(cell)
			max_cell = max_cell.max(cell)
		var data := RepairSiteData.new()
		data.id = StringName(ID_PREFIX + str(index))
		data.name_key = "REPAIR_LADDER"
		data.size = max_cell - min_cell + Vector2i.ONE
		for cell: Vector2i in covered:
			data.blocked_cells.append(cell - min_cell)
		data.exact_collision = true   # las estacas chocan; la escala, con su forma
		data.purpose = PURPOSE
		data.unlocks = [BLUEPRINT]   # repararla enseña a construir escaleras de mano (sesión 30, D-186)
		var center: Vector3 = GridMath.footprint_center(min_cell, data.size, 0, island.ground_height(min_cell))
		data.scene = _model(layout, spot, center, post)
		_set_climb(data, layout, spot)
		for entry: Array in [["stakes", "REPAIR_PIECE_LADDER_STAKES", {timber: 2}],
				["ropes", "REPAIR_PIECE_LADDER_ROPES", {rope: 2, wood: 2}],
				["rungs", "REPAIR_PIECE_LADDER_RUNGS", {rope: 2, wood: 2}]]:
			var piece := RepairPieceData.new()
			piece.id = StringName("ladder_%s" % entry[0])
			piece.name_key = entry[1]
			piece.node_name = StringName("piece_ladder_%s" % entry[0])
			var cost: Dictionary = entry[2]
			for item: ItemData in cost:
				piece.cost[item] = cost[item]
			if entry[0] != "stakes":
				piece.action = &"climb"   # completa la escala, por las cuerdas o los peldaños se agarra uno
			data.pieces.append(piece)
		Content.register_repair_site(data)
		result.append({"data": data, "origin": min_cell})
	model.free()
	return result


## Por dónde sube Mira (`RepairSiteData.climb_path`, en el mundo): la línea de la escala, CLIMB_OUT por fuera, y dónde
## sale arriba (`climb_exit`), CLIMB_EXIT detrás del borde, en el suelo.
static func _set_climb(data: RepairSiteData, layout: IslandLayout, spot: Dictionary) -> void:
	var origin: Vector3 = spot["origin"]
	var dir: Vector2 = spot["dir"]
	var basis := Basis(Vector3.UP, atan2(-dir.x, -dir.y))   # el mismo giro que el marco del modelo
	var path: PackedVector3Array = _path(layout, spot)
	var climb := PackedVector3Array()   # aparte y luego entero: un array empaquetado no se cambia a través de la propiedad
	for point: Vector3 in path:
		climb.append(origin + basis * (point + Vector3(0.0, 0.0, CLIMB_OUT)))
	data.climb_path = climb
	var lip: Vector3 = path[path.size() - 1]
	var exit := Vector3(0.0, 0.0, lip.z - CLIMB_EXIT)
	exit.y = _local_ground(layout, origin, basis, exit) + 0.05
	data.climb_exit = origin + basis * exit


## Dónde va la escala de estas casillas: {"origin": eje de la escala STANDOFF delante del pie de la pared, a ras del suelo
## de abajo (en metros del mundo), "dir": hacia la pared (eje de la cuadrícula), "modules": metros enteros que sube,
## "rise": lo que sube la pared, "depth": de su pie a su borde, en horizontal}. Vacío si no está entre dos alturas.
## Las casillas de lo alto dicen a qué altura del borde se llega; la escala baja por el centro de ellas.
static func measure(layout: IslandLayout, cells: Array[Vector2i]) -> Dictionary:
	var high := Vector2.ZERO
	var low := Vector2.ZERO
	var highs: int = 0
	var lows: int = 0
	for cell: Vector2i in cells:
		var middle := Vector2(cell.x + 0.5, cell.y + 0.5)
		if layout.level(cell) == IslandLayout.HIGH_LEVEL:
			high += middle
			highs += 1
		else:
			low += middle
			lows += 1
	if highs == 0 or lows == 0:
		return {}
	high /= highs
	low /= lows
	var to_wall: Vector2 = high - low
	var dir := Vector2(signf(to_wall.x), 0.0) if absf(to_wall.x) > absf(to_wall.y) else Vector2(0.0, signf(to_wall.y))
	var side := Vector2(-dir.y, dir.x)
	var start: Vector2 = side * high.dot(side) + dir * (low.dot(dir) - SEARCH_OUT)
	var steps: int = int((high.dot(dir) - low.dot(dir) + SEARCH_OUT + SEARCH_BEYOND) / SEARCH_STEP) + 1
	var heights := PackedFloat32Array()
	for k: int in steps:
		var p: Vector2 = start + dir * (k * SEARCH_STEP)
		heights.append(layout.terrain_height(p.x, p.y))
	# Lo más empinado y, desde ahí, hacia abajo hasta el pie y hacia arriba hasta el borde.
	var steepest: int = 0
	for k: int in steps - 1:
		if _slope(heights, k) > _slope(heights, steepest):
			steepest = k
	if _slope(heights, steepest) < WALL_SLOPE:
		return {}
	var low_ground: float = heights[0]
	for k: int in steepest + 1:
		low_ground = minf(low_ground, heights[k])
	var high_ground: float = heights[steps - 1]
	for k: int in range(steepest, steps):
		high_ground = maxf(high_ground, heights[k])
	var foot: int = steepest
	while foot > 0 and heights[foot] > low_ground + EDGE_MARGIN:
		foot -= 1
	var rim: int = steepest + 1
	while rim < steps - 1 and heights[rim] < high_ground - EDGE_MARGIN:
		rim += 1
	var bottom: float = heights[foot]
	var top: float = heights[rim]
	if top - bottom < 1.0:
		return {}
	var at: Vector2 = start + dir * (foot * SEARCH_STEP - STANDOFF)
	return {"origin": Vector3(at.x, bottom, at.y), "dir": dir, "modules": maxi(1, roundi(top - bottom)),
			"rise": top - bottom, "depth": (rim - foot) * SEARCH_STEP}


## Pendiente entre la muestra `k` y la siguiente (m de subida por m).
static func _slope(heights: PackedFloat32Array, k: int) -> float:
	return (heights[k + 1] - heights[k]) / SEARCH_STEP


## Grupos de casillas pintadas que se tocan (también en diagonal): una escala por grupo.
static func groups(ladder_cells: Array[Vector2i]) -> Array[Array]:
	var left: Array[Vector2i] = ladder_cells.duplicate()
	var result: Array[Array] = []
	while not left.is_empty():
		var group: Array[Vector2i] = [left.pop_front()]
		var i: int = 0
		while i < group.size():
			for j: int in range(left.size() - 1, -1, -1):
				if maxi(absi(group[i].x - left[j].x), absi(group[i].y - left[j].y)) <= 1:
					group.append(left[j])
					left.remove_at(j)
			i += 1
		result.append(group)
	return result


## Casillas que ocupan la escala y sus estacas (bloquean construir, plantar, rocas, palos y césped): de lo que se tiende
## en el suelo a las estacas, a lo ancho de las estacas.
static func _covered_cells(spot: Dictionary) -> Array[Vector2i]:
	var origin: Vector3 = spot["origin"]
	var dir: Vector2 = spot["dir"]
	var side := Vector2(-dir.y, dir.x)
	var cells: Array[Vector2i] = []
	var along: float = STANDOFF - FOOT_SLACK
	while along <= STANDOFF + float(spot["depth"]) + STAKE_BACK + 0.2:
		var across: float = -(STAKE_HALF + 0.2)
		while across <= STAKE_HALF + 0.2 + 0.001:
			var p: Vector2 = Vector2(origin.x, origin.z) + dir * along + side * across
			var cell := Vector2i(floori(p.x), floori(p.y))
			if not cells.has(cell):
				cells.append(cell)
			across += 0.25
		along += 0.25
	return cells


## Por dónde baja la escala, en el espacio del marco (x a los lados, y arriba desde el pie, -z hacia la pared): de lo
## que se tiende en el suelo hasta el borde de lo alto, ROPE_GAP por encima de lo que más sobresale de la roca.
static func _path(layout: IslandLayout, spot: Dictionary) -> PackedVector3Array:
	var origin: Vector3 = spot["origin"]
	var dir: Vector2 = spot["dir"]
	var side := Vector2(-dir.y, dir.x)
	var from: float = STANDOFF - FOOT_SLACK
	var to: float = STANDOFF + float(spot["depth"])
	var count: int = int((to - from) / PROFILE_STEP) + 1
	var raw := PackedFloat32Array()
	for k: int in count:
		var along: float = from + k * PROFILE_STEP
		var most: float = -INF
		for across: float in [-PROFILE_HALF, -RAIL_HALF, 0.0, RAIL_HALF, PROFILE_HALF]:
			var p: Vector2 = Vector2(origin.x, origin.z) + dir * along + side * across
			most = maxf(most, _drawn_height(layout, p.x, p.y) - origin.y)
		raw.append(most)
	var points := PackedVector3Array()
	var profile := PackedVector2Array()
	for k: int in count:
		var sum: float = 0.0
		var n: int = 0
		for j: int in range(maxi(0, k - PROFILE_SMOOTH), mini(count, k + PROFILE_SMOOTH + 1)):
			sum += raw[j]
			n += 1
		profile.append(Vector2(from + k * PROFILE_STEP, maxf(sum / n, raw[k])))
	# Separada ROPE_GAP de la roca, hacia fuera (perpendicular a la cuesta).
	for k: int in count:
		var before: Vector2 = profile[maxi(0, k - 1)]
		var after: Vector2 = profile[mini(count - 1, k + 1)]
		var tangent: Vector2 = (after - before).normalized()
		var outward := Vector2(-tangent.y, tangent.x)   # hacia delante y arriba (a menos «along», más altura)
		var at: Vector2 = profile[k] + outward * ROPE_GAP
		points.append(Vector3(0.0, at.y, -at.x))
	return points


## Altura del suelo dibujado bajo `point` (en el espacio del marco), en ese mismo espacio.
static func _local_ground(layout: IslandLayout, origin: Vector3, basis: Basis, point: Vector3) -> float:
	var world: Vector3 = origin + basis * point
	return _drawn_height(layout, world.x, world.z) - origin.y


## Altura del suelo tal como se dibuja en (x, z): el cuadro de MESH_STEP que lo contiene, partido en dos triángulos por
## la diagonal de (x, z) a (x + MESH_STEP, z + MESH_STEP), como lo parte `TerrainView` (César: con la otra diagonal, la
## escala se levantaba en el borde de lo alto).
static func _drawn_height(layout: IslandLayout, x: float, z: float) -> float:
	var gx: float = floorf(x / MESH_STEP) * MESH_STEP
	var gz: float = floorf(z / MESH_STEP) * MESH_STEP
	var fx: float = (x - gx) / MESH_STEP
	var fz: float = (z - gz) / MESH_STEP
	var h00: float = layout.terrain_height(gx, gz)
	var h10: float = layout.terrain_height(gx + MESH_STEP, gz)
	var h01: float = layout.terrain_height(gx, gz + MESH_STEP)
	var h11: float = layout.terrain_height(gx + MESH_STEP, gz + MESH_STEP)
	if fx >= fz:
		return h00 + (h10 - h00) * fx + (h11 - h10) * fz
	return h00 + (h01 - h00) * fz + (h11 - h01) * fx


## El modelo: un marco girado hacia la pared con las tres piezas («piece_ladder_stakes», «…_ropes», «…_rungs») y la
## escala vieja («broken_wreck»).
static func _model(layout: IslandLayout, spot: Dictionary, center: Vector3, post: Node3D) -> PackedScene:
	var root := Node3D.new()
	root.name = "ladder"
	var frame := Node3D.new()
	frame.name = "ladder_frame"
	var dir: Vector2 = spot["dir"]
	var origin: Vector3 = spot["origin"]
	frame.position = origin - center
	frame.rotation.y = atan2(-dir.x, -dir.y)   # el -Z del marco, hacia la pared
	root.add_child(frame)
	var path: PackedVector3Array = _path(layout, spot)
	var lip: Vector3 = path[path.size() - 1]
	# Estacas, en lo alto, detrás del borde, cada una a la altura de su suelo.
	var basis: Basis = frame.basis
	var stakes := Node3D.new()
	stakes.name = "piece_ladder_stakes"
	frame.add_child(stakes)
	var ties: Array[Vector3] = []
	for sx: float in [-STAKE_HALF, STAKE_HALF]:
		var local := Vector3(sx, 0.0, lip.z - STAKE_BACK)
		var world: Vector3 = origin + basis * local
		local.y = layout.terrain_height(world.x, world.z) - origin.y
		var stake: Node3D = post.duplicate() as Node3D
		stake.transform = Transform3D(Basis.IDENTITY, local)   # las antenas, abiertas a los lados
		for mesh: MeshInstance3D in _meshes_of(stake):
			mesh.material_override = PALETTE_MATERIAL
		stakes.add_child(stake)
		ties.append(local + Vector3(0.0, STAKE_TIE, 0.0))
	# Cuerdas: de la cintura de cada estaca al borde y, por la pared, hasta el suelo.
	var ropes := MeshInstance3D.new()
	ropes.name = "piece_ladder_ropes"
	var tool := _begin()
	for k: int in 2:
		var x: float = -RAIL_HALF if k == 0 else RAIL_HALF
		var line := PackedVector3Array()
		line.append(ties[k])
		line.append(Vector3(x, lip.y + ROPE_HALF, lip.z))
		for i: int in range(path.size() - 1, -1, -1):
			line.append(Vector3(x, path[i].y, path[i].z))
		_add_tube(tool, line, ROPE_HALF, Vector3.RIGHT, ROPE_SWATCH)
	ropes.mesh = _commit(tool)
	frame.add_child(ropes)
	# Peldaños, cada RUNG_SPACING por la cuerda, desde abajo.
	var rungs := MeshInstance3D.new()
	rungs.name = "piece_ladder_rungs"
	tool = _begin()
	for at: Vector3 in _along(path, RUNG_START, RUNG_SPACING):
		_add_rung(tool, at, RUNG_SWATCH)
	rungs.mesh = _commit(tool)
	frame.add_child(rungs)
	frame.add_child(_wreck(layout, origin, basis, ties, path))
	_set_owner(root, root)
	var scene := PackedScene.new()
	scene.pack(root)
	root.free()
	return scene


## La escala vieja: un tocón partido donde iba cada estaca y, al pie, dos cuerdas deshechas culebreando por el suelo con
## unos peldaños sueltos, cada punto apoyado en el suelo tal como se dibuja (César: la cuerda flotaba a la altura del
## final de la escala, que no llega del todo al suelo). `origin` y `basis` pasan del marco al mundo.
static func _wreck(layout: IslandLayout, origin: Vector3, basis: Basis, ties: Array[Vector3],
		path: PackedVector3Array) -> Node3D:
	var wreck := MeshInstance3D.new()
	wreck.name = "broken_wreck"
	var tool := _begin()
	for k: int in ties.size():
		var foot := Vector3(ties[k].x, ties[k].y - STAKE_TIE, ties[k].z)
		_add_stump(tool, foot, 0.2 + 0.08 * k, STUMP_SWATCH)
	var ground: Vector3 = path[0]
	for k: int in 2:
		var line := PackedVector3Array()
		var x: float = -0.4 + 0.75 * k
		for i: int in 10:
			var wave: float = sin(i * 1.0 + k * 2.1) * 0.18
			var point := Vector3(x + wave + i * 0.03 * (1 - 2 * k), 0.0, ground.z + 0.35 + i * 0.13)
			point.y = _local_ground(layout, origin, basis, point) + ROPE_HALF
			line.append(point)
		_add_tube(tool, line, ROPE_HALF, Vector3.UP, ROPE_SWATCH)
	for k: int in 3:
		var at := Vector3(-0.5 + 0.55 * k, 0.0, ground.z + 0.6 + 0.3 * (k % 2))
		at.y = _local_ground(layout, origin, basis, at) + RUNG_RADIUS
		_add_rung(tool, at, RUNG_SWATCH, 0.6 + 0.9 * k)
	wreck.mesh = _commit(tool)
	return wreck


## Puntos cada `spacing` a lo largo de `path` (de su primer punto al último), empezando a `start`.
static func _along(path: PackedVector3Array, start: float, spacing: float) -> PackedVector3Array:
	var result := PackedVector3Array()
	var next: float = start
	var walked: float = 0.0
	for i: int in path.size() - 1:
		var a: Vector3 = path[i]
		var b: Vector3 = path[i + 1]
		var length: float = a.distance_to(b)
		while next <= walked + length and length > 0.0:
			result.append(a.lerp(b, (next - walked) / length))
			next += spacing
		walked += length
	return result


## Malla nueva de caras planas (cada triángulo, su normal: así las caras dobles no se anulan entre sí).
static func _begin() -> SurfaceTool:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.set_smooth_group(-1)
	return tool


static func _commit(tool: SurfaceTool) -> ArrayMesh:
	tool.generate_normals()
	var mesh: ArrayMesh = tool.commit()
	mesh.surface_set_material(0, PALETTE_MATERIAL)
	return mesh


static func _uv(swatch: Vector2i) -> Vector2:
	return Vector2((swatch.y * 8 + 4) / 64.0, (swatch.x * 8 + 4) / 64.0)


## Tira de sección cuadrada (2 × `half`) a lo largo de `line`, con las puntas tapadas. `across` es una dirección que no
## va a lo largo de la tira (fija hacia dónde miran sus caras).
static func _add_tube(tool: SurfaceTool, line: PackedVector3Array, half: float, across: Vector3, swatch: Vector2i) -> void:
	var count: int = line.size()
	var rings: Array[PackedVector3Array] = []
	for k: int in count:
		var along: Vector3 = (line[mini(k + 1, count - 1)] - line[maxi(k - 1, 0)]).normalized()
		var side: Vector3 = along.cross(across).normalized()
		if side.length_squared() < 0.5:
			side = along.cross(Vector3.FORWARD).normalized()
		var up: Vector3 = side.cross(along).normalized()
		rings.append(PackedVector3Array([line[k] + (up + side) * half, line[k] + (up - side) * half,
				line[k] + (-up - side) * half, line[k] + (-up + side) * half]))
	for k: int in count - 1:
		_add_band(tool, rings[k], rings[k + 1], swatch)
	_add_cap(tool, rings[0], swatch)
	_add_cap(tool, rings[count - 1], swatch)


## Peldaño: un prisma hexagonal a lo ancho (eje X) centrado en `at`, girado `turn` radianes sobre su eje (y, si se da,
## tumbado en el suelo con ese giro en planta).
static func _add_rung(tool: SurfaceTool, at: Vector3, swatch: Vector2i, lying_turn: float = 0.0) -> void:
	var basis := Basis(Vector3.UP, lying_turn)
	var rings: Array[PackedVector3Array] = []
	for end: float in [-RUNG_LENGTH * 0.5, RUNG_LENGTH * 0.5]:
		var ring := PackedVector3Array()
		for i: int in 6:
			var a: float = TAU * i / 6.0 + at.y   # cada peldaño, girado distinto
			ring.append(at + basis * Vector3(end, cos(a) * RUNG_RADIUS, sin(a) * RUNG_RADIUS))
		rings.append(ring)
	_add_band(tool, rings[0], rings[1], swatch)
	_add_cap(tool, rings[0], swatch)
	_add_cap(tool, rings[1], swatch)


## Tocón de estaca partido: prisma hexagonal de `height` con la punta astillada.
static func _add_stump(tool: SurfaceTool, foot: Vector3, height: float, swatch: Vector2i) -> void:
	var bottom := PackedVector3Array()
	var top := PackedVector3Array()
	var cuts: Array[float] = [0.0, -0.06, -0.02, -0.09, -0.04, 0.02]
	for i: int in 6:
		var a: float = TAU * i / 6.0
		var r: Vector3 = Vector3(cos(a), 0.0, sin(a)) * 0.1
		bottom.append(foot + r - Vector3(0.0, 0.05, 0.0))
		top.append(foot + r * 0.95 + Vector3(0.0, height + cuts[i], 0.0))
	_add_band(tool, bottom, top, swatch)
	_add_cap(tool, top, swatch)


## Caras entre dos anillos con el mismo número de puntos (por las dos caras: así no importa el sentido).
static func _add_band(tool: SurfaceTool, a: PackedVector3Array, b: PackedVector3Array, swatch: Vector2i) -> void:
	var n: int = a.size()
	for i: int in n:
		var j: int = (i + 1) % n
		_add_quad(tool, a[i], a[j], b[j], b[i], swatch)


static func _add_cap(tool: SurfaceTool, ring: PackedVector3Array, swatch: Vector2i) -> void:
	for i: int in range(1, ring.size() - 1):
		_add_double(tool, ring[0], ring[i], ring[i + 1], swatch)


static func _add_quad(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, swatch: Vector2i) -> void:
	_add_double(tool, a, b, c, swatch)
	_add_double(tool, a, c, d, swatch)


## Un triángulo por las dos caras (los dos sentidos), para que se vea desde donde se mire sin preocuparse del orden.
static func _add_double(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, swatch: Vector2i) -> void:
	var uv: Vector2 = _uv(swatch)
	for v: Vector3 in [a, b, c, a, c, b]:
		tool.set_uv(uv)
		tool.add_vertex(v)


static func _meshes_of(root: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	if root is MeshInstance3D:
		result.append(root)
	for child: Node in root.get_children():
		result.append_array(_meshes_of(child))
	return result


static func _set_owner(node: Node, owner: Node) -> void:
	for child: Node in node.get_children():
		child.owner = owner
		_set_owner(child, owner)
