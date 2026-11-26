class_name TerrainView
extends Node3D
## Suelo de una isla con su agua (B3.7, D-094). Sustituye al suelo plano del sandbox: genera el terreno
## de `IslandState.bounds` y, donde hay agua, lo hunde con rampas suaves hasta el fondo (César: «una
## transición natural, no muros»), con arena en las rampas y el fondo. Encima, el agua de juguete
## (`water.gdshader`, C5.4d): turquesa en la orilla y azul en lo hondo, espuma, brillos y, en ríos y canales,
## corriente; quieta en lagos (`flow` = (0, 0)) y en el mar. Por el agua se puede andar (César); nadar, más adelante.
##
## Cómo es el terreno: una rejilla de medio metro. Un punto está en el fondo solo si todas las casillas
## que toca son agua; así un canal de 1 casilla tiene rampas de medio metro a cada lado y su centro hundido.
## Dónde tocar: profundidad, alturas y colores en las constantes; la corriente en FLOW_SPEED.
##
## Con plano (C5.3d, D-155) el terreno es otro, provisional hasta C5.4: una altura por casilla (0 abajo, 6 m
## arriba; la ladera sube poco a poco entre las dos), los bordes de las explanadas planos del todo, fondo bajo el
## agua y el mar. Los colores (C5.4a) los pone `terrain.gdshader` según la zona y la pendiente. Alrededor, el mar.

## Profundidad del fondo y altura del agua (el suelo está a 0).
const DEPTH: float = 0.4
const WATER_Y: float = -0.08
## En las islas con plano, el agua del río y del lago va casi a ras de la orilla, como un río lleno (C5.3d).
const LAYOUT_WATER_Y: float = -0.02
## Velocidad de la corriente de los ríos (m/s; el shader la multiplica por `flow_visual`).
const FLOW_SPEED: float = 0.6
## Rapidez de cada tramo de río: RIVER_PACE_WIDTH / su ancho, entre el mínimo y el máximo (C5.4d).
const RIVER_PACE_WIDTH: float = 4.0
const RIVER_PACE_MIN: float = 0.6
const RIVER_PACE_MAX: float = 1.8
## El mar de las islas con plano: a qué altura está y cuántos metros se dibujan alrededor del plano, hasta donde la
## bruma ya lo tapa todo, para que no se vea dónde acaba (César).
const SEA_Y: float = -0.25
const SEA_MARGIN: float = 1500.0
## Shader del suelo de las islas con plano (C5.4a): mezcla hierba, arena, arena mojada, tierra del sendero, roca
## y fondo según lo que cada esquina lleva apuntado, con ruido para que no se vea plano. Los colores, en el shader.
const TERRAIN_SHADER: Shader = preload("res://entities/nature/terrain.gdshader")
## Lo que cuenta el sendero en el rellano (también es tierra pisada, pero más clara y gastada).
const LANDING_AS_PATH: float = 0.6
## Casillas desde el borde de una explanada en las que los claros de tierra y las manchas suaves aparecen poco a poco.
const FLAT_FADE_CELLS: float = 4.0
## Puntos del terreno por casilla y lado (2 = cada medio metro, C5.4b).
const GROUND_SUBDIVISIONS: int = 2
## Superficie del agua para las esquinas que no tocan agua: tan abajo que nada queda bajo ella.
const NO_WATER_SURFACE: float = -100.0
## Claros cerca del agua (sesión 28, César: junto al lago salía uno cortado en escalones por la regla de «sin claros
## junto a la orilla» del shader): se apagan poco a poco entre estas distancias (casillas) al lago, el río y el remanso.
const CLEARING_WATER_FROM: float = 4.0
const CLEARING_WATER_TO: float = 10.0
## Lo mismo que `terrain.gdshader` para pintar los claros (para saber en las pisadas si se pisa tierra).
const CLEARING_THRESHOLD: float = 0.53
## Hasta cuántas esquinas tierra adentro llega la marca de «mojado» desde el mar (sesión 23, César: la arena mojada no
## se veía, porque las esquinas que tocan el mar ya están bajo el agua). El shader la limita a `wet_height` sobre el
## agua, así que en la playa sale una franja natural. Solo desde el mar: en el río y el lago sigue pegada al agua.
const SEA_WET_SPREAD: int = 3
## Desembocadura (sesión 23, César: el río acababa cortado sobre el mar, que está 23 cm más abajo): en las últimas
## MOUTH_CELLS casillas antes del mar, la superficie del río baja poco a poco hasta el nivel del mar.
const MOUTH_CELLS: int = 4
const MOUTH_ABOVE_SEA: float = 0.01   # un pelo por encima del mar, para que las dos láminas no parpadeen
## Hasta cuántas esquinas de distancia se lleva la superficie del agua tierra adentro.
const WATER_SURFACE_SPREAD: int = 3

## Césped 3D (C5.6, D-179): en las islas con plano, `GrassField` pregunta aquí la altura del suelo y dónde puede crecer.
## Se guarda la rejilla del suelo (un punto cada medio metro, la misma de la malla) con su altura, cuánta hierba admite
## cada punto (0 a 1) y lo metido que está en su explanada (para los claros, que quita el shader del césped).
const GRASS_MATERIAL: ShaderMaterial = preload("res://assets/materials/grass.tres")
## Sin césped por debajo de esta altura sobre el agua cercana (la orilla). Donde el terreno pinta roca, el césped lo quita
## su shader con la misma cuenta y el mismo ruido que `terrain.gdshader` (le llegan la pendiente y la pared de cada mata,
## `get_up_at` y `get_wall_at`). Aquí solo se descarta lo que seguro es roca (pendiente por debajo de *_ROCK_UP, más allá
## del ruido del borde), para no generar matas que no se verían.
## Sesión 28 (César: en la orilla de la explanada baja no crecía): la explanada está a 0 y el río a −0,02; con 0,03 el
## césped la tomaba por sumergida. Con 0,01 llega hasta el borde del agua y sigue sin crecer bajo ella.
const GRASS_ABOVE_WATER: float = 0.01
const GRASS_SLOPE_ROCK_UP: float = 0.58
const GRASS_WALL_ROCK_UP: float = 0.64
const GRASS_ROCK_FADE: float = 0.04
const GRASS_WALL_FROM: float = 0.15
## Objetos del plano bajo los que no crece: todos menos las arboledas y los árboles sueltos.
const GRASS_FREE_FEATURES: String = "Tt"
var _grass: GrassField = null
var _grid_count: Vector2i = Vector2i.ZERO
var _grid_step: float = 0.5
var _grid_heights: PackedFloat32Array = PackedFloat32Array()
var _grid_grass: PackedFloat32Array = PackedFloat32Array()
var _grid_flat: PackedFloat32Array = PackedFloat32Array()
var _grid_wall: PackedFloat32Array = PackedFloat32Array()
var _grid_up: PackedFloat32Array = PackedFloat32Array()

