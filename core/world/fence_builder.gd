class_name FenceBuilder
extends RefCounted
## Barandillas del plano (C5.6b, D-187; sesión 26): lee la capa [barandilla] de `IslandLayout` y hace una estructura
## por reparar por cada tramo seguido de casillas, con un poste-hormiga en cada una y troncos entre postes vecinos
## (`art/tools/fence_blockout.py`). Cada tramo entre dos postes es una pieza: 1 madero + 1 cuerda.
## César pinta las casillas en `paint_alba.png` sin ver el plano, así que aquí se colocan donde quedan mejor: cada poste
## busca el borde de verdad (el terreno dibujado, que desplaza los bordes de las casillas hasta 1,3 m) y se queda un
## poco dentro, en el lado del camino (César: iban por el acantilado); la línea se suaviza y los huecos (la pintura
## que cayó sobre el agua) se rellenan con postes intermedios.
## Las estructuras se crean al poner el plano y se registran en `Content` por su id («fence_0», «fence_1»…), para
## que el guardado las encuentre.
## Después del vertical slice, las mismas dos piezas servirán para la valla básica del modo construcción (César).

const MODEL: PackedScene = preload("res://assets/models/props/fence.glb")
const ID_PREFIX: String = "fence_"
const PURPOSE: StringName = &"fence"
## Plano que enseña al repararla (sesión 30): la valla básica del modo construcción decorativo (D-215).
const BLUEPRINT: StringName = &"fence"
## Casillas de separación que aún unen dos trozos pintados en el mismo tramo (huecos sobre el agua).
const CHAIN_REACH: int = 2
## Búsqueda del borde, desde fuera hacia dentro por la línea que va del mar al camino: desde dónde (m, desde el centro
## de la casilla hacia fuera), hasta dónde hacia dentro, a qué pasos, cuánto puede bajar el suelo a cada lado del punto
## para no estar ya en la pared, cuánto por debajo de lo alto puede estar y cuánto se mete el poste hacia dentro.
const SEARCH_OUT: float = 1.0
const SEARCH_IN: float = 2.0
const SEARCH_STEP: float = 0.1
const RIM_PROBE: float = 0.25
const TOP_MARGIN: float = 0.35
const INSET: float = 0.3
## Pendiente (componente vertical de la normal) por debajo de la cual el suelo cuenta como pared o roca: un poco por
## encima de donde el terreno empieza a pintar roca en las cuestas (`slope_rock_up` 0,74 de `terrain.gdshader`), por
## el ruido que rompe su borde.
const RIM_UP: float = 0.78
## Una casilla vecina cuenta como «fuera» si es mar o agua o está al menos esto más baja (m): el lado del barranco.
const EDGE_DROP: float = 1.0
## Tramo más largo sin poste en medio (m) y cuánto se hunde el pie del poste en el suelo.
const MAX_SPAN: float = 1.45
const POST_SINK: float = 0.03
## Desnivel más grande entre dos postes que aún se salva enterrando el más alto (m); más, y el tramo se inclina.
const MAX_STEP: float = 0.35
## Ajustes a mano de César (sesión 26): cuánto más hacia dentro (m, del mar hacia el camino) va el poste de una casilla.
## El poste 1 del sendero quedaba demasiado cerca del filo.
const POST_NUDGES: Dictionary[Vector2i, float] = {Vector2i(21, 46): 0.45}
## Casillas pintadas cuyo poste no se pone (César, sesión 26): el último del sendero, junto al mirador, sobraba. Los
## postes intermedios de antes de él sí se quedan.
const POSTS_REMOVED: Array[Vector2i] = [Vector2i(24, 46)]
## Un poste necesita el suelo al menos a esta altura (m; el mar está por debajo de 0).
const WATER_CLEARANCE: float = 0.3
## Ataduras de esparto (César: las vueltas del poste las cortaban los troncos): dos vueltas en cada tronco, pegadas al
## poste en cada extremo. Alturas de los troncos sobre el pie del poste y perfil del poste (altura, radio en sus esquinas)
## copiados de `art/tools/fence_blockout.py` (LOW_RAIL_Z, HIGH_RAIL_Z, RAIL_RADIUS y POST_PARTS): si cambian allí,
## cambiarlos aquí.
const RAIL_HEIGHTS: Array[float] = [0.40, 0.71]
const RAIL_RADIUS: float = 0.05
const POST_PROFILE: Array[Vector2] = [
	Vector2(0.0, 0.105), Vector2(0.05, 0.105), Vector2(0.11, 0.125), Vector2(0.24, 0.135), Vector2(0.33, 0.115),
	Vector2(0.40, 0.07), Vector2(0.47, 0.09), Vector2(0.58, 0.095), Vector2(0.66, 0.078), Vector2(0.71, 0.062),
	Vector2(0.77, 0.085), Vector2(0.85, 0.09), Vector2(0.91, 0.07)]
