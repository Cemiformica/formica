@tool
class_name GrassField
extends Node3D
## Césped en 3D al estilo de Solarpunk (C5.6, D-179).
## Genera matas de briznas con MultiMesh, repartidas en trozos (chunks) para que la cámara
## descarte los que no ve. Cada mata lleva giro en Y y escala al azar, y un ruido las agrupa:
## zonas tupidas y altas y zonas ralas y bajas (César: «grupos de césped más unido»).
## Se ve también en el editor: botón «Regenerar» en el inspector.
##
## Los trozos se crean sin owner: no se guardan en la escena y se regeneran al abrirla,
## siempre iguales (cada trozo tiene su propia semilla).

enum HeightSource {
	RAYCAST,  ## Rayo hacia abajo contra la colisión del terreno.
	PROVIDER, ## Pregunta a height_provider (más rápido y exacto si el terreno sale de un plano).
	FLAT,     ## Suelo plano a la altura del nodo (para pruebas).
}

const CHUNK_META: StringName = &"grass_chunk"

@export_group("Zona")
## Tamaño de la zona (x, z) en metros, centrada en el nodo.
@export var area_size: Vector2 = Vector2(32.0, 32.0)
## Lado de cada trozo en metros. Más pequeño = mejor descarte, más llamadas de dibujo.
@export var chunk_size: float = 16.0
## Matas por metro cuadrado donde el césped es más tupido (cada mata lleva blades_per_tuft briznas).
@export_range(1.0, 40.0, 0.5) var density: float = 20.0
@export var random_seed: int = 1

@export_group("Altura")
@export var height_source: HeightSource = HeightSource.RAYCAST
## Opcional. Nodo con get_height_at(x, z) -> float y, si quiere, is_grass_at(x, z) -> bool y
## get_flat_at(x, z) -> float (lo metido en su explanada, para los claros), en coordenadas del mundo.
## En las islas con plano lo hace `TerrainView`.
## is_grass_at se usa también con RAYCAST, para quitar el césped del sendero, la arena, etc.
@export var height_provider: Node
@export_flags_3d_physics var ray_mask: int = 1
## Desde qué altura (sobre el nodo) sale el rayo y cuánto baja.
@export var ray_top: float = 30.0
@export var ray_length: float = 80.0
## Sin césped en cuestas más empinadas que esto (solo con RAYCAST).
@export_range(0.0, 89.0) var max_slope_deg: float = 35.0

@export_group("Matas")
## Frecuencia del ruido que agrupa las matas (0,2 ≈ manchas de 5 m).
@export var clump_frequency: float = 0.2
## Parte de las matas que queda en las zonas ralas (1 = todo igual de tupido).
@export_range(0.0, 1.0) var sparse_fill: float = 0.5
## Hasta cuántas veces más matas en las cuestas (con get_up_at del proveedor). En una cuesta que sube delante de ti
## se ve el suelo entre las matas, que son verticales, y además tiene más superficie que su planta (César: las
## cuestas se veían vacías). Se multiplica por 1 / (llano²): ×1,3 a 30°, ×1,8 a 42°; más empinado ya es roca (C5.6).
@export_range(1.0, 4.0, 0.1) var slope_boost_max: float = 2.2
@export_range(1, 12) var blades_per_tuft: int = 7
## Radio de la base de la mata y cuánto se abren las briznas hacia fuera.
@export var tuft_radius: float = 0.07
@export_range(0.0, 70.0) var tuft_splay_deg: float = 30.0

@export_group("Briznas")
@export var blade_height: float = 0.32
@export var blade_width: float = 0.068
@export var height_scale_range: Vector2 = Vector2(0.75, 1.25)
@export var width_scale_range: Vector2 = Vector2(0.85, 1.15)
@export var material: ShaderMaterial

@export_group("Flores y tréboles")
## Piezas de `plants.glb` (C5.6, sesión 31): flores de 3 colores y tréboles de 3 y 4 hojas, en corros dentro del césped
## (donde no hay césped, tampoco hay flores). Sin escena, no se ponen. Tienen su propio azar: no cambian el césped.
@export var decor_scene: PackedScene
## `plants_ground.tres`: el shader de las plantas con las máscaras del césped (claros, roca y lo construido).
@export var decor_material: ShaderMaterial
## Los tréboles, con su propio material (`plants_ground_clover.tres`: tallos más parecidos al césped). Sin él, el de
## las flores.
@export var clover_material: ShaderMaterial
## Flores por m² en el centro de un corro, y sueltas fuera de los corros.
@export var flower_density: float = 2.2
@export var stray_flower_density: float = 0.012
## Ruido de los corros de flores: frecuencia y desde qué valor empieza un corro (hasta + 0,15, entero).
@export var flower_patch_frequency: float = 0.09
@export var flower_patch_threshold: float = 0.28
## Ruido del color de cada zona (más lento que el de los corros: corros vecinos suelen ser del mismo color).
@export var flower_color_frequency: float = 0.035
## Tréboles por m² en el centro de un corro, frecuencia y umbral de sus corros.
@export var clover_density: float = 3.5
@export var clover_patch_frequency: float = 0.13
@export var clover_patch_threshold: float = 0.22
## Parte de los tréboles que tiene 4 hojas (César: uno de cada ~40).
@export_range(0.0, 0.2, 0.001) var four_leaf_chance: float = 0.025