## Agua de juguete (C5.4d): el mismo shader, con corriente en los ríos y sin ella en lagos, estanques y el mar.
const WATER_SHADER: Shader = preload("res://entities/nature/water.gdshader")
var _water_material: ShaderMaterial
var _ground: MeshInstance3D
var _water: MeshInstance3D
var _body: StaticBody3D
var _sea: MeshInstance3D
var _collision: CollisionShape3D
## Plano de la isla (si la isla tiene), para saber dónde hay agua al pisar (`get_footstep_surface`).
var _layout: IslandLayout = null
## Pisadas: por debajo de esta pendiente (componente vertical de la normal) el suelo es roca, como lo pinta
## `terrain.gdshader` (`slope_rock_up`); en las paredes del plano, desde `FOOTSTEP_WALL_UP` (`wall_rock_up`).
const FOOTSTEP_ROCK_UP: float = 0.74
const FOOTSTEP_WALL_UP: float = 0.8


func _init() -> void:
	_water_material = _make_water_material()
	_ground = MeshInstance3D.new()
	add_child(_ground)
	_water = MeshInstance3D.new()
	_water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_water)
	_sea = MeshInstance3D.new()
	_sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_sea)
	_body = StaticBody3D.new()
	add_child(_body)
	_collision = CollisionShape3D.new()
	_body.add_child(_collision)


## Rehace el suelo, su colisión y el agua desde los datos de la isla. Sin `bounds`, no hay suelo.
func rebuild(island: IslandState) -> void:
	_layout = island.layout
	var bounds: Rect2i = island.bounds
	if not bounds.has_area():
		_ground.mesh = null
		_water.mesh = null
		_collision.shape = null
		return
	if island.layout != null:
		_build_layout_ground(island)
		_build_sea(island.layout)
		_build_debris(island.layout)
		_build_cascade(island)
		_refresh_grass(island.layout)
	else:
		_build_ground(island, bounds)
		_sea.mesh = null
	_build_water(island)


func _build_ground(island: IslandState, bounds: Rect2i) -> void:
	# Rejilla de medio metro: índice par = borde de casilla, impar = centro de casilla.
	var count_x: int = bounds.size.x * 2 + 1
	var count_z: int = bounds.size.y * 2 + 1
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j: int in count_z:
		for i: int in count_x:
			var depth: float = 0.0
			var shore: bool = false
			var cells: Array[Vector2i] = _touching_cells(bounds, i, j)
			var all_water: bool = true
			for cell: Vector2i in cells:
				if island.water.has(cell):
					shore = true
				else:
					all_water = false
			if all_water and shore:
				depth = DEPTH
			# Mismos datos que `_build_layout_ground()` para usar `terrain.gdshader` (C5.6, César: el sandbox con el
			# suelo de Isla Alba, para juzgar el césped): arena y mojado en la orilla, todo explanada y, junto al agua,
			# su superficie, para que el fondo se oscurezca con la hondura.
			var near: float = 1.0 if shore else 0.0
			tool.set_color(Color(near, near, 0.0, 0.0))
			tool.set_uv2(Vector2(WATER_Y if shore else NO_WATER_SURFACE, 1.0))
			tool.add_vertex(Vector3(bounds.position.x + i * 0.5, -depth, bounds.position.y + j * 0.5))
	for j: int in count_z - 1:
		for i: int in count_x - 1:
			var a: int = j * count_x + i
			var b: int = a + 1
			var c: int = a + count_x
			var d: int = c + 1
			for index: int in [a, b, d, a, d, c]:
				tool.add_index(index)
	tool.generate_normals()
	var mesh: ArrayMesh = tool.commit()
	var material := ShaderMaterial.new()
	material.shader = TERRAIN_SHADER
	mesh.surface_set_material(0, material)
	_ground.mesh = mesh
	_collision.shape = mesh.create_trimesh_shape()


## Casillas que toca un punto de la rejilla (1, 2 o 4), solo las que están dentro de la isla.
func _touching_cells(bounds: Rect2i, i: int, j: int) -> Array[Vector2i]:
	var xs: Array[int] = _touching_columns(bounds.position.x, i)
	var zs: Array[int] = _touching_columns(bounds.position.y, j)
	var cells: Array[Vector2i] = []
	for x: int in xs:
		for z: int in zs:
			var cell := Vector2i(x, z)
			if bounds.has_point(cell):
				cells.append(cell)
	return cells


## Columnas (o filas) de casillas que toca el índice `index` de la rejilla de medio metro: una si es el
## centro de una casilla (impar), dos si es el borde entre dos (par).
func _touching_columns(start: int, index: int) -> Array[int]:
	var result: Array[int] = []
	var half: int = floori(index * 0.5)
	if index % 2 == 1:
		result.append(start + half)
	else:
		result.append(start + half - 1)
		result.append(start + half)
	return result


## El agua de los ríos, lagos y canales: una lámina por casilla de agua. Cada esquina lleva la corriente en sus UV.
func _build_water(island: IslandState) -> void:
	if island.water.is_empty():
		_water.mesh = null
		return
	var offset: float = LAYOUT_WATER_Y if island.layout != null else WATER_Y
	# Superficie de cada casilla de agua. El borde de la lámina queda tapado por la orilla, que está justo por encima
	# (`IslandLayout.SHORE_ABOVE_WATER`); la forma de la orilla la da el fondo, que se deforma (C5.4d).
	var surfaces: Dictionary[Vector2i, float] = {}
	for cell: Vector2i in island.water:
		surfaces[cell] = island.ground_height(cell) + offset
	var mouth: Dictionary[Vector2i, int] = _mouth_distances(island)
	for cell: Vector2i in mouth:
		var sea_level: float = SEA_Y + MOUTH_ABOVE_SEA
		surfaces[cell] = lerpf(sea_level, surfaces[cell], float(mouth[cell]) / float(MOUTH_CELLS))
	# Las de la desembocadura y sus vecinas se dibujan con la altura por esquinas (sin escalón donde empieza la bajada).
	var smooth: Dictionary[Vector2i, bool] = {}
	for cell: Vector2i in mouth:
		for dx: int in [-1, 0, 1]:
			for dz: int in [-1, 0, 1]:
				if surfaces.has(cell + Vector2i(dx, dz)):
					smooth[cell + Vector2i(dx, dz)] = true
	var shore: Dictionary[Vector2i, float] = {}
	# Corriente en cada esquina: la media de las casillas de agua que la tocan (velocidad en m/s, con su rapidez),
	# para que pase suave de una casilla a otra.
	var corner_flow: Dictionary[Vector2i, Vector2] = {}
	var corner_count: Dictionary[Vector2i, int] = {}
	for cell: Vector2i in island.water:
		var flow: Vector2i = island.water[cell]
		var velocity := Vector2.ZERO
		if flow != Vector2i.ZERO:
			var pace: float = clampf(RIVER_PACE_WIDTH / float(_river_width(island, cell, flow)), RIVER_PACE_MIN, RIVER_PACE_MAX)
			velocity = Vector2(flow).normalized() * FLOW_SPEED * pace
		for corner: Vector2i in [cell, cell + Vector2i(1, 0), cell + Vector2i(0, 1), cell + Vector2i(1, 1)]:
			corner_flow[corner] = corner_flow.get(corner, Vector2.ZERO) + velocity
			corner_count[corner] = corner_count.get(corner, 0) + 1
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for cells: Dictionary[Vector2i, float] in [surfaces, shore]:
		var on_shore: float = 1.0 if cells == shore else 0.0   # el shader borra la orilla sobre un salto
		for cell: Vector2i in cells:
			var y: float = cells[cell]
			var corners: Array[Vector2i] = [cell, cell + Vector2i(1, 0), cell + Vector2i(1, 1), cell + Vector2i(0, 1)]
			for index: int in [0, 1, 2, 0, 2, 3]:
				var corner: Vector2i = corners[index]
				var velocity: Vector2 = corner_flow.get(corner, Vector2.ZERO) / float(maxi(corner_count.get(corner, 1), 1))
				# En la desembocadura, cada esquina a la altura media de lo que toca (así la bajada al mar es continua).
				var corner_y: float = _mouth_corner_height(island, surfaces, mouth, cell, corner) if smooth.has(cell) else y
				tool.set_normal(Vector3.UP)
				tool.set_color(Color(1.0, on_shore, 0.0))
				tool.set_uv(velocity)
				tool.add_vertex(Vector3(corner.x, corner_y, corner.y))
	var mesh: ArrayMesh = tool.commit()
	mesh.surface_set_material(0, _water_material)
	_water.mesh = mesh