const ROPE_MINOR: float = 0.012
## Cruz de esparto alrededor del poste (César, sesión 27: solo la cruz, como en la escala, sin las vueltas de cada
## tronco): dos lazos que dibujan una X
## delante y otra detrás, de CROSS_REACH por encima a CROSS_REACH por debajo del tronco, entre ±CROSS_ANGLE, y rodean los
## costados por encima y por debajo de él. Dos troncos a menos de CROSS_SAME de altura llevan una.
const CROSS_REACH: float = 0.085
const CROSS_ANGLE: float = 0.9076   # 52°
const CROSS_SAME: float = 0.03
## Cuadritos de la paleta del esparto (fila, columna), como `items_blockout.py`: claro y más claro.
const ROPE_SWATCHES: Array[Vector2i] = [Vector2i(0, 1), Vector2i(0, 0)]
const PALETTE_MATERIAL: Material = preload("res://assets/materials/palette.tres")
## Cada cuánto se mira el suelo entre dos postes para ver si hay agua o un barranco en medio (m).
const GAP_PROBE: float = 0.25


## Las barandillas del plano de `island`, sin poner aún: una lista de {"data": RepairSiteData, "origin": Vector2i}.
## Registra cada `data` en `Content`.
static func build(island: IslandState) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var layout: IslandLayout = island.layout
	if layout == null or layout.fence_cells.is_empty():
		return result
	var timber: ItemData = Content.find_item(&"timber")
	var rope: ItemData = Content.find_item(&"rope")
	var model: Node3D = MODEL.instantiate() as Node3D
	var post_template: Node3D = model.find_child("fence_post", true, false) as Node3D
	var log_template: Node3D = model.find_child("fence_log", true, false) as Node3D
	var runs: Array[Dictionary] = []
	for chain: Array in _chains(layout.fence_cells):
		var cells: Array[Vector2i] = []
		cells.assign(chain)
		runs.append_array(_runs(layout, cells))
	for index: int in runs.size():
		var points: PackedVector3Array = runs[index]["points"]
		var cells: Array[Vector2i] = []
		cells.assign(runs[index]["cells"])
		var min_cell: Vector2i = cells[0]
		var max_cell: Vector2i = cells[0]
		for cell: Vector2i in cells:
			min_cell = min_cell.min(cell)
			max_cell = max_cell.max(cell)
		var data := RepairSiteData.new()
		data.id = StringName(ID_PREFIX + str(index))
		data.name_key = "REPAIR_FENCE"
		data.size = max_cell - min_cell + Vector2i.ONE
		for cell: Vector2i in cells:
			data.blocked_cells.append(cell - min_cell)
		data.exact_collision = true   # cada tramo choca con su forma real al completarse
		data.purpose = PURPOSE
		data.unlocks = [BLUEPRINT]   # reparar cualquier tramo enseña a construir la valla (sesión 30, D-215)
		var center: Vector3 = GridMath.footprint_center(min_cell, data.size, 0, island.ground_height(min_cell))
		data.scene = _model(points, center, post_template, log_template)
		for i: int in points.size() - 1:
			var piece := RepairPieceData.new()
			piece.id = StringName("fence_%d" % i)
			piece.name_key = "REPAIR_PIECE_FENCE"
			piece.node_name = StringName("piece_fence_%d" % i)
			piece.cost[timber] = 1
			piece.cost[rope] = 1
			data.pieces.append(piece)
		Content.register_repair_site(data)
		result.append({"data": data, "origin": min_cell})
	model.free()
	return result


