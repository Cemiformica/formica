class_name GameHud
extends Node
## Toda la interfaz del juego para una escena de isla (C5.3d): barra, mochila, ventanas de máquina y del banco,
## catálogo, desmontar, letrero de lo que miras, opciones (F10), música, aviso de lo recogido y de los planos aprendidos, la mira, los
## avisos de arriba («Partida guardada»…) y guardar y cargar con F5 y F9 (D-112; en C8 irán al menú de pausa).
## Uso: `var hud := GameHud.new(); hud.player = player; add_child(hud)`.
## Es lo mismo que monta el sandbox, en una pieza que puede usar cualquier isla.

## Jugador al que se engancha la interfaz. Se pone antes de añadir este nodo.
var player: Player

var _machine_window: MachineWindow
var _workbench_window: WorkbenchWindow
var _toast: Label
var _toast_tween: Tween = null


func _ready() -> void:
	assert(player != null, "GameHud: pon `player` antes de añadirlo")
	add_child(SettingsPanel.new())
	add_child(InventoryWindow.new())
	var hotbar := HotbarUI.new()
	add_child(hotbar)
	hotbar.set_builder(player.build_controller)
	hotbar.selection_changed.connect(player.set_held_slot)
	player.set_held_slot(hotbar.selected_slot)
	_machine_window = MachineWindow.new()
	add_child(_machine_window)
	_workbench_window = WorkbenchWindow.new()
	add_child(_workbench_window)
	player.building_opened.connect(_on_building_opened)
	var catalog := CatalogWindow.new()
	add_child(catalog)
	catalog.set_builder(player.build_controller, hotbar)
	var dismantle_window := DismantleWindow.new()
	add_child(dismantle_window)
	player.dismantler.confirm_requested.connect(dismantle_window.open_for.bind(player.dismantler))
	hotbar.set_dismantler(player.dismantler)
	var focus_panel := FocusPanel.new()
	add_child(focus_panel)
	focus_panel.set_player(player)
	add_child(MusicPlayer.new())
	add_child(PickupFeed.new())
	add_child(BlueprintToast.new())   # «Plano aprendido» al reparar (sesión 30)
	_add_crosshair_and_toast()
	SaveSystem.notification_requested.connect(_show_toast)


func _exit_tree() -> void:
	if SaveSystem.notification_requested.is_connected(_show_toast):
		SaveSystem.notification_requested.disconnect(_show_toast)


## F5 guarda y F9 carga.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("save_game"):
		player.store_to_world()
		SaveSystem.save_game()
	elif event.is_action_pressed("load_game"):
		var result: String = SaveSystem.load_game()
		if result == "LOAD_DONE" or result == "LOAD_BACKUP":
			player.restore_from_world()


## E sobre una construcción: el banco tiene su ventana; lo demás, la de máquina.
func _on_building_opened(view: BuildingView) -> void:
	if view.placed.is_workbench():
		_workbench_window.open_for(view)
	else:
		_machine_window.open_for(view)


## La mira del centro y el aviso de arriba, como en el sandbox.
func _add_crosshair_and_toast() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var crosshair := Label.new()
	crosshair.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	crosshair.text = "+"
	crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	crosshair.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	crosshair.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(crosshair)
	_toast = Label.new()
	_toast.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_toast.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_toast.offset_top = 150.0
	_toast.offset_bottom = 182.0
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_theme_font_size_override("font_size", 22)
	_toast.add_theme_color_override("font_outline_color", Color.BLACK)
	_toast.add_theme_constant_override("outline_size", 6)
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.modulate.a = 0.0
	layer.add_child(_toast)


## Aviso traducido arriba durante 1,5 s, que se desvanece en 0,5 s.
func _show_toast(text_key: String) -> void:
	_toast.text = tr(text_key)
	if _toast_tween != null:
		_toast_tween.kill()
	_toast.modulate.a = 1.0
	_toast_tween = create_tween()
	_toast_tween.tween_interval(1.5)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.5)
