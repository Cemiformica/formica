class_name VeinView
extends Interactable
## Veta visible (B3.7, D-090). Solo MUESTRA la veta de `IslandState` (D-046): la crea `IslandView`.
## Se dibuja con el modelo de su `VeinData`. Solo los cristales del centro chocan (la losa es baja: se
## camina por encima, y en sus casillas del borde se asientan los extractores).
## E = un golpe: cada `hit_cooldown` segundos como mínimo; al llegar a `hits_per_item` golpes da 1 ítem
## (si cabe en el inventario). Cada golpe levanta una nubecita de polvo y hace botar los cristales.
## El avance de los golpes no se guarda: si te vas, se pierde.

## Choque de los cristales del centro (radio y alto, m).
const CRYSTAL_RADIUS: float = 0.45
const CRYSTAL_HEIGHT: float = 0.8

## Esquina de la veta (casilla con x e y mínimas) e isla a la que pertenece.
var origin: Vector2i
var island: IslandState
var data: VeinData

var _hits: int = 0
var _last_hit_ms: int = -100000
var _model: Node3D = null
var _bump: float = 0.0


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


## Rebote corto del modelo tras un golpe (se ve que el golpe ha contado).
func _process(delta: float) -> void:
	if _bump <= 0.0 or _model == null:
		return
	_bump = maxf(_bump - delta * 6.0, 0.0)
	_model.scale = Vector3.ONE * (1.0 + 0.04 * sin(_bump * PI))


## E: un golpe. Si aún no ha pasado la espera, no cuenta.
func interact(by: Node) -> void:
	super(by)
	var now: int = Time.get_ticks_msec()
	if now - _last_hit_ms < int(data.hit_cooldown * 1000.0):
		return
	if data.item == null:
		return
	var inventory: Inventory = WorldState.player_inventory
	var one: Dictionary[ItemData, int] = {data.item: 1}
	if not inventory.can_add_all(one):
		return # inventario lleno: el golpe no cuenta, para no perder el mineral
	_last_hit_ms = now
	_hits += 1
	_bump = 1.0
	DustPuff.spawn(self, global_position + Vector3(0.0, 0.25, 0.0))
	if _hits >= data.hits_per_item:
		_hits = 0
		inventory.add_item(data.item, 1)