## Las casillas en tramos seguidos (dos casillas a CHAIN_REACH o menos van en el mismo), cada uno ordenado de un
## extremo al otro.
static func _chains(fence_cells: Array[Vector2i]) -> Array[Array]:
	var left: Array[Vector2i] = fence_cells.duplicate()
	var chains: Array[Array] = []
	while not left.is_empty():
		var group: Array[Vector2i] = [left.pop_front()]
		var i: int = 0
		while i < group.size():
			for j: int in range(left.size() - 1, -1, -1):
				if maxi(absi(group[i].x - left[j].x), absi(group[i].y - left[j].y)) <= CHAIN_REACH:
					group.append(left[j])
					left.remove_at(j)
			i += 1
		chains.append(_ordered(group))
	return chains


## De un extremo al otro: se empieza por la casilla más lejana de una cualquiera y se va a la más cercana que quede.
static func _ordered(group: Array[Vector2i]) -> Array[Vector2i]:
	var rest: Array[Vector2i] = group.duplicate()
	var start: Vector2i = rest[0]
	for cell: Vector2i in rest:
		if Vector2(cell - group[0]).length_squared() > Vector2(start - group[0]).length_squared():
			start = cell
	var order: Array[Vector2i] = [start]
	rest.erase(start)
	while not rest.is_empty():
		var best: int = 0
		for j: int in rest.size():
			if Vector2(rest[j] - order.back()).length_squared() < Vector2(rest[best] - order.back()).length_squared():
				best = j
		order.append(rest[best])
		rest.remove_at(best)
	return order


## Los postes de una cadena (en el mundo), en tramos seguidos: cerca del borde, la línea suavizada y con postes
## intermedios en los huecos. Donde entre dos postes hay agua o un barranco (la pintura saltó por encima de una entrada
## del mar, César), la valla se corta y sigue en otro tramo; un poste que no encuentra borde firme no se pone.
## Cada tramo: {"points": PackedVector3Array, "cells": Array[Vector2i]} (solo tramos con dos postes o más).
static func _runs(layout: IslandLayout, cells: Array[Vector2i]) -> Array[Dictionary]:
	var spots: Array[Vector2] = []
	var spot_cells: Array[Vector2i] = []
	for cell: Vector2i in cells:
		var center := Vector2(cell.x + 0.5, cell.y + 0.5)
		var here: float = layout.terrain_height(center.x, center.y)
		var outward := Vector2.ZERO
		for dy: int in range(-1, 2):
			for dx: int in range(-1, 2):
				var other := cell + Vector2i(dx, dy)
				if (dx != 0 or dy != 0) and (not layout.has_cell(other) or not layout.is_land(other)
						or layout.terrain_height(other.x + 0.5, other.y + 0.5) < here - EDGE_DROP):
					outward += Vector2(dx, dy)
		var spot: Vector2 = _rim_spot(layout, center, outward.normalized()) if outward != Vector2.ZERO else center
		if POST_NUDGES.has(cell) and outward != Vector2.ZERO and not is_nan(spot.x):
			spot -= outward.normalized() * POST_NUDGES[cell]
		if not is_nan(spot.x):
			spots.append(spot)
			spot_cells.append(cell)
	# Suavizar: cada poste de en medio, algo hacia la media de sus vecinos (sin escalones de casilla).
	var smooth: Array[Vector2] = spots.duplicate()
	for i: int in range(1, spots.size() - 1):
		smooth[i] = spots[i] * 0.5 + (spots[i - 1] + spots[i + 1]) * 0.25
	var runs: Array[Dictionary] = []
	var points := PackedVector3Array()
	var run_cells: Array[Vector2i] = []
	for i: int in smooth.size():
		var point := Vector3(smooth[i].x, layout.terrain_height(smooth[i].x, smooth[i].y) - POST_SINK, smooth[i].y)
		if not points.is_empty():
			var previous: Vector3 = points[points.size() - 1]
			if _crosses_gap(layout, previous, point):
				if points.size() >= 2:
					runs.append({"points": points, "cells": run_cells})
				points = PackedVector3Array()
				run_cells = []
			else:
				# Postes intermedios en los tramos largos, en el suelo.
				var steps: int = ceili(Vector2(point.x - previous.x, point.z - previous.z).length() / MAX_SPAN)
				for k: int in range(1, steps):
					var middle: Vector3 = previous.lerp(point, float(k) / steps)
					middle.y = layout.terrain_height(middle.x, middle.z) - POST_SINK
					points.append(middle)
		if POSTS_REMOVED.has(spot_cells[i]):
			continue
		points.append(point)
		run_cells.append(spot_cells[i])
	if points.size() >= 2:
		runs.append({"points": points, "cells": run_cells})
	return runs


