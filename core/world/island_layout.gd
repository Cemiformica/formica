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
enum Ground { SEA, BEACH, LOW, LOW_FLAT, HIGH, HIGH_FLAT, SLOPE, LANDING, WATER, FALL }

## Alturas: la parte baja está a 0 y la alta, a LEVEL_HEIGHT metros (D-154). La ladera, el rellano y la cascada
## no tienen una altura fija (`NO_LEVEL`): van entre las dos.
const LEVEL_HEIGHT: float = 6.0
const LOW_LEVEL: int = 0
const HIGH_LEVEL: int = 1
const NO_LEVEL: int = -1
## Hondura del fondo del agua de la isla bajo su nivel, y fondo del mar (C5.3d).
const WATER_DEPTH: float = 0.8
const SEA_BED: float = -1.6
## Lejos de la costa, el fondo del mar baja hacia la oscuridad (C5.4a, César: como en Sea of Thieves, fuera de las
## islas no hay nada debajo): metros que baja por casilla de distancia a la tierra y hasta dónde.
const SEA_DROP_PER_CELL: float = 0.7
const SEA_DEEPEST: float = -14.0
## Donde la tierra toca el agua, el suelo baja a esta altura bajo la superficie del agua, para que el agua llegue
## hasta la orilla (C5.3d: si no, la rueda quedaba sobre la hierba).
const SHORE_BELOW_WATER: float = 0.3
## Desnivel máximo (m) dentro de una casilla para poner un árbol, una roca o unos palos (C5.3d: había árboles
## en el borde del acantilado).
const MAX_SLOPE_FOR_NATURE: float = 1.0

