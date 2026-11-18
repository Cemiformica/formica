class_name RepairSiteView
extends Node3D
## Estructura por reparar visible (C4.3, D-115). Solo MUESTRA un `RepairSite` de `IslandState` (D-046): la
## crea `IslandView`. Dibuja su modelo; las piezas que faltan se ven como fantasmas translúcidos de color
## ámbar, más opacos cuanto más se les ha entregado. Cada pieza es un `RepairPieceTarget`: al mirarla, el
## letrero de arriba dice qué pide, y con E se le entrega lo que lleves.
## Al completarse una pieza, crece y rebota con su polvo y el sonido de colocar, como una construcción (B5.4).
## Al completarse la estructura entera, sale además polvo alrededor de su base.
## Las piezas que faltan no chocan (se atraviesan); las completas y la base, sí.

## Ámbar de la colonia (6,2): distinto del verde del fantasma de construir.
const GHOST_COLOR: Color = Color8(255, 184, 58)
## Opacidad del fantasma sin nada entregado y casi completo.
const GHOST_ALPHA_MIN: float = 0.18
const GHOST_ALPHA_MAX: float = 0.5
## Efecto al completar una pieza: los mismos tiempos que el de colocar (`BuildingView`, B5.4).
const GROW_TIME: float = 0.2
const GROW_START: float = 0.15
const POP_TIME: float = 0.35
const POP_SQUASH: float = 0.2
const DUST_COLOR: Color = Color(0.56, 0.47, 0.34)
## Al entregar sin completar: el fantasma parpadea un momento y suena el clic neumático de los puertos.
const FLASH_TIME: float = 0.25
const PLACE_SOUND: AudioStream = preload("res://assets/audio/build_place.wav")
const DELIVER_SOUND: AudioStream = preload("res://assets/audio/link_pneumatic.wav")
## Lado mínimo de la caja de choque de una pieza (m), para poder apuntarle aunque sea fina.
const MIN_BOX: float = 0.25

var site: RepairSite
var island: IslandState

var _model: Node3D = null
## Por pieza, en el orden de `site.data.pieces`: su nodo del modelo (null si el modelo no la tiene), su
## objetivo para mirar y entregar, su material de fantasma y si ya estaba completa.
var _pieces: Array[Node3D] = []
var _targets: Array[RepairPieceTarget] = []
var _ghosts: Array[StandardMaterial3D] = []
var _done: Array[bool] = []


## Prepara la vista. Se llama ANTES de añadirla al árbol.
func setup(p_site: RepairSite, p_island: IslandState) -> void:
	site = p_site
	island = p_island
	name = "repair_%s_%d_%d" % [site.data.id, site.origin.x, site.origin.y]
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	position = GridMath.footprint_center(site.origin, site.data.size, site.rotation)
	rotation.y = GridMath.rotation_to_yaw(site.rotation)
	if site.data.scene != null:
		_model = site.data.scene.instantiate() as Node3D
		add_child(_model)
	var piece_nodes: Array[Node] = []
	for piece: RepairPieceData in site.data.pieces:
		var node: Node3D = null
		if _model != null and piece.node_name != &"":
			node = _model.find_child(String(piece.node_name), true, false) as Node3D
		if node == null:
			push_warning("RepairSiteView: el modelo de %s no tiene la pieza %s" % [site.data.id, piece.node_name])
		_pieces.append(node)
		if node != null:
			piece_nodes.append(node)
	_add_base_collision(piece_nodes)
	for i: int in site.data.pieces.size():
		var material := StandardMaterial3D.new()
		material.albedo_color = GHOST_COLOR
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_ghosts.append(material)
		var target := RepairPieceTarget.new()
		target.setup(self, i, _piece_box(_pieces[i]))
		add_child(target)
		_targets.append(target)
		_done.append(site.is_piece_done(i))
		_apply(i)


## Se entregó algo a la pieza `index` (lo llama `IslandView`).
func on_piece_changed(index: int) -> void:
	if index < 0 or index >= _done.size():
		return
	var now_done: bool = site.is_piece_done(index)
	var was_done: bool = _done[index]
	_done[index] = now_done
	_apply(index)
	if now_done and not was_done:
		_play_complete(index)
	else:
		_play_flash(index)


## La estructura entera se ha completado (lo llama `IslandView`): polvo alrededor de la base cuando
## aterriza la última pieza.
func on_completed() -> void:
	get_tree().create_timer(GROW_TIME).timeout.connect(_dust_ring)


## Pieza `index`: fantasma (con su opacidad según lo entregado) o sólida, y su objetivo al día.
func _apply(index: int) -> void:
	var done: bool = _done[index]
	_set_ghost_alpha(lerpf(GHOST_ALPHA_MIN, GHOST_ALPHA_MAX, site.piece_fraction(index)), index)
	if _pieces[index] != null:
		for mesh: MeshInstance3D in _meshes_of(_pieces[index]):
			mesh.material_override = null if done else _ghosts[index]
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if done \
					else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_targets[index].set_done(done)


## Pieza completa: crece desde pequeña, se aplasta al llegar, rebota y suelta polvo, con el sonido de
## colocar (que tiene el zumbido mientras crece y el golpe al llegar).
func _play_complete(index: int) -> void:
	_play_sound(PLACE_SOUND, _targets[index].global_position)
	var node: Node3D = _pieces[index]
	if node == null:
		return
	var base_scale: Vector3 = node.scale
	_grow(0.0, node, base_scale)
	var tween: Tween = create_tween()
	tween.tween_method(_grow.bind(node, base_scale), 0.0, 1.0, GROW_TIME)
	tween.tween_callback(_land.bind(node))
	tween.tween_method(_pop.bind(node, base_scale), 0.0, 1.0, POP_TIME)