## Casillas de agua a menos de MOUTH_CELLS pasos de una casilla de mar (0 = la que lo toca), por el agua.
func _mouth_distances(island: IslandState) -> Dictionary[Vector2i, int]:
	var result: Dictionary[Vector2i, int] = {}
	if island.layout == null:
		return result
	var queue: Array[Vector2i] = []
	for cell: Vector2i in island.water:
		for side: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			if island.layout.ground(cell + side) == IslandLayout.Ground.SEA:
				result[cell] = 0
				queue.append(cell)
				break
	var head: int = 0
	while head < queue.size():
		var cell: Vector2i = queue[head]
		head += 1
		if result[cell] + 1 >= MOUTH_CELLS:
			continue
		for side: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var other: Vector2i = cell + side
			if island.water.has(other) and not result.has(other) \
					and is_equal_approx(island.ground_height(other), island.ground_height(cell)):
				result[other] = result[cell] + 1
				queue.append(other)
	return result


## Altura de una esquina de la lámina en la desembocadura: la media de las casillas de agua de la misma altura que la
## tocan y, si toca el mar, también la del mar.
func _mouth_corner_height(island: IslandState, surfaces: Dictionary[Vector2i, float], mouth: Dictionary[Vector2i, int],
		cell: Vector2i, corner: Vector2i) -> float:
	var sum: float = 0.0
	var count: int = 0
	for other: Vector2i in [corner + Vector2i(-1, -1), corner + Vector2i(0, -1), corner + Vector2i(-1, 0), corner]:
		if surfaces.has(other) and (mouth.has(other) or is_equal_approx(island.ground_height(other), island.ground_height(cell))):
			sum += surfaces[other]
			count += 1
		elif island.layout.ground(other) == IslandLayout.Ground.SEA:
			sum += SEA_Y + MOUTH_ABOVE_SEA
			count += 1
	return sum / float(count) if count > 0 else surfaces[cell]


## Ancho del río en esta casilla: casillas de agua seguidas de lado a lado de la corriente (hasta unas pocas).
func _river_width(island: IslandState, cell: Vector2i, flow: Vector2i) -> int:
	var side := Vector2i(-flow.y, flow.x)
	var width: int = 1
	for direction: int in [1, -1]:
		var other: Vector2i = cell + side * direction
		while island.water.has(other) and width < 12:
			width += 1
			other += side * direction
	return width


## Las esquinas que no tocan agua toman la superficie del agua más cercana (hasta unas casillas): así, entre una esquina
## de la orilla y la siguiente, la superficie no se hunde y el shader sabe dónde está el agua.
func _spread_water_surface(surface: PackedFloat32Array, row: int, rows: int) -> void:
	var queue: Array[Vector2i] = []
	var steps := PackedInt32Array()
	steps.resize(surface.size())
	steps.fill(-1)
	for j: int in rows:
		for i: int in row:
			if surface[j * row + i] > NO_WATER_SURFACE:
				steps[j * row + i] = 0
				queue.append(Vector2i(i, j))
	var head: int = 0
	while head < queue.size():
		var corner: Vector2i = queue[head]
		head += 1
		var index: int = corner.y * row + corner.x
		if steps[index] >= WATER_SURFACE_SPREAD:
			continue
		for offset: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var other: Vector2i = corner + offset
			if other.x < 0 or other.y < 0 or other.x >= row or other.y >= rows:
				continue
			var other_index: int = other.y * row + other.x
			if steps[other_index] == -1:
				steps[other_index] = steps[index] + 1
				surface[other_index] = surface[index]
				queue.append(other)


## Marca como mojadas las esquinas a menos de SEA_WET_SPREAD pasos de una esquina que toca el mar.
func _spread_sea_wet(layout: IslandLayout, wet: PackedFloat32Array, row: int, rows: int) -> void:
	var queue: Array[Vector2i] = []
	var steps := PackedInt32Array()
	steps.resize(wet.size())
	steps.fill(-1)
	for j: int in rows:
		for i: int in row:
			for cell: Vector2i in [Vector2i(i - 1, j - 1), Vector2i(i, j - 1), Vector2i(i - 1, j), Vector2i(i, j)]:
				if layout.ground(cell) == IslandLayout.Ground.SEA:
					steps[j * row + i] = 0
					queue.append(Vector2i(i, j))
					break
	var head: int = 0
	while head < queue.size():
		var corner: Vector2i = queue[head]
		head += 1
		var index: int = corner.y * row + corner.x
		if steps[index] >= SEA_WET_SPREAD:
			continue
		for offset: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var other: Vector2i = corner + offset
			if other.x < 0 or other.y < 0 or other.x >= row or other.y >= rows:
				continue
			var other_index: int = other.y * row + other.x
			if steps[other_index] == -1:
				steps[other_index] = steps[index] + 1
				wet[other_index] = 1.0
				queue.append(other)


## Valor de una rejilla de esquinas en un punto (interpolado entre las cuatro esquinas de su casilla).
func _lerp_corners(values: PackedFloat32Array, row: int, x: float, z: float) -> float:
	@warning_ignore("integer_division")
	var height_count: int = values.size() / row
	var i: int = clampi(floori(x), 0, row - 2)
	var j: int = clampi(floori(z), 0, height_count - 2)
	var fx: float = clampf(x - i, 0.0, 1.0)
	var fz: float = clampf(z - j, 0.0, 1.0)
	return lerpf(lerpf(values[j * row + i], values[j * row + i + 1], fx),
			lerpf(values[(j + 1) * row + i], values[(j + 1) * row + i + 1], fx), fz)


