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
## Colores del suelo: hierba (la del suelo de antes), arena en la orilla y, en el fondo, un azul verdoso
## oscuro: como el agua es transparente, se ve clara en la orilla y más oscura cuanto más hondo (César).
const GRASS: Color = Color(0.45, 0.6, 0.38)
const SAND: Color = Color(0.86, 0.79, 0.6)
const BED_DEEP: Color = Color(0.1, 0.38, 0.5)
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
## Hasta cuántas esquinas de distancia se lleva la superficie del agua tierra adentro.
const WATER_SURFACE_SPREAD: int = 3

## Agua de juguete (C5.4d): el mismo shader, con corriente en los ríos y sin ella en lagos, estanques y el mar.
const WATER_SHADER: Shader = preload("res://entities/nature/water.gdshader")
var _water_material: ShaderMaterial
var _ground: MeshInstance3D
var _water: MeshInstance3D
var _body: StaticBody3D
var _sea: MeshInstance3D
var _collision: CollisionShape3D


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
			var color: Color = GRASS
			if depth > 0.0:
				color = BED_DEEP
			elif shore:
				color = SAND
			tool.set_color(color)
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
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true # los colores de arriba están en sRGB (sin esto salen lavados)
	material.roughness = 1.0
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
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
				tool.set_normal(Vector3.UP)
				tool.set_color(Color(1.0, on_shore, 0.0))
				tool.set_uv(velocity)
				tool.add_vertex(Vector3(corner.x, y, corner.y))
	var mesh: ArrayMesh = tool.commit()
	mesh.surface_set_material(0, _water_material)
	_water.mesh = mesh


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


## Valor de una rejilla de esquinas en un punto (interpolado entre las cuatro esquinas de su casilla).
func _lerp_corners(values: PackedFloat32Array, row: int, x: float, z: float) -> float:
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
	for j: int in h + 1:
		for i: int in w + 1:
			var corner_y: float = layout.corner_height(i, j)   # la misma regla que usa todo lo de encima
			var sand: float = 0.0
			var path: float = 0.0
			var flat: float = 0.0
			var wet: float = 0.0
			var water_surface: float = -INF
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
						path += 0.25 * LANDING_AS_PATH
				path += 0.25 * layout.wear(cell)
				# Lo metida que está en su explanada, suave: los claros se apagan antes del borde (César: junto al lago
				# salía uno cortado en seco por las casillas).
				flat += 0.25 * smoothstep(0.5, FLAT_FADE_CELLS, layout.flat_depth(cell))
			var index: int = j * row + i
			sand_at[index] = sand
			wet_at[index] = wet
			path_at[index] = path
			flat_at[index] = flat
			# La superficie del agua que toca: el shader calcula la hondura en cada punto. Interpolar la hondura de las
			# esquinas pintaba de fondo medio acantilado (captura de César).
			depth_at[index] = water_surface if water_surface > -INF else NO_WATER_SURFACE
	_spread_water_surface(depth_at, row, h + 1)
	# Después, un punto cada medio metro (C5.4b: para que las lomas se vean redondas), con la altura del terreno
	# (`IslandLayout.terrain_height()`, la misma que usan los árboles y las rocas) y lo de las esquinas interpolado.
	var step: float = 1.0 / GROUND_SUBDIVISIONS
	var count_x: int = w * GROUND_SUBDIVISIONS + 1
	var count_z: int = h * GROUND_SUBDIVISIONS + 1
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for b: int in count_z:
		for a: int in count_x:
			var x: float = a * step
			var z: float = b * step
			var y: float = layout.terrain_height(x, z)
			tool.set_color(Color(_lerp_corners(sand_at, row, x, z), _lerp_corners(wet_at, row, x, z),
					_lerp_corners(path_at, row, x, z), clampf(y / IslandLayout.LEVEL_HEIGHT, 0.0, 1.0)))
			tool.set_uv2(Vector2(_lerp_corners(depth_at, row, x, z), _lerp_corners(flat_at, row, x, z)))
			tool.set_uv(Vector2(layout.wall_lip(x, z), 0.0))   # el borde de hierba que asoma por lo alto de una pared
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
			var basis := Basis(Vector3.UP, item["yaw"]) * Basis(Vector3.RIGHT, item["tilt"])
			multi.set_instance_transform(k, Transform3D(basis.scaled(Vector3.ONE * float(item["scale"])), item["position"]))
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
