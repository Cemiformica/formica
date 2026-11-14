extends Node3D
## Escena de pruebas de B2 (solo desarrollo). Por ahora imprime en Salida lo que el jugador mira
## y con qué interactúa. En B2.4b y B2.4c se construirá aquí sobre `IslandState`.

@onready var player: Player = $Player
@onready var test_box: Interactable = $TestBox


func _ready() -> void:
	player.focus_changed.connect(_on_player_focus_changed)
	test_box.interacted.connect(_on_test_box_interacted)


func _on_player_focus_changed(target: Interactable) -> void:
	if target != null:
		print("Mirando: ", target.name)
	else:
		print("Mirando: nada")


func _on_test_box_interacted(by: Node) -> void:
	print("Interacción con la caja de prueba (por ", by.name, ")")