## Crecer: de GROW_START a su tamaño, acelerando (como si cayera en su sitio).
func _grow(t: float, node: Node3D, base_scale: Vector3) -> void:
	if is_instance_valid(node):
		node.scale = base_scale * lerpf(GROW_START, 1.0, t * t)


## El golpe: polvo en la base de la pieza.
func _land(node: Node3D) -> void:
	if is_instance_valid(node) and is_inside_tree():
		DustPuff.spawn(get_parent(), node.global_position + Vector3(0.0, 0.05, 0.0), DUST_COLOR)


## Rebote amortiguado, como goma: la altura oscila alrededor de 1 y lo ancho compensa.
func _pop(t: float, node: Node3D, base_scale: Vector3) -> void:
	if not is_instance_valid(node):
		return
	var stretch: float = 1.0 if t >= 1.0 else 1.0 - POP_SQUASH * exp(-4.0 * t) * cos(t * TAU * 1.5)
	var wide: float = 1.0 / sqrt(stretch)
	node.scale = base_scale * Vector3(wide, stretch, wide)


## Entrega sin completar: el fantasma se ilumina un momento y sale un poco de polvo suave.
func _play_flash(index: int) -> void:
	_play_sound(DELIVER_SOUND, _targets[index].global_position)
	DustPuff.spawn(get_parent(), _targets[index].global_position, GHOST_COLOR, true)
	if _done[index]:
		return
	var settled: float = _ghosts[index].albedo_color.a
	var tween: Tween = create_tween()
	tween.tween_method(_set_ghost_alpha.bind(index), minf(settled + 0.35, 0.9), settled, FLASH_TIME)


func _set_ghost_alpha(alpha: float, index: int) -> void:
	var color: Color = _ghosts[index].albedo_color
	color.a = alpha
	_ghosts[index].albedo_color = color


## Polvo alrededor de la base (esquinas y mitad de cada lado), como al colocar una construcción.
func _dust_ring() -> void:
	if not is_inside_tree():
		return
	var s: Vector2i = OccupancyGrid.rotated_size(site.data.size, site.rotation)
	var center: Vector3 = GridMath.footprint_center(site.origin, site.data.size, site.rotation)
	for side_x: float in [-0.5, 0.0, 0.5]:
		for side_z: float in [-0.5, 0.0, 0.5]:
			if side_x != 0.0 or side_z != 0.0:
				DustPuff.spawn(get_parent(), center + Vector3(side_x * s.x, 0.05, side_z * s.y), DUST_COLOR)


func _play_sound(stream: AudioStream, at: Vector3) -> void:
	var sound := AudioStreamPlayer3D.new()
	sound.stream = stream
	sound.bus = &"SFX"
	add_child(sound)
	sound.global_position = at
	sound.finished.connect(sound.queue_free)
	sound.play()


## Dónde se reaparece al descansar en su cama: el vacío «spawn_point» del modelo o, si no lo tiene, una
## casilla delante de la estructura, mirándola.
func spawn_transform() -> Transform3D:
	var marker: Node3D = _model.find_child("spawn_point", true, false) as Node3D if _model != null else null
	if marker != null and marker.is_inside_tree():
		var spot: Transform3D = marker.global_transform
		return Transform3D(Basis(Vector3.UP, spot.basis.get_euler().y), spot.origin + Vector3(0.0, 0.05, 0.0))
	var depth: float = OccupancyGrid.rotated_size(site.data.size, site.rotation).y
	return Transform3D(global_basis, global_position + global_basis * Vector3(0.0, 0.05, depth * 0.5 + 1.0))


## Choque de la base: una caja con todo lo del modelo que no es pieza.
func _add_base_collision(piece_nodes: Array[Node]) -> void:
	if _model == null:
		return
	var box := AABB()
	var first: bool = true
	for mesh: MeshInstance3D in _meshes_of(_model):
		var inside_piece: bool = false
		for piece: Node in piece_nodes:
			if piece.is_ancestor_of(mesh):
				inside_piece = true
				break
		if inside_piece:
			continue
		var part: AABB = _relative_transform(mesh) * mesh.get_aabb()
		box = part if first else box.merge(part)
		first = false
	if first:
		return
	var body := StaticBody3D.new()
	body.name = "BaseCollision"
	var shape := BoxShape3D.new()
	shape.size = box.size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position = box.get_center()
	body.add_child(collision)
	add_child(body)


## Caja de una pieza en el espacio de esta vista (para su choque y para apuntarle).
func _piece_box(node: Node3D) -> AABB:
	if node == null:
		return AABB(Vector3(-0.5, 0.0, -0.5), Vector3(1.0, 1.0, 1.0))
	var box := AABB()
	var first: bool = true
	for mesh: MeshInstance3D in _meshes_of(node):
		var part: AABB = _relative_transform(mesh) * mesh.get_aabb()
		box = part if first else box.merge(part)
		first = false
	if first:
		box = AABB(_relative_transform(node).origin, Vector3.ZERO)
	box = box.grow(0.02)
	box.size = box.size.max(Vector3.ONE * MIN_BOX)
	return box


## Transformación de `node` respecto al modelo (sirve antes de entrar en el árbol: no usa global_transform).
func _relative_transform(node: Node3D) -> Transform3D:
	var result: Transform3D = Transform3D.IDENTITY
	var current: Node = node
	while current != null and current != self:
		if current is Node3D:
			result = (current as Node3D).transform * result
		current = current.get_parent()
	return result


static func _meshes_of(root: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	if root is MeshInstance3D:
		result.append(root)
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		result.append(node as MeshInstance3D)
	return result
