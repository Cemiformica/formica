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
## Los fantasmas «respiran» (César: el suelo por reparar parecía tierra): cada GHOST_PULSE_TIME segundos se aclaran hacia
## GHOST_PULSE_COLOR y ganan algo de opacidad. Así se distingue lo que falta de lo que ya está.
const GHOST_PULSE_TIME: float = 2.4
const GHOST_PULSE_COLOR: Color = Color(1.0, 0.93, 0.7)
const GHOST_PULSE_ALPHA: float = 0.16
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
## Abrir y cerrar (la trampilla, C5.5): lo que tarda en girar y los sonidos. Cerrar usa el de soltar; abrir,
## el mismo un 20 % más agudo y rápido, para que se parezcan sin ser iguales (César, sesión 24).
const TOGGLE_TIME: float = 0.7
const OPEN_SOUND: AudioStream = preload("res://assets/audio/hatch_open.wav")
const CLOSE_SOUND: AudioStream = preload("res://assets/audio/move_drop.wav")

var site: RepairSite
var island: IslandState

var _model: Node3D = null
## Por pieza, en el orden de `site.data.pieces`: su nodo del modelo (null si el modelo no la tiene), su
## objetivo para mirar y entregar, su material de fantasma y si ya estaba completa.
var _pieces: Array[Node3D] = []
var _targets: Array[RepairPieceTarget] = []
var _ghosts: Array[StandardMaterial3D] = []
var _done: Array[bool] = []
## Opacidad de cada fantasma sin el pulso (la pone `_set_ghost_alpha`; `_process` le suma el pulso).
var _ghost_alpha: Array[float] = []
## Por pieza: los nodos que giran al abrirla (vacío si no se abre) y su giro cerrado, en el mismo orden que
## `RepairPieceData.toggle_nodes`.
var _toggles: Array[Array] = []
var _toggle_closed: Array[Array] = []
## Cuerdas que se mueven (C5.5): el modelo trae parejas de vacíos «rope_a_N» y «rope_b_N» y aquí se dibuja una cuerda
## tensa entre cada pareja. Se rehacen mientras algo se mueve (abrir, cerrar o crecer al completar una pieza).
var _ropes: Array[Dictionary] = []
var _ropes_until_ms: int = 0
const ROPE_THICKNESS: float = 0.05   # como la cuerda fija del modelo (ROPE_R de shelter_blockout.py)
const ROPE_COLOR: Color = Color(0.36, 0.25, 0.15)
## Haz de luz (C5.5, D-180): si el modelo trae «light_shaft_top» y «light_shaft_bottom», se ve mientras la pieza que
## los contiene (la trampilla) esté abierta.
var _shaft: LightShaft = null
var _shaft_piece: int = -1
## Luces que se encienden y apagan con E (C5.5, D-191): el candil y el fogón. Una por `RepairLightData`, en el mismo
## orden (null si el modelo no trae su vacío). Lo que cuelga de «lantern» y las llamas y brasas no chocan.
var _glows: Array[LanternGlow] = []
var _light_targets: Array[RepairLightTarget] = []


