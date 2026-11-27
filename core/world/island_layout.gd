class_name IslandLayout
extends RefCounted
## Plano de una isla (C5.3, D-155): lo lee de un archivo de texto con un carácter por casilla
## (`content/islands/isla_alba.txt`; la leyenda está en sus comentarios `//`). Cada carácter es la casilla de
## la cuadrícula del mismo número: la esquina de arriba a la izquierda es la (0, 0).
## Es parte de cómo es la isla (lo pone su escena), no de la partida: no se guarda.
## Dice de cada casilla qué suelo tiene, a qué altura está, si es agua (y hacia dónde corre), si se puede
## construir y si pueden aparecer rocas y palos. Los objetos (`T`, `M`, `R`…) se quedan apuntados en
## `features` para que la isla los ponga (C5.3c) y su suelo se deduce de las casillas de alrededor.
## Dónde tocar: `_GROUND_BY_CHAR` y `_FLOW_BY_CHAR` si cambia la leyenda.

## Tipo de suelo de una casilla.
enum Ground { SEA, BEACH, LOW, LOW_FLAT, HIGH, HIGH_FLAT, SLOPE, LANDING, WATER, FALL, MID, MID_FLAT, HILL, TOP, TOP_FLAT, RAMP, HIGH_HILL }

## Alturas: la parte baja está a 0 y la alta, a LEVEL_HEIGHT metros (D-154). La ladera, el rellano y la cascada
## no tienen una altura fija (`NO_LEVEL`): van entre las dos.
const LEVEL_HEIGHT: float = 6.0
const LOW_LEVEL: int = 0
const HIGH_LEVEL: int = 1
const NO_LEVEL: int = -1
## Terraza a media altura (C5.4b, versión 3 del plano): la parte media y su explanada, a MID_HEIGHT metros.
const MID_LEVEL: int = 2
const MID_HEIGHT: float = 3.0
## Cumbre al noreste, con su explanada y el árbol singular (C5.4b, César: lo alto seguía muy abierto). Más adelante,
## la altura podrá influir en el viento y en los molinos.
const TOP_LEVEL: int = 3
const TOP_HEIGHT: float = 9.0
## Las lomas (`n`) son parte baja que sube hasta HILL_HEIGHT metros en su centro, a HILL_RAMP casillas del borde:
## tapan la vista entre las bolsas de la explanada baja (César: se veía todo de golpe).
const HILL_HEIGHT: float = 2.5
const HILL_RAMP: float = 3.0
## Lomas de lo alto (`m`, dibujo de César): dan forma a la parte alta, donde no hay explanada.
const HIGH_HILL_HEIGHT: float = 3.5
const HIGH_HILL_RAMP: float = 4.0
## Subida (casillas) de las lomas con corte de roca: tan corta que la cara sale empinada.
const HILL_CUT_RAMP: float = 1.2
## Hasta cuántas casillas del sendero las lomas van con corte de roca.
const PATH_CUT_REACH: float = 4.0
## Cabecera de la capa de tierra pisada al final del plano: debajo, filas del mismo tamaño; `x` = tierra pisada.
const WEAR_LAYER_HEADER: String = "[tierra pisada]"
## Capa de la barandilla (sesión 26, para C5.6b): `b` = casilla con un tramo. La pinta César en `paint_alba.png`.
const FENCE_LAYER_HEADER: String = "[barandilla]"
## Capa del césped (sesión 26): `g` = hierba aunque sea sendero, rellano o tierra pisada (César: junto a la barandilla
## del mirador). Solo cambia el color y el césped 3D, no las alturas ni dónde se construye.
const GRASS_LAYER_HEADER: String = "[césped]"
## Capa de la escala (sesión 26, para C5.6b): `e` = casilla de la escala reparable entre las dos alturas.
const LADDER_LAYER_HEADER: String = "[escala]"
const LAYER_HEADERS: PackedStringArray = [WEAR_LAYER_HEADER, FENCE_LAYER_HEADER, GRASS_LAYER_HEADER, LADDER_LAYER_HEADER]
## Hondura del fondo del agua de la isla bajo su nivel, y fondo del mar (C5.3d).
const WATER_DEPTH: float = 0.8
const SEA_BED: float = -1.6
## Lejos de la costa, el fondo del mar baja hacia la oscuridad (C5.4a, César: como en Sea of Thieves, fuera de las
## islas no hay nada debajo): metros que baja por casilla de distancia a la tierra y hasta dónde.
const SEA_DROP_PER_CELL: float = 0.7
const SEA_DEEPEST: float = -14.0
## Donde la tierra toca el agua, el suelo baja a esta altura bajo la superficie del agua, para que el agua llegue
## hasta la orilla (C5.3d: si no, la rueda quedaba sobre la hierba).
const SHORE_BELOW_WATER: float = 0.3   # ya no se usa (C5.4d): se deja por si se vuelve atrás
## La orilla (esquina entre agua y tierra) queda justo por encima del agua dibujada (C5.4d): así el canto de la lámina
## de agua siempre queda tapado y la forma de la orilla la da el fondo, que sí se deforma.
const SHORE_ABOVE_WATER: float = 0.06
## Lo que el cauce de la cascada queda por debajo del agua de arriba (m): justo debajo de la cortina, que va recta.
const FALL_CHANNEL_DEPTH: float = 0.04
## Suavidad de las puntas de las rampas: 0 = recta (cambia de golpe arriba y abajo); 1 = curva en S entera.
const RAMP_EASE: float = 0.6
## Pasadas que igualan la altura del sendero de lado a lado (César: en la curva iba inclinado).
const PATH_LEVEL_PASSES: int = 4
## Lo que baja el tope del fondo del agua por cada metro que se aleja de la orilla.
const BED_DROP_PER_M: float = 0.8
## Desnivel máximo (m) dentro de una casilla para poner un árbol, una roca o unos palos (C5.3d: había árboles
## en el borde del acantilado).
const MAX_SLOPE_FOR_NATURE: float = 1.0

const _GROUND_BY_CHAR: Dictionary[String, Ground] = {
	"~": Ground.SEA, ",": Ground.BEACH, ".": Ground.LOW, "=": Ground.LOW_FLAT, "^": Ground.HIGH,
	"#": Ground.HIGH_FLAT, "-": Ground.MID, "+": Ground.MID_FLAT, "n": Ground.HILL, "*": Ground.TOP, "%": Ground.TOP_FLAT, "r": Ground.RAMP, "m": Ground.HIGH_HILL, "/": Ground.SLOPE, ":": Ground.SLOPE, "_": Ground.LANDING, "O": Ground.WATER, "o": Ground.WATER,
	"v": Ground.WATER, "<": Ground.WATER, ">": Ground.WATER, "s": Ground.WATER, "C": Ground.FALL,
}
## Agua que corre y hacia dónde (un paso de la cuadrícula). El vado (`s`) es río con piedras encima.
const _FLOW_BY_CHAR: Dictionary[String, Vector2i] = {
	"v": Vector2i(0, 1), "<": Vector2i(-1, 0), ">": Vector2i(1, 0), "s": Vector2i(0, 1),
}
## Objetos del plano: no son suelo; su suelo se deduce de alrededor.
const FEATURE_CHARS: String = "RPMSTtXAGHQEK"
## Objetos que tapan la casilla para siempre (rocas modeladas, el árbol singular, los restos…): ahí no se
## construye, no se planta y no aparece nada.
const SOLID_FEATURES: String = "XAGHQEK"
## Casillas alrededor del refugio en las que el terreno no se deforma (ver `_near_shelter()`).
const SHELTER_CLEARANCE: int = 2
## Casillas alrededor de la escala reparable en las que no caen rocas al pie de la pared (C5.6b, sesión 27).
const LADDER_CLEAR: int = 2

## Tamaño del plano en casillas (el ancho es el de la fila más larga; las cortas se rellenan con mar).
var size: Vector2i = Vector2i.ZERO
var _ground: PackedByteArray = PackedByteArray()
var _chars: PackedStringArray = PackedStringArray()
## Altura del suelo de cada casilla (m), calculada al leer el plano.
var _heights: PackedFloat32Array = PackedFloat32Array()
## Alturas de las esquinas ((ancho + 1) × (alto + 1)) y casillas empinadas, calculadas una vez al leer el plano:
## preguntarlas a cada momento daba tirones (C5.3d).
var _corners: PackedFloat32Array = PackedFloat32Array()
var _steep: PackedByteArray = PackedByteArray()
## Relieve (C5.4b): lomas suaves fuera de las explanadas. En cada esquina, cuánto mueve el ruido (m) y cuánto se
## levanta siempre (el rellano, el montículo del árbol singular); entre esquinas, se interpola.
var _relief_scale: PackedFloat32Array = PackedFloat32Array()
var _relief_lift: PackedFloat32Array = PackedFloat32Array()
var _relief_noise: FastNoiseLite = null
## Esquinas que se dibujan (suavizadas) y ruido que deforma los bordes (C5.4b).
var _drawn: PackedFloat32Array = PackedFloat32Array()
var _warp_noise: FastNoiseLite = null
## Suelo mínimo junto al agua, por esquina (C5.4d): el agua de al lado más un poco; muy abajo donde no hay agua cerca.
var _shore_floor: PackedFloat32Array = PackedFloat32Array()
const NO_SHORE_FLOOR: float = -1000.0
## Hasta cuántas casillas del agua llega ese suelo mínimo y cuánto baja por casilla al alejarse (m).
const SHORE_FLOOR_REACH: int = 4
const SHORE_FLOOR_SLOPE: float = 0.6
## Casillas desde el agua en las que ese suelo mínimo no baja (sesión 28, César: junto al lago de arriba, hoyos del relieve
## a 2 o 3 casillas quedaban por debajo del agua y el terreno los pintaba como fondo, sin césped). Las mismas que mira el
## terreno para saber dónde está el agua (`TerrainView.WATER_SURFACE_SPREAD`); después, la rampa.
const SHORE_FLOOR_FLAT: int = 3
## Cuánto es pared cada esquina (0 a 1), por el desnivel con sus vecinas en lo que se dibuja.
var _cliffness: PackedFloat32Array = PackedFloat32Array()
## Pasadas de suavizado, cuánto se desplazan los bordes (m) y su tamaño (frecuencia por metro).
const SMOOTH_PASSES: int = 3
const WARP_AMOUNT: float = 1.3
## Altura mínima (m) de la tierra que está sobre el mar (el mar se dibuja a −0,25).
const LAND_ABOVE_SEA: float = 0.05
## Repisas de las paredes (C5.4c): alto de cada capa (m), parte plana de cada una (0 a 0,5), cuánto se nota (0 a 1),
## cuánto ondulan (m) y desde qué desnivel entre esquinas vecinas (m) una esquina cuenta como pared del todo.
const LEDGE_STEP: float = 1.1
const LEDGE_FLAT: float = 0.3
const LEDGE_AMOUNT: float = 0.7
const LEDGE_WOBBLE: float = 0.35
const CLIFF_DROP: float = 1.5
const WARP_FREQUENCY: float = 0.18
## Altura de las lomas (m) según el suelo: más en la montaña, menos abajo y casi nada en la playa.
const RELIEF_BY_GROUND: Dictionary[int, float] = {
	Ground.HIGH: 1.4, Ground.LOW: 0.7, Ground.SLOPE: 0.5, Ground.BEACH: 0.25, Ground.MID: 0.6,
	Ground.HILL: 0.5, Ground.TOP: 1.0, Ground.HIGH_HILL: 0.8,
}
## Casillas en las que el relieve crece desde cero junto a lo que debe quedar como está: explanadas, agua, mar y
## objetos del plano (vetas, refugio, portal, arboledas, peñascos…; los árboles salvajes no cuentan).
const RELIEF_FADE: float = 4.0
## Tamaño de las lomas (frecuencia del ruido, por metro).
const RELIEF_FREQUENCY: float = 0.045
## Montículo bajo el árbol singular (`G`), para que se vea aún mejor desde toda la isla (D-158).
const LANDMARK_MOUND: float = 1.0
const LANDMARK_MOUND_RADIUS: float = 5.0