## ¿Hay agua o un barranco entre dos postes? Se mira el suelo cada GAP_PROBE m de la línea que los une.
static func _crosses_gap(layout: IslandLayout, a: Vector3, b: Vector3) -> bool:
	var probes: int = maxi(ceili(Vector2(b.x - a.x, b.z - a.z).length() / GAP_PROBE), 1)
	var lowest: float = minf(a.y, b.y)
	for k: int in range(1, probes):
		var p: Vector3 = a.lerp(b, float(k) / probes)
		# Con el terreno dibujado (no las casillas del plano: sus bordes están desplazados).
		var ground: float = layout.terrain_height(p.x, p.z)
		if ground < WATER_CLEARANCE or ground < lowest - TOP_MARGIN:
			return true
	return false


## Dónde va el poste de una casilla del filo: se recorre la línea del mar (`outward`) al camino desde fuera y, pasada la
## parte empinada (la pared o la franja de roca: la pendiente del suelo, en todas direcciones como la mira el terreno
## para pintar la roca, pasa de RIM_UP), se toma el primer punto por encima del agua donde deja de serlo; el poste queda
## INSET más hacia dentro. En todas direcciones porque el sendero también baja a lo largo de la valla, y ahí el terreno
## pinta roca más adentro (César: los postes de abajo se quedaban sobre la roca). Así sigue las curvas del filo, también
## en el sendero, donde no hay pared sino una franja de roca y una cuesta de hierba hasta el camino (César: allí iba
## recta y se metía en el camino). Sin parte empinada, dentro de la casilla. NAN si no hay sitio.
static func _rim_spot(layout: IslandLayout, center: Vector2, outward: Vector2) -> Vector2:
	var inward: Vector2 = -outward
	var start: Vector2 = center + outward * SEARCH_OUT
	var seen_wall: bool = false
	for k: int in int((SEARCH_OUT + SEARCH_IN) / SEARCH_STEP) + 1:
		var spot: Vector2 = start + inward * (k * SEARCH_STEP)
		var here: float = layout.terrain_height(spot.x, spot.y)
		var up: float = _up(layout, spot)
		if here <= WATER_CLEARANCE:
			continue
		if up < RIM_UP:
			seen_wall = true
		elif seen_wall:
			return spot + inward * INSET
	# Sin borde: dentro de la casilla, salvo que ahí ya esté el agua (la casilla está dibujada sobre el mar).
	var fallback: Vector2 = center + inward * INSET
	if layout.terrain_height(fallback.x, fallback.y) > WATER_CLEARANCE:
		return fallback
	return Vector2(NAN, NAN)