## Suelo de una isla con plano. Cada esquina lleva lo que la rodea, para el shader:
## color (r) arena: playa y mar; (g) mojado: toca agua o mar; (b) tierra pisada (sendero y sus extremos);
## (a) altura de 0 (abajo) a 1 (arriba);
## uv2 (x) superficie del agua que toca (m, muy abajo si no toca ninguna); (y) explanada (donde se construye, con menos manchas para que se lea).
## La roca la decide el shader por la pendiente.
func _build_layout_ground(island: IslandState) -> void:
	var layout: IslandLayout = island.layout
	var w: int = layout.size.x
	var h: int = layout.size.y
	var row: int = w + 1
	# Primero, lo de cada esquina de casilla: (w + 1) × (h + 1).
	var sand_at := PackedFloat32Array()
	var wet_at := PackedFloat32Array()
	var path_at := PackedFloat32Array()
	var flat_at := PackedFloat32Array()
	var depth_at := PackedFloat32Array()
	for values: PackedFloat32Array in [sand_at, wet_at, path_at, flat_at, depth_at]:
		values.resize(row * (h + 1))
	var water_distance: PackedFloat32Array = _water_distances(layout)
	for j: int in h + 1:
		for i: int in w + 1:
			var sand: float = 0.0
			var path: float = 0.0
			var flat: float = 0.0
			var wet: float = 0.0
			var water_surface: float = -INF
			# Junto al césped pintado (sesión 26), sin arena ni tierra: la hierba llega hasta el filo del acantilado del
			# mirador (el mar de al lado ponía una franja de arena en lo alto, César).
			var lawn: bool = false
			for cell: Vector2i in [Vector2i(i - 1, j - 1), Vector2i(i, j - 1), Vector2i(i - 1, j), Vector2i(i, j)]:
				lawn = lawn or layout.is_forced_grass(cell)
			for cell: Vector2i in [Vector2i(i - 1, j - 1), Vector2i(i, j - 1), Vector2i(i - 1, j), Vector2i(i, j)]:
				match layout.ground(cell):
					IslandLayout.Ground.BEACH:
						sand += 0.25
					IslandLayout.Ground.SEA:
						sand += 0.25
						wet = 1.0
						water_surface = maxf(water_surface, SEA_Y)
					IslandLayout.Ground.WATER:
						wet = 1.0
						water_surface = maxf(water_surface, island.ground_height(cell) + LAYOUT_WATER_Y)
					IslandLayout.Ground.LANDING:
						if not layout.is_forced_grass(cell):   # el césped pintado (sesión 26) quita la tierra del rellano
							path += 0.25 * LANDING_AS_PATH
				path += 0.25 * layout.wear(cell)
				# Lo metida que está en su explanada, suave: los claros se apagan antes del borde (César: junto al lago
				# salía uno cortado en seco por las casillas).
				var near_water: float = water_distance[cell.y * w + cell.x] if layout.has_cell(cell) else CLEARING_WATER_TO
				flat += 0.25 * smoothstep(0.5, FLAT_FADE_CELLS, layout.flat_depth(cell)) \
						* smoothstep(CLEARING_WATER_FROM, CLEARING_WATER_TO, near_water)
			if lawn:
				sand = 0.0
				path = 0.0
			var index: int = j * row + i
			sand_at[index] = sand
			wet_at[index] = wet
			path_at[index] = path
			flat_at[index] = flat
			# La superficie del agua que toca: el shader calcula la hondura en cada punto. Interpolar la hondura de las
			# esquinas pintaba de fondo medio acantilado (captura de César).
			depth_at[index] = water_surface if water_surface > -INF else NO_WATER_SURFACE
	_spread_water_surface(depth_at, row, h + 1)
	_spread_sea_wet(layout, wet_at, row, h + 1)
	# Después, un punto cada medio metro (C5.4b: para que las lomas se vean redondas), con la altura del terreno
	# (`IslandLayout.terrain_height()`, la misma que usan los árboles y las rocas) y lo de las esquinas interpolado.
	var step: float = 1.0 / GROUND_SUBDIVISIONS
	var count_x: int = w * GROUND_SUBDIVISIONS + 1
	var count_z: int = h * GROUND_SUBDIVISIONS + 1
	_grid_count = Vector2i(count_x, count_z)
	_grid_step = step
	for values: PackedFloat32Array in [_grid_heights, _grid_grass, _grid_flat, _grid_wall, _grid_up]:
		values.resize(count_x * count_z)
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for b: int in count_z:
		for a: int in count_x:
			var x: float = a * step
			var z: float = b * step
			var y: float = layout.terrain_height(x, z)
			var sand: float = _lerp_corners(sand_at, row, x, z)
			var path: float = _lerp_corners(path_at, row, x, z)
			var water_surface: float = _lerp_corners(depth_at, row, x, z)
			var flat: float = _lerp_corners(flat_at, row, x, z)
			var wall: float = layout.wall_amount(x, z)
			var grid_index: int = b * count_x + a
			_grid_heights[grid_index] = y
			_grid_flat[grid_index] = flat
			_grid_wall[grid_index] = wall
			_grid_grass[grid_index] = _grass_amount(layout, x, z, y, sand, path, water_surface)
			tool.set_color(Color(sand, _lerp_corners(wet_at, row, x, z), path, clampf(y / IslandLayout.LEVEL_HEIGHT, 0.0, 1.0)))
			tool.set_uv2(Vector2(water_surface, flat))
			# UV.x: el borde de hierba que asoma por lo alto de una pared; UV.y: lo que es pared (solo ahí hay roca, C5.6).
			tool.set_uv(Vector2(layout.wall_lip(x, z), wall))
			tool.add_vertex(Vector3(x, y, z))
	for b: int in count_z - 1:
		for a: int in count_x - 1:
			var p0: int = b * count_x + a
			var p1: int = p0 + 1
			var p2: int = p0 + count_x
			var p3: int = p2 + 1
			for index: int in [p0, p1, p3, p0, p3, p2]:
				tool.add_index(index)
	tool.generate_normals()
	var mesh: ArrayMesh = tool.commit()
	var material := ShaderMaterial.new()
	material.shader = TERRAIN_SHADER
	mesh.surface_set_material(0, material)
	_ground.mesh = mesh
	_collision.shape = mesh.create_trimesh_shape()
	_remove_steep_grass()


## Distancia (casillas, en diagonal también cuenta 1) de cada casilla al agua de la isla (lago, río, remanso), hasta
## CLEARING_WATER_TO. Para apagar los claros cerca de la orilla.
func _water_distances(layout: IslandLayout) -> PackedFloat32Array:
	var w: int = layout.size.x
	var h: int = layout.size.y
	var distances := PackedFloat32Array()
	distances.resize(w * h)
	distances.fill(CLEARING_WATER_TO)
	var frontier: Array[Vector2i] = []
	for y: int in h:
		for x: int in w:
			if layout.ground(Vector2i(x, y)) == IslandLayout.Ground.WATER:
				distances[y * w + x] = 0.0
				frontier.append(Vector2i(x, y))
	var steps: float = 0.0
	while not frontier.is_empty() and steps < CLEARING_WATER_TO:
		steps += 1.0
		var next: Array[Vector2i] = []
		for cell: Vector2i in frontier:
			for dy: int in range(-1, 2):
				for dx: int in range(-1, 2):
					var other := Vector2i(cell.x + dx, cell.y + dy)
					if other.x < 0 or other.y < 0 or other.x >= w or other.y >= h:
						continue
					if distances[other.y * w + other.x] > steps:
						distances[other.y * w + other.x] = steps
						next.append(other)
		frontier = next
	return distances