## Tierra pisada de cada casilla (0 a 1): 1 en el sendero y, donde el sendero llega a la parte baja o a la alta, una
## mancha que se va apagando para que no empiece de golpe (C5.4a, César). La usa el terreno para pintar.
var _wear: PackedFloat32Array = PackedFloat32Array()
## Casillas con un tramo de barandilla (`FENCE_LAYER_HEADER`), en orden de lectura.
var fence_cells: Array[Vector2i] = []
## Casillas de la escala (`LADDER_LAYER_HEADER`), en orden de lectura.
var ladder_cells: Array[Vector2i] = []
## Casillas con césped pintado (`GRASS_LAYER_HEADER`): 1 = sin tierra pisada.
var _forced_grass: PackedByteArray = PackedByteArray()
## Casillas pintadas de tierra pisada en la capa del plano (`WEAR_LAYER_HEADER`).
var _worn: PackedByteArray = PackedByteArray()
## Desnivel de cada casilla en lo dibujado (m), para no pintar tierra pisada en lo inclinado.
var _drops: PackedFloat32Array = PackedFloat32Array()
## Desde qué desnivel (m por casilla) la tierra pisada se apaga, y del todo (César: subía por la loma).
const WEAR_FLAT_FROM: float = 0.25
const WEAR_FLAT_TO: float = 0.55
## Radio (casillas) de la mancha de tierra pisada en los extremos del sendero.
const WEAR_REACH: float = 6.0
## Radio de la mancha alrededor del portal y de la entrada del refugio, y ancho y fuerza del camino que los une.
const WEAR_SPOT_REACH: float = 5.0
const WEAR_TRAIL_WIDTH: float = 2.5
const WEAR_TRAIL_STRENGTH: float = 0.8
## Tierra pisada de las rampas.
const RAMP_WEAR: float = 0.85
## Casillas donde pueden aparecer rocas y palos (tierra, no empinada, no el rellano).
var spawn_cells: Array[Vector2i] = []
## Carácter de objeto → sus casillas, en orden de lectura (de arriba abajo y de izquierda a derecha).
var features: Dictionary[String, Array] = {}
## Casillas cerca del refugio (ver `_near_shelter()`), calculadas la primera vez que se preguntan.
var _shelter_zone: Dictionary[Vector2i, bool] = {}


## Lee un plano del disco. Null (con aviso) si no se puede abrir.
static func load_file(path: String) -> IslandLayout:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("IslandLayout: no se pudo abrir %s" % path)
		return null
	return from_text(file.get_as_text())


