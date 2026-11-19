class_name TerrainView
extends Node3D
## Suelo de una isla con su agua (B3.7, D-094). Sustituye al suelo plano del sandbox: genera el terreno
## de `IslandState.bounds` y, donde hay agua, lo hunde con rampas suaves hasta el fondo (César: «una
## transición natural, no muros»), con arena en las rampas y el fondo. Encima, el agua: clara y algo
## transparente (se ve el fondo), con corriente donde corre (ríos y canales) y casi quieta donde no
## (lagos: `flow` = (0, 0)). Por el agua se puede andar (César); nadar con estamina, en la fase C.
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
## Agua cristalina: un velo azul claro y transparente, con claros que se mueven con la corriente.
const WATER_DEEP: Color = Color(0.25, 0.6, 0.8, 0.35)
const WATER_LIGHT: Color = Color(0.8, 0.95, 1.0, 0.6)
## Casillas que avanza la corriente por segundo y veces que se repite la textura por metro.
const FLOW_SPEED: float = 0.35
const TEXTURE_PER_M: float = 0.5
## Agua quieta (lagos): vaivén lento de la textura, en metros y segundos.
const STILL_DRIFT: float = 0.15
const STILL_PERIOD: float = 6.0

var _flow_material: StandardMaterial3D
var _still_material: StandardMaterial3D
var _time: float = 0.0
var _ground: MeshInstance3D
var _water: MeshInstance3D
var _body: StaticBody3D
var _sea: MeshInstance3D
var _collision: CollisionShape3D


func _init() -> void:
	_flow_material = _make_water_material()
	_still_material = _make_water_material()
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


## La corriente: un solo desplazamiento para todos los ríos (sus UV ya van orientadas a su dirección);
## los lagos solo se mecen un poco.
func _process(delta: float) -> void:
	_time += delta
	var scroll: float = fposmod(-_time * FLOW_SPEED * TEXTURE_PER_M, 1.0)
	_flow_material.uv1_offset = Vector3(0.0, scroll, 0.0)
	var drift: float = sin(_time * TAU / STILL_PERIOD) * STILL_DRIFT * TEXTURE_PER_M
	_still_material.uv1_offset = Vector3(drift, drift * 0.5, 0.0)


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


func _build_water(island: IslandState) -> void:
	if island.water.is_empty():
		_water.mesh = null
		return
	var flowing := SurfaceTool.new()
	flowing.begin(Mesh.PRIMITIVE_TRIANGLES)
	var still := SurfaceTool.new()
	still.begin(Mesh.PRIMITIVE_TRIANGLES)
	var has_flowing: bool = false
	var has_still: bool = false
	for cell: Vector2i in island.water:
		var flow: Vector2i = island.water[cell]
		var tool: SurfaceTool = still if flow == Vector2i.ZERO else flowing
		if flow == Vector2i.ZERO:
			has_still = true
		else:
			has_flowing = true
		var forward := Vector3(0.0, 0.0, 1.0) if flow == Vector2i.ZERO else Vector3(flow.x, 0.0, flow.y).normalized()
		var right := forward.cross(Vector3.UP)
		var surface: float = LAYOUT_WATER_Y if island.layout != null else WATER_Y
		var center: Vector3 = GridMath.cell_center(cell, island.ground_height(cell) + surface)
		# UV en coordenadas del mundo (u a lo ancho, v a lo largo de la corriente): sin cortes entre casillas.
		var corners: Array[Vector3] = [
			center + (-right - forward) * 0.5, center + (right - forward) * 0.5,
			center + (right + forward) * 0.5, center + (-right + forward) * 0.5]
		for index: int in [0, 1, 2, 0, 2, 3]:
			var p: Vector3 = corners[index]
			tool.set_normal(Vector3.UP)
			tool.set_uv(Vector2(p.dot(right), p.dot(forward)) * TEXTURE_PER_M)
			tool.add_vertex(p)
	var mesh := ArrayMesh.new()
	if has_flowing:
		flowing.commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, _flow_material)
	if has_still:
		still.commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, _still_material)
	_water.mesh = mesh


# --- Terreno a partir del plano (C5.3d, provisional hasta C5.4) ---

## Nivel del mar (las alturas del suelo, también la del fondo, las da `IslandLayout.height()`).
const SEA_Y: float = -0.25
## Metros de mar que se dibujan alrededor del plano: hasta donde la bruma ya lo tapa todo, para que no se vea dónde
## acaba (César).
const SEA_MARGIN: float = 1500.0
## Shader del suelo de las islas con plano (C5.4a): mezcla hierba, arena, arena mojada, tierra del sendero, roca
## y fondo según lo que cada esquina lleva apuntado, con ruido para que no se vea plano. Los colores, en el shader.
const TERRAIN_SHADER: Shader = preload("res://entities/nature/terrain.gdshader")
## Lo que cuenta el sendero en el rellano (también es tierra pisada, pero más clara y gastada).
const LANDING_AS_PATH: float = 0.6


## Suelo de una isla con plano. Cada esquina lleva lo que la rodea, para el shader:
## color (r) arena: playa y mar; (g) mojado: toca agua o mar; (b) tierra pisada (sendero y sus extremos);
## (a) altura de 0 (abajo) a 1 (arriba);
## uv2 (x) hondura bajo el agua (m); (y) explanada (donde se construye, con menos manchas para que se lea).
## La roca la decide el shader por la pendiente.
func _build_layout_ground(island: IslandState) -> void:
	var layout: IslandLayout = island.layout
	var w: int = layout.size.x
	var h: int = layout.size.y
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Un punto en cada esquina de casilla: (w + 1) × (h + 1).
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
				if layout.is_buildable(cell):
					flat += 0.25
			var depth: float = maxf(water_surface - corner_y, 0.0) if water_surface > -INF else 0.0
			tool.set_color(Color(sand, wet, path, clampf(corner_y / IslandLayout.LEVEL_HEIGHT, 0.0, 1.0)))
			tool.set_uv2(Vector2(depth, flat))
			tool.add_vertex(Vector3(i, corner_y, j))
	for j: int in h:
		for i: int in w:
			var a: int = j * (w + 1) + i
			var b: int = a + 1
			var c: int = a + w + 1
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
		tool.set_uv(Vector2(p.x, p.z) * TEXTURE_PER_M)
		tool.add_vertex(p)
	var mesh: ArrayMesh = tool.commit()
	mesh.surface_set_material(0, _still_material)
	_sea.mesh = mesh


func _make_water_material() -> StandardMaterial3D:
	var noise := FastNoiseLite.new()
	noise.frequency = 0.08
	var ramp := Gradient.new()
	ramp.set_color(0, WATER_DEEP)
	ramp.set_color(1, WATER_LIGHT)
	var texture := NoiseTexture2D.new()
	texture.width = 64
	texture.height = 64
	texture.seamless = true
	texture.noise = noise
	texture.color_ramp = ramp
	var material := StandardMaterial3D.new()
	material.albedo_texture = texture
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.roughness = 0.25
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material