## Componente vertical de la normal del suelo en un punto (1 = llano), con las alturas a RIM_PROBE a cada lado.
static func _up(layout: IslandLayout, p: Vector2) -> float:
	var slope_x: float = (layout.terrain_height(p.x + RIM_PROBE, p.y) - layout.terrain_height(p.x - RIM_PROBE, p.y)) \
			/ (2.0 * RIM_PROBE)
	var slope_z: float = (layout.terrain_height(p.x, p.y + RIM_PROBE) - layout.terrain_height(p.x, p.y - RIM_PROBE)) \
			/ (2.0 * RIM_PROBE)
	return 1.0 / sqrt(1.0 + slope_x * slope_x + slope_z * slope_z)


## El modelo: una pieza «piece_fence_<i>» por tramo, con su poste en el punto i, girada hacia el siguiente, y los
## troncos hasta él. Escalonada (César): los troncos van horizontales, a la altura del más bajo de sus dos postes, y el
## poste más alto se entierra para que el tramo quede recto; a cada lado de un poste pueden quedar a alturas distintas.
## Solo un desnivel de más de MAX_STEP inclina su tramo (si no, se enterraría media hormiga). El último tramo lleva
## también el poste final.
static func _model(points: PackedVector3Array, center: Vector3, post_template: Node3D,
		log_template: Node3D) -> PackedScene:
	var count: int = points.size()
	# Altura de cada tramo recto (o NAN si va inclinado) y de la base de cada poste: la más baja de su suelo y de los
	# tramos rectos que sujeta.
	var levels: Array[float] = []
	for i: int in count - 1:
		var step: float = absf(points[i + 1].y - points[i].y)
		levels.append(minf(points[i].y, points[i + 1].y) if step <= MAX_STEP else NAN)
	var bases: Array[float] = []
	for i: int in count:
		var base: float = points[i].y
		if i > 0 and not is_nan(levels[i - 1]):
			base = minf(base, levels[i - 1])
		if i < count - 1 and not is_nan(levels[i]):
			base = minf(base, levels[i])
		bases.append(base)
	var root := Node3D.new()
	root.name = "fence"
	var pieces: Array[Node3D] = []
	var rail_transforms: Array[Transform3D] = []
	var rail_lengths: Array[float] = []
	for i: int in count - 1:
		var to: Vector3 = points[i + 1] - points[i]
		var flat: float = Vector2(to.x, to.z).length()
		var piece := Node3D.new()
		piece.name = "piece_fence_%d" % i
		piece.position = Vector3(points[i].x, bases[i], points[i].z) - center
		piece.rotation.y = atan2(-to.z, to.x)   # +X del tramo, hacia el poste siguiente
		root.add_child(piece)
		var post: Node3D = post_template.duplicate() as Node3D
		post.transform = Transform3D.IDENTITY
		piece.add_child(post)
		# Troncos: la malla, estirada a lo largo del tramo (no el nodo: el choque no lleva bien una escala desigual).
		var rails: Node3D = log_template.duplicate() as Node3D
		var length: float = flat
		if is_nan(levels[i]):
			var rise: float = bases[i + 1] - bases[i]
			length = Vector2(flat, rise).length()
			rails.transform = Transform3D(Basis(Vector3.BACK, atan2(rise, flat)), Vector3.ZERO)
		else:
			rails.transform = Transform3D(Basis.IDENTITY, Vector3(0.0, levels[i] - bases[i], 0.0))
		for mesh: MeshInstance3D in rails.find_children("*", "MeshInstance3D", true, false):
			mesh.mesh = _stretched(mesh.mesh, length)
		if rails is MeshInstance3D:
			(rails as MeshInstance3D).mesh = _stretched((rails as MeshInstance3D).mesh, length)
		piece.add_child(rails)
		pieces.append(piece)
		rail_transforms.append(rails.transform)
		rail_lengths.append(length)
		if i == count - 2:
			var last: Node3D = post_template.duplicate() as Node3D
			last.transform = Transform3D(Basis.IDENTITY, Vector3(flat, bases[i + 1] - bases[i], 0.0))
			piece.add_child(last)
	# Las cruces de esparto de cada poste, a la altura de cada tronco que llega (una sola si los dos de los lados llegan a
	# la misma altura, César). Van en la pieza del poste (la del último poste, en el último tramo), giradas como ella.
	for i: int in count:
		var owner_index: int = mini(i, count - 2)
		var piece: Node3D = pieces[owner_index]
		var at: Vector3 = Vector3.ZERO
		if i == count - 1:
			at = rail_transforms[owner_index] * Vector3(rail_lengths[owner_index], 0.0, 0.0)
			at = Vector3(at.x, bases[i] - bases[owner_index], 0.0)
		var heights: Array[float] = []
		for rail_height: float in RAIL_HEIGHTS:
			if i < count - 1:   # el tronco que sale
				heights.append((rail_transforms[i] * Vector3(0.0, rail_height, 0.0)).y)
			if i > 0:   # el que llega, medido desde el pie de este poste
				var end: Vector3 = rail_transforms[i - 1] * Vector3(rail_lengths[i - 1], rail_height, 0.0)
				heights.append(end.y - (bases[i] - bases[i - 1]))
		var placed: Array[float] = []
		for height: float in heights:
			var repeated: bool = false
			for other: float in placed:
				repeated = repeated or absf(other - height) < CROSS_SAME
			if repeated:
				continue
			placed.append(height)
			var cross := MeshInstance3D.new()
			cross.name = "fence_cross"
			cross.mesh = _cross_lashing(height)
			cross.position = at
			piece.add_child(cross)
	_set_owner(root, root)
	var scene := PackedScene.new()
	scene.pack(root)
	root.free()
	return scene