## Casillas de una capa marcadas con `mark`, en orden de lectura (lo que se sale del plano no cuenta).
static func _layer_cells(layer_rows: PackedStringArray, mark: String, plan_size: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y: int in mini(layer_rows.size(), plan_size.y):
		for x: int in mini(layer_rows[y].length(), plan_size.x):
			if layer_rows[y][x] == mark:
				cells.append(Vector2i(x, y))
	return cells


## ¿Tiene la casilla césped pintado (capa `GRASS_LAYER_HEADER`)? Ahí no hay tierra pisada.
func is_forced_grass(cell: Vector2i) -> bool:
	return has_cell(cell) and not _forced_grass.is_empty() and _forced_grass[cell.y * size.x + cell.x] == 1


## Lee un plano de un texto. Las líneas que empiezan por // son comentarios; un carácter desconocido se
## lee como mar, con aviso.
static func from_text(text: String) -> IslandLayout:
	var layout := IslandLayout.new()
	# Las filas de cada capa (`LAYER_HEADERS`) van aparte; "" es el plano.
	var layers: Dictionary[String, Array] = {"": []}
	var layer: String = ""
	for line: String in text.split("\n"):
		line = line.trim_suffix("\r")
		if line.begins_with("//") or line.strip_edges() == "":
			continue
		if LAYER_HEADERS.has(line.strip_edges()):
			layer = line.strip_edges()
			if not layers.has(layer):
				layers[layer] = []
			continue
		layers[layer].append(line)
	var rows := PackedStringArray(layers[""])
	var worn_rows := PackedStringArray(layers.get(WEAR_LAYER_HEADER, []))
	var width: int = 0
	for row: String in rows:
		width = maxi(width, row.length())
	layout.size = Vector2i(width, rows.size())
	layout._ground.resize(width * rows.size())
	layout._chars.resize(width * rows.size())
	var unknown: Dictionary[String, bool] = {}
	for y: int in rows.size():
		for x: int in width:
			var ch: String = rows[y][x] if x < rows[y].length() else "~"
			if not _GROUND_BY_CHAR.has(ch) and not FEATURE_CHARS.contains(ch):
				unknown[ch] = true
				ch = "~"
			layout._chars[y * width + x] = ch
			if FEATURE_CHARS.contains(ch):
				if not layout.features.has(ch):
					layout.features[ch] = []
				layout.features[ch].append(Vector2i(x, y))
	if not unknown.is_empty():
		push_warning("IslandLayout: caracteres desconocidos leídos como mar: %s" % ", ".join(unknown.keys()))
	# El suelo de cada casilla; el de los objetos, al final, con el de sus vecinas.
	for i: int in layout._chars.size():
		layout._ground[i] = _GROUND_BY_CHAR.get(layout._chars[i], Ground.SEA)
	for ch: String in layout.features:
		for cell: Vector2i in layout.features[ch]:
			# El refugio (C5.5) es un hormiguero que se levanta sobre su zona: el suelo, llano y abajo. Sin esto, el
			# terreno rellenaba la zona con lo de alrededor y salía una aguja suelta junto al acantilado.
			layout._ground[cell.y * width + cell.x] = Ground.LOW_FLAT if ch == "R" else layout._infer_ground(cell)
	layout._worn.resize(width * rows.size())
	for y: int in mini(worn_rows.size(), rows.size()):
		for x: int in mini(worn_rows[y].length(), width):
			if worn_rows[y][x] == "x":
				layout._worn[y * width + x] = 1
	layout.fence_cells = _layer_cells(PackedStringArray(layers.get(FENCE_LAYER_HEADER, [])), "b", layout.size)
	layout.ladder_cells = _layer_cells(PackedStringArray(layers.get(LADDER_LAYER_HEADER, [])), "e", layout.size)
	layout._forced_grass.resize(width * rows.size())
	for cell: Vector2i in _layer_cells(PackedStringArray(layers.get(GRASS_LAYER_HEADER, [])), "g", layout.size):
		layout._forced_grass[cell.y * width + cell.x] = 1
	layout._compute_heights()
	layout._compute_corners()
	return layout


func has_cell(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < size.x and cell.y < size.y


## Carácter del plano en esa casilla ("~" fuera del plano).
func char_at(cell: Vector2i) -> String:
	return _chars[cell.y * size.x + cell.x] if has_cell(cell) else "~"


func ground(cell: Vector2i) -> Ground:
	return _ground[cell.y * size.x + cell.x] as Ground if has_cell(cell) else Ground.SEA


## Altura de la casilla: `LOW_LEVEL`, `HIGH_LEVEL` o `NO_LEVEL` (ladera, rellano, cascada, mar).
func level(cell: Vector2i) -> int:
	match ground(cell):
		Ground.BEACH, Ground.LOW, Ground.LOW_FLAT, Ground.HILL:
			return LOW_LEVEL
		Ground.HIGH, Ground.HIGH_FLAT, Ground.HIGH_HILL:
			return HIGH_LEVEL
		Ground.MID, Ground.MID_FLAT, Ground.LANDING:
			return MID_LEVEL   # el rellano del mirador, también a media altura (C5.4b, César)
		Ground.TOP, Ground.TOP_FLAT:
			return TOP_LEVEL
		Ground.WATER:
			return HIGH_LEVEL if char_at(cell) == "O" else LOW_LEVEL
	return NO_LEVEL


## Metros a los que está una altura (`LOW_LEVEL`, `MID_LEVEL` o `HIGH_LEVEL`).
static func level_height(p_level: int) -> float:
	match p_level:
		HIGH_LEVEL:
			return LEVEL_HEIGHT
		MID_LEVEL:
			return MID_HEIGHT
		TOP_LEVEL:
			return TOP_HEIGHT
	return 0.0


## Altura del suelo de la casilla (m): 0 abajo, `LEVEL_HEIGHT` arriba; la ladera, el rellano y la cascada,
## entre las dos según lo cerca que estén de cada una; bajo el agua y el mar, su fondo. La usan el terreno y
## todo lo que se pone encima (árboles, rocas, construcciones).
func height(cell: Vector2i) -> float:
	return _heights[cell.y * size.x + cell.x] if has_cell(cell) else SEA_BED


## Altura del terreno en la esquina (i, j) de la rejilla de casillas (la de arriba a la izquierda de la casilla
## (i, j)). Si alguna de sus cuatro casillas es de explanada, la de la explanada, para que su borde siga plano;
## si no, la media de las cuatro. Es la regla con la que se dibuja el terreno.
func corner_height(i: int, j: int) -> float:
	if i < 0 or j < 0 or i > size.x or j > size.y:
		return SEA_BED
	return _corners[j * (size.x + 1) + i]


## ¿Toca agua esta esquina? (el terreno la pinta de arena: es la orilla)
func corner_touches_water(i: int, j: int) -> bool:
	for cell: Vector2i in [Vector2i(i - 1, j - 1), Vector2i(i, j - 1), Vector2i(i - 1, j), Vector2i(i, j)]:
		if ground(cell) == Ground.WATER:
			return true
	return false


func _corner_from_cells(i: int, j: int) -> float:
	var cells: Array[Vector2i] = [Vector2i(i - 1, j - 1), Vector2i(i, j - 1), Vector2i(i - 1, j), Vector2i(i, j)]
	# Primero, las explanadas: planas hasta el borde, también junto al agua (si no, la rueda quedaba sobre un
	# escalón, C5.3d).
	for cell: Vector2i in cells:
		if is_buildable(cell):
			return height(cell)
	# Rampa (C5.4b): sus esquinas, solo con sus casillas, para que suba recta sin hundirse junto a las lomas de al lado
	# (César: parecía empinada y había que saltar).
	var ramp_sum: float = 0.0
	var ramp_count: int = 0
	for cell: Vector2i in cells:
		if ground(cell) == Ground.RAMP:
			ramp_sum += height(cell)
			ramp_count += 1
	if ramp_count > 0:
		return ramp_sum / ramp_count
	# Cauce de la cascada: plano hasta el borde, también junto al lago y en el filo de la caída (con la regla de la
	# orilla, una esquina quedaba a la altura del agua: escalón al empezar y pliegue en el filo, César).
	var fall_sum: float = 0.0
	var fall_count: int = 0
	for cell: Vector2i in cells:
		if ground(cell) == Ground.FALL:
			fall_sum += height(cell)
			fall_count += 1
	if fall_count > 0:
		return fall_sum / fall_count
	# Orilla de la tierra donde no se construye: si la esquina toca agua y tierra, queda justo por encima del agua
	# (la más baja, si hay dos).
	var water_surface: float = INF
	var touches_land: bool = false
	for cell: Vector2i in cells:
		if ground(cell) == Ground.WATER:
			water_surface = minf(water_surface, level_height(level(cell)))
		elif is_land(cell):
			touches_land = true
	if touches_land and water_surface != INF:
		return water_surface + SHORE_ABOVE_WATER
	var sum: float = 0.0
	for cell: Vector2i in cells:
		sum += height(cell)
	return sum * 0.25


## Altura del terreno dibujado en el centro de una casilla: la de la explanada si lo es (plana) y, si no, la del
## terreno con sus lomas. Es donde se apoyan los árboles, las rocas y todo lo que va sobre el terreno.
func surface_height(cell: Vector2i) -> float:
	if is_buildable(cell):
		return height(cell)
	return terrain_height(cell.x + 0.5, cell.y + 0.5)


## Altura del terreno dibujado en un punto cualquiera (en metros del mundo, x y z): las esquinas interpoladas más
## las lomas. El terreno se dibuja con esto cada medio metro.
func terrain_height(x: float, z: float) -> float:
	if _point_fixed(x, z):
		return _keep_above_water(x, z, _keep_above_sea(_bilinear_corners(_drawn, x, z), relief(x, z)))
	# Fuera de las explanadas y del agua, la forma se lee un poco desplazada con un ruido: así los bordes de los
	# acantilados y las lomas no siguen la cuadrícula (César: «demasiado geométricas o cuadradas»).
	var wx: float = x + _warp_noise.get_noise_2d(x, z) * WARP_AMOUNT
	var wz: float = z + _warp_noise.get_noise_2d(x + 71.3, z - 37.9) * WARP_AMOUNT
	var base: float = _bilinear_corners(_drawn, clampf(wx, 0.0, size.x), clampf(wz, 0.0, size.y))
	# Paredes (C5.4c): la altura se escalona en repisas, para que los estratos tengan saliente y cara empinada.
	var cliff: float = _bilinear_corners(_cliffness, x, z)
	if cliff > 0.0:
		var t: float = (base + _warp_noise.get_noise_2d(x * 0.5 - 13.0, z * 0.5 + 29.0) * LEDGE_WOBBLE) / LEDGE_STEP
		var f: float = t - floorf(t)
		var stepped: float = (floorf(t) + smoothstep(LEDGE_FLAT, 1.0 - LEDGE_FLAT, f)) * LEDGE_STEP \
				- _warp_noise.get_noise_2d(x * 0.5 - 13.0, z * 0.5 + 29.0) * LEDGE_WOBBLE
		base = lerpf(base, stepped, cliff * LEDGE_AMOUNT)
	return _keep_above_water(x, z, _keep_above_sea(base, relief(x, z)))


## Lo que es pared en un punto (0 a 1), leído también con el desplazamiento que deforma la forma del terreno, para que
## coincida con las paredes dibujadas (C5.6). El terreno solo pinta roca en las paredes de verdad (en las lomas salían
## manchas de roca pequeñas y sin estratos, captura de César) y el césped no crece en ellas.
## Se lee de `_wall_zone`: lo que es pared ensanchado una esquina a cada lado, porque las esquinas de las explanadas no
## cuentan como pared (son fijas) y el pie y lo alto de cada pared salían de hierba (captura de César).
func wall_amount(x: float, z: float) -> float:
	if _wall_zone.is_empty():
		_compute_wall_zone()
	var here: float = _bilinear_corners(_wall_zone, x, z)
	if _point_fixed(x, z):
		return here
	var wx: float = x + _warp_noise.get_noise_2d(x, z) * WARP_AMOUNT
	var wz: float = z + _warp_noise.get_noise_2d(x + 71.3, z - 37.9) * WARP_AMOUNT
	return maxf(here, _bilinear_corners(_wall_zone, clampf(wx, 0.0, size.x), clampf(wz, 0.0, size.y)))


var _wall_zone: PackedFloat32Array = PackedFloat32Array()


func _compute_wall_zone() -> void:
	var row: int = size.x + 1
	var rows: int = size.y + 1
	_wall_zone.resize(row * rows)
	for j: int in rows:
		for i: int in row:
			var most: float = 0.0
			for dj: int in range(-1, 2):
				for di: int in range(-1, 2):
					most = maxf(most, _cliffness[clampi(j + dj, 0, rows - 1) * row + clampi(i + di, 0, row - 1)])
			_wall_zone[j * row + i] = most


## Junto a un río o un lago, la tierra (lo que no es casilla de agua) nunca queda por debajo del agua: si no, al
## deformarse la orilla salían hoyos secos o el agua se veía cortada (C5.4d).
func _keep_above_water(x: float, z: float, y: float) -> float:
	var cell := Vector2i(floori(x), floori(z))
	var g: Ground = ground(cell)
	# El cauce de la cascada y las rampas van a su altura (el suelo mínimo levantaba el principio del cauce por encima
	# de la cortina, César).
	if g == Ground.FALL or g == Ground.RAMP or _on_buildable_edge(x, z):
		return y
	if g == Ground.WATER:
		# El fondo no sube por encima de la orilla y, hacia dentro, baja: si no, al deformarse tomaba altura de una pared
		# de al lado y salía un montículo dentro del río (al pie de la cascada, César).
		var cap: float = level_height(level(cell)) + SHORE_ABOVE_WATER - _distance_to_land(x, z, cell) * BED_DROP_PER_M
		return minf(y, cap)
	return maxf(y, _bilinear_corners(_shore_floor, clampf(x, 0.0, size.x), clampf(z, 0.0, size.y)))


## Las lomas no bajan la tierra por debajo del mar: si no, el agua del mar se veía a través del suelo como un charco
## suelto (César: «un pequeño lago»). Lo que ya está bajo el mar (la orilla, el fondo) sigue como está.
func _keep_above_sea(base: float, relief_offset: float) -> float:
	var y: float = base + relief_offset
	if base >= LAND_ABOVE_SEA:
		return maxf(y, LAND_ABOVE_SEA)
	return maxf(y, base)


## Punto más bajo del terreno dibujado alrededor de (x, z), a `radius` metros: ahí se apoya algo con base ancha (el
## tronco de un árbol) en una cuesta, para que no asome por el lado de abajo (captura de César).
func lowest_around(x: float, z: float, radius: float) -> float:
	var lowest: float = terrain_height(x, z)
	for angle: float in [0.0, TAU * 0.25, TAU * 0.5, TAU * 0.75, TAU * 0.125, TAU * 0.375, TAU * 0.625, TAU * 0.875]:
		lowest = minf(lowest, terrain_height(x + cos(angle) * radius, z + sin(angle) * radius))
	return lowest


## ¿Toca este punto una explanada o el agua? (ahí el terreno no se deforma: tiene que quedar plano y a su altura)
func _point_fixed(x: float, z: float) -> bool:
	var xs: Array[int] = [floori(x)]
	var zs: Array[int] = [floori(z)]
	if is_equal_approx(x, roundf(x)):
		xs = [roundi(x) - 1, roundi(x)]
	if is_equal_approx(z, roundf(z)):
		zs = [roundi(z) - 1, roundi(z)]
	for cx: int in xs:
		for cz: int in zs:
			var cell := Vector2i(cx, cz)
			if is_buildable(cell) or ground(cell) == Ground.RAMP or ground(cell) == Ground.FALL or is_path(cell):
				return true   # el sendero, sin deformar: sube liso (César: un escalón al empezar la subida)
			if _near_shelter(cell):
				return true   # la pared detrás del refugio, recta: el hormiguero se apoya en ella sin grietas (C5.5)
	# En el agua, solo la línea de la orilla (el borde de la lámina tiene que quedar tapado); el fondo de dentro sí se
	# deforma, y así la orilla sale irregular (César: bordes rectos en el lago).
	var touches_water: bool = false
	var touches_land: bool = false
	for cx: int in xs:
		for cz: int in zs:
			if ground(Vector2i(cx, cz)) == Ground.WATER:
				touches_water = true
			else:
				touches_land = true
	return touches_water and touches_land


## Lo que las lomas suben o bajan el terreno en ese punto (0 en las explanadas, el agua y junto a ellas).
func relief(x: float, z: float) -> float:
	var scale: float = _bilinear_corners(_relief_scale, x, z)
	var lift: float = _bilinear_corners(_relief_lift, x, z)
	if scale == 0.0:
		return lift
	return lift + scale * _relief_noise.get_noise_2d(x, z)


## ¿Está a SHELTER_CLEARANCE casillas o menos del refugio (`R`)? Ahí el terreno no se deforma ni se suaviza: la pared
## del acantilado queda recta, de 6 m a 0 en una casilla, y el modelo del hormiguero encaja en ella (C5.5).
func _near_shelter(cell: Vector2i) -> bool:
	if _shelter_zone.is_empty():   # se calcula una vez: el terreno pregunta por cada punto
		_shelter_zone[Vector2i(-9999, -9999)] = true   # marca de «ya calculado», aunque no haya refugio
		for r: Vector2i in features.get("R", []):
			for dz: int in range(-SHELTER_CLEARANCE, SHELTER_CLEARANCE + 1):
				for dx: int in range(-SHELTER_CLEARANCE, SHELTER_CLEARANCE + 1):
					_shelter_zone[r + Vector2i(dx, dz)] = true
	return _shelter_zone.has(cell)


## Esquinas que se dibujan: las de siempre, suavizadas unas pasadas fuera de las explanadas, el agua y su orilla (así los
## acantilados y las lomas se redondean), con el relieve de las lomas suavizado igual.
func _compute_drawn_corners() -> void:
	var row: int = size.x + 1
	var fixed := PackedByteArray()
	fixed.resize(row * (size.y + 1))
	for j: int in size.y + 1:
		for i: int in size.x + 1:
			var water_cells: int = 0
			for cell: Vector2i in [Vector2i(i - 1, j - 1), Vector2i(i, j - 1), Vector2i(i - 1, j), Vector2i(i, j)]:
				if is_buildable(cell) or ground(cell) == Ground.RAMP or ground(cell) == Ground.FALL or _near_shelter(cell):
					fixed[j * row + i] = 1
				if ground(cell) == Ground.WATER:
					water_cells += 1
			# La orilla (agua y tierra) se queda; el fondo de dentro se suaviza (César: el lago se veía a cuadros).
			if water_cells > 0 and water_cells < 4:
				fixed[j * row + i] = 1
	_drawn = _smooth_corners(_corners, fixed, SMOOTH_PASSES)
	# Las lomas no se suavizan sobre el sendero: si no, la loma de al lado lo levantaba y el camino subía por ella.
	var fixed_relief: PackedByteArray = fixed.duplicate()
	for j: int in size.y + 1:
		for i: int in size.x + 1:
			for cell: Vector2i in [Vector2i(i - 1, j - 1), Vector2i(i, j - 1), Vector2i(i - 1, j), Vector2i(i, j)]:
				if is_path(cell):
					fixed_relief[j * row + i] = 1
	_relief_lift = _smooth_corners(_relief_lift, fixed_relief, SMOOTH_PASSES)
	_relief_scale = _smooth_corners(_relief_scale, fixed_relief, SMOOTH_PASSES)
	_warp_noise = FastNoiseLite.new()
	_warp_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_warp_noise.seed = 2
	_warp_noise.frequency = WARP_FREQUENCY
	# Suelo mínimo junto al agua: cerca de cada casilla de agua, las esquinas de tierra a la altura del agua (no las de
	# más abajo de un salto, como el pie de la cascada) quedan, como poco, justo por encima de ella.
	_shore_floor.resize(row * (size.y + 1))
	_shore_floor.fill(NO_SHORE_FLOOR)
	for y: int in size.y:
		for x: int in size.x:
			if ground(Vector2i(x, y)) != Ground.WATER:
				continue
			var water_level: float = level_height(level(Vector2i(x, y)))
			for j: int in range(maxi(y - SHORE_FLOOR_REACH, 0), mini(y + SHORE_FLOOR_REACH + 1, size.y) + 1):
				for i: int in range(maxi(x - SHORE_FLOOR_REACH, 0), mini(x + SHORE_FLOOR_REACH + 1, size.x) + 1):
					var index: int = j * row + i
					# Ni las explanadas (planas a su altura hasta el agua, por la rueda) ni lo de debajo de un salto, ni el
					# mar (sesión 23: en la desembocadura levantaba una barra de arena entre el río y el mar, César).
					if _touches_buildable(i, j) or _touches_sea(i, j) \
							or _drawn[index] < water_level - 1.0 - SHORE_FLOOR_REACH * SHORE_FLOOR_SLOPE:
						continue
					# Junto al agua, justo por encima; al alejarse, baja en rampa (si acababa de golpe, levantaba un
					# rellano con un escalón recto alrededor del lago, César).
					var away: int = maxi(maxi(x - i, i - (x + 1)), maxi(maxi(y - j, j - (y + 1)), 0))
					var floor_y: float = water_level + SHORE_ABOVE_WATER - SHORE_FLOOR_SLOPE * maxi(away - SHORE_FLOOR_FLAT, 0)
					_shore_floor[index] = maxf(_shore_floor[index], floor_y)
	# Lo que es pared: el mayor desnivel con las cuatro vecinas (sin tocar las esquinas fijas), suavizado.
	_cliffness.resize(row * (size.y + 1))
	_cliffness.fill(0.0)
	for j: int in range(1, size.y):
		for i: int in range(1, size.x):
			var index: int = j * row + i
			if fixed[index] == 1:
				continue
			var here: float = _drawn[index]
			var drop: float = maxf(maxf(absf(_drawn[index - 1] - here), absf(_drawn[index + 1] - here)),
					maxf(absf(_drawn[index - row] - here), absf(_drawn[index + row] - here)))
			_cliffness[index] = smoothstep(CLIFF_DROP * 0.5, CLIFF_DROP, drop)
	_cliffness = _smooth_corners(_cliffness, fixed, 1)


## ¿Toca la esquina (i, j) alguna casilla de mar?
func _touches_sea(i: int, j: int) -> bool:
	for cell: Vector2i in [Vector2i(i - 1, j - 1), Vector2i(i, j - 1), Vector2i(i - 1, j), Vector2i(i, j)]:
		if ground(cell) == Ground.SEA:
			return true
	return false


## Distancia (en casillas, con diagonales de 1,41) de cada casilla a la más cercana que valga 0, en dos pasadas.
func _chamfer_distance(values: PackedFloat32Array) -> void:
	var w: int = size.x
	var h: int = size.y
	const D: float = 1.41421
	for y: int in h:
		for x: int in w:
			var index: int = y * w + x
			var best: float = values[index]
			if x > 0:
				best = minf(best, values[index - 1] + 1.0)
			if y > 0:
				best = minf(best, values[index - w] + 1.0)
				if x > 0:
					best = minf(best, values[index - w - 1] + D)
				if x < w - 1:
					best = minf(best, values[index - w + 1] + D)
			values[index] = best
	for y: int in range(h - 1, -1, -1):
		for x: int in range(w - 1, -1, -1):
			var index: int = y * w + x
			var best: float = values[index]
			if x < w - 1:
				best = minf(best, values[index + 1] + 1.0)
			if y < h - 1:
				best = minf(best, values[index + w] + 1.0)
				if x < w - 1:
					best = minf(best, values[index + w + 1] + D)
				if x > 0:
					best = minf(best, values[index + w - 1] + D)
			values[index] = best


## ¿Está el punto en el borde (o dentro) de una casilla donde se construye? Ahí no se toca nada.
func _on_buildable_edge(x: float, z: float) -> bool:
	var xs: Array[int] = [floori(x)]
	var zs: Array[int] = [floori(z)]
	if is_equal_approx(x, roundf(x)):
		xs = [roundi(x) - 1, roundi(x)]
	if is_equal_approx(z, roundf(z)):
		zs = [roundi(z) - 1, roundi(z)]
	for cx: int in xs:
		for cz: int in zs:
			if is_buildable(Vector2i(cx, cz)):
				return true
	return false


## Distancia (m, hasta 1) de un punto de una casilla de agua a la tierra de al lado más cercana.
func _distance_to_land(x: float, z: float, cell: Vector2i) -> float:
	var best: float = 1.0
	for dy: int in range(-1, 2):
		for dx: int in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var other := Vector2i(cell.x + dx, cell.y + dy)
			if ground(other) == Ground.WATER:
				continue
			var nearest := Vector2(clampf(x, other.x, other.x + 1.0), clampf(z, other.y, other.y + 1.0))
			best = minf(best, nearest.distance_to(Vector2(x, z)))
	return best


## ¿Toca esta esquina alguna casilla donde se construye?
func _touches_buildable(i: int, j: int) -> bool:
	for cell: Vector2i in [Vector2i(i - 1, j - 1), Vector2i(i, j - 1), Vector2i(i - 1, j), Vector2i(i, j)]:
		if is_buildable(cell):
			return true
	return false


## Media con las cuatro vecinas, `passes` veces, sin mover las esquinas marcadas en `fixed`.
func _smooth_corners(values: PackedFloat32Array, fixed: PackedByteArray, passes: int) -> PackedFloat32Array:
	var row: int = size.x + 1
	var rows: int = size.y + 1
	var current: PackedFloat32Array = values.duplicate()
	for _pass: int in passes:
		var next: PackedFloat32Array = current.duplicate()
		for j: int in range(1, rows - 1):
			for i: int in range(1, row - 1):
				var index: int = j * row + i
				if fixed[index] == 1:
					continue
				next[index] = (current[index] * 2.0 + current[index - 1] + current[index + 1] + current[index - row]
						+ current[index + row]) / 6.0
		current = next
	return current


## Valor de una rejilla de esquinas ((ancho + 1) × (alto + 1)) en un punto, interpolando entre las cuatro más cercanas.
func _bilinear_corners(values: PackedFloat32Array, x: float, z: float) -> float:
	var i: int = clampi(floori(x), 0, size.x - 1)
	var j: int = clampi(floori(z), 0, size.y - 1)
	var fx: float = clampf(x - i, 0.0, 1.0)
	var fz: float = clampf(z - j, 0.0, 1.0)
	var row: int = size.x + 1
	var a: float = values[j * row + i]
	var b: float = values[j * row + i + 1]
	var c: float = values[(j + 1) * row + i]
	var d: float = values[(j + 1) * row + i + 1]
	return lerpf(lerpf(a, b, fx), lerpf(c, d, fx), fz)


## Desnivel del terreno dibujado dentro de la casilla (m): la diferencia entre su punto más alto y el más bajo
## (esquinas y centro).
func slope_drop(cell: Vector2i) -> float:
	var low: float = INF
	var high: float = -INF
	for f: Vector2 in [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1), Vector2(0.5, 0.5)]:
		var y: float = terrain_height(cell.x + f.x, cell.y + f.y)
		low = minf(low, y)
		high = maxf(high, y)
	return high - low


## ¿Demasiado empinada para un árbol, una roca o unos palos? (el borde del acantilado, por ejemplo)
func is_steep(cell: Vector2i) -> bool:
	return has_cell(cell) and _steep[cell.y * size.x + cell.x] == 1


## ¿Se puede construir aquí? Solo en las explanadas (D-154), y no bajo un objeto que la tape.
func is_buildable(cell: Vector2i) -> bool:
	var g: Ground = ground(cell)
	return (g == Ground.LOW_FLAT or g == Ground.MID_FLAT or g == Ground.HIGH_FLAT or g == Ground.TOP_FLAT \
			or g == Ground.LANDING) \
			and not SOLID_FEATURES.contains(char_at(cell))


## ¿Se puede construir aquí? En las explanadas (`is_buildable`) y, desde la sesión 31 (César), también en el suelo
## natural casi plano (`_natural_build`): la orilla este del río, el sur del mirador, la playa del oeste, rellanos de la
## montaña… El terreno no cambia: solo dónde se deja construir. Lo inclinado, con suelos que nivelan (más adelante).
func can_build(cell: Vector2i) -> bool:
	return is_buildable(cell) or is_natural_build(cell)


## ¿Es suelo natural (no explanada) en el que se puede construir?
func is_natural_build(cell: Vector2i) -> bool:
	return has_cell(cell) and not _natural_build.is_empty() and _natural_build[cell.y * size.x + cell.x] == 1


## Altura (m) a la que va una construcción en esta casilla: en una explanada, la suya; en suelo natural, la de su nivel
## (0, 3, 6 o 9 m), la misma que la explanada de ese nivel, así todo lo de una altura se une (César, sesión 31). El
## suelo natural queda como mucho NATURAL_BUILD_ABOVE metros por encima (la construcción, algo hundida) y nunca más de
## NATURAL_BUILD_BELOW por debajo (no flota).
func build_height(cell: Vector2i) -> float:
	if is_natural_build(cell):
		return level_height(level(cell))
	return height(cell)


## Suelo natural casi plano en el que se construye (1 = sí), calculado una vez al leer el plano.
var _natural_build: PackedByteArray = PackedByteArray()
## Desnivel máximo (m) dentro de una casilla de suelo natural para construir en ella.
const NATURAL_BUILD_DROP: float = 0.15
## Con este desnivel o menos, una casilla también vale si al menos 3 de sus 4 vecinas valen (rellena huecos sueltos).
const NATURAL_BUILD_FILL_DROP: float = 0.25
## Cuánto puede estar el suelo natural por encima y por debajo de la altura de su nivel (m).
const NATURAL_BUILD_ABOVE: float = 0.12
const NATURAL_BUILD_BELOW: float = 0.08
## Las manchas más pequeñas que esto (casillas) no cuentan: no sirven para construir y quedan como motas.
const NATURAL_BUILD_MIN_AREA: int = 12


## ¿Podría ser suelo natural construible esta casilla, sin mirar lo inclinada que está?
func _natural_build_base(cell: Vector2i) -> bool:
	if not is_land(cell) or is_buildable(cell) or is_steep(cell) or _debris_cells.has(cell):
		return false
	var ch: String = char_at(cell)
	if FEATURE_CHARS.contains(ch) and ch != "t":   # un árbol salvaje no: al talarlo, se construye
		return false
	var g: Ground = ground(cell)
	if g == Ground.RAMP or g == Ground.LANDING or g == Ground.FALL or is_path(cell):
		return false
	if _near_shelter(cell) or fence_cells.has(cell) or ladder_cells.has(cell) or _near_ladder(cell):
		return false
	var lv: int = level(cell)
	if lv == NO_LEVEL:
		return false
	# Lo más alto de la casilla manda (sesión 31, César: en los bordes algo inclinados las cintas se hundían, porque
	# el centro estaba bien pero un lado subía) y lo más bajo, para que nada flote.
	var low: float = INF
	var high: float = -INF
	for f: Vector2 in [Vector2(0, 0), Vector2(0.5, 0), Vector2(1, 0), Vector2(0, 0.5), Vector2(0.5, 0.5), Vector2(1, 0.5),
			Vector2(0, 1), Vector2(0.5, 1), Vector2(1, 1)]:
		var y: float = terrain_height(cell.x + f.x, cell.y + f.y)
		low = minf(low, y)
		high = maxf(high, y)
	var base: float = level_height(lv)
	return high - base <= NATURAL_BUILD_ABOVE and low - base >= -NATURAL_BUILD_BELOW


func _compute_natural_build() -> void:
	_natural_build = PackedByteArray()
	_natural_build.resize(size.x * size.y)
	var maybe := PackedByteArray()   # vale para rellenar huecos
	maybe.resize(size.x * size.y)
	for y: int in size.y:
		for x: int in size.x:
			var cell := Vector2i(x, y)
			if not _natural_build_base(cell):
				continue
			var drop: float = _drops[y * size.x + x]
			if drop < NATURAL_BUILD_DROP:
				_natural_build[y * size.x + x] = 1
			elif drop < NATURAL_BUILD_FILL_DROP:
				maybe[y * size.x + x] = 1
	# Huecos sueltos: casillas algo más inclinadas rodeadas de construible (3 de sus 4 vecinas).
	var sides: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]
	for _pass: int in 3:
		var fill: Array[int] = []
		for y: int in range(1, size.y - 1):
			for x: int in range(1, size.x - 1):
				if maybe[y * size.x + x] == 0:
					continue
				var around: int = 0
				for step: Vector2i in sides:
					if can_build(Vector2i(x, y) + step):
						around += 1
				if around >= 3:
					fill.append(y * size.x + x)
		for index: int in fill:
			_natural_build[index] = 1
			maybe[index] = 0
	# Manchas pequeñas fuera.
	var seen := PackedByteArray()
	seen.resize(size.x * size.y)
	for y: int in size.y:
		for x: int in size.x:
			if _natural_build[y * size.x + x] == 0 or seen[y * size.x + x] == 1:
				continue
			var patch: Array[Vector2i] = [Vector2i(x, y)]
			seen[y * size.x + x] = 1
			var k: int = 0
			while k < patch.size():
				var cell: Vector2i = patch[k]
				k += 1
				for step: Vector2i in sides:
					var other: Vector2i = cell + step
					if has_cell(other) and _natural_build[other.y * size.x + other.x] == 1 \
							and seen[other.y * size.x + other.x] == 0:
						seen[other.y * size.x + other.x] = 1
						patch.append(other)
			if patch.size() < NATURAL_BUILD_MIN_AREA:
				for cell: Vector2i in patch:
					_natural_build[cell.y * size.x + cell.x] = 0