@export_group("Distancia")
## Corte duro de cada trozo. Debe ser mayor que fade_end del shader + 0,75 × chunk_size,
## para que las briznas ya se hayan encogido cuando el trozo desaparece.
@export var visibility_end: float = 45.0

@export_tool_button("Regenerar") var rebuild_button: Callable = _queue_rebuild

var _rebuild_pending: bool = false
var _ray_query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.new()
var _clump_noise: FastNoiseLite = FastNoiseLite.new()
var _flower_noise: FastNoiseLite = FastNoiseLite.new()
var _flower_color_noise: FastNoiseLite = FastNoiseLite.new()
var _clover_noise: FastNoiseLite = FastNoiseLite.new()
## Piezas de flores y tréboles por nombre (`flowers_0`…, `clover_3`, `clover_4`), sacadas de `decor_scene`.
var _decor_meshes: Dictionary[String, Mesh] = {}
const FLOWER_PIECES: Array[String] = ["flowers_0", "flowers_1", "flowers_2"]


func _ready() -> void:
	_queue_rebuild()


## Rehace el césped al siguiente fotograma (p. ej. cuando cambia el terreno).
func regenerate() -> void:
	_queue_rebuild()


func _queue_rebuild() -> void:
	if _rebuild_pending or not is_inside_tree():
		return
	_rebuild_pending = true
	_rebuild.call_deferred()


func _rebuild() -> void:
	if height_source == HeightSource.RAYCAST:
		# El espacio físico tiene que haber dado un paso para responder a los rayos.
		await get_tree().physics_frame
	_rebuild_pending = false
	_clear_chunks()
	_ensure_wind_noise()

	var blade_mesh: ArrayMesh = _build_tuft_mesh()
	_clump_noise.seed = random_seed
	_clump_noise.frequency = clump_frequency
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	_ray_query.collision_mask = ray_mask
	_load_decor()
	var cols: int = ceili(area_size.x / chunk_size)
	var rows: int = ceili(area_size.y / chunk_size)
	var total: int = 0
	var decor: Vector2i = Vector2i.ZERO
	var started_ms: int = Time.get_ticks_msec()
	for cz: int in rows:
		for cx: int in cols:
			total += _build_chunk(cx, cz, blade_mesh, space)
			decor += _build_decor(cx, cz, space)
	print("GrassField: %d matas (%d briznas) en %d trozos (%d ms)" % [total, total * blades_per_tuft, cols * rows,
			Time.get_ticks_msec() - started_ms])
	if not _decor_meshes.is_empty():
		print("GrassField: %d flores y %d tréboles" % [decor.x, decor.y])