## Prepara la vista. Se llama ANTES de añadirla al árbol.
func setup(p_site: RepairSite, p_island: IslandState) -> void:
	site = p_site
	island = p_island
	name = "repair_%s_%d_%d" % [site.data.id, site.origin.x, site.origin.y]
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	position = GridMath.footprint_center(site.origin, site.data.size, site.rotation, island.ground_height(site.origin))
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
		_ghost_alpha.append(GHOST_ALPHA_MIN)
		var piece_data: RepairPieceData = site.data.pieces[i]
		var aim: Node3D = _pieces[i]
		if _model != null and piece_data.aim_node != &"":
			var found := _model.find_child(String(piece_data.aim_node), true, false) as Node3D
			if found != null:
				aim = found
		var nodes: Array[Node3D] = []
		var closed: Array[Vector3] = []
		for k: int in piece_data.toggle_nodes.size():
			var node: Node3D = _pieces[i].find_child(String(piece_data.toggle_nodes[k]), true, false) as Node3D \
					if _pieces[i] != null else null
			if node == null:
				push_warning("RepairSiteView: la pieza %s no tiene el nodo %s" % [piece_data.id, piece_data.toggle_nodes[k]])
				continue
			nodes.append(node)
			closed.append(node.rotation)
			if site.is_open(i):
				node.rotation = node.rotation + _toggle_angle(piece_data, k)   # ya abierta al cargar
		_toggles.append(nodes)
		_toggle_closed.append(closed)
		var target := RepairPieceTarget.new()
		var aim_box: AABB = _piece_box(aim)
		if piece_data.aim_size != Vector3.ZERO and aim != null:
			var aim_center: Vector3 = _relative_transform(aim).origin
			aim_box = AABB(aim_center - piece_data.aim_size * 0.5, piece_data.aim_size)
		target.setup(self, i, aim_box)
		if site.data.exact_collision and _pieces[i] != null:
			target.exact_body = _add_piece_collision(_pieces[i], i)
		add_child(target)
		_targets.append(target)
		_done.append(site.is_piece_done(i))
		_apply(i)
	_find_ropes()
	_add_light_shaft()
	_add_lights()


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