## ¿Es tierra (se anda y se puede plantar)? Ni mar, ni agua, ni cascada, ni un objeto que la tape.
func is_land(cell: Vector2i) -> bool:
	var g: Ground = ground(cell)
	return g != Ground.SEA and g != Ground.WATER and g != Ground.FALL and not SOLID_FEATURES.contains(char_at(cell))


## ¿Pueden aparecer rocas o palos aquí? En tierra que no sea empinada, salvo en el rellano (es el mirador: se
## deja despejado), en el sendero y en el refugio (ni en su sala ni en su porche).
func can_spawn(cell: Vector2i) -> bool:
	return is_land(cell) and char_at(cell) != "R" and ground(cell) != Ground.LANDING and ground(cell) != Ground.RAMP and not is_path(cell) \
			and not is_steep(cell) and not _debris_cells.has(cell)


## Rocas caídas al pie de las paredes (C5.4c): decorado. Cada una: posición (m), tamaño, giro y variante (0 a 2).
var debris: Array[Dictionary] = []
var _debris_cells: Dictionary[Vector2i, bool] = {}
## Pie de las paredes altas: casillas llanas junto a una pared de más de WALL_FOOT_DROP metros.
var _wall_foot: Dictionary[Vector2i, bool] = {}
const WALL_FOOT_DROP: float = 1.6
## Cuánto más alta tiene que estar la casilla de la pared que la del pie (m).
const WALL_FOOT_RISE: float = 0.8
## Parte de los pies de pared que lleva una roca caída (nunca en una explanada: ahí se construye), su tamaño y la
## parte que lleva otra pequeña al lado.
const DEBRIS_CHANCE: float = 0.5
const DEBRIS_PAIR_CHANCE: float = 0.45
const DEBRIS_SCALE_MIN: float = 1.4
const DEBRIS_SCALE_MAX: float = 2.8
## Tierra al pie de las paredes (lo que se desprende): cuánta, de 0 a 1.
const WALL_FOOT_WEAR: float = 0.5
## Sin esa tierra a menos de estas casillas del agua de la isla (sesión 28, César: junto al lago de arriba salía una
## mancha de tierra en escalones al pie de las lomas con corte; alrededor del agua, césped).
const WALL_FOOT_WATER_CLEAR: int = 6
## Borde de hierba que asoma por lo alto de una pared: hasta cuántos metros por debajo del borde baja.
const LIP_DEPTH: float = 0.45


## Cuánto asoma la hierba de arriba en este punto de una pared (0 a 1): solo cerca del borde de arriba, donde
## lo de encima ya no es pared (si no, cada repisa de los estratos llevaría su franja de hierba).
func wall_lip(x: float, z: float) -> float:
	var cliff: float = _bilinear_corners(_cliffness, x, z)
	if cliff < 0.2:
		return 0.0
	var here: float = terrain_height(x, z)
	var best: float = -INF
	var best_cliff: float = 1.0
	for k: int in 8:
		var angle: float = TAU * k / 8.0
		var sx: float = x + cos(angle) * 0.9
		var sz: float = z + sin(angle) * 0.9
		var h: float = terrain_height(sx, sz)
		if h > best:
			best = h
			best_cliff = _bilinear_corners(_cliffness, clampf(sx, 0.0, size.x), clampf(sz, 0.0, size.y))
	if best_cliff > 0.35 or best - here > LIP_DEPTH:
		return 0.0
	return (1.0 - (best - here) / LIP_DEPTH) * cliff


