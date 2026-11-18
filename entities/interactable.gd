class_name Interactable
extends StaticBody3D
## Objeto del mundo con el que el jugador puede interactuar mirándolo. Dos acciones (C1.8, César):
## `interact` (E) abre inventarios o acciona cosas (puertas, portales…), y `use` (clic izquierdo, con lo que
## se lleve en la mano) trabaja el objeto: talar, picar, recoger. Cada objeto hace solo las suyas.
## Traído del prototipo (D-054). Quien lo use se conecta a la señal `interacted`.

## Se emite cuando alguien interactúa con este objeto.
signal interacted(by: Node)

## Clave de traducción del nombre visible (por ejemplo, "PROP_OAK"). Se traduce con tr() al mostrarla.
@export var display_name_key: String = ""


## Llamado por el jugador al pulsar `interact` mientras mira este objeto.
func interact(by: Node) -> void:
	interacted.emit(by)


## Llamado por el jugador en cada paso de física mientras mantiene el clic izquierdo mirando este objeto.
## Cada objeto decide cuánto espera entre golpes. Por defecto no hace nada.
func use(_by: Node) -> void:
	pass


## Qué hace la E sobre este objeto (clave de traducción, p. ej. "HINT_OPEN"); vacío si nada. Lo enseña el
## letrero de arriba (`FocusPanel`, C1.8).
func get_interact_hint_key() -> String:
	return ""


## Qué hace el clic izquierdo sobre este objeto ("HINT_CHOP"…); vacío si nada.
func get_use_hint_key() -> String:
	return ""


## Herramienta (id del ítem) que hace falta en la mano para el clic izquierdo; vacío si se hace a mano (C3).
func get_required_tool() -> StringName:
	return &""


## Avance del trabajo para el letrero de arriba («2/4»); vacío si no hay nada empezado (C3).
func get_progress_text() -> String:
	return ""


## Llamado por el jugador cuando empieza (true) o deja (false) de mirar este objeto a alcance de E.
## No hace nada; quien quiera reaccionar lo sobrescribe.
func set_focused(_focused: bool) -> void:
	pass