## Radio del poste (en sus esquinas) a una altura sobre su pie, del perfil POST_PROFILE.
static func _post_radius(height: float) -> float:
	for k: int in POST_PROFILE.size() - 1:
		var a: Vector2 = POST_PROFILE[k]
		var b: Vector2 = POST_PROFILE[k + 1]
		if height <= b.x:
			return lerpf(a.y, b.y, clampf((height - a.x) / (b.x - a.x), 0.0, 1.0))
	return POST_PROFILE[POST_PROFILE.size() - 1].y


static var _crosses: Dictionary[int, ArrayMesh] = {}
static var _rope_material: Material = null


## El material de la cuerda: el de la paleta, por las dos caras (así no importa el sentido de sus caras al generarlas).
static func _rope_mat() -> Material:
	if _rope_material == null:
		_rope_material = PALETTE_MATERIAL.duplicate()
		if _rope_material is BaseMaterial3D:
			(_rope_material as BaseMaterial3D).cull_mode = BaseMaterial3D.CULL_DISABLED
	return _rope_material


## Cruz de esparto alrededor del poste a una altura sobre su pie (el eje del tronco): en el espacio del poste, con el
## tronco a lo largo de X. Son dos lazos cerrados que abrazan el poste (César: con las aspas sueltas, los cabos no se unían
## a nada): cada uno cruza en diagonal por delante, rodea un costado por debajo (o por encima) del tronco, cruza en
## diagonal por detrás y vuelve por el otro costado por encima (o por debajo). Juntos dibujan una X delante y otra
## detrás, y por los costados pasan por encima y por debajo del tronco, como una atadura de verdad. Cada tira sigue la
## superficie del poste (su perfil). Una malla por cada centímetro de altura.
static func _cross_lashing(height: float) -> ArrayMesh:
	var key: int = roundi(height * 100.0)
	if _crosses.has(key):
		return _crosses[key]
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var uv := Vector2((ROPE_SWATCHES[0].y * 8 + 4) / 64.0, (ROPE_SWATCHES[0].x * 8 + 4) / 64.0)
	var diagonal_steps: int = 6
	var side_steps: int = 3
	for slope: float in [1.0, -1.0]:
		# Ángulos alrededor del poste (0 = delante) y alturas de cada tramo del lazo: diagonal delante, costado,
		# diagonal detrás y el otro costado.
		var path: Array[Vector3] = []
		var legs: Array[Array] = [
			[-CROSS_ANGLE, CROSS_ANGLE, CROSS_REACH, -CROSS_REACH, diagonal_steps],
			[CROSS_ANGLE, PI - CROSS_ANGLE, -CROSS_REACH, -CROSS_REACH, side_steps],
			[PI - CROSS_ANGLE, PI + CROSS_ANGLE, -CROSS_REACH, CROSS_REACH, diagonal_steps],
			[PI + CROSS_ANGLE, TAU - CROSS_ANGLE, CROSS_REACH, CROSS_REACH, side_steps],
		]
		for leg: Array in legs:
			var steps: int = leg[4]
			for k: int in steps:   # sin el último punto: es el primero del tramo siguiente (el lazo se cierra solo)
				var t: float = float(k) / steps
				var angle: float = lerpf(leg[0], leg[1], t)
				var y: float = height + lerpf(leg[2], leg[3], t) * slope
				var radius: float = _post_radius(y) + ROPE_MINOR + 0.002
				path.append(Vector3(sin(angle) * radius, y, cos(angle) * radius))
		_add_tube(tool, path, ROPE_MINOR, uv, true)
	tool.generate_normals()
	var mesh: ArrayMesh = tool.commit()
	mesh.surface_set_material(0, _rope_mat())
	_crosses[key] = mesh
	return mesh