## Pies de las paredes altas y, en parte de ellos, una roca caída medio enterrada. Siempre igual (por la casilla).
func _compute_wall_feet(drops: PackedFloat32Array) -> void:
	debris.clear()
	_debris_cells.clear()
	_wall_foot.clear()
	for y: int in range(1, size.y - 1):
		for x: int in range(1, size.x - 1):
			var cell := Vector2i(x, y)
			if not is_land(cell) or is_steep(cell) or FEATURE_CHARS.contains(char_at(cell)):
				continue
			# Solo el pie: la pared tiene que subir por encima de esta casilla (lo de arriba del acantilado no cuenta: una
			# roca caída no se queda en lo alto).
			var here: float = terrain_height(x + 0.5, y + 0.5)
			var wall_dir := Vector2.ZERO
			for dy: int in range(-1, 2):
				for dx: int in range(-1, 2):
					if drops[(y + dy) * size.x + x + dx] > WALL_FOOT_DROP \
							and terrain_height(x + dx + 0.5, y + dy + 0.5) > here + WALL_FOOT_RISE:
						wall_dir += Vector2(dx, dy)
			if wall_dir == Vector2.ZERO:
				continue
			_wall_foot[cell] = true
			var g: Ground = ground(cell)
			if g == Ground.RAMP or g == Ground.LANDING or is_path(cell) or _worn[y * size.x + x] == 1:
				continue
			if _near_ladder(cell):
				continue   # la escala de cuerda baja hasta el suelo (César: una cuerda se metía en una roca caída)
			# Nunca en una explanada (César, sesión 31: en la de arriba y en la de abajo estorbaban para construir).
			if is_buildable(cell):
				continue
			if _cell_random(cell, 1) > DEBRIS_CHANCE:
				continue
			var scale: float = lerpf(DEBRIS_SCALE_MIN, DEBRIS_SCALE_MAX, _cell_random(cell, 2))
			# Un poco hacia la pared y algo al azar, sin salir de su casilla.
			var pos := Vector2(x + 0.5, y + 0.5) + wall_dir.normalized() * 0.25 \
					+ Vector2(_cell_random(cell, 3) - 0.5, _cell_random(cell, 4) - 0.5) * 0.3
			var ground_y: float = lowest_around(pos.x, pos.y, 0.2 * scale)
			debris.append({
				"position": Vector3(pos.x, ground_y - 0.12 * scale, pos.y),
				"scale": scale,
				"yaw": _cell_random(cell, 5) * TAU,
				"tilt": (_cell_random(cell, 6) - 0.5) * 0.5,
				"variant": int(_cell_random(cell, 7) * 3.0) % 3,
			})
			if _cell_random(cell, 8) < DEBRIS_PAIR_CHANCE:   # una pequeña al lado: se ven en grupos
				var side := Vector2(_cell_random(cell, 9) - 0.5, _cell_random(cell, 10) - 0.5).normalized() * 0.3
				var small: float = scale * 0.5
				var spot: Vector2 = (pos + side).clamp(Vector2(x + 0.1, y + 0.1), Vector2(x + 0.9, y + 0.9))
				debris.append({
					"position": Vector3(spot.x, lowest_around(spot.x, spot.y, 0.2 * small) - 0.1 * small, spot.y),
					"scale": small,
					"yaw": _cell_random(cell, 11) * TAU,
					"tilt": (_cell_random(cell, 12) - 0.5) * 0.6,
					"variant": (int(_cell_random(cell, 7) * 3.0) + 1) % 3,
				})
			_debris_cells[cell] = true


# --- Rocas modeladas (C5.6, sesión 30) ---

## Rocas de `rocks.glb` que dibuja el juego. Cada una: {"mesh": nombre de la pieza («rock_m_2», «boulder_1»…), "position"
## (m, a ras del suelo más bajo debajo de ella), "yaw", "scale" y "solid" (con choque; los guijarros, no). Los peñascos salen
## de los grupos de `X` del plano (pintados en `paint_alba.png`) y el del emblema, de su `K`; las rocas medianas y los
## guijarros se reparten solos. Siempre igual (por la casilla).
var rocks: Array[Dictionary] = []
## Piezas de `rocks.glb` (`rocks_blockout.py`).
const MEDIUM_ROCKS: Array[String] = ["rock_m_0", "rock_m_1", "rock_m_2", "rock_m_3"]
const PEBBLES: Array[String] = ["pebbles_0", "pebbles_1", "pebbles_2"]
const SMALL_BOULDER: String = "boulder_0"           # 2 × 2
const BIG_BOULDERS: Array[String] = ["boulder_1", "boulder_split"]   # 3 × 3
const CARVED_BOULDER: String = "boulder_carved"     # 2 × 2, el del emblema (uno solo: `K`)
const CARVED_CHAR: String = "K"
## Rocas medianas sueltas (César, sesión 30: en el césped y en la arena no quedaban bien, y en el sendero sobraban): solo
## junto a las lomas y los acantilados (a una casilla de algo empinado) y en la orilla del río y del lago. Nunca a una casilla
## o menos del sendero. Las hileras de las rampas (la de la cumbre y la de la terraza) son peñascos pintados (`X`). Parte de
## las casillas que llevan una.
## Desde la sesión 31 son corros (César: agrupadas quedan mejor), así que cada casilla empieza un corro con menos
## probabilidad que antes una roca suelta.
const MEDIUM_CHANCE_RELIEF: float = 0.025
const MEDIUM_CHANCE_SHORE: float = 0.06
## Rocas pequeñas que acompañan a la grande de cada corro (de 1 a esto) y casillas libres entre dos corros.
const CLUSTER_EXTRA_MAX: int = 3
const CLUSTER_GAP: int = 2
## Hileras de las rampas (sesión 31): lo que cada roca se aparta de la rampa (m), lo que se mueve al azar (m), sus
## tamaños y la parte que lleva una pequeña al lado.
const ROW_AWAY: float = 0.4
const ROW_WOBBLE: float = 0.45
const ROW_SCALE_MIN: float = 0.75
const ROW_SCALE_MAX: float = 1.7
const ROW_PAIR_CHANCE: float = 0.3
## Tamaño mínimo de las rocas de la hilera donde la rampa va alta, y desde qué desnivel de la casilla (m) se aplica del todo.
const ROW_UPHILL_MIN: float = 1.35
const ROW_UPHILL_DROP: float = 0.9
## Parte de las casillas de la hilera que derraman una roca pequeña a la casilla de fuera.
const ROW_SPILL_CHANCE: float = 0.5
## Las ocho casillas de alrededor.
const NEIGHBOURS_8: Array[Vector2i] = [Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 1),
		Vector2i(-1, 0), Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1)]
## Guijarros: solo al pie de las rocas y de lo empinado (a una casilla), nunca en la arena. Parte de esas casillas.
const PEBBLES_CHANCE: float = 0.25
## Sin rocas medianas a menos de estas casillas del portal, del embarcadero y del vado (por donde se pasa).
const ROCK_CLEAR: int = 3


## ¿Puede ir aquí una roca mediana? En tierra sin objetos que no sea explanada, empinada, sendero, tierra pisada, rampa ni
## rellano, ni junto al refugio, la escala, la barandilla, el portal, el embarcadero o el vado.
func _medium_rock_spot(cell: Vector2i) -> bool:
	if not is_land(cell) or is_buildable(cell) or is_steep(cell) or FEATURE_CHARS.contains(char_at(cell)):
		return false
	var g: Ground = ground(cell)
	if g == Ground.RAMP or g == Ground.LANDING or g == Ground.BEACH or is_path(cell) or _worn[cell.y * size.x + cell.x] == 1:
		return false
	if _debris_cells.has(cell) or _near_shelter(cell) or _near_ladder(cell) or fence_cells.has(cell):
		return false
	for dy: int in range(-ROCK_CLEAR, ROCK_CLEAR + 1):
		for dx: int in range(-ROCK_CLEAR, ROCK_CLEAR + 1):
			if "PEs".contains(char_at(cell + Vector2i(dx, dy))):
				return false
	return true


## ¿Puede caer aquí una roca pequeña derramada de una hilera? Como `_medium_rock_spot()`, pero vale el talud de la rampa
## (empinado): la roca se asienta en lo más bajo.
func _spill_spot(cell: Vector2i) -> bool:
	if not is_land(cell) or is_buildable(cell) or FEATURE_CHARS.contains(char_at(cell)) or _debris_cells.has(cell):
		return false
	var g: Ground = ground(cell)
	return g != Ground.RAMP and g != Ground.LANDING and g != Ground.BEACH and not is_path(cell) \
			and _worn[cell.y * size.x + cell.x] != 1 and slope_drop(cell) < MAX_SLOPE_FOR_NATURE * 1.5


## Grupos de casillas iguales (`ch`) que se tocan por un lado.
func _feature_groups(ch: String) -> Array[Array]:
	var left: Dictionary[Vector2i, bool] = {}
	for cell: Vector2i in cells_of(ch):
		left[cell] = true
	var groups: Array[Array] = []
	while not left.is_empty():
		var start: Vector2i = left.keys()[0]
		left.erase(start)
		var group: Array[Vector2i] = [start]
		var open: Array[Vector2i] = [start]
		while not open.is_empty():
			var cell: Vector2i = open.pop_back()
			for step: Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
				if left.has(cell + step):
					left.erase(cell + step)
					group.append(cell + step)
					open.append(cell + step)
		groups.append(group)
	return groups


func _add_rock(mesh: String, center: Vector2, scale: float, yaw: float, solid: bool, radius: float) -> void:
	rocks.append({"mesh": mesh, "position": Vector3(center.x, lowest_around(center.x, center.y, radius), center.y),
			"yaw": yaw, "scale": scale, "solid": solid})