func _build_chunk(cx: int, cz: int, blade_mesh: ArrayMesh, space: PhysicsDirectSpaceState3D) -> int:
	var half_area: Vector2 = area_size * 0.5
	var start: Vector2 = Vector2(-half_area.x + cx * chunk_size, -half_area.y + cz * chunk_size)
	var size: Vector2 = Vector2(minf(chunk_size, half_area.x - start.x), minf(chunk_size, half_area.y - start.y))
	var center_local: Vector3 = Vector3(start.x + size.x * 0.5, 0.0, start.y + size.y * 0.5)

	# Semilla propia por trozo: el mismo trozo sale siempre igual.
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(random_seed, cx, cz))

	var max_slope_cos: float = cos(deg_to_rad(max_slope_deg))
	# Con cuestas, se prueban más puntos y en lo llano se descartan los que sobran.
	var boost_max: float = slope_boost_max if _provider_has(&"get_up_at") else 1.0
	var attempts: int = int(size.x * size.y * density * boost_max)
	var transforms: Array[Transform3D] = []
	var customs: Array[Color] = []
	for i: int in attempts:
		# Se sacan todos los números antes de mirar el suelo, para que quitar
		# una brizna no cambie las demás.
		var local: Vector3 = Vector3(start.x + rng.randf() * size.x, 0.0, start.y + rng.randf() * size.y)
		var yaw: float = rng.randf() * TAU
		var height_scale: float = rng.randf_range(height_scale_range.x, height_scale_range.y)
		var width_scale: float = rng.randf_range(width_scale_range.x, width_scale_range.y)
		var variation: float = rng.randf()
		var keep_roll: float = rng.randf()

		# Agrupar: en las zonas ralas queda solo una parte de las matas, y más bajas.
		var world: Vector3 = to_global(local)
		var clump: float = smoothstep(-0.2, 0.35, _clump_noise.get_noise_2d(world.x, world.z))
		var keep_chance: float = lerpf(sparse_fill, 1.0, clump)
		if boost_max > 1.0:
			var up: float = maxf(height_provider.call(&"get_up_at", world.x, world.z), 0.1)
			keep_chance *= clampf(1.0 / (up * up), 1.0, boost_max) / boost_max
		if keep_roll > keep_chance:
			continue
		height_scale *= lerpf(0.75, 1.1, clump)

		var ground: Variant = _sample_ground(local, space, max_slope_cos)
		if ground == null:
			continue
		var blade_basis: Basis = Basis(Vector3.UP, yaw).scaled(Vector3(width_scale, height_scale, width_scale))
		transforms.append(Transform3D(blade_basis, (ground as Vector3) - center_local))
		# INSTANCE_CUSTOM.r: número al azar para el tono y el aleteo; .g: lo metida que está en su explanada (el shader
		# quita las matas de los claros de tierra y copia las manchas del terreno); .b y .a: la pendiente y lo que es pared
		# (el shader quita las matas donde el terreno pinta roca).
		customs.append(Color(variation, _flat_at(world), _provider_value(&"get_up_at", world, 1.0),
				_provider_value(&"get_wall_at", world, 0.0)))

	if transforms.is_empty():
		return 0

	var multimesh: MultiMesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true # antes de instance_count
	multimesh.mesh = blade_mesh
	multimesh.instance_count = transforms.size()
	for i: int in transforms.size():
		multimesh.set_instance_transform(i, transforms[i])
		multimesh.set_instance_custom_data(i, customs[i])

	var chunk: MultiMeshInstance3D = MultiMeshInstance3D.new()
	chunk.name = "GrassChunk_%d_%d" % [cx, cz]
	chunk.multimesh = multimesh
	chunk.position = center_local
	chunk.material_override = material
	chunk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# El viento y el jugador sacan las puntas de la caja: margen para que no desaparezcan al borde.
	chunk.extra_cull_margin = blade_height * height_scale_range.y * 1.1
	chunk.visibility_range_end = visibility_end
	chunk.set_meta(CHUNK_META, true)
	add_child(chunk) # sin owner a propósito: no se guarda en la escena
	return transforms.size()


## Lee las piezas de flores y tréboles de `decor_scene` y prepara los ruidos de sus corros.
func _load_decor() -> void:
	_decor_meshes.clear()
	if decor_scene == null or decor_material == null:
		return
	var scene: Node = decor_scene.instantiate()
	for node: Node in scene.find_children("*", "MeshInstance3D", true, false):
		var piece: String = String(node.name).trim_suffix("_mesh")
		if piece.begins_with("flowers_") or piece.begins_with("clover_"):
			_decor_meshes[piece] = (node as MeshInstance3D).mesh
	scene.free()
	_flower_noise.seed = random_seed + 101
	_flower_noise.frequency = flower_patch_frequency
	_flower_color_noise.seed = random_seed + 202
	_flower_color_noise.frequency = flower_color_frequency
	_clover_noise.seed = random_seed + 303
	_clover_noise.frequency = clover_patch_frequency


