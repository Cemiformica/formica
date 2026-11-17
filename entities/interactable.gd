class_name Interactable
extends StaticBody3D
## Objeto del mundo con el que el jugador puede interactuar mirándolo y pulsando `interact` (E).
## Traído del prototipo (D-054). Quien lo use se conecta a la señal `interacted`.

## Se emite cuando alguien interactúa con este objeto.
signal interacted(by: Node)

## Clave de traducción del nombre visible (por ejemplo, "PROP_TREE"). Se traduce con tr() al mostrarla.
@export var display_name_key: String = ""


## Llamado por el jugador al pulsar `interact` mientras mira este objeto.
func interact(by: Node) -> void:
	interacted.emit(by)


## Llamado por el jugador cuando empieza (true) o deja (false) de mirar este objeto a alcance de E.
## No hace nada; quien quiera reaccionar (p. ej., `BuildingView` con su texto) lo sobrescribe.
func set_focused(_focused: bool) -> void:
	pass