func _compute_rocks() -> void:
	rocks.clear()
	# Peñascos del plano: cada grupo de `X`, según su forma.
	for group: Array in _feature_groups("X"):
		var low := Vector2i(1 << 20, 1 << 20)
		var high := Vector2i(-(1 << 20), -(1 << 20))
		for cell: Vector2i in group:
			low = low.min(cell)
			high = high.max(cell)
		var box: Vector2i = high - low + Vector2i.ONE
		var first: Vector2i = low
		var center := Vector2(low) + Vector2(box) * 0.5
		var yaw: float = _cell_random(first, 21) * TAU
		if maxi(box.x, box.y) >= 3 and mini(box.x, box.y) == 1:
			# Hilera (las rampas de la cumbre y de la terraza): una roca mediana en cada casilla, desordenadas (César,
			# sesión 31: centradas y del mismo tamaño quedaban rectas y artificiales). Cada una se aparta un poco de la
			# rampa, del sendero y de la explanada, se mueve algo al azar sin salir de su casilla, cambia mucho de tamaño
			# y algunas llevan una pequeña al lado.
			for cell: Vector2i in group:
				var away := Vector2.ZERO
				for step: Vector2i in NEIGHBOURS_8:
					var other: Vector2i = cell + step
					if ground(other) == Ground.RAMP or is_path(other) or is_buildable(other):
						away -= Vector2(step)
				if away != Vector2.ZERO:
					away = away.normalized()
				var base := Vector2(cell) + Vector2(0.5, 0.5)
				var wobble := Vector2(_cell_random(cell, 26) - 0.5, _cell_random(cell, 27) - 0.5) * ROW_WOBBLE
				var spot: Vector2 = (base + away * _cell_random(cell, 28) * ROW_AWAY + wobble) \
						.clamp(Vector2(cell) + Vector2(0.12, 0.12), Vector2(cell) + Vector2(0.88, 0.88))
				# Algunas pequeñas se derraman a la casilla de fuera (nunca hacia la rampa ni a una explanada): así la
				# hilera no tiene un borde recto.
				var outside := Vector2i(-1, -1)
				if away != Vector2.ZERO and _cell_random(cell, 59) < ROW_SPILL_CHANCE:
					for candidate: Vector2i in [cell + Vector2i(roundi(away.x), roundi(away.y)),
							cell + Vector2i(signi(roundi(away.x * 1.4)), 0), cell + Vector2i(0, signi(roundi(away.y * 1.4)))]:
						if candidate != cell and not group.has(candidate) and _spill_spot(candidate):
							outside = candidate
							break
				if outside != Vector2i(-1, -1):
					_debris_cells[outside] = true
					var spill: Vector2 = (Vector2(outside) + Vector2(0.5, 0.5) - away * 0.2 \
							+ Vector2(_cell_random(outside, 60) - 0.5, _cell_random(outside, 61) - 0.5) * 0.3) \
							.clamp(Vector2(outside) + Vector2(0.15, 0.15), Vector2(outside) + Vector2(0.85, 0.85))
					_add_rock(MEDIUM_ROCKS[int(_cell_random(outside, 62) * 4.0) % 4], spill,
							lerpf(0.6, 1.05, _cell_random(outside, 63)), _cell_random(outside, 64) * TAU, true, 0.3)
				# Donde la rampa va alta, el talud es mayor: rocas más grandes como mínimo y asentadas menos abajo
				# (César, sesión 31: el lado oeste de la rampa de la terraza quedaba vacío arriba).
				var uphill: float = clampf(slope_drop(cell) / ROW_UPHILL_DROP, 0.0, 1.0)
				var low_scale: float = lerpf(ROW_SCALE_MIN, ROW_UPHILL_MIN, uphill)
				_add_rock(MEDIUM_ROCKS[int(_cell_random(cell, 22) * 4.0) % 4], spot,
						lerpf(low_scale, ROW_SCALE_MAX, _cell_random(cell, 23)), _cell_random(cell, 24) * TAU, true,
						lerpf(0.5, 0.25, uphill))
				if _cell_random(cell, 29) < ROW_PAIR_CHANCE:
					var side: Vector2 = (base - spot)
					side = side.normalized() if side.length() > 0.01 else Vector2.RIGHT.rotated(_cell_random(cell, 30) * TAU)
					var small_spot: Vector2 = (spot + side * 0.35).clamp(Vector2(cell) + Vector2(0.15, 0.15),
							Vector2(cell) + Vector2(0.85, 0.85))
					_add_rock(MEDIUM_ROCKS[(int(_cell_random(cell, 22) * 4.0) + 1) % 4], small_spot,
							lerpf(0.45, 0.7, _cell_random(cell, 47)), _cell_random(cell, 48) * TAU, true, 0.3)
		elif group.size() == 1:
			_add_rock(MEDIUM_ROCKS[int(_cell_random(first, 22) * 4.0) % 4], center, lerpf(1.0, 1.3, _cell_random(first, 23)),
					yaw, true, 0.45)
		elif maxi(box.x, box.y) <= 2:
			_add_rock(SMALL_BOULDER, center, 0.75 if group.size() == 2 else 1.0, yaw, true, 0.8)
		else:
			_add_rock(BIG_BOULDERS[int(_cell_random(first, 25) * 2.0) % 2], center,
					clampf(maxi(box.x, box.y) / 3.0, 0.8, 1.3), yaw, true, 1.2)
	# El peñasco del emblema (`K`, 2 × 2, uno solo): sin girar, con el emblema mirando al sur (a la explanada baja).
	var carved: Array[Vector2i] = cells_of(CARVED_CHAR)
	if not carved.is_empty():
		_add_rock(CARVED_BOULDER, _average(carved) + Vector2(0.5, 0.5), 1.0, 0.0, true, 0.8)
	# Rocas medianas en corros (César, sesión 31: agrupadas quedan mejor que sueltas): en la orilla del río y del lago y
	# junto a lo empinado (lomas y acantilados). Cada corro, una roca grande y de 1 a CLUSTER_EXTRA_MAX pequeñas pegadas.
	var taken: Dictionary[Vector2i, bool] = {}
	for y: int in range(1, size.y - 1):
		for x: int in range(1, size.x - 1):
			var cell := Vector2i(x, y)
			if not _medium_rock_spot(cell):
				continue
			if _distance_to(cell, ":", 1) <= 1:
				continue   # el sendero, despejado
			var chance: float = 0.0
			if _near_inland_water(cell):
				chance = MEDIUM_CHANCE_SHORE
			elif _near_steep(cell):
				chance = MEDIUM_CHANCE_RELIEF
			if _cell_random(cell, 31) >= chance:
				continue
			var crowded: bool = false   # entre dos corros, al menos CLUSTER_GAP casillas libres
			for dy: int in range(-CLUSTER_GAP - 1, CLUSTER_GAP + 2):
				for dx: int in range(-CLUSTER_GAP - 1, CLUSTER_GAP + 2):
					crowded = crowded or taken.has(cell + Vector2i(dx, dy))
			if crowded:
				continue
			taken[cell] = true
			_debris_cells[cell] = true   # como una roca caída: ahí no se construye, no se planta y no aparece nada
			var center := Vector2(x + 0.5, y + 0.5) + Vector2(_cell_random(cell, 32) - 0.5, _cell_random(cell, 33) - 0.5) * 0.2
			_add_rock(MEDIUM_ROCKS[int(_cell_random(cell, 34) * 4.0) % 4], center,
					lerpf(1.0, 1.4, _cell_random(cell, 35)),
					_cell_random(cell, 36) * TAU, true, 0.45)
			# Las pequeñas, en casillas de al lado que también valgan (pegadas a la grande); si no cabe ninguna, una en
			# la misma casilla.
			var wanted: int = 1 + int(_cell_random(cell, 37) * CLUSTER_EXTRA_MAX) % CLUSTER_EXTRA_MAX
			var first_step: int = int(_cell_random(cell, 38) * 8.0) % 8
			var placed: int = 0
			for k: int in 8:
				if placed >= wanted:
					break
				var step: Vector2i = NEIGHBOURS_8[(first_step + k * 3) % 8]   # saltando de 3 en 3: salen repartidas
				var other: Vector2i = cell + step
				if taken.has(other) or not _medium_rock_spot(other) or _distance_to(other, ":", 1) <= 1:
					continue
				taken[other] = true
				_debris_cells[other] = true
				var spot: Vector2 = (Vector2(other) + Vector2(0.5, 0.5) - Vector2(step).normalized() * 0.25 \
						+ Vector2(_cell_random(other, 51) - 0.5, _cell_random(other, 52) - 0.5) * 0.2) \
						.clamp(Vector2(other) + Vector2(0.15, 0.15), Vector2(other) + Vector2(0.85, 0.85))
				_add_rock(MEDIUM_ROCKS[int(_cell_random(other, 53) * 4.0) % 4], spot,
						lerpf(0.5, 0.85, _cell_random(other, 54)), _cell_random(other, 55) * TAU, true, 0.3)
				placed += 1
			if placed == 0:
				var side := Vector2.RIGHT.rotated(_cell_random(cell, 56) * TAU) * 0.3
				var small_spot: Vector2 = (center + side).clamp(Vector2(cell) + Vector2(0.15, 0.15),
						Vector2(cell) + Vector2(0.85, 0.85))
				_add_rock(MEDIUM_ROCKS[(int(_cell_random(cell, 34) * 4.0) + 2) % 4], small_spot,
						lerpf(0.45, 0.65, _cell_random(cell, 57)), _cell_random(cell, 58) * TAU, true, 0.3)
	# Guijarros: al pie de las rocas (las del plano, el emblema, las medianas y las caídas) y de lo empinado.
	for y: int in range(1, size.y - 1):
		for x: int in range(1, size.x - 1):
			var cell := Vector2i(x, y)
			if not is_land(cell) or is_buildable(cell) or is_steep(cell) or FEATURE_CHARS.contains(char_at(cell)) \
					or ground(cell) == Ground.BEACH or _debris_cells.has(cell) or _cell_random(cell, 41) >= PEBBLES_CHANCE:
				continue
			# Ni en las rampas ni en el sendero (sesión 31, César: en las dos rampas flotaban por la inclinación).
			if ground(cell) == Ground.RAMP or is_path(cell):
				continue
			var by_rock: bool = _near_steep(cell)
			for dy: int in range(-1, 2):
				for dx: int in range(-1, 2):
					var other := cell + Vector2i(dx, dy)
					by_rock = by_rock or _debris_cells.has(other) or "XK".contains(char_at(other))
			if not by_rock:
				continue
			var spot := Vector2(x + 0.5, y + 0.5) + Vector2(_cell_random(cell, 42) - 0.5, _cell_random(cell, 43) - 0.5) * 0.5
			_add_rock(PEBBLES[int(_cell_random(cell, 44) * 3.0) % 3], spot, lerpf(0.8, 1.3, _cell_random(cell, 45)),
					_cell_random(cell, 46) * TAU, false, 0.3)


## ¿Toca (también en diagonal) el agua de la isla: el río, el lago o el remanso? El mar no cuenta (ahí hay arena).
func _near_inland_water(cell: Vector2i) -> bool:
	for dy: int in range(-1, 2):
		for dx: int in range(-1, 2):
			if (dx != 0 or dy != 0) and ground(cell + Vector2i(dx, dy)) == Ground.WATER:
				return true
	return false


## Helechos, arbustos y juncos (C5.6, sesión 31), decorativos: no dan nada ni chocan. Cada uno: pieza de `plants.glb`
## (`mesh`), `position` (x, z del mundo de la isla; la altura la pone `TerrainView` con la malla dibujada), `yaw`,
## `scale`, `stiffness` (0 = se dobla mucho con el viento, 1 = firme) y `reach` (lo lejos que se sigue viendo).
## Reglas: juncos tocando el río y el lago; helechos a la sombra, junto a árboles y rocas; arbustos en las lomas, al
## pie de lo empinado, junto a rocas y al borde de las arboledas. Nunca donde se construye (las explanadas y el suelo
## natural casi plano quedan libres; ahí ya hay césped, flores y tréboles), ni en el sendero, rampas, arena, junto al
## refugio, el portal, la valla o la escala.
var plants: Array[Dictionary] = []
const REED_CHANCE: float = 0.85
const REED_PAIR_CHANCE: float = 0.55
const FERN_CHANCE: float = 0.3
const BUSH_CHANCE: float = 0.1
const FERNS: Array[String] = ["fern_0", "fern_1"]
const REEDS: Array[String] = ["reeds_0", "reeds_1"]
## Arbustos de pequeño a grande; los grandes, menos.
const BUSHES: Array[String] = ["bush_0", "bush_0", "bush_1", "bush_1", "bush_2"]


## ¿Puede ir aquí un helecho, un arbusto o un junco?
func _plant_spot(cell: Vector2i) -> bool:
	if not is_land(cell) or can_build(cell) or is_steep(cell) or _debris_cells.has(cell) or is_path(cell):
		return false
	if FEATURE_CHARS.contains(char_at(cell)) or _worn[cell.y * size.x + cell.x] == 1:
		return false
	var g: Ground = ground(cell)
	if g == Ground.RAMP or g == Ground.LANDING or g == Ground.BEACH or g == Ground.FALL:
		return false
	if _near_shelter(cell) or fence_cells.has(cell) or ladder_cells.has(cell) or _near_ladder(cell):
		return false
	# Ni junto a la pasarela del vado (sesión 31, César: dos juncos la atravesaban): sus extremos se apoyan en tierra.
	return _distance_to(cell, "P", 2) > 2 and _distance_to(cell, FORD_CELL_CHAR, PLANT_FORD_CLEAR) > PLANT_FORD_CLEAR


## Casillas libres de plantas alrededor del vado (la pasarela y sus apoyos en las orillas).
const PLANT_FORD_CLEAR: int = 3
## Letra del vado en el plano (la misma que `BridgeBuilder.FORD_CHAR`).
const FORD_CELL_CHAR: String = "s"


## ¿Hay a `reach` casillas o menos alguna de `chars` (o una roca, si `rocks`)?
func _near_any(cell: Vector2i, chars: String, reach: int, rocks_too: bool) -> bool:
	for dy: int in range(-reach, reach + 1):
		for dx: int in range(-reach, reach + 1):
			var other: Vector2i = cell + Vector2i(dx, dy)
			if chars.contains(char_at(other)) or (rocks_too and _debris_cells.has(other)):
				return true
	return false


func _add_plant(mesh: String, cell: Vector2i, salt: int, scale: float, stiffness: float, reach: float) -> void:
	var at := Vector2(cell) + Vector2(0.5, 0.5) \
			+ Vector2(_cell_random(cell, salt) - 0.5, _cell_random(cell, salt + 1) - 0.5) * 0.6
	plants.append({"mesh": mesh, "position": at, "yaw": _cell_random(cell, salt + 2) * TAU, "scale": scale,
			"stiffness": stiffness, "reach": reach})


func _compute_plants() -> void:
	plants.clear()
	for y: int in range(1, size.y - 1):
		for x: int in range(1, size.x - 1):
			var cell := Vector2i(x, y)
			if not _plant_spot(cell):
				continue
			if _near_inland_water(cell):
				if _cell_random(cell, 71) < REED_CHANCE:
					var scale: float = lerpf(0.8, 1.2, _cell_random(cell, 72))
					_add_plant(REEDS[int(_cell_random(cell, 73) * 2.0) % 2], cell, 74, scale, 0.05, 0.6)
					if _cell_random(cell, 77) < REED_PAIR_CHANCE:
						_add_plant(REEDS[int(_cell_random(cell, 78) * 2.0) % 2], cell, 79, scale * 0.85, 0.05, 0.6)
				continue
			if _near_any(cell, "tTX", 1, true) and _cell_random(cell, 81) < FERN_CHANCE:
				_add_plant(FERNS[int(_cell_random(cell, 82) * 2.0) % 2], cell, 83,
						lerpf(0.8, 1.2, _cell_random(cell, 86)), 0.45, 0.3)
				continue
			if (_near_steep(cell) or _near_any(cell, "TX", 2, true)) and _cell_random(cell, 91) < BUSH_CHANCE:
				_add_plant(BUSHES[int(_cell_random(cell, 92) * BUSHES.size()) % BUSHES.size()], cell, 93,
						lerpf(0.85, 1.15, _cell_random(cell, 96)), 0.8, 1.0)