## Cuánta hierba admite un punto del suelo (0 a 1): nada bajo el agua ni en la orilla, en la arena, en el sendero y la
## tierra pisada, ni en las casillas de agua, de los objetos del plano (refugio, portal, vetas…) o de las rocas caídas.
## En el borde entre dos casillas manda la peor, así el césped no asoma medio metro dentro del refugio.
func _grass_amount(layout: IslandLayout, x: float, z: float, y: float, sand: float, path: float,
		water_surface: float) -> float:
	if water_surface > NO_WATER_SURFACE + 1.0 and y < water_surface + GRASS_ABOVE_WATER:
		return 0.0
	var offsets: Array[Vector2] = [Vector2(-0.01, -0.01), Vector2(0.01, -0.01), Vector2(-0.01, 0.01), Vector2(0.01, 0.01)]
	# Junto al césped pintado, el mar de al lado no lo quita: llega hasta el filo (lo de bajo el agua sigue fuera).
	var lawn: bool = false
	for offset: Vector2 in offsets:
		lawn = lawn or layout.is_forced_grass(Vector2i(floori(x + offset.x), floori(z + offset.y)))
	for offset: Vector2 in offsets:
		var cell := Vector2i(floori(x + offset.x), floori(z + offset.y))
		if not layout.has_cell(cell) or (not layout.is_land(cell) and not lawn) or layout.has_debris(cell):
			return 0.0
		var ch: String = layout.char_at(cell)
		if IslandLayout.FEATURE_CHARS.contains(ch) and not GRASS_FREE_FEATURES.contains(ch):
			return 0.0
	# Hasta donde el terreno empieza a pintar arena o tierra (hacia 0,45 en `terrain.gdshader`), algo más allá en
	# degradado: `is_grass_at` lo usa como probabilidad y alguna mata se mete en el borde (César).
	return (1.0 - smoothstep(0.35, 0.6, sand)) * (1.0 - smoothstep(0.38, 0.62, path))


## Sin césped donde el terreno pinta roca (acantilados y cuestas fuertes): se mira la pendiente en cada punto.
func _remove_steep_grass() -> void:
	for b: int in _grid_count.y:
		for a: int in _grid_count.x:
			var slope_x: float = (_grid_height(a + 1, b) - _grid_height(a - 1, b)) / (2.0 * _grid_step)
			var slope_z: float = (_grid_height(a, b + 1) - _grid_height(a, b - 1)) / (2.0 * _grid_step)
			var up: float = 1.0 / sqrt(1.0 + slope_x * slope_x + slope_z * slope_z)
			var index: int = b * _grid_count.x + a
			_grid_up[index] = up
			var rock_up: float = GRASS_WALL_ROCK_UP if _grid_wall[index] > GRASS_WALL_FROM else GRASS_SLOPE_ROCK_UP
			_grid_grass[index] *= smoothstep(rock_up, rock_up + GRASS_ROCK_FADE, up)


func _grid_height(a: int, b: int) -> float:
	return _grid_heights[clampi(b, 0, _grid_count.y - 1) * _grid_count.x + clampi(a, 0, _grid_count.x - 1)]


## Crea el césped la primera vez y lo rehace después (se genera al siguiente fotograma, con la rejilla ya lista).
func _refresh_grass(layout: IslandLayout) -> void:
	if _grass == null:
		_grass = GrassField.new()
		_grass.name = "Grass"
		_grass.height_source = GrassField.HeightSource.PROVIDER
		_grass.height_provider = self
		_grass.material = GRASS_MATERIAL
		_grass.area_size = Vector2(layout.size)
		_grass.position = Vector3(layout.size.x * 0.5, 0.0, layout.size.y * 0.5)
		add_child(_grass)
	else:
		_grass.regenerate()


## Pisadas (sesión 28, `Footsteps`): de qué es el suelo en un punto del mundo, con las mismas reglas que lo pintan.
## Agua (río, lago, vado, orilla del mar) → chapoteo; cuesta empinada o pared → roca; donde crece el césped → hierba;
## lo demás (arena, sendero, tierra pisada, claros) → tierra. Las rocas caídas al pie de las paredes, piedra.
func get_footstep_surface(at: Vector3, collider: Object) -> StringName:
	if collider != _body:
		return &"stone"
	if _layout != null:
		var cell_ground: IslandLayout.Ground = _layout.ground(GridMath.world_to_cell(to_local(at)))
		if cell_ground == IslandLayout.Ground.WATER or cell_ground == IslandLayout.Ground.SEA:
			return &"water"
	if _grid_count == Vector2i.ZERO:
		return &"grass"
	var up: float = get_up_at(at.x, at.z)
	if up < FOOTSTEP_ROCK_UP or (get_wall_at(at.x, at.z) > 0.5 and up < FOOTSTEP_WALL_UP):
		return &"stone"
	if _grid_sample(_grid_grass, at.x, at.z) > 0.5 and not _is_clearing(at.x, at.z):
		return &"grass"
	return &"dirt"


## Pisadas: ¿hay un claro de tierra en este punto? Las mismas cuentas que `terrain.gdshader` (con el ruido de
## `toy_noise.gdshaderinc`), así suena a tierra justo donde se ve tierra.
func _is_clearing(x: float, z: float) -> bool:
	var flat: float = get_flat_at(x, z)
	if flat < 0.01:
		return false
	var p := Vector2(0.866 * x - 0.5 * z, 0.5 * x + 0.866 * z)
	var mid: float = _fbm(p * 0.35 + Vector2(17.0, 17.0))
	var fine: float = _value_noise(p * 2.3 + Vector2(41.0, 41.0))
	var warp := Vector2(_fbm(p * 0.05 + Vector2(3.1, 3.1)), _fbm(p * 0.05 + Vector2(9.7, 9.7))) - Vector2(0.5, 0.5)
	var noise: float = _fbm(p * 0.06 + warp * 0.8 + Vector2(73.0, 73.0)) + (mid - 0.5) * 0.12
	var clearing: float = smoothstep(CLEARING_THRESHOLD, CLEARING_THRESHOLD + 0.1, noise) * flat
	return clearing + (fine - 0.5) * 0.15 > 0.45


## Copias de `toy_noise.gdshaderinc` para las pisadas.
static func _hash(p: Vector2) -> float:
	var p3 := Vector3(p.x, p.y, p.x) * 0.1031
	p3 = Vector3(p3.x - floorf(p3.x), p3.y - floorf(p3.y), p3.z - floorf(p3.z))
	p3 += Vector3.ONE * p3.dot(Vector3(p3.y, p3.z, p3.x) + Vector3.ONE * 33.33)
	var value: float = (p3.x + p3.y) * p3.z
	return value - floorf(value)


static func _value_noise(p: Vector2) -> float:
	var i := Vector2(floorf(p.x), floorf(p.y))
	var f: Vector2 = p - i
	var u: Vector2 = f * f * (Vector2(3.0, 3.0) - 2.0 * f)
	var a: float = _hash(i)
	var b: float = _hash(i + Vector2(1.0, 0.0))
	var c: float = _hash(i + Vector2(0.0, 1.0))
	var d: float = _hash(i + Vector2(1.0, 1.0))
	return lerpf(lerpf(a, b, u.x), lerpf(c, d, u.x), u.y)


