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

## Profundidad del fondo y altura del agua (el suelo está a 0).
const DEPTH: float = 0.4
const WATER_Y: float = -0.08
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
var _collision: CollisionShape3D


func _init() -> void:
	_flow_material = _make_water_material()
	_still_material = _make_water_material()
	_ground = MeshInstance3D.new()
	add_child(_ground)
	_water = MeshInstance3D.new()
	_water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_water)
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
	_build_ground(island, bounds)
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
		var center: Vector3 = GridMath.cell_center(cell, WATER_Y)
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