## ¿Hay algo empinado (pared, borde de loma) a una casilla?
func _near_steep(cell: Vector2i) -> bool:
	for dy: int in range(-1, 2):
		for dx: int in range(-1, 2):
			if (dx != 0 or dy != 0) and is_steep(cell + Vector2i(dx, dy)):
				return true
	return false


## Distancia (casillas, en cuadrado) a la casilla `ch` más cercana, mirando hasta `reach`; reach + 1 si no hay ninguna.
func _distance_to(cell: Vector2i, ch: String, reach: int) -> int:
	for d: int in range(0, reach + 1):
		for dy: int in range(-d, d + 1):
			for dx: int in range(-d, d + 1):
				if maxi(absi(dx), absi(dy)) == d and char_at(cell + Vector2i(dx, dy)) == ch:
					return d
	return reach + 1


## Lo metida que está una casilla en su explanada (casillas hasta el borde; 0 fuera de las explanadas). Para que lo que
## solo va en las explanadas (los claros de tierra) se apague antes del borde y no se corte en seco por las casillas.
func flat_depth(cell: Vector2i) -> float:
	if not has_cell(cell):
		return 0.0
	if _flat_depth.is_empty():
		_flat_depth.resize(size.x * size.y)
		for y: int in size.y:
			for x: int in size.x:
				_flat_depth[y * size.x + x] = 1.0e6 if is_buildable(Vector2i(x, y)) else 0.0
		_chamfer_distance(_flat_depth)
	return _flat_depth[cell.y * size.x + cell.x]


var _flat_depth: PackedFloat32Array = PackedFloat32Array()


## ¿Está a LADDER_CLEAR casillas o menos de la escala (`ladder_cells`)? Ahí no caen rocas al pie de la pared (C5.6b).
func _near_ladder(cell: Vector2i) -> bool:
	for ladder_cell: Vector2i in ladder_cells:
		if maxi(absi(cell.x - ladder_cell.x), absi(cell.y - ladder_cell.y)) <= LADDER_CLEAR:
			return true
	return false


## ¿Hay una roca caída en esta casilla? (ahí no se planta ni aparece nada)
func has_debris(cell: Vector2i) -> bool:
	return _debris_cells.has(cell)


## Número de 0 a 1 que siempre sale igual para una casilla y un uso (`salt`).
func _cell_random(cell: Vector2i, salt: int) -> float:
	var n: int = hash(Vector3i(cell.x, cell.y, salt))
	return float(n & 0xFFFF) / 65535.0


## ¿Es sendero? (`:` en el plano, C5.4a): ladera que se pinta de tierra pisada.
func is_path(cell: Vector2i) -> bool:
	return char_at(cell) == ":"


## Tierra pisada de la casilla, de 0 a 1 (ver `_wear`).
func wear(cell: Vector2i) -> float:
	return _wear[cell.y * size.x + cell.x] if has_cell(cell) else 0.0


## Agua de la casilla: dirección en la que corre, `Vector2i.ZERO` si está quieta, o null si no es agua.
## El mar no cuenta: rodea la isla, pero no es agua de la cuadrícula (no hay ruedas en el mar).
func water_flow(cell: Vector2i) -> Variant:
	if ground(cell) != Ground.WATER:
		return null
	return _FLOW_BY_CHAR.get(char_at(cell), Vector2i.ZERO)


## Todas las casillas de un objeto del plano (`"T"`, `"M"`…), en orden de lectura.
func cells_of(ch: String) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	result.assign(features.get(ch, []))
	return result


## Suelo de una casilla con objeto: el más repetido entre sus vecinas (a 2 casillas), sin contar objetos, mar
## ni agua. Así una veta en mitad de la explanada queda en la explanada y un árbol de la montaña, en la montaña.
func _infer_ground(cell: Vector2i) -> Ground:
	var counts: Dictionary[int, int] = {}
	for dy: int in range(-2, 3):
		for dx: int in range(-2, 3):
			var other := Vector2i(cell.x + dx, cell.y + dy)
			if not has_cell(other) or FEATURE_CHARS.contains(char_at(other)):
				continue
			var g: Ground = _GROUND_BY_CHAR.get(char_at(other), Ground.SEA)
			if g == Ground.SEA or g == Ground.WATER or g == Ground.FALL:
				continue
			counts[g] = counts.get(g, 0) + 1
	var best: int = Ground.LOW
	var best_count: int = -1
	for g: int in counts:
		if counts[g] > best_count:
			best = g
			best_count = counts[g]
	return best as Ground


## Altura del suelo de cada casilla (fila a fila). La ladera, el rellano y la cascada suben poco a poco de la
## parte baja a la alta según lo cerca que estén de cada una (búsqueda en anchura sobre sus casillas).
func _compute_heights() -> void:
	var w: int = size.x
	var h: int = size.y
	_heights.resize(w * h)
	var to_land: PackedInt32Array = _sea_distances()
	# Para la ladera y las rampas: la distancia a cada altura. Cada casilla sube entre las dos alturas más cercanas
	# (la ladera del oeste, entre la baja y la alta; la rampa de la terraza, entre la baja y la media).
	# El agua más alta que toca la cascada: su cauce va justo por debajo.
	var fall_top: float = -INF
	for y: int in size.y:
		for x: int in size.x:
			if ground(Vector2i(x, y)) != Ground.FALL:
				continue
			for offset: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				if ground(Vector2i(x, y) + offset) == Ground.WATER:
					fall_top = maxf(fall_top, level_height(level(Vector2i(x, y) + offset)))
	var to_level: Dictionary[int, Dictionary] = {}
	for l: int in [LOW_LEVEL, MID_LEVEL, HIGH_LEVEL, TOP_LEVEL]:
		to_level[l] = _slope_distances(l)
	for y: int in h:
		for x: int in w:
			var cell := Vector2i(x, y)
			var g: Ground = ground(cell)
			var value: float = 0.0
			match g:
				Ground.SEA:
					var far: float = float(maxi(to_land[y * w + x] - 1, 0))
					value = maxf(SEA_BED - far * SEA_DROP_PER_CELL, SEA_DEEPEST)
				Ground.WATER:
					value = level_height(level(cell)) - WATER_DEPTH
				Ground.FALL:
					# Cauce de la cascada (C5.4e): un poco por debajo del agua de arriba hasta el borde, donde cae de
					# golpe al río (si no, su suelo quedaba a ras del lago y se veía un escalón, César).
					value = fall_top - FALL_CHANNEL_DEPTH if fall_top > -INF else _slope_height(cell, to_level)
				Ground.SLOPE:
					value = _slope_height(cell, to_level)
				Ground.RAMP:
					value = _ramp_height(cell, to_level)
				_:
					value = level_height(level(cell))
			_heights[y * w + x] = value


## Altura de una casilla de ladera o de rampa: la media de las alturas a las que llega, pesada por lo cerca que está
## de cada una (1 / distancia²): suave al empezar y al acabar, y sin saltos con tres alturas (la ladera con el rellano
## en medio).
	# El sendero, plano de lado a lado: cada casilla del camino toma la media de las del camino que la rodean (varias
	# pasadas). Así sube recto, sin ir inclinado en las curvas.
	for _pass: int in PATH_LEVEL_PASSES:
		var levelled: PackedFloat32Array = _heights.duplicate()
		for y: int in size.y:
			for x: int in size.x:
				if not is_path(Vector2i(x, y)):
					continue
				var total: float = 0.0
				var count: int = 0
				for dy: int in range(-1, 2):
					for dx: int in range(-1, 2):
						var other := Vector2i(x + dx, y + dy)
						if is_path(other):
							total += _heights[other.y * size.x + other.x]
							count += 1
				levelled[y * size.x + x] = total / float(count)
		_heights = levelled

func _slope_height(cell: Vector2i, to_level: Dictionary[int, Dictionary]) -> float:
	var weights: float = 0.0
	var total: float = 0.0
	for l: int in to_level:
		if not to_level[l].has(cell):
			continue
		# Al cuadrado: pesa mucho más la altura más cercana. Las subidas empiezan y acaban suaves (César: el sendero
		# empezaba empinado, como un montículo, porque lo alto tiraba del principio de la subida).
		var weight: float = 1.0 / pow(float(to_level[l][cell]), 2.0)
		weights += weight
		total += weight * level_height(l)
	return total / weights if weights > 0.0 else 0.0


## Altura de una casilla de rampa: entre las dos alturas que une, en línea recta por la distancia y con las puntas
## suavizadas (empieza y acaba casi plana: César, al subir había un escalón al principio y al final).
func _ramp_height(cell: Vector2i, to_level: Dictionary[int, Dictionary]) -> float:
	var levels: Array[int] = []
	for l: int in to_level:
		if to_level[l].has(cell):
			levels.append(l)
	if levels.size() < 2:
		return _slope_height(cell, to_level)
	levels.sort_custom(func(a: int, b: int) -> bool: return to_level[a][cell] < to_level[b][cell])
	var near_level: int = levels[0]
	var far_level: int = levels[1]
	var near_distance: float = float(to_level[near_level][cell]) - 0.5   # desde el borde de la casilla, no su centro
	var far_distance: float = float(to_level[far_level][cell]) - 0.5
	var t: float = near_distance / maxf(near_distance + far_distance, 0.001)
	# Recta en medio y suave en las dos puntas (César: arriba pasaba de inclinada a plana de golpe; la «barriga» de
	# antes era de lado a lado, por la explanada de al lado). `t` va desde la altura más baja.
	var low_level: int = near_level if level_height(near_level) < level_height(far_level) else far_level
	var high_level: int = far_level if low_level == near_level else near_level
	var from_low: float = t if low_level == near_level else 1.0 - t
	var eased: float = lerpf(from_low, smoothstep(0.0, 1.0, from_low), RAMP_EASE)
	return lerpf(level_height(low_level), level_height(high_level), eased)


## Distancia de cada casilla de mar a la tierra más cercana (en casillas, por la cuadrícula; 0 en tierra).
func _sea_distances() -> PackedInt32Array:
	var distances := PackedInt32Array()
	distances.resize(size.x * size.y)
	distances.fill(-1)
	var queue: Array[Vector2i] = []
	for y: int in size.y:
		for x: int in size.x:
			if ground(Vector2i(x, y)) != Ground.SEA:
				distances[y * size.x + x] = 0
				queue.append(Vector2i(x, y))
	var head: int = 0
	while head < queue.size():
		var cell: Vector2i = queue[head]
		head += 1
		for offset: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var other: Vector2i = cell + offset
			if has_cell(other) and distances[other.y * size.x + other.x] == -1:
				distances[other.y * size.x + other.x] = distances[cell.y * size.x + cell.x] + 1
				queue.append(other)
	return distances


## Distancia en casillas, por la ladera, el rellano y la cascada, hasta la tierra de una altura.
func _slope_distances(target_level: int) -> Dictionary[Vector2i, int]:
	var distances: Dictionary[Vector2i, int] = {}
	var queue: Array[Vector2i] = []
	for y: int in size.y:
		for x: int in size.x:
			var cell := Vector2i(x, y)
			if _is_slope(cell):
				for offset: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
					var other: Vector2i = cell + offset
					# Las lomas no cuentan: tiraban hacia abajo los lados de la rampa de la terraza, que pasa entre ellas.
					if is_land(other) and not _is_slope(other) and level(other) == target_level and ground(other) != Ground.HILL \
							and ground(other) != Ground.HIGH_HILL:   # ni las altas: junto a ellas la ladera queda más baja y
							# se levanta un acantilado (el borde de la ladera, dibujo de César)
						distances[cell] = 1
						queue.append(cell)
						break
	var head: int = 0
	while head < queue.size():
		var cell: Vector2i = queue[head]
		head += 1
		for offset: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var other: Vector2i = cell + offset
			if _is_slope(other) and not distances.has(other):
				distances[other] = distances[cell] + 1
				queue.append(other)
	return distances


func _is_slope(cell: Vector2i) -> bool:
	var g: Ground = ground(cell)
	return g == Ground.SLOPE or g == Ground.FALL or g == Ground.RAMP