static func _fbm(p: Vector2) -> float:
	var value: float = 0.0
	var weight: float = 0.5
	var q: Vector2 = p
	for _i: int in 4:
		value += weight * _value_noise(q)
		q = Vector2(0.8 * q.x - 0.6 * q.y, 0.6 * q.x + 0.8 * q.y) * 2.03 + Vector2(11.0, 5.0)
		weight *= 0.5
	return value / 0.9375


## Para `GrassField` (coordenadas del mundo): altura del suelo, la misma que dibuja la malla (sus triángulos tienen la
## diagonal de la esquina p0 a la p3, ver `_build_layout_ground()`).
func get_height_at(x: float, z: float) -> float:
	var local: Vector3 = to_local(Vector3(x, 0.0, z))
	var gx: float = clampf(local.x / _grid_step, 0.0, _grid_count.x - 1.001)
	var gz: float = clampf(local.z / _grid_step, 0.0, _grid_count.y - 1.001)
	var a: int = floori(gx)
	var b: int = floori(gz)
	var fx: float = gx - a
	var fz: float = gz - b
	var h0: float = _grid_height(a, b)
	var h1: float = _grid_height(a + 1, b)
	var h2: float = _grid_height(a, b + 1)
	var h3: float = _grid_height(a + 1, b + 1)
	var y: float = h0 + fx * (h1 - h0) + fz * (h3 - h1) if fx >= fz else h0 + fz * (h2 - h0) + fx * (h3 - h2)
	return to_global(Vector3(local.x, y, local.z)).y


## Para `GrassField`: ¿puede crecer césped aquí? En los bordes, la cantidad de hierba es una probabilidad (con un
## número fijo por punto), así el borde no es una línea y alguna mata se adelanta (César).
func is_grass_at(x: float, z: float) -> bool:
	var amount: float = _grid_sample(_grid_grass, x, z)
	if amount >= 0.999:
		return true
	var roll: float = float(hash(Vector2i(roundi(x * 100.0), roundi(z * 100.0))) & 0xFFFF) / 65535.0
	return amount > lerpf(0.1, 0.9, roll)


## Para `GrassField`: lo metido que está el punto en su explanada (0 a 1), para los claros de tierra.
func get_flat_at(x: float, z: float) -> float:
	return _grid_sample(_grid_flat, x, z)


## Para `GrassField`: lo que es pared en el punto (`IslandLayout.wall_amount`, lo mismo que lleva el terreno en UV.y).
func get_wall_at(x: float, z: float) -> float:
	return _grid_sample(_grid_wall, x, z)


## Para `GrassField`: lo llano que es el suelo (componente vertical de la normal, 1 = llano), para poner más matas en
## las cuestas.
func get_up_at(x: float, z: float) -> float:
	return _grid_sample(_grid_up, x, z) if _grid_count != Vector2i.ZERO else 1.0


func _grid_sample(values: PackedFloat32Array, x: float, z: float) -> float:
	if _grid_count == Vector2i.ZERO:
		return 0.0
	var local: Vector3 = to_local(Vector3(x, 0.0, z))
	var gx: float = clampf(local.x / _grid_step, 0.0, _grid_count.x - 1.001)
	var gz: float = clampf(local.z / _grid_step, 0.0, _grid_count.y - 1.001)
	var a: int = floori(gx)
	var b: int = floori(gz)
	var fx: float = gx - a
	var fz: float = gz - b
	var row: int = _grid_count.x
	var top: float = lerpf(values[b * row + a], values[b * row + a + 1], fx)
	var bottom: float = lerpf(values[(b + 1) * row + a], values[(b + 1) * row + a + 1], fx)
	return lerpf(top, bottom, fz)


## Rocas caídas al pie de las paredes (C5.4c): decorado con las rocas de `nature.glb`, del color de los estratos, en
## tres MultiMesh (una por variante) y con un choque de esfera cada una para no atravesarlas.
const DEBRIS_COLOR: Color = Color(0.6, 0.4, 0.3)
const DEBRIS_RADIUS: float = 0.18   # radio del choque por unidad de tamaño

func _build_debris(layout: IslandLayout) -> void:
	for child: Node in get_children():
		if child.name.begins_with("Debris"):
			child.queue_free()
	if layout.debris.is_empty():
		return
	var material := StandardMaterial3D.new()
	material.albedo_color = DEBRIS_COLOR
	material.roughness = 1.0
	var body := StaticBody3D.new()
	body.name = "DebrisBody"
	add_child(body)
	for variant: int in 3:
		var mesh: Mesh = TreeView.named_mesh("rock_%d" % variant)
		if mesh == null:
			continue
		var items: Array[Dictionary] = []
		for item: Dictionary in layout.debris:
			if item["variant"] == variant:
				items.append(item)
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = mesh
		multi.instance_count = items.size()
		for k: int in items.size():
			var item: Dictionary = items[k]
			var turn := Basis(Vector3.UP, item["yaw"]) * Basis(Vector3.RIGHT, item["tilt"])
			multi.set_instance_transform(k, Transform3D(turn.scaled(Vector3.ONE * float(item["scale"])), item["position"]))
			var shape := CollisionShape3D.new()
			var sphere := SphereShape3D.new()
			sphere.radius = DEBRIS_RADIUS * float(item["scale"])
			shape.shape = sphere
			shape.position = item["position"] + Vector3.UP * sphere.radius * 0.6
			body.add_child(shape)
		var instance := MultiMeshInstance3D.new()
		instance.name = "Debris%d" % variant
		instance.multimesh = multi
		instance.material_override = material
		add_child(instance)


## Cascada (C5.4e): una cortina de agua pegada a la caída de las casillas `C` (sigue sus repisas), una franja de
## espuma sobre el río al pie y salpicaduras con algo de bruma. Va del agua más alta que toca a la más baja.
const WATERFALL_SHADER: Shader = preload("res://entities/nature/waterfall.gdshader")
## Cada cuánto lleva un punto la cortina (m) y largo de la espuma del pie (m).
## Cada medio metro, como el terreno: así la cortina va a la misma distancia de la roca en todo y no la atraviesa.
const CASCADE_STEP: float = 0.5
## Lo que la cortina entra en el agua de arriba (m), a ras de ella: sin escalón donde empieza a caer.
const CASCADE_INTAKE: float = 1.0
## El salto: velocidad con la que el agua sale del borde (m/s), gravedad y filas del arco.
const CASCADE_LAUNCH: float = 1.0
## La de dentro, algo menos, pero sin meterse en la roca del filo.
const CASCADE_LAUNCH_INNER: float = 0.5
## Dónde empieza el salto, antes del final del cauce (m): ahí la roca ya baja.
const CASCADE_BRINK: float = 0.5
const CASCADE_GRAVITY: float = 9.8
const CASCADE_ARC_ROWS: int = 16
## Lo que la cortina se separa de cada lado del cauce (m), para no meterse en la roca de al lado. Cada lado tiene el
## suyo: «MIN» es el lado de menor coordenada (en Isla Alba, el oeste) y «MAX» el de mayor (el este, donde la esquina
## de la roca aún rozaba con 0,25 y con 0,4: César).
const CASCADE_SIDE_INSET_MIN: float = 0.25
const CASCADE_SIDE_INSET_MAX: float = 0.55
## Filas del salto en las que los lados pasan de deshilachados (cauce) a cerrados por las paredes: así no hay corte
## en la esquina del filo (César).
const CASCADE_SIDE_BLEND_ROWS: int = 4
const CASCADE_POOL: float = 3.5