## Tira de cuerda de sección cuadrada a lo largo de `path`: cerrada en lazo (`closed`) o con las puntas tapadas.
static func _add_tube(tool: SurfaceTool, path: Array[Vector3], half: float, uv: Vector2, closed: bool = false) -> void:
	var count: int = path.size()
	var rings: Array[PackedVector3Array] = []
	for k: int in count:
		var next: Vector3 = path[(k + 1) % count] if closed else path[mini(k + 1, count - 1)]
		var previous: Vector3 = path[(k - 1 + count) % count] if closed else path[maxi(k - 1, 0)]
		var along: Vector3 = (next - previous).normalized()
		var out := Vector3(path[k].x, 0.0, path[k].z).normalized()   # hacia fuera del poste
		var side: Vector3 = along.cross(out).normalized()
		out = side.cross(along).normalized()
		rings.append(PackedVector3Array([path[k] + (out + side) * half, path[k] + (out - side) * half,
				path[k] + (-out - side) * half, path[k] + (-out + side) * half]))
	for k: int in (count if closed else count - 1):
		var a: PackedVector3Array = rings[k]
		var b: PackedVector3Array = rings[(k + 1) % count]
		for c: int in 4:
			var d: int = (c + 1) % 4
			for v: Vector3 in [a[c], b[c], b[d], a[c], b[d], a[d]]:
				tool.set_uv(uv)
				tool.add_vertex(v)
	if closed:
		return
	for cap: PackedVector3Array in [rings[0], rings[count - 1]]:
		for v: Vector3 in [cap[0], cap[1], cap[2], cap[0], cap[2], cap[3]]:
			tool.set_uv(uv)
			tool.add_vertex(v)


## Copia de `mesh` estirada en X (los troncos miden 1 m a lo largo de +X).
static func _stretched(mesh: Mesh, length: float) -> ArrayMesh:
	var result := ArrayMesh.new()
	if mesh == null:
		return result
	for surface: int in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(surface)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for v: int in verts.size():
			verts[v].x *= length
		arrays[Mesh.ARRAY_VERTEX] = verts
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		result.surface_set_material(surface, mesh.surface_get_material(surface))
	return result


static func _set_owner(node: Node, owner: Node) -> void:
	for child: Node in node.get_children():
		child.owner = owner
		_set_owner(child, owner)
