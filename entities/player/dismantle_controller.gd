class_name DismantleController
extends Node3D
## Modo desmontar (C2.2, D-033 del prototipo; D-089: imprescindible en el vertical slice). Hijo del jugador
## (lo crea `Player`). X entra y sale; no puede estar a la vez que el modo construcción (B).
## - Clic sobre una construcción la marca (rojo); mantenerlo y barrer marca o desmarca lo que pase por la
##   mira: el primer clic decide si marca o desmarca.
## - Mayús + clic y arrastrar marca todo lo de un recuadro del suelo (como mucho MAX_AREA_SIDE de lado).
## - Clic derecho abre la ventana de confirmar (César: sin soltar el ratón) (`DismantleWindow`), que enseña lo que se recupera: el coste y todo
##   lo que llevan dentro. Si no cabe en el inventario, no se desmonta nada (todo o nada).

## Se emite al entrar o salir del modo.
signal mode_changed(active: bool)
## Se emite al hacer clic derecho con algo marcado: la interfaz abre la ventana de confirmar.
signal confirm_requested
## Se emite tras desmontar lo marcado (el plano de la mano da un golpecito, D-223).
signal dismantled

## Lado máximo del recuadro (20 × 20 = 400 casillas, como en el prototipo).
const MAX_AREA_SIDE: int = 20
const AREA_COLOR: Color = Color(1.0, 0.25, 0.2, 0.25)
## Sonido al desmontar: el de colocar al revés (se oye «deshacerse»).
const DISMANTLE_SOUND: AudioStream = preload("res://assets/audio/build_dismantle.wav")

var player: Player
## ¿Estamos en el modo desmontar?
var active: bool = false

## Ids marcados para desmontar.
var _marked: Dictionary[int, bool] = {}
## Barrido en curso: true = marcando, false = desmarcando.
var _sweeping: bool = false
var _sweep_marks: bool = true
## Recuadro en curso: casilla donde empezó.
var _boxing: bool = false
var _box_start: Vector2i
var _box_end: Vector2i
var _box_mesh: MeshInstance3D


func _ready() -> void:
	top_level = true
	_box_mesh = MeshInstance3D.new()
	_box_mesh.mesh = BoxMesh.new()
	var material := StandardMaterial3D.new()
	material.albedo_color = AREA_COLOR
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_box_mesh.material_override = material
	_box_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_box_mesh.visible = false
	add_child(_box_mesh)
	player.build_controller.mode_changed.connect(_on_build_mode_changed)


## Ids marcados que siguen existiendo.
func get_marked_ids() -> Array[int]:
	var ids: Array[int] = []
	var island: IslandState = _island()
	for id: int in _marked:
		if island.buildings.has(id):
			ids.append(id)
	return ids


## Reembolso de lo marcado (coste y contenido), calculado ahora.
func get_refund() -> Dictionary[ItemData, int]:
	return _island().refund_for(get_marked_ids())


## Desmonta lo marcado si cabe el reembolso. Devuelve true si lo ha hecho.
func confirm() -> bool:
	var ids: Array[int] = get_marked_ids()
	if ids.is_empty():
		return false
	var positions: Array[Vector3] = []
	for id: int in ids:
		var view: BuildingView = _view(id)
		if view != null:
			positions.append(view.global_position)
	if not _island().dismantle(ids, WorldState.player_inventory):
		return false
	_marked.clear()
	for at: Vector3 in positions:
		DustPuff.spawn(get_parent(), at + Vector3(0.0, 0.2, 0.0))
	if not positions.is_empty():
		_play_sound(positions[0])
	dismantled.emit()
	return true


func _unhandled_input(event: InputEvent) -> void:
	if WindowManager.is_open():
		return
	if event.is_action_pressed("toggle_dismantle"):
		set_active(not active)
		get_viewport().set_input_as_handled()
		return
	if not active:
		return
	if event.is_action_pressed("build_place") and Aim.pointer_ready():
		if Input.is_action_pressed("select_area"):
			var cell: Variant = _aimed_cell()
			if cell != null:
				_boxing = true
				_box_start = cell
				_box_end = cell
		else:
			var id: int = _aimed_building_id()
			if id != 0:
				_sweeping = true
				_sweep_marks = not _marked.has(id)
				_set_mark(id, _sweep_marks)
		get_viewport().set_input_as_handled()
	elif event.is_action_released("build_place"):
		if _boxing:
			_apply_box()
		_sweeping = false
		_boxing = false
		_box_mesh.visible = false
	elif event.is_action_pressed("dismantle_confirm") and not get_marked_ids().is_empty():
		confirm_requested.emit()
		get_viewport().set_input_as_handled()