const _GROUND_BY_CHAR: Dictionary[String, Ground] = {
	"~": Ground.SEA, ",": Ground.BEACH, ".": Ground.LOW, "=": Ground.LOW_FLAT, "^": Ground.HIGH,
	"#": Ground.HIGH_FLAT, "/": Ground.SLOPE, ":": Ground.SLOPE, "_": Ground.LANDING, "O": Ground.WATER, "o": Ground.WATER,
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
## Tierra pisada de cada casilla (0 a 1): 1 en el sendero y, donde el sendero llega a la parte baja o a la alta, una
## mancha que se va apagando para que no empiece de golpe (C5.4a, César). La usa el terreno para pintar.
var _wear: PackedFloat32Array = PackedFloat32Array()
## Radio (casillas) de la mancha de tierra pisada en los extremos del sendero.
const WEAR_REACH: float = 6.0
## Radio de la mancha alrededor del portal y de la entrada del refugio, y ancho y fuerza del camino que los une.
const WEAR_SPOT_REACH: float = 5.0
const WEAR_TRAIL_WIDTH: float = 2.5
const WEAR_TRAIL_STRENGTH: float = 0.8
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
	for line: String in text.split("\n"):
		line = line.trim_suffix("\r")
		if line.begins_with("//") or line.strip_edges() == "":
			continue
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
		Ground.BEACH, Ground.LOW, Ground.LOW_FLAT:
			return LOW_LEVEL
		Ground.HIGH, Ground.HIGH_FLAT:
			return HIGH_LEVEL
		Ground.WATER:
			return HIGH_LEVEL if char_at(cell) == "O" else LOW_LEVEL
	return NO_LEVEL


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
	# Orilla de la tierra donde no se construye: si la esquina toca agua y tierra, baja justo por debajo del agua
	# (la más baja, si hay dos).
	var water_surface: float = INF
	var touches_land: bool = false
	for cell: Vector2i in cells:
		if ground(cell) == Ground.WATER:
			water_surface = minf(water_surface, LEVEL_HEIGHT if level(cell) == HIGH_LEVEL else 0.0)
		elif is_land(cell):
			touches_land = true
	if touches_land and water_surface != INF:
		return water_surface - SHORE_BELOW_WATER
	var sum: float = 0.0
	for cell: Vector2i in cells:
		sum += height(cell)
	return sum * 0.25


## Altura del terreno dibujado en el centro de una casilla: la de la explanada si lo es (plana) y, si no, la media
## de sus cuatro esquinas. Es donde se apoyan los árboles, las rocas y todo lo que va sobre el terreno.
func surface_height(cell: Vector2i) -> float:
	if is_buildable(cell):
		return height(cell)
	return (corner_height(cell.x, cell.y) + corner_height(cell.x + 1, cell.y) + corner_height(cell.x, cell.y + 1)
			+ corner_height(cell.x + 1, cell.y + 1)) * 0.25


## Desnivel del terreno dibujado dentro de la casilla (m): la diferencia entre su esquina más alta y la más baja.
func slope_drop(cell: Vector2i) -> float:
	var corners: Array[float] = [corner_height(cell.x, cell.y), corner_height(cell.x + 1, cell.y),
			corner_height(cell.x, cell.y + 1), corner_height(cell.x + 1, cell.y + 1)]
	return corners.max() - corners.min()


## ¿Demasiado empinada para un árbol, una roca o unos palos? (el borde del acantilado, por ejemplo)
func is_steep(cell: Vector2i) -> bool:
	return has_cell(cell) and _steep[cell.y * size.x + cell.x] == 1


## ¿Se puede construir aquí? Solo en las explanadas (D-154), y no bajo un objeto que la tape.
func is_buildable(cell: Vector2i) -> bool:
	var g: Ground = ground(cell)
	return (g == Ground.LOW_FLAT or g == Ground.HIGH_FLAT) and not SOLID_FEATURES.contains(char_at(cell))


## ¿Es tierra (se anda y se puede plantar)? Ni mar, ni agua, ni cascada, ni un objeto que la tape.
func is_land(cell: Vector2i) -> bool:
	var g: Ground = ground(cell)
	return g != Ground.SEA and g != Ground.WATER and g != Ground.FALL and not SOLID_FEATURES.contains(char_at(cell))


## ¿Pueden aparecer rocas o palos aquí? En tierra que no sea empinada, salvo en el rellano (es el mirador: se
## deja despejado) y en el sendero.
func can_spawn(cell: Vector2i) -> bool:
	return is_land(cell) and ground(cell) != Ground.LANDING and not is_path(cell) and not is_steep(cell)


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
	var to_low: Dictionary[Vector2i, int] = _slope_distances(LOW_LEVEL)
	var to_high: Dictionary[Vector2i, int] = _slope_distances(HIGH_LEVEL)
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
					value = (LEVEL_HEIGHT if level(cell) == HIGH_LEVEL else 0.0) - WATER_DEPTH
				Ground.SLOPE, Ground.LANDING, Ground.FALL:
					var dl: float = float(to_low.get(cell, 1000))
					var dh: float = float(to_high.get(cell, 1000))
					value = LEVEL_HEIGHT * dl / (dl + dh)
				_:
					value = LEVEL_HEIGHT if level(cell) == HIGH_LEVEL else 0.0
			_heights[y * w + x] = value


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
					if is_land(other) and not _is_slope(other) and level(other) == target_level:
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
	return g == Ground.SLOPE or g == Ground.LANDING or g == Ground.FALL


## Esquinas, casillas empinadas y casillas para rocas y palos (después de las alturas).
func _compute_corners() -> void:
	_corners.resize((size.x + 1) * (size.y + 1))
	for j: int in size.y + 1:
		for i: int in size.x + 1:
			_corners[j * (size.x + 1) + i] = _corner_from_cells(i, j)
	_steep.resize(size.x * size.y)
	spawn_cells.clear()
	for y: int in size.y:
		for x: int in size.x:
			var cell := Vector2i(x, y)
			_steep[y * size.x + x] = 1 if slope_drop(cell) > MAX_SLOPE_FOR_NATURE else 0
	for y: int in size.y:
		for x: int in size.x:
			if can_spawn(Vector2i(x, y)):
				spawn_cells.append(Vector2i(x, y))
	_compute_wear()


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
