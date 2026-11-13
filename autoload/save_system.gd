extends Node
## Autoload `SaveSystem`: guarda y carga `WorldState` en disco (D-040, separado de `GameState`).
## Formato: JSON con `version` + `world`. Guardado seguro: se escribe en un temporal y solo al final
## se renombra; la partida anterior queda como copia de seguridad (.bak.json).
## No lee teclas ni cambia de escena: eso lo hará quien lo llame.
## Archivos en Windows: %APPDATA%\Godot\app_userdata\formica\.

## Pide a la interfaz que muestre un aviso breve (clave de traducción).
signal notification_requested(text_key: String)

## Partida principal.
const SAVE_PATH: String = "user://savegame.json"
## Versión del formato. Súbela si cambia el formato y añade la adaptación en _migrate().
const SAVE_VERSION: int = 1


## Guarda la partida en `path`. Devuelve la clave del resultado: "SAVE_DONE" o "SAVE_ERROR".
func save_game(path: String = SAVE_PATH) -> String:
	var data: Dictionary = {"version": SAVE_VERSION, "world": WorldState.to_data()}
	var temp_path: String = path + ".tmp"
	var backup_path: String = _backup_path(path)
	# 1) Escribir completo en el temporal.
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		push_error("No se pudo guardar: %s" % error_string(FileAccess.get_open_error()))
		return _notify("SAVE_ERROR")
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	# 2) La partida anterior pasa a ser la copia. 3) El temporal pasa a ser la principal.
	if FileAccess.file_exists(path):
		if FileAccess.file_exists(backup_path):
			DirAccess.remove_absolute(backup_path)
		DirAccess.rename_absolute(path, backup_path)
	var error: Error = DirAccess.rename_absolute(temp_path, path)
	if error != OK:
		push_error("No se pudo completar el guardado: %s" % error_string(error))
		return _notify("SAVE_ERROR")
	return _notify("SAVE_DONE")


## Carga la partida de `path`; si está dañada, prueba la copia de seguridad. Devuelve la clave:
## "LOAD_DONE", "LOAD_BACKUP", "SAVE_NONE", "LOAD_ERROR" o "LOAD_TOO_NEW".
## Si no devuelve LOAD_DONE ni LOAD_BACKUP, el estado actual no se toca.
func load_game(path: String = SAVE_PATH) -> String:
	var backup_path: String = _backup_path(path)
	if not FileAccess.file_exists(path) and not FileAccess.file_exists(backup_path):
		return _notify("SAVE_NONE")
	var result: Dictionary = _read_save(path)
	var key: String = "LOAD_DONE"
	if result["error"] == "LOAD_ERROR" and FileAccess.file_exists(backup_path):
		push_warning("Partida principal dañada; se intenta la copia de seguridad.")
		result = _read_save(backup_path)
		key = "LOAD_BACKUP"
	if result["error"] != "":
		return _notify(result["error"])
	WorldState.load_data(result["data"]["world"])
	return _notify(key)


## ¿Hay alguna partida guardada (principal o copia)?
func has_save(path: String = SAVE_PATH) -> bool:
	return FileAccess.file_exists(path) or FileAccess.file_exists(_backup_path(path))


## Lee y valida un archivo. Devuelve {"error": "" o clave de aviso, "data": Dictionary}.
func _read_save(path: String) -> Dictionary:
	var fail := func(key: String) -> Dictionary: return {"error": key, "data": {}}
	if not FileAccess.file_exists(path):
		return fail.call("LOAD_ERROR")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		push_warning("Guardado dañado (%s): no es un JSON válido." % path)
		return fail.call("LOAD_ERROR")
	var data: Dictionary = parsed
	var version: int = int(data.get("version", 0))
	if version > SAVE_VERSION:
		return fail.call("LOAD_TOO_NEW")
	if version < 1:
		push_warning("Guardado dañado (%s): sin versión." % path)
		return fail.call("LOAD_ERROR")
	data = _migrate(data, version)
	if not data.get("world") is Dictionary:
		push_warning("Guardado dañado (%s): falta el estado del mundo." % path)
		return fail.call("LOAD_ERROR")
	return {"error": "", "data": data}


## Adapta guardados de versiones anteriores al formato actual. (Versión 1: nada que adaptar.)
func _migrate(data: Dictionary, _from_version: int) -> Dictionary:
	return data


## "user://savegame.json" → "user://savegame.bak.json".
func _backup_path(path: String) -> String:
	return path.get_basename() + ".bak." + path.get_extension()


## Emite el aviso y devuelve la misma clave (para escribir `return _notify(...)`).
func _notify(key: String) -> String:
	notification_requested.emit(key)
	return key