## Flores y tréboles de un trozo (sesión 31): en corros que salen de un ruido; las flores, de un color por zona y alguna
## suelta; cerca del refugio y del portal hay más corros (`get_flower_boost_at` del proveedor). Cada pieza, su
## MultiMesh. Devuelve (flores, tréboles).
func _build_decor(cx: int, cz: int, space: PhysicsDirectSpaceState3D) -> Vector2i:
	if _decor_meshes.is_empty():
		return Vector2i.ZERO
	var half_area: Vector2 = area_size * 0.5
	var start: Vector2 = Vector2(-half_area.x + cx * chunk_size, -half_area.y + cz * chunk_size)
	var size: Vector2 = Vector2(minf(chunk_size, half_area.x - start.x), minf(chunk_size, half_area.y - start.y))
	var center_local: Vector3 = Vector3(start.x + size.x * 0.5, 0.0, start.y + size.y * 0.5)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(random_seed + 7919, cx, cz))
	var max_slope_cos: float = cos(deg_to_rad(max_slope_deg))
	var placed: Dictionary[String, Array] = {}   # pieza → [transforms, customs]
	var counts: Vector2i = Vector2i.ZERO
	# Flores.
	var attempts: int = int(size.x * size.y * flower_density)
	for i: int in attempts:
		var local := Vector3(start.x + rng.randf() * size.x, 0.0, start.y + rng.randf() * size.y)
		var keep_roll: float = rng.randf()
		var stray_roll: float = rng.randf()
		var yaw: float = rng.randf() * TAU
		var grow: float = rng.randf_range(0.8, 1.2)
		var variation: float = rng.randf()
		var world: Vector3 = to_global(local)
		var boost: float = _provider_value(&"get_flower_boost_at", world, 0.0)
		var patch: float = smoothstep(flower_patch_threshold, flower_patch_threshold + 0.15,
				_flower_noise.get_noise_2d(world.x, world.z) + boost * 0.25)
		var stray: bool = stray_roll < stray_flower_density / flower_density
		if keep_roll >= patch and not stray:
			continue
		var color: int = clampi(int((_flower_color_noise.get_noise_2d(world.x, world.z) + 0.45) / 0.9 * 3.0), 0, 2)
		if stray:
			color = int(variation * 3.0) % 3
		if _add_decor(placed, FLOWER_PIECES[color], local, center_local, yaw, grow, variation, space, max_slope_cos):
			counts.x += 1
	# Tréboles.
	attempts = int(size.x * size.y * clover_density)
	for i: int in attempts:
		var local := Vector3(start.x + rng.randf() * size.x, 0.0, start.y + rng.randf() * size.y)
		var keep_roll: float = rng.randf()
		var four_roll: float = rng.randf()
		var yaw: float = rng.randf() * TAU
		var grow: float = rng.randf_range(0.85, 1.3)
		var variation: float = rng.randf()
		var world: Vector3 = to_global(local)
		var patch: float = smoothstep(clover_patch_threshold, clover_patch_threshold + 0.15,
				_clover_noise.get_noise_2d(world.x, world.z))
		if keep_roll >= patch:
			continue
		var piece: String = "clover_4" if four_roll < four_leaf_chance else "clover_3"
		if _add_decor(placed, piece, local, center_local, yaw, grow, variation, space, max_slope_cos):
			counts.y += 1
	for piece: String in placed:
		if not _decor_meshes.has(piece):
			continue
		var transforms: Array = placed[piece][0]
		var customs: Array = placed[piece][1]
		var multimesh: MultiMesh = MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.use_custom_data = true
		multimesh.mesh = _decor_meshes[piece]
		multimesh.instance_count = transforms.size()
		for k: int in transforms.size():
			multimesh.set_instance_transform(k, transforms[k])
			multimesh.set_instance_custom_data(k, customs[k])
		var chunk: MultiMeshInstance3D = MultiMeshInstance3D.new()
		chunk.name = "Decor_%s_%d_%d" % [piece, cx, cz]
		chunk.multimesh = multimesh
		chunk.position = center_local
		chunk.material_override = clover_material if piece.begins_with("clover_") and clover_material != null \
				else decor_material
		chunk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		chunk.extra_cull_margin = 0.5
		chunk.visibility_range_end = visibility_end
		chunk.set_meta(CHUNK_META, true)
		add_child(chunk)
	return counts


## Pone una flor o un trébol si ahí crece césped. Lleva lo mismo que una mata (para las máscaras del shader).
func _add_decor(placed: Dictionary[String, Array], piece: String, local: Vector3, center_local: Vector3, yaw: float,
		grow: float, variation: float, space: PhysicsDirectSpaceState3D, max_slope_cos: float) -> bool:
	if not _decor_meshes.has(piece):
		return false
	var ground: Variant = _sample_ground(local, space, max_slope_cos)
	if ground == null:
		return false
	var world: Vector3 = to_global(local)
	if not placed.has(piece):
		placed[piece] = [[], []]
	(placed[piece][0] as Array).append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * grow),
			(ground as Vector3) - center_local))
	(placed[piece][1] as Array).append(Color(variation, _flat_at(world), _provider_value(&"get_up_at", world, 1.0),
			_provider_value(&"get_wall_at", world, 0.0)))
	return true