## Entra o sale del modo. Al salir se desmarca todo.
func set_active(value: bool) -> void:
	if value == active:
		return
	active = value
	if active:
		player.build_controller.leave()
	else:
		_clear_marks()
		_sweeping = false
		_boxing = false
		_box_mesh.visible = false
	mode_changed.emit(active)


func _process(_delta: float) -> void:
	if not active:
		return
	# Lo que ya no existe (desmontado, o una partida cargada) deja de estar marcado.
	var island: IslandState = _island()
	for id: int in _marked.keys():
		if not island.buildings.has(id):
			_marked.erase(id)
	if _sweeping:
		var id: int = _aimed_building_id()
		if id != 0:
			_set_mark(id, _sweep_marks)
	if _boxing:
		var cell: Variant = _aimed_cell()
		if cell != null:
			_box_end = cell
		_update_box_mesh()


func _on_build_mode_changed(build_active: bool) -> void:
	if build_active:
		set_active(false)


func _set_mark(id: int, marked: bool) -> void:
	if marked == _marked.has(id):
		return
	if marked:
		_marked[id] = true
	else:
		_marked.erase(id)
	var view: BuildingView = _view(id)
	if view != null:
		view.set_marked(marked)


func _clear_marks() -> void:
	for id: int in _marked:
		var view: BuildingView = _view(id)
		if view != null:
			view.set_marked(false)
	_marked.clear()


## Recuadro de `_box_start` a `_box_end`, recortado a MAX_AREA_SIDE desde el inicio.
func _box_rect() -> Rect2i:
	var end: Vector2i = _box_end
	end.x = clampi(end.x, _box_start.x - MAX_AREA_SIDE + 1, _box_start.x + MAX_AREA_SIDE - 1)
	end.y = clampi(end.y, _box_start.y - MAX_AREA_SIDE + 1, _box_start.y + MAX_AREA_SIDE - 1)
	var top_left := Vector2i(mini(_box_start.x, end.x), mini(_box_start.y, end.y))
	var size := Vector2i(absi(end.x - _box_start.x) + 1, absi(end.y - _box_start.y) + 1)
	return Rect2i(top_left, size)


func _apply_box() -> void:
	var island: IslandState = _island()
	var rect: Rect2i = _box_rect()
	for x: int in range(rect.position.x, rect.end.x):
		for y: int in range(rect.position.y, rect.end.y):
			var placed: PlacedBuilding = island.get_at(Vector2i(x, y))
			if placed != null:
				_set_mark(placed.id, true)


func _update_box_mesh() -> void:
	var rect: Rect2i = _box_rect()
	(_box_mesh.mesh as BoxMesh).size = Vector3(rect.size.x, 0.12, rect.size.y)
	var ground: float = _island().build_height(rect.position)   # a la altura de lo construido (C5.3b, sesión 31)
	_box_mesh.global_position = Vector3(rect.position.x + rect.size.x * 0.5, ground + 0.06, rect.position.y + rect.size.y * 0.5)
	_box_mesh.visible = true


func _aim() -> Dictionary:
	var exclude: Array[RID] = [player.get_rid()]
	return Aim.from_screen_center(get_viewport(), player.build_controller.reach, exclude)


## Id de la construcción que se mira (0 si ninguna).
func _aimed_building_id() -> int:
	var hit: Dictionary = _aim()
	if hit.is_empty():
		return 0
	var view := hit["collider"] as BuildingView
	return view.placed.id if view != null and view.placed != null else 0


## Casilla del suelo que se mira (null si nada).
func _aimed_cell() -> Variant:
	var hit: Dictionary = _aim()
	if hit.is_empty():
		return null
	# Un poco hacia dentro de lo que se toca, para que el lado de una construcción cuente como su casilla.
	var point: Vector3 = (hit["position"] as Vector3) - (hit["normal"] as Vector3) * 0.05
	return GridMath.world_to_cell(point)


func _island() -> IslandState:
	return WorldState.get_island(player.build_controller.island_id)


func _view(id: int) -> BuildingView:
	var island_view: Node = get_tree().get_first_node_in_group(&"island_view")
	return island_view.get_view(id) if island_view != null else null


func _play_sound(at: Vector3) -> void:
	var sound := AudioStreamPlayer3D.new()
	sound.stream = DISMANTLE_SOUND
	sound.bus = &"SFX"
	sound.pitch_scale = randf_range(0.92, 1.08)
	get_parent().get_parent().add_child(sound)
	sound.global_position = at
	sound.finished.connect(sound.queue_free)
	sound.play()