func _build_cascade(island: IslandState) -> void:
	for child: Node in get_children():
		if child.name.begins_with("Cascade"):
			child.queue_free()
	var layout: IslandLayout = island.layout
	var cells: Array[Vector2i] = []
	for y: int in layout.size.y:
		for x: int in layout.size.x:
			if layout.char_at(Vector2i(x, y)) == "C":
				cells.append(Vector2i(x, y))
	if cells.is_empty():
		return
	# Hacia dónde cae: del agua más alta que toca a la más baja.
	var high := Vector2.ZERO
	var low := Vector2.ZERO
	var high_level: float = -INF
	var low_level: float = INF
	for cell: Vector2i in cells:
		for offset: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var other: Vector2i = cell + offset
			if not island.water.has(other):
				continue
			var level: float = island.ground_height(other)
			if level > high_level:
				high_level = level
				high = Vector2(other)
			if level < low_level:
				low_level = level
				low = Vector2(other)
	if high_level <= low_level:
		return
	var along_z: bool = absf(low.y - high.y) >= absf(low.x - high.x)
	var forward: float = signf(low.y - high.y) if along_z else signf(low.x - high.x)
	var min_cell := cells[0]
	var max_cell := cells[0]
	for cell: Vector2i in cells:
		min_cell = Vector2i(mini(min_cell.x, cell.x), mini(min_cell.y, cell.y))
		max_cell = Vector2i(maxi(max_cell.x, cell.x), maxi(max_cell.y, cell.y))
	# Ancho (de lado a lado) y largo (de arriba abajo) en metros del mundo.
	var across0: float = float(min_cell.x if along_z else min_cell.y)
	var across1: float = float((max_cell.x if along_z else max_cell.y) + 1)
	var top: float = float(min_cell.y if along_z else min_cell.x) if forward > 0.0 else float((max_cell.y if along_z else max_cell.x) + 1)
	var length: float = float((max_cell.y - min_cell.y if along_z else max_cell.x - min_cell.x) + 1)
	var pool_y: float = low_level + LAYOUT_WATER_Y + 0.02
	var top_y: float = high_level + LAYOUT_WATER_Y + 0.01
	var to_world := func(across: float, along: float) -> Vector2:
		var a: float = top + along * forward
		return Vector2(across, a) if along_z else Vector2(a, across)
	# Perfil de la cortina (a lo largo): el cauce pegado al terreno hasta el borde y, desde ahí, el salto en arco hasta
	# el río (el agua sale despedida: César, caía en tierra y se metía en la roca). Después, la espuma del pie.
	# El cauce va recto, a ras del lago, hasta el filo (César: bajaba una casilla y volvía a subir).
	var brink: float = length - CASCADE_BRINK
	# La cortina, un poco más estrecha que el cauce: si no, su borde rozaba la roca de los lados al caer (César).
	var curtain0: float = across0 + CASCADE_SIDE_INSET_MIN
	var curtain1: float = across1 - CASCADE_SIDE_INSET_MAX
	var lip_y: float = top_y
	var fall_time: float = sqrt(2.0 * maxf(lip_y - pool_y, 0.1) / CASCADE_GRAVITY)
	var columns: int = int(roundf((across1 - across0) / CASCADE_STEP)) * 2
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var points: Array[Vector3] = []
	var uvs: Array[Vector2] = []
	var uv2s: Array[Vector2] = []
	var colors: Array[Color] = []
	var parts: Array[Vector2i] = []   # (primer punto, filas) de cada trozo
	var arc_first: Array[int] = []    # primer punto del salto de cada cortina
	# Dos cortinas (César: de lado se veía la lámina y el hueco de debajo): la de fuera, con el cauce y el salto más
	# largo, y la de dentro, solo el salto, más pegada a la roca. Las dos caen en el río.
	var landing: float = brink + CASCADE_LAUNCH_INNER * fall_time
	for layer: int in 2:
		var launch: float = CASCADE_LAUNCH if layer == 0 else CASCADE_LAUNCH_INNER
		var layer_landing: float = brink + launch * fall_time
		var profile: Array[Vector2] = []   # (a lo largo, altura o NAN si sigue al terreno)
		if layer == 0:
			var step_along: float = -CASCADE_INTAKE
			while step_along < brink - 0.01:
				profile.append(Vector2(step_along, NAN))
				step_along += CASCADE_STEP
		for k: int in CASCADE_ARC_ROWS + 1:
			var t: float = fall_time * float(k) / float(CASCADE_ARC_ROWS)
			profile.append(Vector2(brink + launch * t, lip_y - 0.5 * CASCADE_GRAVITY * t * t))
		var first: int = points.size()
		var travelled := PackedFloat32Array()   # largo recorrido por la cortina en cada columna (para las franjas)
		travelled.resize(columns + 1)
		travelled.fill(0.0 if layer == 0 else CASCADE_INTAKE + length)
		for r: int in profile.size():
			for c: int in columns + 1:
				var across: float = curtain0 + (curtain1 - curtain0) * float(c) / float(columns)
				var w: Vector2 = to_world.call(across, profile[r].x)
				var y: float = profile[r].y
				if is_nan(y):
					y = top_y
				var point := Vector3(w.x, y, w.y)
				if r > 0:
					travelled[c] += point.distance_to(points[first + (r - 1) * (columns + 1) + c])
				points.append(point)
				uvs.append(Vector2(across - across0 + float(layer) * 3.7, travelled[c] - CASCADE_INTAKE))
				uv2s.append(Vector2(0.0, clampf(profile[r].x / layer_landing, 0.0, 1.0)))
				# a: 1 donde los lados se deshilachan (el cauce, sobre la roca); en el salto no, porque ahí los cierran las
				# paredes de los lados y, deshilachados, dejaban una raja entre el frente y el lado (César).
				var arc_row: int = r - (profile.size() - CASCADE_ARC_ROWS - 1)   # negativa en el cauce
				var frays: float = 0.0 if layer == 1 else \
						clampf(1.0 - float(arc_row) / float(CASCADE_SIDE_BLEND_ROWS), 0.0, 1.0)
				# g: la de dentro aparece poco a poco al empezar el salto; si no, se sumaba entera a la de fuera justo en el
				# filo y su borde de arriba se veía como un escalón que sobresalía (César).
				var shows: float = 1.0 if layer == 0 else clampf(float(arc_row) / float(CASCADE_SIDE_BLEND_ROWS), 0.0, 1.0)
				colors.append(Color(float(c) / float(columns), shows, float(layer), frays))
		parts.append(Vector2i(first, profile.size()))
		arc_first.append(first + (profile.size() - CASCADE_ARC_ROWS - 1) * (columns + 1))
	var pool_rows: int = int(roundf(CASCADE_POOL / CASCADE_STEP))
	var pool_first: int = points.size()
	parts.append(Vector2i(pool_first, pool_rows + 1))
	for r: int in pool_rows + 1:
		var along: float = landing + CASCADE_POOL * float(r) / float(pool_rows)
		for c: int in columns + 1:
			var across: float = across0 + (across1 - across0) * float(c) / float(columns)
			var w: Vector2 = to_world.call(across, along)
			var y: float = pool_y if island.water.has(Vector2i(floori(w.x), floori(w.y))) else pool_y - 0.4
			points.append(Vector3(w.x, y, w.y))
			uvs.append(Vector2(across - across0, along))
			uv2s.append(Vector2(1.0, float(r) / float(pool_rows)))
			colors.append(Color(float(c) / float(columns), 0.0, 0.0))
	# Los lados del salto (César: de lado se veían huecos y el pliegue): una pared de agua desde la cortina de fuera hasta
	# dentro de la roca. En el cauce no hace falta: va pegado a la roca y se deshilacha por los lados (con pared, se veía
	# un escalón de cristal, César). Igual de opacas que la de fuera y con sus franjas siguiendo la esquina.
	for c: int in [0, columns]:
		var outward: float = -1.0 if c == 0 else 1.0
		var across: float = curtain0 if c == 0 else curtain1
		# Hasta dentro de la roca, bajo el cauce; pero en lo alto del filo, nada hacia atrás: ahí la pared quedaba por
		# encima del terreno de al lado y se veía como una lámina suelta en la esquina (César).
		var back_at := func(y: float) -> Vector2:
			return to_world.call(across, brink - CASCADE_BRINK * smoothstep(0.0, 0.8, lip_y - y))
		for k: int in CASCADE_ARC_ROWS:
			var o0: int = arc_first[0] + k * (columns + 1) + c
			var o1: int = o0 + columns + 1
			var back0: Vector2 = back_at.call(points[o0].y)
			var back1: Vector2 = back_at.call(points[o1].y)
			var quad: Array[Vector3] = [points[o0], points[o1], Vector3(back1.x, points[o1].y, back1.y),
					Vector3(back0.x, points[o0].y, back0.y)]
			for q: int in [0, 1, 2, 0, 2, 3]:
				var outer: int = o0 if q == 0 or q == 3 else o1
				var gap: float = Vector2(quad[q].x - points[outer].x, quad[q].z - points[outer].z).length()
				# g: la pared aparece poco a poco mientras el lado de la cortina deja de deshilacharse.
				var row_k: int = k if q == 0 or q == 3 else k + 1
				tool.set_color(Color(0.5, clampf(float(row_k) / float(CASCADE_SIDE_BLEND_ROWS), 0.0, 1.0), 0.0, 0.0))
				tool.set_uv(Vector2(uvs[outer].x + outward * gap, uvs[outer].y))
				tool.set_uv2(uv2s[outer])
				tool.add_vertex(quad[q])
	for part: Vector2i in parts:
		for r: int in part.y - 1:
			for c: int in columns:
				var i0: int = part.x + r * (columns + 1) + c
				for index: int in [i0, i0 + 1, i0 + columns + 2, i0, i0 + columns + 2, i0 + columns + 1]:
					tool.set_color(colors[index])
					tool.set_uv(uvs[index])
					tool.set_uv2(uv2s[index])
					tool.add_vertex(points[index])
	tool.generate_normals()
	var mesh: ArrayMesh = tool.commit()
	var material := ShaderMaterial.new()
	material.shader = WATERFALL_SHADER
	material.render_priority = 1   # siempre después del agua (si no, parpadeaba al moverse: César)
	mesh.surface_set_material(0, material)
	var curtain := MeshInstance3D.new()
	curtain.name = "CascadeCurtain"
	curtain.mesh = mesh
	curtain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(curtain)
	# Salpicaduras y bruma al pie.
	var foot: Vector2 = to_world.call((across0 + across1) * 0.5, landing)
	var foot_position := Vector3(foot.x, pool_y, foot.y)
	var width: float = across1 - across0
	add_child(_make_spray("CascadeSpray", foot_position, width, 60, 1.1, Vector2(0.12, 0.3), 0.9, 3.2))
	add_child(_make_spray("CascadeMist", foot_position + Vector3.UP * 0.3, width * 1.3, 14, 3.0, Vector2(1.2, 2.4), 0.18, 0.8))


