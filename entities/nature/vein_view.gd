class_name VeinView
extends Interactable
## Veta visible (B3.7, D-090). Solo MUESTRA la veta de `IslandState` (D-046): la crea `IslandView`.
## Se dibuja con el modelo de su `VeinData`. Solo los cristales del centro chocan (la losa es baja: se
## camina por encima, y en sus casillas del borde se asientan los extractores).
## Clic izquierdo (`use`, C1.8) = un golpe; manteniéndolo, va golpeando. En C3 pedirá el pico en la mano.
## Cada `hit_cooldown` segundos como mínimo; al llegar a `hits_per_item` golpes da 1 ítem
## (si cabe en el inventario). Cada golpe levanta una nubecita de polvo y hace botar los cristales.
## El avance de los golpes no se guarda: si te vas, se pierde.

## Choque de los cristales del centro (radio y alto, m).
const CRYSTAL_RADIUS: float = 0.45
const CRYSTAL_HEIGHT: float = 0.8
## Zona de trabajo (C3): una losa baja que cubre las 9 casillas, para picar o perforar en cualquiera.
## Es un Area3D en su propia capa, que solo ve el rayo de interactuar del jugador (no choca con nada ni
## estorba al apuntar para construir).
const WORK_AREA_LAYER: int = 1 << 3   # capa 4
const WORK_AREA_HEIGHT: float = 0.12

## Esquina de la veta (casilla con x e y mínimas) e isla a la que pertenece.
var origin: Vector2i
var island: IslandState
var data: VeinData

var _hits: int = 0
var _last_hit_ms: int = -100000
var _model: Node3D = null
var _bump: float = 0.0
## Temblor de los cristales mientras la barrena perfora (C3) y cada cuánto sale polvo (ms).
var _tremble: float = 0.0
var _fx_ms: int = -100000
const TOOL_FX_MS: int = 140
## Roca perforada, en bucle mientras la barrena trabaja, y el «tin» al soltar un mineral (C3).
const GRIND_SOUND: AudioStreamWAV = preload("res://assets/audio/vein_grind_loop.wav")
const YIELD_SOUND: AudioStream = preload("res://assets/audio/vein_yield.wav")
const GRIND_MAX_DB: float = -19.0   # bajo: no debe tapar el motor de la barrena ni la roca que se parte (César)
const YIELD_DB: float = 7.0   # el trozo que se parte, más fuerte que el rumor de la barrena (César)   # más bajo, para que se note el «tin» del mineral (César)
var _grind_sound: LoopSound = null


## Prepara la vista. Se llama ANTES de añadirla al árbol.
func setup(p_origin: Vector2i, p_data: VeinData, p_island: IslandState) -> void:
	origin = p_origin
	data = p_data
	island = p_island
	name = "vein_%d_%d" % [origin.x, origin.y]
	display_name_key = data.name_key
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	position = GridMath.footprint_center(origin, Vector2i(VeinData.SIZE, VeinData.SIZE), 0)
	if data.scene != null:
		_model = data.scene.instantiate() as Node3D
		add_child(_model)
	var shape := CylinderShape3D.new()
	shape.radius = CRYSTAL_RADIUS
	shape.height = CRYSTAL_HEIGHT
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position.y = CRYSTAL_HEIGHT * 0.5
	add_child(collision)
	var area := Area3D.new()
	area.name = "WorkArea"
	area.collision_layer = WORK_AREA_LAYER
	area.collision_mask = 0
	area.monitoring = false
	var slab := BoxShape3D.new()
	slab.size = Vector3(VeinData.SIZE, WORK_AREA_HEIGHT, VeinData.SIZE)
	var slab_shape := CollisionShape3D.new()
	slab_shape.shape = slab
	slab_shape.position.y = WORK_AREA_HEIGHT * 0.5
	area.add_child(slab_shape)
	add_child(area)


## Rebote corto del modelo tras un golpe (se ve que el golpe ha contado).
func _process(delta: float) -> void:
	if (_bump <= 0.0 and _tremble <= 0.0) or _model == null:
		return
	_bump = maxf(_bump - delta * 6.0, 0.0)
	_tremble = maxf(_tremble - delta * 4.0, 0.0)
	var jitter: float = 0.01 * sin(Time.get_ticks_msec() * 0.11) * _tremble
	_model.scale = Vector3.ONE * (1.0 + 0.04 * sin(_bump * PI) + jitter)


## Qué hace el clic aquí, para el letrero de arriba.
func get_use_hint_key() -> String:
	return "HINT_MINE"


## Clic: un golpe. Si aún no ha pasado la espera, no cuenta.
func use(_by: Node) -> void:
	var now: int = Time.get_ticks_msec()
	if data.item == null:
		return
	var with_tool: bool = _by.has_method("holding_tool") and _by.holding_tool()
	var at: Vector3 = _by.work_point() if _by.has_method("work_point") else global_position + Vector3(0.0, 0.25, 0.0)
	if with_tool:
		# La barrena perfora sin parar: polvo del color del mineral donde toca y los cristales tiemblan (C3).
		_tremble = 1.0
		if _grind_sound == null:
			_grind_sound = LoopSound.create(self, GRIND_SOUND, GRIND_MAX_DB)
		_grind_sound.global_position = at
		_grind_sound.keep()
		if now - _fx_ms >= TOOL_FX_MS:
			_fx_ms = now
			DustPuff.spawn(self, at, data.item.color, true)
	if now - _last_hit_ms < int(data.hit_cooldown * 1000.0):
		return
	var inventory: Inventory = WorldState.player_inventory
	var one: Dictionary[ItemData, int] = {data.item: 1}
	if not inventory.can_add_all(one):
		return # inventario lleno: el golpe no cuenta, para no perder el mineral
	_last_hit_ms = now
	_hits += 1
	if not with_tool:   # con la barrena no hay rebote de golpe: solo el temblor mientras perfora (César)
		_bump = 1.0
		DustPuff.spawn(self, at)
	if _hits >= data.hits_per_item:
		_hits = 0
		inventory.add_item(data.item, 1)
		ItemPop.spawn(get_parent(), data.item, at)   # el mineral salta hacia la barra (C3)
		PickupFeed.notify(data.item, 1)
		var sound := AudioStreamPlayer3D.new()
		sound.stream = YIELD_SOUND
		sound.bus = &"SFX"
		sound.volume_db = YIELD_DB
		sound.pitch_scale = randf_range(0.92, 1.1)
		add_child(sound)
		sound.global_position = at
		sound.finished.connect(sound.queue_free)
		sound.play()