## Se abrió o se cerró la pieza `index` (lo llama `IslandView`): el nodo gira con un pequeño rebote al final.
func on_piece_toggled(index: int) -> void:
	if index < 0 or index >= _toggles.size() or _toggles[index].is_empty():
		return
	var open: bool = site.is_open(index)
	var piece_data: RepairPieceData = site.data.pieces[index]
	var tween := create_tween().set_parallel(true)
	for k: int in _toggles[index].size():
		var node: Node3D = _toggles[index][k]
		var goal: Vector3 = _toggle_closed[index][k] + (_toggle_angle(piece_data, k) if open else Vector3.ZERO)
		tween.tween_property(node, "rotation", goal, TOGGLE_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_animate_ropes(TOGGLE_TIME + 0.1)
	if _shaft != null and index == _shaft_piece:
		_shaft.set_on(open)
	var sound := AudioStreamPlayer3D.new()
	sound.stream = OPEN_SOUND if open else CLOSE_SOUND
	sound.bus = &"SFX"
	add_child(sound)
	sound.global_position = _targets[index].global_position
	sound.finished.connect(sound.queue_free)
	sound.play()


func _ready() -> void:
	_update_ropes()


func _process(_delta: float) -> void:
	var pulse: float = _pulse()
	for i: int in _ghosts.size():
		if not _done[i]:
			_paint_ghost(i, pulse)
	if not _ropes.is_empty() and Time.get_ticks_msec() < _ropes_until_ms:
		_update_ropes()


## Busca en el modelo las parejas «rope_a_N» / «rope_b_N» y crea una cuerda por pareja (de la pieza que las contiene).
func _find_ropes() -> void:
	if _model == null:
		return
	var material := StandardMaterial3D.new()
	material.albedo_color = ROPE_COLOR
	material.roughness = 1.0
	for n: int in 16:
		var a := _model.find_child("rope_a_%d" % n, true, false) as Node3D
		var b := _model.find_child("rope_b_%d" % n, true, false) as Node3D
		if a == null or b == null:
			break
		var piece: int = -1
		for i: int in _pieces.size():
			if _pieces[i] != null and _pieces[i].is_ancestor_of(b):
				piece = i
		var line := MeshInstance3D.new()
		line.name = "Rope_%d" % n
		add_child(line)
		_ropes.append({"a": a, "b": b, "line": line, "piece": piece, "material": material})
	_paint_ropes()


## Cada cuerda, del color de cuerda o, si su pieza aún falta, de fantasma (como el resto de la pieza).
func _paint_ropes() -> void:
	for rope: Dictionary in _ropes:
		var piece: int = rope["piece"]
		var ghost: bool = piece >= 0 and piece < _done.size() and not _done[piece]
		var line: MeshInstance3D = rope["line"]
		line.material_override = _ghosts[piece] if ghost else rope["material"]
		line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if ghost else GeometryInstance3D.SHADOW_CASTING_SETTING_ON


## Rehace las cuerdas durante `seconds` segundos (mientras gira o crece algo).
func _animate_ropes(seconds: float) -> void:
	_ropes_until_ms = maxi(_ropes_until_ms, Time.get_ticks_msec() + int(seconds * 1000.0))


func _update_ropes() -> void:
	if not is_inside_tree():
		return
	for rope: Dictionary in _ropes:
		IslandView.place_cable(rope["line"], (rope["a"] as Node3D).global_position, (rope["b"] as Node3D).global_position,
				ROPE_THICKNESS, true)


## Giro al abrir del nodo `k` de una pieza, en radianes (el `.tres` lo da en grados).
static func _toggle_angle(piece_data: RepairPieceData, k: int) -> Vector3:
	return piece_data.toggle_rotations[k] * (PI / 180.0) if k < piece_data.toggle_rotations.size() else Vector3.ZERO


## La estructura entera se ha completado (lo llama `IslandView`): polvo alrededor de la base cuando
## aterriza la última pieza.
func on_completed() -> void:
	get_tree().create_timer(GROW_TIME).timeout.connect(_dust_ring)
	for target: RepairLightTarget in _light_targets:
		target.refresh()
	# Las luces que se encienden solas (el candil) prenden cuando la última pieza se asienta.
	get_tree().create_timer(GROW_TIME + POP_TIME).timeout.connect(_show_lights)


func _show_lights() -> void:
	for i: int in _glows.size():
		if _glows[i] != null and site.is_lit(i) != _glows[i].is_lit():
			_glows[i].set_lit(site.is_lit(i))


## Se encendió o apagó la luz `index` (lo llama `IslandView`).
func on_light_switched(index: int) -> void:
	if index >= 0 and index < _glows.size() and _glows[index] != null:
		_glows[index].set_lit(site.is_lit(index))


## Haz de luz entre «light_shaft_top» y «light_shaft_bottom», encendido si su pieza ya está abierta.
func _add_light_shaft() -> void:
	if _model == null:
		return
	var top := _model.find_child("light_shaft_top", true, false) as Node3D
	var bottom := _model.find_child("light_shaft_bottom", true, false) as Node3D
	if top == null or bottom == null:
		return
	for i: int in _pieces.size():
		if _pieces[i] != null and _pieces[i].is_ancestor_of(top):
			_shaft_piece = i
	_shaft = LightShaft.new()
	_shaft.setup(_relative_transform(top).origin, _relative_transform(bottom).origin)
	add_child(_shaft)
	_shaft.set_on(_shaft_piece >= 0 and site.is_open(_shaft_piece), false)


## Una luz por `RepairLightData`: su llama (candil u hoguera) en su vacío y su objetivo para la E, encendida o
## apagada según la partida.
func _add_lights() -> void:
	for i: int in site.data.lights.size():
		var light: RepairLightData = site.data.lights[i]
		var anchor: Node3D = _model.find_child(String(light.light_node), true, false) as Node3D \
				if _model != null and light != null else null
		if anchor == null:
			push_warning("RepairSiteView: el modelo de %s no tiene la luz %s" % [site.data.id, light.light_node if light != null else &"?"])
			_glows.append(null)
			continue
		var flames: Array[MeshInstance3D] = []
		if light.flame_prefix != "":
			for node: Node in _model.find_children(light.flame_prefix + "*", "MeshInstance3D", true, false):
				flames.append(node as MeshInstance3D)
		var embers: MeshInstance3D = _model.find_child(String(light.ember_node), true, false) as MeshInstance3D \
				if light.ember_node != &"" else null
		var glow := LanternGlow.new()
		glow.setup(flames, light.fire, embers)
		anchor.add_child(glow)
		glow.set_lit(site.is_lit(i), false)
		_glows.append(glow)
		var target := RepairLightTarget.new()
		var center: Vector3 = _relative_transform(anchor).origin
		target.setup(self, i, AABB(center - light.aim_size * 0.5, light.aim_size))
		add_child(target)
		_light_targets.append(target)


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
	_paint_ropes()


## Pieza completa: crece desde pequeña, se aplasta al llegar, rebota y suelta polvo, con el sonido de
## colocar (que tiene el zumbido mientras crece y el golpe al llegar).
func _play_complete(index: int) -> void:
	_play_sound(PLACE_SOUND, _targets[index].global_position)
	var node: Node3D = _pieces[index]
	if node == null:
		return
	var base_scale: Vector3 = node.scale
	_grow(0.0, node, base_scale)
	_animate_ropes(GROW_TIME + POP_TIME + 0.1)
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
	var settled: float = _ghost_alpha[index]
	var tween: Tween = create_tween()
	tween.tween_method(_set_ghost_alpha.bind(index), minf(settled + 0.35, 0.9), settled, FLASH_TIME)


func _set_ghost_alpha(alpha: float, index: int) -> void:
	_ghost_alpha[index] = alpha
	_paint_ghost(index, _pulse())


## Pulso de los fantasmas, de 0 a 1 (suave, de ida y vuelta).
func _pulse() -> float:
	return 0.5 - 0.5 * cos(TAU * float(Time.get_ticks_msec()) / 1000.0 / GHOST_PULSE_TIME)


## Color y opacidad del fantasma `index` con el pulso `pulse`.
func _paint_ghost(index: int, pulse: float) -> void:
	var color: Color = GHOST_COLOR.lerp(GHOST_PULSE_COLOR, pulse * 0.6)
	color.a = minf(_ghost_alpha[index] + GHOST_PULSE_ALPHA * pulse, 0.95)
	_ghosts[index].albedo_color = color


## Polvo alrededor de la base (esquinas y mitad de cada lado), como al colocar una construcción.
func _dust_ring() -> void:
	if not is_inside_tree():
		return
	var s: Vector2i = OccupancyGrid.rotated_size(site.data.size, site.rotation)
	var center: Vector3 = GridMath.footprint_center(site.origin, site.data.size, site.rotation, position.y)
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
	if site.data.exact_collision:
		_add_exact_collision(piece_nodes)
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


## Choque con la forma de cada malla de la base (C5.5): se entra por la boca y se anda por dentro. El candil, las
## llamas y las brasas no chocan.
func _add_exact_collision(piece_nodes: Array[Node]) -> void:
	var body := StaticBody3D.new()
	body.name = "BaseCollision"
	var lantern: Node = _model.find_child("lantern", true, false)
	for mesh: MeshInstance3D in _meshes_of(_model):
		var inside_piece: bool = lantern != null and (lantern == mesh or lantern.is_ancestor_of(mesh)) \
				or "flame" in String(mesh.name) or "ember" in String(mesh.name)
		for piece: Node in piece_nodes:
			if piece.is_ancestor_of(mesh):
				inside_piece = true
				break
		if inside_piece or mesh.mesh == null:
			continue
		var collision := CollisionShape3D.new()
		collision.shape = mesh.mesh.create_trimesh_shape()
		collision.transform = _relative_transform(mesh)
		body.add_child(collision)
	add_child(body)


## Choque con la forma real de una pieza (C5.5): un cuerpo con una forma por malla, apagado hasta completarla
## (`RepairPieceTarget.set_done`).
func _add_piece_collision(node: Node3D, index: int) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "PieceCollision_%d" % index
	body.collision_layer = 0
	for mesh: MeshInstance3D in _meshes_of(node):
		if mesh.mesh == null:
			continue
		var collision := CollisionShape3D.new()
		collision.shape = mesh.mesh.create_trimesh_shape()
		collision.transform = _relative_transform(mesh)
		body.add_child(collision)
	add_child(body)
	return body


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
