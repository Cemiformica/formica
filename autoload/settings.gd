extends Node
## Autoload `Settings` (B5.3): opciones gráficas del jugador. Se guardan en `user://settings.cfg`, aparte de la
## partida, y se aplican al arrancar y cada vez que cambian. Valores por defecto: los de D-084.
## Dónde tocar: los valores de cada nivel de sombras en SHADOW_LEVELS y los de la escala en RENDER_SCALES.
## La distancia de las sombras se pone a la luz del sol de cada escena: el `DirectionalLight3D` del grupo «sun».

## Se emite después de aplicar un cambio (p. ej., para que el panel se refresque).
signal changed

const PATH: String = "user://settings.cfg"
const SECTION: String = "graphics"
## Nombres de las opciones (también son las claves del archivo).
const OPTIONS: Array[StringName] = [&"fullscreen", &"vsync", &"msaa", &"smaa", &"shadow_quality", &"render_scale"]
## MSAA por índice: No · 2x · 4x · 8x.
const MSAA_LEVELS: Array[Viewport.MSAA] = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X, Viewport.MSAA_8X]
## Sombras por índice (Baja · Media · Alta): tamaño del mapa del sol, filtro y distancia máxima en metros.
const SHADOW_LEVELS: Array[Dictionary] = [
	{"size": 2048, "filter": RenderingServer.SHADOW_QUALITY_SOFT_LOW, "distance": 20.0},
	{"size": 4096, "filter": RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM, "distance": 30.0},
	{"size": 4096, "filter": RenderingServer.SHADOW_QUALITY_SOFT_HIGH, "distance": 40.0},
]
## Escala de render por índice: 50 % · 75 % · 100 %. Por debajo de 100 % se reescala con FSR.
const RENDER_SCALES: Array[float] = [0.5, 0.75, 1.0]

var fullscreen: bool = true
var vsync: bool = true
var msaa: int = 2 ## índice en MSAA_LEVELS (4x)
var smaa: bool = true
var shadow_quality: int = 2 ## índice en SHADOW_LEVELS (Alta)
var render_scale: int = 2 ## índice en RENDER_SCALES (100 %)


func _ready() -> void:
	_load()
	apply()
	# Las luces del sol que vayan entrando en escena reciben la distancia de sombras elegida.
	get_tree().node_added.connect(_on_node_added)


## Cambia una opción (nombre de OPTIONS), la aplica y la guarda.
func set_option(option: StringName, value: Variant) -> void:
	if not OPTIONS.has(option):
		push_warning("Settings: opción desconocida %s" % option)
		return
	set(option, value)
	_clamp_values()
	apply()
	_save()


## Aplica todas las opciones a la ventana, al render y a las luces del sol.
func apply() -> void:
	var root: Window = get_tree().root
	if fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	elif DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	root.msaa_3d = MSAA_LEVELS[msaa]
	root.screen_space_aa = Viewport.SCREEN_SPACE_AA_SMAA if smaa else Viewport.SCREEN_SPACE_AA_DISABLED
	root.scaling_3d_scale = RENDER_SCALES[render_scale]
	root.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if render_scale < RENDER_SCALES.size() - 1 else Viewport.SCALING_3D_MODE_BILINEAR
	var level: Dictionary = SHADOW_LEVELS[shadow_quality]
	RenderingServer.directional_shadow_atlas_set_size(level["size"], true)
	RenderingServer.directional_soft_shadow_filter_set_quality(level["filter"])
	for node: Node in get_tree().get_nodes_in_group(&"sun"):
		_apply_sun(node)
	changed.emit()


func _on_node_added(node: Node) -> void:
	if node is DirectionalLight3D and node.is_in_group(&"sun"):
		_apply_sun(node)


func _apply_sun(node: Node) -> void:
	var sun := node as DirectionalLight3D
	if sun != null:
		sun.directional_shadow_max_distance = SHADOW_LEVELS[shadow_quality]["distance"]


## Lee el archivo; lo que falte o esté dañado se queda con su valor por defecto.
func _load() -> void:
	var file := ConfigFile.new()
	if file.load(PATH) != OK:
		return # primera vez: valores por defecto
	for option: StringName in OPTIONS:
		var current: Variant = get(option)
		var stored: Variant = file.get_value(SECTION, String(option), current)
		if typeof(stored) == typeof(current):
			set(option, stored)
	_clamp_values()


func _save() -> void:
	var file := ConfigFile.new()
	for option: StringName in OPTIONS:
		file.set_value(SECTION, String(option), get(option))
	var error: Error = file.save(PATH)
	if error != OK:
		push_warning("Settings: no se pudieron guardar las opciones: %s" % error_string(error))


func _clamp_values() -> void:
	msaa = clampi(msaa, 0, MSAA_LEVELS.size() - 1)
	shadow_quality = clampi(shadow_quality, 0, SHADOW_LEVELS.size() - 1)
	render_scale = clampi(render_scale, 0, RENDER_SCALES.size() - 1)