## Esquinas, casillas empinadas y casillas para rocas y palos (después de las alturas).
func _compute_corners() -> void:
	_corners.resize((size.x + 1) * (size.y + 1))
	for j: int in size.y + 1:
		for i: int in size.x + 1:
			_corners[j * (size.x + 1) + i] = _corner_from_cells(i, j)
	# Lo que se dibuja (C5.4b): las esquinas suavizadas, el relieve y la deformación de los bordes. Lo empinado se mide
	# sobre lo dibujado, para que nada aparezca en una pared.
	_compute_relief()
	_compute_drawn_corners()
	_steep.resize(size.x * size.y)
	var drops := PackedFloat32Array()
	drops.resize(size.x * size.y)
	spawn_cells.clear()
	for y: int in size.y:
		for x: int in size.x:
			var cell := Vector2i(x, y)
			drops[y * size.x + x] = slope_drop(cell)
			_steep[y * size.x + x] = 1 if drops[y * size.x + x] > MAX_SLOPE_FOR_NATURE else 0
	_drops = drops
	_compute_wall_feet(drops)
	_compute_rocks()
	_compute_natural_build()
	_compute_plants()
	for y: int in size.y:
		for x: int in size.x:
			if can_spawn(Vector2i(x, y)):
				spawn_cells.append(Vector2i(x, y))
	_compute_wear()


## Relieve: cuánto mueve el ruido cada esquina (según su suelo y lo lejos que está de lo que no se toca) y cuánto se
## levantan el rellano y el montículo del árbol singular. El ruido tiene siempre la misma semilla: la isla sale igual.
func _compute_relief() -> void:
	_relief_noise = FastNoiseLite.new()
	_relief_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_relief_noise.seed = 1
	_relief_noise.frequency = RELIEF_FREQUENCY
	_relief_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_relief_noise.fractal_octaves = 3
	# Distancia de cada casilla a lo que no se toca (0 en ello).
	var distances := PackedInt32Array()
	distances.resize(size.x * size.y)
	distances.fill(-1)
	var queue: Array[Vector2i] = []
	for y: int in size.y:
		for x: int in size.x:
			var cell := Vector2i(x, y)
			var g: Ground = ground(cell)
			var ch: String = char_at(cell)
			if is_buildable(cell) or g == Ground.WATER or g == Ground.SEA or g == Ground.FALL or g == Ground.RAMP or is_path(cell) \
					or (FEATURE_CHARS.contains(ch) and ch != "t"):
				distances[y * size.x + x] = 0
				queue.append(cell)
	var head: int = 0
	while head < queue.size():
		var cell: Vector2i = queue[head]
		head += 1
		for offset: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var other: Vector2i = cell + offset
			if has_cell(other) and distances[other.y * size.x + other.x] == -1:
				distances[other.y * size.x + other.x] = distances[cell.y * size.x + cell.x] + 1
				queue.append(other)
	# Lo que se mete cada casilla en su loma (0 fuera de las lomas), medido en redondo (con diagonales): con la
	# distancia por la cuadrícula salían rombos (César: «formas excesivamente geométricas»).
	var hill_depth := PackedFloat32Array()
	hill_depth.resize(size.x * size.y)
	for y: int in size.y:
		for x: int in size.x:
			# La terraza no cuenta como borde de la loma: las lomas pegadas a ella (su borde, César) suben hasta su
			# altura en lugar de bajar a cero a su lado.
			var g: Ground = ground(Vector2i(x, y))
			var is_edge: bool = g != Ground.HILL and g != Ground.HIGH_HILL and g != Ground.MID and g != Ground.MID_FLAT
			hill_depth[y * size.x + x] = 0.0 if is_edge else 1.0e6
	_chamfer_distance(hill_depth)
	# Distancia al sendero (para poner con corte las lomas de su lado).
	var path_distance := PackedFloat32Array()
	path_distance.resize(size.x * size.y)
	for y: int in size.y:
		for x: int in size.x:
			path_distance[y * size.x + x] = 0.0 if is_path(Vector2i(x, y)) else 1.0e6
	_chamfer_distance(path_distance)
	var landmark: Array[Vector2i] = cells_of("G")
	var landmark_center := Vector2(-1000.0, -1000.0)
	if not landmark.is_empty():
		landmark_center = _average(landmark) + Vector2(0.5, 0.5)
	var row: int = size.x + 1
	_relief_scale.resize(row * (size.y + 1))
	_relief_lift.resize(row * (size.y + 1))
	for j: int in size.y + 1:
		for i: int in size.x + 1:
			var nearest: int = 1000
			var amplitude: float = 0.0
			var count: int = 0
			var fixed: bool = false   # toca una explanada o el agua: no se mueve nunca
			var in_hill: float = 1.0e6
			var near_path: bool = false
			var high_hill: bool = false

			for cell: Vector2i in [Vector2i(i - 1, j - 1), Vector2i(i, j - 1), Vector2i(i - 1, j), Vector2i(i, j)]:
				if not has_cell(cell):
					nearest = 0
					continue
				nearest = mini(nearest, distances[cell.y * size.x + cell.x])
				var g: Ground = ground(cell)
				if is_buildable(cell) or g == Ground.WATER or g == Ground.SEA or g == Ground.RAMP:
					fixed = true
				amplitude += RELIEF_BY_GROUND.get(ground(cell), 0.0)
				count += 1
				if path_distance[cell.y * size.x + cell.x] <= PATH_CUT_REACH:
					near_path = true
				if g == Ground.HILL or g == Ground.HIGH_HILL:
					in_hill = minf(in_hill, hill_depth[cell.y * size.x + cell.x])
					high_hill = high_hill or g == Ground.HIGH_HILL
				elif g != Ground.MID and g != Ground.MID_FLAT:
					in_hill = 0.0
			var fade: float = smoothstep(0.0, RELIEF_FADE, float(nearest))
			_relief_scale[j * row + i] = (amplitude / maxf(count, 1.0)) * fade
			var lift: float = 0.0
			var to_landmark: float = Vector2(i, j).distance_to(landmark_center) / LANDMARK_MOUND_RADIUS
			if in_hill > 0.0 and in_hill < 1.0e5 and not fixed:
				# Cada tramo de loma, a su manera (C5.4b, César): más alta o más baja, y unas suben en cuesta y otras
				# con un corte de roca (subida corta y empinada).
				var character: float = (_relief_noise.get_noise_2d(i * 2.3 + 500.0, j * 2.3) + 1.0) * 0.5
				# Las de lo alto, casi siempre con corte (César: le gustan los acantilados de juguete y arriba había pocos).
				var cut: float = smoothstep(0.15, 0.4, character) if high_hill else smoothstep(0.45, 0.75, character)
				if near_path:
					cut = 1.0   # junto al sendero, corte de roca (César): la subida queda entre paredes de juguete
				var tall: float = lerpf(0.7, 1.45, character)
				var top: float = (HIGH_HILL_HEIGHT if high_hill else HILL_HEIGHT) * tall
				var ramp: float = lerpf(HIGH_HILL_RAMP if high_hill else HILL_RAMP, HILL_CUT_RAMP, cut)
				lift += top * smoothstep(0.0, ramp, in_hill)
			if to_landmark < 1.0 and not fixed:
				lift += LANDMARK_MOUND * (1.0 - smoothstep(0.0, 1.0, to_landmark))
			_relief_lift[j * row + i] = lift


## Tierra pisada (C5.4a): el sendero entero; alrededor de cada extremo (casillas del sendero que tocan tierra que no
## es ladera), del portal y de la entrada del refugio, una mancha redonda que se apaga con la distancia; y un camino
## suave, como el que deja la gente al pasar, de la bajada del sendero a la entrada del refugio y de ahí al portal.
func _compute_wear() -> void:
	_wear.resize(size.x * size.y)
	_wear.fill(0.0)
	var low_ends: Array[Vector2i] = []
	var near_water: PackedByteArray = _cells_near_water(WALL_FOOT_WATER_CLEAR)
	for y: int in size.y:
		for x: int in size.x:
			var cell := Vector2i(x, y)
			if _wall_foot.has(cell) and not is_buildable(cell) and near_water[y * size.x + x] == 0:
				# Lo que se desprende de la pared; en las explanadas no (no se deforman y salía una mancha a casillas).
				_wear[y * size.x + x] = maxf(_wear[y * size.x + x], WALL_FOOT_WEAR)
			var on_hill: bool = ground(cell) == Ground.HILL or ground(cell) == Ground.HIGH_HILL
			if _worn[y * size.x + x] == 1 and not is_steep(cell) and not on_hill:
				_wear[y * size.x + x] = 1.0   # pintado en la capa de tierra pisada (César); no en el pie de las lomas
			if ground(cell) == Ground.RAMP:
				_wear[y * size.x + x] = maxf(_wear[y * size.x + x], RAMP_WEAR)   # se ve por dónde se sube
				continue
			if not is_path(cell):
				continue
			_wear[y * size.x + x] = 1.0
			for offset: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var other: Vector2i = cell + offset
				if is_land(other) and not _is_slope(other):
					_add_wear_disc(Vector2(cell), WEAR_REACH)
					if level(other) == LOW_LEVEL:
						low_ends.append(cell)
					break
	var stops: Array[Vector2] = []
	if not low_ends.is_empty():
		stops.append(_average(low_ends))
	var shelter: Array[Vector2i] = cells_of("R")
	if not shelter.is_empty():
		var front := Vector2(_average(shelter).x, 0.0)
		for cell: Vector2i in shelter:
			front.y = maxf(front.y, cell.y + 1.0) # la boca mira al sur (`Refugio.md`)
		_add_wear_disc(front, WEAR_SPOT_REACH)
		stops.append(front)
	var portal: Array[Vector2i] = cells_of("P")
	if not portal.is_empty():
		_add_wear_disc(_average(portal), WEAR_SPOT_REACH)
		stops.append(_average(portal))
	for i: int in stops.size() - 1:
		_add_wear_line(stops[i], stops[i + 1], WEAR_TRAIL_WIDTH)
	# Solo en lo llano: en una cuesta se apaga (salvo el sendero de la ladera y las rampas, que van en cuesta a propósito).
	for y: int in size.y:
		for x: int in size.x:
			var cell := Vector2i(x, y)
			if is_path(cell) or ground(cell) == Ground.RAMP:
				continue
			var index: int = y * size.x + x
			_wear[index] *= 1.0 - smoothstep(WEAR_FLAT_FROM, WEAR_FLAT_TO, _drops[index])
	# El césped pintado manda (sesión 26): sin tierra pisada, también en el sendero.
	for y: int in size.y:
		for x: int in size.x:
			if is_forced_grass(Vector2i(x, y)):
				_wear[y * size.x + x] = 0.0

## Casillas a `radius` casillas o menos (en diagonal también cuenta 1) de agua de la isla (lago, río, remanso): 1; las
## demás, 0.
func _cells_near_water(radius: int) -> PackedByteArray:
	var near := PackedByteArray()
	near.resize(size.x * size.y)
	near.fill(0)
	for y: int in size.y:
		for x: int in size.x:
			if ground(Vector2i(x, y)) != Ground.WATER:
				continue
			for dy: int in range(-radius, radius + 1):
				for dx: int in range(-radius, radius + 1):
					var other := Vector2i(x + dx, y + dy)
					if has_cell(other):
						near[other.y * size.x + other.x] = 1
	return near


func _average(cells: Array[Vector2i]) -> Vector2:
	var sum := Vector2.ZERO
	for cell: Vector2i in cells:
		sum += Vector2(cell)
	return sum / float(cells.size())


## Mancha redonda de tierra pisada sobre la tierra que no es ladera (la ladera solo la pisa el sendero).
func _add_wear_disc(center: Vector2, radius: float) -> void:
	var reach: int = ceili(radius)
	for dy: int in range(-reach, reach + 1):
		for dx: int in range(-reach, reach + 1):
			var cell := Vector2i(roundi(center.x) + dx, roundi(center.y) + dy)
			_put_wear(cell, 1.0 - Vector2(cell).distance_to(center) / radius)


## Camino suave entre dos puntos: tierra pisada que se apaga hacia los lados (más fuerte en el centro).
func _add_wear_line(a: Vector2, b: Vector2, width: float) -> void:
	var reach: int = ceili(width)
	var x0: int = floori(minf(a.x, b.x)) - reach
	var x1: int = ceili(maxf(a.x, b.x)) + reach
	var y0: int = floori(minf(a.y, b.y)) - reach
	var y1: int = ceili(maxf(a.y, b.y)) + reach
	for y: int in range(y0, y1 + 1):
		for x: int in range(x0, x1 + 1):
			var point := Vector2(x, y)
			var closest: Vector2 = Geometry2D.get_closest_point_to_segment(point, a, b)
			_put_wear(Vector2i(x, y), (1.0 - point.distance_to(closest) / width) * WEAR_TRAIL_STRENGTH)


func _put_wear(cell: Vector2i, amount: float) -> void:
	if amount <= 0.0 or not is_land(cell) or _is_slope(cell) or is_steep(cell):
		return   # ni en la ladera (solo el sendero) ni al pie de un acantilado (captura de César)
	var index: int = cell.y * size.x + cell.x
	_wear[index] = maxf(_wear[index], amount)