## Devuelve el punto del suelo en coordenadas locales del nodo, o null si ahí no va césped.
func _sample_ground(local: Vector3, space: PhysicsDirectSpaceState3D, max_slope_cos: float) -> Variant:
	var world: Vector3 = to_global(local)
	if not _is_grass_allowed(world):
		return null
	match height_source:
		HeightSource.FLAT:
			return local
		HeightSource.PROVIDER:
			if height_provider == null or not height_provider.has_method(&"get_height_at"):
				return local
			var height: float = height_provider.call(&"get_height_at", world.x, world.z)
			return to_local(Vector3(world.x, height, world.z))
		_:
			_ray_query.from = world + Vector3.UP * ray_top
			_ray_query.to = _ray_query.from + Vector3.DOWN * ray_length
			var hit: Dictionary = space.intersect_ray(_ray_query)
			if hit.is_empty():
				return null
			var normal: Vector3 = hit["normal"]
			if normal.y < max_slope_cos:
				return null
			return to_local(hit["position"])


func _provider_has(method: StringName) -> bool:
	return height_provider != null and height_provider.has_method(method)


func _provider_value(method: StringName, world: Vector3, fallback: float) -> float:
	if not _provider_has(method):
		return fallback
	return height_provider.call(method, world.x, world.z)


func _flat_at(world: Vector3) -> float:
	if height_provider == null or not height_provider.has_method(&"get_flat_at"):
		return 1.0
	return height_provider.call(&"get_flat_at", world.x, world.z)


func _is_grass_allowed(world: Vector3) -> bool:
	if height_provider == null or not height_provider.has_method(&"is_grass_at"):
		return true
	return height_provider.call(&"is_grass_at", world.x, world.z)


## Mata low-poly: blades_per_tuft briznas que salen de un círculo pequeño y se abren hacia fuera
## curvándose, como un abanico. Cada brizna: dos tramos y una punta (5 vértices, 3 triángulos).
## UV.y = 1 en la raíz y 0 en la punta (en Godot la v crece hacia abajo); el shader usa 1.0 - UV.y
## como peso de la punta. La mata es siempre la misma (semilla fija); las copias se distinguen
## por el giro y la escala.
func _build_tuft_mesh() -> ArrayMesh:
	var rows: PackedFloat32Array = [0.0, 0.5, 1.0]
	var widths: PackedFloat32Array = [1.0, 0.7, 0.0]
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 7
	var verts: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var indices: PackedInt32Array = PackedInt32Array()
	for blade: int in blades_per_tuft:
		var angle: float = (blade + rng.randf_range(-0.3, 0.3)) / blades_per_tuft * TAU
		var outward: Vector3 = Vector3(cos(angle), 0.0, sin(angle))
		# Ancho de la brizna atravesado a la dirección hacia fuera, algo girado para que no sea un abanico perfecto.
		var side: Vector3 = outward.cross(Vector3.UP).rotated(Vector3.UP, rng.randf_range(-0.5, 0.5))
		var base: Vector3 = outward * tuft_radius * rng.randf_range(0.2, 1.0)
		var height: float = blade_height * rng.randf_range(0.6, 1.0)
		# Las de fuera, más abiertas; las del centro, más rectas.
		var splay: float = deg_to_rad(tuft_splay_deg) * rng.randf_range(0.4, 1.0)
		var first: int = verts.size()
		for i: int in rows.size():
			var t: float = rows[i]
			# Curva: sube recta al principio y se abre hacia la punta.
			var center: Vector3 = base + Vector3.UP * height * t + outward * height * sin(splay) * t * t
			var half: float = widths[i] * blade_width * 0.5
			if i < rows.size() - 1:
				verts.append(center - side * half)
				uvs.append(Vector2(0.0, 1.0 - t))
				verts.append(center + side * half)
				uvs.append(Vector2(1.0, 1.0 - t))
			else:
				verts.append(center)
				uvs.append(Vector2(0.5, 0.0))
		indices.append_array([first, first + 2, first + 1, first + 1, first + 2, first + 3, first + 2, first + 4, first + 3])
	for i: int in verts.size():
		normals.append(Vector3.UP) # el shader las fuerza hacia arriba de todos modos

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Red de seguridad: si el material no trae ruido de viento, le pone uno sin costuras.
## Lo normal es dejarlo configurado en grass.tres.
func _ensure_wind_noise() -> void:
	if material == null or material.get_shader_parameter(&"wind_noise") != null:
		return
	var noise: FastNoiseLite = FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.012
	noise.fractal_octaves = 2
	var texture: NoiseTexture2D = NoiseTexture2D.new()
	texture.width = 256
	texture.height = 256
	texture.seamless = true
	texture.noise = noise
	material.set_shader_parameter(&"wind_noise", texture)


func _clear_chunks() -> void:
	for child: Node in get_children():
		if child.has_meta(CHUNK_META):
			remove_child(child)
			child.queue_free()
