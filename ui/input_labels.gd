class_name InputLabels
extends RefCounted
## Nombre visible de la tecla o el botón de una acción (C1.8), sacado de la configuración de controles: si
## un día se cambian las teclas, las ayudas de la pantalla cambian solas.


## "E", "R", "Clic"… (la primera tecla o botón de la acción; si no tiene ninguno, el nombre de la acción).
static func action_text(action: StringName) -> String:
	for event: InputEvent in InputMap.action_get_events(action):
		if event is InputEventKey:
			var key := event as InputEventKey
			var code: Key = key.keycode
			if key.physical_keycode != KEY_NONE:
				# Tecla física: su letra en la distribución del teclado de quien juega.
				code = DisplayServer.keyboard_get_keycode_from_physical(key.physical_keycode)
			return "Esc" if code == KEY_ESCAPE else OS.get_keycode_string(code)
		if event is InputEventMouseButton:
			match (event as InputEventMouseButton).button_index:
				MOUSE_BUTTON_LEFT:
					return TranslationServer.translate("INPUT_MOUSE_LEFT")
				MOUSE_BUTTON_RIGHT:
					return TranslationServer.translate("INPUT_MOUSE_RIGHT")
				MOUSE_BUTTON_MIDDLE:
					return TranslationServer.translate("INPUT_MOUSE_MIDDLE")
	return String(action)