## Partículas blancas de la cascada: salpicaduras (pequeñas, rápidas) o bruma (grandes, lentas y muy suaves).
func _make_spray(spray_name: String, at: Vector3, width: float, amount: int, lifetime: float, size_range: Vector2,
		opacity: float, speed: float) -> CPUParticles3D:
	var particles := CPUParticles3D.new()
	particles.name = spray_name
	particles.position = at
	particles.amount = amount
	particles.lifetime = lifetime
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	particles.emission_box_extents = Vector3(width * 0.5, 0.1, 0.6)
	particles.direction = Vector3.UP
	particles.spread = 35.0
	particles.initial_velocity_min = speed * 0.6
	particles.initial_velocity_max = speed
	particles.gravity = Vector3(0.0, -6.0 if speed > 2.0 else -0.2, 0.0)
	particles.scale_amount_min = size_range.x
	particles.scale_amount_max = size_range.y
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 1.0, 1.0, opacity))
	ramp.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	particles.color_ramp = ramp
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var material := StandardMaterial3D.new()
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.albedo_texture = _soft_dot()
	material.render_priority = 2   # la espuma y la bruma, lo último
	quad.material = material
	particles.mesh = quad
	return particles


## Mancha blanca redonda y suave para las partículas (se crea una vez).
static var _dot: Texture2D = null

static func _soft_dot() -> Texture2D:
	if _dot == null:
		var ramp := Gradient.new()
		ramp.set_color(0, Color(1, 1, 1, 1))
		ramp.set_color(1, Color(1, 1, 1, 0))
		var texture := GradientTexture2D.new()
		texture.gradient = ramp
		texture.fill = GradientTexture2D.FILL_RADIAL
		texture.fill_from = Vector2(0.5, 0.5)
		texture.fill_to = Vector2(1.0, 0.5)
		texture.width = 32
		texture.height = 32
		_dot = texture
	return _dot


## El mar alrededor de la isla: un plano grande de agua quieta.
func _build_sea(layout: IslandLayout) -> void:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var x0: float = -SEA_MARGIN
	var z0: float = -SEA_MARGIN
	var x1: float = layout.size.x + SEA_MARGIN
	var z1: float = layout.size.y + SEA_MARGIN
	var corners: Array[Vector3] = [Vector3(x0, SEA_Y, z0), Vector3(x1, SEA_Y, z0), Vector3(x1, SEA_Y, z1), Vector3(x0, SEA_Y, z1)]
	for index: int in [0, 1, 2, 0, 2, 3]:
		var p: Vector3 = corners[index]
		tool.set_normal(Vector3.UP)
		tool.set_uv(Vector2.ZERO)   # el mar no corre
		tool.set_color(Color(1.0, 0.0, 0.0))   # sin color, el shader lo tomaría por orilla y lo borraría en lo hondo
		tool.add_vertex(p)
	var mesh: ArrayMesh = tool.commit()
	mesh.surface_set_material(0, _water_material)
	_sea.mesh = mesh


func _make_water_material() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = WATER_SHADER
	return material
