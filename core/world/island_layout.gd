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
## Cabecera de la capa de tierra pisada al final del plano: debajo, filas del mismo tamaño; `x` = tierra pisada.
const WEAR_LAYER_HEADER: String = "[tierra pisada]"
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
const FEATURE_CHARS: String = "RPMSTtXAGHQE"
## Objetos que tapan la casilla para siempre (rocas modeladas, el árbol singular, los restos…): ahí no se
## construye, no se planta y no aparece nada.
const SOLID_FEATURES: String = "XAGHQE"

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
## Casillas pintadas de tierra pisada en la capa del plano (`WEAR_LAYER_HEADER`).
var _worn: PackedByteArray = PackedByteArray()
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


## Lee un plano del disco. Null (con aviso) si no se puede abrir.
static func load_file(path: String) -> IslandLayout:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("IslandLayout: no se pudo abrir %s" % path)
		return null
	return from_text(file.get_as_text())


## Lee un plano de un texto. Las líneas que empiezan por // son comentarios; un carácter desconocido se
## lee como mar, con aviso.
static func from_text(text: String) -> IslandLayout:
	var layout := IslandLayout.new()
	var rows: PackedStringArray = []
	var worn_rows: PackedStringArray = []
	var in_wear_layer: bool = false
	for line: String in text.split("\n"):
		line = line.trim_suffix("\r")
		if line.begins_with("//") or line.strip_edges() == "":
			continue
		if line.strip_edges() == WEAR_LAYER_HEADER:
			in_wear_layer = true
			continue
		if in_wear_layer:
			worn_rows.append(line)
		else:
			rows.append(line)
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
			layout._ground[cell.y * width + cell.x] = layout._infer_ground(cell)
	layout._worn.resize(width * rows.size())
	for y: int in mini(worn_rows.size(), rows.size()):
		for x: int in mini(worn_rows[y].length(), width):
			if worn_rows[y][x] == "x":
				layout._worn[y * width + x] = 1
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


## Junto a un río o un lago, la tierra (lo que no es casilla de agua) nunca queda por debajo del agua: si no, al
## deformarse la orilla salían hoyos secos o el agua se veía cortada (C5.4d).
func _keep_above_water(x: float, z: float, y: float) -> float:
	if ground(Vector2i(floori(x), floori(z))) == Ground.WATER:
		return y
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
			if is_buildable(cell) or ground(cell) == Ground.RAMP:
				return true
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
				if is_buildable(cell) or ground(cell) == Ground.RAMP:
					fixed[j * row + i] = 1
				if ground(cell) == Ground.WATER:
					water_cells += 1
			# La orilla (agua y tierra) se queda; el fondo de dentro se suaviza (César: el lago se veía a cuadros).
			if water_cells > 0 and water_cells < 4:
				fixed[j * row + i] = 1
	_drawn = _smooth_corners(_corners, fixed, SMOOTH_PASSES)
	_relief_lift = _smooth_corners(_relief_lift, fixed, SMOOTH_PASSES)
	_relief_scale = _smooth_corners(_relief_scale, fixed, SMOOTH_PASSES)
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
					# Ni las explanadas (planas a su altura hasta el agua, por la rueda) ni lo de debajo de un salto.
					if _touches_buildable(i, j) or _drawn[index] < water_level - 1.0 - SHORE_FLOOR_REACH * SHORE_FLOOR_SLOPE:
						continue
					# Junto al agua, justo por encima; al alejarse, baja en rampa (si acababa de golpe, levantaba un
					# rellano con un escalón recto alrededor del lago, César).
					var away: int = maxi(maxi(x - i, i - (x + 1)), maxi(maxi(y - j, j - (y + 1)), 0))
					var floor_y: float = water_level + SHORE_ABOVE_WATER - SHORE_FLOOR_SLOPE * away
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


## ¿Es tierra (se anda y se puede plantar)? Ni mar, ni agua, ni cascada, ni un objeto que la tape.
func is_land(cell: Vector2i) -> bool:
	var g: Ground = ground(cell)
	return g != Ground.SEA and g != Ground.WATER and g != Ground.FALL and not SOLID_FEATURES.contains(char_at(cell))


## ¿Pueden aparecer rocas o palos aquí? En tierra que no sea empinada, salvo en el rellano (es el mirador: se
## deja despejado) y en el sendero.
func can_spawn(cell: Vector2i) -> bool:
	return is_land(cell) and ground(cell) != Ground.LANDING and ground(cell) != Ground.RAMP and not is_path(cell) \
			and not is_steep(cell) and not _debris_cells.has(cell)


## Rocas caídas al pie de las paredes (C5.4c): decorado. Cada una: posición (m), tamaño, giro y variante (0 a 2).
var debris: Array[Dictionary] = []
var _debris_cells: Dictionary[Vector2i, bool] = {}
## Pie de las paredes altas: casillas llanas junto a una pared de más de WALL_FOOT_DROP metros.
var _wall_foot: Dictionary[Vector2i, bool] = {}
const WALL_FOOT_DROP: float = 1.6
## Cuánto más alta tiene que estar la casilla de la pared que la del pie (m).
const WALL_FOOT_RISE: float = 0.8
## Parte de los pies de pared que lleva una roca caída (en la explanada, menos: ahí ocupa sitio de construir), su
## tamaño y la parte que lleva otra pequeña al lado.
const DEBRIS_CHANCE: float = 0.5
const DEBRIS_CHANCE_ON_FLAT: float = 0.3
const DEBRIS_PAIR_CHANCE: float = 0.45
const DEBRIS_SCALE_MIN: float = 1.4
const DEBRIS_SCALE_MAX: float = 2.8
## Tierra al pie de las paredes (lo que se desprende): cuánta, de 0 a 1.
const WALL_FOOT_WEAR: float = 0.5
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
			# También en la explanada pegada a la pared (César: se veían pocas); esa casilla deja de servir para construir.
			var r: float = _cell_random(cell, 1)
			if r > (DEBRIS_CHANCE_ON_FLAT if is_buildable(cell) else DEBRIS_CHANCE):
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
				Ground.SLOPE, Ground.FALL, Ground.RAMP:
					value = _slope_height(cell, to_level)
				_:
					value = level_height(level(cell))
			_heights[y * w + x] = value


## Altura de una casilla de ladera o de rampa: la media de las alturas a las que llega, pesada por lo cerca que está
## de cada una (1 / distancia). Con dos alturas es la subida en línea recta de siempre; con tres (la ladera con el
## rellano en medio) pasa de una a otra sin saltos.
func _slope_height(cell: Vector2i, to_level: Dictionary[int, Dictionary]) -> float:
	var weights: float = 0.0
	var total: float = 0.0
	for l: int in to_level:
		if not to_level[l].has(cell):
			continue
		var weight: float = 1.0 / float(to_level[l][cell])
		weights += weight
		total += weight * level_height(l)
	return total / weights if weights > 0.0 else 0.0


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
					if is_land(other) and not _is_slope(other) and level(other) == target_level and ground(other) != Ground.HILL:
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
	_compute_wall_feet(drops)
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
			if is_buildable(cell) or g == Ground.WATER or g == Ground.SEA or g == Ground.FALL \
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
	for y: int in size.y:
		for x: int in size.x:
			var cell := Vector2i(x, y)
			if _wall_foot.has(cell) and not is_buildable(cell):
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
